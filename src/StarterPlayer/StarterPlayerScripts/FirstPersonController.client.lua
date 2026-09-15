--!native
--!strict

-- StarterPlayerScripts > TrueFirstPersonController
--
-- IMPORTANT CAMERA RULE:
-- The camera is the authority.
-- The skeleton follows the camera.
-- The camera must NEVER be positioned from bones that the same camera
-- is currently driving through IK / neck rotation.
--
-- That avoids this feedback loop:
--
-- Camera -> IK/head -> Head.Position/CFrame -> Camera -> IK/head -> ...
--
-- Standing:
--   * Roblox CameraModule owns the camera normally.
--   * Humanoid.CameraOffset nudges the viewpoint slightly toward the eyes.
--   * Neck/head owns standing pitch and most standing yaw.
--   * UpperTorso/Waist only adds a small horizontal yaw assist.
--   * Standing look never asks LowerTorso / hips / legs / feet to move.
--
-- Seated:
--   * Camera becomes Scriptable.
--   * Its POSITION follows the UpperTorso-side Neck base so seated lean
--     carries the camera with the character while neck rotation stays isolated.
--   * Its ROTATION is driven from our own yaw/pitch accumulator.
--   * SeatedFreeLook=true (default) allows +/-170 degrees and looking behind.
--   * SeatedFreeLook=false restricts seated yaw to +/-90 degrees.
--   * Both modes use the same camera/body/hand architecture.
--   * Camera yaw/pitch feeds a constraint-aware head -> upper-torso chain.
--   * The head leads; the UpperTorso begins helping gradually before the neck limit.
--   * Seated body IK uses LowerTorso -> UpperTorso only, keeping hips/root seat-stable.
--   * Active hand IK automatically reduces available torso twist as targets approach
--     arm reach, so steering/held-object constraints take priority over looking around.
--   * A small amount of torso pitch follows camera pitch for natural leaning.
--   * The camera may continue farther than the physical neck/body can reproduce.
--   * SeatedFreeLook is a player preference; free-look is ON by default.
--
-- Steering-arm IK remains a separate system.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- SESSION / MOUSE
----------------------------------------------------------------

player:SetAttribute("SettingsOpen", false)
player:SetAttribute("MouseReleased", false)

local SPARK_INITIAL_LOAD_COMPLETE_ATTRIBUTE = "SparkInitialLoadComplete"

local LOADING_ORIGINAL_TRANSPARENCY_ATTRIBUTE = "SparkLoadingOriginalLocalTransparency"

local CAMERA_MODE_KEY = Enum.KeyCode.Y
local DEFAULT_THIRD_PERSON_CAMERA_MODE = 1
local MAX_THIRD_PERSON_CAMERA_MODE = 3
local CAMERA_MODE_TOGGLE_SOUND_ID = "rbxassetid://128614591007939"

-- This preference survives first-person entry/exit and character respawns.
-- First person derives its effective input state without replacing it.
if player:GetAttribute("ThirdPersonCameraMode") == nil then
	player:SetAttribute("ThirdPersonCameraMode", DEFAULT_THIRD_PERSON_CAMERA_MODE)
end

-- Seated camera preference:
-- true  = free look, +/-170 degrees, can look behind
-- false = restricted steering view, +/-90 degrees
--
-- Free look is the default mode.
if player:GetAttribute("SeatedFreeLook") == nil then
	player:SetAttribute("SeatedFreeLook", true)
end

-- Start in Roblox-normal mouse state. True first person will lock the
-- mouse only after the zoom detector confirms minimum zoom.
UserInputService.MouseBehavior = Enum.MouseBehavior.Default
UserInputService.MouseIconEnabled = true

----------------------------------------------------------------
-- STANDING CAMERA
----------------------------------------------------------------

-- Roblox already puts first person near the head.
-- This is only a small stable nudge toward the eye/front-of-face area.
--
-- CameraOffset is deliberately used instead of writing camera.CFrame
-- from Head.Position every frame. That breaks the camera <-> IK feedback loop.
local STANDING_CAMERA_OFFSET = Vector3.new(0, 0.10, -0.20)

----------------------------------------------------------------
-- FIRST PERSON <-> THIRD PERSON ZOOM TRANSITION
----------------------------------------------------------------

-- IMPORTANT:
-- We deliberately keep Player.CameraMode on Classic.
--
-- LockFirstPerson would trap the player at minimum zoom and make it
-- impossible for Roblox's CameraModule to perform the normal zoom-out.
--
-- Instead, Roblox owns the zoom distance. When CameraModule reaches
-- true first-person distance, this controller activates the custom
-- first-person body/head/IK behaviour. When the player zooms back out,
-- the controller yields to Roblox's normal third-person camera.
local FIRST_PERSON_MIN_ZOOM_DISTANCE = 0.5

-- Only used if this place was previously configured with a tiny
-- CameraMaxZoomDistance that would otherwise prevent zooming out at all.
local THIRD_PERSON_FALLBACK_MAX_ZOOM_DISTANCE = 20

-- Hysteresis prevents rapid toggling right on the first-person boundary.
local FIRST_PERSON_ENTER_DISTANCE = 0.75
local FIRST_PERSON_EXIT_DISTANCE = 1.05

-- Head/accessories disappear quickly when entering first person, but
-- return more gently when zooming back into third person.
local FIRST_PERSON_HIDE_SPEED = 18
local THIRD_PERSON_SHOW_SPEED = 5

----------------------------------------------------------------
-- HEAD / NECK
----------------------------------------------------------------

local MAX_HEAD_PITCH = math.rad(70)
local MAX_HEAD_YAW = math.rad(80)

local MAX_SEATED_HEAD_UP_PITCH = math.rad(60)
local MAX_SEATED_HEAD_DOWN_PITCH = math.rad(45)
local MAX_SEATED_HEAD_YAW = math.rad(90)

local HEAD_FOLLOW_SPEED = 15

----------------------------------------------------------------
-- SEATED CAMERA
----------------------------------------------------------------

-- Two seated look modes share the exact same TrueFirstPerson controller.
--
-- Default:
--   SeatedFreeLook = true
--   +/-170 degrees so the player can look behind while seated.
--
-- Optional restricted mode:
--   SeatedFreeLook = false
--   +/-90 degrees for a tighter steering-oriented view.
local MAX_SEATED_FREE_LOOK_YAW = math.rad(170)
local MAX_SEATED_RESTRICTED_YAW = math.rad(90)

local function getMaxSeatedCameraYaw(): number
	if player:GetAttribute("SeatedFreeLook") == false then
		return MAX_SEATED_RESTRICTED_YAW
	end

	return MAX_SEATED_FREE_LOOK_YAW
end

local MAX_SEATED_CAMERA_UP_PITCH = math.rad(70)
local MAX_SEATED_CAMERA_DOWN_PITCH = math.rad(55)

