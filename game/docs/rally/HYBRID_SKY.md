# Dreamcast hybrid sky

The default Dreamcast mode instantiates `rally_hybrid_sky.gd` instead of Sky3D.
The non-retro mode retains the previous Sky3D integration. TCA remains the
precipitation adapter; calendar and contact surface physics are unchanged.

The shader samples two painted panoramas and one animated cloud-density map.
Mirrored UVs close image edges without extra samples. It has no ray marching,
cloud FBM, TIME input, screen/depth textures or volumetric fog. Sun and moon
disks share directions with the two directional lights. Night/twilight use color
treatments of the day assets; they are not separately painted night skies.

The event clock writes the hour as plain data. The visual owner applies it at
10 Hz, together with wind drift, coverage, illumination and depth fog. No
independent celestial timer or SkyDome cloud loop runs in retro mode. Pausing
the scene tree stops cloud drift. Ambient lighting is a fixed color, sky
reflections are disabled, and the unused sky radiance size is minimized to 32.
Sun shadows extend 80 m and stop in dense overcast or at night; moon shadows
are disabled. Three compressed textures have mipmaps enabled.

Asset prompts, origin and SHA-256 hashes are recorded in
`res://assets/weather/hybrid_sky/PROVENANCE.json`.

Validation:

- `godot --headless --path game --script res://tests/rally/weather_runtime_regression.gd`
- `godot --headless --path game --script res://tests/rally/hybrid_sky_contract.gd`
- Render captures: omit `--headless` and append `-- --hybrid-sky-capture`.
  Four PNGs are written into the OS temporary directory, covering clear,
  overcast, sunset and night in the stage scene.

Visual captures were checked at 1280x720 with Vulkan Forward+ on RTX 3050.
This confirms rendering, not an A/B frame-time improvement or driving acceptance.
