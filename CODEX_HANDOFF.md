# Codex Handoff — Wave-Driven Objects + EditableMesh Deformation

## Read this first

Work ONLY on branch:

`water-gerstner-buoyancy-test`

Repository:

`Smurfis/RBLX-EditableMesh-Water-FirstPerson`

Also read the root `AGENTS.md` before changing code. It contains the safety rules and architectural constraints for this branch.

Do NOT merge this branch into `main`.
Do NOT modify `main`.
Do NOT delete or replace the existing working water systems.

The purpose of this branch is to prove that selected objects can use the exact same moving wave field as the current EditableMesh ocean.

---

# Objective

Build the first real water/object interaction prototype.

We want two related behaviours:

1. **Rigid buoyancy** — Parts/Models rise, fall, pitch and roll as if they are floating on the ocean.
2. **EditableMesh deformation experiment** — explicitly opted-in deformable MeshParts may have their vertices displaced by the same wave field, using cached original local-space vertices so the mesh appears to bend/conform to the ocean rather than accumulating distortion.

This is NOT ray marching.
Roblox does not expose custom GPU shaders for this purpose.
The target technique is CPU-side EditableMesh vertex deformation plus shared Gerstner/stylized wave sampling.

The immediate success condition is simple:

> Put a test object on the ocean, tag it appropriately, and make it visibly ride the exact crests and troughs that the player sees.

Then prove a separate deformable test mesh can bend with that same surface without corrupting its geometry.

---

# Existing source of truth

The current ocean renderer is:

`src/StarterPlayer/StarterPlayerScripts/Water.client.lua`

It currently contains the wave-generation constants and wave-evaluation loop inline.

The shared gameplay surface configuration is:

`src/ReplicatedStorage/Modules/WaterConfig.lua`

Do not replace the current wave character with generic textbook Gerstner waves.

The existing water is stylized and currently uses:

- deterministic `Random.new(1337)` wave directions/phases;
- up to 14 octaves;
- amplitude/frequency/speed progression;
- exponential swell shaping;
- `BASE_STEEPNESS`;
- `SWELL_BASELINE`;
- horizontal `CHOPPINESS` displacement;
- recursive warped X/Z sampling between octaves;
- distance-based octave LOD in the renderer.

The object system must match THIS wave field.

---

# Required implementation sequence

Do not turn this into one giant rewrite.

Use staged commits and keep the game runnable after each stage.

## Commit 1 — Shared wave sampler

Create:

`src/ReplicatedStorage/Modules/WaterWaveSampler.lua`

Move/refactor the deterministic wave definition and evaluation out of `Water.client.lua` into this module.

The renderer must consume the shared sampler after the refactor.

### Critical requirement

After Commit 1, the existing ocean should look visually the same as before.

Do not change coastline visuals, water colours, SurfaceAppearance behaviour, swimming, underwater visuals, footsteps, first person, far-water behaviour, or logical-region scheduling as part of this extraction.

### Shared time

The sampler must own or expose one deterministic shared time basis so the ocean renderer and floating objects cannot drift out of phase because two LocalScripts began at slightly different moments.

Suggested API:

```lua
--!strict

export type WaveSample = {
    Height: number,
    Displacement: Vector3,
    Position: Vector3,
    Normal: Vector3,
}

local WaterWaveSampler = {}

function WaterWaveSampler.GetTime(): number
    -- shared time since module initialization
end

function WaterWaveSampler.Sample(
    worldX: number,
    worldZ: number,
    time: number?,
    octaveCount: number?
): WaveSample
end

return WaterWaveSampler
```

The exact internal organization is Codex's choice, but keep the public API small and stable.

`Height` is wave displacement relative to the base surface.

Final world surface Y for gameplay is:

```lua
WaterConfig.GetSurfaceY() + sample.Height
```

### Normal calculation

A mathematically exact analytical normal is nice but not mandatory for the first prototype because the existing wave field uses recursive warped sampling.