local SEATED_MOUSE_SENSITIVITY = 0.0025

----------------------------------------------------------------
-- SEATED CAMERA POSITION
----------------------------------------------------------------

-- Keep the seated camera physically inside the head rather than
-- preserving a fixed HumanoidRootPart-relative point in front of the torso.
--
-- The anchor is built from the UpperTorso-side Neck joint every frame.
-- That means normal seated forward/back lean moves the camera with the body,
-- but neck pitch/yaw itself cannot drag the camera into a feedback loop.
local SEATED_EYE_HEIGHT_FACTOR = 0.55
local SEATED_EYE_FORWARD_FACTOR = 0.05

-- As the seated view pitches downward, the real head rotates around the
-- neck joint: the eyes move slightly FORWARD and DOWN.
--
-- Recreate that motion analytically from seatedCameraPitch instead of
-- parenting the camera to the rotating Head. This keeps the camera stable
-- while making the viewpoint follow the physical head arc.
local SEATED_DOWN_LOOK_START = math.rad(5)
local SEATED_DOWN_LOOK_MAX_FORWARD_FACTOR = 0.32
local SEATED_DOWN_LOOK_MAX_LOWER_FACTOR = 0.18

----------------------------------------------------------------
-- STANDING TORSO LOOK IK
----------------------------------------------------------------

local STANDING_TORSO_IK_WEIGHT = 0.30
local STANDING_TORSO_IK_PRIORITY = 0

-- Standing UpperTorso only helps LEFT/RIGHT.
-- Vertical look belongs to the neck/head so the neck base does not
-- physically move away from Roblox's standing first-person camera.
local STANDING_TORSO_YAW_SHARE = 0.12
local MAX_STANDING_TORSO_YAW = math.rad(8)

-- Vertical standing look is intentionally asymmetric:
-- looking DOWN = head/neck only
-- looking UP   = head/neck + a small chest/spine assist
local STANDING_TORSO_UP_PITCH_SHARE = 0.12
local MAX_STANDING_TORSO_UP_PITCH = math.rad(7)

local TORSO_TARGET_DISTANCE = 10

----------------------------------------------------------------
-- SEATED HEAD -> TORSO CHAIN
----------------------------------------------------------------

-- Shared seated body model:
--   * Camera limit is selected by SeatedFreeLook (170 or 90 degrees).
--   * Head does most of the look.
--   * Shoulders begin helping before the neck reaches its limit.
--   * UpperTorso yaw remains deliberately small so hand IK can keep both
--     hands attached to a steering wheel / nearby held object.
local TORSO_ASSIST_START_YAW = math.rad(45)
local TORSO_IK_FULL_WEIGHT_YAW = math.rad(80)
local MAX_SEATED_TORSO_YAW = math.rad(12)

-- A small forward/downward shoulder lean is added as the player approaches
-- a sideways look. This rotates the UpperTorso around the waist rather than
-- translating the whole character, bringing the shoulders slightly toward
-- the wheel instead of pulling them away from the arm targets.
local YAW_LEAN_START = math.rad(40)
local MAX_YAW_FORWARD_LEAN = math.rad(6)

-- Vertical camera movement still gets a little torso participation.
local TORSO_PITCH_SHARE = 0.16
local MAX_SEATED_TORSO_UP_PITCH = math.rad(5)
local MAX_SEATED_TORSO_DOWN_PITCH = math.rad(10)
local TORSO_PITCH_ASSIST_START = math.rad(8)
local TORSO_PITCH_FULL_WEIGHT = math.rad(40)

local SEATED_BODY_IK_WEIGHT = 0.999
local TORSO_FOLLOW_SPEED = 9

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

local RENDER_STEP_NAME = "TrueFirstPersonController"

local configuredThirdPersonCameraMode = player:GetAttribute("ThirdPersonCameraMode")

local selectedThirdPersonCameraMode = if typeof(configuredThirdPersonCameraMode) == "number"
	then math.clamp(math.floor(configuredThirdPersonCameraMode), 1, MAX_THIRD_PERSON_CAMERA_MODE)
	else DEFAULT_THIRD_PERSON_CAMERA_MODE

player:SetAttribute("ThirdPersonCameraMode", selectedThirdPersonCameraMode)

local character: Model? = nil
local humanoid: Humanoid? = nil

local abilityManagerTurning: Instance? = nil

local cameraModeToggleSound = Instance.new("Sound")
cameraModeToggleSound.Name = "CameraModeToggleSound"
cameraModeToggleSound.SoundId = CAMERA_MODE_TOGGLE_SOUND_ID
cameraModeToggleSound.Parent = SoundService

local head: BasePart? = nil
local upperTorso: BasePart? = nil
local lowerTorso: BasePart? = nil
local rootPart: BasePart? = nil

local neck: Motor6D? = nil
local originalNeckC0: CFrame? = nil

local originalCameraOffset: Vector3? = nil

-- Standing:
-- LowerTorso -> UpperTorso
local standingTorsoIK: IKControl? = nil

-- Seated:
-- LowerTorso -> UpperTorso only. Hips/root remain seat-stable.
local seatedBodyTurnIK: IKControl? = nil

local torsoIKTarget: BasePart? = nil

local currentHeadPitch = 0
local currentHeadYaw = 0

-- Desired seated upper-body pose.
local currentTorsoYaw = 0
local currentTorsoPitch = 0

-- Continuous seated camera state.
local seatedCameraYaw = 0
local seatedCameraPitch = 0

local wasSeated = false
local mouseReleased = false

-- Hybrid zoom state.
local firstPersonActive = false

-- When the seated Scriptable camera is released by mouse-wheel zoom-out,
-- wait until Roblox CameraModule has actually moved away from the
-- first-person boundary before allowing first person to engage again.
local waitingForSeatedZoomOut = false

-- 0 = head/accessories fully visible.
-- 1 = head/accessories fully hidden.
local firstPersonVisibilityAlpha = 0

----------------------------------------------------------------
-- VISIBILITY
----------------------------------------------------------------

local originalLocalTransparency: { [BasePart]: number } = {}
local characterDescendantAddedConnection: RBXScriptConnection? = nil

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

