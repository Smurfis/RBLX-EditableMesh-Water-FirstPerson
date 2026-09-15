## v0.6.0-dev — 2026-09-15 — CharacterAbilities/CCL Swimming Ownership and Omnidirectional Water Input

> Developer status: Smurfiend's sanity level is depleting. Spark remains operational.

CharacterAbilities and Roblox's Character Controller Library (CCL) are now active in the project. `SwimmingController.client.lua` has been updated so the custom EditableMesh ocean can coexist with that controller stack without asking Roblox's native water state to simulate a surface it cannot detect.

### SwimmingController — CCL Input Bridge

Swimming now treats player intent and physical motion as separate responsibilities.

```text
ControllerManager.MovingDirection
    -> W/A/S/D movement intent

local camera LookVector
    -> immediate full 3D aim, including pitch

Space / controller A
    -> explicit world-up input

Ctrl / C / controller B
    -> explicit world-down input

combined swim direction
    -> Spark's custom velocity, buoyancy and orientation
```

`ControllerManager.MovingDirection` is preferred over `Humanoid.MoveDirection` when CCL is available. A `Humanoid.MoveDirection` fallback remains for characters whose `ControllerManager` is absent or still being created, which keeps the water controller usable during beta API changes and partial rollout.

Movement intent deliberately does not use `ControllerManager.FacingDirection` as a replacement for the camera vector. The swimmer needs the complete camera `LookVector`, including its Y component, so looking down while pressing W dives and looking up while pressing W climbs. This hybrid input path preserves true omnidirectional swimming while still allowing CharacterAbilities/CCL to own the normal character input pipeline.

Surface and underwater movement remain intentionally different:

- At the surface, movement is flattened for a stable horizontal heading and the surface-hold band prevents camera pitch from pulling the character through the waterline.
- Underwater, the full camera-relative direction is retained for three-dimensional travel.
- Space and Ctrl remain world-vertical commands, independent of the character's current body rotation.
- Directional input drives both target velocity and the head-first swim pose, while idle input smoothly returns the avatar to the neutral/treading pose.

### Explicit Custom-Water Ownership

The EditableMesh ocean still owns its own detection and physics. Entering custom water no longer forces `HumanoidStateType.Swimming`, because that state belongs to Roblox-recognised water and can cause the native CharacterAbilities/CCL water logic to compete with Spark's simulated surface.

On custom-water entry, `SwimmingController` now:

1. records the active CCL controller and the AirController settings that it will temporarily change;
2. selects the AirController as a neutral host for CCL input and sensors;
3. disables the AirController's movement, turning, balancing and retained momentum forces;
4. keeps Spark's existing buoyancy, velocity, surface hold and `AlignOrientation` in control;
5. reasserts that ownership while swimming because built-in abilities may select another controller during their own update.

On exit, the controller restores every captured AirController setting. If the ground sensor already has support, control goes directly to the GroundController; otherwise, the controller active before swimming is restored and normal CharacterAbilities may choose the next state on the following update. The existing graduated surface-exit band is retained, so this handoff does not replace the proven buoyancy and velocity fade.

This creates one writer for each part of locomotion while the avatar is in custom water. CCL continues to provide input, sensors and controller lifecycle, while Spark controls the physics that correspond to the visible animated ocean.

### Character State Contract

The character now exposes two attributes for custom-water state:

- `IsSwimming` is true while Spark's custom water controller owns locomotion.
- `IsSubmerged` is true once the root is sufficiently below the configured base surface.

`IsSubmerged` uses separate enter and exit depths. This hysteresis prevents Gerstner displacement and surface bobbing from rapidly toggling the value at the waterline.

These attributes are the integration boundary for CharacterAbilities, animations, VFX, audio and future state machines. Consumers can react to a stable state transition instead of repeating water-height checks or inferring swimming from a native Humanoid state that does not describe EditableMesh water.

### Why This Architecture Is Better for CharacterAbilities

The controller now separates three concepts that previously risked becoming coupled:

```text
intent
    CCL movement direction + local camera aim + explicit vertical actions

state
    IsSwimming + IsSubmerged + entry/exit transitions

execution
    custom buoyancy + velocity + surface hold + body orientation
```

This is a stronger foundation for CharacterAbilities state machines because an ability can observe or claim the swimming state without needing to know how Gerstner water is rendered or how buoyancy is calculated. Future abilities can use the same state boundary to suspend land turning, alter animation, apply stamina rules or select water-specific actions. The water implementation can also evolve independently without changing the public character-state contract.

The snapshot/restore handoff is equally important. CharacterAbilities may add or change land, air, climbing, dash or interaction states later; swimming no longer assumes one permanent controller configuration. It borrows control for the custom-water interval, restores the previous configuration afterward, and lets the state machine resume from sensed ground or its prior controller.

### Swimming Do-Not-Regress Rules

- Preserve `ControllerManager.MovingDirection` as the preferred CCL movement-intent source and retain the legacy fallback.
- Preserve the immediate local camera `LookVector` for underwater pitch; do not substitute a flattened facing direction.
- Do not force Roblox's native Swimming state for the EditableMesh ocean.
- Keep `WaterWaveSampler`, water detection and buoyancy independent from CharacterAbilities internals.
- Keep `IsSwimming` and `IsSubmerged` as explicit custom-water state signals.
- Preserve submerged-state hysteresis at the animated surface boundary.
- Restore captured CCL settings and controller ownership when custom swimming ends.
- Preserve the graduated surface exit, horizontal surface behavior, full 3D underwater movement and explicit world-up/world-down controls.

### Central Boat and Helm Controller

Boat steering is now sourced from the repository rather than requiring a separate steering script inside each Studio boat model.

`ServerScriptService.BoatController` manages boat models using this hierarchy:

```text
Workspace
└─ Boats
   └─ <Boat Model>
      ├─ BoatSeat (VehicleSeat)
      └─ <Helm Model or Folder>
         └─ Handle (BasePart)
            ├─ HingeConstraint
            ├─ LeftAttachment
            └─ RightAttachment
```

Each boat must be a direct child Model of `Workspace.Boats`. `BoatSeat`, the helm model and `Handle` may be nested within that boat. The controller discovers `BoatSeat` and `Handle` recursively, then maps `BoatSeat.SteerFloat` to the helm hinge's `TargetAngle`.

The default maximum helm angle is 45 degrees. A numeric `HelmMaxAngle` attribute on `BoatSeat`, or on the boat model as a fallback, can override it per boat without duplicating scripts.

The controller binds every existing boat and listens for boats added or removed at runtime. It also refreshes a boat binding when relevant descendants are added or removed, allowing Studio/streamed hierarchies to finish assembling after the boat model appears. There is no per-frame Workspace scan.

`HandsInitializer` now follows the same hierarchy contract. It only enables steering-hand IK when the occupied seat:

- is a `VehicleSeat` named `BoatSeat`;
- belongs to a top-level boat Model under `Workspace.Boats`;
- can resolve a descendant BasePart named `Handle`;
- has valid `LeftAttachment` and `RightAttachment` targets beneath that handle.

Ordinary seats no longer qualify merely because their immediate parent contains something named `Handle`. Leaving the boat, entering a non-boat seat or encountering an incomplete helm clears both IK targets cleanly.

### Spark Intro Iteration — Isolated Place, Pending Import

A new Spark/Fairy intro iteration was created on 14 September 2026 in a separate Roblox place used for isolated development. It has not yet been imported into this repository or its current Rojo project, so it is recorded here as completed external prototype work pending integration rather than current project behavior.

The isolated place contains the newly created systems/assets named:

- `ReplicatedFirst`
- `IntroSpark`
- `NewSparkModels`
- `CameraModes`
- `Behaviours`

This iteration substantially changes Spark's introduction and moves the opening animation into the `ReplicatedFirst` startup flow. Its exact animation sequence, module responsibilities, model hierarchy and camera handoff must be documented from the imported source after it is copied into this project.

Import requirements:

1. preserve the isolated place as the source reference until the repository copy has been validated;
2. import the five named areas without overwriting the current runtime Spark follower or Studio-managed assets blindly;
3. add the imported scripts/assets to the Rojo tree where appropriate, while retaining `$ignoreUnknownInstances` for Studio-managed content;
4. compare `NewSparkModels` with the current `ReplicatedStorage.Models.NPCs.SparkModels` hierarchy;
5. verify the transition from `IntroSpark` to the gameplay Spark does not create two visible companions;
6. verify `CameraModes` returns camera ownership cleanly to the current first-person controller;
7. verify `Behaviours` does not duplicate or conflict with the gameplay follower's movement, focus, animation or visual-state logic;
8. update this section from pending import to integrated only after the actual source and Studio hierarchy are present and tested in the main project.

## v0.5.1-dev — 2026-09-13 Late Night to 2026-09-14 — First-Person Rebuild, Boat and Helm Integration

This milestone began late on 13 September and continued through 14 September. The chronology is recorded from the development session, while the implementation details below were verified by comparing the current working copy with the GitHub-tracked `origin/main` baseline at commit `2c9dee6`.

### 13 September Late Night — First-Person Architecture Rebuilt

`FirstPersonController.client.lua` evolved from a roughly 200-line forced-first-person script into the project's full camera, visibility and upper-body presentation controller.

The earlier version always selected `CameraMode.LockFirstPerson`, locked the mouse, hid the local head/accessories and applied a direct world-space camera offset every frame. That worked as an initial visible-body prototype but could not support normal zoom, a stable seated view or coordinated steering poses.

The replacement establishes a clearer ownership rule:

```text
camera aim
    -> authoritative player view

head / neck
    -> follows camera aim

UpperTorso
    -> limited secondary assistance

hands
    -> retain interaction authority when constrained to the helm
```

The camera is deliberately not positioned from a head or bone whose pose is being solved from that same camera. This prevents the circular `camera -> IK -> head -> camera` feedback that previously caused clipping, drift and unstable seated movement.

Major first-person changes include:

