--!native
--!strict

-- StarterPlayerScripts > RealisticWater V4
--
-- ONE EditableMesh.
-- 25 LOGICAL update regions.
--
-- Key design:
--   * Water is world locked.
--   * Camera NEVER rotates the ocean.
--   * Camera only decides which logical regions need updating.
--   * Near-camera regions always update.
--   * Off-camera regions freeze.
--   * Regions prewarm before entering view.
--   * Deep underwater progressively reduces surface updates.
--   * 20+ studs underwater freezes wave simulation.
--   * The mesh treadmill moves only in exact grid increments.
--   * Wave phase is evaluated in WORLD SPACE.
--   * Four stacked render layers share one EditableMesh for a stylized white water rim.
--   * Cheap far-ocean coverage follows the camera-projected water target.
--   * High viewpoints therefore move cheap coverage ahead of the camera instead
--     of wasting half of it behind the player.

local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")

--==============================================================
-- MATH LOCALS
--==============================================================

local m_clamp = math.clamp
local m_round = math.round
local m_floor = math.floor
local m_sqrt = math.sqrt
local m_tan = math.tan
local m_rad = math.rad
local m_abs = math.abs
local m_min = math.min
local m_max = math.max
local m_atan = math.atan
local m_acos = math.acos

--==============================================================
-- CONFIG
--==============================================================

local WaterConfig =
	require(
		ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterConfig")
	)

local WaterWaveSampler =
	require(
		ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterWaveSampler")
	)

local WaterAssets =
	ReplicatedStorage
	:WaitForChild("Shared")
	:WaitForChild("Assets")

local function getSurfaceY(): number
	return WaterConfig.GetSurfaceY()
end

local currentWaveTime = 0

--==============================================================
-- GENERAL
--==============================================================

local WATER_FOLDER_NAME = "__ClientRealisticWaterV4"
local RENDER_STEP_NAME = "RealisticWaterV4"

--==============================================================
-- LOGICAL CHUNK GRID
--==============================================================

-- 5 x 5 logical regions.
-- They are NOT separate EditableMeshes.

local LOGICAL_CHUNKS_PER_AXIS = 5
local LOGICAL_CHUNK_SIZE = 300

-- 18 cells inside each logical chunk.
--
-- Whole mesh:
--
-- 5 * 18 = 90 cells
-- 91 x 91 vertices
--
-- = 8,281 vertices
-- = 16,200 triangles

local CELLS_PER_LOGICAL_CHUNK = 18

local TOTAL_CELLS_PER_AXIS =
	LOGICAL_CHUNKS_PER_AXIS
	* CELLS_PER_LOGICAL_CHUNK

local VERTICES_PER_AXIS =
	TOTAL_CELLS_PER_AXIS + 1

local TOTAL_VERTICES =
	VERTICES_PER_AXIS
	* VERTICES_PER_AXIS

local TOTAL_TRIANGLES =
	TOTAL_CELLS_PER_AXIS
	* TOTAL_CELLS_PER_AXIS
	* 2

local TOTAL_WATER_SIZE =
	LOGICAL_CHUNKS_PER_AXIS
	* LOGICAL_CHUNK_SIZE

local HALF_WATER_SIZE =
	TOTAL_WATER_SIZE * 0.5

local VERTEX_SPACING =
	LOGICAL_CHUNK_SIZE
	/ CELLS_PER_LOGICAL_CHUNK

--==============================================================
-- CAMERA PRIORITY
--==============================================================

-- Anything close to the camera stays alive regardless of facing.

local ALWAYS_ACTIVE_RADIUS = 240

-- Extra view angle beyond the actual horizontal FOV.

local VISIBLE_MARGIN_DEGREES = 25

-- Wake water significantly before it becomes visible.

local PREWARM_MARGIN_DEGREES = 80

local PREWARM_RATE_MULTIPLIER = 0.35
local PREWARM_MAX_HZ = 20

--==============================================================
-- UNDERWATER PERFORMANCE
--==============================================================

-- Full wave simulation down to 3 studs underwater.

local UNDERWATER_FULL_RATE_DEPTH = 3

-- Completely freeze surface animation at 20 studs underwater.

local UNDERWATER_FREEZE_DEPTH = 20

-- Controls how rapidly performance scales down.

local UNDERWATER_RATE_EXPONENT = 1.8

--==============================================================
-- DISTANCE LOD
--==============================================================

local LOD_NEAR_END = 160
local LOD_MID_END = 400
local LOD_FAR_END = 700

local LOD_MID_OCTAVES = 10
local LOD_FAR_OCTAVES = 7
local LOD_HORIZON_OCTAVES = 4

local LOD_NEAR_END_SQ = LOD_NEAR_END * LOD_NEAR_END
local LOD_MID_END_SQ = LOD_MID_END * LOD_MID_END
local LOD_FAR_END_SQ = LOD_FAR_END * LOD_FAR_END

--==============================================================
-- WATER APPEARANCE
--==============================================================

-- The visual ocean is rendered as several almost-coincident MeshParts
-- all driven by ONE EditableMesh. This deliberately recreates the
-- stacked-transparent-water trick used by the reference water.
--
-- IMPORTANT:
-- These are rendering layers only. Wave geometry is still calculated once.

local WATER_OVERLAY_TEMPLATE_NAME = "WaterOverlaySurfaceAppearance"

