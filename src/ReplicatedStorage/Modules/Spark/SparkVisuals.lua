local TweenService = game:GetService("TweenService")

local SparkVisuals = {}
SparkVisuals.__index = SparkVisuals

----------------------------------------------------------------
-- CANONICAL SPARK VISUAL CONSTANTS
--
-- Reconstructed from the ReplicatedFirst FirstEffect that established
-- Spark's visual identity. Keep these values/order canonical unless the
-- actual visual language is intentionally changed.
----------------------------------------------------------------

local SPARK_SOUL_AMBIENT_TEXTURE = "rbxassetid://417249972"
local SPARK_SOUL_CIRCLE_TEXTURE = "rbxassetid://417249923"
local SPARK_SOUL_EXPLODE_TEXTURE = "rbxassetid://417249675"
local SPARK_SOUL_RING_TEXTURE = "rbxassetid://417249865"

local SPARK_SOUL_AMBIENT_RATE = 28
local SPARK_SOUL_AMBIENT_BURST_RATE = 135

local SPARK_SOUL_BURST_COUNT = 70
local SPARK_SOUL_REFORM_COUNT = 52

local SPARK_DULL_BODY_COLOR =
	Color3.fromRGB(
		120,
		132,
		126
	)

local SPARK_DULL_WING_COLOR =
	Color3.fromRGB(
		165,
		175,
		170
	)

local SPARK_DULL_EMISSIVE_STRENGTH = 1.5

local SPARK_SOUL_DISSOLVE_DURATION = 0.14
local SPARK_SOUL_VANISH_DURATION = 0.10
local SPARK_SOUL_INVISIBLE_HOLD = 0.055
local SPARK_SOUL_REFORM_DURATION = 0.24
local SPARK_SOUL_SETTLE_DURATION = 0.16

local SPARK_CINEMATIC_TRAIL_LIFETIME = 0.34
local SPARK_CINEMATIC_TRAIL_START_SPEED = 1.25

----------------------------------------------------------------
-- CANONICAL INTRO VISUAL TIMING / COLOUR RULES
----------------------------------------------------------------

local SPARK_INTRO_NORMAL_SATURATION_MIN = 0.68
local SPARK_INTRO_NORMAL_SATURATION_MAX = 0.92

local SPARK_INTRO_FORCEFIELD_SATURATION_MIN = 0.34
local SPARK_INTRO_FORCEFIELD_SATURATION_MAX = 0.58

local SPARK_INTRO_FORCEFIELD_HUE_SHIFT_MIN = 0.08
local SPARK_INTRO_FORCEFIELD_HUE_SHIFT_MAX = 0.22

local SPARK_CLOSE_EMISSIVE_STRENGTH = 16
local SPARK_PASS_EMISSIVE_STRENGTH = 10

local SPARK_LEFT_TO_CENTER_DURATION = 0.80
local SPARK_FORCEFIELD_FLASH_DURATION = 0.12
local SPARK_CENTER_TO_RIGHT_DURATION = 0.65
local SPARK_RIGHT_TO_CENTER_DURATION = 0.70
local SPARK_READY_DURATION = 0.45

----------------------------------------------------------------
-- IDLE SELF-MATERIALISATION
--
-- Spark is allowed to quietly experiment with his own engineered shell
-- while the player is idle. The inner NeonBodyOrb is deliberately excluded:
-- it is Spark's stable inner soul/VFX body, not part of the idle display.
----------------------------------------------------------------

local SPARK_IDLE_MORPH_DURATION_MIN = 3.5
local SPARK_IDLE_MORPH_DURATION_MAX = 6.5

local SPARK_IDLE_HOLD_DURATION_MIN = 1.5
local SPARK_IDLE_HOLD_DURATION_MAX = 4.0

local SPARK_IDLE_BODY_EMISSIVE_MIN = 1.0
local SPARK_IDLE_BODY_EMISSIVE_MAX = 6.0

local SPARK_IDLE_NEON_FORM_CHANCE = 0.38
local SPARK_IDLE_WHITE_FORM_CHANCE = 0.12

local SPARK_IDLE_SATURATION_MIN = 0.48
local SPARK_IDLE_SATURATION_MAX = 0.92

local SPARK_IDLE_WING_WHITE_LERP = 0.22
local SPARK_IDLE_SHELL_WHITE_LERP = 0.10

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

local function tweenInstance(
	instance: Instance,
	duration: number,
	easingStyle: Enum.EasingStyle,
	easingDirection: Enum.EasingDirection,
	properties: {[string]: any}
): Tween
	local tween =
		TweenService:Create(
			instance,
			TweenInfo.new(
				duration,
				easingStyle,
				easingDirection
			),
			properties
		)

	tween:Play()

	return tween
end

local function getSurfaceAppearance(
	part: BasePart?
): SurfaceAppearance?
	if not part then
		return nil
	end

	return part:FindFirstChildWhichIsA(
		"SurfaceAppearance"
	)
end

----------------------------------------------------------------
-- CONSTRUCTOR
----------------------------------------------------------------

