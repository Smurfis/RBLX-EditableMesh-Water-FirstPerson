--!strict

-- ServerScriptService > BoatController
--
-- Central steering controller for boats placed beneath Workspace.Boats.
-- Each direct child Model is expected to contain:
--   * a VehicleSeat named BoatSeat;
--   * a BasePart named Handle;
--   * a HingeConstraint beneath either the boat or Handle.

local Workspace = game:GetService("Workspace")

local BoatDynamicAuthority = require(script.Parent:WaitForChild("BoatDynamicAuthority"))

local BOATS_FOLDER_NAME = "Boats"
local BOAT_SEAT_NAME = "BoatSeat"
local HELM_HANDLE_NAME = "Handle"
local DEFAULT_MAX_HELM_ANGLE = 45

type BoatBinding = {
	SteerConnection: RBXScriptConnection?,
	ThrottleConnection: RBXScriptConnection?,
	OccupantConnection: RBXScriptConnection?,
	DescendantConnection: RBXScriptConnection,
	DescendantRemovingConnection: RBXScriptConnection,
	AttributeConnection: RBXScriptConnection,
}

local bindings: { [Model]: BoatBinding } = {}

local function disconnectSteering(binding: BoatBinding)
	if binding.SteerConnection then
		binding.SteerConnection:Disconnect()
		binding.SteerConnection = nil
	end
	if binding.ThrottleConnection then
		binding.ThrottleConnection:Disconnect()
		binding.ThrottleConnection = nil
	end
end

local function disconnectOccupant(binding: BoatBinding)
	if binding.OccupantConnection then
		binding.OccupantConnection:Disconnect()
		binding.OccupantConnection = nil
	end
end

local function findBoatSeat(boat: Model): VehicleSeat?
	local candidate = boat:FindFirstChild(BOAT_SEAT_NAME, true)

	if candidate and candidate:IsA("VehicleSeat") then
		return candidate
	end

	return nil
end

local function findHelmHinge(boat: Model): HingeConstraint?
	-- The original in-boat script used script.Parent.HingeConstraint, so
	-- prefer a specifically named hinge anywhere beneath the boat model.
	local namedHinge = boat:FindFirstChild("HingeConstraint", true)

	if namedHinge and namedHinge:IsA("HingeConstraint") then
		return namedHinge
	end

	-- Also support helm imports that keep the constraint beneath Handle.
	local handle = boat:FindFirstChild(HELM_HANDLE_NAME, true)

	if not handle or not handle:IsA("BasePart") then
		return nil
	end

	local hinge = handle:FindFirstChildWhichIsA("HingeConstraint", true)

	return hinge
end

local function getMaxHelmAngle(boat: Model, seat: VehicleSeat): number
	local configured = seat:GetAttribute("HelmMaxAngle")

	if typeof(configured) ~= "number" then
		configured = boat:GetAttribute("HelmMaxAngle")
	end

	if typeof(configured) == "number" then
		return math.abs(configured)
	end

	return DEFAULT_MAX_HELM_ANGLE
end

local function refreshBoat(boat: Model)
	local binding = bindings[boat]

	if not binding then
		return
	end

	disconnectSteering(binding)
	disconnectOccupant(binding)
	BoatDynamicAuthority.Refresh(boat)

	local seat = findBoatSeat(boat)

	local hinge = findHelmHinge(boat)

	if not seat then
		return
	end

	binding.OccupantConnection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		BoatDynamicAuthority.Refresh(boat)
	end)

	if not hinge then
		return
	end

	local function updateHelm()
		if not seat.Parent or not hinge.Parent then
			return
		end

		hinge.TargetAngle = seat.SteerFloat * getMaxHelmAngle(boat, seat)
		boat:SetAttribute("BoatHelmSteerFloat", seat.SteerFloat)
		boat:SetAttribute("BoatHelmThrottleFloat", seat.ThrottleFloat)
	end

	binding.SteerConnection = seat:GetPropertyChangedSignal("SteerFloat"):Connect(updateHelm)
	binding.ThrottleConnection = seat:GetPropertyChangedSignal("ThrottleFloat"):Connect(updateHelm)
	updateHelm()
end

local function addBoat(boat: Model)
	if bindings[boat] then
		return
	end

	local binding: BoatBinding

	binding = {
		SteerConnection = nil,
		ThrottleConnection = nil,
		OccupantConnection = nil,
		AttributeConnection = boat.AttributeChanged:Connect(function(name)
			if name == "WaterDynamicPhysics" or name == "WaterProfile" or name == "WaterEnabled" then
				BoatDynamicAuthority.Refresh(boat)
			end
		end),

		DescendantConnection = boat.DescendantAdded:Connect(function()
			task.defer(refreshBoat, boat)
		end),

		DescendantRemovingConnection = boat.DescendantRemoving:Connect(function()
			task.defer(refreshBoat, boat)
		end),
	}

	bindings[boat] = binding
	refreshBoat(boat)
end

local function removeBoat(boat: Model)
	local binding = bindings[boat]

	if not binding then
		return
	end

	disconnectSteering(binding)
	disconnectOccupant(binding)
	BoatDynamicAuthority.Remove(boat)
	binding.AttributeConnection:Disconnect()
	binding.DescendantConnection:Disconnect()
	binding.DescendantRemovingConnection:Disconnect()
	bindings[boat] = nil
end

local boatsFolder = Workspace:WaitForChild(BOATS_FOLDER_NAME)

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
