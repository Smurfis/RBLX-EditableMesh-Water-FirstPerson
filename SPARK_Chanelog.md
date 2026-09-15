# Spark – Full Changelog / Handoff
**Date:** 2026-09-14
**Project area:** Roblox Spark companion – visuals, materialisation, idle personality, camera-follow behaviour, climbing/falling handling, ReplicatedFirst cinematic inspection.

This document is intended as a complete handoff to another ChatGPT conversation. It records the decisions, discoveries, bugs, fixes, current architecture, current accepted behaviour, and the important intermediate experiments from today.

---

# 1. Core Direction Established Today

Spark is no longer being treated as a simple neon fairy/orb. His visual language is now:

- **Outer SparkBody = engineered shell / relic casing**
- **Inner NeonBodyOrb = soul / energy / VFX body**
- **Wings = expressive magical-engineered geometry**
- **SurfaceAppearance = metallic/golden/silver embellishment and emission**
- **PointLight / particles / trail = secondary visual language**

Canonical idea:

> OUTER BODY = what Spark is made from
> INNER BODY = what Spark is made OF

Spark should feel like impossible arcane engineering rather than a plain floating sphere.

Important rig rule:

- Do **not** remesh/rerig in Blender.
- Preserve the current rig, bones, Motor6Ds, animations, body/wings, and imported structure.
- All new visual complexity should be layered on top through materials, SurfaceAppearance, the welded inner orb, particles, light, and code.

---

# 2. New Body / SurfaceAppearance Work

## 2.1 Outer body material experimentation

Spark’s outer body was successfully changed to use a panel/brick-like engineered material look.

A reference clone is being kept so there is always a visually-correct authored copy to compare against.

The current preferred canonical presentation is:

- outer shell has engineered/golden appearance
- outer shell transparency roughly **0.2**
- body can use a Brick / panel `MaterialVariant`
- `SurfaceAppearance` provides metallic/golden embellishments
- body can still change `Color`
- body emission can change independently

The outer shell is meant to become more sophisticated over time as Spark advances.

## 2.2 SurfaceAppearance discovery

Important Roblox behaviour confirmed:

- `SurfaceAppearance.AlphaMode = Overlay` works for this setup.
- Transparent pixels in the ColorMap allow `MeshPart.Color` to remain visible underneath.
- This means:
  - SparkBody.Color can be changed dynamically
  - golden/silver linework can remain overlaid
  - emission can be controlled separately

This was preferred over `AlphaMode = Transparency`, which visually cuts out the transparent map regions.

Other notes:

- `SurfaceAppearance.Color` is a tint multiplier.
- `EmissiveTint` changes emitted colour.
- `EmissiveStrength` controls intensity.
- SurfaceAppearance has no UV offset/rotation API, so animated scrolling of a texture would require rotating geometry or some other approach.

## 2.3 Emission scale

A useful semantic body-emission scale was established:

- `1` = dormant / minimum
- `2–3` = normal
- `4` = active / interested
- `5` = alert
- `6` = max / overcharged

This applies particularly well to the body SurfaceAppearance.

The wings may use their own larger numeric range; do not assume the same raw values must be used for body and wings.

---

# 3. NeonBodyOrb – New Inner Body

A new inner body called:

```text
NeonBodyOrb
```

was added under `SparkBody`.

Hierarchy concept:

```text
Spark
├─ SparkBody
│  ├─ SurfaceAppearance
│  ├─ PointLight
│  ├─ NeonBodyOrb
│  │  └─ WeldConstraint
│  └─ BodyMotor6D
├─ SparkWingL
└─ SparkWingR
```

Safe configuration:

```text
NeonBodyOrb:
Anchored = false
Massless = true
CanCollide = false
CanTouch = false
CanQuery = false
CastShadow = false
```

The orb is welded directly to `SparkBody`.

Do **not**:
- weld it to a Bone
- add another Motor6D
- anchor it
- parent it under the rig bones
- alter existing rig joints

The follower’s rig-prep loop already makes all BaseParts:
- non-collidable
- non-queryable
- massless
- unanchored

while `SparkBody` itself becomes the anchored control part.

The orb is therefore automatically compatible with the existing follower.

---

# 4. Canonical Material Ownership Rule

This became a hard rule today.

## SparkBody owns

- engineered shell
- normal body colour / semantic body hue
- authored Brick / panel MaterialVariant
- transparency
- body SurfaceAppearance
- golden/silver engineering embellishment
- body SurfaceAppearance emission

## NeonBodyOrb owns

- Neon
- Glass
- ForceField
- soul-state material transitions
- soul colour
- materialisation/reappearance core

Canonical comment recommended:

```lua
------------------------------------------------------------
-- SPARK BODY LAYER RULE
--
-- SparkBody is the engineered outer shell.
-- It must never become ForceField.
--
-- NeonBodyOrb is Spark's internal soul / VFX body and owns:
-- Neon, Glass, ForceField, and related material transitions.
--
-- During ForceField reform:
-- SparkBody + wings remain invisible until the soul has
-- visibly re-established itself.
------------------------------------------------------------
```

The outer SparkBody should **never** become ForceField again during runtime materialisation.

---

# 5. Materialisation / Pop / Reappear Language

The “pop and reappear” behaviour was redesigned to use the new layered body correctly.

Canonical sequence:

```text
NORMAL
SparkBody visible
Wings visible
NeonBodyOrb visible

↓ dissolve

DISSOLVE
outer shell fades
wings fade
inner orb transitions toward soul state
particles begin

↓ burst

VANISH
SparkBody = invisible
Wings = invisible
NeonBodyOrb = invisible
PointLight dims out

↓ hidden callback

onInvisible()
Spark may PivotTo / swap side / teleport while completely invisible

↓ reform

FORCEFIELD SOUL REAPPEAR
NeonBodyOrb.Material = ForceField
NeonBodyOrb fades visible
SparkBody stays invisible
Wings stay invisible

↓ rebuild

ENGINEERED BODY RETURNS
SparkBody fades back
Wings fade back
body/wings emission returns
NeonBodyOrb transitions back to authored normal material

↓ settle

NORMAL
```

Critical visual decision:

> During the ForceField reappearance phase, **only the inner soul should be visible**.

The gold engineered shell and wings remain hidden until after the soul has visibly re-established itself.

This visually communicates:

- shell/body broke apart
- soul returned first
- engineering reconstructed around it

---

# 6. Bugs Found in the First NeonBodyOrb Patch

A first patch to `SparkVisuals` introduced several bugs.

## 6.1 Inner orb colour was being overwritten

The patched `_ApplyBodySoulColor()` was incorrectly doing:

```lua
self.NeonBodyOrb.Color = bodyColor
```

This destroyed the authored inner-body colour.

Example authored inner colour mentioned:

```text
215, 197, 154
```

It could get changed to odd greens/black/dull colours during runtime.

Fix:

- NeonBodyOrb colour is now treated independently.
- Outer body semantic colour no longer automatically overwrites the inner orb.

## 6.2 SparkBody got stuck sand-green / dull grey-green

During materialisation the outer body was intentionally tweened to:

```lua
SPARK_DULL_BODY_COLOR = Color3.fromRGB(120, 132, 126)
```

The code later attempted to restore body colour by writing the same already-existing `VisualColorValue.Value`.

Because that value had not changed, Roblox did not fire the property-change path again, so the actual `SparkBody.Color` could remain stuck in the dull/sand-green state.

Fix:

- explicitly reapply the body colour at the end of the effect
- do not rely on reassigning an unchanged Color3Value to trigger the restoration

## 6.3 MaterialVariant was not restored

