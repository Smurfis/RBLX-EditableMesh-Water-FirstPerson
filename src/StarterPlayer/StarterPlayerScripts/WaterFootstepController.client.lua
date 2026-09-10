--!strict

-- Replaces Roblox's regular running sound while the character is wading at
-- the water surface. The normal character sounds return as soon as the feet
-- leave the water band.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterConfig = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterConfig")
)
local WaterWaveSampler = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterWaveSampler")
)

local waterSounds = ReplicatedStorage
	:WaitForChild("Shared")
	:WaitForChild("Sounds")
	:WaitForChild("Water")
local splashEvent = ReplicatedStorage:WaitForChild("WaterSplashRingEvent")

local shallowFootstepTemplate = waterSounds:FindFirstChild("ShallowFootsteps")
if not shallowFootstepTemplate or not shallowFootstepTemplate:IsA("Sound") then
	warn("[WaterFootsteps] ShallowFootsteps is missing from ReplicatedStorage.Shared.Sounds.Water; falling back to WaterSplashEntry.")
	shallowFootstepTemplate = waterSounds:WaitForChild("WaterSplashEntry")
end
assert(shallowFootstepTemplate:IsA("Sound"), "ReplicatedStorage.Shared.Sounds.Water.ShallowFootsteps must be a Sound")

local player = Players.LocalPlayer

local FOOT_WATER_DEPTH = 4
-- Keep shallow walking active slightly above the visible wave edge. The
-- footprint ring still uses the separate calibrated foot-contact plane.
local FOOT_WATER_MARGIN = 1.4
local FOOT_RING_CONTACT_TOLERANCE = 0.75
local FOOT_RING_HEIGHT_OFFSET = 0.08
local FOOT_CONTACT_OFFSET = WaterConfig.Swimming.SurfaceTest.FootContactOffset or 1.458
local MIN_ROOT_HEIGHT_ABOVE_SURFACE = 0.4
local MAX_ROOT_HEIGHT_ABOVE_SURFACE = 6.0
local MIN_STEP_INTERVAL = 0.24
local MAX_STEP_INTERVAL = 0.55
local STEP_SPEED_SCALE = 0.018
local STEP_VOLUME_SCALE = 0.55

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local waterFootstep: Sound? = nil
local descendantConnection: RBXScriptConnection? = nil
local savedRunningVolumes: { [Sound]: number } = {}
local stepClock = 0
local shallowPaused = false

local function isRunningSound(instance: Instance): boolean
	return instance:IsA("Sound") and instance.Name == "Running"
end

local function muteRunningSound(instance: Instance)
	if not isRunningSound(instance) then
		return
	end

	local sound = instance :: Sound
	if savedRunningVolumes[sound] == nil then
		savedRunningVolumes[sound] = sound.Volume
	end
	sound.Volume = 0
end

local function restoreRunningSounds()
	for sound, volume in savedRunningVolumes do
		if sound.Parent then
			sound.Volume = volume
		end
	end
	table.clear(savedRunningVolumes)
end

local function destroyWaterFootstep()
	if waterFootstep then
		waterFootstep:Destroy()
		waterFootstep = nil
	end
	restoreRunningSounds()
	if descendantConnection then
		descendantConnection:Disconnect()
		descendantConnection = nil
	end
end

local function setupCharacter(newCharacter: Model)
	destroyWaterFootstep()
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
	rootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart

	local shallowSound = shallowFootstepTemplate:Clone()
	shallowSound.Name = "ShallowFootsteps_Local"
	shallowSound.Looped = true
	shallowSound.Volume *= STEP_VOLUME_SCALE
	shallowSound.Parent = rootPart
	shallowSound:Stop()
	waterFootstep = shallowSound
	shallowPaused = false

	for _, descendant in newCharacter:GetDescendants() do
		muteRunningSound(descendant)
	end
	descendantConnection = newCharacter.DescendantAdded:Connect(muteRunningSound)
	stepClock = 0
end

