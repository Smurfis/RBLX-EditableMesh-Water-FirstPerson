--!strict

-- Owns only the parked/physical handoff. Water sampling stays on the driver
-- inside WaterInteractionController; helm and character presentation stay separate.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local WaterConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WaterConfig"))
local BoatRuntimeDebug = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BoatRuntimeDebug"))

local remote = ReplicatedStorage:FindFirstChild("BoatDynamicReady")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "BoatDynamicReady"
	remote.Parent = ReplicatedStorage
end
assert(remote:IsA("RemoteEvent"), "ReplicatedStorage.BoatDynamicReady must be a RemoteEvent")
local readyRemote = remote :: RemoteEvent

local MAX_EXIT_TO_SEAT_DISTANCE = 20
local MAX_EXIT_TO_ROOT_DISTANCE = 35

type ExitAttachmentInfo = {
	Attachment: Attachment?,
	Parent: Instance?,
	ParentPart: BasePart?,
	ParentAssemblyRoot: BasePart?,
	BoatAssemblyRoot: BasePart?,
	DistanceToSeat: number?,
	DistanceToRoot: number?,
	SameAssembly: boolean,
	SpatiallyPlausible: boolean,
}

type State = {
	boat: Model,
	root: BasePart?,
	seat: VehicleSeat?,
	driver: Player?,
	occupant: Humanoid?,
	originalAnchored: { [BasePart]: boolean },
	session: number,
	active: boolean,
	lastAlive: number,
	lastSafeTransform: CFrame?,
	currentTransform: CFrame?,
	failedOccupant: Humanoid?,
	releaseStarted: number?,
	dismountPending: boolean,
	pendingExitPlayer: Player?,
	pendingExitHumanoid: Humanoid?,
	pendingExitBeforeSeatLoss: CFrame?,
	pendingExitSeatPartAtLoss: BasePart?,
	pendingExitAttachment: Attachment?,
	pendingExitSeatConnection: RBXScriptConnection?,
	pendingExitPlacementInProgress: boolean,
	repairOwnership: boolean,
	anchorConnections: { [BasePart]: RBXScriptConnection },
	warnedAnchors: { [BasePart]: boolean },
}
local states: { [Model]: State } = {}
local Authority = {}
local activationMessages: { [Model]: string } = setmetatable({}, { __mode = "k" }) :: any

local function activationLog(boat: Model, message: string, enumerate: boolean?)
	boat:SetAttribute("BoatPhysicsLastTransitionReason", message)
	if not RunService:IsStudio() or activationMessages[boat] == message then return end
	activationMessages[boat] = message
	local root = boat:FindFirstChild("BoatRoot", true)
	print(string.format("[BoatActivation] %s | %s | root=%s anchored=%s mass=%s",
		boat:GetFullName(), message,
		if root then root:GetFullName() else "MISSING",
		if root and root:IsA("BasePart") then tostring(root.Anchored) else "n/a",
		if root and root:IsA("BasePart") then tostring(root.AssemblyMass) else "n/a"))
	if enumerate then
		for _, part in boat:GetDescendants() do
			if part:IsA("BasePart") and part.Anchored then
				warn("[BoatDebug] ANCHORED BOAT DESCENDANT: " .. part:GetFullName())
			end
		end
	end
end

local function optInFailure(boat: Model): string?
	local folder = workspace:FindFirstChild("Boats")
	if not folder or boat.Parent ~= folder then return "not a live direct child of Workspace.Boats" end
	if not CollectionService:HasTag(boat, "WaterInteractable") then return "missing WaterInteractable tag" end
	if boat:GetAttribute("WaterProfile") ~= "Boat" then return "WaterProfile must be Boat" end
	if boat:GetAttribute("WaterDynamicPhysics") ~= true then return "WaterDynamicPhysics is not true" end
	if boat:GetAttribute("WaterEnabled") == false then return "WaterEnabled is false" end
	return nil
end

local function optedIn(boat: Model): boolean
	return optInFailure(boat) == nil
end

local function setMode(state: State, mode: string)
	local previous = state.boat:GetAttribute("BoatPhysicsMode")
	if previous ~= mode then
		state.boat:SetAttribute("BoatPhysicsMode", mode)
		print(string.format("[BoatPhysics] %s: %s -> %s", state.boat:GetFullName(), tostring(previous), mode))
	end
end

local function setBoatState(state: State, value: string)
	if state.boat:GetAttribute("BoatState") ~= value then
		state.boat:SetAttribute("BoatState", value)
	end
end

local function commitCurrentTransform(state: State, transform: CFrame)
	state.currentTransform = transform
	state.boat:SetAttribute("CurrentTransform", transform)
