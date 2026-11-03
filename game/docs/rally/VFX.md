# Rally vehicle VFX

Surface emission is restricted to rear wheels (indices 2 and 3). All particle materials use a vehicle-local exclusion box to clip fragments inside the body/cabin in every camera view. This is a visual exclusion, not physical particle collision; exterior trails and chassis impact effects remain visible outside the vehicle.

`VehicleVFX` is attached to the shared Ford scene, so both Russia Stage 1 and the proving ground use it. It reads the four existing wheel ShapeCasts, loads, world contact points, normals and tire slip. Chassis events come from the existing Jolt contact manifold; no additional physics queries or forces are introduced.

## Moderate default

The `intensity` property on `VehicleVFX` defaults to **0.975** (50% above the original 0.65); set `enabled` to false to disable it. Tune `SURFACES` and emitter lifetime/size in `scripts/rally/rally_vehicle_vfx.gd`.

| Contact | Effect |
| --- | --- |
| Gravel | Sparse brown dust and small grit |
| Dirt | Brown dust and earth flecks |
| Sand | Light tan dust and sparse debris |
| Grass | Very little dust; low green/brown flecks |
| Road/asphalt/tarmac | Subtle gray tire smoke only during slip |
| Chassis impact/landing on terrain | Short burst of earth/grit at the physical contact |
| Chassis impact on barriers or tree trunks | Muted debris burst, no automatic sparks |
| Chassis scraping hard props or asphalt | Small warm sparks if sliding fast enough |

The collision GLB combines different objects into broad categories. `Collision_Props` is treated as hard material; barriers/trunks conservatively use debris. Exact metal/wood identification would require finer collider material metadata from the exporter.

Effects stop emitting when a wheel is unloaded, airborne or stationary. Wetness reduces dust/smoke by up to 90%. Eight wheel emitters and six reusable impact slots bound the particle budget to 280 particles at maximum allocation, normally substantially fewer. Impacts have a 0.22–0.35 second cooldown; resets/teleports clear the trails. Particles remain in world coordinates instead of following the car.

## Assets and packaging

The complete Brackeys bundle is installed in `assets/vfx/brackeys`, retaining its license and credits. macOS metadata was omitted. Rear-wheel emitters use the CMR4 `Dust_01` for the dust core, `Dust_02` for the plume, and `smoke_01` for both layers on asphalt, road and tarmac. The 128 × 128 RGBA PNGs and source hashes are in `assets/vfx/cmr4`. Debris, impact sparks and steam use Brackeys textures. The supplied `spark_*` images resemble electricity, so tiny trace sprites are used for physical sparks instead. Explosions, magical effects and fire are not automatically triggered by normal vehicle impacts.

The Windows staging script includes both the VFX controller and assets. Original asset files are not modified.

## Verification

Run `Godot --headless --path game --script res://tests/rally/vehicle_vfx_contract.gd --quit-after 1000` to check real proving-ground wheel contact, surface routing, wetness suppression, asphalt slip, unloaded wheels, impact cooldown and pool/reset behavior. Render validation must use Forward+ with a GPU; headless particle checks alone do not verify appearance.