The old module stored:

```text
OriginalBodyMaterial
```

but not:

```text
OriginalBodyMaterialVariant
```

So Spark could return to the correct base Material but lose the authored Brick/panel variant.

Fix:

Snapshot and restore:

```text
OriginalBodyMaterial
OriginalBodyMaterialVariant
OriginalBodyColor
OriginalBodyTransparency
```

plus the inner orb’s authored:

```text
Color
Material
Transparency
```

---

# 7. Visual State Architecture Discussed

Spark should eventually support semantic display presets.

Current intended semantic language:

- **Neutral / Illuminate** = authored gold Spark
- **Friendly** = green
- **Enemy** = red
- **Interact** = white body + silver/white embellishment/emission
- possible Focus/Special = white
- Dormant / active / overcharged use same hue but different emission levels

Important rule:

Colour transitions should tween from the **actual current intermediate colour**, not snap back through neutral.

Example:

```text
Gold → Green
halfway through
Enemy state arrives
→ continue directly from current mixed colour to Red
```

Do not force a neutral reset.

Future API discussed:

```lua
sparkVisuals:SetDisplayPreset("Neutral")
sparkVisuals:SetDisplayPreset("Interact")
sparkVisuals:SetDisplayPreset("Friendly")
sparkVisuals:SetDisplayPreset("Enemy")
sparkVisuals:SetPowerLevel(level)
sparkVisuals:SetForceField(enabled, duration?)
sparkVisuals:SetVisible(visible, duration?)
```

These are not all final/implemented yet, but this is the intended architecture.

---

# 8. Idle / Illuminate Personality Visuals

A new idle personality system was added.

## Illuminate mode

Spark’s normal/helper state.

He is:

- canonical authored gold
- Brick/panel engineered shell
- normal light/emission
- helping illuminate / guide the player

Illuminate wins whenever the player is actively doing something.

Activity includes:

- character movement
- camera rotation
- camera zoom
- focus/targeting
- climbing
- other active states

## Idle mode

If both:

- player is not moving
- camera is not moving

for roughly:

```text
3.5 seconds
```

Spark is allowed to quietly experiment with his own appearance.

Idle can change:

- SparkBody colour
- wings SurfaceAppearance colour
- wings EmissiveTint
- body SurfaceAppearance colour
- body EmissiveTint
- body EmissiveStrength
- body Material / MaterialVariant presentation
- Brick/panel ↔ Neon outer-shell form experiments

Important:

- `NeonBodyOrb` is **not** used for the idle colour/personality morph.
- The idle system changes the outer shell and wings, not the fake/soul body.

Material change is hidden inside a slower colour/emission transition rather than snapping obviously.

Idle transitions were intentionally slow/unpredictable so the player may only gradually notice Spark has changed.

When player/camera activity resumes:

```text
Idle → Illuminate
```

Spark rapidly returns to the exact authored gold state.

Return duration around:

```text
0.22s
```

The canonical neutral is captured from Studio rather than hardcoded.

So if Spark’s authored gold changes later, the code automatically follows it.

---

# 9. Personality Teleport / Pop Use

The pop/materialisation effect was expanded conceptually into a legitimate movement language.

Spark can eventually recover from being displaced using:

- normal physical flight
- rare pop/materialisation teleport
- emergency hidden reposition

The goal is that Spark does not feel like a UI widget constantly correcting coordinates.

He should sometimes fly and sometimes inexplicably pop.

Important personality principle:

> We do not always know why Spark does things. He just does.

The existing `PlaySoulMaterialisation(onInvisible)` callback is ideal for teleport/side-swap because Spark is moved only during complete invisibility.

Teleport should **not spam**.

During climbing observer / special movement, teleport should be blocked.

---

# 10. SparkFollower – Camera Positioning Work

This became the main tuning task today.

Existing follower architecture was preserved.

Important parts already present:

- camera-relative Spark position
- shoulder position
- free-camera position
- geometry avoidance
- visibility checking
- Spherecast world clamping
- SmoothDamp movement
- animation-speed adaptation
- trail based on visible movement
- target/focus system
- climbing state via new controller attribute
- camera angular-speed response
- zoom-speed response
- target-distance catch-up

The aim was **not** to replace this system, because it already adapts extremely well to arbitrary camera angles.

The goal became simply to make the camera-home rules cohesive and solve vertical ladder/freefall edge cases.

---

# 11. Camera Distance Rules – Final Simplified Reference

The percent-based zoom-band experiments were replaced with straightforward camera distance in studs.

Current tuning reference discussed:

```text
CameraMinZoomDistance ≈ 0.5

0.5–2 studs
    first-person Spark

2–15 studs
    physical shoulder

15–30 studs
    free-camera / camera-relative Spark

>30 studs
    far shoulder
```

User noted Roblox’s default max zoom can be much larger (e.g. 128), and these numbers may change later.

The key design improvement is:

> Camera-home rules should be based on real camera distance in studs because they are easier to reason about and retune than percentages.

For example, if shoulder range later changes:

```text
15 → 18 studs
```

only one number needs changing.

---

# 12. Close Shoulder Before First Person

A specific desired behaviour was restored:

- Spark should go onto the physical shoulder shortly before the camera reaches first person.
- Actual first person remains the existing camera-relative companion position.

This creates:

```text
first person
    → camera companion

zoom out slightly
    → shoulder

zoom farther
    → free camera

zoom farther again
    → shoulder
```

This is intentional and gives Spark a nice rhythm instead of staying in one mode.

---

# 13. CCL / New Character Controller State Detection

The project is intentionally adopting Roblox’s newer character controller tech early.

Climbing state is detected from the Humanoid attribute:

```text
ccl_humanoidstate
```

The current helper uses a case-insensitive `"climb"` substring check so small beta naming changes do not instantly break behaviour.

Debug output was added to inspect:

```text
ccl_humanoidstate
Humanoid:GetState()
Humanoid.MoveDirection
other attributes containing:
    ccl
    state
    controller
```

This was intentionally added so future beta changes are discoverable instead of guessed.

Keep this state-driven architecture for future:

- climbing
- swimming
- crouching
- crawling
- vehicles
- stealth
- jumping/falling

rather than reverting to old-only Humanoid behaviour.

---

# 14. Climbing Observer Experiment

An experimental climbing observer mode was built.

Intended visual:

- player climbs ladder
- camera is far/zoomed out
- player stops
- Spark flies to upper-right of the screen
- Spark turns to watch the player
- moving again returns Spark to normal rules

Several trigger strategies were tried:

1. effectively full zoom percentage
2. exact CameraMaxZoomDistance
3. practical ~60% zoom
4. true screen-space top-right observer point
5. 2-second physical-idle delay using measured RootPart movement

A proper screen-space observer target was also implemented using a viewport point around:

```text
82% across
18% down
```

projected through the camera.

This was better than a world-space `head.Position + camera.RightVector + camera.UpVector` target because it means:

> top-right actually means top-right of the screen at any camera pitch/yaw/ladder height.

However:

**The observer/max-zoom behaviour is currently intentionally disabled/deferred.**

The user decided the main priority was the free-camera climbing/falling problem.

The observer infrastructure can be returned to later.

---

# 15. Roblox Pill / CoreGui Avoidance

The Roblox top-left UI pill was interfering visually with Spark.

A climbing-only screen-safe region was added using:

```lua
GuiService:GetGuiInset()
```

plus an upper-left no-fly region.

Design:

- ordinary target remains untouched if safely on-screen
- if climbing target drifts out of viewport, clamp it into a safe screen region
- if it enters the top-left Roblox pill region, push it horizontally clear