end

local function moveRootTo(state: State, target: CFrame, reason: string)
	local root = state.root
	if not root then return end
	local seat = state.seat
	local occupant = if seat then seat.Occupant else nil
	print(string.format(
		"[BoatTransform] boat=%s currentRoot=%s destinationRoot=%s reason=%s occupant=%s physicsMode=%s boatState=%s",
		state.boat:GetFullName(), tostring(root.CFrame), tostring(target), reason,
		if occupant then occupant:GetFullName() else "NONE",
		tostring(state.boat:GetAttribute("BoatPhysicsMode")),
		tostring(state.boat:GetAttribute("BoatState"))
	))
	state.boat:PivotTo(target * root.CFrame:Inverse() * state.boat:GetPivot())
end

local function captureParts(state: State)
	for _, part in state.boat:GetDescendants() do
		if part:IsA("BasePart") and state.originalAnchored[part] == nil then
			state.originalAnchored[part] = part.Anchored
			state.anchorConnections[part] = part:GetPropertyChangedSignal("Anchored"):Connect(function()
				if part.Anchored and part:IsDescendantOf(state.boat)
					and (state.active or state.releaseStarted ~= nil) then
					if not state.warnedAnchors[part] then
						state.warnedAnchors[part] = true
						warn("[BoatDebug] ANCHORED CONNECTED PART: " .. part:GetFullName() .. " (active vessel; releasing anchor)")
					end
					part.Anchored = false
					state.repairOwnership = true
				end
			end)
		end
	end
end

local function disconnectAnchors(state: State)
	for _, connection in state.anchorConnections do connection:Disconnect() end
	table.clear(state.anchorConnections)
end

local function releaseParts(state: State)
	-- Include structure added since preparation, without touching connected
	-- characters or world geometry outside this boat Model.
	captureParts(state)
	for part in state.originalAnchored do
		if part:IsDescendantOf(state.boat) and part.Anchored then
			part.Anchored = false
			if state.active then state.repairOwnership = true end
		end
	end
end

local function assertReleased(root: BasePart)
	assert(not root.Anchored, "BoatRoot remains anchored")
	for _, part in root:GetConnectedParts(true) do
		assert(not part.Anchored, "anchored connected part: " .. part:GetFullName())
	end
	assert(root.AssemblyMass > 0 and root.AssemblyMass < math.huge, "BoatRoot assembly mass is not finite")
end

local function getNetworkOwnerName(root: BasePart): string
	if root.Anchored then return "SERVER (anchored)" end
	local ok, owner = pcall(function()
		return (root.AssemblyRootPart or root):GetNetworkOwner()
	end)
	if not ok then return "UNAVAILABLE" end
	return if owner then owner:GetFullName() else "SERVER"
end

local function describeMotionConstraints(boat: Model): string
	local descriptions = {}
	for _, descendant in boat:GetDescendants() do
		if descendant:IsA("VectorForce") then
			local force = descendant :: VectorForce
			table.insert(descriptions, string.format("%s[Enabled=%s Force=%s]", force:GetFullName(), tostring(force.Enabled), tostring(force.Force)))
		elseif descendant:IsA("LinearVelocity") then
			local velocity = descendant :: LinearVelocity
			table.insert(descriptions, string.format("%s[Enabled=%s VectorVelocity=%s]", velocity:GetFullName(), tostring(velocity.Enabled), tostring(velocity.VectorVelocity)))
		elseif descendant:IsA("AngularVelocity") then
			local velocity = descendant :: AngularVelocity
			table.insert(descriptions, string.format("%s[Enabled=%s AngularVelocity=%s]", velocity:GetFullName(), tostring(velocity.Enabled), tostring(velocity.AngularVelocity)))
		elseif descendant:IsA("Torque") then
			local torque = descendant :: Torque
			table.insert(descriptions, string.format("%s[Enabled=%s Torque=%s]", torque:GetFullName(), tostring(torque.Enabled), tostring(torque.Torque)))
		elseif descendant:IsA("AlignPosition") or descendant:IsA("AlignOrientation") then
			local constraint = descendant :: any
			table.insert(descriptions, string.format("%s[Enabled=%s]", constraint:GetFullName(), tostring(constraint.Enabled)))
		end
	end
	return if #descriptions > 0 then table.concat(descriptions, "; ") else "NONE"
end

