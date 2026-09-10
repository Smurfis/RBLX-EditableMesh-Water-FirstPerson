--!strict

-- ReplicatedStorage > UI > Checkbox

local Checkbox = {}

export type Checkbox = {
	Frame: Frame,
	Button: ImageButton,
	Label: TextLabel,

	Value: boolean,

	Set: (self: Checkbox, value: boolean) -> (),
	Toggle: (self: Checkbox) -> (),
	Destroy: (self: Checkbox) -> (),
}

local UNCHECKED_IMAGE = "rbxassetid://85391243227134"
local HOVER_IMAGE = "rbxassetid://111799388614411"

-- Replace this when you have a checked image.
local CHECKED_IMAGE = "rbxassetid://85391243227134"

function Checkbox.new(
	parent: Instance,
	text: string,
	defaultValue: boolean?,
	callback: ((boolean) -> ())?
): Checkbox

	local self = {} :: any

	self.Value = defaultValue == true

	--------------------------------------------------
	-- Container
	--------------------------------------------------

	local frame = Instance.new("Frame")
	frame.Name = "Checkbox"
	frame.Size = UDim2.fromOffset(240, 32)
	frame.BackgroundTransparency = 1
	frame.Parent = parent

	self.Frame = frame

	--------------------------------------------------
	-- Checkbox button
	--------------------------------------------------

	local button = Instance.new("ImageButton")
	button.Name = "Button"

	button.Size = UDim2.fromOffset(24, 24)
	button.Position = UDim2.fromOffset(0, 4)

	button.BackgroundTransparency = 1

	button.Image = if self.Value
		then CHECKED_IMAGE
		else UNCHECKED_IMAGE

	button.HoverImage = HOVER_IMAGE

	button.Parent = frame

	self.Button = button

	--------------------------------------------------
	-- Text
	--------------------------------------------------

	local label = Instance.new("TextLabel")
	label.Name = "Label"

	label.Position = UDim2.fromOffset(32, 0)
	label.Size = UDim2.new(1, -32, 1, 0)

	label.BackgroundTransparency = 1

	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left

	label.TextColor3 = Color3.fromRGB(255, 255, 255)

	label.Font = Enum.Font.Gotham
	label.TextSize = 16

	label.Parent = frame

	self.Label = label

	--------------------------------------------------
	-- Functions
	--------------------------------------------------

	function self:Set(value: boolean)
		self.Value = value

		button.Image = if value
			then CHECKED_IMAGE
			else UNCHECKED_IMAGE

		if callback then
			callback(value)
		end
	end

	function self:Toggle()
		self:Set(not self.Value)
	end

	function self:Destroy()
		frame:Destroy()
	end

	--------------------------------------------------
	-- Input
	--------------------------------------------------

	button.Activated:Connect(function()
		self:Toggle()
	end)

	return self
end

return Checkbox