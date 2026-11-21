use std::collections::HashMap;

use godot::builtin::{
    PackedFloat32Array, PackedVector2Array, PackedVector3Array, Vector2, Vector3,
};
use godot::classes::RefCounted;
use godot::prelude::*;

const BUCKET_CELL_M: f32 = 8.0;

struct RiverChannelData {
    active: bool,
    min_x: f32,
    min_z: f32,
    max_x: f32,
    max_z: f32,
    base_cx: f32,
    base_cz: f32,
    base_b0: f32,
    base_gx: f32,
    base_gz: f32,
    drag_scale: f32,
    rise_m: f32,
    tris: Vec<[Vector2; 3]>,
    buckets: HashMap<(i32, i32), Vec<usize>>,
}

impl RiverChannelData {
    #[inline]
    fn surface_level_at(&self, x: f32, z: f32) -> f32 {
        self.base_b0
            + self.base_gx * (x - self.base_cx)
            + self.base_gz * (z - self.base_cz)
            + self.rise_m
    }

    #[inline]
    fn inside_coverage(&self, x: f32, z: f32) -> bool {
        if x < self.min_x || x > self.max_x || z < self.min_z || z > self.max_z {
            return false;
        }
        if self.buckets.is_empty() {
            return true;
        }
        let key = (
            (x / BUCKET_CELL_M).floor() as i32,
            (z / BUCKET_CELL_M).floor() as i32,
        );
        let Some(tri_indices) = self.buckets.get(&key) else {
            return false;
        };
        let p = Vector2::new(x, z);
        for &ti in tri_indices {
            let tri = &self.tris[ti];
            if point_in_tri(p, tri[0], tri[1], tri[2]) {
                return true;
            }
        }
        false
    }
}

#[inline]
fn point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool {
    let d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
    if d.abs() < 1e-7 {
        return false;
    }
    let l1 = ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / d;
    let l2 = ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / d;
    let l3 = 1.0 - l1 - l2;
    l1 >= -0.001 && l2 >= -0.001 && l3 >= -0.001
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustRiverChannels {
    channels: Vec<RiverChannelData>,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustRiverChannels {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            channels: Vec::new(),
            base,
        }
    }
}

#[godot_api]
impl RustRiverChannels {
    #[func]
    pub fn clear(&mut self) {
        self.channels.clear();
    }

    #[func]
    #[allow(clippy::too_many_arguments)]
    pub fn add_channel(
        &mut self,
        active: bool,
        min_x: f32,
        min_z: f32,
        max_x: f32,
        max_z: f32,
        base_cx: f32,
        base_cz: f32,
        base_b0: f32,
        base_gx: f32,
        base_gz: f32,
        drag_scale: f32,
        rise_m: f32,
        tri_verts_2d: PackedVector2Array,
    ) -> i32 {
        let v_slice = tri_verts_2d.as_slice();
        let tri_count = v_slice.len() / 3;
        let mut tris = Vec::with_capacity(tri_count);
        let mut buckets: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
        for ti in 0..tri_count {
            let a = v_slice[ti * 3];
            let b = v_slice[ti * 3 + 1];
            let c = v_slice[ti * 3 + 2];
            tris.push([a, b, c]);

            let minx = a.x.min(b.x).min(c.x);
            let maxx = a.x.max(b.x).max(c.x);
            let minz = a.y.min(b.y).min(c.y);
            let maxz = a.y.max(b.y).max(c.y);
            let cx0 = (minx / BUCKET_CELL_M).floor() as i32;
            let cx1 = (maxx / BUCKET_CELL_M).floor() as i32;
            let cz0 = (minz / BUCKET_CELL_M).floor() as i32;
            let cz1 = (maxz / BUCKET_CELL_M).floor() as i32;
            for cx in cx0..=cx1 {
                for cz in cz0..=cz1 {
                    buckets.entry((cx, cz)).or_default().push(ti);
                }
            }
        }
        let idx = self.channels.len() as i32;
        self.channels.push(RiverChannelData {
            active,
            min_x,
            min_z,
            max_x,
            max_z,
            base_cx,
            base_cz,
            base_b0,
            base_gx,
            base_gz,
            drag_scale,
            rise_m,
            tris,
            buckets,
        });
        idx
    }

    #[func]
    pub fn update_rises(&mut self, rises: PackedFloat32Array) {
        let r_slice = rises.as_slice();
        for (ch, &rise) in self.channels.iter_mut().zip(r_slice.iter()) {
            ch.rise_m = rise;
        }
    }

    #[func]
    pub fn set_channel_active(&mut self, idx: i32, active: bool) {
        if let Some(ch) = self.channels.get_mut(idx as usize) {
            ch.active = active;
        }
    }

