--!strict

-- First rigid buoyancy milestone. This controller is deliberately opt-in:
-- only instances tagged WaterInteractable are ever touched.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local WaterConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WaterConfig"))
local WaterWaveSampler = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WaterWaveSampler"))
local BoatPropulsion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BoatPropulsion"))
local player = Players.LocalPlayer

local TAG_NAME = "WaterInteractable"
local POSITION_RESPONSE = 7
local ROTATION_RESPONSE = 6
local MAX_UPDATE_DISTANCE = 500

local PROFILES = {
	SmallProp = { SampleCount = 1, Octaves = 8, UpdateHz = 30 },
	MediumProp = { SampleCount = 3, Octaves = 8, UpdateHz = 30 },
	Boat = { SampleCount = 6, Octaves = 6, UpdateHz = 30 },
	LargeShip = { SampleCount = 8, Octaves = 4, UpdateHz = 20 },
}

type DynamicState = {
	propulsion: BoatPropulsion.State,
	attachment: Attachment,
	force: VectorForce,
	orientation: AlignOrientation,
	session: number,
	preparedMass: number,
	lastMessage: number,
	lastDebug: number,
	remote: RemoteEvent,
}

type InteractableState = {
	instance: Instance,
	root: BasePart,
	model: Model?,
	currentY: number,
	restTransform: CFrame,
	originPosition: Vector3,
	yaw: number,
	baseRotation: CFrame,
	currentRotation: CFrame,
	targetY: number,
	targetPosition: Vector3,
	targetRotation: CFrame,
	updateTimer: number,
	dynamic: DynamicState?,
	wasDynamic: boolean,
	failedSession: number?,
}

local states: { [Instance]: InteractableState } = {}

local function getRoot(instance: Instance): (BasePart?, Model?)
	if instance:IsA("BasePart") then
		return instance, nil
	end

	if instance:IsA("Model") then
		local boatRoot = instance:FindFirstChild("BoatRoot", true)
		if boatRoot and boatRoot:IsA("BasePart") then
			return boatRoot, instance
		end
		local primaryPart = instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart", true)
		if not primaryPart or not primaryPart:IsA("BasePart") then
			return nil, instance
		end
		return primaryPart, instance
	end

	return nil, nil
end

local function addInteractable(instance: Instance)
	if states[instance] then
		return
	end

	local root, model = getRoot(instance)
	if not root then
		if instance:IsA("Model") then
			task.delay(0.5, function()
				if instance.Parent and CollectionService:HasTag(instance, TAG_NAME) then
					addInteractable(instance)
				end
			end)
		end
		return
	end

	local storedTransform = instance:GetAttribute("CurrentTransform")
	local restTransform = if typeof(storedTransform) == "CFrame" then storedTransform else root.CFrame

	states[instance] = {
		instance = instance,
		root = root,
		model = model,
		currentY = root.Position.Y,
		restTransform = restTransform,
		originPosition = restTransform.Position,
		yaw = select(2, restTransform:ToOrientation()),
		baseRotation = restTransform.Rotation,
		currentRotation = root.CFrame.Rotation,
		targetY = root.Position.Y,
		targetPosition = restTransform.Position,
		targetRotation = root.CFrame.Rotation,
		updateTimer = 0,
		dynamic = nil,
		wasDynamic = false,
		failedSession = nil,
	}
end

local function clearDynamic(state: InteractableState, notifyServer: boolean)
	local dynamic = state.dynamic
	if not dynamic then return end
	if notifyServer then
		dynamic.remote:FireServer(state.instance, dynamic.session, "Stop")
	end
	BoatPropulsion.Destroy(dynamic.propulsion)
	state.instance:SetAttribute("BoatConsumedSteerFloat", 0)
	state.instance:SetAttribute("BoatConsumedThrottleFloat", 0)
	dynamic.force:Destroy()
	dynamic.orientation:Destroy()
	dynamic.attachment:Destroy()
	state.dynamic = nil
end

local function removeInteractable(instance: Instance)
	local state = states[instance]
	if state then clearDynamic(state, true) end
	states[instance] = nil