function SparkVisuals.new(
	sparkModel: Model
)
	local self =
		setmetatable(
			{},
			SparkVisuals
		)

	self.Model = sparkModel

	self.Body =
		sparkModel:FindFirstChild(
			"SparkBody",
			true
		)

	assert(
		self.Body
			and self.Body:IsA("BasePart"),
		"SparkVisuals requires SparkBody"
	)

	----------------------------------------------------------------
	-- INNER VFX / SOUL BODY
	--
	-- SparkBody remains the engineered outer shell.
	-- NeonBodyOrb is the inner visual body used for Neon / Glass /
	-- ForceField material transitions.
	----------------------------------------------------------------

	self.NeonBodyOrb =
		self.Body:FindFirstChild(
			"NeonBodyOrb",
			true
		)

	if self.NeonBodyOrb
		and not self.NeonBodyOrb:IsA("BasePart")
	then
		self.NeonBodyOrb = nil
	end

	if not self.NeonBodyOrb then
		warn(
			"[SparkVisuals]: SparkBody.NeonBodyOrb was not found; "
				.. "falling back to legacy SparkBody material transitions."
		)
	end

	self.WingL =
		sparkModel:FindFirstChild(
			"SparkWingL",
			true
		)

	if self.WingL
		and not self.WingL:IsA("BasePart")
	then
		self.WingL = nil
	end

	self.WingR =
		sparkModel:FindFirstChild(
			"SparkWingR",
			true
		)

	if self.WingR
		and not self.WingR:IsA("BasePart")
	then
		self.WingR = nil
	end

	self.BodySurfaceAppearance =
		getSurfaceAppearance(
			self.Body
		)

	self.WingLSurfaceAppearance =
		getSurfaceAppearance(
			self.WingL
		)

	self.WingRSurfaceAppearance =
		getSurfaceAppearance(
			self.WingR
		)

	self.PointLight =
		self.Body:FindFirstChildWhichIsA(
			"PointLight"
		)

	----------------------------------------------------------------
	-- ORIGINAL APPEARANCE
	----------------------------------------------------------------

	self.OriginalBodyColor =
		self.Body.Color

	self.OriginalBodyMaterial =
		self.Body.Material

	self.OriginalBodyMaterialVariant =
		self.Body.MaterialVariant

	self.OriginalBodyTransparency =
		self.Body.Transparency

	self.OriginalBodySurfaceColor =
		if self.BodySurfaceAppearance
		then self.BodySurfaceAppearance.Color
		else nil

	self.OriginalBodySurfaceEmissiveTint =
		if self.BodySurfaceAppearance
		then self.BodySurfaceAppearance.EmissiveTint
		else nil

	self.OriginalBodySurfaceEmissiveStrength =
		if self.BodySurfaceAppearance
		then self.BodySurfaceAppearance.EmissiveStrength
		else nil

	self.OriginalNeonBodyOrbColor =
		if self.NeonBodyOrb
		then self.NeonBodyOrb.Color
		else nil

	self.OriginalNeonBodyOrbMaterial =
		if self.NeonBodyOrb
		then self.NeonBodyOrb.Material
		else nil

	self.OriginalNeonBodyOrbTransparency =
		if self.NeonBodyOrb
		then self.NeonBodyOrb.Transparency
		else nil

	self.OriginalWingLTransparency =
		if self.WingL
		then self.WingL.Transparency
		else 0

	self.OriginalWingRTransparency =
		if self.WingR
		then self.WingR.Transparency
		else 0

	self.OriginalWingLColor =
		if self.WingLSurfaceAppearance
		then self.WingLSurfaceAppearance.Color
		else nil

	self.OriginalWingRColor =
		if self.WingRSurfaceAppearance
		then self.WingRSurfaceAppearance.Color
		else nil

	self.OriginalWingLEmissiveTint =
		if self.WingLSurfaceAppearance
		then self.WingLSurfaceAppearance.EmissiveTint
		else nil

	self.OriginalWingREmissiveTint =
		if self.WingRSurfaceAppearance
		then self.WingRSurfaceAppearance.EmissiveTint
		else nil

	self.OriginalWingLEmissiveStrength =
		if self.WingLSurfaceAppearance
		then self.WingLSurfaceAppearance.EmissiveStrength
		else nil

	self.OriginalWingREmissiveStrength =
		if self.WingRSurfaceAppearance
		then self.WingRSurfaceAppearance.EmissiveStrength
		else nil

	self.OriginalPointLightColor =
		if self.PointLight
		then self.PointLight.Color
		else nil

	self.OriginalPointLightBrightness =
		if self.PointLight
		then self.PointLight.Brightness
		else 1

	----------------------------------------------------------------
	-- STATE
	----------------------------------------------------------------

	self.SoulBurstInProgress = false
	self.Destroyed = false

	self.IdleVisualsActive = false
	self.IdleVisualGeneration = 0
	self.IdleVisualTweens = {}
	self.IdleVisualRandom = Random.new()

	self.LastTrailWorldPosition = nil

	self.IntroColorSeed = 0

	self.IntroNormalBodyColor =
		Color3.fromRGB(
			111,
			242,
			129
		)

	self.IntroNormalWingColor =
		Color3.fromRGB(
			150,
			255,
			170
		)

	self.IntroForceFieldBodyColor =
		Color3.fromRGB(
			205,
			255,
			240
		)

	self.IntroForceFieldWingColor =
		Color3.fromRGB(
			235,
			255,
			255
		)

	----------------------------------------------------------------
	-- SHARED BODY / PARTICLE / TRAIL COLOUR DRIVER
	--
	-- This intentionally mirrors FirstEffect:
	-- body + particles + trail move together.
	--
	-- Wings are still allowed to have their own lighter visual state.
	----------------------------------------------------------------

	self.VisualColorValue =
		Instance.new(
			"Color3Value"
		)

	self.VisualColorValue.Name =
		"SparkVisualColor"

	self.VisualColorValue.Value =
		self.Body.Color

	----------------------------------------------------------------
	-- CREATE THE CANONICAL SOUL VFX
	----------------------------------------------------------------

	self:_CreateSoulVFX()

	self.VisualColorConnection =
		self.VisualColorValue
		:GetPropertyChangedSignal(
			"Value"
		)
		:Connect(function()
			if self.Destroyed then
				return
			end

			self:_ApplyBodySoulColor(
				self.VisualColorValue.Value
			)
		end)

	self:_ApplyBodySoulColor(
		self.VisualColorValue.Value
	)

	return self
end

----------------------------------------------------------------
-- CANONICAL PARTICLE / TRAIL CONSTRUCTION
----------------------------------------------------------------

