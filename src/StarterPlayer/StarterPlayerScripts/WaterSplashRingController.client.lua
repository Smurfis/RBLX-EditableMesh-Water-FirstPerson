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
local PADDLE_HAND_RANGE = 1.6
local PADDLE_DISTANCE = 0.12

local root: BasePart? = nil
local previousRootY: number? = nil
local previousHands: { [string]: Vector3 } = {}
local entryArmed = true
local lastPaddleAt = -math.huge

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

local function fireRing(position: Vector3)
	event:FireServer(Vector3.new(position.X, WaterConfig.GetSurfaceY(), position.Z))
end

local function bindCharacter(character: Model)
	root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	previousRootY = if root then root.Position.Y else nil
	previousHands = {}
	entryArmed = true
	lastPaddleAt = -math.huge
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

	-- Once the entry splash has fired, show restrained surface paddling rings
	-- near the hands. SurfaceHold is owned by SwimmingController and stays false
	-- while the player is jumping, so holding Space cannot spam entry splashes.
	if PlayerWaveMotionState.SurfaceHold and os.clock() - lastPaddleAt >= PADDLE_INTERVAL then
		local character = currentRoot.Parent
		if character and character:IsA("Model") then
			for _, side in ipairs({ "Left", "Right" }) do
				local hand = getHand(character, side)
				if hand then
					local handPosition = hand.Position
					local previousHand = previousHands[side]
					previousHands[side] = handPosition
					if math.abs(handPosition.Y - surfaceY) <= PADDLE_HAND_RANGE
						and previousHand
						and (handPosition - previousHand).Magnitude >= PADDLE_DISTANCE then
						lastPaddleAt = os.clock()
						fireRing(handPosition)
						break
					end
				end
			end
		end
	end
end)