- `CameraMode.Classic` remains active so Roblox can provide normal first-person/third-person zoom.
- Enter and exit distance thresholds use hysteresis so the controller does not rapidly switch modes at the first-person boundary.
- `TrueFirstPersonActive` exposes the current local camera mode to Spark and other presentation systems.
- The local body remains visible in first person while the head and accessories fade out.
- Head/accessory visibility fades back more gently when returning to third person.
- Original transparency and `Humanoid.CameraOffset` values are captured and restored during character cleanup.
- Mouse capture yields to Roblox in third person, while the existing settings and manual mouse-release attributes remain supported.
- Standing look keeps pitch primarily in the neck/head and limits UpperTorso participation, especially while looking down.

This is better suited to the wider Spark project because companion placement, interaction prompts, swimming presentation and vehicle controls can observe camera state without each system trying to own the camera.

### 14 September — Seated Camera and Steering-Safe Body Pose

Seated first person now uses its own controlled camera path while leaving ordinary standing and third-person camera movement with Roblox.

When seated in true first person:

- the camera becomes `Scriptable`;
- its position follows an analytic eye point derived from the UpperTorso-side neck base;
- yaw and pitch use stable accumulated input rather than reading rotation back from the animated head;
- looking down moves the eye point slightly forward and lower to follow the natural skull arc;
- leaving the seat or zooming out restores `CameraType.Custom`, the Humanoid camera subject and the previous camera offset;
- mouse-wheel zoom-out releases the seated Scriptable camera before Roblox resumes its normal zoom.

Two seated look modes share the same implementation:

- `SeatedFreeLook = true` allows approximately 170 degrees of yaw for looking behind while seated.
- `SeatedFreeLook = false` limits yaw to approximately 90 degrees for a tighter helm-focused view.

The head leads the view. LowerTorso-to-UpperTorso IK supplies only a limited shoulder/chest assist as the head approaches its comfortable range. Seated body IK does not move the hips or character root, keeping the avatar planted in the seat.

The controller contains a helper that measures enabled hand IK targets and approximate arm reach. Its intended use is to reduce torso twist as either hand approaches its reach limit, keeping steering and future held-object constraints above cosmetic body turning. In the current working copy, that helper is not yet called by `updateTorsoIK`, so the reach-aware reduction must be treated as designed but unfinished rather than active behaviour.

The controller exposes `SeatedTorsoYaw`, `SeatedTorsoPitch` and `UpperBodyConstraintAlpha` through player attributes for steering and interaction consumers. `UpperBodyConstraintAlpha` is currently written as `0`; it should report the reach helper's result once that integration is completed.

### Boat Model and Port Helm

A boat model and a dedicated helm model were added for the steering prototype.

The boat currently remains Studio-managed and is not represented by a standalone source file in the Rojo tree. Its Roblox model backup must preserve the `VehicleSeat`, steering assembly, constraints, hand-target attachments, water-interaction tags/attributes and authored physical properties.

The repository contains the Blender-authored helm source:

`Models/PortHelmSteering.fbx`

The helm replaces the earlier temporary steering-wheel presentation with a purpose-built, chunky stylised wheel. The documented Studio runtime relationship is:

```text
VehicleSeat.SteerFloat
    -> steering hinge target angle
    -> helm/handle rotates
    -> LeftAttachment and RightAttachment move with the handle
    -> per-arm IK keeps each hand on its authored target
```

Each arm uses its own Transform `IKControl`, rooted at `LeftUpperArm` or `RightUpperArm` and ending at the matching hand. The IK controls activate only when the character is seated in a model with a valid `Handle`, `LeftAttachment` and `RightAttachment`, and they clear their targets when the character leaves the seat.

The hand controls use higher priority than the camera controller's torso assistance. This lets the avatar look around while steering without allowing cosmetic torso movement to detach the hands or move the whole boat rig.

### Supporting Working-Copy Changes Reviewed Against GitHub

`Water.client.lua`:

- `FAR_FILL_ENABLED` changed from `true` to `false`.
- The separate far-water fill is currently unnecessary while the four base water parts provide the intended coverage, and it was not visibly contributing even at high render distance.
- This disables only the flat far-fill coverage path; it does not simplify or replace the EditableMesh wave renderer.

`PlayerWaveMotionController.client.lua`:

- The comparison contains one added blank line.
- There is no functional runtime change to record for player wave motion in this working-copy delta.

`SlimePickup.server.lua`:

- `ProximityPrompt.ClickablePrompt` is now `false`.
- The Slime prompt no longer accepts direct click/tap activation through the prompt UI, reducing accidental pointer-driven pickup while the first-person camera, mouse-release mode and interaction controls share input.
- Existing proximity, line-of-sight, pickup, drop and water-interaction behaviour remains intact.

`SwimmingController.client.lua`:

- The later CharacterAbilities/CCL input, state and ownership work is documented separately in `v0.6.0-dev` above.
- Its full omnidirectional movement and custom-water state contract should not be duplicated into this earlier milestone.

### Why This Milestone Matters

The late-13/14 September work turns the camera, body and helm from isolated experiments into cooperating systems with explicit priorities. Roblox owns normal zoom and third-person camera behaviour; the custom controller owns only the first-person presentation it needs; head and torso follow that view within anatomical and interaction limits; hand IK owns physical helm contact; and boat motion remains separate from camera pose.

That division is compatible with the CharacterAbilities direction because camera mode, seated pose, swimming state and controller ownership are exposed as state boundaries rather than inferred through competing root or bone writes. Future boat steering, held-object abilities, Spark behaviours and water abilities can respond to those boundaries without replacing the first-person controller.

### Known Integration Gaps at This Snapshot

- `FirstPersonController.client.lua` publishes `TrueFirstPersonActive`, while the current `SparkFollower.client.lua` still reads and listens to `FirstPerson`. Until those names are unified or bridged, zooming between first and third person will not automatically switch the current follower between its two placement modes.
- `getUpperBodyConstraintAlpha()` is implemented but not consumed by `updateTorsoIK`; the published `UpperBodyConstraintAlpha` therefore remains `0`.
- The boat, steering hinge script and assembled helm hierarchy remain Studio-managed, so only the `PortHelmSteering.fbx` source and related IK code can be verified from this repository.
- `PlayerWaveMotionController.client.lua` has no behavioural delta from `origin/main` despite appearing modified.

This update replaces the earlier temporary steering-wheel presentation with a purpose-built Blender steering wheel and corrects the orientation / hand-target problems that were still present in the boat steering prototype.

The existing seated first-person and body-look architecture remains valid and should not be rewritten as part of this steering-wheel work.

The steering changes are additive.

### New Blender Steering Wheel Asset

The boat now uses a newly modelled steering wheel created specifically for Spark rather than continuing with the earlier placeholder / simpler steering-wheel geometry.

The new wheel deliberately keeps a chunky stylised appearance rather than attempting to become a realistic high-detail ship wheel.

Current visual direction includes:

