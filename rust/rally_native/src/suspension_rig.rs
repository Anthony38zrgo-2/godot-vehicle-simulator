use godot::builtin::{
    Basis, PackedByteArray, PackedFloat64Array, PackedVector3Array, Vector3,
};
use godot::classes::RefCounted;
use godot::prelude::*;

const SPRING_PROGRESSIVITY_RATE: f64 = 0.15;
const HELPER_ZONE_FRACTION: f64 = 0.08;
const RADIAL_BISECTION_REL_TOL: f64 = 1.0e-4;
const RADIAL_PACK_SIZE: usize = 14;

// Indices into TireRadialModel packed 14-float layout.
const P_STIFFNESS: usize = 0;
const P_SEATING_BAND: usize = 1;
const P_INV_SEATING: usize = 2;
const P_RIM_START: usize = 3;
const P_RIM_BAND: usize = 4;
const P_INV_RIM_BAND: usize = 5;
const P_RIM_STOP_K: usize = 6;
const P_DAMP_RATIO: usize = 7;
const P_INV_DAMP_RAMP: usize = 9;

#[derive(Clone, Copy, Default)]
struct Vec3 {
    x: f64,
    y: f64,
    z: f64,
}

impl Vec3 {
    const ZERO: Self = Self { x: 0.0, y: 0.0, z: 0.0 };
    const UP: Self = Self { x: 0.0, y: 1.0, z: 0.0 };

    #[inline]
    const fn new(x: f64, y: f64, z: f64) -> Self {
        Self { x, y, z }
    }

    #[inline]
    fn from_v3(v: Vector3) -> Self {
        Self {
            x: v.x as f64,
            y: v.y as f64,
            z: v.z as f64,
        }
    }

    #[inline]
    fn add(self, o: Self) -> Self {
        Self::new(self.x + o.x, self.y + o.y, self.z + o.z)
    }

    #[inline]
    fn sub(self, o: Self) -> Self {
        Self::new(self.x - o.x, self.y - o.y, self.z - o.z)
    }

    #[inline]
    fn scale(self, s: f64) -> Self {
        Self::new(self.x * s, self.y * s, self.z * s)
    }

    #[inline]
    fn neg(self) -> Self {
        Self::new(-self.x, -self.y, -self.z)
    }

    #[inline]
    fn dot(self, o: Self) -> f64 {
        self.x * o.x + self.y * o.y + self.z * o.z
    }

    #[inline]
    fn cross(self, o: Self) -> Self {
        Self::new(
            self.y * o.z - self.z * o.y,
            self.z * o.x - self.x * o.z,
            self.x * o.y - self.y * o.x,
        )
    }

    #[inline]
    fn length_squared(self) -> f64 {
        self.dot(self)
    }

    #[inline]
    fn length(self) -> f64 {
        self.length_squared().sqrt()
    }

    #[inline]
    fn normalized_or(self, fallback: Self) -> Self {
        let lsq = self.length_squared();
        if lsq > 1.0e-9 {
            self.scale(1.0 / lsq.sqrt())
        } else {
            fallback
        }
    }
}

/// Column-major 3x3 matrix matching Godot's Basis(col0, col1, col2) in f64.
#[derive(Clone, Copy)]
struct Mat3 {
    c0: Vec3,
    c1: Vec3,
    c2: Vec3,
}

impl Mat3 {
    const ZERO: Self = Self {
        c0: Vec3::ZERO,
        c1: Vec3::ZERO,
        c2: Vec3::ZERO,
    };

    const IDENTITY: Self = Self {
        c0: Vec3::new(1.0, 0.0, 0.0),
        c1: Vec3::new(0.0, 1.0, 0.0),
        c2: Vec3::new(0.0, 0.0, 1.0),
    };

    #[inline]
    fn from_basis(b: Basis) -> Self {
        Self {
            c0: Vec3::from_v3(b.col_a()),
            c1: Vec3::from_v3(b.col_b()),
            c2: Vec3::from_v3(b.col_c()),
        }
    }

    #[inline]
    fn from_scale(d: Vec3) -> Self {
        Self {
            c0: Vec3::new(d.x, 0.0, 0.0),
            c1: Vec3::new(0.0, d.y, 0.0),
            c2: Vec3::new(0.0, 0.0, d.z),
        }
    }

    #[inline]
    fn add(self, o: Self) -> Self {
        Self {
            c0: self.c0.add(o.c0),
            c1: self.c1.add(o.c1),
            c2: self.c2.add(o.c2),
        }
    }

    #[inline]
    fn sub(self, o: Self) -> Self {
        Self {
            c0: self.c0.sub(o.c0),
            c1: self.c1.sub(o.c1),
            c2: self.c2.sub(o.c2),
        }
    }

    #[inline]
    fn scale(self, s: f64) -> Self {
        Self {
            c0: self.c0.scale(s),
            c1: self.c1.scale(s),
            c2: self.c2.scale(s),
        }
    }

    #[inline]
    fn mul_vec(self, v: Vec3) -> Vec3 {
        Vec3::new(
            self.c0.x * v.x + self.c1.x * v.y + self.c2.x * v.z,
            self.c0.y * v.x + self.c1.y * v.y + self.c2.y * v.z,
            self.c0.z * v.x + self.c1.z * v.y + self.c2.z * v.z,
        )
    }

    #[inline]
    fn mul_mat(self, o: Self) -> Self {
        Self {
            c0: self.mul_vec(o.c0),
            c1: self.mul_vec(o.c1),
            c2: self.mul_vec(o.c2),
        }
    }

    #[inline]
    fn transpose(self) -> Self {
        Self {
            c0: Vec3::new(self.c0.x, self.c1.x, self.c2.x),
            c1: Vec3::new(self.c0.y, self.c1.y, self.c2.y),
            c2: Vec3::new(self.c0.z, self.c1.z, self.c2.z),
        }
    }

    #[inline]
    fn skew(r: Vec3) -> Self {
        Self {
            c0: Vec3::new(0.0, r.z, -r.y),
            c1: Vec3::new(-r.z, 0.0, r.x),
            c2: Vec3::new(r.y, -r.x, 0.0),
        }
    }

    #[inline]
    fn perp_projector(e: Vec3) -> Self {
        Self {
            c0: Vec3::new(1.0 - e.x * e.x, -e.y * e.x, -e.z * e.x),
            c1: Vec3::new(-e.x * e.y, 1.0 - e.y * e.y, -e.z * e.y),
            c2: Vec3::new(-e.x * e.z, -e.y * e.z, 1.0 - e.z * e.z),
        }
    }

    #[inline]
    fn inverse(self) -> Self {
        let r0 = self.c1.cross(self.c2);
        let r1 = self.c2.cross(self.c0);
        let r2 = self.c0.cross(self.c1);
        let det = self.c0.dot(r0);
        if det.abs() < 1.0e-18 {
            return Self::IDENTITY;
        }
        let inv_det = 1.0 / det;
        // Rows of inverse are r0, r1, r2 scaled by inv_det -> columns are transpose.
        Self {
            c0: Vec3::new(r0.x * inv_det, r1.x * inv_det, r2.x * inv_det),
            c1: Vec3::new(r0.y * inv_det, r1.y * inv_det, r2.y * inv_det),
            c2: Vec3::new(r0.z * inv_det, r1.z * inv_det, r2.z * inv_det),
        }
    }

    #[inline]
    fn from_axis_angle(axis: Vec3, angle: f64) -> Self {
        let c = angle.cos();
        let s = angle.sin();
        let t = 1.0 - c;
        let x = axis.x;
        let y = axis.y;
        let z = axis.z;
        Self {
            c0: Vec3::new(t * x * x + c, t * x * y + s * z, t * x * z - s * y),
            c1: Vec3::new(t * x * y - s * z, t * y * y + c, t * y * z + s * x),
            c2: Vec3::new(t * x * z + s * y, t * y * z - s * x, t * z * z + c),
        }
    }
}

#[inline]
fn dot10(a: &[f64; 10], b: &[f64; 10]) -> f64 {
    a[0] * b[0]
        + a[1] * b[1]
        + a[2] * b[2]
        + a[3] * b[3]
        + a[4] * b[4]
        + a[5] * b[5]
        + a[6] * b[6]
        + a[7] * b[7]
        + a[8] * b[8]
        + a[9] * b[9]
}

