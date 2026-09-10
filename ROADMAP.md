# Roadmap

Updated 10 September 2026 against `water-gerstner-buoyancy-test` through `0ca845a`. Checked items describe implemented code; live Studio visual and multiplayer acceptance remains separate. See [changelog.md](changelog.md) for commit details.

## Completed branch prototypes

- [x] Shared deterministic wave sampler used by the ocean and interacting objects (`fd8fa03`). The Gerstner experiment preserves the existing exponential swell/warped-wave maths and horizontal choppiness.
- [x] Opt-in `WaterInteractable` Parts/Models follow sampled wave height with smoothed pitch/roll and preserved heading (`d4fed6a`, `3297f41`).
- [x] SmallProp / MediumProp / Boat / LargeShip profiles, 1/3/6/8 sample points, distance culling and update throttling (`29008d9`).
- [x] Optional horizontal buoyancy drift (`7d2901a`).
- [x] Separate opt-in `WaterDeformable` EditableMesh experiment (`12269f9`).
- [x] Gentle player surface bobbing/tilt integrated with swimming (`00b5d6d`).
- [x] Player tracking on floating Parts/Models, inheriting platform movement and rotation (`a60f019`).
- [x] Stable tilt composition and suppression of double wave motion while riding (`6e2e9c6`, `44c236e`).
- [x] Five-point support detection for platform edges/corners (`eba2507`).
- [x] Spawn-effect cleanup and appearance restoration (`249e3bc`).
- [x] Animated settings panel, slider controls, compact/tappable keybind HUD, mouse-lock reticle and responsive server/title/version/FPS display (`97bbb9f` through `3f2fdca`). Settings uses `=`; free mouse uses `M`.
- [x] Remove Player Reflections; revert experimental developer tools (`6e0ef29`).
- [x] Replicated water-entry splash rings using the Studio `SplashRing` template (`0ca845a`).

## Acceptance and next checks

- [ ] Confirm ocean visual parity with the V4 baseline and camera-independent wave direction in Studio.
- [ ] Verify tagged Parts follow crest/trough timing, preserve heading and stop control on tag removal; verify untagged Parts remain unchanged.
- [ ] Retest walking at floating-platform edges/corners, jumping off and reboarding under wave motion.
- [ ] Validate deformable mesh appearance, cleanup and EditableMesh allocation failure handling in Studio.
- [ ] Validate HUD layout and input on desktop and mobile.
- [ ] Resolve/investigate Studio multiplayer graphics-memory crashes and verify splash rings across clients.

The remaining phases include longer-term architecture goals. Current buoyancy and platform riding are local visual prototypes; server-authoritative physics and full water-body/exclusion infrastructure remain future work.

## Phase 1 — Water world model

- [x] Define WaterBody volume format.
- [x] Define WaterExclusion volume format.
- [ ] Implement WaterRegistry spatial/query API in the current source tree (early architecture explored this; no current module).
- [x] Separate shared wave sampling from rendering.
- [ ] Studio authoring helper / gizmos.
- [ ] Water body debug visualization.

## Phase 2 — Stable world-aligned clipmap renderer

- [ ] Pooled near/mid/far chunks.
- [ ] Power-of-two LOD spacing (4 / 8 / 16 / 32 studs).
- [ ] Neighbor border alignment.
- [x] Camera-direction scheduling without rotating geometry in the existing single-mesh renderer.
- [x] Visible/prewarm/hidden scheduling in the existing renderer.
- [ ] EditableMesh batch-write path + fallback.
- [ ] Preserve prototype color/choppiness/foam behavior through any future clipmap refactor.

## Phase 3 — Gameplay integration

- [ ] `GetWaterAtPosition(position)` becomes the only gameplay query.
- [x] Swimming controller.
- [x] Underwater depth effects.
- [ ] Fishing hooks.
- [ ] NPC / projectile water queries.

## Phase 4 — Shorelines and masks

- [ ] Explicit exclusion volumes.
- [ ] Terrain/part shoreline sampling.
- [ ] Edge masks for water chunks.
- [ ] Avoid rendering through solid world geometry where practical.

## Phase 5 — Surface effects

- [x] Stylized wave-line/foam layer on the animated mesh.
- [x] Player-following coastline/intersection effect.
- [ ] Geometry-aware shoreline foam beyond the player-following effect.
- [ ] Splash particles on entry/exit.
- [x] Replicated expanding/fading water-entry rings.
- [ ] Simulated ripple/impulse response in the wave field.
- [ ] Wake trails for moving bodies.

## Phase 6 — Physics interaction

- [x] Wave height, displacement and normal queries.
- [x] Buoyancy sample points.
- [ ] Wave-driven forces.
- [x] Local visual floating objects driven by CFrame.
- [x] Player tracking/carry on floating objects.
- [ ] Server-authoritative buoyancy and boat physics.
- [ ] Character/object displacement splashes.

## Phase 7 — Advanced interaction

- [ ] Local disturbance field.
- [ ] Object-contact foam.
- [ ] Better clipping/shore collision treatment.
- [ ] Research mesh/shore deformation that prevents obvious water-through-object artifacts.