local function lerpNumber(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

local function expAlpha(speed: number, dt: number): number
	return 1 - math.exp(-speed * dt)
end

local function ensureZoomableCameraMode()
	-- Classic is required so Roblox CameraModule can zoom between
	-- first person and normal third person.
	if player.CameraMode ~= Enum.CameraMode.Classic then
		player.CameraMode = Enum.CameraMode.Classic
	end

	-- Make sure the player can always physically reach true first person.
	if player.CameraMinZoomDistance > FIRST_PERSON_MIN_ZOOM_DISTANCE then
		player.CameraMinZoomDistance = FIRST_PERSON_MIN_ZOOM_DISTANCE
	end

	if player.CameraMaxZoomDistance <= FIRST_PERSON_EXIT_DISTANCE then
		player.CameraMaxZoomDistance = THIRD_PERSON_FALLBACK_MAX_ZOOM_DISTANCE
	end
end

local function playCameraModeToggleSound()
	cameraModeToggleSound:Stop()
	cameraModeToggleSound.TimePosition = 0
	cameraModeToggleSound:Play()
end

local function getAbilityManagerTurning(currentCharacter: Model): Instance?
	local abilityManagerActor = currentCharacter:WaitForChild("AbilityManagerActor", 10)

	if not abilityManagerActor then
		warn("[FirstPersonController] Character.AbilityManagerActor was not found")
		return nil
	end

	local abilities = abilityManagerActor:WaitForChild("Abilities", 10)

	if not abilities then
		warn("[FirstPersonController] Character.AbilityManagerActor.Abilities was not found")
		return nil
	end

	local turning = abilities:WaitForChild("Turning", 10)

	if not turning then
		warn("[FirstPersonController] Character.AbilityManagerActor.Abilities.Turning was not found")
		return nil
	end

	return turning
end

local function locomotionOwnsOrientation(): boolean
	local currentHumanoid = humanoid
	local currentCharacter = character

	if currentHumanoid and currentHumanoid.SeatPart ~= nil then
		return true
	end

	return currentCharacter ~= nil and currentCharacter:GetAttribute("IsSwimming") == true
end

local function updateAbilityManagerTurning()
	local turning = abilityManagerTurning

	if not turning or not turning.Parent then
		return
	end

	local useLookDirectionInput = (firstPersonActive or selectedThirdPersonCameraMode == 3)
		and not locomotionOwnsOrientation()

	if turning:GetAttribute("UseLookDirectionInput") ~= useLookDirectionInput then
		turning:SetAttribute("UseLookDirectionInput", useLookDirectionInput)
	end
end

local function setFirstPersonActive(active: boolean)
	if firstPersonActive == active then
		return
	end

	firstPersonActive = active

	player:SetAttribute("TrueFirstPersonActive", active)

	updateAbilityManagerTurning()

	if not active then
		-- Release the FPS lock immediately. After this point third-person
		-- CameraModule is free to manage RMB orbit / mouse capture normally.
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default

		UserInputService.MouseIconEnabled = true
	end
end

local function updateFirstPersonZoomState()
	local camera = Workspace.CurrentCamera

	if not camera then
		return
	end

	-- While seated first person owns a Scriptable camera. In that state
	-- Camera.Focus is not a useful zoom-distance signal, so keep the
	-- current state until Roblox CameraModule owns the camera again.
	if camera.CameraType == Enum.CameraType.Scriptable then
		return
	end

	local zoomDistance = (camera.CFrame.Position - camera.Focus.Position).Magnitude

	if waitingForSeatedZoomOut then
		if zoomDistance >= FIRST_PERSON_EXIT_DISTANCE then
			waitingForSeatedZoomOut = false
		else
			return
		end
	end

	if firstPersonActive then
		if zoomDistance >= FIRST_PERSON_EXIT_DISTANCE then
			setFirstPersonActive(false)
		end
	else
		if zoomDistance <= FIRST_PERSON_ENTER_DISTANCE then
			setFirstPersonActive(true)
		end
	end
end

local function isCurrentlySeated(): boolean
	local currentHumanoid = humanoid

	return currentHumanoid ~= nil and currentHumanoid.SeatPart ~= nil
end

local function getFlatRootReference(): CFrame?
	local currentRoot = rootPart

	if not currentRoot then
		return nil
	end

	local look = currentRoot.CFrame.LookVector

	local flatLook = Vector3.new(look.X, 0, look.Z)

	if flatLook.Magnitude < 0.001 then
		return nil
	end

	return CFrame.lookAt(Vector3.zero, flatLook.Unit, Vector3.yAxis)
end

local function smoothstep01(value: number): number
	local x = math.clamp(value, 0, 1)
	return x * x * (3 - 2 * x)
end

local function getIKTargetWorldPosition(target: Instance?): Vector3?
	if not target then
		return nil
	end

	if target:IsA("Attachment") then
		return target.WorldPosition
	end

	if target:IsA("BasePart") then
		return target.Position
	end

	return nil
end

local function getShoulderWorldPosition(side: string): Vector3?
	local currentUpperTorso = upperTorso
	local currentCharacter = character

	if not currentUpperTorso or not currentCharacter then
		return nil
	end

	local shoulderName = if side == "Left" then "LeftShoulder" else "RightShoulder"

	local shoulder = currentUpperTorso:FindFirstChild(shoulderName)

	if shoulder and shoulder:IsA("Motor6D") then
		return (currentUpperTorso.CFrame * shoulder.C0).Position
	end

	local upperArm = currentCharacter:FindFirstChild(side .. "UpperArm")

	if upperArm and upperArm:IsA("BasePart") then
		return upperArm.Position
	end

	return nil
end

local function getApproximateArmReach(side: string): number?
	local currentCharacter = character

	if not currentCharacter then
		return nil
	end

	local upperArm = currentCharacter:FindFirstChild(side .. "UpperArm")

	local lowerArm = currentCharacter:FindFirstChild(side .. "LowerArm")

	local hand = currentCharacter:FindFirstChild(side .. "Hand")

	if
		not upperArm
		or not upperArm:IsA("BasePart")
		or not lowerArm
		or not lowerArm:IsA("BasePart")
		or not hand
		or not hand:IsA("BasePart")
	then
		return nil
	end

	-- R15 arm segments use Y as their longitudinal dimension.
	-- Hand contributes half its height because the IK end effector sits
	-- around the hand centre rather than at the fingertips.
	return upperArm.Size.Y + lowerArm.Size.Y + hand.Size.Y * 0.5
end

-- 0 = upper body is free to rotate.
-- 1 = hand targets are close to comfortable maximum reach, so the
--     head/camera should take priority and torso twist should yield.
--
-- This intentionally detects ANY enabled hand IK, not only steering-wheel
-- IK, so the same behaviour works later while holding or operating objects.
local function getUpperBodyConstraintAlpha(): number
	local currentHumanoid = humanoid

	if not currentHumanoid then
		return 0
	end

	local constraintAlpha = 0

	for _, child in currentHumanoid:GetChildren() do
		if child:IsA("IKControl") and child.Enabled and child.Weight > 0.001 then
			local endEffector = child.EndEffector

			if endEffector then
				local side: string? = nil

				if endEffector.Name == "LeftHand" then
					side = "Left"
				elseif endEffector.Name == "RightHand" then
					side = "Right"
				end

				if side then
					local targetPosition = getIKTargetWorldPosition(child.Target)

					local shoulderPosition = getShoulderWorldPosition(side)

					local armReach = getApproximateArmReach(side)

					if targetPosition and shoulderPosition and armReach and armReach > 0.001 then
						local distance = (targetPosition - shoulderPosition).Magnitude

						local reachRatio = distance / armReach

						local reachPressure = math.clamp(
							(reachRatio - HAND_REACH_SOFT_START) / (HAND_REACH_HARD_START - HAND_REACH_SOFT_START),
							0,
							1
						)

						-- Simply having a hand hard-targeted means the torso
						-- should already be conservative. Reach pressure then
						-- increases that constraint toward 1.
						local handConstraint = ACTIVE_HAND_BASE_CONSTRAINT
							+ (1 - ACTIVE_HAND_BASE_CONSTRAINT) * reachPressure

						constraintAlpha = math.max(constraintAlpha, handConstraint)
					else
						-- An enabled hand IK exists but the rig could not be
						-- measured. Still use the safe constrained posture.
						constraintAlpha = math.max(constraintAlpha, ACTIVE_HAND_BASE_CONSTRAINT)
					end
				end
			end
		end
	end

	return constraintAlpha
end

-- Seated camera POSITION only.
--
-- This follows the animated UpperTorso / Neck BASE position so leaning
-- forward or backward carries the camera with the character.
--
-- It deliberately does NOT use:
--   * Head.CFrame
--   * current Neck rotation
--   * an Attachment parented to the rotating Head
--
-- Therefore head pitch/yaw cannot feed back into the camera position.
local function getSeatedEyePosition(): Vector3?
	local currentUpperTorso = upperTorso
	local currentHead = head
	local baseNeckC0 = originalNeckC0

	if not currentUpperTorso or not currentHead or not baseNeckC0 then
		return nil
	end

	-- UpperTorso-side neck joint.
	local neckBaseWorld = currentUpperTorso.CFrame * baseNeckC0

	-- Neutral eye position: inside the head, slightly above the neck.
	local position = neckBaseWorld.Position
		+ currentUpperTorso.CFrame.UpVector * (currentHead.Size.Y * SEATED_EYE_HEIGHT_FACTOR)

	position += currentUpperTorso.CFrame.LookVector * (currentHead.Size.Z * SEATED_EYE_FORWARD_FACTOR)

	------------------------------------------------------------
	-- DOWNWARD HEAD ARC
	--
	-- When the view pitches down, the skull rotates around the neck.
	-- The eyes therefore travel slightly forward and lower.
	--
	-- We derive this only from our seated pitch state, so it cannot
	-- create camera <-> Head.CFrame feedback.
	------------------------------------------------------------

	local downwardPitch = math.max(0, -seatedCameraPitch - SEATED_DOWN_LOOK_START)

	local availablePitch = math.max(0.001, MAX_SEATED_CAMERA_DOWN_PITCH - SEATED_DOWN_LOOK_START)

	local downAlpha = math.clamp(downwardPitch / availablePitch, 0, 1)

	-- Smoothstep: little movement near level, increasingly noticeable
	-- as the player looks toward their feet.
	downAlpha = downAlpha * downAlpha * (3 - 2 * downAlpha)

	if downAlpha > 0 then
		position += currentUpperTorso.CFrame.LookVector * (currentHead.Size.Z * SEATED_DOWN_LOOK_MAX_FORWARD_FACTOR * downAlpha)

		position -= currentUpperTorso.CFrame.UpVector * (currentHead.Size.Y * SEATED_DOWN_LOOK_MAX_LOWER_FACTOR * downAlpha)
	end

	return position
end

----------------------------------------------------------------
-- MOUSE
----------------------------------------------------------------

local function applyMouseState()
	local settingsOpen = player:GetAttribute("SettingsOpen") == true

	local releasedOverride = player:GetAttribute("MouseReleased")

	local shouldRelease = if typeof(releasedOverride) == "boolean" then releasedOverride else mouseReleased

	if not firstPersonActive then
		if settingsOpen or shouldRelease then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default

			UserInputService.MouseIconEnabled = true

			return
		end

		if selectedThirdPersonCameraMode >= 2 then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

			UserInputService.MouseIconEnabled = false
		end

		-- Mode 1 deliberately stops writing MouseBehavior so Roblox's
		-- third-person CameraModule retains normal RMB orbit behavior.
		return
	end

	if settingsOpen or shouldRelease then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default

		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

		UserInputService.MouseIconEnabled = false
	end
end

local function setThirdPersonCameraMode(mode: number, playSound: boolean)
	selectedThirdPersonCameraMode = math.clamp(math.floor(mode), 1, MAX_THIRD_PERSON_CAMERA_MODE)

	player:SetAttribute("ThirdPersonCameraMode", selectedThirdPersonCameraMode)

	-- Changing the stored preference recaptures the mouse. Entering first
	-- person never changes this preference, so zoom-out restores it.
	mouseReleased = false
	player:SetAttribute("MouseReleased", false)

	if not firstPersonActive and selectedThirdPersonCameraMode == 1 then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default

		UserInputService.MouseIconEnabled = true
	end

	updateAbilityManagerTurning()
	applyMouseState()

	if playSound then
		playCameraModeToggleSound()
	end
end

----------------------------------------------------------------
-- VISIBILITY
----------------------------------------------------------------

local function isAccessoryPart(part: BasePart): boolean
	return part:FindFirstAncestorOfClass("Accessory") ~= nil
end

local function applyVisibilityToPart(part: BasePart)
	if originalLocalTransparency[part] == nil then
		local loadingOriginalTransparency = part:GetAttribute(LOADING_ORIGINAL_TRANSPARENCY_ATTRIBUTE)

		originalLocalTransparency[part] = if typeof(loadingOriginalTransparency) == "number"
			then loadingOriginalTransparency
			else part.LocalTransparencyModifier
	end

	local originalTransparency = originalLocalTransparency[part] or 0

	if player:GetAttribute(SPARK_INITIAL_LOAD_COMPLETE_ATTRIBUTE) == false then
		part.LocalTransparencyModifier = 1
		return
	end

	if part == head or isAccessoryPart(part) then
		part.LocalTransparencyModifier = lerpNumber(originalTransparency, 1, firstPersonVisibilityAlpha)
	else
		-- Roblox's own first-person transparency controller normally hides
		-- the entire local character. Running after CameraModule lets this
		-- custom controller restore the body while only hiding the head and
		-- accessories.
		part.LocalTransparencyModifier = originalTransparency
	end
end

local function updateCharacterVisibility(dt: number)
	local currentCharacter = character

	if not currentCharacter then
		return
	end

	local targetAlpha = if firstPersonActive then 1 else 0

	local visibilitySpeed = if firstPersonActive then FIRST_PERSON_HIDE_SPEED else THIRD_PERSON_SHOW_SPEED

	firstPersonVisibilityAlpha = lerpNumber(firstPersonVisibilityAlpha, targetAlpha, expAlpha(visibilitySpeed, dt))

	-- Snap the tiny exponential tail so accessories eventually reach
	-- their exact original transparency.
	if math.abs(firstPersonVisibilityAlpha - targetAlpha) < 0.001 then
		firstPersonVisibilityAlpha = targetAlpha
	end

	for _, descendant in currentCharacter:GetDescendants() do
		if descendant:IsA("BasePart") then
			applyVisibilityToPart(descendant)
		end
	end
end

----------------------------------------------------------------
-- CAMERA OWNERSHIP
----------------------------------------------------------------

local function restoreDefaultCamera()
	local camera = Workspace.CurrentCamera

	if camera then
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		end

		if humanoid then
			camera.CameraSubject = humanoid
		end
	end

	local currentHumanoid = humanoid

	if currentHumanoid then
		if firstPersonActive then
			currentHumanoid.CameraOffset = STANDING_CAMERA_OFFSET
		else
			currentHumanoid.CameraOffset = originalCameraOffset or Vector3.zero
		end
	end
end

local function updateCameraOffsetForMode()
	local currentHumanoid = humanoid

	if not currentHumanoid then
		return
	end

	if firstPersonActive then
		currentHumanoid.CameraOffset = STANDING_CAMERA_OFFSET
	else
		currentHumanoid.CameraOffset = originalCameraOffset or Vector3.zero
	end
end

----------------------------------------------------------------
-- IK CREATION / CLEANUP
----------------------------------------------------------------

local function destroyLookIK()
	if standingTorsoIK then
		standingTorsoIK:Destroy()
		standingTorsoIK = nil
	end

	if seatedBodyTurnIK then
		seatedBodyTurnIK:Destroy()
		seatedBodyTurnIK = nil
	end

	if torsoIKTarget then
		torsoIKTarget:Destroy()
		torsoIKTarget = nil
	end
end

local function createLookIK()
	destroyLookIK()

	local currentHumanoid = humanoid
	local currentUpperTorso = upperTorso
	local currentLowerTorso = lowerTorso
	local currentRoot = rootPart

	if not currentHumanoid or not currentUpperTorso or not currentLowerTorso or not currentRoot then
		return
	end

	------------------------------------------------------------
	-- LOCAL INVISIBLE TARGET
	------------------------------------------------------------

	local target = Instance.new("Part")
	target.Name = "FirstPersonTorsoLookTarget"

	target.Size = Vector3.new(0.1, 0.1, 0.1)

	target.Anchored = true
	target.CanCollide = false
	target.CanTouch = false
	target.CanQuery = false
	target.CastShadow = false
	target.Transparency = 1

	target.Parent = Workspace

	torsoIKTarget = target

	------------------------------------------------------------
	-- STANDING TORSO LOOK
	------------------------------------------------------------

	local standingIK = Instance.new("IKControl")

	standingIK.Name = "StandingUpperTorsoLookIK"

	standingIK.Type = Enum.IKControlType.LookAt

	standingIK.ChainRoot = currentLowerTorso

	standingIK.EndEffector = currentUpperTorso

	standingIK.Target = target

	standingIK.Weight = STANDING_TORSO_IK_WEIGHT

	standingIK.Priority = STANDING_TORSO_IK_PRIORITY
	standingIK.Enabled = true

	standingIK.Parent = currentHumanoid

	standingTorsoIK = standingIK

	------------------------------------------------------------
	-- SEATED UPPER-BODY LOOK ASSIST
	--
	-- LowerTorso -> UpperTorso only. This keeps the hips/root planted in
	-- the seat and lets the waist/shoulders provide a modest look assist.
	------------------------------------------------------------

	local seatedIK = Instance.new("IKControl")

	seatedIK.Name = "SeatedBodyTurnIK"

	seatedIK.Type = Enum.IKControlType.LookAt

	seatedIK.ChainRoot = currentLowerTorso

	seatedIK.EndEffector = currentUpperTorso

	seatedIK.Target = target

	seatedIK.Weight = 0
	seatedIK.Priority = 1
	seatedIK.Enabled = false

	seatedIK.Parent = currentHumanoid

	seatedBodyTurnIK = seatedIK
end

----------------------------------------------------------------
-- RESTORE CHARACTER
----------------------------------------------------------------

local function restorePreviousCharacter()
	if abilityManagerTurning and abilityManagerTurning.Parent then
		abilityManagerTurning:SetAttribute("UseLookDirectionInput", false)
	end

	abilityManagerTurning = nil

	if neck and originalNeckC0 then
		neck.C0 = originalNeckC0
	end

	destroyLookIK()

	-- Cleanup must always leave Roblox in normal camera ownership.
	firstPersonActive = false
	waitingForSeatedZoomOut = false
	firstPersonVisibilityAlpha = 0

	restoreDefaultCamera()

	local currentHumanoid = humanoid

	if currentHumanoid and originalCameraOffset then
		currentHumanoid.CameraOffset = originalCameraOffset
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

----------------------------------------------------------------
-- CHARACTER SETUP
----------------------------------------------------------------

local function setupCharacter(newCharacter: Model)
	restorePreviousCharacter()

	character = newCharacter

	humanoid = newCharacter:FindFirstChildOfClass("Humanoid")

	------------------------------------------------------------
	-- HEAD
	------------------------------------------------------------

	local foundHead = newCharacter:WaitForChild("Head")

	if foundHead:IsA("BasePart") then
		head = foundHead
	else
		head = nil
	end

	------------------------------------------------------------
	-- ROOT
	------------------------------------------------------------

	local foundRoot = newCharacter:WaitForChild("HumanoidRootPart")

	if foundRoot:IsA("BasePart") then
		rootPart = foundRoot
	else
		rootPart = nil
	end

	------------------------------------------------------------
	-- UPPER TORSO
	------------------------------------------------------------

	local upperCandidate = newCharacter:FindFirstChild("UpperTorso") or newCharacter:FindFirstChild("Torso")

	if upperCandidate and upperCandidate:IsA("BasePart") then
		upperTorso = upperCandidate
	else
		upperTorso = nil
	end

	------------------------------------------------------------
	-- LOWER TORSO
	------------------------------------------------------------

	local lowerCandidate = newCharacter:FindFirstChild("LowerTorso")

	if lowerCandidate and lowerCandidate:IsA("BasePart") then
		lowerTorso = lowerCandidate
	else
		lowerTorso = nil
	end

	------------------------------------------------------------
	-- NECK
	------------------------------------------------------------

	neck = nil
	originalNeckC0 = nil

	if upperTorso then
		local possibleNeck = upperTorso:FindFirstChild("Neck")

		if possibleNeck and possibleNeck:IsA("Motor6D") then
			neck = possibleNeck

			originalNeckC0 = possibleNeck.C0
		end
	end

	------------------------------------------------------------
	-- CAMERA OFFSET
	------------------------------------------------------------

	originalCameraOffset = nil

	if humanoid then
		originalCameraOffset = humanoid.CameraOffset

		-- Start by yielding to Roblox until the zoom detector confirms
		-- that the camera is actually at first-person distance.
		humanoid.CameraOffset = originalCameraOffset
	end

	------------------------------------------------------------
	-- RESET
	------------------------------------------------------------

	currentHeadPitch = 0
	currentHeadYaw = 0
	currentTorsoYaw = 0
	currentTorsoPitch = 0

	seatedCameraYaw = 0
	seatedCameraPitch = 0
	wasSeated = false

	firstPersonActive = false
	waitingForSeatedZoomOut = false
	firstPersonVisibilityAlpha = 0

	player:SetAttribute("TrueFirstPersonActive", false)

	------------------------------------------------------------
	-- IK
	------------------------------------------------------------

	createLookIK()

	------------------------------------------------------------
	-- VISIBILITY
	------------------------------------------------------------

	updateCharacterVisibility(0)

	characterDescendantAddedConnection = newCharacter.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			applyVisibilityToPart(descendant)
		end
	end)

	ensureZoomableCameraMode()
	applyMouseState()

	task.spawn(function()
		local turning = getAbilityManagerTurning(newCharacter)

		if character ~= newCharacter or not turning then
			return
		end

		abilityManagerTurning = turning
		updateAbilityManagerTurning()
	end)
