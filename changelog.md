# Changelog — RBLX EditableMesh Water First Person

Development log for 9–10 September 2026 from the Git history of `Smurfis/RBLX-EditableMesh-Water-FirstPerson`, plus documented Studio-side changes. Updated from the 10 September development chat through splash-ring commit `0ca845a` and subsequent asset organisation on `water-gerstner-buoyancy-test`.

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

### Cartoony Water V1

During the camera-angle investigation, `WaveFoamVFX` was made solid temporarily to remove visual tearing/clipping between water layers before final transparency and SurfaceAppearance tuning.

A polished visual checkpoint was committed as `Cartoony water working v1`. The project had moved beyond the original realistic-water tutorial toward a stylized identity combining animated wave geometry, layered translucent water, bright intersection highlights, atmospheric horizon treatment, first-person swimming, and underwater depth presentation.

### Custom Water Footsteps

`WaterFootstepController` was added for shallow-water movement. When the player's feet are in the water band, it suppresses the normal Roblox running sound, plays custom water footsteps using `WaterSplashEntry`, adjusts playback speed and timing with movement speed, and restores normal running audio after leaving the water.

### Coastline Transparency Tuning

The player-following coastline effect was made less visually dominant with:

```lua
EFFECT_OPACITY_MULTIPLIER = 0.55
```

This runtime opacity change made the generated water's SurfaceAppearance changes easier to evaluate. The `__ClientCoastlineEffect` SurfaceAppearance settings themselves were unchanged. Further transparency tuning was performed manually in Studio on the Neon and upper visual layers. These Studio notes were also recorded in `e65d701` on `main` after this experiment branch's baseline.

### Wind Waker Surface Effect — First Successful Version

A custom alpha-mask texture containing large irregular white cellular wave lines was added:

```text
Imgs/AlphaMaskOverlay/
└── WindWaker_WaveLines_01.png
```

Reference:

<https://medium.com/@gordonnl/the-ocean-170fdfd659f1>

The upper `WaveFoamVFX` layer already supported world-locked UVs and a Studio-managed `SurfaceAppearance`. The final Studio-side configuration is:

```text
WaterOverlaySurfaceAppearance
ColorMap = rbxassetid://92873785961587
```

The Neon coastline and upper water layer were made slightly more transparent so all effects remain visible together. This produced the first successful Wind Waker-style cellular wave overlay integrated with the moving EditableMesh ocean.

The current look combines:

```text
Wind Waker wave-line mask
        + WaveFoamVFX / upper surface
        + player-following coastline / intersection effect
        + layered animated EditableMesh water
        + depth-based wave colouring
        + atmospheric horizon
```

## 2026-09-10 — Shared Waves, Buoyancy and Player Tracking

Work in this section is on `water-gerstner-buoyancy-test`, created from `b45789e`. The prototype remains separate from `main`.

### Shared Wave Sampler / Gerstner Experiment

`fd8fa03` extracted the existing wave field into `ReplicatedStorage.Modules.WaterWaveSampler`. The renderer and interaction controllers now share deterministic wave data and one time origin. This retained seed `1337`, 14 maximum octaves, exponential swell shaping, recursive sampling and horizontal choppiness, together with the existing renderer's mesh, layers, scheduling, LOD and far-water coverage. Queries expose height, displacement, position and a finite-difference normal.

The Gerstner experiment uses the ocean's existing stylized wave implementation; it did not replace the wave field with a new textbook Gerstner formula. Floating objects sample those same waves, with profile-specific filtering.

### Opt-In Buoyancy and Deformation

- `d4fed6a` added smooth height following for Parts and Models tagged `WaterInteractable`; untagged geometry is untouched and Models require a `PrimaryPart`.
- `3297f41` added smoothed pitch and roll with heading preservation and adjustable rotation strength.
- `29008d9` added SmallProp, MediumProp, Boat and LargeShip profiles with 1/3/6/8 samples, filtered octave counts, update-rate limits and distance culling.
- `7d2901a` added optional `WaterAllowHorizontalDrift` tuning; fixed X/Z remains the default.
- `12269f9` added a separate `WaterDeformable` MeshPart experiment. It caches original vertices, creates a local runtime visual, samples the shared waves and guards EditableMesh creation failures while preserving the source mesh.

These systems are local visual prototypes; their object positions are not server-authoritative boat physics.

### Player Surface Motion and Tracking on Floating Parts

`00b5d6d` added gentle player surface bobbing and body tilt through `PlayerWaveMotionController` and `PlayerWaveMotionState`. Swimming consumes the smoothed offset; response fades when surface hold ends. Sampling is capped at 30 Hz with six octaves, and height/tilt limits are centralised in `WaterConfig`.

`a60f019` added player tracking/carry from the movement and rotation of supporting `WaterInteractable` platforms. The player follows their vertical movement, pitch, roll and yaw while standing on them. Follow-up fixes replaced unsupported Humanoid floor access with raycasts (`09967d1`), stabilised body tilt through a cached Motor6D base pose (`6e2e9c6`), and suppressed independent wave motion while riding to avoid applying wave movement twice (`44c236e`). `eba2507` expanded support detection to five points around the character to improve contact at platform edges and corners.

Controller regression checks and Studio test guidance are included under `tests/` and [docs/PLAYER_WAVE_MOTION.md](docs/PLAYER_WAVE_MOTION.md).

### Spawn Visual Cleanup

`249e3bc` brought the spawn visual controller into source control and hardened cleanup: temporary body highlights become fully transparent, render callbacks disconnect, the authored SpawnLocation appearance is restored, and the final state is checked again on the next render frame.

