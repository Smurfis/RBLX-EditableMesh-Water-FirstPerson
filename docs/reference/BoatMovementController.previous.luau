--!strict
-- Archived, excluded from Rojo: superseded by WaterInteractionController's
-- six-sample dynamic branch. Kept only to make the earlier prototype recoverable.

-- Local visual/physics controller for opted-in boats. The server validates
-- the seated driver and assigns network ownership; this client consumes the
-- VehicleSeat intent so wave response uses the same local wave phase as water.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local boatsFolder = workspace:WaitForChild("Boats")
local OceanSurface = require(ReplicatedStorage.Modules:WaitForChild("OceanSurface"))
local BoatConfig = require(ReplicatedStorage.Modules:WaitForChild("BoatConfig"))

type BoatState = {
	boat: Model,
	root: BasePart,
	seat: VehicleSeat,
	attachment: Attachment,
	force: VectorForce,
	orientation: AlignOrientation,
	heading: number,
	lastSpeed: number,
	targetY: number,
	connection: RBXScriptConnection?,
}

local states: { [Model]: BoatState } = {}

local function findSeat(boat: Model): VehicleSeat?
	local seat = boat:FindFirstChild("BoatSeat", true)
	return if seat and seat:IsA("VehicleSeat") then seat else nil
end

local function getRoot(boat: Model): BasePart?
	local root = boat:FindFirstChild("BoatRoot", true)
	if root and root:IsA("BasePart") then
		return root
	end
	return boat.PrimaryPart
end

local function getOrCreateRootAttachment(root: BasePart): Attachment
	local attachment = root:FindFirstChild("BoatMovementAttachment")
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end
	local created = Instance.new("Attachment")
	created.Name = "BoatMovementAttachment"
	created.Parent = root
	return created
end

local function getSamplePoints(state: BoatState): { Vector3 }
	local folder = state.boat:FindFirstChild("BuoyancyPoints", true)
	local points: { Vector3 } = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Attachment") then
				table.insert(points, child.WorldPosition)
			end
		end
	end
	if #points >= 4 then
		return points
	end
	local size = state.boat:GetExtentsSize()
	local halfX = math.max(size.X * 0.38, 1)
	local halfZ = math.max(size.Z * 0.38, 1)
	local pivot = state.root.CFrame
	return {
		pivot:PointToWorldSpace(Vector3.new(-halfX, 0, -halfZ)),
		pivot:PointToWorldSpace(Vector3.new(halfX, 0, -halfZ)),
		pivot:PointToWorldSpace(Vector3.new(-halfX, 0, halfZ)),
		pivot:PointToWorldSpace(Vector3.new(halfX, 0, halfZ)),
	}
end

local function addBoat(boat: Model)
	if states[boat] then
		return
	end
	local root = getRoot(boat)
	local seat = findSeat(boat)
	if not root then
		task.delay(0.5, function()
			if boat.Parent and not states[boat] then
				addBoat(boat)
			end
		end)
		return
	end
	if not seat then
		task.delay(0.5, function()
			if boat.Parent and not states[boat] then
				addBoat(boat)
			end
		end)
		return
	end
	boat:SetAttribute("BoatControllerManaged", true)
	local _, heading = root.CFrame:ToOrientation()
	states[boat] = {
		boat = boat,
		root = root,
		seat = seat,
		attachment = getOrCreateRootAttachment(root),
		force = Instance.new("VectorForce"),
		orientation = Instance.new("AlignOrientation"),
		heading = heading,
		lastSpeed = 0,
		targetY = root.Position.Y,
		connection = nil,
	}
	local state = states[boat] :: BoatState
	state.force.Name = "BoatMovementForce"
	state.force.Attachment0 = state.attachment
	state.force.RelativeTo = Enum.ActuatorRelativeTo.World
	state.force.Parent = root
	state.orientation.Name = "BoatMovementOrientation"
	state.orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	state.orientation.Attachment0 = state.attachment
	state.orientation.MaxTorque = math.huge
	state.orientation.Parent = root
end

local function removeBoat(boat: Model)
	local state = states[boat]
	if not state then
		return
	end
	if state.connection then
		state.connection:Disconnect()
	end
	state.force:Destroy()
	state.orientation:Destroy()
	states[boat] = nil
end

for _, child in boatsFolder:GetChildren() do
	if child:IsA("Model") then
		addBoat(child)
	end
end
boatsFolder.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		addBoat(child)
	end
end)
boatsFolder.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		removeBoat(child)
	end
end)

