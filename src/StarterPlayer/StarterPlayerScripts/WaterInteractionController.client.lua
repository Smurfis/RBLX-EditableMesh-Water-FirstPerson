--!strict

-- First rigid buoyancy milestone. This controller is deliberately opt-in:
-- only instances tagged WaterInteractable are ever touched.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WaterConfig = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterConfig")
)

local WaterWaveSampler = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("WaterWaveSampler")
)

local TAG_NAME = "WaterInteractable"
local SAMPLE_OCTAVES = 8
local POSITION_RESPONSE = 7
local MAX_UPDATE_DISTANCE = 500

type InteractableState = {
	instance: Instance,
	root: BasePart,
	model: Model?,
	currentY: number,
}

local states: { [Instance]: InteractableState } = {}
local warnedMissingPrimary: { [Model]: boolean } = {}

local function getRoot(instance: Instance): (BasePart?, Model?)
	if instance:IsA("BasePart") then
		return instance, nil
	end

	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if not primaryPart then
			if not warnedMissingPrimary[instance] then
				warnedMissingPrimary[instance] = true
				warn(
					"[WaterInteraction] WaterInteractable Model '",
					instance:GetFullName(),
					"' has no PrimaryPart; ignoring it."
				)
			end
			return nil, instance
		end
		return primaryPart, instance
	end

	return nil, nil
end

local function addInteractable(instance: Instance)
	if states[instance] then
		return
	end

	local root, model = getRoot(instance)
	if not root then
		return
	end

	states[instance] = {
		instance = instance,
		root = root,
		model = model,
		currentY = root.Position.Y,
	}
end

local function removeInteractable(instance: Instance)
	states[instance] = nil
end

for _, instance in CollectionService:GetTagged(TAG_NAME) do
	addInteractable(instance)
end

CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(addInteractable)
CollectionService:GetInstanceRemovedSignal(TAG_NAME):Connect(removeInteractable)

local function getNumberAttribute(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function isEnabled(instance: Instance): boolean
	local value = instance:GetAttribute("WaterEnabled")
	return value ~= false
end

local function moveVertically(state: InteractableState, targetY: number)
	local root = state.root
	local deltaY = targetY - root.Position.Y
	if state.model then
		state.model:PivotTo(state.model:GetPivot() + Vector3.new(0, deltaY, 0))
		return
	end

	root.CFrame = CFrame.new(
		root.Position.X,
		targetY,
		root.Position.Z
	) * root.CFrame.Rotation
end

local function updateState(state: InteractableState, dt: number, cameraPosition: Vector3)
	local instance = state.instance
	if not instance.Parent or not state.root.Parent then
		states[instance] = nil
		return
	end

	if not isEnabled(instance) then
		return
	end

	local root = state.root
	local offset = getNumberAttribute(instance, "WaterVerticalOffset", 0)
	local strength = math.max(
		0,
		getNumberAttribute(instance, "WaterBuoyancyStrength", 1)
	)

	local horizontalDistance = (
		Vector2.new(root.Position.X, root.Position.Z)
		- Vector2.new(cameraPosition.X, cameraPosition.Z)
	).Magnitude
	if horizontalDistance > MAX_UPDATE_DISTANCE then
		return
	end

	local sample = WaterWaveSampler.Sample(
		root.Position.X,
		root.Position.Z,
		WaterWaveSampler.GetTime(),
		SAMPLE_OCTAVES
	)
	local targetY = WaterConfig.GetSurfaceY() + sample.Height * strength + offset
	local alpha = 1 - math.exp(-POSITION_RESPONSE * dt)
	state.currentY = state.currentY + (targetY - state.currentY) * alpha
	moveVertically(state, state.currentY)
end

RunService:BindToRenderStep(
	"WaterInteractionController",
	Enum.RenderPriority.Camera.Value + 2,
	function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		for _, state in states do
			updateState(state, dt, camera.CFrame.Position)
		end
	end
)