end

----------------------------------------------------------------
-- SEATED CAMERA
----------------------------------------------------------------

local function updateSeatedCamera()
	local camera = Workspace.CurrentCamera

	local currentRoot = rootPart

	local reference = getFlatRootReference()

	if not camera or not currentRoot or not reference then
		return
	end

	local seated = isCurrentlySeated()

	------------------------------------------------------------
	-- THIRD PERSON
	------------------------------------------------------------

	-- Zoomed out means this controller completely yields camera ownership
	-- back to Roblox, including while seated.
	if not firstPersonActive then
		if wasSeated or camera.CameraType == Enum.CameraType.Scriptable then
			restoreDefaultCamera()
		end

		wasSeated = false
		seatedCameraYaw = 0
		seatedCameraPitch = 0

		return
	end

	------------------------------------------------------------
	-- STANDING
	------------------------------------------------------------

	if not seated then
		if wasSeated then
			restoreDefaultCamera()
		end

		wasSeated = false

		seatedCameraYaw = 0
		seatedCameraPitch = 0

		return
	end

	------------------------------------------------------------
	-- ENTERING SEAT
	------------------------------------------------------------

	local justSatDown = not wasSeated

	if justSatDown then
		local localLook = reference:VectorToObjectSpace(camera.CFrame.LookVector)

		seatedCameraPitch = math.asin(math.clamp(localLook.Y, -1, 1))

		seatedCameraYaw = math.atan2(-localLook.X, -localLook.Z)

		seatedCameraYaw = math.clamp(seatedCameraYaw, -getMaxSeatedCameraYaw(), getMaxSeatedCameraYaw())

		seatedCameraPitch = math.clamp(seatedCameraPitch, -MAX_SEATED_CAMERA_DOWN_PITCH, MAX_SEATED_CAMERA_UP_PITCH)

		camera.CameraType = Enum.CameraType.Scriptable

		wasSeated = true
	else
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
	end

	------------------------------------------------------------
	-- INPUT
	------------------------------------------------------------

	if not justSatDown and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		local mouseDelta = UserInputService:GetMouseDelta()

		seatedCameraYaw -= mouseDelta.X * SEATED_MOUSE_SENSITIVITY

		seatedCameraPitch -= mouseDelta.Y * SEATED_MOUSE_SENSITIVITY
	end

	------------------------------------------------------------
	-- HARD LIMITS
	------------------------------------------------------------

	seatedCameraYaw = math.clamp(seatedCameraYaw, -getMaxSeatedCameraYaw(), getMaxSeatedCameraYaw())

	seatedCameraPitch = math.clamp(seatedCameraPitch, -MAX_SEATED_CAMERA_DOWN_PITCH, MAX_SEATED_CAMERA_UP_PITCH)

	------------------------------------------------------------
	-- CAMERA DIRECTION
	------------------------------------------------------------

	local cosPitch = math.cos(seatedCameraPitch)

	local localDirection = Vector3.new(
		-math.sin(seatedCameraYaw) * cosPitch,
		math.sin(seatedCameraPitch),
		-math.cos(seatedCameraYaw) * cosPitch
	)

	local worldDirection = reference:VectorToWorldSpace(localDirection)

	------------------------------------------------------------
	-- HEAD / NECK-BASE CAMERA POSITION
	--
	-- Follow the torso/neck base so forward/back seated lean moves the
	-- camera with the character, while head rotation itself cannot
	-- create a camera <-> neck feedback loop.
	------------------------------------------------------------

	local cameraPosition = getSeatedEyePosition()

	if not cameraPosition then
		-- R15 fallback only; normally getSeatedEyePosition succeeds.
		cameraPosition = currentRoot.Position + Vector3.new(0, 1.5, 0)
	end

	camera.CFrame = CFrame.lookAt(cameraPosition, cameraPosition + worldDirection, Vector3.yAxis)
