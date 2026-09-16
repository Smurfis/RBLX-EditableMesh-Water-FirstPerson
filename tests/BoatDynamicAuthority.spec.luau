-- Runs the actual authority module with mocked Roblox services. These checks
-- cover permissions/lifecycle, not Studio physics, constraints or replication.
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			function connection:Disconnect() self.Connected = false end
			table.insert(callbacks, { callback, connection })
			return connection
		end,
		Fire = function(_, ...) for _, entry in callbacks do if entry[2].Connected then entry[1](...) end end end,
	}
end
local frames = {}
frames.__index = frames
function frames:Inverse() return self end
function frames.__mul(left, _) return left end
local function cframe(name)
	return setmetatable({ Name = name, __cframe = true }, frames)
end

local function instance(class, name, parent)
	local obj = { ClassName = class, Name = name, Parent = parent, attributes = {}, children = {}, __instance = true }
	obj.anchorSignal = signal()
	setmetatable(obj, {
		__index = function(self, key)
			if key == "Anchored" then return rawget(self, "_anchored") end
			if key == "AssemblyMass" then
				if self.staleMass or self.Anchored then return math.huge end
				for _, part in self:GetConnectedParts(true) do if part.Anchored then return math.huge end end
				return 100
			end
		end,
		__newindex = function(self, key, value)
			if key == "Anchored" then
				local changed = rawget(self, "_anchored") ~= value
				rawset(self, "_anchored", value)
				if changed then self.anchorSignal:Fire() end
			else rawset(self, key, value) end
		end,
	})
	function obj:GetPropertyChangedSignal(_) return self.anchorSignal end
	function obj:GetConnectedParts(_) return self.connected or {} end
	if parent then table.insert(parent.children, obj) end
	function obj:IsA(wanted) return wanted == self.ClassName or (wanted == "BasePart" and (self.ClassName == "MeshPart" or self.ClassName == "VehicleSeat")) end
	function obj:IsDescendantOf(ancestor)
		local cursor = self.Parent
		while cursor do if cursor == ancestor then return true end cursor = cursor.Parent end
		return false
	end
	function obj:GetDescendants()
		local list = {}
		for _, child in self.children do
			table.insert(list, child)
			for _, descendant in child:GetDescendants() do table.insert(list, descendant) end
		end
		return list
	end
	function obj:FindFirstChild(wanted, recursive)
		for _, child in (if recursive then self:GetDescendants() else self.children) do
			if child.Name == wanted then return child end
		end
		return nil
	end
	function obj:WaitForChild(wanted) return assert(self:FindFirstChild(wanted), wanted) end
	function obj:FindFirstChildOfClass(wanted)
		for _, child in self.children do if child.ClassName == wanted then return child end end
		return nil
	end
	function obj:GetAttribute(key) return self.attributes[key] end
	function obj:SetAttribute(key, value)
		self.attributes[key] = value
		if key == "BoatPhysicsMode" then
			self.modeHistory = self.modeHistory or {}
			table.insert(self.modeHistory, value)
		end
	end
	function obj:GetFullName() return self.Name end
	function obj:GetPivot() return self.pivot end
	function obj:PivotTo(pivot) self.pivot = pivot; self.restores = (self.restores or 0) + 1 end
	return obj
end
local builtinTypeof = typeof
local function typeof(value)
	if type(value) == "table" and value.__instance then return "Instance" end
	if type(value) == "table" and value.__cframe then return "CFrame" end
	return builtinTypeof(value)
end
local vectorMetatable = {}
vectorMetatable.__index = function(vector, key)
	if key == "Magnitude" then return math.sqrt(vector.X * vector.X + vector.Y * vector.Y + vector.Z * vector.Z) end
	return vectorMetatable[key]
