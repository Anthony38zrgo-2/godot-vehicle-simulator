# rally scripts — rally simulation and session adapters

Scope: rally-only controllers, camera, HUD, audio, stage collision and export telemetry.
Consumers: `game/scenes/rally/` and `scripts/run_rally.ps1`.
Rules: the Ford Rally runtime is owned by `game/scripts/physics/` and `rally_escort_vehicle.gd`. It uses one Jolt `RigidBody3D`, one central ray per wheel per physics callback, and Jolt body shapes for chassis collisions. Keep Rally independent of GEVP vehicle and wheel classes.

`VehicleProfileLoader` resolves the domain manifest and hashes each source JSON. `FordRallyVehicleSimulation` coordinates the domain models and applies forces in `_integrate_forces`; the vehicle script adapts input, mass properties, visuals and telemetry. `rally_track_collision_builder.gd` turns the exported stage collision GLB into static Jolt trimeshes. The rally recorder is independent. The HUD reuses the retro presentation and driving-controls panel while reading live GDScript thermal state. Input actions remain sourced from the input profile.
