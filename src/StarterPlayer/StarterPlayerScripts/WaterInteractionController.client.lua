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
local ROTATION_RESPONSE = 6
local MAX_UPDATE_DISTANCE = 500

type InteractableState = {
	instance: Instance,
	root: BasePart,
	model: Model?,
	currentY: number,
	yaw: number,
	currentRotation: CFrame,
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
		yaw = select(2, root.CFrame:ToOrientation()),
		currentRotation = root.CFrame.Rotation,
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

local function movePose(state: InteractableState, targetY: number, rotation: CFrame)
	local root = state.root
	local targetCFrame = CFrame.new(
		root.Position.X,
		targetY,
		root.Position.Z
	) * rotation

	if state.model then
		local delta = targetCFrame * root.CFrame:Inverse()
		state.model:PivotTo(delta * state.model:GetPivot())
		return
	end

	root.CFrame = targetCFrame
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

	local rotationStrength = math.max(
		0,
		getNumberAttribute(instance, "WaterRotationStrength", 1)
	)
	local yawFrame = CFrame.Angles(0, state.yaw, 0)
	local localNormal = yawFrame:VectorToObjectSpace(sample.Normal)
	local pitch = -math.atan2(localNormal.Z, localNormal.Y) * rotationStrength
	local roll = math.atan2(localNormal.X, localNormal.Y) * rotationStrength
	local targetRotation = yawFrame * CFrame.Angles(pitch, 0, roll)
	local rotationAlpha = 1 - math.exp(-ROTATION_RESPONSE * dt)
	state.currentRotation = state.currentRotation:Lerp(targetRotation, rotationAlpha)

	movePose(state, state.currentY, state.currentRotation)
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
