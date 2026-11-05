# Rally puddles

`rally_puddles.gd` owns the deterministic catalogue, route placement, water mask and per-contact response. The stage session rebuilds it after collision geometry becomes available, including stage transitions. Stage-ID seeds keep the layout fixed across reloads. Weather changes fill, never position.

| Profile | Nominal length x width | Maximum center depth | Drag scale |
| --- | --- | --- | --- |
| Shallow | 4 x 2 m | 5 mm | 0.8 |
| Rut | 9 x 0.85 m | 9 mm | 1.0 |
| Deep | 5 x 2.8 m | 20 mm | 1.15 |
| Crossing | 2 x 4 m | 12 mm | 1.0 |

Candidates occur every 12–26 route meters with seeded lateral offsets and size variation. Road collision checks use the `is_stage_road` metadata and reject roadside terrain, steep grades and corner height deviations above 35 mm. These are virtual depressions: this version does not compute hydrological basins or runoff from the mesh.

Background water fills patches from 0.35 to 4 mm. Event mode reads the shared surface provider at each patch distance; practice uses terrain wetness. Footprint radius grows with the fourth root of fill, while center depth grows linearly with fill. This makes shallow accumulations broader without filling deep puddles prematurely. CPU sampling and shader use the same local-space contour. Contacts outside the patch or more than 12 cm from its plane receive no local depth. A spatial index limits wheel queries.

The simulation takes the maximum of background water and local puddle depth, avoiding addition of the same water twice. Existing wet-compound grip and thermal cooling receive that water. Their existing 12 mm saturation remains; deeper water continues increasing local drag and loss of support. Additional speed-dependent support loss represents aquaplaning, separately from the existing speed-independent wet-surface grip. Per-wheel compound IDs preserve mixed sets.

Support loss starts earlier for dry tires (18 m/s reference versus 30 m/s for rain tires). Water resistance acts at each contact, opposing planar velocity and capped at 45% of wheel normal load. Uneven entry therefore produces a physical yaw moment. Wheel friction heating and aligning torque follow remaining support. Values are gameplay tuning, not calibrated measurements.

The Mobile-compatible shader samples the active tropospheric sky cubemaps with their current blends and tints. It uses transparent edges, grazing-angle opacity and rain ripples without screen-space reflections. Existing CMR4 spray receives local wheel water, with a new entry burst for each puddle even on already-wet roads.

Validation:
- `godot --headless --path game --script res://tests/rally/puddles_contract.gd --quit-after 120`
- `godot --path game --script res://tests/rally/puddles_stage_probe.gd --quit-after 500`
- Existing `dynamic_weather_tires_contract.gd`, `compound_thermal_regression.gd`, `vehicle_vfx_contract.gd`.

The stage probe forces full water for inspection and saves `user://puddles_stage_probe.png`; it does not modify saved event weather. Manual driving remains necessary to accept force tuning, visibility at race speed and performance across all stages.

The stage reuses validated `course.points`. Wheel condition queries share the same contact sampler; auxiliary queries are read-only and cannot overwrite the last physics publication. Published wheels expose `water_mm`, `puddle_depth_mm`, `puddle_support` and `puddle_drag_n` (scalar resistance magnitude).

Review corrections: geometry tolerances, hydro drag torque, compound grip and thermal coefficients remain unchanged. No tests were run for these review corrections, at the user's request.

Visibility tuning: candidates now start at 14 route meters with 12-26 m spacing. Profiles are wider/larger, while depth limits and contact-response coefficients remain unchanged. The fourth-root footprint expands early. Shader opacity follows footprint and a separate fill fade instead of normalized depth, keeping shallow water readable. More coverage increases time spent in water; it does not increase the center depth or instantaneous force at the same depth and speed. Geometry rejection remains active, so candidate spacing is not a guarantee of actual puddle spacing. These tuning changes have not been tested at the user's request.
