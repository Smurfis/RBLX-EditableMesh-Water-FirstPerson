--!strict

local RunService = game:GetService("RunService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

local localPlayer: Player = Players.LocalPlayer

ReplicatedFirst:RemoveDefaultLoadingScreen()

local SPARK_INTRO_READY_ATTRIBUTE: string = "SparkIntroReadyForCameraTransition"

local SPARK_INITIAL_LOAD_COMPLETE_ATTRIBUTE: string = "SparkInitialLoadComplete"

local SPARK_INTRO_STAGE_ATTRIBUTE: string = "SparkIntroStage"

local SPARK_LOADING_SCREEN_READY_ATTRIBUTE: string = "SparkLoadingScreenReady"

local SPARK_INTRO_FREEZE_ACTION_NAME: string = "SparkIntro_FreezeInput"

local LOADING_ORIGINAL_TRANSPARENCY_ATTRIBUTE: string = "SparkLoadingOriginalLocalTransparency"

localPlayer:SetAttribute(SPARK_INTRO_READY_ATTRIBUTE, false)

localPlayer:SetAttribute(SPARK_INITIAL_LOAD_COMPLETE_ATTRIBUTE, false)

localPlayer:SetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE, "Booting")

local function waitForLoadingScreenReady()
	local deadline = time() + 30
	while localPlayer:GetAttribute(SPARK_LOADING_SCREEN_READY_ATTRIBUTE) ~= true do
		local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
		local loadingGui = playerGui and playerGui:FindFirstChild("LoadingGui")
		if not loadingGui or (loadingGui:IsA("ScreenGui") and not loadingGui.Enabled) then
			localPlayer:SetAttribute(SPARK_LOADING_SCREEN_READY_ATTRIBUTE, true)
			return
		end
		if time() >= deadline then
			warn("[Spark Intro]: Loading screen ready signal was not received; continuing.")
			return
		end
		task.wait(0.05)
	end
end

---------------------------------------------------------
-- SPARK LOADING SCREEN
---------------------------------------------------------

local loadingGui: ScreenGui = localPlayer:WaitForChild("PlayerGui"):FindFirstChild("LoadingGui") :: ScreenGui
	or Instance.new("ScreenGui")
loadingGui.Name = "LoadingGui"
loadingGui.IgnoreGuiInset = true
loadingGui.ResetOnSpawn = false
loadingGui.DisplayOrder = 1000
loadingGui.Enabled = true
loadingGui.Parent = localPlayer:WaitForChild("PlayerGui")

local loadingGroup: CanvasGroup = loadingGui:FindFirstChild("SparkLoadingGroup") :: CanvasGroup
	or Instance.new("CanvasGroup")
loadingGroup.Name = "SparkLoadingGroup"
loadingGroup.Size = UDim2.fromScale(1, 1)
loadingGroup.Parent = loadingGui

local loadingBackground: Frame = loadingGui:FindFirstChild("SparkLoadingBackground") :: Frame or Instance.new("Frame")
loadingBackground.Name = "SparkLoadingBackground"
loadingBackground.Size = UDim2.fromScale(1, 1)
loadingBackground.BackgroundColor3 = Color3.fromRGB(76, 76, 76)
loadingBackground.BorderSizePixel = 0
loadingBackground.ZIndex = 0
loadingBackground.Parent = loadingGui
loadingGroup.ZIndex = 1

local loadingTopPanel: Frame = loadingGui:FindFirstChild("SparkLoadingTopPanel") :: Frame or Instance.new("Frame")
loadingTopPanel.Name = "SparkLoadingTopPanel"
loadingTopPanel.Size = UDim2.fromScale(1.5, 0.5)
loadingTopPanel.Position = UDim2.fromScale(0, 0)
loadingTopPanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
loadingTopPanel.BorderSizePixel = 0
loadingTopPanel.ZIndex = 2
loadingTopPanel.Parent = loadingGui

local loadingBottomPanel: Frame = loadingGui:FindFirstChild("SparkLoadingBottomPanel") :: Frame or Instance.new("Frame")
loadingBottomPanel.Name = "SparkLoadingBottomPanel"
loadingBottomPanel.Size = UDim2.fromScale(1.5, 0.5)
loadingBottomPanel.Position = UDim2.fromScale(0, 0.5)
loadingBottomPanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
loadingBottomPanel.BorderSizePixel = 0
loadingBottomPanel.ZIndex = 2
loadingBottomPanel.Parent = loadingGui

local loadingText: TextLabel = loadingGroup:FindFirstChild("Status") :: TextLabel or Instance.new("TextLabel")
loadingText.Name = "Status"
loadingText.AnchorPoint = Vector2.new(0.5, 0.5)
loadingText.Position = UDim2.fromScale(0.5, 0.72)
loadingText.Size = UDim2.fromScale(0.8, 0.08)
loadingText.BackgroundTransparency = 1
loadingText.Font = Enum.Font.FredokaOne
loadingText.TextSize = 24
loadingText.TextColor3 = Color3.fromRGB(182, 182, 182)
loadingText.Text = "Finding your Spark..."
loadingText.Parent = loadingGroup

local loadingGradient: UIGradient = loadingText:FindFirstChild("Wipe") :: UIGradient or Instance.new("UIGradient")
loadingGradient.Name = "Wipe"
loadingGradient.Parent = loadingText

local function wipeLoadingText(alpha: number, exiting: boolean)
	local edge = math.clamp(alpha, 0.001, 0.999)
	local left = if exiting then 1 else 0
	loadingGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, left),
		NumberSequenceKeypoint.new(math.max(0.0001, edge - 0.04), left),
		NumberSequenceKeypoint.new(edge, 1 - left),
		NumberSequenceKeypoint.new(1, 1 - left),
	})
end

local loadingTextRevision = 0
local function setLoadingText(text: string)
	loadingTextRevision += 1
	local revision = loadingTextRevision
	task.spawn(function()
		local started = time()
		while revision == loadingTextRevision do
			local alpha = math.clamp((time() - started) / 0.35, 0, 1)
			wipeLoadingText(alpha, true)
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		if revision ~= loadingTextRevision then
			return
		end
		loadingText.Text = text
		started = time()
		while revision == loadingTextRevision do
			local alpha = math.clamp((time() - started) / 0.45, 0, 1)
			wipeLoadingText(alpha, false)
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

local loadingRevealStarted = false

local function revealSparkFromLoadingScreen()
	if loadingRevealStarted then
		return
	end

	loadingRevealStarted = true

	---------------------------------------------------------
	-- OPEN THE LOADING PANELS
	---------------------------------------------------------

	local panelTweenInfo = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local topTween = TweenService:Create(loadingTopPanel, panelTweenInfo, {
		Position = UDim2.fromScale(0, -0.55),
	})

	local bottomTween = TweenService:Create(loadingBottomPanel, panelTweenInfo, {
		Position = UDim2.fromScale(0, 1.05),
	})

	---------------------------------------------------------
	-- FADE STATUS TEXT / LOADING CONTENT
	---------------------------------------------------------

	local loadingGroupFade =
		TweenService:Create(loadingGroup, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = 1,
		})

	topTween:Play()
	bottomTween:Play()
	loadingGroupFade:Play()

	---------------------------------------------------------
	-- WAIT UNTIL THE PANELS HAVE CLEARED THE SCREEN
	---------------------------------------------------------

	bottomTween.Completed:Wait()

	---------------------------------------------------------
	-- LOADING SCREEN IS NOW FINISHED
	---------------------------------------------------------

	loadingBackground.BackgroundTransparency = 1

	loadingTopPanel.Visible = false
	loadingBottomPanel.Visible = false

	loadingGroup.Visible = false

	---------------------------------------------------------
	-- IMPORTANT:
	-- The custom loading screen has now done its only job:
	-- replacing Roblox's default loading screen.
	--
	-- Disable it BEFORE the actual Spark cinematic begins.
	---------------------------------------------------------

	loadingGui.Enabled = false

	---------------------------------------------------------
	-- TELL THE CINEMATIC IT MAY NOW BEGIN
	---------------------------------------------------------

	localPlayer:SetAttribute(SPARK_LOADING_SCREEN_READY_ATTRIBUTE, true)

	print("[Spark Intro]: Loading screen cleared. " .. "ReplicatedFirst cinematic may begin.")
end

