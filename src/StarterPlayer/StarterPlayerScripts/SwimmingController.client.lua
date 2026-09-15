-- StarterPlayerScripts, SwimmingController.client.lua
-- V2

--!native
--!strict

-- StarterPlayerScripts > SwimmingController
--
-- Responsibilities ONLY:
--   * Decide whether the local character is in the current test water.
--   * Apply neutral buoyancy for custom EditableMesh water.
--   * Camera-relative omnidirectional 3D swimming.
--   * Looking up/down + W naturally swims vertically.
--   * Space / controller A = explicit swim up.
--   * Ctrl/C / controller B = explicit swim down.
--
-- It does NOT manipulate the camera or water renderer.
--
-- V2 NOTES:
--   * Roblox Terrain water provides its own buoyancy.
--     EditableMesh water does not, so we cancel gravity ourselves.
--
--   * HumanoidStateType.Swimming is NOT relied upon for physics.
--
--   * W/S moves along the full camera LookVector.
--     This means looking straight up + W behaves like swimming upward.
--
--   * Space/Ctrl are blended into the same desired 3D direction.
--
--   * Horizontal and vertical maximum speeds can still be configured
--     separately using Speed and VerticalSpeed.
--
-- GRADUATED EXIT (added):
--   * Water entry uses SwimSettings.EnterOffset + surfaceY.
--   * Exiting is no longer a single boolean threshold. Root-part Y is
--     compared against two absolute-height bands, the same banded-tween
--     approach used on the coastline visual effect:
--
--       6.975 -> 7.161 : swimming and buoyancy fade out after an
--                        intentional jump through the surface.
--
--     Both ramps start at the foam band's upper edge so there's no seam/pop
--     where one hands off to the other.
--
-- CCL INTENT BRIDGE (added):
--   * ControllerManager.MovingDirection supplies movement intent.
--   * Existing local camera LookVector supplies full 3D look intent.
--   * Native CCL physics is neutralized only while custom water owns motion.
--   * We DO NOT force HumanoidStateType.Swimming for EditableMesh water.
--   * Character attributes IsSwimming / IsSubmerged describe custom water.


local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")

local ContextActionService =
	game:GetService("ContextActionService")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local Workspace =
	game:GetService("Workspace")


-- CCL supplies movement intent through ControllerManager.MovingDirection.
-- The existing local camera LookVector supplies full 3D pitch/yaw intent.
-- Our EditableMesh ocean still owns the actual swimming physics.

local WaterConfig =
	require(
		ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterConfig")
	)

local PlayerWaveMotionState = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerWaveMotionState")
)

local WaterSounds =
	ReplicatedStorage
	:WaitForChild("Shared")
	:WaitForChild("Sounds")
	:WaitForChild("Water")

local WaterSplashEntryTemplate =
	WaterSounds:WaitForChild(
		"WaterSplashEntry"
	)

assert(
	WaterSplashEntryTemplate:IsA("Sound"),
	"ReplicatedStorage.Shared.Sounds.Water.WaterSplashEntry must be a Sound"
)


local player =
	Players.LocalPlayer


local SwimSettings =
	WaterConfig.Swimming

local SurfaceTest =
	SwimSettings.SurfaceTest


----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------

-- 1.0 = exactly cancel Roblox gravity.
--
-- Later we could use something slightly above 1 near the surface
-- to make the player naturally float upward.
local BUOYANCY_SCALE =
	SwimSettings.BuoyancyScale
	or 1.0


local ACTION_PRIORITY =
	Enum.ContextActionPriority.High.Value
	+ 10

-- Walking down a shallow slope can briefly cross the entry threshold.
-- Require real downward momentum before playing the impact sound.
local ENTRY_SPLASH_MIN_FALL_SPEED = 4

-- Once an entry has occurred, require the character to return to solid
-- ground clearly above the surface before another splash can play.
local ENTRY_SPLASH_REARM_HEIGHT = 4


----------------------------------------------------------------
-- GRADUATED EXIT SETTINGS
----------------------------------------------------------------