end

for _, instance in CollectionService:GetTagged(TAG_NAME) do
	addInteractable(instance)
end

CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(addInteractable)
CollectionService:GetInstanceRemovedSignal(TAG_NAME):Connect(removeInteractable)

local function getNumberAttribute(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" and value == value and math.abs(value) < math.huge then value else fallback
end

local function isEnabled(instance: Instance): boolean
	local value = instance:GetAttribute("WaterEnabled")
	return value ~= false
end

local function getProfile(instance: Instance)
	local name = instance:GetAttribute("WaterProfile")
	if typeof(name) == "string" then
		local normalized = string.lower(name)
		if normalized == "medprop" then
			return PROFILES.MediumProp
		end
		for profileName, profile in PROFILES do
			if string.lower(profileName) == normalized then
				return profile
			end
		end
	end
	return PROFILES.SmallProp
end

local function getObjectSize(state: InteractableState): Vector3
	if getProfile(state.instance) == PROFILES.Boat and state.root.Name == "BoatRoot" then
		return state.root.Size
	end
	if state.model then
		return state.model:GetExtentsSize()
	end
	return state.root.Size
end

local function getSampleOffsets(state: InteractableState, sampleCount: number): { Vector3 }
	if sampleCount <= 1 then
		return { Vector3.zero }
	end

	local size = getObjectSize(state)
	local halfX = math.max(size.X * 0.4, 0.5)
	local halfZ = math.max(size.Z * 0.4, 0.5)

	if sampleCount <= 3 then
		return {
			Vector3.zero,
			Vector3.new(0, 0, -halfZ),
			Vector3.new(0, 0, halfZ),
		}
	end

	if sampleCount <= 6 then
		return {
			Vector3.new(-halfX, 0, -halfZ),
			Vector3.new(halfX, 0, -halfZ),
			Vector3.new(-halfX, 0, 0),
			Vector3.new(halfX, 0, 0),
			Vector3.new(-halfX, 0, halfZ),
			Vector3.new(halfX, 0, halfZ),
		}
	end

	return {
		Vector3.new(-halfX, 0, -halfZ),
		Vector3.new(0, 0, -halfZ),
		Vector3.new(halfX, 0, -halfZ),
		Vector3.new(-halfX, 0, halfZ),
		Vector3.new(0, 0, halfZ),
		Vector3.new(halfX, 0, halfZ),
		Vector3.new(-halfX, 0, 0),
		Vector3.new(halfX, 0, 0),
	}
end

local function sampleObject(state: InteractableState, profile, dynamic: boolean?)
	local override = state.instance:GetAttribute("WaterSampleCount")
	local sampleCount = profile.SampleCount
	if profile ~= PROFILES.Boat and typeof(override) == "number" then
		sampleCount = math.clamp(math.floor(override), 1, 8)
	end

	local offsets = getSampleOffsets(state, sampleCount)
	local time = WaterWaveSampler.GetTime()
	local totalHeight = 0
	local totalNormal = Vector3.zero
	local totalDisplacement = Vector3.zero
	local frontHeight = 0
	local rearHeight = 0
	local leftHeight = 0
	local rightHeight = 0
	local frontCount = 0
	local rearCount = 0
	local leftCount = 0
	local rightCount = 0
	local frontPosition, rearPosition = Vector3.zero, Vector3.zero
	local leftPosition, rightPosition = Vector3.zero, Vector3.zero

	local usesHullFrame = profile == PROFILES.Boat and state.root.Name == "BoatRoot"
	local sampleFrame = if dynamic or usesHullFrame then state.root.CFrame.Rotation else CFrame.Angles(0, state.yaw, 0)
	for _, localOffset in offsets do
		local worldPoint = state.root.Position + sampleFrame:VectorToWorldSpace(localOffset)
		local sample = WaterWaveSampler.Sample(worldPoint.X, worldPoint.Z, time, profile.Octaves)
		local surfacePoint = Vector3.new(worldPoint.X, sample.Height, worldPoint.Z)
		totalHeight += sample.Height
		totalNormal += sample.Normal
		totalDisplacement += sample.Displacement

		if localOffset.Z < -0.01 then
			frontHeight += sample.Height
			frontCount += 1
			frontPosition += surfacePoint
		elseif localOffset.Z > 0.01 then
			rearHeight += sample.Height
			rearCount += 1
			rearPosition += surfacePoint
		end
		if localOffset.X < -0.01 then
			leftHeight += sample.Height
			leftCount += 1
			leftPosition += surfacePoint
		elseif localOffset.X > 0.01 then
			rightHeight += sample.Height
			rightCount += 1
			rightPosition += surfacePoint
		end
	end

	local averageHeight = totalHeight / #offsets
	if dynamic or usesHullFrame then
		-- The same six heights, measured across the hull's CURRENT footprint.
		-- These world-space tangents avoid adding hull tilt to the water normal.
		local longitudinal = rearPosition / rearCount - frontPosition / frontCount
		local lateral = rightPosition / rightCount - leftPosition / leftCount
		local cross = longitudinal:Cross(lateral)
		local normal = if cross.Magnitude > 0.001 then cross.Unit else Vector3.yAxis
		if normal.Y < 0 then normal = -normal end
		return averageHeight, normal, totalDisplacement / #offsets
	end
	local normal = (totalNormal / #offsets).Unit
	if #offsets > 1 then
		local size = getObjectSize(state)
		local depth = math.max(size.Z * 0.8, 1)
		local width = math.max(size.X * 0.8, 1)
		local averageFront = if frontCount > 0 then frontHeight / frontCount else averageHeight
		local averageRear = if rearCount > 0 then rearHeight / rearCount else averageHeight
		local averageLeft = if leftCount > 0 then leftHeight / leftCount else averageHeight
		local averageRight = if rightCount > 0 then rightHeight / rightCount else averageHeight
		normal = Vector3.new(-(averageRight - averageLeft) / width, 1, (averageFront - averageRear) / depth).Unit
	end

	return averageHeight, sampleFrame:VectorToWorldSpace(normal), totalDisplacement / #offsets
end

local function isDynamicBoat(state: InteractableState): boolean
	local folder = workspace:FindFirstChild("Boats")
	return state.model ~= nil and folder ~= nil and state.model.Parent == folder
		and getProfile(state.instance) == PROFILES.Boat
		and state.instance:GetAttribute("WaterDynamicPhysics") == true
end

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function failDynamic(state: InteractableState, message: string)
	local session = state.instance:GetAttribute("BoatDynamicSession")
	if state.failedSession ~= session then
		warn("[BoatPhysics][FAIL] " .. state.instance:GetFullName() .. ": " .. message)
	end
	state.failedSession = if typeof(session) == "number" then session else nil
	clearDynamic(state, true)
end

local function prepareDynamic(state: InteractableState, session: number): DynamicState?
	local remote = ReplicatedStorage:FindFirstChild("BoatDynamicReady")
	if not remote or not remote:IsA("RemoteEvent") then return nil end
	local root = state.root
	-- AssemblyMass is infinite while anchored. Estimate finite mass once for
	-- the ready handshake, then use actual AssemblyMass immediately on release.
	local mass = root:GetMass()
	for _, part in root:GetConnectedParts(true) do
		if part ~= root and not part.Massless then mass += part:GetMass() end
	end
	if not finite(mass) or mass <= 0 then
		failDynamic(state, "invalid preparation mass")
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "BoatDynamicPhysicsAttachment"
	-- Primary axis is hull up; align only that axis, leaving yaw free.
	attachment.CFrame = CFrame.Angles(0, 0, math.pi / 2)
	attachment.Parent = root
	local force = Instance.new("VectorForce")
	force.Name = "BoatDynamicBuoyancyForce"
	force.Attachment0 = attachment
	force.ApplyAtCenterOfMass = true
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = Vector3.yAxis * mass * workspace.Gravity
	force.Parent = root
	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "BoatDynamicAlignOrientation"
	orientation.Attachment0 = attachment
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.AlignType = Enum.AlignType.PrimaryAxisParallel
	orientation.RigidityEnabled = false
	orientation.Responsiveness = 6
	orientation.MaxAngularVelocity = 2
	orientation.MaxTorque = mass * 1000
	orientation.CFrame = root.CFrame.Rotation * attachment.CFrame.Rotation
	orientation.Parent = root
	local dynamic: DynamicState = {
		propulsion = BoatPropulsion.Create(root, attachment),
		attachment = attachment, force = force, orientation = orientation,
		session = session, preparedMass = mass, lastMessage = -math.huge,
		lastDebug = -math.huge, remote = remote,
	}
	state.dynamic = dynamic
	state.wasDynamic = true
	return dynamic
end

local function updateDynamic(state: InteractableState, dt: number)
	local boat, root = state.instance, state.root
	local mode = boat:GetAttribute("BoatPhysicsMode")
	if not isDynamicBoat(state) or not isEnabled(boat) then
		clearDynamic(state, true)
		return
	end
	if mode == "DYNAMIC_DRIVING" then state.wasDynamic = true end
	local seat = boat:FindFirstChild("BoatSeat", true)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local session = boat:GetAttribute("BoatDynamicSession")
	local localDriver = seat and seat:IsA("VehicleSeat") and humanoid
		and seat.Occupant == humanoid and humanoid.SeatPart == seat and humanoid.Health > 0
	local permitted = mode == "DYNAMIC_PREPARING" or mode == "DYNAMIC_DRIVING"
	if not localDriver or not permitted or typeof(session) ~= "number" then
		clearDynamic(state, mode == "DYNAMIC_DRIVING")
		return
	end
	if state.failedSession == session then return end
	if mode == "DYNAMIC_DRIVING" and boat:GetAttribute("BoatDynamicDriverUserId") ~= player.UserId then
		if state.dynamic then BoatPropulsion.Stop(state.dynamic.propulsion) end
		-- Owner and mode attributes may arrive separately. No force or PivotTo
		-- from another client's boat; the server watchdog owns failed handoffs.
		return
	end
	if state.dynamic and state.dynamic.session ~= session then clearDynamic(state, false) end
	if root.Name ~= "BoatRoot" then
		failDynamic(state, "BoatRoot missing")
		return
	end
	local height, normal = sampleObject(state, PROFILES.Boat, true)
	local targetY = WaterConfig.GetSurfaceY()
		+ height * math.max(0, getNumberAttribute(boat, "WaterBuoyancyStrength", 1))
		+ getNumberAttribute(boat, "WaterVerticalOffset", 0)
	if not finite(targetY) or not finite(normal.Magnitude) then
		failDynamic(state, "valid six-point water sample unavailable")
		return
	end
	local dynamic = state.dynamic or prepareDynamic(state, session)
	if not dynamic then return end
	if dynamic.attachment.Parent ~= root or dynamic.force.Parent ~= root
		or dynamic.orientation.Parent ~= root or not dynamic.force.Enabled
		or not dynamic.orientation.Enabled or dynamic.force.Attachment0 ~= dynamic.attachment
		or dynamic.orientation.Attachment0 ~= dynamic.attachment then
		failDynamic(state, "dynamic force/orientation helper missing or disabled")
		return
	end
	local mass = if root.Anchored then dynamic.preparedMass else root.AssemblyMass
	local velocity = root.AssemblyLinearVelocity
	if not finite(mass) or mass <= 0 or not finite(velocity.Magnitude) then
		failDynamic(state, "invalid assembly mass or velocity after release")
		return
	end
	local stiffness = math.clamp(getNumberAttribute(boat, "BoatBuoyancyStiffness", 14), 0, 50)
	local damping = math.clamp(getNumberAttribute(boat, "BoatBuoyancyDamping", 7.5), 0, 30)
	local maxLift = math.clamp(getNumberAttribute(boat, "BoatMaxLiftMultiplier", 2.5), 1, 4)
	local acceleration = workspace.Gravity + (targetY - root.Position.Y) * stiffness - velocity.Y * damping
	dynamic.force.Force = Vector3.yAxis * mass * math.clamp(acceleration, 0, workspace.Gravity * maxLift)
	local strength = math.clamp(getNumberAttribute(boat, "WaterRotationStrength", 1), 0, 3)
	local up = Vector3.yAxis:Lerp(normal, strength).Unit
	local forward = root.CFrame.LookVector
	forward -= up * forward:Dot(up)
	if forward.Magnitude < 0.001 then forward = root.CFrame.RightVector:Cross(up) end
	dynamic.orientation.CFrame = CFrame.lookAt(Vector3.zero, forward.Unit, up) * dynamic.attachment.CFrame.Rotation
	dynamic.orientation.MaxTorque = mass * 1000
	if mode == "DYNAMIC_DRIVING" and not root.Anchored then
		BoatPropulsion.Update(dynamic.propulsion, boat, root, seat :: VehicleSeat, dynamic.attachment, up, dt)
	else
		BoatPropulsion.Stop(dynamic.propulsion)
	end
	state.targetY = targetY
	local now = os.clock()
	if now - dynamic.lastMessage >= 0.5 then
		dynamic.lastMessage = now
		dynamic.remote:FireServer(boat, session, if mode == "DYNAMIC_PREPARING" then "Ready" else "Alive")
	end
	if boat:GetAttribute("BoatPhysicsDebug") == true and now - dynamic.lastDebug >= 1 then
		dynamic.lastDebug = now
		local driverSeat = seat :: VehicleSeat
		print(string.format(
			"[BoatPhysics] boat=%s mode=%s root=%s seat=%s(%s) disabled=%s assembly=%s mass=%.2f rootY=%.2f targetY=%.2f wave=%.2f vy=%.2f forceY=%.2f steer=%.2f throttle=%.2f helm=%s normal=%s anchored=%s ownerId=%s",
			boat.Name, tostring(mode), root:GetFullName(), driverSeat:GetFullName(), driverSeat.ClassName,
			tostring(driverSeat.Disabled), tostring(root.AssemblyRootPart), mass, root.Position.Y,
			targetY, height, velocity.Y, dynamic.force.Force.Y, driverSeat.SteerFloat,
			driverSeat.ThrottleFloat, tostring(boat:GetAttribute("BoatHelmSteerFloat")), tostring(normal),
			tostring(root.Anchored), tostring(boat:GetAttribute("BoatDynamicDriverUserId"))
		))
	end
end

local function movePose(state: InteractableState, targetPosition: Vector3, rotation: CFrame)
	local root = state.root
	local targetCFrame = CFrame.new(targetPosition.X, targetPosition.Y, targetPosition.Z) * rotation

	if state.model then
		local delta = targetCFrame * root.CFrame:Inverse()
		state.model:PivotTo(delta * state.model:GetPivot())
		return
	end

	root.CFrame = targetCFrame
end

local function updateState(state: InteractableState, dt: number, cameraPosition: Vector3)
	local instance = state.instance
	if not instance.Parent or not state.root.Parent then
		removeInteractable(instance)
		return
	end

	if not isEnabled(instance) then
		return
	end
	local root = state.root
	-- No kinematic writes while a handoff is prepared, while any driver owns
	-- the assembly, or while its anchored state is still replicating.
	if isDynamicBoat(state) then
		local mode = instance:GetAttribute("BoatPhysicsMode")
		if state.dynamic or mode == "DYNAMIC_DRIVING" or not root.Anchored then return end
	end
	local storedTransform = instance:GetAttribute("CurrentTransform")
	local replicatedRest = if typeof(storedTransform) == "CFrame" then storedTransform else nil
	if replicatedRest and replicatedRest ~= state.restTransform and root.Anchored then
		state.restTransform = replicatedRest
		state.originPosition = replicatedRest.Position
		state.yaw = select(2, replicatedRest:ToOrientation())
		state.baseRotation = replicatedRest.Rotation
		state.targetPosition = replicatedRest.Position
		state.updateTimer = 0
	end
	if state.wasDynamic then
		if not root.Anchored then return end
		state.wasDynamic = false
		local resting = replicatedRest or root.CFrame
		state.restTransform = resting
		state.originPosition = resting.Position
		state.yaw = select(2, resting:ToOrientation())
		state.baseRotation = resting.Rotation
		state.currentRotation = root.CFrame.Rotation
		state.currentY = root.Position.Y
		state.targetPosition = resting.Position
		state.updateTimer = 0
	end
	if instance:GetAttribute("WaterBuoyancyOnContact") == true and instance:GetAttribute("WaterContacted") ~= true then
		if root.Position.Y > WaterConfig.GetSurfaceY() + 1 then
			return
		end
		instance:SetAttribute("WaterContacted", true)
	end

	local horizontalDistance = (Vector2.new(root.Position.X, root.Position.Z) - Vector2.new(
		cameraPosition.X,
		cameraPosition.Z
	)).Magnitude
	if horizontalDistance > MAX_UPDATE_DISTANCE then
		return
	end

	local profile = getProfile(instance)
	state.updateTimer -= dt
	if state.updateTimer <= 0 then
		local offset = getNumberAttribute(instance, "WaterVerticalOffset", 0)
		local strength = math.max(0, getNumberAttribute(instance, "WaterBuoyancyStrength", 1))
		local height, normal, displacement = sampleObject(state, profile)
		state.targetY = WaterConfig.GetSurfaceY() + height * strength + offset
		if instance:GetAttribute("WaterAllowHorizontalDrift") == true then
			state.targetPosition = state.originPosition + displacement
		else
			local parkedPosition = if profile == PROFILES.Boat then state.originPosition else state.root.Position
			state.targetPosition = Vector3.new(parkedPosition.X, 0, parkedPosition.Z)
		end

		local rotationStrength = math.max(0, getNumberAttribute(instance, "WaterRotationStrength", 1))
		if rotationStrength <= 0 then
			state.targetRotation = state.baseRotation
		else
			local yawFrame = CFrame.Angles(0, state.yaw, 0)
			local localNormal = yawFrame:VectorToObjectSpace(normal)
			local pitch = -math.atan2(localNormal.Z, localNormal.Y) * rotationStrength
			local roll = math.atan2(localNormal.X, localNormal.Y) * rotationStrength
			state.targetRotation = yawFrame * CFrame.Angles(pitch, 0, roll)
		end
		state.updateTimer = 1 / profile.UpdateHz
	end

	local alpha = 1 - math.exp(-POSITION_RESPONSE * dt)
	state.currentY = state.currentY + (state.targetY - state.currentY) * alpha
	local rotationAlpha = 1 - math.exp(-ROTATION_RESPONSE * dt)
	state.currentRotation = state.currentRotation:Lerp(state.targetRotation, rotationAlpha)

	movePose(state, Vector3.new(state.targetPosition.X, state.currentY, state.targetPosition.Z), state.currentRotation)
end

-- Physics runs before simulation and is independent of camera culling and
-- prop contact gates. Ordinary kinematic props retain their render update.
RunService.PreSimulation:Connect(function(dt: number)
	for instance, state in states do
		if not instance.Parent or not state.root.Parent then
			removeInteractable(instance)
			if instance.Parent and CollectionService:HasTag(instance, TAG_NAME) then addInteractable(instance) end
			continue
		end
		-- Prefer a BoatRoot that arrived after a streamed-in PrimaryPart.
		if getProfile(instance) == PROFILES.Boat then
			local resolved = getRoot(instance)
			if resolved and resolved ~= state.root then
				removeInteractable(instance)
				addInteractable(instance)
				continue
			end
		end
		if isDynamicBoat(state) or state.dynamic then
			local ok, err = pcall(updateDynamic, state, dt)
			if not ok then failDynamic(state, tostring(err)) end
		end
	end
end)

RunService:BindToRenderStep("WaterInteractionController", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	for _, state in states do
		updateState(state, dt, camera.CFrame.Position)
	end
end)
