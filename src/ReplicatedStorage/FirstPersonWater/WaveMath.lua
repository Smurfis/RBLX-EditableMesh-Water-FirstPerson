--!native
--!strict

-- Shared deterministic world-space wave field.
-- Renderers, buoyancy and splash systems should sample the SAME function.

local WaveMath = {}

local MAX_OCTAVES = 14
local INITIAL_AMP = 2.8
local INITIAL_FREQ = 0.12
local INITIAL_SPEED = 1.5
local BASE_STEEPNESS = 1.2
local AMP_MULT = 0.82
local FREQ_MULT = 1.18
local SPEED_MULT = 1.07
local CHOPPINESS = 1.1

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

local amp = INITIAL_AMP
local freq = INITIAL_FREQ
local speed = INITIAL_SPEED

for i = 1, MAX_OCTAVES do
	local angle = rng:NextNumber(0, math.pi * 2)
	local dirX = math.cos(angle)
	local dirZ = math.sin(angle)

	waveKX[i] = dirX * freq
	waveKZ[i] = dirZ * freq
	waveSpeed[i] = speed
	wavePhase[i] = rng:NextNumber(0, math.pi * 2)
	waveAmp[i] = amp
	waveChopX[i] = CHOPPINESS * amp * dirX
	waveChopZ[i] = CHOPPINESS * amp * dirZ
	waveDerivX[i] = amp * dirX
	waveDerivZ[i] = amp * dirZ

	amp *= AMP_MULT
	freq *= FREQ_MULT
	speed *= SPEED_MULT
end

export type Sample = {
	Height: number,
	DisplacementX: number,
	DisplacementZ: number,
}

function WaveMath.Sample(
	worldX: number,
	worldZ: number,
	timeSeconds: number,
	octaveCount: number?,
	waveScale: number?,
	heightScale: number?
): Sample
	local count = math.clamp(octaveCount or MAX_OCTAVES, 1, MAX_OCTAVES)
	local scale = waveScale or 1
	local verticalScale = heightScale or 1

	local aY = 0
	local aDX = 0
	local aDZ = 0
	local aWX = 0
	local aWZ = 0

	for i = 1, count do
		local sx = (worldX + aWX) * scale
		local sz = (worldZ + aWZ) * scale
		local angle = sx * waveKX[i] + sz * waveKZ[i]
			+ timeSeconds * waveSpeed[i] + wavePhase[i]

		local sinAngle = math.sin(angle)
		local cosAngle = math.cos(angle)
		local sw = math.exp(BASE_STEEPNESS * (sinAngle - 1))

		aY += sw * waveAmp[i]
		aDX += waveChopX[i] * cosAngle
		aDZ += waveChopZ[i] * cosAngle

		local derivative = sw * BASE_STEEPNESS * cosAngle
		aWX += derivative * waveDerivX[i]
		aWZ += derivative * waveDerivZ[i]
	end

	return {
		Height = aY * verticalScale,
		DisplacementX = aDX * verticalScale,
		DisplacementZ = aDZ * verticalScale,
	}
end

return WaveMath
