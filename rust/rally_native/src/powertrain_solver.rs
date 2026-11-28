use std::f64::consts::{PI, TAU};

use godot::builtin::PackedFloat64Array;
use godot::classes::RefCounted;
use godot::prelude::*;

const DIFFERENTIAL_DRIVE_EPS: f64 = 0.000001;
const DEG_TO_RAD: f64 = PI / 180.0;
const RAD_TO_DEG: f64 = 180.0 / PI;

#[inline]
fn lerpf(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

#[inline]
fn signf(x: f64) -> f64 {
    if x > 0.0 {
        1.0
    } else if x < 0.0 {
        -1.0
    } else {
        0.0
    }
}

#[derive(Clone, Copy, Default)]
struct AxleDiffConfig {
    is_friction_type: bool,
    preload_nm: f64,
    power_ratio: f64,
    coast_ratio: f64,
    power_ramp_deg: f64,
    coast_ramp_deg: f64,
    clutches: f64,
    ramp_gain: f64,
    lock_stiff: f64,
    lock_zeta: f64,
    press_tau: f64,
    rel_tau: f64,
    blend_frac: f64,
    blend_nm: f64,
    static_fac: f64,
    slip_ref: f64,
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustPowertrainSolver {
    engine_inertia_kg_m2: f64,
    gearbox_input_inertia_kg_m2: f64,
    clutch_damper_disc_inertia_kg_m2: f64,
    output_shaft_inertia_kg_m2: f64,
    front_torque_split: f64,
    final_drive_ratio: f64,
    peak_torque_nm: f64,
    clutch_max_torque_nm: f64,
    clutch_max_torque_ratio: f64,
    clutch_bite_start: f64,
    clutch_bite_full: f64,
    clutch_bite_exponent: f64,
    clutch_mu_static_ratio: f64,
    clutch_static_slip_rad_s: f64,
    clutch_damper_idle_stiffness: f64,
    clutch_damper_idle_travel_deg: f64,
    clutch_damper_main_stiffness: f64,
    clutch_damper_travel_deg: f64,
    clutch_damper_stop_stiffness_factor: f64,
    clutch_damper_hysteresis_nm: f64,
    clutch_damper_viscous_nms_per_rad: f64,
    torsional_stiffness_nm_per_rad: f64,
    torsional_damping_nms_per_rad: f64,
    driveline_backlash_rad: f64,
    driveline_backlash_damping_ratio: f64,
    driveline_contact_soft_zone_rad: f64,
    driveline_contact_restitution: f64,
    driveline_end_stop_margin: f64,
    driveline_end_stop_stiffness_factor: f64,
    synchronizer_capacity_nm: f64,
    synchronizer_tolerance_rad_s: f64,
    shift_time_seconds: f64,
    gear_inertia_shift_seconds: f64,
    differential_slip_transition_threshold_rad_s: f64,
    chassis_reaction_scale: f64,
    chassis_reaction_crank_sign: f64,
    chassis_reaction_driveshaft_roll_fraction: f64,
    chassis_reaction_transaxle_pitch_fraction: f64,
    chassis_reaction_mount_tau_s: f64,
    chassis_reaction_mount_frequency_hz: f64,
    chassis_reaction_mount_damping_ratio: f64,
    chassis_reaction_roll_inertia_kg_m2: f64,
    chassis_reaction_pitch_inertia_kg_m2: f64,
    chassis_reaction_snubber_angle_deg: f64,
    chassis_reaction_snubber_stiffness_factor: f64,
    gear1_ratio_abs: f64,
    min_clutch_capacity_factor: f64,
    min_synchronizer_factor: f64,
    max_damage_backlash_rad: f64,
    max_chassis_reaction_nm: f64,

    driveline_compliance_enabled: bool,
    clutch_bite_enabled: bool,
    clutch_damper_enabled: bool,
    chassis_reaction_enabled: bool,
    mount_second_order: bool,
    mount_is_transverse: bool,
    freewheel_enabled: bool,

    axles: [AxleDiffConfig; 2],

    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustPowertrainSolver {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            engine_inertia_kg_m2: 0.15,
            gearbox_input_inertia_kg_m2: 0.02,
            clutch_damper_disc_inertia_kg_m2: 0.006,
            output_shaft_inertia_kg_m2: 0.02,
            front_torque_split: 0.0,
            final_drive_ratio: 4.0,
            peak_torque_nm: 200.0,
            clutch_max_torque_nm: 300.0,
            clutch_max_torque_ratio: 1.35,
            clutch_bite_start: 0.24,
            clutch_bite_full: 0.76,
            clutch_bite_exponent: 1.4,
            clutch_mu_static_ratio: 1.0,
            clutch_static_slip_rad_s: 3.0,
            clutch_damper_idle_stiffness: 220.0,
            clutch_damper_idle_travel_deg: 2.5,
            clutch_damper_main_stiffness: 1300.0,
            clutch_damper_travel_deg: 10.0,
            clutch_damper_stop_stiffness_factor: 15.0,
            clutch_damper_hysteresis_nm: 8.0,
            clutch_damper_viscous_nms_per_rad: 2.0,
            torsional_stiffness_nm_per_rad: 2200.0,
            torsional_damping_nms_per_rad: 35.0,
            driveline_backlash_rad: 0.0,
            driveline_backlash_damping_ratio: 0.1,
            driveline_contact_soft_zone_rad: 0.0,
            driveline_contact_restitution: 0.3,
            driveline_end_stop_margin: 1.8,
            driveline_end_stop_stiffness_factor: 8.0,
            synchronizer_capacity_nm: 60.0,
            synchronizer_tolerance_rad_s: 15.0,
            shift_time_seconds: 0.12,
            gear_inertia_shift_seconds: 0.0,
            differential_slip_transition_threshold_rad_s: 0.0,
            chassis_reaction_scale: 1.0,
            chassis_reaction_crank_sign: 1.0,
            chassis_reaction_driveshaft_roll_fraction: 0.0,
            chassis_reaction_transaxle_pitch_fraction: 0.0,
            chassis_reaction_mount_tau_s: 0.02,
            chassis_reaction_mount_frequency_hz: 12.0,
            chassis_reaction_mount_damping_ratio: 0.35,
            chassis_reaction_roll_inertia_kg_m2: 4.5,
            chassis_reaction_pitch_inertia_kg_m2: 6.0,
            chassis_reaction_snubber_angle_deg: 4.0,
            chassis_reaction_snubber_stiffness_factor: 6.0,
            gear1_ratio_abs: 3.5,
            min_clutch_capacity_factor: 0.70,
            min_synchronizer_factor: 0.35,
            max_damage_backlash_rad: 0.05,
            max_chassis_reaction_nm: 1200.0,

            driveline_compliance_enabled: false,
            clutch_bite_enabled: false,
            clutch_damper_enabled: false,
            chassis_reaction_enabled: false,
            mount_second_order: false,
            mount_is_transverse: false,
            freewheel_enabled: false,

            axles: [AxleDiffConfig::default(); 2],

            base,
        }
    }
}

impl RustPowertrainSolver {
    #[inline]
    fn evaluate_clutch_bite(&self, engagement: f64) -> f64 {
        let e = engagement.clamp(0.0, 1.0);
        if !self.clutch_bite_enabled {
            return e * e * (3.0 - 2.0 * e);
        }
        let u = ((e - self.clutch_bite_start)
            / (self.clutch_bite_full - self.clutch_bite_start).max(0.01))
        .clamp(0.0, 1.0);
        let s = u * u * (3.0 - 2.0 * u);
        s.powf(self.clutch_bite_exponent)
    }

    #[inline]
    fn evaluate_clutch_damper_spring(&self, theta_rad: f64) -> (f64, f64, f64) {
        let a = theta_rad.abs();
        let sgn = if theta_rad >= 0.0 { 1.0 } else { -1.0 };
        let th1 = self.clutch_damper_idle_travel_deg * DEG_TO_RAD;
        let th2 = self.clutch_damper_travel_deg * DEG_TO_RAD;
        let k1 = self.clutch_damper_idle_stiffness;
        let k2 = self.clutch_damper_main_stiffness;
        if a <= th1 {
            return (sgn * k1 * a, k1, 0.0);
        }
        if a <= th2 {
            return (sgn * (k1 * th1 + k2 * (a - th1)), k2, 0.0);
        }
        let k3 = k2 * self.clutch_damper_stop_stiffness_factor;
        let t_stop = k1 * th1 + k2 * (th2 - th1);
        let ex = a - th2;
        let stop_band = (0.15 * (th2 - th1).max(0.02)).max(0.005);
        let k_extra = k3 - k2;
        if ex < stop_band {
            (
                sgn * (t_stop + k2 * ex + k_extra * ex * ex / (2.0 * stop_band)),
                k2 + k_extra * (ex / stop_band),
                1.0,
            )
        } else {
            (
                sgn * (t_stop + k2 * ex + k_extra * (ex - 0.5 * stop_band)),
                k3,
                1.0,
            )
        }
    }

    #[inline]
    fn driveline_end_stop_delta(&self) -> f64 {
        let t_axle_max = (self.peak_torque_nm
            * self.clutch_max_torque_ratio.max(1.0)
            * self.gear1_ratio_abs
            * self.final_drive_ratio)
            .max(self.peak_torque_nm.max(100.0));
        (self.driveline_end_stop_margin * t_axle_max / self.torsional_stiffness_nm_per_rad.max(1.0))
            .max(0.15)
    }

    #[inline]
    fn evaluate_driveline_flank(&self, delta_pen: f64, end_stop_delta: f64) -> (f64, f64) {
        let d = delta_pen.max(0.0);
        let k = self.torsional_stiffness_nm_per_rad;
        let ds = self.driveline_contact_soft_zone_rad;
        if d < ds {
            return (k * d * d / (2.0 * ds), k * d / ds);
        }
        if d < end_stop_delta {
            return (k * (d - 0.5 * ds), k);
        }
        let ex = d - end_stop_delta;
        let end_band = (0.15 * end_stop_delta).max(0.02);
        let k_extra = k * (self.driveline_end_stop_stiffness_factor - 1.0);
        if ex < end_band {
            (
                k * (d - 0.5 * ds) + k_extra * ex * ex / (2.0 * end_band),
                k + k_extra * (ex / end_band),
            )
        } else {
            (
                k * (d - 0.5 * ds) + k_extra * (ex - 0.5 * end_band),
                k + k_extra,
            )
        }
    }

    #[inline]
    fn evaluate_driveline_energy(&self, delta_pen: f64, end_stop_delta: f64) -> f64 {
        let d = delta_pen.max(0.0);
        let k = self.torsional_stiffness_nm_per_rad;
        let ds = self.driveline_contact_soft_zone_rad;
        if d <= 0.0 {
            return 0.0;
        }
        if d < ds {
            return k * d * d * d / (6.0 * ds);
        }
        let e_soft = k * ds * ds / 6.0;
        let d_lin = d.min(end_stop_delta) - ds;
        let e_lin = 0.5 * k * (d_lin * d_lin + ds * d_lin);
        if d <= end_stop_delta {
            return e_soft + e_lin;
        }
        let ex = d - end_stop_delta;
        let end_band = (0.15 * end_stop_delta).max(0.02);
        let k_extra = k * (self.driveline_end_stop_stiffness_factor - 1.0);
        let e_base = e_soft + 0.5 * k * ((d - ds) * (d - ds) + ds * (d - ds));
        if ex < end_band {
            return e_base + k_extra * ex * ex * ex / (6.0 * end_band);
        }
        let e_band = k_extra * end_band * end_band / 6.0;
        let ex2 = ex - end_band;
        e_base + e_band + 0.5 * k_extra * (ex2 * ex2 + end_band * ex2)
    }

    #[inline]
    fn evaluate_mount_spring(
        angle_rad: f64,
        k_base: f64,
        snubber_rad: f64,
        snubber_factor: f64,
    ) -> (f64, f64) {
        let a = angle_rad.abs();
        let sgn = if angle_rad >= 0.0 { 1.0 } else { -1.0 };
        if a <= snubber_rad || snubber_factor <= 1.0 {
            return (k_base * angle_rad, k_base);
        }
        let ex = a - snubber_rad;
        let band = (0.25 * snubber_rad).max(0.01);
        let k_extra = k_base * (snubber_factor - 1.0);
        if ex < band {
            (
                sgn * (k_base * a + k_extra * ex * ex / (2.0 * band)),
                k_base + k_extra * (ex / band),
            )
        } else {
            (
                sgn * (k_base * a + k_extra * (ex - 0.5 * band)),
                k_base + k_extra,
            )
        }
    }
}

#[godot_api]
impl RustPowertrainSolver {
    #[func]
    fn sync_config(
        &mut self,
        cfg50: PackedFloat64Array,
        axle32: PackedFloat64Array,
        flags: i32,
    ) {
        let c = cfg50.as_slice();
        if c.len() >= 50 {
            self.engine_inertia_kg_m2 = c[0];
            self.gearbox_input_inertia_kg_m2 = c[1];
            self.clutch_damper_disc_inertia_kg_m2 = c[2];
            self.output_shaft_inertia_kg_m2 = c[3];
            self.front_torque_split = c[4];
            self.final_drive_ratio = c[5];
            self.peak_torque_nm = c[6];
            self.clutch_max_torque_nm = c[7];
            self.clutch_max_torque_ratio = c[8];
            self.clutch_bite_start = c[9];
            self.clutch_bite_full = c[10];
            self.clutch_bite_exponent = c[11];
            self.clutch_mu_static_ratio = c[12];
            self.clutch_static_slip_rad_s = c[13];
            self.clutch_damper_idle_stiffness = c[14];
            self.clutch_damper_idle_travel_deg = c[15];
            self.clutch_damper_main_stiffness = c[16];
            self.clutch_damper_travel_deg = c[17];
            self.clutch_damper_stop_stiffness_factor = c[18];
            self.clutch_damper_hysteresis_nm = c[19];
            self.clutch_damper_viscous_nms_per_rad = c[20];
            self.torsional_stiffness_nm_per_rad = c[21];
            self.torsional_damping_nms_per_rad = c[22];
            self.driveline_backlash_rad = c[23];
            self.driveline_backlash_damping_ratio = c[24];
            self.driveline_contact_soft_zone_rad = c[25];
            self.driveline_contact_restitution = c[26];
            self.driveline_end_stop_margin = c[27];
            self.driveline_end_stop_stiffness_factor = c[28];
            self.synchronizer_capacity_nm = c[29];
            self.synchronizer_tolerance_rad_s = c[30];
            self.shift_time_seconds = c[31];
            self.gear_inertia_shift_seconds = c[32];
            self.differential_slip_transition_threshold_rad_s = c[33];
            self.chassis_reaction_scale = c[34];
            self.chassis_reaction_crank_sign = c[35];
            self.chassis_reaction_driveshaft_roll_fraction = c[36];
            self.chassis_reaction_transaxle_pitch_fraction = c[37];
            self.chassis_reaction_mount_tau_s = c[38];
            self.chassis_reaction_mount_frequency_hz = c[39];
            self.chassis_reaction_mount_damping_ratio = c[40];
            self.chassis_reaction_roll_inertia_kg_m2 = c[41];
            self.chassis_reaction_pitch_inertia_kg_m2 = c[42];
            self.chassis_reaction_snubber_angle_deg = c[43];
            self.chassis_reaction_snubber_stiffness_factor = c[44];
            self.gear1_ratio_abs = c[45];
            self.min_clutch_capacity_factor = c[46];
            self.min_synchronizer_factor = c[47];
            self.max_damage_backlash_rad = c[48];
            self.max_chassis_reaction_nm = c[49];
        }
        let a = axle32.as_slice();
        if a.len() >= 32 {
            for idx in 0..2 {
                let b = idx * 16;
                self.axles[idx] = AxleDiffConfig {
                    is_friction_type: a[b] > 0.5,
                    preload_nm: a[b + 1],
                    power_ratio: a[b + 2],
                    coast_ratio: a[b + 3],
                    power_ramp_deg: a[b + 4],
                    coast_ramp_deg: a[b + 5],
                    clutches: a[b + 6],
                    ramp_gain: a[b + 7],
                    lock_stiff: a[b + 8],
                    lock_zeta: a[b + 9],
                    press_tau: a[b + 10],
                    rel_tau: a[b + 11],
                    blend_frac: a[b + 12],
                    blend_nm: a[b + 13],
                    static_fac: a[b + 14],
                    slip_ref: a[b + 15],
                };
            }
        }
        self.driveline_compliance_enabled = (flags & (1 << 0)) != 0;
        self.clutch_bite_enabled = (flags & (1 << 1)) != 0;
        self.clutch_damper_enabled = (flags & (1 << 2)) != 0;
        self.chassis_reaction_enabled = (flags & (1 << 3)) != 0;
        self.mount_second_order = (flags & (1 << 4)) != 0;
        self.mount_is_transverse = (flags & (1 << 5)) != 0;
        self.freewheel_enabled = (flags & (1 << 6)) != 0;
    }

    #[func]
    fn solve_rotation(&self, inp53: PackedFloat64Array, step_flags: i32) -> PackedFloat64Array {
        let s = inp53.as_slice();
        let mut out = PackedFloat64Array::new();
        out.resize(54);
        if s.len() < 53 {
            return out;
        }

        let h = s[0].max(0.000001);
        let mut spins = [s[1], s[2], s[3], s[4]];
        let inertias = [s[5], s[6], s[7], s[8]];
        let tire_torques = [s[9], s[10], s[11], s[12]];
        let brakes = [s[13], s[14], s[15], s[16]];
        let spin_damping = [s[17], s[18], s[19], s[20]];
        let ch_om = [s[21], s[22], s[23]];
        let mut engine_omega = s[24] * TAU / 60.0;
        let mut input_shaft_omega = s[25];
        let mut output_shaft_omega = s[26];
        let clutch_engagement = s[27];
        let ratio = s[28];
        let current_gear_ratio = s[29];
        let shift_phase_seconds = s[30];
        let transmission_damage = s[31];
        let mut clutch_damper_twist_rad = s[32];
        let mut driveline_twist_rad = s[33];
        let prev_flank = s[34].round() as i32;
        let mut mount_roll_rad = s[35];
        let mut mount_roll_omega = s[36];
        let mut mount_pitch_rad = s[37];
        let mut mount_pitch_omega = s[38];
        let mut axle_lock_twists = [s[39], s[40]];
        let mut axle_filt_torques = [s[41], s[42]];
        let mut axle_blends = [s[43], s[44]];
        let reaction_prev_engine_omega = s[45];
        let reaction_prev_input_omega = s[46];
        let mut chassis_reaction_torque = [s[47], s[48], s[49]];
        let prev_ch_om = [s[50], s[51], s[52]];

        let connected = (step_flags & (1 << 0)) != 0;
        let synchronizing = (step_flags & (1 << 1)) != 0;
        let current_gear_nonzero = (step_flags & (1 << 2)) != 0;
        let pending_gear_nonzero = (step_flags & (1 << 3)) != 0;
        let shift_phase_is_sync = (step_flags & (1 << 4)) != 0;
        let reaction_initialized = (step_flags & (1 << 5)) != 0;
        let mount_ch_initialized = (step_flags & (1 << 6)) != 0;

        let ie = self.engine_inertia_kg_m2.max(0.000001);
        let use_clutch_damper = self.clutch_damper_enabled && connected && !synchronizing;
        let shaft_inertia = if self.clutch_damper_enabled {
            self.clutch_damper_disc_inertia_kg_m2
        } else {
            self.gearbox_input_inertia_kg_m2
        };
        let weights = [
            self.front_torque_split * 0.5,
            self.front_torque_split * 0.5,
            (1.0 - self.front_torque_split) * 0.5,
            (1.0 - self.front_torque_split) * 0.5,
        ];
        let mut inverse = [0.0; 4];
        let mut brake_impulses = [0.0; 4];
        let mut brake_work = [0.0; 4];
        let mut carrier_inverse = 0.0;
        let primary_reflected = if use_clutch_damper && self.driveline_compliance_enabled {
            self.gearbox_input_inertia_kg_m2 * ratio * ratio
        } else {
            0.0
        };
        let output_inverse = 1.0 / (self.output_shaft_inertia_kg_m2 + primary_reflected).max(0.000001);
        for i in 0..4 {
            let inv_wheel = 1.0 / inertias[i].max(0.000001);
            inverse[i] = inv_wheel;
            let c_spin = spin_damping[i].max(0.0);
            let tire_damping_scale = 1.0 / (1.0 + h * c_spin * inv_wheel);
            spins[i] -= h * tire_torques[i] * inv_wheel * tire_damping_scale;
            carrier_inverse += weights[i] * weights[i] * inv_wheel;
        }

        let mount_second_order = self.chassis_reaction_enabled && self.mount_second_order;
        let mount_is_transverse = self.mount_is_transverse;
        let mount_roll_active = mount_second_order && !mount_is_transverse;
        let mount_pitch_active = mount_second_order
            && (mount_is_transverse || self.chassis_reaction_transaxle_pitch_fraction > 0.0);
        let mount_roll_inv = 1.0 / self.chassis_reaction_roll_inertia_kg_m2.max(0.01);
        let mount_pitch_inv = 1.0 / self.chassis_reaction_pitch_inertia_kg_m2.max(0.01);
        let mount_crank_inv = if mount_second_order {
            if mount_is_transverse {
                mount_pitch_inv
            } else {
                mount_roll_inv
            }
        } else {
            0.0
        };
        let mount_omega_nat = TAU * self.chassis_reaction_mount_frequency_hz;
        let mount_k_roll = self.chassis_reaction_roll_inertia_kg_m2 * mount_omega_nat * mount_omega_nat;
        let mount_c_roll = 2.0
            * self.chassis_reaction_mount_damping_ratio
            * (mount_k_roll * self.chassis_reaction_roll_inertia_kg_m2).sqrt();
        let mount_k_pitch =
            self.chassis_reaction_pitch_inertia_kg_m2 * mount_omega_nat * mount_omega_nat;
        let mount_c_pitch = 2.0
            * self.chassis_reaction_mount_damping_ratio
            * (mount_k_pitch * self.chassis_reaction_pitch_inertia_kg_m2).sqrt();
        let mount_snubber_rad = self.chassis_reaction_snubber_angle_deg * DEG_TO_RAD;
        let ds_kappa_z = if mount_roll_active && self.chassis_reaction_driveshaft_roll_fraction > 0.0 {
            self.chassis_reaction_driveshaft_roll_fraction / self.final_drive_ratio.max(0.0001)
        } else {
            0.0
        };
        let tx_kappa_x = if mount_pitch_active {
            self.chassis_reaction_transaxle_pitch_fraction
        } else {
            0.0
        };

        if mount_second_order {
            if mount_ch_initialized {
                let ch_alpha_x = (ch_om[0] - prev_ch_om[0]) / h;
                let ch_alpha_z = (ch_om[2] - prev_ch_om[2]) / h;
                if mount_roll_active {
                    mount_roll_omega -= ch_alpha_z.clamp(-50.0, 50.0) * h;
                }
                if mount_pitch_active {
                    mount_pitch_omega -= ch_alpha_x.clamp(-50.0, 50.0) * h;
                }
            }
            if reaction_initialized {
                let max_adv_imp = self.peak_torque_nm.max(100.0) * 2.5 * h;
                let j_adv =
                    (ie * (engine_omega - reaction_prev_engine_omega)).clamp(-max_adv_imp, max_adv_imp);
                if mount_is_transverse {
                    mount_pitch_omega -= self.chassis_reaction_crank_sign * j_adv * mount_pitch_inv;
                } else {
                    mount_roll_omega -= self.chassis_reaction_crank_sign * j_adv * mount_roll_inv;
                }
            }
        }

        let gear_effective_inverse = 1.0 / shaft_inertia
            + ratio
                * ratio
                * if self.driveline_compliance_enabled {
                    output_inverse
                } else {
                    carrier_inverse
                }
            + mount_crank_inv;
        let spring_inverse = output_inverse
            + carrier_inverse
            + ds_kappa_z * ds_kappa_z * mount_roll_inv
            + tx_kappa_x * tx_kappa_x * mount_pitch_inv;
        let implicit_damping =
            self.torsional_damping_nms_per_rad + h * self.torsional_stiffness_nm_per_rad;
        let spring_denominator = 1.0 + h * implicit_damping * spring_inverse;
        let progressive_contact_enabled = self.driveline_contact_soft_zone_rad > 0.0;
        let mut contact_zeta = 0.0;
        let mut end_stop_delta = 0.35;
        if progressive_contact_enabled {
            let ln_e = self.driveline_contact_restitution.clamp(0.05, 0.99).ln();
            contact_zeta = -ln_e / (PI * PI + ln_e * ln_e).sqrt();
            end_stop_delta = self.driveline_end_stop_delta();
        }
        let spring_j_eff = 1.0 / spring_inverse.max(0.000001);
        let clutch_damage_fac = lerpf(1.0, self.min_clutch_capacity_factor, transmission_damage);
        let sync_damage_fac = lerpf(1.0, self.min_synchronizer_factor, transmission_damage);
        let damage_backlash = transmission_damage * self.max_damage_backlash_rad;
        let effective_backlash_rad = self.driveline_backlash_rad
            + if self.driveline_compliance_enabled {
                damage_backlash
            } else {
                0.0
            };
        let backlash_half_rad = 0.5 * effective_backlash_rad;
        let lash_damping =
            self.torsional_damping_nms_per_rad * self.driveline_backlash_damping_ratio;
        let lash_denominator = 1.0 + h * lash_damping * spring_inverse;
        let initial_carrier =
            weights[0] * spins[0] + weights[1] * spins[1] + weights[2] * spins[2] + weights[3] * spins[3];
        let initial_mount_offset = (self.chassis_reaction_crank_sign * ds_kappa_z * mount_roll_omega)
            - (tx_kappa_x * mount_pitch_omega);
        let initial_twist_speed = output_shaft_omega - initial_carrier + initial_mount_offset;

        let mut spring_impulse = 0.0;
        let mut clutch_impulse = 0.0;
        let mut gear_impulse = 0.0;
        let mut damper_spring_impulse = 0.0;
        let mut damper_hyst_impulse = 0.0;
        let mut mount_roll_impulse = 0.0;
        let mut mount_pitch_impulse = 0.0;
        let mut clutch_work = 0.0;

        let smooth_clutch = self.evaluate_clutch_bite(clutch_engagement);
        let clutch_base_capacity = self.clutch_max_torque_nm * clutch_damage_fac * smooth_clutch * h;
        let use_clutch_mu_curve = (self.clutch_mu_static_ratio - 1.0).abs() > 0.000001;
        let nominal_sync_time = (self.shift_time_seconds + self.gear_inertia_shift_seconds).max(0.02);
        let sync_overtime = if synchronizing {
            (shift_phase_seconds / nominal_sync_time).clamp(1.0, 4.0)
        } else {
            1.0
        };
        let effective_sync_cap = self.synchronizer_capacity_nm * sync_damage_fac * sync_overtime * h;
        let cd_hyst_cap = self.clutch_damper_hysteresis_nm * h;
        let cd_t0 = if use_clutch_damper {
            self.evaluate_clutch_damper_spring(clutch_damper_twist_rad)
        } else {
            (0.0, 0.0, 0.0)
        };

        let axle_shares = [self.front_torque_split, 1.0 - self.front_torque_split];
        let axle_pair_invs_pure = [inverse[0] + inverse[1], inverse[2] + inverse[3]];
        let axle_pair_invs = [
            axle_pair_invs_pure[0] + h * self.differential_slip_transition_threshold_rad_s * 0.35,
            axle_pair_invs_pure[1] + h * self.differential_slip_transition_threshold_rad_s * 0.35,
        ];
        let mut axle_lock_c_eff = [0.0; 2];
        let mut axle_lock_denom = [1.0; 2];
        let mut axle_use_filtered = [false; 2];
        let mut axle_precomp_base_cap_nm = [0.0; 2];
        let mut ref_ratio_abs = ratio.abs();
        if ref_ratio_abs <= 0.0001 {
            ref_ratio_abs = self.gear1_ratio_abs * self.final_drive_ratio;
        }
        for axle in 0..2 {
            let ac = &self.axles[axle];
            if ac.lock_stiff > 0.0 {
                let k_l = ac.lock_stiff;
                let inv_p = axle_pair_invs_pure[axle];
                let c_l = 2.0 * ac.lock_zeta * (k_l / inv_p.max(0.000001)).sqrt();
                let c_l_eff = c_l + h * k_l;
                axle_lock_c_eff[axle] = c_l_eff;
                axle_lock_denom[axle] = 1.0 + h * c_l_eff * inv_p;
            }
            let use_filt = ac.press_tau > 0.0 || ac.rel_tau > 0.0;
            axle_use_filtered[axle] = use_filt;
            if use_filt && axle_shares[axle] > DIFFERENTIAL_DRIVE_EPS && ac.is_friction_type {
                let left_p = axle * 2;
                let ax_in = axle_filt_torques[axle];
                let ax_car = 0.5 * (spins[left_p] + spins[left_p + 1]);
                let blend_p = if ac.blend_frac > 0.0 || ac.blend_nm > 0.0 {
                    let dir_s = if ax_car.abs() > 0.5 {
                        if ax_car >= 0.0 { 1.0 } else { -1.0 }
                    } else {
                        signf(ax_in)
                    };
                    let signed_t = ax_in * dir_s;
                    let band = ac
                        .blend_nm
                        .max(ac.blend_frac * self.peak_torque_nm * ref_ratio_abs * axle_shares[axle])
                        .max(1.0);
                    let xb = (signed_t / band).clamp(-1.0, 1.0);
                    0.5 + 0.5 * xb * (1.5 - 0.5 * xb * xb)
                } else {
                    let dp = ax_in * if ax_car.abs() > 0.5 { ax_car } else { signf(ax_in) };
                    (0.5 + 0.5 * (dp / 150.0).tanh()).clamp(0.0, 1.0)
                };
                axle_blends[axle] = blend_p;
                let r_deg = lerpf(ac.coast_ramp_deg, ac.power_ramp_deg, blend_p);
                let mu_p = lerpf(ac.coast_ratio, ac.power_ratio, blend_p);
                let cot_r = if r_deg >= 90.0 {
                    0.0
                } else {
                    1.0 / (r_deg.max(15.0) * DEG_TO_RAD).tan()
                };
                let r_cap = ax_in.abs()
                    * cot_r
                    * ac.clutches.max(1.0)
                    * mu_p.max(0.0)
                    * ac.ramp_gain.max(0.0);
                axle_precomp_base_cap_nm[axle] = ac.preload_nm.max(0.0) + r_cap.max(0.0);
            }
        }

        let mut lsd_impulses = [0.0; 2];
        let mut axle_speeds = [0.0; 2];
        let mut axle_capacities = [0.0; 2];
        let mut axle_torques = [0.0; 2];
        let mut axle_saturations = [0.0; 2];
        let inv_ie_plus_shaft = 1.0 / ie + 1.0 / shaft_inertia;

        for _ in 0..48 {
            if connected {
                let carrier = weights[0] * spins[0]
                    + weights[1] * spins[1]
                    + weights[2] * spins[2]
                    + weights[3] * spins[3];
                let gear_output = if self.driveline_compliance_enabled {
                    output_shaft_omega
                } else {
                    carrier
                };
                let housing_crank_omega = if mount_second_order {
                    if mount_is_transverse {
                        self.chassis_reaction_crank_sign * mount_pitch_omega
                    } else {
                        self.chassis_reaction_crank_sign * mount_roll_omega
                    }
                } else {
                    0.0
                };
                if use_clutch_damper {
                    let v_cd = input_shaft_omega - housing_crank_omega - ratio * gear_output;
                    let theta_cd_pred = clutch_damper_twist_rad + h * v_cd;
                    let cd_pred = self.evaluate_clutch_damper_spring(theta_cd_pred);
                    let mut k_cd_eff = cd_t0.1;
                    if v_cd.abs() > 0.00001 {
                        let k_cd_sec = (cd_pred.0 - cd_t0.0) / (h * v_cd);
                        k_cd_eff = k_cd_eff.max(k_cd_sec);
                    }
                    let c_cd_eff = self.clutch_damper_viscous_nms_per_rad + h * k_cd_eff;
                    let cd_denom = 1.0 + h * c_cd_eff * gear_effective_inverse;
                    let d_cd =
                        -(damper_spring_impulse + h * cd_t0.0 + h * c_cd_eff * v_cd) / cd_denom;
                    damper_spring_impulse += d_cd;
                    input_shaft_omega += d_cd / shaft_inertia;
                    if self.driveline_compliance_enabled {
                        output_shaft_omega -= ratio * d_cd * output_inverse;
                    } else {
                        for i in 0..4 {
                            spins[i] -= ratio * weights[i] * d_cd * inverse[i];
                        }
                    }
                    if mount_second_order {
                        if mount_is_transverse {
                            mount_pitch_omega -=
                                self.chassis_reaction_crank_sign * d_cd * mount_pitch_inv;
                        } else {
                            mount_roll_omega -=
                                self.chassis_reaction_crank_sign * d_cd * mount_roll_inv;
                        }
                    }
                    if cd_hyst_cap > 0.0 {
                        let gear_out_h = if self.driveline_compliance_enabled {
                            output_shaft_omega
                        } else {
                            weights[0] * spins[0]
                                + weights[1] * spins[1]
                                + weights[2] * spins[2]
                                + weights[3] * spins[3]
                        };
                        let housing_h = if mount_second_order {
                            if mount_is_transverse {
                                self.chassis_reaction_crank_sign * mount_pitch_omega
                            } else {
                                self.chassis_reaction_crank_sign * mount_roll_omega
                            }
                        } else {
                            0.0
                        };
                        let v_cd_h = input_shaft_omega - housing_h - ratio * gear_out_h;
                        let next_hyst = (damper_hyst_impulse - v_cd_h / gear_effective_inverse)
                            .clamp(-cd_hyst_cap, cd_hyst_cap);
                        let d_hyst = next_hyst - damper_hyst_impulse;
                        damper_hyst_impulse = next_hyst;
                        input_shaft_omega += d_hyst / shaft_inertia;
                        if self.driveline_compliance_enabled {
                            output_shaft_omega -= ratio * d_hyst * output_inverse;
                        } else {
                            for i in 0..4 {
                                spins[i] -= ratio * weights[i] * d_hyst * inverse[i];
                            }
                        }
                        if mount_second_order {
                            if mount_is_transverse {
                                mount_pitch_omega -=
                                    self.chassis_reaction_crank_sign * d_hyst * mount_pitch_inv;
                            } else {
                                mount_roll_omega -=
                                    self.chassis_reaction_crank_sign * d_hyst * mount_roll_inv;
                            }
                        }
                    }
                    gear_impulse = damper_spring_impulse + damper_hyst_impulse;
                } else {
                    let mut impulse = -(input_shaft_omega - housing_crank_omega - ratio * gear_output)
                        / gear_effective_inverse;
                    if synchronizing {
                        let next_gear_impulse = (gear_impulse + impulse)
                            .clamp(-effective_sync_cap, effective_sync_cap);
                        impulse = next_gear_impulse - gear_impulse;
                    }
                    input_shaft_omega += impulse / shaft_inertia;
                    gear_impulse += impulse;
                    if self.driveline_compliance_enabled {
                        output_shaft_omega -= ratio * impulse * output_inverse;
                    } else {
                        for i in 0..4 {
                            spins[i] -= ratio * weights[i] * impulse * inverse[i];
                        }
                    }
                    if mount_second_order {
                        if mount_is_transverse {
                            mount_pitch_omega -=
                                self.chassis_reaction_crank_sign * impulse * mount_pitch_inv;
                        } else {
                            mount_roll_omega -=
                                self.chassis_reaction_crank_sign * impulse * mount_roll_inv;
                        }
                    }
                }
            }

            if self.driveline_compliance_enabled {
                let carrier_speed = weights[0] * spins[0]
                    + weights[1] * spins[1]
                    + weights[2] * spins[2]
                    + weights[3] * spins[3];
                let mount_offset = (self.chassis_reaction_crank_sign * ds_kappa_z * mount_roll_omega)
                    - (tx_kappa_x * mount_pitch_omega);
                let relative_speed = output_shaft_omega - carrier_speed + mount_offset;
                let spring_delta;
                if progressive_contact_enabled {
                    let theta_pred = driveline_twist_rad + h * relative_speed;
                    if theta_pred > backlash_half_rad {
                        let delta_pred = theta_pred - backlash_half_rad;
                        let f_pred = self.evaluate_driveline_flank(delta_pred, end_stop_delta);
                        let pen_frac =
                            (delta_pred / self.driveline_contact_soft_zone_rad).clamp(0.0, 1.0);
                        let mut c_active =
                            lerpf(lash_damping, self.torsional_damping_nms_per_rad, pen_frac);
                        if relative_speed > 0.0 && pen_frac < 1.0 {
                            let bell = 4.0 * pen_frac * (1.0 - pen_frac);
                            c_active += 2.0 * contact_zeta * (f_pred.1.max(1.0) * spring_j_eff).sqrt() * bell;
                        }
                        let raw_delta = if driveline_twist_rad > backlash_half_rad {
                            let delta0 = driveline_twist_rad - backlash_half_rad;
                            let f0 = self.evaluate_driveline_flank(delta0, end_stop_delta);
                            let d_del = delta_pred - delta0;
                            let k_sec = if d_del.abs() > 0.000001 {
                                (f_pred.0 - f0.0) / d_del
                            } else {
                                f0.1
                            };
                            let c_imp = c_active + h * k_sec;
                            let denom = 1.0 + h * c_imp * spring_inverse;
                            -(spring_impulse + h * f0.0 + h * c_imp * relative_speed) / denom
                        } else {
                            let contact_frac =
                                (delta_pred / (h * relative_speed).max(0.000001)).clamp(0.0, 1.0);
                            let k_sec = f_pred.0 / delta_pred.max(0.000001);
                            let c_imp = c_active * contact_frac + h * k_sec;
                            let denom = 1.0 + h * c_imp * spring_inverse;
                            -(spring_impulse
                                + h * k_sec * (driveline_twist_rad - backlash_half_rad)
                                + h * c_imp * relative_speed)
                                / denom
                        };
                        if backlash_half_rad > 0.0 {
                            spring_delta = (spring_impulse + raw_delta).min(0.0) - spring_impulse;
                        } else {
                            spring_delta = raw_delta;
                        }
                    } else if theta_pred < -backlash_half_rad {
                        let delta_pred = -theta_pred - backlash_half_rad;
                        let f_pred = self.evaluate_driveline_flank(delta_pred, end_stop_delta);
                        let pen_frac =
                            (delta_pred / self.driveline_contact_soft_zone_rad).clamp(0.0, 1.0);
                        let mut c_active =
                            lerpf(lash_damping, self.torsional_damping_nms_per_rad, pen_frac);
                        if relative_speed < 0.0 && pen_frac < 1.0 {
                            let bell = 4.0 * pen_frac * (1.0 - pen_frac);
                            c_active += 2.0 * contact_zeta * (f_pred.1.max(1.0) * spring_j_eff).sqrt() * bell;
                        }
                        let raw_delta = if driveline_twist_rad < -backlash_half_rad {
                            let delta0 = -driveline_twist_rad - backlash_half_rad;
                            let f0 = self.evaluate_driveline_flank(delta0, end_stop_delta);
                            let d_del = delta_pred - delta0;
                            let k_sec = if d_del.abs() > 0.000001 {
                                (f_pred.0 - f0.0) / d_del
                            } else {
                                f0.1
                            };
                            let c_imp = c_active + h * k_sec;
                            let denom = 1.0 + h * c_imp * spring_inverse;
                            -(spring_impulse - h * f0.0 + h * c_imp * relative_speed) / denom
                        } else {
                            let contact_frac =
                                (delta_pred / (-h * relative_speed).max(0.000001)).clamp(0.0, 1.0);
                            let k_sec = f_pred.0 / delta_pred.max(0.000001);
                            let c_imp = c_active * contact_frac + h * k_sec;
                            let denom = 1.0 + h * c_imp * spring_inverse;
                            -(spring_impulse
                                + h * k_sec * (driveline_twist_rad + backlash_half_rad)
                                + h * c_imp * relative_speed)
                                / denom
                        };
                        if backlash_half_rad > 0.0 {
                            spring_delta = (spring_impulse + raw_delta).max(0.0) - spring_impulse;
                        } else {
                            spring_delta = raw_delta;
                        }
                    } else {
                        spring_delta =
                            -(spring_impulse + h * lash_damping * relative_speed) / lash_denominator;
                    }
                } else if backlash_half_rad > 0.0 {
                    let theta_pred = driveline_twist_rad + h * relative_speed;
                    if theta_pred > backlash_half_rad {
                        let raw_delta = -(spring_impulse
                            + h * self.torsional_stiffness_nm_per_rad
                                * (driveline_twist_rad - backlash_half_rad)
                            + h * implicit_damping * relative_speed)
                            / spring_denominator;
                        spring_delta = (spring_impulse + raw_delta).min(0.0) - spring_impulse;
                    } else if theta_pred < -backlash_half_rad {
                        let raw_delta = -(spring_impulse
                            + h * self.torsional_stiffness_nm_per_rad
                                * (driveline_twist_rad + backlash_half_rad)
                            + h * implicit_damping * relative_speed)
                            / spring_denominator;
                        spring_delta = (spring_impulse + raw_delta).max(0.0) - spring_impulse;
                    } else {
                        spring_delta =
                            -(spring_impulse + h * lash_damping * relative_speed) / lash_denominator;
                    }
                } else {
                    spring_delta = -(spring_impulse
                        + h * self.torsional_stiffness_nm_per_rad * driveline_twist_rad
                        + h * implicit_damping * relative_speed)
                        / spring_denominator;
                }
                spring_impulse += spring_delta;
                output_shaft_omega += spring_delta * output_inverse;
                for i in 0..4 {
                    spins[i] -= weights[i] * spring_delta * inverse[i];
                }
                if ds_kappa_z > 0.0 {
                    mount_roll_omega +=
                        self.chassis_reaction_crank_sign * ds_kappa_z * spring_delta * mount_roll_inv;
                }
                if tx_kappa_x > 0.0 {
                    mount_pitch_omega -= tx_kappa_x * spring_delta * mount_pitch_inv;
                }
            }

            let slip = engine_omega - input_shaft_omega;
            let clutch_capacity = if use_clutch_mu_curve {
                let mu_fac = (1.0
                    + (self.clutch_mu_static_ratio - 1.0)
                        * (-slip.abs() / self.clutch_static_slip_rad_s).exp())
                    / self.clutch_mu_static_ratio;
                clutch_base_capacity * mu_fac
            } else {
                clutch_base_capacity
            };
            let next_clutch =
                (clutch_impulse + slip / inv_ie_plus_shaft).clamp(-clutch_capacity, clutch_capacity);
            let clutch_delta = next_clutch - clutch_impulse;
            engine_omega -= clutch_delta / ie;
            input_shaft_omega += clutch_delta / shaft_inertia;
            clutch_work += clutch_delta * (slip + engine_omega - input_shaft_omega) * 0.5;
            clutch_impulse = next_clutch;

            if mount_roll_active {
                let roll_pred = mount_roll_rad + h * mount_roll_omega;
                let mr0 = Self::evaluate_mount_spring(
                    mount_roll_rad,
                    mount_k_roll,
                    mount_snubber_rad,
                    self.chassis_reaction_snubber_stiffness_factor,
                );
                let mr_pred = Self::evaluate_mount_spring(
                    roll_pred,
                    mount_k_roll,
                    mount_snubber_rad,
                    self.chassis_reaction_snubber_stiffness_factor,
                );
                let mut k_mr = mr0.1;
                if mount_roll_omega.abs() > 0.00001 {
                    k_mr = k_mr.max((mr_pred.0 - mr0.0) / (h * mount_roll_omega));
                }
                let c_mr_eff = mount_c_roll + h * k_mr;
                let mr_denom = 1.0 + h * c_mr_eff * mount_roll_inv;
                let d_mr =
                    -(mount_roll_impulse + h * mr0.0 + h * c_mr_eff * mount_roll_omega) / mr_denom;
                mount_roll_impulse += d_mr;
                mount_roll_omega += d_mr * mount_roll_inv;
            }
            if mount_pitch_active {
                let pitch_pred = mount_pitch_rad + h * mount_pitch_omega;
                let mp0 = Self::evaluate_mount_spring(
                    mount_pitch_rad,
                    mount_k_pitch,
                    mount_snubber_rad,
                    self.chassis_reaction_snubber_stiffness_factor,
                );
                let mp_pred = Self::evaluate_mount_spring(
                    pitch_pred,
                    mount_k_pitch,
                    mount_snubber_rad,
                    self.chassis_reaction_snubber_stiffness_factor,
                );
                let mut k_mp = mp0.1;
                if mount_pitch_omega.abs() > 0.00001 {
                    k_mp = k_mp.max((mp_pred.0 - mp0.0) / (h * mount_pitch_omega));
                }
                let c_mp_eff = mount_c_pitch + h * k_mp;
                let mp_denom = 1.0 + h * c_mp_eff * mount_pitch_inv;
                let d_mp = -(mount_pitch_impulse + h * mp0.0 + h * c_mp_eff * mount_pitch_omega)
                    / mp_denom;
                mount_pitch_impulse += d_mp;
                mount_pitch_omega += d_mp * mount_pitch_inv;
            }

            let transmitted = if self.driveline_compliance_enabled {
                -spring_impulse / h
            } else if connected {
                -ratio * gear_impulse / h
            } else {
                0.0
            };

            for axle in 0..2 {
                let ac = &self.axles[axle];
                if axle_shares[axle] <= DIFFERENTIAL_DRIVE_EPS || !ac.is_friction_type {
                    continue;
                }
                let left = axle * 2;
                let diff_speed = spins[left] - spins[left + 1];
                let base_cap_nm = if axle_use_filtered[axle] {
                    axle_precomp_base_cap_nm[axle]
                } else {
                    let axle_input = transmitted * axle_shares[axle];
                    let axle_carrier = 0.5 * (spins[left] + spins[left + 1]);
                    let power_blend = if ac.blend_frac > 0.0 || ac.blend_nm > 0.0 {
                        let dir_s = if axle_carrier.abs() > 0.5 {
                            if axle_carrier >= 0.0 { 1.0 } else { -1.0 }
                        } else {
                            signf(axle_input)
                        };
                        let signed_t = axle_input * dir_s;
                        let band = ac
                            .blend_nm
                            .max(
                                ac.blend_frac
                                    * self.peak_torque_nm
                                    * ref_ratio_abs
                                    * axle_shares[axle],
                            )
                            .max(1.0);
                        let xb = (signed_t / band).clamp(-1.0, 1.0);
                        0.5 + 0.5 * xb * (1.5 - 0.5 * xb * xb)
                    } else {
                        let driving_power = axle_input
                            * if axle_carrier.abs() > 0.5 {
                                axle_carrier
                            } else {
                                signf(axle_input)
                            };
                        (0.5 + 0.5 * (driving_power / 150.0).tanh()).clamp(0.0, 1.0)
                    };
                    axle_blends[axle] = power_blend;
                    let ramp_deg = lerpf(ac.coast_ramp_deg, ac.power_ramp_deg, power_blend);
                    let friction_mu = lerpf(ac.coast_ratio, ac.power_ratio, power_blend);
                    let cot_ramp = if ramp_deg >= 90.0 {
                        0.0
                    } else {
                        1.0 / (ramp_deg.max(15.0) * DEG_TO_RAD).tan()
                    };
                    let ramp_capacity = axle_input.abs()
                        * cot_ramp
                        * ac.clutches.max(1.0)
                        * friction_mu.max(0.0)
                        * ac.ramp_gain.max(0.0);
                    ac.preload_nm.max(0.0) + ramp_capacity.max(0.0)
                };
                let mu_slip_scale = if (ac.static_fac - 1.0).abs() > 0.000001 {
                    lerpf(ac.static_fac, 1.0, (diff_speed.abs() / ac.slip_ref).tanh())
                } else {
                    1.0
                };
                let lsd_capacity = base_cap_nm * mu_slip_scale * h;
                let next_lsd = if ac.lock_stiff > 0.0 {
                    let raw_lsd_d = (h * ac.lock_stiff * axle_lock_twists[axle]
                        + h * axle_lock_c_eff[axle] * diff_speed
                        - lsd_impulses[axle])
                        / axle_lock_denom[axle];
                    (lsd_impulses[axle] + raw_lsd_d).clamp(-lsd_capacity, lsd_capacity)
                } else {
                    (lsd_impulses[axle] + diff_speed / axle_pair_invs[axle])
                        .clamp(-lsd_capacity, lsd_capacity)
                };
                let lsd_delta = next_lsd - lsd_impulses[axle];
                spins[left] -= lsd_delta * inverse[left];
                spins[left + 1] += lsd_delta * inverse[left + 1];
                lsd_impulses[axle] = next_lsd;
                axle_speeds[axle] = diff_speed;
                axle_capacities[axle] = lsd_capacity / h.max(0.000001);
                axle_torques[axle] = next_lsd / h.max(0.000001);
                axle_saturations[axle] = if lsd_capacity > 0.0 {
                    (next_lsd.abs() / lsd_capacity.max(0.000001)).clamp(0.0, 1.0)
                } else {
                    0.0
                };
            }

            for i in 0..4 {
                let before = spins[i];
                let capacity = brakes[i].abs() * h;
                let next_brake =
                    (brake_impulses[i] - before / inverse[i]).clamp(-capacity, capacity);
                let brake_delta = next_brake - brake_impulses[i];
                spins[i] += brake_delta * inverse[i];
                brake_work[i] -= brake_delta * (before + spins[i]) * 0.5;
                brake_impulses[i] = next_brake;
            }
        }

        // Post-loop LSD state updates.
        let final_transmitted = if self.driveline_compliance_enabled {
            -spring_impulse / h
        } else if connected {
            -ratio * gear_impulse / h
        } else {
            0.0
        };
        for axle in 0..2 {
            let ac = &self.axles[axle];
            if axle_shares[axle] <= DIFFERENTIAL_DRIVE_EPS || !ac.is_friction_type {
                axle_lock_twists[axle] = 0.0;
                axle_filt_torques[axle] = 0.0;
                axle_blends[axle] = 0.5;
                continue;
            }
            let left = axle * 2;
            if ac.lock_stiff > 0.0 {
                let final_diff = spins[left] - spins[left + 1];
                let mut next_twist = axle_lock_twists[axle] + h * final_diff;
                let cap_nm = axle_capacities[axle];
                if cap_nm > 0.0 {
                    let max_tw = cap_nm / ac.lock_stiff;
                    next_twist = next_twist.clamp(-max_tw, max_tw);
                } else {
                    next_twist = 0.0;
                }
                axle_lock_twists[axle] = next_twist;
            } else {
                axle_lock_twists[axle] = 0.0;
            }
            let t_ax = final_transmitted * axle_shares[axle];
            if axle_use_filtered[axle] {
                let tau_f = if t_ax.abs() > axle_filt_torques[axle].abs() {
                    ac.press_tau
                } else {
                    ac.rel_tau
                };
                if tau_f > 0.0001 {
                    axle_filt_torques[axle] +=
                        (t_ax - axle_filt_torques[axle]) * (1.0 - (-h / tau_f).exp());
                } else {
                    axle_filt_torques[axle] = t_ax;
                }
            } else {
                axle_filt_torques[axle] = t_ax;
            }
        }

        // Clutch damper update.
        let clutch_damper_twist_deg;
        let clutch_damper_torque_nm;
        let clutch_damper_at_stop;
        if use_clutch_damper {
            let cd_carrier = weights[0] * spins[0]
                + weights[1] * spins[1]
                + weights[2] * spins[2]
                + weights[3] * spins[3];
            let cd_out = if self.driveline_compliance_enabled {
                output_shaft_omega
            } else {
                cd_carrier
            };
            let cd_housing = if mount_second_order {
                if mount_is_transverse {
                    self.chassis_reaction_crank_sign * mount_pitch_omega
                } else {
                    self.chassis_reaction_crank_sign * mount_roll_omega
                }
            } else {
                0.0
            };
            let final_v_cd = input_shaft_omega - cd_housing - ratio * cd_out;
            clutch_damper_twist_rad = (clutch_damper_twist_rad + h * final_v_cd).clamp(-1.0, 1.0);
            clutch_damper_twist_deg = clutch_damper_twist_rad * RAD_TO_DEG;
            clutch_damper_torque_nm = -gear_impulse / h;
            let cd_eval = self.evaluate_clutch_damper_spring(clutch_damper_twist_rad);
            clutch_damper_at_stop = cd_eval.2 > 0.5;
        } else if self.clutch_damper_enabled {
            clutch_damper_twist_rad *= (-h / 0.02).exp();
            clutch_damper_twist_deg = clutch_damper_twist_rad * RAD_TO_DEG;
            clutch_damper_torque_nm = 0.0;
            clutch_damper_at_stop = false;
        } else {
            clutch_damper_twist_rad = 0.0;
            clutch_damper_twist_deg = 0.0;
            clutch_damper_torque_nm = 0.0;
            clutch_damper_at_stop = false;
        }

        // Synchronizer completion check.
        let mut sync_completed = false;
        if shift_phase_is_sync && shift_phase_seconds >= nominal_sync_time {
            let target_carrier = weights[0] * spins[0]
                + weights[1] * spins[1]
                + weights[2] * spins[2]
                + weights[3] * spins[3];
            let sync_output = if self.driveline_compliance_enabled {
                output_shaft_omega
            } else {
                target_carrier
            };
            let sync_housing = if mount_second_order {
                if mount_is_transverse {
                    self.chassis_reaction_crank_sign * mount_pitch_omega
                } else {
                    self.chassis_reaction_crank_sign * mount_roll_omega
                }
            } else {
                0.0
            };
            let dynamic_tol = self.synchronizer_tolerance_rad_s * sync_overtime * 2.5;
            if !pending_gear_nonzero
                || (input_shaft_omega - sync_housing - ratio * sync_output).abs() <= dynamic_tol
                || shift_phase_seconds >= nominal_sync_time * 1.75
            {
                if pending_gear_nonzero {
                    input_shaft_omega = ratio * sync_output + sync_housing;
                }
                sync_completed = true;
            }
        }

        // Driveline twist & energy update.
        let mut current_flank = prev_flank;
        let mut driveline_in_backlash = false;
        let mut driveline_backlash_impact = 0.0;
        let mut driveline_torque_nm = 0.0;
        let mut driveline_energy_j = 0.0;
        let mut driveline_dissipation_w = 0.0;
        if self.driveline_compliance_enabled {
            let final_carrier = weights[0] * spins[0]
                + weights[1] * spins[1]
                + weights[2] * spins[2]
                + weights[3] * spins[3];
            let final_mount_offset =
                (self.chassis_reaction_crank_sign * ds_kappa_z * mount_roll_omega)
                    - (tx_kappa_x * mount_pitch_omega);
            let twist_speed = output_shaft_omega - final_carrier + final_mount_offset;
            let twist_limit = if progressive_contact_enabled { 2.0 } else { 0.35 };
            driveline_twist_rad =
                (driveline_twist_rad + h * twist_speed).clamp(-twist_limit, twist_limit);
            let effective_twist;
            if backlash_half_rad > 0.0 {
                if driveline_twist_rad > backlash_half_rad {
                    effective_twist = driveline_twist_rad - backlash_half_rad;
                    current_flank = 1;
                } else if driveline_twist_rad < -backlash_half_rad {
                    effective_twist = driveline_twist_rad + backlash_half_rad;
                    current_flank = -1;
                } else {
                    effective_twist = 0.0;
                    current_flank = 0;
                }
                driveline_in_backlash = current_flank == 0;
                driveline_backlash_impact = if current_flank != 0 && current_flank != prev_flank {
                    initial_twist_speed.abs()
                } else {
                    0.0
                };
            } else {
                effective_twist = driveline_twist_rad;
                current_flank = if driveline_twist_rad > 0.0 {
                    1
                } else if driveline_twist_rad < 0.0 {
                    -1
                } else {
                    0
                };
                driveline_in_backlash = false;
                driveline_backlash_impact = 0.0;
            }
            driveline_torque_nm = -spring_impulse / h;
            driveline_energy_j = if progressive_contact_enabled {
                self.evaluate_driveline_energy(effective_twist.abs(), end_stop_delta)
            } else {
                0.5 * self.torsional_stiffness_nm_per_rad * effective_twist * effective_twist
            };
            let active_damping = if driveline_in_backlash {
                lash_damping
            } else {
                self.torsional_damping_nms_per_rad
            };
            driveline_dissipation_w = active_damping * twist_speed * twist_speed;
        }

        let engine_rpm_out = engine_omega.max(0.0) * 60.0 / TAU;
        let clutch_torque_nm = clutch_impulse / h;
        let clutch_slip_rad_s = engine_omega - input_shaft_omega;
        let clutch_slip_power_w = (clutch_work / h).max(0.0);
        let shaft_torque = if self.driveline_compliance_enabled {
            driveline_torque_nm
        } else if connected {
            -ratio * gear_impulse / h
        } else {
            0.0
        };

        let engine_roll_deg;
        let engine_pitch_deg;
        if self.chassis_reaction_enabled {
            if mount_second_order {
                if mount_roll_active {
                    mount_roll_rad = (mount_roll_rad + h * mount_roll_omega).clamp(-0.6, 0.6);
                    engine_roll_deg = mount_roll_rad * RAD_TO_DEG;
                } else {
                    mount_roll_rad = 0.0;
                    mount_roll_omega = 0.0;
                    engine_roll_deg = 0.0;
                }
                if mount_pitch_active {
                    mount_pitch_rad = (mount_pitch_rad + h * mount_pitch_omega).clamp(-0.6, 0.6);
                    engine_pitch_deg = mount_pitch_rad * RAD_TO_DEG;
                } else {
                    mount_pitch_rad = 0.0;
                    mount_pitch_omega = 0.0;
                    engine_pitch_deg = 0.0;
                }
                let tau_mount_z = if mount_roll_active {
                    -mount_roll_impulse / h
                } else {
                    0.0
                };
                let tau_mount_x = if mount_pitch_active {
                    -mount_pitch_impulse / h
                } else {
                    0.0
                };
                let tx_chassis = (tau_mount_x - tx_kappa_x * shaft_torque) * self.chassis_reaction_scale;
                let tz_chassis = tau_mount_z * self.chassis_reaction_scale;
                chassis_reaction_torque = [
                    tx_chassis.clamp(-self.max_chassis_reaction_nm, self.max_chassis_reaction_nm),
                    0.0,
                    tz_chassis.clamp(-self.max_chassis_reaction_nm, self.max_chassis_reaction_nm),
                ];
            } else {
                mount_roll_rad = 0.0;
                mount_roll_omega = 0.0;
                mount_pitch_rad = 0.0;
                mount_pitch_omega = 0.0;
                engine_roll_deg = 0.0;
                engine_pitch_deg = 0.0;
                let alpha_e = if reaction_initialized {
                    (engine_omega - reaction_prev_engine_omega) / h
                } else {
                    0.0
                };
                let alpha_in = if reaction_initialized {
                    (input_shaft_omega - reaction_prev_input_omega) / h
                } else {
                    0.0
                };
                let inertial_reaction = -(ie * alpha_e + shaft_inertia * alpha_in);
                let raw_torque = if mount_is_transverse {
                    let tx = (inertial_reaction * self.chassis_reaction_scale)
                        .clamp(-self.max_chassis_reaction_nm, self.max_chassis_reaction_nm);
                    [self.chassis_reaction_crank_sign * tx, 0.0, 0.0]
                } else {
                    let mut ds_roll = 0.0;
                    if self.chassis_reaction_driveshaft_roll_fraction > 0.0
                        && connected
                        && current_gear_nonzero
                    {
                        ds_roll = -clutch_torque_nm
                            * current_gear_ratio
                            * self.chassis_reaction_driveshaft_roll_fraction;
                    }
                    let tz = ((inertial_reaction + ds_roll) * self.chassis_reaction_scale)
                        .clamp(-self.max_chassis_reaction_nm, self.max_chassis_reaction_nm);
                    [0.0, 0.0, self.chassis_reaction_crank_sign * tz]
                };
                let mount_alpha = if self.chassis_reaction_mount_tau_s <= 0.0001 {
                    1.0
                } else {
                    1.0 - (-h / self.chassis_reaction_mount_tau_s).exp()
                };
                for axis in 0..3 {
                    chassis_reaction_torque[axis] =
                        lerpf(chassis_reaction_torque[axis], raw_torque[axis], mount_alpha);
                }
            }
        } else {
            mount_roll_rad = 0.0;
            mount_roll_omega = 0.0;
            mount_pitch_rad = 0.0;
            mount_pitch_omega = 0.0;
            engine_roll_deg = 0.0;
            engine_pitch_deg = 0.0;
            chassis_reaction_torque = [0.0, 0.0, 0.0];
        }

        let o = out.as_mut_slice();
        for i in 0..4 {
            o[i] = spins[i];
            o[4 + i] = brake_work[i].max(0.0);
        }
        o[8] = engine_rpm_out;
        o[9] = input_shaft_omega;
        o[10] = output_shaft_omega;
        o[11] = smooth_clutch;
        o[12] = clutch_torque_nm;
        o[13] = clutch_slip_rad_s;
        o[14] = clutch_slip_power_w;
        o[15] = clutch_damper_twist_rad;
        o[16] = clutch_damper_twist_deg;
        o[17] = clutch_damper_torque_nm;
        o[18] = if clutch_damper_at_stop { 1.0 } else { 0.0 };
        o[19] = driveline_twist_rad;
        o[20] = current_flank as f64;
        o[21] = if driveline_in_backlash { 1.0 } else { 0.0 };
        o[22] = driveline_backlash_impact;
        o[23] = driveline_torque_nm;
        o[24] = driveline_energy_j;
        o[25] = driveline_dissipation_w;
        o[26] = shaft_torque;
        o[27] = mount_roll_rad;
        o[28] = mount_roll_omega;
        o[29] = mount_pitch_rad;
        o[30] = mount_pitch_omega;
        o[31] = engine_roll_deg;
        o[32] = engine_pitch_deg;
        o[33] = chassis_reaction_torque[0];
        o[34] = chassis_reaction_torque[1];
        o[35] = chassis_reaction_torque[2];
        o[36] = if sync_completed { 1.0 } else { 0.0 };
        for axle in 0..2 {
            let b = 37 + axle * 7;
            o[b] = axle_speeds[axle];
            o[b + 1] = axle_capacities[axle];
            o[b + 2] = axle_torques[axle];
            o[b + 3] = axle_saturations[axle];
            o[b + 4] = axle_filt_torques[axle];
            o[b + 5] = axle_blends[axle];
            o[b + 6] = axle_lock_twists[axle];
        }
        o[51] = engine_omega;
        o[52] = input_shaft_omega;
        o[53] = nominal_sync_time;
        out
    }
}
