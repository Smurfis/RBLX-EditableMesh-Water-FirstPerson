--!strict

local WaterConfig = {}

-- Current test ocean
WaterConfig.RenderPlaneY = 0

-- Your old controller effectively used:
-- water.Position.Y + 6
--
-- Change this to 0 if the actual gameplay surface should be Y = 0.
WaterConfig.SurfaceOffset = 6


function WaterConfig.GetSurfaceY(): number
	return WaterConfig.RenderPlaneY + WaterConfig.SurfaceOffset
end


WaterConfig.Swimming = {
	EnterOffset = 1.161,
	ExitOffset = 1.161,

	Speed = 16,
	VerticalSpeed = 13,
	Acceleration = 8,

	-- Experimental HumanoidRootPart world-space surface boundaries.
	-- These are deliberately grouped here so the test can be tuned or
	-- removed without changing the swimming implementation again.
	SurfaceTest = {
		AssistStartY = 5.691,
		FloatMinY = 6.825,
		FloatTargetY = 6.9,
		FloatMaxY = 6.975,
		ExitY = 7.161,

		RestoreResponse = 6,
		MaxRestoreSpeed = 4,
		DescendInputThreshold = -0.1,
		-- Measured lower-CoastLine foot contact for the current shoreline test.
		-- Base surface Y=6 plus this offset gives Y=7.458.
		FootContactOffset = 1.458,
	},
}


-- Gentle player-only response. This deliberately filters small wave chop.
WaterConfig.PlayerWaveMotion = {
	Enabled = true,
	Octaves = 6,
	SampleHz = 30,
	HeightStrength = 0.3,
	MaxHeight = 0.35,
	MaxOffsetSpeed = 0.75,
	Response = 5,
	TiltStrength = 0.35,
	MaxTiltDegrees = 6,
}

WaterConfig.Underwater = {
	CameraEnterDepth = 0.15,
	CameraExitHeight = 0.30,

	FullDarkDepth = 20,
	DepthVisualFollowSpeed = 8,
	ExitTransitionTime = 0.25,

	ShallowTint = Color3.fromRGB(95, 175, 220),
	ShallowBrightness = -0.08,
	ShallowContrast = 0.05,
	ShallowSaturation = -0.10,
	ShallowBlur = 1,

	DeepTint = Color3.fromRGB(5, 15, 30),
	DeepBrightness = -1,
	DeepContrast = 0.45,
	DeepSaturation = -0.75,
	DeepBlur = 10,
	-- Prevent already-dark night lighting from making deep water unreadable.
	NightBrightnessLift = 0.35,
	NightBlackoutReduction = 0.45,
}


return WaterConfig
