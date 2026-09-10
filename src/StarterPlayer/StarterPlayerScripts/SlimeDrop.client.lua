local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= Enum.KeyCode.G then return end
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("RemoteEvent") and descendant.Name == "DropEvent" then
			descendant:FireServer()
		end
	end
end)