#[inline]
fn radial_packed_force_n(
    p: &[f64; RADIAL_PACK_SIZE],
    unsprung_mass: f64,
    deflection: f64,
    speed: f64,
    viscous_scale: f64,
) -> f64 {
    if deflection <= 0.0 {
        return 0.0;
    }
    let stiffness = p[P_STIFFNESS];
    let seating_band = p[P_SEATING_BAND];
    let exp_seat = (-deflection * p[P_INV_SEATING]).exp();
    let one_minus_exp = 1.0 - exp_seat;
    let seating_tangent_scale = 1.0 - 0.35 * exp_seat;
    let effective_delta = deflection - 0.35 * seating_band * one_minus_exp;
    let over = (deflection - p[P_RIM_START]).max(0.0);
    let stop_k = p[P_RIM_STOP_K];
    let (stop_tangent, stop_force) = if over > 0.0 {
        let band = p[P_RIM_BAND];
        let st = stop_k * (over * p[P_INV_RIM_BAND]).min(1.0);
        let sf = if over < band {
            0.5 * stop_k * over * over * p[P_INV_RIM_BAND]
        } else {
            stop_k * (over - 0.5 * band)
        };
        (st, sf)
    } else {
        (0.0, 0.0)
    };
    let tangent = stiffness * seating_tangent_scale + stop_tangent;
    let tangent_for_damping = tangent.min(stiffness * 2.5 + 5000.0);
    let mut damping =
        2.0 * (tangent_for_damping.max(1.0) * unsprung_mass.max(1.0)).sqrt() * p[P_DAMP_RATIO];
    let cf = (deflection * p[P_INV_DAMP_RAMP]).clamp(0.0, 1.0);
    damping *= cf * cf * (3.0 - 2.0 * cf);
    let elastic = stiffness * effective_delta + stop_force;
    let effective_speed = if speed >= 0.0 { speed } else { speed * 0.45 };
    let viscous = damping * effective_speed.clamp(-8.0, 8.0) * viscous_scale;
    (elastic + viscous).max(0.0)
}

#[inline]
fn radial_packed_force_and_dissipation(
    p: &[f64; RADIAL_PACK_SIZE],
    unsprung_mass: f64,
    deflection: f64,
    speed: f64,
    viscous_scale: f64,
) -> (f64, f64) {
    if deflection <= 0.0 {
        return (0.0, 0.0);
    }
    let stiffness = p[P_STIFFNESS];
    let seating_band = p[P_SEATING_BAND];
    let exp_seat = (-deflection * p[P_INV_SEATING]).exp();
    let one_minus_exp = 1.0 - exp_seat;
    let seating_tangent_scale = 1.0 - 0.35 * exp_seat;
    let effective_delta = deflection - 0.35 * seating_band * one_minus_exp;
    let over = (deflection - p[P_RIM_START]).max(0.0);
    let stop_k = p[P_RIM_STOP_K];
    let (stop_tangent, stop_force) = if over > 0.0 {
        let band = p[P_RIM_BAND];
        let st = stop_k * (over * p[P_INV_RIM_BAND]).min(1.0);
        let sf = if over < band {
            0.5 * stop_k * over * over * p[P_INV_RIM_BAND]
        } else {
            stop_k * (over - 0.5 * band)
        };
        (st, sf)
    } else {
        (0.0, 0.0)
    };
    let tangent = stiffness * seating_tangent_scale + stop_tangent;
    let tangent_for_damping = tangent.min(stiffness * 2.5 + 5000.0);
    let mut damping =
        2.0 * (tangent_for_damping.max(1.0) * unsprung_mass.max(1.0)).sqrt() * p[P_DAMP_RATIO];
    let cf = (deflection * p[P_INV_DAMP_RAMP]).clamp(0.0, 1.0);
    damping *= cf * cf * (3.0 - 2.0 * cf);
    let elastic = stiffness * effective_delta + stop_force;
    let effective_speed = if speed >= 0.0 { speed } else { speed * 0.45 };
    let viscous = damping * effective_speed.clamp(-8.0, 8.0) * viscous_scale;
    let force = (elastic + viscous).max(0.0);
    let diss = if force > 0.0 {
        ((force - elastic) * speed).max(0.0)
    } else {
        0.0
    };
    (force, diss)
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustSuspensionRig {
    // Rig geometry & unsprung masses
    neutral_positions: [Vec3; 4],
    m_unsprung: [f64; 4],
    inv_m_unsprung: [f64; 4],
    track_front_m: f64,
    track_rear_m: f64,

    // Full inertia tensor & chassis torsion config
    has_full_inertia_tensor: bool,
    tick_inertia_local: Mat3,
    chassis_torsion_enabled: bool,
    chassis_twist_rad: f64,
    chassis_twist_vel_rad_s: f64,
    chassis_torsion_stiffness_nm_per_rad: f64,
    chassis_torsion_damping_ratio: f64,
    chassis_torsion_inertia_kg_m2: f64,

    // Suspension flat parameters (synced only on configure / setup change)
    spring_rate: [f64; 4],
    static_load: [f64; 4],
    rest_offset: [f64; 4],
    bump_m: [f64; 4],
    droop_m: [f64; 4],
    bump_damping: [f64; 4],
    rebound_damping: [f64; 4],
    fast_factor: [f64; 4],
    knee_speed: [f64; 4],
    bump_stop_travel: [f64; 4],
    bump_stop_stiffness: [f64; 4],
    bump_stop_damping: [f64; 4],
    axis_pitch: [f64; 4],
    axis_roll: [f64; 4],
    axis_pitch_gain: [f64; 4],
    axis_roll_gain: [f64; 4],
    spring_can_unseat: [u8; 4],
    has_inclined_axis: [u8; 4],
    any_inclined_axis: bool,
    front_arb_stiffness: f64,
    rear_arb_stiffness: f64,

    // Canonical 1DOF state & predictor
    q: [f64; 4],
    u: [f64; 4],
    apoyo_previo: [bool; 4],
    has_pred: bool,
    c_pred: Vec3,
    r_pred: Mat3,
    v_pred: Vec3,
    omega_pred: Vec3,
    w: [f64; 10],
    w_free: [f64; 10],
    w_normal: [f64; 10],
    w_cand: [f64; 10],

    // Schur complement matrices & solver scratch
    inertia_before: Mat3,
    jolt_inertia_before: Mat3,
    schur_svv_inv: Mat3,
    schur_svw: Mat3,
    schur_k: Mat3,
    schur_srot_inv: Mat3,
    tick_rx: [Vec3; 4],
    axis_response: [[f64; 10]; 4],
    normal_response: [[f64; 10]; 4],
    normal_rows: [[f64; 10]; 4],
    relative_mass: [f64; 4],
    normal_deflection: [f64; 4],
    normal_road_speed: [f64; 4],
    reuse_mass_factor_per_tick: bool,
    mass_factored_this_tick: bool,
    normals_prepared_this_tick: bool,
    prev_jrad: [f64; 4],
    prev_hh: f64,
    last_v_fin: [f64; 4],
    last_d_fin: [f64; 4],
    qmin: [f64; 4],
    qmax: [f64; 4],

    // Tick-anchored state
    tick_r: [Vec3; 4],
    tick_e: Vec3,
    tick_e_wheel: [Vec3; 4],
    tick_m_s: f64,
    tick_com_local: Vec3,
    tick_inertia_diag: Vec3,
    tick_grav: Vec3,
    t_hit: [bool; 4],
    t_h0: [Vec3; 4],
    t_n: [Vec3; 4],
    t_delta0: [f64; 4],
    t_road_vel: [Vec3; 4],
    t_radial_packed: [[f64; RADIAL_PACK_SIZE]; 4],
    t_rim_max: [f64; 4],
    radial_viscous_scale: f64,
    t_elapsed: f64,
    t_h: f64,

    // Per-substep outputs
    s_fz: [f64; 4],
    s_defl: [f64; 4],
    s_diss: [f64; 4],
    s_jrad: [f64; 4],
    s_kn: [f64; 4],
    compression: [f64; 4],
    compression_velocity: [f64; 4],
    spring_forces_n: [f64; 4],
    last_elastic_forces_n: [f64; 4],
    last_damper_forces_n: [f64; 4],
    last_damper_explicit_n: [f64; 4],
    last_bump_forces_n: [f64; 4],

    // Tick accumulators & trace
    acc_j: Vec3,
    acc_l: Vec3,
    acc_fz: [f64; 4],
    acc_defl: [f64; 4],
    acc_diss: [f64; 4],
    trace_axis: Vec3,
    trace_chassis_velocity: Vec3,
    trace_start_hub_velocity: [Vec3; 4],
    spring_impulse_ns: [f64; 4],
    suspension_axial_impulse_ns: [f64; 4],
    contact_axial_impulse_ns: [f64; 4],
    contact_vertical_impulse_ns: [f64; 4],
    radial_impulse_ns: [f64; 4],
    last_damper_impulse_ns: [f64; 4],

    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustSuspensionRig {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            neutral_positions: [Vec3::ZERO; 4],
            m_unsprung: [15.0; 4],
            inv_m_unsprung: [1.0 / 15.0; 4],
            track_front_m: 1.4,
            track_rear_m: 1.4,

            has_full_inertia_tensor: false,
            tick_inertia_local: Mat3::IDENTITY,
            chassis_torsion_enabled: true,
            chassis_twist_rad: 0.0,
            chassis_twist_vel_rad_s: 0.0,
            chassis_torsion_stiffness_nm_per_rad: 180000.0,
            chassis_torsion_damping_ratio: 0.25,
            chassis_torsion_inertia_kg_m2: 70.0,

            spring_rate: [20000.0; 4],
            static_load: [3000.0; 4],
            rest_offset: [0.0; 4],
            bump_m: [0.22; 4],
            droop_m: [0.18; 4],
            bump_damping: [2000.0; 4],
            rebound_damping: [3000.0; 4],
            fast_factor: [0.4; 4],
            knee_speed: [0.15; 4],
            bump_stop_travel: [0.03; 4],
            bump_stop_stiffness: [80000.0; 4],
            bump_stop_damping: [1500.0; 4],
            axis_pitch: [0.0; 4],
            axis_roll: [0.0; 4],
            axis_pitch_gain: [0.0; 4],
            axis_roll_gain: [0.0; 4],
            spring_can_unseat: [1; 4],
            has_inclined_axis: [0; 4],
            any_inclined_axis: false,
            front_arb_stiffness: 0.0,
            rear_arb_stiffness: 0.0,

            q: [0.0; 4],
            u: [0.0; 4],
            apoyo_previo: [false; 4],
            has_pred: false,
            c_pred: Vec3::ZERO,
            r_pred: Mat3::IDENTITY,
            v_pred: Vec3::ZERO,
            omega_pred: Vec3::ZERO,
            w: [0.0; 10],
            w_free: [0.0; 10],
            w_normal: [0.0; 10],
            w_cand: [0.0; 10],

            inertia_before: Mat3::IDENTITY,
            jolt_inertia_before: Mat3::IDENTITY,
            schur_svv_inv: Mat3::IDENTITY,
            schur_svw: Mat3::ZERO,
            schur_k: Mat3::ZERO,
            schur_srot_inv: Mat3::IDENTITY,
            tick_rx: [Vec3::ZERO; 4],
            axis_response: [[0.0; 10]; 4],
            normal_response: [[0.0; 10]; 4],
            normal_rows: [[0.0; 10]; 4],
            relative_mass: [15.0; 4],
            normal_deflection: [0.0; 4],
            normal_road_speed: [0.0; 4],
            reuse_mass_factor_per_tick: true,
            mass_factored_this_tick: false,
            normals_prepared_this_tick: false,
            prev_jrad: [0.0; 4],
            prev_hh: 1.0 / 120.0,
            last_v_fin: [0.0; 4],
            last_d_fin: [0.0; 4],
            qmin: [-0.28; 4],
            qmax: [0.32; 4],

            tick_r: [Vec3::ZERO; 4],
            tick_e: Vec3::UP,
            tick_e_wheel: [Vec3::UP; 4],
            tick_m_s: 1000.0,
            tick_com_local: Vec3::ZERO,
            tick_inertia_diag: Vec3::new(500.0, 800.0, 1200.0),
            tick_grav: Vec3::new(0.0, -9.80665, 0.0),
            t_hit: [false; 4],
            t_h0: [Vec3::ZERO; 4],
            t_n: [Vec3::UP; 4],
            t_delta0: [0.0; 4],
            t_road_vel: [Vec3::ZERO; 4],
            t_radial_packed: [[0.0; RADIAL_PACK_SIZE]; 4],
            t_rim_max: [0.05; 4],
            radial_viscous_scale: 1.0,
            t_elapsed: 0.0,
            t_h: 0.008,

            s_fz: [0.0; 4],
            s_defl: [0.0; 4],
            s_diss: [0.0; 4],
            s_jrad: [0.0; 4],
            s_kn: [1.0; 4],
            compression: [0.0; 4],
            compression_velocity: [0.0; 4],
            spring_forces_n: [0.0; 4],
            last_elastic_forces_n: [0.0; 4],
            last_damper_forces_n: [0.0; 4],
            last_damper_explicit_n: [0.0; 4],
            last_bump_forces_n: [0.0; 4],

            acc_j: Vec3::ZERO,
            acc_l: Vec3::ZERO,
            acc_fz: [0.0; 4],
            acc_defl: [0.0; 4],
            acc_diss: [0.0; 4],
            trace_axis: Vec3::UP,
            trace_chassis_velocity: Vec3::ZERO,
            trace_start_hub_velocity: [Vec3::ZERO; 4],
            spring_impulse_ns: [0.0; 4],
            suspension_axial_impulse_ns: [0.0; 4],
            contact_axial_impulse_ns: [0.0; 4],
            contact_vertical_impulse_ns: [0.0; 4],
            radial_impulse_ns: [0.0; 4],
            last_damper_impulse_ns: [0.0; 4],

            base,
        }
    }
}

