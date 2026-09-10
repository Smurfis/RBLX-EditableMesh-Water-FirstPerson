# Player wave motion experiment

`PlayerWaveMotionController.client.lua` adds local surface bobbing and body
tilt automatically. No character tags or attributes are required. The existing
swimming controller owns velocity; the new controller supplies a smoothed offset
through the client-local `PlayerWaveMotionState` module. Swimming applies that
offset to its surface band, entry/exit and buoyancy calculations consistently.

The new controller samples the existing `WaterWaveSampler` at most 30 times per
second during airborne surface hold, using six octaves. Interpolation runs per
simulation frame. There are no world scans, raycasts, new forces, or per-frame
attribute writes. Root-joint discovery scans only the character at spawn.

Defaults in `WaterConfig.PlayerWaveMotion`:

| Setting | Value | Purpose |
| --- | --- | --- |
| Enabled | true | Enable the experiment |
| Octaves | 6 | Filter high-frequency chop |
| SampleHz | 30 | Maximum wave sampling rate |
| HeightStrength | 0.3 | Scale sampled height |
| MaxHeight | 0.35 | Maximum bob offset in studs, either direction |
| MaxOffsetSpeed | 0.75 | Limit offset changes in studs/second |
| Response | 5 | Frame-rate-independent smoothing response |
| TiltStrength | 0.35 | Scale surface tilt |
| MaxTiltDegrees | 6 | Limit pitch and roll independently |

To disable temporarily during Play, set the Boolean attribute
`PlayerWaveMotionEnabled` to `false` on the local **Player** instance. This
fades out the response. Set it to `true` or remove it to re-enable. For subsequent
sessions, set `WaterConfig.PlayerWaveMotion.Enabled = false` in source.

## Studio checks

1. Rojo sync this branch and start a fresh Play session. Float at the surface
   without pressing Space or diving. Expect gentle bobbing and body rocking.
2. Turn in place: heading stays under player control; tilt follows the water.
3. Swim forward, jump, deliberately dive, surface again, and walk onto land.
   Wave response should fade out when surface hold is no longer active.
4. Toggle the Player attribute to compare, then respawn to check cleanup.
5. Check the foam and underwater transitions while bobbing. Their existing
   world-height thresholds still apply; this is a conservative motion test.

This is filtered player motion, not exact full-amplitude crest attachment. It
does not implement carrying passengers standing on moving test Parts. Body tilt
supports the existing R6/R15 Motor6D root joint; rigs without that joint still
receive the swimming offset. The controller adds no camera roll or root rotation.

## Automated checks

With the official Luau CLI available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/RunPlayerWaveMotionTests.ps1 -LuauPath C:\path\to\luau.exe
```

The fixture executes the actual controller/config with mocked services and joints.
It covers sample limits, response at 30/60/144 FPS, bob/tilt caps, non-accumulating
joint offsets, dry/seated/inactive behavior, disable, death, respawn, and cleanup.
It does not simulate Roblox physics, animation scheduling, or rendering. Those
checks require Studio. Joint composition follows Roblox's documented
[Motor6D timing](https://create.roblox.com/docs/reference/engine/classes/Motor6D/Transform).