local function loadingTextForStage(stage: string): string
	if stage == "ReadyForCameraTransition" then
		return "Spark is finding your Vessel, Character and you..."
	elseif stage == "PlayingInitialSparkCinematic" then
		return "Spark Found"
	elseif stage == "LoadingCameraLocked" then
		return "Finding your Spark..."
	end
	return "Spark is finding your Vessel, Character and you..."
end

localPlayer:GetAttributeChangedSignal(SPARK_INTRO_STAGE_ATTRIBUTE):Connect(function()
	local stage = localPlayer:GetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE)
	if typeof(stage) == "string" then
		setLoadingText(loadingTextForStage(stage))
	end
end)

setLoadingText("Finding your Spark...")

ContextActionService:BindActionAtPriority(
	SPARK_INTRO_FREEZE_ACTION_NAME,
	function(): Enum.ContextActionResult
		return Enum.ContextActionResult.Sink
	end,
	false,
	10001,
	Enum.PlayerActions.CharacterForward,
	Enum.PlayerActions.CharacterBackward,
	Enum.PlayerActions.CharacterLeft,
	Enum.PlayerActions.CharacterRight,
	Enum.PlayerActions.CharacterJump
)

---------------------------------------------------------
-- INITIAL CHARACTER CONCEALMENT
---------------------------------------------------------

local concealedCharacterConnection: RBXScriptConnection? = nil

local function concealCharacterPart(part: BasePart)
	if part:GetAttribute(LOADING_ORIGINAL_TRANSPARENCY_ATTRIBUTE) == nil then
		part:SetAttribute(LOADING_ORIGINAL_TRANSPARENCY_ATTRIBUTE, part.LocalTransparencyModifier)
	end

	part.LocalTransparencyModifier = 1
end

local function concealInitialCharacter(character: Model)
	if concealedCharacterConnection then
		concealedCharacterConnection:Disconnect()
		concealedCharacterConnection = nil
	end

	for _, descendant: Instance in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			concealCharacterPart(descendant)
		end
	end

	concealedCharacterConnection = character.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			concealCharacterPart(descendant)
		end
	end)
end

local function restoreInitialCharacter()
	if concealedCharacterConnection then
		concealedCharacterConnection:Disconnect()
		concealedCharacterConnection = nil
	end

	local currentCharacter: Model? = localPlayer.Character

	if not currentCharacter then
		return
	end

	for _, descendant: Instance in currentCharacter:GetDescendants() do
		if descendant:IsA("BasePart") then
			local originalTransparency: any = descendant:GetAttribute(LOADING_ORIGINAL_TRANSPARENCY_ATTRIBUTE)

			if typeof(originalTransparency) == "number" then
				descendant.LocalTransparencyModifier = originalTransparency

				descendant:SetAttribute(LOADING_ORIGINAL_TRANSPARENCY_ATTRIBUTE, nil)
			end
		end
	end
end

local characterAddedConnection: RBXScriptConnection = localPlayer.CharacterAdded:Connect(concealInitialCharacter)

if localPlayer.Character then
	concealInitialCharacter(localPlayer.Character)
end

local loadCompleteConnection: RBXScriptConnection? = nil

loadCompleteConnection = localPlayer:GetAttributeChangedSignal(SPARK_INITIAL_LOAD_COMPLETE_ATTRIBUTE):Connect(function()
	if localPlayer:GetAttribute(SPARK_INITIAL_LOAD_COMPLETE_ATTRIBUTE) ~= true then
		return
	end

	restoreInitialCharacter()
	characterAddedConnection:Disconnect()

	if loadCompleteConnection then
		loadCompleteConnection:Disconnect()
		loadCompleteConnection = nil
	end
end)

---------------------------------------------------------
-- LOADING CAMERA
---------------------------------------------------------

local LOADING_CAMERA_BIND_NAME: string = "LoadingCameraLock"
local LOADING_SPARK_BIND_NAME: string = "LoadingSparkCinematic"

local LOADING_CAMERA_POSITION: Vector3 = Vector3.new(0, 2000, 0)

---------------------------------------------------------
-- SPARK
---------------------------------------------------------

local SPARK_INTRO_TEMPLATE_NAME: string = "SparkIntroTemplate"
local SPARK_GAMEPLAY_TEMPLATE_NAME: string = "Spark"
local SPARK_CINEMATIC_NAME: string = "CinematicSpark"

local SPARK_FLIGHT_ANIMATION_ID: string = "rbxassetid://110340492323310"

---------------------------------------------------------
-- SPARK CINEMATIC POSITION
---------------------------------------------------------

local SPARK_START_HORIZONTAL_OFFSET: number = -8
local SPARK_CENTER_HORIZONTAL_OFFSET: number = 0
local SPARK_RIGHT_HORIZONTAL_OFFSET: number = 8

local SPARK_START_DISTANCE: number = 18
local SPARK_CLOSE_DISTANCE: number = 10.5
local SPARK_NORMAL_DISTANCE: number = 14
local SPARK_RIGHT_DISTANCE: number = 15

---------------------------------------------------------
-- SPARK CINEMATIC SCALE
---------------------------------------------------------

local SPARK_START_SCALE: number = 0.5
local SPARK_CLOSE_SCALE: number = 5
local SPARK_PASS_SCALE: number = 1.6
local SPARK_NORMAL_SCALE: number = 1

---------------------------------------------------------
-- CINEMATIC TIMING
---------------------------------------------------------

local SPARK_OPENING_HOLD: number = 0.20

local SPARK_LEFT_TO_CENTER_DURATION: number = 0.80
local SPARK_CENTER_TO_RIGHT_DURATION: number = 0.65
local SPARK_RIGHT_TO_CENTER_DURATION: number = 0.70

local SPARK_FORCEFIELD_FLASH_DURATION: number = 0.12

local SPARK_READY_DURATION: number = 0.45

---------------------------------------------------------
-- CINEMATIC COLOR SEED
---------------------------------------------------------

-- Every intro gets one random hue seed and TWO related variants:
--
-- Normal      = Spark's main cinematic colour.
-- ForceField  = a brighter shifted colour used for his close flash /
--               soul-rematerialisation state.
--
-- Gameplay Spark is still restored to his original green before the
-- ReplicatedFirst -> camera-module handoff.
local SPARK_INTRO_NORMAL_SATURATION_MIN: number = 0.68
local SPARK_INTRO_NORMAL_SATURATION_MAX: number = 0.92

local SPARK_INTRO_FORCEFIELD_SATURATION_MIN: number = 0.34
local SPARK_INTRO_FORCEFIELD_SATURATION_MAX: number = 0.58

local SPARK_INTRO_FORCEFIELD_HUE_SHIFT_MIN: number = 0.08
local SPARK_INTRO_FORCEFIELD_HUE_SHIFT_MAX: number = 0.22

local SPARK_CLOSE_EMISSIVE_STRENGTH: number = 16
local SPARK_PASS_EMISSIVE_STRENGTH: number = 10

local sparkIntroColorSeed: number = 0

local sparkIntroNormalBodyColor: Color3 = Color3.fromRGB(111, 242, 129)

local sparkIntroNormalWingColor: Color3 = Color3.fromRGB(150, 255, 170)

local sparkIntroForceFieldBodyColor: Color3 = Color3.fromRGB(205, 255, 240)

local sparkIntroForceFieldWingColor: Color3 = Color3.fromRGB(235, 255, 255)