impl RustSuspensionRig {
    #[inline]
    fn inertia_world_diag(&self, r: Mat3, d: Vec3) -> Mat3 {
        r.mul_mat(Mat3::from_scale(d)).mul_mat(r.transpose())
    }

    #[inline]
    fn inertia_world(&self, r: Mat3, d: Vec3) -> Mat3 {
        if !self.has_full_inertia_tensor {
            return self.inertia_world_diag(r, d);
        }
        let iw = r.mul_mat(self.tick_inertia_local).mul_mat(r.transpose());
        let i01 = 0.5 * (iw.c1.x + iw.c0.y);
        let i02 = 0.5 * (iw.c2.x + iw.c0.z);
        let i12 = 0.5 * (iw.c2.y + iw.c1.z);
        Mat3 {
            c0: Vec3::new(iw.c0.x, i01, i02),
            c1: Vec3::new(i01, iw.c1.y, i12),
            c2: Vec3::new(i02, i12, iw.c2.z),
        }
    }

    #[inline]
    fn suspension_axis_local(&self, i: usize, travel_m: f64) -> Vec3 {
        if self.has_inclined_axis[i] == 0 {
            return Vec3::UP;
        }
        let travel_delta = travel_m - self.rest_offset[i];
        let pitch = self.axis_pitch[i] + self.axis_pitch_gain[i] * travel_delta;
        let side_sign = if i == 0 || i == 2 { 1.0 } else { -1.0 };
        let roll = side_sign * (self.axis_roll[i] + self.axis_roll_gain[i] * travel_delta);
        if pitch.abs() < 1.0e-7 && roll.abs() < 1.0e-7 {
            return Vec3::UP;
        }
        let axis = Vec3::new(roll.sin(), pitch.cos() * roll.cos(), pitch.sin());
        axis.normalized_or(Vec3::UP)
    }

    fn factor_schur(&mut self) {
        let mut s_vv = Mat3::from_scale(Vec3::new(self.tick_m_s, self.tick_m_s, self.tick_m_s));
        let mut s_vw = Mat3::ZERO;
        let mut s_ww = self.inertia_before;
        for i in 0..4 {
            let m_i = self.m_unsprung[i];
            let e_i = self.tick_e_wheel[i];
            let r_i = self.tick_r[i];
            self.tick_rx[i] = r_i.cross(e_i);
            let p_i = Mat3::perp_projector(e_i);
            let r_skew = Mat3::skew(r_i);
            let m_p = p_i.scale(m_i);
            let m_pr = m_p.mul_mat(r_skew);
            s_vv = s_vv.add(m_p);
            s_vw = s_vw.sub(m_pr);
            s_ww = s_ww.add(r_skew.transpose().mul_mat(m_pr));
        }
        self.schur_svv_inv = s_vv.inverse();
        self.schur_svw = s_vw;
        self.schur_k = s_vw.transpose().mul_mat(self.schur_svv_inv);
        let s_rot = s_ww.sub(self.schur_k.mul_mat(s_vw));
        self.schur_srot_inv = s_rot.inverse();
    }

