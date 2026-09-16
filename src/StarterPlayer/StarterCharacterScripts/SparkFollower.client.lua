-- StarterCharacterScripts > SparkFollower
-- Local Spark companion controller

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local SparkVisuals =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Spark"):WaitForChild("SparkVisuals"))

local player = Players.LocalPlayer
local character = script.Parent

local SPARK_GAMEPLAY_READY_ATTRIBUTE = "SparkGameplayFollowerReady"

player:SetAttribute(SPARK_GAMEPLAY_READY_ATTRIBUTE, false)

local head = character:WaitForChild("Head") :: BasePart
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
local humanoid = character:WaitForChild("Humanoid") :: Humanoid

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------

----------------------------------------------------------------
-- SPARK CAMERA TYPE SETTINGS
----------------------------------------------------------------

-- Zoomed-out Spark home.
-- First-person positioning below is intentionally left untouched.
local HOME_SIDE_LEFT = -1
local HOME_SIDE_RIGHT = 1

-- Spark stays on the RIGHT side for neutral camera/shoulder presentation.
-- Left-side placement is intentionally disabled because the trail crosses too
-- much of the player's view.
local DEFAULT_SHOULDER_HOME_SIDE = HOME_SIDE_RIGHT

-- Local-space homes relative to UpperTorso/Torso.
-- +Z is behind the character.
local SHOULDER_HOME_HORIZONTAL = 1
local SHOULDER_HOME_VERTICAL = 1.35
local SHOULDER_HOME_BEHIND = 0.85

-- Camera-home rules now use actual camera distance in studs.
--
-- Current tuning reference:
--   CameraMinZoomDistance ~= 0.5
--   <= 2 studs           : first-person camera companion
--   >2  -> 15 studs      : physical shoulder
--   >15 -> 30 studs      : free / camera-relative companion
--   >30 studs            : far physical shoulder
--
-- IMPORTANT:
-- CameraMaxZoomDistance only gets a special presentation while CLIMBING.
-- Outside climbing, maximum zoom remains the normal far physical shoulder.
--
-- These numbers are intentionally easy to retune later without rewriting the
-- movement system.
local FIRST_PERSON_MAX_DISTANCE = 2
local CLOSE_SHOULDER_MAX_DISTANCE = 15
local FREE_CAMERA_MAX_DISTANCE = 30

-- Climbing observer is deliberately simple:
-- if the character is climbing AND the camera is genuinely at the configured
-- CameraMaxZoomDistance, Spark flies to the top-right observer position.
--
-- This automatically adapts whether MaxZoom is currently 30, Roblox's default
-- 128, or something else you choose later.
local CLIMB_MAX_ZOOM_DISTANCE_TOLERANCE = 0.5

-- Entry is intentionally more cinematic than ordinary catch-up. After this
-- short window the regular climbing response takes over so Spark can continue
-- tracking camera movement while he watches.
local CLIMB_OBSERVER_ENTRY_SMOOTH_TIME = 0.85
local CLIMB_OBSERVER_ENTRY_SMOOTH_DURATION = 1.15

-- Observer target is truly screen-space. This is what keeps Spark in the
-- top-right regardless of camera pitch, yaw, ladder height, or character motion.
local CLIMB_OBSERVER_SCREEN_X_FRACTION = 0.82
local CLIMB_OBSERVER_SCREEN_Y_FRACTION = 0.18
local CLIMB_OBSERVER_CAMERA_DEPTH = 8

-- During ordinary climbing/free-camera movement, keep the selected target
-- inside a safe viewport rectangle. This is a guard rail only; if the existing
-- target is already safe, it is left completely untouched.
local CLIMB_SCREEN_SAFE_X_FRACTION = 0.06
local CLIMB_SCREEN_SAFE_TOP_FRACTION = 0.10
local CLIMB_SCREEN_SAFE_BOTTOM_FRACTION = 0.10

-- Reserve the upper-left CoreGui/Roblox-pill area as a no-fly zone.
-- The fractional component lets this scale to wider displays.
local CLIMB_ROBLOX_PILL_SAFE_X_PIXELS = 170
local CLIMB_ROBLOX_PILL_SAFE_X_FRACTION = 0.12
local CLIMB_ROBLOX_PILL_SAFE_Y_PIXELS = 70

-- Vertical movement response. The original response solver intentionally
-- measured lateral target movement, so rapid up/down ladder travel could
-- leave Spark behind vertically.
local CLIMB_VERTICAL_FAST_RESPONSE_START_SPEED = 0.75
local CLIMB_VERTICAL_FAST_RESPONSE_FULL_SPEED = 5
local CLIMB_OFFSCREEN_RESPONSE_ALPHA = 1

-- Free-camera climbing starts slightly lower than the ordinary camera-relative
-- target. This gives Spark one stud of vertical headroom before ladder motion
-- starts trying to throw him toward the top of the viewport.
local CLIMB_FREECAM_BASE_WORLD_Y_OFFSET = -1

-- When the character is actually travelling downward, lead Spark even farther
-- down. This is ADDITIONAL to the -1 stud climbing/free-camera baseline.
local CLIMB_DESCENT_EXTRA_WORLD_Y_OFFSET = -2
local CLIMB_DESCENT_MIN_SPEED = 0.35
local CLIMB_DESCENT_FULL_SPEED = 5

-- Downward travel is allowed to be much more aggressive than ordinary follow.
-- This is the actual "catch him before he leaves the screen" behavior.
local CLIMB_DESCENT_FAST_SMOOTH_TIME = 0.025
local CLIMB_DESCENT_FAST_SPEED_THRESHOLD = 1.25

-- Give Spark a brief nose-down presentation while he is actively descending.
local CLIMB_DESCENT_PITCH_DEGREES = -18

-- Temporary diagnostic for Roblox's newer character-controller state
-- attributes. Leave this true while discovering the exact beta-state strings.
local DEBUG_CHARACTER_CONTROLLER_STATE = true

-- Spark is non-collidable, but his resting position should behave
-- as though he occupies a small physical volume.
local SHOULDER_CLEARANCE_RADIUS = 0.65
local SHOULDER_WALL_PADDING = 0.12

-- When the zoom rule changes his home, let him zip decisively toward it.
local SHOULDER_HOME_SWITCH_FAST_DURATION = 0.45
local SHOULDER_HOME_SWITCH_RESPONSE_ALPHA = 0.9

----------------------------------------------------------------
-- CLIMBING SETTINGS
----------------------------------------------------------------

-- While climbing, Spark becomes a camera companion:
-- he stays in the upper-right region of the screen and is allowed
-- to travel outward WITH the camera as the player zooms out.
--
-- This deliberately overrides the normal zoomed-out shoulder rule
-- for as long as ccl_humanoidstate == "Climbing".
-- Climbing framing is anchored to the CHARACTER, then shaped using
-- the camera basis. This means Spark follows the player's actual W/S
-- movement up/down the ladder instead of becoming vertically stuck
-- whenever the camera itself stays still.
--
-- The offsets scale with camera distance so zooming outward still lets
-- Spark travel outward toward the upper-right framing of the screen.
-- Keep Spark deliberately pushed toward the far upper-right while
-- climbing. These restore the more extreme framing you had before.
local CLIMB_HORIZONTAL_DISTANCE_SCALE = 0.55
local CLIMB_VERTICAL_DISTANCE_SCALE = 0.28

local CLIMB_MIN_HORIZONTAL_DISTANCE = 5.5
local CLIMB_MAX_HORIZONTAL_DISTANCE = 16

local CLIMB_MIN_VERTICAL_DISTANCE = 2.4
local CLIMB_MAX_VERTICAL_DISTANCE = 8

-- Pull Spark slightly toward the camera from the player's plane so
-- his wings remain easy to read while he watches the climb.
local CLIMB_TOWARD_CAMERA_OFFSET = 0.75

-- Even with a static camera, Spark should actively follow the player's
-- vertical ladder movement instead of using the relaxed neutral follow.
local CLIMB_MIN_RESPONSE_ALPHA = 0.65

local CLIMB_OBSERVER_CLEARANCE_RADIUS = 0.65
local CLIMB_OBSERVER_WALL_PADDING = 0.15

-- The instant climbing ends, Spark aggressively returns to whatever
-- neutral home is correct at that exact camera distance.
local CLIMB_EXIT_FAST_DURATION = 0.75
local CLIMB_EXIT_RESPONSE_ALPHA = 0.25

-- First-person position relative to the camera.
-- -Z = in front of the camera.
local FIRST_PERSON_OFFSET = Vector3.new(
	6, -- preferred horizontal distance; clamped to the visible screen edge
	1.8, -- slightly above eye level
	-4 -- in front
)

-- Keep Spark's CENTER comfortably inside either edge of the viewport.
-- This fixes both the right-side and mirrored-left-side positions without
-- hard-coding a different offset for every aspect ratio / FOV.
local FIRST_PERSON_SCREEN_EDGE_FRACTION = 0.82

-- TRUE MINIMUM FIRST-PERSON PHYSICAL MODE
--
-- At the actual minimum camera zoom (normally ~0.5 studs), Spark stops
-- behaving like pure camera UI and becomes a small collidable world object.
-- A small tolerance accounts for camera-distance rounding.
local FIRST_PERSON_PHYSICAL_DISTANCE_TOLERANCE = 0.20