A stable finite-difference normal is acceptable:

- sample centre;
- sample a small X offset;
- sample a small Z offset;
- form tangent vectors;
- cross them into a normalized surface normal.

Keep this deterministic and independent of camera orientation.

Avoid recursively calculating the normal when callers only need height. If useful for performance, provide a cheap height-only/internal path and a full sample path.

---

# Commit 2 — Rigid WaterInteractable prototype

Create a client controller, suggested path:

`src/StarterPlayer/StarterPlayerScripts/WaterInteractionController.client.lua`

Use `CollectionService`.

The system must be opt-in.

Tag:

`WaterInteractable`

Objects without this tag must NEVER be moved by the system.

Do not scan every Workspace descendant each frame.
Use `CollectionService:GetTagged()` once for startup and tag-added/tag-removed signals afterwards.

## Supported test targets

Support:

- a `BasePart`; or
- a `Model` with a valid `PrimaryPart`.

If a tagged Model has no `PrimaryPart`, warn once and ignore it.
Do not guess a root and do not mutate the hierarchy.

## Attributes

Support these optional Attributes on the tagged Part/Model:

```text
WaterEnabled             boolean   default true
WaterProfile             string    default SmallProp
WaterVerticalOffset      number    default 0
WaterBuoyancyStrength    number    default 1
WaterRotationStrength    number    default 1
WaterSampleCount         number    optional experimental override
WaterAllowHorizontalDrift boolean  default false
```

The system should work with only the `WaterInteractable` tag present; attributes are tuning overrides.

## First behaviour

Start with one-point height sampling.

For a tagged test Part:

- preserve its authored X/Z;
- sample the shared water at its X/Z;
- set target Y to the sampled water surface plus `WaterVerticalOffset`;
- smoothly follow target Y;
- do not teleport or jitter visibly;
- do not alter yaw.

An anchored test Part is acceptable for this local visual prototype.
Do not silently unanchor world objects.

Use frame-rate-independent smoothing.

Example principle:

```lua
local alpha = 1 - math.exp(-response * dt)
current = current:Lerp(target, alpha)
```

Do not use a fixed `Lerp(..., 0.1)` value that changes behaviour with frame rate.

---

# Commit 3 — Pitch and roll

Add wave orientation to `WaterInteractable` objects.

Preserve yaw.

The waves should produce pitch/roll only; the ocean must not randomly rotate a boat around Y.

For `SmallProp`, using the shared sampled normal is sufficient.

Blend/exaggerate with:

`WaterRotationStrength`

Expected behaviour:

- `0` = no wave rotation;
- `1` = normal surface response;
- values above `1` = deliberate stylized exaggerated rocking.

Keep rotation smoothing frame-rate independent.

Do not use the camera's LookVector to orient the object.

---

# Commit 4 — Multi-point buoyancy profiles

Add profile-driven sampling.

Starting profiles:

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

These are prototype values, not permanent balance values.

Large objects should NOT evaluate all 14 visual octaves.
Small high-frequency ripples should not violently rotate a large ship.

## Boat layout

For `Boat`, use six local sample locations around the hull/root bounding area:

```text
        BOW

   FL -------- FR
    |          |
   ML          MR
    |          |
   RL -------- RR

       STERN
```

Derive:

- average sampled height for Y;
- front-vs-rear height difference for pitch;
- left-vs-right height difference for roll;
- preserve existing yaw.

Do not horizontally drag the boat with the wave unless `WaterAllowHorizontalDrift` is explicitly enabled.

---

# Commit 5 — EditableMesh deformation experiment

Only begin this after rigid floating works and the renderer still matches the original ocean.

This is a separate opt-in mode.

Recommended tag:

`WaterDeformable`

Do not automatically deform every `WaterInteractable` MeshPart.

A deformable mesh may also be WaterInteractable, but the two behaviours must be independently controllable.

## Core rule: cache ORIGINAL local-space vertices

