# Rally Puddles

`rally_puddles.gd` owns the deterministic catalogue, route placement, prefabricated mask textures and per-contact response. The stage session rebuilds it after collision geometry becomes available, including stage transitions. Stage-ID seeds keep the layout fixed across reloads. Weather changes fill, never position.

## Puddle Profiles & Mask Textures

| Profile | Nominal length x width | Max Center Depth | Activation Threshold | Basin Retention | Mask Asset | Drag Scale | Edge Softness |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `pothole_deep` | 3.75 x 3.25 m | 48 mm | 0.60 mm | 1.40 | `puddle_round_organic.png` | 1.55 | 0.12 |
| `basin_kidney` | 4.50 x 3.88 m | 36 mm | 0.70 mm | 1.25 | `puddle_kidney_soft.png` | 1.35 | 0.18 |
| `pond_egg` | 4.12 x 3.62 m | 25 mm | 0.75 mm | 1.20 | `puddle_egg_asym.png` | 1.20 | 0.16 |
| `pool_clover` | 4.75 x 4.25 m | 14 mm | 0.85 mm | 1.10 | `puddle_lobe_triple.png` | 1.10 | 0.22 |
| `shallow_round` | 3.12 x 2.88 m | 5 mm | 1.15 mm | 0.85 | `puddle_round_organic.png` | 0.80 | 0.20 |

## Spatial Distribution & Topography

Puddles avoid artificial "single-file centerline" placement and unrealistic slope accumulation:

1. **Topographic Wetness Index (TWI)**:
   - Longitudinal slope and vertical route concavity ($\kappa_v = s_{next} - s_{prev}$) are evaluated along the track.
   - Steep slopes ($> 12\%$) and hill crests ($\kappa_v < -0.025$) drain rapidly and reject puddles.
   - Valleys, compressions, and flat zones accumulate water ($twi > 1.0$).
2. **Poisson Cluster Process**:
   - Puddles form wet zones / clusters of 1 to 4 puddles (1 primary puddle + 1–3 smaller satellite pools) separated by dry stretches of 35–75 m.
3. **Bimodal Lateral Offset (Wheel-Ruts & Road Shoulders)**:
   - Water never sticks strictly to the crown/centerline.
   - Parches are placed bimodally in vehicle wheel-tracks ($0.72\text{–}1.42\text{ m}$) or outer shoulders/ditches ($1.45\text{–}2.15\text{ m}$).
   - Curves bias puddle accumulation towards the inside radius ($75\%$ probability).
4. **Full 360° Free Yaw Rotation**:
   - Each puddle rotates independently ($0\text{..}2\pi$) around the surface normal, breaking directional alignment.

## Adaptive Conformal Mesh ($5 \times 5$ Grid)
- Rather than a flat rigid quad that gets rejected by cambered road borders, puddles are built as a $5 \times 5$ subdivided mesh using `SurfaceTool`.
- Each vertex is raycast onto `Collision_Road` to hug local ruts, bumps, and shoulder slopes.
- Vertices outside the road boundary have their heights smoothed and receive vertex color `COLOR.r = 0.0`. The shader uses this to smoothly feather the water edge prior to the road boundary, eliminating floating triangles.

## Double-Zone PBR Shading & Visual Depth Optics
`rally_puddle.gdshader` decomposes puddles into two concentric physical zones with distinct depth perception cues:
1. **Outer Wet Soil Ring** (`mask` between 0.006 and 0.26):
   - Simulates soaked mud around the puddle meniscus.
   - Multiplicatively darkens the dirt road underneath (`ALBEDO = vec3(0.012, 0.009, 0.007)`).
   - Zero emission, medium roughness ($0.48$), and subtle transparency ($0.38$).