-- Spark is still moved by the existing SmoothDamp solver, so use a small
-- spherecast guard to stop that kinematic movement from simply passing
-- through world geometry.
local FIRST_PERSON_PHYSICAL_COLLISION_RADIUS = 0.42
local FIRST_PERSON_PHYSICAL_WALL_PADDING = 0.08

-- If physical Spark gets badly separated from his intended first-person
-- home for a short moment, use the canonical soul materialisation to
-- disappear and reform beside the player instead of flying across the map.
local FIRST_PERSON_RECOVERY_DISTANCE = 12
local FIRST_PERSON_RECOVERY_HOLD_TIME = 0.25
local FIRST_PERSON_RECOVERY_COOLDOWN = 1.25

local SMOOTH_TIME = 0.55
local FAST_CAMERA_SMOOTH_TIME = 0.045

-- First-person Spark keeps the exact same camera-relative target.
-- Adaptive response should react to camera intent, not ordinary zoom depth.
local CAMERA_FAST_RESPONSE_START_DEGREES = 90
local CAMERA_FAST_RESPONSE_FULL_DEGREES = 360

local TARGET_LATERAL_RESPONSE_START_SPEED = 5
local TARGET_LATERAL_RESPONSE_FULL_SPEED = 28

-- Gentle zoom keeps the existing flutter.
-- Aggressive scroll-wheel zoom can override that and catch Spark up fast.
local CAMERA_ZOOM_RESPONSE_START_SPEED = 10
local CAMERA_ZOOM_RESPONSE_FULL_SPEED = 50

-- Distance response is deliberately an emergency catch-up only.
-- This may also help after very large third-person / zoomed-out separations.
local TARGET_DISTANCE_RESPONSE_START = 7
local TARGET_DISTANCE_RESPONSE_FULL = 16

-- Preserve the slower flutter when camera mode / zoom mode changes.
local CAMERA_MODE_TRANSITION_GRACE = 0.75

local MAX_SPEED = nil

----------------------------------------------------------------
-- ANIMATION
----------------------------------------------------------------

local HOVER_ANIMATION_ID = "rbxassetid://110340492323310"

local MIN_ANIMATION_SPEED = 1
local MAX_ANIMATION_SPEED = 3

local ANIMATION_SPEED_DIVISOR = 10
local ANIMATION_SPEED_RESPONSE = 5

----------------------------------------------------------------
-- TRAIL
----------------------------------------------------------------

local TRAIL_START_SPEED = 1.25

----------------------------------------------------------------
-- SPARK PERSONALITY TIMERS
--
-- SparkVisuals owns HOW Spark looks.
-- SparkFollower only decides WHEN a visual behavior should happen.
----------------------------------------------------------------

-- When the player stops moving, Spark is allowed to quietly experiment
-- with his own outer shell: body colour, wing colour, body emission, and
-- Brick/MaterialVariant <-> Neon form. Movement returns him to the exact
-- Studio-authored neutral gold state.
local SPARK_IDLE_VISUAL_DELAY = 3.5
local SPARK_IDLE_RETURN_DURATION = 0.22
local SPARK_IDLE_MOVE_DIRECTION_THRESHOLD = 0.05

-- Illuminate mode wins whenever the player is actively using the camera.
-- Idle transformations are only allowed when BOTH character and camera are calm.
local SPARK_IDLE_CAMERA_ANGULAR_SPEED_THRESHOLD = 1.5
local SPARK_IDLE_CAMERA_ZOOM_SPEED_THRESHOLD = 0.05

----------------------------------------------------------------
-- SPARK LOOK / FOCUS SETTINGS
----------------------------------------------------------------

-- How far Spark can detect what the player is looking at.
local LOOK_DISTANCE = 100

-- How long the player has to keep looking at something
-- before Spark decides to investigate it.
local LOOK_DWELL_TIME = 0.35

-- How far above the target model Spark hovers.
local TARGET_HOVER_HEIGHT = 1

----------------------------------------------------------------
-- TRUE FIRST-PERSON CAMERA STATE
----------------------------------------------------------------

local FIRST_PERSON_ATTRIBUTE = "TrueFirstPersonActive"

local isFirstPerson = player:GetAttribute(FIRST_PERSON_ATTRIBUTE) == true
local lastCameraModeChangeTime = os.clock()

local zoomedOutShoulderMode = false
local closeShoulderMode = false
local lastShoulderHomeModeChangeTime = os.clock()

local firstPersonConnection = player:GetAttributeChangedSignal(FIRST_PERSON_ATTRIBUTE):Connect(function()
	isFirstPerson = player:GetAttribute(FIRST_PERSON_ATTRIBUTE) == true
	lastCameraModeChangeTime = os.clock()
end)

local FirstPersonReturnFacing = {
	Flipped = false,
	MinimumMovementSpeed = 1.5,
	MinimumCatchupDistance = 0.85,
	EnterDot = -0.15,
	ExitDot = 0.05,
}

----------------------------------------------------------------
-- CHARACTER LOCOMOTION STATE
----------------------------------------------------------------

local HUMANOID_STATE_ATTRIBUTE = "ccl_humanoidstate"

local currentCharacterControllerState = humanoid:GetAttribute(HUMANOID_STATE_ATTRIBUTE)

local lastClimbStateChangeTime = os.clock()
local climbStateChanged = false

-- Full-zoom ladder observer is a latched presentation state. It is deliberately
-- separate from the raw climbing attribute so a tiny zoom wobble does not make
-- Spark bounce between the shoulder and observer position.
local climbObserverMode = false
local lastClimbObserverModeChangeTime = -math.huge

-- Actual physical character motion, measured from RootPart position rather
-- than input intent. This is much more reliable with the new beta controller.
local previousCharacterWorldPosition: Vector3? = rootPart.Position
local currentCharacterWorldSpeed = 0
local currentCharacterVerticalSpeed = 0
local currentCharacterVerticalVelocityY = 0

local function controllerStateLooksLikeClimbing(stateValue: any): boolean
	if typeof(stateValue) ~= "string" then
		return false
	end

	-- The current beta controller has exposed values such as "Climbing", but
	-- use a case-insensitive contains check while the debug listener is enabled
	-- so small naming changes do not silently break Spark's behavior.
	return string.find(string.lower(stateValue), "climb", 1, true) ~= nil
end

local function isCharacterClimbing(): boolean
	local humanoidState = humanoid:GetState()

	return controllerStateLooksLikeClimbing(currentCharacterControllerState)
		or humanoidState == Enum.HumanoidStateType.Climbing
end

local function updateCharacterWorldMotion(dt: number)
	local currentPosition = rootPart.Position

	local previousPosition = previousCharacterWorldPosition

	previousCharacterWorldPosition = currentPosition

	if previousPosition == nil or dt <= 0 then
		currentCharacterWorldSpeed = 0
		currentCharacterVerticalSpeed = 0
		currentCharacterVerticalVelocityY = 0
		return
	end

	local worldDelta = currentPosition - previousPosition

	currentCharacterWorldSpeed = worldDelta.Magnitude / dt

	currentCharacterVerticalVelocityY = worldDelta.Y / dt

	currentCharacterVerticalSpeed = math.abs(currentCharacterVerticalVelocityY)
end

local function debugCharacterControllerState(reason: string)
	if not DEBUG_CHARACTER_CONTROLLER_STATE then
		return
	end

	print(
		"[SparkFollower][CharacterControllerState]",
		reason,
		HUMANOID_STATE_ATTRIBUTE .. " =",
		tostring(currentCharacterControllerState),
		"| Humanoid:GetState() =",
		humanoid:GetState().Name,
		"| MoveDirection =",
		humanoid.MoveDirection
	)
end

local humanoidStateConnection = humanoid:GetAttributeChangedSignal(HUMANOID_STATE_ATTRIBUTE):Connect(function()
	local wasClimbing = controllerStateLooksLikeClimbing(currentCharacterControllerState)

	currentCharacterControllerState = humanoid:GetAttribute(HUMANOID_STATE_ATTRIBUTE)

	local isNowClimbing = controllerStateLooksLikeClimbing(currentCharacterControllerState)

	debugCharacterControllerState("attribute changed")

	if wasClimbing ~= isNowClimbing then
		lastClimbStateChangeTime = os.clock()
		climbStateChanged = true
	end
end)

-- While the new controller stack is still evolving, also report any other
-- Humanoid attribute that looks related to CCL/controller state. This is only
-- diagnostic and does not drive gameplay behavior.
local humanoidAttributeDebugConnection: RBXScriptConnection? = nil

if DEBUG_CHARACTER_CONTROLLER_STATE then
	humanoidAttributeDebugConnection = humanoid.AttributeChanged:Connect(function(attributeName: string)
		if attributeName == HUMANOID_STATE_ATTRIBUTE then
			return
		end

		local lowerName = string.lower(attributeName)

		if
			string.find(lowerName, "ccl", 1, true)
			or string.find(lowerName, "state", 1, true)
			or string.find(lowerName, "controller", 1, true)
		then
			print(
				"[SparkFollower][HumanoidAttributeDebug]",
				attributeName,
				"=",
				tostring(humanoid:GetAttribute(attributeName))
			)
		end
	end)

	task.defer(function()
		debugCharacterControllerState("initial")
	end)
end

