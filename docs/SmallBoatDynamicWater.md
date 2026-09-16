# SmallBoat physical flotation milestone

The user confirmed the physical flotation milestone passed in Studio, including
mounting, six-point buoyancy and working helm/hand IK. Physical propulsion and
yaw steering are now implemented and ready for a Studio driving test.
No live Studio runtime is connected to this workspace session.

## Physical propulsion

### Runtime anchoring diagnostic

The reported live failure was an anchored BoatRoot/BoatRail/thwarts/ControllerSeat
assembly with infinite mass. Repository writes affecting boat Anchored state are
in BoatDynamicAuthority: parked-state restoration, root replacement recovery,
and dynamic release. Other repository Anchored writes target VFX/separate props.
Studio-managed scripts are not inspectable from this coding session.

The release transaction now waits for an assembly update after unanchoring before
validating finite mass/driver ownership. It briefly retries stale mass/root data
instead of immediately restoring every saved anchor on the same frame. Every
boat descendant BasePart is released, including nested BoatRail and later-added
structure. While dynamic, anchor guards reject subsequent anchoring of boat-owned
parts; intentional parking ends that guard first. Welds and external connected
character/world parts are never rewritten. An external anchored connection fails
validation rather than unanchoring unrelated geometry.

This addresses code-level release/anchor hazards; it does **not** prove which
gate failed in the reported live session. The Studio logs now expose:

- `BLOCKED`: exact missing opt-in, live hierarchy, BoatRoot or BoatSeat requirement;
- `WAITING`: missing/invalid occupant or client Ready not received;
- `READY REJECTED`: driver/session or occupant validation failed;
- `BEFORE UNANCHOR`, `AFTER UNANCHOR`, `ACTIVE`: exact live boat/root paths,
  root Anchored/mass and enumeration of any remaining anchored descendants;
- `PARK` or recovery reason if a later transition deliberately restores anchors.

Check `BoatPhysicsLastTransitionReason` on **Workspace.Boats.Boat**. Do not use
template inspection as evidence that this live instance has been released.

Run this in Studio's Server Command Bar and, if needed, Client Command Bar to
compare replicas (the output names which side it inspected):

```lua
require(game.ReplicatedStorage.Modules.BoatRuntimeDebug).Inspect(workspace.Boats.Boat)
```

It reports mass/assembly root and every connected part; warnings identify
infinite mass, an unexpected assembly root, anchored connected parts and
anchored descendants omitted from the connected graph. Once it reports
`DYNAMIC_DRIVING`, no anchored connections and finite mass, run the explicitly
requested impulse smoke test in an open area of the test place:

```lua
require(game.ReplicatedStorage.Modules.BoatRuntimeDebug).TestImpulse(workspace.Boats.Boat, 50)
```

The helper applies the impulse only when invoked manually and reports observed
velocity before/after; it never applies an automatic test impulse during play.
These helpers assert Studio context and add no production update loop.
If Server says unanchored but Client still reports BoatRail anchored, inspect
Studio-only/client scripts or synchronization: the server cannot observe a
client-only Anchored write. Propulsion and buoyancy remain unchanged in this fix.

Automated coverage includes stale assembly mass during release, nested anchored
BoatRail/thwarts/ControllerSeat, re-anchoring, late-added structure, finite mass
and diagnostic inspection. Live mass/impulse verification is still required.

`BoatPropulsion` is a helper called by the existing WaterInteractionController
dynamic lifecycle. It has no update loop, input bindings, water sampler or
ownership logic. The controller's additions are creation/update/cleanup hooks;
its buoyancy calculation, six samples and hull-up alignment remain intact.

- The authorized driver must be in `DYNAMIC_DRIVING`, with an unanchored hull.
  Preparation and parked states apply no thrust or steering torque.
- The existing BoatSeat supplies ThrottleFloat and SteerFloat. The helm script
  and IK retain the same input and targets. No keyboard input is duplicated.
- A separate centre-of-mass VectorForce provides horizontal, hull-relative
  thrust and drag. It never supplies vertical force or overwrites velocity.
- A Torque constraint steers about the same effective up axis as buoyancy.
  Existing hull-up alignment remains unchanged. Positive steering turns right;
  reverse travel reverses rudder response. Low-speed authority is reduced.