local function selectSparkIntroColorSeed(spark: Model)
	local unixMilliseconds: number = DateTime.now().UnixTimestampMillis

	-- Keep the seed in Random.new's comfortable signed integer range.
	sparkIntroColorSeed = unixMilliseconds % 2147483647

	local random = Random.new(sparkIntroColorSeed)

	local normalHue: number = random:NextNumber()

	local forceFieldHueDirection: number = if random:NextNumber() >= 0.5 then 1 else -1

	local forceFieldHueShift: number = random:NextNumber(
		SPARK_INTRO_FORCEFIELD_HUE_SHIFT_MIN,
		SPARK_INTRO_FORCEFIELD_HUE_SHIFT_MAX
	) * forceFieldHueDirection

	local forceFieldHue: number = (normalHue + forceFieldHueShift) % 1

	sparkIntroNormalBodyColor = Color3.fromHSV(
		normalHue,
		random:NextNumber(SPARK_INTRO_NORMAL_SATURATION_MIN, SPARK_INTRO_NORMAL_SATURATION_MAX),
		1
	)

	sparkIntroForceFieldBodyColor = Color3.fromHSV(
		forceFieldHue,
		random:NextNumber(SPARK_INTRO_FORCEFIELD_SATURATION_MIN, SPARK_INTRO_FORCEFIELD_SATURATION_MAX),
		1
	)

	-- Wings use the same two colour identities, just lifted toward white
	-- so their emissive SurfaceAppearance still reads clearly.
	sparkIntroNormalWingColor = sparkIntroNormalBodyColor:Lerp(Color3.new(1, 1, 1), 0.18)

	sparkIntroForceFieldWingColor = sparkIntroForceFieldBodyColor:Lerp(Color3.new(1, 1, 1), 0.34)

	-- Leave the pair on CinematicSpark so the camera module can opt into
	-- continuing this exact intro palette later without re-rolling it.
	spark:SetAttribute("IntroColorSeed", sparkIntroColorSeed)

	spark:SetAttribute("IntroColorPrimary", sparkIntroNormalBodyColor)

	spark:SetAttribute("IntroColorSecondary", sparkIntroForceFieldBodyColor)

	spark:SetAttribute("IntroColorNormal", sparkIntroNormalBodyColor)

	spark:SetAttribute("IntroColorForceField", sparkIntroForceFieldBodyColor)

	print(
		"[Spark Intro] Color seed:",
		sparkIntroColorSeed,
		"Normal:",
		sparkIntroNormalBodyColor,
		"ForceField:",
		sparkIntroForceFieldBodyColor
	)
end

---------------------------------------------------------
-- SPARK SIGNATURE SOUL VFX
---------------------------------------------------------

-- USER SPARK PARTICLE SET
--
-- 417249972 = little spark
-- 417249923 = clean circle
-- 417249675 = circle explode 2
-- 417249865 = broken/cut-out circle frame
--
-- We deliberately sequence these rather than relying on generic
-- fairy-dust particles, so Spark has his own visual language.
local SPARK_SOUL_AMBIENT_TEXTURE: string = "rbxassetid://417249972"

local SPARK_SOUL_CIRCLE_TEXTURE: string = "rbxassetid://417249923"

local SPARK_SOUL_EXPLODE_TEXTURE: string = "rbxassetid://417249675"

local SPARK_SOUL_RING_TEXTURE: string = "rbxassetid://417249865"

-- A subtle cloud remains inside/around Spark so his body looks
-- like loosely-contained soul matter rather than a solid orb.
local SPARK_SOUL_AMBIENT_RATE: number = 28
local SPARK_SOUL_AMBIENT_BURST_RATE: number = 135

local SPARK_SOUL_BURST_COUNT: number = 70
local SPARK_SOUL_REFORM_COUNT: number = 52

-- When Spark "runs out of himself", his colour and wing emission
-- desaturate toward this deadened soul-grey before reforming.
local SPARK_DULL_BODY_COLOR: Color3 = Color3.fromRGB(120, 132, 126)

local SPARK_DULL_WING_COLOR: Color3 = Color3.fromRGB(165, 175, 170)

local SPARK_DULL_EMISSIVE_STRENGTH: number = 1.5

local SPARK_SOUL_DISSOLVE_DURATION: number = 0.14
local SPARK_SOUL_VANISH_DURATION: number = 0.10
local SPARK_SOUL_INVISIBLE_HOLD: number = 0.055
local SPARK_SOUL_REFORM_DURATION: number = 0.24
local SPARK_SOUL_SETTLE_DURATION: number = 0.16

-- Cinematic version is slightly longer/brighter than gameplay,
-- but uses the same centered, body-coloured identity.
local SPARK_CINEMATIC_TRAIL_LIFETIME: number = 0.34
local SPARK_CINEMATIC_TRAIL_START_SPEED: number = 1.25

---------------------------------------------------------
-- STATE
---------------------------------------------------------

local cinematicSpark: Model? = nil
local cinematicSparkFlightTrack: AnimationTrack? = nil

local sparkBody: BasePart? = nil
local sparkWingL: BasePart? = nil
local sparkWingR: BasePart? = nil

local sparkWingLSurfaceAppearance: SurfaceAppearance? = nil
local sparkWingRSurfaceAppearance: SurfaceAppearance? = nil

local sparkPointLight: PointLight? = nil

local sparkSoulAttachment: Attachment? = nil
local sparkSoulAmbientEmitter: ParticleEmitter? = nil
local sparkSoulBurstEmitter: ParticleEmitter? = nil
local sparkSoulReformEmitter: ParticleEmitter? = nil
local sparkSoulRingEmitter: ParticleEmitter? = nil

local cinematicSparkTrail: Trail? = nil
local sparkLastTrailWorldPosition: Vector3? = nil

local sparkSoulBurstInProgress: boolean = false

local sparkOriginalModelScale: number = 1

local sparkOriginalBodyColor: Color3? = nil
local sparkOriginalBodyMaterial: Enum.Material? = nil
local sparkOriginalBodyTransparency: number? = nil

local sparkOriginalWingLTransparency: number? = nil
local sparkOriginalWingRTransparency: number? = nil

local sparkOriginalWingLColor: Color3? = nil
local sparkOriginalWingRColor: Color3? = nil

local sparkOriginalWingLEmissiveTint: Color3? = nil
local sparkOriginalWingREmissiveTint: Color3? = nil

local sparkOriginalWingLEmissiveStrength: number? = nil
local sparkOriginalWingREmissiveStrength: number? = nil

-- Shared color driver for SparkBody + particles + Trail.
-- This guarantees all three interpolate together.
local sparkVisualColorValue = Instance.new("Color3Value")

local sparkVisualColorConnection: RBXScriptConnection? = nil

local sparkOriginalPointLightColor: Color3? = nil
local sparkOriginalPointLightBrightness: number? = nil

local gameFinishedLoading: boolean = false
local initialSparkCinematicFinished: boolean = false
local preparingSparkForCameraModule: boolean = false

---------------------------------------------------------
-- CINEMATIC VALUES
---------------------------------------------------------

local sparkHorizontalOffsetValue = Instance.new("NumberValue")

sparkHorizontalOffsetValue.Value = SPARK_START_HORIZONTAL_OFFSET

local sparkDistanceValue = Instance.new("NumberValue")

sparkDistanceValue.Value = SPARK_START_DISTANCE

local sparkScaleValue = Instance.new("NumberValue")

sparkScaleValue.Value = SPARK_START_SCALE

local sparkBankValue = Instance.new("NumberValue")

sparkBankValue.Value = -18

---------------------------------------------------------
-- TWEEN HELPERS
---------------------------------------------------------

local function tweenNumber(
	valueObject: NumberValue,
	targetValue: number,
	duration: number,
	easingStyle: Enum.EasingStyle,
	easingDirection: Enum.EasingDirection
): Tween
	local tween: Tween = TweenService:Create(valueObject, TweenInfo.new(duration, easingStyle, easingDirection), {
		Value = targetValue,
	})

	tween:Play()

	return tween
end

local function tweenSparkBodyColor(color: Color3, duration: number)
	if not sparkBody then
		return
	end

	TweenService
		:Create(sparkVisualColorValue, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Value = color,
		})
		:Play()
end

local function tweenSparkWingAppearance(color: Color3, emissiveStrength: number, duration: number)
	local leftSurface: SurfaceAppearance? = sparkWingLSurfaceAppearance

	local rightSurface: SurfaceAppearance? = sparkWingRSurfaceAppearance

	if leftSurface then
		TweenService:Create(leftSurface, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Color = color,
			EmissiveTint = color,
			EmissiveStrength = emissiveStrength,
		}):Play()
	end

	if rightSurface then
		TweenService:Create(rightSurface, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Color = color,
			EmissiveTint = color,
			EmissiveStrength = emissiveStrength,
		}):Play()
	end
end

local function tweenSparkPointLight(color: Color3, brightness: number, duration: number)
	local pointLight: PointLight? = sparkPointLight

	if not pointLight then
		return
	end

	TweenService:Create(pointLight, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Color = color,
		Brightness = brightness,
	}):Play()
end

local function tweenSparkPartTransparency(part: BasePart?, transparency: number, duration: number)
	if not part then
		return
	end

	TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Transparency = transparency,
	}):Play()
end

