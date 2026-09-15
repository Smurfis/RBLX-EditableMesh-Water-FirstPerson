local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local HAND_IK_PRIORITY = 10


local function getBoatForSeat(
	seatPart: BasePart
): Model?
	if
		seatPart.Name ~= "BoatSeat"
		or not seatPart:IsA("VehicleSeat")
	then
		return nil
	end

	local boatsFolder =
		Workspace:FindFirstChild("Boats")

	if not boatsFolder then
		return nil
	end

	local candidate: Instance? =
		seatPart

	while
		candidate
		and candidate.Parent ~= boatsFolder
	do
		candidate = candidate.Parent
	end

	if
		candidate
		and candidate:IsA("Model")
	then
		return candidate
	end

	return nil
end


local function clearHandTargets(
	ikLeft: IKControl,
	ikRight: IKControl
)
	ikLeft.Enabled = false
	ikRight.Enabled = false
	ikLeft.Target = nil
	ikRight.Target = nil
end


local function CharacterAdded(character)
	local humanoid =
		character:WaitForChild("Humanoid")

	------------------------------------------------------------
	-- ARM PARTS
	------------------------------------------------------------

	local leftUpperArm =
		character:WaitForChild("LeftUpperArm")

	local leftHand =
		character:WaitForChild("LeftHand")

	local rightUpperArm =
		character:WaitForChild("RightUpperArm")

	local rightHand =
		character:WaitForChild("RightHand")


	------------------------------------------------------------
	-- LEFT ARM IK
	------------------------------------------------------------

	local ikLeft =
		Instance.new("IKControl")

	ikLeft.Name =
		"SteeringWheelIK_Left"

	ikLeft.Enabled =
		false

	ikLeft.Type =
		Enum.IKControlType.Transform

	-- The arm itself is the IK chain.
	--
	-- LeftUpperArm
	--      ↓
	-- LeftLowerArm
	--      ↓
	-- LeftHand
	--
	-- The torso can rotate independently underneath this.
	ikLeft.ChainRoot =
		leftUpperArm

	ikLeft.EndEffector =
		leftHand

	-- Higher than the seated torso IK.
	--
	-- Torso moves first,
	-- then the arm corrects itself back onto the wheel.
	ikLeft.Priority =
		HAND_IK_PRIORITY

	ikLeft.Weight =
		1

	-- Don't deliberately lag behind the wheel target.
	ikLeft.SmoothTime =
		0

	ikLeft.Parent =
		humanoid


	------------------------------------------------------------
	-- RIGHT ARM IK
	------------------------------------------------------------

	local ikRight =
		Instance.new("IKControl")

	ikRight.Name =
		"SteeringWheelIK_Right"

	ikRight.Enabled =
		false

	ikRight.Type =
		Enum.IKControlType.Transform

	ikRight.ChainRoot =
		rightUpperArm

	ikRight.EndEffector =
		rightHand

	ikRight.Priority =
		HAND_IK_PRIORITY

	ikRight.Weight =
		1

	ikRight.SmoothTime =
		0

	ikRight.Parent =
		humanoid


	------------------------------------------------------------
	-- SEATED
	------------------------------------------------------------

	humanoid.Seated:Connect(
		function(active, seatPart)

			----------------------------------------------------
			-- LEFT SEAT
			----------------------------------------------------

			if not active then
				clearHandTargets(
					ikLeft,
					ikRight
				)

				return
			end


			----------------------------------------------------
			-- VALIDATE SEAT
			----------------------------------------------------

			if not seatPart then
				return
			end

			local boat =
				getBoatForSeat(seatPart)

			if not boat then
				clearHandTargets(
					ikLeft,
					ikRight
				)

				return
			end


			----------------------------------------------------
			-- FIND STEERING HANDLE
			----------------------------------------------------

			local handle =
				boat:FindFirstChild(
					"Handle",
					true
				)

			if
				not handle
				or not handle:IsA("BasePart")
			then
				warn(
					string.format(
						"[HandsInitializer] %s requires a BasePart named Handle beneath the boat model",
						boat:GetFullName()
					)
				)

				clearHandTargets(
					ikLeft,
					ikRight
				)

				return
			end


			----------------------------------------------------
			-- FIND HAND TARGETS
			----------------------------------------------------

			local leftAttachment =
				handle:FindFirstChild(
					"LeftAttachment"
				)

			local rightAttachment =
				handle:FindFirstChild(
					"RightAttachment"
				)

			if
				not leftAttachment
				or not leftAttachment:IsA("Attachment")
				or not rightAttachment
				or not rightAttachment:IsA("Attachment")
			then
				warn(
					string.format(
						"[HandsInitializer] %s.Handle is missing LeftAttachment or RightAttachment",
						boat:GetFullName()
					)
				)

				clearHandTargets(
					ikLeft,
					ikRight
				)

				return
			end


			----------------------------------------------------
			-- LOCK HANDS TO WHEEL
			----------------------------------------------------

			ikLeft.Target =
				leftAttachment

			ikRight.Target =
				rightAttachment

			ikLeft.Enabled =
				true

			ikRight.Enabled =
				true
		end
	)
end


------------------------------------------------------------
-- PLAYER SETUP
------------------------------------------------------------

local function PlayerAdded(player)

	if player.Character then
		task.spawn(
			CharacterAdded,
			player.Character
		)
	end

	player.CharacterAdded:Connect(
		CharacterAdded
	)
end


------------------------------------------------------------
-- EXISTING PLAYERS
------------------------------------------------------------

for _, player
	in Players:GetPlayers()
do
	PlayerAdded(player)
end


------------------------------------------------------------
-- NEW PLAYERS
------------------------------------------------------------

Players.PlayerAdded:Connect(
	PlayerAdded
)