- Throttle/steer ramp exponentially. Forward thrust tapers near the configured
  speed limit; reverse is weaker/slower by default. Longitudinal drag and lateral
  resistance reduce coasting/slip progressively. Yaw-rate feedback damps turning.
- The existing dynamic attachment is reused. Force and torque are created once
  per activation and destroyed by existing exit/failure cleanup.
- No PivotTo, Position/CFrame movement, velocity writes, TweenService, new
  update connection or new ownership remote was introduced by propulsion.

### Tuning

BoatConfig defaults apply only when model attributes are absent. Existing
waterline/rotation attributes are unaffected; BoatConfig's old water settings
are not consumed by propulsion.

| Existing/model attribute | Default | Meaning |
| --- | ---: | --- |
| ForwardAcceleration / ReverseAcceleration | 32 / 14 | Maximum thrust acceleration |
| MaxForwardSpeed / MaxReverseSpeed | 42 / 16 | Thrust taper speeds, studs/sec |
| ForwardDrag / IdleDrag | 0.18 / 1.2 | Longitudinal drag while powered/coasting |
| SideCatch | 2.4 | Lateral resistance |
| MaxHorizontalSpeed | 48 | Additional overspeed resistance threshold |
| SpeedGainLimit | 48 | Maximum commanded horizontal acceleration |
| TurnRate | 0.733 radians/sec | Maximum requested yaw rate (42 degrees/sec) |
| DriveResponse | 2.5 | Throttle response per second |
| SteeringResponse | 3 | Steering-input and yaw-rate response per second |
| SteeringStrength | 1.2 | Maximum yaw acceleration, radians/sec squared |
| SteeringFullAuthoritySpeed | 12 | Speed at full rudder authority |
| MinimumSteeringAuthority | 0.08 | Stationary rudder authority |

Speed limits use physical resistance and thrust taper, not hard velocity clamps;
collisions/external forces may temporarily exceed them. Steering uses a hull-box
inertia estimate, so real model mass distribution may need tuning.

### Driving validation

Automated tests passed for forward/reverse ramp, coasting drag, overspeed
resistance, yaw direction, reverse/low-speed steering, hull-relative thrust,
lateral catch, frame-rate response and cleanup. Existing authority, six-sample
flotation, no-PivotTo-during-driving and ten re-entry tests also passed.

Studio checks still required for the new propulsion: W/S movement; A/D yaw with
wheel and hands following; wave following and pitch/roll through a turn; coasting;
and mount-drive-dismount-remount. Enable BoatPhysicsDebug to compare local input
with helm diagnostics; BoatConsumedSteerFloat/BoatConsumedThrottleFloat record
the values consumed locally. Stop if the already-verified flotation or IK regresses.

## Setup

On the existing boat Model directly under `Workspace.Boats`:

- Keep the `WaterInteractable` tag.
- Set `WaterProfile = "Boat"` and `WaterDynamicPhysics = true`.
- Keep `WaterEnabled` enabled/absent.
- Preserve your existing `WaterVerticalOffset` and `WaterRotationStrength`.
  Earlier values of 4.5 and 0.4 are context, not enforced defaults.
- Keep the descendant `BoatRoot` MeshPart and the existing `BoatSeat`
  VehicleSeat rigidly connected. No model hierarchy rewrite is required.
- Set `BoatPhysicsDebug = true` temporarily for one diagnostic line per second.

`BoatRoot.Size`, `BoatRoot.CFrame` and `BoatRoot.Position` exclusively define
the six-point hull footprint, parked and physical. Model extents, helm, sail
and passenger seats do not define that footprint. Other prop profiles retain
their existing sampling and kinematic path.

## Ownership flow

1. **KINEMATIC_IDLE:** the hull is anchored; WaterInteractionController runs
   its existing kinematic wave following. Original anchor settings of other
   parts are preserved, including the helm's free part.
2. **DYNAMIC_PREPARING:** the exact BoatSeat occupant is validated. The local
   driver samples water and creates one attachment, one central VectorForce
   and one AlignOrientation before sending readiness. The boat stays anchored
   until that message is accepted. Missing client initialization leaves it safe.
3. **DYNAMIC_DRIVING:** the server validates the same driver/session/seat/root,
   unanchors the boat and assigns assembly ownership. The driver updates
   physical flotation before simulation. Every client's kinematic path yields.
4. **Exit:** the server revokes ownership and anchors the hull. Local helpers
   are destroyed. Kinematic state resumes from the current position/heading.