local function getFootParts(currentCharacter: Model): { BasePart }
	local parts = {}
	for _, name in { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" } do
		local part = currentCharacter:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

local function feetTouchWater(currentCharacter: Model, currentRoot: BasePart): (boolean, BasePart?, number?)
	local surfaceY = WaterConfig.GetSurfaceY()
	local rootHeight = currentRoot.Position.Y - surfaceY
	if rootHeight < MIN_ROOT_HEIGHT_ABOVE_SURFACE
		or rootHeight > MAX_ROOT_HEIGHT_ABOVE_SURFACE
	then
		return false, nil, nil
	end

	for _, foot in getFootParts(currentCharacter) do
		local footY = foot.Position.Y
		local wave = WaterWaveSampler.Sample(foot.Position.X, foot.Position.Z, nil, 6)
		local animatedSurfaceY = surfaceY + wave.Height
		local footContactY = surfaceY + FOOT_CONTACT_OFFSET
		local shallowTopY = math.max(animatedSurfaceY + FOOT_WATER_MARGIN, footContactY + FOOT_WATER_MARGIN)
		if footY <= shallowTopY
			and footY >= footContactY - FOOT_WATER_DEPTH
		then
			local ringSurfaceY = if footY <= footContactY + FOOT_RING_CONTACT_TOLERANCE
				and footY >= footContactY - FOOT_WATER_DEPTH
				then footContactY
				else nil
			return true, foot, ringSurfaceY
		end
	end
	return false, nil, nil
end

local function playWaterStep(speed: number, foot: BasePart?, ringSurfaceY: number?)
	local sound = waterFootstep
	if not sound then
		return
	end

	sound.PlaybackSpeed = math.clamp(0.9 + speed / 24, 0.9, 1.45)
	if not sound.IsPlaying then
		sound.TimePosition = 0
		sound:Play()
	end
	if foot and ringSurfaceY then
		splashEvent:FireServer(
			Vector3.new(foot.Position.X, ringSurfaceY + FOOT_RING_HEIGHT_OFFSET, foot.Position.Z),
			"Footstep"
		)
	end
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then
	task.spawn(setupCharacter, player.Character)
end

RunService.Heartbeat:Connect(function(deltaTime)
	local currentCharacter = character
	local currentHumanoid = humanoid
	local currentRoot = rootPart
	if not currentCharacter or not currentHumanoid or not currentRoot then
		return
	end

	local touchingWater, touchingFoot, ringSurfaceY = feetTouchWater(currentCharacter, currentRoot)
	if not touchingWater then
		restoreRunningSounds()
		stepClock = 0
		if waterFootstep then
			waterFootstep:Stop()
		end
		shallowPaused = false
		return
	end

	for sound in pairs(savedRunningVolumes) do
		if sound.Parent then
			sound.Volume = 0
			if sound.IsPlaying then
				sound:Stop()
			end
		end
	end
	for _, descendant in currentCharacter:GetDescendants() do
		if isRunningSound(descendant) then
			local runningSound = descendant :: Sound
			if savedRunningVolumes[runningSound] == nil then
				savedRunningVolumes[runningSound] = runningSound.Volume
			end
			runningSound.Volume = 0
			if runningSound.IsPlaying then
				runningSound:Stop()
			end
		end
	end

	local speed = currentRoot.AssemblyLinearVelocity.Magnitude
	local moving = currentHumanoid.MoveDirection.Magnitude > 0.05
	if not moving or currentHumanoid.FloorMaterial == Enum.Material.Air then
		stepClock = 0
		if waterFootstep and waterFootstep.IsPlaying then
			waterFootstep.Looped = false
			waterFootstep:Pause()
			shallowPaused = true
		end
		return
	end
	if waterFootstep then
		waterFootstep.Looped = true
		if shallowPaused then
			waterFootstep:Resume()
			shallowPaused = false
		end
	end

	stepClock -= deltaTime
	if stepClock <= 0 then
		playWaterStep(speed, touchingFoot, ringSurfaceY)
		stepClock = math.clamp(
			MAX_STEP_INTERVAL - speed * STEP_SPEED_SCALE,
			MIN_STEP_INTERVAL,
			MAX_STEP_INTERVAL
		)
	end
end)
