--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local existing = ReplicatedStorage:FindFirstChild("SparkCameraTransitionRemote")
if existing and not existing:IsA("RemoteFunction") then
	existing:Destroy() -- Removes old RemoteEvent if it was created incorrectly
end

local remote = ReplicatedStorage:FindFirstChild("SparkCameraTransitionRemote")
if not remote then
	local newRemote = Instance.new("RemoteFunction")
	newRemote.Name = "SparkCameraTransitionRemote"
	newRemote.Parent = ReplicatedStorage
	remote = newRemote
end

local serverRemote = remote :: RemoteFunction

serverRemote.OnServerInvoke = function(player: Player, action: any)
	if action == "TransitionFinished" then
		print(string.format("[Server]: Handshake received from player '%s'. Completing spawn sequence.", player.Name))
		return true
	end
	return false
end
