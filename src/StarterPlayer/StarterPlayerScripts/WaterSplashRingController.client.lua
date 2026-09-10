-- Detects local downward contact with the configured water surface.
-- The server validates and replicates the visual ring to every client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WaterConfig = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WaterConfig")
)
local PlayerWaveMotionState = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerWaveMotionState")
)

local player = Players.LocalPlayer
local event = ReplicatedStorage:WaitForChild("WaterSplashRingEvent")

local ENTRY_HEIGHT = WaterConfig.Swimming.EnterOffset
local ENTRY_REARM_HEIGHT = 4
local PADDLE_INTERVAL = 0.85
local PADDLE_FORWARD_DISTANCE = 1.35
local PADDLE_MIN_SPEED = 1.5

local root: BasePart? = nil
local previousRootY: number? = nil
local entryArmed = true
local lastPaddleAt = -math.huge
local paddleSide = 1

local function getHand(character: Model, side: string): BasePart?
	local names = if side == "Left" then { "LeftHand", "Left Arm" } else { "RightHand", "Right Arm" }
	for _, name in ipairs(names) do
		local hand = character:FindFirstChild(name)
		if hand and hand:IsA("BasePart") then
			return hand
		end
	end
	return nil
end

local function fireRing(position: Vector3, ringKind: string?)
	event:FireServer(
		Vector3.new(position.X, WaterConfig.GetSurfaceY(), position.Z),
		ringKind
	)
end

local function bindCharacter(character: Model)
	root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	previousRootY = if root then root.Position.Y else nil
	entryArmed = true
	lastPaddleAt = -math.huge
	paddleSide = 1
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

RunService.RenderStepped:Connect(function()
	local currentRoot = root
	if not currentRoot or not currentRoot.Parent then
		return
	end

	local surfaceY = WaterConfig.GetSurfaceY()
	local currentRootY = currentRoot.Position.Y
	local previousY = previousRootY
	previousRootY = currentRootY
	if not previousY then
		return
	end

	local threshold = surfaceY + ENTRY_HEIGHT
	if currentRootY > threshold + ENTRY_REARM_HEIGHT then
		entryArmed = true
	end
	local descending = currentRoot.AssemblyLinearVelocity.Y <= 2
	if previousY > threshold
		and currentRootY <= threshold
		and descending
		and entryArmed then
		entryArmed = false
		fireRing(currentRoot.Position)
	end

	-- Surface paddling follows swimming direction rather than hand height. The
	-- hand animation often leaves hands visibly above the surface while moving
	-- forward, so place an alternating ring just ahead of each hand at the
	-- CoastLine/waterline instead.
	if PlayerWaveMotionState.SurfaceHold and os.clock() - lastPaddleAt >= PADDLE_INTERVAL then
		local character = currentRoot.Parent
		if character and character:IsA("Model") then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local velocity = currentRoot.AssemblyLinearVelocity
				local movement = Vector3.new(velocity.X, 0, velocity.Z)
				if movement.Magnitude < PADDLE_MIN_SPEED and humanoid then
					movement = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
				end
				if movement.Magnitude >= PADDLE_MIN_SPEED then
					local direction = movement.Unit
					local sideName = if paddleSide < 0 then "Left" else "Right"
					local hand = getHand(character, sideName)
					local handPosition = if hand then hand.Position else currentRoot.Position
					local ringPosition = handPosition + direction * PADDLE_FORWARD_DISTANCE
					lastPaddleAt = os.clock()
					paddleSide *= -1
					fireRing(ringPosition, "Paddle")
				end
			end
		end
	end
end)