```text
large faceted outer wheel
chunky steering handles
central hub
raised inner rim band
raised outer rim band
rear shaft / support geometry
simple stylised construction

5e4c6a2e-765c-49eb-b0d3-afeda4e06f8b.png
So now hes ingame I need to clean him up and really find a way to set surfaceappearance for wings as they are just being given a mesh texture

1128d052-f31d-43f0-96aa-f76c39b612ef.png
Textures is one thing but his bones is another!


Pasted text(20260912-170324).txt
Document
I think this was it when I updated it to have trails but it did a lot more than that so we need to simplify


Pasted text(20260912-175227).txt
Document
  17:52:17.076  Workspace.neepstars2833.SparkFollower:145: attempt to perform arithmetic (mul) on Vector3 and nil  -  Client - SparkFollower:145
  17:52:17.076  Stack Begin  -  Studio
  17:52:17.076  Script 'Workspace.neepstars2833.SparkFollower', Line 145 - function getLookedAtSlime  -  Studio - SparkFollower:145
  17:52:17.077  Script 'Workspace.neepstars2833.SparkFollower', Line 157 - function onUpdate  -  Studio - SparkFollower:157


Pasted text(20260912-180900).txt
Document
Update the full code

UpperTorso IK included at a certain degrees then I suppose but only looking behind us try to account for no headbutting the steering wheel t.r



Pasted text(20260912-184826).txt
Document
Alter full code to reflect:



Pasted text(20260912-190340).txt
Document
My arms respond when seated, the uppertorso leaning forward and back seems turned off now only thing to do is get the LowerTorso and UpperTorso rotating with me when I turn my head past 90 degrees left or right and fix the weird camera issue bug we spoke about cool! Obviously IK needs to toggle itself at 90 degrees left or right and turn itself off as we come back cool.


Right now our head is sort of just behind our characters neck so it may be nice to move it forward slightly and really get the position of our characters head or eyes so as he leans forward our body isnt ripped into position lol

If I look down I see neck and back.

0bb2a19d-4941-42ec-a7f6-18bf6eba00fb.png
Our camera is still not where our characters head is so we still arent actually looking controlling our head rotation anymore either


e03c2b5d-df2f-459d-afff-724474560460.png
Look what happens when I look down


Pasted text(20260912-193006).txt
Document
Here's the code for you to do so

cf096de3-75d6-48b2-8662-3a5d855330ee.png
bef4b5ff-c89a-4f73-855b-e2867ed4ed92.png
Heads rotating, shoulders rotating seated camera broken need to fix that, also the rotation of our characters torso when we lean forward and backwards should still be there when were holding the steering wheel we just should only be able to look so far up and so far down to prevent the headbutting thing we can look at our feet just no headbutting the steering wheel is what I want and here is the angle I have when I look behind me my head when sat down isnt correcly positioned they are more positioned at my hand?

Still have issues with if I continue to look right as well camera doesnt move as much but my characters uppertorso if I keep looking right  right, right eventually he snaps forward again instead of actually just freezing looking in the direction we are actually looking you can see from the second image I am looking 90 degrees camera is too infront of our torso not in our head.

Also the rotation as I said if I look down my head still isnt fixed either so thats the issue our camera should probably be fixed to our head with an attachment that rotates or something that actually uses slightly above our neck attachment or something idk


Screen Recording 2026-09-12 194714.mp4
File
Looking down is also problematic as I said


Screenshot 2026-09-12 194940.png
As I lean down my camera should really be here.


Analyzed
Yep — and the recording makes the issue clear: when you pitch down, the body/head moves but the camera is staying too high/behind, so you end up looking down onto your own back. Your marked image is the right target: the camera should physically travel with the head as the character leans.

I also backed out the part that was breaking the boat. The previous version directly changed the Root/Waist C0, which was too invasive for a seated rig. This new version leaves the seat/base animation intact and adds the seated twist/lean through Motor6D.Transform instead.

Download the revised FirstPersonController

The important change is now:

camera rotation
      ↓
head + torso pose
      ↓
actual Head.Position moves
      ↓
camera POSITION follows Head.Position
But the eye offset itself does not rotate downward with the head. It's just:

Head.Position
+ small world-up eye offset
+ tiny horizontal forward offset
So as you lean down, the camera should move forward/down with your skull toward the position you marked, rather than remaining above your shoulders.

For seated turning, I also removed the seated LookAt IK entirely. That solver was almost certainly responsible for the body eventually deciding to snap forward at extreme angles. The new seated yaw is deterministic:

0°–90°      head/neck
90°–170°    Root + Waist progressively join
170°        stays there indefinitely
Holding the mouse farther right at the 170° limit shouldn't change the body solution anymore.

And seated vertical movement is restored: looking down gives the body a small forward lean, capped at about 12°, while the head supplies the rest of the downward look. So you can look at your feet without allowing the entire torso to fold into the steering wheel.

This is the version I'd test before we touch CharacterLean, because I've deliberately made it additive to whatever seated/boat animation is already running rather than replacing it.


FirstPersonController_HeadTracked_SeatSafe.lua
Code



Pasted text(20260912-195658).txt
Document
This worked pretty well the only issues where really when we was seated in the boat we needed to move our camera so it was more in our head and not infront of our torso

And that when we leaned forward there was issues. everything else kind of worked.

Screenshot 2026-09-12 202623.png
Screenshot 2026-09-12 202628.png
I took left and right photo for your enjoyment

c7467e23-0db2-4735-9635-f2d9a0a60ed4.png
The attachment is not the issue



Pasted text(20260912-203937).txt
Document
It would probably be good to instate some sort of chain behaviour so the torso tilts with us and can change priority based on the distance of the objects

You have the freedom to try and change first person camera behaviour to how it should behave as I believe it is the culprit



Screen Recording 2026-09-12 204607.mp4
File
I think we just restrict it and make it so you can only rotate yourself so far so the arms stay attached possibly we keep it at 90 degrees and your shoulders turn slightly with you, you cannot look behind you we can add a glass mirror for reflections to look behind you but this isnt very instinctive for reversing at all.

It's a bit of a long clip considering all I do is look left and right but perhaps we have the torso move so we dont fuck it up our hard work so far torso just moves downard to ensure it doesnt rip from the arms ?


Pasted markdown(7).md
File
I need changelog entries for every single thing we did today super indepth so codex can know do not put anything relating to link or navi spark only references for spark.


Not necessarily — it means you probably no longer need foot IK for physical stability/grounding, but you may still want it for visual foot planting.

With the Character Controller Library, the ControllerManager/GroundController handles the character’s actual ground interaction, and the floor sensor can tell you the sensed part, contact point (HitFrame) and surface normal (HitNormal).
 So for a rigid buoyant object that is physically pitching and rolling with your Gerstner system, I’d let CCL handle standing on it rather than forcing the feet to determine where the character physically belongs.

The split I’d use is:

PHYSICS / GROUNDING
Character Controller Library
GroundController
GroundSensor
platform contact-point movement

VISUALS
optional foot IK
LeftFoot / RightFoot
raycast or sampled surface
tiny pose correction only
So if you're standing on a boat/plank/crate that itself is moving with the ocean, try no foot IK at all first. CCL may already make the character look acceptable because the feet are landing on an actual collidable surface.

If the feet visually hover or clip when the platform is significantly tilted, then add foot IK back as a purely cosmetic layer:

GroundSensor says:
    we're standing on BoatDeck

Left foot raycast
Right foot raycast
        ↓
find each individual contact point
        ↓
IK adjusts legs a few studs/degrees
IKControl is still useful for that kind of procedural pose correction; CCL doesn't replace the animation/IK system itself.

For your ocean itself, there is a crucial distinction.

If the visible ocean is an EditableMesh visual surface with no matching collision surface, CCL cannot magically put the feet on the visual wave. Its ground sensor detects BasePart surfaces using Roblox's floor-detection logic.

So:

actual floating Part / boat / crate
→ CCL can physically stand on it
→ foot IK optional visual polish

pure visual Gerstner ocean mesh
→ CCL does not know the visual crest is "ground"
→ your WaterWaveSampler still has to provide the wave position/normal
→ IK can use that data if you ever want feet visually contacting it
And for your project, I think this is actually a simplification.

I would stop trying to make the legs responsible for following the ocean-impacted object. The object and CCL should handle that. Foot IK should only answer:

“Given where the character already physically is, where should this individual foot visually sit?”

That should also greatly reduce the chances of the IK fighting swimming, UpperTorso look IK, CharacterLean, platform riding, and the new controller all at once.

So I'd test in this order:

CCL + buoyant platform, no PlatformRider, no foot IK.

If standing/rotating works physically, leave it alone.

Only if the feet visibly float/clip, add lightweight foot IK using the detected platform surface/normal.

Never use foot IK to move the HumanoidRootPart to follow the platform.

That would make your foot IK a polish system instead of a fundamental part of your water physics, which is a much healthier architecture.


We can add it to a future todo for now we can later move on to fixing the feet into the IK but for now I think we just stick with keeping without it as its a beta feature we dont want to heavily invest roblox scrap it or no one like it so on

Yeah, that’s the sensible call.

For now I’d treat CCL as optional infrastructure we’re experimenting with, not something the project architecture should become dependent on.

So the rule becomes:

FOR NOW

Character Controller Library:
    enabled for testing

Custom platform-rider / foot IK:
    do not rebuild around CCL yet

Feet on Gerstner-driven objects:
    accept default animation/contact for now

Existing water-wave sampling:
    keep independent of CCL

Do not make core water systems require beta-only APIs
And I’d add this future TODO for Codex:

### TODO — Character Controller Library / Foot Planting

Status: Deferred while Roblox Character Controller Library remains a beta feature.

Do not heavily couple the water, buoyancy, platform-riding, camera, or animation architecture to the Character Controller Library yet.

Current approach:
- Allow Roblox/CCL to handle normal physical grounding where possible.
- Do not use foot IK as a requirement for standing on Gerstner-driven or buoyant objects.
- Do not use foot IK to move HumanoidRootPart or physically carry the character.
- Keep WaterWaveSampler and buoyancy systems independent from the character-controller implementation.

Future investigation:
- Re-evaluate CCL once the feature is more mature/stable.
- If retained, investigate GroundSensor / ControllerManager data for moving-platform support.
- Add optional cosmetic LeftFoot / RightFoot IK for visual foot planting on tilted floating objects.
- Foot IK should only correct the visible leg/foot pose.
- Physical grounding and platform movement should remain the responsibility of the character controller / physics layer.
- Test independently with swimming, boats, Gerstner platforms, CharacterLean, first-person head/torso IK and steering-arm IK.

Reason for deferral:
The Character Controller Library is currently a Roblox beta feature. Avoid significant project investment or architecture lock-in until its long-term behaviour and support are clearer.
That keeps the door open without spending two days engineering perfect feet around something Roblox may substantially change before release.

And visually, slightly imperfect feet on a rocking crate are a far cheaper problem to tolerate right now than unstable swimming, cameras, boats, or grounding.



Pasted text(20260912-212144).txt
Document
We should alter the whole changelog and tell it what we did I moved the fairy as well and rescaled him changing code to ScaleTo 0.5 and repositioning him so he sits nicely below our UI

 we should probably mark version numbers as well as the project name is even changing from water test to "Spark"



Called tool
Yes — I’ve now reworked the changelog as a project-history document for Spark, rather than continuing to treat it as merely “WaterTest with additions.”

Download the rewritten Spark changelog — v0.5.0-dev

The biggest structural changes are that the document now identifies the project as Spark, treats WaterTest and RBLX EditableMesh Water First Person as historical names, and introduces development milestone versions from v0.1.0-dev through the current v0.5.0-dev. I explicitly note that these are documentation/development milestones rather than pretending they were historical Git tags. The older changelog genuinely still described the project as the water prototype and contained the earlier Spark follower offsets, so those needed to be marked as historical rather than current.




I also added today's newest state properly: Spark now uses:

sparkModel:ScaleTo(0.5)
and his follower position has been retuned so he sits comfortably below the HUD/UI, instead of competing with interface elements. The old offset values are retained only as historical tuning references, with a warning to Codex not to restore them blindly.

The Character Controller section has also been corrected based on what we discovered after the previous changelog revision. It now records that Legacy fixes the moving-platform problem and disabling WaterPlatformRiderController also fixes it, so the current diagnosis is an incompatibility between the beta Character Controller Library and our legacy-style full-root platform carry—not “Gerstner is broken” and not “UpperTorso IK definitely causes the physical failure.” The previous document only had this as an unresolved suspicion.


It additionally records the deferred decision on feet: no major foot IK / CCL platform rewrite for now. CCL remains experimental, sprinting remains deliberately disabled, water/wave systems should stay controller-independent, and cosmetic foot planting is a future task if the beta proves worth keeping.

And I validated the final file to make sure the two companion names you specifically banned do not occur anywhere in it. All companion references are Spark.


CHANGELOG_SPARK_v0.5.0-dev.md
Document


CHANGELOG_SPARK_v0.5.0-dev.md


Changelog — Spark
Development log for Spark, covering 9–12 September 2026. The project began as the WaterTest / RBLX EditableMesh Water First Person laboratory and is now being renamed and reframed as Spark. The water, swimming, first-person, boat, buoyancy and interaction systems remain part of the project; they are no longer the identity of the project by themselves.

Historical repository references may still use Smurfis/RBLX-EditableMesh-Water-FirstPerson. That is a legacy technical/repository name unless and until the repository itself is renamed. Current project-facing documentation, comments and new systems should use Spark.

The 9–10 September sections are reconstructed from Git history and Studio notes. The 12 September section records the detailed Spark, first-person, boat, steering, IK, Character Controller Library and movement-controller work completed during the development session, including failed/superseded experiments so Codex does not accidentally restore them.

The repository itself begins on 9 September 2026. Experiments before the first commit are not represented in Git history.

Project Identity and Development Versions
Current project name: Spark

Former working/project names: WaterTest, RBLX EditableMesh Water First Person

Current development version: v0.5.0-dev

The version numbers below are documentation/development milestone labels. They describe meaningful project states for Codex and future development. They should not be interpreted as historical Git tags unless matching tags are created later.

v0.1.0-dev — 2026-09-09
    Initial standalone water / first-person foundation.

v0.2.0-dev — 2026-09-10
    Immersive ocean pass: far water, swimming, underwater presentation,
    shallow-water audio and stylised surface work.

v0.3.0-dev — 2026-09-10
    Shared wave sampler, buoyancy, WaterInteractable objects,
    deformation experiments and moving-platform/player wave work.

v0.4.0-dev — 2026-09-10
    Settings/HUD, water-contact feedback, replicated splash rings,
    additional water polish and laboratory tooling.

v0.5.0-dev — 2026-09-12
    Project identity changes to Spark.
    Spark becomes an actual modelled/rigged companion.
    Major first-person/seated-camera and steering IK development.
    Character Controller Library beta experimentation begins.
Versioning rule going forward:

patch-level dev updates
    tuning, fixes, assets, small interaction improvements

minor dev versions
    meaningful new playable/system milestones

1.0.0
    reserved for a genuinely release-ready project state
Codex naming rule:

WaterTest is historical context. Spark is the current project identity. New project-facing code comments, documentation and UI should not rename the project back to WaterTest.

## Project Origin

This project began as an experiment based on a Roblox water tutorial:

<https://www.youtube.com/watch?v=NmJweT_IbBw>

The original goal was a convincing animated ocean. It expanded into a first-person water project focused on immersive Roblox water: custom EditableMesh waves, swimming, underwater visuals, shoreline effects, audio, large-ocean rendering, and stylized presentation.

What began as a first-person water simulation is now becoming Spark: a broader first-person exploration and interaction project built on the water laboratory's reusable ocean, swimming, buoyancy, boat, camera and environmental systems. Water remains foundational technology, but Spark is now the project identity.

## v0.1.0-dev — 2026-09-09 — From Tutorial Experiment to Water System

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

## v0.2.0-dev — 2026-09-10 — Turning the Prototype Into an Immersive Ocean

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

## v0.3.0-dev — 2026-09-10 — Shared Waves, Buoyancy and Player Tracking

Work in this section is on `water-gerstner-buoyancy-test`, created from `b45789e`. The prototype remains separate from `main`.

### Shared Wave Sampler / Gerstner Experiment

`fd8fa03` extracted the existing wave field into `ReplicatedStorage.Modules.WaterWaveSampler`. The renderer and interaction controllers now share deterministic wave data and one time origin. This retained seed `1337`, 14 maximum octaves, exponential swell shaping, recursive sampling and horizontal choppiness, together with the existing renderer's mesh, layers, scheduling, LOD and far-water coverage. Queries expose height, displacement, position and a finite-difference normal.

The Gerstner experiment uses the ocean's existing stylized wave implementation; it did not replace the wave field with a new textbook Gerstner formula. Floating objects sample those same waves, with profile-specific filtering.

Profile names are case-insensitive and `medprop` resolves to `MediumProp`. The temporary calmer response experiment was reverted after confirming the frantic behavior came from a large prop configured as `SmallProp`; the original MediumProp profile remains unchanged.

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

## v0.4.0-dev — 2026-09-10 — UI Changes and Replicated Splash Rings

### Settings and First-Person HUD

The settings/HUD work from `97bbb9f` through `3f2fdca` added the `ReplicatedStorage.UI.Checkbox` Rojo mapping, an animated scrollable settings panel, water-opacity and camera-sensitivity slider controls, and a compact keybind HUD option. Final controls use `SETTINGS: [=]` and `Free Mouse: [M]`, with tappable controls for mobile. Opening settings releases the cursor; closing it restores first-person lock.

The HUD uses cartoon styling, a centred server identifier and a separate responsive top-right title/version/FPS group. FPS is capitalised and appears beside the version. Mouse initialisation and icon state were corrected: the icon is visible while locked, hidden while released, and a small centre reticle indicates first-person lock.

Compact keybind HUD mode now keeps the key symbols visible (`[=]` and `[M]`) while removing only the descriptive words. Toggling compact mode also reveals both keybind icons so the first transition remains visually clear.

Settings now includes independent `Wave foam transparency` and `Coastline transparency` sliders, initialized to the current visual defaults. The Coastline slider drives both parts inside `__ClientCoastlineEffect` together, preserving their shared fade and movement while allowing the foam and coastline systems to be tuned separately.

Settings also includes `Remove CoastLine Effect` and `Transparent Ocean` toggles. Both toggles can detach the two client Coastline VFX parts for a performance-friendly transparent-water view and restore them later; the ocean layers themselves remain available for separate transparency tuning.

The underlying ocean color layers remain coupled to the foam appearance; `Transparent Ocean` therefore only detaches the Coastline VFX folder and does not hide individual water passes.

Added an isolated `Workspace.Slime` pickup test object setup. Slime is tagged as a `SmallProp` water interactable, can be picked up with its ProximityPrompt, and dropped with `G` for buoyancy testing.

Slime now supports Model setups using its `HumanoidRootPart` as PrimaryPart and produces a local ring plus splash-particle burst when it falls through the water surface.

Added lightweight client-only underwater bubbles. ForceField spheres spawn at a distance from the camera, rise, expand, and fade without collision.

Swimming now explicitly plays Roblox's built-in swim animation across surface and underwater movement, then fades it out on exit so the normal standing pose returns.

While held, Slime no longer collides with the player, and pressing `E` again throws it forward with an upward impulse. Experimental arm posing was removed until a proper authored animation is available.

Slime now receives a faint `(255, 212, 138)` hover highlight and a matching falling trail that disables when it reaches the water.

Removed the held-object orientation constraint again after testing showed it could interfere with first-person camera rotation; held Slime now uses position alignment only.

The falling trail now uses texture `138569364097517` with a soft green tint.

Transparent Water is now an explicit toggle. While enabled it exposes individual sliders for `WaveFoamVFX`, `WaterSurface`, `WaterMiddle`, and `WaterBase`, starts at 0.3 / 0.6 / 0.8 / 0.95 transparency, and detaches the Coastline effect. Disabling it restores the normal authored layers.

Added a reversible `Disable Fancy Ocean` toggle. It detaches the generated ocean layers while leaving `__ClientCoastlineEffect` visible as the remaining ocean VFX; switching it back restores the same generated instances.

The Coastline visibility control is inverted for clarity: slider value `1` keeps the effect at its minimum 45% transparency, and the effect can only become more transparent from there. `CALM OCEAN` is stored as the calm preset within the `WIND WAKER` visual family.

The developer water-tuning panel introduced in `4e6f7c3` was reverted in `6e0ef29` at the user's request. Only removal of the Player Reflections option was retained; developer sliders and their renderer changes are not part of the final state.

### Replicated Water-Contact Splash Rings

`0ca845a` added local detection of downward crossings into the configured water-entry band and a server handler for splash requests. The server checks request type, distance from the player, proximity to the base water surface and a cooldown, then clones the Studio-authored `ReplicatedStorage.Shared.Assets.SplashRing` Part into Workspace. Rings expand to 2.5 times their starting size and fade over 0.7 seconds before cleanup, making the effect visible to other players. The Rojo project now maps `ServerScriptService`.

This is replicated visual feedback at the configured base surface. It does not establish server authority for the separate buoyancy prototype.

The follow-up paddle pass separates airborne entry from surface contact. An entry ring is armed only after the player has clearly left the water, so holding Space or small surface bobbing cannot repeatedly fire the entry effect. While `SurfaceHold` is active, hand movement near the waterline emits a restrained ring at most once every 0.85 seconds, creating the requested paddling response around the player's hands.

The paddle trigger now follows horizontal swimming speed and alternates hands. It places each smaller ring 1.35 studs ahead of the active hand at the CoastLine/waterline, so forward and backstroke swimming produces the pushing-water illusion even when the hand animation remains visually above the surface. Paddle rings start 0.45 studs above CoastLine, tween down into it, remain throttled at 0.62 seconds, and are 5% larger than the previous paddle size.

The entry ring now starts 10% wider and 50% thicker vertically, with a slightly longer fade, so the first jump into the water reads clearly before disappearing.

Shallow-water walking audio now checks the shared animated wave height at each foot rather than only the fixed base surface. The footstep band was widened slightly so standing and walking through visible wave crests keeps the water sound active instead of falling back to solid-ground audio.

Walking just above the shoreline now also emits a small replicated `WaterFootstepRing` at the detected foot. These rings start slightly above CoastLine, settle into the waterline and fade quickly, creating a subtle bubble/splash contact without using the heavier entry effect.

Footprint placement uses the sampled animated surface for shallow-water audio while the ring eligibility is tuned to the measured lower-CoastLine contact plane. Audio can remain active across a broad shallow-water band, and the ring contact tolerance is widened to 0.75 studs so the measured foot position is captured; it starts slightly above contact and settles into the CoastLine touch.

The foot contact plane is now explicitly tuned to the measured shoreline marker at Y=7.458 (`WaterConfig.Swimming.SurfaceTest.FootContactOffset = 1.458` for the current base surface Y=6). Foot rings emit at or below that plane, then settle from 0.08 studs above it.

Footstep rings use `SmoothPlastic` instead of the ForceField material used by entry and paddle rings, making the smaller shoreline contacts visibly distinct.

Shallow walking now uses the Studio-managed `ShallowFootsteps` sound. Its three-second clip loops while movement continues, plays for up to one second after a short movement, and stops when the player leaves the shallow-water band. The per-foot shoreline rings remain tied to the movement cadence.

When movement stops, the sound now pauses immediately at its current position instead of continuing through the rest of the clip; it resumes and loops again when shallow movement resumes.

The pause state is tracked locally because Roblox `Sound` has no `PlaybackState` property; this removes the runtime error reported by Studio.

Underwater visuals now compensate for night lighting. Between 18:00 and 06:00, deep-water brightness is lifted by up to 0.35 and the black overlay is reduced by up to 45%, preventing 24:00 underwater scenes from becoming unreadably black while preserving the daytime depth treatment.

The shallow sound no longer restarts on every footstep tick, preventing rapid looping. A single delayed exit ring and particle burst is also emitted when the player leaves the pool, allowing a clean jump-out and re-entry effect without repeated triggers.

While shallow water is active, captured Roblox `Running` sounds are now explicitly stopped as well as muted. This prevents the default footstep system from restarting or cutting across `ShallowFootsteps`; normal running sound volume is restored after leaving the water band.

The shallow eligibility check now includes the calibrated foot-contact plane, rather than requiring the foot to be inside a lower animated-crest window. This keeps rings active on the Y=6.901 shoreline floor even when the local wave sample is lower, and the root-height allowance is raised to six studs for that near-surface edge.

The controller now checks for that Studio sound without an infinite wait. If it is absent or misnamed, it warns once and falls back to `WaterSplashEntry` so shallow-water movement remains functional until `ShallowFootsteps` is placed under `ReplicatedStorage.Shared.Sounds.Water`.

Raised the shallow-footstep detection margin from 1.0 to 1.4 studs so walking on a floor around Y=6.901, just above the visible wave threshold, still processes shallow-water footsteps. Footprint placement remains governed by the measured Y=7.458 contact plane.

The replicated splash rings now emit the supplied rainsplash texture (`rbxassetid://105796658952670`) from their centre. Jump entries use a larger 18-particle burst, paddle rings use a restrained three-particle burst, and footstep rings use a small four-particle burst.

