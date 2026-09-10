--!strict

-- Shared source of truth for the stylized wave field used by the ocean and
-- client-side floating/deformable test objects.

local m_cos = math.cos
local m_sin = math.sin
local m_exp = math.exp
local m_pi = math.pi

export type WaveSample = {
	Height: number,
	Displacement: Vector3,
	Position: Vector3,
	Normal: Vector3,
}

local WaterWaveSampler = {}

local MAX_OCTAVES = 14
local INITIAL_AMP = 2.8
local INITIAL_FREQ = 0.12
local INITIAL_SPEED = 1.5
local BASE_STEEPNESS = 1.2
local SWELL_BASELINE = 0.4197820789351331
local AMP_MULT = 0.82
local FREQ_MULT = 1.18
local SPEED_MULT = 1.07
local CHOPPINESS = 1.1
local NORMAL_SAMPLE_DISTANCE = 0.25

local rng = Random.new(1337)
local waveKX = table.create(MAX_OCTAVES, 0)
local waveKZ = table.create(MAX_OCTAVES, 0)
local waveSpeed = table.create(MAX_OCTAVES, 0)
local wavePhase = table.create(MAX_OCTAVES, 0)
local waveAmp = table.create(MAX_OCTAVES, 0)
local waveChopX = table.create(MAX_OCTAVES, 0)
local waveChopZ = table.create(MAX_OCTAVES, 0)
local waveDerivX = table.create(MAX_OCTAVES, 0)
local waveDerivZ = table.create(MAX_OCTAVES, 0)
local cumulativeAmplitude = table.create(MAX_OCTAVES, 0)

local currentAmp = INITIAL_AMP
local currentFreq = INITIAL_FREQ
local currentSpeed = INITIAL_SPEED
local totalAmplitude = 0

for i = 1, MAX_OCTAVES do
	local angle = rng:NextNumber(0, m_pi * 2)
	local dirX = m_cos(angle)
	local dirZ = m_sin(angle)

	totalAmplitude += currentAmp
	waveKX[i] = dirX * currentFreq
	waveKZ[i] = dirZ * currentFreq
	waveSpeed[i] = currentSpeed
	wavePhase[i] = rng:NextNumber(0, m_pi * 2)
	waveAmp[i] = currentAmp
	waveChopX[i] = CHOPPINESS * currentAmp * dirX
	waveChopZ[i] = CHOPPINESS * currentAmp * dirZ
	waveDerivX[i] = currentAmp * dirX
	waveDerivZ[i] = currentAmp * dirZ
	cumulativeAmplitude[i] = totalAmplitude

	currentAmp *= AMP_MULT
	currentFreq *= FREQ_MULT
	currentSpeed *= SPEED_MULT
end

local moduleStartTime = os.clock()

function WaterWaveSampler.GetTime(): number
	return os.clock() - moduleStartTime
end

function WaterWaveSampler.GetMaxOctaves(): number
	return MAX_OCTAVES
end

function WaterWaveSampler.GetCumulativeAmplitude(octaveCount: number): number
	local count = math.clamp(math.floor(octaveCount), 1, MAX_OCTAVES)
	return cumulativeAmplitude[count]
end

local function sampleHeightDisplacement(
	worldX: number,
	worldZ: number,
	time: number,
	octaveCount: number
): (number, number, number)
	local waveY = 0
	local displacementX = 0
	local displacementZ = 0
	local warpedX = 0
	local warpedZ = 0

	for i = 1, octaveCount do
		local sampleX = worldX + warpedX
		local sampleZ = worldZ + warpedZ
		local angle = sampleX * waveKX[i] + sampleZ * waveKZ[i] + time * waveSpeed[i] + wavePhase[i]
		local sinAngle = m_sin(angle)
		local cosAngle = m_cos(angle)
		local swell = m_exp(BASE_STEEPNESS * (sinAngle - 1))

		waveY += (swell - SWELL_BASELINE) * waveAmp[i]
		displacementX += waveChopX[i] * cosAngle
		displacementZ += waveChopZ[i] * cosAngle

		local derivative = swell * BASE_STEEPNESS * cosAngle
		warpedX += derivative * waveDerivX[i]
		warpedZ += derivative * waveDerivZ[i]
	end

	return waveY, displacementX, displacementZ
end

function WaterWaveSampler.Sample(
	worldX: number,
	worldZ: number,
	time: number?,
	octaveCount: number?
): WaveSample
	local sampleTime = time or WaterWaveSampler.GetTime()
	local count = math.clamp(math.floor(octaveCount or MAX_OCTAVES), 1, MAX_OCTAVES)
	local height, displacementX, displacementZ = sampleHeightDisplacement(
		worldX,
		worldZ,
		sampleTime,
		count
	)

	local offset = NORMAL_SAMPLE_DISTANCE
	local heightX = sampleHeightDisplacement(worldX + offset, worldZ, sampleTime, count)
	local heightZ = sampleHeightDisplacement(worldX, worldZ + offset, sampleTime, count)
	local tangentX = Vector3.new(offset, heightX - height, 0)
	local tangentZ = Vector3.new(0, heightZ - height, offset)
	local normal = tangentZ:Cross(tangentX).Unit

	return {
		Height = height,
		Displacement = Vector3.new(displacementX, 0, displacementZ),
		Position = Vector3.new(worldX + displacementX, height, worldZ + displacementZ),
		Normal = normal,
	}
end

return WaterWaveSampler