-- The source water this look came from was roughly 248 studs across, so
-- use that as the world-space repeat size. UVs are re-anchored whenever
-- the treadmill moves so the pattern stays locked to world coordinates.
local WATER_OVERLAY_WORLD_TILE_SIZE = 248

-- Layer offsets are intentionally tiny. Adjust these first if the white
-- intersection/rim is too strong or too weak.
local WATER_BASE_Y_OFFSET = -0.10
local WATER_MIDDLE_Y_OFFSET = -0.045
local WATER_SURFACE_Y_OFFSET = 0
local WATER_COASTLINE_Y_OFFSET = 0.055

-- Three underlying glass passes plus the white top pass.
-- The top pass matches the reference values you gave:
-- RGB 248,248,248 / Glass / Transparency 0.15 / SurfaceAppearance Overlay.
local WATER_BASE_COLOR = Color3.fromRGB(15, 75, 120)
local WATER_BASE_TRANSPARENCY = 0.58

local WATER_MIDDLE_COLOR = Color3.fromRGB(104, 143, 187)
local WATER_MIDDLE_TRANSPARENCY = 0.46

local WATER_SURFACE_COLOR = Color3.fromRGB(106,141,148)
local WATER_SURFACE_TRANSPARENCY = 0.30

local WATER_COASTLINE_COLOR = Color3.fromRGB(236, 235, 226)
local WATER_COASTLINE_TRANSPARENCY = 0

-- Temporary isolation switch while diagnosing the camera-angle visual bug.
-- Keep the generated WaveFoamVFX instance in the folder so this test can be
-- reversed without rebuilding the renderer's layer structure.
local HIDE_GENERATED_WAVELINES = false

local deepColor =
	Color3.fromRGB(
		0,
		10,
		40
	)

local midColor =
	Color3.fromRGB(
		5,
		50,
		100
	)

local foamColor =
	Color3.fromRGB(
		255,
		255,
		255
	)

local COLOR_STEPS = 48

--==============================================================
-- OPTIONAL FAR WATER
--==============================================================

-- Cheap flat world-locked water surrounding the detailed simulation.
-- It moves on the same grid as the detailed mesh and never follows camera
-- rotation, preventing the dark fill from sliding beneath transparent water.

local FAR_FILL_ENABLED = true

-- The ring reaches 4,500 studs from its center in each direction, matching
-- the previous 9,000 x 9,000 coverage area.
local FAR_WATER_OUTER_HALF_SIZE = 4500
local FAR_WATER_INNER_HALF_SIZE = HALF_WATER_SIZE
local FAR_WATER_BAND_SIZE =
	FAR_WATER_OUTER_HALF_SIZE
	- FAR_WATER_INNER_HALF_SIZE
local FAR_WATER_BAND_CENTER =
	FAR_WATER_INNER_HALF_SIZE
	+ FAR_WATER_BAND_SIZE * 0.5

-- Keep the ring just below the average plane. It touches the detailed mesh
-- only at its outer boundary instead of overlapping its full footprint.
local FAR_WATER_Y_OFFSET = -0.15

-- Distant water does not need to reveal the baseplate underneath it.
local FAR_WATER_TRANSPARENCY = 0.08

--==============================================================
-- QUALITY
--==============================================================

type QualityProfile = {
	name: string,
	octaves: number,
	waveHz: number,
}

local QUALITY_PROFILES: { QualityProfile } = {
	{
		name = "Ultra",
		octaves = 14,
		waveHz = 60,
	},

	{
		name = "High",
		octaves = 12,
		waveHz = 45,
	},

	{
		name = "Medium",
		octaves = 9,
		waveHz = 30,
	},

	{
		name = "Low",
		octaves = 6,
		waveHz = 20,
	},
}

local FORCE_QUALITY: string? = nil

local ADAPTIVE_QUALITY_ENABLED = true
local ADAPTIVE_START_DELAY = 5
local PERFORMANCE_SAMPLE_TIME = 2.5
local QUALITY_CHANGE_COOLDOWN = 6

--==============================================================
-- CLEANUP
--==============================================================

pcall(function()
	RunService:UnbindFromRenderStep(
		RENDER_STEP_NAME
	)
end)

-- Clean both previous prototypes if they exist.

for _, folderName in {
	"__ClientRealisticWaterV3",
	"__ClientRealisticWaterV4",
	} do

	local existing =
		Workspace:FindFirstChild(
			folderName
		)

	if existing then
		existing:Destroy()
	end
end

local waterFolder =
	Instance.new("Folder")

waterFolder.Name =
	WATER_FOLDER_NAME

waterFolder.Parent =
	Workspace

waterFolder:SetAttribute(
	"WaterVersion",
	"V4 Single EditableMesh"
)

waterFolder:SetAttribute(
	"LogicalRegions",
	LOGICAL_CHUNKS_PER_AXIS
		* LOGICAL_CHUNKS_PER_AXIS
)

waterFolder:SetAttribute(
	"Vertices",
	TOTAL_VERTICES
)

waterFolder:SetAttribute(
	"Triangles",
	TOTAL_TRIANGLES
)

--==============================================================
-- COLOR PALETTE
--==============================================================

local function lerpColor(
	a: Color3,
	b: Color3,
	alpha: number
): Color3

	return a:Lerp(
		b,
		m_clamp(
			alpha,
			0,
			1
		)
	)
end

local colorPalette: { Color3 } =
	table.create(
		COLOR_STEPS,
		deepColor
	)