### Source Assets

- Moved the unchanged wave-line texture to `Imgs/AlphaMaskOverlay/WindWaker_WaveLines_01.png`.

- Added `Imgs/Decals/SpawnLocationDecal.png`.

- Added audio source files `Sounds/Water-Splash-Entry.mp3` and `Sounds/Water-Surface-Idle.mp3`.

These files are repository source assets; Studio-managed instances and uploaded asset IDs remain configured in Studio.

### Validation and Open Testing Issue

The development chat records successful Rojo builds/sourcemaps, Luau compilation and player-wave controller regression checks during implementation. Those checks do not prove visual parity, physics behaviour or multiplayer stability in Studio.

The final chat investigation recorded `RBXCRASH: OutOfMemoryGraphics` and out-of-memory messages during Studio client/server testing. Graphics-memory pressure remains an open testing issue; no crash fix was committed. Single-client testing or lower Studio graphics quality was suggested for further investigation.

## v0.4.0-dev Snapshot — Water Laboratory Before the Spark Rename

At the end of the initial water-only phase, the laboratory had become a standalone first-person water prototype with:

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

At this milestone the goal was to make first-person water in Roblox feel more immersive, reactive, cinematic, and visually interesting than Roblox water by default. This remains a core technical goal inside Spark, but no longer describes the whole project.

