# Helm prompt and driver exit

The helm action is server-authoritative:

```text
ProximityPrompt.Triggered
→ validate player, range, lifecycle and current BoatSeat occupant
→ free seat: BoatSeat:Sit(humanoid)
→ current driver: BoatDynamicAuthority.RequestDismount(...)
```

There is no client boarding remote, automated walking, entry animation, entry
position marker or entry transform write. `BoatDynamicAuthority` still owns the
complete parking/ownership/physics transaction.

## Studio setup

On a stable, non-rotating helm frame part, add an optional Attachment named:

```text
HelmPromptAnchor
```

The runtime `HelmPrompt` is parented there. It explicitly uses Roblox's default
prompt style, empty action/object text, instant E/ButtonX activation and the
normal built-in keyboard/controller/mobile glyph. Without this Attachment, the
module tries the fixed side of the helm hinge, then a BasePart named `HelmFrame`,
`HelmStand`, `HelmPedestal` or `HelmMount`, and finally falls back to `BoatSeat`.

The current driver continues to see and use the same prompt while preparing or
driving. A small presentation-only LocalScript hides an occupied helm from other
clients; the server independently rejects their trigger attempts.

For dismount placement, add an Attachment named:

```text
HelmOccupantExit
```

Place and orient it as the desired `HumanoidRootPart` world pose for the former
driver. Parent it directly to `BoatRoot` or to another BasePart which is rigidly
connected to the same physical assembly as `BoatRoot` while driving. It is used
only after the existing parking transaction reaches `KINEMATIC_IDLE` and
`BoatSeat` occupancy has cleared. It is never used for entering the seat.

Before using the marker, the server verifies its parent is a BasePart, that its
parent shared the live BoatRoot assembly before parking, and that its uncached
world position remains within 20 studs of the current BoatSeat and 35 studs of
BoatRoot. A missing, detached or stale marker uses the calculated live-seat
fallback instead. `[BoatExitValidation]` logs the actual Studio parent,
assembly roots, CFrames, distances and selected source for validation.

`HelmPromptDistance` is the only optional prompt attribute and defaults to 10
studs.

While registered, `BoatSeat.CanTouch` is disabled so touching the seat cannot
bypass the helm prompt. Its previous value is restored if the boat/controller is
removed.

Temporary `[HelmSeatDiagnostic]` logs report client and server HRP, BoatRoot,
BoatSeat, lifecycle and `CurrentTransform` values at helm entry. They are for the
first Studio transform-mismatch test and can be removed after validation.

Unexpected loss of the validated driver is handled directly by the server's
`BoatSeat.Occupant` callback. It captures the live sailed-to BoatRoot and former
driver HRP poses, completes normal parking synchronously, and listens directly
for the former Humanoid's `SeatPart` to clear. This avoids waiting for the
authority heartbeat. A single final CFrame write uses `HelmOccupantExit` (or the
fallback), with character assembly velocity cleared before and after it.
`[BoatDriverExit]` reports the captured pose, pre-placement pose, destination,
final pose, and any movement that occurred before that one final placement.
