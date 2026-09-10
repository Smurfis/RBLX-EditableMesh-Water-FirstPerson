--!strict

-- StarterPlayerScripts > CoastlineRenderer
--
-- Local visual shoreline/intersection effect.
--
-- This is COMPLETELY independent of the EditableMesh ocean.
--
-- The trick requires TWO stacked MeshParts:
--
--      CoastLine
--      ----------
--        tiny gap
--      ----------
--      WaterPart
--
-- Both templates are configured manually in Studio and cloned at runtime.
-- We deliberately do NOT modify SurfaceAppearance / RenderFidelity /
-- material appearance properties here.
--
-- SUBMERSION FADE (added):
-- The stacked-glass trick only reads correctly when the camera is
-- above it looking down through both semi-transparent layers. Viewed
-- from underneath (camera underwater looking up) the two coincident
-- layers sort/refract in ways they were never authored for. Rather
-- than trying to fix that view, we fade the pair out as the camera
-- submerges and fade it back in as it resurfaces. The fade follows the
-- root-part height so camera rotation cannot change it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--==============================================================
-- WATER CONFIG
--==============================================================

local WaterConfig =
	require(
		ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterConfig")
	)

local SurfaceTest =
	WaterConfig.Swimming.SurfaceTest

--==============================================================
-- ASSETS
--==============================================================

local assets =
	ReplicatedStorage
	:WaitForChild("Shared")
	:WaitForChild("Assets")

local waterSounds =
	ReplicatedStorage
	:WaitForChild("Shared")
	:WaitForChild("Sounds")
	:WaitForChild("Water")

local coastlineTemplate =
	assets
	:WaitForChild("CoastLine")

local waterPartTemplate =
	assets
	:WaitForChild("WaterPart")

local surfaceIdleTemplate =
	waterSounds
	:WaitForChild("WaterSurfaceIdle")

assert(
	coastlineTemplate:IsA("BasePart"),
	"ReplicatedStorage.Shared.Assets.CoastLine must be a BasePart/MeshPart"
)

assert(
	waterPartTemplate:IsA("BasePart"),
	"ReplicatedStorage.Shared.Assets.WaterPart must be a BasePart/MeshPart"
)

assert(
	surfaceIdleTemplate:IsA("Sound"),
	"ReplicatedStorage.Shared.Sounds.Water.WaterSurfaceIdle must be a Sound"
)

--==============================================================
-- SETTINGS
--==============================================================

-- This pair follows the PLAYER, not the camera.
--
-- Start with the gameplay water surface as the base reference.
local EFFECT_Y_OFFSET = 1.75

local WATER_PART_Y_OFFSET = -0.4
local COASTLINE_Y_OFFSET = 0.4

local FOLLOW_SNAP = 32

-- Keep the authored coastline effect present while reducing how strongly it
-- competes with the generated ocean layers. Set to 1 to restore full opacity.
local EFFECT_OPACITY_MULTIPLIER = 0.55
local MINIMUM_EFFECT_TRANSPARENCY = 1 - EFFECT_OPACITY_MULTIPLIER

-- The query remains a little tolerant of thin visual geometry and animated
-- hands, then uses timing hysteresis to avoid rapidly restarting the loop.
local HAND_CONTACT_VERTICAL_PADDING = 0.15
local HAND_CONTACT_START_DELAY = 0.12
local HAND_CONTACT_RELEASE_DELAY = 0.25

-- Preserve the authored pitch at rest and accelerate the loop as surface
-- swimming approaches the configured maximum speed.
local SURFACE_SOUND_SWIM_SPEED_MULTIPLIER = 1.65
local SURFACE_SOUND_SPEED_FOLLOW_RATE = 8

-- Muffle from the listener's camera position so dipping only the head below
-- the surface sounds submerged even while a hand still touches the foam.
local SURFACE_SOUND_MUFFLE_FULL_DEPTH = 2
local SURFACE_SOUND_MUFFLED_LOW_GAIN = -2
local SURFACE_SOUND_MUFFLED_MID_GAIN = -9
local SURFACE_SOUND_MUFFLED_HIGH_GAIN = -22

local HAND_PART_NAMES: { [string]: boolean } = {
	LeftHand = true,
	RightHand = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
}

--==============================================================
-- SUBMERSION FADE SETTINGS
--==============================================================

