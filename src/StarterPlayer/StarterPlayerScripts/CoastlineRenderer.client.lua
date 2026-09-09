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

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--==============================================================
-- WATER CONFIG
--==============================================================

local waterFolder =
	ReplicatedStorage
	:WaitForChild("Shared")
	:WaitForChild("Water")

local WaterConfig =
	require(
		waterFolder
		:WaitForChild("WaterConfig")
	)

local assets =
	waterFolder
	:WaitForChild("Assets")

local coastlineTemplate =
	assets:WaitForChild("CoastLine")

local waterPartTemplate =
	assets:WaitForChild("WaterPart")

--==============================================================
-- ASSETS
--==============================================================

local waterFolder =
	ReplicatedStorage
	:WaitForChild("Shared")
	:WaitForChild("Water")

local assets =
	waterFolder
	:WaitForChild("Assets")

local coastlineTemplate =
	assets
	:WaitForChild("CoastLine")

local waterPartTemplate =
	assets
	:WaitForChild("WaterPart")

assert(
	coastlineTemplate:IsA("BasePart"),
	"ReplicatedStorage.Shared.Water.Assets.CoastLine must be a BasePart/MeshPart"
)

assert(
	waterPartTemplate:IsA("BasePart"),
	"ReplicatedStorage.Shared.Water.Assets.WaterPart must be a BasePart/MeshPart"
)

--==============================================================
-- SETTINGS
--==============================================================

-- This pair follows the PLAYER, not the camera.
--
-- Start with the gameplay water surface as the base reference.
local EFFECT_Y_OFFSET =
	0

-- WaterPart sits slightly underneath CoastLine.
--
-- THIS is probably the most important value for reproducing the effect.
local WATER_PART_Y_OFFSET =
	0

local COASTLINE_Y_OFFSET =
	0.10

-- Snap X/Z rather than moving every frame.
--
-- Smaller = follows player more closely.
-- Larger = moves less frequently.
local FOLLOW_SNAP =
	32

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
-- UPDATE
--==============================================================

RunService:BindToRenderStep(
	"CoastlineRenderer",
	Enum.RenderPriority.Camera.Value + 2,

	function()

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
	end
)
