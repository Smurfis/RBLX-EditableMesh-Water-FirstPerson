local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

local statusGui = Instance.new("ScreenGui")
statusGui.Name = "ProjectStatusGui"
statusGui.ResetOnSpawn = false
statusGui.IgnoreGuiInset = true
statusGui.DisplayOrder = 20
statusGui.Parent = playerGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "ProjectStatus"
statusLabel.AnchorPoint = Vector2.new(1, 1)
statusLabel.Position = UDim2.new(1, -18, 1, -18)
statusLabel.Size = UDim2.fromOffset(620, 44)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
statusLabel.TextStrokeTransparency = 0.35
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextXAlignment = Enum.TextXAlignment.Right
statusLabel.TextYAlignment = Enum.TextYAlignment.Bottom
statusLabel.RichText = false
statusLabel.Parent = statusGui

local serverId = game.JobId
if serverId == "" then
	serverId = "studio"
end

local fps = 60
RunService.RenderStepped:Connect(function(deltaTime)
	if deltaTime > 0 then
		local instantFps = 1 / deltaTime
		fps += (instantFps - fps) * math.clamp(deltaTime * 5, 0, 1)
	end

	local waterFolder = Workspace:FindFirstChild("__ClientRealisticWaterV4")
	local waterVersion = "V4"
	if waterFolder then
		local configuredVersion = waterFolder:GetAttribute("WaterVersion")
		if typeof(configuredVersion) == "string" and configuredVersion ~= "" then
			waterVersion = configuredVersion
		end
	end

	statusLabel.Text = string.format(
		"RBLX EditableMesh Water First Person\n[server: %s, waterVersion: %s, fps: %d]",
		serverId,
		waterVersion,
		math.floor(fps + 0.5)
	)
end)