----------------------------------------------------------------
-- CODEX STATE MARKERS
----------------------------------------------------------------
-- CODEX_STATE_MARKER: CLIMBING
-- Implemented now through Humanoid attribute:
-- ccl_humanoidstate == "Climbing"
-- Climbing keeps Spark on the normal zoom-home rules until the player is
-- while climbing, reaching the configured CameraMaxZoomDistance immediately
-- moves Spark to the true top-right screen-space observer perch. Zooming in
-- or leaving climbing immediately returns control to the normal resolver.
--
-- CODEX_STATE_MARKER: SWIMMING
-- FUTURE: Spark water / buoyancy behaviour.
-- Confirm the exact ccl_humanoidstate string before implementing.
--
-- CODEX_STATE_MARKER: CROUCHING
-- FUTURE: lower Spark's home and prepare stealth presentation.
-- Confirm the exact ccl_humanoidstate string before implementing.
--
-- CODEX_STATE_MARKER: CRAWLING
-- FUTURE: close/low-behind placement with strict geometry clearance.
-- Confirm the exact ccl_humanoidstate string before implementing.
--
-- CODEX_STATE_MARKER: JUMPING_FALLING
-- FUTURE: optional personality response only; do not disturb core follow.
-- Confirm exact state strings before implementing.
--
-- CODEX_STATE_MARKER: SEATED_VEHICLE
-- FUTURE: vehicle-specific follow behaviour inspired by old fairy code.
-- Do not infer vehicle mode from camera distance alone.
--
-- CODEX_STATE_MARKER: STEALTH
-- FUTURE: likely a gameplay/status state rather than locomotion only.
-- Keep this separate from ccl_humanoidstate unless the controller exposes
-- a confirmed stealth/crouch state.
--
-- CODEX_STATE_MARKER: PERSONALITY
-- FUTURE: personality may choose HomeLeft/HomeRight or temporary perches,
-- but must yield to explicit focus, locomotion, safety, and scripted states.
----------------------------------------------------------------

----------------------------------------------------------------
-- GET SPARK
----------------------------------------------------------------

local sparkModels = ReplicatedStorage:WaitForChild("Models"):WaitForChild("NPCs"):WaitForChild("SparkModels")

local sparkTemplate = sparkModels:WaitForChild("Spark")

assert(sparkTemplate:IsA("Model"), "ReplicatedStorage.Models.NPCs.SparkModels.Spark must be a Model")

local spark = sparkTemplate:Clone()
spark.Name = player.Name .. "'s Spark"
spark:ScaleTo(0.5)
spark.Parent = workspace

----------------------------------------------------------------
-- CINEMATIC HANDOFF VISIBILITY
----------------------------------------------------------------

local SPARK_CAMERA_HANDOFF_EVENT_NAME = "SparkCameraHandoff"

local sparkGameplayVisible = false

local sparkEffectEnabledStates: { [Instance]: boolean } = {}

for _, object in spark:GetDescendants() do
	if object:IsA("BasePart") then
		object.LocalTransparencyModifier = 1
	elseif object:IsA("Light") or object:IsA("ParticleEmitter") or object:IsA("Beam") or object:IsA("Trail") then
		sparkEffectEnabledStates[object] = object.Enabled
		object.Enabled = false
	end
end

local existingSparkCameraHandoffEvent = ReplicatedStorage:FindFirstChild(SPARK_CAMERA_HANDOFF_EVENT_NAME)

local sparkCameraHandoffEvent: BindableEvent

if existingSparkCameraHandoffEvent and existingSparkCameraHandoffEvent:IsA("BindableEvent") then
	sparkCameraHandoffEvent = existingSparkCameraHandoffEvent
else
	if existingSparkCameraHandoffEvent then
		existingSparkCameraHandoffEvent:Destroy()
	end

	sparkCameraHandoffEvent = Instance.new("BindableEvent")
	sparkCameraHandoffEvent.Name = SPARK_CAMERA_HANDOFF_EVENT_NAME
	sparkCameraHandoffEvent.Parent = ReplicatedStorage
end

----------------------------------------------------------------
-- SPARK FOCUS / LOOK TARGETING
----------------------------------------------------------------

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = {
	character,
	spark,
}
raycastParams.IgnoreWater = true

local lookedAtModel: Model? = nil
local lookedAtSince = 0

local focusedModel: Model? = nil

local function findSlimeAncestor(instance: Instance?): Model?
	while instance and instance ~= workspace do
		if instance:IsA("Model") and instance.Name == "Slime" then
			return instance
		end

		instance = instance.Parent
	end

	return nil
end

----------------------------------------------------------------
-- HELPER FUNCTIONS
----------------------------------------------------------------

local function getLookedAtSlime(): Model?
	local camera = workspace.CurrentCamera

	if not camera then
		return nil
	end

	local viewportSize = camera.ViewportSize

	local ray = camera:ViewportPointToRay(viewportSize.X * 0.5, viewportSize.Y * 0.5)

	local result = workspace:Raycast(ray.Origin, ray.Direction * LOOK_DISTANCE, raycastParams)

	if not result then
		return nil
	end

	return findSlimeAncestor(result.Instance)
end

local function updateSparkFocus()
	local slime = getLookedAtSlime()

	if slime ~= lookedAtModel then
		lookedAtModel = slime
		lookedAtSince = os.clock()
	end

	if slime then
		if os.clock() - lookedAtSince >= LOOK_DWELL_TIME then
			focusedModel = slime
		end
	else
		focusedModel = nil
	end
end

local function getFocusedTargetCFrame(): CFrame?
	if not focusedModel or not focusedModel.Parent then
		focusedModel = nil
		return nil
	end

	local pivot, size = focusedModel:GetBoundingBox()

	local position = pivot.Position + Vector3.new(0, size.Y * 0.5 + TARGET_HOVER_HEIGHT, 0)

	return CFrame.new(position)
end

----------------------------------------------------------------
-- PREPARE RIG
----------------------------------------------------------------

local body = spark:FindFirstChild("SparkBody", true)

assert(body and body:IsA("BasePart"), "Spark requires a BasePart named SparkBody")

-- Body carries the imported Motor6D rig.
for _, object in spark:GetDescendants() do
	if object:IsA("BasePart") then
		object.Anchored = false
		object.CanCollide = false
		object.CanTouch = false
		object.CanQuery = false
		object.CastShadow = false
		object.Massless = true
	end
end

body.Anchored = true

----------------------------------------------------------------
-- TRUE MINIMUM FIRST-PERSON PHYSICAL BODY
----------------------------------------------------------------

local firstPersonPhysicalModeActive = false
local firstPersonRecoveryFarSince: number? = nil
local firstPersonRecoveryActive = false
local lastFirstPersonRecoveryTime = -math.huge

-- Only SparkBody becomes collidable. Wings / visual rig parts remain
-- non-collidable exactly as before.
body.CanCollide = false

-- Spark may collide with the world in true first person, but never with
-- the player's own character. NoCollisionConstraint is local and does not
-- disturb the character's existing collision groups.
local firstPersonCharacterNoCollisionFolder = Instance.new("Folder")

firstPersonCharacterNoCollisionFolder.Name = "FirstPersonCharacterNoCollision"

firstPersonCharacterNoCollisionFolder.Parent = spark

for _, characterObject in character:GetDescendants() do
	if characterObject:IsA("BasePart") then
		local noCollisionConstraint = Instance.new("NoCollisionConstraint")

		noCollisionConstraint.Part0 = body
		noCollisionConstraint.Part1 = characterObject
		noCollisionConstraint.Parent = firstPersonCharacterNoCollisionFolder
	end
end

----------------------------------------------------------------
-- CANONICAL SPARK VISUALS
--
-- One source of truth for:
-- body colour / material
-- wing SurfaceAppearance
-- PointLight
-- soul particles
-- trail
-- dissolve / reform language
----------------------------------------------------------------

local sparkVisuals = SparkVisuals.new(spark)

-- Gameplay Spark is hidden until the cinematic handoff.
-- SparkVisuals creates the canonical ambient soul emitter immediately,
-- so explicitly keep it off until that handoff occurs.
sparkVisuals:SetAmbientEnabled(false)

----------------------------------------------------------------
-- ANIMATION CONTROLLER
----------------------------------------------------------------

local animationController = spark:FindFirstChildOfClass("AnimationController")

if not animationController then
	animationController = Instance.new("AnimationController")
	animationController.Name = "AnimationController"
	animationController.Parent = spark
end

local animator = animationController:FindFirstChildOfClass("Animator")

if not animator then
	animator = Instance.new("Animator")
	animator.Parent = animationController
end

local hoverAnimation = Instance.new("Animation")
hoverAnimation.Name = "Hover"
hoverAnimation.AnimationId = HOVER_ANIMATION_ID

local hoverTrack = animator:LoadAnimation(hoverAnimation)

hoverTrack.Looped = true
hoverTrack.Priority = Enum.AnimationPriority.Idle
hoverTrack:Play(0)

local currentAnimationSpeed = 1

----------------------------------------------------------------
-- CINEMATIC HANDOFF -> RUNTIME VISUALS
----------------------------------------------------------------

local sparkCameraHandoffConnection = sparkCameraHandoffEvent.Event:Connect(function()
	sparkGameplayVisible = true

	-- Restore only the effects that existed on the original Spark model
	-- before SparkVisuals was constructed.
	for _, object in spark:GetDescendants() do
		if object:IsA("BasePart") then
			object.LocalTransparencyModifier = 0
		elseif object:IsA("Light") or object:IsA("ParticleEmitter") or object:IsA("Beam") then
			local wasEnabled = sparkEffectEnabledStates[object]

			if wasEnabled ~= nil then
				object.Enabled = wasEnabled
			end
		end
	end

	-- SparkVisuals owns this canonical emitter; it was created after
	-- the hidden-effect snapshot above.
	sparkVisuals:SetAmbientEnabled(true)
end)