When the EditableMesh is created/acquired for the opted-in MeshPart, cache every original vertex position ONCE:

```lua
local originalPositions = {}

for _, vertexId in editableMesh:GetVertices() do
    originalPositions[vertexId] = editableMesh:GetPosition(vertexId)
end
```

Every update must begin from that cached original/bind position.

DO NOT read the previously deformed vertex and deform it again.

Wrong:

```text
frame 1 result
  -> deform result again
  -> deform result again
  -> accumulated corruption
```

Correct:

```text
original vertex -> deformation at t1
original vertex -> deformation at t2
original vertex -> deformation at t3
```

This prevents cumulative drift/distortion.

## Core rule: local -> world -> local

`EditableMesh:GetPosition()` / `SetPosition()` operate in mesh-local coordinates.

The wave sampler operates in world-space X/Z.

For each original local vertex:

```lua
local originalLocal = originalPositions[vertexId]

local originalWorld =
    meshPart.CFrame:PointToWorldSpace(originalLocal)

local sample = WaterWaveSampler.Sample(
    originalWorld.X,
    originalWorld.Z,
    nil,
    deformOctaves
)

local targetWorld = Vector3.new(
    originalWorld.X + sample.Displacement.X * horizontalStrength,
    baseReferenceY + originalLocal.Y + sample.Height * verticalStrength,
    originalWorld.Z + sample.Displacement.Z * horizontalStrength
)

local targetLocal =
    meshPart.CFrame:PointToObjectSpace(targetWorld)
```

Then write `targetLocal` to the vertex.

Do not feed world-space coordinates directly to `EditableMesh:SetPosition()`.
That will break as soon as the MeshPart is translated/rotated.

## Important deformation design choice

The mesh should not automatically be flattened onto sea level.

Preserve a sensible reference/bind height so the object's local form remains intact while the wave adds displacement.

For example, a floating subdivided raft should flex relative to its base pose rather than every vertex being forced directly to the absolute water Y.

Use the object's initial transform / a captured reference plane to calculate the deformation offset cleanly.

## Batch writes

Use `EditableMesh:BatchSetValues()` for vertex positions when available, matching the performance strategy already used by the ocean renderer.

Fall back to `SetPosition()` only when required.

Do not rebuild vertices/faces every frame.
Topology is created/read once; positions are updated repeatedly.

## Imported MeshParts

If using `AssetService:CreateEditableMeshAsync()` or another current Roblox API to obtain editable geometry from an existing MeshPart, verify the API against the installed/current engine expectations before committing assumptions.

Do not destroy the source MeshPart if editable allocation fails.
Warn and leave the object unchanged.

Keep this experiment isolated and reversible.

---

# Suggested deformation attributes

For `WaterDeformable` targets support sensible optional tuning such as:

```text
WaterDeformEnabled              boolean default true
WaterDeformOctaves              number  default 6
WaterDeformVerticalStrength     number  default 1
WaterDeformHorizontalStrength   number  default 0.25
WaterDeformUpdateHz             number  default 30
WaterDeformMaxDistance          number  default 250
```

Do not create dozens of required Attributes.
These are tuning overrides only.

For a raft or rigid wooden object, horizontal deformation should usually be much weaker than vertical deformation.

The intent is visually convincing flex, not rubber geometry.

---

# Test setup expectations

Do not depend on a specific existing game object name.

The user should be able to create a Part or Model in Studio and add tags/attributes manually.

## Test A — rigid floater

Create any anchored Part above/in the ocean and tag:

`WaterInteractable`

Optional:

```text
WaterProfile = SmallProp
WaterVerticalOffset = 1
WaterRotationStrength = 1
```

Expected:

- object tracks visible crest/trough timing;
- object pitches/rolls with water;
- yaw remains stable;
- removing tag stops control cleanly.

## Test B — boat-like object

Tag Model:

`WaterInteractable`

Set:

