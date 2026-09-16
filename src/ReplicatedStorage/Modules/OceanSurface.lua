--!strict

-- Canonical custom-ocean surface query. Consumers may apply their own
-- swimmer, hull, or gameplay offsets after resolving this shared surface.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ReplicatedStorage:WaitForChild("Modules")
local WaterConfig = require(modules:WaitForChild("WaterConfig"))
local WaterWaveSampler = require(modules:WaitForChild("WaterWaveSampler"))

local OceanSurface = {}

function OceanSurface.GetTime(): number
	return WaterWaveSampler.GetTime()
end

function OceanSurface.Sample(worldPosition: Vector3, time: number?, octaveCount: number?)
	local waveSample = WaterWaveSampler.Sample(worldPosition.X, worldPosition.Z, time, octaveCount)
	local surfaceY = WaterConfig.GetSurfaceY() + waveSample.Height

	return {
		SurfaceY = surfaceY,
		Height = waveSample.Height,
		Normal = waveSample.Normal,
		Displacement = waveSample.Displacement,
		Position = Vector3.new(worldPosition.X, surfaceY, worldPosition.Z),
	}
end

return OceanSurface