2. **Inner Liquid Basin** (`mask > 0.18`):
   - **Beer-Lambert Turbidity Extinction**: exponential light extinction through suspended mud ($\text{turbidity} = 1 - \exp(-\text{depth} \cdot 0.065)$). Shallow puddles ($< 10\text{ mm}$) remain transparent ($\alpha \approx 0.22$) revealing rocks and road gravel underneath; deep potholes ($> 40\text{ mm}$) become opaque dark chocolate mud ($\alpha \approx 0.88$).
   - **Cavity Rim Occlusion**: deep potholes generate an internal embankment shadow along their perimeter ($1 - \text{rim} \cdot \text{depth\_norm} \cdot 0.55$), giving them a distinct sunken 3D hollow appearance.
   - **Meniscus Surface Tension Glint**: subtle specular highlight where water surface tension contacts the damp soil boundary.
   - **Depth-Modulated Ripple Dynamics**: shallow puddles produce high-frequency, low-amplitude capillary ripples, while deep water generates broad gravity waves that softly distort reflections.
   - **Chase-Camera Fresnel Recalibration**: multiplying $\mathbf{N} \cdot \mathbf{V}$ by $2.8$ keeps puddles at $6\text{–}15\text{ m}$ translucent and dark from the low chase camera, eliminating the "chalky gray paint disc" artifact while preserving horizon specular mirroring.

## Prefabricated PNG Masks & Natural Contours
- Dedicated grayscale PNG textures in `res://assets/vfx/puddles/`:
  - `puddle_round_organic.png`: smooth round potholes
  - `puddle_kidney_soft.png`: soft bean/kidney depressions
  - `puddle_egg_asym.png`: smooth oval/egg pools
  - `puddle_lobe_triple.png`: 3-lobed rounded ponds
- GPU samples `texture(puddle_mask, uv).r`; CPU samples the cached `Image` memory (`sample_image_mask`) with identical UV coordinates and random flips.

## Dry Weather Protection
- In dry weather (`precipitation_mm_h < 0.05` without antecedent rain), initial surface water is strictly `0.0 mm`.
- Each puddle profile defines a minimum activation threshold (`min_water`). When background water is below the threshold, `fill` is `0.0` and the mesh is hidden (`visible = false`). No puddles appear on dry roads.

## Physics: Impact, Drag & Handling Instability
1. **Two-Phase Hydrodynamic Resistance**:
   - **Continuous displacement drag**: combines linear viscous resistance and quadratic dynamic pressure:
     $$F_{\text{drag}} = (150 v + 2750 v^2) \cdot w_{\text{tire}} \cdot h_{\text{water}} \cdot \text{drag\_scale}$$
   - **Entry slam impulse**: when a wheel hits standing water at speed ($\Delta d / \Delta t > 0$), a sharp deceleration impulse is delivered immediately:
     $$F_{\text{slam}} = 22.5 \cdot w_{\text{tire}} \cdot \min(\Delta d / \Delta t, 200) \cdot v \cdot \text{drag\_scale}$$
     capped at $31.25\%$ of wheel normal load.
   - Total drag is capped at $81.25\%$ of wheel normal load ($+25\%$ maximum reaction force), producing massive, palpable G-force retarding deceleration and resistance when striking water.
2. **Wheel Rotational Braking**:
   - Hydrodynamic drag exerts direct braking torque on the tire tread ($\tau = F_{\text{drag}} \cdot 0.75 \cdot r_{\text{wheel}}$), added to `tire_reactions[i]`. This decelerates wheel rotation in `powertrain_model.solve_rotation`, creating authentic differential mismatch and engine lugging.
3. **Asymmetric Yaw & Steering Pull**:
   - Striking water on one side generates a violent chassis yaw moment and tugs the front steering angle via `steering_pull_nm` ($F_{\text{drag}} \cdot 0.07$).
4. **Differentiated Aquaplaning**:
   - Longitudinal support retains $20\%\text{–}45\%$ grip, while lateral cornering support drops to $6\%\text{–}25\%$, causing the vehicle to slide when turning through water. Reference evacuation speeds: $16\text{ m/s}$ (dry tires) vs $28\text{ m/s}$ (wet tires).

## Validation
- Unit contract: `godot --headless --path game --script res://tests/rally/puddles_contract.gd --quit-after 120`
- Stage integration probe: `godot --headless --path game --script res://tests/rally/puddles_stage_probe.gd --quit-after 500`
- Dynamic weather integration: `godot --headless --path game --script res://tests/rally/dynamic_weather_tires_contract.gd --quit-after 120`
- Vehicle VFX splash/spray contract: `godot --headless --path game --script res://tests/rally/vehicle_vfx_contract.gd --quit-after 120`
