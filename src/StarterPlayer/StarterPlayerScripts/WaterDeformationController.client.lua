--!strict

-- Opt-in EditableMesh deformation experiment. Source MeshParts are never
-- destroyed; a local runtime visual is created only when import succeeds.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WaterWaveSampler = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterWaveSampler")
)

local TAG_NAME = "WaterDeformable"
local DEFAULT_OCTAVES = 6
local DEFAULT_VERTICAL_STRENGTH = 1
local DEFAULT_HORIZONTAL_STRENGTH = 0.25
local DEFAULT_UPDATE_HZ = 30
local DEFAULT_MAX_DISTANCE = 250

type DeformState = {
	source: MeshPart,
	editable: EditableMesh,
	runtime: MeshPart,
	vertexIds: { number },
	originalPositions: { [number]: Vector3 },
	updateTimer: number,
	originalLocalTransparency: number,
}

local states: { [MeshPart]: DeformState } = {}
local warnedInstances: { [Instance]: boolean } = {}

local function getNumberAttribute(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function isEnabled(source: MeshPart): boolean
	local value = source:GetAttribute("WaterDeformEnabled")
	return value ~= false
end

local function copySurfaceAppearance(source: MeshPart, runtime: MeshPart)
	for _, child in source:GetChildren() do
		if child:IsA("SurfaceAppearance") then
			child:Clone().Parent = runtime
		end
	end
end

local function destroyState(source: MeshPart)
	local state = states[source]
	if not state then
		return
	end

	if source.Parent then
		source.LocalTransparencyModifier = state.originalLocalTransparency
	end
	if state.runtime.Parent then
		state.runtime:Destroy()
	end
	states[source] = nil
end

local function createState(source: MeshPart)
	if states[source] or not source.Parent or not isEnabled(source) then
		return
	end

	local success, editableOrError = pcall(function()
		return AssetService:CreateEditableMeshAsync(Content.fromObject(source))
	end)
	if not success or not editableOrError then
		if not warnedInstances[source] then
			warnedInstances[source] = true
			warn(
				"[WaterDeformation] Could not create EditableMesh for '",
				source:GetFullName(),
				"'. Leaving the source MeshPart unchanged. API/runtime error: ",
				tostring(editableOrError)
			)
		end
		return
	end

	local editable = editableOrError :: EditableMesh
	local vertexIds = editable:GetVertices()
	local originalPositions: { [number]: Vector3 } = {}
	for _, vertexId in vertexIds do
		originalPositions[vertexId] = editable:GetPosition(vertexId)
	end

	local meshSuccess, runtimeOrError = pcall(function()
		return AssetService:CreateMeshPartAsync(
			Content.fromObject(editable),
			{
				RenderFidelity = Enum.RenderFidelity.Precise,
				CollisionFidelity = Enum.CollisionFidelity.Default,
			}
		)
	end)
	if not meshSuccess or not runtimeOrError then
		editable:Destroy()
		if not warnedInstances[source] then
			warnedInstances[source] = true
			warn(
				"[WaterDeformation] Could not create runtime MeshPart for '",
				source:GetFullName(),
				"'. Leaving the source MeshPart unchanged. API/runtime error: ",
				tostring(runtimeOrError)
			)
		end
		return
	end

	local runtime = runtimeOrError :: MeshPart
	runtime.Name = "__WaterDeformable_" .. source.Name
	runtime.CFrame = source.CFrame
	runtime.Anchored = true
	runtime.CanCollide = false
	runtime.CanTouch = false
	runtime.CanQuery = false
	runtime.CastShadow = source.CastShadow
	runtime.Color = source.Color
	runtime.Material = source.Material
	runtime.Transparency = source.Transparency
	runtime.Parent = source.Parent
	copySurfaceAppearance(source, runtime)

	local state: DeformState = {
		source = source,
		editable = editable,
		runtime = runtime,
		vertexIds = vertexIds,
		originalPositions = originalPositions,
		updateTimer = 0,
		originalLocalTransparency = source.LocalTransparencyModifier,
	}
	states[source] = state
	source.LocalTransparencyModifier = 1
end

local function addSource(instance: Instance)
	if not instance:IsA("MeshPart") then
		if not warnedInstances[instance] then
			warnedInstances[instance] = true
			warn("[WaterDeformation] WaterDeformable requires a MeshPart; ignoring '", instance:GetFullName(), "'.")
		end
		return
	end
	task.spawn(createState, instance)
end

for _, instance in CollectionService:GetTagged(TAG_NAME) do
	addSource(instance)
end
CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(addSource)
CollectionService:GetInstanceRemovedSignal(TAG_NAME):Connect(function(instance)
	if instance:IsA("MeshPart") then
		destroyState(instance)
	end
end)

local function updateState(state: DeformState, dt: number, cameraPosition: Vector3)
	local source = state.source
	if not source.Parent or not state.runtime.Parent then
		destroyState(source)
		return
	end
	if not isEnabled(source) then
		destroyState(source)
		return
	end

	local maxDistance = math.max(
		0,
		getNumberAttribute(source, "WaterDeformMaxDistance", DEFAULT_MAX_DISTANCE)
	)
	if (source.Position - cameraPosition).Magnitude > maxDistance then
		return
	end

	local updateHz = math.max(
		1,
		getNumberAttribute(source, "WaterDeformUpdateHz", DEFAULT_UPDATE_HZ)
	)
	state.updateTimer -= dt
	if state.updateTimer > 0 then
		return
	end
	state.updateTimer = 1 / updateHz

	local octaves = math.clamp(
		math.floor(getNumberAttribute(source, "WaterDeformOctaves", DEFAULT_OCTAVES)),
		1,
		WaterWaveSampler.GetMaxOctaves()
	)
	local verticalStrength = getNumberAttribute(
		source,
		"WaterDeformVerticalStrength",
		DEFAULT_VERTICAL_STRENGTH
	)
	local horizontalStrength = getNumberAttribute(
		source,
		"WaterDeformHorizontalStrength",
		DEFAULT_HORIZONTAL_STRENGTH
	)
	local time = WaterWaveSampler.GetTime()
	local positions = table.create(#state.vertexIds)

	for index, vertexId in state.vertexIds do
		local originalLocal = state.originalPositions[vertexId]
		local originalWorld = source.CFrame:PointToWorldSpace(originalLocal)
		local sample = WaterWaveSampler.Sample(
			originalWorld.X,
			originalWorld.Z,
			time,
			octaves
		)
		local targetWorld = originalWorld + Vector3.new(
			sample.Displacement.X * horizontalStrength,
			sample.Height * verticalStrength,
			sample.Displacement.Z * horizontalStrength
		)
		positions[index] = source.CFrame:PointToObjectSpace(targetWorld)
	end

	local batchSuccess = pcall(function()
		state.editable:BatchSetValues(state.vertexIds, positions)
	end)
	if not batchSuccess then
		for index, vertexId in state.vertexIds do
			state.editable:SetPosition(vertexId, positions[index])
		end
	end

	state.runtime.CFrame = source.CFrame
end

RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	for _, state in states do
		updateState(state, dt, camera.CFrame.Position)
	end
end)

