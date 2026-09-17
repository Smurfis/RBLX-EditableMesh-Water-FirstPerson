--!strict

-- Owns only helm prompt interaction and the final BoatSeat:Sit call. BoatSeat
-- occupancy and BoatDynamicAuthority continue to own every physics transition.
local Players = game:GetService("Players")

local BoatDynamicAuthority = require(script.Parent:WaitForChild("BoatDynamicAuthority"))

local PROMPT_NAME = "HelmPrompt"
local PROMPT_ANCHOR_NAME = "HelmPromptAnchor"
local BOAT_SEAT_NAME = "BoatSeat"
local DEFAULT_PROMPT_DISTANCE = 10
local DISTANCE_GRACE = 3
local ATTEMPT_TIMEOUT = 1.5

type PromptMarker = Attachment | BasePart
type AttemptKind = "Take" | "Dismount"

type Binding = {
	Boat: Model,
	Seat: VehicleSeat?,
	OriginalSeatCanTouch: boolean?,
	Prompt: ProximityPrompt?,
	OwnsPrompt: boolean,
	PromptConnection: RBXScriptConnection?,
	TakingPlayer: Player?,
	AttemptKind: AttemptKind?,
	AttemptId: number,
}

local Boarding = {}
local bindings: { [Model]: Binding } = {}

