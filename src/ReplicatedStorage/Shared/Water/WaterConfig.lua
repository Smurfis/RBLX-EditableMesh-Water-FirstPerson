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
	EnterOffset = 1.5,
	ExitOffset = 2.0,

	Speed = 16,
	VerticalSpeed = 13,
	Acceleration = 8,
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
}


return WaterConfig
