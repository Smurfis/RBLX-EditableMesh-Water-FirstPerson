--!strict

-- Local surface bob + body tilt. Swimming remains the sole velocity writer.
-- Samples are throttled; interpolation runs each simulation frame. The body
-- offset composes with animation/lean and never rotates the camera or root.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(modules:WaitForChild("WaterConfig"))
local Sampler = require(modules:WaitForChild("WaterWaveSampler"))
local State = require(modules:WaitForChild("PlayerWaveMotionState"))
local settings = Config.PlayerWaveMotion
local player = Players.LocalPlayer

local root: BasePart? = nil
local humanoid: Humanoid? = nil
local joint: Motor6D? = nil
local descendantConnection: RBXScriptConnection? = nil
local characterGeneration = 0
local targetHeight = 0
local targetNormal = Vector3.yAxis
local pitch = 0
local roll = 0
local sampleTimer = 0
local baseC0: CFrame? = nil

local function removeTilt()
	local currentJoint = joint
	-- Only remove our last write if animation/another controller has not
	if currentJoint and currentJoint.Parent and baseC0 then
		currentJoint.C0 = baseC0
	end
	baseC0 = nil
end

local function clearCharacter()
	characterGeneration += 1
	removeTilt()
	if descendantConnection then
		descendantConnection:Disconnect()
		descendantConnection = nil
	end
	root = nil
	humanoid = nil
	joint = nil
	baseC0 = nil
	targetHeight = 0
	targetNormal = Vector3.yAxis
	pitch = 0
	roll = 0
	sampleTimer = 0
	State.Offset = 0
end

local function bindCharacter(character: Model)
	clearCharacter()
	local generation = characterGeneration
	local newHumanoid = character:WaitForChild("Humanoid", 10)
	local newRoot = character:WaitForChild("HumanoidRootPart", 10)
	if generation ~= characterGeneration or player.Character ~= character then
		return
	end
	if not newHumanoid or not newHumanoid:IsA("Humanoid") or not newRoot or not newRoot:IsA("BasePart") then
		return
	end
	root = newRoot
	humanoid = newHumanoid

	local function findRootJoint(instance: Instance)
		if
			not joint
			and instance:IsA("Motor6D")
			and instance.Part0 == newRoot
			and instance.Part1
			and (instance.Part1.Name == "LowerTorso" or instance.Part1.Name == "Torso")
		then
			joint = instance
			baseC0 = instance.C0
		end
	end
	-- One character-only scan per spawn; R6 RootJoint and R15 Root supported.
	descendantConnection = character.DescendantAdded:Connect(findRootJoint)
	for _, instance in character:GetDescendants() do
		findRootJoint(instance)
	end
end

local characterAdded = player.CharacterAdded:Connect(bindCharacter)
local characterRemoving = player.CharacterRemoving:Connect(clearCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

	-- Remove the previous base-pose layer before animation/lean updates.
local preAnimation = RunService.PreAnimation:Connect(removeTilt)
local preSimulation = RunService.PreSimulation:Connect(function(dt: number)
	local currentRoot = root
	local currentHumanoid = humanoid
	if not currentRoot or not currentHumanoid or not currentRoot.Parent or currentHumanoid.Health <= 0 then
		removeTilt()
		State.Offset = 0
		return
	end

	local active = settings.Enabled
		and player:GetAttribute("PlayerWaveMotionEnabled") ~= false
		and State.Root == currentRoot
		and not State.PlatformRiding
		and State.SurfaceHold
		and currentHumanoid.FloorMaterial == Enum.Material.Air
		and not currentHumanoid.Sit
		and not currentHumanoid.PlatformStand

	if active then
		sampleTimer -= dt
		if sampleTimer <= 0 then
			local position = currentRoot.Position
			local sample = Sampler.Sample(position.X, position.Z, Sampler.GetTime(), settings.Octaves)
			targetHeight = math.clamp(sample.Height * settings.HeightStrength, -settings.MaxHeight, settings.MaxHeight)
			targetNormal = sample.Normal
			-- Drop missed samples following a stall rather than doing catch-up work.
			sampleTimer = 1 / settings.SampleHz
		end
	else
		sampleTimer = 0
		targetHeight = 0
		targetNormal = Vector3.yAxis
	end

	local alpha = 1 - math.exp(-settings.Response * dt)
	local maxStep = settings.MaxOffsetSpeed * dt
	State.Offset += math.clamp((targetHeight - State.Offset) * alpha, -maxStep, maxStep)
	if not active and math.abs(State.Offset) < 0.0001 then
		State.Offset = 0
	end

	local localNormal = currentRoot.CFrame:VectorToObjectSpace(targetNormal)
	local limit = math.rad(settings.MaxTiltDegrees)
	local targetPitch = if active
		then math.clamp(math.atan2(localNormal.Z, localNormal.Y) * settings.TiltStrength, -limit, limit)
		else 0
	local targetRoll = if active
		then math.clamp(-math.asin(math.clamp(localNormal.X, -1, 1)) * settings.TiltStrength, -limit, limit)
		else 0
	pitch += (targetPitch - pitch) * alpha
	roll += (targetRoll - roll) * alpha

	local currentJoint = joint
	if currentJoint and currentJoint.Parent and baseC0 then
		-- C0 is our stable base pose. CharacterLeanScript and the Animator
		-- remain free to compose their own per-frame Transform on top.
		local bindRotation = baseC0.Rotation
		local tilt = bindRotation:Inverse() * CFrame.Angles(pitch, 0, roll) * bindRotation
		currentJoint.C0 = baseC0 * tilt
	end
end)

script.Destroying:Connect(function()
	preAnimation:Disconnect()
	preSimulation:Disconnect()
	characterAdded:Disconnect()
	characterRemoving:Disconnect()
	clearCharacter()
end)
