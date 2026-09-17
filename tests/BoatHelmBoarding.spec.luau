-- Runs the actual prompt module with mocked Roblox services. This covers the
-- server validation/locking contract, not Roblox's physical seat weld.
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			function connection:Disconnect() self.Connected = false end
			table.insert(callbacks, { callback, connection })
			return connection
		end,
		Fire = function(_, ...)
			for _, entry in callbacks do
				if entry[2].Connected then entry[1](...) end
			end
		end,
	}
end

local Vector3 = {}
local vectorMetatable = {}
vectorMetatable.__index = function(vector, key)
	if key == "Magnitude" then
		return math.sqrt(vector.X * vector.X + vector.Y * vector.Y + vector.Z * vector.Z)
	end
	return vectorMetatable[key]
end
function vectorMetatable.__sub(left, right)
	return Vector3.new(left.X - right.X, left.Y - right.Y, left.Z - right.Z)
end
function Vector3.new(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, vectorMetatable)
end

local CFrame = {}
function CFrame.new(x, y, z)
	return { Position = Vector3.new(x or 0, y or 0, z or 0), __cframe = true }
end

local function removeChild(parent, child)
	if not parent or not parent.children then return end
	for index, candidate in parent.children do
		if candidate == child then table.remove(parent.children, index); return end
	end
end

local function makeInstance(className, name, parent)
	local obj = {
		ClassName = className,
		Name = name,
		_parent = nil,
		children = {},
		attributes = {},
		__instance = true,
	}
	setmetatable(obj, {
		__index = function(self, key)
			if key == "Parent" then return rawget(self, "_parent") end
			return rawget(obj, key)
		end,
		__newindex = function(self, key, value)
			if key == "Parent" then
				local previous = rawget(self, "_parent")
				if previous == value then return end
				removeChild(previous, self)
				rawset(self, "_parent", value)
				if value and value.children then table.insert(value.children, self) end
			else
				rawset(self, key, value)
			end
		end,
	})
	function obj:IsA(wanted)
		local basePart = self.ClassName == "Part" or self.ClassName == "MeshPart" or self.ClassName == "VehicleSeat"
		return wanted == self.ClassName or (wanted == "BasePart" and basePart)
	end
	function obj:GetDescendants()
		local results = {}
		for _, child in self.children do
			table.insert(results, child)
			for _, descendant in child:GetDescendants() do table.insert(results, descendant) end
		end
		return results
	end
	function obj:FindFirstChild(wanted, recursive)
		for _, child in (if recursive then self:GetDescendants() else self.children) do
			if child.Name == wanted then return child end
		end
		return nil
	end
	function obj:FindFirstChildOfClass(wanted)
		for _, child in self.children do if child:IsA(wanted) then return child end end
		return nil
	end
	function obj:IsDescendantOf(ancestor)
		local cursor = self.Parent
		while cursor do
			if cursor == ancestor then return true end
			cursor = cursor.Parent
		end
		return false
	end
	function obj:GetAttribute(attribute) return self.attributes[attribute] end
	function obj:SetAttribute(attribute, value) self.attributes[attribute] = value end
	function obj:GetFullName() return self.Name end
	function obj:Destroy() self.Destroyed = true; self.Parent = nil end
	if className == "ProximityPrompt" then
		obj.Triggered = signal()
		obj.Enabled = true
		obj.MaxActivationDistance = 10
	end
	if parent then obj.Parent = parent end
	return obj
end

local Instance = {}
function Instance.new(className) return makeInstance(className, className, nil) end
local builtinTypeof = typeof
local function typeof(value)
	if type(value) == "table" and value.__instance then return "Instance" end
	if type(value) == "table" and value.__cframe then return "CFrame" end
	return builtinTypeof(value)
end

local delayed = {}
local task = {
	delay = function(_, callback) table.insert(delayed, callback) end,
}
local function runDelayed()
	local callbacks = delayed
	delayed = {}
	for _, callback in callbacks do callback() end