for i = 1, COLOR_STEPS do

	local h =
		(i - 1)
		/ (COLOR_STEPS - 1)

	if h >= 0.70 then

		colorPalette[i] =
			foamColor

	elseif h >= 0.50 then

		colorPalette[i] =
			lerpColor(
				midColor,
				foamColor,
				(h - 0.5) / 0.35
			)

	else

		colorPalette[i] =
			lerpColor(
				deepColor,
				midColor,
				h / 0.5
			)
	end
end

--==============================================================
-- LOGICAL REGION TYPE
--==============================================================

type RegionState =
	"Visible"
| "Prewarm"
| "Hidden"

type LogicalRegion = {

	x: number,
	z: number,

	bufferIndices: { number },

	vertexIds: { number },
	colorIds: { number },

	positionValues: { Vector3 },
	colorValues: { Color3 },

	state: RegionState,

	accumulator: number,

	forceUpdate: boolean,
}

local regions: { LogicalRegion } = {}

for z = 0, LOGICAL_CHUNKS_PER_AXIS - 1 do

	for x = 0, LOGICAL_CHUNKS_PER_AXIS - 1 do

		table.insert(
			regions,

			{
				x = x,
				z = z,

				bufferIndices = {},

				vertexIds = {},
				colorIds = {},

				positionValues = {},
				colorValues = {},

				state = "Hidden",

				accumulator = 0,

				forceUpdate = true,
			}
		)
	end
end

local function getRegionIndex(
	x: number,
	z: number
): number

	return
		z
		* LOGICAL_CHUNKS_PER_AXIS
		+ x
		+ 1
end

--==============================================================
-- CREATE SINGLE EDITABLE MESH
--==============================================================

local editable =
	AssetService:CreateEditableMesh()

if not editable then

	error(
		"[Water V4] Roblox refused to allocate the single EditableMesh. "
			.. "Stop Play and begin a fresh Play session; the previous failed "
			.. "multi-mesh attempt may still have consumed the editable memory budget."
	)
end

local vertexIds =
	table.create(
		TOTAL_VERTICES,
		0
	)

local colorIds =
	table.create(
		TOTAL_VERTICES,
		0
	)

local uvIds =
	table.create(
		TOTAL_VERTICES,
		0
	)

local uvValues: { Vector2 } =
	table.create(
		TOTAL_VERTICES,
		Vector2.zero
	)

local baseLocalX =
	table.create(
		TOTAL_VERTICES,
		0
	)

local baseLocalZ =
	table.create(
		TOTAL_VERTICES,
		0
	)

local function vertexIndex(
	row: number,
	column: number
): number

	return
		(row - 1)
		* VERTICES_PER_AXIS
		+ column
end

--==============================================================
-- ADD VERTICES
--==============================================================

for row = 1, VERTICES_PER_AXIS do

	local localZ =
		-HALF_WATER_SIZE

		+ (row - 1)
		* VERTEX_SPACING

	for column = 1, VERTICES_PER_AXIS do

		local localX =
			-HALF_WATER_SIZE

			+ (column - 1)
			* VERTEX_SPACING

		local idx =
			vertexIndex(
				row,
				column
			)

		baseLocalX[idx] =
			localX

		baseLocalZ[idx] =
			localZ

		local vertexId =
			editable:AddVertex(
				Vector3.new(
					localX,
					0,
					localZ
				)
			)

		local colorId =
			editable:AddColor(
				deepColor,
				1
			)

		-- Start with local-space UVs. They are converted to world-locked UVs
		-- once the treadmill receives its first anchor position.
		local initialUV =
			Vector2.new(
				localX / WATER_OVERLAY_WORLD_TILE_SIZE,
				localZ / WATER_OVERLAY_WORLD_TILE_SIZE
			)

		local uvId =
			editable:AddUV(
				initialUV
			)

		vertexIds[idx] =
			vertexId

		colorIds[idx] =
			colorId

		uvIds[idx] =
			uvId

		uvValues[idx] =
			initialUV

		-- Assign this vertex to exactly one logical update region.
		--
		-- Border vertices are still physically shared by all triangles,
		-- because this is ONE continuous mesh.

		local regionX =
			m_min(
				LOGICAL_CHUNKS_PER_AXIS - 1,

				m_floor(
					(column - 1)
					/ CELLS_PER_LOGICAL_CHUNK
				)
			)

		local regionZ =
			m_min(
				LOGICAL_CHUNKS_PER_AXIS - 1,

				m_floor(
					(row - 1)
					/ CELLS_PER_LOGICAL_CHUNK
				)
			)

		local region =
			regions[
		getRegionIndex(
			regionX,
			regionZ
		)
		]

		table.insert(
			region.bufferIndices,
			idx
		)

		table.insert(
			region.vertexIds,
			vertexId
		)

		table.insert(
			region.colorIds,
			colorId
		)

		table.insert(
			region.positionValues,
			Vector3.new(
				localX,
				0,
				localZ
			)
		)

		table.insert(
			region.colorValues,
			deepColor
		)
	end
end

--==============================================================
-- ADD TRIANGLES
--==============================================================