local function describeMovingParts(boat: Model): string
	local descriptions = {}
	for _, descendant in boat:GetDescendants() do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			local linear = part.AssemblyLinearVelocity or Vector3.zero
			local angular = part.AssemblyAngularVelocity or Vector3.zero
			if linear.Magnitude > 0.001 or angular.Magnitude > 0.001 or string.find(part.Name, "BoatDynamic", 1, true) then
				table.insert(descriptions, string.format("%s[linear=%s angular=%s anchored=%s]", part:GetFullName(), tostring(linear), tostring(angular), tostring(part.Anchored)))
			end
		end
	end
	return if #descriptions > 0 then table.concat(descriptions, "; ") else "NONE"
end

local function logMotionState(state: State, phase: string, reason: string)
	local root = state.root
	if not root or not root.Parent then return end
	local linear = root.AssemblyLinearVelocity
	local horizontalSpeed = math.sqrt(linear.X * linear.X + linear.Z * linear.Z)
	local occupant = if state.seat then state.seat.Occupant else nil
	print(string.format(
		"[BoatParkingMotion][SERVER][%s] boat=%s reason=%s speed=%.3f horizontalSpeed=%.3f linear=%s angular=%s owner=%s anchored=%s occupant=%s physicsMode=%s boatState=%s constraints=%s movingParts=%s",
		phase, state.boat:GetFullName(), reason, linear.Magnitude, horizontalSpeed,
		tostring(linear), tostring(root.AssemblyAngularVelocity), getNetworkOwnerName(root),
		tostring(root.Anchored), if occupant then occupant:GetFullName() else "NONE",
		tostring(state.boat:GetAttribute("BoatPhysicsMode")), tostring(state.boat:GetAttribute("BoatState")),
		describeMotionConstraints(state.boat), describeMovingParts(state.boat)
	))
end

local function zeroBoatMotion(state: State)
	for _, descendant in state.boat:GetDescendants() do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function fullName(instance: Instance?): string
	return if instance then instance:GetFullName() else "MISSING"
end

local function inspectExitAttachment(state: State): ExitAttachmentInfo
	local root = state.root
	local seat = state.seat
	local candidate = state.boat:FindFirstChild("HelmOccupantExit", true)
	local attachment = if candidate and candidate:IsA("Attachment") then candidate :: Attachment else nil
	local parent = if attachment then attachment.Parent else nil
	local parentPart = if parent and parent:IsA("BasePart") then parent :: BasePart else nil
	local parentAssemblyRoot = if parentPart then parentPart.AssemblyRootPart else nil
	local boatAssemblyRoot = if root then root.AssemblyRootPart or root else nil
	local distanceToSeat = if attachment and seat
		then (attachment.WorldPosition - seat.Position).Magnitude else nil
	local distanceToRoot = if attachment and root
		then (attachment.WorldPosition - root.Position).Magnitude else nil
	local sameAssembly = parentAssemblyRoot ~= nil and boatAssemblyRoot ~= nil
		and parentAssemblyRoot == boatAssemblyRoot
	local spatiallyPlausible = attachment ~= nil and parentPart ~= nil
		and distanceToSeat ~= nil and distanceToSeat <= MAX_EXIT_TO_SEAT_DISTANCE
		and distanceToRoot ~= nil and distanceToRoot <= MAX_EXIT_TO_ROOT_DISTANCE
	return {
		Attachment = attachment,
		Parent = parent,
		ParentPart = parentPart,
		ParentAssemblyRoot = parentAssemblyRoot,
		BoatAssemblyRoot = boatAssemblyRoot,
		DistanceToSeat = distanceToSeat,
		DistanceToRoot = distanceToRoot,
		SameAssembly = sameAssembly,
		SpatiallyPlausible = spatiallyPlausible,
	}
end

local function logExitValidation(state: State, info: ExitAttachmentInfo, phase: string, source: string)
	local root = state.root
	local seat = state.seat
	local parent = info.Parent
	local parentPart = info.ParentPart
	print(string.format(
		"[BoatExitValidation]\nphase=%s\nBoatRoot = %s\nBoatRootAssemblyRoot = %s\nBoatSeat = %s\nExitAttachment = %s\nExitParent = %s [IsBasePart=%s Anchored=%s]\nExitParentAssemblyRoot = %s\ndistanceExitToSeat = %s\ndistanceExitToRoot = %s\nsameAssembly = %s\nsource=%s",
		phase,
		if root then tostring(root.CFrame) else "MISSING",
		fullName(info.BoatAssemblyRoot),
		if seat then tostring(seat.CFrame) else "MISSING",
		if info.Attachment then tostring(info.Attachment.WorldCFrame) else "MISSING",
		fullName(parent), tostring(parentPart ~= nil),
		if parentPart then tostring(parentPart.Anchored) else "n/a",
		fullName(info.ParentAssemblyRoot),
		if info.DistanceToSeat then string.format("%.3f", info.DistanceToSeat) else "n/a",
		if info.DistanceToRoot then string.format("%.3f", info.DistanceToRoot) else "n/a",
		tostring(info.SameAssembly), source
	))
