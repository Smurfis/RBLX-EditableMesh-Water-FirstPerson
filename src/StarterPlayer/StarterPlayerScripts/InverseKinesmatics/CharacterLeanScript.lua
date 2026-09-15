--[[
	CharacterLeanScript

	Lean while moving on foot.

	IMPORTANT:
	While seated this script does not touch the Root Motor6D at all,
	because the seated body-turn IK needs the Root + Waist chain.
]]

local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

if script.Parent == StarterPlayer.StarterCharacterScripts then
	return
end

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local rootJoint = character:WaitForChild("LowerTorso"):WaitForChild("Root")

local ROLL_ANGLE = math.rad(15)
local PITCH_ANGLE = math.rad(5)
local LEAN_SPEED = 10

local leanCFrame = CFrame.new()

local function onStepped(_: number, deltaTime: number)
	-- Do not compete with seated Root/LowerTorso IK.
	if humanoid.SeatPart ~= nil then
		leanCFrame = CFrame.new()
		return
	end

	local moveVelocity = humanoid:GetMoveVelocity()
	local relativeVelocity =
		root.CFrame:VectorToObjectSpace(
			moveVelocity
		)

	local pitch = 0
	local roll = 0

	if humanoid.WalkSpeed ~= 0 then
		pitch =
			math.clamp(
				relativeVelocity.Z / humanoid.WalkSpeed,
				-1,
				1
			)
			* PITCH_ANGLE

		roll =
			-math.clamp(
				relativeVelocity.X / humanoid.WalkSpeed,
				-1,
				1
			)
			* ROLL_ANGLE
	end

	leanCFrame =
		leanCFrame:Lerp(
			CFrame.Angles(
				pitch,
				0,
				roll
			),
			math.min(
				deltaTime * LEAN_SPEED,
				1
			)
		)

	rootJoint.Transform =
		leanCFrame
		* rootJoint.Transform
end

RunService.Stepped:Connect(onStepped)
