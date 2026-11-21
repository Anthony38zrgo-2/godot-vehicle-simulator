use godot::builtin::{Color, PackedByteArray, Vector3, Vector4};
use godot::classes::RefCounted;
use godot::prelude::*;

#[inline]
fn lerpf(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[inline]
fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustGisSampler {
    grass_w: i32,
    grass_h: i32,
    grass_rgba8: Vec<u8>,
    grass_bounds: Vector4,

    snow_w: i32,
    snow_h: i32,
    snow_rgba8: Vec<u8>,
    snow_bounds: Vector4,

    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustGisSampler {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            grass_w: 0,
            grass_h: 0,
            grass_rgba8: Vec::new(),
            grass_bounds: Vector4::ZERO,
            snow_w: 0,
            snow_h: 0,
            snow_rgba8: Vec::new(),
            snow_bounds: Vector4::ZERO,
            base,
        }
    }
}

#[godot_api]
impl RustGisSampler {
    #[func]
    pub fn set_grass_gis(
        &mut self,
        width: i32,
        height: i32,
        rgba8_bytes: PackedByteArray,
        bounds: Vector4,
    ) {
        if width <= 0 || height <= 0 {
            self.grass_w = 0;
            self.grass_h = 0;
            self.grass_rgba8.clear();
            return;
        }
        let expected = (width as usize) * (height as usize) * 4;
        let src = rgba8_bytes.as_slice();
        if src.len() < expected {
            godot_error!("RustGisSampler::set_grass_gis buffer too small");
            return;
        }
        self.grass_w = width;
        self.grass_h = height;
        self.grass_rgba8.clear();
        self.grass_rgba8.extend_from_slice(&src[..expected]);
        self.grass_bounds = bounds;
    }

    #[func]
    pub fn set_snow_coverage(
        &mut self,
        width: i32,
        height: i32,
        rgba8_bytes: PackedByteArray,
        bounds: Vector4,
    ) {
        if width <= 0 || height <= 0 {
            self.snow_w = 0;
            self.snow_h = 0;
            self.snow_rgba8.clear();
            return;
        }
        let expected = (width as usize) * (height as usize) * 4;
        let src = rgba8_bytes.as_slice();
        if src.len() < expected {
            godot_error!("RustGisSampler::set_snow_coverage buffer too small");
            return;
        }
        self.snow_w = width;
        self.snow_h = height;
        self.snow_rgba8.clear();
        self.snow_rgba8.extend_from_slice(&src[..expected]);
        self.snow_bounds = bounds;
    }

    #[func]
    pub fn grass_gis_at(&self, point: Vector3) -> Color {
        let [r, g, b, a] = self.sample_grass_gis(point);
        Color::from_rgba(r, g, b, a)
    }

    #[func]
    pub fn snow_coverage_at(&self, point: Vector3) -> f32 {
        self.sample_snow(point)
    }
}

impl RustGisSampler {
    #[inline]
    pub fn has_grass(&self) -> bool {
        self.grass_w > 0 && self.grass_h > 0 && !self.grass_rgba8.is_empty()
    }

    #[inline]
    pub fn has_snow(&self) -> bool {
        self.snow_w > 0 && self.snow_h > 0 && !self.snow_rgba8.is_empty()
    }

    #[inline]
    pub fn sample_grass_gis(&self, point: Vector3) -> [f32; 4] {
        if !self.has_grass() || self.grass_bounds.z <= 0.0 || self.grass_bounds.w <= 0.0 {
            return [0.45, 0.06, 0.15, 0.0];
        }
        let uvx = (point.x - self.grass_bounds.x) / self.grass_bounds.z;
        let uvy = (point.z - self.grass_bounds.y) / self.grass_bounds.w;
        let edge_m = (uvx.min(1.0 - uvx) * self.grass_bounds.z)
            .min(uvy.min(1.0 - uvy) * self.grass_bounds.w);
        if edge_m <= 0.0 {
            return [0.45, 0.06, 0.15, 0.0];
        }
        let tx = uvx * (self.grass_w as f32) - 0.5;
        let ty = uvy * (self.grass_h as f32) - 0.5;
        let bx = tx.floor();
        let by = ty.floor();
        let fx = tx - bx;
        let fy = ty - by;
        let ax = (bx as i32).clamp(0, self.grass_w - 1) as usize;
        let ay = (by as i32).clamp(0, self.grass_h - 1) as usize;
        let cx = ((bx as i32) + 1).clamp(0, self.grass_w - 1) as usize;
        let cy = ((by as i32) + 1).clamp(0, self.grass_h - 1) as usize;

        let w = self.grass_w as usize;
        let p00 = pixel_rgba(&self.grass_rgba8, w, ax, ay);
        let p10 = pixel_rgba(&self.grass_rgba8, w, cx, ay);
        let p01 = pixel_rgba(&self.grass_rgba8, w, ax, cy);
        let p11 = pixel_rgba(&self.grass_rgba8, w, cx, cy);

        let r = lerpf(lerpf(p00[0], p10[0], fx), lerpf(p01[0], p11[0], fx), fy);
        let g = lerpf(lerpf(p00[1], p10[1], fx), lerpf(p01[1], p11[1], fx), fy);
        let b = lerpf(lerpf(p00[2], p10[2], fx), lerpf(p01[2], p11[2], fx), fy);
        let a = smoothstep(0.0, 180.0, edge_m);
        [r, g, b, a]
    }

    #[inline]
    pub fn sample_snow(&self, point: Vector3) -> f32 {
        if !self.has_snow() || self.snow_bounds.z <= 0.0 || self.snow_bounds.w <= 0.0 {
            return 0.0;
        }
        let uvx = (point.x - self.snow_bounds.x) / self.snow_bounds.z;
        let uvy = (point.z - self.snow_bounds.y) / self.snow_bounds.w;
        let edge = uvx.min(uvy).min((1.0 - uvx).min(1.0 - uvy));
        if edge <= 0.0 {
            return 0.0;
        }
        let tx = uvx * (self.snow_w as f32) - 0.5;
        let ty = uvy * (self.snow_h as f32) - 0.5;
        let bx = tx.floor();
        let by = ty.floor();
        let fx = tx - bx;
        let fy = ty - by;
        let ax = (bx as i32).clamp(0, self.snow_w - 1) as usize;
        let ay = (by as i32).clamp(0, self.snow_h - 1) as usize;
        let cx = ((bx as i32) + 1).clamp(0, self.snow_w - 1) as usize;
        let cy = ((by as i32) + 1).clamp(0, self.snow_h - 1) as usize;

        let w = self.snow_w as usize;
        let r00 = self.snow_rgba8[(ay * w + ax) * 4] as f32 / 255.0;
        let r10 = self.snow_rgba8[(ay * w + cx) * 4] as f32 / 255.0;
        let r01 = self.snow_rgba8[(cy * w + ax) * 4] as f32 / 255.0;
        let r11 = self.snow_rgba8[(cy * w + cx) * 4] as f32 / 255.0;

        let top = lerpf(r00, r10, fx);
        let bottom = lerpf(r01, r11, fx);
        lerpf(top, bottom, fy) * smoothstep(0.0, 0.025, edge)
    }
}

#[inline]
fn pixel_rgba(buf: &[u8], w: usize, x: usize, y: usize) -> [f32; 4] {
    let idx = (y * w + x) * 4;
    [
        buf[idx] as f32 / 255.0,
        buf[idx + 1] as f32 / 255.0,
        buf[idx + 2] as f32 / 255.0,
        buf[idx + 3] as f32 / 255.0,
    ]
}