5. **Recovery:** a missing client heartbeat (3 seconds), ownership loss,
   helper failure or a fall 40 studs below the configured base surface parks
   the boat and restores its saved pre-release pivot. Re-entry is required
   after a failure; repeated readiness cannot restart the failed session.

`ReplicatedStorage.BoatDynamicReady` carries session-bound Ready/Alive/Stop
notifications only. Clients cannot nominate roots, owners, water heights or
recovery transforms. The server samples no waves and performs no water raycasts.

## Design choices

- `BoatDynamicAuthority` is a small server module called by the existing helm
  script. This keeps handoff/failure logic separate from wheel presentation;
  it is not a vehicle framework. It creates/reuses one dedicated RemoteEvent.
- The existing `sampleObject` uses six Boat samples and the existing shared
  WaterWaveSampler time. Both modes compute
  `WaterConfig.GetSurfaceY() + averageHeight * WaterBuoyancyStrength + WaterVerticalOffset`.
  This also repairs the earlier wrapper migration that accidentally discarded
  the six-sample height average in favour of a centre sample.
- Dynamic normals use world-space tangents between those same samples. Hull
  tilt is not added a second time to the sampled water normal.
- AlignOrientation aligns only the hull-up axis. Yaw remains free, so later
  steering torque will not fight a cached heading. The propulsion helper now
  supplies yaw damping and thrust separately.
- [Anchored AssemblyMass is infinite](https://create.roblox.com/docs/physics/assemblies).
  Preparation uses a finite connected-part
  mass estimate; physical updates use actual AssemblyMass once released.
  Brief handoff latency remains a Studio test concern.
- The old independent BoatMovementController is an empty compatibility script
  so Rojo also replaces stale Studio copies. Its previous source is archived
  outside mapped source at `docs/reference/BoatMovementController.previous.luau`.
- The previously added OceanSurface module is untouched because swimming
  references it. Boat flotation does not depend on it or create another wrapper.

## Defaults and staged validation

Only absent attributes use these defaults:

| Attribute | Default |
| --- | ---: |
| BoatBuoyancyStiffness | 14 |
| BoatBuoyancyDamping | 7.5 |
| BoatMaxLiftMultiplier | 2.5 |

In Studio, test these stages in order. Do not continue if helm/IK breaks.

1. Parked boat: confirm six-point bob/tilt at the previous waterline.
2. Neutral lift: temporarily set stiffness/damping to 0 and rotation strength
   to 0 before entering the seat. Confirm no rapid gravity-driven fall. A small
   inherited vertical velocity can persist with damping disabled. Restore the
   original rotation strength and remove the two temporary overrides afterward.
3. Spring and wave tilt: with defaults restored, sit still for 60 seconds;
   check targetY/rootY/forceY and current network owner on the server.
4. A/D: wheel rotation and both hand targets must behave exactly as before.
   W/S and steer appear in diagnostics and now feed the propulsion helper.
5. Exit/re-enter ten times; verify parked recovery, no duplicate helpers,
   correct seated look behaviour and ordinary swimming after entering water.
6. Controlled failure in a test session: disable BoatDynamicBuoyancyForce;
   confirm recovery and the failure diagnostic. Test a second client observing
   the driven boat, and repeat with camera far away or no current camera.

## Validation results

Automated tests execute actual controller/module source with mocked services:

- ready-before-release and invalid driver/session/model rejection;
- disconnected seat rejection, duplicate Ready and stale-message handling;
- ten ownership handoffs and ten local helper lifecycles;
- timeout, abyss, ownership loss, helper failure and tag-removal recovery;
- six BoatRoot samples with rotated/translated hull; no Model:GetExtentsSize;
- averaged height/strength/offset formula in kinematic mode;
- finite preparation force and physical spring/gravity force independent of thrust;
- physical sampling without a camera and no concurrent PivotTo;
- cleanup and resuming from the current X/Z after exit.

Run `tests/RunBoatDynamicTests.ps1 -LuauPath <path-to-luau.exe>`.
These are lifecycle/math tests, not a Roblox physics simulator.

**Studio status:** the user reported the flotation milestone passed. New
propulsion handling and continued helm/IK/wave behaviour while driving still
need runtime verification; automated mocks cannot establish those results.
Client ownership also retains
Roblox's usual trust limitations; this prototype adds no authoritative racing,
damage or progression decisions.
