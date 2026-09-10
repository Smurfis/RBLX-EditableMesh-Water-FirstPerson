# Codex Instructions — Gerstner Wave Buoyancy Test

These instructions apply to the `water-gerstner-buoyancy-test` branch of `Smurfis/RBLX-EditableMesh-Water-FirstPerson`.

## Safety rule

Do not make experimental Gerstner/buoyancy changes directly on `main`.

The branch was created from known-good commit:

`b45789ee584e2605a477848976cfee5b3c75e8fb`

The current water appearance is a working visual baseline. Preserve it unless a task explicitly says to alter the look.

Do not delete or replace the existing ocean renderer, coastline effect, swimming controller, underwater controller, first-person controller, water footsteps, Studio-managed water assets, or sound assets as part of this experiment.

Keep changes small and reversible. Prefer one architectural change per commit. If a refactor is required, the first refactor milestone must produce an ocean that is visually indistinguishable from the current V4 baseline.

## Current renderer facts that must be preserved

The current main renderer is:

`src/StarterPlayer/StarterPlayerScripts/Water.client.lua`

It currently owns both rendering and the shared mathematical wave definition. Important current behaviour includes:

- one continuous EditableMesh;
- 5 x 5 logical regions;
- 91 x 91 vertices / 8,281 vertices;
- deterministic seeded wave field;
- maximum 14 octaves;
- exponential swell shaping;
- horizontal choppy displacement;
- recursive/warped sampling between octaves;
- camera-based visible/prewarm/hidden update scheduling;
- distance-based visual octave LOD;
- adaptive quality;
- world-locked treadmill motion;
- world-locked overlay UVs;
- four rendered water layers sharing the same EditableMesh;
- separate flat far-water coverage;
- underwater update throttling/freezing.

Do not casually simplify these systems while implementing buoyancy.

## Goal

Make selected Roblox objects behave as though they are physically resting on the exact same animated ocean that the EditableMesh displays.

The immediate test goal is intentionally small:

1. Extract the current wave field into a shared deterministic ModuleScript without changing the rendered water appearance.
2. Allow another LocalScript to query the wave surface at arbitrary world X/Z positions.
3. Make explicitly opted-in test Parts/Models follow the sampled surface height.
4. Make opted-in test objects pitch and roll with the large wave shape.
5. Leave all ordinary world geometry completely unaffected by default.

This is a visual/gameplay buoyancy prototype, not a full fluid simulation.

## Required opt-in behaviour

Water interaction must be opt-in.

Do NOT add an `Immovable` attribute to every static object in the world.

Ordinary Parts, MeshParts, Models, terrain/buildings and props with no water-interaction marker must remain untouched.

Use CollectionService tag:

`WaterInteractable`

Recommended optional Attributes on the tagged Instance:

- `WaterProfile` string — default `SmallProp`;
- `WaterBuoyancyStrength` number — default `1`;
- `WaterRotationStrength` number — default `1`;
- `WaterVerticalOffset` number — default `0`;
- `WaterEnabled` boolean — default `true` if absent;
- `WaterSampleCount` number — optional override for experiments.

A tagged Model should use its `PrimaryPart` as the controlled root. If it has no PrimaryPart, warn once and ignore it rather than guessing destructively.

## Shared wave module

Create a shared ModuleScript under:

`src/ReplicatedStorage/Modules/`

Suggested name:

`WaterWaveSampler.lua`

The module must own the deterministic wave definitions that are currently duplicated/embedded in `Water.client.lua`.

The renderer and buoyancy controller must consume the same wave data rather than independently re-creating similar-looking waves.

The shared module should be deterministic per client and should own a single shared time origin so the renderer and interacting objects cannot drift out of phase because separate scripts started at slightly different times.

Suggested public API shape:

```lua
export type WaveSample = {
    Height: number,
    Displacement: Vector3,
    Position: Vector3,
    Normal: Vector3,
}

WaterWaveSampler.GetTime(): number

WaterWaveSampler.Sample(
    worldX: number,
    worldZ: number,
    time: number?,
    octaveCount: number?
): WaveSample
```

The exact names can change if there is a strong reason, but keep the API small and clear.

`Position.Y` / `Height` should represent displacement relative to the base water surface. The caller can add `WaterConfig.GetSurfaceY()`.

The returned horizontal displacement must use the same choppiness calculation as the rendered mesh.

## Preserve the exact current wave character

The first extraction must preserve the current constants and seeded wave construction from `Water.client.lua`, including the current values for maximum octaves, amplitude/frequency/speed progression, base steepness, swell baseline, choppiness, and random seed.

Do not replace the current wave field with a generic textbook Gerstner implementation merely because the task uses the name Gerstner. The current renderer has a stylized exponential swell/warped-wave implementation and the floating objects need to match the ocean the player actually sees.

The branch can later evolve the maths, but first get one source of truth.

## Normal / orientation

The first buoyancy milestone does not require a mathematically perfect analytical normal for every recursive warped octave.

A stable finite-difference surface normal is acceptable for the buoyancy prototype if it uses the same shared sampler. For example, sample the surface a small distance to the right and forward and derive a normal from those points.

Do not use camera orientation to determine the water normal.

For large objects, prefer multiple object-space sample positions over one centre normal.

## Buoyancy profiles

Create a simple profile table in the buoyancy controller or a small shared config module.

Recommended starting profiles:

```lua
SmallProp = {
    SampleCount = 1,
    Octaves = 8,
    UpdateHz = 30,
}

MediumProp = {
    SampleCount = 3,
    Octaves = 8,
    UpdateHz = 30,
}

Boat = {
    SampleCount = 6,
    Octaves = 6,
    UpdateHz = 30,
}

LargeShip = {
    SampleCount = 8,
    Octaves = 4,
    UpdateHz = 20,
}
```

These are starting values, not permanent balance values.

Do not evaluate all 14 visual octaves for every large floating object. Large hulls should primarily react to large/medium swells, not microscopic visual chop.

## First test object

The first test should support a normal anchored or controlled Part tagged `WaterInteractable` with:

`WaterProfile = "SmallProp"`

The object should visibly rise and fall with the same water surface under it.

Then add orientation support.

The implementation must not automatically modify every anchored Part in Workspace.

For the prototype, it is acceptable for the buoyancy controller to drive a test object's CFrame directly if this is clearly isolated to `WaterInteractable` objects. Do not silently unanchor unrelated instances.

If a test object is anchored and intentionally controlled by this visual buoyancy system, preserve its original X/Z location while updating sampled Y and orientation unless the profile explicitly allows horizontal drift.

## Boat sampling

For the first boat profile, use six hull samples rather than sampling every point on the hull:

```text
        bow

   FL -------- FR
    |          |
   ML          MR
    |          |
   RL -------- RR

       stern
```

Use the sampled heights to derive average vertical placement, front-vs-rear pitch, and left-vs-right roll.

Do not make a boat react to all tiny visual octaves.

Do not introduce uncontrolled yaw from the wave normal. The boat's existing heading should remain its heading unless propulsion/gameplay code changes it.

## Smoothing

Avoid hard snapping visible objects to the sampled surface.

Use frame-rate-independent smoothing for vertical position and rotation. The object should chase the target wave pose rather than teleporting each update.

Expose or centralise reasonable tuning values so visual exaggeration can be adjusted later.

We may deliberately use `WaterRotationStrength > 1` on showcase objects to exaggerate pitch/roll while keeping the actual water unchanged.

## Network / authority boundary

The current water is client-rendered. Treat this first buoyancy implementation as a local visual prototype.

Do not move server-authoritative gameplay objects from a LocalScript and then assume the server agrees with their position.

Do not add RemoteEvents or client-authoritative damage/gameplay decisions merely to demonstrate floating.

When this prototype is visually approved, server/gameplay authority can be designed separately.

## Water surface and WaterConfig

The current gameplay base surface comes from:

`ReplicatedStorage.Modules.WaterConfig.GetSurfaceY()`

For this prototype:

`finalSurfaceY = WaterConfig.GetSurfaceY() + sample.Height`

Do not rewrite swimming/underwater behaviour to use moving crests in the same commit as the first buoyancy experiment.

That integration is a later milestone.

## Culling / scalability expectations

Do not scan all Workspace descendants every frame.

Use CollectionService tag signals to maintain a compact set of active `WaterInteractable` objects.

Distance-cull or reduce update frequency for objects that are far from the local camera/player.

The first test can be conservative, but structure it so hundreds of unrelated world instances do not cause work.

Do not perform per-frame raycasts for every EditableMesh vertex.

Water-render exclusion/culling under terrain/buildings is a separate system from buoyancy and should not be mixed into the first floating-object commit.

## Existing coastline / white-line effect

Do not modify `CoastlineRenderer.client.lua` as part of the first Gerstner buoyancy extraction unless explicitly requested.

The current player-following white intersection effect is visually valuable and should remain an independent VFX system during this experiment.

Do not attempt to make the object-contact foam system at the same time as first buoyancy. First prove that objects follow the wave surface correctly; contact foam/wakes come afterwards.

## Suggested implementation sequence

Commit 1: shared wave source

- add `WaterWaveSampler.lua`;
- move/reproduce the current deterministic wave generation there;
- modify `Water.client.lua` to consume it;
- verify the ocean looks the same as before.

Commit 2: one-point floating object

- add a client buoyancy/interactor controller;
- track only `WaterInteractable` tags;
- one-point height sampling;
- smooth Y response;
- no rotation yet if that helps isolate correctness.

Commit 3: surface orientation

- add stable normal/pitch/roll support;
- preserve object yaw;
- expose rotation strength.

Commit 4: profile sampling

- add SmallProp / MediumProp / Boat / LargeShip profiles;
- add 3/6/8-point sampling where appropriate;
- add distance/update-rate throttling.

Do not combine all four milestones into one giant unreviewable rewrite if avoidable.

## Acceptance checks

Before considering the first prototype successful, verify all of the following:

- the ocean still visually matches the current V4 baseline;
- changing camera pitch does not rotate the wave field;
- the wave sampler and renderer remain phase-aligned;
- an untagged Part remains completely unchanged;
- a `WaterInteractable` test Part rises/falls at the correct crest/trough timing;
- enabling rotation makes the object lean with the local water surface rather than with the camera;
- object yaw is preserved;
- removing the `WaterInteractable` tag stops water control cleanly;
- no Workspace-wide per-frame descendant scan was introduced;
- no changes were made to `main` while testing.

## Future work — explicitly not part of the first prototype

After floating objects are working, later tasks may add:

- moving gameplay surface queries for swimming/camera;
- server-authoritative buoyancy where necessary;
- hull displacement;
- boat wakes;
- object-contact foam;
- splash impulses;
- local disturbance/ripple fields;
- `WaterExclusion` rendering masks under terrain/buildings;
- interior water suppression;
- storm-dependent wave profiles;
- whirlpools/currents.

Keep those systems separate from the first proof that an object can accurately ride the existing animated ocean.
