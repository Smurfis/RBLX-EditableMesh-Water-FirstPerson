--!strict

local CollectionService = game:GetService("CollectionService")

local WaterConfig = require(script.Parent.WaterConfig)
local WaterBody = require(script.Parent.WaterBody)

type WaterBodyRecord = WaterBody.WaterBody

export type WaterQuery = {
	Body: BasePart,
	SurfaceY: number,
	BottomY: number,
	Depth: number,
	Priority: number,
	WaveScale: number,
	WaveHeightScale: number,
}

local WaterRegistry = {}

local bodies: { [BasePart]: WaterBodyRecord } = {}
local exclusions: { [BasePart]: true } = {}

local function addBody(instance: Instance)
	if instance:IsA("BasePart") then
		bodies[instance] = WaterBody.fromPart(instance)
	end
end

local function removeBody(instance: Instance)
	if instance:IsA("BasePart") then
		bodies[instance] = nil
	end
end

local function addExclusion(instance: Instance)
	if instance:IsA("BasePart") then
		exclusions[instance] = true
	end
end

local function removeExclusion(instance: Instance)
	if instance:IsA("BasePart") then
		exclusions[instance] = nil
	end
end

local function pointInsidePartXZ(part: BasePart, worldPosition: Vector3): boolean
	local localPosition = part.CFrame:PointToObjectSpace(worldPosition)
	local half = part.Size * 0.5

	return math.abs(localPosition.X) <= half.X
		and math.abs(localPosition.Z) <= half.Z
end

local function excludedAt(worldPosition: Vector3, surfaceY: number): boolean
	for part in exclusions do
		if not part.Parent then
			exclusions[part] = nil
			continue
		end

		if pointInsidePartXZ(part, worldPosition) then
			local halfY = part.Size.Y * 0.5
			local topY = part.Position.Y + halfY
			local bottomY = part.Position.Y - halfY

			if surfaceY >= bottomY and surfaceY <= topY then
				return true
			end
		end
	end

	return false
end

function WaterRegistry.Refresh()
	table.clear(bodies)
	table.clear(exclusions)

	for _, instance in CollectionService:GetTagged(WaterConfig.Tags.WaterBody) do
		addBody(instance)
	end

	for _, instance in CollectionService:GetTagged(WaterConfig.Tags.WaterExclusion) do
		addExclusion(instance)
	end
end

function WaterRegistry.GetWaterAtPosition(worldPosition: Vector3): WaterQuery?
	local best: WaterBodyRecord? = nil

	for part, body in bodies do
		if not part.Parent then
			bodies[part] = nil
			continue
		end

		body = WaterBody.fromPart(part)
		bodies[part] = body

		if not WaterBody.containsXZ(body, worldPosition) then
			continue
		end

		if excludedAt(worldPosition, body.SurfaceY) then
			continue
		end

		if best == nil or body.Priority > best.Priority then
			best = body
		end
	end

	if best == nil then
		return nil
	end

	return {
		Body = best.Part,
		SurfaceY = best.SurfaceY,
		BottomY = best.BottomY,
		Depth = best.SurfaceY - best.BottomY,
		Priority = best.Priority,
		WaveScale = best.WaveScale,
		WaveHeightScale = best.WaveHeightScale,
	}
end

function WaterRegistry.IsPointSubmerged(worldPosition: Vector3): boolean
	local result = WaterRegistry.GetWaterAtPosition(worldPosition)
	if result == nil then
		return false
	end

	return worldPosition.Y <= result.SurfaceY
		and worldPosition.Y >= result.BottomY
end

WaterRegistry.Refresh()

CollectionService:GetInstanceAddedSignal(WaterConfig.Tags.WaterBody):Connect(addBody)
CollectionService:GetInstanceRemovedSignal(WaterConfig.Tags.WaterBody):Connect(removeBody)
CollectionService:GetInstanceAddedSignal(WaterConfig.Tags.WaterExclusion):Connect(addExclusion)
CollectionService:GetInstanceRemovedSignal(WaterConfig.Tags.WaterExclusion):Connect(removeExclusion)

return WaterRegistry
