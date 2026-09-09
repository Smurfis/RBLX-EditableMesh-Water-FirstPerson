--!native
--!strict

-- StarterPlayerScripts > UnderwaterVisualController
--
-- Responsibilities:
--   * Determine whether the CAMERA is below the configured water surface.
--   * Apply shallow -> deep underwater colour, blur, and darkness.
--   * Smoothly remove those effects when the camera exits the water.
--   * Swap between world ambience and underwater ambience.
--
-- It does NOT force first person.
-- It does NOT touch accessories/head/character visibility.
-- It does NOT control swimming.
-- It does NOT reference RealisticWater_Left / Right.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")


--==============================================================
-- AMBIENCE
--==============================================================

local WaterSounds =
	ReplicatedStorage
	:WaitForChild("Shared")
	:WaitForChild("Sounds")
	:WaitForChild("Water")


local WorldAmbienceTemplate =
	WaterSounds:WaitForChild("WorldAmbience") :: Sound

local UnderWaterAmbienceTemplate =
	WaterSounds:WaitForChild("UnderwaterAmbience") :: Sound


-- ReplicatedStorage sounds are templates only.
-- Make sure they themselves are not being used as live audio.
WorldAmbienceTemplate:Stop()
UnderWaterAmbienceTemplate:Stop()


-- Remove stale local ambience if this LocalScript was restarted in Studio.
local oldAmbienceFolder =
	SoundService:FindFirstChild("WaterAmbience_Local")

if oldAmbienceFolder then
	oldAmbienceFolder:Destroy()
end


local ambienceFolder =
	Instance.new("Folder")

ambienceFolder.Name =
	"WaterAmbience_Local"

ambienceFolder.Parent =
	SoundService


local WorldAmbience =
	WorldAmbienceTemplate:Clone()

WorldAmbience.Name =
	"WorldAmbience"

WorldAmbience.Looped =
	true

WorldAmbience.Parent =
	ambienceFolder


local UnderWaterAmbience =
	UnderWaterAmbienceTemplate:Clone()

UnderWaterAmbience.Name =
	"UnderwaterAmbience"

UnderWaterAmbience.Looped =
	true

UnderWaterAmbience.Parent =
	ambienceFolder


-- Remember the volumes configured on the original sounds.
local WORLD_AMBIENCE_VOLUME =
	WorldAmbience.Volume

local UNDERWATER_AMBIENCE_VOLUME =
	UnderWaterAmbience.Volume


local AMBIENCE_FADE_TIME =
	0.35


-- Start above water.
WorldAmbience.Volume =
	WORLD_AMBIENCE_VOLUME

UnderWaterAmbience.Volume =
	0


-- Both loops run continuously.
-- The state controller decides which one is audible.
WorldAmbience:Play()
UnderWaterAmbience:Play()


local ambienceTweens: { Tween } = {}


local function cancelAmbienceTweens()

	for _, tween in ambienceTweens do
		tween:Cancel()
	end

	table.clear(
		ambienceTweens
	)
end


local function tweenAmbience(
	sound: Sound,
	targetVolume: number
)

	local tween =
		TweenService:Create(
			sound,

			TweenInfo.new(
				AMBIENCE_FADE_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),

			{
				Volume = targetVolume,
			}
		)

	table.insert(
		ambienceTweens,
		tween
	)

	tween:Play()
end


local function setAmbienceState(
	isUnderwater: boolean
)

	cancelAmbienceTweens()


	-- Defensive recovery:
	-- if something stopped either sound, start it again.
	if not WorldAmbience.IsPlaying then
		WorldAmbience:Play()
	end

	if not UnderWaterAmbience.IsPlaying then
		UnderWaterAmbience:Play()
	end


	if isUnderwater then

		-- Fade surface/world ambience completely out.
		tweenAmbience(
			WorldAmbience,
			0
		)

		-- Fade underwater ambience in.
		tweenAmbience(
			UnderWaterAmbience,
			UNDERWATER_AMBIENCE_VOLUME
		)

	else

		-- Fade underwater ambience completely out.
		tweenAmbience(
			UnderWaterAmbience,
			0
		)

		-- Fade surface/world ambience back in.
		tweenAmbience(
			WorldAmbience,
			WORLD_AMBIENCE_VOLUME
		)
	end
end


--==============================================================
-- CONFIG
--==============================================================

local WaterConfig =
	require(
		ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Water")
		:WaitForChild("WaterConfig")
	)


local player =
	Players.LocalPlayer


local Settings =
	WaterConfig.Underwater


local RENDER_STEP_NAME =
	"UnderwaterVisualController"


local camera =
	Workspace.CurrentCamera


local underwater =
	false


local currentDepthAlpha =
	0


local activeTweens: { Tween } =
	{}


local function lerpNumber(
	a: number,
	b: number,
	alpha: number
): number

	return a + (b - a) * alpha
end


local function getSurfaceY(): number

	return WaterConfig.GetSurfaceY()
end


--==============================================================
-- EFFECT OBJECTS
--==============================================================

local colorCorrection =
	Instance.new("ColorCorrectionEffect")


colorCorrection.Name =
	"UnderwaterColorCorrection"


colorCorrection.TintColor =
	Color3.fromRGB(
		255,
		255,
		255
	)


colorCorrection.Brightness = 0
colorCorrection.Contrast = 0
colorCorrection.Saturation = 0


local blur =
	Instance.new("BlurEffect")


blur.Name =
	"UnderwaterBlur"


blur.Size =
	0


local playerGui =
	player:WaitForChild(
		"PlayerGui"
	)