end

local placePendingDriverExit: (State) -> ()

local function clearPendingDriverExit(state: State)
	if state.pendingExitSeatConnection then
		state.pendingExitSeatConnection:Disconnect()
		state.pendingExitSeatConnection = nil
	end
	state.pendingExitPlayer = nil
	state.pendingExitHumanoid = nil
	state.pendingExitBeforeSeatLoss = nil
	state.pendingExitSeatPartAtLoss = nil
	state.pendingExitAttachment = nil
	state.pendingExitPlacementInProgress = false
end

local function queueDriverExit(state: State, player: Player?, humanoid: Humanoid?)
	if not player or not humanoid or humanoid.Health <= 0 or player.Character ~= humanoid.Parent then return end
	if state.pendingExitHumanoid ~= humanoid then
		clearPendingDriverExit(state)
	end
	state.pendingExitPlayer = player
	state.pendingExitHumanoid = humanoid
	state.pendingExitSeatPartAtLoss = humanoid.SeatPart
	local exitInfo = inspectExitAttachment(state)
	local attachmentValid = exitInfo.SameAssembly and exitInfo.SpatiallyPlausible
	state.pendingExitAttachment = if attachmentValid then exitInfo.Attachment else nil
	logExitValidation(state, exitInfo, "BeforeParking",
		if attachmentValid then "HelmOccupantExit" else "LiveSeatFallback")
	local characterRoot = humanoid.Parent:FindFirstChild("HumanoidRootPart")
	if characterRoot and characterRoot:IsA("BasePart") then
		state.pendingExitBeforeSeatLoss = characterRoot.CFrame
	end
	if not state.pendingExitSeatConnection then
		-- Occupant and SeatPart do not have to clear in the same engine update.
		-- Observe SeatPart directly so final placement never waits for the 10 Hz
		-- authority watchdog after the server has already parked the vessel.
		state.pendingExitSeatConnection = humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if states[state.boat] == state then
				placePendingDriverExit(state)
			end
		end)
	end
end

