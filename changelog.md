# Changelog — RBLX EditableMesh Water First Person

Reconstructed development log for 9–10 September 2026 from the Git history of `Smurfis/RBLX-EditableMesh-Water-FirstPerson`, plus documented Studio-side changes.

The repository itself begins on 9 September 2026. Experiments before the first commit are not represented in Git history.

## Project Origin

This project began as an experiment based on a Roblox water tutorial:

<https://www.youtube.com/watch?v=NmJweT_IbBw>

The original goal was a convincing animated ocean. It expanded into a first-person water project focused on immersive Roblox water: custom EditableMesh waves, swimming, underwater visuals, shoreline effects, audio, large-ocean rendering, and stylized presentation.

The current direction is a first-person water simulation and cinematic showcase, with future plans for boats, buoyancy, wakes, shoreline interaction, storms, and deeper water simulation.

## 2026-09-09 — From Tutorial Experiment to Water System

### Repository and Water Architecture

The standalone water repository was created and separated into its own codebase. The architecture was designed around world-space water, deterministic wave sampling, configurable water bodies, exclusion volumes, distance-based rendering, and shared water queries for swimming, buoyancy, fishing, NPCs, projectiles, and effects.

The core rule became:

> The camera decides where rendering work is spent; the camera does not rotate the water itself.

Early architecture work also explored `WaterBody`, `WaterRegistry`, `WaveMath`, and chunk scheduling concepts.

### First-Person Controller

A dedicated first-person controller was added. It forces first person, keeps the local body visible, hides the local head and accessories, supports mouse release and recapture, raises the camera slightly, and makes the head and neck follow the camera. It remains independent from the water renderer.

This established the project as a first-person experience rather than an extension of the original top-down MMORPG camera.

### Horizon and Atmosphere

A horizon controller added haze, density, glare, ocean-friendly colour, and distant atmospheric decay so the ocean blends into the horizon instead of ending against Roblox's default distance rendering.

### Coastline / Surface Intersection Experiment

A separate `CoastlineRenderer` was created independently from the EditableMesh ocean. It uses two stacked Studio-authored MeshParts:

```text
CoastLine
---------
small gap
---------
WaterPart
```

The effect follows the player in snapped X/Z increments and reproduces the bright stylized line and intersection effect around characters and shorelines.

### Custom Swimming V2

EditableMesh water does not provide Roblox Terrain water physics, so a custom swimming controller was introduced with neutral buoyancy using `VectorForce`, camera-relative 3D swimming, full `LookVector` movement, natural vertical swimming, explicit swim-up and swim-down controls, keyboard and controller support, controlled entry and exit, and protection against excessive upward velocity.

Roblox's `Swimming` humanoid state can still support animation and state behaviour, but the physics no longer depend on Terrain water.

### Underwater Visual System

A dedicated underwater controller added camera-based entry detection, shallow blue tinting, depth-based darkening, blur, reduced brightness and saturation, a darkness overlay, smooth transitions, and surface/underwater ambience switching. The system is tuned around approximately 20 studs of depth for very dark water.

### Character Lean

A character lean script was introduced to make first-person movement feel less rigid.

### RealisticWater V4

The first major standalone renderer arrived with RealisticWater V4. It uses one EditableMesh, 25 logical update regions in a 5×5 grid, 91×91 vertices, 8,281 vertices, 16,200 triangles, world-space wave evaluation, deterministic seeded waves, up to 14 wave octaves, choppy horizontal displacement, height-based colouring, camera-aware update prioritisation, visible/prewarm/hidden regions, distance-based octave LOD, adaptive quality profiles, reduced underwater work, deep-water freezing, a snapped treadmill ocean, world-locked UVs, and cheap far-ocean coverage.

The key breakthrough was an ocean that follows the playable area without visually rotating or sliding with the camera.

### Multi-Layer Water Rendering

Multiple rendered MeshParts began sharing the same EditableMesh geometry:

- dark/deep base pass;
- lighter middle pass;
- main surface pass;
- upper foam and wave-line pass.

This created the stylized layered-water look without running four wave simulations.

### Shared Water Configuration and Rojo Cleanup

Water configuration was centralised in `ReplicatedStorage/Modules/WaterConfig`. Rojo mappings were updated with `$ignoreUnknownInstances` so source-controlled scripts coexist with Studio-managed assets and sounds.

## 2026-09-10 — Turning the Prototype Into an Immersive Ocean

### Far-Ocean Stabilisation

The distant-water system was reworked after camera movement exposed instability. The camera-projected far-water tile was replaced with a world-locked ring surrounding the detailed EditableMesh. It moves on the same snapped grid, does not rotate with the camera, extends roughly 4,500 studs from its centre, and avoids wasting a transparent layer underneath the detailed ocean.

### Custom Water Entry Splash

Roblox's default splash audio was replaced with `WaterSplashEntry`. The swimming system suppresses the default character splash, creates a local custom entry splash, checks downward velocity, and avoids triggering from minor surface-height changes. A later fix prevents repeated triggering while the player remains near the threshold.