end
local Enum = {
	KeyCode = { E = "E", ButtonX = "ButtonX" },
	ProximityPromptStyle = { Default = "Default" },
	ProximityPromptExclusivity = { OnePerButton = "OnePerButton" },
}
local function print(...) end
local function warn(...) end

local players = makeInstance("Players", "Players", nil)
players.PlayerRemoving = signal()
function players:GetPlayerFromCharacter(character) return character.player end
local game = { GetService = function(_, name) assert(name == "Players"); return players end }
local authorityModule = makeInstance("ModuleScript", "BoatDynamicAuthority", nil)
local dismountCalls = {}
local BoatDynamicAuthority = {
	RequestDismount = function(boat, player, humanoid)
		table.insert(dismountCalls, { boat, player, humanoid })
		return true
	end,
}
local script = {
	Parent = {
		WaitForChild = function(_, name)
			assert(name == "BoatDynamicAuthority")
			return authorityModule
		end,
	},
}
local function require(module)
	assert(module == authorityModule)
	return BoatDynamicAuthority
end

local Boarding = (function()
--[[HELM_BOARDING_SOURCE]]
end)()

local function playerFixture(name, position)
	local player = makeInstance("Player", name, players)
	local character = makeInstance("Model", name .. "Character", nil)
	character.player = player
	player.Character = character
	local humanoid = makeInstance("Humanoid", "Humanoid", character)
	humanoid.Health = 100
	humanoid.SeatPart = nil
	local root = makeInstance("Part", "HumanoidRootPart", character)
	root.Position = position
	root.CFrame = CFrame.new(position.X, position.Y, position.Z)
	return player, humanoid, root
end

local function boatFixture(name, withAnchor)
	local boat = makeInstance("Model", name, makeInstance("Folder", name .. "Parent", nil))
	boat:SetAttribute("BoatPhysicsMode", "KINEMATIC_IDLE")
	boat:SetAttribute("BoatState", "Docked")
	local deck = makeInstance("Model", "Deck", boat)
	local seat = makeInstance("VehicleSeat", "BoatSeat", deck)
	seat.CanTouch = true
	seat.Occupant = nil
	seat.Position = Vector3.new(0, 0, 0)
	seat.CFrame = CFrame.new(0, 0, 0)
	seat.sitCalls = 0
	seat.deferOccupancy = false
	function seat:Sit(humanoid)
		self.sitCalls += 1
		self.lastHumanoid = humanoid
		if not self.deferOccupancy then
			self.Occupant = humanoid
			humanoid.SeatPart = self
		end
	end
	local anchor = nil
	if withAnchor then
		local frame = makeInstance("Part", "HelmFrame", deck)
		frame.Position = Vector3.new(0, 0, 0)
		frame.CFrame = CFrame.new(0, 0, 0)
		anchor = makeInstance("Attachment", "HelmPromptAnchor", frame)
		anchor.WorldCFrame = CFrame.new(0, 0, 0)
	end
	return boat, seat, anchor
end

local boat, seat, promptAnchor = boatFixture("SmallBoat", true)
local firstPlayer, firstHumanoid = playerFixture("First", Vector3.new(0, 0, 2))
local secondPlayer, secondHumanoid = playerFixture("Second", Vector3.new(0, 0, 2))
Boarding.Refresh(boat)

local prompt = boat:FindFirstChild("HelmPrompt", true)
assert(prompt and prompt:IsA("ProximityPrompt"), "helm prompt was not created")
assert(prompt.Parent == promptAnchor, "prompt did not use fixed HelmPromptAnchor")
assert(prompt.Style == Enum.ProximityPromptStyle.Default, "helm prompt retained a custom/broken style")
assert(prompt.ActionText == "" and prompt.ObjectText == "" and prompt.HoldDuration == 0)
assert(prompt.ClickablePrompt and prompt.KeyboardKeyCode == Enum.KeyCode.E
	and prompt.GamepadKeyCode == Enum.KeyCode.ButtonX)