local function updateSparkSoulVFXColor(color: Color3?)
	local body: BasePart? = sparkBody

	if not body then
		return
	end

	local resolvedColor: Color3 = color or sparkVisualColorValue.Value

	local colorSequence = ColorSequence.new(resolvedColor)

	if sparkSoulAmbientEmitter then
		sparkSoulAmbientEmitter.Color = colorSequence
	end

	if sparkSoulBurstEmitter then
		sparkSoulBurstEmitter.Color = colorSequence
	end

	if sparkSoulReformEmitter then
		sparkSoulReformEmitter.Color = colorSequence
	end

	if sparkSoulRingEmitter then
		sparkSoulRingEmitter.Color = colorSequence
	end

	if cinematicSparkTrail then
		cinematicSparkTrail.Color = colorSequence
	end
end

local function tweenSparkWingSoulAppearance(color: Color3, emissiveStrength: number, duration: number)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	if sparkWingLSurfaceAppearance then
		TweenService:Create(sparkWingLSurfaceAppearance, tweenInfo, {
			Color = color,
			EmissiveTint = color,
			EmissiveStrength = emissiveStrength,
		}):Play()
	end

	if sparkWingRSurfaceAppearance then
		TweenService:Create(sparkWingRSurfaceAppearance, tweenInfo, {
			Color = color,
			EmissiveTint = color,
			EmissiveStrength = emissiveStrength,
		}):Play()
	end
end

---------------------------------------------------------
-- SPARK SOUL MATERIALISATION
---------------------------------------------------------

local function playSparkSoulMaterialisationBurst()
	local body: BasePart? = sparkBody

	if not body then
		return
	end

	sparkSoulBurstInProgress = true

	local originalBodyTransparency: number = sparkOriginalBodyTransparency or 0

	local originalWingLTransparency: number = sparkOriginalWingLTransparency or 0

	local originalWingRTransparency: number = sparkOriginalWingRTransparency or 0

	local originalBrightness: number = sparkOriginalPointLightBrightness or 1

	local bodyColorBeforeBurst: Color3 = body.Color

	local leftWingSurfaceColorBeforeBurst: Color3? = if sparkWingLSurfaceAppearance
		then sparkWingLSurfaceAppearance.Color
		else nil

	local rightWingSurfaceColorBeforeBurst: Color3? = if sparkWingRSurfaceAppearance
		then sparkWingRSurfaceAppearance.Color
		else nil

	local leftWingColorBeforeBurst: Color3? = if sparkWingLSurfaceAppearance
		then sparkWingLSurfaceAppearance.EmissiveTint
		else nil

	local rightWingColorBeforeBurst: Color3? = if sparkWingRSurfaceAppearance
		then sparkWingRSurfaceAppearance.EmissiveTint
		else nil

	local leftWingStrengthBeforeBurst: number? = if sparkWingLSurfaceAppearance
		then sparkWingLSurfaceAppearance.EmissiveStrength
		else nil

	local rightWingStrengthBeforeBurst: number? = if sparkWingRSurfaceAppearance
		then sparkWingRSurfaceAppearance.EmissiveStrength
		else nil

	-----------------------------------------------------
	-- SOUL MATTER BECOMES VISIBLE
	-----------------------------------------------------

	if sparkSoulAmbientEmitter then
		sparkSoulAmbientEmitter.Enabled = true
		sparkSoulAmbientEmitter.Rate = SPARK_SOUL_AMBIENT_BURST_RATE
	end

	body.Material = Enum.Material.Glass

	TweenService
		:Create(body, TweenInfo.new(SPARK_SOUL_DISSOLVE_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Color = SPARK_DULL_BODY_COLOR,
		})
		:Play()

	tweenSparkWingSoulAppearance(SPARK_DULL_WING_COLOR, SPARK_DULL_EMISSIVE_STRENGTH, SPARK_SOUL_DISSOLVE_DURATION)

	tweenSparkPartTransparency(body, math.max(originalBodyTransparency, 0.58), SPARK_SOUL_DISSOLVE_DURATION)

	tweenSparkPartTransparency(sparkWingL, math.max(originalWingLTransparency, 0.58), SPARK_SOUL_DISSOLVE_DURATION)

	tweenSparkPartTransparency(sparkWingR, math.max(originalWingRTransparency, 0.58), SPARK_SOUL_DISSOLVE_DURATION)

	tweenSparkPointLight(SPARK_DULL_WING_COLOR, math.max(originalBrightness * 1.15, 1.5), SPARK_SOUL_DISSOLVE_DURATION)

	task.wait(SPARK_SOUL_DISSOLVE_DURATION)

	-----------------------------------------------------
	-- BURST APART
	-----------------------------------------------------

	-- USER PARTICLE POP SEQUENCE:
	-- little spark -> broken ring -> circle -> explode
	if sparkSoulAmbientEmitter then
		sparkSoulAmbientEmitter:Emit(8)
	end

	if sparkSoulRingEmitter then
		sparkSoulRingEmitter:Emit(3)
	end

	if sparkSoulReformEmitter then
		sparkSoulReformEmitter:Emit(10)
	end

	task.delay(0.045, function()
		if sparkSoulBurstEmitter then
			sparkSoulBurstEmitter:Emit(SPARK_SOUL_BURST_COUNT)
		end
	end)

	tweenSparkPartTransparency(body, 1, SPARK_SOUL_VANISH_DURATION)

	tweenSparkPartTransparency(sparkWingL, 1, SPARK_SOUL_VANISH_DURATION)

	tweenSparkPartTransparency(sparkWingR, 1, SPARK_SOUL_VANISH_DURATION)

	tweenSparkPointLight(body.Color, 0, SPARK_SOUL_VANISH_DURATION)

	task.wait(SPARK_SOUL_VANISH_DURATION + SPARK_SOUL_INVISIBLE_HOLD)

	-----------------------------------------------------
	-- REFORM FROM THE CLOUD
	-----------------------------------------------------

	body.Material = Enum.Material.ForceField

	TweenService
		:Create(body, TweenInfo.new(SPARK_SOUL_REFORM_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Color = bodyColorBeforeBurst,
		})
		:Play()

	if leftWingColorBeforeBurst and leftWingStrengthBeforeBurst and sparkWingLSurfaceAppearance then
		TweenService:Create(
			sparkWingLSurfaceAppearance,
			TweenInfo.new(SPARK_SOUL_REFORM_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{
				Color = leftWingSurfaceColorBeforeBurst or leftWingColorBeforeBurst,

				EmissiveTint = leftWingColorBeforeBurst,

				EmissiveStrength = leftWingStrengthBeforeBurst,
			}
		):Play()
	end

	if rightWingColorBeforeBurst and rightWingStrengthBeforeBurst and sparkWingRSurfaceAppearance then
		TweenService:Create(
			sparkWingRSurfaceAppearance,
			TweenInfo.new(SPARK_SOUL_REFORM_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{
				Color = rightWingSurfaceColorBeforeBurst or rightWingColorBeforeBurst,

				EmissiveTint = rightWingColorBeforeBurst,

				EmissiveStrength = rightWingStrengthBeforeBurst,
			}
		):Play()
	end

	body.Transparency = math.max(originalBodyTransparency, 0.92)

	if sparkWingL then
		sparkWingL.Transparency = math.max(originalWingLTransparency, 0.92)
	end

	if sparkWingR then
		sparkWingR.Transparency = math.max(originalWingRTransparency, 0.92)
	end

	-- REVERSED REFORM SEQUENCE:
	-- explode residue -> circle -> broken ring -> little spark
	if sparkSoulBurstEmitter then
		sparkSoulBurstEmitter:Emit(12)
	end

	task.delay(0.035, function()
		if sparkSoulReformEmitter then
			sparkSoulReformEmitter:Emit(SPARK_SOUL_REFORM_COUNT)
		end
	end)

	task.delay(0.075, function()
		if sparkSoulRingEmitter then
			sparkSoulRingEmitter:Emit(2)
		end
	end)

	task.delay(0.10, function()
		if sparkSoulAmbientEmitter then
			sparkSoulAmbientEmitter:Emit(12)
		end
	end)

	tweenSparkPartTransparency(body, originalBodyTransparency, SPARK_SOUL_REFORM_DURATION)

	tweenSparkPartTransparency(sparkWingL, originalWingLTransparency, SPARK_SOUL_REFORM_DURATION)

	tweenSparkPartTransparency(sparkWingR, originalWingRTransparency, SPARK_SOUL_REFORM_DURATION)

	tweenSparkPointLight(bodyColorBeforeBurst, math.max(originalBrightness * 3, 4), SPARK_SOUL_REFORM_DURATION * 0.55)

	task.wait(SPARK_SOUL_REFORM_DURATION)

	updateSparkSoulVFXColor()

	-----------------------------------------------------
	-- SETTLE BACK INTO SPARK
	-----------------------------------------------------

	if sparkOriginalBodyMaterial then
		body.Material = sparkOriginalBodyMaterial
	end

	tweenSparkPointLight(body.Color, originalBrightness, SPARK_SOUL_SETTLE_DURATION)

	if sparkSoulAmbientEmitter then
		sparkSoulAmbientEmitter.Rate = SPARK_SOUL_AMBIENT_RATE
	end

	task.wait(SPARK_SOUL_SETTLE_DURATION)

	sparkSoulBurstInProgress = false
end

---------------------------------------------------------
-- RESTORE SPARK APPEARANCE
---------------------------------------------------------

local function restoreSparkAppearance(duration: number)
	if sparkOriginalBodyColor then
		tweenSparkBodyColor(sparkOriginalBodyColor, duration)
	end

	local leftSurface: SurfaceAppearance? = sparkWingLSurfaceAppearance

	local rightSurface: SurfaceAppearance? = sparkWingRSurfaceAppearance

	if leftSurface and sparkOriginalWingLEmissiveTint and sparkOriginalWingLEmissiveStrength then
		TweenService:Create(leftSurface, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Color = sparkOriginalWingLColor or sparkOriginalWingLEmissiveTint,

			EmissiveTint = sparkOriginalWingLEmissiveTint,

			EmissiveStrength = sparkOriginalWingLEmissiveStrength,
		}):Play()
	end

	if rightSurface and sparkOriginalWingREmissiveTint and sparkOriginalWingREmissiveStrength then
		TweenService:Create(rightSurface, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Color = sparkOriginalWingRColor or sparkOriginalWingREmissiveTint,

			EmissiveTint = sparkOriginalWingREmissiveTint,

			EmissiveStrength = sparkOriginalWingREmissiveStrength,
		}):Play()
	end

	local pointLight: PointLight? = sparkPointLight

	if pointLight and sparkOriginalPointLightColor and sparkOriginalPointLightBrightness then
		TweenService:Create(pointLight, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Color = sparkOriginalPointLightColor,

			Brightness = sparkOriginalPointLightBrightness,
		}):Play()
	end

	local body: BasePart? = sparkBody

	if body and sparkOriginalBodyTransparency ~= nil then
		tweenSparkPartTransparency(body, sparkOriginalBodyTransparency, duration)
	end

	if sparkWingL and sparkOriginalWingLTransparency ~= nil then
		tweenSparkPartTransparency(sparkWingL, sparkOriginalWingLTransparency, duration)
	end

	if sparkWingR and sparkOriginalWingRTransparency ~= nil then
		tweenSparkPartTransparency(sparkWingR, sparkOriginalWingRTransparency, duration)
	end

	if body and sparkOriginalBodyMaterial then
		body.Material = sparkOriginalBodyMaterial
	end
