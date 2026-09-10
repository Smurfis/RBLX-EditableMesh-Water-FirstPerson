-- Detects local downward contact with the configured water surface.
-- The server validates and replicates the visual ring to every client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WaterConfig = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WaterConfig")
)

local player = Players.LocalPlayer
local event = ReplicatedStorage:WaitForChild("WaterSplashRingEvent")

local ENTRY_HEIGHT = WaterConfig.Swimming.EnterOffset
local LOCAL_COOLDOWN = 0.55

local root: BasePart? = nil
local previousRootY: number? = nil
local lastSplashAt = -math.huge

local function bindCharacter(character: Model)
	root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	previousRootY = if root then root.Position.Y else nil
	lastSplashAt = -math.huge
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
	local descending = currentRoot.AssemblyLinearVelocity.Y <= 2
	if previousY > threshold
		and currentRootY <= threshold
		and descending
		and os.clock() - lastSplashAt >= LOCAL_COOLDOWN then
		lastSplashAt = os.clock()
		event:FireServer(Vector3.new(currentRoot.Position.X, surfaceY, currentRoot.Position.Z))
	end
end)
