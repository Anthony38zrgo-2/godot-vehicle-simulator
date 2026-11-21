mod procedural_weather;
mod puddles;
mod river_channels;
mod rng;
mod spatial_gis;
mod stage_grass;
mod telemetry_async;
mod wheel_particles;

use godot::prelude::*;

struct RallyNativeExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RallyNativeExtension {}
