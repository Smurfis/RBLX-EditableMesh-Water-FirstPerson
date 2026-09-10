--!strict

-- Carries the local character with an opted-in WaterInteractable platform.
-- The platform controller remains responsible for moving the Part/Model; this
-- controller applies the platform's last full CFrame delta to the character
-- after that movement, so feet, body, and camera inherit bobbing and rotation.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local playerWaveState = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerWaveMotionState")
)

local TAG_NAME = "WaterInteractable"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 3

local player = Players.LocalPlayer
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local characterConnection: RBXScriptConnection? = nil
local floorRaycastParams: RaycastParams? = nil

local ridingPlatform: Instance? = nil
local previousPlatformCFrame: CFrame? = nil

local function clearPlatform()
	ridingPlatform = nil
	previousPlatformCFrame = nil
	playerWaveState.PlatformRiding = false
end

local function bindCharacter(character: Model)
	clearPlatform()
	if characterConnection then
		characterConnection:Disconnect()
		characterConnection = nil
	end

	local currentHumanoid = character:WaitForChild("Humanoid", 10)
	local currentRoot = character:WaitForChild("HumanoidRootPart", 10)
	if not currentHumanoid or not currentHumanoid:IsA("Humanoid")
		or not currentRoot or not currentRoot:IsA("BasePart") then
		humanoid = nil
		root = nil
		return
	end

	humanoid = currentHumanoid
	root = currentRoot
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	floorRaycastParams = params
	characterConnection = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			clearPlatform()
		end
	end)
end

local function getPlatformFromFloor(floorPart: BasePart?): Instance?
	local current: Instance? = floorPart
	while current do
		if CollectionService:HasTag(current, TAG_NAME) then
			if current:IsA("BasePart") then
				return current
			end
			if current:IsA("Model") and current.PrimaryPart then
				return current
			end
			return nil
		end
		current = current.Parent
	end
	return nil
end

local function getPlatformCFrame(platform: Instance): CFrame?
	if platform:IsA("BasePart") then
		return platform.CFrame
	end
	if platform:IsA("Model") and platform.PrimaryPart then
		return platform.PrimaryPart.CFrame
	end
	return nil
end

local function getSupportingPart(currentHumanoid: Humanoid, currentRoot: BasePart): BasePart?
	if currentHumanoid.FloorMaterial == Enum.Material.Air then
		return nil
	end

	local params = floorRaycastParams
	if not params then
		return nil
	end

	local distance = math.max(currentHumanoid.HipHeight + 3, 5)
	local result = workspace:Raycast(
		currentRoot.Position,
		Vector3.new(0, -distance, 0),
		params
	)
	return if result then result.Instance else nil
end

local function carryCharacter()
	local currentHumanoid = humanoid
	local currentRoot = root
	if not currentHumanoid or not currentRoot or not currentRoot.Parent
		or currentHumanoid.Health <= 0
		or currentHumanoid.FloorMaterial == Enum.Material.Air
		or currentHumanoid.Sit
		or currentHumanoid.PlatformStand
	then
		clearPlatform()
		return
	end

	local platform = getPlatformFromFloor(
		getSupportingPart(currentHumanoid, currentRoot)
	)
	if not platform then
		clearPlatform()
		return
	end

	local platformCFrame = getPlatformCFrame(platform)
	if not platformCFrame then
		clearPlatform()
		return
	end

	if ridingPlatform ~= platform or not previousPlatformCFrame then
		ridingPlatform = platform
		previousPlatformCFrame = platformCFrame
		playerWaveState.PlatformRiding = true
		return
	end

	local previous = previousPlatformCFrame
	previousPlatformCFrame = platformCFrame
	local delta = platformCFrame * previous:Inverse()

	-- Applying the complete transform preserves the character's relative
	-- position and makes platform yaw, pitch, and roll visible to the camera.
	currentRoot.CFrame = delta * currentRoot.CFrame
end

player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(function()
	if characterConnection then
		characterConnection:Disconnect()
		characterConnection = nil
	end
	humanoid = nil
	root = nil
	floorRaycastParams = nil
	clearPlatform()
end)

if player.Character then
	task.spawn(bindCharacter, player.Character)
end

RunService:BindToRenderStep("WaterPlatformRiderController", RENDER_PRIORITY, carryCharacter)
