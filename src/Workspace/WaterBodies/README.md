# Water body authoring

In Studio, create an invisible anchored Part and tag it `WaterBody`.

Recommended properties:

- `Anchored = true`
- `CanCollide = false`
- `CanTouch = false`
- `CanQuery = false` (WaterRegistry does not require physics queries)
- `Transparency = 1`

The Part itself is the water volume:

- top face = surface Y
- bottom face = maximum water depth
- X/Z dimensions = footprint

Optional attributes:

- `Priority` (number, default 0)
- `WaveScale` (number, default 1)
- `WaveHeightScale` (number, default 1)

To create a dry region inside water, create another invisible Part tagged
`WaterExclusion`. If the exclusion intersects the water surface and contains
the queried X/Z point, water is considered absent there.