placePendingDriverExit = function(state: State)
	local player = state.pendingExitPlayer
	local humanoid = state.pendingExitHumanoid
	if not player or not humanoid or state.pendingExitPlacementInProgress then return end
	local character = player.Character
	if not character or humanoid.Parent ~= character or humanoid.Health <= 0 then
		clearPendingDriverExit(state)
		return
	end
	if state.boat:GetAttribute("BoatPhysicsMode") ~= "KINEMATIC_IDLE" then return end
	local seat = state.seat
	if not seat or not seat.Parent or seat.Occupant == humanoid or humanoid.SeatPart == seat then return end
	local characterRoot = character:FindFirstChild("HumanoidRootPart")
	if not characterRoot or not characterRoot:IsA("BasePart") then
		clearPendingDriverExit(state)
		return
	end

	local rootPart = characterRoot :: BasePart
	local beforeSeatLoss = state.pendingExitBeforeSeatLoss or rootPart.CFrame
	local beforeFinalPlacement = rootPart.CFrame
	local seatPartAtLoss = state.pendingExitSeatPartAtLoss
	local validatedExitAttachment = state.pendingExitAttachment
	local exitInfo = inspectExitAttachment(state)
	-- Never trust an authored WorldCFrame merely because the Attachment exists.
	-- Its BasePart had to share BoatRoot's live physical assembly before parking,
	-- and its current uncached pose must still be plausible beside this boat.
	local exitAttachment = if validatedExitAttachment ~= nil
		and exitInfo.Attachment == validatedExitAttachment
		and exitInfo.SpatiallyPlausible
		then validatedExitAttachment else nil
	local standingCFrame: CFrame
	local placementSource: string
	if exitAttachment then
		-- This runs only after KINEMATIC_IDLE and after the seat weld/occupancy
		-- is gone, so the authored marker cannot move the driver prematurely.
		standingCFrame = exitAttachment.WorldCFrame
		placementSource = exitAttachment:GetFullName()
	else
		local verticalClearance = seat.Size.Y * 0.5 + math.max(0, humanoid.HipHeight)
			+ rootPart.Size.Y * 0.5 + 0.5
		local sideClearance = seat.Size.X * 0.5 + rootPart.Size.X * 0.5 + 0.35
		local standingPosition = (seat.CFrame * CFrame.new(sideClearance, verticalClearance, 0)).Position
		local seatForward = seat.CFrame.LookVector
		local facing = Vector3.new(seatForward.X, 0, seatForward.Z)
		if facing.Magnitude < 0.001 then
			local currentForward = rootPart.CFrame.LookVector
			facing = Vector3.new(currentForward.X, 0, currentForward.Z)
		end
		if facing.Magnitude < 0.001 then facing = Vector3.new(0, 0, -1) end
		standingCFrame = CFrame.lookAt(standingPosition, standingPosition + facing.Unit, Vector3.yAxis)
		placementSource = "BoatSeat fallback"
	end
	logExitValidation(state, exitInfo, "FinalPlacement",
		if exitAttachment then "HelmOccupantExit" else "LiveSeatFallback")

	-- The seat weld is already gone. Clear jump/boat momentum on the character
	-- assembly and perform the one final exit placement without touching the boat.
	state.pendingExitPlacementInProgress = true
	-- Disconnect and clear the pending identity before the sole CFrame write so
	-- re-entrant seat/property signals cannot perform a second placement.
	if state.pendingExitSeatConnection then
		state.pendingExitSeatConnection:Disconnect()
		state.pendingExitSeatConnection = nil
	end
	state.pendingExitPlayer = nil
	state.pendingExitHumanoid = nil
	state.pendingExitBeforeSeatLoss = nil
	state.pendingExitSeatPartAtLoss = nil
	state.pendingExitAttachment = nil
	humanoid.Sit = false
	humanoid.Jump = false
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	rootPart.CFrame = standingCFrame
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid.Sit = false
	humanoid.Jump = false
	local afterPlacement = rootPart.CFrame
	local displacement = (beforeFinalPlacement.Position - beforeSeatLoss.Position).Magnitude
	print(string.format(
		"[BoatDriverExit]\nHRP_beforeSeatLoss = %s\nHRP_beforeFinalPlacement = %s\nExitAttachment = %s\nHRP_afterPlacement = %s\ndisplacement = %.3f",
		tostring(beforeSeatLoss), tostring(beforeFinalPlacement),
		if exitAttachment then tostring(exitAttachment.WorldCFrame) else "MISSING (BoatSeat fallback)",
		tostring(afterPlacement), displacement
	))
	if displacement > 3 then
		warn(string.format(
			"[BoatDriverExit] %.3f studs of pre-placement movement detected; source=%s. BoatDynamicAuthority made no character CFrame write before final placement.",
			displacement,
			if seatPartAtLoss == seat then
				"Roblox SeatPart/SeatWeld teardown after Occupant cleared (platform-rider was suppressed by PARKING)"
			else
				"replicated character physics already free of BoatSeat (platform-rider was suppressed by PARKING)"
		))
	end
	print(string.format(
		"[BoatExit] player=%s boat=%s seat=%s standingCFrame=%s physicsMode=%s placementSource=%s",
		player:GetFullName(), state.boat:GetFullName(), seat:GetFullName(), tostring(rootPart.CFrame),
		tostring(state.boat:GetAttribute("BoatPhysicsMode")), placementSource
	))
	state.pendingExitPlacementInProgress = false
end

local function park(state: State, failure: string?, capturedParkingTransform: CFrame?)
	-- Tell the client to stop forces before ownership or anchoring changes.
	-- BoatState changes only after the final resting transform is committed.
	setMode(state, "PARKING")
	state.active = false
	state.releaseStarted = nil
	state.dismountPending = false
	state.repairOwnership = false
	local root = state.root
	local parkingTransform = capturedParkingTransform or (if root and root.Parent then root.CFrame else nil)
	if root and root.Parent and root.Position.Y < WaterConfig.GetSurfaceY() - 40 then
		failure = failure or "boat below safety threshold on exit"
	end
	if not failure and parkingTransform then
		-- Commit the physical pose before revoking ownership or anchoring.
		commitCurrentTransform(state, parkingTransform)
	end
	local parkingReason = failure or "normal driver release"
	logMotionState(state, "BEFORE", parkingReason)
	state.boat:SetAttribute("BoatPhysicsLastTransitionReason", failure or "parked: no validated dynamic driver")
	activationLog(state.boat, failure or "PARK: no validated dynamic driver")
	if root and root.Parent and not root.Anchored then
		pcall(function()
			(root.AssemblyRootPart or root):SetNetworkOwner(nil)
		end)
	end
	-- Revoke the moving client's authority, then clear every assembly before
	-- changing anchors. A second pass after anchoring rejects a final replicated
	-- owner packet and prevents an anchored hull from behaving like a conveyor.
	zeroBoatMotion(state)
	for part, anchored in state.originalAnchored do
		if part:IsDescendantOf(state.boat) then
			part.Anchored = anchored
		end
	end
	if root and root.Parent then
		root.Anchored = true
	end
	zeroBoatMotion(state)
	state.boat:SetAttribute("BoatDynamicDriverUserId", nil)
	if failure then
		state.failedOccupant = state.occupant
		if state.lastSafeTransform then
			moveRootTo(state, state.lastSafeTransform, "RECOVERING: " .. failure)
		end
		zeroBoatMotion(state)
		if root and root.Parent then
			commitCurrentTransform(state, root.CFrame)
		end
		warn("[BoatPhysics][RECOVERY] " .. state.boat:GetFullName() .. ": " .. failure)
		setMode(state, "RECOVERING")
	else
		setMode(state, "KINEMATIC_IDLE")
	end
	setBoatState(state, "Docked")
	logMotionState(state, "AFTER", parkingReason)
