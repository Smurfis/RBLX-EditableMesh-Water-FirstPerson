local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WaterConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WaterConfig"))

local player = Players.LocalPlayer
local slime = workspace:WaitForChild("Slime", 10)
local previousY: number? = nil
local wasInWater = false

local function makeSplash(position: Vector3)
	local assets = ReplicatedStorage:FindFirstChild("Shared")
	local template = assets and assets:FindFirstChild("Assets") and assets.Assets:FindFirstChild("SplashRing")
	local ring = if template and template:IsA("BasePart") then template:Clone() else Instance.new("Part")
	ring.Name = "SlimeWaterSplash"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Size = if template and template:IsA("BasePart") then template.Size else Vector3.new(3, 0.08, 3)
	if ring:IsA("Part") then
		ring.Shape = Enum.PartType.Cylinder
	end
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	local attachment = Instance.new("Attachment")
	attachment.Parent = ring
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://105796658952670"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.35, 0.65)
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Size = NumberSequence.new(0.8)
	emitter.Parent = attachment
	emitter:Emit(18)
	local startSize = ring.Size
	ring.Size = startSize * 1.15
	TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
		Size = startSize * 2.5,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 1)
end

if slime and slime:IsA("Model") then
	local root = slime.PrimaryPart or slime:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		game:GetService("RunService").Heartbeat:Connect(function()
			local y = root.Position.Y
			local surfaceY = WaterConfig.GetSurfaceY()
			local inWater = y <= surfaceY + 1.5
			if previousY and not wasInWater and inWater and y < previousY - 0.15 then
				makeSplash(Vector3.new(root.Position.X, surfaceY, root.Position.Z))
			end
			previousY = y
			wasInWater = inWater
		end)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or (input.KeyCode ~= Enum.KeyCode.G and input.KeyCode ~= Enum.KeyCode.E) then return end
	if input.KeyCode == Enum.KeyCode.E and (not slime or slime:GetAttribute("SlimeHolderUserId") ~= player.UserId) then return end
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("RemoteEvent") and descendant.Name == "DropEvent" then
			descendant:FireServer()
		end
	end
end)