function SparkVisuals:_CreateSoulVFX()
	----------------------------------------------------------------
	-- ATTACHMENT
	----------------------------------------------------------------

	local existingAttachment =
		self.Body:FindFirstChild(
			"SparkSoulVFXAttachment"
		)

	if existingAttachment then
		existingAttachment:Destroy()
	end

	self.SoulAttachment =
		Instance.new(
			"Attachment"
		)

	self.SoulAttachment.Name =
		"SparkSoulVFXAttachment"

	self.SoulAttachment.Parent =
		self.Body

	----------------------------------------------------------------
	-- AMBIENT INTERNAL SOUL MOTES
	--
	-- Exact canonical FirstEffect values.
	----------------------------------------------------------------

	self.AmbientEmitter =
		Instance.new(
			"ParticleEmitter"
		)

	self.AmbientEmitter.Name =
		"SparkSoulMotes"

	self.AmbientEmitter.Texture =
		SPARK_SOUL_AMBIENT_TEXTURE

	self.AmbientEmitter.Color =
		ColorSequence.new(
			self.Body.Color
		)

	self.AmbientEmitter.LightEmission = 1
	self.AmbientEmitter.LightInfluence = 0

	self.AmbientEmitter.Lifetime =
		NumberRange.new(
			0.70,
			1.25
		)

	self.AmbientEmitter.Rate =
		SPARK_SOUL_AMBIENT_RATE

	self.AmbientEmitter.Speed =
		NumberRange.new(
			0.12,
			0.42
		)

	self.AmbientEmitter.SpreadAngle =
		Vector2.new(
			180,
			180
		)

	self.AmbientEmitter.Shape =
		Enum.ParticleEmitterShape.Sphere

	self.AmbientEmitter.ShapeStyle =
		Enum.ParticleEmitterShapeStyle.Volume

	self.AmbientEmitter.ShapeInOut =
		Enum.ParticleEmitterShapeInOut.Outward

	self.AmbientEmitter.Rotation =
		NumberRange.new(
			0,
			360
		)

	self.AmbientEmitter.RotSpeed =
		NumberRange.new(
			-70,
			70
		)

	self.AmbientEmitter.Drag = 2.5
	self.AmbientEmitter.LockedToPart = true

	self.AmbientEmitter.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.34
			),

			NumberSequenceKeypoint.new(
				0.55,
				0.22
			),

			NumberSequenceKeypoint.new(
				1,
				0.08
			),
		})

	self.AmbientEmitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.06
			),

			NumberSequenceKeypoint.new(
				0.65,
				0.26
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	self.AmbientEmitter.Parent =
		self.SoulAttachment

	----------------------------------------------------------------
	-- OUTWARD SOUL BURST
	----------------------------------------------------------------

	self.BurstEmitter =
		Instance.new(
			"ParticleEmitter"
		)

	self.BurstEmitter.Name =
		"SparkSoulBurst"

	self.BurstEmitter.Texture =
		SPARK_SOUL_EXPLODE_TEXTURE

	self.BurstEmitter.Color =
		ColorSequence.new(
			self.Body.Color
		)

	self.BurstEmitter.LightEmission = 1
	self.BurstEmitter.LightInfluence = 0
	self.BurstEmitter.Enabled = false

	self.BurstEmitter.Lifetime =
		NumberRange.new(
			0.28,
			0.52
		)

	self.BurstEmitter.Speed =
		NumberRange.new(
			5,
			11
		)

	self.BurstEmitter.SpreadAngle =
		Vector2.new(
			180,
			180
		)

	self.BurstEmitter.Shape =
		Enum.ParticleEmitterShape.Sphere

	self.BurstEmitter.ShapeStyle =
		Enum.ParticleEmitterShapeStyle.Volume

	self.BurstEmitter.ShapeInOut =
		Enum.ParticleEmitterShapeInOut.Outward

	self.BurstEmitter.Rotation =
		NumberRange.new(
			0,
			360
		)

	self.BurstEmitter.RotSpeed =
		NumberRange.new(
			-140,
			140
		)

	self.BurstEmitter.Drag = 5

	self.BurstEmitter.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.52
			),

			NumberSequenceKeypoint.new(
				0.38,
				0.34
			),

			NumberSequenceKeypoint.new(
				1,
				0.08
			),
		})

	self.BurstEmitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.05
			),

			NumberSequenceKeypoint.new(
				0.55,
				0.30
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	self.BurstEmitter.Parent =
		self.SoulAttachment

	----------------------------------------------------------------
	-- REFORMATION CLOUD
	----------------------------------------------------------------

	self.ReformEmitter =
		Instance.new(
			"ParticleEmitter"
		)

	self.ReformEmitter.Name =
		"SparkSoulReform"

	self.ReformEmitter.Texture =
		SPARK_SOUL_CIRCLE_TEXTURE

	self.ReformEmitter.Color =
		ColorSequence.new(
			self.Body.Color
		)

	self.ReformEmitter.LightEmission = 1
	self.ReformEmitter.LightInfluence = 0
	self.ReformEmitter.Enabled = false

	self.ReformEmitter.Lifetime =
		NumberRange.new(
			0.22,
			0.42
		)

	self.ReformEmitter.Speed =
		NumberRange.new(
			1.0,
			3.4
		)

	self.ReformEmitter.SpreadAngle =
		Vector2.new(
			180,
			180
		)

	self.ReformEmitter.Shape =
		Enum.ParticleEmitterShape.Sphere

	self.ReformEmitter.ShapeStyle =
		Enum.ParticleEmitterShapeStyle.Volume

	self.ReformEmitter.ShapeInOut =
		Enum.ParticleEmitterShapeInOut.Outward

	self.ReformEmitter.Rotation =
		NumberRange.new(
			0,
			360
		)

	self.ReformEmitter.RotSpeed =
		NumberRange.new(
			-100,
			100
		)

	self.ReformEmitter.Drag = 8
	self.ReformEmitter.LockedToPart = true

	self.ReformEmitter.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.42
			),

			NumberSequenceKeypoint.new(
				0.65,
				0.26
			),

			NumberSequenceKeypoint.new(
				1,
				0.08
			),
		})

	self.ReformEmitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.10
			),

			NumberSequenceKeypoint.new(
				0.72,
				0.38
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	self.ReformEmitter.Parent =
		self.SoulAttachment

	----------------------------------------------------------------
	-- BROKEN RING / POP ACCENT
	----------------------------------------------------------------

	self.RingEmitter =
		Instance.new(
			"ParticleEmitter"
		)

	self.RingEmitter.Name =
		"SparkSoulRingPop"

	self.RingEmitter.Texture =
		SPARK_SOUL_RING_TEXTURE

	self.RingEmitter.Color =
		ColorSequence.new(
			self.Body.Color
		)

	self.RingEmitter.LightEmission = 1
	self.RingEmitter.LightInfluence = 0
	self.RingEmitter.Enabled = false

	self.RingEmitter.Lifetime =
		NumberRange.new(
			0.16,
			0.30
		)

	self.RingEmitter.Speed =
		NumberRange.new(
			0.4,
			1.8
		)

	self.RingEmitter.SpreadAngle =
		Vector2.new(
			24,
			24
		)

	self.RingEmitter.Rotation =
		NumberRange.new(
			0,
			360
		)

	self.RingEmitter.RotSpeed =
		NumberRange.new(
			-80,
			80
		)

	self.RingEmitter.Size =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.36
			),

			NumberSequenceKeypoint.new(
				0.45,
				0.95
			),

			NumberSequenceKeypoint.new(
				1,
				1.55
			),
		})

	self.RingEmitter.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.03
			),

			NumberSequenceKeypoint.new(
				0.65,
				0.26
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	self.RingEmitter.Parent =
		self.SoulAttachment

	----------------------------------------------------------------
	-- SIGNATURE CENTERED TRAIL
	----------------------------------------------------------------

	local existingTrailLeft =
		self.Body:FindFirstChild(
			"SparkSoulTrailLeft"
		)

	if existingTrailLeft then
		existingTrailLeft:Destroy()
	end

	local existingTrailRight =
		self.Body:FindFirstChild(
			"SparkSoulTrailRight"
		)

	if existingTrailRight then
		existingTrailRight:Destroy()
	end

	local existingTrail =
		self.Body:FindFirstChild(
			"SparkSoulTrail"
		)

	if existingTrail then
		existingTrail:Destroy()
	end

	local trailHalfWidth =
		math.max(
			self.Body.Size.X * 0.12,
			0.025
		)

	self.TrailLeft =
		Instance.new(
			"Attachment"
		)

	self.TrailLeft.Name =
		"SparkSoulTrailLeft"

	self.TrailLeft.Position =
		Vector3.new(
			-trailHalfWidth,
			0,
			0
		)

	self.TrailLeft.Parent =
		self.Body

	self.TrailRight =
		Instance.new(
			"Attachment"
		)

	self.TrailRight.Name =
		"SparkSoulTrailRight"

	self.TrailRight.Position =
		Vector3.new(
			trailHalfWidth,
			0,
			0
		)

	self.TrailRight.Parent =
		self.Body

	self.Trail =
		Instance.new(
			"Trail"
		)

	self.Trail.Name =
		"SparkSoulTrail"

	self.Trail.Attachment0 =
		self.TrailLeft

	self.Trail.Attachment1 =
		self.TrailRight

	self.Trail.Color =
		ColorSequence.new(
			self.Body.Color
		)

	self.Trail.Transparency =
		NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				0.08
			),

			NumberSequenceKeypoint.new(
				0.35,
				0.35
			),

			NumberSequenceKeypoint.new(
				1,
				1
			),
		})

	self.Trail.Lifetime =
		SPARK_CINEMATIC_TRAIL_LIFETIME

	self.Trail.LightEmission = 1
	self.Trail.LightInfluence = 0
	self.Trail.FaceCamera = true
	self.Trail.MinLength = 0.02
	self.Trail.Enabled = false

	self.Trail.Parent =
		self.Body

	self.SoulEmitters = {
		self.AmbientEmitter,
		self.BurstEmitter,
		self.ReformEmitter,
		self.RingEmitter,
	}
end

----------------------------------------------------------------
-- IDLE SELF-MATERIALISATION API
--
-- Only the engineered outer shell and wings are altered here.
-- NeonBodyOrb is intentionally never touched.
----------------------------------------------------------------

function SparkVisuals:_CancelIdleVisualTweens()
	for _, tween in self.IdleVisualTweens do
		tween:Cancel()
	end

	table.clear(
		self.IdleVisualTweens
	)
end

function SparkVisuals:_CreateIdleVisualTween(
	instance: Instance,
	duration: number,
	properties: {[string]: any}
): Tween
	local tween =
		TweenService:Create(
			instance,
			TweenInfo.new(
				duration,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			),
			properties
		)

	table.insert(
		self.IdleVisualTweens,
		tween
	)

	tween:Play()

	return tween
end

function SparkVisuals:_GetRandomIdleVisualState(): (
	Color3,
	Color3,
	Color3,
	number,
	Enum.Material
)
	local random = self.IdleVisualRandom

	local bodyColor: Color3

	if random:NextNumber()
		<= SPARK_IDLE_WHITE_FORM_CHANCE
	then
		local whiteValue =
			random:NextNumber(
				0.88,
				1
			)

		bodyColor =
			Color3.new(
				whiteValue,
				whiteValue,
				whiteValue
			)
	else
		bodyColor =
			Color3.fromHSV(
				random:NextNumber(),
				random:NextNumber(
					SPARK_IDLE_SATURATION_MIN,
					SPARK_IDLE_SATURATION_MAX
				),
				1
			)
	end

	local shellColor =
		bodyColor:Lerp(
			Color3.new(1, 1, 1),
			SPARK_IDLE_SHELL_WHITE_LERP
		)

	local wingColor =
		bodyColor:Lerp(
			Color3.new(1, 1, 1),
			SPARK_IDLE_WING_WHITE_LERP
		)

	local bodyEmissiveStrength =
		random:NextNumber(
			SPARK_IDLE_BODY_EMISSIVE_MIN,
			SPARK_IDLE_BODY_EMISSIVE_MAX
		)

	local bodyMaterial =
		if random:NextNumber()
			<= SPARK_IDLE_NEON_FORM_CHANCE
		then Enum.Material.Neon
		else self.OriginalBodyMaterial

	return
		bodyColor,
		shellColor,
		wingColor,
		bodyEmissiveStrength,
		bodyMaterial
