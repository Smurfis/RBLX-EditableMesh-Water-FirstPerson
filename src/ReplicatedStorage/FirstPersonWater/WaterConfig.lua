--!strict

local WaterConfig = {
	Tags = {
		WaterBody = "WaterBody",
		WaterExclusion = "WaterExclusion",
	},

	Defaults = {
		Priority = 0,
		WaveScale = 1,
		WaveHeightScale = 1,
	},

	Renderer = {
		NearSpacing = 4,
		MidSpacing = 8,
		FarSpacing = 16,
		HorizonSpacing = 32,

		NearRadius = 160,
		MidRadius = 400,
		FarRadius = 800,
		HorizonRadius = 1400,

		PreloadHalfAngleDegrees = 72,
	},
}

return WaterConfig