for row = 1, TOTAL_CELLS_PER_AXIS do

	for column = 1, TOTAL_CELLS_PER_AXIS do

		local i00 =
			vertexIndex(
				row,
				column
			)

		local i10 =
			vertexIndex(
				row,
				column + 1
			)

		local i01 =
			vertexIndex(
				row + 1,
				column
			)

		local i11 =
			vertexIndex(
				row + 1,
				column + 1
			)

		local v00 = vertexIds[i00]
		local v10 = vertexIds[i10]
		local v01 = vertexIds[i01]
		local v11 = vertexIds[i11]

		local c00 = colorIds[i00]
		local c10 = colorIds[i10]
		local c01 = colorIds[i01]
		local c11 = colorIds[i11]

		local uv00 = uvIds[i00]
		local uv10 = uvIds[i10]
		local uv01 = uvIds[i01]
		local uv11 = uvIds[i11]

		local face1 =
			editable:AddTriangle(
				v00,
				v11,
				v01
			)

		editable:SetFaceColors(
			face1,

			{
				c00,
				c11,
				c01,
			}
		)

		editable:SetFaceUVs(
			face1,
			{
				uv00,
				uv11,
				uv01,
			}
		)

		local face2 =
			editable:AddTriangle(
				v00,
				v10,
				v11
			)

		editable:SetFaceColors(
			face2,

			{
				c00,
				c10,
				c11,
			}
		)

		editable:SetFaceUVs(
			face2,
			{
				uv00,
				uv10,
				uv11,
			}
		)
	end
end

--==============================================================
-- CREATE STACKED WATER MESHPARTS
--==============================================================

-- All four rendered layers reference this SAME EditableMesh.
-- This increases transparent rendering cost, but does NOT create four
-- separate wave simulations or four EditableMesh allocations.
local sharedWaterContent =
	Content.fromObject(
		editable
	)

local function createWaterLayer(
	name: string,
	color: Color3,
	transparency: number
): MeshPart

	local layer =
		AssetService:CreateMeshPartAsync(
			sharedWaterContent,
			{
				-- RenderFidelity cannot be assigned by a normal runtime LocalScript,
				-- so it is supplied when the MeshPart is created.
				RenderFidelity = Enum.RenderFidelity.Precise,
				CollisionFidelity = Enum.CollisionFidelity.Default,
			}
		)

	layer.Name =
		name

	layer.Anchored =
		true

	layer.CanCollide =
		false

	layer.CanQuery =
		false

	layer.CanTouch =
		false

	layer.CastShadow =
		false

	layer.DoubleSided =
		true

	layer.Material =
		Enum.Material.Glass

	layer.Color =
		color

	layer.Transparency =
		transparency

	layer.Parent =
		waterFolder

	return layer
end

-- Lowest/darkest pass.
local waterBaseMesh =
	createWaterLayer(
		"WaterBase",
		WATER_BASE_COLOR,
		WATER_BASE_TRANSPARENCY
	)

-- Light/refraction pass.
local waterMiddleMesh =
	createWaterLayer(
		"WaterMiddle",
		WATER_MIDDLE_COLOR,
		WATER_MIDDLE_TRANSPARENCY
	)

-- Main readable animated surface.
local waterMesh =
	createWaterLayer(
		"WaterSurface",
		WATER_SURFACE_COLOR,
		WATER_SURFACE_TRANSPARENCY
	)

-- White upper pass. This is the deliberate "engine abuse" layer that
-- attempts to reproduce the bright stylized intersection/rim effect.
local waveLinesMesh =
	createWaterLayer(
		"WaveFoamVFX",
		WATER_COASTLINE_COLOR,
		WATER_COASTLINE_TRANSPARENCY
	)

if HIDE_GENERATED_WAVELINES then
	waveLinesMesh.Transparency = 1
end

local function updateWaveFoamTransparency()
	if HIDE_GENERATED_WAVELINES or waterFolder:GetAttribute("TransparentOcean") == true then
		waveLinesMesh.Transparency = 1
		return
	end
	local override = waterFolder:GetAttribute("WaveFoamTransparencyOverride")
	waveLinesMesh.Transparency = if typeof(override) == "number"
		then math.clamp(override, 0, 1)
		else WATER_COASTLINE_TRANSPARENCY
end
waterFolder:GetAttributeChangedSignal("WaveFoamTransparencyOverride"):Connect(updateWaveFoamTransparency)

local function updateTransparentOcean()
	local transparent = waterFolder:GetAttribute("TransparentOcean") == true
	waterBaseMesh.Transparency = if transparent then 1 else WATER_BASE_TRANSPARENCY
	waterMiddleMesh.Transparency = if transparent then 1 else WATER_MIDDLE_TRANSPARENCY
	waterMesh.Transparency = if transparent then 1 else WATER_SURFACE_TRANSPARENCY
	for _, child in waterFolder:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 8) == "FarWater" then
			child.Transparency = if transparent then 1 else FAR_WATER_TRANSPARENCY
		end
	end
	updateWaveFoamTransparency()
end
waterFolder:GetAttributeChangedSignal("TransparentOcean"):Connect(updateTransparentOcean)
updateWaveFoamTransparency()
updateTransparentOcean()

-- Clone the preconfigured SurfaceAppearance ONLY onto the white upper
-- layer. We intentionally do NOT assign ColorMap from this LocalScript
-- because Roblox restricts that property at runtime.
local overlayTemplate =
	WaterAssets:FindFirstChild(
		WATER_OVERLAY_TEMPLATE_NAME
	)

if overlayTemplate and overlayTemplate:IsA("SurfaceAppearance") then
	local overlay =
		overlayTemplate:Clone()

	overlay.Name =
		"SurfaceAppearance"

	overlay.Parent =
		waveLinesMesh