-- Absolute world-space ROOT PART Y thresholds, tuned from testing.
--
-- At or above this height, the effect is fully visible.
local SURFACE_EFFECT_VISIBLE_Y =
	SurfaceTest.FloatMinY

-- At or below this height, the effect is fully invisible.
local SURFACE_EFFECT_HIDDEN_Y =
	SurfaceTest.AssistStartY

-- Optional extra time-based smoothing layered on top of the
-- position-based ramp above, so fast camera movement through the
-- band doesn't pop. Higher = snappier. Set to a very large number
-- (e.g. 1000) if you'd rather the ramp track camera height exactly
-- with no lag at all.
local FADE_SPEED = 10

--==============================================================
-- CREATE CLIENT EFFECT
--==============================================================

local old =
	Workspace:FindFirstChild(
		"__ClientCoastlineEffect"
	)

if old then
	old:Destroy()
end

local effectFolder =
	Instance.new("Folder")

effectFolder.Name =
	"__ClientCoastlineEffect"

effectFolder.Parent =
	Workspace

--==============================================================
-- CLONE STUDIO-AUTHORED PARTS
--==============================================================

local waterPart =
	waterPartTemplate:Clone()

waterPart.Name =
	"SurfaceWaterVFX"

waterPart.Anchored =
	true

waterPart.CanCollide =
	false

waterPart.CanTouch =
	false

waterPart.CanQuery =
	false

waterPart.CastShadow =
	false

if waterPart:IsA("MeshPart") then
	waterPart.DoubleSided = true
end

waterPart.Parent =
	effectFolder

local coastline =
	coastlineTemplate:Clone()

coastline.Name =
	"CoastlineFoamVFX"

coastline.Anchored =
	true

coastline.CanCollide =
	false

coastline.CanTouch =
	false

coastline.CanQuery =
	false

coastline.CastShadow =
	false

if coastline:IsA("MeshPart") then
	coastline.DoubleSided = true
end

coastline.Parent =
	effectFolder

--==============================================================
-- PLAYER
--==============================================================

local player =
	Players.LocalPlayer

local handOverlapParams =
	OverlapParams.new()

handOverlapParams.FilterType =
	Enum.RaycastFilterType.Include

handOverlapParams.MaxParts =
	16

local surfaceIdleSound: Sound? =
	nil

local surfaceIdleMuffle: EqualizerSoundEffect? =
	nil

local surfaceIdleCharacter: Model? =
	nil

local surfaceIdleBasePlaybackSpeed = 1
local surfaceIdlePlaybackMultiplier = 1
local handContactTime = 0
local handReleaseTime = 0

local function destroySurfaceIdleSound()
	if surfaceIdleSound then
		surfaceIdleSound:Destroy()
		surfaceIdleSound = nil
	end

	surfaceIdleMuffle = nil
	surfaceIdleCharacter = nil
	surfaceIdleBasePlaybackSpeed = 1
	surfaceIdlePlaybackMultiplier = 1
	handContactTime = 0
	handReleaseTime = 0
end

local function ensureSurfaceIdleSound(
	character: Model,
	root: BasePart
): Sound
	if
		surfaceIdleSound
		and surfaceIdleSound.Parent
		and surfaceIdleCharacter == character
	then
		return surfaceIdleSound
	end

	destroySurfaceIdleSound()

	local sound =
		surfaceIdleTemplate:Clone()

	sound.Name =
		"WaterSurfaceIdle_Local"

	sound.Looped =
		true

	surfaceIdleBasePlaybackSpeed =
		sound.PlaybackSpeed

	local muffle =
		Instance.new(
			"EqualizerSoundEffect"
		)

	muffle.Name =
		"WaterSurfaceMuffle"

	muffle.LowGain = 0
	muffle.MidGain = 0
	muffle.HighGain = 0
	muffle.Parent = sound

	sound.Parent =
		root

	surfaceIdleSound = sound
	surfaceIdleMuffle = muffle
	surfaceIdleCharacter = character
	handOverlapParams.FilterDescendantsInstances = {
		character,
	}

	return sound
end

