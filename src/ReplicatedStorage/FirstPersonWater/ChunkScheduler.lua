--!strict

-- Pure scheduling logic. It decides where rendering work should be spent,
-- without rotating any water geometry with the camera.

local ChunkScheduler = {}

export type LOD = "Near" | "Mid" | "Far" | "Horizon" | "Inactive"

export type Decision = {
	LOD: LOD,
	UpdateHz: number,
	Octaves: number,
}

function ChunkScheduler.Decide(
	distance: number,
	cameraFacingDot: number
): Decision
	if distance <= 160 then
		return { LOD = "Near", UpdateHz = 60, Octaves = 14 }
	end

	if distance <= 400 then
		if cameraFacingDot < -0.35 then
			return { LOD = "Mid", UpdateHz = 10, Octaves = 6 }
		end
		return { LOD = "Mid", UpdateHz = 30, Octaves = 9 }
	end

	if distance <= 800 then
		if cameraFacingDot <= 0 then
			return { LOD = "Inactive", UpdateHz = 0, Octaves = 0 }
		end
		return { LOD = "Far", UpdateHz = 15, Octaves = 5 }
	end

	if distance <= 1400 and cameraFacingDot > 0.25 then
		return { LOD = "Horizon", UpdateHz = 6, Octaves = 3 }
	end

	return { LOD = "Inactive", UpdateHz = 0, Octaves = 0 }
end

return ChunkScheduler
