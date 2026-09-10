--!strict

-- Client-local handoff: swimming owns physics and eligibility; the wave
-- controller supplies a bounded surface offset. No attributes/replication
-- are needed for per-frame communication.
return {
	Root = nil :: BasePart?,
	SurfaceHold = false,
	Offset = 0,
}