else
	warn(
		"[Water V4] Missing SurfaceAppearance '"
			.. WATER_OVERLAY_TEMPLATE_NAME
			.. "' in ReplicatedStorage.Shared.Assets. Set ColorMap to rbxassetid://521579191 and AlphaMode to Overlay."
	)
end

waterFolder:SetAttribute(
	"StackedWaterLayers",
	4
)

--==============================================================
-- BATCH WRITE SUPPORT
--==============================================================

local batchWritesAvailable =
	false

do

	local id =
		vertexIds[1]

	local position =
		editable:GetPosition(
			id
		)

	local ok =
		pcall(function()

			editable:BatchSetValues(
				{ id },
				{ position }
			)
		end)

	batchWritesAvailable =
		ok
end

waterFolder:SetAttribute(
	"BatchWrites",
	batchWritesAvailable
)

--==============================================================
-- FAR WATER
--==============================================================

local farTiles: { Part } = {}
local farTileOffsets: { Vector3 } = {}

local function createFarTile(
	name: string,
	size: Vector3,
	offset: Vector3
)
	local tile =
		Instance.new("Part")

	tile.Name =
		name

	tile.Anchored =
		true

	tile.CanCollide =
		false

	tile.CanTouch =
		false

	tile.CanQuery =
		false

	tile.CastShadow =
		false

	tile.Size =
		size

	tile.Material =
		Enum.Material.Glass

	tile.Color =
		midColor

	tile.Transparency =
		if waterFolder:GetAttribute("TransparentOcean") == true
			then 1
			else FAR_WATER_TRANSPARENCY

	tile.Parent =
		waterFolder

	table.insert(
		farTiles,
		tile
	)

	table.insert(
		farTileOffsets,
		offset
	)
end

if FAR_FILL_ENABLED then
	local outerDiameter =
		FAR_WATER_OUTER_HALF_SIZE * 2

	local innerDiameter =
		FAR_WATER_INNER_HALF_SIZE * 2

	createFarTile(
		"FarWaterNorth",
		Vector3.new(
			outerDiameter,
			0.05,
			FAR_WATER_BAND_SIZE
		),
		Vector3.new(
			0,
			0,
			-FAR_WATER_BAND_CENTER
		)
	)

	createFarTile(
		"FarWaterSouth",
		Vector3.new(
			outerDiameter,
			0.05,
			FAR_WATER_BAND_SIZE
		),
		Vector3.new(
			0,
			0,
			FAR_WATER_BAND_CENTER
		)
	)

	createFarTile(
		"FarWaterWest",
		Vector3.new(
			FAR_WATER_BAND_SIZE,
			0.05,
			innerDiameter
		),
		Vector3.new(
			-FAR_WATER_BAND_CENTER,
			0,
			0
		)
	)

	createFarTile(
		"FarWaterEast",
		Vector3.new(
			FAR_WATER_BAND_SIZE,
			0.05,
			innerDiameter
		),
		Vector3.new(
			FAR_WATER_BAND_CENTER,
			0,
			0
		)
	)
end

local lastFarAnchorX: number? = nil
local lastFarAnchorZ: number? = nil

local function updateFarWater(
	cameraPosition: Vector3,
	surfaceY: number
)

	if not FAR_FILL_ENABLED then
		return
	end

	-- Use the same anchor grid as the detailed mesh. Translation moves both
	-- sections together, while camera rotation does not move either one.
	local anchorX =
		m_round(
			cameraPosition.X
			/ LOGICAL_CHUNK_SIZE
		)
		* LOGICAL_CHUNK_SIZE

	local anchorZ =
		m_round(
			cameraPosition.Z
			/ LOGICAL_CHUNK_SIZE
		)
		* LOGICAL_CHUNK_SIZE

	if
		anchorX == lastFarAnchorX
		and anchorZ == lastFarAnchorZ
	then
		return
	end

	for index, tile in ipairs(farTiles) do
		local offset =
			farTileOffsets[index]

		tile.CFrame =
			CFrame.new(
				anchorX + offset.X,
				surfaceY + FAR_WATER_Y_OFFSET,
				anchorZ + offset.Z
			)
	end

	lastFarAnchorX =
		anchorX

	lastFarAnchorZ =
		anchorZ
end

--==============================================================
-- QUALITY
--==============================================================

local currentQualityIndex = 1
local activeOctaves = QUALITY_PROFILES[1].octaves

local function applyQuality(
	index: number
)

	currentQualityIndex =
		m_clamp(
			index,
			1,
			#QUALITY_PROFILES
		)

	local profile =
		QUALITY_PROFILES[
	currentQualityIndex
	]

	activeOctaves =
		profile.octaves

	for _, region in ipairs(regions) do
		region.forceUpdate = true
	end

	waterFolder:SetAttribute(
		"WaterQuality",
		profile.name
	)

	waterFolder:SetAttribute(
		"WaveHz",
		profile.waveHz
	)
end

if FORCE_QUALITY then

	for index, profile in ipairs(
		QUALITY_PROFILES
		) do

		if profile.name == FORCE_QUALITY then

			currentQualityIndex =
				index

			break
		end
	end
end

applyQuality(
	currentQualityIndex
)

--==============================================================
-- ADAPTIVE QUALITY
--==============================================================

local runtime = 0
local sampleTimer = 0
local frameTotal = 0
local frameSamples = 0

local lastQualityChange =
	-math.huge