end
local Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vectorMetatable) end
Vector3.zero = Vector3.new(0, 0, 0)
local clock = 0
local os = { clock = function() return clock end }
local warnings = {}
local function warn(message) table.insert(warnings, message) end
local function print(...) end
local workspace = instance("Workspace", "Workspace")
local folder = instance("Folder", "Boats", workspace)
local storage = instance("ReplicatedStorage", "ReplicatedStorage")
local modules = instance("Folder", "Modules", storage)
instance("ModuleScript", "WaterConfig", modules)
instance("ModuleScript", "BoatRuntimeDebug", modules)
local remote = instance("RemoteEvent", "BoatDynamicReady", storage)
remote.OnServerEvent = signal()
local heartbeat = signal()
local added, removed = signal(), signal()
local players = { PlayerRemoving = signal() }
function players:GetPlayerFromCharacter(character) return character.player end
local services = {
	Players = players, ReplicatedStorage = storage, RunService = { Heartbeat = heartbeat, IsStudio = function() return true end, IsServer = function() return true end },
	CollectionService = {
		HasTag = function(_, boat) return boat.tagged == true end,
		GetInstanceAddedSignal = function() return added end,
		GetInstanceRemovedSignal = function() return removed end,
	},
}
local game = { GetService = function(_, name) return assert(services[name], name) end }
local RuntimeDebug = (function()
--[[BOAT_DEBUG_SOURCE]]
end)()
local function require(module)
	if module.Name == "BoatRuntimeDebug" then return RuntimeDebug end
	return { GetSurfaceY = function() return 6 end }
end
local Authority = (function()
--[[AUTHORITY_SOURCE]]
end)()

local function fixture()
	local boat = instance("Model", "SmallBoat", folder)
	boat.tagged = true
	boat.pivot = cframe("spawn")
	boat:SetAttribute("WaterProfile", "Boat")
	boat:SetAttribute("WaterDynamicPhysics", true)
	local deck = instance("Model", "Deck", boat)
	local root = instance("MeshPart", "BoatRoot", deck)
	root.Position = { Y = 10 }; root.Anchored = true; root.AssemblyRootPart = root
	root.CFrame = boat.pivot
	root.owner = nil; root.ownershipCalls = 0
	function boat:GetPivot() return root.CFrame end
	function boat:PivotTo(pivot)
		self.pivot = pivot; root.CFrame = pivot; self.restores = (self.restores or 0) + 1
	end
	function root:CanSetNetworkOwnership() return not self.Anchored, "anchored" end
	function root:SetNetworkOwner(owner)
		assert(not self.Anchored, "ownership API called while anchored")
		self.owner = owner; self.ownershipCalls += 1
	end
	function root:GetNetworkOwner() return self.owner end
	local seat = instance("VehicleSeat", "BoatSeat", deck)
	seat.AssemblyRootPart = root; seat.Anchored = false
	local wheel = instance("MeshPart", "Handle", deck)
	wheel.Anchored = false
	local rail = instance("MeshPart", "BoatRail", root)
	rail.Anchored = true
	root.connected = { rail, seat }
	for _, name in { "MastThwart", "CentreThwart", "ControllerSeat" } do
		local part = instance("MeshPart", name, deck)
		part.Anchored = true
		table.insert(root.connected, part)
	end
	for _, part in boat:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local character = instance("Model", "Character")
	local player = instance("Player", "Driver")
	player.UserId = 10; player.Character = character; character.player = player
	local humanoid = instance("Humanoid", "Humanoid", character)
	humanoid.Health = 100
	Authority.Refresh(boat)
	return boat, root, seat, wheel, player, humanoid
end