-- The camera transition may now safely fire SparkCameraHandoff: the gameplay
-- clone, canonical visuals and handoff listener all exist.
player:SetAttribute(SPARK_GAMEPLAY_READY_ATTRIBUTE, true)

----------------------------------------------------------------
-- SHOULDER HOME / PLACEMENT RESOLVER
----------------------------------------------------------------

local shoulderAnchorPart = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or rootPart

assert(
	shoulderAnchorPart and shoulderAnchorPart:IsA("BasePart"),
	"Spark requires UpperTorso, Torso, or HumanoidRootPart for shoulder homes"
)

local function getOrCreateShoulderHomeAttachment(name: string, side: number): Attachment
	local existing = shoulderAnchorPart:FindFirstChild(name)

	if existing and existing:IsA("Attachment") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = Vector3.new(SHOULDER_HOME_HORIZONTAL * side, SHOULDER_HOME_VERTICAL, SHOULDER_HOME_BEHIND)
	attachment.Parent = shoulderAnchorPart

	return attachment
end

local shoulderHomeLeft = getOrCreateShoulderHomeAttachment("SparkHomeLeft", HOME_SIDE_LEFT)

local shoulderHomeRight = getOrCreateShoulderHomeAttachment("SparkHomeRight", HOME_SIDE_RIGHT)

local shoulderOverlapParams = OverlapParams.new()

shoulderOverlapParams.FilterType = Enum.RaycastFilterType.Exclude

shoulderOverlapParams.FilterDescendantsInstances = {
	character,
	spark,
}

local shoulderRaycastParams = RaycastParams.new()

shoulderRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

shoulderRaycastParams.FilterDescendantsInstances = {
	character,
	spark,
}

shoulderRaycastParams.IgnoreWater = true

local firstPersonPhysicalRaycastParams = RaycastParams.new()

firstPersonPhysicalRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

firstPersonPhysicalRaycastParams.FilterDescendantsInstances = {
	character,
	spark,
}

firstPersonPhysicalRaycastParams.IgnoreWater = true

local function resolveFirstPersonPhysicalMovement(previousPosition: Vector3, proposedCFrame: CFrame): CFrame
	if not firstPersonPhysicalModeActive then
		return proposedCFrame
	end

	local movement = proposedCFrame.Position - previousPosition

	if movement.Magnitude <= 0.001 then
		return proposedCFrame
	end

	local result = workspace:Spherecast(
		previousPosition,
		FIRST_PERSON_PHYSICAL_COLLISION_RADIUS,
		movement,
		firstPersonPhysicalRaycastParams
	)

	if not result then
		return proposedCFrame
	end

	local safePosition = result.Position
		+ result.Normal * (FIRST_PERSON_PHYSICAL_COLLISION_RADIUS + FIRST_PERSON_PHYSICAL_WALL_PADDING)

	return CFrame.new(safePosition) * proposedCFrame.Rotation
end

local function getShoulderHomeAttachment(side: number): Attachment
	if side == HOME_SIDE_LEFT then
		return shoulderHomeLeft
	end

	return shoulderHomeRight
end

local function isShoulderPositionClear(position: Vector3): boolean
	local nearbyParts = workspace:GetPartBoundsInRadius(position, SHOULDER_CLEARANCE_RADIUS, shoulderOverlapParams)

	for _, nearbyPart in nearbyParts do
		if nearbyPart:IsA("BasePart") and nearbyPart.CanCollide then
			return false
		end
	end

	return true
end

local function isShoulderPositionVisible(position: Vector3): boolean
	local camera = workspace.CurrentCamera

	if not camera then
		return true
	end

	local viewportPoint, onScreen = camera:WorldToViewportPoint(position)

	if not onScreen or viewportPoint.Z <= 0 then
		return false
	end

	local direction = position - camera.CFrame.Position

	if direction.Magnitude <= 0.001 then
		return true
	end

	local hit = workspace:Raycast(camera.CFrame.Position, direction, shoulderRaycastParams)

	return hit == nil
end

local function clampShoulderPositionAgainstWorld(preferredPosition: Vector3): Vector3
	local origin = head.Position

	local direction = preferredPosition - origin

	if direction.Magnitude <= 0.001 then
		return preferredPosition
	end

	local result = workspace:Spherecast(origin, SHOULDER_CLEARANCE_RADIUS, direction, shoulderRaycastParams)

	if not result then
		return preferredPosition
	end

	return result.Position + result.Normal * (SHOULDER_CLEARANCE_RADIUS + SHOULDER_WALL_PADDING)
end

local function getClearShoulderPosition(preferredSide: number): Vector3?
	local preferredAttachment = getShoulderHomeAttachment(preferredSide)

	local preferredPosition = preferredAttachment.WorldPosition

	if isShoulderPositionClear(preferredPosition) and isShoulderPositionVisible(preferredPosition) then
		return preferredPosition
	end

	-- Right-side-only presentation:
	-- never silently fall back to the opposite shoulder. If the preferred
	-- right-side home is obstructed, return nil and let the existing world
	-- clamp keep Spark near that same preferred side.
	return nil
end

local function getResolvedShoulderPosition(preferredSide: number): Vector3
	local clearShoulderPosition = getClearShoulderPosition(preferredSide)

	if clearShoulderPosition then
		return clearShoulderPosition
	end

	local preferredAttachment = getShoulderHomeAttachment(preferredSide)

	-- Both homes are compromised. Keep Spark physically near the
	-- shoulder region, but push the preferred position out of geometry.
	return clampShoulderPositionAgainstWorld(preferredAttachment.WorldPosition)
end

local function resolveCameraObserverPosition(preferredPosition: Vector3): Vector3
	local camera = workspace.CurrentCamera

	if not camera then
		return preferredPosition
	end

	local direction = preferredPosition - camera.CFrame.Position

	if direction.Magnitude <= 0.001 then
		return preferredPosition
	end

	local result =
		workspace:Spherecast(camera.CFrame.Position, CLIMB_OBSERVER_CLEARANCE_RADIUS, direction, shoulderRaycastParams)

	if not result then
		return preferredPosition
	end

	local safeDistance = math.max(result.Distance - CLIMB_OBSERVER_CLEARANCE_RADIUS - CLIMB_OBSERVER_WALL_PADDING, 0.5)

	return camera.CFrame.Position + direction.Unit * safeDistance
end

local function getCameraDistanceFromCharacter(): number
	local camera = workspace.CurrentCamera

	if not camera then
		return 0
	end

	return (camera.CFrame.Position - head.Position).Magnitude
end

local function getCameraZoomPercent(cameraDistance: number): number
	local minimumZoomDistance = player.CameraMinZoomDistance

	local maximumZoomDistance = player.CameraMaxZoomDistance

	local zoomRange = maximumZoomDistance - minimumZoomDistance

	if zoomRange <= 0.001 then
		return 1
	end

	return math.clamp((cameraDistance - minimumZoomDistance) / zoomRange, 0, 1)
end

local function isCameraActuallyFirstPerson(cameraDistance: number): boolean
	return cameraDistance <= FIRST_PERSON_MAX_DISTANCE
end

local function isCameraAtMaximumZoom(cameraDistance: number): boolean
	local camera = workspace.CurrentCamera

	local maximumZoomDistance = player.CameraMaxZoomDistance

	local maximumZoomThreshold = maximumZoomDistance - CLIMB_MAX_ZOOM_DISTANCE_TOLERANCE

	if camera then
		local actualCameraZoomDistance = (camera.CFrame.Position - camera.Focus.Position).Magnitude

		if actualCameraZoomDistance >= maximumZoomThreshold then
			return true
		end
	end

	-- Fallback for custom-camera frames where Focus may be in transition.
	return cameraDistance >= maximumZoomThreshold
end

local function isTrueMinimumFirstPerson(cameraDistance: number): boolean
	return cameraDistance <= player.CameraMinZoomDistance + FIRST_PERSON_PHYSICAL_DISTANCE_TOLERANCE
end

local function updateFirstPersonPhysicalMode(cameraDistance: number)
	local shouldBePhysical = sparkGameplayVisible and isTrueMinimumFirstPerson(cameraDistance)

	if firstPersonPhysicalModeActive == shouldBePhysical then
		return
	end

	firstPersonPhysicalModeActive = shouldBePhysical

	body.CanCollide = firstPersonPhysicalModeActive

	if not firstPersonPhysicalModeActive then
		firstPersonRecoveryFarSince = nil
	end
end

local function updateCloseShoulderMode(cameraDistance: number): boolean
	local previousMode = closeShoulderMode

	closeShoulderMode = cameraDistance > FIRST_PERSON_MAX_DISTANCE and cameraDistance <= CLOSE_SHOULDER_MAX_DISTANCE

	if previousMode ~= closeShoulderMode then
		lastShoulderHomeModeChangeTime = os.clock()

		return true
	end

	return false
end

