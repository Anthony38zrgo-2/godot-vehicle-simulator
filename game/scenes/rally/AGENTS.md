# rally scenes — standalone Godot/Jolt Rally simulator

Scope: the Russia Stage 1 Ford session and the small proving-ground session.
Consumers: `scripts/run_rally.ps1`, the Godot editor, and the isolated Windows export.
Rules: scenes compose only. The Rally GDScript domains calculate suspension, tire contact and wheel motion; Godot/Jolt owns the sprung chassis and four unsprung hubs, their vertical guide constraints, gravity, terrain/obstacle collisions and penetration resolution. Tire radial forces act on the hubs; suspension forces act equally and oppositely on hubs and chassis. The Ford uses exactly one cylindrical ShapeCast3D per wheel per physics callback. Do not add legacy GEVP vehicle or wheel dependencies to these Rally scenes.

The full session is `russia_stage1_ford_escort_rs2000.tscn`. `rally_proving_ground.tscn` is the first-line driveable field and owns no Open Formula terrain. Both use the same `ford_escort_rs2000_1971.tscn` vehicle scene.