local function isHandTouchingCoastline(): boolean
	local querySize =
		coastline.Size
		+ Vector3.new(
			0,
			HAND_CONTACT_VERTICAL_PADDING * 2,
			0
		)

	local overlappingParts =
		Workspace:GetPartBoundsInBox(
			coastline.CFrame,
			querySize,
			handOverlapParams
		)

	for _, part in overlappingParts do
		if HAND_PART_NAMES[part.Name] then
			return true
		end
	end

	return false
end

local function updateSurfaceIdleSound(
	dt: number,
	character: Model,
	humanoid: Humanoid,
	root: BasePart
)
	local sound =
		ensureSurfaceIdleSound(
			character,
			root
		)

	local velocity =
		root.AssemblyLinearVelocity

	local horizontalSpeed =
		Vector3.new(
			velocity.X,
			0,
			velocity.Z
		).Magnitude

	local speedAlpha =
		math.clamp(
			math.max(
				horizontalSpeed
				/ WaterConfig.Swimming.Speed,

				humanoid.MoveDirection.Magnitude
				* 0.25
			),
			0,
			1
		)

	local targetPlaybackMultiplier =
		1
		+ (
			SURFACE_SOUND_SWIM_SPEED_MULTIPLIER
			- 1
		)
		* speedAlpha

	local speedFollowAlpha =
		1
		- math.exp(
			-SURFACE_SOUND_SPEED_FOLLOW_RATE
			* dt
		)

	surfaceIdlePlaybackMultiplier +=
		(
			targetPlaybackMultiplier
			- surfaceIdlePlaybackMultiplier
		)
		* speedFollowAlpha

	sound.PlaybackSpeed =
		surfaceIdleBasePlaybackSpeed
		* surfaceIdlePlaybackMultiplier

	local camera =
		Workspace.CurrentCamera

	local listenerY =
		camera
		and camera.CFrame.Position.Y
		or root.Position.Y

	local muffleDepth =
		math.max(
			0,

			WaterConfig.GetSurfaceY()
			- listenerY
			- WaterConfig.Underwater.CameraEnterDepth
		)

	local muffleAlpha =
		math.clamp(
			muffleDepth
			/ SURFACE_SOUND_MUFFLE_FULL_DEPTH,
			0,
			1
		)

	local muffle =
		surfaceIdleMuffle

	if muffle then
		muffle.LowGain =
			SURFACE_SOUND_MUFFLED_LOW_GAIN
			* muffleAlpha

		muffle.MidGain =
			SURFACE_SOUND_MUFFLED_MID_GAIN
			* muffleAlpha

		muffle.HighGain =
			SURFACE_SOUND_MUFFLED_HIGH_GAIN
			* muffleAlpha
	end

	local touching =
		isHandTouchingCoastline()

	if touching then
		handContactTime += dt
		handReleaseTime = 0

		if
			handContactTime
			>= HAND_CONTACT_START_DELAY
			and not sound.IsPlaying
		then
			sound:Play()
		end

		return
	end

	handContactTime = 0
	handReleaseTime += dt

	if
		handReleaseTime
		>= HAND_CONTACT_RELEASE_DELAY
		and sound.IsPlaying
	then
		sound:Stop()
	end
end

--==============================================================
-- POSITIONING
--==============================================================

local lastX: number? = nil
local lastZ: number? = nil
local lastSurfaceY: number? = nil

local function snap(
	value: number
): number

	return
		math.round(
			value / FOLLOW_SNAP
		)
		* FOLLOW_SNAP
end

local function positionEffect(
	rootPosition: Vector3
)

	local surfaceY =
		WaterConfig.GetSurfaceY()

	local x =
		snap(
			rootPosition.X
		)

	local z =
		snap(
			rootPosition.Z
		)

	-- Don't rewrite CFrames unless something actually changed.
	if
		x == lastX
		and z == lastZ
		and surfaceY == lastSurfaceY
	then
		return
	end

	lastX =
		x

	lastZ =
		z

	lastSurfaceY =
		surfaceY

	local baseY =
		surfaceY
		+ EFFECT_Y_OFFSET

	-- Lower supporting water layer.
	waterPart.CFrame =
		CFrame.new(
			x,
			baseY
			+ WATER_PART_Y_OFFSET,
			z
		)

	-- White translucent intersection layer.
	coastline.CFrame =
		CFrame.new(
			x,
			baseY
			+ COASTLINE_Y_OFFSET,
			z
		)
end

--==============================================================
-- SUBMERSION FADE
--==============================================================