    #[inline]
    fn solve_schur_parts(
        &self,
        f_v: Vec3,
        f_w: Vec3,
        fu: [f64; 4],
    ) -> [f64; 10] {
        let mut t_v = f_v;
        let mut t_w = f_w;
        for i in 0..4 {
            t_v = t_v.sub(self.tick_e_wheel[i].scale(fu[i]));
            t_w = t_w.sub(self.tick_rx[i].scale(fu[i]));
        }
        let om_out = self.schur_srot_inv.mul_vec(t_w.sub(self.schur_k.mul_vec(t_v)));
        let v_out = self.schur_svv_inv.mul_vec(t_v.sub(self.schur_svw.mul_vec(om_out)));
        let mut out = [0.0; 10];
        out[0] = v_out.x;
        out[1] = v_out.y;
        out[2] = v_out.z;
        out[3] = om_out.x;
        out[4] = om_out.y;
        out[5] = om_out.z;
        for i in 0..4 {
            out[6 + i] = fu[i] * self.inv_m_unsprung[i]
                - self.tick_e_wheel[i].dot(v_out.add(om_out.cross(self.tick_r[i])));
        }
        out
    }

    fn solve_schur_axis(&mut self, wheel: usize) {
        let t_v = self.tick_e_wheel[wheel].neg();
        let t_w = self.tick_rx[wheel].neg();
        let om_out = self.schur_srot_inv.mul_vec(t_w.sub(self.schur_k.mul_vec(t_v)));
        let v_out = self.schur_svv_inv.mul_vec(t_v.sub(self.schur_svw.mul_vec(om_out)));
        let res = &mut self.axis_response[wheel];
        res[0] = v_out.x;
        res[1] = v_out.y;
        res[2] = v_out.z;
        res[3] = om_out.x;
        res[4] = om_out.y;
        res[5] = om_out.z;
        for i in 0..4 {
            let fu = if i == wheel { self.inv_m_unsprung[i] } else { 0.0 };
            res[6 + i] = fu - self.tick_e_wheel[i].dot(v_out.add(om_out.cross(self.tick_r[i])));
        }
    }

    fn solve_schur_normal(&mut self, wheel: usize, nrm: Vec3) -> f64 {
        let e_i = self.tick_e_wheel[wheel];
        let r_i = self.tick_r[wheel];
        let en = e_i.dot(nrm);
        let n_perp = nrm.sub(e_i.scale(en));
        if n_perp.length_squared() < 1.0e-12 {
            let res = &mut self.normal_response[wheel];
            *res = [0.0; 10];
            let u_i = en * self.inv_m_unsprung[wheel];
            res[6 + wheel] = u_i;
            return (en * u_i).max(1.0e-9);
        }
        let t_w = r_i.cross(n_perp);
        let om_out = self.schur_srot_inv.mul_vec(t_w.sub(self.schur_k.mul_vec(n_perp)));
        let v_out = self.schur_svv_inv.mul_vec(n_perp.sub(self.schur_svw.mul_vec(om_out)));
        let res = &mut self.normal_response[wheel];
        res[0] = v_out.x;
        res[1] = v_out.y;
        res[2] = v_out.z;
        res[3] = om_out.x;
        res[4] = om_out.y;
        res[5] = om_out.z;
        for i in 0..4 {
            let fu = if i == wheel { en * self.inv_m_unsprung[i] } else { 0.0 };
            res[6 + i] = fu - self.tick_e_wheel[i].dot(v_out.add(om_out.cross(self.tick_r[i])));
        }
        let rn = r_i.cross(nrm);
        (nrm.dot(v_out) + rn.dot(om_out) + en * res[6 + wheel]).max(1.0e-9)
    }

    fn fill_normal_row(&mut self, wheel: usize) {
        let r = self.tick_r[wheel];
        let e = self.tick_e_wheel[wheel];
        let normal = self.t_n[wheel];
        let row = &mut self.normal_rows[wheel];
        row[0] = normal.x;
        row[1] = normal.y;
        row[2] = normal.z;
        let torque = r.cross(normal);
        row[3] = torque.x;
        row[4] = torque.y;
        row[5] = torque.z;
        row[6] = 0.0;
        row[7] = 0.0;
        row[8] = 0.0;
        row[9] = 0.0;
        row[6 + wheel] = e.dot(normal);
    }

    fn compute_suspension_forces_1dof(&mut self, dt: f64) -> [f64; 4] {
        let mut forces = [0.0; 4];
        let dt_safe = dt.max(0.00001);
        for i in 0..4 {
            let travel = self.compression[i];
            let speed = self.compression_velocity[i];
            let damper_rate = if speed >= 0.0 {
                self.bump_damping[i]
            } else {
                self.rebound_damping[i]
            };
            let abs_speed = speed.abs();
            let knee = self.knee_speed[i];
            let damper_explicit = if knee.is_finite() && abs_speed > 0.0 {
                let slow_part = knee * (abs_speed / knee).tanh();
                let fast_part = (abs_speed - slow_part).max(0.0) * self.fast_factor[i];
                let sgn = if speed > 0.0 { 1.0 } else if speed < 0.0 { -1.0 } else { 0.0 };
                sgn * damper_rate * (slow_part + fast_part)
            } else {
                damper_rate * speed
            };
            let c_lin = if abs_speed > 1.0e-4 {
                damper_explicit.abs() / abs_speed
            } else {
                damper_rate
            };
            let m_eff = self.relative_mass[i].max(1.0);
            let damper_force = if abs_speed > 1.0e-9 {
                damper_explicit / (1.0 + (c_lin * dt_safe) / m_eff)
            } else {
                0.0
            };
            let travel_delta = travel - self.rest_offset[i];
            let bump_m_i = self.bump_m[i];
            let max_range = bump_m_i.max(0.05);
            let norm_travel = (travel_delta / max_range).clamp(-1.0, 1.5);
            let progressive_rate = self.spring_rate[i]
                * (1.0 + SPRING_PROGRESSIVITY_RATE * norm_travel * norm_travel.abs());
            let static_load_i = self.static_load[i];
            let mut elastic_force = static_load_i + progressive_rate * travel_delta;
            if self.spring_can_unseat[i] != 0 {
                let helper_zone = static_load_i * HELPER_ZONE_FRACTION;
                if elastic_force < helper_zone {
                    elastic_force =
                        helper_zone * ((elastic_force - helper_zone) / helper_zone.max(1.0)).exp();
                }
            }
            let mut force = elastic_force + damper_force;
            self.last_elastic_forces_n[i] = elastic_force;
            self.last_damper_forces_n[i] = damper_force;
            self.last_damper_explicit_n[i] = damper_explicit;

            let bump_range = self.bump_stop_travel[i];
            let bump_threshold = bump_m_i - bump_range;
            let mut bump_force = 0.0;
            if travel > bump_threshold {
                let overtravel = travel - bump_threshold;
                let norm_over = (overtravel / bump_range).clamp(0.0, 2.0);
                let b_stiff = self.bump_stop_stiffness[i];
                let bump_elastic = b_stiff * overtravel * norm_over * (0.5 + 0.5 * norm_over);
                let bump_damp =
                    self.bump_stop_damping[i] * speed.max(0.0) * norm_over.clamp(0.0, 1.0);
                let bump_explicit = bump_elastic + bump_damp;
                let mut k_lin = b_stiff * norm_over * (0.5 + 0.5 * norm_over);
                k_lin = k_lin.max(bump_explicit.abs() / overtravel.max(1.0e-4));
                bump_force = bump_explicit / (1.0 + (k_lin * dt * dt) / m_eff);
                force += bump_force;
            }
            self.last_bump_forces_n[i] = bump_force;
            forces[i] = force;
        }
        let front_roll = self.compression[0] - self.compression[1];
        let rear_roll = self.compression[2] - self.compression[3];
        let m_roll_front =
            1.0 / (1.0 / self.relative_mass[0].max(1.0) + 1.0 / self.relative_mass[1].max(1.0));
        let m_roll_rear =
            1.0 / (1.0 / self.relative_mass[2].max(1.0) + 1.0 / self.relative_mass[3].max(1.0));
        let dt2 = dt_safe * dt_safe;
        let k_arb_front_eff =
            self.front_arb_stiffness / (1.0 + (self.front_arb_stiffness * dt2) / m_roll_front);
        let k_arb_rear_eff =
            self.rear_arb_stiffness / (1.0 + (self.rear_arb_stiffness * dt2) / m_roll_rear);
        let mut front_arb = k_arb_front_eff * front_roll;
        let mut rear_arb = k_arb_rear_eff * rear_roll;
        let f_w0 = if !self.apoyo_previo[0] {
            (forces[0] / (self.static_load[0] * 0.25).max(1.0)).clamp(0.0, 1.0)
        } else {
            1.0
        };
        let f_w1 = if !self.apoyo_previo[1] {
            (forces[1] / (self.static_load[1] * 0.25).max(1.0)).clamp(0.0, 1.0)
        } else {
            1.0
        };
        front_arb *= f_w0.min(f_w1);
        let r_w2 = if !self.apoyo_previo[2] {
            (forces[2] / (self.static_load[2] * 0.25).max(1.0)).clamp(0.0, 1.0)
        } else {
            1.0
        };
        let r_w3 = if !self.apoyo_previo[3] {
            (forces[3] / (self.static_load[3] * 0.25).max(1.0)).clamp(0.0, 1.0)
        } else {
            1.0
        };
        rear_arb *= r_w2.min(r_w3);
        forces[0] += front_arb;
        forces[1] -= front_arb;
        forces[2] += rear_arb;
        forces[3] -= rear_arb;
        forces
    }