end

function Authority.Refresh(boat: Model)
	local state = states[boat]
	local rootCandidate = boat:FindFirstChild("BoatRoot", true)
	local seatCandidate = boat:FindFirstChild("BoatSeat", true)
	local root = if rootCandidate and rootCandidate:IsA("BasePart") then rootCandidate else nil
	local seat = if seatCandidate and seatCandidate:IsA("VehicleSeat") then seatCandidate else nil
	local blocked = optInFailure(boat)
	if blocked or not root or not seat then
		if state then
			park(state, if state.active then "dynamic opt-in, BoatRoot or BoatSeat removed" else nil)
			clearPendingDriverExit(state)
			disconnectAnchors(state)
			states[boat] = nil
		end
		activationLog(boat, "BLOCKED: " .. (blocked or (if not root then "BoatRoot BasePart/MeshPart missing" else "BoatSeat VehicleSeat missing")))
		return
	end
	if not state then
		state = {
			boat = boat, root = root, seat = seat, driver = nil, occupant = nil,
			originalAnchored = {}, session = 0, active = false, lastAlive = 0,
			lastSafeTransform = nil, currentTransform = nil, failedOccupant = nil,
			releaseStarted = nil, dismountPending = false,
			pendingExitPlayer = nil, pendingExitHumanoid = nil,
			pendingExitBeforeSeatLoss = nil, pendingExitSeatPartAtLoss = nil,
			pendingExitAttachment = nil,
			pendingExitSeatConnection = nil, pendingExitPlacementInProgress = false,
			repairOwnership = false,
			anchorConnections = {}, warnedAnchors = {},
		}
		states[boat] = state
		local storedTransform = boat:GetAttribute("CurrentTransform")
		if typeof(storedTransform) == "CFrame" then
			state.currentTransform = storedTransform
			moveRootTo(state, storedTransform, "INITIALIZE: apply replicated CurrentTransform")
		else
			commitCurrentTransform(state, root.CFrame)
		end
		state.lastSafeTransform = root.CFrame
		setBoatState(state, "Docked")
		captureParts(state)
		park(state)
	end
	if state.root ~= root or state.seat ~= seat then
		park(state, "BoatRoot or BoatSeat changed during handoff")
		state.root = root
		state.seat = seat
		root.Anchored = true
	end
	local occupant = seat.Occupant
	local character = if occupant then occupant.Parent else nil
	local driver = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
	if occupant and (occupant.Health <= 0 or occupant.SeatPart ~= seat) then
		driver = nil
	end
	-- Occupant loss from the validated driver is a normal dismount, not a
	-- watchdog/recovery condition. Capture both live poses before doing any
	-- lifecycle work, then synchronously enter PARKING in this property-change
	-- callback. PARKING also prevents the client rider controller from consuming
	-- a stale physical-boat delta; KINEMATIC_IDLE later establishes a new baseline.
	local mode = state.boat:GetAttribute("BoatPhysicsMode")
	if not state.dismountPending and occupant == nil and state.driver and state.occupant
		and (mode == "DYNAMIC_PREPARING" or mode == "DYNAMIC_DRIVING") then
		local departedDriver = state.driver
		local departedHumanoid = state.occupant
		local sailedToTransform = root.CFrame
		queueDriverExit(state, departedDriver, departedHumanoid)
		park(state, nil, sailedToTransform)
		state.session += 1
		state.boat:SetAttribute("BoatDynamicSession", state.session)
		state.occupant = nil
		state.driver = nil
		state.failedOccupant = nil
		placePendingDriverExit(state)
		return
	end
	placePendingDriverExit(state)
	if state.dismountPending then
		if state.occupant == occupant and state.driver == driver then
			-- The explicit handback already parked the boat. Wait for the server's
			-- seat properties to catch up without starting or parking a second time.
			return
		end
		state.dismountPending = false
		state.session += 1
		state.boat:SetAttribute("BoatDynamicSession", state.session)
		state.occupant = occupant
		state.driver = driver
		state.failedOccupant = nil
		if driver then
			captureParts(state)
			state.lastSafeTransform = root.CFrame
			commitCurrentTransform(state, root.CFrame)
			activationLog(boat, "WAITING: replacement BoatSeat driver, client Ready not received")
			setMode(state, "DYNAMIC_PREPARING")
		else
			activationLog(boat, if occupant then "WAITING: occupant is not a living player with SeatPart == BoatSeat" else "WAITING: BoatSeat has no occupant")
		end
		placePendingDriverExit(state)
		return
	end
	if state.occupant == occupant and state.driver == driver then
		if state.active or state.releaseStarted then releaseParts(state) end
		if not state.active and not state.releaseStarted and driver and not state.failedOccupant then
			activationLog(boat, "WAITING: valid BoatSeat driver, client Ready not received")
		elseif not state.active and not state.releaseStarted and not driver then
			activationLog(boat, if occupant then "WAITING: occupant is not a living player with SeatPart == BoatSeat" else "WAITING: BoatSeat has no occupant")
		end
		return
	end
	local previousDriver = state.driver
	local previousOccupant = state.occupant
	if previousDriver and previousOccupant and (previousDriver ~= driver or previousOccupant ~= occupant) then
		queueDriverExit(state, previousDriver, previousOccupant)
	end
	park(state)
	state.session += 1
	state.boat:SetAttribute("BoatDynamicSession", state.session)
	state.occupant = occupant
	state.driver = driver
	state.failedOccupant = nil
	placePendingDriverExit(state)
	if driver then
		captureParts(state)
		state.lastSafeTransform = root.CFrame
		commitCurrentTransform(state, root.CFrame)
		activationLog(boat, "WAITING: valid BoatSeat driver, client Ready not received")
		setMode(state, "DYNAMIC_PREPARING")
	end
