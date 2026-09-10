-- Controller integration checks with minimal services/joints, not a physics
-- or rendering emulator. Run with RunPlayerWaveMotionTests.ps1 and Luau CLI.
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			function connection:Disconnect() self.Connected = false end
			table.insert(callbacks, { connection, callback })
			return connection
		end,
		Fire = function(_, ...)
			for _, entry in callbacks do
				if entry[1].Connected then entry[2](...) end
			end
		end,
	}
end

local Vector3 = { yAxis = { X = 0, Y = 1, Z = 0 } }
local Color3 = { fromRGB = function(...) return {...} end }
local frames = {}
frames.__index = frames
local function frame(pitch, roll)
	local result = setmetatable({ Pitch = pitch or 0, Roll = roll or 0 }, frames)
	result.Rotation = result
	return result
end
function frames:Inverse() return frame(-self.Pitch, -self.Roll) end
function frames:VectorToObjectSpace(v) return v end
function frames.__mul(a, b) return frame(a.Pitch + b.Pitch, a.Roll + b.Roll) end
local CFrame = { Angles = function(pitch, _, roll) return frame(pitch, roll) end }
local Config = (function()
--[[CONFIG_SOURCE]]
end)()
local State = { Root = nil, SurfaceHold = false, Offset = 0 }
local count = 0
local sampleHeight = 100
local Sampler = {
	GetTime = function() return 10 end,
	Sample = function()
		count += 1
		return { Height = sampleHeight, Normal = { X = -0.6, Y = 0.1, Z = 0.6 } }
	end,
}
local RunService = { PreAnimation = signal(), PreSimulation = signal() }
local Enum = { Material = { Air = "Air" } }
local task = { spawn = function(fn, ...) fn(...) end }
local script = { Destroying = signal() }
local function object(class, properties)
	properties.Parent = true
	properties.IsA = function(_, name) return name == class end
	return properties
end
local function makeCharacter()
	local root = object("BasePart", { Position = { X = 0, Y = 6.9, Z = 0 }, CFrame = frame() })
	local humanoid = object("Humanoid", { Health = 100, FloorMaterial = "Air", Sit = false, PlatformStand = false })
	local motor = object("Motor6D", { Part0 = root, Part1 = { Name = "LowerTorso" }, C0 = frame(), Transform = frame() })
	local children = { Humanoid = humanoid, HumanoidRootPart = root }
	local character = {
		DescendantAdded = signal(),
		WaitForChild = function(_, name) return children[name] end,
		GetDescendants = function() return { root, humanoid, motor } end,
	}
	return character, root, humanoid, motor
end
local character, root, humanoid, motor = makeCharacter()
local player = {
	Character = character,
	CharacterAdded = signal(), CharacterRemoving = signal(),
	GetAttribute = function(self) return self.Enabled end,
}
local services = {
	Players = { LocalPlayer = player }, RunService = RunService,
	ReplicatedStorage = { WaitForChild = function() return { WaitForChild = function(_, name) return name end } end },
}
local game = { GetService = function(_, name) return services[name] end }
local required = { WaterConfig = Config, WaterWaveSampler = Sampler, PlayerWaveMotionState = State }
local require = function(name) return required[name] end
do
--[[CONTROLLER_SOURCE]]
end

local function step(dt)
	RunService.PreAnimation:Fire()
	RunService.PreSimulation:Fire(dt)
end
local function advance(seconds, hz)
	for _ = 1, seconds * hz do step(1 / hz) end
end
advance(1, 60)
assert(count == 0 and State.Offset == 0, "Dry/missing swimming state must do no sampling")
State.Root = root
State.SurfaceHold = true
for _, hz in { 30, 60, 144 } do
	count = 0
	State.Offset = 0
	for _ = 1, hz * 2 do
		local previous = State.Offset
		step(1 / hz)
		assert(math.abs(State.Offset) <= Config.PlayerWaveMotion.MaxHeight, "Bobbing exceeded height cap")
		assert(math.abs(State.Offset - previous) <= Config.PlayerWaveMotion.MaxOffsetSpeed / hz + 1e-9, "Offset changed too fast")
		assert(math.abs(motor.Transform.Pitch) <= math.rad(6) + 1e-9, "Pitch accumulated/exceeded cap")
		assert(math.abs(motor.Transform.Roll) <= math.rad(6) + 1e-9, "Roll accumulated/exceeded cap")
	end
	assert(count <= 61, "More than 30 samples per second")
	assert(State.Offset > 0.34, "Different frame rates must approach target height")
end
sampleHeight = -100
advance(3, 60)
assert(State.Offset < -0.34, "Trough should lower the floating band")
State.SurfaceHold = false
local previousCount = count
advance(3, 60)
assert(count == previousCount and State.Offset == 0, "Diving/jumping must stop sampling and fade bob")
State.SurfaceHold = true
humanoid.FloorMaterial = "Concrete"
advance(1, 60)
assert(count == previousCount, "Grounded characters must not sample")
humanoid.FloorMaterial = "Air"
humanoid.Sit = true
advance(1, 60)
assert(count == previousCount, "Seated characters must not sample")
humanoid.Sit = false
advance(1, 60)
player.Enabled = false
previousCount = count
advance(3, 60)
assert(count == previousCount and State.Offset == 0, "Disable attribute must fade out without sampling")
player.Enabled = true
advance(1, 60)
humanoid.Health = 0
step(1 / 60)
assert(State.Offset == 0, "Death must clear the offset")
player.CharacterRemoving:Fire()
character, root, humanoid, motor = makeCharacter()
player.Character = character
player.CharacterAdded:Fire(character)
State.Root = root
State.SurfaceHold = true
advance(1, 60)
assert(State.Offset < 0, "Respawn must resume sampling for the new root")
script.Destroying:Fire()
previousCount = count
advance(1, 60)
assert(State.Offset == 0 and count == previousCount, "Destroy must disconnect and restore offset")
assert(motor.Transform.Pitch == 0 and motor.Transform.Roll == 0, "Destroy must restore the joint")
print("Player wave motion: cadence, frame rates, caps, dry/seat/dive/disable, death, respawn, cleanup passed")