-- Preserve whatever transparency was authored on the templates in
-- Studio; the fade lerps between that value and fully invisible
-- rather than assuming a hardcoded base transparency.
local waterPartBaseTransparency =
	waterPart.Transparency

local coastlineBaseTransparency =
	coastline.Transparency

local waterPartVisibleTransparency =
	waterPartBaseTransparency
	+ (1 - waterPartBaseTransparency)
	* (1 - EFFECT_OPACITY_MULTIPLIER)

local coastlineVisibleTransparency =
	coastlineBaseTransparency
	+ (1 - coastlineBaseTransparency)
	* (1 - EFFECT_OPACITY_MULTIPLIER)

local fadeAlpha = 0 -- 0 = fully visible, 1 = fully hidden

local function setEffectEnabled(enabled: boolean)
	if enabled then
		waterPart.Parent = effectFolder
		coastline.Parent = effectFolder
	else
		-- Removing the two render parts from the data model gives the toggle a
		-- real performance benefit while retaining them for instant re-enable.
		waterPart.Parent = nil
		coastline.Parent = nil
	end
end

effectFolder:GetAttributeChangedSignal("Enabled"):Connect(function()
	setEffectEnabled(effectFolder:GetAttribute("Enabled") ~= false)
end)
setEffectEnabled(effectFolder:GetAttribute("Enabled") ~= false)

local function lerpNumber(
	a: number,
	b: number,
	alpha: number
): number

	return a
		+ (b - a)
		* alpha
end

-- Linear ramp purely as a function of root-part height.
--
-- >= SURFACE_EFFECT_VISIBLE_Y : 0 (fully visible)
-- <= SURFACE_EFFECT_HIDDEN_Y  : 1 (fully invisible)
-- in between          : smooth 0 -> 1
local function getTargetFadeAlpha(
	rootY: number
): number

	if rootY >= SURFACE_EFFECT_VISIBLE_Y then
		return 0
	end

	if rootY <= SURFACE_EFFECT_HIDDEN_Y then
		return 1
	end

	return
		(SURFACE_EFFECT_VISIBLE_Y - rootY)
		/ (
			SURFACE_EFFECT_VISIBLE_Y
			- SURFACE_EFFECT_HIDDEN_Y
		)
end

local function updateSubmersionFade(
	dt: number,
	rootY: number
)
	if effectFolder:GetAttribute("Enabled") == false then
		return
	end

	local target =
		getTargetFadeAlpha(
			rootY
		)

	local alpha =
		1
	- math.exp(
		-FADE_SPEED * dt
	)

	fadeAlpha =
		fadeAlpha
		+ (
			target - fadeAlpha
		)
		* alpha
	local transparencyOverride = effectFolder:GetAttribute("TransparencyOverride")
	local visibleWaterTransparency = if typeof(transparencyOverride) == "number"
		then math.clamp(transparencyOverride, MINIMUM_EFFECT_TRANSPARENCY, 1)
		else waterPartVisibleTransparency
	local visibleCoastlineTransparency = if typeof(transparencyOverride) == "number"
		then math.clamp(transparencyOverride, MINIMUM_EFFECT_TRANSPARENCY, 1)
		else coastlineVisibleTransparency

	waterPart.Transparency =
		lerpNumber(
			visibleWaterTransparency,
			1,
			fadeAlpha
		)

	coastline.Transparency =
		lerpNumber(
			visibleCoastlineTransparency,
			1,
			fadeAlpha
		)
end

--==============================================================
-- UPDATE
--==============================================================

RunService:BindToRenderStep(
	"CoastlineRenderer",
	Enum.RenderPriority.Camera.Value + 2,

	function(dt: number)

		local character =
			player.Character

		if not character then
			destroySurfaceIdleSound()
			return
		end

		local humanoid =
			character:FindFirstChildOfClass(
				"Humanoid"
			)

		local root =
			character:FindFirstChild(
				"HumanoidRootPart"
			)

		if
			not root
			or not root:IsA("BasePart")
			or not humanoid
		then
			destroySurfaceIdleSound()
			return
		end

		positionEffect(
			root.Position
		)

		updateSubmersionFade(
			dt,
			root.Position.Y
		)

		updateSurfaceIdleSound(
			dt,
			character,
			humanoid,
			root
		)
	end
)