-- Absolute world-space ROOT PART Y thresholds (same pattern as the
-- coastline effect's camera-Y fade), tuned from testing.

-- The surface assist starts before the visual clipping seen around this
-- height and gently returns an idle/rising swimmer to the foam band.
local SURFACE_ASSIST_START_Y =
	SurfaceTest.AssistStartY

local SURFACE_FLOAT_MIN_Y =
	SurfaceTest.FloatMinY

local SURFACE_FLOAT_TARGET_Y =
	SurfaceTest.FloatTargetY

local SURFACE_FLOAT_MAX_Y =
	SurfaceTest.FloatMaxY

local SURFACE_RESTORE_RESPONSE =
	SurfaceTest.RestoreResponse

local SURFACE_MAX_RESTORE_SPEED =
	SurfaceTest.MaxRestoreSpeed

local SURFACE_DESCEND_INPUT_THRESHOLD =
	SurfaceTest.DescendInputThreshold

-- Below the foam band's upper edge, full swim control applies.
local SWIM_STOP_START_Y =
	SURFACE_FLOAT_MAX_Y

-- Swimming itself is fully stopped by this height.
local SWIM_STOP_END_Y =
	SurfaceTest.ExitY

-- This test uses the same clear out-of-water boundary for buoyancy.
local BUOYANCY_RELEASE_END_Y =
	SWIM_STOP_END_Y


----------------------------------------------------------------
-- SWIM ORIENTATION SETTINGS
----------------------------------------------------------------

-- AlignOrientation gives the physical character a smooth response rather
-- than snapping the root to a new CFrame every frame.
local SWIM_ORIENTATION_RESPONSIVENESS =
	12

local SWIM_DIRECTION_DEADZONE =
	0.05


----------------------------------------------------------------
-- CUSTOM WATER STATE SETTINGS
----------------------------------------------------------------

-- IsSubmerged deliberately uses hysteresis so Gerstner-wave motion and
-- surface bobbing cannot flick the attribute on/off every frame.
local SUBMERGED_ENTER_DEPTH =
	1.5

local SUBMERGED_EXIT_DEPTH =
	1.0


----------------------------------------------------------------
-- CHARACTER STATE
----------------------------------------------------------------

local humanoid: Humanoid? =
	nil

local swimAnimationTrack: AnimationTrack? = nil

local function setSwimAnimationEnabled(enabled: boolean)
	local currentHumanoid = humanoid
	if not currentHumanoid then return end
	local animator = currentHumanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	if enabled then
		if swimAnimationTrack and swimAnimationTrack.IsPlaying then return end
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://507784897"
		swimAnimationTrack = animator:LoadAnimation(animation)
		swimAnimationTrack.Priority = Enum.AnimationPriority.Movement
		swimAnimationTrack.Looped = true
		swimAnimationTrack:Play(0.2)
	else
		if swimAnimationTrack then
			swimAnimationTrack:Stop(0.2)
			swimAnimationTrack = nil
		end
	end
end

local rootPart: BasePart? =
	nil


local swimAttachment: Attachment? =
	nil

local buoyancyForce: VectorForce? =
	nil

local swimOrientation: AlignOrientation? =
	nil

local humanoidAutoRotateBeforeSwimming: boolean? =
	nil


local characterModel: Model? =
	nil


----------------------------------------------------------------
-- CHARACTER CONTROLLER LIBRARY STATE
----------------------------------------------------------------

local controllerManager: ControllerManager? =
	nil

local airController: AirController? =
	nil

local groundController: GroundController? =
	nil

local activeControllerBeforeSwimming: ControllerBase? =
	nil

type AirControllerState = {
	MoveMaxForce: number,
	TurnMaxTorque: number,
	BalanceMaxTorque: number,
	BalanceSpeed: number,
	TurnSpeedFactor: number,
	BalanceRigidityEnabled: boolean,
	MaintainLinearMomentum: boolean,
	MaintainAngularMomentum: boolean,
}

local airControllerStateBeforeSwimming: AirControllerState? =
	nil


local lastSurfaceSwimFacingDirection =
	Vector3.new(0, 0, -1)

local entrySplashSound: Sound? =
	nil

local entrySplashArmed =
	true

local characterDescendantAddedConnection: RBXScriptConnection? =
	nil

local mutedDefaultSplashes: { [Instance]: RBXScriptConnection } = {}


local bodyInWater =
	false


-- True for the short window after swimming has stopped but before
-- buoyancy has fully released (i.e. we're coasting out of the water,
-- not falling toward it). Prevents buoyancy from applying while simply
-- descending from height above the water before ever having entered it.
local recentlyExitedWater =
	false


local swimUpHeld =
	false

local swimDownHeld =
	false

local swimControlsBound =
	false


----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

local function lerpNumber(
	a: number,
	b: number,
	alpha: number
): number

	return a
		+ (b - a)
		* alpha
end


local function getSurfaceY(): number
	return WaterConfig.GetSurfaceY()
end


local function disconnectDefaultSplashSuppression()
	if characterDescendantAddedConnection then
		characterDescendantAddedConnection:Disconnect()
		characterDescendantAddedConnection = nil
	end

	for _, connection in mutedDefaultSplashes do
		connection:Disconnect()
	end

	table.clear(mutedDefaultSplashes)
end


local function suppressDefaultSplash(
	instance: Instance
)
	if
		instance.Name ~= "Splash"
		or (
			not instance:IsA("Sound")
				and not instance:IsA("AudioPlayer")
		)
			or mutedDefaultSplashes[instance]
	then
		return
	end

	local playable =
		instance :: any

	local function keepMuted()
		if playable.Volume ~= 0 then
			playable.Volume = 0
		end
	end

	mutedDefaultSplashes[instance] =
		instance
		:GetPropertyChangedSignal("Volume")
		:Connect(keepMuted)

	keepMuted()
end


local function setupEntrySplashAudio(
	character: Model,
	currentRoot: BasePart
)
	disconnectDefaultSplashSuppression()
	entrySplashSound = nil

	for _, descendant in character:GetDescendants() do
		suppressDefaultSplash(descendant)
	end

	characterDescendantAddedConnection =
		character.DescendantAdded:Connect(
			suppressDefaultSplash
		)

	local oldSplash =
		currentRoot:FindFirstChild(
			"WaterSplashEntry_Local"
		)

	if oldSplash then
		oldSplash:Destroy()
	end

	local splash =
		WaterSplashEntryTemplate:Clone()

	splash.Name =
		"WaterSplashEntry_Local"

	splash.Looped =
		false

	splash.Parent =
		currentRoot

	splash:Stop()
	entrySplashSound = splash
end


local function playEntrySplash(
	verticalVelocity: number
)
	local wasArmed =
		entrySplashArmed

	-- Every water entry consumes the current airborne cycle, including a
	-- gentle entry. Surface bobbing cannot repeatedly qualify afterward.
	entrySplashArmed = false

	if
		not wasArmed
		or verticalVelocity > -ENTRY_SPLASH_MIN_FALL_SPEED
	then
		return
	end

	local splash =
		entrySplashSound

	if not splash then
		return
	end

	splash:Stop()
	splash.TimePosition = 0
	splash:Play()
end


-- 1 = full swim control, 0 = swimming has fully stopped.
-- Ramps out linearly between SWIM_STOP_START_Y and SWIM_STOP_END_Y.
local function getSwimAlpha(
	rootY: number
): number

	if rootY <= SWIM_STOP_START_Y then
		return 1
	end

	if rootY >= SWIM_STOP_END_Y then
		return 0
	end

	return
		1
	- (
		rootY - SWIM_STOP_START_Y
	)
		/ (
			SWIM_STOP_END_Y
			- SWIM_STOP_START_Y
		)
end


-- 1 = full buoyancy, 0 = fully released to normal gravity.
-- This test fades buoyancy across the same narrow surface-exit band as
-- swim control so Y=7.161 is a clear handoff to normal physics.
local function getBuoyancyAlpha(
	rootY: number
): number

	if rootY <= SWIM_STOP_START_Y then
		return 1
	end

	if rootY >= BUOYANCY_RELEASE_END_Y then
		return 0
	end

	return
		1
	- (
		rootY - SWIM_STOP_START_Y
	)
		/ (
			BUOYANCY_RELEASE_END_Y
			- SWIM_STOP_START_Y
		)
end


----------------------------------------------------------------
-- BUOYANCY
----------------------------------------------------------------

local function setBuoyancyEnabled(
	enabled: boolean,
	scale: number?
)

	local currentRoot =
		rootPart

	local force =
		buoyancyForce

	if
		not currentRoot
		or not force
	then
		return
	end


	if not enabled then
		force.Force =
			Vector3.zero

		return
	end


	-- AssemblyMass represents the entire connected character assembly.
	--
	-- Gravity force:
	--
	-- mass * gravity
	--
	-- Applying the opposite upward force gives approximately
	-- neutral buoyancy. `scale` lets callers taper this down smoothly
	-- instead of only ever being fully on or fully off.

	local appliedScale =
		scale
		or 1

	local requiredForce =
		currentRoot.AssemblyMass
		* Workspace.Gravity
		* BUOYANCY_SCALE
		* appliedScale


	force.Force =
		Vector3.new(
			0,
			requiredForce,
			0
		)
end


----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------

local function swimUpAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult

	if not bodyInWater then
		return Enum.ContextActionResult.Pass
	end


	if
		inputState
		== Enum.UserInputState.Begin
	then

		swimUpHeld =
			true

	elseif
		inputState
		== Enum.UserInputState.End

		or inputState
		== Enum.UserInputState.Cancel
	then

		swimUpHeld =
			false
	end


	return Enum.ContextActionResult.Sink
end


local function swimDownAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult

	if not bodyInWater then
		return Enum.ContextActionResult.Pass
	end


	if
		inputState
		== Enum.UserInputState.Begin
	then

		swimDownHeld =
			true

	elseif
		inputState
		== Enum.UserInputState.End

		or inputState
		== Enum.UserInputState.Cancel
	then

		swimDownHeld =
			false
	end


	return Enum.ContextActionResult.Sink
end


local function bindSwimControls()

	if swimControlsBound then
		return
	end


	swimControlsBound =
		true


	ContextActionService:BindActionAtPriority(
		"WaterSwimUp",
		swimUpAction,
		true,
		ACTION_PRIORITY,

		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA
	)


	ContextActionService:SetTitle(
		"WaterSwimUp",
		"↑"
	)


	ContextActionService:SetPosition(
		"WaterSwimUp",

		UDim2.new(
			1,
			-150,

			1,
			-220
		)
	)


	ContextActionService:BindActionAtPriority(
		"WaterSwimDown",
		swimDownAction,
		true,
		ACTION_PRIORITY,

		Enum.KeyCode.LeftControl,
		Enum.KeyCode.C,
		Enum.KeyCode.ButtonB
	)


	ContextActionService:SetTitle(
		"WaterSwimDown",
		"↓"
	)


	ContextActionService:SetPosition(
		"WaterSwimDown",

		UDim2.new(
			1,
			-80,

			1,
			-220
		)
	)
end


local function unbindSwimControls()

	if not swimControlsBound then
		return
	end


	swimControlsBound =
		false


	swimUpHeld =
		false

	swimDownHeld =
		false


	ContextActionService:UnbindAction(
		"WaterSwimUp"
	)


	ContextActionService:UnbindAction(
		"WaterSwimDown"
	)
end


----------------------------------------------------------------
-- CUSTOM WATER / CCL OWNERSHIP
----------------------------------------------------------------

local function setCustomWaterAttributes(
	isSwimming: boolean,
	isSubmerged: boolean
)
	local currentCharacter =
		characterModel

	if not currentCharacter then
		return
	end

	currentCharacter:SetAttribute(
		"IsSwimming",
		isSwimming
	)

	currentCharacter:SetAttribute(
		"IsSubmerged",
		isSubmerged
	)
end


local function updateSubmergedAttribute(
	surfaceY: number,
	rootY: number
)
	local currentCharacter =
		characterModel

	if not currentCharacter then
		return
	end

	if not bodyInWater then
		if currentCharacter:GetAttribute("IsSubmerged") == true then
			currentCharacter:SetAttribute(
				"IsSubmerged",
				false
			)
		end

		return
	end

	local depthBelowSurface =
		surfaceY - rootY

	local currentlySubmerged =
		currentCharacter:GetAttribute(
			"IsSubmerged"
		) == true

	if not currentlySubmerged then
		if depthBelowSurface >= SUBMERGED_ENTER_DEPTH then
			currentCharacter:SetAttribute(
				"IsSubmerged",
				true
			)
		end

	elseif depthBelowSurface <= SUBMERGED_EXIT_DEPTH then
		currentCharacter:SetAttribute(
			"IsSubmerged",
			false
		)
	end
end


local function findControllerManager(
	character: Model,
	currentHumanoid: Humanoid
): ControllerManager?
	-- Roblox's CCL hierarchy has changed during the beta. The documented
	-- layout places ControllerManager on the character, while some generated
	-- rigs/builds have exposed it beneath the Humanoid. Support both.
	local deadline =
		time() + 5

	repeat
		local fromCharacter =
			character:FindFirstChildOfClass(
				"ControllerManager"
			)

		if fromCharacter then
			return fromCharacter
		end

		local fromHumanoid =
			currentHumanoid:FindFirstChildOfClass(
				"ControllerManager"
			)

		if fromHumanoid then
			return fromHumanoid
		end

		task.wait()
	until
	not character.Parent
		or time() >= deadline

	return nil
end


local function captureCCLReferences(
	character: Model,
	currentHumanoid: Humanoid
)
	controllerManager =
		findControllerManager(
			character,
			currentHumanoid
		)

	local currentControllerManager =
		controllerManager

	if currentControllerManager then
		airController =
			currentControllerManager:FindFirstChildOfClass(
				"AirController"
			)

		groundController =
			currentControllerManager:FindFirstChildOfClass(
				"GroundController"
			)
	else
		airController =
			nil

		groundController =
			nil
	end

	if not controllerManager then
		warn(
			"[SwimmingController] CCL ControllerManager was not found; using legacy movement fallbacks."
		)
	end
end


local function takeCustomWaterCCLOwnership()
	local currentControllerManager =
		controllerManager

	local currentAirController =
		airController

	if
		not currentControllerManager
		or not currentAirController
	then
		return
	end

	activeControllerBeforeSwimming =
		currentControllerManager.ActiveController

	airControllerStateBeforeSwimming = {
		MoveMaxForce =
			currentAirController.MoveMaxForce,

		TurnMaxTorque =
			currentAirController.TurnMaxTorque,

		BalanceMaxTorque =
			currentAirController.BalanceMaxTorque,

		BalanceSpeed =
			currentAirController.BalanceSpeed,

		TurnSpeedFactor =
			currentAirController.TurnSpeedFactor,

		BalanceRigidityEnabled =
			currentAirController.BalanceRigidityEnabled,

		MaintainLinearMomentum =
			currentAirController.MaintainLinearMomentum,

		MaintainAngularMomentum =
			currentAirController.MaintainAngularMomentum,
	}

	-- Our EditableMesh ocean owns velocity, buoyancy and orientation.
	-- The CCL remains alive purely as an INPUT/SENSOR source.
	currentAirController.MoveMaxForce =
		0

	currentAirController.TurnMaxTorque =
		0

	currentAirController.BalanceMaxTorque =
		0

	currentAirController.TurnSpeedFactor =
		0

	currentAirController.BalanceRigidityEnabled =
		false

	currentAirController.MaintainLinearMomentum =
		false

	currentAirController.MaintainAngularMomentum =
		false

	currentControllerManager.ActiveController =
		currentAirController
end


local function maintainCustomWaterCCLOwnership()
	if not bodyInWater then
		return
	end

	local currentControllerManager =
		controllerManager

	local currentAirController =
		airController

	if
		not currentControllerManager
		or not currentAirController
	then
		return
	end

	-- Built-in abilities can select controllers during their own updates.
	-- Reassert the neutral AirController while custom water owns locomotion.
	currentControllerManager.ActiveController =
		currentAirController

	currentAirController.MoveMaxForce =
		0

	currentAirController.TurnMaxTorque =
		0

	currentAirController.BalanceMaxTorque =
		0

	currentAirController.TurnSpeedFactor =
		0

	currentAirController.BalanceRigidityEnabled =
		false

	currentAirController.MaintainLinearMomentum =
		false

	currentAirController.MaintainAngularMomentum =
		false
end


local function releaseCustomWaterCCLOwnership()
	local currentControllerManager =
		controllerManager

	local currentAirController =
		airController

	local savedAirControllerState =
		airControllerStateBeforeSwimming

	if
		currentAirController
		and savedAirControllerState
	then
		currentAirController.MoveMaxForce =
			savedAirControllerState.MoveMaxForce

		currentAirController.TurnMaxTorque =
			savedAirControllerState.TurnMaxTorque

		currentAirController.BalanceMaxTorque =
			savedAirControllerState.BalanceMaxTorque

		currentAirController.BalanceSpeed =
			savedAirControllerState.BalanceSpeed

		currentAirController.TurnSpeedFactor =
			savedAirControllerState.TurnSpeedFactor

		currentAirController.BalanceRigidityEnabled =
			savedAirControllerState.BalanceRigidityEnabled

		currentAirController.MaintainLinearMomentum =
			savedAirControllerState.MaintainLinearMomentum

		currentAirController.MaintainAngularMomentum =
			savedAirControllerState.MaintainAngularMomentum
	end

	airControllerStateBeforeSwimming =
		nil


	if currentControllerManager then
		local currentGroundController =
			groundController

		local groundSensor =
			currentControllerManager.GroundSensor

		local groundIsSensed =
			false

		if
			groundSensor
			and groundSensor:IsA("ControllerPartSensor")
		then
			groundIsSensed =
				groundSensor.SensedPart ~= nil
		end

		-- If we have already reached a floor/beach, hand directly to ground.
		-- Otherwise restore whichever controller was active before custom water
		-- took ownership; normal CCL abilities can then choose again next frame.
		if
			groundIsSensed
			and currentGroundController
		then
			currentControllerManager.ActiveController =
				currentGroundController

		elseif
			activeControllerBeforeSwimming
			and activeControllerBeforeSwimming.Parent
		then
			currentControllerManager.ActiveController =
				activeControllerBeforeSwimming
		end
	end

	activeControllerBeforeSwimming =
		nil
end


local function getCCLMoveDirection(
	currentHumanoid: Humanoid
): Vector3
	local currentControllerManager =
		controllerManager

	if currentControllerManager then
		return currentControllerManager.MovingDirection
	end

	-- Legacy fallback if CCL is absent/late during character creation.
	return currentHumanoid.MoveDirection
end


----------------------------------------------------------------
-- ENTER / EXIT WATER
----------------------------------------------------------------

local function enterSwimming()

	if bodyInWater then
		return
	end

	local entryVerticalVelocity = 0
	local currentRoot =
		rootPart

	if currentRoot then
		entryVerticalVelocity =
			currentRoot.AssemblyLinearVelocity.Y
	end


	bodyInWater =
		true

	setCustomWaterAttributes(
		true,
		false
	)

	takeCustomWaterCCLOwnership()

	setSwimAnimationEnabled(true)

	-- Fresh cycle - any leftover post-exit coast-out is no longer
	-- relevant once we're actively swimming again.
	recentlyExitedWater =
		false


	bindSwimControls()

	setBuoyancyEnabled(
		true,
		1
	)

	playEntrySplash(
		entryVerticalVelocity
	)


	-- This is only useful for whatever animation/state behaviour
	-- Roblox chooses to provide.
	--
	-- We DO NOT rely on this state for actual swimming physics.

	local currentHumanoid =
		humanoid

	if currentHumanoid then

		humanoidAutoRotateBeforeSwimming =
			currentHumanoid.AutoRotate

		currentHumanoid.AutoRotate =
			false


		local orientation =
			swimOrientation

		local currentRootForOrientation =
			rootPart

		if
			orientation
			and currentRootForOrientation
		then

			orientation.CFrame =
				currentRootForOrientation.CFrame.Rotation

			orientation.Enabled =
				true
		end


		-- IMPORTANT:
		-- Do NOT call Humanoid:ChangeState(Swimming) here. This is not
		-- Roblox/Terrain water. Native CCL Water/WaterSurface sensing remains
		-- free to identify real Roblox water; our ocean uses IsSwimming instead.
	end
end


local function exitSwimming()

	if not bodyInWater then
		return
	end


	bodyInWater =
		false

	setCustomWaterAttributes(
		false,
		false
	)

	releaseCustomWaterCCLOwnership()

	setSwimAnimationEnabled(false)


	local orientation =
		swimOrientation

	if orientation then

		orientation.Enabled =
			false
	end


	local currentHumanoid =
		humanoid

	if
		currentHumanoid
		and humanoidAutoRotateBeforeSwimming ~= nil
	then

		currentHumanoid.AutoRotate =
			humanoidAutoRotateBeforeSwimming
	end

	humanoidAutoRotateBeforeSwimming =
		nil


	-- Preserve the exit handoff until buoyancy has reached zero. Keeping
	-- this state separate prevents buoyancy from affecting a new fall.
	recentlyExitedWater =
		true


	unbindSwimControls()


	local currentRoot =
		rootPart


	if currentRoot then

		local velocity =
			currentRoot.AssemblyLinearVelocity


		-- Prevent a massive swim-up velocity from launching the
		-- character into orbit after leaving the water.

		currentRoot.AssemblyLinearVelocity =
			Vector3.new(
				velocity.X,

				math.min(
					velocity.Y,
					8
				),

				velocity.Z
			)
	end
end


----------------------------------------------------------------
-- CHARACTER SETUP
----------------------------------------------------------------

local function setupCharacter(
	character: Model
)
	characterModel =
		character

	setCustomWaterAttributes(
		false,
		false
	)

	disconnectDefaultSplashSuppression()
	entrySplashSound = nil
	entrySplashArmed = true

	local foundHumanoid =
		character:WaitForChild(
			"Humanoid"
		)


	local foundRoot =
		character:WaitForChild(
			"HumanoidRootPart"
		)


	if foundHumanoid:IsA("Humanoid") then
		humanoid =
			foundHumanoid
	else
		humanoid =
			nil
	end


	if foundRoot:IsA("BasePart") then
		rootPart =
			foundRoot
	else
		rootPart =
			nil
	end


	if foundHumanoid:IsA("Humanoid") then
		captureCCLReferences(
			character,
			foundHumanoid
		)
	else
		controllerManager =
			nil

		airController =
			nil

		groundController =
			nil
	end


	bodyInWater =
		false

	recentlyExitedWater =
		false


	swimUpHeld =
		false

	swimDownHeld =
		false


	unbindSwimControls()


	----------------------------------------------------------------
	-- CREATE BUOYANCY ACTUATOR
	----------------------------------------------------------------

	if rootPart then

		local currentRoot =
			rootPart

		setupEntrySplashAudio(
			character,
			currentRoot
		)


		local oldAttachment =
			currentRoot:FindFirstChild(
				"WaterSwimAttachment"
			)


		if oldAttachment then
			oldAttachment:Destroy()
		end


		local oldForce =
			currentRoot:FindFirstChild(
				"WaterBuoyancy"
			)


		if oldForce then
			oldForce:Destroy()
		end


		local attachment =
			Instance.new("Attachment")


		attachment.Name =
			"WaterSwimAttachment"


		attachment.Parent =
			currentRoot


		swimAttachment =
			attachment


		------------------------------------------------------------
		-- CREATE SWIM ORIENTATION ACTUATOR
		------------------------------------------------------------

		local oldOrientation =
			currentRoot:FindFirstChild(
				"WaterSwimOrientation"
			)

		if oldOrientation then
			oldOrientation:Destroy()
		end


		local orientation =
			Instance.new(
				"AlignOrientation"
			)

		orientation.Name =
			"WaterSwimOrientation"

		orientation.Mode =
			Enum.OrientationAlignmentMode.OneAttachment

		orientation.Attachment0 =
			attachment

		orientation.RigidityEnabled =
			false

		orientation.Responsiveness =
			SWIM_ORIENTATION_RESPONSIVENESS

		orientation.MaxTorque =
			math.huge

		orientation.MaxAngularVelocity =
			math.huge

		orientation.Enabled =
			false

		orientation.Parent =
			currentRoot

		swimOrientation =
			orientation


		local initialFlatLook =
			Vector3.new(
				currentRoot.CFrame.LookVector.X,
				0,
				currentRoot.CFrame.LookVector.Z
			)

		if initialFlatLook.Magnitude > 0.001 then

			lastSurfaceSwimFacingDirection =
				initialFlatLook.Unit
		end


		local force =
			Instance.new("VectorForce")


		force.Name =
			"WaterBuoyancy"


		force.Attachment0 =
			attachment


		force.RelativeTo =
			Enum.ActuatorRelativeTo.World


		force.ApplyAtCenterOfMass =
			true


		force.Force =
			Vector3.zero


		force.Parent =
			currentRoot


		buoyancyForce =
			force
	end
end


----------------------------------------------------------------
-- OMNIDIRECTIONAL SWIMMING
----------------------------------------------------------------

local function getOmnidirectionalSwimDirection(): (Vector3, Vector3, Vector3)

	local camera =
		Workspace.CurrentCamera

	local currentHumanoid =
		humanoid

	local currentRoot =
		rootPart

	if
		not camera
		or not currentHumanoid
	then
		return Vector3.zero, Vector3.zero, Vector3.zero
	end


	----------------------------------------------------------------
	-- GET ROBLOX MOVEMENT INPUT
	----------------------------------------------------------------

	local moveDirection =
		getCCLMoveDirection(
			currentHumanoid
		)


	----------------------------------------------------------------
	-- CAMERA BASIS
	----------------------------------------------------------------

	-- CCL MovingDirection gives us movement intent, but we deliberately keep
	-- the OLD full camera LookVector for pitch. FacingDirection is not the
	-- right source for head-first up/down swimming.
	local trackedLookVector =
		player:GetAttribute(
			"LooKVector"
		)

	local cameraLook =
		camera.CFrame.LookVector

	if
		typeof(trackedLookVector) == "Vector3"
		and trackedLookVector.Magnitude > 0.001
	then
		cameraLook =
			trackedLookVector.Unit
	end

	local cameraRight =
		camera.CFrame.RightVector


	-- Flat camera vectors are used only to work out what W/A/S/D
	-- the player is providing. Forward swimming itself still uses the
	-- COMPLETE camera LookVector, including pitch.
	local flatForward =
		Vector3.new(
			cameraLook.X,
			0,
			cameraLook.Z
		)

	-- If the camera is almost directly above/below the player, LookVector
	-- has almost no horizontal component. Camera UpVector still gives us
	-- the direction corresponding to the top of the screen, which keeps
	-- camera-relative A/D/W/S interpretation stable.
	if
		flatForward.Magnitude
		<= 0.001
	then

		local cameraUp =
			camera.CFrame.UpVector

		flatForward =
			Vector3.new(
				cameraUp.X,
				0,
				cameraUp.Z
			)
	end

	if
		flatForward.Magnitude
		<= 0.001
	then

		if currentRoot then

			local rootLook =
				currentRoot.CFrame.LookVector

			flatForward =
				Vector3.new(
					rootLook.X,
					0,
					rootLook.Z
				)
		end
	end

	if
		flatForward.Magnitude
		<= 0.001
	then

		flatForward =
			Vector3.new(
				0,
				0,
				-1
			)

	else

		flatForward =
			flatForward.Unit
	end


	local flatRight =
		Vector3.new(
			cameraRight.X,
			0,
			cameraRight.Z
		)

	if
		flatRight.Magnitude
		<= 0.001
	then

		flatRight =
			Vector3.new(
				-flatForward.Z,
				0,
				flatForward.X
			)

	else

		flatRight =
			flatRight.Unit
	end


	----------------------------------------------------------------
	-- EXTRACT FORWARD / RIGHT INPUT
	----------------------------------------------------------------

	local forwardAmount =
		0

	local rightAmount =
		0

	if
		moveDirection.Magnitude
		> 0.01
	then

		forwardAmount =
			moveDirection:Dot(
				flatForward
			)

		rightAmount =
			moveDirection:Dot(
				flatRight
			)
	end


	----------------------------------------------------------------
	-- DIRECTIONAL SWIM VECTOR
	----------------------------------------------------------------

	-- Underwater, W/S use the complete camera LookVector, so the player
	-- can naturally pitch into dives and climbs. A/D remain horizontal
	-- camera-relative strafing inputs and contribute to the final heading.
	local directionalSwimDirection =
		cameraLook
		* forwardAmount

		+ flatRight
		* rightAmount

	if directionalSwimDirection.Magnitude > 1 then

		directionalSwimDirection =
			directionalSwimDirection.Unit
	end


	----------------------------------------------------------------
	-- SURFACE ORIENTATION VECTOR
	----------------------------------------------------------------

	-- ControllerManager.MovingDirection is Roblox CCL's desired movement
	-- direction in world space. Flattening it gives us a very stable
	-- surface heading, including when the camera is nearly directly above
	-- the swimmer. This affects BODY ORIENTATION ONLY; the actual swim
	-- physics below remain unchanged.
	local surfaceDirectionalSwimDirection =
		Vector3.new(
			moveDirection.X,
			0,
			moveDirection.Z
		)

	if surfaceDirectionalSwimDirection.Magnitude > 1 then

		surfaceDirectionalSwimDirection =
			surfaceDirectionalSwimDirection.Unit
	end


	----------------------------------------------------------------
	-- EXPLICIT VERTICAL INPUT
	----------------------------------------------------------------

	local verticalAmount =
		0

	if swimUpHeld then
		verticalAmount += 1
	end

	if swimDownHeld then
		verticalAmount -= 1
	end


	----------------------------------------------------------------
	-- FINAL PHYSICAL SWIM VECTOR
	----------------------------------------------------------------

	-- Space/Ctrl remain WORLD-VERTICAL movement. Character orientation
	-- never feeds back into this vector, so rotating/spinning the avatar
	-- cannot bend an explicit ascent or descent.
	local desired =
		directionalSwimDirection

		+ Vector3.yAxis
		* verticalAmount

	if desired.Magnitude > 1 then

		desired =
			desired.Unit
	end


	return
		desired,
		directionalSwimDirection,
		surfaceDirectionalSwimDirection
end


----------------------------------------------------------------
-- SWIM ORIENTATION
----------------------------------------------------------------

local function getTrackedLookVector(): Vector3

	-- Keep the old full 3D look source for swimming orientation. The separate
	-- Look controller updates this locally every time the camera CFrame changes,
	-- so it preserves camera pitch without inheriting the RemoteEvent throttle.
	local trackedLookVector =
		player:GetAttribute(
			"LooKVector"
		)

	if
		typeof(trackedLookVector) == "Vector3"
		and trackedLookVector.Magnitude > 0.001
	then
		return trackedLookVector.Unit
	end


	local camera =
		Workspace.CurrentCamera

	if camera then

		local cameraLookVector =
			camera.CFrame.LookVector

		if cameraLookVector.Magnitude > 0.001 then
			return cameraLookVector.Unit
		end
	end


	local currentRoot =
		rootPart

	if currentRoot then
		return currentRoot.CFrame.LookVector
	end


	return Vector3.new(
		0,
		0,
		-1
	)
end

local function getNeutralSwimOrientation(): CFrame

	local trackedLookVector =
		getTrackedLookVector()

	local flatLookVector =
		Vector3.new(
			trackedLookVector.X,
			0,
			trackedLookVector.Z
		)

	if
		flatLookVector.Magnitude
		> SWIM_DIRECTION_DEADZONE
	then

		lastSurfaceSwimFacingDirection =
			flatLookVector.Unit
	end


	-- Neutral means a normal upright Roblox character. AlignOrientation's
	-- responsiveness makes the transition back from a prone swim smooth.
	return CFrame.lookAt(
		Vector3.zero,
		lastSurfaceSwimFacingDirection,
		Vector3.yAxis
	)
end


local function getProneSwimOrientation(
	swimHeading: Vector3
): CFrame

	local currentRoot =
		rootPart

	local camera =
		Workspace.CurrentCamera

	local heading =
		swimHeading.Unit


	----------------------------------------------------------------
	-- HEAD-FIRST AXIS
	----------------------------------------------------------------

	-- A standing Roblox character's HEAD/FEET axis is RootPart.UpVector.
	-- While prone-swimming, LOCAL +Y therefore points along travel.
	--
	-- The important extra rule here is BELLY-DOWN STABILITY:
	-- reversing direction must not leave the character permanently on
	-- their back. We project world-up onto the plane perpendicular to
	-- the head-first heading and use that as the character's BackVector.
	-- That makes LookVector/chest face toward world-down whenever the
	-- heading is not almost perfectly vertical.

	local worldUp =
		Vector3.yAxis

	local projectedWorldUp =
		worldUp
	- heading
		* worldUp:Dot(
			heading
		)


	----------------------------------------------------------------
	-- NORMAL PRONE SWIMMING: KEEP BELLY TOWARD THE WATER / GROUND
	----------------------------------------------------------------

	if projectedWorldUp.Magnitude > 0.05 then

		local backVector =
			projectedWorldUp.Unit

		-- For CFrame.fromMatrix:
		-- X = Right
		-- Y = Up      (our head-first swim heading)
		-- Z = Back    (opposite the chest/LookVector)
		--
		-- heading x back gives the matching RightVector. Recomputing
		-- BackVector afterward removes tiny floating-point skew.
		local rightVector =
			heading:Cross(
				backVector
			)

		if rightVector.Magnitude <= 0.001 then
			return getNeutralSwimOrientation()
		end

		rightVector =
			rightVector.Unit

		backVector =
			rightVector:Cross(
				heading
			).Unit

		return CFrame.fromMatrix(
			Vector3.zero,
			rightVector,
			heading,
			backVector
		)
	end


	----------------------------------------------------------------
	-- NEAR-VERTICAL SWIMMING
	----------------------------------------------------------------

	-- When swimming almost perfectly straight up/down, world-up is
	-- parallel to the body axis and cannot tell us which way the chest
	-- should roll. Use camera-right (or the current root-right) only for
	-- that roll decision. This keeps Ctrl dives and vertical climbs stable
	-- without letting that camera roll reference cause the old backstroke
	-- problem during ordinary forward/backward swimming.

	local rollReference =
		Vector3.xAxis

	if camera then

		rollReference =
			camera.CFrame.RightVector

	elseif currentRoot then

		rollReference =
			currentRoot.CFrame.RightVector
	end


	local rightVector =
		rollReference
	- heading
		* rollReference:Dot(
			heading
		)

	if rightVector.Magnitude <= 0.001 then

		local fallbackReference =
			Vector3.zAxis

		rightVector =
			fallbackReference
		- heading
			* fallbackReference:Dot(
				heading
			)
	end

	if rightVector.Magnitude <= 0.001 then
		return getNeutralSwimOrientation()
	end

	rightVector =
		rightVector.Unit


	local backVector =
		rightVector:Cross(
			heading
		)

	if backVector.Magnitude <= 0.001 then
		return getNeutralSwimOrientation()
	end

	backVector =
		backVector.Unit


	return CFrame.fromMatrix(
		Vector3.zero,
		rightVector,
		heading,
		backVector
	)
end

local function updateSwimOrientation(
	directionalSwimDirection: Vector3,
	surfaceDirectionalSwimDirection: Vector3,
	surfaceHoldActive: boolean
)

	local orientation =
		swimOrientation

	if
		not orientation
		or not orientation.Enabled
	then
		return
	end


	----------------------------------------------------------------
	-- EXPLICIT VERTICAL POSES
	----------------------------------------------------------------

	-- If both vertical buttons are held, their physical Y input cancels.
	-- Visually return to neutral too rather than fighting between poses.
	if swimUpHeld and swimDownHeld then

		orientation.CFrame =
			getNeutralSwimOrientation()

		return
	end


	-- CTRL / C / controller B:
	--
	-- Go straight down in world space, while visually using the SAME
	-- head-first dive pose produced by looking straight down and pressing W.
	--
	-- This is deliberately only an orientation target. The physical descent
	-- is still produced separately by the world-space -Y movement vector.
	if swimDownHeld then

		orientation.CFrame =
			getProneSwimOrientation(
				-Vector3.yAxis
			)

		return
	end


	-- SPACE / controller A:
	--
	-- Re-centre into the neutral/treading pose while the controller moves
	-- straight upward in world space. This preserves the animation that
	-- already looks good for surfacing instead of standing the avatar on
	-- their head/feet axis.
	if swimUpHeld then

		orientation.CFrame =
			getNeutralSwimOrientation()

		return
	end


	----------------------------------------------------------------
	-- SURFACE SWIMMING
	----------------------------------------------------------------

	if surfaceHoldActive then

		-- At the surface, use Roblox's already camera-relative horizontal
		-- MoveDirection. This gives the old useful "laying down and turning"
		-- feel without allowing camera pitch to tip the swimmer through the
		-- surface. It also remains intuitive with a top-down camera: A/D and
		-- the other movement keys still produce a real horizontal heading.
		if
			surfaceDirectionalSwimDirection.Magnitude
			> SWIM_DIRECTION_DEADZONE
		then

			local surfaceHeading =
				surfaceDirectionalSwimDirection.Unit

			lastSurfaceSwimFacingDirection =
				surfaceHeading

			orientation.CFrame =
				getProneSwimOrientation(
					surfaceHeading
				)

			return
		end


		-- No movement at the surface: smoothly stand the character back into
		-- the neutral/treading animation rather than leaving them frozen prone.
		orientation.CFrame =
			getNeutralSwimOrientation()

		return
	end


	----------------------------------------------------------------
	-- UNDERWATER OMNIDIRECTIONAL SWIMMING
	----------------------------------------------------------------

	-- Once SurfaceHold releases, use the complete 3D camera-relative
	-- directional vector. This is the head-first behaviour that is already
	-- working correctly: look down + W dives, look up + W climbs, and
	-- combinations with A/D naturally alter the heading.
	if
		directionalSwimDirection.Magnitude
		> SWIM_DIRECTION_DEADZONE
	then

		local desiredHeading =
			directionalSwimDirection.Unit

		local horizontalHeading =
			Vector3.new(
				desiredHeading.X,
				0,
				desiredHeading.Z
			)

		if
			horizontalHeading.Magnitude
			> SWIM_DIRECTION_DEADZONE
		then

			lastSurfaceSwimFacingDirection =
				horizontalHeading.Unit
		end


		orientation.CFrame =
			getProneSwimOrientation(
				desiredHeading
			)

		return
	end


	----------------------------------------------------------------
	-- IDLE UNDERWATER
	----------------------------------------------------------------

	-- Let AlignOrientation smoothly carry the swimmer back to the normal
	-- upright/treading pose when directional movement stops.
	orientation.CFrame =
		getNeutralSwimOrientation()
end


----------------------------------------------------------------
-- SWIM UPDATE
----------------------------------------------------------------

local function updateSwimming(
	dt: number
)
	PlayerWaveMotionState.SurfaceHold = false
	PlayerWaveMotionState.Root = rootPart

	local currentHumanoid =
		humanoid


	local currentRoot =
		rootPart


	if
		not currentHumanoid
		or not currentRoot
		or currentHumanoid.Health <= 0
	then

		-- Don't leave a stray upward force applied to a character
		-- that no longer exists / is dead.
		setBuoyancyEnabled(
			false
		)

		return
	end


	local surfaceY =
		getSurfaceY()

	local rootY =
		currentRoot.Position.Y
	- PlayerWaveMotionState.Offset


	maintainCustomWaterCCLOwnership()


	if
		not bodyInWater
		and not entrySplashArmed
		and rootY >= surfaceY + ENTRY_SPLASH_REARM_HEIGHT
		and currentHumanoid.FloorMaterial ~= Enum.Material.Air
	then
		entrySplashArmed = true
	end


	----------------------------------------------------------------
	-- WATER ENTRY (unchanged - still relative to surfaceY)
	----------------------------------------------------------------

	if not bodyInWater then

		if
			rootY
			< surfaceY
			+ SwimSettings.EnterOffset
		then

			enterSwimming()
		end
	end


	----------------------------------------------------------------
	-- GRADUATED EXIT
	----------------------------------------------------------------

	-- 1 = full swim control, 0 = swimming has fully stopped.
	local swimAlpha =
		getSwimAlpha(
			rootY
		)

	if
		bodyInWater
		and swimAlpha <= 0
	then

		exitSwimming()
	end


	updateSubmergedAttribute(
		surfaceY,
		rootY
	)


	----------------------------------------------------------------
	-- BUOYANCY
	----------------------------------------------------------------

	-- Only relevant while actively swimming, or while coasting out
	-- of the water right after swimming stopped. NOT while merely
	-- falling toward the water from height before ever entering it.
	local applyBuoyancy =
		bodyInWater
		or recentlyExitedWater

	if applyBuoyancy then

		local buoyancyAlpha =
			getBuoyancyAlpha(
				rootY
			)

		if buoyancyAlpha > 0 then

			setBuoyancyEnabled(
				true,
				buoyancyAlpha
			)

		else

			setBuoyancyEnabled(
				false
			)

			-- Fully settled back to vanilla gravity/movement.
			recentlyExitedWater =
				false
		end

	else

		setBuoyancyEnabled(
			false
		)
	end


	if not bodyInWater then
		return
	end


	----------------------------------------------------------------
	-- OMNIDIRECTIONAL MOVEMENT
	----------------------------------------------------------------

	local
	swimDirection,
		directionalSwimDirection,
		surfaceDirectionalSwimDirection =
		getOmnidirectionalSwimDirection()


	-- Horizontal and vertical speeds remain independently tunable.
	--
	-- Therefore:
	--
	-- straight forward:
	--     Speed
	--
	-- straight upward:
	--     VerticalSpeed
	--
	-- diagonal upward:
	--     proportional mixture

	local targetVelocity =
		Vector3.new(

			swimDirection.X
			* SwimSettings.Speed,

			swimDirection.Y
			* SwimSettings.VerticalSpeed,

			swimDirection.Z
			* SwimSettings.Speed
		)


	----------------------------------------------------------------
	-- EXPERIMENTAL SURFACE HOLD
	----------------------------------------------------------------

	-- Space deliberately releases this hold so the character can jump
	-- through the foam. Ctrl or a clear downward camera-relative input
	-- still permits diving below the surface-assist region.
	local descendingFromSurface =
		swimDownHeld
		or swimDirection.Y
		< SURFACE_DESCEND_INPUT_THRESHOLD

	local surfaceHoldActive =
		rootY >= SURFACE_ASSIST_START_Y
		and not swimUpHeld
		and not descendingFromSurface

	-- Wave motion only runs during this controller's surface hold, never
	-- while walking on solid ground, jumping, seated, or deliberately diving.
	PlayerWaveMotionState.SurfaceHold = surfaceHoldActive
		and currentHumanoid.FloorMaterial == Enum.Material.Air
		and not currentHumanoid.Sit
		and not currentHumanoid.PlatformStand


	updateSwimOrientation(
		directionalSwimDirection,
		surfaceDirectionalSwimDirection,
		surfaceHoldActive
	)


	if surfaceHoldActive then
		local verticalError = 0

		if
			rootY < SURFACE_FLOAT_MIN_Y
			or rootY > SURFACE_FLOAT_MAX_Y
		then
			verticalError =
				SURFACE_FLOAT_TARGET_Y
			- rootY
		end

		targetVelocity =
			Vector3.new(
				targetVelocity.X,

				math.clamp(
					verticalError
					* SURFACE_RESTORE_RESPONSE,

					-SURFACE_MAX_RESTORE_SPEED,
					SURFACE_MAX_RESTORE_SPEED
				),

				targetVelocity.Z
			)
	end


	----------------------------------------------------------------
	-- WATER DRAG / ACCELERATION
	----------------------------------------------------------------

	local currentVelocity =
		currentRoot.AssemblyLinearVelocity


	-- Scaling by swimAlpha here is what actually "gives movement
	-- back to the player": as swimAlpha fades toward 0 near
	-- SWIM_STOP_END_Y, our correction toward the forced swim
	-- velocity gets weaker and weaker each frame, so normal
	-- Roblox gravity/momentum increasingly takes over on its own
	-- instead of our override letting go all at once.

	local alpha =
		(
			1
			- math.exp(
				-SwimSettings.Acceleration
				* dt
			)
		)
		* swimAlpha


	local nextVerticalVelocity =
		lerpNumber(
			currentVelocity.Y,
			targetVelocity.Y,
			alpha
		)

	if surfaceHoldActive then
		-- Prevent the controller's own velocity from carrying the root
		-- through either edge of the foam band. This also absorbs entry
		-- momentum before the character reaches the bad visual layer.
		local frameTime =
			math.max(
				dt,
				1 / 240
			)

		local downwardVelocityFloor =
			math.min(
				0,

				(
					SURFACE_FLOAT_MIN_Y
					- rootY
				)
				/ frameTime
			)

		local upwardVelocityCeiling =
			math.max(
				0,

				(
					SURFACE_FLOAT_MAX_Y
					- rootY
				)
				/ frameTime
			)

		nextVerticalVelocity =
			math.clamp(
				nextVerticalVelocity,
				downwardVelocityFloor,
				upwardVelocityCeiling
			)
	end


	currentRoot.AssemblyLinearVelocity =
		Vector3.new(

			lerpNumber(
				currentVelocity.X,
				targetVelocity.X,
				alpha
			),

			nextVerticalVelocity,

			lerpNumber(
				currentVelocity.Z,
				targetVelocity.Z,
				alpha
			)
		)
end


----------------------------------------------------------------
-- CHARACTER CONNECTIONS
----------------------------------------------------------------

if player.Character then

	setupCharacter(
		player.Character
	)
end


player.CharacterAdded:Connect(
	setupCharacter
)


player.CharacterRemoving:Connect(function()
	setCustomWaterAttributes(
		false,
		false
	)

	PlayerWaveMotionState.Root = nil
	PlayerWaveMotionState.SurfaceHold = false
	PlayerWaveMotionState.Offset = 0
	disconnectDefaultSplashSuppression()
	entrySplashSound = nil
	entrySplashArmed = false

	humanoid =
		nil


	rootPart =
		nil


	swimAttachment =
		nil


	buoyancyForce =
		nil


	swimOrientation =
		nil

	humanoidAutoRotateBeforeSwimming =
		nil


	characterModel =
		nil


	controllerManager =
		nil


	airController =
		nil


	groundController =
		nil



	activeControllerBeforeSwimming =
		nil


	airControllerStateBeforeSwimming =
		nil




	bodyInWater =
		false

	recentlyExitedWater =
		false


	unbindSwimControls()
end)


----------------------------------------------------------------
-- LOOP
----------------------------------------------------------------

RunService.Heartbeat:Connect(
	updateSwimming
)
