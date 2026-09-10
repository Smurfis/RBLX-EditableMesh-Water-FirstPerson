local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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
container.Visible = false
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

local function createKeybindRow(
	name: string,
	imageId: string,
	text: string,
	yOffset: number
): Frame
	local row = Instance.new("Frame")
	row.Name = name
	row.AnchorPoint = Vector2.new(1, 1)
	row.Position = UDim2.new(1, -18, 1, yOffset)
	row.Size = UDim2.fromOffset(270, 28)
	row.BackgroundTransparency = 1
	row.Parent = statusGui

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromOffset(24, 24)
	icon.Position = UDim2.fromOffset(0, 2)
	icon.BackgroundTransparency = 1
	icon.Image = imageId
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.fromOffset(32, 0)
	label.Size = UDim2.new(1, -32, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.35
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = row

	return row
end

createKeybindRow(
	"SettingsKeybind",
	"rbxassetid://97812683336887",
	"[SETTINGS: KEYBIND]",
	-70
)

local freeMouseRow = createKeybindRow(
	"MouseLockKeybind",
	"rbxassetid://77904780414059",
	"[Free Mouse: M]",
	-42
)

local reticle = Instance.new("Frame")
reticle.Name = "FirstPersonReticle"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.5)
reticle.Size = UDim2.fromOffset(6, 6)
reticle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
reticle.BackgroundTransparency = 0.1
reticle.BorderSizePixel = 0
reticle.Parent = statusGui

local reticleCorner = Instance.new("UICorner")
reticleCorner.CornerRadius = UDim.new(1, 0)
reticleCorner.Parent = reticle

local reticleStroke = Instance.new("UIStroke")
reticleStroke.Color = Color3.fromRGB(0, 0, 0)
reticleStroke.Transparency = 0.25
reticleStroke.Thickness = 1
reticleStroke.Parent = reticle

local serverLabel = Instance.new("TextLabel")
serverLabel.Name = "ServerStatus"
serverLabel.Position = UDim2.fromOffset(18, 18)
serverLabel.Size = UDim2.fromOffset(620, 24)
serverLabel.BackgroundTransparency = 1
serverLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
serverLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
serverLabel.TextStrokeTransparency = 0.35
serverLabel.Font = Enum.Font.Gotham
serverLabel.TextSize = 14
serverLabel.TextXAlignment = Enum.TextXAlignment.Left
serverLabel.TextYAlignment = Enum.TextYAlignment.Center
serverLabel.Parent = statusGui

local versionLabel = Instance.new("TextLabel")
versionLabel.Name = "WaterVersionStatus"
versionLabel.AnchorPoint = Vector2.new(0, 1)
versionLabel.Position = UDim2.new(0, 18, 1, -18)
versionLabel.Size = UDim2.fromOffset(620, 24)
versionLabel.BackgroundTransparency = 1
versionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
versionLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
versionLabel.TextStrokeTransparency = 0.35
versionLabel.Font = Enum.Font.Gotham
versionLabel.TextSize = 14
versionLabel.TextXAlignment = Enum.TextXAlignment.Left
versionLabel.TextYAlignment = Enum.TextYAlignment.Center
versionLabel.Parent = statusGui

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

local SETTINGS_TOGGLE_KEY = Enum.KeyCode.K
local mouseReleased = false

local function updateMouseUi()
	freeMouseRow.Visible = mouseReleased
	reticle.Visible = not mouseReleased
end

updateMouseUi()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.M then
		mouseReleased = not mouseReleased
		updateMouseUi()
		return
	end

	if input.KeyCode ~= SETTINGS_TOGGLE_KEY then
		return
	end

	container.Visible = not container.Visible
end)

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
		"RBLX EditableMesh Water First Person\n[fps: %d]",
		math.floor(fps + 0.5)
	)
	serverLabel.Text = string.format("[server: %s]", serverId)
	versionLabel.Text = string.format("[waterVersion: %s]", waterVersion)
end)