-- Remove a duplicate if this script was restarted during Studio testing.
local oldGui =
	playerGui:FindFirstChild(
		"UnderwaterDarkness"
	)


if oldGui then
	oldGui:Destroy()
end


local darknessGui =
	Instance.new("ScreenGui")


darknessGui.Name =
	"UnderwaterDarkness"


darknessGui.IgnoreGuiInset =
	true


darknessGui.ResetOnSpawn =
	false


darknessGui.DisplayOrder =
	-100


darknessGui.Parent =
	playerGui


local darknessFrame =
	Instance.new("Frame")


darknessFrame.Name =
	"Darkness"


darknessFrame.Size =
	UDim2.fromScale(
		1,
		1
	)


darknessFrame.Position =
	UDim2.fromScale(
		0,
		0
	)


darknessFrame.BorderSizePixel =
	0


darknessFrame.BackgroundColor3 =
	Color3.new(
		0,
		0,
		0
	)


darknessFrame.BackgroundTransparency =
	1


darknessFrame.Parent =
	darknessGui


local function attachEffectsToCamera()

	camera =
		Workspace.CurrentCamera


	if not camera then
		return
	end


	colorCorrection.Parent =
		camera


	blur.Parent =
		camera
end


attachEffectsToCamera()


Workspace:GetPropertyChangedSignal(
	"CurrentCamera"
):Connect(
	attachEffectsToCamera
)


--==============================================================
-- TWEEN HELPERS
--==============================================================

local function cancelTweens()

	for _, tween in activeTweens do
		tween:Cancel()
	end


	table.clear(
		activeTweens
	)
end


local function makeTween(
	object: Instance,
	properties: { [string]: any }
)

	local tween =
		TweenService:Create(
			object,

			TweenInfo.new(
				Settings.ExitTransitionTime,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),

			properties
		)


	table.insert(
		activeTweens,
		tween
	)


	tween:Play()
end


--==============================================================
-- UNDERWATER STATE
--==============================================================

local function enterUnderwater()

	if underwater then
		return
	end


	underwater =
		true


	-- WORLD OFF
	-- UNDERWATER ON
	setAmbienceState(
		true
	)


	cancelTweens()


	local currentCamera =
		camera


	if currentCamera then

		local depth =
			math.max(
				0,

				getSurfaceY()
				- currentCamera.CFrame.Position.Y
			)


		currentDepthAlpha =
			math.clamp(
				depth
				/ Settings.FullDarkDepth,

				0,
				1
			)
	end
end


local function exitUnderwater()

	if not underwater then
		return
	end


	underwater =
		false


	-- UNDERWATER OFF
	-- WORLD ON
	setAmbienceState(
		false
	)


	currentDepthAlpha =
		0


	cancelTweens()


	makeTween(
		colorCorrection,

		{
			TintColor =
				Color3.fromRGB(
					255,
					255,
					255
				),

			Brightness = 0,

			Contrast = 0,

			Saturation = 0,
		}
	)


	makeTween(
		blur,

		{
			Size = 0,
		}
	)


	makeTween(
		darknessFrame,

		{
			BackgroundTransparency = 1,
		}
	)
end


--==============================================================
-- DEPTH VISUALS
--==============================================================

local function updateUnderwaterVisuals(
	dt: number
)

	local currentCamera =
		camera


	if
		not underwater
		or not currentCamera
	then
		return
	end


	local depth =
		math.max(
			0,

			getSurfaceY()
			- currentCamera.CFrame.Position.Y
		)


	local targetDepthAlpha =
		math.clamp(
			depth
			/ Settings.FullDarkDepth,

			0,
			1
		)


	local followAlpha =
		1
	- math.exp(
		-Settings.DepthVisualFollowSpeed
			* dt
	)


	currentDepthAlpha =
		lerpNumber(
			currentDepthAlpha,
			targetDepthAlpha,
			followAlpha
		)


	local darkness =
		currentDepthAlpha ^ 1.35


	colorCorrection.TintColor =
		Settings.ShallowTint:Lerp(
			Settings.DeepTint,
			darkness
		)


	colorCorrection.Brightness =
		lerpNumber(
			Settings.ShallowBrightness,
			Settings.DeepBrightness,
			darkness
		)


	colorCorrection.Contrast =
		lerpNumber(
			Settings.ShallowContrast,
			Settings.DeepContrast,
			darkness
		)


	colorCorrection.Saturation =
		lerpNumber(
			Settings.ShallowSaturation,
			Settings.DeepSaturation,
			darkness
		)


	blur.Size =
		lerpNumber(
			Settings.ShallowBlur,
			Settings.DeepBlur,
			darkness
		)


	local blackout =
		math.clamp(
			(currentDepthAlpha - 0.25)
			/ 0.75,

			0,
			1
		) ^ 1.6


	darknessFrame.BackgroundTransparency =
		1 - blackout
end


--==============================================================
-- CAMERA UPDATE
--==============================================================

RunService:BindToRenderStep(
	RENDER_STEP_NAME,

	Enum.RenderPriority.Camera.Value + 2,

	function(dt: number)

		camera =
			Workspace.CurrentCamera


		local currentCamera =
			camera


		if not currentCamera then
			return
		end


		local surfaceY =
			getSurfaceY()


		local cameraY =
			currentCamera.CFrame.Position.Y


		if not underwater then

			if
				cameraY
				< surfaceY
				- Settings.CameraEnterDepth
			then

				enterUnderwater()
			end

		else

			if
				cameraY
				> surfaceY
				+ Settings.CameraExitHeight
			then

				exitUnderwater()

				return
			end
		end


		if underwater then

			updateUnderwaterVisuals(
				dt
			)
		end
	end
)