Do not try to move/disable the Roblox pill itself.

Spark should adapt around CoreGui.

---

# 16. Major Climbing Problem Found

The most irritating remaining issue was:

> While Spark was in free-camera mode and the player climbed up/down or fell rapidly, Spark could be thrown off the screen vertically.

This happened even though the rest of the camera system behaved well.

Why:

The original fast-response system measured target movement mostly **laterally** across the camera:

```text
camera RightVector
```

It intentionally ignored vertical target movement.

That was good for normal camera flutter but bad for ladders/falling.

When the character moved vertically quickly:

- target moved vertically
- SmoothDamp remained relaxed
- Spark lagged
- player/camera movement effectively launched Spark out of frame

---

# 17. Vertical Response / Ladder Descent Fixes Tried

Several iterations were tested.

## Iteration 1 – general downward catch-up

Measured frame-to-frame RootPart vertical movement.

Added stronger response while:

- falling
- moving downward quickly

This improved it but still lagged too much.

## Iteration 2 – viewport screen guard

While climbing:

- keep target inside viewport
- reserve Roblox-pill region
- force maximum catch-up if Spark is already outside the safe screen

This helped noticeably.

## Iteration 3 – projected “10% lower on screen”

Tried leading Spark’s target lower by up to ~10% of viewport height while descending.

This could behave oddly depending on camera pitch and sometimes visually moved him the wrong way/upward.

This approach was abandoned.

## Iteration 4 – simple world Y offset

Changed the descent compensation to a simple:

```lua
Vector3.new(0, -2, 0)
```

while physically descending.

This was more predictable than screen-space projection.

## Final accepted direction

The current accepted follower goes further:

### Free-camera climbing baseline

When climbing in the **15–30 stud free-camera band**, Spark starts:

```text
1 stud lower
```

than the ordinary camera-relative target.

This gives him vertical headroom.

### Additional descent lead

When actively descending:

- add up to another **2 studs lower**
- progressive based on real vertical speed

So hard descent can make the effective target roughly:

```text
3 studs lower than old free-camera target
```

### Aggressive downward/fall SmoothDamp

When the character is:

- descending quickly
- or genuinely falling

Spark uses an extremely fast SmoothDamp:

```text
~0.025
```

instead of preserving relaxed flutter.

This is deliberately aggressive because the priority is keeping Spark on-screen.

### Brief downward rotation

During descent Spark gets a slight nose-down pitch:

```text
~ -18°
```

This makes the movement look intentional:

> Spark is diving down with the player

rather than simply being dragged vertically by code.

When downward movement stops:

- extra descent offset disappears
- pitch returns
- normal resolver resumes

---

# 18. Current Final Accepted Follower

The user considered the positioning problem **fixed** after the last tuning.

They specifically noted:

- Spark now centres himself better
- violent camera throwing recovers better
- the camera-angle adaptability remains strong
- climbing/downward response is now acceptable

The current final follower from today is:

```text
SparkFollower_FreeCamClimbDownFast.lua
```

Important current behaviours:

- first person / shoulder / free cam / far shoulder distance bands
- close shoulder before first person
- camera movement affects Idle/Illuminate state
- body/visual personality integration
- fast camera catch-up
- screen-safe climbing guard
- Roblox-pill avoidance
- lower climbing free-cam baseline
- progressive extra downward offset
- extremely fast falling/downward response
- slight downward Spark rotation during descent
- max-zoom observer temporarily disabled

Do not regress the rest of the camera system while working on future additions.

---

# 19. Current Final Visual Module Direction

Latest visual work today centred around:

```text
SparkVisuals_IdleForms.lua
```

plus the earlier fixed NeonBodyOrb restoration logic.

Critical rules to preserve:

- outer SparkBody does not become ForceField
- NeonBodyOrb owns ForceField/Glass/Neon transitions
- MaterialVariant must restore
- inner orb colour must not be overwritten by the outer body colour driver
- shell/wings stay invisible during ForceField soul reform
- authored Studio neutral appearance is the source of truth
- Idle alters outer shell / wings / body SurfaceAppearance
- Illuminate returns to authored gold state

---

# 20. ReplicatedFirst / FirstEffect Inspection

The actual ReplicatedFirst `FirstEffect` was finally shared.

Important discovery:

It is still using the **old visual architecture**.

It directly does things like:

```lua
sparkBody.Material = Enum.Material.Glass
```

and:

```lua
sparkBody.Material = Enum.Material.ForceField
```

It also snapshots:

```text
sparkOriginalBodyMaterial
```

but not the new:

```text
MaterialVariant
NeonBodyOrb
body SurfaceAppearance architecture
```

Therefore:

> Runtime Spark and cinematic Spark are currently not using the same layered-body rules.

This explains cinematic discrepancies.

The ReplicatedFirst cinematic still:
- clones `Spark`
- creates `CinematicSpark`
- uses random intro colour seeds
- animates Spark toward/around the loading camera
- flashes ForceField on outer body
- runs old soul materialisation
- sets `ReadyForCameraTransition`
- hands off to GtaCameraManager

Future task:

Refactor `FirstEffect` to use the same:
- outer shell
- inner soul orb
- MaterialVariant restoration
- ForceField ownership
- shell/wings hidden during soul-only reform

Do this later and carefully; the runtime Spark behaviour was the priority today.

---

# 21. GtaCameraManager Findings

GtaCameraManager was inspected earlier.

It:

- waits for `workspace.CinematicSpark`
- waits for `ReadyForCameraTransition`
- takes ownership from ReplicatedFirst
- moves CinematicSpark as a whole Model with `PivotTo`
- adds cinematic SpotLight
- flies Spark relative to camera
- aligns CinematicSpark with gameplay Spark at final handoff
- fires `SparkCameraHandoff`
- destroys CinematicSpark

It does **not** need rig-level changes for NeonBodyOrb.

Because NeonBodyOrb is welded to SparkBody and the model is moved as a whole, it follows automatically.

---

# 22. SparkFollower Handoff Behaviour

Gameplay Spark is cloned from:

```text
ReplicatedStorage
└─ Models
   └─ NPCs
      └─ SparkModels
         └─ Spark
```

and renamed:

```text
<player name>'s Spark
```

The gameplay clone is initially hidden during the loading cinematic using:

```text
LocalTransparencyModifier = 1
```

on all BaseParts.

Existing lights/particles/beams/trails are also temporarily disabled.

This automatically includes the new inner orb because it is a BasePart descendant.

At `SparkCameraHandoff`:

- BasePart LocalTransparencyModifier restored to 0
- saved effect enabled states restored
- SparkVisuals ambient system enabled

This path remains good.

---

# 23. Important “Do Not Regress” Rules

Future work should preserve all of these:

1. **Do not remesh/rerig Spark.**
2. Do not alter existing bones/Motor6Ds just for VFX.
3. `SparkBody` = engineered outer shell.
4. `NeonBodyOrb` = soul/material-transition body.
5. Outer SparkBody never becomes ForceField during runtime materialisation.
6. During ForceField reform:
   - SparkBody invisible
   - wings invisible
   - only inner orb visible
7. Restore SparkBody `MaterialVariant`.
8. Do not overwrite NeonBodyOrb authored colour from the outer body colour driver.
9. Neutral/Illuminate gold appearance should come from Studio-authored values.
10. Idle visual personality should never fight semantic target modes later.
11. Camera movement returns Spark to Illuminate/gold.
12. Character movement returns Spark to Illuminate/gold.
13. Spark’s movement system should remain SmoothDamp-based.
14. Do not replace normal flying with constant teleportation.
15. Teleport/pop is personality/safety behaviour, not the default correction.
16. While special observer/climbing behaviour is active, personality teleport must be blocked.
17. Camera rules should be expressed in real stud distances where practical.
18. New controller state detection should continue using the new `ccl_humanoidstate` path.
19. Vertical climbing/falling requires stronger response than normal camera flutter.
20. Preserve arbitrary-camera-angle adaptability.
21. The current follower is considered essentially fixed; future edits should be surgical.