## v0.4.x Notes — Experiments Proposed Before the Spark Rename

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

## v0.5.0-dev — 2026-09-12 — Spark, First-Person Body IK, Boat Steering and Camera Stabilisation

This section is intentionally much more detailed than the earlier daily summaries. A large amount of first-person, seated-camera, body-IK and steering work was iterative, and several approaches were found to be unstable or anatomically wrong. The purpose of recording the rejected approaches as well as the working architecture is to stop future automated refactors from reintroducing the same failures.

### Naming / Lore / Code Terminology Rule

The companion used throughout this project is Spark.

Use Spark in prose, code comments, model names, animation names, variables and future documentation. Do not substitute unrelated franchise character names or legacy comparison names into project code or changelog entries.

Current canonical Spark model path:

ReplicatedStorage
└── Models
    └── NPCs
        └── SparkModels
            └── Spark
The folder name is NPCs, not NPC's.

### Spark Visual Direction

Spark was advanced from a simple particle-like fairy concept into a proper tiny animated companion model.

Current visual direction:

small white glowing orb
+ two stylised symmetrical wings
+ bright emissive presentation
+ no metallic decorative orb texture
+ wing silhouette is the main identity
The body is a Blender Icosphere at subdivision 3 / approximately 320 faces. That geometry count is intentionally small and is not considered a meaningful performance risk compared with transparency, particles, lights, overdraw and draw calls.

The body material direction is:

Base Color      white
Metallic        0
Roughness       ~0.35–0.50
IOR             1.5
Alpha           1
Emission        white
EmissionStrength ~2
The wing material direction is:

Image Texture Color -> Base Color
Image Texture Alpha -> Principled Alpha
Image Texture Color -> Emission Color

Metallic         0
Roughness        ~0.35
IOR              1.5
EmissionStrength ~3
double-sided
Backface Culling off
wing shadows preferably disabled
A separate wing ColorMap / transparency workflow was established so wing colour and emission can be controlled independently. The transparent background must be actual RGBA alpha; a black background is not equivalent to transparent alpha when used as a Roblox SurfaceAppearance.ColorMap.

The project also explored keeping a separate black/white or alpha emission mask over the coloured water/wing texture so glow can be driven independently from colour. This same principle is useful for the stylised ocean overlay: colour presentation and emissive presentation should not be forced to share the same texture behaviour.

A wing image/texture around asset ID rbxassetid://118587989725082 was used during this work. Treat that ID as a current asset reference, not a permanent naming convention.

### Spark Blender Rig

Spark uses one armature with a simple rigid hierarchy:

Armature
└── Root
    ├── Wing_L
    └── Wing_R
All three bones remain in one armature.

Rigid weighting:

SparkBody  -> Root   1.0
SparkWingL -> Wing_L 1.0
SparkWingR -> Wing_R 1.0
Each mesh has an Armature modifier.

Recommended object names:

SparkBody
SparkWingL
SparkWingR
Recommended bone names remain:

Root
Wing_L
Wing_R
Spark faces Blender -Y with +Z as up.

Current FBX export expectations:

Selected Objects
Mesh + Armature
Only Deform Bones ON
Add Leaf Bones OFF
Primary Bone Axis Y
Secondary Bone Axis X
Apply Scalings FBX Unit Scale
Forward Z Forward
Up Y Up
Bake Animation ON for animated exports
NLA Strips OFF
All Actions OFF
Simplify 0
The neutral rest pose should remain neutral. Do not bake the Hover animation pose into the rest pose.

### Spark Hover Animation

The first Spark animation is Hover.

Current design:

60 FPS
roughly 60 frames / 1 second
mirrored wing flap
small Root/body vertical bob
looping
start/end pose matched
Current Hover asset:

rbxassetid://110340492323310
The complete Hover animation should play at 1x. Earlier experimentation established that increasing the entire animation speed makes the body bob too frantic.

Future preferred split:

HoverBob
    Root/body only
    fixed calm speed

WingFlap
    Wing_L + Wing_R
    independently variable speed
This would allow flight state to accelerate the wings without accelerating the body bob.

Possible future states remain:

Hover
Fly
Dash
Inspect
Alert
Target
Scan
### Spark Runtime Follower

Spark is cloned locally into Workspace by a local follower controller.

Current Spark body lookup uses SparkBody.

The local clone should:

be non-collidable
CanTouch false
CanQuery false
CastShadow false
Massless true
use the body/root as the movement carrier
play Hover through AnimationController/Animator
Current first-person / third-person intent is controlled by the player attribute:

player:SetAttribute("FirstPerson", true)
player:SetAttribute("FirstPerson", false)
Earlier follower tuning used these starting offsets:

local FIRST_PERSON_OFFSET = Vector3.new(3, 1.5, -4)
local THIRD_PERSON_OFFSET = Vector3.new(2.5, 1.2, 0.25)
Those values are now historical tuning references, not guaranteed current placement.

Spark was subsequently made smaller in-game through the model scaling API:

sparkModel:ScaleTo(0.5)
The follower position was also manually retuned so Spark sits comfortably below the main UI/HUD area rather than competing visually with interface elements near the top/edge of the first-person view.

Current presentation rule:

Spark scale
    Model:ScaleTo(0.5)

Spark screen-space composition
    close enough to feel like a companion
    below primary UI
    not covering interaction prompts / HUD
    not sitting directly in the player's central aiming/look region
Do not remove the ScaleTo(0.5) call and do not restore the old offsets merely because they appear earlier in this changelog. The current source code is the authority for Spark's exact post-reposition offsets.

Spark follows the camera in first person and the character/head region in third person.

The follower belongs under:

StarterPlayer
└── StarterCharacterScripts
    └── SparkFollower
The follower uses TweenService:SmoothDamp with CFrames. The CFrame velocity state must be initialised with CFrame.new(), not Vector3.zero.

Movement speed for trail logic is derived from frame-to-frame position delta rather than by reading .Magnitude from the CFrame velocity state.

A small white movement trail was added beneath Spark using two attachments. Current direction:

LightEmission 1
FaceCamera true
Lifetime ~0.20
enabled only above a small movement-speed threshold
### Spark Gaze / Slime Focus Prototype

