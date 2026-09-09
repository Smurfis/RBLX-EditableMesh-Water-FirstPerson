--!strict

export type WaterBody = {
	Part: BasePart,
	Priority: number,
	WaveScale: number,
	WaveHeightScale: number,
	SurfaceY: number,
	BottomY: number,
}

local WaterBody = {}

local function numberAttribute(part: BasePart, name: string, fallback: number): number
	local value = part:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return fallback
end

function WaterBody.fromPart(part: BasePart): WaterBody
	local halfHeight = part.Size.Y * 0.5
	local surfaceY = part.Position.Y + halfHeight
	local bottomY = part.Position.Y - halfHeight

	return {
		Part = part,
		Priority = numberAttribute(part, "Priority", 0),
		WaveScale = numberAttribute(part, "WaveScale", 1),
		WaveHeightScale = numberAttribute(part, "WaveHeightScale", 1),
		SurfaceY = surfaceY,
		BottomY = bottomY,
	}
end

function WaterBody.containsXZ(body: WaterBody, worldPosition: Vector3): boolean
	local localPosition = body.Part.CFrame:PointToObjectSpace(worldPosition)
	local half = body.Part.Size * 0.5

	return math.abs(localPosition.X) <= half.X
		and math.abs(localPosition.Z) <= half.Z
end

function WaterBody.containsPoint(body: WaterBody, worldPosition: Vector3): boolean
	if not WaterBody.containsXZ(body, worldPosition) then
		return false
	end

	return worldPosition.Y <= body.SurfaceY
		and worldPosition.Y >= body.BottomY
end

return WaterBody