```text
WaterProfile = Boat
```

Model must have `PrimaryPart`.

Expected:

- bow can rise before stern as a wave passes;
- port/starboard height difference produces roll;
- no uncontrolled yaw spinning;
- tiny chop does not dominate large-hull motion.

## Test C — deformable subdivided mesh

Use a MeshPart with enough vertices/subdivision to visibly flex.

Tag:

`WaterDeformable`

Expected:

- vertices bend with the same wave timing as the ocean;
- rotating/translating the MeshPart does not corrupt the deformation;
- no cumulative distortion over time;
- disabling/removing tag restores or freezes cleanly according to implementation;
- untagged MeshParts remain unchanged.

---

# Performance requirements

This system is client-side visual experimentation for now.

Do not run expensive work for the entire world.

Use:

- CollectionService-maintained registries;
- update-rate profiles;
- camera/player distance culling;
- fewer octaves for large objects;
- batched vertex writes;
- cached arrays and original positions;
- no per-frame Workspace descendant scanning;
- no per-frame topology rebuilding.

For deformable meshes outside the configured maximum distance, stop deformation updates.

When they re-enter range, rebuild the current pose from ORIGINAL cached vertices and the current shared wave time so they instantly rejoin the ocean correctly rather than replaying missed frames.

---

# Network boundary

This branch is proving visual interaction.

The current ocean is client-rendered.

Do NOT add client-authoritative server gameplay or trust client buoyancy for combat/gameplay state.

Do NOT add RemoteEvents just to make the demo work.

A later design can determine which boats/objects need server-authoritative roots with local visual wave motion layered on top.

---

# Do not touch during this task

Unless compilation/runtime integration absolutely requires a tiny compatibility edit, leave these systems alone:

- `CoastlineRenderer.client.lua`;
- swimming behaviour;
- underwater visual behaviour;
- first-person controller;
- water footsteps;
- custom sounds;
- Studio-authored SurfaceAppearances;
- white intersection effect tuning;
- far-ocean visual design;
- shoreline masking/culling;
- WaterExclusion implementation;
- wakes;
- splash impulses;
- foam around floating objects;
- weather/storm profiles;
- server authority.

Do not “clean up” unrelated code while here.

---

# Acceptance criteria before stopping

Codex should consider this task successful only when the branch contains a coherent prototype meeting these checks:

1. Existing V4 ocean still renders and moves as before.
2. Renderer and water-object sampler use one shared wave definition/time source.
3. Untagged world objects remain untouched.
4. A `WaterInteractable` Part follows the same crest/trough timing visible beneath it.
5. Rotation response follows water, not camera direction.
6. Object yaw is preserved.
7. Boat profile uses multiple samples and visibly responds bow/stern + left/right.
8. A `WaterDeformable` subdivided test MeshPart can deform from cached ORIGINAL local vertices.
9. Rotating the deformable MeshPart does not cause coordinate-space distortion.
10. Vertex deformation does not accumulate frame-over-frame error.
11. Batch vertex updates are used when available.
12. Removing/disabling water tags stops object processing cleanly.
13. No Workspace-wide per-frame scan is introduced.
14. No changes are merged into `main`.

---

# When you finish

Do not merge.

Report:

- commits created;
- files added/changed;
- exact tags and attributes required for each test;
- how to create the first Studio test Part;
- how to create the first boat-style Model test;
- how to create the first subdivided `WaterDeformable` MeshPart test;
- any Roblox EditableMesh API limitation encountered;
- any visual mismatch between `Water.client.lua` and `WaterWaveSampler`;
- any performance measurements or obvious hotspots.

If the shared-sampler extraction changes the ocean visually, STOP there and explain the mismatch rather than continuing to build buoyancy on top of a broken baseline.

If EditableMesh deformation cannot be implemented safely with the current source MeshPart/runtime API, leave rigid buoyancy working, document the exact blocker, and do not destroy or rewrite the source object to force the experiment through.