Spark gained the first version of gaze-driven object attention.

The local camera raycasts from the centre of the view. If the player keeps looking at a Model named Slime for approximately:

0.35 seconds
Spark flies to a point above that Slime's bounding box.

Current settings:

local LOOK_DISTANCE = 100
local LOOK_DWELL_TIME = 0.35
local TARGET_HOVER_HEIGHT = 1
Looking away makes Spark return to the normal follow position.

The current Slime-name lookup is only a prototype. Future production direction is to use a tag or attribute such as:

SparkScannable
rather than hard-coding model names.

The intended long-term Spark interaction state machine is:

Hover
  -> Notice
  -> Approach
  -> Inspect
  -> Scan
  -> Return
The defining interaction concept is that Spark physically flies to the object the player is examining and can project scanning/analysis VFX around it.

A torus-like scanner and hologram-style projection remain planned visual components.

### ProximityPrompt / Camera Conflict Investigation

While testing Spark against the Slime, looking at a Slime sometimes appeared to affect camera control at the same time a ProximityPrompt became active.

The default prompt itself should not be assumed to be the final cause. The project should check custom scripts for interactions with:

PromptShown
PromptHidden
ProximityPromptService
MouseBehavior
MouseReleased
SettingsOpen
CameraType
CameraSubject
Useful isolation tests include temporarily setting:

Prompt.Enabled = false
Prompt.ClickablePrompt = false
Do not bake prompt-specific camera behaviour into Spark until the source of the conflict is confirmed.

### First-Person Controller — Core Invariants

The first-person controller now has several non-negotiable behaviour rules.

Standing:

Roblox CameraModule owns normal standing camera rotation
body remains visible
local Head/accessories are hidden
head/neck visibly follows camera LookVector
standing torso LookAt IK follows the camera
M releases / recaptures the mouse
settings can release the mouse through player attributes
Seated:

CameraType becomes Scriptable
camera yaw/pitch is accumulated directly from mouse delta
camera yaw has a hard limit and does not wrap
camera position is managed independently from rotating head bones
head/neck follows the seated camera state
upper-body assistance is separate from steering-arm IK
The most important camera rule discovered today is:

The camera may drive the skeleton, but the camera must not then read its next position/orientation from the same rotating bones in a way that feeds back into the solver.

The rejected feedback loop is:

Camera
 -> Neck / IK
 -> Head CFrame / Head Position
 -> Camera
 -> Neck / IK
 -> ...
That architecture caused severe jitter, orbiting, camera displacement and unstable seated behaviour.

### Standing Head / Torso Behaviour

Standing neck behaviour was preserved rather than disabled.

Current head limits remain approximately:

local MAX_HEAD_PITCH = math.rad(70)
local MAX_HEAD_YAW = math.rad(80)
local HEAD_FOLLOW_SPEED = 15
The standing head uses the camera LookVector transformed into UpperTorso object space.

The standing torso LookAt IK remains conceptually:

ChainRoot   LowerTorso
EndEffector UpperTorso
Target      invisible look target
The target is placed in front of the UpperTorso along the camera LookVector.

This standing torso behaviour was visually confirmed to work while running around and should not be removed simply because seated behaviour uses a different solution.

CharacterLeanScript remains a separate locomotion-pose system. It modifies the Root Motor6D Transform based on movement velocity. Do not conflate movement lean with camera/look IK.

### Remote Look Replication Architecture

The project already has a local-to-server look replication concept for other players.

Intended architecture:

LOCAL PLAYER
CurrentCamera.LookVector
  ├─> local FirstPersonController
  │     immediate local head/body pose
  │
  └─> ReplicatedStorage.Look:FireServer(...)
         ↓
      server validates
         ↓
      Player.LookVector attribute
         ↓
      remote clients render that player's look pose locally
The local player should use the actual local camera directly to avoid network latency.

Remote players should use the replicated LookVector as input to their own local visual IK/rendering.

A typo was identified in older code:

"LooKVector"
versus the intended:

"LookVector"
Future cleanup should standardise on LookVector.

Server-side look updates should validate type, non-zero magnitude and rate before normalising the vector. Avoid calling .Unit on a zero vector.

### Seated Camera — Root-Relative Anchor Experiment

An early stable-camera attempt captured the first-person camera position relative to HumanoidRootPart when the player sat down, then kept using that root-relative point while the camera became Scriptable.

This successfully broke the camera/head feedback loop, but created a new visual problem:

camera remained too far forward
camera could appear near hands / front of torso
camera did not follow the actual neck/head area during torso lean
This root-relative seated camera position is therefore superseded.

Do not restore a fixed HumanoidRootPart-relative seated camera anchor as the final camera solution.

### Seated Camera — Head-Tracked Experiment and Regression

A later experiment moved the camera from actual Head.Position after updating the seated pose.

That exposed another important failure mode.

When Root/Waist Motor6D.Transform offsets were multiplied onto their existing transforms every render frame:

joint.Transform = joint.Transform * offset
the offsets could accumulate and destabilise the seated pose.

Symptoms included:

camera glitching
seated boat motion breaking
body pose corruption
That experiment was rolled back.

Do not accumulate seated body transforms every RenderStep by repeatedly multiplying the previous result.

### Seated Camera Isolation / Virtual Head Approach

The successful camera recovery step separated camera orientation state from the animated skeleton.

The seated camera yaw/pitch accumulator became authoritative.

The controller could analytically reconstruct a virtual head/eye region from:

UpperTorso
 -> Neck base
 -> desired neck angles
 -> virtual head/eye point
without reading the already-rotated actual Head back into the solver.

This restored stable boat behaviour and became the basis for later refinements.

### Seated Camera — Neck-Base Eye Anchor

The seated camera position was then moved from the root-relative anchor to the UpperTorso-side Neck base.

Current conceptual anchor:

UpperTorso.CFrame
    *
original Neck C0
    =
Neck-base world position
The camera is positioned inside the head region using:

small upward offset
+
very small forward offset
rather than being placed out in front of the torso.

This produces an important behaviour:

UpperTorso leans
    ↓
Neck base moves
    ↓
camera moves with the body
while the camera still avoids reading the rotating Head itself.

Current eye-position tuning from the working branch used approximately:

local SEATED_EYE_HEIGHT_FACTOR = 0.55
local SEATED_EYE_FORWARD_FACTOR = 0.05
These values are tuning parameters, not architecture.

### Looking Down — Forward / Lower Eye Arc

Looking down exposed a second positional issue: even with the camera near the Neck base, a real person's eyes move slightly forward and downward as the skull pitches around the neck.

A synthetic downward eye arc was added using the seated camera pitch.

Current direction:

local SEATED_DOWN_LOOK_START = math.rad(5)
local SEATED_DOWN_LOOK_MAX_FORWARD_FACTOR = 0.32
local SEATED_DOWN_LOOK_MAX_LOWER_FACTOR = 0.18
The downward offset uses a smoothstep-like blend so very small pitch changes barely move the camera, while looking toward the feet progressively pushes the eye position forward and lower.

This motion is derived from the independent seatedCameraPitch state rather than Head.CFrame, preserving camera stability.

This was a major improvement to looking down in first person and should not be replaced by a raw Head attachment without carefully preserving the no-feedback rule.

### Seated Rearward Look — Pitch Must Not Cancel Yaw

A specific bug was found where looking behind while seated worked until the player also looked downward.

The old seated body code explicitly disabled the body-turn IK while pitch was below a downward threshold and interpolated the torso yaw back to zero.

That caused the character to visibly snap its shoulders/body forward even while the camera was still looking behind.

The rule was corrected:

Camera pitch must not cancel seated horizontal torso yaw.

The torso target remains horizontal for yaw assistance, while the neck handles vertical look.

This change made the boat rearward-look behaviour work correctly.

### Earlier Shoulder Participation

Waiting until exactly 90 degrees of camera yaw before the shoulders began helping felt robotic.

The shoulder/torso-assist threshold was experimentally moved earlier:

start around 75 degrees
full influence around 95 degrees
This produced a more natural transition where the head leads and the shoulders begin contributing before the neck appears mechanically maxed out.

This experiment led directly to the later constraint-aware chain.

### Steering Wheel Rotation

The current steering-wheel server behaviour is simple and remains valid:

local seat = script.Parent.VehicleSeat
local hingeConstraint = script.Parent.HingeConstraint

seat:GetPropertyChangedSignal("SteerFloat"):Connect(function()
    hingeConstraint.TargetAngle = seat.SteerFloat * 45
end)
VehicleSeat.SteerFloat therefore rotates the wheel/handle through the HingeConstraint up to roughly ±45 degrees.

The steering wheel itself should be positioned for the boat model and seated character, not moved excessively just to compensate for a broken body/IK solver.

### Steering Hand IK

The steering hand system creates one IKControl per arm while the character is seated.

The working arm-chain direction is:

LeftUpperArm
 -> LeftLowerArm
 -> LeftHand

RightUpperArm
 -> RightLowerArm
 -> RightHand
Current steering-hand intent:

ikLeft.Type = Enum.IKControlType.Transform
ikLeft.ChainRoot = LeftUpperArm
ikLeft.EndEffector = LeftHand

ikRight.Type = Enum.IKControlType.Transform
ikRight.ChainRoot = RightUpperArm
ikRight.EndEffector = RightHand
Hand targets are:

Handle.LeftAttachment
Handle.RightAttachment
The hand IK should have a higher priority than seated body/look IK.

Current tested value:

HAND_IK_PRIORITY = 10
Current tested settings also use:

Weight = 1
SmoothTime = 0
The hand IK is enabled only while seated on a seat whose parent contains the expected Handle and attachments.

Leaving the seat disables both IK controls and clears their targets.

### Rejected Hand ChainRoot — UpperTorso

An experiment changed both arm IK chains to use UpperTorso as their ChainRoot so the shoulder joint would be inside the solve.

This produced poor left-arm behaviour while the right arm happened to look acceptable. The left hand/arm could float outward even when the wheel attachment itself was correctly positioned.