end

function SparkVisuals:_PlayIdleVisualState(
	generation: number
)
	if self.Destroyed
		or not self.IdleVisualsActive
		or generation ~= self.IdleVisualGeneration
	then
		return
	end

	local bodyColor,
		shellColor,
		wingColor,
		bodyEmissiveStrength,
		bodyMaterial =
		self:_GetRandomIdleVisualState()

	local duration =
		self.IdleVisualRandom:NextNumber(
			SPARK_IDLE_MORPH_DURATION_MIN,
			SPARK_IDLE_MORPH_DURATION_MAX
		)

	self:_CancelIdleVisualTweens()

	-- Keep Spark's canonical body/particle/trail colour driver in sync.
	-- NeonBodyOrb is excluded by _ApplyBodySoulColor.
	self:_CreateIdleVisualTween(
		self.VisualColorValue,
		duration,
		{
			Value = bodyColor,
		}
	)

	if self.BodySurfaceAppearance then
		self:_CreateIdleVisualTween(
			self.BodySurfaceAppearance,
			duration,
			{
				Color = shellColor,
				EmissiveTint = shellColor,
				EmissiveStrength =
					bodyEmissiveStrength,
			}
		)
	end

	if self.WingLSurfaceAppearance then
		self:_CreateIdleVisualTween(
			self.WingLSurfaceAppearance,
			duration,
			{
				Color = wingColor,
				EmissiveTint = wingColor,
			}
		)
	end

	if self.WingRSurfaceAppearance then
		self:_CreateIdleVisualTween(
			self.WingRSurfaceAppearance,
			duration,
			{
				Color = wingColor,
				EmissiveTint = wingColor,
			}
		)
	end

	-- Material itself cannot be tweened. Delay the form switch until the
	-- colour/emission transition is well underway so it reads as a morph.
	task.delay(
		duration * 0.45,
		function()
			if self.Destroyed
				or not self.IdleVisualsActive
				or generation ~= self.IdleVisualGeneration
			then
				return
			end

			self.Body.Material =
				bodyMaterial

			if bodyMaterial
				== self.OriginalBodyMaterial
			then
				self.Body.MaterialVariant =
					self.OriginalBodyMaterialVariant
			end
		end
	)

	return duration
end

function SparkVisuals:StartIdleVisuals()
	if self.Destroyed
		or self.IdleVisualsActive
	then
		return
	end

	self.IdleVisualsActive = true
	self.IdleVisualGeneration += 1

	local generation =
		self.IdleVisualGeneration

	task.spawn(function()
		while self.Model.Parent
			and not self.Destroyed
			and self.IdleVisualsActive
			and generation == self.IdleVisualGeneration
		do
			if self.SoulBurstInProgress then
				task.wait(0.10)
				continue
			end

			local duration =
				self:_PlayIdleVisualState(
					generation
				)

			if not duration then
				break
			end

			task.wait(
				duration
					+ self.IdleVisualRandom:NextNumber(
						SPARK_IDLE_HOLD_DURATION_MIN,
						SPARK_IDLE_HOLD_DURATION_MAX
					)
			)
		end
	end)
end

function SparkVisuals:_RestoreIdleVisualBaseline(
	duration: number
)
	self:_CancelIdleVisualTweens()

	self.Body.Material =
		self.OriginalBodyMaterial

	self.Body.MaterialVariant =
		self.OriginalBodyMaterialVariant

	self:_CreateIdleVisualTween(
		self.VisualColorValue,
		duration,
		{
			Value = self.OriginalBodyColor,
		}
	)

	if self.BodySurfaceAppearance
		and self.OriginalBodySurfaceColor
		and self.OriginalBodySurfaceEmissiveTint
		and self.OriginalBodySurfaceEmissiveStrength ~= nil
	then
		self:_CreateIdleVisualTween(
			self.BodySurfaceAppearance,
			duration,
			{
				Color =
					self.OriginalBodySurfaceColor,
				EmissiveTint =
					self.OriginalBodySurfaceEmissiveTint,
				EmissiveStrength =
					self.OriginalBodySurfaceEmissiveStrength,
			}
		)
	end

	if self.WingLSurfaceAppearance
		and self.OriginalWingLColor
		and self.OriginalWingLEmissiveTint
	then
		self:_CreateIdleVisualTween(
			self.WingLSurfaceAppearance,
			duration,
			{
				Color = self.OriginalWingLColor,
				EmissiveTint =
					self.OriginalWingLEmissiveTint,
			}
		)
	end

	if self.WingRSurfaceAppearance
		and self.OriginalWingRColor
		and self.OriginalWingREmissiveTint
	then
		self:_CreateIdleVisualTween(
			self.WingRSurfaceAppearance,
			duration,
			{
				Color = self.OriginalWingRColor,
				EmissiveTint =
					self.OriginalWingREmissiveTint,
			}
		)
	end
end

function SparkVisuals:StopIdleVisuals(
	returnDuration: number?
)
	if self.Destroyed then
		return
	end

	self.IdleVisualsActive = false
	self.IdleVisualGeneration += 1

	local generation =
		self.IdleVisualGeneration

	local duration =
		returnDuration
		or 0.22

	self:_CancelIdleVisualTweens()

	-- If Spark is currently inside the canonical disappear/reform effect,
	-- let that effect finish before forcing the neutral gold baseline back.
	if self.SoulBurstInProgress then
		task.spawn(function()
			while self.SoulBurstInProgress
				and not self.Destroyed
				and self.Model.Parent
			do
				task.wait(0.03)
			end

			if self.Destroyed
				or self.IdleVisualsActive
				or generation ~= self.IdleVisualGeneration
			then
				return
			end

			self:_RestoreIdleVisualBaseline(
				duration
			)
		end)

		return
	end

	self:_RestoreIdleVisualBaseline(
		duration
	)
end

----------------------------------------------------------------
-- COLOUR API
----------------------------------------------------------------

function SparkVisuals:_ApplyBodySoulColor(
	bodyColor: Color3
)
	self.Body.Color =
		bodyColor

	-- NeonBodyOrb deliberately does NOT follow this shared colour driver.
	-- It is an independent inner-energy layer and must retain whatever colour
	-- is currently authored/applied to it unless a dedicated VFX state changes it.

	local colorSequence =
		ColorSequence.new(
			bodyColor
		)

	self.AmbientEmitter.Color =
		colorSequence

	self.BurstEmitter.Color =
		colorSequence

	self.ReformEmitter.Color =
		colorSequence

	self.RingEmitter.Color =
		colorSequence

	self.Trail.Color =
		colorSequence
end

function SparkVisuals:SetColor(
	bodyColor: Color3
)
	self.VisualColorValue.Value =
		bodyColor

	-- Runtime/core Spark rule:
	-- high-level SetColor keeps the complete creature coherent.
	local wingColor =
		bodyColor:Lerp(
			Color3.new(1, 1, 1),
			0.18
		)

	if self.WingLSurfaceAppearance then
		self.WingLSurfaceAppearance.Color =
			wingColor

		self.WingLSurfaceAppearance.EmissiveTint =
			wingColor
	end

	if self.WingRSurfaceAppearance then
		self.WingRSurfaceAppearance.Color =
			wingColor

		self.WingRSurfaceAppearance.EmissiveTint =
			wingColor
	end

	if self.PointLight then
		self.PointLight.Color =
			bodyColor
	end
end

function SparkVisuals:TweenColor(
	bodyColor: Color3,
	duration: number
): Tween
	local tween =
		tweenInstance(
			self.VisualColorValue,
			duration,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			{
				Value = bodyColor,
			}
		)

	-- Tween the runtime wing identity in parallel.
	local wingColor =
		bodyColor:Lerp(
			Color3.new(1, 1, 1),
			0.18
		)

	self:_TweenWingAppearance(
		wingColor,
		nil,
		duration
	)

	if self.PointLight then
		tweenInstance(
			self.PointLight,
			duration,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			{
				Color = bodyColor,
			}
		)
	end

	return tween
end

----------------------------------------------------------------
-- INTERNAL VISUAL TWEEN HELPERS
----------------------------------------------------------------

