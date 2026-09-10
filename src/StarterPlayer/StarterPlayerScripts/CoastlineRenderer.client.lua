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
-- submerges and fade it back in as it resurfaces.

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

--==============================================================
-- ASSETS
--==============================================================

local assets =
	ReplicatedStorage
	:WaitForChild("Shared")
	:WaitForChild("Assets")

local coastlineTemplate =
	assets
	:WaitForChild("CoastLine")

local waterPartTemplate =
	assets
	:WaitForChild("WaterPart")

assert(
	coastlineTemplate:IsA("BasePart"),
	"ReplicatedStorage.Shared.Assets.CoastLine must be a BasePart/MeshPart"
)

assert(
	waterPartTemplate:IsA("BasePart"),
	"ReplicatedStorage.Shared.Assets.WaterPart must be a BasePart/MeshPart"
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

--==============================================================
-- SUBMERSION FADE SETTINGS
--==============================================================

-- Absolute world-space CAMERA Y thresholds, tuned from testing.
--
-- At or above this height, the effect is fully visible.
local CAMERA_VISIBLE_Y = 8.5

-- At or below this height, the effect is fully invisible.
local CAMERA_HIDDEN_Y = 8.0

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
	"WaterPart"

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

waterPart.Parent =
	effectFolder

local coastline =
	coastlineTemplate:Clone()

coastline.Name =
	"CoastLine"

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

coastline.Parent =
	effectFolder

--==============================================================
-- PLAYER
--==============================================================

local player =
	Players.LocalPlayer

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

local fadeAlpha = 0 -- 0 = fully visible, 1 = fully hidden

local function lerpNumber(
	a: number,
	b: number,
	alpha: number
): number

	return a
		+ (b - a)
		* alpha
end

-- Linear ramp purely as a function of camera height.
--
-- >= CAMERA_VISIBLE_Y : 0 (fully visible)
-- <= CAMERA_HIDDEN_Y  : 1 (fully invisible)
-- in between          : smooth 0 -> 1
local function getTargetFadeAlpha(
	cameraY: number
): number

	if cameraY >= CAMERA_VISIBLE_Y then
		return 0
	end

	if cameraY <= CAMERA_HIDDEN_Y then
		return 1
	end

	return
		(CAMERA_VISIBLE_Y - cameraY)
		/ (
			CAMERA_VISIBLE_Y
			- CAMERA_HIDDEN_Y
		)
end

local function updateSubmersionFade(
	dt: number,
	cameraY: number
)

	local target =
		getTargetFadeAlpha(
			cameraY
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

	waterPart.Transparency =
		lerpNumber(
			waterPartBaseTransparency,
			1,
			fadeAlpha
		)

	coastline.Transparency =
		lerpNumber(
			coastlineBaseTransparency,
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
			return
		end

		local root =
			character:FindFirstChild(
				"HumanoidRootPart"
			)

		if
			not root
			or not root:IsA("BasePart")
		then
			return
		end

		positionEffect(
			root.Position
		)

		local camera =
			Workspace.CurrentCamera

		local cameraY =
			camera
			and camera.CFrame.Position.Y
			or root.Position.Y

		updateSubmersionFade(
			dt,
			cameraY
		)
	end
)
