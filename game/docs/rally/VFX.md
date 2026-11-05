# Rally VFX

The Ford Escort reuses the simulation's wheel contacts, loads and slip for particles and tire marks. Chassis impacts use the existing Jolt contact reports.

- CMR4 supplies the wheel sprites, exhaust smoke, radiator steam, impacts, snow and tire marks. The mud sprite also represents gravel and generic debris.
- CMR2 supplies the individual raindrops and the splats that sample nearby terrain. Rain streaks follow the wind relative to the car.
- The CMR2 four-frame exhaust flash plays on the same backfire event as the sound.
- Wheel particles use fixed surface profiles, a 400-slot pool and a 25 Hz visual step. Tire marks use six bounded batches of up to 256 segments each.
- The manifests in `assets/vfx/cmr2` and `assets/vfx/cmr4` record the source archive and hashes for the sprites kept in the project.

Run `vehicle_vfx_contract.gd`, `weather_precipitation_sprite_contract.gd` and `tire_tracks_contract.gd` from `game/tests/rally`. The tire track contract needs a GPU renderer.
