--!strict
-- Studio-only, usable from Server or Client Command Bar to compare replicas.
-- Invoked manually or at handoff failure. No automatic impulse.
local RunService = game:GetService("RunService")
local Debug = {}

function Debug.Inspect(boat: Model)
	assert(RunService:IsStudio(), "BoatRuntimeDebug is only available in Studio")
	local root = boat:FindFirstChild("BoatRoot", true)
	assert(root and root:IsA("BasePart"), "BoatRoot BasePart/MeshPart missing")
	local parts = root:GetConnectedParts(true)
	if not table.find(parts, root) then table.insert(parts, root) end
	local anchored = {}
	print(string.format("[BoatDebug] side=%s %s mode=%s session=%s mass=%s assemblyRoot=%s reason=%s",
		if RunService:IsServer() then "Server" else "Client", boat:GetFullName(), tostring(boat:GetAttribute("BoatPhysicsMode")),
		tostring(boat:GetAttribute("BoatDynamicSession")), tostring(root.AssemblyMass),
		if root.AssemblyRootPart then root.AssemblyRootPart:GetFullName() else "nil",
		tostring(boat:GetAttribute("BoatPhysicsLastTransitionReason"))))
	if root.AssemblyMass == math.huge or root.AssemblyMass ~= root.AssemblyMass then
		warn("[BoatDebug] NON-FINITE ASSEMBLY MASS: " .. root:GetFullName())
	end
	if root.AssemblyRootPart ~= root then
		warn("[BoatDebug] UNEXPECTED ASSEMBLY ROOT: " .. root:GetFullName() .. " -> "
			.. (if root.AssemblyRootPart then root.AssemblyRootPart:GetFullName() else "nil"))
	end
	for _, part in parts do
		print(string.format("[BoatDebug] CONNECTED: %s Anchored=%s", part:GetFullName(), tostring(part.Anchored)))
		if part.Anchored then
			table.insert(anchored, part)
			warn("[BoatDebug] ANCHORED CONNECTED PART: " .. part:GetFullName())
		end
	end
	-- A disconnected/independently anchored structural part may be absent
	-- from GetConnectedParts, so also inspect the whole live boat hierarchy.
	for _, part in boat:GetDescendants() do
		if part:IsA("BasePart") and part.Anchored and not table.find(parts, part) then
			warn("[BoatDebug] ANCHORED BOAT DESCENDANT: " .. part:GetFullName())
		end
	end
	return { Root = root, Mass = root.AssemblyMass, ConnectedParts = parts, AnchoredParts = anchored }
end

function Debug.TestImpulse(boat: Model, deltaSpeed: number?)
	local report = Debug.Inspect(boat)
	local root = report.Root
	assert(boat:GetAttribute("BoatPhysicsMode") == "DYNAMIC_DRIVING", "boat is not in dynamic driving state")
	assert(not root.Anchored and #report.AnchoredParts == 0, "connected assembly is anchored")
	assert(report.Mass > 0 and report.Mass < math.huge, "assembly mass is not finite")
	local speed = deltaSpeed or 50
	assert(speed > 0 and speed <= 50, "test delta speed must be in (0, 50]")
	local before = root.AssemblyLinearVelocity
	root:ApplyImpulse(root.CFrame.LookVector * report.Mass * speed)
	-- Allow the driver-owned result to reach the server diagnostic.
	task.wait(0.2)
	local after = root.AssemblyLinearVelocity
	local changed = (after - before).Magnitude > 0.01
	print(string.format("[BoatDebug] IMPULSE velocity before=%s after=%s changed=%s", tostring(before), tostring(after), tostring(changed)))
	if not changed then warn("[BoatDebug] IMPULSE FAILED: velocity did not change; inspect ownership and constraints") end
	return changed
end

return Debug
