--!strict

local BoatConfig = {}

BoatConfig.Default = {
	ForwardAcceleration = 32,
	ReverseAcceleration = 14,
	MaxForwardSpeed = 42,
	MaxReverseSpeed = 16,
	TurnRate = math.rad(42),
	SideCatch = 2.4,
	ForwardDrag = 0.18,
	IdleDrag = 1.2,
	DriveResponse = 2.5, -- throttle response per second
	SteeringResponse = 3, -- yaw-rate response per second
	SteeringStrength = 1.2, -- maximum yaw acceleration, radians/s^2
	SteeringFullAuthoritySpeed = 12,
	MinimumSteeringAuthority = 0.08,
	WaterlineOffset = 0,
	VerticalResponse = 5,
	VerticalDamping = 4,
	RotationResponse = 4,
	MaxPitchDegrees = 12,
	MaxRollDegrees = 14,
	SpeedGainLimit = 48,
	MaxVerticalSpeed = 35,
	MaxHorizontalSpeed = 48,
	SampleOctaves = 6,
}

local function numberAttribute(boat: Model, name: string, fallback: number): number
	local value = boat:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

function BoatConfig.Resolve(boat: Model): { [string]: number }
	local config: { [string]: number } = table.clone(BoatConfig.Default)
	for key, fallback in pairs(BoatConfig.Default) do
		config[key] = numberAttribute(boat, key, fallback)
	end
	return config
end

return BoatConfig
