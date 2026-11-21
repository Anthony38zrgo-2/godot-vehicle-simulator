use std::f32::consts::{FRAC_PI_2, PI, TAU};

use godot::builtin::{
    Basis, Color, GString, PackedByteArray, PackedFloat32Array, PackedInt32Array, Rid,
    Transform3D, Vector3,
};
use godot::classes::{RefCounted, RenderingServer};
use godot::prelude::*;

use crate::rng::Pcg32;

pub const CAPACITY: usize = 400;
pub const STEP: f32 = 1.0 / 25.0;
pub const INSTANCE_STRIDE_FLOATS: usize = 20;

const FOLIAGE_TICKS: i32 = 0xC8;
const LEAF_SIZE: f32 = 1.0 * (0xCCCC as f32 / 65536.0) * (0x1999 as f32 / 65536.0);
const GRASS_SIZE: f32 = 1.0 * (0x18000 as f32 / 65536.0) * (0x1999 as f32 / 65536.0);
const SHORT_GRASS_SIZE: f32 = 1.0 * (0x18000 as f32 / 65536.0) * (0x147A as f32 / 65536.0);
const FOLIAGE_SPIN: f32 = TAU * (0x71 as f32) / 4096.0 / STEP;

const SHADES: [f32; 3] = [0.88, 1.0, 1.12];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Kind {
    Dust = 0,
    DirtDust = 1,
    SandDust = 2,
    SlipDust = 3,
    Smoke = 4,
    Splash = 5,
    Water = 6,
    Snow = 7,
    Leaf = 8,
    Grass = 9,
    GrassShort = 10,
    Rock = 11,
    Mud = 12,
    Exhaust = 13,
    Backfire = 14,
    Glass = 15,
    RainSplat = 16,
    GravelChip = 17,
    GravelSpray = 18,
    BeadYellow = 19,
    BeadOrange = 20,
}

impl Kind {
    #[inline]
    fn from_i32(v: i32) -> Self {
        match v {
            0 => Self::Dust,
            1 => Self::DirtDust,
            2 => Self::SandDust,
            3 => Self::SlipDust,
            4 => Self::Smoke,
            5 => Self::Splash,
            6 => Self::Water,
            7 => Self::Snow,
            8 => Self::Leaf,
            9 => Self::Grass,
            10 => Self::GrassShort,
            11 => Self::Rock,
            12 => Self::Mud,
            13 => Self::Exhaust,
            14 => Self::Backfire,
            15 => Self::Glass,
            16 => Self::RainSplat,
            17 => Self::GravelChip,
            18 => Self::GravelSpray,
            19 => Self::BeadYellow,
            20 => Self::BeadOrange,
            _ => Self::Dust,
        }
    }

    #[inline]
    fn is_dust(self) -> bool {
        matches!(self, Self::Dust | Self::DirtDust | Self::SandDust | Self::SlipDust)
    }

    #[inline]
    fn is_cloud(self) -> bool {
        matches!(
            self,
            Self::Dust
                | Self::DirtDust
                | Self::SandDust
                | Self::SlipDust
                | Self::Smoke
                | Self::Exhaust
                | Self::Splash
        )
    }

    #[inline]
    fn is_debris(self) -> bool {
        matches!(
            self,
            Self::Rock | Self::Mud | Self::Glass | Self::Water | Self::Snow | Self::GravelChip
        )
    }
}

#[derive(Clone, Copy)]
struct KindProfile {
    color: [f32; 3],
    ticks: i32,
    size: [f32; 2],
    alpha: f32,
    gravity: f32,
    drag: f32,
    frames: i32,
    frame_delay: i32, // -1 if none
    frame_ticks: i32,
    cutout: bool,
}