end

---------------------------------------------------------
-- CREATE SPARK
---------------------------------------------------------

local function waitForIntroChild(parent: Instance, childName: string, stageName: string): Instance
	localPlayer:SetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE, stageName)

	local existingChild: Instance? = parent:FindFirstChild(childName)

	if existingChild then
		return existingChild
	end

	task.delay(10, function()
		if not parent:FindFirstChild(childName) then
			warn(
				string.format(
					"[Spark Intro]: Still waiting for %s.%s while in stage %s.",
					parent:GetFullName(),
					childName,
					stageName
				)
			)
		end
	end)

	return parent:WaitForChild(childName)
end

local function getCinematicSparkTemplate(): Model
	local introTemplate: Instance? = ReplicatedFirst:FindFirstChild(SPARK_INTRO_TEMPLATE_NAME)
	if introTemplate and introTemplate:IsA("Model") then
		localPlayer:SetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE, "UsingReplicatedFirst.SparkIntroTemplate")
		return introTemplate
	end

	-- Use the established hierarchy from the original working intro.
	localPlayer:SetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE, "WaitingForReplicatedStorage.Spark")
	local models: Instance = waitForIntroChild(ReplicatedStorage, "Models", "WaitingForReplicatedStorage.Models")
	local npcs: Instance = waitForIntroChild(models, "NPCs", "WaitingForModels.NPCs")
	local sparkModels: Instance = waitForIntroChild(npcs, "SparkModels", "WaitingForNPCs.SparkModels")
	local sparkTemplate: Instance =
		waitForIntroChild(sparkModels, SPARK_GAMEPLAY_TEMPLATE_NAME, "WaitingForSparkModels.Spark")
	assert(sparkTemplate:IsA("Model"), "ReplicatedStorage.Models.NPCs.SparkModels.Spark must be a Model")
	return sparkTemplate
end