The wheel attachment was visually verified and was not the source of the error.

The steering arm chain was therefore returned to:

LeftUpperArm -> LeftHand
RightUpperArm -> RightHand
Do not automatically change both steering hand ChainRoots back to UpperTorso.

### Arm Reach / Shoulder-Popping Problem

Even with the correct per-arm chains, forcing both hands to remain at Weight = 1 while the body turns a very large amount can become anatomically impossible.

At large body yaw:

shoulder socket moves away from wheel
hand target remains fixed to wheel
IK tries to preserve target
arm visually stretches / pulls from shoulder
Moving the physical steering wheel farther forward can temporarily hide the issue but is not the preferred architectural solution.

Potential future elbow-pole targets remain useful for controlling elbow bend direction, but Pole targets do not solve impossible reach.

### Constraint-Aware Head -> Torso Chain

The best seated body architecture reached during this session was a constraint-aware chain that lets the head/camera lead and makes the torso yield when hand constraints are active.

The major change was changing seated body look IK from a root-level solve to an upper-body-only solve:

LowerTorso
   -> UpperTorso
rather than:

HumanoidRootPart
   -> LowerTorso
   -> UpperTorso
This keeps the hips/root planted more reliably in the seat and uses the waist/shoulders for look assistance.

The controller can inspect enabled hand IK controls whose EndEffector is LeftHand or RightHand, find their targets, estimate shoulder-to-target distance and approximate arm reach, and calculate an UpperBodyConstraintAlpha.

Conceptually:

hands free
    ↓
more torso freedom

hands attached to nearby object
    ↓
torso becomes more conservative

hand target approaches comfortable arm reach
    ↓
torso yields further
    ↓
head/camera absorb more of the look
The experimental values in the working constraint-aware controller were approximately:

free seated torso yaw maximum        ~35 degrees
constrained seated torso yaw maximum ~15 degrees
The exact angles can be retuned, but the architecture is important: body freedom should reduce when rotating the shoulders would threaten hand contact.

This same system is intentionally generic enough for later:

steering wheels
levers
cannons
held tools
fishing rods
other fixed hand targets
rather than being hard-coded only for the current boat.

### Seated Torso Pitch / Natural Lean

The constraint-aware controller also introduced a small amount of UpperTorso pitch following camera pitch.

The head still performs most of the up/down motion.

Current experimental direction:

small torso pitch share
roughly 5 degrees maximum upward torso pitch
roughly 8 degrees maximum downward torso pitch
The purpose is not to make the character fold into the steering wheel. It is to let the chest/shoulders subtly follow the player's gaze so the pose does not look like a rigid torso with a rotating head.

The camera follows the Neck-base position, so this torso pitch also naturally moves the first-person viewpoint with the upper body.

### Exposed First-Person Pose Attributes

The constraint-aware controller exposes seated pose state through Player attributes so other systems can react without reaching into the controller internals.

Current attributes:

SeatedTorsoYaw
SeatedTorsoPitch
UpperBodyConstraintAlpha
These are intended for future systems such as:

steering animations
shoulder lift
elbow pole adjustment
held-object animation
camera HUD debugging
vehicle-specific upper-body behaviour
### Restricted 90-Degree Steering Experiment

A separate experiment hard-limited the seated camera to approximately:

-90 degrees ... +90 degrees
and deliberately kept torso rotation small.

That mode felt more steering-safe and prevents the player from physically turning around while both hands remain on the wheel.

A small forward/downward torso lean was also explored near the side-view limit to move the shoulder sockets slightly toward the wheel rather than away from it.

This experiment was useful, but it should not replace the working free-look behaviour globally.

### Dual Seated Look Modes

Both seated-camera behaviours are now considered valid player choices.

The working combined design uses:

player:SetAttribute("SeatedFreeLook", true)
for free look, and:

player:SetAttribute("SeatedFreeLook", false)
for restricted look.

Current behaviour:

SeatedFreeLook = true
    camera yaw approximately +/-170 degrees
    player can look behind
    constraint-aware body logic remains active
    this is the current default

SeatedFreeLook = false
    camera yaw approximately +/-90 degrees
    player cannot look directly behind
    intended as a tighter steering-oriented option
Only the maximum camera yaw should change between these modes.

Do not maintain two independent first-person controller scripts for the two modes.

The preferred architecture is one controller with:

getMaxSeatedCameraYaw()
or equivalent selecting the active limit.

A future settings UI can expose this as something like:

Seated Free Look
[ ] Allow looking behind while seated / steering
The restricted mode can later be paired with a functional mirror/reflection solution for reversing awareness.

### Current First-Person Baseline / Do-Not-Regress Rules

The following rules are the current best-known first-person baseline after today's iteration:

1. Standing camera remains Roblox CameraModule-driven.

2. Standing head/neck continues visibly following the camera.

3. Standing torso LookAt IK remains separate from seated logic.

4. Seated camera becomes Scriptable and owns its yaw/pitch accumulator.

5. Never create a camera -> rotating head -> camera feedback loop.

6. Seated camera position follows the UpperTorso-side Neck-base region,
   with a synthetic forward/lower eye arc when looking down.

7. Looking down must not reset/cancel a valid seated rearward body yaw.

8. Steering arm IK remains a separate higher-priority system.

9. Steering hand chains start at LeftUpperArm / RightUpperArm.

10. Do not accumulate Root/waist Transform offsets every frame by
    multiplying onto the previous Transform.

11. Prefer upper-body-only seated look assistance over rotating the entire
    seated HumanoidRootPart chain.

12. Hand-target reach should constrain how much the torso is allowed to turn.

13. Free-look and restricted-look modes should share the same controller and
    differ primarily by the camera yaw limit.

14. Do not weaken working arm/steering behaviour to make an extreme camera
    pose look physically exact. Camera freedom and physical avatar pose do
    not have to be identical at extreme angles.
### Water Platform Rider / Character Throwing Into Ocean — Diagnosis

Testing the new first-person/body behaviour on floating WaterInteractable platforms exposed a separate water-platform issue.

WaterPlatformRiderController currently takes the supporting platform's complete CFrame delta and applies it directly to the player's HumanoidRootPart.CFrame.

That means the player inherits:

translation
yaw
pitch
roll
from the platform.

This is why a character standing on a strongly bobbing/tilting water platform can be physically rotated or displaced aggressively enough to lose support and fall into the ocean.

The support system currently uses multiple downward raycasts around the character footprint to improve contact at corners/edges, and PlayerWaveMotionController already suppresses its own independent wave bob while PlatformRiding is true, so the duplicate player-wave offset is not the primary issue.

The dangerous operation is the direct full-platform transform being applied to HumanoidRootPart.

This remains an open issue.

Future investigation should consider separating:

platform translation carry
platform yaw carry
visual pitch/roll
physical character root orientation
rather than applying the complete platform pitch/roll to the humanoid root.

Do not treat this as a first-person camera bug merely because the camera makes the throw easier to see.

### Water / SurfaceAppearance Mask Workflow

The stylised ocean workflow was extended conceptually so colour/transparency and emission can be controlled independently.

The important material lesson from this work is:

RGBA ColorMap
    controls visible colour + transparency

separate emission / alpha mask
    controls where glow appears

runtime colour/emission controls
    can then recolour the glow independently
This is preferable to baking every appearance property into one texture when the goal is a highly adjustable Wind Waker-inspired water surface.

The existing wave-line / transparent-overlay system remains compatible with this approach.

### Laboratory / Prototype Scope

The place formerly referred to as WaterTest remains a development laboratory rather than a production map, but the project identity is now transitioning to Spark. WaterTest should be treated as a historical/internal prototype name, not the current player-facing project name.

It is intentionally used to combine and stress-test:

EditableMesh ocean
floating props
water-platform riding
custom swimming
first-person body visibility
character lean
Spark
Slime pickup / target tests
boat seating
steering wheel constraints
arm IK
camera limits
underwater visuals
surface intersection VFX
Temporary conflicts between these systems are acceptable during experimentation, but a fix for one subsystem should not silently rewrite or remove a working system in another.

The Spark laboratory should remain focused on systems that directly support Spark's first-person exploration and interaction stack: boats, ocean, floating physics, swimming, Spark interactions, camera/body presentation and related environmental systems. Unrelated room/door/portal experiments are still better isolated in a separate test place.

### End-of-Day Working Direction

The strongest combined direction at the end of 12 September is:

Spark:
    fully modelled/rigged companion direction
    local hover/follow
    gaze-driven object approach
    future inspect/scan state machine

First person:
    stable standing body/head presentation
    Scriptable seated camera
    Neck-base camera position
    downward forward/lower eye arc
    no camera/head feedback loop

Seated body:
    head leads
    shoulders/UpperTorso assist naturally
    body assistance constrained by hand reach
    pitch does not cancel yaw
    hips/root remain more seat-stable

Steering:
    VehicleSeat drives wheel hinge
    per-arm Transform IK
    arm ChainRoots at UpperArms
    hand IK priority above body look IK
    wheel attachments remain the direct targets

Player preference:
    free seated look up to ~170 degrees
    OR restricted seated look up to ~90 degrees
    one shared controller

Movement / platform status:
    Character Controller Library beta is enabled for experimentation
    beta sprinting is disabled
    legacy character controller removes the observed platform instability
    disabling WaterPlatformRiderController also removes the instability
    old full-CFrame platform carry is therefore not assumed CCL-compatible
    CCL-specific platform maths is deferred rather than rushed
The next first-person/boat changes should be incremental and should preserve this working architecture rather than replacing the controller wholesale.

Project identity at this point:

Project: Spark
Version: v0.5.0-dev
Former laboratory name: WaterTest
Spark runtime scale: 0.5


### Character Controller Library Beta Enabled

The Roblox Character Controller Library beta feature was enabled during today's first-person / movement testing.

Current experimental environment:

Character Controller Library beta
    ENABLED

Character Controller Library sprinting
    DISABLED
