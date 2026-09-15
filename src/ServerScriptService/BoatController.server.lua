--!strict

-- ServerScriptService > BoatController
--
-- Central steering controller for boats placed beneath Workspace.Boats.
-- Each direct child Model is expected to contain:
--   * a VehicleSeat named BoatSeat;
--   * a BasePart named Handle;
--   * a HingeConstraint beneath Handle.

local Workspace = game:GetService("Workspace")

local BOATS_FOLDER_NAME = "Boats"
local BOAT_SEAT_NAME = "BoatSeat"
local HELM_HANDLE_NAME = "Handle"
local DEFAULT_MAX_HELM_ANGLE = 45

type BoatBinding = {
	SteerConnection: RBXScriptConnection?,
	DescendantConnection: RBXScriptConnection,
	DescendantRemovingConnection: RBXScriptConnection,
}

local bindings: { [Model]: BoatBinding } = {}


local function disconnectSteering(
	binding: BoatBinding
)
	if binding.SteerConnection then
		binding.SteerConnection:Disconnect()
		binding.SteerConnection = nil
	end
end


local function findBoatSeat(
	boat: Model
): VehicleSeat?
	local candidate =
		boat:FindFirstChild(
			BOAT_SEAT_NAME,
			true
		)

	if candidate and candidate:IsA("VehicleSeat") then
		return candidate
	end

	return nil
end


local function findHelmHinge(
	boat: Model
): HingeConstraint?
	local handle =
		boat:FindFirstChild(
			HELM_HANDLE_NAME,
			true
		)

	if
		not handle
		or not handle:IsA("BasePart")
	then
		return nil
	end

	local hinge =
		handle:FindFirstChildWhichIsA(
			"HingeConstraint",
			true
		)

	return hinge
end


local function getMaxHelmAngle(
	boat: Model,
	seat: VehicleSeat
): number
	local configured =
		seat:GetAttribute("HelmMaxAngle")

	if typeof(configured) ~= "number" then
		configured = boat:GetAttribute("HelmMaxAngle")
	end

	if typeof(configured) == "number" then
		return math.abs(configured)
	end

	return DEFAULT_MAX_HELM_ANGLE
end


local function refreshBoat(
	boat: Model
)
	local binding =
		bindings[boat]

	if not binding then
		return
	end

	disconnectSteering(binding)

	local seat =
		findBoatSeat(boat)

	local hinge =
		findHelmHinge(boat)

	if not seat or not hinge then
		return
	end

	local function updateHelm()
		if
			not seat.Parent
			or not hinge.Parent
		then
			return
		end

		hinge.TargetAngle =
			seat.SteerFloat
			* getMaxHelmAngle(
				boat,
				seat
			)
	end

	binding.SteerConnection =
		seat:GetPropertyChangedSignal(
			"SteerFloat"
		):Connect(updateHelm)

	updateHelm()
end


local function addBoat(
	boat: Model
)
	if bindings[boat] then
		return
	end

	local binding: BoatBinding

	binding = {
		SteerConnection = nil,

		DescendantConnection =
			boat.DescendantAdded:Connect(function()
				task.defer(
					refreshBoat,
					boat
				)
			end),

		DescendantRemovingConnection =
			boat.DescendantRemoving:Connect(function()
				task.defer(
					refreshBoat,
					boat
				)
			end),
	}

	bindings[boat] = binding
	refreshBoat(boat)
end


local function removeBoat(
	boat: Model
)
	local binding =
		bindings[boat]

	if not binding then
		return
	end

	disconnectSteering(binding)
	binding.DescendantConnection:Disconnect()
	binding.DescendantRemovingConnection:Disconnect()
	bindings[boat] = nil
end


local boatsFolder =
	Workspace:WaitForChild(BOATS_FOLDER_NAME)

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