local function updateZoomedOutShoulderMode(cameraDistance: number): boolean
	local previousMode = zoomedOutShoulderMode

	-- 15-30 studs is the free-camera band.
	-- Anything beyond 30 returns Spark to the physical shoulder.
	zoomedOutShoulderMode = cameraDistance > FREE_CAMERA_MAX_DISTANCE

	if previousMode ~= zoomedOutShoulderMode then
		lastShoulderHomeModeChangeTime = os.clock()

		return true
	end

	return false
end

local function updateClimbObserverMode(cameraDistance: number): boolean
	local previousMode = climbObserverMode

	-- Re-enable the existing top-right climbing observer ONLY when:
	--   1) the character is actually climbing, and
	--   2) the camera is genuinely at its configured maximum zoom.
	--
	-- isCameraAtMaximumZoom() reads player.CameraMaxZoomDistance every frame,
	-- so this follows whatever max zoom the game/player is currently configured for.
	-- The helper includes a tiny tolerance for Roblox camera-distance rounding.
	climbObserverMode = isCharacterClimbing() and isCameraAtMaximumZoom(cameraDistance)

	if previousMode ~= climbObserverMode then
		lastClimbObserverModeChangeTime = os.clock()

		-- Entering observer is its own authored travel transition.
		-- Exiting observer should NOT inherit the aggressive shoulder-switch
		-- response, otherwise Spark snaps violently back across the view.
		if climbObserverMode then
			lastShoulderHomeModeChangeTime = os.clock()
		end

		if DEBUG_CHARACTER_CONTROLLER_STATE then
			local camera = workspace.CurrentCamera

			local actualZoomDistance = if camera
				then (camera.CFrame.Position - camera.Focus.Position).Magnitude
				else cameraDistance

			print(
				"[SparkFollower][ClimbObserver]",
				if climbObserverMode then "ENTER" else "EXIT",
				"| ccl =",
				tostring(currentCharacterControllerState),
				"| humanoid =",
				humanoid:GetState().Name,
				"| zoom =",
				actualZoomDistance,
				"| max =",
				player.CameraMaxZoomDistance
			)
		end

		return true
	end

	return false
end

----------------------------------------------------------------
-- CLIMBING SCREEN-SAFETY
--
-- The existing camera/home resolver remains authoritative. These helpers only
-- intervene when climbing would otherwise place Spark outside the viewport or
-- underneath the Roblox pill.
----------------------------------------------------------------

local function getClimbingScreenBounds()
	local camera = workspace.CurrentCamera

	if not camera then
		return nil
	end

	local viewportSize = camera.ViewportSize

	local topLeftInset = select(1, GuiService:GetGuiInset())

	local minX = math.max(viewportSize.X * CLIMB_SCREEN_SAFE_X_FRACTION, 8)

	local maxX = viewportSize.X - minX

	local minY = math.max(viewportSize.Y * CLIMB_SCREEN_SAFE_TOP_FRACTION, topLeftInset.Y + 8)

	local maxY = viewportSize.Y - math.max(viewportSize.Y * CLIMB_SCREEN_SAFE_BOTTOM_FRACTION, 8)

	local pillSafeX = math.max(CLIMB_ROBLOX_PILL_SAFE_X_PIXELS, viewportSize.X * CLIMB_ROBLOX_PILL_SAFE_X_FRACTION)

	local pillSafeY = math.max(CLIMB_ROBLOX_PILL_SAFE_Y_PIXELS, topLeftInset.Y + 34)

	return {
		ViewportSize = viewportSize,
		MinX = minX,
		MaxX = maxX,
		MinY = minY,
		MaxY = maxY,
		PillSafeX = pillSafeX,
		PillSafeY = pillSafeY,
	}
end

local function isViewportPointClimbSafe(viewportPoint: Vector3): boolean
	local bounds = getClimbingScreenBounds()

	if not bounds or viewportPoint.Z <= 0 then
		return false
	end

	if
		viewportPoint.X < bounds.MinX
		or viewportPoint.X > bounds.MaxX
		or viewportPoint.Y < bounds.MinY
		or viewportPoint.Y > bounds.MaxY
	then
		return false
	end

	-- Avoid the Roblox/CoreGui pill specifically.
	if viewportPoint.X < bounds.PillSafeX and viewportPoint.Y < bounds.PillSafeY then
		return false
	end

	return true
end

local function resolveClimbingScreenSafeCFrame(preferredCFrame: CFrame): CFrame
	local camera = workspace.CurrentCamera
	local bounds = getClimbingScreenBounds()

	if not camera or not bounds then
		return preferredCFrame
	end

	local viewportPoint = camera:WorldToViewportPoint(preferredCFrame.Position)

	if isViewportPointClimbSafe(viewportPoint) then
		return preferredCFrame
	end

	local clampedX = math.clamp(viewportPoint.X, bounds.MinX, bounds.MaxX)

	local clampedY = math.clamp(viewportPoint.Y, bounds.MinY, bounds.MaxY)

	-- If the target is in the top-left CoreGui region, push it horizontally
	-- clear of the Roblox pill instead of merely clamping to the left margin.
	if clampedX < bounds.PillSafeX and clampedY < bounds.PillSafeY then
		clampedX = bounds.PillSafeX
	end

	local targetDepth = math.max((preferredCFrame.Position - camera.CFrame.Position):Dot(camera.CFrame.LookVector), 4)

	local screenRay = camera:ViewportPointToRay(clampedX, clampedY)

	local rayForwardDot = math.max(screenRay.Direction:Dot(camera.CFrame.LookVector), 0.15)

	local correctedDistance = targetDepth / rayForwardDot

	local correctedPosition = screenRay.Origin + screenRay.Direction * correctedDistance

	return CFrame.new(correctedPosition) * preferredCFrame.Rotation
end

local function getResponseAlpha(value: number, startValue: number, fullValue: number): number
	if fullValue <= startValue then
		return 1
	end

	return math.clamp((value - startValue) / (fullValue - startValue), 0, 1)
end

local function applyClimbingFreeCameraVerticalBias(targetCFrame: CFrame, cameraDistance: number): CFrame
	if not isCharacterClimbing() or climbObserverMode then
		return targetCFrame
	end

	-- Only bias the middle/free-camera climbing band.
	-- Shoulder and first-person homes keep their authored positions.
	if cameraDistance <= CLOSE_SHOULDER_MAX_DISTANCE or cameraDistance > FREE_CAMERA_MAX_DISTANCE then
		return targetCFrame
	end

	local downwardSpeed = math.max(0, -currentCharacterVerticalVelocityY)

	local descentAlpha = getResponseAlpha(downwardSpeed, CLIMB_DESCENT_MIN_SPEED, CLIMB_DESCENT_FULL_SPEED)

	local verticalOffset = CLIMB_FREECAM_BASE_WORLD_Y_OFFSET + (CLIMB_DESCENT_EXTRA_WORLD_Y_OFFSET * descentAlpha)

	local adjustedPosition = targetCFrame.Position + Vector3.new(0, verticalOffset, 0)

	local descentPitch = math.rad(CLIMB_DESCENT_PITCH_DEGREES * descentAlpha)

	return CFrame.new(adjustedPosition) * targetCFrame.Rotation * CFrame.Angles(descentPitch, 0, 0)
end

local function isSparkOutsideClimbingSafeScreen(sparkCFrame: CFrame): boolean
	local camera = workspace.CurrentCamera

	if not camera then
		return false
	end

	local viewportPoint = camera:WorldToViewportPoint(sparkCFrame.Position)

	return not isViewportPointClimbSafe(viewportPoint)
end

----------------------------------------------------------------
-- TARGET CFRAMES
----------------------------------------------------------------

local function getFirstPersonTargetCFrame(): CFrame
	local camera = workspace.CurrentCamera

	if not camera then
		return rootPart.CFrame
	end

	local viewportSize = camera.ViewportSize

	local horizontalOffset = math.abs(FIRST_PERSON_OFFSET.X)

	if viewportSize.Y > 0 then
		local aspectRatio = viewportSize.X / viewportSize.Y

		local depth = math.max(math.abs(FIRST_PERSON_OFFSET.Z), 0.01)

		local halfVisibleWidthAtDepth = math.tan(math.rad(camera.FieldOfView) * 0.5) * depth * aspectRatio

		local safeHorizontalOffset = halfVisibleWidthAtDepth * FIRST_PERSON_SCREEN_EDGE_FRACTION

		horizontalOffset = math.min(horizontalOffset, safeHorizontalOffset)
	end

	local firstPersonOffset =
		Vector3.new(horizontalOffset * HOME_SIDE_RIGHT, FIRST_PERSON_OFFSET.Y, FIRST_PERSON_OFFSET.Z)

	local position = camera.CFrame:PointToWorldSpace(firstPersonOffset)

	return CFrame.new(position) * camera.CFrame.Rotation
end

local function getShoulderTargetCFrame(): CFrame
	local camera = workspace.CurrentCamera

	local position = getResolvedShoulderPosition(HOME_SIDE_RIGHT)

	-- Keep Spark visually parallel with the camera while he flies
	-- into the shoulder home. This prevents his wings presenting
	-- at strange world-space angles during catch-up.
	if camera then
		return CFrame.new(position) * camera.CFrame.Rotation
	end

	return CFrame.new(position) * rootPart.CFrame.Rotation
end

