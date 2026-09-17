--!strict

-- Local presentation only: hide occupied helms from non-drivers and provide
-- temporary client-side transform diagnostics for the first Studio validation.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local boatsFolder = Workspace:WaitForChild("Boats")

type PromptBinding = {
	Prompt: ProximityPrompt,
	SeatConnection: RBXScriptConnection?,
	AttributeConnection: RBXScriptConnection,
	EnabledConnection: RBXScriptConnection,
	AncestryConnection: RBXScriptConnection,
	Updating: boolean,
}

local bindings: { [ProximityPrompt]: PromptBinding } = {}

local function boatFor(instance: Instance): Model?
	local candidate: Instance? = instance
	while candidate and candidate.Parent ~= boatsFolder do
		candidate = candidate.Parent
	end
	return if candidate and candidate:IsA("Model") then candidate else nil
end

local function boatSeat(boat: Model): VehicleSeat?
	local candidate = boat:FindFirstChild("BoatSeat", true)
	return if candidate and candidate:IsA("VehicleSeat") then candidate else nil
end

local function localHumanoid(): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function update(binding: PromptBinding)
	if binding.Updating then return end
	local prompt = binding.Prompt
	local boat = boatFor(prompt)
	local seat = if boat then boatSeat(boat) else nil
	local occupant = if seat then seat.Occupant else nil
	local visibleToLocalPlayer = occupant == nil or occupant == localHumanoid()
	local enabled = prompt:GetAttribute("HelmServerEnabled") == true and visibleToLocalPlayer
	if prompt.Enabled ~= enabled then
		binding.Updating = true
		prompt.Enabled = enabled
		binding.Updating = false
	end
end

local function unbind(prompt: ProximityPrompt)
	local binding = bindings[prompt]
	if not binding then return end
	if binding.SeatConnection then binding.SeatConnection:Disconnect() end
	binding.AttributeConnection:Disconnect()
	binding.EnabledConnection:Disconnect()
	binding.AncestryConnection:Disconnect()
	bindings[prompt] = nil
end

local function bind(prompt: ProximityPrompt)
	if bindings[prompt] or prompt.Name ~= "HelmPrompt" then return end
	local boat = boatFor(prompt)
	if not boat then return end
	local binding: PromptBinding
	binding = {
		Prompt = prompt,
		SeatConnection = nil,
		AttributeConnection = prompt:GetAttributeChangedSignal("HelmServerEnabled"):Connect(function()
			update(binding)
		end),
		EnabledConnection = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			update(binding)
		end),
		AncestryConnection = prompt.AncestryChanged:Connect(function()
			if not prompt:IsDescendantOf(boatsFolder) then unbind(prompt) end
		end),
		Updating = false,
	}
	bindings[prompt] = binding
	local seat = boatSeat(boat)
	if seat then
		binding.SeatConnection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			update(binding)
		end)
	end
	update(binding)
end

local function refreshAll()
	for _, binding in bindings do update(binding) end
end

for _, descendant in boatsFolder:GetDescendants() do
	if descendant:IsA("ProximityPrompt") then bind(descendant) end
end

boatsFolder.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		task.defer(bind, descendant)
	end
end)

player.CharacterAdded:Connect(function()
	task.defer(refreshAll)
end)
player.CharacterRemoving:Connect(refreshAll)

ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, triggeringPlayer: Player?)
	if prompt.Name ~= "HelmPrompt" or (triggeringPlayer and triggeringPlayer ~= player) then return end
	local boat = boatFor(prompt)
	local seat = if boat then boatSeat(boat) else nil
	local rootCandidate = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
	local root = if rootCandidate and rootCandidate:IsA("BasePart") then rootCandidate else nil
	local boatRootCandidate = if boat then boat:FindFirstChild("BoatRoot", true) else nil
	local boatRoot = if boatRootCandidate and boatRootCandidate:IsA("BasePart") then boatRootCandidate else nil
	print(string.format(
		"[HelmSeatDiagnostic][CLIENT][TRIGGER] player=%s hrp=%s boatRoot=%s boatSeat=%s boatState=%s physicsMode=%s currentTransform=%s occupant=%s",
		player:GetFullName(), if root then tostring(root.CFrame) else "MISSING",
		if boatRoot then tostring(boatRoot.CFrame) else "MISSING",
		if seat then tostring(seat.CFrame) else "MISSING",
		if boat then tostring(boat:GetAttribute("BoatState")) else "MISSING",
		if boat then tostring(boat:GetAttribute("BoatPhysicsMode")) else "MISSING",
		if boat then tostring(boat:GetAttribute("CurrentTransform")) else "MISSING",
		if seat and seat.Occupant then seat.Occupant:GetFullName() else "NONE"
	))
end)
