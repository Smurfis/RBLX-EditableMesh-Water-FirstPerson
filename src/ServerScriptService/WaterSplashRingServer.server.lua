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
local SPLASH_TEXTURE = "rbxassetid://105796658952670"

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

local function emitSplashParticles(ring: BasePart, ringKind: string?)
	local attachment = Instance.new("Attachment")
	attachment.Name = "WaterSplashCenter"
	attachment.Parent = ring

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "WaterSplashParticles"
	emitter.Texture = SPLASH_TEXTURE
	emitter.Rate = 0
	emitter.LightEmission = 0.2
	emitter.Lifetime = if ringKind == "Footstep" then NumberRange.new(0.18, 0.32) else NumberRange.new(0.35, 0.65)
	emitter.Speed = if ringKind == "Footstep" then NumberRange.new(2, 4) elseif ringKind == "Paddle" then NumberRange.new(3, 6) else NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Drag = if ringKind == "Footstep" then 5 else 2
	emitter.Size = if ringKind == "Footstep"
		then NumberSequence.new(0.18)
		else if ringKind == "Paddle" then NumberSequence.new(0.28) else NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.25, 1.1),
			NumberSequenceKeypoint.new(1, 0.1),
		})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment
	emitter:Emit(if ringKind == "Footstep" then 4 elseif ringKind == "Paddle" then 3 else 18)
	Debris:AddItem(attachment, if ringKind == "Footstep" then 0.8 else 1.2)
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
	emitSplashParticles(ring, ringKind)

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
	if ringKind == "Paddle" then
		tweenGoal.Position = Vector3.new(requestedPosition.X, surfaceY, requestedPosition.Z)
	elseif ringKind == "Footstep" then
		-- Keep a foot ring just above its animated contact point. The client
		-- sampled that wave height; only settle it slightly into the contact.
		tweenGoal.Position = requestedPosition - Vector3.new(0, 0.08, 0)
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