local function numberAttribute(instance: Instance, name: string, fallback: number, minimum: number, maximum: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then math.clamp(value, minimum, maximum) else fallback
end

local function findBoatSeat(boat: Model): VehicleSeat?
	local candidate = boat:FindFirstChild(BOAT_SEAT_NAME, true)
	return if candidate and candidate:IsA("VehicleSeat") then candidate else nil
end

local function findBoatRoot(boat: Model): BasePart?
	local candidate = boat:FindFirstChild("BoatRoot", true)
	return if candidate and candidate:IsA("BasePart") then candidate else nil
end

local function markerCFrame(marker: PromptMarker): CFrame
	return if marker:IsA("Attachment") then marker.WorldCFrame else (marker :: BasePart).CFrame
end

local function isOnRotatingHandle(part: BasePart, handle: BasePart?): boolean
	return handle ~= nil and (part == handle or part:IsDescendantOf(handle))
end

local function findPromptParent(boat: Model, seat: VehicleSeat): PromptMarker
	local authored = boat:FindFirstChild(PROMPT_ANCHOR_NAME, true)
	if authored and (authored:IsA("Attachment") or authored:IsA("BasePart")) then
		return authored :: PromptMarker
	end

	local handleCandidate = boat:FindFirstChild("Handle", true)
	local handle = if handleCandidate and handleCandidate:IsA("BasePart") then handleCandidate else nil
	local hingeCandidate = boat:FindFirstChild("HingeConstraint", true)
	if hingeCandidate and hingeCandidate:IsA("HingeConstraint") then
		for _, attachment in { hingeCandidate.Attachment0, hingeCandidate.Attachment1 } do
			local part = if attachment then attachment.Parent else nil
			if part and part:IsA("BasePart") and not isOnRotatingHandle(part, handle) then
				return attachment :: Attachment
			end
		end
	end

	for _, name in { "HelmFrame", "HelmStand", "HelmPedestal", "HelmMount" } do
		local candidate = boat:FindFirstChild(name, true)
		if candidate and candidate:IsA("BasePart") and not isOnRotatingHandle(candidate, handle) then
			return candidate
		end
	end

	return seat
end

local function liveCharacter(player: Player): (Humanoid?, BasePart?)
	if player.Parent ~= Players then
		return nil, nil
	end
	local character = player.Character
	if not character or Players:GetPlayerFromCharacter(character) ~= player then
		return nil, nil
	end
	local humanoidCandidate = character:FindFirstChildOfClass("Humanoid")
	local rootCandidate = character:FindFirstChild("HumanoidRootPart")
	local humanoid = if humanoidCandidate and humanoidCandidate:IsA("Humanoid") then humanoidCandidate else nil
	local root = if rootCandidate and rootCandidate:IsA("BasePart") then rootCandidate else nil
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

local function freeHelmLifecycle(boat: Model): boolean
	return boat:GetAttribute("BoatPhysicsMode") == "KINEMATIC_IDLE"
		and boat:GetAttribute("BoatState") == "Docked"
end

local function driverHelmLifecycle(boat: Model): boolean
	local mode = boat:GetAttribute("BoatPhysicsMode")
	local state = boat:GetAttribute("BoatState")
	return (mode == "DYNAMIC_PREPARING" and state == "Docked")
		or (mode == "DYNAMIC_DRIVING" and state == "Sailing")
end

local function validSeat(binding: Binding): VehicleSeat?
	local seat = binding.Seat
	if not seat or not seat.Parent or not seat:IsDescendantOf(binding.Boat) then
		return nil
	end
	return seat
end

local function helmCanInteract(binding: Binding): boolean
	if binding.Boat.Parent == nil or binding.TakingPlayer ~= nil then
		return false
	end
	local seat = validSeat(binding)
	if not seat then
		return false
	end
	if seat.Occupant == nil then
		return freeHelmLifecycle(binding.Boat)
	end
	local character = seat.Occupant.Parent
	local driver = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
	return driver ~= nil and driverHelmLifecycle(binding.Boat)
end

local function updatePrompt(binding: Binding)
	local prompt = binding.Prompt
	if prompt and prompt.Parent then
		local enabled = helmCanInteract(binding)
		prompt:SetAttribute("HelmServerEnabled", enabled)
		prompt.Enabled = enabled
	end
end

local function releaseAttempt(binding: Binding)
	binding.TakingPlayer = nil
	binding.AttemptKind = nil
	updatePrompt(binding)
end

local function occupantName(seat: VehicleSeat): string
	return if seat.Occupant then seat.Occupant:GetFullName() else "NONE"
end

local function logSeatDiagnostic(phase: string, binding: Binding, player: Player, root: BasePart, seat: VehicleSeat)
	local boatRoot = findBoatRoot(binding.Boat)
	print(string.format(
		"[HelmSeatDiagnostic][SERVER][%s] player=%s hrp=%s boatRoot=%s boatSeat=%s boatState=%s physicsMode=%s currentTransform=%s occupant=%s",
		phase, player:GetFullName(), tostring(root.CFrame),
		if boatRoot then tostring(boatRoot.CFrame) else "MISSING",
		tostring(seat.CFrame), tostring(binding.Boat:GetAttribute("BoatState")),
		tostring(binding.Boat:GetAttribute("BoatPhysicsMode")),
		tostring(binding.Boat:GetAttribute("CurrentTransform")), occupantName(seat)
	))
end

local function beginAttempt(binding: Binding, player: Player, kind: AttemptKind): number
	binding.TakingPlayer = player
	binding.AttemptKind = kind
	binding.AttemptId += 1
	local attemptId = binding.AttemptId
	updatePrompt(binding)
	task.delay(ATTEMPT_TIMEOUT, function()
		if bindings[binding.Boat] == binding and binding.AttemptId == attemptId
			and binding.TakingPlayer == player then
			releaseAttempt(binding)
		end
	end)
	return attemptId
end

local function interact(binding: Binding, player: Player)
	if not helmCanInteract(binding) then
		return
	end

	local humanoid, root = liveCharacter(player)
	local seat = validSeat(binding)
	local prompt = binding.Prompt
	if not humanoid or not root or not seat or not prompt or not prompt.Parent then
		return
	end
	local promptParent = prompt.Parent
	if not (promptParent:IsA("Attachment") or promptParent:IsA("BasePart")) then
		return
	end
	if (root.Position - markerCFrame(promptParent :: PromptMarker).Position).Magnitude
		> prompt.MaxActivationDistance + DISTANCE_GRACE then
		return
	end

	local occupant = seat.Occupant
	if occupant == nil then
		if humanoid.SeatPart ~= nil or not freeHelmLifecycle(binding.Boat) then
			return
		end
		beginAttempt(binding, player, "Take")
		logSeatDiagnostic("BEFORE_SIT", binding, player, root, seat)
		local ok, problem = pcall(function()
			-- Entry deliberately uses the current live seat and performs no CFrame,
			-- PivotTo, MoveTo or cached-transform operation.
			seat:Sit(humanoid)
		end)
		logSeatDiagnostic("AFTER_SIT", binding, player, root, seat)
		if not ok then
			warn("[BoatHelmBoarding] BoatSeat:Sit failed: " .. tostring(problem))
			releaseAttempt(binding)
		end
		return
	end

	if occupant ~= humanoid or humanoid.SeatPart ~= seat or not driverHelmLifecycle(binding.Boat) then
		return
	end
	beginAttempt(binding, player, "Dismount")
	if not BoatDynamicAuthority.RequestDismount(binding.Boat, player, humanoid) then
		releaseAttempt(binding)
	end
end

local function disconnectPrompt(binding: Binding)
	if binding.PromptConnection then
		binding.PromptConnection:Disconnect()
		binding.PromptConnection = nil
	end
end

local function releaseSeat(binding: Binding)
	local seat = binding.Seat
	if seat and seat.Parent and binding.OriginalSeatCanTouch ~= nil then
		seat.CanTouch = binding.OriginalSeatCanTouch
	end
	binding.Seat = nil
	binding.OriginalSeatCanTouch = nil
end

function Boarding.Refresh(boat: Model)
	local binding = bindings[boat]
	if not binding then
		binding = {
			Boat = boat, Seat = nil, OriginalSeatCanTouch = nil,
			Prompt = nil, OwnsPrompt = false, PromptConnection = nil,
			TakingPlayer = nil, AttemptKind = nil, AttemptId = 0,
		}
		bindings[boat] = binding
	end

	local seat = findBoatSeat(boat)
	if binding.Seat ~= seat then
		releaseAttempt(binding)
		releaseSeat(binding)
		binding.Seat = seat
		if seat then
			binding.OriginalSeatCanTouch = seat.CanTouch
			seat.CanTouch = false
		end
	end

	if binding.TakingPlayer then
		if binding.AttemptKind == "Take" and seat and seat.Occupant ~= nil then
			releaseAttempt(binding)
		elseif binding.AttemptKind == "Dismount" and (not seat or seat.Occupant == nil) then
			releaseAttempt(binding)
		end
	end

	if not seat then
		if binding.Prompt then
			binding.Prompt:SetAttribute("HelmServerEnabled", false)
			binding.Prompt.Enabled = false
		end
		return
	end

	local promptCandidate = boat:FindFirstChild(PROMPT_NAME, true)
	local prompt = if promptCandidate and promptCandidate:IsA("ProximityPrompt") then promptCandidate else nil
	if binding.Prompt and binding.Prompt.Parent and binding.Prompt ~= prompt then
		prompt = binding.Prompt
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.Parent = findPromptParent(boat, seat)
		binding.OwnsPrompt = true
	elseif binding.Prompt ~= prompt then
		binding.OwnsPrompt = false
	end

	if binding.Prompt ~= prompt then
		disconnectPrompt(binding)
		binding.Prompt = prompt
		binding.PromptConnection = prompt.Triggered:Connect(function(triggeringPlayer: Player)
			interact(binding :: Binding, triggeringPlayer)
		end)
	elseif binding.OwnsPrompt then
		local expectedParent = findPromptParent(boat, seat)
		if prompt.Parent ~= expectedParent then prompt.Parent = expectedParent end
	end

	-- Force Roblox's complete built-in prompt UI. A pre-existing Studio prompt
	-- may otherwise retain Style=Custom and render an unusable empty indicator.
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.ActionText = ""
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = numberAttribute(boat, "HelmPromptDistance", DEFAULT_PROMPT_DISTANCE, 4, 20)
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	updatePrompt(binding)
end

function Boarding.Remove(boat: Model)
	local binding = bindings[boat]
	if not binding then return end
	disconnectPrompt(binding)
	if binding.Prompt then
		binding.Prompt:SetAttribute("HelmServerEnabled", false)
		binding.Prompt.Enabled = false
		if binding.OwnsPrompt and binding.Prompt.Parent then binding.Prompt:Destroy() end
	end
	releaseSeat(binding)
	bindings[boat] = nil
end

Players.PlayerRemoving:Connect(function(player: Player)
	for _, binding in bindings do
		if binding.TakingPlayer == player then releaseAttempt(binding) end
	end
end)

return Boarding