local function updateAdaptiveQuality(
	dt: number
)

	runtime += dt

	if
		not ADAPTIVE_QUALITY_ENABLED
		or FORCE_QUALITY ~= nil
	then
		return
	end

	if runtime < ADAPTIVE_START_DELAY then
		return
	end

	local frameTime =
		Stats.FrameTime

	if
		frameTime > 0
		and frameTime < 0.25
	then

		frameTotal +=
			frameTime

		frameSamples +=
			1
	end

	sampleTimer +=
		dt

	if
		sampleTimer
		< PERFORMANCE_SAMPLE_TIME
	then
		return
	end

	if frameSamples > 0 then

		local fps =
			1
			/ (
				frameTotal
				/ frameSamples
			)

		waterFolder:SetAttribute(
			"MeasuredFPS",
			m_round(fps)
		)

		if
			runtime - lastQualityChange
			>= QUALITY_CHANGE_COOLDOWN
		then

			local newIndex =
				currentQualityIndex

			if fps < 35 then

				newIndex =
					m_min(
						#QUALITY_PROFILES,
						currentQualityIndex + 2
					)

			elseif fps < 49 then

				newIndex =
					m_min(
						#QUALITY_PROFILES,
						currentQualityIndex + 1
					)

			elseif fps > 58 then

				newIndex =
					m_max(
						1,
						currentQualityIndex - 1
					)
			end

			if
				newIndex
				~= currentQualityIndex
			then

				applyQuality(
					newIndex
				)

				lastQualityChange =
					runtime
			end
		end
	end

	sampleTimer = 0
	frameTotal = 0
	frameSamples = 0
end

--==============================================================
-- UNDERWATER RATE
--==============================================================

local function getUnderwaterScale(
	cameraY: number,
	surfaceY: number
): (number, number)

	local depth =
		m_max(
			0,
			surfaceY - cameraY
		)

	if
		depth
		<= UNDERWATER_FULL_RATE_DEPTH
	then

		return 1, depth
	end

	if
		depth
		>= UNDERWATER_FREEZE_DEPTH
	then

		return 0, depth
	end

	local alpha =
		(
			UNDERWATER_FREEZE_DEPTH
			- depth
		)
		/
		(
			UNDERWATER_FREEZE_DEPTH
			- UNDERWATER_FULL_RATE_DEPTH
		)

	return
		m_clamp(
			alpha,
			0,
			1
		)
		^ UNDERWATER_RATE_EXPONENT,
		depth
end

--==============================================================
-- CAMERA DATA
--==============================================================

local fallbackForwardX = 0
local fallbackForwardZ = -1

local function getCameraData(
	camera: Camera
)

	local cf =
		camera.CFrame

	local position =
		cf.Position

	local rawRight =
		cf.RightVector

	local rightX =
		rawRight.X

	local rightZ =
		rawRight.Z

	local magnitude =
		m_sqrt(
			rightX * rightX
			+ rightZ * rightZ
		)

	local forwardX =
		fallbackForwardX

	local forwardZ =
		fallbackForwardZ

	if magnitude > 0.001 then

		rightX /=
			magnitude

		rightZ /=
			magnitude

		forwardX =
			rightZ

		forwardZ =
			-rightX

		fallbackForwardX =
			forwardX

		fallbackForwardZ =
			forwardZ
	end

	local viewport =
		camera.ViewportSize

	local aspect =
		16 / 9

	if viewport.Y > 0 then

		aspect =
			viewport.X
			/ viewport.Y
	end

	local horizontalHalfFov =
		m_atan(

			m_tan(
				m_rad(
					camera.FieldOfView
					* 0.5
				)
			)

			* aspect
		)

	return
		position,
		forwardX,
		forwardZ,
		horizontalHalfFov
end

--==============================================================
-- WORLD-LOCKED OVERLAY UVS
--==============================================================

local function updateWorldLockedUVs(
	anchorX: number,
	anchorZ: number
)
	for idx = 1, TOTAL_VERTICES do
		uvValues[idx] =
			Vector2.new(
				(anchorX + baseLocalX[idx]) / WATER_OVERLAY_WORLD_TILE_SIZE,
				(anchorZ + baseLocalZ[idx]) / WATER_OVERLAY_WORLD_TILE_SIZE
			)
	end

	-- BatchSetValues accepts stable attribute IDs, including UV IDs.
	if batchWritesAvailable then
		local ok =
			pcall(function()
				editable:BatchSetValues(
					uvIds,
					uvValues
				)
			end)

		if ok then
			return
		end
	end

	for idx = 1, TOTAL_VERTICES do
		editable:SetUV(
			uvIds[idx],
			uvValues[idx]
		)
	end
end

--==============================================================
-- TREADMILL
--==============================================================

local meshAnchorX: number? = nil
local meshAnchorZ: number? = nil

