-- Purely visual underwater bubbles. They have no collision or gameplay effect.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WaterConfig"))
local player = Players.LocalPlayer
local rng = Random.new()
local elapsed = 0
local nextSpawn = 0.2
local bubbleFolder = Instance.new("Folder")
bubbleFolder.Name = "UnderwaterBubbles_Local"
bubbleFolder.Parent = workspace

local function spawnBubble(cameraPosition: Vector3)
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(8, 18)
	local position = cameraPosition + Vector3.new(math.cos(angle) * distance, rng:NextNumber(-3, 5), math.sin(angle) * distance)
	local bubble = Instance.new("Part")
	bubble.Name = "UnderwaterBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.one * rng:NextNumber(0.12, 0.42)
	bubble.Material = Enum.Material.ForceField
	bubble.Color = Color3.fromRGB(190, 235, 255)
	bubble.Transparency = rng:NextNumber(0.2, 0.5)
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanTouch = false
	bubble.CanQuery = false
	bubble.CFrame = CFrame.new(position)
	bubble.Parent = bubbleFolder

	local lifetime = rng:NextNumber(1.2, 2.4)
	TweenService:Create(bubble, TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = position + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(2, 5), rng:NextNumber(-1, 1)),
		Size = bubble.Size * rng:NextNumber(1.4, 2.2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(bubble, lifetime + 0.1)
end

RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local underwater = camera.CFrame.Position.Y < WaterConfig.GetSurfaceY() - WaterConfig.Underwater.CameraEnterDepth
	if not underwater then
		elapsed = 0
		return
	end
	elapsed += dt
	if elapsed >= nextSpawn then
		elapsed = 0
		nextSpawn = rng:NextNumber(0.18, 0.55)
		spawnBubble(camera.CFrame.Position)
	end
end)

player.AncestryChanged:Connect(function(_, parent)
	if not parent then bubbleFolder:Destroy() end
end)