---

# 24. Current Camera Distance Reference

Current practical reference from testing:

```text
CameraMinZoomDistance = 0.5

0.5–2
    first-person Spark

2–15
    physical shoulder

15–30
    free-camera Spark

>30
    far shoulder
```

These are tuning values, not lore/canonical design. They may change.

Roblox default max zoom may be around:

```text
128
```

depending on configuration.

---

# 25. Current “Modes” Concept

Spark is moving toward a proper state/mode system.

Current conceptual modes:

```text
Illuminate
Idle
Interact
Friendly
Enemy
Scripted/Cinematic
```

### Illuminate
- gold
- helper/light state
- default when active

### Idle
- self-expression
- chooses body/wings/emission/material form
- only when player and camera are calm

### Interact
Planned:
- white body
- silver/white embellishments/emission

### Friendly
Planned:
- green

### Enemy
Planned:
- red

### Scripted/Cinematic
- FirstEffect / camera cinematic ownership

Eventually these should become explicit semantic visual states rather than ad-hoc colour tweens.

---

# 26. Key Design Philosophy Established

Spark should feel like an entity, not a UI marker.

Examples:

- sometimes flies
- sometimes pops
- sometimes changes colour/material while bored
- sometimes swaps sides
- sometimes behaves inexplicably
- still has reliable helper/indicator functions underneath

He is also becoming the player’s **Illuminate light/helper**.

The idle behaviour reinforces that:

> when you need him, he becomes gold and useful
> when you are doing nothing, he starts experimenting with himself

---

# 27. Files Generated Today

Important generated/modified files during this chat included:

```text
SparkVisuals_NeonBodyOrb.lua
SparkVisuals_NeonBodyOrb_Fixed.lua
SparkVisuals_IdleForms.lua

SparkFollower_IdleForms.lua
SparkFollower_IlluminateIdle_CloseShoulder.lua
SparkFollower_CohesiveZoomBands.lua
SparkFollower_CohesiveZoomBands_ClimbObserverDebug.lua
SparkFollower_ClimbObserver_FallCatchup.lua
SparkFollower_ClimbingScreenGuard_ObserverFixed.lua
SparkFollower_ClimbingDescentLead.lua
SparkFollower_MaxZoomObserver.lua
SparkFollower_ClimbDownYOffset_Observer60Percent.lua
SparkFollower_SimpleDistanceBands_MaxZoomClimb.lua
SparkFollower_FreeCamClimbDownFast.lua
```

Several of these are intermediate experiments and are superseded.

### Current preferred runtime follower

```text
SparkFollower_FreeCamClimbDownFast.lua
```

### Current preferred visual direction

```text
SparkVisuals_IdleForms.lua
```

with the fixed NeonBodyOrb/MaterialVariant restoration rules preserved.

---

# 28. Suggested Next Work

When continuing in another chat, the next safest order is:

1. **Do not touch SparkFollower unless a real regression appears.**
2. Move to semantic visual states:
   - Illuminate
   - Idle
   - Interact
   - Friendly
   - Enemy
3. Make body + body SurfaceAppearance + wing SurfaceAppearances transition coherently.
4. Keep NeonBodyOrb independent from semantic outer-shell colour unless intentionally needed.
5. Refactor ReplicatedFirst `FirstEffect` to use the new layered-body architecture.
6. Only after runtime + cinematic visual ownership are unified, revisit the optional climbing observer/top-right watching behaviour.
7. Later, formalise Spark’s teleport-vs-fly personality resolver with cooldowns.

---

# 29. Final Status at End of Today

### Considered working / accepted

- Spark’s rig
- new inner orb
- outer engineered shell concept
- SurfaceAppearance Overlay workflow
- runtime materialisation ownership split
- shell/wings hidden during ForceField reform
- MaterialVariant restoration
- inner-orb colour preservation
- Idle/Illuminate visual personality
- camera activity returning Spark to gold
- close shoulder before first person
- distance-based camera bands
- general camera adaptability
- climbing/falling vertical catch-up
- lower free-camera climbing baseline
- aggressive downward/fall response
- descent pitch
- Roblox-pill avoidance
- violent camera recovery

### Deferred / not final

- climbing observer / top-right watching trigger
- exact max-zoom semantics for observer
- full semantic target-indicator system
- Friendly/Enemy/Interact preset implementation
- ReplicatedFirst FirstEffect layered-body refactor
- final teleport/fly personality resolver
- exact long-term camera-distance tuning

### User’s final assessment

The main camera/follower problem was considered **fixed**.

Spark was also observed to centre himself better after violent camera movement.

The current goal going forward should be refinement, not another wholesale follower rewrite.

---

# 30. One-Sentence Handoff Summary

**Spark is now a layered engineered/soul companion with authored gold Illuminate state, self-expressive Idle visuals, a separate ForceField/Glass inner orb, preserved Brick/MaterialVariant outer shell, robust SmoothDamp camera following, real-distance camera bands, new CCL climbing detection, and aggressive vertical ladder/fall catch-up; runtime follower is considered essentially fixed, while semantic target colours and ReplicatedFirst cinematic conversion remain the main future work.**

Spark Changelog Addendum

v0.6.0-dev — 2026-09-14 — Spark Vessel Pass, First-Person Recovery, Boat Steering Revision, Swimming Orientation and Character Controller Library Migration

This section is intended to be appended directly after the current v0.5.0-dev material.

The 14 September session was highly iterative. Several systems were rebuilt or partially migrated while Roblox's new Character Controller Library / Ability system was enabled. Some intermediate swimming-controller versions were deliberately superseded after live Studio testing. Those failed or transitional approaches are recorded here so Codex does not accidentally restore them later.

The major themes of this milestone were:

restoring the intended visible-body first-person camera after an arms-only regression;

continuing Spark's transition from a visual follower into a proper physical/visual companion vessel;

creating and integrating a new steering wheel asset and re-rooting the steering-hand IK around it;

rebuilding custom swimming orientation so the player can physically lie into the swim direction;

adding separate surface, underwater, explicit-up and explicit-down orientation behaviour;

identifying and correcting the avatar-axis mistake in the first swimming-orientation attempts;

adapting the custom EditableMesh swimming system to Roblox's new Character Controller Library / Ability architecture;

separating custom ocean state from Roblox Terrain-water state;

testing CCL movement intent, look intent, Turning ownership and controller handoff;

restoring the old full camera LookVector specifically where CCL's facing direction lost vertical swim pitch.

Project / Laboratory Status

The project remains:

Project
    Spark

Development status
    experimental laboratory / prototype

Current development milestone
    v0.6.0-dev

Historical/internal names
    WaterTest
    RBLX EditableMesh Water First Person

The laboratory remains intentionally focused on:

Spark
first-person body / camera
boats
steering
IK
EditableMesh ocean
Gerstner wave sampling
buoyancy
custom swimming
water interaction
floating objects
ocean VFX

Temporary conflicts between experimental systems are acceptable while they are being isolated. A fix for one subsystem should not silently remove another working subsystem.

First-Person Body Visibility Restored

A regression was investigated where the first-person controller stopped showing the player's complete body.

