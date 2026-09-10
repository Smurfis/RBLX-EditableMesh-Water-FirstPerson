local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
local SETTINGS_SIZE = UDim2.fromOffset(360, 300)
container.Size = UDim2.fromOffset(0, 300)
container.Position = UDim2.fromScale(0.5, 0.5)
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
container.BackgroundTransparency = 0.08
container.BorderSizePixel = 0
container.ClipsDescendants = true
container.Visible = false
container.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = container

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(16, 10)
title.Size = UDim2.new(1, -32, 0, 28)
title.BackgroundTransparency = 1
title.Text = "SETTINGS"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = container

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "SettingsList"
scroll.Position = UDim2.fromOffset(12, 46)
scroll.Size = UDim2.new(1, -24, 1, -58)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 180, 220)
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = container

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 10)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

local function createSlider(
	name: string,
	labelText: string,
	defaultValue: number,
	callback: (number) -> ()
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(1, -8, 0, 48)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = 2
	frame.Parent = scroll

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(0, 28)
	track.Size = UDim2.new(1, 0, 0, 8)
	track.BackgroundColor3 = Color3.fromRGB(60, 70, 82)
	track.BorderSizePixel = 0
	track.Parent = frame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(defaultValue, 1)
	fill.BackgroundColor3 = Color3.fromRGB(100, 190, 240)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local knob = Instance.new("TextButton")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(defaultValue, 0.5)
	knob.Size = UDim2.fromOffset(16, 16)
	knob.BackgroundColor3 = Color3.fromRGB(235, 250, 255)
	knob.Text = ""
	knob.AutoButtonColor = false
	knob.Parent = track

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local value = defaultValue
	local dragging = false

	local function setValue(nextValue: number)
		value = math.clamp(nextValue, 0, 1)
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
		label.Text = string.format("%s: %d%%", labelText, math.floor(value * 100 + 0.5))
		callback(value)
	end

	local function updateFromInput(input: InputObject)
		local width = math.max(track.AbsoluteSize.X, 1)
		setValue((input.Position.X - track.AbsolutePosition.X) / width)
	end

	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			updateFromInput(input)
		end
	end)
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			updateFromInput(input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			updateFromInput(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	setValue(defaultValue)
	return frame
end

createSlider("WaterOpacitySlider", "Water opacity", 0.75, function(value)
	container:SetAttribute("WaterOpacity", value)
end)

createSlider("CameraSensitivitySlider", "Camera sensitivity", 0.5, function(value)
	container:SetAttribute("CameraSensitivity", value)
end)

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
	row.Position = UDim2.fromScale(0.98, if yOffset < -50 then 0.88 else 0.94)
	row.Size = UDim2.fromScale(0.22, 0.04)
	row.BackgroundTransparency = 1
	row.Parent = statusGui

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromOffset(24, 24)
	icon.AnchorPoint = Vector2.new(1, 0)
	icon.Position = UDim2.new(1, 0, 0, 2)
	icon.BackgroundTransparency = 1
	icon.Image = imageId
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.fromOffset(0, 0)
	label.Size = UDim2.new(1, -32, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 1
	label.Font = Enum.Font.Cartoon
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = row

	return row
end

local settingsRow = createKeybindRow(
	"SettingsKeybind",
	"rbxassetid://97812683336887",
	"SETTINGS: [=]",
	-42
)

local freeMouseRow = createKeybindRow(
	"MouseLockKeybind",
	"rbxassetid://77904780414059",
	"Free Mouse: [M]",
	-70
)

local settingsLabel = settingsRow:FindFirstChild("Label")
local mouseLabel = freeMouseRow:FindFirstChild("Label")

local compactKeybinds = false
local function applyCompactKeybinds()
	if settingsLabel and settingsLabel:IsA("TextLabel") then
		settingsLabel.Visible = not compactKeybinds
	end
	if mouseLabel and mouseLabel:IsA("TextLabel") then
		mouseLabel.Visible = not compactKeybinds
	end
end

local compactSetting = Checkbox.new(
	scroll,
	"Compact keybind HUD",
	false,
	function(enabled)
		compactKeybinds = enabled
		applyCompactKeybinds()
	end
)
compactSetting.Frame.LayoutOrder = 4
local settingsIcon = settingsRow:FindFirstChild("Icon")
local mouseIcon = freeMouseRow:FindFirstChild("Icon")

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

local serverLabel = Instance.new("TextLabel")
serverLabel.Name = "ServerStatus"
serverLabel.AnchorPoint = Vector2.new(0.5, 0)
serverLabel.Position = UDim2.fromScale(0.5, 0.035)
serverLabel.Size = UDim2.fromScale(0.32, 0.035)
serverLabel.BackgroundTransparency = 1
serverLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
serverLabel.TextStrokeTransparency = 1
serverLabel.Font = Enum.Font.Cartoon
serverLabel.TextSize = 18
serverLabel.TextXAlignment = Enum.TextXAlignment.Center
serverLabel.TextYAlignment = Enum.TextYAlignment.Center
serverLabel.Parent = statusGui

local fpsLabel = Instance.new("TextLabel")
fpsLabel.Name = "FPSStatus"
fpsLabel.AnchorPoint = Vector2.new(1, 0)
fpsLabel.Position = UDim2.fromScale(0.91, 0.035)
fpsLabel.Size = UDim2.fromScale(0.08, 0.035)
fpsLabel.BackgroundTransparency = 1
fpsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
fpsLabel.TextStrokeTransparency = 1
fpsLabel.Font = Enum.Font.Cartoon
fpsLabel.TextSize = 16
fpsLabel.TextXAlignment = Enum.TextXAlignment.Right
fpsLabel.TextYAlignment = Enum.TextYAlignment.Center
fpsLabel.Parent = statusGui

local versionLabel = Instance.new("TextLabel")
versionLabel.Name = "WaterVersionStatus"
versionLabel.AnchorPoint = Vector2.new(1, 0)
versionLabel.Position = UDim2.fromScale(0.98, 0.035)
versionLabel.Size = UDim2.fromScale(0.06, 0.035)
versionLabel.BackgroundTransparency = 1
versionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
versionLabel.TextStrokeTransparency = 1
versionLabel.Font = Enum.Font.Cartoon
versionLabel.TextSize = 16
versionLabel.TextXAlignment = Enum.TextXAlignment.Left
versionLabel.TextYAlignment = Enum.TextYAlignment.Center
versionLabel.Parent = statusGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "ProjectStatus"
statusLabel.AnchorPoint = Vector2.new(1, 0)
statusLabel.Position = UDim2.fromScale(0.72, 0.035)
statusLabel.Size = UDim2.fromScale(0.27, 0.035)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.TextStrokeTransparency = 1
statusLabel.Font = Enum.Font.Cartoon
statusLabel.TextSize = 16
statusLabel.TextXAlignment = Enum.TextXAlignment.Right
statusLabel.TextYAlignment = Enum.TextYAlignment.Center
statusLabel.RichText = false
statusLabel.Parent = statusGui

local SETTINGS_TOGGLE_KEY = Enum.KeyCode.Equals
local mouseReleased = false
local settingsOpen = false
player:SetAttribute("SettingsOpen", false)

local function updateMouseUi()
	player:SetAttribute("MouseReleased", mouseReleased)
	if settingsIcon and settingsIcon:IsA("ImageLabel") then
		settingsIcon.Visible = not settingsOpen
	end
	if mouseIcon and mouseIcon:IsA("ImageLabel") then
		mouseIcon.Visible = not mouseReleased
	end
	reticle.Visible = not mouseReleased
end

updateMouseUi()

local settingsTweenInfo = TweenInfo.new(
	0.24,
	Enum.EasingStyle.Quart,
	Enum.EasingDirection.Out
)

local function setSettingsOpen(open: boolean)
	settingsOpen = open
	player:SetAttribute("SettingsOpen", open)

	if open then
		mouseReleased = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		updateMouseUi()
		container.Visible = true
		TweenService:Create(container, settingsTweenInfo, {
			Size = SETTINGS_SIZE,
		}):Play()
		return
	end

	mouseReleased = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	updateMouseUi()

	local tween = TweenService:Create(container, settingsTweenInfo, {
		Size = UDim2.fromOffset(0, SETTINGS_SIZE.Y.Offset),
	})
	tween.Completed:Connect(function()
		if not settingsOpen then
			container.Visible = false
		end
	end)
	tween:Play()
end

local function addKeybindButton(row: Frame): TextButton
	local button = Instance.new("TextButton")
	button.Name = "TapTarget"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.ZIndex = 10
	button.Parent = row
	return button
end

local settingsButton = addKeybindButton(settingsRow)
settingsButton.Activated:Connect(function()
	setSettingsOpen(not settingsOpen)
end)

local mouseButton = addKeybindButton(freeMouseRow)
mouseButton.Activated:Connect(function()
	if settingsOpen then
		return
	end
	mouseReleased = not mouseReleased
	updateMouseUi()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == SETTINGS_TOGGLE_KEY then
		setSettingsOpen(not settingsOpen)
		return
	end

	if settingsOpen then
		return
	end

	if input.KeyCode == Enum.KeyCode.M then
		mouseReleased = not mouseReleased
		updateMouseUi()
	end
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

	statusLabel.Text = "RBLX EditableMesh Water First Person"
	serverLabel.Text = string.format("server: %s", serverId)
	versionLabel.Text = "v4.x.x"
	fpsLabel.Text = string.format("FPS: %d", math.floor(fps + 0.5))
end)