end

----------------------------------------------------------------
-- TORSO IK
----------------------------------------------------------------

local function updateTorsoIK(dt: number)
	local camera = Workspace.CurrentCamera

	local standingIK = standingTorsoIK

	local seatedIK = seatedBodyTurnIK

	local target = torsoIKTarget

	local currentUpperTorso = upperTorso

	if not camera or not standingIK or not seatedIK or not target or not currentUpperTorso then
		return
	end

	------------------------------------------------------------
	-- THIRD PERSON YIELDS BODY LOOK TO NORMAL CHARACTER CONTROL
	------------------------------------------------------------

	if not firstPersonActive then
		standingIK.Enabled = false
		standingIK.Weight = 0

		seatedIK.Enabled = false
		seatedIK.Weight = 0

		local returnAlpha = expAlpha(TORSO_FOLLOW_SPEED, dt)

		currentTorsoYaw = lerpNumber(currentTorsoYaw, 0, returnAlpha)

		currentTorsoPitch = lerpNumber(currentTorsoPitch, 0, returnAlpha)

		player:SetAttribute("SeatedTorsoYaw", 0)

		player:SetAttribute("SeatedTorsoPitch", 0)

		player:SetAttribute("UpperBodyConstraintAlpha", 0)

		return
	end

	local seated = isCurrentlySeated()

	------------------------------------------------------------
	-- STANDING
	------------------------------------------------------------

	if not seated then
		seatedIK.Enabled = false
		seatedIK.Weight = 0

		--------------------------------------------------------
		-- SWIMMING OWNS THE BODY POSE
		--------------------------------------------------------

		local currentHumanoid = humanoid

		if
			currentHumanoid
			and (
				currentHumanoid:GetState() == Enum.HumanoidStateType.Swimming
				or (character ~= nil and character:GetAttribute("IsSwimming") == true)
			)
		then
			standingIK.Enabled = false
			standingIK.Weight = 0
			return
		end

		--------------------------------------------------------
		-- STANDING: HEAD OWNS PITCH, SPINE ONLY HELPS YAW
		--
		-- Important:
		-- Do NOT feed camera Y/pitch into StandingUpperTorsoLookIK.
		-- Roblox's normal standing camera does not physically follow
		-- this Waist/UpperTorso pitch, so pitching the chest makes the
		-- neck base move away from the camera and exposes the back/neck.
		--
		-- The chain remains:
		--     LowerTorso -> UpperTorso
		-- so hips / legs / feet never join the look pose.
		--------------------------------------------------------

		local reference = getFlatRootReference()

		if not reference then
			standingIK.Enabled = false
			standingIK.Weight = 0
			return
		end

		local localLook = reference:VectorToObjectSpace(camera.CFrame.LookVector)

		local cameraYaw = math.atan2(-localLook.X, -localLook.Z)

		local cameraPitch = math.asin(math.clamp(localLook.Y, -1, 1))

		local torsoYaw =
			math.clamp(cameraYaw * STANDING_TORSO_YAW_SHARE, -MAX_STANDING_TORSO_YAW, MAX_STANDING_TORSO_YAW)

		-- IMPORTANT:
		-- Downward pitch never reaches the standing torso IK.
		-- Upward pitch gets a small chest/spine contribution because
		-- that pose looked natural and did not create the neck/back
		-- camera separation seen while looking down.
		local torsoPitch = 0

		if cameraPitch > 0 then
			torsoPitch = math.clamp(cameraPitch * STANDING_TORSO_UP_PITCH_SHARE, 0, MAX_STANDING_TORSO_UP_PITCH)
		end

		local cosPitch = math.cos(torsoPitch)

		local torsoDirectionLocal =
			Vector3.new(-math.sin(torsoYaw) * cosPitch, math.sin(torsoPitch), -math.cos(torsoYaw) * cosPitch)

		local torsoDirectionWorld = reference:VectorToWorldSpace(torsoDirectionLocal)

		standingIK.Enabled = true
		standingIK.Weight = STANDING_TORSO_IK_WEIGHT

		target.Position = currentUpperTorso.Position + torsoDirectionWorld * TORSO_TARGET_DISTANCE

		local alpha = expAlpha(TORSO_FOLLOW_SPEED, dt)

		currentTorsoYaw = lerpNumber(currentTorsoYaw, 0, alpha)

		currentTorsoPitch = lerpNumber(currentTorsoPitch, 0, alpha)

		player:SetAttribute("SeatedTorsoYaw", 0)

		player:SetAttribute("SeatedTorsoPitch", 0)

		player:SetAttribute("UpperBodyConstraintAlpha", 0)

		return
	end

	------------------------------------------------------------
	-- SEATED:
	-- CAMERA / HEAD LEADS, SHOULDERS ONLY ASSIST
	------------------------------------------------------------

	standingIK.Enabled = false

	local absoluteYaw = math.abs(seatedCameraYaw)

	local maxSeatedCameraYaw = getMaxSeatedCameraYaw()

	------------------------------------------------------------
	-- SMALL SHOULDER YAW
	--
	-- At +/-90 camera yaw the torso only contributes ~12 degrees.
	-- The head therefore carries roughly the remaining ~78 degrees.
	------------------------------------------------------------

	local yawAlpha = math.clamp(
		(absoluteYaw - TORSO_ASSIST_START_YAW) / math.max(0.001, maxSeatedCameraYaw - TORSO_ASSIST_START_YAW),
		0,
		1
	)

	yawAlpha = smoothstep01(yawAlpha)

	local targetTorsoYaw = MAX_SEATED_TORSO_YAW * yawAlpha

	if seatedCameraYaw < 0 then
		targetTorsoYaw = -targetTorsoYaw
	end

	------------------------------------------------------------
	-- FORWARD / DOWNWARD YAW LEAN
	--
	-- When looking far sideways, lean the shoulders a few degrees
	-- forward around the waist. This keeps the shoulder sockets a little
	-- closer to a steering wheel rather than pulling them backward/outward.
	------------------------------------------------------------

	local yawLeanAlpha =
		math.clamp((absoluteYaw - YAW_LEAN_START) / math.max(0.001, maxSeatedCameraYaw - YAW_LEAN_START), 0, 1)

	yawLeanAlpha = smoothstep01(yawLeanAlpha)

	local yawForwardLean = MAX_YAW_FORWARD_LEAN * yawLeanAlpha

	------------------------------------------------------------
	-- CAMERA PITCH -> SMALL TORSO PITCH
	------------------------------------------------------------

	local cameraPitchContribution = seatedCameraPitch * TORSO_PITCH_SHARE

	-- Negative pitch means forward/downward in this target convention.
	local targetTorsoPitch = cameraPitchContribution - yawForwardLean

	targetTorsoPitch = math.clamp(targetTorsoPitch, -MAX_SEATED_TORSO_DOWN_PITCH, MAX_SEATED_TORSO_UP_PITCH)

	------------------------------------------------------------
	-- SMOOTH BODY STATE
	------------------------------------------------------------

	local alpha = expAlpha(TORSO_FOLLOW_SPEED, dt)

	currentTorsoYaw = lerpNumber(currentTorsoYaw, targetTorsoYaw, alpha)

	currentTorsoPitch = lerpNumber(currentTorsoPitch, targetTorsoPitch, alpha)

	------------------------------------------------------------
	-- BODY IK WEIGHT
	------------------------------------------------------------

	local yawWeight = math.clamp(
		(absoluteYaw - TORSO_ASSIST_START_YAW) / math.max(0.001, TORSO_IK_FULL_WEIGHT_YAW - TORSO_ASSIST_START_YAW),
		0,
		1
	)

	yawWeight = smoothstep01(yawWeight)

	local pitchMagnitude = math.abs(seatedCameraPitch)

	local pitchWeight = math.clamp(
		(pitchMagnitude - TORSO_PITCH_ASSIST_START)
			/ math.max(0.001, TORSO_PITCH_FULL_WEIGHT - TORSO_PITCH_ASSIST_START),
		0,
		1
	)

	pitchWeight = smoothstep01(pitchWeight)

	local leanWeight = yawLeanAlpha

	local bodyWeight = math.max(yawWeight, pitchWeight, leanWeight)

	if bodyWeight <= 0.001 then
		seatedIK.Enabled = false
		seatedIK.Weight = 0

		player:SetAttribute("SeatedTorsoYaw", math.deg(currentTorsoYaw))

		player:SetAttribute("SeatedTorsoPitch", math.deg(currentTorsoPitch))

		player:SetAttribute("UpperBodyConstraintAlpha", 0)

		return
	end

	seatedIK.Enabled = true
	seatedIK.Weight = SEATED_BODY_IK_WEIGHT * bodyWeight

	------------------------------------------------------------
	-- YAW + PITCH LOOK TARGET
	------------------------------------------------------------

	local reference = getFlatRootReference()

	if not reference then
		seatedIK.Enabled = false
		seatedIK.Weight = 0
		return
	end

	local cosPitch = math.cos(currentTorsoPitch)

	local torsoDirectionLocal = Vector3.new(
		-math.sin(currentTorsoYaw) * cosPitch,
		math.sin(currentTorsoPitch),
		-math.cos(currentTorsoYaw) * cosPitch
	)

	local torsoDirectionWorld = reference:VectorToWorldSpace(torsoDirectionLocal)

	target.Position = currentUpperTorso.Position + torsoDirectionWorld * TORSO_TARGET_DISTANCE

	------------------------------------------------------------
	-- EXPOSE STATE FOR STEERING / HELD-OBJECT SYSTEMS
	------------------------------------------------------------

	player:SetAttribute("SeatedTorsoYaw", math.deg(currentTorsoYaw))

	player:SetAttribute("SeatedTorsoPitch", math.deg(currentTorsoPitch))

	player:SetAttribute("UpperBodyConstraintAlpha", 0)
