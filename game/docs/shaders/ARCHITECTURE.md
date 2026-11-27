# Modular Shader Architecture (SOLID & Data-Driven)

All project-owned shaders live under `res://shaders/` and are organized by responsibility into atomic `.gdshaderinc` libraries (`lib/`), domain entrypoints, JSON presets (`res://data/shaders/`), and GDScript builders (`res://scripts/shaders/`). Third-party addons under `res://addons/` remain isolated.

## Folder Structure

```text
game/shaders/
├── lib/
│   ├── atmosphere/
│   │   ├── depth_haze.gdshaderinc
│   │   ├── global_env_uniforms.gdshaderinc
│   │   └── sky_cubemap_sample.gdshaderinc
│   ├── math/
│   │   ├── coordinates.gdshaderinc
│   │   ├── cpu_gpu_parity.gdshaderinc        # Sealed parity with Rust/CPU simulation
│   │   └── hash_noise.gdshaderinc
│   ├── props/
│   │   └── psx_object_base.gdshaderinc
│   ├── retro/
│   │   ├── dither_quantize_fn.gdshaderinc    # Pure Bayer/PS1/RGB565 quantization
│   │   ├── psx_projection.gdshaderinc        # GTE vertex snap + affine pack/resolve
│   │   └── psx_quantize_uniforms.gdshaderinc
│   ├── surface/
│   │   ├── base_albedo_contract.gdshaderinc  # Unified LSP vehicle material contract
│   │   ├── procedural_road_film.gdshaderinc
│   │   ├── snow_accumulation.gdshaderinc
│   │   └── terrain_palette_gis.gdshaderinc
│   ├── vehicle/
│   │   ├── dirt_overlay.gdshaderinc          # <= 16 instance uniforms (Mobile safe)
│   │   ├── glass_droplets.gdshaderinc
│   │   ├── louver_slats.gdshaderinc
│   │   ├── paint_bands.gdshaderinc
│   │   └── toon_core.gdshaderinc
│   ├── vfx/
│   │   ├── billboard_sprite.gdshaderinc
│   │   ├── soft_particles.gdshaderinc
│   │   └── vehicle_sdf_exclusion.gdshaderinc
│   └── water/
│       ├── water_optics.gdshaderinc
│       └── water_waves.gdshaderinc
├── props/      # Stage objects, bush card outline, sign backs, workshop tint
├── terrain/    # Road asphalt, near blend, mid backdrop, far DEM, tire tracks
├── ui/         # Loading blur & showroom vignette canvas shaders
├── vehicle/    # Toon, cutout, louver, GT2, Dreamcast, exterior/interior glass, livery bake
├── vfx/        # Alpha & additive vehicle particles
├── water/      # Puddles/slush, PS2 rivers, static lakes
└── weather/    # Tropospheric sky & precipitation sprites
```

## SOLID Design & Data-Driven Workflow

- **Single Responsibility (`lib/` modules)**: Pure math, retro quantization, CPU↔GPU parity, water waves/optics, dirt overlays, and VFX billboarding live once in `lib/`.
- **Liskov Substitution (`base_albedo_contract.gdshaderinc`)**: Vehicle surface shaders (`vehicle.toon`, `vehicle.toon_cutout`, `vehicle.louver`, `vehicle.gt2`, `vehicle.dreamcast`) share the same base albedo/texture/normal/emission/PSX-snap uniforms and are interchangeable via `ShaderMaterialFactory.apply_vehicle_base_contract()`.
- **Open/Closed**: Per-vehicle styling parameters live in `res://data/vehicles/rt/<id>/visuals.json` (e.g. `rt-lancia-stratos/visuals.json`) and shared material presets in `res://data/shaders/presets/*.json`.
- **GDScript Core**:
  - `ShaderRegistry` (`game/scripts/shaders/shader_registry.gd`) — loads `res://data/shaders/shader_registry.json`, caches `Shader` resources & uniform schemas.
  - `ShaderPresetResolver` (`game/scripts/shaders/shader_preset_resolver.gd`) — resolves `extends` inheritance chains, quality profiles, and JSON-to-Godot type coercions.
  - `ShaderMaterialFactory` (`game/scripts/shaders/shader_material_factory.gd`) — instantiates `ShaderMaterial`s from presets or shader IDs.
  - `ShaderEnvironmentBus` (`game/scripts/shaders/shader_environment_bus.gd`) — publishes stage atmosphere/weather `[shader_globals]` defined in `project.godot`.

## Adding a New Shader or Preset

1. Place any reusable functions in an appropriate `game/shaders/lib/<category>/<name>.gdshaderinc` (remember Godot GLSL rules: never assign `varying`s inside non-`vertex()` helper functions, and avoid shadowing `uniform` names with function parameter names).
2. Create the `.gdshader` entrypoint under `game/shaders/<domain>/`.
3. Register its `shader_id` in `game/data/shaders/shader_registry.json`.
4. Add or extend presets in `game/data/shaders/presets/`.
5. Run `godot.cmd --headless --path game -s res://tests/rally/shader_architecture_contract.gd` to validate compilation, preset uniform schemas, and constraints.
