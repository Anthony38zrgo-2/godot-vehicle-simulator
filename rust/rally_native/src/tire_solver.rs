use godot::builtin::{PackedFloat64Array, Vector3};
use godot::classes::RefCounted;
use godot::prelude::*;

const STATIC_BLEND_FULL_M_S: f64 = 0.25;
const STATIC_BLEND_FREE_M_S: f64 = 1.25;
const STATIC_DAMPING_RATIO: f64 = 0.5;
const EFFECTIVE_RADIUS_COMPRESSION_GAIN: f64 = 0.92;
const EFFECTIVE_RADIUS_RIM_MARGIN_M: f64 = 0.01;
const ENVELOPE_PATCH_TAU_MIN_S: f64 = 0.002;
const CONTACT_LANDING_TAU_S: f64 = 0.02;
const RECOVERY_FZ_CAP_MULT: f64 = 2.4;

#[inline]
fn lerpf(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

#[inline]
fn smoothstep(edge0: f64, edge1: f64, x: f64) -> f64 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[inline]
fn brush_force_elliptical(dx: f64, dy: f64, limit_x: f64, limit_y: f64) -> (f64, f64) {
    if limit_x <= 1.0e-6 || limit_y <= 1.0e-6 {
        return (0.0, 0.0);
    }
    let nx = dx / limit_x;
    let ny = dy / limit_y;
    let mag = (nx * nx + ny * ny).sqrt();
    if mag <= 1.0e-9 {
        return (0.0, 0.0);
    }
    let theta = (mag / 3.0).clamp(0.0, 1.0);
    let factor = 3.0 * theta - 3.0 * theta * theta + theta * theta * theta;
    let scale = factor / mag;
    (nx * scale * limit_x, ny * scale * limit_y)
}

#[inline]
fn advance_memory(current: f64, target: f64, loss_tau: f64, recovery_tau: f64, delta: f64) -> f64 {
    let tau = if target > current { loss_tau } else { recovery_tau };
    if tau <= 1.0e-6 {
        return target;
    }
    let alpha = 1.0 - (-delta.max(0.0) / tau).exp();
    (current + (target - current) * alpha).clamp(0.0, 1.0)
}

#[derive(Clone, Copy)]
struct WheelConfig {
    surface_tau_s: f64,
    base_contact_patch_m: f64,
    base_relaxation_length_m: f64,
    static_deflection_ratio: f64,
    static_wheel_load_n: f64,
    maximum_tire_deflection_m: f64,
    reference_hot_pressure_kpa: f64,
    load_sensitivity_exp: f64,
    rolling_coefficient: f64,
    pneumatic_trail: f64,
    camber_gain: f64,
    contact_load_gain: f64,
    contact_deflection_gain: f64,
    pressure_relaxation: f64,
    pressure_rolling: f64,
    optimal_carcass_c: f64,

    // Profile
    contact_ramp_tau_s: f64,
    min_relaxation_tau_s: f64,
    relaxation_recovery_scale: f64,
    peak_load_sensitivity: f64,
    lateral_peak_slip_angle_rad: f64,
    longitudinal_peak_slip_ratio: f64,
    lateral_slide_mu_ratio: f64,
    longitudinal_slide_mu_ratio: f64,
    combined_lateral_peak_migration: f64,
    combined_longitudinal_peak_migration: f64,
    legacy_longitudinal_relief: f64,
    legacy_relief_blend_m: f64,
    falloff_sharpness: f64,
    slip_loss_tau_s: f64,
    slip_recovery_tau_s: f64,

    // Compound
    water_grip_loss_per_mm: f64,
    water_grip_floor: f64,
    snow_grip_loss_per_mm: f64,
    snow_grip_floor: f64,
    water_evacuation_ref_speed: f64,
    road_grip_scale: f64,
    loose_grip_scale: f64,
    uncovered_grip_scale: f64,
    snow_packed_grip_scale: f64,
    snow_loose_grip_scale: f64,
    ice_grip_scale: f64,
    mud_comp_floor: f64,

    migration_v2_enabled: bool,
    has_compound: bool,
    is_snow_studded: bool,
}

impl Default for WheelConfig {
    fn default() -> Self {
        Self {
            surface_tau_s: 0.0,
            base_contact_patch_m: 0.2,
            base_relaxation_length_m: 0.3,
            static_deflection_ratio: 0.2,
            static_wheel_load_n: 3000.0,
            maximum_tire_deflection_m: 0.1,
            reference_hot_pressure_kpa: 225.0,
            load_sensitivity_exp: 0.15,
            rolling_coefficient: 0.015,
            pneumatic_trail: 0.035,
            camber_gain: 0.15,
            contact_load_gain: 0.12,
            contact_deflection_gain: 0.20,
            pressure_relaxation: 0.0,
            pressure_rolling: 0.0,
            optimal_carcass_c: 60.0,

            contact_ramp_tau_s: 0.0,
            min_relaxation_tau_s: 0.0,
            relaxation_recovery_scale: 1.0,
            peak_load_sensitivity: 0.0,
            lateral_peak_slip_angle_rad: 0.18,
            longitudinal_peak_slip_ratio: 0.2,
            lateral_slide_mu_ratio: 0.94,
            longitudinal_slide_mu_ratio: 0.95,
            combined_lateral_peak_migration: 0.0,
            combined_longitudinal_peak_migration: 0.0,
            legacy_longitudinal_relief: 0.0,
            legacy_relief_blend_m: 0.01,
            falloff_sharpness: 1.2,
            slip_loss_tau_s: 0.0,
            slip_recovery_tau_s: 0.0,

            water_grip_loss_per_mm: 0.12,
            water_grip_floor: 0.6,
            snow_grip_loss_per_mm: 0.09,
            snow_grip_floor: 0.6,
            water_evacuation_ref_speed: 16.0,
            road_grip_scale: 1.0,
            loose_grip_scale: 1.0,
            uncovered_grip_scale: 1.0,
            snow_packed_grip_scale: 0.45,
            snow_loose_grip_scale: 0.45,
            ice_grip_scale: 0.18,
            mud_comp_floor: 1.0,

            migration_v2_enabled: false,
            has_compound: false,
            is_snow_studded: false,
        }
    }
}

#[derive(Clone, Copy, Default)]
struct WheelState {
    patch_x: f64,
    patch_y: f64,
    patch_fwd: [f64; 3],
    patch_right: [f64; 3],
    patch_energy_j: f64,
    effective_slip_angle: f64,
    effective_slip_ratio: f64,
    post_peak_decay_lat: f64,
    post_peak_decay_lon: f64,
    contact_blend: f64,
    surface_initialized: bool,
    surface_friction: f64,
    surface_stiffness: f64,
    surface_rolling: f64,
    dynamic_contact_patch_m: f64,
    relaxation_length_m: f64,
    enveloped_load_n: f64,
    envelope_valid: bool,
    effective_radius_m: f64,
    liftoff_discard_j: f64,
    contact_work_j: f64,
    heat_work_j: f64,
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustTireSolver {
    configs: [WheelConfig; 4],
    states: [WheelState; 4],
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustTireSolver {
    fn init(base: Base<RefCounted>) -> Self {
        let mut states = [WheelState::default(); 4];
        for st in &mut states {
            st.dynamic_contact_patch_m = 0.2;
            st.relaxation_length_m = 0.3;
            st.effective_radius_m = 0.28;
        }
        Self {
            configs: [WheelConfig::default(); 4],
            states,
            base,
        }
    }
}

impl RustTireSolver {
    #[inline]
    fn compound_wsg(
        cfg: &WheelConfig,
        water_mm: f64,
        snow_mm: f64,
        ground_c: f64,
        planar_speed: f64,
    ) -> (f64, f64, f64, f64) {
        if !cfg.has_compound {
            return (1.0, 1.0, 1.0, 1.0);
        }
        let w = water_mm.clamp(0.0, 12.0);
        let s = snow_mm.clamp(0.0, 8.0);
        let wf_static = (1.0 - w * cfg.water_grip_loss_per_mm).max(cfg.water_grip_floor);
        let sf = (1.0 - s * cfg.snow_grip_loss_per_mm).max(cfg.snow_grip_floor);
        let evac = cfg.water_evacuation_ref_speed.max(1.0);
        let speed_ratio = (planar_speed / evac).clamp(0.0, 1.0);
        let speed_gain = 0.35 + 0.65 * speed_ratio * speed_ratio;
        let wf = if w > 1.0e-9 {
            1.0 - (1.0 - wf_static) * speed_gain
        } else {
            1.0
        };
        let gf = if ground_c < 5.0 {
            lerpf(0.92, 1.0, ((ground_c + 5.0) / 10.0).clamp(0.0, 1.0))
        } else if ground_c > 32.0 {
            lerpf(1.0, 0.96, ((ground_c - 32.0) / 12.0).clamp(0.0, 1.0))
        } else {
            1.0
        };
        (wf, sf, gf, (wf * sf * gf).clamp(0.35, 1.0))
    }

    #[inline]
    fn footprint_weights(snow_cov: f64, ice_cov: f64) -> (f64, f64, f64) {
        let w_snow = snow_cov.clamp(0.0, 1.0);
        let w_ice = (ice_cov * (1.0 - w_snow * 0.7)).clamp(0.0, (1.0 - w_snow).max(0.0));
        let w_dry = (1.0 - w_snow - w_ice).max(0.0);
        let total = (w_dry + w_snow + w_ice).max(1.0e-6);
        (w_dry / total, w_snow / total, w_ice / total)
    }
}

#[godot_api]
impl RustTireSolver {
    #[func]
    fn sync_wheel_config(&mut self, wheel: i32, cfg43: PackedFloat64Array, flags: i32) {
        if !(0..4).contains(&wheel) {
            return;
        }
        let c = cfg43.as_slice();
        if c.len() < 43 {
            return;
        }
        let idx = wheel as usize;
        self.configs[idx] = WheelConfig {
            surface_tau_s: c[0],
            base_contact_patch_m: c[1],
            base_relaxation_length_m: c[2],
            static_deflection_ratio: c[3],
            static_wheel_load_n: c[4],
            maximum_tire_deflection_m: c[5],
            reference_hot_pressure_kpa: c[6],
            load_sensitivity_exp: c[7],
            rolling_coefficient: c[8],
            pneumatic_trail: c[9],
            camber_gain: c[10],
            contact_load_gain: c[11],
            contact_deflection_gain: c[12],
            pressure_relaxation: c[13],
            pressure_rolling: c[14],
            optimal_carcass_c: c[15],

            contact_ramp_tau_s: c[16],
            min_relaxation_tau_s: c[17],
            relaxation_recovery_scale: c[18],
            peak_load_sensitivity: c[19],
            lateral_peak_slip_angle_rad: c[20],
            longitudinal_peak_slip_ratio: c[21],
            lateral_slide_mu_ratio: c[22],
            longitudinal_slide_mu_ratio: c[23],
            combined_lateral_peak_migration: c[24],
            combined_longitudinal_peak_migration: c[25],
            legacy_longitudinal_relief: c[26],
            legacy_relief_blend_m: c[27],
            falloff_sharpness: c[28],
            slip_loss_tau_s: c[29],
            slip_recovery_tau_s: c[30],

            water_grip_loss_per_mm: c[31],
            water_grip_floor: c[32],
            snow_grip_loss_per_mm: c[33],
            snow_grip_floor: c[34],
            water_evacuation_ref_speed: c[35],
            road_grip_scale: c[36],
            loose_grip_scale: c[37],
            uncovered_grip_scale: c[38],
            snow_packed_grip_scale: c[39],
            snow_loose_grip_scale: c[40],
            ice_grip_scale: c[41],
            mud_comp_floor: c[42],

            migration_v2_enabled: (flags & (1 << 0)) != 0,
            has_compound: (flags & (1 << 1)) != 0,
            is_snow_studded: (flags & (1 << 2)) != 0,
        };
    }

    #[func]
    fn reset_all(&mut self) {
        for i in 0..4 {
            let cfg = self.configs[i];
            self.states[i] = WheelState {
                dynamic_contact_patch_m: cfg.base_contact_patch_m,
                relaxation_length_m: cfg.base_relaxation_length_m,
                enveloped_load_n: cfg.static_wheel_load_n,
                effective_radius_m: 0.28,
                ..WheelState::default()
            };
        }
    }

    #[func]
    fn reset_patch(&mut self, wheel: i32) {
        if !(0..4).contains(&wheel) {
            return;
        }
        let idx = wheel as usize;
        let cfg = self.configs[idx];
        let st = &mut self.states[idx];
        st.patch_x = 0.0;
        st.patch_y = 0.0;
        st.patch_fwd = [0.0; 3];
        st.patch_right = [0.0; 3];
        st.patch_energy_j = 0.0;
        st.effective_slip_angle = 0.0;
        st.effective_slip_ratio = 0.0;
        st.post_peak_decay_lat = 0.0;
        st.post_peak_decay_lon = 0.0;
        st.contact_blend = 0.0;
        st.enveloped_load_n = 0.0;
        st.envelope_valid = false;
        st.dynamic_contact_patch_m = cfg.base_contact_patch_m;
        st.relaxation_length_m = cfg.base_relaxation_length_m;
        st.liftoff_discard_j = 0.0;
    }

    #[func]
    fn rotate_patch_frame(&mut self, wheel: i32, forward: Vector3, right: Vector3) {
        if !(0..4).contains(&wheel) {
            return;
        }
        let st = &mut self.states[wheel as usize];
        let pf = st.patch_fwd;
        let lsq = pf[0] * pf[0] + pf[1] * pf[1] + pf[2] * pf[2];
        let fx = forward.x as f64;
        let fy = forward.y as f64;
        let fz = forward.z as f64;
        let rx = right.x as f64;
        let ry = right.y as f64;
        let rz = right.z as f64;
        if lsq > 0.5 {
            let pr = st.patch_right;
            let wx = pf[0] * st.patch_x + pr[0] * st.patch_y;
            let wy = pf[1] * st.patch_x + pr[1] * st.patch_y;
            let wz = pf[2] * st.patch_x + pr[2] * st.patch_y;
            st.patch_x = wx * fx + wy * fy + wz * fz;
            st.patch_y = wx * rx + wy * ry + wz * rz;
        }
        st.patch_fwd = [fx, fy, fz];
        st.patch_right = [rx, ry, rz];
    }

    /// flags:
    ///   bits 0..2: surface_kind (0=other, 1=Road, 2=Gravel/Dirt, 3=Sand)
    ///   bits 3..5: winter_layer_code (0=none, 1=snow_packed, 2=snow_loose, 3=snow_deep, 4=ice)
    ///   bit 6: recovery_low_confidence
    #[func]
    fn evaluate_wheel(&mut self, wheel: i32, inp24: PackedFloat64Array, flags: i32) -> PackedFloat64Array {
        let mut out = PackedFloat64Array::new();
        out.resize(43);
        if !(0..4).contains(&wheel) {
            return out;
        }
        let s = inp24.as_slice();
        if s.len() < 24 {
            return out;
        }
        let idx = wheel as usize;
        let cfg = self.configs[idx];
        let st = &mut self.states[idx];

        let normal_load_n = s[0];
        let longitudinal_speed = s[1];
        let lateral_speed = s[2];
        let wheel_speed_rad_s = s[3];
        let rolling_radius_m = s[4];
        let camber_rad = s[5];
        let thermal_grip_factor = s[6];
        let pressure_kpa_gauge = s[7];
        let delta = s[8];
        let carcass_temp_c = s[9];
        let water_mm = s[10];
        let snow_mm = s[11];
        let ground_temp_c = s[12];
        let _ice_mm = s[13];
        let snow_coverage = s[14];
        let ice_coverage = s[15];
        let loose_gravel_coverage = s[16];
        let mud_factor = s[17];
        let mut target_friction = s[18];
        let mut target_stiffness = s[19];
        let mut target_rolling = s[20];
        let target_lon_ratio = s[21];
        let mut target_lat_assist = s[22];
        let estimated_deflection = s[23];

        let surface_kind = flags & 0x7;
        let winter_code = (flags >> 3) & 0x7;
        let recovery_low_confidence = (flags & (1 << 6)) != 0;

        let is_gravel_or_dirt = surface_kind == 2;
        let eff_loose_cov = if is_gravel_or_dirt {
            loose_gravel_coverage.clamp(0.0, 1.0)
        } else {
            0.0
        };
        let eff_mud = if is_gravel_or_dirt {
            mud_factor.clamp(0.0, 1.0)
        } else {
            0.0
        };
        let dry_loose = (eff_loose_cov - eff_mud).clamp(0.0, 1.0);
        if eff_loose_cov > 0.001 || eff_mud > 0.001 {
            let fric_scale = 1.0 - 0.11 * dry_loose - 0.38 * eff_mud;
            let stiff_scale = 1.0 - 0.16 * dry_loose - 0.44 * eff_mud;
            let roll_scale = 1.0 + 0.08 * dry_loose + 1.75 * eff_mud;
            let lat_assist_scale = 1.0 - 0.12 * dry_loose - 0.62 * eff_mud;
            target_friction *= fric_scale;
            target_stiffness *= stiff_scale;
            target_rolling *= roll_scale;
            target_lat_assist *= lat_assist_scale;
        }

        let tau_surface = cfg.surface_tau_s.max(0.0);
        if !st.surface_initialized {
            st.surface_friction = target_friction;
            st.surface_stiffness = target_stiffness;
            st.surface_rolling = target_rolling;
            st.surface_initialized = true;
        } else {
            let surface_alpha = if tau_surface <= 1.0e-9 {
                1.0
            } else {
                1.0 - (-delta.max(0.0) / tau_surface).exp()
            };
            st.surface_friction += (target_friction - st.surface_friction) * surface_alpha;
            st.surface_stiffness += (target_stiffness - st.surface_stiffness) * surface_alpha;
            st.surface_rolling += (target_rolling - st.surface_rolling) * surface_alpha;
        }

        let contact_target = normal_load_n > 1.0e-4;
        let contact_tau = cfg.contact_ramp_tau_s.clamp(0.0, 1.0);
        let effective_contact_tau = if contact_target && st.contact_blend < 1.0 {
            contact_tau.min(CONTACT_LANDING_TAU_S)
        } else {
            contact_tau
        };
        if effective_contact_tau <= 1.0e-9 {
            st.contact_blend = if contact_target { 1.0 } else { 0.0 };
        } else {
            let contact_alpha = 1.0 - (-delta.max(0.0) / effective_contact_tau).exp();
            let target_b = if contact_target { 1.0 } else { 0.0 };
            st.contact_blend =
                (st.contact_blend + (target_b - st.contact_blend) * contact_alpha).clamp(0.0, 1.0);
        }

        if !contact_target {
            let recovery_tau = cfg.slip_recovery_tau_s;
            let release = if recovery_tau <= 1.0e-6 {
                0.0
            } else {
                (-delta.max(0.0) / recovery_tau).exp()
            };
            st.liftoff_discard_j += st.patch_energy_j;
            st.patch_x = 0.0;
            st.patch_y = 0.0;
            st.patch_fwd = [0.0; 3];
            st.patch_right = [0.0; 3];
            st.patch_energy_j = 0.0;
            st.enveloped_load_n = 0.0;
            st.envelope_valid = false;
            st.dynamic_contact_patch_m = cfg.base_contact_patch_m;
            st.relaxation_length_m = cfg.base_relaxation_length_m;
            st.effective_slip_angle = 0.0;
            st.effective_slip_ratio = 0.0;
            st.post_peak_decay_lat *= release;
            st.post_peak_decay_lon *= release;

            let o = out.as_mut_slice();
            o[6] = st.effective_radius_m;
            o[19] = st.liftoff_discard_j;
            o[20] = st.contact_work_j;
            o[21] = st.heat_work_j;
            o[26] = st.dynamic_contact_patch_m;
            o[27] = st.relaxation_length_m;
            o[29] = 1.0;
            o[30] = 1.0;
            o[31] = 1.0;
            o[32] = 1.0;
            o[33] = 1.0;
            o[36] = st.post_peak_decay_lat;
            o[37] = st.post_peak_decay_lon;
            o[38] = st.contact_blend;
            o[39] = st.surface_friction;
            o[40] = st.surface_stiffness;
            o[41] = st.surface_rolling;
            return out;
        }

        let planar_speed =
            (longitudinal_speed * longitudinal_speed + lateral_speed * lateral_speed).sqrt();
        let envelope_tau = (st.dynamic_contact_patch_m / planar_speed.max(1.0)).max(ENVELOPE_PATCH_TAU_MIN_S);
        if !st.envelope_valid {
            st.enveloped_load_n = normal_load_n.max(0.0);
            st.envelope_valid = true;
        } else {
            let env_alpha = 1.0 - (-delta.max(0.0) / envelope_tau.max(1.0e-4)).exp();
            st.enveloped_load_n = lerpf(st.enveloped_load_n, normal_load_n.max(0.0), env_alpha);
        }
        let enveloped_load = st.enveloped_load_n.max(0.0);

        let nominal_radius = rolling_radius_m.max(0.05);
        let sidewall_max = cfg.maximum_tire_deflection_m;
        let rim = (nominal_radius - sidewall_max.max(0.03)).max(0.05);
        let radius = (nominal_radius - estimated_deflection.max(0.0) * EFFECTIVE_RADIUS_COMPRESSION_GAIN)
            .max(rim + EFFECTIVE_RADIUS_RIM_MARGIN_M);
        st.effective_radius_m = radius;

        let rim_speed = wheel_speed_rad_s * radius;
        let speed_reference = longitudinal_speed.abs().max(rim_speed.abs()).max(1.0);
        let target_ratio = ((rim_speed - longitudinal_speed) / speed_reference).clamp(-3.0, 3.0);
        let target_angle = (-lateral_speed)
            .atan2(longitudinal_speed.abs().max(0.5))
            .clamp(-0.75, 0.75);

        let reference_load = cfg.static_wheel_load_n.max(100.0);
        let load_ratio = (normal_load_n.max(0.0) / reference_load).max(0.05);
        let pressure_ratio = (pressure_kpa_gauge / cfg.reference_hot_pressure_kpa).max(0.001);
        let deflection_ratio = (estimated_deflection / sidewall_max).clamp(0.0, 1.5);
        let patch_scale = (1.0
            + cfg.contact_load_gain * (load_ratio - 1.0)
            + cfg.contact_deflection_gain * (deflection_ratio - cfg.static_deflection_ratio))
            .clamp(0.70, 1.45);
        let dynamic_contact_patch = cfg.base_contact_patch_m * patch_scale;
        let patch_ratio = (dynamic_contact_patch / cfg.base_contact_patch_m).clamp(0.70, 1.50);
        let pressure_relaxation_scale = pressure_ratio
            .powf(cfg.pressure_relaxation.clamp(-3.0, 3.0))
            .clamp(0.80, 1.30);
        let relaxation_length =
            cfg.base_relaxation_length_m * patch_ratio.sqrt() * pressure_relaxation_scale;
        st.dynamic_contact_patch_m = dynamic_contact_patch;
        st.relaxation_length_m = relaxation_length;

        let min_relaxation_tau = cfg.min_relaxation_tau_s.clamp(0.0, 0.5);
        let relaxation_tau = (relaxation_length / planar_speed.max(4.0)).max(min_relaxation_tau);
        let recovery_scale = cfg.relaxation_recovery_scale.clamp(0.1, 5.0);
        let lat_recovering = st.effective_slip_angle.abs() > target_angle.abs();
        let lon_recovering = st.effective_slip_ratio.abs() > target_ratio.abs();
        let lat_tau = relaxation_tau * if lat_recovering { recovery_scale } else { 1.0 };
        let lon_tau = relaxation_tau * if lon_recovering { recovery_scale } else { 1.0 };
        let lat_alpha = 1.0 - (-delta.max(0.0) / lat_tau.max(1.0e-4)).exp();
        let lon_alpha = 1.0 - (-delta.max(0.0) / lon_tau.max(1.0e-4)).exp();
        st.effective_slip_angle += (target_angle - st.effective_slip_angle) * lat_alpha;
        st.effective_slip_ratio += (target_ratio - st.effective_slip_ratio) * lon_alpha;

        let mut fz = enveloped_load;
        let mut fz_static = normal_load_n.max(0.0);
        if recovery_low_confidence {
            let cap = (reference_load * RECOVERY_FZ_CAP_MULT).max(100.0);
            fz = fz.min(cap);
            fz_static = fz_static.min(cap);
        }
        let pressure_rr = pressure_ratio
            .powf(cfg.pressure_rolling.clamp(-3.0, 3.0))
            .clamp(0.75, 1.50);
        let load_scale = ((load_ratio * reference_load).max(1.0) / reference_load.max(1.0))
            .powf(-cfg.load_sensitivity_exp.clamp(0.0, 0.5))
            .clamp(0.60, 1.20);

        let mut compound_mult = 1.0;
        let mut cw_factor = 1.0;
        let mut cs_factor = 1.0;
        let mut cg_factor = 1.0;
        let procedural_blend = winter_code == 0 && (snow_coverage >= 0.0 || ice_coverage >= 0.0);
        let mut fp_w = (1.0, 0.0, 0.0);

        if cfg.has_compound {
            if procedural_blend {
                fp_w = Self::footprint_weights(snow_coverage.max(0.0), ice_coverage.max(0.0));
                let (wf, _sf, gf, _comb) =
                    Self::compound_wsg(&cfg, water_mm, 0.0, ground_temp_c, planar_speed);
                let mut base_surface_scale = match surface_kind {
                    1 => cfg.road_grip_scale,
                    2 | 3 => cfg.loose_grip_scale,
                    _ => 1.0,
                };
                if cfg.is_snow_studded {
                    base_surface_scale *= cfg.uncovered_grip_scale;
                }
                let exposed_comp = wf * gf * base_surface_scale;
                let snow_depth_t = ((snow_mm - 2.0) / 4.0).clamp(0.0, 1.0);
                let snow_scale =
                    lerpf(cfg.snow_packed_grip_scale, cfg.snow_loose_grip_scale, snow_depth_t);
                let snow_comp = snow_scale * gf * lerpf(1.0, wf, 0.35);
                let ice_comp = cfg.ice_grip_scale * wf * gf;
                compound_mult =
                    (fp_w.0 * exposed_comp + fp_w.1 * snow_comp + fp_w.2 * ice_comp).clamp(0.05, 1.25);
                cw_factor = wf;
                cs_factor = if fp_w.1 >= fp_w.2 {
                    snow_scale
                } else {
                    cfg.ice_grip_scale
                };
                cg_factor = gf;
            } else if winter_code >= 1 && winter_code <= 4 {
                let snow_base = match winter_code {
                    1 => cfg.snow_packed_grip_scale,
                    2 | 3 => cfg.snow_loose_grip_scale,
                    4 => cfg.ice_grip_scale,
                    _ => 1.0,
                };
                let (wf, _sf, gf, wet_mult) =
                    Self::compound_wsg(&cfg, water_mm, snow_mm, ground_temp_c, planar_speed);
                cw_factor = wf;
                cs_factor = snow_base;
                cg_factor = gf;
                compound_mult = (snow_base * wet_mult).clamp(0.05, 1.0);
                if cfg.is_snow_studded && winter_code != 4 {
                    compound_mult = (compound_mult * cfg.uncovered_grip_scale).clamp(0.05, 1.0);
                }
            } else {
                let (wf, sf, gf, comb) =
                    Self::compound_wsg(&cfg, water_mm, snow_mm, ground_temp_c, planar_speed);
                cw_factor = wf;
                cs_factor = sf;
                cg_factor = gf;
                compound_mult = comb;
                if cfg.is_snow_studded {
                    compound_mult *= cfg.uncovered_grip_scale;
                }
            }
        }
        if winter_code == 0 && !procedural_blend && cfg.has_compound {
            match surface_kind {
                1 => compound_mult *= cfg.road_grip_scale,
                2 | 3 => compound_mult *= cfg.loose_grip_scale,
                _ => {}
            }
        }
        if eff_mud > 0.001 && cfg.has_compound {
            compound_mult *= lerpf(1.0, cfg.mud_comp_floor, eff_mud);
        }

        let mu =
            st.surface_friction.max(0.0) * load_scale * thermal_grip_factor.clamp(0.05, 1.0) * compound_mult;
        let longitudinal_ratio = target_lon_ratio.clamp(0.10, 1.50);
        let lateral_bonus = 1.0 + target_lat_assist.clamp(-0.5, 1.0);
        let fx_capacity = (mu * longitudinal_ratio * fz).max(1.0e-6);
        let fy_capacity = (mu * lateral_bonus * fz).max(1.0e-6);
        let stiffness_scale = (st.surface_stiffness.max(0.0) / 5.0).clamp(0.15, 2.5).sqrt();
        let rise_gamma = (2.0 * stiffness_scale).clamp(1.2, 4.0);
        let peak_load_exp = cfg.peak_load_sensitivity.clamp(-0.5, 0.5);
        let peak_load_scale = if peak_load_exp.abs() > 1.0e-9 {
            load_ratio.powf(peak_load_exp)
        } else {
            1.0
        };
        let peak_thermal_scale =
            (0.85 + 0.15 * thermal_grip_factor.clamp(0.0, 1.0)).clamp(0.85, 1.0);
        let base_peak_lat =
            (cfg.lateral_peak_slip_angle_rad * peak_load_scale * peak_thermal_scale).max(1.0e-6);
        let base_peak_lon =
            (cfg.longitudinal_peak_slip_ratio * peak_load_scale * peak_thermal_scale).max(1.0e-6);
        let carcass_stiff_scale =
            (1.0 - 0.0015 * (carcass_temp_c - cfg.optimal_carcass_c)).clamp(0.88, 1.12);
        let slide_lat = cfg.lateral_slide_mu_ratio.clamp(0.0, 1.0);
        let slide_lon = cfg.longitudinal_slide_mu_ratio.clamp(0.0, 1.0);
        let signed_camber = camber_rad * if idx == 0 || idx == 2 { 1.0 } else { -1.0 };
        let blend = st.contact_blend;

        let patch_before_x = st.patch_x;
        let patch_before_y = st.patch_y;
        let transport_speed = planar_speed.max(rim_speed.abs());
        let transport_rate = transport_speed / relaxation_length.max(0.001);
        let pv_x = rim_speed - longitudinal_speed;
        let pv_y = -lateral_speed
            + longitudinal_speed.abs() * (signed_camber * cfg.camber_gain).clamp(-0.5, 0.5).tan();
        let patch_dt = delta.max(0.0);
        let mut px = patch_before_x + pv_x * patch_dt;
        let mut py = patch_before_y + pv_y * patch_dt;
        if transport_rate > 1.0e-6 {
            let transport_tau = 1.0 / transport_rate;
            let lon_patch_tau =
                min_relaxation_tau.max(transport_tau * if lon_recovering { recovery_scale } else { 1.0 });
            let lat_patch_tau =
                min_relaxation_tau.max(transport_tau * if lat_recovering { recovery_scale } else { 1.0 });
            px = lerpf(
                patch_before_x,
                pv_x / transport_rate,
                1.0 - (-patch_dt / lon_patch_tau).exp(),
            );
            py = lerpf(
                patch_before_y,
                pv_y / transport_rate,
                1.0 - (-patch_dt / lat_patch_tau).exp(),
            );
        }

        let length_m = relaxation_length.max(0.001);
        let mut stiffness_x = fx_capacity * 3.0 * carcass_stiff_scale / (base_peak_lon * length_m);
        let mut stiffness_y =
            fy_capacity * rise_gamma * carcass_stiff_scale / (base_peak_lat * length_m);
        let mut trial_x = stiffness_x * px;
        let mut trial_y = stiffness_y * py;

        if cfg.migration_v2_enabled {
            let ux = (trial_x.abs() / (3.0 * fx_capacity).max(1.0e-6)).clamp(0.0, 1.0);
            let uy = (trial_y.abs() / (rise_gamma * fy_capacity).max(1.0e-6)).clamp(0.0, 1.0);
            let m_lat = cfg.combined_lateral_peak_migration.clamp(0.0, 0.65);
            let m_lon = cfg.combined_longitudinal_peak_migration.clamp(0.0, 0.65);
            let peak_lat_eff = base_peak_lat * (1.0 + m_lat * ux);
            let peak_lon_eff = base_peak_lon * (1.0 + m_lon * uy);
            stiffness_x = fx_capacity * 3.0 * carcass_stiff_scale / (peak_lon_eff * length_m);
            stiffness_y = fy_capacity * rise_gamma * carcass_stiff_scale / (peak_lat_eff * length_m);
            trial_x = stiffness_x * px;
            trial_y = stiffness_y * py;
        }

        let mut norm_demand_x = trial_x.abs() / fx_capacity;
        let norm_demand_y = trial_y.abs() / fy_capacity;
        if !cfg.migration_v2_enabled {
            let legacy_relief = cfg.legacy_longitudinal_relief.clamp(0.0, 0.65);
            if legacy_relief > 1.0e-9 {
                let legacy_blend_m = cfg.legacy_relief_blend_m.clamp(0.001, 0.10);
                let relief_s = smoothstep(-legacy_blend_m, legacy_blend_m, px);
                norm_demand_x *= 1.0 - legacy_relief * relief_s;
            }
        }

        let combined_theta = (norm_demand_x * norm_demand_x + norm_demand_y * norm_demand_y).sqrt() / 3.0;
        let sharpness = cfg.falloff_sharpness.clamp(0.2, 8.0);
        let over_peak = (((combined_theta - 0.68) / 0.32) * sharpness).clamp(0.0, 1.0);
        let target_decay = over_peak * over_peak * (3.0 - 2.0 * over_peak);
        let lat_weight = norm_demand_y / (norm_demand_x + norm_demand_y).max(1.0e-6);
        let lon_weight = 1.0 - lat_weight;
        st.post_peak_decay_lat = advance_memory(
            st.post_peak_decay_lat,
            target_decay * lat_weight,
            cfg.slip_loss_tau_s,
            cfg.slip_recovery_tau_s,
            delta,
        );
        st.post_peak_decay_lon = advance_memory(
            st.post_peak_decay_lon,
            target_decay * lon_weight,
            cfg.slip_loss_tau_s,
            cfg.slip_recovery_tau_s,
            delta,
        );

        let sliding_fraction = (st.post_peak_decay_lon + st.post_peak_decay_lat).clamp(0.0, 1.0);
        let directional_slide_mu = lerpf(slide_lon, slide_lat, lat_weight);
        let slide_scale = lerpf(1.0, directional_slide_mu, sliding_fraction);
        let limit_x = fx_capacity * slide_scale;
        let limit_y = fy_capacity * slide_scale;

        let mut plastic_loss_j = 0.0;
        if limit_x <= 1.0e-6 || limit_y <= 1.0e-6 {
            px = 0.0;
            py = 0.0;
            trial_x = 0.0;
            trial_y = 0.0;
        } else {
            let ntx = trial_x / limit_x;
            let nty = trial_y / limit_y;
            let mut norm_length = (ntx * ntx + nty * nty).sqrt();
            let unloading = (px * pv_x + py * pv_y) < 0.0;
            let current_theta = norm_length / 3.0;
            if unloading && current_theta > 0.5 {
                let recovery_boost =
                    (-((current_theta - 0.5) * 12.0).clamp(0.0, 15.0) * patch_dt).exp();
                px *= recovery_boost;
                py *= recovery_boost;
                trial_x *= recovery_boost;
                trial_y *= recovery_boost;
                norm_length *= recovery_boost;
            }
            let max_elastic_norm = 2.65;
            if norm_length > max_elastic_norm {
                let ps = max_elastic_norm / norm_length;
                let e_pre = 0.5 * (trial_x * px + trial_y * py) * blend;
                px *= ps;
                py *= ps;
                trial_x *= ps;
                trial_y *= ps;
                let e_post = 0.5 * (trial_x * px + trial_y * py) * blend;
                plastic_loss_j = (e_pre - e_post).max(0.0);
            }
        }

        let (bx_u, by_u) = brush_force_elliptical(trial_x, trial_y, limit_x, limit_y);
        let mut fx = bx_u * blend;
        let mut fy = by_u * blend;

        let static_w = 1.0 - smoothstep(STATIC_BLEND_FULL_M_S, STATIC_BLEND_FREE_M_S, transport_speed);
        if static_w > 1.0e-6 {
            let anchor_mass = fz.max(100.0) / 9.81;
            let damp_scale = static_w * STATIC_DAMPING_RATIO;
            let static_damp_x = 2.0 * damp_scale * (stiffness_x * anchor_mass).max(1.0).sqrt();
            let static_damp_y = 2.0 * damp_scale * (stiffness_y * anchor_mass).max(1.0).sqrt();
            let mut fsx = (stiffness_x * px + static_damp_x * pv_x) * blend;
            let mut fsy = (stiffness_y * py + static_damp_y * pv_y) * blend;
            let cx = fsx / limit_x.max(1.0e-6);
            let cy = fsy / limit_y.max(1.0e-6);
            let cap_norm = (cx * cx + cy * cy).sqrt();
            if cap_norm > 1.0 {
                fsx /= cap_norm;
                fsy /= cap_norm;
            }
            fx = lerpf(fx, fsx, static_w);
            fy = lerpf(fy, fsy, static_w);
        }

        let dot_tp = trial_x * px + trial_y * py;
        let patch_energy = 0.5 * dot_tp * blend;
        let previous_patch_energy = st.patch_energy_j;
        let blend_loss_j = (0.5 * dot_tp * (1.0 - blend)).max(0.0);
        st.patch_x = px;
        st.patch_y = py;
        st.patch_energy_j = patch_energy;

        let rolling_spin = (rim_speed.abs() / 0.5).clamp(0.0, 1.0);
        let rolling_base = fz_static * cfg.rolling_coefficient * st.surface_rolling * pressure_rr;
        let mut rolling_force =
            rolling_base * (longitudinal_speed / 0.3).tanh() * rolling_spin * blend;
        fx -= rolling_force;

        let bound_x = (limit_x * blend).max(1.0e-6);
        let bound_y = (limit_y * blend).max(1.0e-6);
        let bnx = fx / bound_x;
        let bny = fy / bound_y;
        let budget_norm = (bnx * bnx + bny * bny).sqrt();
        if budget_norm > 1.0 {
            fx /= budget_norm;
            fy /= budget_norm;
            rolling_force /= budget_norm;
        }
        let limit_x_inst = mu * longitudinal_ratio * fz_static * slide_scale;
        let limit_y_inst = mu * lateral_bonus * fz_static * slide_scale;
        let bound_x_inst = (limit_x_inst * blend).max(1.0e-6);
        let bound_y_inst = (limit_y_inst * blend).max(1.0e-6);
        let bix = fx / bound_x_inst;
        let biy = fy / bound_y_inst;
        let budget_inst = (bix * bix + biy * biy).sqrt();
        if budget_inst > 1.0 {
            fx /= budget_inst;
            fy /= budget_inst;
            rolling_force /= budget_inst;
        }

        let btx = trial_x / limit_x.max(1.0e-6);
        let bty = trial_y / limit_y.max(1.0e-6);
        let brush_theta = ((btx * btx + bty * bty).sqrt() / 3.0).clamp(0.0, 1.0);
        let lon_theta = (trial_x.abs() / (3.0 * limit_x).max(1.0e-6)).clamp(0.0, 1.0);
        let trail = cfg.pneumatic_trail
            * patch_ratio
            * (1.0 - brush_theta).powf(1.35)
            * (1.0 - 0.75 * lon_theta);
        let aligning_torque = -fy * trail;
        let slip_lon_speed = rim_speed - longitudinal_speed;
        let fx_contact = fx + rolling_force;
        let contact_power = fx_contact * slip_lon_speed - fy * lateral_speed;
        let rolling_power = rolling_force * longitudinal_speed;
        let energy_residue =
            contact_power - (patch_energy - previous_patch_energy) / patch_dt.max(1.0e-6);
        let friction_power = energy_residue.max(0.0) + (rolling_force * longitudinal_speed).abs();
        let slide_heat_w =
            ((trial_x - bx_u) * pv_x + (trial_y - by_u) * pv_y).max(0.0) * blend;

        let cu_x = fx / fx_capacity.max(1.0e-6);
        let cu_y = fy / fy_capacity.max(1.0e-6);
        let combined_util = (cu_x * cu_x + cu_y * cu_y).sqrt();
        let icu_x = fx / bound_x_inst;
        let icu_y = fy / bound_y_inst;
        let inst_combined_util = (icu_x * icu_x + icu_y * icu_y).sqrt();
        let brush_demand_n = (trial_x * trial_x + trial_y * trial_y).sqrt();
        st.contact_work_j += contact_power * patch_dt;
        st.heat_work_j += friction_power * patch_dt;

        let o = out.as_mut_slice();
        o[0] = fx;
        o[1] = rolling_force;
        o[2] = fy;
        o[3] = aligning_torque;
        o[4] = friction_power;
        o[5] = energy_residue;
        o[6] = radius;
        o[7] = enveloped_load;
        o[8] = target_ratio;
        o[9] = target_angle;
        o[10] = st.effective_slip_ratio;
        o[11] = st.effective_slip_angle;
        o[12] = combined_util;
        o[13] = inst_combined_util;
        o[14] = contact_power;
        o[15] = rolling_power;
        o[16] = slide_heat_w;
        o[17] = plastic_loss_j;
        o[18] = blend_loss_j;
        o[19] = st.liftoff_discard_j;
        o[20] = st.contact_work_j;
        o[21] = st.heat_work_j;
        o[22] = px;
        o[23] = py;
        o[24] = patch_energy;
        o[25] = brush_demand_n;
        o[26] = dynamic_contact_patch;
        o[27] = relaxation_length;
        o[28] = estimated_deflection;
        o[29] = cw_factor;
        o[30] = cs_factor;
        o[31] = cg_factor;
        o[32] = compound_mult;
        o[33] = fp_w.0;
        o[34] = fp_w.1;
        o[35] = fp_w.2;
        o[36] = st.post_peak_decay_lat;
        o[37] = st.post_peak_decay_lon;
        o[38] = st.contact_blend;
        o[39] = st.surface_friction;
        o[40] = st.surface_stiffness;
        o[41] = st.surface_rolling;
        o[42] = previous_patch_energy;
        out
    }
}