function SparkVisuals:_TweenBodySoulColor(
	color: Color3,
	duration: number
): Tween
	-- Canonical FirstEffect path:
	-- body + particles + trail together.
	-- Wings and PointLight are separately authored during the intro.
	return tweenInstance(
		self.VisualColorValue,
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		{
			Value = color,
		}
	)
end

function SparkVisuals:_TweenWingAppearance(
	color: Color3,
	emissiveStrength: number?,
	duration: number
)
	local tweenInfo =
		TweenInfo.new(
			duration,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		)

	if self.WingLSurfaceAppearance then
		local properties = {
			Color = color,
			EmissiveTint = color,
		}

		if emissiveStrength ~= nil then
			properties.EmissiveStrength =
				emissiveStrength
		end

		TweenService:Create(
			self.WingLSurfaceAppearance,
			tweenInfo,
			properties
		):Play()
	end

	if self.WingRSurfaceAppearance then
		local properties = {
			Color = color,
			EmissiveTint = color,
		}

		if emissiveStrength ~= nil then
			properties.EmissiveStrength =
				emissiveStrength
		end

		TweenService:Create(
			self.WingRSurfaceAppearance,
			tweenInfo,
			properties
		):Play()
	end
end

function SparkVisuals:_TweenPointLight(
	color: Color3,
	brightness: number,
	duration: number
)
	if not self.PointLight then
		return
	end

	tweenInstance(
		self.PointLight,
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		{
			Color = color,
			Brightness = brightness,
		}
	)
end

function SparkVisuals:_TweenPartTransparency(
	part: BasePart?,
	transparency: number,
	duration: number
)
	if not part then
		return
	end

	tweenInstance(
		part,
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		{
			Transparency = transparency,
		}
	)
end

----------------------------------------------------------------
-- INTRO COLOUR SEED
----------------------------------------------------------------

function SparkVisuals:SelectIntroColorSeed()
	local unixMilliseconds =
		DateTime.now().UnixTimestampMillis

	self.IntroColorSeed =
		unixMilliseconds
		% 2147483647

	local random =
		Random.new(
			self.IntroColorSeed
		)

	local normalHue =
		random:NextNumber()

	local forceFieldHueDirection =
		if random:NextNumber() >= 0.5
		then 1
		else -1

	local forceFieldHueShift =
		random:NextNumber(
			SPARK_INTRO_FORCEFIELD_HUE_SHIFT_MIN,
			SPARK_INTRO_FORCEFIELD_HUE_SHIFT_MAX
		)
		* forceFieldHueDirection

	local forceFieldHue =
		(
			normalHue
			+ forceFieldHueShift
		)
		% 1

	self.IntroNormalBodyColor =
		Color3.fromHSV(
			normalHue,
			random:NextNumber(
				SPARK_INTRO_NORMAL_SATURATION_MIN,
				SPARK_INTRO_NORMAL_SATURATION_MAX
			),
			1
		)

	self.IntroForceFieldBodyColor =
		Color3.fromHSV(
			forceFieldHue,
			random:NextNumber(
				SPARK_INTRO_FORCEFIELD_SATURATION_MIN,
				SPARK_INTRO_FORCEFIELD_SATURATION_MAX
			),
			1
		)

	self.IntroNormalWingColor =
		self.IntroNormalBodyColor:Lerp(
			Color3.new(1, 1, 1),
			0.18
		)

	self.IntroForceFieldWingColor =
		self.IntroForceFieldBodyColor:Lerp(
			Color3.new(1, 1, 1),
			0.34
		)

	-- Same attributes the canonical FirstEffect left on CinematicSpark.
	self.Model:SetAttribute(
		"IntroColorSeed",
		self.IntroColorSeed
	)

	self.Model:SetAttribute(
		"IntroColorPrimary",
		self.IntroNormalBodyColor
	)

	self.Model:SetAttribute(
		"IntroColorSecondary",
		self.IntroForceFieldBodyColor
	)

	self.Model:SetAttribute(
		"IntroColorNormal",
		self.IntroNormalBodyColor
	)

	self.Model:SetAttribute(
		"IntroColorForceField",
		self.IntroForceFieldBodyColor
	)

	print(
		"[Spark Intro] Color seed:",
		self.IntroColorSeed,
		"Normal:",
		self.IntroNormalBodyColor,
		"ForceField:",
		self.IntroForceFieldBodyColor
	)
end

----------------------------------------------------------------
-- CANONICAL SOUL MATERIALISATION
--
-- EXACT VISUAL ORDER FROM FIRSTEFFECT:
--
-- ambient soul matter
-- -> Glass
-- -> dull body + grey wings
-- -> 0.14 dissolve
-- -> little sparks
-- -> broken ring
-- -> clean circles
-- -> delayed explode
-- -> body/wings vanish
-- -> 0.055 invisible hold
-- -> ForceField
-- -> explode residue
-- -> clean circles
-- -> broken ring
-- -> little sparks
-- -> reform
-- -> original material
-- -> settle
--
-- onInvisible is intentionally optional. Runtime Spark can use it to
-- PivotTo the opposite shoulder/screen side while Spark does not exist.
----------------------------------------------------------------