local function createCinematicSpark()
	local sparkTemplate: Model = getCinematicSparkTemplate()

	localPlayer:SetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE, "CreatingCinematicSpark")

	local existingSpark: Instance? = workspace:FindFirstChild(SPARK_CINEMATIC_NAME)

	if existingSpark then
		existingSpark:Destroy()
	end

	local sparkClone: Model = sparkTemplate:Clone()

	sparkClone.Name = SPARK_CINEMATIC_NAME

	sparkClone:SetAttribute("ReadyForCameraTransition", false)

	-----------------------------------------------------
	-- PART REFERENCES
	-----------------------------------------------------

	sparkBody = sparkClone:FindFirstChild("SparkBody") :: BasePart?

	sparkWingL = sparkClone:FindFirstChild("SparkWingL") :: BasePart?

	sparkWingR = sparkClone:FindFirstChild("SparkWingR") :: BasePart?

	if sparkWingL then
		sparkWingLSurfaceAppearance = sparkWingL:FindFirstChildWhichIsA("SurfaceAppearance")
	end

	if sparkWingR then
		sparkWingRSurfaceAppearance = sparkWingR:FindFirstChildWhichIsA("SurfaceAppearance")
	end

	if sparkBody then
		sparkPointLight = sparkBody:FindFirstChildWhichIsA("PointLight")
	end

	-----------------------------------------------------
	-- SAVE ORIGINAL APPEARANCE
	-----------------------------------------------------

	sparkOriginalModelScale = sparkClone:GetScale()

	if sparkBody then
		sparkOriginalBodyColor = sparkBody.Color

		sparkOriginalBodyMaterial = sparkBody.Material

		sparkOriginalBodyTransparency = sparkBody.Transparency
	end

	if sparkWingL then
		sparkOriginalWingLTransparency = sparkWingL.Transparency
	end

	if sparkWingR then
		sparkOriginalWingRTransparency = sparkWingR.Transparency
	end

	if sparkWingLSurfaceAppearance then
		sparkOriginalWingLColor = sparkWingLSurfaceAppearance.Color

		sparkOriginalWingLEmissiveTint = sparkWingLSurfaceAppearance.EmissiveTint

		sparkOriginalWingLEmissiveStrength = sparkWingLSurfaceAppearance.EmissiveStrength
	end

	if sparkWingRSurfaceAppearance then
		sparkOriginalWingRColor = sparkWingRSurfaceAppearance.Color

		sparkOriginalWingREmissiveTint = sparkWingRSurfaceAppearance.EmissiveTint

		sparkOriginalWingREmissiveStrength = sparkWingRSurfaceAppearance.EmissiveStrength
	end

	if sparkPointLight then
		sparkOriginalPointLightColor = sparkPointLight.Color

		sparkOriginalPointLightBrightness = sparkPointLight.Brightness
	end

	-----------------------------------------------------
	-- SELECT THIS INTRO'S COLOR PAIR
	-----------------------------------------------------

	selectSparkIntroColorSeed(sparkClone)

	-- Start the cinematic already wearing the seeded NORMAL variant.
	sparkVisualColorValue.Value = sparkIntroNormalBodyColor

	if sparkBody then
		sparkBody.Color = sparkIntroNormalBodyColor
	end

	if sparkWingLSurfaceAppearance then
		sparkWingLSurfaceAppearance.Color = sparkIntroNormalWingColor

		sparkWingLSurfaceAppearance.EmissiveTint = sparkIntroNormalWingColor
	end

	if sparkWingRSurfaceAppearance then
		sparkWingRSurfaceAppearance.Color = sparkIntroNormalWingColor

		sparkWingRSurfaceAppearance.EmissiveTint = sparkIntroNormalWingColor
	end

	if sparkPointLight then
		sparkPointLight.Color = sparkIntroNormalWingColor
	end

	-----------------------------------------------------
	-- PHYSICS
	-----------------------------------------------------

	local sparkRoot: BasePart? = sparkClone.PrimaryPart

	if not sparkRoot then
		sparkRoot = sparkClone:FindFirstChild("RootPart", true) :: BasePart?
	end

	if not sparkRoot then
		sparkRoot = sparkClone:FindFirstChildWhichIsA("BasePart", true)
	end

	for _, descendant: Instance in sparkClone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end

	if sparkRoot then
		sparkRoot.Anchored = true
	end

	sparkClone.Parent = workspace

	localPlayer:SetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE, "CinematicSparkCreated")

	cinematicSpark = sparkClone
	sparkLastTrailWorldPosition = nil

	-----------------------------------------------------
	-- SIGNATURE SOUL BODY VFX
	-----------------------------------------------------

	if sparkBody then
		local soulAttachment = Instance.new("Attachment")

		soulAttachment.Name = "SparkSoulVFXAttachment"

		soulAttachment.Parent = sparkBody

		sparkSoulAttachment = soulAttachment

		-------------------------------------------------
		-- AMBIENT INTERNAL SOUL MOTES
		-------------------------------------------------

		local ambientEmitter = Instance.new("ParticleEmitter")

		ambientEmitter.Name = "SparkSoulMotes"

		ambientEmitter.Texture = SPARK_SOUL_AMBIENT_TEXTURE

		ambientEmitter.Color = ColorSequence.new(sparkBody.Color)

		ambientEmitter.LightEmission = 1
		ambientEmitter.LightInfluence = 0

		ambientEmitter.Lifetime = NumberRange.new(0.70, 1.25)

		ambientEmitter.Rate = SPARK_SOUL_AMBIENT_RATE

		ambientEmitter.Speed = NumberRange.new(0.12, 0.42)

		ambientEmitter.SpreadAngle = Vector2.new(180, 180)

		ambientEmitter.Shape = Enum.ParticleEmitterShape.Sphere

		ambientEmitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume

		ambientEmitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward

		ambientEmitter.Rotation = NumberRange.new(0, 360)

		ambientEmitter.RotSpeed = NumberRange.new(-70, 70)

		ambientEmitter.Drag = 2.5
		ambientEmitter.LockedToPart = true

		ambientEmitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.34),

			NumberSequenceKeypoint.new(0.55, 0.22),

			NumberSequenceKeypoint.new(1, 0.08),
		})

		ambientEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.06),

			NumberSequenceKeypoint.new(0.65, 0.26),

			NumberSequenceKeypoint.new(1, 1),
		})

		ambientEmitter.Parent = soulAttachment

		sparkSoulAmbientEmitter = ambientEmitter

		-------------------------------------------------
		-- OUTWARD SOUL BURST
		-------------------------------------------------

		local burstEmitter = Instance.new("ParticleEmitter")

		burstEmitter.Name = "SparkSoulBurst"

		burstEmitter.Texture = SPARK_SOUL_EXPLODE_TEXTURE

		burstEmitter.Color = ColorSequence.new(sparkBody.Color)

		burstEmitter.LightEmission = 1
		burstEmitter.LightInfluence = 0
		burstEmitter.Enabled = false

		burstEmitter.Lifetime = NumberRange.new(0.28, 0.52)

		burstEmitter.Speed = NumberRange.new(5, 11)

		burstEmitter.SpreadAngle = Vector2.new(180, 180)

		burstEmitter.Shape = Enum.ParticleEmitterShape.Sphere

		burstEmitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume

		burstEmitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward

		burstEmitter.Rotation = NumberRange.new(0, 360)

		burstEmitter.RotSpeed = NumberRange.new(-140, 140)

		burstEmitter.Drag = 5

		burstEmitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.52),

			NumberSequenceKeypoint.new(0.38, 0.34),

			NumberSequenceKeypoint.new(1, 0.08),
		})

		burstEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),

			NumberSequenceKeypoint.new(0.55, 0.30),

			NumberSequenceKeypoint.new(1, 1),
		})

		burstEmitter.Parent = soulAttachment

		sparkSoulBurstEmitter = burstEmitter

		-------------------------------------------------
		-- REFORMATION CLOUD
		-------------------------------------------------

		local reformEmitter = Instance.new("ParticleEmitter")

		reformEmitter.Name = "SparkSoulReform"

		reformEmitter.Texture = SPARK_SOUL_CIRCLE_TEXTURE

		reformEmitter.Color = ColorSequence.new(sparkBody.Color)

		reformEmitter.LightEmission = 1
		reformEmitter.LightInfluence = 0
		reformEmitter.Enabled = false

		reformEmitter.Lifetime = NumberRange.new(0.22, 0.42)

		reformEmitter.Speed = NumberRange.new(1.0, 3.4)

		reformEmitter.SpreadAngle = Vector2.new(180, 180)

		reformEmitter.Shape = Enum.ParticleEmitterShape.Sphere

		reformEmitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume

		reformEmitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward

		reformEmitter.Rotation = NumberRange.new(0, 360)

		reformEmitter.RotSpeed = NumberRange.new(-100, 100)

		reformEmitter.Drag = 8
		reformEmitter.LockedToPart = true

		reformEmitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.42),

			NumberSequenceKeypoint.new(0.65, 0.26),

			NumberSequenceKeypoint.new(1, 0.08),
		})

		reformEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.10),

			NumberSequenceKeypoint.new(0.72, 0.38),

			NumberSequenceKeypoint.new(1, 1),
		})

		reformEmitter.Parent = soulAttachment

		sparkSoulReformEmitter = reformEmitter

		-------------------------------------------------
		-- BROKEN RING / POP ACCENT
		-------------------------------------------------

		local ringEmitter = Instance.new("ParticleEmitter")

		ringEmitter.Name = "SparkSoulRingPop"

		ringEmitter.Texture = SPARK_SOUL_RING_TEXTURE

		ringEmitter.Color = ColorSequence.new(sparkBody.Color)

		ringEmitter.LightEmission = 1
		ringEmitter.LightInfluence = 0
		ringEmitter.Enabled = false

		ringEmitter.Lifetime = NumberRange.new(0.16, 0.30)

		ringEmitter.Speed = NumberRange.new(0.4, 1.8)

		ringEmitter.SpreadAngle = Vector2.new(24, 24)

		ringEmitter.Rotation = NumberRange.new(0, 360)

		ringEmitter.RotSpeed = NumberRange.new(-80, 80)

		ringEmitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.36),

			NumberSequenceKeypoint.new(0.45, 0.95),

			NumberSequenceKeypoint.new(1, 1.55),
		})

		ringEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.03),

			NumberSequenceKeypoint.new(0.65, 0.26),

			NumberSequenceKeypoint.new(1, 1),
		})

		ringEmitter.Parent = soulAttachment

		sparkSoulRingEmitter = ringEmitter

		-------------------------------------------------
		-- SIGNATURE CENTERED TRAIL
		-------------------------------------------------

		local trailHalfWidth: number = math.max(sparkBody.Size.X * 0.12, 0.025)

		local trailLeft = Instance.new("Attachment")

		trailLeft.Name = "CinematicSparkTrailLeft"

		trailLeft.Position = Vector3.new(-trailHalfWidth, 0, 0)

		trailLeft.Parent = sparkBody

		local trailRight = Instance.new("Attachment")

		trailRight.Name = "CinematicSparkTrailRight"

		trailRight.Position = Vector3.new(trailHalfWidth, 0, 0)

		trailRight.Parent = sparkBody

		local trail = Instance.new("Trail")

		trail.Name = "CinematicSparkTrail"

		trail.Attachment0 = trailLeft

		trail.Attachment1 = trailRight

		trail.Color = ColorSequence.new(sparkBody.Color)

		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08),

			NumberSequenceKeypoint.new(0.35, 0.35),

			NumberSequenceKeypoint.new(1, 1),
		})

		trail.Lifetime = SPARK_CINEMATIC_TRAIL_LIFETIME

		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.FaceCamera = true
		trail.MinLength = 0.02
		trail.Enabled = false

		trail.Parent = sparkBody

		cinematicSparkTrail = trail

		if sparkVisualColorConnection then
			sparkVisualColorConnection:Disconnect()
		end

		sparkVisualColorConnection = sparkVisualColorValue:GetPropertyChangedSignal("Value"):Connect(function()
			if sparkBody then
				sparkBody.Color = sparkVisualColorValue.Value
			end

			updateSparkSoulVFXColor(sparkVisualColorValue.Value)
		end)

		updateSparkSoulVFXColor(sparkVisualColorValue.Value)
	end

	-----------------------------------------------------
	-- FLIGHT ANIMATION
	-----------------------------------------------------

	local animationController = sparkClone:FindFirstChildWhichIsA("AnimationController", true)

	if not animationController then
		animationController = Instance.new("AnimationController")

		animationController.Name = "CinematicAnimationController"

		animationController.Parent = sparkClone
	end

	local animator = animationController:FindFirstChildWhichIsA("Animator")

	if not animator then
		animator = Instance.new("Animator")

		animator.Parent = animationController
	end

	local flightAnimation = Instance.new("Animation")

	flightAnimation.AnimationId = SPARK_FLIGHT_ANIMATION_ID

	local flightTrack: AnimationTrack = animator:LoadAnimation(flightAnimation)

	flightTrack.Looped = true
	flightTrack.Priority = Enum.AnimationPriority.Action

	flightTrack:Play()

	cinematicSparkFlightTrack = flightTrack

	flightAnimation:Destroy()

	-----------------------------------------------------
	-- START SCALE
	-----------------------------------------------------

	sparkClone:ScaleTo(sparkOriginalModelScale * SPARK_START_SCALE)

	sparkScaleValue:GetPropertyChangedSignal("Value"):Connect(function()
		if sparkClone.Parent then
			sparkClone:ScaleTo(sparkOriginalModelScale * sparkScaleValue.Value)
		end
	end)