## 2026-09-10 — UI Changes and Replicated Splash Rings

### Settings and First-Person HUD

The settings/HUD work from `97bbb9f` through `3f2fdca` added the `ReplicatedStorage.UI.Checkbox` Rojo mapping, an animated scrollable settings panel, water-opacity and camera-sensitivity slider controls, and a compact keybind HUD option. Final controls use `SETTINGS: [=]` and `Free Mouse: [M]`, with tappable controls for mobile. Opening settings releases the cursor; closing it restores first-person lock.

The HUD uses cartoon styling, a centred server identifier and a separate responsive top-right title/version/FPS group. FPS is capitalised and appears beside the version. Mouse initialisation and icon state were corrected: the icon is visible while locked, hidden while released, and a small centre reticle indicates first-person lock.

The developer water-tuning panel introduced in `4e6f7c3` was reverted in `6e0ef29` at the user's request. Only removal of the Player Reflections option was retained; developer sliders and their renderer changes are not part of the final state.

### Replicated Water-Contact Splash Rings

`0ca845a` added local detection of downward crossings into the configured water-entry band and a server handler for splash requests. The server checks request type, distance from the player, proximity to the base water surface and a cooldown, then clones the Studio-authored `ReplicatedStorage.Shared.Assets.SplashRing` Part into Workspace. Rings expand to 2.5 times their starting size and fade over 0.7 seconds before cleanup, making the effect visible to other players. The Rojo project now maps `ServerScriptService`.

This is replicated visual feedback at the configured base surface. It does not establish server authority for the separate buoyancy prototype.

The follow-up paddle pass separates airborne entry from surface contact. An entry ring is armed only after the player has clearly left the water, so holding Space or small surface bobbing cannot repeatedly fire the entry effect. While `SurfaceHold` is active, hand movement near the waterline emits a restrained ring at most once every 0.85 seconds, creating the requested paddling response around the player's hands.

The paddle trigger now follows horizontal swimming speed and alternates hands. It places each smaller ring 1.35 studs ahead of the active hand at the CoastLine/waterline, so forward and backstroke swimming produces the pushing-water illusion even when the hand animation remains visually above the surface. Paddle rings start 0.45 studs above CoastLine, tween down into it, remain throttled at 0.62 seconds, and are 5% larger than the previous paddle size.

The entry ring now starts 10% wider and 50% thicker vertically, with a slightly longer fade, so the first jump into the water reads clearly before disappearing.

Shallow-water walking audio now checks the shared animated wave height at each foot rather than only the fixed base surface. The footstep band was widened slightly so standing and walking through visible wave crests keeps the water sound active instead of falling back to solid-ground audio.

Walking just above the shoreline now also emits a small replicated `WaterFootstepRing` at the detected foot. These rings start slightly above CoastLine, settle into the waterline and fade quickly, creating a subtle bubble/splash contact without using the heavier entry effect.

The replicated splash rings now emit the supplied rainsplash texture (`rbxassetid://105796658952670`) from their centre. Jump entries use a larger 18-particle burst, paddle rings use a restrained three-particle burst, and footstep rings use a small four-particle burst.

### Source Assets

- Moved the unchanged wave-line texture to `Imgs/AlphaMaskOverlay/WindWaker_WaveLines_01.png`.
- Added `Imgs/Decals/SpawnLocationDecal.png`.
- Added audio source files `Sounds/Water-Splash-Entry.mp3` and `Sounds/Water-Surface-Idle.mp3`.

These files are repository source assets; Studio-managed instances and uploaded asset IDs remain configured in Studio.

### Validation and Open Testing Issue

The development chat records successful Rojo builds/sourcemaps, Luau compilation and player-wave controller regression checks during implementation. Those checks do not prove visual parity, physics behaviour or multiplayer stability in Studio.

The final chat investigation recorded `RBXCRASH: OutOfMemoryGraphics` and out-of-memory messages during Studio client/server testing. Graphics-memory pressure remains an open testing issue; no crash fix was committed. Single-client testing or lower Studio graphics quality was suggested for further investigation.

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
- shared wave sampling, opt-in floating props and experimental mesh deformation;
- gentle player wave motion and tracking on floating platforms;
- animated settings, mobile keybind controls and a first-person status HUD;
- server-replicated water-contact splash rings;
- Studio-authored visual assets that survive Rojo synchronisation.

The current goal is to make first-person water in Roblox feel more immersive, reactive, cinematic, and visually interesting than Roblox water by default.

## Next Experiments

These are future directions rather than completed features:

- animate or distort the Wind Waker UV mask;
- experiment with multiple moving wave-line frequencies;
- improve shoreline behaviour around world geometry;
- extend the existing splash rings with splash and ripple particles;
- add camera-level water droplets and surfacing effects;
- validate visual wave parity and refine the existing buoyancy queries;
- develop server-authoritative boat physics beyond the local floating-prop prototype;
- hull interaction and wake generation;
- foam around moving objects;
- stronger storm and ocean states;
- whirlpools and local disturbances;
- improved deep-water atmosphere;
- cinematic water reveals and first-person demonstration spaces.

## Development Note

This changelog distinguishes between source-controlled work reconstructed from Git history, Studio-managed configuration such as `WaterOverlaySurfaceAppearance`, materials, sounds, and transparency tuning, and future ideas listed under **Next Experiments**.

The first repository commit is dated 9 September 2026, making 9–10 September 2026 the first documented two-day development period for the standalone water project.