function SparkVisuals:PlaySoulMaterialisation(
	onInvisible: (() -> ())?
)
	if self.SoulBurstInProgress
		or self.Destroyed
	then
		return
	end

	self.SoulBurstInProgress = true

	local originalBodyTransparency =
		self.OriginalBodyTransparency

	local neonBodyOrbTransparencyBeforeBurst =
		if self.NeonBodyOrb
		then self.NeonBodyOrb.Transparency
		else nil

	local neonBodyOrbColorBeforeBurst =
		if self.NeonBodyOrb
		then self.NeonBodyOrb.Color
		else nil

	local neonBodyOrbMaterialBeforeBurst =
		if self.NeonBodyOrb
		then self.NeonBodyOrb.Material
		else nil

	local originalWingLTransparency =
		self.OriginalWingLTransparency

	local originalWingRTransparency =
		self.OriginalWingRTransparency

	local originalBrightness =
		self.OriginalPointLightBrightness
		or 1

	local bodyColorBeforeBurst =
		self.VisualColorValue.Value

	local leftWingSurfaceColorBeforeBurst =
		if self.WingLSurfaceAppearance
		then self.WingLSurfaceAppearance.Color
		else nil

	local rightWingSurfaceColorBeforeBurst =
		if self.WingRSurfaceAppearance
		then self.WingRSurfaceAppearance.Color
		else nil

	local leftWingColorBeforeBurst =
		if self.WingLSurfaceAppearance
		then self.WingLSurfaceAppearance.EmissiveTint
		else nil

	local rightWingColorBeforeBurst =
		if self.WingRSurfaceAppearance
		then self.WingRSurfaceAppearance.EmissiveTint
		else nil

	local leftWingStrengthBeforeBurst =
		if self.WingLSurfaceAppearance
		then self.WingLSurfaceAppearance.EmissiveStrength
		else nil

	local rightWingStrengthBeforeBurst =
		if self.WingRSurfaceAppearance
		then self.WingRSurfaceAppearance.EmissiveStrength
		else nil

	----------------------------------------------------------------
	-- SOUL MATTER BECOMES VISIBLE
	--
	-- Layer rule:
	-- SparkBody = engineered outer shell.
	-- NeonBodyOrb = material-changing inner soul / VFX body.
	----------------------------------------------------------------

	self.AmbientEmitter.Enabled = true

	self.AmbientEmitter.Rate =
		SPARK_SOUL_AMBIENT_BURST_RATE

	-- Keep particle identity on the pre-burst/current Spark colour.
	self:_ApplyBodySoulColor(
		bodyColorBeforeBurst
	)

	if self.NeonBodyOrb then
		self.NeonBodyOrb.Material =
			Enum.Material.Glass

		tweenInstance(
			self.NeonBodyOrb,
			SPARK_SOUL_DISSOLVE_DURATION,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			{
				Color =
					SPARK_DULL_BODY_COLOR,
			}
		)
	else
		-- Backwards-compatible fallback for an older Spark model.
		self.Body.Material =
			Enum.Material.Glass
	end

	-- Canonical FirstEffect dull-body tween is separate from the shared
	-- colour driver, so particles remain the colour Spark had before bursting.
	tweenInstance(
		self.Body,
		SPARK_SOUL_DISSOLVE_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		{
			Color =
				SPARK_DULL_BODY_COLOR,
		}
	)

	self:_TweenWingAppearance(
		SPARK_DULL_WING_COLOR,
		SPARK_DULL_EMISSIVE_STRENGTH,
		SPARK_SOUL_DISSOLVE_DURATION
	)

	self:_TweenPartTransparency(
		self.Body,
		math.max(
			originalBodyTransparency,
			0.58
		),
		SPARK_SOUL_DISSOLVE_DURATION
	)

	if
		self.NeonBodyOrb
		and neonBodyOrbTransparencyBeforeBurst ~= nil
	then
		self:_TweenPartTransparency(
			self.NeonBodyOrb,
			math.max(
				neonBodyOrbTransparencyBeforeBurst,
				0.58
			),
			SPARK_SOUL_DISSOLVE_DURATION
		)
	end

	self:_TweenPartTransparency(
		self.WingL,
		math.max(
			originalWingLTransparency,
			0.58
		),
		SPARK_SOUL_DISSOLVE_DURATION
	)

	self:_TweenPartTransparency(
		self.WingR,
		math.max(
			originalWingRTransparency,
			0.58
		),
		SPARK_SOUL_DISSOLVE_DURATION
	)

	self:_TweenPointLight(
		SPARK_DULL_WING_COLOR,
		math.max(
			originalBrightness * 1.15,
			1.5
		),
		SPARK_SOUL_DISSOLVE_DURATION
	)

	task.wait(
		SPARK_SOUL_DISSOLVE_DURATION
	)

	if self.Destroyed then
		return
	end

	----------------------------------------------------------------
	-- BURST APART
	--
	-- Exact original particle order:
	-- little spark -> broken ring -> circle -> explode
	----------------------------------------------------------------

	self.AmbientEmitter:Emit(8)
	self.RingEmitter:Emit(3)
	self.ReformEmitter:Emit(10)

	task.delay(
		0.045,
		function()
			if self.Destroyed then
				return
			end

			self.BurstEmitter:Emit(
				SPARK_SOUL_BURST_COUNT
			)
		end
	)

	self:_TweenPartTransparency(
		self.Body,
		1,
		SPARK_SOUL_VANISH_DURATION
	)

	self:_TweenPartTransparency(
		self.NeonBodyOrb,
		1,
		SPARK_SOUL_VANISH_DURATION
	)

	self:_TweenPartTransparency(
		self.WingL,
		1,
		SPARK_SOUL_VANISH_DURATION
	)

	self:_TweenPartTransparency(
		self.WingR,
		1,
		SPARK_SOUL_VANISH_DURATION
	)

	self:_TweenPointLight(
		self.Body.Color,
		0,
		SPARK_SOUL_VANISH_DURATION
	)

	task.wait(
		SPARK_SOUL_VANISH_DURATION
			+ SPARK_SOUL_INVISIBLE_HOLD
	)

	if self.Destroyed then
		return
	end

	----------------------------------------------------------------
	-- INVISIBLE TRANSITION HOOK
	----------------------------------------------------------------

	if onInvisible then
		onInvisible()
	end

	if self.Destroyed then
		return
	end

	----------------------------------------------------------------
	-- REFORM FROM THE CLOUD
	--
	-- IMPORTANT:
	-- During the ForceField phase the engineered outer SparkBody and both
	-- wings remain completely invisible. Only NeonBodyOrb is allowed to
	-- reform as ForceField. Once that phase completes, the shell and wings
	-- rebuild around it.
	----------------------------------------------------------------

	if
		self.NeonBodyOrb
		and neonBodyOrbTransparencyBeforeBurst ~= nil
	then
		self.Body.Transparency = 1

		if self.WingL then
			self.WingL.Transparency = 1
		end

		if self.WingR then
			self.WingR.Transparency = 1
		end

		self.NeonBodyOrb.Material =
			Enum.Material.ForceField

		if neonBodyOrbColorBeforeBurst then
			self.NeonBodyOrb.Color =
				neonBodyOrbColorBeforeBurst
		end

		self.NeonBodyOrb.Transparency =
			math.max(
				neonBodyOrbTransparencyBeforeBurst,
				0.92
			)
	else
		-- Legacy fallback when NeonBodyOrb is missing.
		self.Body.Material =
			Enum.Material.ForceField

		self.Body.Transparency =
			math.max(
				originalBodyTransparency,
				0.92
			)

		if self.WingL then
			self.WingL.Transparency =
				math.max(
					originalWingLTransparency,
					0.92
				)
		end

		if self.WingR then
			self.WingR.Transparency =
				math.max(
					originalWingRTransparency,
					0.92
				)
		end
	end

	-- Restore the authored wing colour/emission while the physical wings
	-- remain hidden during the inner ForceField reform.
	if
		leftWingColorBeforeBurst
		and leftWingStrengthBeforeBurst
		and self.WingLSurfaceAppearance
	then
		tweenInstance(
			self.WingLSurfaceAppearance,
			SPARK_SOUL_REFORM_DURATION,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out,
			{
				Color =
					leftWingSurfaceColorBeforeBurst
					or leftWingColorBeforeBurst,

				EmissiveTint =
					leftWingColorBeforeBurst,

				EmissiveStrength =
					leftWingStrengthBeforeBurst,
			}
		)
	end

	if
		rightWingColorBeforeBurst
		and rightWingStrengthBeforeBurst
		and self.WingRSurfaceAppearance
	then
		tweenInstance(
			self.WingRSurfaceAppearance,
			SPARK_SOUL_REFORM_DURATION,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out,
			{
				Color =
					rightWingSurfaceColorBeforeBurst
					or rightWingColorBeforeBurst,

				EmissiveTint =
					rightWingColorBeforeBurst,

				EmissiveStrength =
					rightWingStrengthBeforeBurst,
			}
		)
	end

	----------------------------------------------------------------
	-- REVERSED REFORM SEQUENCE
	--
	-- Exact original order:
	-- explode residue -> circle -> broken ring -> little spark
	----------------------------------------------------------------

	self.BurstEmitter:Emit(12)

	task.delay(
		0.035,
		function()
			if self.Destroyed then
				return
			end

			self.ReformEmitter:Emit(
				SPARK_SOUL_REFORM_COUNT
			)
		end
	)

	task.delay(
		0.075,
		function()
			if self.Destroyed then
				return
			end

			self.RingEmitter:Emit(2)
		end
	)

	task.delay(
		0.10,
		function()
			if self.Destroyed then
				return
			end

			self.AmbientEmitter:Emit(12)
		end
	)

	if
		self.NeonBodyOrb
		and neonBodyOrbTransparencyBeforeBurst ~= nil
	then
		self:_TweenPartTransparency(
			self.NeonBodyOrb,
			neonBodyOrbTransparencyBeforeBurst,
			SPARK_SOUL_REFORM_DURATION
		)
	else
		self:_TweenPartTransparency(
			self.Body,
			originalBodyTransparency,
			SPARK_SOUL_REFORM_DURATION
		)

		self:_TweenPartTransparency(
			self.WingL,
			originalWingLTransparency,
			SPARK_SOUL_REFORM_DURATION
		)

		self:_TweenPartTransparency(
			self.WingR,
			originalWingRTransparency,
			SPARK_SOUL_REFORM_DURATION
		)
	end

	self:_TweenPointLight(
		bodyColorBeforeBurst,
		math.max(
			originalBrightness * 3,
			4
		),
		SPARK_SOUL_REFORM_DURATION * 0.55
	)

	task.wait(
		SPARK_SOUL_REFORM_DURATION
	)

	if self.Destroyed then
		return
	end

	-- Put the shared colour driver back in undisputed ownership.
	-- IMPORTANT: VisualColorValue may already equal bodyColorBeforeBurst, which
	-- means assigning the same value does NOT fire PropertyChanged. The outer
	-- body was directly tweened to SPARK_DULL_BODY_COLOR above, so restore the
	-- actual rendered body explicitly as well.
	self.VisualColorValue.Value =
		bodyColorBeforeBurst

	self:_ApplyBodySoulColor(
		bodyColorBeforeBurst
	)

	----------------------------------------------------------------
	-- SETTLE BACK INTO SPARK
	--
	-- The inner soul has reformed. Now rebuild the engineered shell and
	-- wings around it.
	----------------------------------------------------------------

	if self.NeonBodyOrb then
		self.NeonBodyOrb.Material =
			neonBodyOrbMaterialBeforeBurst
			or self.OriginalNeonBodyOrbMaterial
			or self.NeonBodyOrb.Material

		if neonBodyOrbColorBeforeBurst then
			self.NeonBodyOrb.Color =
				neonBodyOrbColorBeforeBurst
		end
	else
		self.Body.Material =
			self.OriginalBodyMaterial
	end

	-- Guarantee the engineered casing returns to its authored material AND
	-- custom MaterialVariant. Setting Material alone is not enough for Spark's
	-- brick-panel look to be treated as canonical state.
	self.Body.Material =
		self.OriginalBodyMaterial

	self.Body.MaterialVariant =
		self.OriginalBodyMaterialVariant

	self:_TweenPartTransparency(
		self.Body,
		originalBodyTransparency,
		SPARK_SOUL_SETTLE_DURATION
	)

	self:_TweenPartTransparency(
		self.WingL,
		originalWingLTransparency,
		SPARK_SOUL_SETTLE_DURATION
	)

	self:_TweenPartTransparency(
		self.WingR,
		originalWingRTransparency,
		SPARK_SOUL_SETTLE_DURATION
	)

	self:_TweenPointLight(
		self.Body.Color,
		originalBrightness,
		SPARK_SOUL_SETTLE_DURATION
	)

	self.AmbientEmitter.Rate =
		SPARK_SOUL_AMBIENT_RATE

	task.wait(
		SPARK_SOUL_SETTLE_DURATION
	)

	if self.Destroyed then
		return
	end

	-- Exact final layered-body ownership.
	self.Body.Transparency =
		originalBodyTransparency

	if self.NeonBodyOrb
		and neonBodyOrbTransparencyBeforeBurst ~= nil
	then
		self.NeonBodyOrb.Transparency =
			neonBodyOrbTransparencyBeforeBurst

		self.NeonBodyOrb.Material =
			neonBodyOrbMaterialBeforeBurst
			or self.OriginalNeonBodyOrbMaterial
			or self.NeonBodyOrb.Material

		if neonBodyOrbColorBeforeBurst then
			self.NeonBodyOrb.Color =
				neonBodyOrbColorBeforeBurst
		end
	end

	-- Final exact outer-shell ownership after the burst.
	self.Body.Color =
		bodyColorBeforeBurst

	self.Body.Material =
		self.OriginalBodyMaterial

	self.Body.MaterialVariant =
		self.OriginalBodyMaterialVariant

	if self.WingL then
		self.WingL.Transparency =
			originalWingLTransparency
	end

	if self.WingR then
		self.WingR.Transparency =
			originalWingRTransparency
	end

	self.SoulBurstInProgress = false