The earlier controller had been modified to support an optional reduced-body / arms-only presentation, but that experiment accidentally became too authoritative and removed the normal visible-body first-person behaviour.

The desired baseline was restored:

first person
    body remains visible

head near the camera
    may disappear / become locally hidden as required

zoom out
    head / full body presentation returns naturally

The first-person system should behave as an enhancement of Roblox's camera rather than forcing a permanently detached FPS-arms presentation.

Do not restore a blanket local transparency rule that makes the player's entire character disappear.

The longer-term camera direction remains:

third person
    normal avatar

zoom toward character
    smooth transition

camera reaches head
    local head presentation fades / disappears

first person
    visible body

zoom back out
    head reappears smoothly

The goal is a Roblox-like zoom transition with a better body-aware first-person implementation rather than a hard instant swap between two unrelated cameras.

Camera / Character Orientation Ownership

The camera and character orientation systems continued moving toward explicit ownership rules.

The project now has several separate concepts that must not be conflated:

camera look
    where the player is looking

character facing
    where the root/body is physically facing

movement intent
    where the player is trying to move

swim heading
    where the custom swimmer should physically travel

body pose
    how the avatar should rotate/lie while travelling

The 14 September swimming work reinforced the rule that movement and visual orientation must be separable.

A character can:

move vertically
while
rotating smoothly into a pose

or

return to a neutral pose
while
continuing explicit vertical movement

Body rotation must never accidentally redefine the velocity vector unless a system explicitly intends that behaviour.

Spark — Physical Vessel / Body-Orb Direction

Spark continued moving away from being only a floating effect and toward a proper companion body/vessel.

The visual setup now treats Spark's body orb as an actual authored body element rather than relying only on the old glow presentation.

Important conceptual split:

Spark body colour
    visual/state communication

Spark emission / glow
    brightness / magical intensity

Spark physical vessel
    authored model / rig presence

Spark non-physical nature
    lore / abilities / limitations

Spark remains conceptually non-physical in the broader lore: Spark can perceive, warn, illuminate and communicate, but needs a physical vessel / the player to manipulate ordinary material objects.

The new orb/body work is therefore useful both visually and thematically.

Spark Colour-State Direction

Spark's body is intended to become a reusable colour-display unit.

Current desired state language includes:

neutral / interact
    gold

friendly
    green

hostile / warning
    red

Colour changes should not snap instantly.

Preferred presentation:

current colour
    ↓
Tween / smooth transition
    ↓
target state colour

Brightness / emission should remain independently controllable from the body colour so Spark can become brighter or dimmer without requiring every colour state to be recreated manually.

The neutral gold state should remain a reusable preset.

Do not hard-code presentation in a way that prevents later state expansion.

Spark Runtime Placement / ReplicatedFirst Investigation

Spark continued being tested around the player's shoulder / peripheral first-person view.

The project has been exploring early/local setup through ReplicatedFirst so companion presentation and player-facing systems can initialise cleanly.

The important rule remains that Spark should:

remain visible
avoid the central aiming region
avoid covering HUD / interaction UI
sit naturally in peripheral view

Exact offsets remain tuning data and should be read from the current source.

Do not blindly restore older offsets from previous changelog sections.

New Steering Wheel Asset — Blender -> Roblox

A new steering wheel was created in Blender and imported into the project.

This replaces the previous steering-wheel presentation used during the earlier seated/IK tests.

Completed work:

new steering wheel model authored in Blender
    ↓
imported into Roblox
    ↓
positioned for the current boat / seated character
    ↓
hand target attachments retuned for the new geometry

The steering wheel remains driven by the boat's steering value / hinge behaviour.

The physical wheel should remain the source of the hand targets rather than compensating for bad IK by moving the entire boat character rig.

Steering Hand IK Re-Rooted for the New Wheel

The steering hand IK was updated to orient correctly to the new wheel.

The arm solve remains intentionally per-arm:

LeftUpperArm
    ↓
LeftLowerArm
    ↓
LeftHand

RightUpperArm
    ↓
RightLowerArm
    ↓
RightHand

The steering targets remain authored attachments on the wheel/handle.

Important rule:

wheel moves / rotates
    ↓
attachments move
    ↓
IK hands follow attachments

The arm IK should not depend on a torso/root chain to keep the hands attached.

The new steering wheel required the target/attachment and IK relationship to be re-rooted / reoriented so both hands correctly follow the new wheel geometry.

Preserve the separation between:

steering hand IK
    interaction constraint

upper-body camera/look behaviour
    presentation

seat/root animation
    vehicle pose

Steering-hand authority remains higher priority than cosmetic torso look assistance.

Custom Swimming — Major Orientation Pass

The custom swimming controller received a substantial orientation pass.

The underlying custom-water physics were already useful:

EditableMesh water detection
neutral buoyancy
camera-relative movement
explicit swim up
explicit swim down
surface hold
graduated exit
water drag / acceleration
wave-motion integration
custom entry splash

The problem was presentation.

Before this pass, the avatar could physically move through the water while remaining vertically oriented or facing the wrong way, making the swim animation look like the character was being dragged through the ocean.

The goal became:

movement direction
    ↓
whole-body swim orientation

without allowing the orientation controller to rewrite the actual physical movement vector.

Swim Animation Intentionally Kept

The existing swim animation was not considered a problem.

The controller continues to use Roblox's built-in swim animation asset:

rbxassetid://507784897

The animation was visually useful for:

surface treading
surface movement
vertical ascent
general swimming

The work therefore focused on rotating the character appropriately around the animation rather than replacing the animation.

Do not delete the working swim animation merely because individual poses need orientation correction.

First Swim-Orientation Attempt — AlignOrientation

A dedicated AlignOrientation was added to the custom swimming controller.

The swim system temporarily disables ordinary humanoid auto-rotation while custom water owns the character.

Conceptually:

enter custom water
    ↓
custom swim orientation enabled
    ↓
Humanoid.AutoRotate yields

leave custom water
    ↓
custom swim orientation disabled
    ↓
previous AutoRotate behaviour restored

The orientation actuator shares the water attachment used around the custom root controller.

The goal is smooth physical rotation rather than teleporting the root CFrame every frame.

The tested orientation responsiveness was approximately:

SWIM_ORIENTATION_RESPONSIVENESS = 12

This remains a tuning value rather than an architectural constant.

Avatar Axis Error Identified

The first orientation implementation used the avatar's LookVector as though that were the head-first swimming axis.

That was wrong for the desired prone swimming pose.

The critical discovery was:

standing R15 character

RootPart.UpVector
    head -> feet axis

RootPart.LookVector
    chest / face forward axis

For head-first prone swimming, the desired swim trajectory needs to drive the character's local Y / UpVector.

Correct conceptual rule:

RootPart.UpVector
    ≈ swim heading

not:

RootPart.LookVector
    ≈ swim heading

This fixed the behaviour where looking straight down could still make the character visually look as though they were swimming horizontally/forward.

Do not revert to a simple CFrame.lookAt() implementation that assumes the normal standing LookVector is the swimmer's long-body axis.

Head-First Underwater Swimming

After correcting the body axis, underwater directional swimming could physically orient the complete character head-first along the requested trajectory.

Desired behaviour:

look forward + W
    swim forward

look downward + W
    rotate head-first down
    physically descend

look upward + W
    rotate head-first up
    physically ascend

camera-relative A / D
    alter horizontal heading

combined input
    produces a combined 3D heading

The character should appear to be travelling in the direction their body is actually pointing rather than translating independently of the pose.

Belly-Down Stability

A later issue appeared when reversing direction.

The character could roll onto their back and remain in a backstroke-like orientation.