The sprint behaviour supplied by the beta controller was tested and deliberately turned off because it felt poor for the current project.

Do not re-enable beta sprinting automatically during refactors.

The Character Controller Library is still a beta dependency. Spark should be able to experiment with it without making core water, swimming, camera, Spark-follow or buoyancy architecture impossible to use if Roblox changes or removes the feature.

### Character Controller Library vs Legacy — Moving-Platform Isolation Result

The moving ocean-platform instability was isolated much further than the earlier changelog revision suggested.

Two separate changes remove the observed problem:

A. Switching back to the Legacy avatar / legacy character controller
    -> platform instability disappears

B. Keeping the new Character Controller Library but disabling
   WaterPlatformRiderController
    -> the same instability also disappears
This materially changes the diagnosis.

The strongest current interpretation is:

WaterPlatformRiderController was designed around the legacy character movement stack and its full-root transform maths is not safely compatible with the new Character Controller Library behaviour.

The old rider applies the supporting platform's complete transform delta to the player's HumanoidRootPart, including:

translation
yaw
pitch
roll
That can duplicate or conflict with movement/grounding work performed by the new controller.

The Gerstner / buoyancy system itself should not be declared broken from this result.

The current test question is whether the Character Controller Library can provide acceptable native moving-surface behaviour with the old platform-rider code disabled.

Do not immediately restore the old full-CFrame rider merely because it behaves correctly under Legacy.

### CCL-Native Moving-Platform Maths — Deferred

If Spark eventually commits to the Character Controller Library, the old platform-riding code will probably require a CCL-aware rewrite.

Possible future direction:

controller/ground sensor identifies actual supporting surface
        ↓
sample movement of the support/contact point
        ↓
inherit only required translational/contact displacement
        ↓
avoid blindly rotating HumanoidRootPart through platform pitch/roll
        ↓
let the character controller own grounding/upright movement
The exact implementation is intentionally deferred.

Reason:

The Character Controller Library is still a Roblox beta. Do not heavily re-architect Spark around beta-only movement behaviour until the feature has matured enough to justify the investment.

Keep existing wave sampling and buoyancy systems independent from whichever Roblox character controller is active.

### IK Toggle Broke Swimming Animation Behaviour

Enabling/toggling the new body-look IK was confirmed to interfere badly with swimming presentation.

Observed result:

look/body IK active
    ↓
built-in/custom swimming animation presentation can break
This is an important integration rule.

Do not assume that a standing or seated IK solution is safe while swimming.

Future state gating must test at least:

standing
walking/running
jumping
surface swimming
underwater swimming
seated / steering
standing on moving WaterInteractable object
Swimming animation should not be deleted or weakened merely to preserve cosmetic UpperTorso look behaviour.

If required, standing/seated torso IK should disable or yield while swimming.

### Standing UpperTorso IK Priority / Weight Reduced

Reducing the influence/priority of the standing LowerTorso -> UpperTorso look IK produced a useful visual improvement:

before
    looking down could pull the camera/body relationship far enough
    that the first-person camera visibly clipped outside the body

after reducing UpperTorso authority
    downward camera clipping was improved/fixed
However, this did not fully solve the separate behaviour where the body itself still participates too strongly when looking downward.

This means two issues should remain conceptually separate:

camera clipping
    improved by reducing UpperTorso look authority

whole-body downward pose
    still requires better pitch-specific pose logic
Current design direction:

horizontal look:
    head leads
    shoulders/UpperTorso may assist modestly

vertical look:
    head/neck should do most of the work
    UpperTorso pitch should be small/cosmetic
Do not solve vertical first-person look by making the UpperTorso strongly authoritative again.

### UpperTorso IK Is No Longer the Primary Suspect for Physical Platform Failure

Earlier in the session, UpperTorso IK was suspected of causing the Gerstner/moving-platform rotation failure because toggling IK correlated with broken standing behaviour.

Later isolation changed that conclusion.

Because:

Legacy controller fixes the physical platform problem
AND
disabling WaterPlatformRiderController fixes the physical platform problem
the primary physical-platform suspect is now the interaction between:

Character Controller Library
+
legacy-style WaterPlatformRiderController full-root CFrame carry
UpperTorso IK can still produce visual/camera/animation conflicts and should remain conservative, but it should not currently be documented as the proven cause of the physical platform launch/fall issue.

### Camera / Neck / UpperTorso Ownership Rule

A persistent first-person limitation remains: attempting to make the camera literally follow a neck/UpperTorso pose that is itself being solved from the camera can create a circular dependency.

Rejected loop:

Camera
 -> UpperTorso / Neck IK
 -> neck-base / torso pose changes
 -> camera directly follows solved pose
 -> IK input changes again
 -> ...
The stable architecture remains:

camera yaw/pitch state is authoritative
        ↓
head/neck follows camera
        ↓
UpperTorso is secondary assistance
        ↓
camera position uses controlled/analytic anchoring rather than feeding
directly from the same solved rotating bones
Reducing UpperTorso authority is therefore intentional.

### Updated IK Priority Philosophy

The current practical priority philosophy is:

must-win interaction / locomotion
    steering hands
    required held-object constraints
    swimming animation / locomotion
    stable grounding / movement

primary first-person presentation
    camera
    head / neck look

secondary presentation
    UpperTorso / shoulder look assistance

cosmetic
    extra lean / pose polish
UpperTorso look IK is not important enough to break:

swimming
grounding
moving-platform stability
steering hands
camera stability
Numeric priorities/weights can continue to be tuned, but this ownership hierarchy should remain.

### Foot IK on Gerstner / Ocean-Impacted Objects — Deferred TODO

Do not build a full foot-planting system around the Character Controller Library yet.

Current approach:

physical grounding
    leave to the active Roblox character controller / physics where possible

Gerstner / buoyant object motion
    keep driven by the existing independent water-wave / buoyancy systems

foot IK
    NOT required for current functionality
    deferred visual polish
If the Character Controller Library becomes stable enough to keep long-term, revisit cosmetic foot planting later.

Future foot-IK rules:

LeftFoot / RightFoot IK may visually align to tilted floating objects

foot IK should NOT:
    move HumanoidRootPart to carry the player
    become required for buoyancy
    become required for physical platform following
    become a hard dependency of WaterWaveSampler
For pure visual EditableMesh ocean waves without matching physical collision, WaterWaveSampler remains the appropriate source for wave position/normal information if visual foot placement is ever desired.

Reason for deferral:

Do not spend substantial project time coupling Spark to a Roblox beta feature that may still change significantly.

### Spark Size and HUD-Safe Repositioning

Spark's in-game presentation was retuned after the initial follower implementation.

Completed change:

sparkModel:ScaleTo(0.5)
Spark is now rendered at half the imported/model scale used by the follower before this adjustment.

His normal companion position was also moved so he sits more naturally below the project's UI/HUD, reducing visual competition with interface elements while keeping him clearly visible in the player's peripheral first-person view.

This is now part of Spark's current presentation, not an optional experiment.

Codex should preserve:

ScaleTo(0.5)
HUD-safe / below-UI companion placement
smooth follower motion
existing Hover animation playback
existing gaze/inspection behaviour
Exact positional offsets should be read from current source rather than reconstructed from older values in this changelog.

### v0.5.0-dev Current State

At the end of the documented 12 September session, the project is no longer best described as WaterTest.

Current identity:

Project
    Spark

Version
    v0.5.0-dev

Historical prototype names
    WaterTest
    RBLX EditableMesh Water First Person
Current high-level state:

Spark companion
    modelled and rigged
    Hover animation integrated
    ScaleTo(0.5)
    repositioned below UI
    local smooth follow
    gaze-driven Slime approach prototype
    future inspect/scan behaviour planned

Water
    EditableMesh ocean remains foundational
    shared wave sampling remains independent
    buoyancy / WaterInteractable prototypes remain useful
    custom swimming and water VFX remain part of Spark

First person
    body remains visible
    head/neck follow is retained
    seated camera has an independent yaw/pitch architecture
    camera/head feedback loops are explicitly prohibited
    UpperTorso assistance is being reduced and treated as secondary

Boat steering
    wheel hinge follows VehicleSeat steering
    hands use independent per-arm IK chains
    hand interaction remains higher priority than torso look assistance
    free-look and restricted-look seated modes remain valid options

Movement controller
    Character Controller Library beta enabled for testing
    beta sprinting disabled
    Legacy controller fixes the moving-platform instability
    disabling legacy WaterPlatformRiderController also fixes it
    CCL-specific moving-platform rewrite deferred

Animation / IK
    torso IK can break swimming and must yield when necessary
    reducing UpperTorso authority improves downward camera clipping
    foot IK deferred until there is a stronger reason to invest
### Codex Do-Not-Regress Summary

Future automated changes should preserve these rules:

PROJECT
- Current project name is Spark.
- WaterTest is historical terminology.
- Current development milestone is v0.5.0-dev.

SPARK
- Use Spark naming consistently.
- Keep ScaleTo(0.5) unless intentionally retuning size.
- Keep current HUD-safe follower placement.
- Do not restore superseded follower offsets blindly.

CAMERA
- Camera drives the first-person pose.
- Do not create camera -> solved bone -> camera feedback.
- Head/neck are primary.
- UpperTorso is secondary assistance.

IK / ANIMATION
- Steering hand IK must retain interaction authority.
- UpperTorso look IK must yield to swimming/locomotion when required.
- Do not use foot IK as physical platform carry.
- Do not make beta movement APIs mandatory for water systems.

CHARACTER CONTROLLER
- Character Controller Library is experimental/beta.
- Sprinting is intentionally disabled.
- Legacy movement fixing a bug is an important comparison baseline.
- Old WaterPlatformRiderController full-root CFrame carry is not assumed
  compatible with CCL.
- Do not heavily invest in a CCL-specific platform/foot system yet.

WATER
- WaterWaveSampler / buoyancy should remain controller-independent.
- Gerstner-driven object motion is not considered inherently broken by
  the Character Controller Library regression.