    /// Least-squares plane fit over water mesh vertices.
    /// Returns `[cx, cz, cy, gx, gz, ymin, ymax, auto_minx, auto_minz, auto_maxx, auto_maxz]`.
    #[func]
    pub fn fit_base_plane_pts(pts: PackedVector3Array) -> PackedFloat32Array {
        let s = pts.as_slice();
        if s.is_empty() {
            return PackedFloat32Array::new();
        }
        let mut ymin = f32::INFINITY;
        let mut ymax = f32::NEG_INFINITY;
        let mut min_x = f32::INFINITY;
        let mut min_z = f32::INFINITY;
        let mut max_x = f32::NEG_INFINITY;
        let mut max_z = f32::NEG_INFINITY;
        let mut sum_x = 0.0f64;
        let mut sum_z = 0.0f64;
        let mut sum_y = 0.0f64;
        for &p in s {
            ymin = ymin.min(p.y);
            ymax = ymax.max(p.y);
            min_x = min_x.min(p.x);
            min_z = min_z.min(p.z);
            max_x = max_x.max(p.x);
            max_z = max_z.max(p.z);
            sum_x += p.x as f64;
            sum_z += p.z as f64;
            sum_y += p.y as f64;
        }
        let inv_n = 1.0 / (s.len() as f64);
        let cx = sum_x * inv_n;
        let cz = sum_z * inv_n;
        let cy = sum_y * inv_n;

        let mut sxx = 0.0f64;
        let mut sxz = 0.0f64;
        let mut szz = 0.0f64;
        let mut sxy = 0.0f64;
        let mut szy = 0.0f64;
        for &p in s {
            let dx = (p.x as f64) - cx;
            let dz = (p.z as f64) - cz;
            let dy = (p.y as f64) - cy;
            sxx += dx * dx;
            sxz += dx * dz;
            szz += dz * dz;
            sxy += dx * dy;
            szy += dz * dy;
        }
        let det = sxx * szz - sxz * sxz;
        let mut gx = 0.0f32;
        let mut gz = 0.0f32;
        if det.abs() > 1e-6 {
            gx = ((sxy * szz - szy * sxz) / det) as f32;
            gz = ((sxx * szy - sxz * sxy) / det) as f32;
        }
        gx = gx.clamp(-0.25, 0.25);
        gz = gz.clamp(-0.25, 0.25);
        PackedFloat32Array::from(
            &[
                cx as f32, cz as f32, cy as f32, gx, gz, ymin, ymax, min_x, min_z, max_x, max_z,
            ][..],
        )
    }

    /// Returns `[depth_mm, surface_y, drag_scale, channel_idx_f32]` (`-1.0` if none).
    #[func]
    pub fn sample_contact_packed(&self, pos: Vector3) -> PackedFloat32Array {
        let res = self.sample_single(pos);
        PackedFloat32Array::from(&res[..])
    }

    /// Batch query for 4 wheels in ONE ABI call.
    /// Returns 16 floats: `[depth_mm, surface_y, drag_scale, channel_idx_f32]` x 4.
    #[func]
    pub fn sample_4wheels(
        &self,
        positions: PackedVector3Array,
        loaded_mask: i32,
    ) -> PackedFloat32Array {
        let mut out = [0.0f32; 16];
        for i in 0..4 {
            out[i * 4 + 1] = f32::NEG_INFINITY;
            out[i * 4 + 3] = -1.0;
        }
        let pos_s = positions.as_slice();
        let count = pos_s.len().min(4);
        for i in 0..count {
            if (loaded_mask & (1 << i)) == 0 {
                continue;
            }
            let res = self.sample_single(pos_s[i]);
            out[i * 4] = res[0];
            out[i * 4 + 1] = res[1];
            out[i * 4 + 2] = res[2];
            out[i * 4 + 3] = res[3];
        }
        PackedFloat32Array::from(&out[..])
    }
}

impl RustRiverChannels {
    #[inline]
    fn sample_single(&self, pos: Vector3) -> [f32; 4] {
        let mut best_depth = 0.0f32;
        let mut best_surface_y = f32::NEG_INFINITY;
        let mut best_drag = 0.0f32;
        let mut best_ch = -1.0f32;

        for (idx, ch) in self.channels.iter().enumerate() {
            if !ch.active {
                continue;
            }
            if !ch.inside_coverage(pos.x, pos.z) {
                continue;
            }
            let surface_y = ch.surface_level_at(pos.x, pos.z);
            let depth = ((surface_y - pos.y) * 1000.0).max(0.0);
            if depth > best_depth {
                best_depth = depth;
                best_surface_y = surface_y;
                best_drag = ch.drag_scale;
                best_ch = idx as f32;
            }
        }
        [best_depth, best_surface_y, best_drag, best_ch]
    }
}
