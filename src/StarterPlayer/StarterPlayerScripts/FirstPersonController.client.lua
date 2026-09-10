--!native
--!strict

-- StarterPlayerScripts > FirstPersonController
--
-- Responsibilities ONLY:
--   * Force first person.
--   * M releases / recaptures the mouse.
--   * Keep the local body visible.
--   * Hide the local head and ALL accessories.
--   * Make the character's head/neck follow the camera.
--
-- It does NOT know that water exists.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local MAX_HEAD_PITCH = math.rad(70)
local MAX_HEAD_YAW = math.rad(80)
local HEAD_FOLLOW_SPEED = 15
local CAMERA_HEIGHT_OFFSET = 0.5

local RENDER_STEP_NAME = "FirstPersonCharacterController"

local character: Model? = nil
local head: BasePart? = nil
local upperTorso: BasePart? = nil
local neck: Motor6D? = nil
local originalNeckC0: CFrame? = nil

local currentHeadPitch = 0
local currentHeadYaw = 0

local mouseReleased = false

-- Preserve whatever another local system had already put on body parts.
local originalLocalTransparency: { [BasePart]: number } = {}

local characterDescendantAddedConnection: RBXScriptConnection? = nil


local function lerpNumber(
	a: number,
	b: number,
	alpha: number
): number
	return a + (b - a) * alpha
end


local function enforceFirstPerson()
	if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
end


local function applyMouseState()
	local settingsOpen = player:GetAttribute("SettingsOpen") == true
	local releasedOverride = player:GetAttribute("MouseReleased")
	local shouldRelease = if typeof(releasedOverride) == "boolean"
		then releasedOverride
		else mouseReleased

	if settingsOpen or shouldRelease then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end

local function applyCameraOffset()
	local camera =
		Workspace.CurrentCamera

	if not camera then
		return
	end

	camera.CFrame =
		camera.CFrame
		+ Vector3.new(
			0,
			CAMERA_HEIGHT_OFFSET,
			0
		)
end

local function isAccessoryPart(
	part: BasePart
): boolean
	return part:FindFirstAncestorOfClass("Accessory") ~= nil
end


local function applyVisibilityToPart(
	part: BasePart
)
	if originalLocalTransparency[part] == nil then
		originalLocalTransparency[part] =
			part.LocalTransparencyModifier
	end

	if part == head or isAccessoryPart(part) then
		part.LocalTransparencyModifier = 1
	else
		part.LocalTransparencyModifier =
			originalLocalTransparency[part] or 0
	end
end


local function applyCharacterVisibility()
	local currentCharacter = character

	if not currentCharacter then
		return
	end

	for _, descendant in currentCharacter:GetDescendants() do
		if descendant:IsA("BasePart") then
			applyVisibilityToPart(descendant)
		end
	end
end


local function restorePreviousCharacter()
	if neck and originalNeckC0 then
		neck.C0 = originalNeckC0
	end

	for part, transparency in originalLocalTransparency do
		if part.Parent then
			part.LocalTransparencyModifier = transparency
		end
	end

	table.clear(originalLocalTransparency)

	if characterDescendantAddedConnection then
		characterDescendantAddedConnection:Disconnect()
		characterDescendantAddedConnection = nil
	end
end


local function setupCharacter(
	newCharacter: Model
)
	restorePreviousCharacter()

	character = newCharacter

	local foundHead =
		newCharacter:WaitForChild("Head")

	if foundHead:IsA("BasePart") then
		head = foundHead
	else
		head = nil
	end

	local torsoCandidate =
		newCharacter:FindFirstChild("UpperTorso")
		or newCharacter:FindFirstChild("Torso")

	if torsoCandidate and torsoCandidate:IsA("BasePart") then
		upperTorso = torsoCandidate
	else
		upperTorso = nil
	end

	neck = nil
	originalNeckC0 = nil

	if upperTorso then
		local possibleNeck =
			upperTorso:FindFirstChild("Neck")

		if possibleNeck and possibleNeck:IsA("Motor6D") then
			neck = possibleNeck
			originalNeckC0 = possibleNeck.C0
		end
	end

	currentHeadPitch = 0
	currentHeadYaw = 0

	-- Cache + apply once.
	applyCharacterVisibility()

	-- Then only process newly-added character geometry/accessories instead
	-- of rescanning the entire character every render frame.
	characterDescendantAddedConnection =
		newCharacter.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				applyVisibilityToPart(descendant)
			end
		end)

	enforceFirstPerson()
	applyMouseState()
end


local function updateHeadLook(
	dt: number
)
	local camera =
		Workspace.CurrentCamera

	local currentUpperTorso =
		upperTorso

	local currentNeck =
		neck

	local baseNeckC0 =
		originalNeckC0

	if
		not camera
		or not currentUpperTorso
		or not currentNeck
		or not baseNeckC0
	then
		return
	end

	local localLook =
		currentUpperTorso.CFrame:VectorToObjectSpace(
			camera.CFrame.LookVector
		)

	local targetPitch =
		math.asin(
			math.clamp(
				localLook.Y,
				-1,
				1
			)
		)

	local targetYaw =
		math.atan2(
			-localLook.X,
			-localLook.Z
		)

	targetPitch =
		math.clamp(
			targetPitch,
			-MAX_HEAD_PITCH,
			MAX_HEAD_PITCH
		)

	targetYaw =
		math.clamp(
			targetYaw,
			-MAX_HEAD_YAW,
			MAX_HEAD_YAW
		)

	local alpha =
		1
	- math.exp(
		-HEAD_FOLLOW_SPEED * dt
	)

	currentHeadPitch =
		lerpNumber(
			currentHeadPitch,
			targetPitch,
			alpha
		)

	currentHeadYaw =
		lerpNumber(
			currentHeadYaw,
			targetYaw,
			alpha
		)

	currentNeck.C0 =
		baseNeckC0
		* CFrame.Angles(
			currentHeadPitch,
			currentHeadYaw,
			0
		)
end


UserInputService.InputBegan:Connect(function(
	input: InputObject,
	gameProcessed: boolean
)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.M then
		mouseReleased = not mouseReleased
		player:SetAttribute("MouseReleased", mouseReleased)
		applyMouseState()
	end
end)


if player.Character then
	setupCharacter(player.Character)
end

player.CharacterAdded:Connect(
	setupCharacter
)

player.CharacterRemoving:Connect(function(
	removingCharacter: Model
)
	if removingCharacter ~= character then
		return
	end

	restorePreviousCharacter()

	character = nil
	head = nil
	upperTorso = nil
	neck = nil
	originalNeckC0 = nil
end)

RunService:BindToRenderStep(
	RENDER_STEP_NAME,
	Enum.RenderPriority.Camera.Value + 1,
	function(dt: number)
		enforceFirstPerson()
		applyMouseState()

		applyCharacterVisibility()

		-- Raise the first-person viewpoint without changing
		-- the camera's rotation / LookVector.
		applyCameraOffset()

		updateHeadLook(dt)
	end
)