local function getClimbingTargetCFrame(): CFrame
	local camera = workspace.CurrentCamera

	if not camera then
		return getShoulderTargetCFrame()
	end

	local viewportSize = camera.ViewportSize

	local topLeftInset = select(1, GuiService:GetGuiInset())

	-- Observer mode is a SCREEN position, not a character-relative world offset.
	-- That is what makes it stable at every camera angle and ladder height.
	local observerScreenX = viewportSize.X * CLIMB_OBSERVER_SCREEN_X_FRACTION

	local observerScreenY = math.max(viewportSize.Y * CLIMB_OBSERVER_SCREEN_Y_FRACTION, topLeftInset.Y + 42)

	local observerRay = camera:ViewportPointToRay(observerScreenX, observerScreenY)

	local preferredObserverPosition = observerRay.Origin + observerRay.Direction * CLIMB_OBSERVER_CAMERA_DEPTH

	local resolvedObserverPosition = resolveCameraObserverPosition(preferredObserverPosition)

	local watchPosition = head.Position + Vector3.new(0, 0.35, 0)

	return CFrame.lookAt(resolvedObserverPosition, watchPosition, camera.CFrame.UpVector)
end

local function getTargetCFrame(): CFrame
	-- Climbing at the actual configured CameraMaxZoomDistance is a hard
	-- presentation state. Spark belongs in the top-right observer perch and
	-- ordinary look/focus targeting is not allowed to pull him away.
	if climbObserverMode then
		return getClimbingTargetCFrame()
	end

	local focusCFrame = getFocusedTargetCFrame()

	if focusCFrame then
		return focusCFrame
	end

	-- CODEX_STATE_MARKER: FUTURE_LOCOMOTION_TARGETS
	-- Add future Swimming/Crouching/Crawling/etc. branches HERE.
	-- Explicit focus still wins over all neutral camera-home behavior.

	local cameraDistance = getCameraDistanceFromCharacter()

	------------------------------------------------------------
	-- <= 2 STUDS: FIRST-PERSON CAMERA COMPANION
	------------------------------------------------------------

	if isCameraActuallyFirstPerson(cameraDistance) then
		return getFirstPersonTargetCFrame()
	end

	------------------------------------------------------------
	-- NORMAL CAMERA-HOME RESOLUTION
	------------------------------------------------------------

	local resolvedTargetCFrame: CFrame

	if closeShoulderMode then
		resolvedTargetCFrame = getShoulderTargetCFrame()
	elseif zoomedOutShoulderMode then
		resolvedTargetCFrame = getShoulderTargetCFrame()
	else
		resolvedTargetCFrame = getFirstPersonTargetCFrame()
	end

	------------------------------------------------------------
	-- CLIMBING SCREEN GUARD
	--
	-- Keep all of the existing home rules. Only when climbing and the selected
	-- target would leave the visible safe area do we pull it back on-screen.
	-- This prevents vertical ladder travel from throwing Spark off-camera.
	------------------------------------------------------------

	if isCharacterClimbing() and cameraDistance > CLOSE_SHOULDER_MAX_DISTANCE then
		-- In the free-camera climbing band Spark starts one stud lower, then leads
		-- progressively farther downward as the character descends. The same
		-- helper also gives him a slight nose-down attitude during descent.
		resolvedTargetCFrame = applyClimbingFreeCameraVerticalBias(resolvedTargetCFrame, cameraDistance)

		-- Safety clamp runs AFTER the offset so the lower target can never
		-- deliberately place Spark outside the visible safe region.
		resolvedTargetCFrame = resolveClimbingScreenSafeCFrame(resolvedTargetCFrame)
	end

	return resolvedTargetCFrame
end

----------------------------------------------------------------
-- CAMERA MOVEMENT RESPONSE
----------------------------------------------------------------

local previousCameraLookVector: Vector3? = nil
local previousTargetPosition: Vector3? = nil
local previousCameraDistance: number? = nil

local function getCameraAngularSpeedDegrees(dt: number): number
	local camera = workspace.CurrentCamera

	if not camera then
		previousCameraLookVector = nil
		return 0
	end

	local currentCameraLookVector = camera.CFrame.LookVector
	local previousLookVector = previousCameraLookVector

	previousCameraLookVector = currentCameraLookVector

	if not previousLookVector or dt <= 0 then
		return 0
	end

	local lookDot = math.clamp(previousLookVector:Dot(currentCameraLookVector), -1, 1)

	local angularDifferenceRadians = math.acos(lookDot)

	return math.deg(angularDifferenceRadians) / dt
end

local function getTargetLateralSpeed(targetCFrame: CFrame, dt: number): number
	local currentTargetPosition = targetCFrame.Position
	local previousPosition = previousTargetPosition

	previousTargetPosition = currentTargetPosition

	if not previousPosition or dt <= 0 then
		return 0
	end

	local camera = workspace.CurrentCamera

	if not camera then
		return 0
	end

	local targetMovement = currentTargetPosition - previousPosition

	-- Only care about movement across the camera's horizontal axis.
	-- Forward/back depth changes from zooming should therefore retain
	-- Spark's slower fluttering transition.
	return math.abs(targetMovement:Dot(camera.CFrame.RightVector)) / dt
end

local function getCameraZoomSpeed(cameraDistance: number, dt: number): number
	local previousDistance = previousCameraDistance

	previousCameraDistance = cameraDistance

	if previousDistance == nil or dt <= 0 then
		return 0
	end

	return math.abs(cameraDistance - previousDistance) / dt
end

local function getCurrentSmoothTime(
	currentSparkCFrame: CFrame,
	targetCFrame: CFrame,
	cameraAngularSpeedDegrees: number,
	targetLateralSpeed: number,
	cameraZoomSpeed: number
): number
	-- Focused targets remain deliberate and world-relative, except while
	-- climbing at maximum zoom: observer mode owns Spark completely.
	if focusedModel and not climbObserverMode then
		return SMOOTH_TIME
	end

	local zoomResponseAlpha =
		getResponseAlpha(cameraZoomSpeed, CAMERA_ZOOM_RESPONSE_START_SPEED, CAMERA_ZOOM_RESPONSE_FULL_SPEED)

	-- Ordinary camera-mode changes keep the original flutter.
	-- Aggressive zoom is allowed to override the grace period.
	if os.clock() - lastCameraModeChangeTime < CAMERA_MODE_TRANSITION_GRACE then
		return SMOOTH_TIME + (FAST_CAMERA_SMOOTH_TIME - SMOOTH_TIME) * zoomResponseAlpha
	end

	local distanceFromTarget = (currentSparkCFrame.Position - targetCFrame.Position).Magnitude

	local targetDistanceResponseAlpha =
		getResponseAlpha(distanceFromTarget, TARGET_DISTANCE_RESPONSE_START, TARGET_DISTANCE_RESPONSE_FULL)

	local shoulderSwitchResponseAlpha = 0

	if os.clock() - lastShoulderHomeModeChangeTime < SHOULDER_HOME_SWITCH_FAST_DURATION then
		shoulderSwitchResponseAlpha = SHOULDER_HOME_SWITCH_RESPONSE_ALPHA
	end

	local climbExitResponseAlpha = 0

	if not isCharacterClimbing() and os.clock() - lastClimbStateChangeTime < CLIMB_EXIT_FAST_DURATION then
		climbExitResponseAlpha = CLIMB_EXIT_RESPONSE_ALPHA
	end

	local verticalResponseAlpha = getResponseAlpha(
		currentCharacterVerticalSpeed,
		CLIMB_VERTICAL_FAST_RESPONSE_START_SPEED,
		CLIMB_VERTICAL_FAST_RESPONSE_FULL_SPEED
	)

	local offscreenResponseAlpha = 0

	if isCharacterClimbing() and not climbObserverMode and isSparkOutsideClimbingSafeScreen(currentSparkCFrame) then
		offscreenResponseAlpha = CLIMB_OFFSCREEN_RESPONSE_ALPHA
	end

	------------------------------------------------------------
	-- DOWNWARD / FALLING EMERGENCY CATCH-UP
	--
	-- This intentionally runs BEFORE the generic climbing response. When the
	-- character is dropping fast, Spark should chase hard instead of preserving
	-- the relaxed flutter that feels good everywhere else.
	------------------------------------------------------------

	local characterDownwardSpeed = math.max(0, -currentCharacterVerticalVelocityY)

	local humanoidState = humanoid:GetState()

	local characterIsFalling = humanoidState == Enum.HumanoidStateType.Freefall
		or humanoidState == Enum.HumanoidStateType.FallingDown

	if
		characterDownwardSpeed >= CLIMB_DESCENT_FAST_SPEED_THRESHOLD
		or (characterIsFalling and characterDownwardSpeed > 0.25)
	then
		return CLIMB_DESCENT_FAST_SMOOTH_TIME
	end

	-- Give the shoulder -> climbing-observer transition a deliberate tween-like
	-- flight instead of letting emergency catch-up immediately zip Spark there.
	if climbObserverMode and os.clock() - lastClimbObserverModeChangeTime < CLIMB_OBSERVER_ENTRY_SMOOTH_DURATION then
		return CLIMB_OBSERVER_ENTRY_SMOOTH_TIME
	end

	-- When max zoom is released, or the Humanoid leaves Climbing for
	-- Running/Freefall/FallingDown, glide away from the observer perch instead
	-- of using the normal aggressive catch-up response.
	if not climbObserverMode and os.clock() - lastClimbObserverModeChangeTime < 0.95 then
		return 0.68
	end

	-- Climbing keeps the responsive movement solver available. Once Spark has
	-- arrived at the observer perch this lets him continue following camera
	-- framing naturally while he watches.
	if isCharacterClimbing() then
		local cameraResponseAlpha = getResponseAlpha(
			cameraAngularSpeedDegrees,
			CAMERA_FAST_RESPONSE_START_DEGREES,
			CAMERA_FAST_RESPONSE_FULL_DEGREES
		)

		local lateralResponseAlpha = getResponseAlpha(
			targetLateralSpeed,
			TARGET_LATERAL_RESPONSE_START_SPEED,
			TARGET_LATERAL_RESPONSE_FULL_SPEED
		)

		local climbingResponseAlpha = math.max(
			CLIMB_MIN_RESPONSE_ALPHA,
			cameraResponseAlpha,
			lateralResponseAlpha,
			zoomResponseAlpha,
			targetDistanceResponseAlpha,
			verticalResponseAlpha,
			offscreenResponseAlpha
		)

		return SMOOTH_TIME + (FAST_CAMERA_SMOOTH_TIME - SMOOTH_TIME) * climbingResponseAlpha
	end

	-- Once Spark is living at the shoulder, stop treating ordinary
	-- camera rotation as permission to fling him around world-space.
	-- Maximum zoom is special ONLY through climbObserverMode.
	if zoomedOutShoulderMode or closeShoulderMode then
		local shoulderResponseAlpha = math.max(
			zoomResponseAlpha,
			targetDistanceResponseAlpha,
			shoulderSwitchResponseAlpha,
			climbExitResponseAlpha,
			verticalResponseAlpha,
			offscreenResponseAlpha
		)

		return SMOOTH_TIME + (FAST_CAMERA_SMOOTH_TIME - SMOOTH_TIME) * shoulderResponseAlpha
	end

	local cameraResponseAlpha = getResponseAlpha(
		cameraAngularSpeedDegrees,
		CAMERA_FAST_RESPONSE_START_DEGREES,
		CAMERA_FAST_RESPONSE_FULL_DEGREES
	)

	local lateralResponseAlpha =
		getResponseAlpha(targetLateralSpeed, TARGET_LATERAL_RESPONSE_START_SPEED, TARGET_LATERAL_RESPONSE_FULL_SPEED)

	local fastResponseAlpha = math.max(
		cameraResponseAlpha,
		lateralResponseAlpha,
		zoomResponseAlpha,
		targetDistanceResponseAlpha,
		shoulderSwitchResponseAlpha,
		climbExitResponseAlpha,
		verticalResponseAlpha,
		offscreenResponseAlpha
	)

	return SMOOTH_TIME + (FAST_CAMERA_SMOOTH_TIME - SMOOTH_TIME) * fastResponseAlpha
