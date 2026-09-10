--StarterPlayerScripts, HorizonController.client.lua

local Lighting = game:GetService("Lighting")

local atmosphere =
	Lighting:FindFirstChildOfClass("Atmosphere")

if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end

atmosphere.Density = 0.32
atmosphere.Offset = 0.1
atmosphere.Haze = 2.2
atmosphere.Glare = 0.05

atmosphere.Color =
	Color3.fromRGB(
		150,
		190,
		215
	)

atmosphere.Decay =
	Color3.fromRGB(
		80,
		120,
		150
	)