The transition itself looked interesting and can be retained briefly as a natural turn/trick, but the final pose should correct itself.

A belly-down stabilisation rule was added.

Conceptually:

head
    points along swim heading

belly / chest
    biased toward world-down

back
    biased toward world-up

This prevents a 180-degree change in heading from selecting an equally valid but permanently inverted orientation.

Desired result:

forward swim
    ↓
hard reverse
    ↓
brief roll / flip transition is acceptable
    ↓
body settles belly-down

Near-perfect vertical swimming is a special case because world-up becomes parallel to the swimmer's body axis and cannot define roll.

For that case, a camera/right-vector-style reference can be used only to resolve roll.

Do not use camera roll reference for ordinary horizontal/reversing swimming because that can reintroduce the permanent backstroke problem.

Surface Swimming Orientation

Surface movement now has different orientation requirements from fully submerged swimming.

At the surface:

avatar should lie into a swimming pose while moving
but
camera pitch should not force the body through the water plane

Surface directional orientation therefore uses a horizontal heading.

The desired surface behaviour is:

W
    swim toward forward surface direction

A
    orient / swim left

D
    orient / swim right

S
    reverse / turn into new direction

no movement
    return toward neutral / treading posture

This remains useful even when the camera is high above the player.

The surface heading must remain stable when the camera approaches a top-down angle.

A camera-up fallback / movement-based horizontal direction was explored specifically so A/D/W/S remain meaningful when the camera LookVector has almost no X/Z component.

Explicit Ctrl Dive Pose

Ctrl, C, or controller B remains an explicit world-down swim command.

Important separation:

movement
    world -Y

visual pose
    head-first downward

Pressing Ctrl should create the same visual appearance as deliberately looking straight down and swimming forward.

The body may smoothly rotate into the dive pose, but that rotation must not bend or redirect the actual world-down movement.

Conceptually:

physicalMovement = -Vector3.yAxis
visualHeading = -Vector3.yAxis

The movement and orientation are still processed separately.

Explicit Space Swim-Up Pose

Space or controller A remains an explicit world-up movement command.

The existing animation looked acceptable during ascent, so the chosen presentation is intentionally different from Ctrl:

Space
    move world-up
    recenter toward neutral / upright treading presentation

The player should not be required to stand head-first along +Y for Space to move upward.

Again:

movement
    world +Y

pose
    neutral / recentered

This reinforces the rule that orientation does not define movement.

Idle Swim Recovery

When directional swimming stops, the character should not remain frozen in a random prone or rolled orientation.

Desired behaviour:

directional movement ends
    ↓
AlignOrientation smoothly recovers
    ↓
neutral / treading orientation

The neutral facing direction can preserve the last useful horizontal heading so the character does not snap to an unrelated world direction.

Roblox Character Controller Library / Ability Beta — Major Integration Investigation

Enabling Roblox's newer Character Controller Library / Ability system changed swimming behaviour.

The custom swimmer had previously worked under the older movement pipeline.

After enabling the beta, a specific regression appeared:

Ctrl / Space orientation
    still worked

ordinary W/A/S/D omnidirectional orientation
    stopped behaving correctly

This strongly suggested that the custom pose maths itself was not the only issue.

The difference was input/ownership:

Ctrl / Space
    captured by our own ContextActionService bindings

W / A / S / D
    passed through Roblox movement / ability pipeline

The new character movement stack therefore became the primary investigation target.

CCL ManagerContext / AbilityContext Architecture Reviewed

Roblox's ability callback architecture exposes a ManagerContext as the first callback parameter.

Fields identified as relevant to Spark include:

managerCtx.AbilityOwner
managerCtx.AbilityManager
managerCtx.BodyParts
managerCtx.ControllerManager
managerCtx.RootCFrame
managerCtx.RootLookVector
managerCtx.RootUpVectorY
managerCtx.TaskSynchronize()

The second callback parameter is AbilityContext.

Relevant state locations:

abilityCtx.Config
    read-only registration configuration

abilityCtx.State
    mutable replicated / rollback-aware state

abilityCtx.Local
    mutable non-replicated scratch state

Custom callback data must live in:

abilityCtx.State
or
abilityCtx.Local

Do not write custom arbitrary fields directly onto the abilityCtx object.

CCL Sensors Identified as a Better Input Layer

The new sensor layer exposes several values that overlap with plumbing Spark had previously implemented manually.

Particularly relevant sensors:

Sensor.LookDirectionInput
    commanded look direction

Sensor.RotateToLookDirectionInput
    whether the character should rotate to commanded look direction

Sensor.IsMoving
    whether movement input is active

Sensor.MoveInput
    movement vector / movement command

Sensor.Ground
    standing on a surface

Sensor.Water
Sensor.WaterSurface
    Roblox-native water state

This is important because the custom controller had previously reconstructed or forwarded some of the same intent manually.

Manual LookVector Pipeline Re-Evaluated

The project already has a local camera-look pipeline similar to:

CurrentCamera.CFrame.LookVector
    ↓
Player attribute
    ↓
ReplicatedStorage.Look RemoteEvent

That remains useful for remote-player look replication and other systems.

However, CCL's:

Sensor.LookDirectionInput

is conceptually the input abstraction that custom abilities wanted from the beginning.

Important distinction:

LookDirectionInput
    commanded direction

RootLookVector
    direction the body is currently physically facing

Do not confuse those two.

For purely local camera-critical presentation, direct local camera information may still be preferable when the CCL-facing value has already lost pitch information.

Roblox Water Sensors Become a Useful Discriminator

A key architectural realisation was that Spark's EditableMesh water not being recognised as Roblox water is useful.

The desired split is:

Roblox-native water
    Sensor.Water
    Sensor.WaterSurface
    Roblox swimming behaviour

Spark custom EditableMesh ocean
    custom water detector
    custom swim controller

Spark does not need to force its ocean to register as Terrain water.

Instead, the absence of native water sensing helps differentiate which movement system should own the character.

The broader switch becomes:

native Roblox water detected
    let Roblox's native swimming architecture apply

custom Spark ocean detected
    Spark custom swimming owns locomotion

ground detected / custom-water exit begins
    return ownership to ordinary Roblox movement

The handoff should begin before the character physically collides with land rather than waiting for the first grounded frame.

Spark's existing graduated surface-exit logic remains useful for this.

Custom Swim State Attributes Proposed

Two custom attributes were selected as the preferred custom-ocean state vocabulary:

IsSwimming
IsSubmerged

Intended combinations:

Situation

IsSwimming

IsSubmerged

Land

false

false

Surface swimming / treading

true

false

Underwater swimming

true

true

Future sinking / incapacitated underwater case

false

true

The distinction is intentional:

IsSwimming
    custom locomotion ownership

IsSubmerged
    physical environmental condition

The attributes should represent relatively slow state changes.

Do not turn attributes into a per-frame physics bus.

Keep values such as:

swimDirection
depthBelowSurface
orientationTarget
surfaceHoldActive

as runtime variables.

A hysteresis gap should be used around the submersion boundary to avoid Gerstner-wave flicker.

Do Not Depend on HumanoidStateType.Swimming for Custom Ocean Physics

The old controller still contained an explicit:

Humanoid:ChangeState(
    Enum.HumanoidStateType.Swimming
)

even though its custom physics did not depend on the Humanoid swimming state.

With the new CCL ability architecture, this call became increasingly undesirable because Roblox's Swimming ability may activate its own controller / movement logic.

The custom EditableMesh ocean should not rely on native HumanoidStateType.Swimming for its physical behaviour.

The long-term ownership rule is:

Spark water detector
    decides custom swimming

Spark buoyancy / velocity
    performs custom motion

Spark AlignOrientation
    performs custom pose

Roblox native swimming
    reserved for Roblox-recognised water

Intermediate test versions intentionally changed one ownership system at a time to isolate regressions.

CCL Turning Conflict Investigation

The new beta introduced/reworked the Turning ability.

The controller was investigated because Humanoid.AutoRotate = false was no longer necessarily sufficient to guarantee that Spark's AlignOrientation was the only system trying to rotate the avatar.

A test version temporarily disabled custom CCL Turning ownership while Spark swimming was active.

Conceptual ownership test:

land
    Roblox Turning owns normal body orientation

custom swimming
    Spark swim orientation owns body rotation

exit custom water
    restore previous Roblox Turning behaviour

This test helped isolate the new movement stack, but the architecture evolved again once CCL look/movement intent became more useful.

Do not assume that permanently disabling Turning globally is the final solution.

ControllerManager.MovingDirection Experiment

The old swim controller used:

Humanoid.MoveDirection

as the input from which it reconstructed forward/right intent.

Under the new Character Controller Library, a test changed this to prefer:

ControllerManager.MovingDirection

while retaining a fallback to Humanoid.MoveDirection.

This improved compatibility with the new movement stack.

The key idea is:

CCL
    provides movement intent

Spark
    decides what that intent means in custom water

Roblox should not be asked to perform custom ocean swimming simply because it supplies the player's movement command.

CCL Intent Bridge — Horizontal Movement Worked

A larger CCL-intent bridge was tested.

The bridge successfully restored useful W/A/S/D movement under the new abilities/controller stack.

However, it introduced a clear limitation:

horizontal intent
    worked

look pitch
    did not survive correctly

look down + W
    no longer produced proper vertical movement

look up + W
    no longer produced proper vertical movement

This was an important diagnostic result.

It proved that the new movement-intent side could be used without proving that the CCL-facing direction was an adequate replacement for the old full camera LookVector.

ControllerManager.FacingDirection Is Not a Complete Replacement for Full Camera LookVector

The first CCL refactor attempted to source both movement and look/facing intent from the new controller architecture.

In practice:

ControllerManager.FacingDirection

did not provide the same behaviour the custom swimmer depended on for camera pitch.

The original custom swimmer intentionally used the complete camera vector:

CurrentCamera.CFrame.LookVector

including its Y component.

That was what made:

look down + W
    descend

look up + W
    ascend

work naturally.

Therefore, replacing the old look vector wholesale was a regression.

Current Swimming Direction — Hybrid CCL + Full LookVector

The current migration direction is hybrid rather than ideological.

Use the new Roblox character-controller infrastructure where it improves ownership/input, but retain the old direct camera vector for true 3D swimming pitch.

Current conceptual architecture:

ControllerManager.MovingDirection
    ↓
W / A / S / D movement intent

CurrentCamera.LookVector
or existing local LookVector source
    ↓
full X / Y / Z camera aim

combine
    ↓
Spark custom 3D swim vector

custom swim vector
    ├─> target velocity
    └─> prone body orientation

This preserves the feature that already worked:

camera pitch + W
    changes actual vertical swim travel

while still benefiting from the new CCL movement-intent layer.

This is the current test baseline after the CCL-intent bridge lost vertical pitch.

The hybrid version still requires live Studio validation before being considered final production code.

CCL Air Momentum / Flopping Investigation

The new movement stack also exposed air-controller behaviour around jumping and entering water.

A specific CCL setting identified during testing was:

local controllerManager =
    humanoid:WaitForChild("ControllerManager")

local airManager =
    controllerManager:WaitForChild("AirManager")

airManager.MaintainLinearMomentum =
    false

The intention is to prevent unwanted new-controller momentum from making the character carry/flip awkwardly into custom-water transitions.

There was also concern about the character physically flopping into the water after jumping from certain parts.

This area should remain isolated from the swimming pose system.

Do not compensate for an air-controller momentum problem by weakening the custom swim orientation maths.

Ground Handoff Direction

Sensor.Ground / ControllerManager grounding is useful for returning ownership to Roblox.

However, the custom swimmer should not wait until literal ground contact before beginning the handoff.

Preferred sequence:

custom surface exit band reached
    ↓
begin reducing Spark swim ownership / buoyancy
    ↓
ordinary Roblox air/ground behaviour increasingly resumes
    ↓
ground sensor confirms support
    ↓
normal Roblox locomotion fully owns character

This preserves the existing graduated water-exit behaviour.

Do not replace the graduated exit with a single hard GroundSensor switch.

Swimming Code Evolution — Superseded Intermediate Versions

Several full controller versions were produced during this session.

They should be treated as experimental snapshots rather than independent systems to merge together blindly.

The progression was approximately:

base custom swimming V2
    ↓
AlignOrientation body-facing attempt
    ↓
surface / underwater orientation split
    ↓
head-first axis correction
    ↓
surface + Ctrl orientation pass
    ↓
belly-down correction
    ↓
custom-water attribute experiment
    ↓
CCL Turning/input test
    ↓
CCL intent bridge
    ↓
hybrid CCL movement intent + old full LookVector

The important lesson is not to stack every intermediate patch simultaneously.

Use the latest working architecture and preserve the reasons the earlier attempts were superseded.

Swim Orientation Do-Not-Regress Rules

Future swimming refactors should preserve the following:

Do not make body orientation drive the velocity vector accidentally.

The character's long head-first swimming axis is the root's local Y / UpVector, not ordinary standing LookVector.

Underwater directional swimming must support full 3D camera pitch.

Look down + W must be able to physically descend.

Look up + W must be able to physically ascend.

Ctrl remains explicit world-down motion.

Ctrl visually uses the head-first-down pose.

Space remains explicit world-up motion.

Space may visually recenter into the useful neutral/treading pose.

Stopping movement should smoothly return to neutral rather than freezing prone.

Surface movement should use stable horizontal orientation and should not let camera pitch force the player through the surface.

Hard direction reversals may briefly look like a roll/trick, but the swimmer should settle belly-down rather than remain in backstroke.

Near-perfect vertical swimming needs a separate roll-reference solution.

Do not remove the working swim animation simply to solve orientation.

Do not reintroduce Roblox-native swimming physics as a requirement for the EditableMesh ocean.

Do not assume Humanoid.MoveDirection is the only authoritative input source when CCL is enabled.

Do not assume ControllerManager.FacingDirection contains the full camera pitch information needed by the old custom swimmer.

The current migration direction is hybrid CCL input + direct/full LookVector where necessary.

Character Controller Library — Current Philosophy Updated

The earlier v0.5.0-dev changelog correctly treated CCL as experimental and warned against rewriting the whole project around it.

That remains true, but the 14 September work showed that selective adoption can be useful.

Updated position:

CCL
    useful for:
        movement intent
        look intent experiments
        ability ownership
        controller handoff
        ground sensing
        future custom abilities

Spark custom systems
    remain authoritative for:
        EditableMesh water detection
        custom buoyancy
        Gerstner integration
        custom swimming velocity
        custom swimming orientation

Avoid both extremes:

DO NOT
    ignore the new CCL architecture completely

DO NOT
    throw away working custom water physics simply to become "native CCL"

Prefer incremental migration.

Future Proper Custom Ability Direction

A future version may move the swimming ownership/input layer into a formal custom CCL ability.

That would allow direct use of:

Sensor.MoveInput
Sensor.LookDirectionInput
Sensor.RotateToLookDirectionInput
Sensor.Ground
managerCtx.ControllerManager
managerCtx.RootCFrame
managerCtx.RootLookVector
abilityCtx.State
abilityCtx.Local

