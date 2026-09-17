-- Executes the real platform rider against a moving dynamic-boat fixture.
-- It verifies that dismount/parking movement cannot be replayed onto the
-- character and that ordinary parked wave carry starts from a fresh baseline.
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback) table.insert(callbacks, callback) end,
		Fire = function(_, ...) for _, callback in callbacks do callback(...) end end,
	}
end

local Vector3 = {}
local vectors = {}
vectors.__index = vectors
function vectors.__add(left, right) return Vector3.new(left.X + right.X, left.Y + right.Y, left.Z + right.Z) end
function vectors.__mul(left, right)
	if type(left) == "number" then left, right = right, left end
	return Vector3.new(left.X * right, left.Y * right, left.Z * right)
end
function Vector3.new(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vectors) end
Vector3.zero = Vector3.new(0, 0, 0)

local frames = {}
frames.__index = frames
local CFrame = {}
function CFrame.new(x, y, z)
	return setmetatable({
		Position = Vector3.new(x or 0, y or 0, z or 0),
		RightVector = Vector3.new(1, 0, 0),
		LookVector = Vector3.new(0, 0, -1),
	}, frames)
end
function frames:Inverse()
	return CFrame.new(-self.Position.X, -self.Position.Y, -self.Position.Z)
end
function frames.__mul(left, right)
	return CFrame.new(
		left.Position.X + right.Position.X,
		left.Position.Y + right.Position.Y,
		left.Position.Z + right.Position.Z
	)
end

local allInstances = {}
local function node(className, name, parent)
	local object = {
		ClassName = className,
		Name = name,
		Parent = parent,
		children = {},
		attributes = {},
		AncestryChanged = signal(),
	}
	if parent then table.insert(parent.children, object) end
	table.insert(allInstances, object)
	function object:IsA(wanted)
		return wanted == self.ClassName or (wanted == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart"))
	end
	function object:GetAttribute(key) return self.attributes[key] end
	function object:SetAttribute(key, value) self.attributes[key] = value end
	function object:FindFirstChild(wanted, recursive)
		for _, child in (if recursive then self:GetDescendants() else self.children) do
			if child.Name == wanted then return child end
		end
		return nil
	end
	function object:GetDescendants()
		local descendants = {}
		for _, child in self.children do
			table.insert(descendants, child)
			for _, descendant in child:GetDescendants() do table.insert(descendants, descendant) end
		end
		return descendants
	end
	function object:WaitForChild(wanted) return self:FindFirstChild(wanted) end
	return object
end

local storage = node("Folder", "ReplicatedStorage")
local modules = node("Folder", "Modules", storage)
local waveStateModule = node("ModuleScript", "PlayerWaveMotionState", modules)
local playerWaveState = { PlatformRiding = false }
local function require(module)
	assert(module == waveStateModule)
	return playerWaveState
end

local workspace = node("Workspace", "Workspace")
local boats = node("Folder", "Boats", workspace)
local boat = node("Model", "SmallBoat", boats)
boat.tagged = true
boat:SetAttribute("WaterProfile", "Boat")
boat:SetAttribute("WaterDynamicPhysics", true)
boat:SetAttribute("BoatPhysicsMode", "DYNAMIC_DRIVING")
boat:SetAttribute("BoatState", "Sailing")
local boatRoot = node("MeshPart", "BoatRoot", boat)
boatRoot.CFrame = CFrame.new(100, 8, 0)
boatRoot.Anchored = false
local deck = node("Part", "Deck", boat)
boat.PrimaryPart = deck -- BoatRoot must define dynamic-boat platform movement.

local character = node("Model", "Character", workspace)
local humanoid = node("Humanoid", "Humanoid", character)
humanoid.Health = 100
humanoid.Sit = false
humanoid.PlatformStand = false
humanoid.HipHeight = 2
local characterRoot = node("Part", "HumanoidRootPart", character)
characterRoot.CFrame = CFrame.new(0, 12, 0)
characterRoot.Position = characterRoot.CFrame.Position

local player = {
	Character = character,
	CharacterAdded = signal(),
	CharacterRemoving = signal(),
}
local renderStep
local services = {
	Players = { LocalPlayer = player },
	ReplicatedStorage = storage,
	RunService = { BindToRenderStep = function(_, _, _, callback) renderStep = callback end },
	CollectionService = { HasTag = function(_, instance) return instance.tagged == true end },
}
local game = { GetService = function(_, name) return services[name] end }
local Enum = {
	RenderPriority = { Camera = { Value = 200 } },
	RaycastFilterType = { Exclude = "Exclude" },
}
local RaycastParams = { new = function() return {} end }
function workspace:Raycast() return { Instance = deck } end
local task = { spawn = function(callback, ...) callback(...) end }

(function()
--[[PLATFORM_RIDER_SOURCE]]
end)()

local function assertCharacterPosition(x, y, message)
	assert(characterRoot.CFrame.Position.X == x and characterRoot.CFrame.Position.Y == y, message)
end

-- The rider must ignore all physical, handoff and recovery motion.
renderStep()
boatRoot.CFrame = CFrame.new(140, 24, 0)
renderStep()
assertCharacterPosition(0, 12, "dynamic sailing delta was applied to dismounted character")
boat:SetAttribute("BoatPhysicsMode", "PARKING")
boat:SetAttribute("BoatState", "Docked")
boatRoot.Anchored = true
boatRoot.CFrame = CFrame.new(180, 30, 0)
renderStep()
assertCharacterPosition(0, 12, "parking delta was applied to character")

-- Kinematic idle establishes a new sailed-to baseline. Only later wave motion
-- is carried, and the Model's deliberately wrong PrimaryPart is irrelevant.
boat:SetAttribute("BoatPhysicsMode", "KINEMATIC_IDLE")
boatRoot.CFrame = CFrame.new(200, 8, 0)
renderStep()
assertCharacterPosition(0, 12, "new parked baseline teleported character")
boatRoot.CFrame = CFrame.new(203, 9, 0)
renderStep()
assertCharacterPosition(3, 13, "parked BoatRoot wave delta was not carried")
assert(playerWaveState.PlatformRiding, "parked platform riding state was not published")

-- A later recovery/parking cycle must clear the old frame before resuming.
boat:SetAttribute("BoatPhysicsMode", "RECOVERING")
boatRoot.CFrame = CFrame.new(400, 40, 0)
renderStep()
assertCharacterPosition(3, 13, "recovery delta was applied to character")
boat:SetAttribute("BoatPhysicsMode", "KINEMATIC_IDLE")
boatRoot.CFrame = CFrame.new(500, 8, 0)
renderStep()
assertCharacterPosition(3, 13, "recovery-to-idle baseline replayed a stale delta")
boatRoot.CFrame = CFrame.new(502, 8.5, 0)
renderStep()
assertCharacterPosition(5, 13.5, "parked carry did not resume from fresh baseline")

print("PASS: dynamic/PARKING/RECOVERING boat deltas are blocked; KINEMATIC_IDLE BoatRoot carry starts from a fresh baseline")