end

-- Alias using the original FirstEffect naming language.
function SparkVisuals:PlaySoulMaterialisationBurst(
	onInvisible: (() -> ())?
)
	self:PlaySoulMaterialisation(
		onInvisible
	)
end

----------------------------------------------------------------
-- CANONICAL INTRO VISUAL SEQUENCE
--
-- This intentionally contains ONLY Spark's visual language.
-- ReplicatedFirst may still own camera movement / model movement.
--
-- If run in parallel with the old movement timeline, the stage lengths
-- line up with the original FirstEffect:
--
-- 0.80 approach visuals
-- 0.12 ForceField flash
-- canonical soul materialisation
-- 0.65 pass visuals
-- 0.70 return visuals
----------------------------------------------------------------

function SparkVisuals:PlayIntro()
	if self.Destroyed then
		return
	end

	self:SelectIntroColorSeed()

	self.AmbientEmitter.Enabled = true

	-- Start wearing this intro's normal colour pair.
	self.VisualColorValue.Value =
		self.IntroNormalBodyColor

	if self.WingLSurfaceAppearance then
		self.WingLSurfaceAppearance.Color =
			self.IntroNormalWingColor

		self.WingLSurfaceAppearance.EmissiveTint =
			self.IntroNormalWingColor
	end

	if self.WingRSurfaceAppearance then
		self.WingRSurfaceAppearance.Color =
			self.IntroNormalWingColor

		self.WingRSurfaceAppearance.EmissiveTint =
			self.IntroNormalWingColor
	end

	if self.PointLight then
		self.PointLight.Color =
			self.IntroNormalWingColor
	end

	local originalBrightness =
		self.OriginalPointLightBrightness
		or 1

	----------------------------------------------------------------
	-- LEFT -> CENTER VISUALS
	----------------------------------------------------------------

	self:_TweenBodySoulColor(
		self.IntroNormalBodyColor,
		SPARK_LEFT_TO_CENTER_DURATION
	)

	self:_TweenWingAppearance(
		self.IntroNormalWingColor,
		SPARK_CLOSE_EMISSIVE_STRENGTH,
		SPARK_LEFT_TO_CENTER_DURATION
	)

	self:_TweenPointLight(
		self.IntroNormalWingColor,
		math.max(
			originalBrightness * 2.5,
			3
		),
		SPARK_LEFT_TO_CENTER_DURATION
	)

	task.wait(
		SPARK_LEFT_TO_CENTER_DURATION
	)

	if self.Destroyed then
		return
	end

	----------------------------------------------------------------
	-- CLOSE PASS FLASH
	----------------------------------------------------------------

	self.Body.Material =
		Enum.Material.ForceField

	self:_TweenBodySoulColor(
		self.IntroForceFieldBodyColor,
		0.10
	)

	self:_TweenWingAppearance(
		self.IntroForceFieldWingColor,
		SPARK_CLOSE_EMISSIVE_STRENGTH,
		0.10
	)

	task.wait(
		SPARK_FORCEFIELD_FLASH_DURATION
	)

	if self.Destroyed then
		return
	end

	self.Body.Material =
		self.OriginalBodyMaterial

	self.Body.MaterialVariant =
		self.OriginalBodyMaterialVariant

	----------------------------------------------------------------
	-- SIGNATURE SOUL BURST / REMATERIALISATION
	----------------------------------------------------------------

	self:PlaySoulMaterialisation()

	if self.Destroyed then
		return
	end

	----------------------------------------------------------------
	-- CENTER -> RIGHT VISUALS
	----------------------------------------------------------------

	self:_TweenBodySoulColor(
		self.IntroNormalBodyColor,
		SPARK_CENTER_TO_RIGHT_DURATION
	)

	self:_TweenWingAppearance(
		self.IntroNormalWingColor,
		SPARK_PASS_EMISSIVE_STRENGTH,
		SPARK_CENTER_TO_RIGHT_DURATION
	)

	self:_TweenPointLight(
		self.IntroNormalWingColor,
		math.max(
			originalBrightness * 1.8,
			2
		),
		SPARK_CENTER_TO_RIGHT_DURATION
	)

	task.wait(
		SPARK_CENTER_TO_RIGHT_DURATION
	)

	if self.Destroyed then
		return
	end

	----------------------------------------------------------------
	-- RIGHT -> CENTER VISUALS
	----------------------------------------------------------------

	self.Body.Material =
		self.OriginalBodyMaterial

	self.Body.MaterialVariant =
		self.OriginalBodyMaterialVariant

	self:_TweenBodySoulColor(
		self.IntroNormalBodyColor,
		SPARK_RIGHT_TO_CENTER_DURATION
	)

	self:_TweenWingAppearance(
		self.IntroNormalWingColor,
		SPARK_PASS_EMISSIVE_STRENGTH,
		SPARK_RIGHT_TO_CENTER_DURATION
	)

	self:_TweenPointLight(
		self.IntroNormalWingColor,
		originalBrightness,
		SPARK_RIGHT_TO_CENTER_DURATION
	)

	task.wait(
		SPARK_RIGHT_TO_CENTER_DURATION
	)
