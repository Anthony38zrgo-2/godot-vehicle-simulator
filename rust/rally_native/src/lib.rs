mod powertrain_solver;
mod procedural_weather;
mod puddles;
mod river_channels;
mod rng;
mod spatial_gis;
mod stage_grass;
mod suspension_rig;
mod telemetry_async;
mod tire_solver;
mod wheel_particles;

use godot::prelude::*;

struct RallyNativeExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RallyNativeExtension {}