### Reactive Surface-Water Audio

`WaterSurfaceIdle` was added to the coastline system. It activates when either hand overlaps the surface effect, uses start and release delays, increases playback speed with movement, muffles as the camera moves underwater, and uses an equalizer for underwater filtering.

The coastline visibility fade follows root-part height rather than camera rotation, preventing looking up or down from changing it incorrectly.

### Swimming Surface Tuning

Experimental surface thresholds were centralised in `WaterConfig` for surface assistance, minimum and target floating heights, maximum floating height, exit height, restoration speed, corrective velocity, and deliberate descent input. This made movement around the waterline more controlled.

### Camera-Angle Rendering Investigation

A major visual bug appeared when the camera approached the horizon. The generated upper foam layer was temporarily hidden as an isolation test, identifying the issue as an interaction between almost-coincident transparent layers rather than wave rotation. The layer was restored and runtime names were clarified:

```text
WaterBase
WaterMiddle
WaterSurface
WaveFoamVFX
```

During this investigation, `WaveFoamVFX` was made solid temporarily to remove a visual screen-tearing effect where the ocean appeared to clip through itself. This established a stable readable upper layer before the final transparency and SurfaceAppearance tuning.

### Cartoony Water V1

A polished visual checkpoint was committed as `Cartoony water working v1`. The project had moved beyond the original realistic-water tutorial toward a stylized identity combining animated wave geometry, layered translucent water, bright intersection highlights, atmospheric horizon treatment, first-person swimming, and underwater depth presentation.

### Custom Water Footsteps

`WaterFootstepController` was added for shallow-water movement. When the player's feet are in the water band, it suppresses the normal Roblox running sound, plays custom water footsteps using `WaterSplashEntry`, adjusts playback speed and timing with movement speed, and restores normal running audio after leaving the water.

### Coastline Transparency Tuning

The player-following coastline effect was made less visually dominant with:

```lua
EFFECT_OPACITY_MULTIPLIER = 0.55
```

This runtime opacity change allowed the visible `SurfaceAppearance` changes on the generated water to be evaluated clearly. The `__ClientCoastlineEffect` SurfaceAppearance settings themselves were not changed. Further transparency tuning was performed manually in Studio on the Neon and upper visual layers.

### Wind Waker Surface Effect — First Successful Version

A custom alpha-mask texture containing large irregular white cellular wave lines was added:

```text
AlphaMaskOverlay/
└── WindWaker_WaveLines_01.png
```

Reference:

<https://medium.com/@gordonnl/the-ocean-170fdfd659f1>

The upper `WaveFoamVFX` layer already supported world-locked UVs and a Studio-managed `SurfaceAppearance`. The final Studio-side configuration is:

```text
WaterOverlaySurfaceAppearance
ColorMap = rbxassetid://92873785961587
```

The Neon coastline and upper water layer were made slightly more transparent so all effects remain visible together. The coastline SurfaceAppearance itself was left unchanged. This produced the first successful Wind Waker-style cellular wave overlay integrated with the moving EditableMesh ocean.

The current look combines:

```text
Wind Waker wave-line mask
        + WaveFoamVFX / upper surface
        + player-following coastline / intersection effect
        + layered animated EditableMesh water
        + depth-based wave colouring
        + atmospheric horizon
```

## Current State After Two Days

The tutorial experiment has become a standalone first-person water project with:

- custom EditableMesh ocean;
- world-space deterministic waves;
- snapped infinite-ocean-style treadmill;
- logical region scheduling and LOD;
- adaptive performance quality;
- large-distance far-water coverage;
- first-person body presentation;
- custom 3D swimming and buoyancy;
- underwater colour, darkness, and blur;
- surface and underwater sound behaviour;
- custom entry splashes and shallow-water footsteps;
- player-following intersection/coastline rendering;
- layered stylized water rendering;
- world-locked texture UVs;
- Wind Waker-inspired cellular wave lines;
- Studio-authored visual assets that survive Rojo synchronisation.

The current goal is to make first-person water in Roblox feel more immersive, reactive, cinematic, and visually interesting than Roblox water by default.

## Next Experiments

These are future directions rather than completed features:

- animate or distort the Wind Waker UV mask;
- experiment with multiple moving wave-line frequencies;
- improve shoreline behaviour around world geometry;
- add splash and ripple particles;
- add camera-level water droplets and surfacing effects;
- add wave-aware buoyancy queries;
- floating props and boat physics;
- hull interaction and wake generation;
- foam around moving objects;
- stronger storm and ocean states;
- whirlpools and local disturbances;
- improved deep-water atmosphere;
- cinematic water reveals and first-person demonstration spaces.

## Development Note

This changelog distinguishes between source-controlled work reconstructed from Git history, Studio-managed configuration such as `WaterOverlaySurfaceAppearance`, materials, sounds, and transparency tuning, and future ideas listed under **Next Experiments**.

The first repository commit is dated 9 September 2026, making 9–10 September 2026 the first documented two-day development period for the standalone water project.