end

----------------------------------------------------------------
-- HEAD / NECK
----------------------------------------------------------------

local function updateHeadLook(dt: number)
	local camera = Workspace.CurrentCamera

	local currentUpperTorso = upperTorso

	local currentNeck = neck

	local baseNeckC0 = originalNeckC0

	if not camera or not currentUpperTorso or not currentNeck or not baseNeckC0 then
		return
	end

	------------------------------------------------------------
	-- THIRD PERSON: RETURN NECK TO ITS NORMAL POSE
	------------------------------------------------------------

	if not firstPersonActive then
		local returnAlpha = expAlpha(HEAD_FOLLOW_SPEED, dt)

		currentHeadPitch = lerpNumber(currentHeadPitch, 0, returnAlpha)

		currentHeadYaw = lerpNumber(currentHeadYaw, 0, returnAlpha)

		currentNeck.C0 = baseNeckC0 * CFrame.Angles(currentHeadPitch, currentHeadYaw, 0)

		return
	end

	local seated = isCurrentlySeated()

	-- Camera is now independent of this animated torso/head pose,
	-- so reading the actual torso orientation here is safe.
	local localLook = currentUpperTorso.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)

	------------------------------------------------------------
	-- PITCH
	------------------------------------------------------------

	local targetPitch = math.asin(math.clamp(localLook.Y, -1, 1))

	if seated then
		targetPitch = math.clamp(targetPitch, -MAX_SEATED_HEAD_DOWN_PITCH, MAX_SEATED_HEAD_UP_PITCH)
	else
		targetPitch = math.clamp(targetPitch, -MAX_HEAD_PITCH, MAX_HEAD_PITCH)
	end

	------------------------------------------------------------
	-- YAW
	------------------------------------------------------------

	local targetYaw = math.atan2(-localLook.X, -localLook.Z)

	if seated then
		targetYaw = math.clamp(targetYaw, -MAX_SEATED_HEAD_YAW, MAX_SEATED_HEAD_YAW)
	else
		targetYaw = math.clamp(targetYaw, -MAX_HEAD_YAW, MAX_HEAD_YAW)
	end

	------------------------------------------------------------
	-- SMOOTH + APPLY
	------------------------------------------------------------

	local alpha = expAlpha(HEAD_FOLLOW_SPEED, dt)

	currentHeadPitch = lerpNumber(currentHeadPitch, targetPitch, alpha)

	currentHeadYaw = lerpNumber(currentHeadYaw, targetYaw, alpha)

	currentNeck.C0 = baseNeckC0 * CFrame.Angles(currentHeadPitch, currentHeadYaw, 0)
