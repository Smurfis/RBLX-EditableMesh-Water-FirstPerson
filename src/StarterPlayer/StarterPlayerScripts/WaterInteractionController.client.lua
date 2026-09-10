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
local POSITION_RESPONSE = 7
local ROTATION_RESPONSE = 6
local MAX_UPDATE_DISTANCE = 500

local PROFILES = {
	SmallProp = { SampleCount = 1, Octaves = 8, UpdateHz = 30 },
	MediumProp = { SampleCount = 3, Octaves = 8, UpdateHz = 30 },
	Boat = { SampleCount = 6, Octaves = 6, UpdateHz = 30 },
	LargeShip = { SampleCount = 8, Octaves = 4, UpdateHz = 20 },
}

type InteractableState = {
	instance: Instance,
	root: BasePart,
	model: Model?,
	currentY: number,
	originPosition: Vector3,
	yaw: number,
	baseRotation: CFrame,
	currentRotation: CFrame,
	targetY: number,
	targetPosition: Vector3,
	targetRotation: CFrame,
	updateTimer: number,
}

local states: { [Instance]: InteractableState } = {}
local warnedMissingPrimary: { [Model]: boolean } = {}

local function getRoot(instance: Instance): (BasePart?, Model?)
	if instance:IsA("BasePart") then
		return instance, nil
	end

	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart", true)
		if not primaryPart then
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
		if instance:IsA("Model") then
			task.delay(0.5, function()
				if instance.Parent and CollectionService:HasTag(instance, TAG_NAME) then
					addInteractable(instance)
				end
			end)
		end
		return
	end

	states[instance] = {
		instance = instance,
		root = root,
		model = model,
		currentY = root.Position.Y,
		originPosition = root.Position,
		yaw = select(2, root.CFrame:ToOrientation()),
		baseRotation = root.CFrame.Rotation,
		currentRotation = root.CFrame.Rotation,
		targetY = root.Position.Y,
		targetPosition = root.Position,
		targetRotation = root.CFrame.Rotation,
		updateTimer = 0,
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

local function getProfile(instance: Instance)
	local name = instance:GetAttribute("WaterProfile")
	if typeof(name) == "string" then
		local normalized = string.lower(name)
		if normalized == "medprop" then
			return PROFILES.MediumProp
		end
		for profileName, profile in PROFILES do
			if string.lower(profileName) == normalized then
				return profile
			end
		end
	end
	return PROFILES.SmallProp
end

local function getObjectSize(state: InteractableState): Vector3
	if state.model then
		return state.model:GetExtentsSize()
	end
	return state.root.Size
end

local function getSampleOffsets(state: InteractableState, sampleCount: number): { Vector3 }
	if sampleCount <= 1 then
		return { Vector3.zero }
	end

	local size = getObjectSize(state)
	local halfX = math.max(size.X * 0.4, 0.5)
	local halfZ = math.max(size.Z * 0.4, 0.5)

	if sampleCount <= 3 then
		return {
			Vector3.zero,
			Vector3.new(0, 0, -halfZ),
			Vector3.new(0, 0, halfZ),
		}
	end

	if sampleCount <= 6 then
		return {
			Vector3.new(-halfX, 0, -halfZ),
			Vector3.new(halfX, 0, -halfZ),
			Vector3.new(-halfX, 0, 0),
			Vector3.new(halfX, 0, 0),
			Vector3.new(-halfX, 0, halfZ),
			Vector3.new(halfX, 0, halfZ),
		}
	end

	return {
		Vector3.new(-halfX, 0, -halfZ),
		Vector3.new(0, 0, -halfZ),
		Vector3.new(halfX, 0, -halfZ),
		Vector3.new(-halfX, 0, halfZ),
		Vector3.new(0, 0, halfZ),
		Vector3.new(halfX, 0, halfZ),
		Vector3.new(-halfX, 0, 0),
		Vector3.new(halfX, 0, 0),
	}
end

local function sampleObject(state: InteractableState, profile)
	local override = state.instance:GetAttribute("WaterSampleCount")
	local sampleCount = profile.SampleCount
	if typeof(override) == "number" then
		sampleCount = math.clamp(math.floor(override), 1, 8)
	end

	local offsets = getSampleOffsets(state, sampleCount)
	local time = WaterWaveSampler.GetTime()
	local totalHeight = 0
	local totalNormal = Vector3.zero
	local totalDisplacement = Vector3.zero
	local frontHeight = 0
	local rearHeight = 0
	local leftHeight = 0
	local rightHeight = 0
	local frontCount = 0
	local rearCount = 0
	local leftCount = 0
	local rightCount = 0

	local sampleFrame = CFrame.Angles(0, state.yaw, 0)
	for _, localOffset in offsets do
		local worldPoint = state.root.Position + sampleFrame:VectorToWorldSpace(localOffset)
		local sample = WaterWaveSampler.Sample(
			worldPoint.X,
			worldPoint.Z,
			time,
			profile.Octaves
		)
		totalHeight += sample.Height
		totalNormal += sample.Normal
		totalDisplacement += sample.Displacement

		if localOffset.Z < -0.01 then
			frontHeight += sample.Height
			frontCount += 1
		elseif localOffset.Z > 0.01 then
			rearHeight += sample.Height
			rearCount += 1
		end
		if localOffset.X < -0.01 then
			leftHeight += sample.Height
			leftCount += 1
		elseif localOffset.X > 0.01 then
			rightHeight += sample.Height
			rightCount += 1
		end
	end

	local averageHeight = totalHeight / #offsets
	local normal = (totalNormal / #offsets).Unit
	if #offsets > 1 then
		local size = getObjectSize(state)
		local depth = math.max(size.Z * 0.8, 1)
		local width = math.max(size.X * 0.8, 1)
		local averageFront = if frontCount > 0 then frontHeight / frontCount else averageHeight
		local averageRear = if rearCount > 0 then rearHeight / rearCount else averageHeight
		local averageLeft = if leftCount > 0 then leftHeight / leftCount else averageHeight
		local averageRight = if rightCount > 0 then rightHeight / rightCount else averageHeight
		normal = Vector3.new(
			-(averageRight - averageLeft) / width,
			1,
			(averageFront - averageRear) / depth
		).Unit
	end

	return averageHeight, sampleFrame:VectorToWorldSpace(normal), totalDisplacement / #offsets
end

local function movePose(state: InteractableState, targetPosition: Vector3, rotation: CFrame)
	local root = state.root
	local targetCFrame = CFrame.new(
		targetPosition.X,
		targetPosition.Y,
		targetPosition.Z
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
	local horizontalDistance = (
		Vector2.new(root.Position.X, root.Position.Z)
		- Vector2.new(cameraPosition.X, cameraPosition.Z)
	).Magnitude
	if horizontalDistance > MAX_UPDATE_DISTANCE then
		return
	end

	local profile = getProfile(instance)
	state.updateTimer -= dt
	if state.updateTimer <= 0 then
		local offset = getNumberAttribute(instance, "WaterVerticalOffset", 0)
		local strength = math.max(
			0,
			getNumberAttribute(instance, "WaterBuoyancyStrength", 1)
		)
		local height, normal, displacement = sampleObject(state, profile)
		state.targetY = WaterConfig.GetSurfaceY() + height * strength + offset
		if instance:GetAttribute("WaterAllowHorizontalDrift") == true then
			state.targetPosition = state.originPosition + displacement
		else
			state.targetPosition = Vector3.new(
				state.root.Position.X,
				0,
				state.root.Position.Z
			)
		end

		local rotationStrength = math.max(
			0,
			getNumberAttribute(instance, "WaterRotationStrength", 1)
		)
		if rotationStrength <= 0 then
			state.targetRotation = state.baseRotation
		else
			local yawFrame = CFrame.Angles(0, state.yaw, 0)
			local localNormal = yawFrame:VectorToObjectSpace(normal)
			local pitch = -math.atan2(localNormal.Z, localNormal.Y) * rotationStrength
			local roll = math.atan2(localNormal.X, localNormal.Y) * rotationStrength
			state.targetRotation = yawFrame * CFrame.Angles(pitch, 0, roll)
		end
		state.updateTimer = 1 / profile.UpdateHz
	end

	local alpha = 1 - math.exp(-POSITION_RESPONSE * dt)
	state.currentY = state.currentY + (state.targetY - state.currentY) * alpha
	local rotationAlpha = 1 - math.exp(-ROTATION_RESPONSE * dt)
	state.currentRotation = state.currentRotation:Lerp(state.targetRotation, rotationAlpha)

	movePose(
		state,
		Vector3.new(
			state.targetPosition.X,
			state.currentY,
			state.targetPosition.Z
		),
		state.currentRotation
	)
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
