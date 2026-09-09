--!strict

-- Bootstrap only. Renderer implementation will be added in Phase 2.
-- Keeping this tiny is deliberate: WaterBody/Registry/WaveMath should be
-- usable independently by gameplay systems before renderer work begins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = ReplicatedStorage:WaitForChild("FirstPersonWater")
local WaterRegistry = require(packageRoot:WaitForChild("WaterRegistry"))

print("[FirstPersonWater] client initialized")

-- Example query while developing:
-- local water = WaterRegistry.GetWaterAtPosition(workspace.CurrentCamera.CFrame.Position)
-- if water then
--     print(water.Body.Name, water.SurfaceY, water.Depth)
-- end
