use std::collections::{BTreeMap, HashMap};
use std::f32::consts::TAU;

use godot::builtin::{
    Aabb, Basis, PackedByteArray, PackedFloat32Array, PackedInt32Array, PackedVector3Array,
    Quaternion, Transform3D, Vector2, Vector3,
};
use godot::classes::RefCounted;
use godot::prelude::*;

use crate::rng::Pcg32;
use crate::spatial_gis::RustGisSampler;

const ARC_TABLE_STEP: f64 = 1.0;

#[inline]
fn lerpf(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[inline]
fn lerpf64(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

#[inline]
fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[inline]
fn value_noise_hash(ix: i64, iz: i64) -> f64 {
    let mut h = ix
        .wrapping_mul(374_761_393)
        .wrapping_add(iz.wrapping_mul(668_265_263));
    h = (h ^ (h >> 13)).wrapping_mul(1_274_126_177);
    let v = (h ^ (h >> 16)) & 0x00FF_FFFF;
    (v as f64) / 16_777_215.0
}

#[inline]
fn value_noise(x: f64, z: f64) -> f64 {
    let cell_x = x.floor();
    let cell_z = z.floor();
    let frac_x = x - cell_x;
    let frac_z = z - cell_z;
    let smooth_x = frac_x * frac_x * (3.0 - 2.0 * frac_x);
    let smooth_z = frac_z * frac_z * (3.0 - 2.0 * frac_z);
    let ix = cell_x as i64;
    let iz = cell_z as i64;
    let v00 = value_noise_hash(ix, iz);
    let v10 = value_noise_hash(ix + 1, iz);
    let v01 = value_noise_hash(ix, iz + 1);
    let v11 = value_noise_hash(ix + 1, iz + 1);
    let top = lerpf64(v00, v10, smooth_x);
    let bottom = lerpf64(v01, v11, smooth_x);
    lerpf64(top, bottom, smooth_z)
}

#[derive(Clone, Copy)]
struct VariantInfo {
    weight: f32,
    scale_min: f32,
    scale_max: f32,
    mesh_height: f32,
    height_norm: f32,
    has_snow: bool,
    aabb_pos: Vector3,
    aabb_size: Vector3,
}

#[derive(Clone, Copy)]
struct ParkingSite {
    point: Vector3,
    forward: Vector3,
    right: Vector3,
    length: f32,
    width: f32,
}

#[derive(Clone, Copy)]
struct SectorEntry {
    min_x: f32,
    min_z: f32,
    max_x: f32,
    max_z: f32,
}

struct BucketData {
    buffer: Vec<f32>,
    billboard_aabb: Option<Aabb>,
    bush_colliders: Vec<f32>,
}

impl BucketData {
    fn new() -> Self {
        Self {
            buffer: Vec::new(),
            billboard_aabb: None,
            bush_colliders: Vec::new(),
        }
    }
}

#[derive(Clone, Copy)]
struct PendingParent {
    base: Vector3,
    arc_sector: i32,
    density: f32,
}

#[derive(Clone, Copy)]
struct PendingDaughter {
    base: Vector3,
    arc_sector: i32,
    density: f32,
    parent_y: f32,
    parent_group: i32,
    radial_frac: f32,
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustStageGrassPlanner {
    route: Vec<Vector3>,
    cumulative: Vec<f64>,
    total_length: f64,
    arc_table: Vec<usize>,
    bins: Vec<(f32, f32)>,
    rng: Pcg32,

    budget: i32,
    max_attempts: i32,
    attempts: i32,
    placed: i32,
    clusters: i32,
    snow_skipped: i32,
    snow_placed: i32,
    gis_skipped: i32,
    min_height_m: f32,
    max_height_m: f32,
    min_delta_m: f32,
    max_delta_m: f32,

    density_floor: f32,
    instance_scale: f32,
    outer_offset_scale: f32,
    side_bias_strength: f32,
    spacing_m: f32,
    reservation_radius: f32,
    max_tilt_degrees: f32,
    terrain_clearance: f32,
    sector_length: f32,
    min_surface_up: f32,
    node_inv_xform: Transform3D,

    cluster_scatter: bool,
    use_grass_gis: bool,
    use_snow_coverage: bool,
    face_camera: bool,
    outline_bush_cards: bool,
    collidable_bushes: bool,
    variant_group_size: i32,

    variants: Vec<VariantInfo>,
    gis_sampler: Option<Gd<RustGisSampler>>,
    parking: Vec<ParkingSite>,
    reserved_grid: HashMap<(i32, i32), Vec<Vector2>>,
    spacing_cells: HashMap<(i32, i32), Vector2>,

    sector_cell_m: f32,
    sectors: Vec<SectorEntry>,
    sector_grid: HashMap<(i32, i32), i32>,

    pending_parents: Vec<PendingParent>,
    pending_daughters: Vec<PendingDaughter>,

    buckets: BTreeMap<(i32, i32), BucketData>,
    ordered_buckets: Vec<(i32, i32)>,

    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustStageGrassPlanner {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            route: Vec::new(),
            cumulative: Vec::new(),
            total_length: 0.0,
            arc_table: Vec::new(),
            bins: Vec::new(),
            rng: Pcg32::seeded(1),
            budget: 0,
            max_attempts: 0,
            attempts: 0,
            placed: 0,
            clusters: 0,
            snow_skipped: 0,
            snow_placed: 0,
            gis_skipped: 0,
            min_height_m: f32::INFINITY,
            max_height_m: 0.0,
            min_delta_m: f32::INFINITY,
            max_delta_m: f32::NEG_INFINITY,
            density_floor: 0.2,
            instance_scale: 1.0,
            outer_offset_scale: 1.0,
            side_bias_strength: 0.0,
            spacing_m: 0.0,
            reservation_radius: 0.46,
            max_tilt_degrees: 5.0,
            terrain_clearance: 0.02,
            sector_length: 96.0,
            min_surface_up: 0.72,
            node_inv_xform: Transform3D::IDENTITY,
            cluster_scatter: false,
            use_grass_gis: false,
            use_snow_coverage: false,
            face_camera: false,
            outline_bush_cards: false,
            collidable_bushes: false,
            variant_group_size: 1,
            variants: Vec::new(),
            gis_sampler: None,
            parking: Vec::new(),
            reserved_grid: HashMap::new(),
            spacing_cells: HashMap::new(),
            sector_cell_m: 0.0,
            sectors: Vec::new(),
            sector_grid: HashMap::new(),
            pending_parents: Vec::new(),
            pending_daughters: Vec::new(),
            buckets: BTreeMap::new(),
            ordered_buckets: Vec::new(),
            base,
        }
    }
}

#[godot_api]
impl RustStageGrassPlanner {
    #[func]
    pub fn set_route(
        &mut self,
        route: PackedVector3Array,
        bins_flat: PackedFloat32Array,
        stage_seed: i64,
        budget: i32,
        max_attempts: i32,
    ) {
        self.route = route.as_slice().to_vec();
        self.bins.clear();
        let b = bins_flat.as_slice();
        for chunk in b.chunks_exact(2) {
            self.bins.push((chunk[0], chunk[1]));
        }
        self.rng = Pcg32::seeded(stage_seed as u64);
        self.budget = budget.max(0);
        self.max_attempts = max_attempts.max(0);
        self.attempts = 0;
        self.placed = 0;
        self.clusters = 0;
        self.snow_skipped = 0;
        self.snow_placed = 0;
        self.gis_skipped = 0;
        self.min_height_m = f32::INFINITY;
        self.max_height_m = 0.0;
        self.min_delta_m = f32::INFINITY;
        self.max_delta_m = f32::NEG_INFINITY;
        self.pending_parents.clear();
        self.pending_daughters.clear();
        self.spacing_cells.clear();
        self.buckets.clear();
        self.ordered_buckets.clear();

        self.cumulative.clear();
        self.arc_table.clear();
        self.total_length = 0.0;
        if self.route.len() >= 2 {
            self.cumulative.resize(self.route.len(), 0.0);
            for i in 1..self.route.len() {
                let d = self.route[i] - self.route[i - 1];
                let len = ((d.x as f64).powi(2) + (d.y as f64).powi(2) + (d.z as f64).powi(2)).sqrt();
                self.cumulative[i] = self.cumulative[i - 1] + len;
            }
            self.total_length = *self.cumulative.last().unwrap_or(&0.0);
            if self.total_length > 0.01 {
                let table_size = (self.total_length / ARC_TABLE_STEP) as usize + 1;
                self.arc_table.resize(table_size, 0);
                let mut cursor = 0_usize;
                let last = self.cumulative.len() - 2;
                for (k, slot) in self.arc_table.iter_mut().enumerate() {
                    let travelled = (k as f64) * ARC_TABLE_STEP;
                    while cursor < last && self.cumulative[cursor + 1] <= travelled {
                        cursor += 1;
                    }
                    *slot = cursor;
                }
            }
        }
    }

    #[func]
    pub fn set_scatter_params(
        &mut self,
        params: PackedFloat32Array,
        flags: PackedInt32Array,
        node_inv_xform: Transform3D,
    ) {
        let p = params.as_slice();
        if p.len() >= 10 {
            self.density_floor = p[0];
            self.instance_scale = p[1];
            self.outer_offset_scale = p[2];
            self.side_bias_strength = p[3];
            self.spacing_m = p[4];
            self.reservation_radius = p[5];
            self.max_tilt_degrees = p[6];
            self.terrain_clearance = p[7];
            self.sector_length = p[8];
            self.min_surface_up = p[9];
        }
        let f = flags.as_slice();
        if f.len() >= 7 {
            self.cluster_scatter = f[0] != 0;
            self.use_grass_gis = f[1] != 0;
            self.use_snow_coverage = f[2] != 0;
            self.face_camera = f[3] != 0;
            self.outline_bush_cards = f[4] != 0;
            self.collidable_bushes = f[5] != 0;
            self.variant_group_size = f[6].max(1);
        }
        self.node_inv_xform = node_inv_xform;
    }

    #[func]
    #[allow(clippy::too_many_arguments)]
    pub fn set_variants(
        &mut self,
        weights: PackedFloat32Array,
        scales_flat: PackedFloat32Array,
        mesh_heights: PackedFloat32Array,
        height_norms: PackedFloat32Array,
        has_snow: PackedInt32Array,
        aabb_pos: PackedVector3Array,
        aabb_size: PackedVector3Array,
    ) {
        self.variants.clear();
        let w = weights.as_slice();
        let sc = scales_flat.as_slice();
        let mh = mesh_heights.as_slice();
        let hn = height_norms.as_slice();
        let hs = has_snow.as_slice();
        let ap = aabb_pos.as_slice();
        let asz = aabb_size.as_slice();
        let n = w
            .len()
            .min(sc.len() / 2)
            .min(mh.len())
            .min(hn.len())
            .min(hs.len())
            .min(ap.len())
            .min(asz.len());
        self.variants.reserve(n);
        for i in 0..n {
            self.variants.push(VariantInfo {
                weight: w[i],
                scale_min: sc[i * 2],
                scale_max: sc[i * 2 + 1],
                mesh_height: mh[i],
                height_norm: hn[i],
                has_snow: hs[i] != 0,
                aabb_pos: ap[i],
                aabb_size: asz[i],
            });
        }
    }

    #[func]
    pub fn set_reserved_points(&mut self, points: PackedVector3Array) {
        self.reserved_grid.clear();
        let radius = self.reservation_radius;
        if radius <= 0.0 {
            return;
        }
        for pt in points.as_slice() {
            let cell = (
                (pt.x / radius).floor() as i32,
                (pt.z / radius).floor() as i32,
            );
            self.reserved_grid
                .entry(cell)
                .or_default()
                .push(Vector2::new(pt.x, pt.z));
        }
    }

    #[func]
    pub fn set_gis_sampler(&mut self, sampler: Gd<RustGisSampler>) {
        self.gis_sampler = Some(sampler);
    }

    #[func]
    pub fn clear_gis_sampler(&mut self) {
        self.gis_sampler = None;
    }

    #[func]
    pub fn set_parking_rects(&mut self, rects_flat: PackedFloat32Array) {
        self.parking.clear();
        for c in rects_flat.as_slice().chunks_exact(11) {
            self.parking.push(ParkingSite {
                point: Vector3::new(c[0], c[1], c[2]),
                forward: Vector3::new(c[3], c[4], c[5]),
                right: Vector3::new(c[6], c[7], c[8]),
                length: c[9],
                width: c[10],
            });
        }
    }

    #[func]
    pub fn set_sectors(
        &mut self,
        cell_m: f32,
        grid_coords: PackedInt32Array,
        rects_flat: PackedFloat32Array,
    ) {
        self.sector_cell_m = cell_m;
        self.sectors.clear();
        self.sector_grid.clear();
        let g = grid_coords.as_slice();
        let r = rects_flat.as_slice();
        let n = (g.len() / 2).min(r.len() / 4);
        self.sectors.reserve(n);
        for i in 0..n {
            let gx = g[i * 2];
            let gz = g[i * 2 + 1];
            let x = r[i * 4];
            let z = r[i * 4 + 1];
            let w = r[i * 4 + 2];
            let h = r[i * 4 + 3];
            self.sectors.push(SectorEntry {
                min_x: x,
                min_z: z,
                max_x: x + w,
                max_z: z + h,
            });
            if gx != i32::MIN && gz != i32::MIN {
                self.sector_grid.insert((gx, gz), i as i32);
            }
        }
    }

    #[func]
    pub fn is_done(&self) -> bool {
        self.placed >= self.budget
            || self.attempts >= self.max_attempts
            || self.total_length <= 0.01
            || self.variants.is_empty()
            || self.bins.is_empty()
            || self.arc_table.is_empty()
    }

    #[func]
    pub fn get_attempts(&self) -> i32 {
        self.attempts
    }

    #[func]
    pub fn generate_parent_candidates(&mut self, max_rays: i32) -> PackedVector3Array {
        self.pending_parents.clear();
        if self.is_done() || max_rays <= 0 {
            return PackedVector3Array::new();
        }
        let rem_budget = self.budget - self.placed;
        let ray_cap = if self.cluster_scatter {
            (rem_budget * 2).clamp(2, max_rays.min(512))
        } else {
            (rem_budget * 3).clamp(1, max_rays)
        } as usize;

        let mut out = Vec::with_capacity(ray_cap);
        while self.attempts < self.max_attempts
            && self.placed < self.budget
            && self.pending_parents.len() < ray_cap
        {
            self.attempts += 1;
            let Some(cand) = self.sample_point() else {
                continue;
            };
            let density = self.density_chance(cand.pos.x as f64, cand.pos.z as f64) as f32;
            if self.rng.randf() > density {
                continue;
            }
            out.push(cand.pos);
            self.pending_parents.push(PendingParent {
                base: cand.base,
                arc_sector: cand.arc_sector,
                density,
            });
        }
        PackedVector3Array::from(out.as_slice())
    }

    #[func]
    pub fn process_parent_hits(
        &mut self,
        hit_positions: PackedVector3Array,
        hit_normals: PackedVector3Array,
        hit_flags: PackedByteArray,
    ) -> PackedVector3Array {
        self.pending_daughters.clear();
        let pos_slice = hit_positions.as_slice();
        let norm_slice = hit_normals.as_slice();
        let flag_slice = hit_flags.as_slice();
        let n = self
            .pending_parents
            .len()
            .min(pos_slice.len())
            .min(norm_slice.len())
            .min(flag_slice.len());

        let mut daughter_pts: Vec<Vector3> = Vec::new();
        let parents = std::mem::take(&mut self.pending_parents);

        for i in 0..n {
            if self.placed >= self.budget {
                break;
            }
            if flag_slice[i] == 0 {
                continue;
            }
            let cand = parents[i];
            let pos = pos_slice[i];
            let normal = norm_slice[i];
            let (accept, lushness) = self.evaluate_habitat(pos, normal, cand.base);
            if (self.cluster_scatter || self.use_grass_gis) && self.rng.randf() > accept {
                self.gis_skipped += 1;
                continue;
            }
            if !self.reserved_grid.is_empty() && self.near_reserved_point(pos) {
                continue;
            }
            if self.spacing_m > 0.0 && !self.reserve_position(pos) {
                continue;
            }
            let parent_slot = self.emit_tuft(
                pos,
                normal,
                cand.base,
                cand.arc_sector,
                cand.density,
                lushness,
                0.0,
                -1,
            );
            if !self.cluster_scatter || parent_slot < 0 {
                continue;
            }
            self.clusters += 1;
            let parent_group = parent_slot / self.variant_group_size.max(1);
            let cluster_raw =
                lerpf(2.0, 7.0, cand.density * 0.50 + lushness * 0.50) + self.rng.randf_range(-1.2, 1.2);
            let cluster_size = cluster_raw.round().clamp(2.0, 7.0) as i32;
            let radius = self.rng.randf_range(0.65, 2.35);
            let elongation = self.rng.randf_range(1.0, 1.75);
            let mut contour = Vector3::UP.cross(normal);
            if contour.length_squared() < 0.01 {
                let angle = self.rng.randf_range(0.0, TAU);
                contour = Vector3::new(angle.cos(), 0.0, angle.sin());
            } else {
                contour = contour.normalized();
            }
            let across = Vector3::UP.cross(contour).normalized();

            for _member in 1..cluster_size {
                if self.placed + (self.pending_daughters.len() as i32) >= self.budget {
                    break;
                }
                let r_frac = (self.rng.randf() + self.rng.randf()) * 0.5;
                let theta = self.rng.randf_range(0.0, TAU);
                let offset_vec = contour * (theta.cos() * r_frac * radius * elongation)
                    + across * (theta.sin() * r_frac * radius);
                daughter_pts.push(pos + offset_vec);
                self.pending_daughters.push(PendingDaughter {
                    base: cand.base,
                    arc_sector: cand.arc_sector,
                    density: cand.density,
                    parent_y: pos.y,
                    parent_group,
                    radial_frac: r_frac,
                });
            }
        }
        PackedVector3Array::from(daughter_pts.as_slice())
    }

    #[func]
    pub fn process_daughter_hits(
        &mut self,
        hit_positions: PackedVector3Array,
        hit_normals: PackedVector3Array,
        hit_flags: PackedByteArray,
    ) {
        let pos_slice = hit_positions.as_slice();
        let norm_slice = hit_normals.as_slice();
        let flag_slice = hit_flags.as_slice();
        let n = self
            .pending_daughters
            .len()
            .min(pos_slice.len())
            .min(norm_slice.len())
            .min(flag_slice.len());
        let daughters = std::mem::take(&mut self.pending_daughters);

        for i in 0..n {
            if self.placed >= self.budget {
                break;
            }
            if flag_slice[i] == 0 {
                continue;
            }
            let d = daughters[i];
            let d_pos = pos_slice[i];
            if (d_pos.y - d.parent_y).abs() > 1.35 {
                continue;
            }
            let d_normal = norm_slice[i];
            let (accept, lushness) = self.evaluate_habitat(d_pos, d_normal, d.base);
            if self.rng.randf() > accept {
                self.gis_skipped += 1;
                continue;
            }
            if !self.reserved_grid.is_empty() && self.near_reserved_point(d_pos) {
                continue;
            }
            if self.spacing_m > 0.0 && !self.reserve_position(d_pos) {
                continue;
            }
            self.emit_tuft(
                d_pos,
                d_normal,
                d.base,
                d.arc_sector,
                d.density,
                lushness,
                d.radial_frac,
                d.parent_group,
            );
        }
    }

    #[func]
    pub fn finalize_buckets(&mut self) -> PackedInt32Array {
        self.ordered_buckets = self.buckets.keys().copied().collect();
        let mut flat = Vec::with_capacity(self.ordered_buckets.len() * 2);
        for &(kx, ky) in &self.ordered_buckets {
            flat.push(kx);
            flat.push(ky);
        }
        PackedInt32Array::from(flat.as_slice())
    }

    #[func]
    pub fn get_bucket_multimesh_buffer(&self, bucket_idx: i32) -> PackedFloat32Array {
        if bucket_idx < 0 || (bucket_idx as usize) >= self.ordered_buckets.len() {
            return PackedFloat32Array::new();
        }
        let key = self.ordered_buckets[bucket_idx as usize];
        match self.buckets.get(&key) {
            Some(b) => PackedFloat32Array::from(b.buffer.as_slice()),
            None => PackedFloat32Array::new(),
        }
    }

    #[func]
    pub fn get_bucket_aabb(&self, bucket_idx: i32) -> Aabb {
        if bucket_idx < 0 || (bucket_idx as usize) >= self.ordered_buckets.len() {
            return Aabb::default();
        }
        let key = self.ordered_buckets[bucket_idx as usize];
        self.buckets
            .get(&key)
            .and_then(|b| b.billboard_aabb)
            .unwrap_or_default()
    }

    #[func]
    pub fn get_bucket_bush_colliders(&self, bucket_idx: i32) -> PackedFloat32Array {
        if bucket_idx < 0 || (bucket_idx as usize) >= self.ordered_buckets.len() {
            return PackedFloat32Array::new();
        }
        let key = self.ordered_buckets[bucket_idx as usize];
        match self.buckets.get(&key) {
            Some(b) => PackedFloat32Array::from(b.bush_colliders.as_slice()),
            None => PackedFloat32Array::new(),
        }
    }

    #[func]
    pub fn get_stats_array(&self) -> PackedFloat32Array {
        let total_instances: usize = self.buckets.values().map(|b| b.buffer.len() / 12).sum();
        PackedFloat32Array::from(&[
            total_instances as f32,
            self.placed as f32,
            self.attempts as f32,
            self.clusters as f32,
            self.snow_skipped as f32,
            self.snow_placed as f32,
            self.gis_skipped as f32,
            if self.min_height_m.is_finite() {
                self.min_height_m
            } else {
                -1.0
            },
            self.max_height_m,
            if self.min_delta_m.is_finite() {
                self.min_delta_m
            } else {
                0.0
            },
            if self.max_delta_m.is_finite() {
                self.max_delta_m
            } else {
                0.0
            },
        ])
    }
}

struct SampledCandidate {
    pos: Vector3,
    base: Vector3,
    arc_sector: i32,
}

impl RustStageGrassPlanner {
    fn sample_point(&mut self) -> Option<SampledCandidate> {
        let travelled = (self.rng.randf() as f64) * self.total_length;
        let table_idx =
            ((travelled / ARC_TABLE_STEP) as usize).min(self.arc_table.len().saturating_sub(1));
        let index = self.arc_table[table_idx];
        let start = self.route[index];
        let delta = self.route[index + 1] - start;
        let segment = self.cumulative[index + 1] - self.cumulative[index];
        if segment <= 0.0001 {
            return None;
        }
        let lateral = Vector3::UP.cross(delta);
        if lateral.length_squared() < 1e-10 {
            return None;
        }
        let lateral = lateral.normalized();
        let bin_idx = self.rng.randi_range(0, (self.bins.len() as i32) - 1) as usize;
        let bin = self.bins[bin_idx];

        let mut left_chance = 0.5_f32;
        if self.side_bias_strength > 0.0 {
            let bias = (value_noise(travelled / 73.0, 19.6) * 0.62
                + value_noise(travelled / 191.0 + 13.4, 41.2) * 0.38) as f32;
            left_chance += lerpf(-self.side_bias_strength, self.side_bias_strength, bias);
        }
        let side = if self.rng.randf() < left_chance {
            -1.0_f32
        } else {
            1.0_f32
        };
        let t_seg = ((travelled - self.cumulative[index]) / segment) as f32;
        let base = start + delta * t_seg;
        let arc_sector = (travelled / (self.sector_length as f64)) as i32;

        let mut offset = self.rng.randf_range(bin.0, bin.1);
        let mut effective_outer = self.outer_offset_scale;
        if self.cluster_scatter {
            let side_seed = if side < 0.0 { 17.0_f64 } else { 61.0_f64 };
            let reach_wave = value_noise(travelled / 89.0 + side_seed, 27.1) as f32;
            effective_outer *= lerpf(0.68, 1.22, reach_wave);
            let setback_wave = smoothstep(
                0.42,
                0.88,
                value_noise(travelled / 53.0 + side_seed * 1.7, 9.4) as f32,
            );
            offset += setback_wave * 3.4;
        }
        if (effective_outer - 1.0).abs() > f32::EPSILON {
            offset += (offset - self.bins[0].0) * (effective_outer - 1.0);
        }
        let pos = base + lateral * (offset * side);
        Some(SampledCandidate {
            pos,
            base,
            arc_sector,
        })
    }

    #[inline]
    fn density_chance(&self, x: f64, z: f64) -> f64 {
        let warp_x = (value_noise(x / 37.0 + 11.3, z / 37.0 + 47.9) - 0.5) * 18.0;
        let warp_z = (value_noise(x / 37.0 + 83.1, z / 37.0 + 19.7) - 0.5) * 18.0;
        let wx = x + warp_x;
        let wz = z + warp_z;
        let macro_n = value_noise(wx / 118.0 + 5.2, wz / 118.0 + 23.4);
        let broad = value_noise(wx / 29.0, wz / 29.0);
        let fine = value_noise(wx / 11.5 + 31.7, wz / 11.5 + 17.3);
        let combined = (macro_n * 0.38 + broad * 0.40 + fine * 0.22).clamp(0.0, 1.0);
        let t = ((combined - 0.26) / (0.74 - 0.26)).clamp(0.0, 1.0);
        let shaped = t * t * (3.0 - 2.0 * t);
        lerpf64(self.density_floor as f64, 1.0, shaped)
    }

    #[inline]
    fn evaluate_habitat(&self, position: Vector3, normal: Vector3, base: Vector3) -> (f32, f32) {
        let mut sparse = 0.45_f32;
        let mut olive = 0.06_f32;
        let mut mineral = 0.15_f32;
        let mut gis_density = 1.0_f32;

        if self.use_grass_gis
            && let Some(sampler_gd) = &self.gis_sampler
        {
            let sampler = sampler_gd.bind();
            let s = sampler.sample_grass_gis(position);
            sparse = lerpf(0.45, s[0], s[3]);
            olive = lerpf(0.06, s[1], s[3]);
            mineral = lerpf(0.15, s[2], s[3]);
            let mineral_penalty = smoothstep(0.22, 0.68, mineral);
            gis_density = (lerpf(1.0, 0.30, sparse) * (1.0 - mineral_penalty * 0.90)
                + olive * 0.20)
                .clamp(0.04, 1.15);
        }
        let slope_factor = lerpf(0.25, 1.0, smoothstep(self.min_surface_up, 0.94, normal.y));
        let elevation_above_road = position.y - base.y;
        let bank_factor = lerpf(1.0, 0.38, smoothstep(1.8, 5.5, elevation_above_road));
        let accept = (gis_density * slope_factor * bank_factor).clamp(0.0, 1.0);
        let lushness = ((1.0 - sparse) * 0.45
            + olive * 0.30
            - mineral * 0.35
            + slope_factor * 0.35
            + (0.20 - elevation_above_road * 0.06).clamp(-0.15, 0.20))
        .clamp(0.0, 1.0);
        (accept, lushness)
    }

    #[inline]
    fn near_reserved_point(&self, position: Vector3) -> bool {
        let radius = self.reservation_radius;
        let point = Vector2::new(position.x, position.z);
        let cx = (point.x / radius).floor() as i32;
        let cy = (point.y / radius).floor() as i32;
        let r2 = radius * radius;
        for x in (cx - 1)..=(cx + 1) {
            for y in (cy - 1)..=(cy + 1) {
                if let Some(pts) = self.reserved_grid.get(&(x, y)) {
                    for &other in pts {
                        if point.distance_squared_to(other) < r2 {
                            return true;
                        }
                    }
                }
            }
        }
        false
    }

    #[inline]
    fn reserve_position(&mut self, position: Vector3) -> bool {
        let sp = self.spacing_m;
        let point = Vector2::new(position.x, position.z);
        let cell = ((point.x / sp).floor() as i32, (point.y / sp).floor() as i32);
        let min_sq = sp * sp;
        for x in (cell.0 - 1)..=(cell.0 + 1) {
            for y in (cell.1 - 1)..=(cell.1 + 1) {
                if let Some(&other) = self.spacing_cells.get(&(x, y))
                    && point.distance_squared_to(other) < min_sq
                {
                    return false;
                }
            }
        }
        if self.spacing_cells.contains_key(&cell) {
            return false;
        }
        self.spacing_cells.insert(cell, point);
        true
    }

    #[inline]
    fn parking_covers(&self, position: Vector3) -> bool {
        for site in &self.parking {
            let delta = position - site.point;
            if delta.dot(site.forward).abs() <= site.length
                && delta.dot(site.right).abs() <= site.width
            {
                return true;
            }
        }
        false
    }

    #[inline]
    fn sector_for_point(&self, global_pos: Vector3) -> i32 {
        if self.sector_cell_m > 0.0 {
            let cx = (global_pos.x / self.sector_cell_m).floor() as i32;
            let cz = (global_pos.z / self.sector_cell_m).floor() as i32;
            if let Some(&idx) = self.sector_grid.get(&(cx, cz)) {
                return idx;
            }
        }
        let mut best_idx = 0_i32;
        let mut best_dist = f32::INFINITY;
        for (i, s) in self.sectors.iter().enumerate() {
            let nx = global_pos.x.clamp(s.min_x, s.max_x);
            let nz = global_pos.z.clamp(s.min_z, s.max_z);
            let dx = global_pos.x - nx;
            let dz = global_pos.z - nz;
            let d2 = dx * dx + dz * dz;
            if d2 < best_dist {
                best_dist = d2;
                best_idx = i as i32;
            }
        }
        best_idx
    }

    fn pick_variant(&mut self) -> usize {
        let count = self.variants.len();
        if count <= 1 {
            return 0;
        }
        let mut total = 0.0_f32;
        for v in &self.variants {
            total += v.weight;
        }
        if total <= 0.0 {
            return self.rng.randi_range(0, (count as i32) - 1) as usize;
        }
        let mut roll = self.rng.randf() * total;
        for (slot, v) in self.variants.iter().enumerate() {
            roll -= v.weight;
            if roll <= 0.0 {
                return slot;
            }
        }
        count - 1
    }

    fn pick_habitat_slot(
        &mut self,
        position: Vector3,
        lushness: f32,
        forced_group: i32,
    ) -> usize {
        let n = self.variants.len();
        let group_size = self.variant_group_size.max(1) as usize;
        let group_count = n / group_size;
        if group_count <= 1 || !n.is_multiple_of(group_size) {
            return self.pick_variant();
        }
        if forced_group >= 0
            && (forced_group as usize) < group_count
            && self.rng.randf() < 0.75
        {
            let sub = self.rng.randi_range(0, (group_size as i32) - 1) as usize;
            return (forced_group as usize) * group_size + sub;
        }
        let px = position.x as f64;
        let pz = position.z as f64;
        let warp_x = (value_noise(px / 58.0 + 21.1, pz / 58.0 + 67.3) - 0.5) * 22.0;
        let warp_z = (value_noise(px / 58.0 + 91.7, pz / 58.0 + 14.9) - 0.5) * 22.0;
        let stand_field =
            value_noise((px + warp_x) / 48.0 + 3.7, (pz + warp_z) / 48.0 + 29.5) as f32;
        let dominant = stand_field * (group_count as f32);

        let mut group_weights = Vec::with_capacity(group_count);
        let mut total = 0.0_f32;
        for g in 0..group_count {
            let rep = self.variants[g * group_size];
            let base_w = rep.weight.max(0.01);
            let dist = ((g as f32) + 0.5 - dominant).abs();
            let stand_affinity = lerpf(0.18, 1.0, (-dist * dist * 1.9).exp());
            let habitat_affinity = lerpf(0.55, 1.45, 1.0 - (rep.height_norm - lushness).abs());
            let w = base_w * stand_affinity * habitat_affinity;
            group_weights.push(w);
            total += w;
        }
        let mut chosen_group = group_count - 1;
        let mut roll = self.rng.randf() * total;
        for (g, &w) in group_weights.iter().enumerate() {
            roll -= w;
            if roll <= 0.0 {
                chosen_group = g;
                break;
            }
        }
        let sub = self.rng.randi_range(0, (group_size as i32) - 1) as usize;
        chosen_group * group_size + sub
    }

    #[allow(clippy::too_many_arguments)]
    fn emit_tuft(
        &mut self,
        position: Vector3,
        normal: Vector3,
        base: Vector3,
        arc_sector: i32,
        density: f32,
        lushness: f32,
        radial_frac: f32,
        forced_group: i32,
    ) -> i32 {
        self.placed += 1;
        if !self.parking.is_empty() && self.parking_covers(position) {
            return -1;
        }
        let mut snow = 0.0_f32;
        if self.use_snow_coverage
            && let Some(sampler_gd) = &self.gis_sampler
        {
            let sampler = sampler_gd.bind();
            if sampler.has_snow() {
                snow = sampler.sample_snow(position);
                if self.rng.randf() < smoothstep(0.18, 0.75, snow) {
                    self.snow_skipped += 1;
                    return -1;
                }
            }
        }
        let slot = if self.cluster_scatter {
            self.pick_habitat_slot(position, lushness, forced_group)
        } else {
            self.pick_variant()
        };
        let v = self.variants[slot];
        let snowy = snow > 0.0
            && v.has_snow
            && self.rng.randf() < smoothstep(0.13, 0.62, snow);
        if snowy {
            self.snow_placed += 1;
        }
        let num_variants = self.variants.len() as i32;
        let variant_key = if snowy {
            (slot as i32) + num_variants
        } else {
            slot as i32
        };

        let bell = (self.rng.randf() + self.rng.randf()) * 0.5;
        let vigor = (density * 0.45 + lushness * 0.35 + (1.0 - radial_frac) * 0.20).clamp(0.0, 1.0);
        let t = lerpf(
            bell,
            if self.cluster_scatter { vigor } else { density },
            0.25,
        )
        .clamp(0.0, 1.0);
        let scale_y = lerpf(v.scale_min, v.scale_max, t) * self.instance_scale;
        let actual_h = v.mesh_height * scale_y;
        let delta_h = actual_h - v.mesh_height * self.instance_scale;
        self.min_height_m = self.min_height_m.min(actual_h);
        self.max_height_m = self.max_height_m.max(actual_h);
        self.min_delta_m = self.min_delta_m.min(delta_h);
        self.max_delta_m = self.max_delta_m.max(delta_h);

        let scale_xz = scale_y * self.rng.randf_range(0.82, 1.22);
        let yaw = self.rng.randf_range(0.0, TAU);
        let mut basis = Basis::from_axis_angle(Vector3::UP, yaw)
            .scaled(Vector3::new(scale_xz, scale_y, scale_xz));

        if self.cluster_scatter {
            let wind_angle = (value_noise(
                (position.x as f64) / 95.0 + 7.1,
                (position.z as f64) / 95.0 + 53.3,
            ) - 0.5) as f32
                * 1.4
                + 0.65;
            let wind_dir = Vector3::new(wind_angle.cos(), 0.0, wind_angle.sin());
            let wind_lean = self.rng.randf_range(1.5, 6.5).to_radians();
            let jitter_angle = self.rng.randf_range(0.0, TAU);
            let jitter_rad = self.rng.randf_range(0.0, 3.0).to_radians();
            let jitter =
                Vector3::new(jitter_angle.cos(), 0.0, jitter_angle.sin()) * jitter_rad;
            let target_up =
                (Vector3::UP.lerp(normal, 0.28) + wind_dir * wind_lean.sin() + jitter)
                    .normalized();
            if target_up.y > 0.70 {
                basis = Basis::from_quaternion(Quaternion::from_rotation_arc(
                    Vector3::UP,
                    target_up,
                )) * basis;
            }
        } else {
            let mut tilt_axis = Vector3::new(position.x - base.x, 0.0, position.z - base.z);
            if tilt_axis.length() < 0.05 {
                tilt_axis = Vector3::RIGHT;
            }
            let tilt = self
                .rng
                .randf_range(-self.max_tilt_degrees, self.max_tilt_degrees)
                .to_radians();
            basis = Basis::from_axis_angle(tilt_axis.normalized(), tilt) * basis;
        }

        let world_ground_pos = position - Vector3::UP * self.terrain_clearance;
        let local_origin = self.node_inv_xform * world_ground_pos;
        let key_x = if !self.sectors.is_empty() {
            self.sector_for_point(world_ground_pos)
        } else {
            arc_sector
        };

        let bucket = self
            .buckets
            .entry((key_x, variant_key))
            .or_insert_with(BucketData::new);

        // MultiMesh.buffer 12-float layout: row-major 3x4 affine matrix.
        let r0 = basis.rows[0];
        let r1 = basis.rows[1];
        let r2 = basis.rows[2];
        bucket.buffer.extend_from_slice(&[
            r0.x,
            r0.y,
            r0.z,
            local_origin.x,
            r1.x,
            r1.y,
            r1.z,
            local_origin.y,
            r2.x,
            r2.y,
            r2.z,
            local_origin.z,
        ]);

        let sx = basis.col_a().length();
        let sy = basis.col_b().length();
        let sz = basis.col_c().length();

        if self.face_camera {
            let expansion = if self.outline_bush_cards { 1.6_f32 } else { 1.0_f32 };
            let radius = v.aabb_size.x * sx * 0.5 * expansion;
            let half_height = v.aabb_size.y * sy * 0.5 * expansion;
            let mesh_center_y = v.aabb_pos.y + v.aabb_size.y * 0.5;
            let center = local_origin + Vector3::UP * (mesh_center_y * sy);
            let extent = Vector3::new(radius, half_height, radius);
            let b_aabb = Aabb::new(center - extent, extent * 2.0);
            bucket.billboard_aabb = Some(match bucket.billboard_aabb {
                Some(prev) => prev.merge(b_aabb),
                None => b_aabb,
            });
        }

        if self.collidable_bushes {
            let depth = if self.face_camera {
                v.aabb_size.x
            } else {
                v.aabb_size.z
            };
            let cap_radius = (v.aabb_size.x * sx).min(depth * sz) * 0.29;
            let cap_radius = cap_radius.max(0.12);
            let cap_height = (v.aabb_size.y * sy * 0.80).max(cap_radius * 2.0);
            let local_pt = Vector3::new(
                v.aabb_pos.x + v.aabb_size.x * 0.5,
                v.aabb_pos.y,
                v.aabb_pos.z + v.aabb_size.z * 0.5,
            );
            let instance_xform = Transform3D::new(basis, local_origin);
            let mut collider_pos = instance_xform * local_pt;
            collider_pos.y += cap_height * 0.5;
            bucket.bush_colliders.extend_from_slice(&[
                collider_pos.x,
                collider_pos.y,
                collider_pos.z,
                cap_radius,
                cap_height,
            ]);
        }

        slot as i32
    }
}
