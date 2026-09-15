local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------------------------------------------------------
-- REMOTE
----------------------------------------------------------------

local lookEvent =
	ReplicatedStorage:FindFirstChild("Look")

if not lookEvent then
	lookEvent = Instance.new("RemoteEvent")
	lookEvent.Name = "Look"
	lookEvent.Parent = ReplicatedStorage
end

assert(
	lookEvent:IsA("RemoteEvent"),
	"ReplicatedStorage.Look must be a RemoteEvent"
)

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------

local MIN_SEND_INTERVAL = 0.08

local lastSendTimes: { [Player]: number } = {}

----------------------------------------------------------------
-- PLAYER SETUP
----------------------------------------------------------------

local function setupPlayer(player: Player)
	player:SetAttribute(
		"LookVector",
		Vector3.new(0, 0, -1)
	)

	lastSendTimes[player] = 0
end

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerAdded:Connect(
	setupPlayer
)

Players.PlayerRemoving:Connect(function(player)
	lastSendTimes[player] = nil
end)

----------------------------------------------------------------
-- LOOK REPLICATION
----------------------------------------------------------------

lookEvent.OnServerEvent:Connect(function(
	player: Player,
	lookVector: any
)
	------------------------------------------------------------
	-- TYPE VALIDATION
	------------------------------------------------------------

	if typeof(lookVector) ~= "Vector3" then
		return
	end

	------------------------------------------------------------
	-- RATE LIMIT
	------------------------------------------------------------

	local now = os.clock()
	local lastSend =
		lastSendTimes[player] or 0

	if now - lastSend < MIN_SEND_INTERVAL then
		return
	end

	lastSendTimes[player] = now

	------------------------------------------------------------
	-- VECTOR VALIDATION
	------------------------------------------------------------

	local magnitude =
		lookVector.Magnitude

	if magnitude < 0.001 then
		return
	end

	-- Camera LookVector should normally already be unit length.
	-- Don't accept absurd values from the client.
	if magnitude > 2 then
		return
	end

	------------------------------------------------------------
	-- REPLICATE
	------------------------------------------------------------

	player:SetAttribute(
		"LookVector",
		lookVector.Unit
	)
end)