const PROFILES: [KindProfile; 21] = [
    // 0: Dust
    KindProfile {
        color: [152.0 / 255.0, 126.0 / 255.0, 102.0 / 255.0],
        ticks: 50,
        size: [0.42, 2.10],
        alpha: 100.0 / 255.0,
        gravity: -0.32,
        drag: 1.2,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 1: DirtDust
    KindProfile {
        color: [0.60, 0.39, 0.24],
        ticks: 46,
        size: [0.38, 1.80],
        alpha: 0.43,
        gravity: -0.26,
        drag: 1.4,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 2: SandDust
    KindProfile {
        color: [0.86, 0.72, 0.47],
        ticks: 54,
        size: [0.44, 2.20],
        alpha: 0.40,
        gravity: -0.36,
        drag: 1.1,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 3: SlipDust
    KindProfile {
        color: [0.74, 0.66, 0.56],
        ticks: 33,
        size: [0.22, 0.83],
        alpha: 100.0 / 255.0,
        gravity: -0.32,
        drag: 0.0,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 4: Smoke
    KindProfile {
        color: [0.71, 0.74, 0.78],
        ticks: 34,
        size: [0.16, 0.68],
        alpha: 0.32,
        gravity: -0.15,
        drag: 1.0,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 5: Splash
    KindProfile {
        color: [0.82, 0.90, 0.96],
        ticks: 17,
        size: [0.20, 0.83],
        alpha: 0.65,
        gravity: 2.5,
        drag: 0.6,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 6: Water
    KindProfile {
        color: [0.76, 0.87, 0.96],
        ticks: 25,
        size: [0.16, 0.36],
        alpha: 0.75,
        gravity: 7.0,
        drag: 0.0,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 7: Snow
    KindProfile {
        color: [0.90, 0.95, 1.0],
        ticks: 35,
        size: [0.18, 0.52],
        alpha: 0.82,
        gravity: 2.0,
        drag: 0.8,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 8: Leaf
    KindProfile {
        color: [0.48, 0.53, 0.14],
        ticks: FOLIAGE_TICKS,
        size: [LEAF_SIZE, LEAF_SIZE],
        alpha: 1.0,
        gravity: 4.0,
        drag: 0.7,
        frames: 5,
        frame_delay: 2,
        frame_ticks: 1,
        cutout: true,
    },
    // 9: Grass
    KindProfile {
        color: [0.24, 0.43, 0.08],
        ticks: FOLIAGE_TICKS,
        size: [GRASS_SIZE, GRASS_SIZE],
        alpha: 1.0,
        gravity: 4.0,
        drag: 0.7,
        frames: 2,
        frame_delay: 4,
        frame_ticks: 4,
        cutout: true,
    },
    // 10: GrassShort
    KindProfile {
        color: [0.37, 0.47, 0.10],
        ticks: FOLIAGE_TICKS,
        size: [SHORT_GRASS_SIZE, SHORT_GRASS_SIZE],
        alpha: 1.0,
        gravity: 4.0,
        drag: 0.7,
        frames: 2,
        frame_delay: 4,
        frame_ticks: 4,
        cutout: true,
    },
    // 11: Rock
    KindProfile {
        color: [0.78, 0.68, 0.52],
        ticks: 12,
        size: [0.022, 0.038],
        alpha: 1.0,
        gravity: 9.5,
        drag: 2.0,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: true,
    },
    // 12: Mud
    KindProfile {
        color: [0.44, 0.31, 0.19],
        ticks: 25,
        size: [0.14, 0.14],
        alpha: 1.0,
        gravity: 13.0,
        drag: 0.0,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: true,
    },
    // 13: Exhaust
    KindProfile {
        color: [1.0, 1.0, 1.0],
        ticks: 27,
        size: [0.04, 0.42],
        alpha: 80.0 / 255.0,
        gravity: -0.18,
        drag: 1.0,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 14: Backfire
    KindProfile {
        color: [1.0, 0.85, 0.58],
        ticks: 4,
        size: [0.16, 0.28],
        alpha: 1.0,
        gravity: 0.0,
        drag: 0.0,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 15: Glass
    KindProfile {
        color: [0.78, 0.88, 0.95],
        ticks: 26,
        size: [0.11, 0.11],
        alpha: 1.0,
        gravity: 9.8,
        drag: 0.0,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: true,
    },
    // 16: RainSplat
    KindProfile {
        color: [0.84, 0.91, 1.0],
        ticks: 8,
        size: [0.14, 0.42],
        alpha: 0.82,
        gravity: 0.0,
        drag: 0.0,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 17: GravelChip
    KindProfile {
        color: [0.78, 0.68, 0.52],
        ticks: 18,
        size: [0.025, 0.045],
        alpha: 1.0,
        gravity: 10.0,
        drag: 0.8,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: true,
    },
    // 18: GravelSpray
    KindProfile {
        color: [0.78, 0.68, 0.52],
        ticks: 35,
        size: [0.198, 0.572],
        alpha: 0.82,
        gravity: 10.0,
        drag: 0.8,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 19: BeadYellow
    KindProfile {
        color: [1.0, 0.94, 0.10],
        ticks: 18,
        size: [0.15, 0.09],
        alpha: 0.95,
        gravity: 1.8,
        drag: 1.6,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
    // 20: BeadOrange
    KindProfile {
        color: [1.0, 0.12, 0.01],
        ticks: 18,
        size: [0.15, 0.09],
        alpha: 0.95,
        gravity: 1.8,
        drag: 1.6,
        frames: 1,
        frame_delay: -1,
        frame_ticks: 1,
        cutout: false,
    },
];

#[derive(Clone, Copy)]
struct LookConfig {
    snap: f32,
    fraction_steps: i32,
    size_steps: i32,
    alpha_steps: i32,
    color_bits: i32,
    angle_steps: i32,
    ramps: bool,
    shade_var: f32,
    cloud_scale: f32,
    debris_scale: f32,
    alpha_boost: f32,
    saturation: f32,
    contrast: f32,
}

const LOOKS: [LookConfig; 3] = [
    // 0: MODERN
    LookConfig {
        snap: 0.0,
        fraction_steps: 0,
        size_steps: 0,
        alpha_steps: 0,
        color_bits: 8,
        angle_steps: 0,
        ramps: false,
        shade_var: 0.0,
        cloud_scale: 1.0,
        debris_scale: 1.0,
        alpha_boost: 1.0,
        saturation: 1.0,
        contrast: 1.0,
    },
    // 1: CMR2
    LookConfig {
        snap: 1.0 / 32.0,
        fraction_steps: 2,
        size_steps: 6,
        alpha_steps: 5,
        color_bits: 5,
        angle_steps: 8,
        ramps: true,
        shade_var: 0.6,
        cloud_scale: 1.2,
        debris_scale: 1.5,
        alpha_boost: 1.25,
        saturation: 1.15,
        contrast: 1.10,
    },
    // 2: VRALLY2
    LookConfig {
        snap: 1.0 / 16.0,
        fraction_steps: 1,
        size_steps: 4,
        alpha_steps: 4,
        color_bits: 5,
        angle_steps: 8,
        ramps: true,
        shade_var: 1.0,
        cloud_scale: 1.1,
        debris_scale: 1.8,
        alpha_boost: 1.4,
        saturation: 1.35,
        contrast: 1.20,
    },
];

const fn c8(r: u8, g: u8, b: u8) -> [f32; 3] {
    [r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0]
}

const RAMP_DUST: [[f32; 3]; 4] = [
    c8(214, 184, 142),
    c8(178, 146, 112),
    c8(152, 126, 102),
    c8(128, 108, 92),
];
const RAMP_DIRT_DUST: [[f32; 3]; 3] = [c8(176, 120, 76), c8(150, 98, 62), c8(120, 84, 60)];
const RAMP_SAND_DUST: [[f32; 3]; 3] = [c8(240, 214, 150), c8(220, 186, 124), c8(196, 166, 120)];
const RAMP_SLIP_DUST: [[f32; 3]; 3] = [c8(226, 208, 178), c8(190, 170, 142), c8(160, 142, 120)];
const RAMP_SMOKE: [[f32; 3]; 3] = [c8(236, 236, 240), c8(190, 194, 204), c8(140, 146, 158)];
const RAMP_EXHAUST: [[f32; 3]; 3] = [c8(255, 255, 255), c8(220, 224, 232), c8(170, 176, 188)];
const RAMP_BACKFIRE: [[f32; 3]; 4] = [
    c8(255, 255, 224),
    c8(255, 206, 72),
    c8(255, 120, 24),
    c8(200, 48, 16),
];
const RAMP_SPLASH: [[f32; 3]; 3] = [c8(232, 238, 242), c8(200, 212, 222), c8(168, 184, 198)];

#[inline]
fn ramp_for(kind: Kind) -> Option<&'static [[f32; 3]]> {
    match kind {
        Kind::Dust => Some(&RAMP_DUST),
        Kind::DirtDust => Some(&RAMP_DIRT_DUST),
        Kind::SandDust => Some(&RAMP_SAND_DUST),
        Kind::SlipDust => Some(&RAMP_SLIP_DUST),
        Kind::Smoke => Some(&RAMP_SMOKE),
        Kind::Exhaust => Some(&RAMP_EXHAUST),
        Kind::Backfire => Some(&RAMP_BACKFIRE),
        Kind::Splash => Some(&RAMP_SPLASH),
        _ => None,
    }
}

#[inline]
fn lerpf(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[inline]
fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[inline]
fn stepped(t: f32, steps: i32) -> f32 {
    if steps <= 1 {
        return t;
    }
    ((t * steps as f32).floor() / (steps - 1) as f32).min(1.0)
}

#[inline]
fn snapf(val: f32, step: f32) -> f32 {
    if step == 0.0 {
        val
    } else {
        (val / step).round() * step
    }
}

struct BatchBuffer {
    rid: Option<Rid>,
    data: Vec<f32>,
    visible_count: i32,
    prev_visible_count: i32,
}

impl BatchBuffer {
    fn new(rid: Option<Rid>) -> Self {
        Self {
            rid,
            data: Vec::new(),
            visible_count: 0,
            prev_visible_count: 0,
        }
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustWheelParticles {
    look: usize,
    kind: [Kind; CAPACITY],
    batch_id: [u16; CAPACITY],
    is_gravel_dust: [bool; CAPACITY],
    previous: [Vector3; CAPACITY],
    position: [Vector3; CAPACITY],
    velocity: [Vector3; CAPACITY],
    floor_point: [Vector3; CAPACITY],
    floor_normal: [Vector3; CAPACITY],
    ticks: [i32; CAPACITY],
    max_ticks: [i32; CAPACITY],
    frame_offset: [i32; CAPACITY],
    size_factor: [f32; CAPACITY],
    spin: [f32; CAPACITY],
    angle: [f32; CAPACITY],
    shade: [f32; CAPACITY],
    intensity: [f32; CAPACITY],
    bounced: [bool; CAPACITY],

    visual_dirty: [bool; CAPACITY],
    visual_basis: [Basis; CAPACITY],
    visual_color: [Color; CAPACITY],
    visual_data: [[f32; 4]; CAPACITY],

    active_slots: Vec<usize>,
    free_slots: Vec<usize>,
    batches: Vec<BatchBuffer>,
    sim_dirty: bool,
    last_draw_fraction: f32,
    last_active_mask: i64,
    rng: Pcg32,
    style_rng: Pcg32,

    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustWheelParticles {
    fn init(base: Base<RefCounted>) -> Self {
        let mut free_slots = Vec::with_capacity(CAPACITY);
        for slot in (0..CAPACITY).rev() {
            free_slots.push(slot);
        }
        Self {
            look: 2, // Look.VRALLY2 default matching rally_wheel_particles.gd
            kind: [Kind::Dust; CAPACITY],
            batch_id: [0; CAPACITY],
            is_gravel_dust: [false; CAPACITY],
            previous: [Vector3::ZERO; CAPACITY],
            position: [Vector3::ZERO; CAPACITY],
            velocity: [Vector3::ZERO; CAPACITY],
            floor_point: [Vector3::ZERO; CAPACITY],
            floor_normal: [Vector3::UP; CAPACITY],
            ticks: [0; CAPACITY],
            max_ticks: [0; CAPACITY],
            frame_offset: [0; CAPACITY],
            size_factor: [1.0; CAPACITY],
            spin: [0.0; CAPACITY],
            angle: [0.0; CAPACITY],
            shade: [1.0; CAPACITY],
            intensity: [1.0; CAPACITY],
            bounced: [false; CAPACITY],
            visual_dirty: [true; CAPACITY],
            visual_basis: [Basis::IDENTITY; CAPACITY],
            visual_color: [Color::WHITE; CAPACITY],
            visual_data: [[0.0; 4]; CAPACITY],
            active_slots: Vec::with_capacity(CAPACITY),
            free_slots,
            batches: Vec::with_capacity(16),
            sim_dirty: true,
            last_draw_fraction: -1.0,
            last_active_mask: 0,
            rng: Pcg32::seeded(0x434d5232),
            style_rng: Pcg32::seeded(0x56524c32),
            base,
        }
    }
}

#[godot_api]
impl RustWheelParticles {
    #[func]
    pub fn set_look(&mut self, look_idx: i32) {
        let idx = (look_idx as usize).min(LOOKS.len() - 1);
        if self.look != idx {
            self.look = idx;
            self.visual_dirty.fill(true);
            self.sim_dirty = true;
            self.last_draw_fraction = -1.0;
        }
    }

    #[func]
    pub fn register_batch(&mut self) -> i32 {
        let id = self.batches.len() as i32;
        self.batches.push(BatchBuffer::new(None));
        self.sim_dirty = true;
        id
    }

    #[func]
    pub fn register_batch_rid(&mut self, multimesh_rid: Rid) -> i32 {
        let id = self.batches.len() as i32;
        self.batches.push(BatchBuffer::new(Some(multimesh_rid)));
        self.sim_dirty = true;
        id
    }

    /// Emits a particle and returns `[slot, reused_active_flag, max_ticks, frame_offset]`.
    #[func]
    #[allow(clippy::too_many_arguments)]
    pub fn emit_particle(
        &mut self,
        kind_val: i32,
        batch_id: i32,
        is_gravel_dust: bool,
        point: Vector3,
        velocity: Vector3,
        floor_point: Vector3,
        floor_normal: Vector3,
        intensity: f32,
    ) -> PackedInt32Array {
        let mut reused_active = 0i32;
        let slot: usize;
        if let Some(free) = self.free_slots.pop() {
            slot = free;
            let insert_at = self.active_slots.binary_search(&slot).unwrap_or_else(|e| e);
            self.active_slots.insert(insert_at, slot);
        } else {
            reused_active = 1;
            let mut best_slot = self.active_slots[0];
            let mut oldest_age = -1;
            for &candidate in &self.active_slots {
                let age = self.max_ticks[candidate] - self.ticks[candidate];
                if age > oldest_age {
                    oldest_age = age;
                    best_slot = candidate;
                }
            }
            slot = best_slot;
        }

        let kind = Kind::from_i32(kind_val);
        let profile = &PROFILES[kind as usize];
        let foliage = profile.frame_delay >= 0;
        let max_ticks = if is_gravel_dust {
            ((profile.ticks as f32) * 0.65).round() as i32
        } else {
            profile.ticks
        };
        let mut frame_offset = 0;
        if foliage {
            frame_offset = self.rng.randi_range(0, profile.frames - 1);
        } else if kind.is_dust() && kind != Kind::SlipDust {
            frame_offset = self.rng.randi_range(0, 7);
        }

        let size_factor = if foliage {
            1.0
        } else {
            self.rng.randf_range(0.82, 1.18)
        };
        let spin = if foliage {
            FOLIAGE_SPIN
        } else if kind == Kind::Glass {
            self.rng.randf_range(-5.0, 5.0)
        } else {
            0.0
        };
        let angle = if foliage
            || matches!(
                kind,
                Kind::Rock | Kind::Mud | Kind::Glass | Kind::GravelChip
            ) {
            self.rng.randf_range(-PI, PI)
        } else {
            0.0
        };
        let shade = SHADES[self.style_rng.randi_range(0, 2) as usize];

        self.visual_dirty[slot] = true;
        self.kind[slot] = kind;
        self.batch_id[slot] = batch_id.max(0) as u16;
        self.is_gravel_dust[slot] = is_gravel_dust;
        self.previous[slot] = point;
        self.position[slot] = point;
        self.velocity[slot] = velocity;
        self.floor_point[slot] = floor_point;
        self.floor_normal[slot] = floor_normal;
        self.intensity[slot] = intensity;
        self.max_ticks[slot] = max_ticks;
        self.ticks[slot] = max_ticks;
        self.frame_offset[slot] = frame_offset;
        self.size_factor[slot] = size_factor;
        self.spin[slot] = spin;
        self.angle[slot] = angle;
        self.shade[slot] = shade;
        self.bounced[slot] = false;
        self.sim_dirty = true;

        PackedInt32Array::from(&[slot as i32, reused_active, max_ticks, frame_offset][..])
    }

    /// Advances all active particles by `STEP` (1/25 s) and returns expired slot indices.
    #[func]
    pub fn step(&mut self, wind: Vector3) -> PackedInt32Array {
        if self.active_slots.is_empty() {
            return PackedInt32Array::new();
        }
        self.sim_dirty = true;
        for &slot in &self.active_slots {
            self.ticks[slot] -= 1;
            self.visual_dirty[slot] = true;
            self.previous[slot] = self.position[slot];

            let kind = self.kind[slot];
            let profile = &PROFILES[kind as usize];
            let mut vel = self.velocity[slot].lerp(wind, profile.drag * STEP);
            vel.y -= profile.gravity * STEP;
            let mut pos = self.position[slot] + vel * STEP;
            self.angle[slot] += self.spin[slot] * STEP;

            let fn_vec = self.floor_normal[slot];
            let height = (pos - self.floor_point[slot]).dot(fn_vec);
            if height < 0.0 {
                if matches!(
                    kind,
                    Kind::Rock | Kind::Mud | Kind::GravelChip | Kind::GravelSpray
                ) {
                    pos -= fn_vec * height;
                    let vertical = vel.dot(fn_vec);
                    if vertical < 0.0 {
                        let rebound = -vertical * 0.7;
                        vel -= fn_vec * vertical;
                        if rebound > 0.20 {
                            vel += fn_vec * rebound;
                        }
                        self.bounced[slot] = true;
                    }
                } else if matches!(kind, Kind::BeadYellow | Kind::BeadOrange) {
                    pos -= fn_vec * height;
                    vel = vel.slide(fn_vec);
                } else if profile.cutout || matches!(kind, Kind::Water | Kind::Snow | Kind::Glass) {
                    self.ticks[slot] = 0;
                }
            }
            self.velocity[slot] = vel;
            self.position[slot] = pos;
        }

        let mut expired = Vec::new();
        for idx in (0..self.active_slots.len()).rev() {
            let slot = self.active_slots[idx];
            if self.ticks[slot] <= 0 {
                self.ticks[slot] = 0;
                self.active_slots.remove(idx);
                self.free_slots.push(slot);
                expired.push(slot as i32);
            }
        }
        PackedInt32Array::from(expired.as_slice())
    }

    #[func]
    pub fn clear(&mut self) {
        self.ticks.fill(0);
        for b in &mut self.batches {
            b.visible_count = 0;
            b.prev_visible_count = 0;
        }
        self.active_slots.clear();
        self.free_slots.clear();
        for slot in (0..CAPACITY).rev() {
            self.free_slots.push(slot);
        }
        self.sim_dirty = false;
        self.last_draw_fraction = -1.0;
        self.last_active_mask = 0;
        self.rng = Pcg32::seeded(0x434d5232);
        self.style_rng = Pcg32::seeded(0x56524c32);
    }

    /// Writes only active instances (`0..visible_count`) directly to `RenderingServer`
    /// via `multimesh_instance_set_*`, skipping unchanged frames (e.g., 25 Hz stepped looks).
    /// Returns bitmask of batches with `visible_count > 0` in bits `0..30`, plus bit `31`
    /// set if any batch's `visible_count` changed since the previous draw.
    #[func]
    pub fn draw_to_rendering_server(&mut self, mut fraction: f32) -> i64 {
        let cfg = LOOKS[self.look];
        let snap = cfg.snap;
        if cfg.fraction_steps > 0 {
            let fs = cfg.fraction_steps as f32;
            fraction = (fraction * fs).ceil() / fs;
        }

        if !self.sim_dirty && (fraction - self.last_draw_fraction).abs() < 1e-6 {
            return self.last_active_mask;
        }

        for b in &mut self.batches {
            b.visible_count = 0;
        }

        let active_len = self.active_slots.len();
        if active_len > 0 {
            let mut rs = RenderingServer::singleton();
            for i in 0..active_len {
                let slot = self.active_slots[i];
                if self.visual_dirty[slot] {
                    self.update_particle_visual(slot);
                }

                let bid = self.batch_id[slot] as usize;
                if bid >= self.batches.len() {
                    continue;
                }

                let mut pos = self.previous[slot].lerp(self.position[slot], fraction);
                if snap > 0.0 {
                    pos = Vector3::new(
                        snapf(pos.x, snap),
                        snapf(pos.y, snap),
                        snapf(pos.z, snap),
                    );
                }

                let basis = self.visual_basis[slot];
                let col = self.visual_color[slot];
                let data = self.visual_data[slot];

                let batch = &mut self.batches[bid];
                let out_idx = batch.visible_count;
                if (out_idx as usize) >= CAPACITY {
                    continue;
                }
                if let Some(rid) = batch.rid
                    && rid.is_valid()
                {
                    rs.multimesh_instance_set_transform(rid, out_idx, Transform3D::new(basis, pos));
                    rs.multimesh_instance_set_color(rid, out_idx, col);
                    rs.multimesh_instance_set_custom_data(
                        rid,
                        out_idx,
                        Color::from_rgba(data[0], data[1], data[2], data[3]),
                    );
                }
                batch.visible_count += 1;
            }
        }

        let mut active_mask: i64 = 0;
        let mut vis_changed = false;
        for (bid, b) in self.batches.iter_mut().enumerate() {
            if b.visible_count > 0 && bid < 31 {
                active_mask |= 1i64 << bid;
            }
            if b.visible_count != b.prev_visible_count {
                b.prev_visible_count = b.visible_count;
                vis_changed = true;
            }
        }

        self.sim_dirty = false;
        self.last_draw_fraction = fraction;
        self.last_active_mask = active_mask;

        if vis_changed {
            active_mask | (1i64 << 31)
        } else {
            active_mask
        }
    }

    #[func]
    pub fn prepare_draw(&mut self, mut fraction: f32) {
        let cfg = LOOKS[self.look];
        let snap = cfg.snap;
        if cfg.fraction_steps > 0 {
            let fs = cfg.fraction_steps as f32;
            fraction = (fraction * fs).ceil() / fs;
        }

        for b in &mut self.batches {
            b.visible_count = 0;
        }

        let active_len = self.active_slots.len();
        for i in 0..active_len {
            let slot = self.active_slots[i];
            if self.visual_dirty[slot] {
                self.update_particle_visual(slot);
            }

            let bid = self.batch_id[slot] as usize;
            if bid >= self.batches.len() {
                continue;
            }

            let mut pos = self.previous[slot].lerp(self.position[slot], fraction);
            if snap > 0.0 {
                pos = Vector3::new(
                    snapf(pos.x, snap),
                    snapf(pos.y, snap),
                    snapf(pos.z, snap),
                );
            }

            let basis = self.visual_basis[slot];
            let col = self.visual_color[slot];
            let data = self.visual_data[slot];

            let batch = &mut self.batches[bid];
            let out_idx = batch.visible_count as usize;
            if out_idx >= CAPACITY {
                continue;
            }
            if batch.data.is_empty() {
                batch.data.resize(CAPACITY * INSTANCE_STRIDE_FLOATS, 0.0);
            }
            let base = out_idx * INSTANCE_STRIDE_FLOATS;
            let buf = &mut batch.data;

            // Transform3D row-major (3x4): [x.x, y.x, z.x, o.x,  x.y, y.y, z.y, o.y,  x.z, y.z, z.z, o.z]
            buf[base] = basis.rows[0].x;
            buf[base + 1] = basis.rows[0].y;
            buf[base + 2] = basis.rows[0].z;
            buf[base + 3] = pos.x;

            buf[base + 4] = basis.rows[1].x;
            buf[base + 5] = basis.rows[1].y;
            buf[base + 6] = basis.rows[1].z;
            buf[base + 7] = pos.y;

            buf[base + 8] = basis.rows[2].x;
            buf[base + 9] = basis.rows[2].y;
            buf[base + 10] = basis.rows[2].z;
            buf[base + 11] = pos.z;

            // Color
            buf[base + 12] = col.r;
            buf[base + 13] = col.g;
            buf[base + 14] = col.b;
            buf[base + 15] = col.a;

            // CustomData
            buf[base + 16] = data[0];
            buf[base + 17] = data[1];
            buf[base + 18] = data[2];
            buf[base + 19] = data[3];

            batch.visible_count += 1;
        }
    }

    #[func]
    pub fn get_batch_visible_count(&self, batch_id: i32) -> i32 {
        self.batches
            .get(batch_id as usize)
            .map_or(0, |b| b.visible_count)
    }

    #[func]
    pub fn get_batch_buffer(&self, batch_id: i32) -> PackedFloat32Array {
        if let Some(b) = self.batches.get(batch_id as usize) {
            PackedFloat32Array::from(b.data.as_slice())
        } else {
            PackedFloat32Array::new()
        }
    }

    #[func]
    pub fn generate_proc_sprite_rgba8(kind_name: GString, variant: i32) -> PackedByteArray {
        let kind_str = kind_name.to_string();
        let (size, bytes) = match kind_str.as_str() {
            "dot" => (128usize, proc_soft_dot(128, 1000 + variant)),
            "speck" => (16usize, proc_speck(16, 2000 + variant)),
            "square" => (16usize, proc_square(16, 2100 + variant)),
            "disc" => (16usize, proc_disc(16, 2200 + variant)),
            "leaf" => (32usize, proc_leaf(32, 3000 + variant)),
            _ => (64usize, proc_soft_dot(64, 4000 + variant)),
        };
        let _ = size;
        PackedByteArray::from(bytes.as_slice())
    }
}

impl RustWheelParticles {
    #[inline]
    fn dust_frame_for(&self, slot: usize) -> i32 {
        let age = self.max_ticks[slot] - self.ticks[slot];
        let frame = self.frame_offset[slot] + (age >> 1);
        if self.kind[slot] == Kind::SlipDust {
            frame.min(7)
        } else {
            frame % 8
        }
    }

    fn update_particle_visual(&mut self, slot: usize) {
        let cfg = LOOKS[self.look];
        let retro = self.look != 0;
        let kind = self.kind[slot];
        let profile = &PROFILES[kind as usize];
        let max_t = self.max_ticks[slot].max(1) as f32;
        let progress = 1.0 - (self.ticks[slot] as f32) / max_t;

        // Sprite frame
        let mut frame = if kind.is_dust() {
            self.dust_frame_for(slot)
        } else {
            0
        };
        if profile.frame_delay >= 0 {
            let age = self.max_ticks[slot] - self.ticks[slot];
            if age > profile.frame_delay {
                frame = (self.frame_offset[slot]
                    + ((age - profile.frame_delay) as f32 / profile.frame_ticks as f32) as i32)
                    % profile.frames;
            }
        } else if kind == Kind::Backfire {
            frame = self.max_ticks[slot] - self.ticks[slot];
        }

        // Size
        let mut size =
            lerpf(profile.size[0], profile.size[1], stepped(progress, cfg.size_steps))
                * self.size_factor[slot];
        size *= lerpf(0.6, 1.0, self.intensity[slot]);
        if kind.is_cloud() {
            size *= cfg.cloud_scale;
        } else if kind.is_debris() {
            size *= cfg.debris_scale;
        }
        if retro && kind == Kind::Backfire && frame % 2 == 1 {
            size *= 0.75;
        }

        let bead_spark = matches!(kind, Kind::BeadYellow | Kind::BeadOrange);
        let constant_alpha =
            profile.cutout || kind == Kind::SlipDust || (retro && kind == Kind::Backfire);
        let mut fade = 1.0;
        if bead_spark {
            fade = 1.0 - smoothstep(0.65, 1.0, progress);
        } else if !constant_alpha {
            fade = if cfg.alpha_steps <= 0 {
                1.0 - progress
            } else {
                let as_f = cfg.alpha_steps as f32;
                1.0 - (progress * as_f).floor() / as_f
            };
        }
        let opacity = profile.alpha * if self.is_gravel_dust[slot] { 1.6 } else { 1.0 };
        let alpha =
            (opacity * cfg.alpha_boost * fade * lerpf(0.5, 1.0, self.intensity[slot])).clamp(0.0, 1.0);

        let mut angle = self.angle[slot];
        if cfg.angle_steps > 0 {
            angle = snapf(angle, TAU / (cfg.angle_steps as f32));
        }

        let mut basis = Basis::IDENTITY;
        let vel = self.velocity[slot];
        if bead_spark && vel.length_squared() > 0.001 {
            let direction = vel.normalized();
            let up = if direction.y.abs() > 0.95 {
                Vector3::RIGHT
            } else {
                Vector3::UP
            };
            basis = Basis::looking_at_ex(direction).up(up).done()
                * Basis::from_axis_angle(Vector3::RIGHT, -FRAC_PI_2);
        }
        let mesh_scale = if bead_spark {
            Vector3::new(size * 0.285, size * 1.2375, size * 0.75)
        } else {
            Vector3::ONE * size
        };

        self.visual_basis[slot] = basis.scaled(mesh_scale);
        self.visual_color[slot] = self.particle_color(kind, profile.color, self.shade[slot], progress, alpha, &cfg);
        self.visual_data[slot] = [angle, frame as f32, 0.0, 0.0];
        self.visual_dirty[slot] = false;
    }

    fn particle_color(
        &self,
        kind: Kind,
        base_rgb: [f32; 3],
        shade: f32,
        progress: f32,
        alpha: f32,
        cfg: &LookConfig,
    ) -> Color {
        if matches!(kind, Kind::BeadYellow | Kind::BeadOrange) {
            return Color::from_rgba(base_rgb[0], base_rgb[1], base_rgb[2], alpha);
        }
        let mut rgb = base_rgb;
        if cfg.ramps
            && let Some(ramp) = ramp_for(kind)
        {
            let idx = ((progress * ramp.len() as f32) as usize).min(ramp.len() - 1);
            rgb = ramp[idx];
        }
        let graded = if self.look == 0 {
            rgb
        } else {
            let brightness = lerpf(1.0, shade, cfg.shade_var);
            let gray = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
            let mut r = (((gray + (rgb[0] - gray) * cfg.saturation) - 0.5) * cfg.contrast + 0.5) * brightness;
            let mut g = (((gray + (rgb[1] - gray) * cfg.saturation) - 0.5) * cfg.contrast + 0.5) * brightness;
            let mut b = (((gray + (rgb[2] - gray) * cfg.saturation) - 0.5) * cfg.contrast + 0.5) * brightness;
            r = r.clamp(0.0, 1.0);
            g = g.clamp(0.0, 1.0);
            b = b.clamp(0.0, 1.0);
            if cfg.color_bits < 8 {
                let levels = ((1i32 << cfg.color_bits) - 1) as f32;
                r = (r * levels).round() / levels;
                g = (g * levels).round() / levels;
                b = (b * levels).round() / levels;
            }
            [r, g, b]
        };
        Color::from_rgba(graded[0], graded[1], graded[2], alpha)
    }
}

#[inline]
fn f_to_u8(v: f32) -> u8 {
    (v.clamp(0.0, 1.0) * 255.0).round() as u8
}

#[allow(clippy::too_many_arguments)]
fn set_px(buf: &mut [u8], size: usize, x: usize, y: usize, r: f32, g: f32, b: f32, a: f32) {
    let idx = (y * size + x) * 4;
    buf[idx] = f_to_u8(r);
    buf[idx + 1] = f_to_u8(g);
    buf[idx + 2] = f_to_u8(b);
    buf[idx + 3] = f_to_u8(a);
}

fn proc_soft_dot(size: usize, seed: i32) -> Vec<u8> {
    let mut rng = Pcg32::seeded(seed as u64);
    let mut buf = vec![0u8; size * size * 4];
    let r = (size as f32) * 0.5;
    for y in 0..size {
        for x in 0..size {
            let dx = (x as f32 + 0.5) / r - 1.0;
            let dy = (y as f32 + 0.5) / r - 1.0;
            let d = (dx * dx + dy * dy).sqrt();
            let a = (1.0 - d).max(0.0).powf(1.6).clamp(0.0, 1.0) * rng.randf_range(0.92, 1.0);
            set_px(&mut buf, size, x, y, 1.0, 1.0, 1.0, a);
        }
    }
    buf
}

fn proc_speck(size: usize, seed: i32) -> Vec<u8> {
    let mut rng = Pcg32::seeded(seed as u64);
    let mut buf = vec![0u8; size * size * 4];
    let max_coord = (size - 1) as f32;
    let mut px = max_coord * 0.5;
    let mut py = max_coord * 0.5;
    for _ in 0..72 {
        px = (px + rng.randf_range(-1.6, 1.6)).clamp(0.0, max_coord);
        py = (py + rng.randf_range(-1.6, 1.6)).clamp(0.0, max_coord);
        let a = if rng.randf() < 0.72 { 1.0 } else { 0.55 };
        let ix = px as usize;
        let iy = py as usize;
        set_px(&mut buf, size, ix, iy, 1.0, 1.0, 1.0, a);
        if ix + 1 < size {
            set_px(&mut buf, size, ix + 1, iy, 1.0, 1.0, 1.0, a);
        }
    }
    buf
}

fn proc_square(size: usize, seed: i32) -> Vec<u8> {
    let mut buf = vec![255u8; size * size * 4];
    if seed % 2 == 1 {
        for x in 0..size {
            set_px(&mut buf, size, x, 0, 1.0, 1.0, 1.0, 0.0);
            set_px(&mut buf, size, x, size - 1, 1.0, 1.0, 1.0, 0.0);
        }
        for y in 0..size {
            set_px(&mut buf, size, 0, y, 1.0, 1.0, 1.0, 0.0);
            set_px(&mut buf, size, size - 1, y, 1.0, 1.0, 1.0, 0.0);
        }
    }
    buf
}

fn proc_disc(size: usize, seed: i32) -> Vec<u8> {
    let mut buf = vec![0u8; size * size * 4];
    let r = (size as f32) * 0.5 - if seed % 2 == 1 { 1.0 } else { 0.0 };
    let c = ((size - 1) as f32) * 0.5;
    for y in 0..size {
        for x in 0..size {
            let dx = x as f32 - c;
            let dy = y as f32 - c;
            if (dx * dx + dy * dy).sqrt() <= r {
                set_px(&mut buf, size, x, y, 1.0, 1.0, 1.0, 1.0);
            }
        }
    }
    buf
}

fn proc_leaf(size: usize, seed: i32) -> Vec<u8> {
    let mut rng = Pcg32::seeded(seed as u64);
    let mut buf = vec![0u8; size * size * 4];
    let strokes = if seed % 3 == 0 { 9 } else { 4 };
    let fsize = size as f32;
    for _ in 0..strokes {
        let x = rng.randf_range(3.0, fsize - 3.0);
        let y = rng.randf_range(3.0, fsize - 3.0);
        let dx = rng.randf_range(-1.0, 1.0);
        let dy = rng.randf_range(-1.0, 1.0);
        let length = rng.randi_range(3, 7);
        for i in 0..length {
            let ix = ((x + dx * i as f32) as i32).clamp(0, size as i32 - 1) as usize;
            let iy = ((y + dy * i as f32) as i32).clamp(0, size as i32 - 1) as usize;
            set_px(&mut buf, size, ix, iy, 1.0, 1.0, 1.0, 1.0);
        }
    }
    for _ in 0..12 {
        let ix = rng.randi_range(0, size as i32 - 1) as usize;
        let iy = rng.randi_range(0, size as i32 - 1) as usize;
        set_px(&mut buf, size, ix, iy, 1.0, 1.0, 1.0, 0.85);
    }
    buf
}