    fn internal_begin_substep(&mut self, h: f64, f_body: Vec3, t_body: Vec3) {
        let t_h = h.max(0.00001);
        self.t_h = t_h;
        let e = self.r_pred.mul_vec(Vec3::UP).normalized_or(Vec3::UP);
        self.tick_e = e;
        let om = Vec3::new(self.w[3], self.w[4], self.w[5]);
        let need_factor = (!self.reuse_mass_factor_per_tick) || (!self.mass_factored_this_tick);
        self.inertia_before = self.inertia_world(self.r_pred, self.tick_inertia_diag);
        self.jolt_inertia_before = if self.has_full_inertia_tensor {
            self.inertia_world_diag(self.r_pred, self.tick_inertia_diag)
        } else {
            self.inertia_before
        };
        if need_factor {
            for i in 0..4 {
                let e_i = if self.any_inclined_axis {
                    self.r_pred
                        .mul_vec(self.suspension_axis_local(i, self.q[i]))
                        .normalized_or(e)
                } else {
                    e
                };
                self.tick_e_wheel[i] = e_i;
                self.tick_r[i] = self
                    .r_pred
                    .mul_vec(self.neutral_positions[i].sub(self.tick_com_local))
                    .add(e_i.scale(self.q[i]));
            }
            self.factor_schur();
            for i in 0..4 {
                self.solve_schur_axis(i);
                self.relative_mass[i] = 1.0 / self.axis_response[i][6 + i].max(1.0e-9);
            }
            self.mass_factored_this_tick = true;
        } else {
            for i in 0..4 {
                self.tick_r[i] = self
                    .r_pred
                    .mul_vec(self.neutral_positions[i].sub(self.tick_com_local))
                    .add(self.tick_e_wheel[i].scale(self.q[i]));
            }
        }

        // Suspensión: q_nom (incluyendo torsión estructural del chasis en serie) y m_rel.
        let hf_f = if self.chassis_torsion_enabled {
            0.25 * self.track_front_m
        } else {
            0.0
        };
        let hf_r = if self.chassis_torsion_enabled {
            0.25 * self.track_rear_m
        } else {
            0.0
        };
        let dq0 = hf_f * self.chassis_twist_rad;
        let dq2 = -hf_r * self.chassis_twist_rad;
        let du0 = hf_f * self.chassis_twist_vel_rad_s;
        let du2 = -hf_r * self.chassis_twist_vel_rad_s;
        for i in 0..4 {
            let dq_i = match i {
                0 => dq0,
                1 => -dq0,
                2 => dq2,
                _ => -dq2,
            };
            let du_i = match i {
                0 => du0,
                1 => -du0,
                2 => du2,
                _ => -du2,
            };
            let qn = (self.q[i] - dq_i).clamp(-self.droop_m[i], self.bump_m[i]);
            self.compression[i] = qn;
            self.compression_velocity[i] = self.u[i] - du_i;
        }
        let mut fs = self.compute_suspension_forces_1dof(t_h);
        // Resistencia al droop semi-implícita.
        for i in 0..4 {
            let droop = self.droop_m[i];
            let qn = self.compression[i];
            if qn < -droop + 0.025 {
                let pen = (-droop + 0.025) - qn;
                let m_eff_d = self.relative_mass[i].max(1.0);
                let k_droop = self.spring_rate[i] * 6.0;
                let c_droop = self.rebound_damping[i] * 2.5;
                let k_droop_eff = k_droop / (1.0 + (k_droop * t_h * t_h) / m_eff_d);
                let c_droop_eff = c_droop / (1.0 + (c_droop * t_h) / m_eff_d);
                fs[i] -= k_droop_eff * pen - c_droop_eff * self.u[i].min(0.0);
            }
        }
        if self.chassis_torsion_enabled {
            let m_roll_f = (fs[0] - fs[1]) * (0.5 * self.track_front_m);
            let m_roll_r = (fs[2] - fs[3]) * (0.5 * self.track_rear_m);
            let t_twist_ext = 0.5 * (m_roll_f - m_roll_r);
            let k_tw = self.chassis_torsion_stiffness_nm_per_rad.max(10000.0);
            let i_tw = self.chassis_torsion_inertia_kg_m2.max(5.0);
            let c_tw = 2.0 * (k_tw * i_tw).sqrt() * self.chassis_torsion_damping_ratio.clamp(0.05, 1.5);
            let k_f_roll = (self.spring_rate[0] + 2.0 * self.front_arb_stiffness)
                * (0.125 * self.track_front_m * self.track_front_m);
            let k_r_roll = (self.spring_rate[2] + 2.0 * self.rear_arb_stiffness)
                * (0.125 * self.track_rear_m * self.track_rear_m);
            let k_series = k_tw + k_f_roll + k_r_roll;
            let denom_tw = i_tw + t_h * c_tw + t_h * t_h * k_series;
            let acc_tw = (t_twist_ext - k_tw * self.chassis_twist_rad - c_tw * self.chassis_twist_vel_rad_s)
                / denom_tw.max(1.0e-6);
            self.chassis_twist_vel_rad_s += acc_tw * t_h;
            self.chassis_twist_rad =
                (self.chassis_twist_rad + self.chassis_twist_vel_rad_s * t_h).clamp(-0.08, 0.08);
        }

        let e_dot_trace = e.dot(self.trace_axis);
        for i in 0..4 {
            self.spring_forces_n[i] = fs[i];
            self.last_damper_impulse_ns[i] += self.last_damper_forces_n[i] * t_h;
            let spring_impulse = fs[i] * t_h;
            self.spring_impulse_ns[i] += spring_impulse;
            self.suspension_axial_impulse_ns[i] -= spring_impulse * e_dot_trace;
        }

        let mut q_v = self.tick_grav.scale(self.tick_m_s).add(f_body);
        let iw_om = self.inertia_before.mul_vec(om);
        let mut q_t = om.cross(iw_om).neg().add(t_body);
        let mut fu = [0.0; 4];
        for i in 0..4 {
            let r = self.tick_r[i];
            let e_i = self.tick_e_wheel[i];
            let bias = om.cross(om.cross(r)).add(om.cross(e_i.scale(self.u[i])).scale(2.0));
            let force = self.tick_grav.sub(bias).scale(self.m_unsprung[i]);
            q_v = q_v.add(force);
            q_t = q_t.add(r.cross(force));
            fu[i] = e_i.dot(force) - fs[i];
        }
        let resp = self.solve_schur_parts(q_v, q_t, fu);
        for k in 0..10 {
            self.w_free[k] = self.w[k] + t_h * resp[k];
        }
    }

