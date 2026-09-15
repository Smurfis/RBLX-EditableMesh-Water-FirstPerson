-- StarterCharacterScripts > SparkFollower
-- Local Spark companion controller

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local character = script.Parent

local head = character:WaitForChild("Head") :: BasePart
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------

----------------------------------------------------------------
-- SPARK CAMERA TYPE SETTINGS
----------------------------------------------------------------


-- Third-person position relative to the player's facing direction.
local THIRD_PERSON_OFFSET = Vector3.new(
	2.5,   -- right
	1.2,   -- up
	0.25   -- forward/back
)

-- First-person position relative to the camera.
-- -Z = in front of the camera.
local FIRST_PERSON_OFFSET = Vector3.new(
	4,  -- right side of view
	1.6,  -- slightly above eye level
	-4   -- in front
)

local SMOOTH_TIME = 0.55
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
local TRAIL_LIFETIME = 0.20

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
-- CAMERA MODE ATTRIBUTE
----------------------------------------------------------------

-- Temporary default until your camera controller owns this.
if player:GetAttribute("FirstPerson") == nil then
	player:SetAttribute("FirstPerson", true)
end

local isFirstPerson = player:GetAttribute("FirstPerson") == true

local firstPersonConnection =
	player:GetAttributeChangedSignal("FirstPerson"):Connect(function()
		isFirstPerson = player:GetAttribute("FirstPerson") == true
	end)

----------------------------------------------------------------
-- GET SPARK
----------------------------------------------------------------

local sparkModels =
	ReplicatedStorage
		:WaitForChild("Models")
		:WaitForChild("NPCs")
		:WaitForChild("SparkModels")

local sparkTemplate =
	sparkModels:WaitForChild("Spark")

assert(
	sparkTemplate:IsA("Model"),
	"ReplicatedStorage.Models.NPCs.SparkModels.Spark must be a Model"
)

local spark = sparkTemplate:Clone()
spark.Name = player.Name .."'s Spark"
spark:ScaleTo(0.5)
spark.Parent = workspace

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

	local ray = camera:ViewportPointToRay(
		viewportSize.X * 0.5,
		viewportSize.Y * 0.5
	)

	local result = workspace:Raycast(
		ray.Origin,
		ray.Direction * LOOK_DISTANCE,
		raycastParams
	)

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

	local position =
		pivot.Position
		+ Vector3.new(
			0,
			size.Y * 0.5 + TARGET_HOVER_HEIGHT,
			0
		)

	return CFrame.new(position)
end

----------------------------------------------------------------
-- PREPARE RIG
----------------------------------------------------------------

local body = spark:FindFirstChild("SparkBody", true)

assert(
	body and body:IsA("BasePart"),
	"Spark requires a BasePart named SparkBody"
)

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
-- ANIMATION CONTROLLER
----------------------------------------------------------------

local animationController =
	spark:FindFirstChildOfClass("AnimationController")

if not animationController then
	animationController = Instance.new("AnimationController")
	animationController.Name = "AnimationController"
	animationController.Parent = spark
end

local animator =
	animationController:FindFirstChildOfClass("Animator")

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
-- TRAIL
----------------------------------------------------------------

local bodyHalfHeight = body.Size.Y * 0.5

-- Slightly beneath Spark's body.
local trailY = -bodyHalfHeight - 0.03

local trailHalfWidth =
	math.max(body.Size.X * 0.12, 0.025)

local trailLeft = Instance.new("Attachment")
trailLeft.Name = "SparkTrailLeft"
trailLeft.Position = Vector3.new(
	-trailHalfWidth,
	trailY,
	0
)
trailLeft.Parent = body

local trailRight = Instance.new("Attachment")
trailRight.Name = "SparkTrailRight"
trailRight.Position = Vector3.new(
	trailHalfWidth,
	trailY,
	0
)
trailRight.Parent = body

local trail = Instance.new("Trail")
trail.Name = "SparkTrail"

trail.Attachment0 = trailLeft
trail.Attachment1 = trailRight

trail.Color =
	ColorSequence.new(Color3.new(1, 1, 1))

trail.Transparency =
	NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.35, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})

trail.Lifetime = TRAIL_LIFETIME
trail.LightEmission = 1
trail.LightInfluence = 0
trail.FaceCamera = true
trail.MinLength = 0.02
trail.Enabled = false

trail.Parent = body

----------------------------------------------------------------
-- TARGET CFRAMES
----------------------------------------------------------------

local function getFirstPersonTargetCFrame(): CFrame
	local camera = workspace.CurrentCamera

	if not camera then
		return rootPart.CFrame
	end

	local position =
		camera.CFrame:PointToWorldSpace(
			FIRST_PERSON_OFFSET
		)

	return CFrame.new(position)
		* camera.CFrame.Rotation
end

local function getThirdPersonTargetCFrame(): CFrame
	local worldOffset =
		rootPart.CFrame:VectorToWorldSpace(
			THIRD_PERSON_OFFSET
		)

	local position =
		head.Position + worldOffset

	return CFrame.new(position)
		* rootPart.CFrame.Rotation
end

local function getTargetCFrame(): CFrame
	local focusCFrame = getFocusedTargetCFrame()

	if focusCFrame then
		return focusCFrame
	end

	if isFirstPerson then
		return getFirstPersonTargetCFrame()
	end

	return getThirdPersonTargetCFrame()
end

----------------------------------------------------------------
-- INITIAL STATE
----------------------------------------------------------------

local currentCFrame = getTargetCFrame()

-- IMPORTANT:
-- CFrame SmoothDamp uses a CFrame velocity state.
local smoothVelocity = CFrame.new()

spark:PivotTo(currentCFrame)

----------------------------------------------------------------
-- UPDATE
----------------------------------------------------------------

local function onUpdate(dt: number)
	if not spark.Parent then
		return
	end

	if not head.Parent or not rootPart.Parent then
		return
	end

	updateSparkFocus()

	local targetCFrame = getTargetCFrame()

	------------------------------------------------------------
	-- REMEMBER WHERE SPARK WAS
	------------------------------------------------------------

	local previousPosition =
		currentCFrame.Position

	------------------------------------------------------------
	-- SMOOTH FOLLOWING
	------------------------------------------------------------

	currentCFrame, smoothVelocity =
		TweenService:SmoothDamp(
			currentCFrame,
			targetCFrame,
			smoothVelocity,
			SMOOTH_TIME,
			MAX_SPEED,
			dt
		)

	spark:PivotTo(currentCFrame)

	------------------------------------------------------------
	-- ACTUAL VISIBLE MOVEMENT SPEED
	------------------------------------------------------------

	local movementSpeed = 0

	if dt > 0 then
		movementSpeed =
			(
				currentCFrame.Position
				- previousPosition
			).Magnitude / dt
	end

	------------------------------------------------------------
	-- TRAIL
	------------------------------------------------------------

	trail.Enabled =
		movementSpeed >= TRAIL_START_SPEED
end

----------------------------------------------------------------
-- START
----------------------------------------------------------------

local updateConnection =
	RunService.PreRender:Connect(onUpdate)

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------

script.Destroying:Connect(function()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	if firstPersonConnection then
		firstPersonConnection:Disconnect()
	end

	if hoverTrack then
		hoverTrack:Stop()
	end

	if spark then
		spark:Destroy()
	end
end)