end

local function performDriverStop(state: State, player: Player, queueExit: boolean, forceSeatExit: boolean): boolean
	if state.driver ~= player then
		return false
	end
	local mode = state.boat:GetAttribute("BoatPhysicsMode")
	if mode ~= "DYNAMIC_PREPARING" and mode ~= "DYNAMIC_DRIVING" and mode ~= "PARKING" then
		return false
	end
	local occupant = state.occupant
	if queueExit then
		queueDriverExit(state, player, occupant)
	end
	park(state)
	state.dismountPending = true
	if forceSeatExit and occupant and occupant.Parent and occupant.Health > 0 then
		-- Parking and ownership handback are already complete. Request weld/seat
		-- release now; final character placement still waits for Occupant and
		-- SeatPart to clear inside placePendingDriverExit.
		occupant.Jump = false
		occupant.Sit = false
	end
	placePendingDriverExit(state)
	return true
end

function Authority.RequestDismount(boat: Model, player: Player, humanoid: Humanoid): boolean
	local state = states[boat]
	local seat = if state then state.seat else nil
	if not state or not seat or state.driver ~= player or state.occupant ~= humanoid
		or seat.Occupant ~= humanoid or humanoid.SeatPart ~= seat
		or player.Character ~= humanoid.Parent or humanoid.Health <= 0 then
		return false
	end
	return performDriverStop(state, player, true, true)
end

function Authority.Remove(boat: Model)
	local state = states[boat]
	if state then
		park(state)
		clearPendingDriverExit(state)
		disconnectAnchors(state)
		states[boat] = nil
	end
end

