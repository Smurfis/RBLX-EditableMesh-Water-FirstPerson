# Roadmap

## Phase 1 — Water world model

- [x] Define WaterBody volume format.
- [x] Define WaterExclusion volume format.
- [x] Create WaterRegistry spatial/query API.
- [x] Separate shared wave sampling from rendering.
- [ ] Studio authoring helper / gizmos.
- [ ] Water body debug visualization.

## Phase 2 — Stable world-aligned clipmap renderer

- [ ] Pooled near/mid/far chunks.
- [ ] Power-of-two LOD spacing (4 / 8 / 16 / 32 studs).
- [ ] Neighbor border alignment.
- [ ] Camera-direction scheduling without rotating geometry.
- [ ] Preload cone wider than camera FOV.
- [ ] EditableMesh batch-write path + fallback.
- [ ] Preserve prototype color/choppiness/foam behavior.

## Phase 3 — Gameplay integration

- [ ] `GetWaterAtPosition(position)` becomes the only gameplay query.
- [ ] Swimming controller.
- [ ] Underwater depth effects.
- [ ] Fishing hooks.
- [ ] NPC / projectile water queries.

## Phase 4 — Shorelines and masks

- [ ] Explicit exclusion volumes.
- [ ] Terrain/part shoreline sampling.
- [ ] Edge masks for water chunks.
- [ ] Avoid rendering through solid world geometry where practical.

## Phase 5 — Surface effects

- [ ] Wave crest foam.
- [ ] Shoreline foam.
- [ ] Splash particles on entry/exit.
- [ ] Ripple rings / impulse events.
- [ ] Wake trails for moving bodies.

## Phase 6 — Physics interaction

- [ ] Wave height and normal queries.
- [ ] Buoyancy sample points.
- [ ] Wave-driven forces.
- [ ] Floating objects.
- [ ] Character/object displacement splashes.

## Phase 7 — Advanced interaction

- [ ] Local disturbance field.
- [ ] Object-contact foam.
- [ ] Better clipping/shore collision treatment.
- [ ] Research mesh/shore deformation that prevents obvious water-through-object artifacts.