local function updateMeshAnchor(
	cameraPosition: Vector3,
	surfaceY: number
): boolean

	-- IMPORTANT:
	--
	-- LOGICAL_CHUNK_SIZE is exactly 18 vertex spacings.
	--
	-- Therefore when the treadmill moves one logical chunk,
	-- the new vertex lattice perfectly overlaps the old
	-- world-space lattice.

	local newX =
		m_round(
			cameraPosition.X
			/ LOGICAL_CHUNK_SIZE
		)
		* LOGICAL_CHUNK_SIZE

	local newZ =
		m_round(
			cameraPosition.Z
			/ LOGICAL_CHUNK_SIZE
		)
		* LOGICAL_CHUNK_SIZE

	local changed =
		meshAnchorX == nil
		or meshAnchorZ == nil
		or newX ~= meshAnchorX
		or newZ ~= meshAnchorZ

	meshAnchorX =
		newX

	meshAnchorZ =
		newZ

	if changed then
		updateWorldLockedUVs(
			newX,
			newZ
		)
	end

	-- Keep every rendered water pass locked to the exact same X/Z
	-- treadmill position. Only the tiny Y offsets differ.
	waterBaseMesh.CFrame =
		CFrame.new(
			newX,
			surfaceY + WATER_BASE_Y_OFFSET,
			newZ
		)

	waterMiddleMesh.CFrame =
		CFrame.new(
			newX,
			surfaceY + WATER_MIDDLE_Y_OFFSET,
			newZ
		)

	waterMesh.CFrame =
		CFrame.new(
			newX,
			surfaceY + WATER_SURFACE_Y_OFFSET,
			newZ
		)

	waveLinesMesh.CFrame =
		CFrame.new(
			newX,
			surfaceY + WATER_COASTLINE_Y_OFFSET,
			newZ
		)

	return changed
end

--==============================================================
-- REGION CLASSIFICATION
--==============================================================

local REGION_BOUNDING_RADIUS =
	LOGICAL_CHUNK_SIZE
	* 0.70710678

local function classifyRegion(
	region: LogicalRegion,

	cameraPosition: Vector3,

	forwardX: number,
	forwardZ: number,

	horizontalHalfFov: number
): RegionState

	assert(meshAnchorX ~= nil)
	assert(meshAnchorZ ~= nil)

	local centerX =
		meshAnchorX

	- HALF_WATER_SIZE

		+ (
			region.x + 0.5
		)
		* LOGICAL_CHUNK_SIZE

	local centerZ =
		meshAnchorZ

	- HALF_WATER_SIZE

		+ (
			region.z + 0.5
		)
		* LOGICAL_CHUNK_SIZE

	local dx =
		centerX
	- cameraPosition.X

	local dz =
		centerZ
	- cameraPosition.Z

	local distance =
		m_sqrt(
			dx * dx
			+ dz * dz
		)

	if
		distance
		<= ALWAYS_ACTIVE_RADIUS
		+ REGION_BOUNDING_RADIUS
	then

		return "Visible"
	end

	if distance <= 0.001 then
		return "Visible"
	end

	local dirX =
		dx / distance

	local dirZ =
		dz / distance

	local dot =
		m_clamp(

			forwardX * dirX
			+ forwardZ * dirZ,

			-1,
			1
		)

	local angle =
		m_acos(dot)

	-- Region width itself gets included in the visibility test.

	local angularRadius =
		m_atan(

			REGION_BOUNDING_RADIUS

			/
			m_max(
				1,

				distance
				- REGION_BOUNDING_RADIUS
			)
		)

	local visibleLimit =
		horizontalHalfFov

		+ m_rad(
			VISIBLE_MARGIN_DEGREES
		)

	local prewarmLimit =
		horizontalHalfFov

		+ m_rad(
			PREWARM_MARGIN_DEGREES
		)

	if
		angle - angularRadius
		<= visibleLimit
	then

		return "Visible"
	end

	if
		angle - angularRadius
		<= prewarmLimit
	then

		return "Prewarm"
	end

	return "Hidden"
end

--==============================================================
-- OCTAVE LOD
--==============================================================

local function getOctaveCount(
	distanceSquared: number
): number

	if distanceSquared > LOD_FAR_END_SQ then

		return
			m_min(
				activeOctaves,
				LOD_HORIZON_OCTAVES
			)

	elseif distanceSquared > LOD_MID_END_SQ then

		return
			m_min(
				activeOctaves,
				LOD_FAR_OCTAVES
			)

	elseif distanceSquared > LOD_NEAR_END_SQ then

		return
			m_min(
				activeOctaves,
				LOD_MID_OCTAVES
			)
	end

	return activeOctaves
end

--==============================================================
-- COLOR
--==============================================================

local function getWaveColor(
	height: number,
	octaves: number
): Color3

	local amplitude =
		WaterWaveSampler.GetCumulativeAmplitude(
			octaves
		)

	if amplitude <= 0 then
		return deepColor
	end

	local h =
		m_clamp(
			height / amplitude,
			0,
			1
		)

	local index =
		m_floor(
			h
			* (COLOR_STEPS - 1)
		)
		+ 1

	return
		colorPalette[index]
end

--==============================================================
-- UPDATE LOGICAL REGION
--==============================================================

local function calculateRegion(
	region: LogicalRegion,
	cameraPosition: Vector3
)

	assert(meshAnchorX ~= nil)
	assert(meshAnchorZ ~= nil)

	local indices =
		region.bufferIndices

	local positionValues =
		region.positionValues

	local colorValues =
		region.colorValues

	for localIndex = 1, #indices do

		local bufferIndex =
			indices[localIndex]

		local localX =
			baseLocalX[
		bufferIndex
		]

		local localZ =
			baseLocalZ[
		bufferIndex
		]

		local worldX =
			meshAnchorX
			+ localX

		local worldZ =
			meshAnchorZ
			+ localZ

		local cameraDX =
			worldX
		- cameraPosition.X

		local cameraDZ =
			worldZ
		- cameraPosition.Z

		local distanceSquared =
			cameraDX * cameraDX
			+ cameraDZ * cameraDZ

		local octaves =
			getOctaveCount(
				distanceSquared
			)

		local sample =
			WaterWaveSampler.Sample(
				worldX,
				worldZ,
				currentWaveTime,
				octaves
			)

		local waveY = sample.Height
		local displacementX = sample.Displacement.X
		local displacementZ = sample.Displacement.Z

		positionValues[localIndex] =
			Vector3.new(

				localX
				+ displacementX,

				waveY,

				localZ
				+ displacementZ
			)

		colorValues[localIndex] =
			getWaveColor(
				waveY,
				octaves
			)
	end