    fn internal_solve_normal(&mut self, h: f64) {
        let hh = h.max(0.00001);
        let hh_scale = hh / self.prev_hh.max(0.00001);
        let mut w_rad = self.w_free;
        let need_normals = (!self.reuse_mass_factor_per_tick) || (!self.normals_prepared_this_tick);
        let v_scale = self.radial_viscous_scale;
        for i in 0..4 {
            self.s_jrad[i] = 0.0;
            self.s_fz[i] = 0.0;
            self.s_defl[i] = 0.0;
            self.s_diss[i] = 0.0;
            if !self.t_hit[i] {
                self.prev_jrad[i] = 0.0;
                continue;
            }
            if need_normals {
                self.fill_normal_row(i);
                let nrm = self.t_n[i];
                self.s_kn[i] = self.solve_schur_normal(i, nrm);
            }
            let kn = self.s_kn[i];
            let h_pos = self.c_pred.add(self.tick_r[i]);
            let delta = self.t_delta0[i]
                - self.t_n[i].dot(h_pos.sub(self.t_h0[i]).sub(self.t_road_vel[i].scale(self.t_elapsed)));
            self.normal_deflection[i] = delta;
            self.normal_road_speed[i] = self.t_n[i].dot(self.t_road_vel[i]);
            let v_free = dot10(&self.normal_rows[i], &self.w_free) - self.normal_road_speed[i];
            let mi = self.m_unsprung[i].max(1.0);
            let rp = &self.t_radial_packed[i];
            let mut j_val = 0.0;
            let dfin_free = (delta - hh * v_free).max(0.0);
            if dfin_free > 0.0 {
                let jmax = ((delta / hh - v_free) / kn).max(0.0);
                let mut lo = 0.0;
                let mut hi = jmax;
                let f_lo = radial_packed_force_n(rp, mi, dfin_free, (-v_free).clamp(-12.0, 12.0), v_scale);
                let mut r_lo = -hh * f_lo;
                let mut r_hi = jmax;
                if r_lo < 0.0 && jmax > 0.0 {
                    let mut j_try = if self.prev_jrad[i] > 0.0 {
                        (self.prev_jrad[i] * hh_scale).clamp(lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo))
                    } else {
                        0.5 * jmax
                    };
                    for _ in 0..24 {
                        let v_try = v_free + kn * j_try;
                        let d_try = (delta - hh * v_try).max(0.0);
                        let c_try = (-v_try).clamp(-12.0, 12.0);
                        let f_try = radial_packed_force_n(rp, mi, d_try, c_try, v_scale);
                        let res = j_try - hh * f_try;
                        if res.abs() <= RADIAL_BISECTION_REL_TOL * j_try.abs().max(1.0) {
                            j_val = j_try;
                            lo = j_try;
                            hi = j_try;
                            break;
                        }
                        if res >= 0.0 {
                            hi = j_try;
                            r_hi = res;
                        } else {
                            lo = j_try;
                            r_lo = res;
                        }
                        if hi - lo <= RADIAL_BISECTION_REL_TOL * lo.abs().max(1.0) {
                            j_val = 0.5 * (lo + hi);
                            break;
                        }
                        let denom_sec = r_hi - r_lo;
                        let mut j_next = 0.5 * (lo + hi);
                        if denom_sec > 1.0e-12 {
                            let j_sec = (lo * r_hi - hi * r_lo) / denom_sec;
                            let margin = 0.08 * (hi - lo);
                            if j_sec > lo + margin && j_sec < hi - margin {
                                j_next = j_sec;
                            }
                        }
                        j_try = j_next;
                    }
                    if hi > lo {
                        j_val = 0.5 * (lo + hi);
                    }
                }
            }
            let j_rad = j_val.max(0.0);
            self.s_jrad[i] = j_rad;
            self.prev_jrad[i] = j_rad;
            let v_fin = v_free + kn * j_rad;
            let d_fin = (delta - hh * v_fin).max(0.0);
            let c_fin = (-v_fin).clamp(-12.0, 12.0);
            self.last_v_fin[i] = c_fin;
            self.last_d_fin[i] = d_fin;
            let (_f_fin, diss_fin) = radial_packed_force_and_dissipation(rp, mi, d_fin, c_fin, v_scale);
            self.s_defl[i] = d_fin;
            self.s_diss[i] = diss_fin;
            for k in 0..10 {
                w_rad[k] += self.normal_response[i][k] * j_rad;
            }
        }
        self.normals_prepared_this_tick = true;
        self.prev_hh = hh;

        self.w_normal = w_rad;
        let rim_impulse_cap = 8.0 * self.tick_m_s.max(100.0) * self.tick_grav.length() * hh;
        for i in 0..4 {
            if !self.t_hit[i] {
                continue;
            }
            let gap = self.t_rim_max[i] - self.normal_deflection[i];
            let target = if gap >= 0.0 {
                -gap / hh
            } else {
                (-0.18 * gap / hh).min(2.0)
            };
            let normal_speed = dot10(&self.normal_rows[i], &w_rad) - self.normal_road_speed[i];
            let impulse = ((target - normal_speed) / self.s_kn[i]).clamp(0.0, rim_impulse_cap);
            let normal_impulse = self.s_jrad[i] + impulse;
            self.s_fz[i] = normal_impulse / hh;
            self.radial_impulse_ns[i] += self.s_jrad[i];
            self.contact_axial_impulse_ns[i] += normal_impulse * self.t_n[i].dot(self.trace_axis);
            self.contact_vertical_impulse_ns[i] += normal_impulse * self.t_n[i].y;
            for k in 0..10 {
                self.w_normal[k] += self.normal_response[i][k] * impulse;
            }
        }
    }

    fn internal_apply_tangential(&mut self, f_j: Vec3, t_j: Vec3, j_hub: [f64; 4]) {
        let resp = self.solve_schur_parts(f_j, t_j, j_hub);
        for k in 0..10 {
            self.w_cand[k] = self.w_normal[k] + resp[k];
        }
    }

    fn internal_solve_hard_stops(&mut self, h: f64) {
        let hh = h.max(0.00001);
        let mut lo = [0.0; 4];
        let mut hi = [0.0; 4];
        let mut needs_stop = false;
        for i in 0..4 {
            lo[i] = (self.qmin[i] - self.q[i]) / hh;
            hi[i] = (self.qmax[i] - self.q[i]) / hh;
            if self.w_cand[6 + i] < lo[i] || self.w_cand[6 + i] > hi[i] {
                needs_stop = true;
            }
        }
        if !needs_stop {
            return;
        }
        let mut lam = [0.0; 4];
        for _ in 0..20 {
            let mut maxd: f64 = 0.0;
            for i in 0..4 {
                let d = &self.axis_response[i];
                let inverse_mass = d[6 + i].max(1.0e-9);
                let w_s = self.w_cand[6 + i] - inverse_mass * lam[i];
                let ul = w_s.clamp(lo[i], hi[i]);
                let lam_new = (ul - w_s) / inverse_mass.max(1.0e-12);
                let dl = lam_new - lam[i];
                maxd = maxd.max(dl.abs());
                if dl.abs() > 1.0e-12 {
                    for k in 0..10 {
                        self.w_cand[k] += d[k] * dl;
                    }
                    lam[i] = lam_new;
                }
            }
            if maxd < 1.0e-9 {
                break;
            }
        }
    }

    fn internal_end_substep(&mut self, h: f64) {
        let hh = h.max(0.00001);
        let v_old = Vec3::new(self.w[0], self.w[1], self.w[2]);
        let om_old = Vec3::new(self.w[3], self.w[4], self.w[5]);
        let iw_old = self.inertia_before;
        let v_new = Vec3::new(self.w_cand[0], self.w_cand[1], self.w_cand[2]);
        let om_new = Vec3::new(self.w_cand[3], self.w_cand[4], self.w_cand[5]);
        for i in 0..4 {
            self.u[i] = self.w_cand[6 + i];
            self.q[i] = (self.q[i] + hh * self.u[i]).clamp(self.qmin[i], self.qmax[i]);
        }
        self.c_pred = self.c_pred.add(v_new.scale(hh));
        let om_len = om_new.length();
        if om_len > 1.0e-9 {
            let axis = om_new.scale(1.0 / om_len);
            self.r_pred = Mat3::from_axis_angle(axis, om_len * hh).mul_mat(self.r_pred);
        }
        self.acc_j = self.acc_j.add(
            v_new
                .sub(v_old)
                .scale(self.tick_m_s)
                .sub(self.tick_grav.scale(hh * self.tick_m_s)),
        );
        let iw_jolt_new = if self.has_full_inertia_tensor {
            self.inertia_world_diag(self.r_pred, self.tick_inertia_diag)
        } else {
            self.inertia_world(self.r_pred, self.tick_inertia_diag)
        };
        let iw_jolt_old = if self.has_full_inertia_tensor {
            self.jolt_inertia_before
        } else {
            iw_old
        };
        self.acc_l = self
            .acc_l
            .add(iw_jolt_new.mul_vec(om_new).sub(iw_jolt_old.mul_vec(om_old)));
        self.w = self.w_cand;
        self.v_pred = v_new;
        self.omega_pred = om_new;
        for i in 0..4 {
            self.apoyo_previo[i] = self.s_fz[i] > 0.0;
            self.acc_fz[i] += self.s_fz[i] * hh;
            self.acc_defl[i] += self.s_defl[i] * hh;
            self.acc_diss[i] += self.s_diss[i] * hh;
        }
        self.t_elapsed += hh;
    }

    fn pack_substep_end(&self) -> PackedFloat64Array {
        let mut out = PackedFloat64Array::new();
        out.resize(27);
        let s = out.as_mut_slice();
        s[0] = self.c_pred.x;
        s[1] = self.c_pred.y;
        s[2] = self.c_pred.z;
        s[3] = self.r_pred.c0.x;
        s[4] = self.r_pred.c0.y;
        s[5] = self.r_pred.c0.z;
        s[6] = self.r_pred.c1.x;
        s[7] = self.r_pred.c1.y;
        s[8] = self.r_pred.c1.z;
        s[9] = self.r_pred.c2.x;
        s[10] = self.r_pred.c2.y;
        s[11] = self.r_pred.c2.z;
        s[12] = self.v_pred.x;
        s[13] = self.v_pred.y;
        s[14] = self.v_pred.z;
        s[15] = self.omega_pred.x;
        s[16] = self.omega_pred.y;
        s[17] = self.omega_pred.z;
        for i in 0..4 {
            s[18 + i] = self.q[i];
            s[22 + i] = self.u[i];
        }
        s[26] = self.t_elapsed;
        out
    }

    fn pack_substep_normal(&self) -> PackedFloat64Array {
        let mut out = PackedFloat64Array::new();
        out.resize(44);
        let s = out.as_mut_slice();
        for i in 0..4 {
            s[i] = self.s_fz[i];
            s[4 + i] = self.s_defl[i];
            s[8 + i] = self.s_diss[i];
            s[12 + i] = self.s_jrad[i];
            s[16 + i] = self.compression[i];
            s[20 + i * 3] = self.tick_r[i].x;
            s[21 + i * 3] = self.tick_r[i].y;
            s[22 + i * 3] = self.tick_r[i].z;
            s[32 + i * 3] = self.tick_e_wheel[i].x;
            s[33 + i * 3] = self.tick_e_wheel[i].y;
            s[34 + i * 3] = self.tick_e_wheel[i].z;
        }
        out
    }
}