local boat, root, seat, wheel, player, humanoid = fixture()
assert(boat:GetAttribute("BoatPhysicsMode") == "KINEMATIC_IDLE" and root.Anchored)
assert(boat:GetAttribute("BoatState") == "Docked")
assert(boat:GetAttribute("CurrentTransform") == root.CFrame)
seat.Occupant = humanoid; humanoid.SeatPart = seat
Authority.Refresh(boat)
assert(root.Anchored and root.ownershipCalls == 0, "sitting must not release boat")
assert(not wheel.Anchored, "park must preserve free helm part")
local session = boat:GetAttribute("BoatDynamicSession")
local stranger = instance("Player", "Stranger")
remote.OnServerEvent:Fire(stranger, boat, session, "Ready")
remote.OnServerEvent:Fire(player, boat, session - 1, "Ready")
remote.OnServerEvent:Fire(player, workspace, session, "Ready")
assert(root.Anchored, "invalid sender/session/target was allowed")
remote.OnServerEvent:Fire(player, boat, session, "Ready")
assert(not root.Anchored and root.owner == nil, "must wait for assembly update before assigning owner")
root.staleMass = true; heartbeat:Fire(0.1)
assert(not root.Anchored and boat:GetAttribute("BoatPhysicsMode") == "DYNAMIC_PREPARING", "transient infinite mass must not immediately restore anchors")
root.staleMass = false; heartbeat:Fire(0.1)
assert(not root.Anchored and root.owner == player)
assert(root.AssemblyMass < math.huge)
for _, part in root:GetConnectedParts(true) do assert(not part.Anchored, part.Name) end
-- Regression: nested BoatRail re-anchored after release must not freeze vessel.
local rail = root:FindFirstChild("BoatRail")
rail.Anchored = true
assert(not rail.Anchored and root.AssemblyMass < math.huge)
heartbeat:Fire(0.1)
assert(root.owner == player and boat:GetAttribute("BoatPhysicsMode") == "DYNAMIC_DRIVING")
assert(boat:GetAttribute("BoatState") == "Sailing")
local late = instance("MeshPart", "LateStructure", root)
late.Anchored = true; table.insert(root.connected, late)
Authority.Refresh(boat); heartbeat:Fire(0.1)
assert(not late.Anchored and root.owner == player, "late structure must be unanchored")
local report = RuntimeDebug.Inspect(boat)
assert(#report.AnchoredParts == 0 and report.Mass < math.huge)
assert(boat:GetAttribute("BoatPhysicsMode") == "DYNAMIC_DRIVING")
local calls = root.ownershipCalls
remote.OnServerEvent:Fire(player, boat, session, "Ready")
assert(root.ownershipCalls == calls, "duplicate ready repeated release")
local leftTransform = cframe("left-at-sea")
root.CFrame = leftTransform
root.AssemblyLinearVelocity = Vector3.new(28, 13, -7)
root.AssemblyAngularVelocity = Vector3.new(0.4, 1.2, -0.3)
wheel.AssemblyLinearVelocity = Vector3.new(28, 13, -7)
wheel.AssemblyAngularVelocity = Vector3.new(0.4, 1.2, -0.3)
-- Client seat state changes before the server's Occupant property. The explicit
-- handback must park normally even while the server still sees the old driver.
local transitionsBeforeDismount = #boat.modeHistory
remote.OnServerEvent:Fire(player, boat, session, "Dismounting")
assert(root.Anchored and root.owner == nil and not wheel.Anchored)
assert(boat:GetAttribute("BoatPhysicsMode") == "KINEMATIC_IDLE")
assert(#boat.modeHistory == transitionsBeforeDismount + 2)
assert(boat.modeHistory[#boat.modeHistory - 1] == "PARKING" and boat.modeHistory[#boat.modeHistory] == "KINEMATIC_IDLE")
assert(boat:GetAttribute("BoatState") == "Docked")
assert(boat:GetAttribute("CurrentTransform") == leftTransform, "dismount restored the activation transform")
assert(root.AssemblyLinearVelocity.Magnitude == 0 and root.AssemblyAngularVelocity.Magnitude == 0, "BoatRoot retained sailing motion after parking")
assert(wheel.AssemblyLinearVelocity.Magnitude == 0 and wheel.AssemblyAngularVelocity.Magnitude == 0, "separate boat part retained sailing motion after parking")
seat.Occupant = nil; humanoid.SeatPart = nil
Authority.Refresh(boat)
assert(#boat.modeHistory == transitionsBeforeDismount + 2, "seat replication parked the boat twice")
assert(root.Anchored and root.owner == nil and not wheel.Anchored)
assert(boat:GetAttribute("BoatPhysicsMode") == "KINEMATIC_IDLE")
assert(boat:GetAttribute("BoatState") == "Docked")
assert(boat:GetAttribute("CurrentTransform") == leftTransform, "exit did not commit the physical transform")
remote.OnServerEvent:Fire(player, boat, session, "Ready")
assert(root.Anchored, "late ready after exit released boat")

for _ = 1, 10 do
	seat.Occupant = humanoid; humanoid.SeatPart = seat; Authority.Refresh(boat)
	session = boat:GetAttribute("BoatDynamicSession")
	remote.OnServerEvent:Fire(player, boat, session, "Ready")
	heartbeat:Fire(0.1)
	assert(root.owner == player and not root.Anchored)
	seat.Occupant = nil; humanoid.SeatPart = nil; Authority.Refresh(boat)
	assert(root.Anchored and root.owner == nil)
end

local function activate()
	seat.Occupant = nil; humanoid.SeatPart = nil; Authority.Refresh(boat)
	seat.Occupant = humanoid; humanoid.SeatPart = seat; Authority.Refresh(boat)
	session = boat:GetAttribute("BoatDynamicSession")
	remote.OnServerEvent:Fire(player, boat, session, "Ready")
	heartbeat:Fire(0.1)
end
activate()
local logoutTransform = cframe("logout-at-sea")
root.CFrame = logoutTransform
players.PlayerRemoving:Fire(player)
assert(root.Anchored and boat:GetAttribute("BoatState") == "Docked")
assert(boat:GetAttribute("CurrentTransform") == logoutTransform, "logout restored the pre-sailing transform")

activate()
clock = 2; remote.OnServerEvent:Fire(player, boat, session, "Alive")
heartbeat:Fire(0.1); assert(not root.Anchored)
clock = 6; heartbeat:Fire(0.1)
assert(root.Anchored and boat:GetAttribute("BoatPhysicsMode") == "RECOVERING", "client timeout must recover")
remote.OnServerEvent:Fire(player, boat, session, "Ready")
assert(root.Anchored, "failed session must remain blocked until exit")

activate(); root.Position.Y = -50; heartbeat:Fire(0.1)
assert(root.Anchored and boat.restores >= 2, "abyss must restore safe BoatRoot transform")
root.Position.Y = 10
activate(); root.owner = stranger; heartbeat:Fire(0.1)
assert(root.Anchored, "lost ownership must recover")
activate(); remote.OnServerEvent:Fire(player, boat, session, "Failure", "disabled helper")
assert(root.Anchored, "client failure must recover")
assert(boat:GetAttribute("BoatPhysicsMode") == "RECOVERING")
-- Compatibility Stop is graceful; it must never recreate the dismount bug.
activate(); local legacyStopTransform = cframe("legacy-stop-at-sea"); root.CFrame = legacyStopTransform
remote.OnServerEvent:Fire(player, boat, session, "Stop")
assert(boat:GetAttribute("BoatPhysicsMode") == "KINEMATIC_IDLE")
assert(boat:GetAttribute("CurrentTransform") == legacyStopTransform)
activate(); boat.tagged = false; removed:Fire(boat)
assert(root.Anchored, "tag removal must park")

local other, otherRoot, otherSeat, _, otherPlayer, otherHumanoid = fixture()
otherSeat.AssemblyRootPart = otherSeat
otherSeat.Occupant = otherHumanoid; otherHumanoid.SeatPart = otherSeat
Authority.Refresh(other)
remote.OnServerEvent:Fire(otherPlayer, other, other:GetAttribute("BoatDynamicSession"), "Ready")
clock += 1; heartbeat:Fire(0.1)
assert(otherRoot.Anchored and other:GetAttribute("BoatPhysicsMode") == "RECOVERING", "disconnected seat must recover")
assert(#warnings >= 6)
-- Guard connections must be removed with the boat's authority state.
Authority.Remove(other)
otherRoot.Anchored = true
assert(otherRoot.Anchored)
_G.print("PASS: current-transform dismount, complete motion stop, ten mount cycles, and isolated timeout/abyss/ownership/helper/tag recovery")
