use std::collections::HashMap;

use godot::builtin::{
    PackedByteArray, PackedFloat32Array, PackedInt32Array, PackedVector2Array, PackedVector3Array,
    Vector2, Vector3,
};
use godot::classes::RefCounted;
use godot::prelude::*;

const BUCKET_CELL_M: f32 = 16.0;
const WATER_GRIP_DEPTH_SATURATION_MM: f32 = 12.0;
const WATER_DRAG_MAX_LOAD_FRACTION: f32 = 0.8125;

#[inline]
fn lerpf(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[inline]
fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

struct MaskData {
    width: i32,
    height: i32,
    red: Vec<u8>,
}

struct PuddlePatch {
    inv_bx: Vector3,
    inv_by: Vector3,
    inv_bz: Vector3,
    inv_origin: Vector3,
    size: Vector2,
    uv_scale: Vector2,
    shape_params: [f32; 4],
    depth_mm: f32,
    drag: f32,
    fill: f32,
    mask_id: i32,
}

impl PuddlePatch {
    #[inline]
    fn inv_xform(&self, p: Vector3) -> Vector3 {
        // Affine transform: basis * p + origin
        Vector3::new(
            self.inv_bx.x * p.x + self.inv_by.x * p.y + self.inv_bz.x * p.z + self.inv_origin.x,
            self.inv_bx.y * p.x + self.inv_by.y * p.y + self.inv_bz.y * p.z + self.inv_origin.y,
            self.inv_bx.z * p.x + self.inv_by.z * p.y + self.inv_bz.z * p.z + self.inv_origin.z,
        )
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustPuddleField {
    masks: HashMap<i32, MaskData>,
    patches: Vec<PuddlePatch>,
    buckets: HashMap<(i32, i32), Vec<usize>>,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustPuddleField {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            masks: HashMap::new(),
            patches: Vec::new(),
            buckets: HashMap::new(),
            base,
        }
    }
}

#[godot_api]
impl RustPuddleField {
    #[func]
    pub fn register_mask(
        &mut self,
        mask_id: i32,
        width: i32,
        height: i32,
        rgba8_bytes: PackedByteArray,
    ) {
        if width <= 0 || height <= 0 {
            return;
        }
        let expected_rgba = (width as usize) * (height as usize) * 4;
        let expected_r8 = (width as usize) * (height as usize);
        let src = rgba8_bytes.as_slice();
        let mut red = Vec::with_capacity(expected_r8);
        if src.len() >= expected_rgba {
            for i in 0..expected_r8 {
                red.push(src[i * 4]);
            }
        } else if src.len() >= expected_r8 {
            red.extend_from_slice(&src[..expected_r8]);
        } else {
            return;
        }
        self.masks.insert(
            mask_id,
            MaskData {
                width,
                height,
                red,
            },
        );
    }

    #[func]
    pub fn clear_patches(&mut self) {
        self.patches.clear();
        self.buckets.clear();
    }

    #[func]
    #[allow(clippy::too_many_arguments)]
    pub fn set_patches(
        &mut self,
        inv_bx: PackedVector3Array,
        inv_by: PackedVector3Array,
        inv_bz: PackedVector3Array,
        inv_origins: PackedVector3Array,
        world_centers: PackedVector3Array,
        sizes: PackedVector2Array,
        uv_scales: PackedVector2Array,
        shape_params: PackedFloat32Array,
        max_depths_mm: PackedFloat32Array,
        drags: PackedFloat32Array,
        mask_ids: PackedInt32Array,
        fills: PackedFloat32Array,
    ) {
        self.patches.clear();
        self.buckets.clear();

        let n = world_centers.len();
        if inv_bx.len() != n
            || inv_by.len() != n
            || inv_bz.len() != n
            || inv_origins.len() != n
            || sizes.len() != n
            || uv_scales.len() != n
            || shape_params.len() != n * 4
            || max_depths_mm.len() != n
            || drags.len() != n
            || mask_ids.len() != n
            || fills.len() != n
        {
            godot_error!("RustPuddleField::set_patches array length mismatch");
            return;
        }

        let bx_s = inv_bx.as_slice();
        let by_s = inv_by.as_slice();
        let bz_s = inv_bz.as_slice();
        let org_s = inv_origins.as_slice();
        let ctr_s = world_centers.as_slice();
        let sz_s = sizes.as_slice();
        let uvs_s = uv_scales.as_slice();
        let sp_s = shape_params.as_slice();
        let dp_s = max_depths_mm.as_slice();
        let dr_s = drags.as_slice();
        let mk_s = mask_ids.as_slice();
        let fl_s = fills.as_slice();

        self.patches.reserve(n);
        for i in 0..n {
            let size = sz_s[i];
            self.patches.push(PuddlePatch {
                inv_bx: bx_s[i],
                inv_by: by_s[i],
                inv_bz: bz_s[i],
                inv_origin: org_s[i],
                size,
                uv_scale: uvs_s[i],
                shape_params: [sp_s[i * 4], sp_s[i * 4 + 1], sp_s[i * 4 + 2], sp_s[i * 4 + 3]],
                depth_mm: dp_s[i],
                drag: dr_s[i],
                fill: fl_s[i],
                mask_id: mk_s[i],
            });

            let center = ctr_s[i];
            let radius = size.length() * 0.55;
            let min_cx = ((center.x - radius) / BUCKET_CELL_M).floor() as i32;
            let max_cx = ((center.x + radius) / BUCKET_CELL_M).floor() as i32;
            let min_cz = ((center.z - radius) / BUCKET_CELL_M).floor() as i32;
            let max_cz = ((center.z + radius) / BUCKET_CELL_M).floor() as i32;
            for x in min_cx..=max_cx {
                for z in min_cz..=max_cz {
                    self.buckets.entry((x, z)).or_default().push(i);
                }
            }
        }
    }

    #[func]
    pub fn update_fills(&mut self, fills: PackedFloat32Array) {
        let f_slice = fills.as_slice();
        for (patch, &fill) in self.patches.iter_mut().zip(f_slice.iter()) {
            patch.fill = fill;
        }
    }

    /// Returns `[depth_mm, drag, fill, max_depth_mm, patch_index_f32]` (`-1.0` if none).
    #[func]
    pub fn sample_contact_packed(&self, pos: Vector3) -> PackedFloat32Array {
        let res = self.sample_single(pos);
        PackedFloat32Array::from(&res[..])
    }

    /// Batch query for 4 wheels in a single ABI call.
    /// `loaded_mask` is bitmask `(1 << wheel_idx)`.
    /// Returns 8 floats: `[depth0, drag0, depth1, drag1, depth2, drag2, depth3, drag3]`.
    #[func]
    pub fn sample_4wheels(
        &self,
        positions: PackedVector3Array,
        loaded_mask: i32,
    ) -> PackedFloat32Array {
        let mut out = [0.0f32; 8];
        let pos_s = positions.as_slice();
        let count = pos_s.len().min(4);
        for i in 0..count {
            if (loaded_mask & (1 << i)) == 0 {
                continue;
            }
            let res = self.sample_single(pos_s[i]);
            out[i * 2] = res[0];
            out[i * 2 + 1] = res[1];
        }
        PackedFloat32Array::from(&out[..])
    }

    #[func]
    pub fn mask_at_static(uv: Vector2, sp_x: f32, sp_y: f32, sp_z: f32, sp_w: f32) -> f32 {
        mask_at_impl(uv, [sp_x, sp_y, sp_z, sp_w])
    }

    #[func]
    pub fn compute_route_topography_packed(route_pts: PackedVector3Array) -> PackedFloat32Array {
        let pts = route_pts.as_slice();
        let n = pts.len();
        let mut out = Vec::with_capacity(n * 4);
        if n == 0 {
            return PackedFloat32Array::new();
        }
        if n < 3 {
            for _ in 0..n {
                out.extend_from_slice(&[0.0, 0.0, 0.0, 1.0]);
            }
            return PackedFloat32Array::from(out.as_slice());
        }
        let w = (n / 90).clamp(1, 4);
        for i in 0..n {
            let i_prev = i.saturating_sub(w);
            let i_next = (i + w).min(n - 1);
            let p_prev = pts[i_prev];
            let p_curr = pts[i];
            let p_next = pts[i_next];

            let v_prev = p_curr - p_prev;
            let v_next = p_next - p_curr;
            let d_prev_xz = (v_prev.x * v_prev.x + v_prev.z * v_prev.z).sqrt().max(0.5);
            let d_next_xz = (v_next.x * v_next.x + v_next.z * v_next.z).sqrt().max(0.5);

            let slope_prev = v_prev.y / d_prev_xz;
            let slope_next = v_next.y / d_next_xz;
            let slope = 0.5 * (slope_prev + slope_next);
            let concavity = slope_next - slope_prev;

            let f_prev_v = Vector3::new(v_prev.x, 0.0, v_prev.z);
            let f_prev = if f_prev_v.length_squared() < 0.1 {
                Vector3::FORWARD
            } else {
                f_prev_v.normalized()
            };
            let f_next_v = Vector3::new(v_next.x, 0.0, v_next.z);
            let f_next = if f_next_v.length_squared() < 0.1 {
                f_prev
            } else {
                f_next_v.normalized()
            };
            let right_prev = f_prev.cross(Vector3::UP).normalized();
            let turn_signed = f_next.dot(right_prev);

            let slope_factor = (1.0 - slope.abs() / 0.12).clamp(0.0, 1.0);
            let mut valley_boost = (1.0 + concavity * 14.0).clamp(0.0, 1.65);
            if concavity < -0.025 {
                valley_boost = 0.05;
            }
            let twi = (slope_factor * valley_boost).clamp(0.0, 1.5);
            out.extend_from_slice(&[slope, concavity, turn_signed, twi]);
        }
        PackedFloat32Array::from(out.as_slice())
    }

    #[func]
    #[allow(clippy::too_many_arguments)]
    pub fn contact_response_packed(
        depth_mm: f32,
        speed: f32,
        evac_speed: f32,
        load_n: f32,
        width: f32,
        drag_scale: f32,
        delta_depth_s: f32,
        wheel_radius: f32,
    ) -> PackedFloat32Array {
        let out = contact_response_impl(
            depth_mm,
            speed,
            evac_speed,
            load_n,
            width,
            drag_scale,
            delta_depth_s,
            wheel_radius,
        );
        PackedFloat32Array::from(&out[..])
    }
}

impl RustPuddleField {
    #[inline]
    fn sample_single(&self, pos: Vector3) -> [f32; 5] {
        let mut best_depth = 0.0f32;
        let mut best_drag = 0.0f32;
        let mut best_fill = 0.0f32;
        let mut best_max_depth = 0.0f32;
        let mut best_idx = -1.0f32;

        let cx = (pos.x / BUCKET_CELL_M).floor() as i32;
        let cz = (pos.z / BUCKET_CELL_M).floor() as i32;
        let Some(indices) = self.buckets.get(&(cx, cz)) else {
            return [0.0, 0.0, 0.0, 0.0, -1.0];
        };

        for &idx in indices {
            let patch = &self.patches[idx];
            if patch.fill <= 0.001 {
                continue;
            }
            let local = patch.inv_xform(pos);
            if local.y.abs() > 0.20 {
                continue;
            }
            let uv = Vector2::new(local.x / patch.size.x, local.z / patch.size.y);
            let mask = if let Some(img) = self.masks.get(&patch.mask_id) {
                sample_image_mask_impl(img, uv, patch.uv_scale)
            } else {
                mask_at_impl(uv, patch.shape_params)
            };
            if mask <= 0.18 {
                continue;
            }
            let water_mask = ((mask - 0.18) / 0.82).clamp(0.0, 1.0);
            let depth = water_mask * patch.fill * patch.depth_mm;
            if depth > best_depth {
                best_depth = depth;
                best_drag = patch.drag;
                best_fill = patch.fill;
                best_max_depth = patch.depth_mm;
                best_idx = idx as f32;
            }
        }
        [best_depth, best_drag, best_fill, best_max_depth, best_idx]
    }
}

#[inline]
fn mask_at_impl(uv: Vector2, sp: [f32; 4]) -> f32 {
    let mut px = uv.x * 2.0;
    let py = uv.y * 2.0;
    px += (py * 0.20) * sp[1];
    px *= 1.0 + py * 0.15 * sp[0];
    let phase = sp[3];
    let w1 = (py * 2.2 + phase).sin() * 0.08 * sp[2];
    let w2 = (px * 2.0 + phase * 1.2).cos() * 0.08 * sp[2];
    let wx = px + w1;
    let wy = py + w2;
    let r = (wx * wx + wy * wy).sqrt();
    let theta = wy.atan2(wx);
    let r_bound = 0.86 + 0.05 * (2.0 * theta + phase).sin();
    (1.0 - (r / r_bound)).clamp(0.0, 1.0)
}

#[inline]
fn sample_image_mask_impl(img: &MaskData, uv: Vector2, uv_scale: Vector2) -> f32 {
    let mx = uv.x * uv_scale.x + 0.5;
    let my = uv.y * uv_scale.y + 0.5;
    if !(0.0..=1.0).contains(&mx) || !(0.0..=1.0).contains(&my) {
        return 0.0;
    }
    let px = ((mx * (img.width - 1) as f32) as i32).clamp(0, img.width - 1) as usize;
    let py = ((my * (img.height - 1) as f32) as i32).clamp(0, img.height - 1) as usize;
    (img.red[py * (img.width as usize) + px] as f32) / 255.0
}

#[inline]
#[allow(clippy::too_many_arguments)]
fn contact_response_impl(
    depth_mm: f32,
    speed: f32,
    evac_speed_in: f32,
    load_n: f32,
    width: f32,
    drag_scale: f32,
    delta_depth_s: f32,
    wheel_radius: f32,
) -> [f32; 9] {
    if depth_mm <= 0.001 || speed.abs() <= 0.001 {
        return [1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    }
    let abs_speed = speed.abs();
    let evac_speed = evac_speed_in.max(0.1);
    let wet_factor = ((evac_speed - 16.0) / 12.0).clamp(0.0, 1.0);
    let risk = smoothstep(evac_speed * 0.60, evac_speed * 1.30, abs_speed)
        * smoothstep(1.5, WATER_GRIP_DEPTH_SATURATION_MM, depth_mm);

    let support_long = 1.0 - risk * lerpf(0.80, 0.55, wet_factor);
    let support_lat = 1.0 - risk * lerpf(0.94, 0.75, wet_factor);
    let support = support_long.min(support_lat);

    let continuous_drag = (150.0 * abs_speed + 2750.0 * abs_speed * abs_speed)
        * width
        * depth_mm
        * 0.001
        * drag_scale;

    let mut slam_drag = 0.0f32;
    if delta_depth_s > 0.0 {
        slam_drag = 22.5 * width * delta_depth_s.min(200.0) * abs_speed * drag_scale;
        slam_drag = slam_drag.min(load_n * 0.3125);
    }

    let max_drag = load_n * WATER_DRAG_MAX_LOAD_FRACTION;
    let total_drag = (continuous_drag + slam_drag).min(max_drag);
    let wheel_torque_nm = total_drag * 0.75 * wheel_radius;
    let steering_pull_nm = total_drag * 0.07;
    let vertical_dip_m = (depth_mm * 0.001 * 0.45).clamp(0.0, 0.018);

    [
        support,
        support_long,
        support_lat,
        total_drag,
        slam_drag,
        continuous_drag,
        wheel_torque_nm,
        steering_pull_nm,
        vertical_dip_m,
    ]
}