readyRemote.OnServerEvent:Connect(function(player: Player, boat: Instance, session: number, action: string, detail: any)
	if typeof(boat) ~= "Instance" or not boat:IsA("Model") or not optedIn(boat) then
		return
	end
	local state = states[boat]
	if not state or state.session ~= session or state.driver ~= player then
		if action == "Ready" then activationLog(boat, "READY REJECTED: session or validated driver does not match") end
		return
	end
	-- Dismount is an explicit normal handback. Handle it before validating the
	-- seat properties because Occupant/SeatPart replication is the state that is
	-- actively changing. Legacy Stop messages are also treated as graceful so an
	-- older client can never route ordinary teardown through recovery.
	if action == "Dismounting" or action == "Stop" then
		performDriverStop(state, player, action == "Dismounting", false)
		return
	end
	local root, seat = state.root, state.seat
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not seat or not humanoid or humanoid.Health <= 0
		or seat.Occupant ~= humanoid or humanoid.SeatPart ~= seat
		or state.failedOccupant == humanoid then
		if action == "Ready" then activationLog(boat, "READY REJECTED: seat/root/humanoid validation failed or session is recovering") end
		return
	end
	if action == "Failure" then
		local mode = boat:GetAttribute("BoatPhysicsMode")
		if mode == "DYNAMIC_PREPARING" or mode == "DYNAMIC_DRIVING" then
			local failureDetail = if typeof(detail) == "string" then detail else "unspecified client failure"
			park(state, "validated driver reported dynamic helper/sample failure: " .. failureDetail)
		end
		return
	end
	if state.active then
		if action == "Alive" then
			state.lastAlive = os.clock()
		end
		return
	end
	if state.releaseStarted then return end
	if action ~= "Ready" or boat:GetAttribute("BoatPhysicsMode") ~= "DYNAMIC_PREPARING" then
		return
	end
	-- Ready is a notification, never permission to nominate another root/owner.
	state.lastSafeTransform = root.CFrame
	state.releaseStarted = os.clock()
	activationLog(boat, "BEFORE UNANCHOR: Ready accepted for live boat", true)
	releaseParts(state)
	activationLog(boat, "AFTER UNANCHOR: all live boat BaseParts visited; awaiting assembly update", true)
end)

local function completeRelease(state: State)
	local root, seat, player = state.root, state.seat, state.driver
	if not root or not seat or not player then return end
	local ok, err = pcall(function()
		assertReleased(root)
		local assembly = root.AssemblyRootPart or root
		assert(seat.AssemblyRootPart == assembly, "BoatSeat is not rigidly connected to BoatRoot")
		local canSet, reason = assembly:CanSetNetworkOwnership()
		assert(canSet, reason)
		assembly:SetNetworkOwner(player)
		assert(assembly:GetNetworkOwner() == player, "driver ownership did not apply")
	end)
	if not ok then
		-- Anchored assemblies can report their old roots/mass until physics has
		-- rebuilt the graph. Retry only within this validated readiness session.
		if state.releaseStarted and os.clock() - state.releaseStarted < 0.5 then return end
		if RunService:IsStudio() then BoatRuntimeDebug.Inspect(state.boat) end
		park(state, "ownership handoff failed: " .. tostring(err))
		return
	end
	state.active = true
	state.releaseStarted = nil
	state.repairOwnership = false
	state.lastAlive = os.clock()
	state.boat:SetAttribute("BoatDynamicDriverUserId", player.UserId)
	activationLog(state.boat, "ACTIVE: connected parts unanchored, finite mass, driver owns assembly", true)
	setMode(state, "DYNAMIC_DRIVING")
	setBoatState(state, "Sailing")
	if RunService:IsStudio() and state.boat:GetAttribute("BoatPhysicsDebug") == true then BoatRuntimeDebug.Inspect(state.boat) end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	-- Finish release after physics has had a step to rebuild the assembly.
	for boat, state in states do
		if state.releaseStarted then
			Authority.Refresh(boat)
			if state.releaseStarted then completeRelease(state) end
		end
	end
	elapsed += dt
	if elapsed < 0.1 then return end
	elapsed = 0
	for boat, state in states do
		Authority.Refresh(boat)
		if not state.active then continue end
		local root = state.root
		if not root then continue end
		local y = root.Position.Y
		if y ~= y or y < WaterConfig.GetSurfaceY() - 40 then
			park(state, "boat dropped below safety threshold")
		elseif os.clock() - state.lastAlive > 3 then
			park(state, "dynamic client heartbeat timed out")
		else
			local ok, err = pcall(function()
				assertReleased(root)
				local assembly = root.AssemblyRootPart or root
				if state.repairOwnership then
					assembly:SetNetworkOwner(state.driver)
					state.repairOwnership = false
				end
				assert(assembly:GetNetworkOwner() == state.driver, "active boat lost driver network ownership")
			end)
			if not ok then
				if RunService:IsStudio() then BoatRuntimeDebug.Inspect(boat) end
				park(state, tostring(err))
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, state in states do
		if state.driver == player then park(state) end
	end
end)

CollectionService:GetInstanceAddedSignal("WaterInteractable"):Connect(function(instance)
	if instance:IsA("Model") then Authority.Refresh(instance) end
end)
CollectionService:GetInstanceRemovedSignal("WaterInteractable"):Connect(function(instance)
	if instance:IsA("Model") then Authority.Remove(instance) end
end)

return Authority