end

--==============================================================
-- WRITE REGION
--==============================================================

local function writeRegion(
	region: LogicalRegion
)

	if batchWritesAvailable then

		editable:BatchSetValues(
			region.vertexIds,
			region.positionValues
		)

		editable:BatchSetValues(
			region.colorIds,
			region.colorValues
		)

	else

		for i = 1, #region.vertexIds do

			editable:SetPosition(
				region.vertexIds[i],
				region.positionValues[i]
			)

			editable:SetColor(
				region.colorIds[i],
				region.colorValues[i]
			)
		end
	end
end

--==============================================================
-- MAIN LOOP
--==============================================================

local previousUnderwaterScale =
	1

RunService:BindToRenderStep(

	RENDER_STEP_NAME,

	Enum.RenderPriority.Camera.Value + 1,

	function(dt: number)

		updateAdaptiveQuality(
			dt
		)

		local camera =
			Workspace.CurrentCamera

		if not camera then
			return
		end

		local surfaceY =
			getSurfaceY()

		local cameraPosition,
		forwardX,
		forwardZ,
		horizontalHalfFov =
			getCameraData(
				camera
			)

		local anchorChanged =
			updateMeshAnchor(
				cameraPosition,
				surfaceY
			)

		updateFarWater(
			cameraPosition,
			surfaceY
		)

		local underwaterScale,
		underwaterDepth =
			getUnderwaterScale(
				cameraPosition.Y,
				surfaceY
			)

		-- Coming back toward surface:
		-- wake relevant water immediately.

		if
			previousUnderwaterScale <= 0
			and underwaterScale > 0
		then

			for _, region in ipairs(regions) do
				region.forceUpdate = true
			end
		end

		previousUnderwaterScale =
			underwaterScale

		waterFolder:SetAttribute(
			"UnderwaterDepth",

			m_round(
				underwaterDepth * 100
			)
				/ 100
		)

		waterFolder:SetAttribute(
			"WaveUpdateScale",

			m_round(
				underwaterScale * 100
			)
				/ 100
		)

		waterFolder:SetAttribute(
			"SurfaceFrozen",

			underwaterScale <= 0
		)

		-- Current WORLD wave time. This remains current even when
		-- regions are frozen, so waking regions reconstruct the same
		-- surface phase as the shared sampler.
		currentWaveTime =
			WaterWaveSampler.GetTime()

		local profile =
			QUALITY_PROFILES[
		currentQualityIndex
		]

		local visibleHz =
			profile.waveHz
			* underwaterScale

		local prewarmHz =
			m_min(

				PREWARM_MAX_HZ,

				profile.waveHz
				* PREWARM_RATE_MULTIPLIER
			)

			* underwaterScale

		local visibleCount = 0
		local prewarmCount = 0
		local hiddenCount = 0
		local updatedCount = 0

		for _, region in ipairs(regions) do

			local oldState =
				region.state

			local newState =
				classifyRegion(

					region,

					cameraPosition,

					forwardX,
					forwardZ,

					horizontalHalfFov
				)

			region.state =
				newState

			if newState == "Visible" then

				visibleCount += 1

			elseif newState == "Prewarm" then

				prewarmCount += 1

			else

				hiddenCount += 1
			end

			-- Deep underwater:
			--
			-- stop all expensive surface calculations.
			--
			-- We still move the overall treadmill MeshPart,
			-- but waves are reconstructed once we approach
			-- the surface again.

			if underwaterScale <= 0 then

				continue
			end

			local targetHz = 0

			if newState == "Visible" then

				targetHz =
					visibleHz

			elseif newState == "Prewarm" then

				targetHz =
					prewarmHz
			end

			local enteredActiveRegion =
				newState ~= "Hidden"
				and oldState == "Hidden"

			-- If the treadmill moved, all currently useful
			-- regions need their world-space wave state updated
			-- on this same rendered frame.

			local immediate =
				region.forceUpdate
				or enteredActiveRegion
				or (
					anchorChanged
					and newState ~= "Hidden"
				)

			local due =
				false

			if targetHz > 0 then

				region.accumulator +=
					dt

				local interval =
					1 / targetHz

				if
					region.accumulator
					>= interval
				then

					due =
						true

					region.accumulator %=
						interval
				end
			end

			if immediate or due then

				calculateRegion(
					region,
					cameraPosition
				)

				writeRegion(
					region
				)

				region.forceUpdate =
					false

				updatedCount +=
					1
			end
		end

		waterFolder:SetAttribute(
			"VisibleRegions",
			visibleCount
		)

		waterFolder:SetAttribute(
			"PrewarmRegions",
			prewarmCount
		)

		waterFolder:SetAttribute(
			"FrozenRegions",
			hiddenCount
		)

		waterFolder:SetAttribute(
			"RegionsUpdatedThisFrame",
			updatedCount
		)
	end
)
