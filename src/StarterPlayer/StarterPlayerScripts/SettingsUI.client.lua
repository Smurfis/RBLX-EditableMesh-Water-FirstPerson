local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Checkbox = require(
	ReplicatedStorage
		:WaitForChild("UI")
		:WaitForChild("Checkbox")
)

local gui = Instance.new("ScreenGui")
gui.Name = "SettingsGui"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local container = Instance.new("Frame")
container.Size = UDim2.fromOffset(300, 300)
container.Position = UDim2.fromScale(0.5, 0.5)
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Parent = gui

local reflections = Checkbox.new(
	container,
	"Player Reflections",
	true,
	function(enabled)
		print("Player Reflections:", enabled)

		if enabled then
			-- Enable reflections
		else
			-- Disable reflections
		end
	end
)

reflections.Frame.Position = UDim2.fromOffset(20, 20)