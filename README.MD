# RBLX First Person Water

A performance-focused first-person water system for Roblox built around **world-space water bodies**, **world-aligned chunk LOD**, and a shared deterministic wave field.

## Core rule

**The camera decides where rendering work is spent; the camera does not rotate the water itself.**

The high-detail surface stays world-aligned and visually stable. Camera direction only prioritizes mid/far chunks, chooses LOD, and changes update frequency.

## Goals

- Oceans, lakes, raised pools and lowered pools at different Y levels.
- Explicit water depth per body.
- Dry/exclusion volumes for caves, docks, interiors and terrain cut-outs.
- Stable first-person rendering using pooled world-aligned EditableMesh chunks.
- Shared water queries for swimming, underwater camera, fishing and NPC/gameplay systems.
- Foam, splashes, ripples and shoreline awareness.
- Buoyancy and wave-driven object interaction.
- Eventually local disturbances/wakes and better interaction around world geometry.

## Proposed world authoring

Create invisible Parts and tag them with `WaterBody` using CollectionService.

- X/Z size = footprint.
- Top face = surface height.
- Part height = water depth.
- `Priority` resolves overlapping water bodies.
- `WaveScale` / `WaveHeightScale` customize each body.

Create Parts tagged `WaterExclusion` to cut dry areas out of a water body.

## Project layout

```text
src/
├── ReplicatedStorage/
│   └── FirstPersonWater/
│       ├── WaterConfig.lua
│       ├── WaterBody.lua
│       ├── WaterRegistry.lua
│       ├── WaveMath.lua
│       └── ChunkScheduler.lua
└── StarterPlayer/
    └── StarterPlayerScripts/
        └── FirstPersonWater/
            └── WaterClient.client.lua
```

## Roadmap

See [ROADMAP.md](ROADMAP.md).