end

-- If you prefer the shorter object-language:
-- visuals:Intro()
function SparkVisuals:Intro()
	self:PlayIntro()
end

----------------------------------------------------------------
-- TRAIL API
----------------------------------------------------------------

function SparkVisuals:SetTrailEnabled(
	enabled: boolean
)
	self.Trail.Enabled =
		enabled
		and not self.SoulBurstInProgress
end

function SparkVisuals:UpdateTrailFromPosition(
	worldPosition: Vector3,
	deltaTime: number,
	startSpeed: number?
)
	local previousPosition =
		self.LastTrailWorldPosition

	self.LastTrailWorldPosition =
		worldPosition

	local movementSpeed = 0

	if
		previousPosition
		and deltaTime > 0
	then
		movementSpeed =
			(
				worldPosition
				- previousPosition
			).Magnitude
			/ deltaTime
	end

	self.Trail.Enabled =
		not self.SoulBurstInProgress
		and movementSpeed
		>= (
			startSpeed
			or SPARK_CINEMATIC_TRAIL_START_SPEED
		)
end

----------------------------------------------------------------
-- AMBIENT SOUL MATTER API
----------------------------------------------------------------

function SparkVisuals:SetAmbientEnabled(
	enabled: boolean
)
	self.AmbientEmitter.Enabled =
		enabled
end

----------------------------------------------------------------
-- RESTORE / HANDOFF
----------------------------------------------------------------

function SparkVisuals:RestoreOriginalAppearance(
	duration: number?
)
	self.IdleVisualsActive = false
	self.IdleVisualGeneration += 1
	self:_CancelIdleVisualTweens()

	local restoreDuration =
		duration
		or SPARK_READY_DURATION

	self:_TweenBodySoulColor(
		self.OriginalBodyColor,
		restoreDuration
	)

	if self.BodySurfaceAppearance
		and self.OriginalBodySurfaceColor
		and self.OriginalBodySurfaceEmissiveTint
		and self.OriginalBodySurfaceEmissiveStrength ~= nil
	then
		tweenInstance(
			self.BodySurfaceAppearance,
			restoreDuration,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			{
				Color = self.OriginalBodySurfaceColor,
				EmissiveTint =
					self.OriginalBodySurfaceEmissiveTint,
				EmissiveStrength =
					self.OriginalBodySurfaceEmissiveStrength,
			}
		)
	end

	if
		self.WingLSurfaceAppearance
		and self.OriginalWingLEmissiveTint
		and self.OriginalWingLEmissiveStrength
	then
		tweenInstance(
			self.WingLSurfaceAppearance,
			restoreDuration,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			{
				Color =
					self.OriginalWingLColor
					or self.OriginalWingLEmissiveTint,

				EmissiveTint =
					self.OriginalWingLEmissiveTint,

				EmissiveStrength =
					self.OriginalWingLEmissiveStrength,
			}
		)
	end

	if
		self.WingRSurfaceAppearance
		and self.OriginalWingREmissiveTint
		and self.OriginalWingREmissiveStrength
	then
		tweenInstance(
			self.WingRSurfaceAppearance,
			restoreDuration,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			{
				Color =
					self.OriginalWingRColor
					or self.OriginalWingREmissiveTint,

				EmissiveTint =
					self.OriginalWingREmissiveTint,

				EmissiveStrength =
					self.OriginalWingREmissiveStrength,
			}
		)
	end

	if
		self.PointLight
		and self.OriginalPointLightColor
	then
		self:_TweenPointLight(
			self.OriginalPointLightColor,
			self.OriginalPointLightBrightness,
			restoreDuration
		)
	end

	self:_TweenPartTransparency(
		self.Body,
		self.OriginalBodyTransparency,
		restoreDuration
	)

	if
		self.NeonBodyOrb
		and self.OriginalNeonBodyOrbTransparency ~= nil
	then
		self:_TweenPartTransparency(
			self.NeonBodyOrb,
			self.OriginalNeonBodyOrbTransparency,
			restoreDuration
		)
	end

	self:_TweenPartTransparency(
		self.WingL,
		self.OriginalWingLTransparency,
		restoreDuration
	)

	self:_TweenPartTransparency(
		self.WingR,
		self.OriginalWingRTransparency,
		restoreDuration
	)

	task.wait(
		restoreDuration
	)

	if self.Destroyed then
		return
	end

	-- Exact final ownership values.
	self.VisualColorValue.Value =
		self.OriginalBodyColor

	self.Body.Color =
		self.OriginalBodyColor

	self.Body.Material =
		self.OriginalBodyMaterial

	self.Body.MaterialVariant =
		self.OriginalBodyMaterialVariant

	if self.BodySurfaceAppearance
		and self.OriginalBodySurfaceColor
		and self.OriginalBodySurfaceEmissiveTint
		and self.OriginalBodySurfaceEmissiveStrength ~= nil
	then
		self.BodySurfaceAppearance.Color =
			self.OriginalBodySurfaceColor

		self.BodySurfaceAppearance.EmissiveTint =
			self.OriginalBodySurfaceEmissiveTint

		self.BodySurfaceAppearance.EmissiveStrength =
			self.OriginalBodySurfaceEmissiveStrength
	end

	self.Body.Transparency =
		self.OriginalBodyTransparency

	if self.NeonBodyOrb then
		if self.OriginalNeonBodyOrbColor then
			self.NeonBodyOrb.Color =
				self.OriginalNeonBodyOrbColor
		end

		if self.OriginalNeonBodyOrbMaterial then
			self.NeonBodyOrb.Material =
				self.OriginalNeonBodyOrbMaterial
		end

		if self.OriginalNeonBodyOrbTransparency ~= nil then
			self.NeonBodyOrb.Transparency =
				self.OriginalNeonBodyOrbTransparency
		end
	end

	if self.WingL then
		self.WingL.Transparency =
			self.OriginalWingLTransparency
	end

	if self.WingR then
		self.WingR.Transparency =
			self.OriginalWingRTransparency
	end

	if
		self.WingLSurfaceAppearance
		and self.OriginalWingLEmissiveTint
		and self.OriginalWingLEmissiveStrength
	then
		if self.OriginalWingLColor then
			self.WingLSurfaceAppearance.Color =
				self.OriginalWingLColor
		end

		self.WingLSurfaceAppearance.EmissiveTint =
			self.OriginalWingLEmissiveTint

		self.WingLSurfaceAppearance.EmissiveStrength =
			self.OriginalWingLEmissiveStrength
	end

	if
		self.WingRSurfaceAppearance
		and self.OriginalWingREmissiveTint
		and self.OriginalWingREmissiveStrength
	then
		if self.OriginalWingRColor then
			self.WingRSurfaceAppearance.Color =
				self.OriginalWingRColor
		end

		self.WingRSurfaceAppearance.EmissiveTint =
			self.OriginalWingREmissiveTint

		self.WingRSurfaceAppearance.EmissiveStrength =
			self.OriginalWingREmissiveStrength
	end

	if
		self.PointLight
		and self.OriginalPointLightColor
	then
		self.PointLight.Color =
			self.OriginalPointLightColor

		self.PointLight.Brightness =
			self.OriginalPointLightBrightness
	end
end

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------

function SparkVisuals:Destroy()
	if self.Destroyed then
		return
	end

	self.IdleVisualsActive = false
	self.IdleVisualGeneration += 1
	self:_CancelIdleVisualTweens()

	self.Destroyed = true

	if self.VisualColorConnection then
		self.VisualColorConnection:Disconnect()
		self.VisualColorConnection = nil
	end

	if self.VisualColorValue then
		self.VisualColorValue:Destroy()
	end
end

return SparkVisuals