end

----------------------------------------------------------------
-- INITIAL STATE
----------------------------------------------------------------

local initialCameraDistance = getCameraDistanceFromCharacter()

updateZoomedOutShoulderMode(initialCameraDistance)

updateCloseShoulderMode(initialCameraDistance)

updateClimbObserverMode(initialCameraDistance)

previousCameraDistance = initialCameraDistance

local currentCFrame = getTargetCFrame()

-- IMPORTANT:
-- CFrame SmoothDamp uses a CFrame velocity state.
local smoothVelocity = CFrame.new()

spark:PivotTo(currentCFrame)

local function playFirstPersonRecoveryTeleport()
	if
		firstPersonRecoveryActive
		or not firstPersonPhysicalModeActive
		or not sparkGameplayVisible
		or sparkVisuals.SoulBurstInProgress
		or focusedModel
		or climbObserverMode
	then
		return
	end

	firstPersonRecoveryActive = true
	firstPersonRecoveryFarSince = nil

	task.spawn(function()
		sparkVisuals:PlaySoulMaterialisation(function()
			if not spark.Parent then
				return
			end

			-- Re-resolve at the invisible moment. If the player changed zoom
			-- during the dissolve, Spark reforms at whatever target is correct now.
			currentCFrame = getTargetCFrame()

			smoothVelocity = CFrame.new()

			spark:PivotTo(currentCFrame)
		end)

		lastFirstPersonRecoveryTime = os.clock()

		firstPersonRecoveryActive = false
	end)
end

----------------------------------------------------------------
-- SPARK VISUAL PERSONALITY
--
-- SparkFollower decides WHEN / WHERE.
-- SparkVisuals owns the actual visual effect.
----------------------------------------------------------------

local sparkPersonality = {
	Random = Random.new(),
	Destroyed = false,
	IdleVisualsActive = false,
	LastPlayerMovementTime = os.clock(),
}

local function canRunSparkVisualPersonality(): boolean
	return sparkGameplayVisible
		and spark.Parent ~= nil
		and not sparkPersonality.Destroyed
		and not sparkVisuals.SoulBurstInProgress
		and focusedModel == nil
		and not climbObserverMode
		and not isCharacterClimbing()
end

-- Random left/right side swapping is intentionally disabled.
-- Spark's neutral presentation is right-side only so his trail never sweeps
-- across the left side of the player's view.

----------------------------------------------------------------
-- IDLE VISUAL STATE
--
-- This is intentionally a very small runtime hook, not the planned follower
-- rework. SparkVisuals owns HOW the idle morph looks; SparkFollower only says
-- whether the player is currently idle enough to allow it.
----------------------------------------------------------------

local function isPlayerActivelyMoving(): boolean
	if humanoid.MoveDirection.Magnitude > SPARK_IDLE_MOVE_DIRECTION_THRESHOLD then
		return true
	end

	local humanoidState = humanoid:GetState()

	return humanoidState == Enum.HumanoidStateType.Jumping
		or humanoidState == Enum.HumanoidStateType.Freefall
		or humanoidState == Enum.HumanoidStateType.FallingDown
		or isCharacterClimbing()
end

local function updateSparkIdleVisualState(cameraAngularSpeedDegrees: number, cameraZoomSpeed: number)
	local now = os.clock()

	-- Do not let the hidden gameplay clone begin an idle cycle behind the
	-- loading cinematic. This also gives Spark a fresh idle delay after handoff.
	if not sparkGameplayVisible then
		sparkPersonality.LastPlayerMovementTime = now
		return
	end

	local playerIsMoving = isPlayerActivelyMoving()

	local cameraIsMoving = cameraAngularSpeedDegrees >= SPARK_IDLE_CAMERA_ANGULAR_SPEED_THRESHOLD
		or cameraZoomSpeed >= SPARK_IDLE_CAMERA_ZOOM_SPEED_THRESHOLD

	local idleVisualsSuppressed = focusedModel ~= nil or isCharacterClimbing()

	-- ILLUMINATE MODE:
	-- Any character movement OR deliberate camera movement immediately returns
	-- Spark to his canonical gold light/helper form and restarts the idle timer.
	if playerIsMoving or cameraIsMoving or idleVisualsSuppressed then
		sparkPersonality.LastPlayerMovementTime = now

		if sparkPersonality.IdleVisualsActive then
			sparkPersonality.IdleVisualsActive = false

			sparkVisuals:StopIdleVisuals(SPARK_IDLE_RETURN_DURATION)
		end

		return
	end

	if sparkVisuals.SoulBurstInProgress then
		return
	end

	if
		not sparkPersonality.IdleVisualsActive
		and now - sparkPersonality.LastPlayerMovementTime >= SPARK_IDLE_VISUAL_DELAY
	then
		sparkPersonality.IdleVisualsActive = true

		sparkVisuals:StartIdleVisuals()
	end
end

----------------------------------------------------------------
-- UPDATE
----------------------------------------------------------------

local function getRenderedSparkCFrame(
	solvedCFrame: CFrame,
	targetCFrame: CFrame,
	previousPosition: Vector3,
	dt: number
): CFrame
	local camera = workspace.CurrentCamera

	if not camera or not isFirstPerson or zoomedOutShoulderMode or isCharacterClimbing() or focusedModel ~= nil then
		FirstPersonReturnFacing.Flipped = false
		return solvedCFrame
	end

	local movementVector = solvedCFrame.Position - previousPosition
	local movementSpeed = if dt > 0 then movementVector.Magnitude / dt else 0
	local catchupDistance = (targetCFrame.Position - solvedCFrame.Position).Magnitude

	if
		movementSpeed < FirstPersonReturnFacing.MinimumMovementSpeed
		or movementVector.Magnitude <= 0.0001
		or catchupDistance < FirstPersonReturnFacing.MinimumCatchupDistance
	then
		FirstPersonReturnFacing.Flipped = false
		return CFrame.new(solvedCFrame.Position) * camera.CFrame.Rotation
	end

	local cameraForwardDot = movementVector.Unit:Dot(camera.CFrame.LookVector)

	if FirstPersonReturnFacing.Flipped then
		if cameraForwardDot >= FirstPersonReturnFacing.ExitDot then
			FirstPersonReturnFacing.Flipped = false
		end
	elseif cameraForwardDot <= FirstPersonReturnFacing.EnterDot then
		FirstPersonReturnFacing.Flipped = true
	end

	local renderedRotation = camera.CFrame.Rotation
	if FirstPersonReturnFacing.Flipped then
		renderedRotation *= CFrame.Angles(0, math.rad(180), 0)
	end

	return CFrame.new(solvedCFrame.Position) * renderedRotation
end

