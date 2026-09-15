local Players = game:GetService("Players")

local HAND_IK_PRIORITY = 10


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
				ikLeft.Enabled =
					false

				ikRight.Enabled =
					false

				ikLeft.Target =
					nil

				ikRight.Target =
					nil

				return
			end


			----------------------------------------------------
			-- VALIDATE SEAT
			----------------------------------------------------

			if not seatPart then
				return
			end

			local seatModel =
				seatPart.Parent

			if not seatModel then
				return
			end


			----------------------------------------------------
			-- FIND STEERING HANDLE
			----------------------------------------------------

			local handle =
				seatModel:FindFirstChild("Handle")

			if not handle then
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
					"Steering wheel Handle is missing valid hand attachments"
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