#[godot_api]
impl RustSuspensionRig {
    #[func]
    fn configure_rig(
        &mut self,
        neutral_pos: PackedVector3Array,
        m_unsprung: PackedFloat64Array,
        track_front: f64,
        track_rear: f64,
    ) {
        let np = neutral_pos.as_slice();
        let mu = m_unsprung.as_slice();
        for i in 0..4 {
            if i < np.len() {
                self.neutral_positions[i] = Vec3::from_v3(np[i]);
            }
            let m = if i < mu.len() { mu[i].max(1.0) } else { 15.0 };
            self.m_unsprung[i] = m;
            self.inv_m_unsprung[i] = 1.0 / m;
        }
        self.track_front_m = track_front.max(0.5);
        self.track_rear_m = track_rear.max(0.5);
    }

    #[func]
    fn set_local_inertia_tensor(&mut self, has_full: bool, tensor: Basis) {
        self.has_full_inertia_tensor = has_full;
        if has_full {
            self.tick_inertia_local = Mat3::from_basis(tensor);
        }
    }

    #[func]
    fn configure_chassis_torsion(&mut self, stiffness: f64, damping_ratio: f64, inertia: f64) {
        self.chassis_torsion_stiffness_nm_per_rad = stiffness.max(10000.0);
        self.chassis_torsion_damping_ratio = damping_ratio.clamp(0.05, 1.5);
        self.chassis_torsion_inertia_kg_m2 = inertia.max(5.0);
    }

    #[func]
    fn sync_suspension_params(
        &mut self,
        params66: PackedFloat64Array,
        flags9: PackedByteArray,
    ) {
        let p = params66.as_slice();
        if p.len() >= 66 {
            for i in 0..4 {
                self.spring_rate[i] = p[i];
                self.static_load[i] = p[4 + i];
                self.rest_offset[i] = p[8 + i];
                self.bump_m[i] = p[12 + i];
                self.droop_m[i] = p[16 + i];
                self.bump_damping[i] = p[20 + i];
                self.rebound_damping[i] = p[24 + i];
                self.fast_factor[i] = p[28 + i];
                self.knee_speed[i] = p[32 + i];
                self.bump_stop_travel[i] = p[36 + i];
                self.bump_stop_stiffness[i] = p[40 + i];
                self.bump_stop_damping[i] = p[44 + i];
                self.axis_pitch[i] = p[48 + i];
                self.axis_roll[i] = p[52 + i];
                self.axis_pitch_gain[i] = p[56 + i];
                self.axis_roll_gain[i] = p[60 + i];
            }
            self.front_arb_stiffness = p[64];
            self.rear_arb_stiffness = p[65];
        }
        let f = flags9.as_slice();
        if f.len() >= 9 {
            for i in 0..4 {
                self.spring_can_unseat[i] = f[i];
                self.has_inclined_axis[i] = f[4 + i];
            }
            self.any_inclined_axis = f[8] != 0;
        }
    }

    #[func]
    fn reset_state(&mut self, q_init: PackedFloat64Array) {
        let qs = q_init.as_slice();
        for i in 0..4 {
            self.q[i] = if i < qs.len() { qs[i] } else { 0.0 };
            self.u[i] = 0.0;
            self.apoyo_previo[i] = false;
            self.spring_forces_n[i] = 0.0;
            self.acc_fz[i] = 0.0;
            self.acc_defl[i] = 0.0;
            self.acc_diss[i] = 0.0;
            self.s_jrad[i] = 0.0;
            self.prev_jrad[i] = 0.0;
            self.last_v_fin[i] = 0.0;
            self.last_d_fin[i] = 0.0;
            self.s_fz[i] = 0.0;
            self.s_defl[i] = 0.0;
            self.s_diss[i] = 0.0;
            self.last_damper_impulse_ns[i] = 0.0;
        }
        self.chassis_twist_rad = 0.0;
        self.chassis_twist_vel_rad_s = 0.0;
        self.has_pred = false;
        self.acc_j = Vec3::ZERO;
        self.acc_l = Vec3::ZERO;
        self.t_elapsed = 0.0;
    }