end

---------------------------------------------------------
-- UPDATE CAMERA
---------------------------------------------------------

local function updateLoadingCamera()
	local camera = workspace.CurrentCamera :: Camera?

	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	camera.CFrame = CFrame.lookAt(LOADING_CAMERA_POSITION, LOADING_CAMERA_POSITION + Vector3.new(0, 1, 0))
end

---------------------------------------------------------
-- UPDATE SPARK
---------------------------------------------------------

local function updateLoadingSpark(deltaTime: number)
	local camera = workspace.CurrentCamera :: Camera?

	local spark: Model? = cinematicSpark

	if not camera or not spark or not spark.Parent then
		return
	end

	local sparkPosition: Vector3 = camera.CFrame.Position
		+ (camera.CFrame.LookVector * sparkDistanceValue.Value)
		+ (camera.CFrame.RightVector * sparkHorizontalOffsetValue.Value)

	local sparkCFrame: CFrame = CFrame.lookAt(sparkPosition, camera.CFrame.Position)
		* CFrame.Angles(0, 0, math.rad(45 + sparkBankValue.Value))

	spark:PivotTo(sparkCFrame)

	-----------------------------------------------------
	-- SIGNATURE TRAIL ONLY WHILE ACTUALLY MOVING
	-----------------------------------------------------

	if cinematicSparkTrail then
		local previousPosition: Vector3? = sparkLastTrailWorldPosition

		sparkLastTrailWorldPosition = sparkPosition

		local movementSpeed: number = 0

		if previousPosition and deltaTime > 0 then
			movementSpeed = (sparkPosition - previousPosition).Magnitude / deltaTime
		end

		cinematicSparkTrail.Enabled = not sparkSoulBurstInProgress
			and movementSpeed >= SPARK_CINEMATIC_TRAIL_START_SPEED
	end
end

---------------------------------------------------------
-- INITIAL SPARK CINEMATIC
---------------------------------------------------------

