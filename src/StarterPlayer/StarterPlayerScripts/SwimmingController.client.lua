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
--   * Water entry is unchanged (SwimSettings.EnterOffset + surfaceY).
--   * Exiting is no longer a single boolean threshold. Root-part Y is
--     compared against two absolute-height bands, the same banded-tween
--     approach used on the coastline visual effect:
--
--       8.5 -> 9.0  : swimming itself (forced swim velocity + the
--                     Space/Ctrl controls) fades out and fully stops.
--       8.5 -> 10.0 : buoyancy fades out over a WIDER band than
--                     swimming does, so gravity doesn't snap on the
--                     instant swimming stops - it eases the character
--                     the rest of the way out until 10.0, where
--                     movement is fully back to vanilla Roblox control.
--
--     Both ramps start at the same point (8.5) so there's no seam/pop
--     where one hands off to the other.


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


local WaterConfig =
	require(
		ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterConfig")
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

-- Below this, full swim control (forced velocity + Space/Ctrl) applies.
local SWIM_STOP_START_Y = 8.5

-- Swimming itself is fully stopped by this height.
local SWIM_STOP_END_Y = 9.0

-- Buoyancy keeps gently fading a bit further than swimming does, so
-- the handoff to normal gravity/movement feels eased rather than
-- instant. Fully vanilla by this height.
local BUOYANCY_RELEASE_END_Y = 10.0


----------------------------------------------------------------
-- CHARACTER STATE
----------------------------------------------------------------

local humanoid: Humanoid? =
	nil

local rootPart: BasePart? =
	nil


local swimAttachment: Attachment? =
	nil

local buoyancyForce: VectorForce? =
	nil

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
-- Ramps out over the WIDER band SWIM_STOP_START_Y -> BUOYANCY_RELEASE_END_Y
-- so it stays continuous with getSwimAlpha() at the low end and simply
-- keeps fading a little longer at the top end.
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

		currentHumanoid:ChangeState(
			Enum.HumanoidStateType.Swimming
		)
	end
end


local function exitSwimming()

	if not bodyInWater then
		return
	end


	bodyInWater =
		false

	-- Swimming has stopped, but buoyancy keeps gently fading a bit
	-- further (see BUOYANCY_RELEASE_END_Y) - this flag is what lets
	-- the main loop know that fade is still legitimately in progress.
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

local function getOmnidirectionalSwimDirection(): Vector3

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

		return Vector3.zero
	end


	----------------------------------------------------------------
	-- GET ROBLOX MOVEMENT INPUT
	----------------------------------------------------------------

	-- Humanoid.MoveDirection gives us the player's normal WASD
	-- movement intent in world space.
	--
	-- Roblox normally flattens movement against the ground,
	-- so below we recover how much of that intent represents
	-- forwards/backwards and left/right relative to the camera.

	local moveDirection =
		currentHumanoid.MoveDirection


	----------------------------------------------------------------
	-- CAMERA BASIS
	----------------------------------------------------------------

	local cameraLook =
		camera.CFrame.LookVector


	local cameraRight =
		camera.CFrame.RightVector


	-- Flat camera vectors are used ONLY to determine what WASD
	-- input the player is providing.
	--
	-- Actual swimming uses the full cameraLook afterward.

	local flatForward =
		Vector3.new(
			cameraLook.X,
			0,
			cameraLook.Z
		)


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
	-- EXPLICIT VERTICAL INPUT
	----------------------------------------------------------------

	local verticalAmount =
		0


	if swimUpHeld then
		verticalAmount +=
			1
	end


	if swimDownHeld then
		verticalAmount -=
			1
	end


	----------------------------------------------------------------
	-- BUILD ONE 3D MOVEMENT VECTOR
	----------------------------------------------------------------

	-- W/S:
	-- full camera LookVector
	--
	-- A/D:
	-- horizontal camera RightVector
	--
	-- Space/Ctrl:
	-- global vertical axis

	local desired =
		cameraLook
		* forwardAmount

		+ flatRight
		* rightAmount

		+ Vector3.yAxis
		* verticalAmount


	----------------------------------------------------------------
	-- PREVENT DIAGONAL SPEED BOOST
	----------------------------------------------------------------

	if desired.Magnitude > 1 then

		desired =
			desired.Unit
	end


	return desired
end


----------------------------------------------------------------
-- SWIM UPDATE
----------------------------------------------------------------

local function updateSwimming(
	dt: number
)

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

	local swimDirection =
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


	currentRoot.AssemblyLinearVelocity =
		Vector3.new(

			lerpNumber(
				currentVelocity.X,
				targetVelocity.X,
				alpha
			),

			lerpNumber(
				currentVelocity.Y,
				targetVelocity.Y,
				alpha
			),

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