assert(prompt.Enabled and seat.CanTouch == false, "available prompt/touch-to-sit protection was not configured")

prompt.Triggered:Fire(firstPlayer)
assert(seat.sitCalls == 1 and seat.lastHumanoid == firstHumanoid, "valid prompt did not seat the triggering Humanoid")
assert(not prompt.Enabled, "prompt stayed enabled after a successful take-helm request")
boat:SetAttribute("BoatPhysicsMode", "DYNAMIC_PREPARING")
Boarding.Refresh(boat)
assert(prompt.Enabled, "current driver lost the helm prompt while seated")
boat:SetAttribute("BoatPhysicsMode", "DYNAMIC_DRIVING")
boat:SetAttribute("BoatState", "Sailing")
Boarding.Refresh(boat)
assert(prompt.Enabled, "current driver lost the helm prompt while driving")
prompt.Triggered:Fire(secondPlayer)
assert(seat.sitCalls == 1 and seat.lastHumanoid ~= secondHumanoid, "occupied helm seated a second player")
assert(#dismountCalls == 0, "non-driver requested occupied-helm dismount")
prompt.Triggered:Fire(firstPlayer)
assert(#dismountCalls == 1 and dismountCalls[1][1] == boat
	and dismountCalls[1][2] == firstPlayer and dismountCalls[1][3] == firstHumanoid,
	"current driver did not route through BoatDynamicAuthority.RequestDismount")
assert(not prompt.Enabled, "dismount request did not lock the helm")
runDelayed()
assert(prompt.Enabled, "current-driver prompt did not recover after request timeout")

seat.Occupant = nil
firstHumanoid.SeatPart = nil
boat:SetAttribute("BoatPhysicsMode", "KINEMATIC_IDLE")
boat:SetAttribute("BoatState", "Docked")
Boarding.Refresh(boat)
assert(prompt.Enabled, "free parked helm did not restore its prompt")

-- A no-op/delayed Sit call holds a short server lock so a second trigger
-- cannot race into the same helm before Occupant updates.
seat.deferOccupancy = true
prompt.Triggered:Fire(firstPlayer)
prompt.Triggered:Fire(secondPlayer)
assert(seat.sitCalls == 2 and seat.lastHumanoid == firstHumanoid, "two players acquired one helm attempt")
assert(not prompt.Enabled)
runDelayed()
assert(prompt.Enabled, "failed Sit attempt did not release the prompt lock")

local farPlayer = playerFixture("Far", Vector3.new(100, 0, 0))
prompt.Triggered:Fire(farPlayer)
assert(seat.sitCalls == 2, "server accepted an out-of-range prompt trigger")

boat:SetAttribute("BoatPhysicsMode", "PARKING")
Boarding.Refresh(boat)
assert(not prompt.Enabled, "PARKING boat exposed its helm prompt")
prompt.Triggered:Fire(secondPlayer)
assert(seat.sitCalls == 2, "transitioning boat accepted a helm request")
boat:SetAttribute("BoatPhysicsMode", "KINEMATIC_IDLE")
Boarding.Refresh(boat)
assert(prompt.Enabled)

local fallbackBoat, fallbackSeat = boatFixture("FallbackBoat", false)
Boarding.Refresh(fallbackBoat)
local fallbackPrompt = fallbackBoat:FindFirstChild("HelmPrompt", true)
assert(fallbackPrompt.Parent == fallbackSeat, "missing fixed helm anchor did not fail soft to BoatSeat")
Boarding.Remove(fallbackBoat)
assert(fallbackSeat.CanTouch == true and fallbackPrompt.Destroyed, "boarding removal did not restore the seat/prompt")

Boarding.Remove(boat)
assert(seat.CanTouch == true, "BoatSeat.CanTouch was not restored")
_G.print("PASS: minimal helm glyph, direct seating, current-driver dismount routing, server validation and two-player lock")