end

----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.KeyCode == CAMERA_MODE_KEY then
		local nextMode = selectedThirdPersonCameraMode + 1

		if nextMode > MAX_THIRD_PERSON_CAMERA_MODE then
			nextMode = 1
		end

		setThirdPersonCameraMode(nextMode, true)

		return
	end

	if input.KeyCode == Enum.KeyCode.M then
		if not firstPersonActive then
			return
		end
		mouseReleased = not mouseReleased

		player:SetAttribute("MouseReleased", mouseReleased)

		applyMouseState()
	end
end)

-- A seated first-person camera is Scriptable, so Roblox cannot move
-- Camera.CFrame itself until we release it. Mouse-wheel zoom-out performs
-- that release immediately; CameraModule then resumes its normal zoom.
UserInputService.InputChanged:Connect(function(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end

	if firstPersonActive and isCurrentlySeated() and input.Position.Z < 0 then
		waitingForSeatedZoomOut = true

		setFirstPersonActive(false)
		restoreDefaultCamera()
	end
end)

----------------------------------------------------------------
-- CHARACTER CONNECTIONS
----------------------------------------------------------------

if player.Character then
	setupCharacter(player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

player.CharacterRemoving:Connect(function(removingCharacter: Model)
	if removingCharacter ~= character then
		return
	end

	restorePreviousCharacter()

	character = nil
	humanoid = nil

	head = nil
	upperTorso = nil
	lowerTorso = nil
	rootPart = nil

	neck = nil
	originalNeckC0 = nil

	originalCameraOffset = nil

	currentHeadPitch = 0
	currentHeadYaw = 0
	currentTorsoYaw = 0
	currentTorsoPitch = 0

	seatedCameraYaw = 0
	seatedCameraPitch = 0
	wasSeated = false
end)

----------------------------------------------------------------
-- RENDER
----------------------------------------------------------------

RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	--------------------------------------------------------
	-- ROBLOX CAMERA OWNS ZOOM
	--------------------------------------------------------

	ensureZoomableCameraMode()
	updateFirstPersonZoomState()
	updateCameraOffsetForMode()

	applyMouseState()
	updateAbilityManagerTurning()
	updateCharacterVisibility(dt)

	--------------------------------------------------------
	-- CUSTOM CAMERA ONLY WHILE TRUE FIRST PERSON NEEDS IT
	--------------------------------------------------------

	updateSeatedCamera()

	--------------------------------------------------------
	-- SKELETON FOLLOWS CAMERA
	--------------------------------------------------------

	updateTorsoIK(dt)
	updateHeadLook(dt)
end)