local function onUpdate(dt: number)
	if not spark.Parent then
		return
	end

	if not head.Parent or not rootPart.Parent then
		return
	end

	updateSparkFocus()

	-- Measure what the beta controller actually did in world-space this frame.
	-- Observer-idle detection and vertical catch-up use this instead of input.
	updateCharacterWorldMotion(dt)

	-- CODEX_STATE_MARKER: STATE_DRIVEN_UPDATE
	-- Locomotion state should affect target selection, not duplicate
	-- Spark's movement solver. Keep SmoothDamp/trail logic shared.

	if climbStateChanged then
		-- Prevent momentum from the climbing camera-corner target
		-- carrying into the shoulder / first-person return target.
		smoothVelocity = CFrame.new()
		climbStateChanged = false
	end

	local cameraDistance = getCameraDistanceFromCharacter()

	updateFirstPersonPhysicalMode(cameraDistance)

	local zoomedOutShoulderModeChanged = updateZoomedOutShoulderMode(cameraDistance)

	local closeShoulderModeChanged = updateCloseShoulderMode(cameraDistance)

	local climbObserverModeChanged = updateClimbObserverMode(cameraDistance)

	if zoomedOutShoulderModeChanged or closeShoulderModeChanged or climbObserverModeChanged then
		-- Kill only the old target's momentum. SmoothDamp still flies from Spark's
		-- current CFrame to the newly selected target; this is not a teleport.
		smoothVelocity = CFrame.new()
	end

	local targetCFrame = getTargetCFrame()

	local cameraAngularSpeedDegrees = getCameraAngularSpeedDegrees(dt)

	local targetLateralSpeed = getTargetLateralSpeed(targetCFrame, dt)

	local cameraZoomSpeed = getCameraZoomSpeed(cameraDistance, dt)

	updateSparkIdleVisualState(cameraAngularSpeedDegrees, cameraZoomSpeed)

	local currentSmoothTime = getCurrentSmoothTime(
		currentCFrame,
		targetCFrame,
		cameraAngularSpeedDegrees,
		targetLateralSpeed,
		cameraZoomSpeed
	)

	------------------------------------------------------------
	-- REMEMBER WHERE SPARK WAS
	------------------------------------------------------------

	local previousPosition = currentCFrame.Position

	------------------------------------------------------------
	-- SMOOTH FOLLOWING
	------------------------------------------------------------

	currentCFrame, smoothVelocity =
		TweenService:SmoothDamp(currentCFrame, targetCFrame, smoothVelocity, currentSmoothTime, MAX_SPEED, dt)

	------------------------------------------------------------
	-- CATCH-UP CAMERA ORIENTATION
	--
	-- First person + close camera:
	--     camera-facing presentation is allowed during catch-up.
	--
	-- Free camera (15-30 studs) + exact maximum zoom:
	--     only use it when Spark is genuinely catching up from a meaningful
	--     distance OR he is physically in front of the player.
	--
	-- Far shoulder:
	--     leave his authored/world presentation alone.
	--
	-- This block changes ROTATION ONLY. Position remains exactly the
	-- SmoothDamp result above.
	------------------------------------------------------------

	local camera = workspace.CurrentCamera

	------------------------------------------------------------
	-- CLIMB OBSERVER ENTRY ORIENTATION
	--
	-- While Spark is flying from the normal home to the top-right
	-- observer perch, let him briefly face the camera so the flight
	-- reads deliberately on-screen.
	--
	-- During the final part of the flight, blend back toward the
	-- observer target's authored rotation. Once the entry window ends,
	-- this block does absolutely nothing.
	--
	-- POSITION IS NOT CHANGED HERE.
	------------------------------------------------------------

	if camera and climbObserverMode then
		local observerEntryElapsed = os.clock() - lastClimbObserverModeChangeTime

		if observerEntryElapsed < CLIMB_OBSERVER_ENTRY_SMOOTH_DURATION then
			local observerEntryAlpha = math.clamp(observerEntryElapsed / CLIMB_OBSERVER_ENTRY_SMOOTH_DURATION, 0, 1)

			local cameraFacingCFrame =
				CFrame.lookAt(currentCFrame.Position, camera.CFrame.Position, camera.CFrame.UpVector)

			-- Face the camera through most of the travel, then gently
			-- hand rotation back to the final top-right observer pose.
			local observerRotationReturnAlpha = math.clamp((observerEntryAlpha - 0.68) / 0.32, 0, 1)

			local finalObserverRotationCFrame = CFrame.new(currentCFrame.Position) * targetCFrame.Rotation

			local observerPresentationCFrame =
				cameraFacingCFrame:Lerp(finalObserverRotationCFrame, observerRotationReturnAlpha)

			local observerOrientationResponse = 1 - math.exp(-10 * dt)

			currentCFrame = currentCFrame:Lerp(observerPresentationCFrame, observerOrientationResponse)
		end
	end

	if camera and not focusedModel and not climbObserverMode and currentSmoothTime < SMOOTH_TIME then
		local cameraZoomIsFirstPerson = isCameraActuallyFirstPerson(cameraDistance)

		local cameraZoomIsClose = closeShoulderMode

		local cameraZoomIsOrdinaryFree = cameraDistance > CLOSE_SHOULDER_MAX_DISTANCE
			and cameraDistance <= FREE_CAMERA_MAX_DISTANCE

		local distanceFromCurrentTarget = (currentCFrame.Position - targetCFrame.Position).Magnitude

		local sparkIsMeaningfullyCatchingUp = distanceFromCurrentTarget >= TARGET_DISTANCE_RESPONSE_START

		local sparkIsInFrontOfPlayer = (currentCFrame.Position - rootPart.Position):Dot(rootPart.CFrame.LookVector) > 0

		local freeCameraAllowsOrientation = cameraZoomIsOrdinaryFree
			and (sparkIsMeaningfullyCatchingUp or sparkIsInFrontOfPlayer)

		local shouldCameraAlignCatchUp = cameraZoomIsFirstPerson or cameraZoomIsClose or freeCameraAllowsOrientation

		if shouldCameraAlignCatchUp then
			local catchUpStrength =
				math.clamp((SMOOTH_TIME - currentSmoothTime) / (SMOOTH_TIME - FAST_CAMERA_SMOOTH_TIME), 0, 1)

			local cameraOrientationAlpha = (1 - math.exp(-12 * dt)) * catchUpStrength

			local cameraAlignedCFrame = CFrame.new(currentCFrame.Position) * camera.CFrame.Rotation

			currentCFrame = currentCFrame:Lerp(cameraAlignedCFrame, cameraOrientationAlpha)
		end
	end

	currentCFrame = resolveFirstPersonPhysicalMovement(previousPosition, currentCFrame)

	local sparkRenderedCFrame = getRenderedSparkCFrame(currentCFrame, targetCFrame, previousPosition, dt)

	spark:PivotTo(sparkRenderedCFrame)

	------------------------------------------------------------
	-- TRUE FIRST-PERSON RECOVERY TELEPORT
	------------------------------------------------------------

	if
		firstPersonPhysicalModeActive
		and sparkGameplayVisible
		and not focusedModel
		and not climbObserverMode
		and not firstPersonRecoveryActive
		and not sparkVisuals.SoulBurstInProgress
		and os.clock() - lastFirstPersonRecoveryTime >= FIRST_PERSON_RECOVERY_COOLDOWN
	then
		local distanceFromIntendedHome = (currentCFrame.Position - targetCFrame.Position).Magnitude

		if distanceFromIntendedHome >= FIRST_PERSON_RECOVERY_DISTANCE then
			if firstPersonRecoveryFarSince == nil then
				firstPersonRecoveryFarSince = os.clock()
			elseif os.clock() - firstPersonRecoveryFarSince >= FIRST_PERSON_RECOVERY_HOLD_TIME then
				playFirstPersonRecoveryTeleport()
			end
		else
			firstPersonRecoveryFarSince = nil
		end
	else
		firstPersonRecoveryFarSince = nil
	end

	------------------------------------------------------------
	-- ACTUAL VISIBLE MOVEMENT SPEED
	------------------------------------------------------------

	local movementSpeed = 0

	if dt > 0 then
		movementSpeed = (currentCFrame.Position - previousPosition).Magnitude / dt
	end

	------------------------------------------------------------
	-- TRAIL
	------------------------------------------------------------

	sparkVisuals:SetTrailEnabled(sparkGameplayVisible and movementSpeed >= TRAIL_START_SPEED)
end

----------------------------------------------------------------
-- START
----------------------------------------------------------------

local updateConnection = RunService.PreRender:Connect(onUpdate)

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------

script.Destroying:Connect(function()
	sparkPersonality.Destroyed = true

	if player.Character == character then
		player:SetAttribute(SPARK_GAMEPLAY_READY_ATTRIBUTE, false)
	end

	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	if firstPersonConnection then
		firstPersonConnection:Disconnect()
	end

	if humanoidStateConnection then
		humanoidStateConnection:Disconnect()
	end

	if humanoidAttributeDebugConnection then
		humanoidAttributeDebugConnection:Disconnect()
		humanoidAttributeDebugConnection = nil
	end

	if sparkCameraHandoffConnection then
		sparkCameraHandoffConnection:Disconnect()
	end

	if hoverTrack then
		hoverTrack:Stop()
	end

	if sparkVisuals then
		sparkVisuals:StopIdleVisuals(0)
		sparkVisuals:Destroy()
	end

	if spark then
		spark:Destroy()
	end
end)