local function playInitialSparkCinematic()
	task.wait(SPARK_OPENING_HOLD)

	-----------------------------------------------------
	-- LEFT -> CENTER
	--
	-- Spark accelerates toward camera.
	-----------------------------------------------------

	if cinematicSparkFlightTrack then
		cinematicSparkFlightTrack:AdjustSpeed(1.6)
	end

	tweenSparkBodyColor(sparkIntroNormalBodyColor, SPARK_LEFT_TO_CENTER_DURATION)

	tweenSparkWingAppearance(sparkIntroNormalWingColor, SPARK_CLOSE_EMISSIVE_STRENGTH, SPARK_LEFT_TO_CENTER_DURATION)

	local originalBrightness: number = sparkOriginalPointLightBrightness or 1

	tweenSparkPointLight(
		sparkIntroNormalWingColor,
		math.max(originalBrightness * 2.5, 3),
		SPARK_LEFT_TO_CENTER_DURATION
	)

	tweenNumber(
		sparkDistanceValue,
		SPARK_CLOSE_DISTANCE,
		SPARK_LEFT_TO_CENTER_DURATION,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	)

	tweenNumber(
		sparkScaleValue,
		SPARK_CLOSE_SCALE,
		SPARK_LEFT_TO_CENTER_DURATION,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	)

	tweenNumber(sparkBankValue, 0, SPARK_LEFT_TO_CENTER_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	local centerTween: Tween = tweenNumber(
		sparkHorizontalOffsetValue,
		SPARK_CENTER_HORIZONTAL_OFFSET,
		SPARK_LEFT_TO_CENTER_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	centerTween.Completed:Wait()

	-----------------------------------------------------
	-- CLOSE PASS FLASH
	-----------------------------------------------------

	if sparkBody then
		sparkBody.Material = Enum.Material.ForceField
	end

	tweenSparkBodyColor(sparkIntroForceFieldBodyColor, 0.10)

	tweenSparkWingAppearance(sparkIntroForceFieldWingColor, SPARK_CLOSE_EMISSIVE_STRENGTH, 0.10)

	task.wait(SPARK_FORCEFIELD_FLASH_DURATION)

	if sparkBody and sparkOriginalBodyMaterial then
		sparkBody.Material = sparkOriginalBodyMaterial
	end

	-----------------------------------------------------
	-- SIGNATURE SOUL BURST / REMATERIALISATION
	--
	-- Do this while Spark is still enormous and close to
	-- the camera. Immediately after reforming he tears off
	-- to the right with his signature trail.
	-----------------------------------------------------

	playSparkSoulMaterialisationBurst()

	-----------------------------------------------------
	-- CENTER -> RIGHT
	--
	-- Spark flies past the player.
	-----------------------------------------------------

	if cinematicSparkFlightTrack then
		cinematicSparkFlightTrack:AdjustSpeed(2.1)
	end

	tweenSparkBodyColor(sparkIntroNormalBodyColor, SPARK_CENTER_TO_RIGHT_DURATION)

	tweenSparkWingAppearance(sparkIntroNormalWingColor, SPARK_PASS_EMISSIVE_STRENGTH, SPARK_CENTER_TO_RIGHT_DURATION)

	tweenSparkPointLight(
		sparkIntroNormalWingColor,
		math.max(originalBrightness * 1.8, 2),
		SPARK_CENTER_TO_RIGHT_DURATION
	)

	tweenNumber(
		sparkScaleValue,
		SPARK_PASS_SCALE,
		SPARK_CENTER_TO_RIGHT_DURATION,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)

	tweenNumber(
		sparkDistanceValue,
		SPARK_RIGHT_DISTANCE,
		SPARK_CENTER_TO_RIGHT_DURATION,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)

	tweenNumber(sparkBankValue, 22, SPARK_CENTER_TO_RIGHT_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	local rightTween: Tween = tweenNumber(
		sparkHorizontalOffsetValue,
		SPARK_RIGHT_HORIZONTAL_OFFSET,
		SPARK_CENTER_TO_RIGHT_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	rightTween.Completed:Wait()

	-----------------------------------------------------
	-- RIGHT -> CENTER
	--
	-- Spark curves back into his handoff position.
	-----------------------------------------------------

	if cinematicSparkFlightTrack then
		cinematicSparkFlightTrack:AdjustSpeed(1)
	end

	if sparkBody and sparkOriginalBodyMaterial then
		sparkBody.Material = sparkOriginalBodyMaterial
	end

	tweenSparkBodyColor(sparkIntroNormalBodyColor, SPARK_RIGHT_TO_CENTER_DURATION)

	tweenSparkWingAppearance(sparkIntroNormalWingColor, SPARK_PASS_EMISSIVE_STRENGTH, SPARK_RIGHT_TO_CENTER_DURATION)

	local returnBrightness: number = sparkOriginalPointLightBrightness or 1

	tweenSparkPointLight(sparkIntroNormalWingColor, returnBrightness, SPARK_RIGHT_TO_CENTER_DURATION)

	tweenNumber(
		sparkScaleValue,
		SPARK_NORMAL_SCALE,
		SPARK_RIGHT_TO_CENTER_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	tweenNumber(
		sparkDistanceValue,
		SPARK_NORMAL_DISTANCE,
		SPARK_RIGHT_TO_CENTER_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	tweenNumber(sparkBankValue, 0, SPARK_RIGHT_TO_CENTER_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	local returnCenterTween: Tween = tweenNumber(
		sparkHorizontalOffsetValue,
		SPARK_CENTER_HORIZONTAL_OFFSET,
		SPARK_RIGHT_TO_CENTER_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	returnCenterTween.Completed:Wait()

	initialSparkCinematicFinished = true
end

---------------------------------------------------------
-- WAITING MOTION
---------------------------------------------------------

local function playSparkWaitingMotion()
	while not gameFinishedLoading and not preparingSparkForCameraModule do
		-- Waiting motion belongs to the NORMAL intro colour.
		tweenSparkBodyColor(sparkIntroNormalBodyColor, 0.30)

		local waitingBrightness: number = sparkOriginalPointLightBrightness or 1

		tweenSparkPointLight(sparkIntroNormalWingColor, waitingBrightness, 0.30)

		-------------------------------------------------
		-- CENTER -> LEFT
		-------------------------------------------------

		tweenSparkWingAppearance(sparkIntroNormalWingColor, SPARK_PASS_EMISSIVE_STRENGTH, 0.80)

		tweenNumber(sparkScaleValue, 1.25, 0.80, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

		tweenNumber(sparkBankValue, -10, 0.80, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

		local leftTween: Tween =
			tweenNumber(sparkHorizontalOffsetValue, -4, 0.80, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

		leftTween.Completed:Wait()

		if gameFinishedLoading then
			break
		end

		-------------------------------------------------
		-- LEFT -> RIGHT
		-------------------------------------------------

		tweenSparkWingAppearance(sparkIntroNormalWingColor, SPARK_PASS_EMISSIVE_STRENGTH, 1.10)

		tweenNumber(sparkScaleValue, 0.85, 1.10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

		tweenNumber(sparkBankValue, 10, 1.10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

		local rightTween: Tween =
			tweenNumber(sparkHorizontalOffsetValue, 4, 1.10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

		rightTween.Completed:Wait()
	end
end

---------------------------------------------------------
-- PREPARE FOR CAMERA MODULE
---------------------------------------------------------

local function prepareSparkForCameraModule()
	if preparingSparkForCameraModule then
		return
	end

	preparingSparkForCameraModule = true

	-----------------------------------------------------
	-- EXACT GAMEPLAY / HANDOFF SPARK STATE
	--
	-- IMPORTANT:
	-- Cinematic color seeds END here.
	-- Restore Spark's original model colours (green in the current
	-- gameplay model) before the next system takes ownership.
	-----------------------------------------------------

	if cinematicSparkFlightTrack then
		cinematicSparkFlightTrack:AdjustSpeed(1)
	end

	restoreSparkAppearance(SPARK_READY_DURATION)

	tweenNumber(
		sparkScaleValue,
		SPARK_NORMAL_SCALE,
		SPARK_READY_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	tweenNumber(
		sparkDistanceValue,
		SPARK_NORMAL_DISTANCE,
		SPARK_READY_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	tweenNumber(sparkBankValue, 0, SPARK_READY_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	local centerTween: Tween = tweenNumber(
		sparkHorizontalOffsetValue,
		SPARK_CENTER_HORIZONTAL_OFFSET,
		SPARK_READY_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	centerTween.Completed:Wait()

	-----------------------------------------------------
	-- GUARANTEE EXACT RESTORED VALUES
	-----------------------------------------------------

	local spark: Model? = cinematicSpark

	if spark then
		spark:ScaleTo(sparkOriginalModelScale)
	end

	if sparkBody and sparkOriginalBodyColor and sparkOriginalBodyMaterial then
		sparkVisualColorValue.Value = sparkOriginalBodyColor

		sparkBody.Color = sparkOriginalBodyColor

		sparkBody.Material = sparkOriginalBodyMaterial

		if sparkOriginalBodyTransparency ~= nil then
			sparkBody.Transparency = sparkOriginalBodyTransparency
		end
	end

	if sparkWingL and sparkOriginalWingLTransparency ~= nil then
		sparkWingL.Transparency = sparkOriginalWingLTransparency
	end

	if sparkWingR and sparkOriginalWingRTransparency ~= nil then
		sparkWingR.Transparency = sparkOriginalWingRTransparency
	end

	if sparkWingLSurfaceAppearance and sparkOriginalWingLEmissiveTint and sparkOriginalWingLEmissiveStrength then
		if sparkOriginalWingLColor then
			sparkWingLSurfaceAppearance.Color = sparkOriginalWingLColor
		end

		sparkWingLSurfaceAppearance.EmissiveTint = sparkOriginalWingLEmissiveTint

		sparkWingLSurfaceAppearance.EmissiveStrength = sparkOriginalWingLEmissiveStrength
	end

	if sparkWingRSurfaceAppearance and sparkOriginalWingREmissiveTint and sparkOriginalWingREmissiveStrength then
		if sparkOriginalWingRColor then
			sparkWingRSurfaceAppearance.Color = sparkOriginalWingRColor
		end

		sparkWingRSurfaceAppearance.EmissiveTint = sparkOriginalWingREmissiveTint

		sparkWingRSurfaceAppearance.EmissiveStrength = sparkOriginalWingREmissiveStrength
	end

	if sparkPointLight and sparkOriginalPointLightColor and sparkOriginalPointLightBrightness then
		sparkPointLight.Color = sparkOriginalPointLightColor

		sparkPointLight.Brightness = sparkOriginalPointLightBrightness
	end

	-----------------------------------------------------
	-- MODULE CAN NOW TAKE THIS SAME SPARK
	-----------------------------------------------------

	if spark and spark.Parent then
		spark:SetAttribute("ReadyForCameraTransition", true)

		localPlayer:SetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE, "ReadyForCameraTransition")

		localPlayer:SetAttribute(SPARK_INTRO_READY_ATTRIBUTE, true)
	end
end

---------------------------------------------------------
-- START CAMERA IMMEDIATELY
---------------------------------------------------------

RunService:BindToRenderStep(LOADING_CAMERA_BIND_NAME, Enum.RenderPriority.Camera.Value + 100, updateLoadingCamera)

localPlayer:SetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE, "LoadingCameraLocked")

---------------------------------------------------------
-- CREATE SPARK
---------------------------------------------------------

createCinematicSpark()
task.spawn(revealSparkFromLoadingScreen)

RunService:BindToRenderStep(LOADING_SPARK_BIND_NAME, Enum.RenderPriority.Camera.Value + 101, updateLoadingSpark)

---------------------------------------------------------
-- WATCH GAME LOAD
---------------------------------------------------------

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	gameFinishedLoading = true
end)

---------------------------------------------------------
-- PLAY CINEMATIC
---------------------------------------------------------

task.spawn(function()
	waitForLoadingScreenReady()
	localPlayer:SetAttribute(SPARK_INTRO_STAGE_ATTRIBUTE, "PlayingInitialSparkCinematic")

	playInitialSparkCinematic()

	-----------------------------------------------------
	-- IF ROBLOX IS STILL LOADING, KEEP SPARK ALIVE
	-----------------------------------------------------

	if not gameFinishedLoading then
		playSparkWaitingMotion()
	end

	-----------------------------------------------------
	-- GAME LOADED + INTRO PLAYED
	-- CENTER HIM FOR SPARKCAMERAMODULE
	-----------------------------------------------------

	while not gameFinishedLoading do
		RunService.Heartbeat:Wait()
	end

	while not initialSparkCinematicFinished do
		RunService.Heartbeat:Wait()
	end

	prepareSparkForCameraModule()
end)