    /// Vec14 layout: [com_local, inertia_diag, grav, c_in, v_in, om_in, t_n[0..4], t_road_vel[0..4]]
    /// Scalars30 layout: [mass_s, radial_viscous_scale, t_delta0[0..4], t_rim_max[0..4], q_min[0..4], q_max[0..4], q[0..4], u[0..4], m_unsprung[0..4]]
    /// flags_mask: bits 0..3 = t_hit[0..4], bit 4 = reuse_mass_factor, bit 5 = chassis_torsion_enabled
    #[func]
    fn begin_tick(
        &mut self,
        vec14: PackedVector3Array,
        r_in: Basis,
        scalars30: PackedFloat64Array,
        radial_packed_56: PackedFloat64Array,
        flags_mask: i32,
    ) {
        let vs = vec14.as_slice();
        let sc = scalars30.as_slice();
        if vs.len() < 14 || sc.len() < 30 {
            return;
        }
        self.tick_com_local = Vec3::from_v3(vs[0]);
        self.tick_inertia_diag = Vec3::from_v3(vs[1]);
        self.tick_grav = Vec3::from_v3(vs[2]);
        let c = Vec3::from_v3(vs[3]);
        let v = Vec3::from_v3(vs[4]);
        let om = Vec3::from_v3(vs[5]);
        let r = Mat3::from_basis(r_in);

        self.tick_m_s = sc[0].max(1.0);
        self.radial_viscous_scale = sc[1];
        self.reuse_mass_factor_per_tick = (flags_mask & (1 << 4)) != 0;
        self.chassis_torsion_enabled = (flags_mask & (1 << 5)) != 0;

        for i in 0..4 {
            self.qmin[i] = sc[10 + i];
            self.qmax[i] = sc[14 + i];
            self.q[i] = sc[18 + i];
            self.u[i] = sc[22 + i];
            let m = sc[26 + i].max(1.0);
            self.m_unsprung[i] = m;
            self.inv_m_unsprung[i] = 1.0 / m;
        }

        let e_act = r.mul_vec(Vec3::UP).normalized_or(Vec3::UP);
        for i in 0..4 {
            self.tick_e_wheel[i] = if self.any_inclined_axis {
                r.mul_vec(self.suspension_axis_local(i, self.q[i])).normalized_or(e_act)
            } else {
                e_act
            };
        }
        self.c_pred = c;
        self.r_pred = r;
        self.v_pred = v;
        self.omega_pred = om;
        self.tick_e = e_act;
        self.w = [v.x, v.y, v.z, om.x, om.y, om.z, self.u[0], self.u[1], self.u[2], self.u[3]];
        self.mass_factored_this_tick = false;
        self.normals_prepared_this_tick = false;
        self.trace_axis = e_act;
        self.trace_chassis_velocity = v;
        self.spring_impulse_ns = [0.0; 4];
        self.suspension_axial_impulse_ns = [0.0; 4];
        self.contact_axial_impulse_ns = [0.0; 4];
        self.contact_vertical_impulse_ns = [0.0; 4];
        self.radial_impulse_ns = [0.0; 4];
        self.last_damper_impulse_ns = [0.0; 4];

        let rp_s = radial_packed_56.as_slice();
        for i in 0..4 {
            let hit = (flags_mask & (1 << i)) != 0;
            self.t_hit[i] = hit;
            let a2 = self.neutral_positions[i].sub(self.tick_com_local);
            let e_i = self.tick_e_wheel[i];
            let r2 = r.mul_vec(a2).add(e_i.scale(self.q[i]));
            self.tick_r[i] = r2;
            let h0 = c.add(r2);
            self.trace_start_hub_velocity[i] = v.add(om.cross(r2)).add(e_i.scale(self.u[i]));
            self.t_h0[i] = h0;
            if !hit {
                self.t_n[i] = e_i;
                self.t_delta0[i] = 0.0;
                self.t_road_vel[i] = Vec3::ZERO;
                self.t_rim_max[i] = 0.05;
                self.prev_jrad[i] = 0.0;
                continue;
            }
            self.t_n[i] = Vec3::from_v3(vs[6 + i]);
            self.t_delta0[i] = sc[2 + i];
            self.t_road_vel[i] = Vec3::from_v3(vs[10 + i]);
            self.t_rim_max[i] = sc[6 + i];
            let base_idx = i * RADIAL_PACK_SIZE;
            if base_idx + RADIAL_PACK_SIZE <= rp_s.len() {
                self.t_radial_packed[i].copy_from_slice(&rp_s[base_idx..base_idx + RADIAL_PACK_SIZE]);
            }
        }
        self.t_elapsed = 0.0;
        self.acc_j = Vec3::ZERO;
        self.acc_l = Vec3::ZERO;
        self.acc_fz = [0.0; 4];
        self.acc_defl = [0.0; 4];
        self.acc_diss = [0.0; 4];
        self.s_fz = [0.0; 4];
        self.s_defl = [0.0; 4];
        self.s_diss = [0.0; 4];
        self.s_jrad = [0.0; 4];
    }

    /// Fused begin_substep + solve_normal (1 FFI crossing per substep).
    #[func]
    fn step_substep_normal(&mut self, h: f64, f_body: Vector3, t_body: Vector3) -> PackedFloat64Array {
        self.internal_begin_substep(h, Vec3::from_v3(f_body), Vec3::from_v3(t_body));
        self.internal_solve_normal(h);
        self.pack_substep_normal()
    }

    #[func]
    fn begin_substep(&mut self, h: f64, f_body: Vector3, t_body: Vector3) -> PackedFloat64Array {
        self.internal_begin_substep(h, Vec3::from_v3(f_body), Vec3::from_v3(t_body));
        let mut out = PackedFloat64Array::new();
        out.resize(28);
        let s = out.as_mut_slice();
        for i in 0..4 {
            s[i] = self.compression[i];
            s[4 + i * 3] = self.tick_r[i].x;
            s[5 + i * 3] = self.tick_r[i].y;
            s[6 + i * 3] = self.tick_r[i].z;
            s[16 + i * 3] = self.tick_e_wheel[i].x;
            s[17 + i * 3] = self.tick_e_wheel[i].y;
            s[18 + i * 3] = self.tick_e_wheel[i].z;
        }
        out
    }

    #[func]
    fn solve_normal(&mut self, h: f64) -> PackedFloat64Array {
        self.internal_solve_normal(h);
        self.pack_substep_normal()
    }

    /// Fused apply_tangential + solve_hard_stops + end_substep (1 FFI crossing per substep).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn step_substep_tangential_and_end(
        &mut self,
        h: f64,
        f_patch_j: Vector3,
        t_patch_j: Vector3,
        j_hub0: f64,
        j_hub1: f64,
        j_hub2: f64,
        j_hub3: f64,
    ) -> PackedFloat64Array {
        self.internal_apply_tangential(
            Vec3::from_v3(f_patch_j),
            Vec3::from_v3(t_patch_j),
            [j_hub0, j_hub1, j_hub2, j_hub3],
        );
        self.internal_solve_hard_stops(h);
        self.internal_end_substep(h);
        self.pack_substep_end()
    }

    #[func]
    fn apply_tangential(
        &mut self,
        f_patch_j: Vector3,
        t_patch_j: Vector3,
        j_hub0: f64,
        j_hub1: f64,
        j_hub2: f64,
        j_hub3: f64,
    ) {
        self.internal_apply_tangential(
            Vec3::from_v3(f_patch_j),
            Vec3::from_v3(t_patch_j),
            [j_hub0, j_hub1, j_hub2, j_hub3],
        );
    }

    #[func]
    fn solve_hard_stops(&mut self, h: f64) {
        self.internal_solve_hard_stops(h);
    }

    #[func]
    fn end_substep(&mut self, h: f64) -> PackedFloat64Array {
        self.internal_end_substep(h);
        self.pack_substep_end()
    }

    #[func]
    fn end_tick_snapshot(&mut self) -> PackedFloat64Array {
        self.has_pred = true;
        let mut out = PackedFloat64Array::new();
        out.resize(98);
        let s = out.as_mut_slice();
        s[0] = self.acc_j.x;
        s[1] = self.acc_j.y;
        s[2] = self.acc_j.z;
        s[3] = self.acc_l.x;
        s[4] = self.acc_l.y;
        s[5] = self.acc_l.z;
        for i in 0..4 {
            s[6 + i] = self.acc_fz[i];
            s[10 + i] = self.acc_defl[i];
            s[14 + i] = self.acc_diss[i];
            s[18 + i] = self.q[i];
            s[22 + i] = self.u[i];
            s[26 + i] = self.last_d_fin[i];
            s[30 + i] = self.last_v_fin[i];
            s[34 + i] = self.spring_forces_n[i];
            s[38 + i] = self.last_damper_explicit_n[i];
            s[42 + i] = self.last_damper_forces_n[i];
            s[46 + i] = self.last_damper_impulse_ns[i];
            s[50 + i] = self.spring_impulse_ns[i];
            s[54 + i] = self.suspension_axial_impulse_ns[i];
            s[58 + i] = self.contact_axial_impulse_ns[i];
            s[62 + i] = self.contact_vertical_impulse_ns[i];
            s[66 + i] = self.radial_impulse_ns[i];
            s[70 + i] = self.last_elastic_forces_n[i];
            s[74 + i] = self.last_bump_forces_n[i];
        }
        s[78] = self.chassis_twist_rad;
        s[79] = self.chassis_twist_vel_rad_s;
        s[80] = self.trace_axis.x;
        s[81] = self.trace_axis.y;
        s[82] = self.trace_axis.z;
        s[83] = self.trace_chassis_velocity.x;
        s[84] = self.trace_chassis_velocity.y;
        s[85] = self.trace_chassis_velocity.z;
        for i in 0..4 {
            s[86 + i * 3] = self.trace_start_hub_velocity[i].x;
            s[87 + i * 3] = self.trace_start_hub_velocity[i].y;
            s[88 + i * 3] = self.trace_start_hub_velocity[i].z;
        }
        out
    }
}