However, the 14 September implementation deliberately stopped short of rewriting all buoyancy/orientation/wave code as a formal ability.

Preferred migration order:

1. make CCL intent bridge behave identically to working legacy/custom swim
2. preserve custom physics
3. validate surface / underwater / Ctrl / Space / exit behaviour
4. only then consider moving ownership into a formal ability module

This avoids discarding a proven water controller merely to adopt a new API.

First-Person / Swimming Integration Rule

The first-person body and custom swimming orientation are now tightly related.

The body must be visible enough that the player can perceive:

surface treading
prone swim direction
head-first dive
head-first climb
roll correction
neutral recovery

Therefore first-person visibility changes must be tested against swimming.

A camera/body refactor is not complete until it has been tested in:

land movement
jumping
surface swimming
underwater swimming
Ctrl dive
Space ascent
boat seating
steering

Do not optimise the FPS camera around walking only.

LookVector Replication — Keep Local vs Remote Purposes Separate

The project already transmits look direction for remote-player presentation.

That system and the custom swim controller have different latency requirements.

Local player:

camera / direct local look
    immediate
    used for local swim orientation / camera / IK

Remote player:

replicated look value
    rate-limited / networked
    used for remote visual presentation

Do not unnecessarily make the local swimmer wait for a throttled networked look update.

The CCL sensor architecture may eventually reduce duplicated local plumbing, but remote look replication remains a separate multiplayer concern.

Updated Movement Ownership Map

The current desired ownership model is:

LAND
    Roblox / CCL normal locomotion

AIR
    Roblox / CCL air controller
    custom systems should not create unnecessary momentum conflicts

ROBLOX TERRAIN WATER
    Roblox-native water sensors / swimming behaviour

SPARK EDITABLEMESH WATER
    Spark custom water detection
    Spark custom buoyancy
    Spark custom target velocity
    Spark custom swim orientation

SURFACE EXIT
    graduated custom-water release

GROUND FOUND
    normal Roblox movement fully resumes

This ownership map should be preferred over multiple systems writing the root simultaneously with no state boundary.

Current Test Matrix

Any future swimming-controller change should be tested at minimum with:

SURFACE
    idle
    W
    A
    D
    S
    camera overhead
    hard 180-degree reverse

UNDERWATER
    idle
    W level
    W while looking down
    W while looking up
    A / D turning
    S reverse
    diagonal combinations

VERTICAL
    Ctrl straight down
    Space straight up
    Ctrl release
    Space release

TRANSITIONS
    jump into water
    surface -> dive
    underwater -> surface
    jump out
    climb / walk onto solid ground

CAMERA
    first person
    third person / zoomed out
    camera looking nearly straight up
    camera looking nearly straight down

INTEGRATION
    CCL enabled
    boat / steering state
    Spark present
    wave surface hold active

Current Known / Open Swimming Questions

The following remain open tuning or verification items:

verify the final hybrid CCL + full LookVector controller restores actual Y movement for look-down/look-up + W;

verify CCL movement intent remains stable with the camera nearly vertical;

verify surface A/D movement continues to orient naturally with the hybrid controller;

verify hard reverse still settles belly-down;

verify custom orientation never fights land Turning after exit;

verify air-controller momentum settings do not create new jump/entry regressions;

decide whether custom IsSwimming / IsSubmerged attributes should remain purely local or be server-replicated on state transitions;

decide when/if to formalise the custom swimmer as a real CCL custom ability;

preserve compatibility with Roblox changing the beta API.

Updated Codex Do-Not-Regress Summary — v0.6.0-dev

PROJECT

Project-facing name remains Spark.

WaterTest remains historical/internal terminology.

The current laboratory is intentionally experimental.

Do not silently remove working systems while fixing another subsystem.

FIRST PERSON

Preserve visible-body first person.

Do not accidentally restore a permanent arms-only FPS mode.

Future zoom should smoothly hide/show the local head rather than hard-switching the whole avatar.

Camera/body changes must be tested while swimming and seated.

SPARK

Spark remains the canonical companion name.

Preserve the existing smaller/HUD-safe presentation unless intentionally retuning it.

Treat body colour and emission as separable presentation channels.

Preserve smooth colour transitions rather than snapping state colours.

Neutral gold / friendly green / hostile red are useful state directions.

Spark's physical vessel/body work should not erase the lore distinction that Spark is fundamentally non-physical without a vessel/agent.

BOAT / STEERING

Preserve the newly authored Blender steering wheel.

Preserve hand targets authored on the new wheel.

Steering hands remain independent per-arm IK chains rooted from the UpperArms.

Hand IK has higher authority than cosmetic upper-body look behaviour.

Do not move the whole body/boat merely to compensate for bad hand IK.

WATER

Spark's ocean is custom EditableMesh water, not Roblox Terrain water.

Preserve independent water detection, wave sampling and buoyancy.

Roblox Water sensors are useful as a discriminator, not a requirement for the custom ocean.

Do not make WaterWaveSampler dependent on CCL.

SWIMMING

Preserve custom buoyancy and velocity.

Preserve the working swim animation.

Preserve head-first prone orientation.

Use the correct avatar head/feet axis.

Preserve belly-down correction.

Preserve Ctrl world-down + head-first-down presentation.

Preserve Space world-up + neutral/recentered presentation.

Preserve neutral recovery when movement stops.

Surface and underwater orientation are intentionally different.

Full camera pitch must remain available for true underwater omnidirectional movement.

CHARACTER CONTROLLER LIBRARY

CCL remains experimental.

Prefer selective migration over a full rewrite.

ControllerManager.MovingDirection is useful movement intent.

CCL-facing direction did not fully replace the old full camera LookVector for vertical swimming.

Do not force the custom ocean into Roblox's native Swimming state merely to use CCL.

Ground/controller handoff should complement, not replace, the existing graduated swim exit.

Preserve the ability to fall back from beta-specific architecture if Roblox changes the feature.

INPUT / LOOK

Distinguish movement intent from look intent.

Distinguish commanded look direction from actual root facing.

The local player should use immediate local look data for responsive presentation.

Remote replicated LookVector is for remote visual replication and may remain throttled.

Do not make local swimming depend on a rate-limited RemoteEvent.

v0.6.0-dev Current Working Direction

The strongest combined direction after the 14 September work is:

Spark
    evolving physical vessel / body presentation
    smooth colour-state architecture
    shoulder / peripheral companion placement

First person
    visible body restored
    smooth Roblox-like zoom remains target
    body/head visibility should transition rather than hard-swap

Boat steering
    new Blender steering wheel
    re-rooted / retuned hand IK
    wheel attachments remain direct hand targets

Swimming
    custom EditableMesh-water physics retained
    swim animation retained
    whole-body prone orientation
    head-first 3D swim axis corrected
    belly-down final orientation
    separate surface / underwater behaviour
    Ctrl explicit dive pose
    Space explicit ascent / neutral pose
    idle neutral recovery

CCL
    enabled as an experimental movement/ability layer
    movement intent integration useful
    native water sensors treated as Roblox-water-only
    custom water remains independently detected
    Ground used as part of movement handoff
    full camera LookVector restored where CCL-facing data lost vertical pitch

The guiding architectural rule going forward is:

Let Roblox provide useful input, sensors and controller infrastructure, but do not throw away Spark's working custom ocean physics merely to conform to Roblox's native water model.

The next swimming work should be incremental validation of the hybrid CCL input + full camera LookVector controller, not another complete rewrite of the water system.