local function updateBoat(state: BoatState, dt: number)
	local boat = state.boat
	local root = state.root
	local seat = state.seat
	if not boat.Parent or not root.Parent then
		removeBoat(boat)
		return
	end

	local config = BoatConfig.Resolve(boat)
	local occupant = seat.Occupant
	local isDriver = occupant ~= nil and Players:GetPlayerFromCharacter(occupant.Parent) == player
	local throttle = if isDriver then seat.ThrottleFloat else 0
	local steer = if isDriver then seat.SteerFloat else 0
	boat:SetAttribute("BoatConsumedSteerFloat", steer)
	boat:SetAttribute("BoatConsumedThrottleFloat", throttle)

	local speed = root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector)
	local targetSpeed = if throttle >= 0 then throttle * config.MaxForwardSpeed else throttle * config.MaxReverseSpeed
	local acceleration = if throttle >= 0 then config.ForwardAcceleration else config.ReverseAcceleration
	local speedDelta = math.clamp(targetSpeed - speed, -config.SpeedGainLimit * dt, config.SpeedGainLimit * dt)
	local drive = math.clamp(speedDelta * acceleration, -acceleration, acceleration)
	local velocity = root.AssemblyLinearVelocity
	local lateralSpeed = velocity:Dot(root.CFrame.RightVector)
	local lateralForce = -root.CFrame.RightVector * lateralSpeed * config.SideCatch * root.AssemblyMass
	local forwardForce = root.CFrame.LookVector * drive * root.AssemblyMass
	local drag = -velocity
		* (if math.abs(throttle) > 0.01 then config.ForwardDrag else config.IdleDrag)
		* root.AssemblyMass

	local samples = getSamplePoints(state)
	local time = OceanSurface.GetTime()
	local averageHeight = 0
	local frontHeight = 0
	local rearHeight = 0
	local leftHeight = 0
	local rightHeight = 0
	for _, point in samples do
		local sample = OceanSurface.Sample(point, time, config.SampleOctaves)
		averageHeight += sample.Height
		local localPoint = root.CFrame:PointToObjectSpace(point)
		if localPoint.Z < 0 then
			frontHeight += sample.Height
		else
			rearHeight += sample.Height
		end
		if localPoint.X < 0 then
			leftHeight += sample.Height
		else
			rightHeight += sample.Height
		end
	end
	averageHeight /= #samples
	frontHeight /= math.max(1, math.ceil(#samples / 2))
	rearHeight /= math.max(1, math.floor(#samples / 2))
	leftHeight /= math.max(1, math.ceil(#samples / 2))
	rightHeight /= math.max(1, math.floor(#samples / 2))

	local centerSurface = OceanSurface.Sample(root.Position, time, config.SampleOctaves)
	state.targetY = centerSurface.SurfaceY + (averageHeight - centerSurface.Height) + config.WaterlineOffset
	local verticalVelocity = velocity.Y
	local verticalForce = (
		(state.targetY - root.Position.Y) * config.VerticalResponse - verticalVelocity * config.VerticalDamping
	) * root.AssemblyMass
	local currentHorizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if currentHorizontalSpeed > config.MaxHorizontalSpeed then
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Unit * config.MaxHorizontalSpeed
		root.AssemblyLinearVelocity = Vector3.new(
			horizontal.X,
			math.clamp(velocity.Y, -config.MaxVerticalSpeed, config.MaxVerticalSpeed),
			horizontal.Z
		)
	end

	local speedAlpha = math.clamp(math.abs(speed) / math.max(config.MaxForwardSpeed, 1), 0, 1)
	state.heading += steer * config.TurnRate * (0.25 + speedAlpha) * dt
	local pitch = math.clamp(
		(frontHeight - rearHeight) * 0.35,
		-math.rad(config.MaxPitchDegrees),
		math.rad(config.MaxPitchDegrees)
	)
	local roll =
		math.clamp((rightHeight - leftHeight) * 0.35, -math.rad(config.MaxRollDegrees), math.rad(config.MaxRollDegrees))
	local orientation = CFrame.Angles(0, state.heading, 0) * CFrame.Angles(pitch, 0, roll)

	state.force.Force = forwardForce
		+ lateralForce
		+ drag
		+ Vector3.new(0, verticalForce + root.AssemblyMass * workspace.Gravity, 0)
	state.orientation.Responsiveness = config.RotationResponse
	state.orientation.CFrame = orientation
end

RunService.Heartbeat:Connect(function(dt)
	for _, state in states do
		updateBoat(state, dt)
	end
end)
