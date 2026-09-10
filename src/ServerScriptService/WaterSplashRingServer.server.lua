-- Replicates validated water-contact splash rings for every player.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local WaterConfig = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WaterConfig")
)

local EVENT_NAME = "WaterSplashRingEvent"
local MAX_DISTANCE_FROM_PLAYER = 16
local MAX_SURFACE_DISTANCE = 4
local COOLDOWN = 0.55

local event = ReplicatedStorage:FindFirstChild(EVENT_NAME)
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = EVENT_NAME
	event.Parent = ReplicatedStorage
end

local lastSplashAt: { [Player]: number } = {}

local function getTemplate(): BasePart?
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local assets = shared and shared:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("SplashRing")
	if template and template:IsA("BasePart") then
		return template
	end
	return nil
end

event.OnServerEvent:Connect(function(player, requestedPosition, ringKind)
	if typeof(requestedPosition) ~= "Vector3" then
		return
	end
	if ringKind ~= nil and ringKind ~= "Paddle" and ringKind ~= "Footstep" then
		return
	end

	local now = os.clock()
	if now - (lastSplashAt[player] or -math.huge) < COOLDOWN then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local surfaceY = WaterConfig.GetSurfaceY()
	if (Vector3.new(requestedPosition.X, root.Position.Y, requestedPosition.Z) - root.Position).Magnitude
		> MAX_DISTANCE_FROM_PLAYER
		or math.abs(requestedPosition.Y - surfaceY) > MAX_SURFACE_DISTANCE then
		return
	end

	local template = getTemplate()
	if not template then
		return
	end

	lastSplashAt[player] = now
	local ring = template:Clone()
	ring.Name = if ringKind == "Paddle" then "WaterPaddleRing" elseif ringKind == "Footstep" then "WaterFootstepRing" else "WaterSplashRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CFrame = CFrame.new(requestedPosition) * (template.CFrame - template.Position)
	ring.Parent = workspace

	local initialSize = ring.Size
	if ringKind == "Paddle" then
		initialSize *= 0.756
		ring.Size = initialSize
	elseif ringKind == "Footstep" then
		initialSize *= 0.42
		ring.Size = initialSize
	else
		-- Give the initial jump-in impact a thicker, more readable body.
		initialSize = Vector3.new(initialSize.X * 1.1, initialSize.Y * 1.5, initialSize.Z * 1.1)
		ring.Size = initialSize
	end
	ring.Transparency = template.Transparency
	local tweenGoal = {
		Size = initialSize * (if ringKind == "Paddle" then 1.35 elseif ringKind == "Footstep" then 1.5 else 2.5),
		Transparency = 1,
	}
	if ringKind == "Paddle" or ringKind == "Footstep" then
		tweenGoal.Position = Vector3.new(requestedPosition.X, surfaceY, requestedPosition.Z)
	end
	local tween = TweenService:Create(
		ring,
		TweenInfo.new(if ringKind == "Paddle" then 0.85 elseif ringKind == "Footstep" then 0.45 else 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		tweenGoal
	)
	tween:Play()
	Debris:AddItem(ring, if ringKind == "Paddle" then 1 elseif ringKind == "Footstep" then 0.6 else 1.0)
end)

game.Players.PlayerRemoving:Connect(function(player)
	lastSplashAt[player] = nil
end)
