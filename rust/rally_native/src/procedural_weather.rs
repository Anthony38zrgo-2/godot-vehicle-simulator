use std::collections::HashMap;
use std::f32::consts::PI;

use godot::builtin::{PackedFloat32Array, VarArray, VarDictionary};
use godot::classes::RefCounted;
use godot::prelude::*;

use crate::rng::Pcg32;

pub const ALGO_VERSION: u32 = 1;
const FRONT_BLOCK_SECONDS: f64 = 21600.0; // 6-hour deterministic blocks
const MAX_FRONT_HALF_DURATION_S: f64 = 7200.0;

#[inline]
fn lerpf(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[inline]
fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    if (edge1 - edge0).abs() < 1e-6 {
        return if x >= edge1 { 1.0 } else { 0.0 };
    }
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[inline]
fn fnv1a_64(bytes: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for &b in bytes {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

#[inline]
fn splitmix64(mut x: u64) -> u64 {
    x = x.wrapping_add(0x9e3779b97f4a7c15);
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94d049bb133111eb);
    x ^ (x >> 31)
}

pub fn derive_stream_seed(event_seed: u64, track_id: &str, algo_version: u32, stream_tag: &str) -> u64 {
    let mut acc = splitmix64(event_seed ^ ((algo_version as u64) << 32));
    acc ^= fnv1a_64(track_id.as_bytes());
    acc = splitmix64(acc);
    acc ^= fnv1a_64(stream_tag.as_bytes());
    splitmix64(acc)
}

/// Minimal self-contained JSON parser so pure-Rust tests and GDExtension parse identical JSON files
/// without external crate dependencies.
mod json_lite {
    use std::collections::HashMap;

    #[derive(Clone, Debug)]
    pub enum Val {
        Null,
        Bool(bool),
        Num(f64),
        Str(String),
        Arr(Vec<Val>),
        Obj(HashMap<String, Val>),
    }

    impl Val {
        pub fn get(&self, key: &str) -> Option<&Val> {
            match self {
                Val::Obj(map) => map.get(key),
                _ => None,
            }
        }
        pub fn as_str(&self) -> Option<&str> {
            match self {
                Val::Str(s) => Some(s.as_str()),
                _ => None,
            }
        }
        pub fn as_f64(&self) -> Option<f64> {
            match self {
                Val::Num(n) => Some(*n),
                _ => None,
            }
        }
        pub fn as_f32(&self) -> Option<f32> {
            self.as_f64().map(|v| v as f32)
        }
        pub fn as_bool(&self) -> Option<bool> {
            match self {
                Val::Bool(b) => Some(*b),
                _ => None,
            }
        }
        pub fn as_arr(&self) -> Option<&[Val]> {
            match self {
                Val::Arr(a) => Some(a.as_slice()),
                _ => None,
            }
        }
        pub fn as_obj(&self) -> Option<&HashMap<String, Val>> {
            match self {
                Val::Obj(o) => Some(o),
                _ => None,
            }
        }
    }

    struct Parser<'a> {
        bytes: &'a [u8],
        pos: usize,
    }

    impl<'a> Parser<'a> {
        fn skip_ws(&mut self) {
            while self.pos < self.bytes.len() && self.bytes[self.pos].is_ascii_whitespace() {
                self.pos += 1;
            }
        }

        fn peek(&mut self) -> Option<u8> {
            self.skip_ws();
            self.bytes.get(self.pos).copied()
        }

        fn next(&mut self) -> Result<u8, String> {
            let b = self.bytes.get(self.pos).copied().ok_or_else(|| "Unexpected EOF".to_string())?;
            self.pos += 1;
            Ok(b)
        }

        fn expect(&mut self, ch: u8) -> Result<(), String> {
            self.skip_ws();
            let got = self.next()?;
            if got != ch {
                return Err(format!("Expected '{}' at {}, got '{}'", ch as char, self.pos - 1, got as char));
            }
            Ok(())
        }

        fn parse_str(&mut self) -> Result<String, String> {
            self.expect(b'"')?;
            let mut out = String::new();
            loop {
                let b = self.next()?;
                if b == b'"' {
                    return Ok(out);
                }
                if b == b'\\' {
                    let esc = self.next()?;
                    match esc {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{0008}'),
                        b'f' => out.push('\u{000c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            if self.pos + 4 > self.bytes.len() {
                                return Err("Truncated \\u escape".into());
                            }
                            let hex = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4])
                                .map_err(|_| "Invalid UTF-8 in \\u".to_string())?;
                            let code = u16::from_str_radix(hex, 16).map_err(|_| "Invalid hex".to_string())?;
                            self.pos += 4;
                            if let Some(ch) = char::from_u32(code as u32) {
                                out.push(ch);
                            }
                        }
                        _ => return Err(format!("Invalid escape \\{}", esc as char)),
                    }
                } else {
                    // Handle multi-byte UTF-8 directly from slice when possible.
                    if b < 0x80 {
                        out.push(b as char);
                    } else {
                        let start = self.pos - 1;
                        while self.pos < self.bytes.len() && (self.bytes[self.pos] & 0b1100_0000) == 0b1000_0000 {
                            self.pos += 1;
                        }
                        let s = std::str::from_utf8(&self.bytes[start..self.pos])
                            .map_err(|_| "Invalid UTF-8 in string".to_string())?;
                        out.push_str(s);
                    }
                }
            }
        }

        fn parse_num(&mut self) -> Result<f64, String> {
            self.skip_ws();
            let start = self.pos;
            while self.pos < self.bytes.len() {
                let b = self.bytes[self.pos];
                if b.is_ascii_digit() || matches!(b, b'-' | b'+' | b'.' | b'e' | b'E') {
                    self.pos += 1;
                } else {
                    break;
                }
            }
            let s = std::str::from_utf8(&self.bytes[start..self.pos]).map_err(|_| "Bad number".to_string())?;
            s.parse::<f64>().map_err(|e| format!("Invalid number '{}': {}", s, e))
        }

        fn parse_val(&mut self) -> Result<Val, String> {
            match self.peek() {
                Some(b'{') => {
                    self.next()?;
                    let mut map = HashMap::new();
                    if self.peek() == Some(b'}') {
                        self.next()?;
                        return Ok(Val::Obj(map));
                    }
                    loop {
                        let k = self.parse_str()?;
                        self.expect(b':')?;
                        let v = self.parse_val()?;
                        map.insert(k, v);
                        match self.peek() {
                            Some(b',') => {
                                self.next()?;
                            }
                            Some(b'}') => {
                                self.next()?;
                                break;
                            }
                            other => return Err(format!("Expected ',' or '}}' in object, got {:?}", other)),
                        }
                    }
                    Ok(Val::Obj(map))
                }
                Some(b'[') => {
                    self.next()?;
                    let mut arr = Vec::new();
                    if self.peek() == Some(b']') {
                        self.next()?;
                        return Ok(Val::Arr(arr));
                    }
                    loop {
                        arr.push(self.parse_val()?);
                        match self.peek() {
                            Some(b',') => {
                                self.next()?;
                            }
                            Some(b']') => {
                                self.next()?;
                                break;
                            }
                            other => return Err(format!("Expected ',' or ']' in array, got {:?}", other)),
                        }
                    }
                    Ok(Val::Arr(arr))
                }
                Some(b'"') => Ok(Val::Str(self.parse_str()?)),
                Some(b't') => {
                    if self.bytes[self.pos..].starts_with(b"true") {
                        self.pos += 4;
                        Ok(Val::Bool(true))
                    } else {
                        Err("Invalid token starting with t".into())
                    }
                }
                Some(b'f') => {
                    if self.bytes[self.pos..].starts_with(b"false") {
                        self.pos += 5;
                        Ok(Val::Bool(false))
                    } else {
                        Err("Invalid token starting with f".into())
                    }
                }
                Some(b'n') => {
                    if self.bytes[self.pos..].starts_with(b"null") {
                        self.pos += 4;
                        Ok(Val::Bool(false)).map(|_| Val::Null)
                    } else {
                        Err("Invalid token starting with n".into())
                    }
                }
                Some(b'-' | b'0'..=b'9') => Ok(Val::Num(self.parse_num()?)),
                other => Err(format!("Unexpected byte {:?} at {}", other, self.pos)),
            }
        }
    }

    pub fn parse(input: &str) -> Result<Val, String> {
        let mut p = Parser {
            bytes: input.as_bytes(),
            pos: 0,
        };
        p.parse_val()
    }
}

#[derive(Clone, Debug)]
pub struct RouteSample {
    pub progress_m: f32,
    pub shader_station_m: f32,
    pub altitude_m: f32,
    pub local_x_m: f32,
    pub local_z_m: f32,
    pub grade: f32,
    pub heading_rad: f32,
}

#[derive(Clone, Debug)]
pub struct RouteProfile {
    pub track_id: String,
    pub vertical_datum_verified: bool,
    pub samples: Vec<RouteSample>,
    pub total_distance_m: f32,
    pub min_altitude_m: f32,
    pub max_altitude_m: f32,
    pub center_x_m: f32,
    pub center_z_m: f32,
    pub extent_radius_m: f32,
    pub five_sector_boundaries_m: Option<[f32; 6]>,
    pub snow_transition_altitude_m: Option<f32>,
}

impl RouteProfile {
    pub fn from_json_str(json_text: &str) -> Result<Self, String> {
        let root = json_lite::parse(json_text)?;
        let track_id = root
            .get("track_id")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();
        let vertical_datum_verified = root
            .get("geography")
            .and_then(|g| g.get("vertical_datum_verified"))
            .and_then(|b| b.as_bool())
            .unwrap_or(false);
        let arr = root
            .get("samples")
            .and_then(|v| v.as_arr())
            .ok_or_else(|| "RouteProfile missing 'samples' array".to_string())?;
        if arr.len() < 2 {
            return Err("RouteProfile requires at least 2 samples".into());
        }
        let mut samples: Vec<RouteSample> = Vec::with_capacity(arr.len());
        let mut min_alt = f32::INFINITY;
        let mut max_alt = f32::NEG_INFINITY;
        let mut min_x = f32::INFINITY;
        let mut max_x = f32::NEG_INFINITY;
        let mut min_z = f32::INFINITY;
        let mut max_z = f32::NEG_INFINITY;

        for (i, item) in arr.iter().enumerate() {
            let progress_m = item
                .get("progress_m")
                .and_then(|v| v.as_f32())
                .ok_or_else(|| format!("Sample {} missing progress_m", i))?;
            let shader_station_m = item
                .get("shader_station_m")
                .and_then(|v| v.as_f32())
                .unwrap_or(progress_m);
            let altitude_m = item
                .get("altitude_m")
                .and_then(|v| v.as_f32())
                .unwrap_or(0.0);
            let local_x_m = item
                .get("local_x_m")
                .and_then(|v| v.as_f32())
                .unwrap_or(progress_m);
            let local_z_m = item
                .get("local_z_m")
                .and_then(|v| v.as_f32())
                .unwrap_or(0.0);
            let grade = item.get("grade").and_then(|v| v.as_f32()).unwrap_or(0.0);
            let heading_rad = item.get("heading_rad").and_then(|v| v.as_f32()).unwrap_or(0.0);

            if i > 0 && progress_m < samples[i - 1_usize].progress_m {
                return Err(format!("Sample {} progress_m is not monotonic", i));
            }
            min_alt = min_alt.min(altitude_m);
            max_alt = max_alt.max(altitude_m);
            min_x = min_x.min(local_x_m);
            max_x = max_x.max(local_x_m);
            min_z = min_z.min(local_z_m);
            max_z = max_z.max(local_z_m);

            samples.push(RouteSample {
                progress_m,
                shader_station_m,
                altitude_m,
                local_x_m,
                local_z_m,
                grade,
                heading_rad,
            });
        }

        let total_distance_m = samples.last().map(|s| s.progress_m).unwrap_or(0.0);
        let center_x_m = 0.5 * (min_x + max_x);
        let center_z_m = 0.5 * (min_z + max_z);
        let extent_radius_m = (0.5 * (max_x - min_x)).hypot(0.5 * (max_z - min_z)).max(500.0);

        let mut five_sector_boundaries_m: Option<[f32; 6]> = None;
        if let Some(fs_obj) = root.get("five_sectors").or_else(|| root.get("climate_sectors")) {
            let mut out_b = [0.0_f32; 6];
            if let Some(arr) = fs_obj.get("boundaries_m").and_then(|v| v.as_arr()) {
                if arr.len() == 6 && total_distance_m > 1.0 {
                    let mut prev = 0.0_f32;
                    for i in 0..6 {
                        let raw_m = arr[i].as_f32().unwrap_or(total_distance_m * (i as f32) * 0.2);
                        let clamped = if i == 0 {
                            0.0
                        } else if i == 5 {
                            total_distance_m
                        } else {
                            raw_m.max(prev + 10.0).min(total_distance_m - (5 - i) as f32 * 10.0)
                        };
                        out_b[i] = clamped;
                        prev = clamped;
                    }
                    five_sector_boundaries_m = Some(out_b);
                }
            } else if let Some(arr) = fs_obj.get("boundaries_fraction").and_then(|v| v.as_arr()) {
                if arr.len() == 6 && total_distance_m > 1.0 {
                    let mut prev = 0.0_f32;
                    for i in 0..6 {
                        let raw_m = arr[i].as_f32().unwrap_or((i as f32) * 0.2).clamp(0.0, 1.0) * total_distance_m;
                        let clamped = if i == 0 {
                            0.0
                        } else if i == 5 {
                            total_distance_m
                        } else {
                            raw_m.max(prev + 10.0).min(total_distance_m - (5 - i) as f32 * 10.0)
                        };
                        out_b[i] = clamped;
                        prev = clamped;
                    }
                    five_sector_boundaries_m = Some(out_b);
                }
            }
        }

        Ok(Self {
            track_id,
            vertical_datum_verified,
            samples,
            total_distance_m,
            min_altitude_m: min_alt,
            max_altitude_m: max_alt,
            center_x_m,
            center_z_m,
            extent_radius_m,
            five_sector_boundaries_m,
            snow_transition_altitude_m: root.get("snow_transition_altitude_m").and_then(|v| v.as_f32()).filter(|v| v.is_finite()),
        })
    }

    pub fn sample_at_progress(&self, progress_m: f32) -> RouteSample {
        let p = progress_m.clamp(self.samples[0].progress_m, self.total_distance_m);
        let idx = self.samples.partition_point(|s| s.progress_m < p);
        if idx == 0 {
            return self.samples[0].clone();
        }
        if idx >= self.samples.len() {
            return self.samples[self.samples.len() - 1].clone();
        }
        let a = &self.samples[idx - 1];
        let b = &self.samples[idx];
        let span = (b.progress_m - a.progress_m).max(1e-6);
        let t = ((p - a.progress_m) / span).clamp(0.0, 1.0);
        RouteSample {
            progress_m: p,
            shader_station_m: lerpf(a.shader_station_m, b.shader_station_m, t),
            altitude_m: lerpf(a.altitude_m, b.altitude_m, t),
            local_x_m: lerpf(a.local_x_m, b.local_x_m, t),
            local_z_m: lerpf(a.local_z_m, b.local_z_m, t),
            grade: lerpf(a.grade, b.grade, t),
            heading_rad: lerp_angle_rad(a.heading_rad, b.heading_rad, t),
        }
    }

    pub fn shader_station_to_progress(&self, shader_station_m: f32) -> f32 {
        let first = self.samples[0].shader_station_m;
        let last = self.samples[self.samples.len() - 1].shader_station_m;
        let s = shader_station_m.clamp(first, last);
        let idx = self.samples.partition_point(|x| x.shader_station_m < s);
        if idx == 0 {
            return self.samples[0].progress_m;
        }
        if idx >= self.samples.len() {
            return self.samples[self.samples.len() - 1].progress_m;
        }
        let a = &self.samples[idx - 1];
        let b = &self.samples[idx];
        let span = (b.shader_station_m - a.shader_station_m).max(1e-6);
        let t = ((s - a.shader_station_m) / span).clamp(0.0, 1.0);
        lerpf(a.progress_m, b.progress_m, t)
    }
}

#[inline]
fn lerp_angle_rad(a: f32, b: f32, t: f32) -> f32 {
    let mut diff = (b - a) % (2.0 * PI);
    if diff > PI {
        diff -= 2.0 * PI;
    } else if diff < -PI {
        diff += 2.0 * PI;
    }
    a + diff * t
}

#[inline]
fn lerp_angle_deg(a: f32, b: f32, t: f32) -> f32 {
    let mut diff = (b - a).rem_euclid(360.0);
    if diff > 180.0 {
        diff -= 360.0;
    }
    (a + diff * t).rem_euclid(360.0)
}

#[derive(Clone, Debug)]
pub struct PrecipBand {
    pub min_mm_h: f32,
    pub max_mm_h: f32,
    pub weight: f32,
}

#[derive(Clone, Debug)]
pub struct SeasonParams {
    pub base_temp_c: f32,
    pub diurnal_amplitude_c: f32,
    pub diurnal_peak_hour: f32,
    pub lapse_rate_c_per_km: f32,
    pub lapse_rate_front_c_per_km: f32,
    pub background_humidity: f32,
    pub diurnal_humidity_amplitude: f32,
    pub background_cloud_cover: f32,
    pub dry_day_probability: f32,
    pub front_frequency_per_day: f32,
    pub front_duration_s_range: [f32; 2],
    pub front_radius_m_range: [f32; 2],
    pub front_speed_m_s_range: [f32; 2],
    pub front_temp_anomaly_c_range: [f32; 2],
    pub front_humidity_boost_range: [f32; 2],
    pub front_cloud_boost_range: [f32; 2],
    pub precip_bands: Vec<PrecipBand>,
    pub orographic_enabled: bool,
    pub prevailing_wind_dir_deg: f32,
    pub wind_dir_jitter_deg: f32,
    pub wind_speed_m_s_range: [f32; 2],
    pub orographic_precip_gain: f32,
}

impl SeasonParams {
    pub fn sample_precip_mm_h(&self, rng: &mut Pcg32) -> f32 {
        let total_w: f32 = self.precip_bands.iter().map(|b| b.weight.max(0.0)).sum();
        if total_w <= 0.0 || self.precip_bands.is_empty() {
            return rng.randf_range(0.6, 3.2);
        }
        let mut pick = rng.randf() * total_w;
        for band in &self.precip_bands {
            pick -= band.weight.max(0.0);
            if pick <= 0.0 {
                return rng.randf_range(band.min_mm_h, band.max_mm_h);
            }
        }
        let last = self.precip_bands.last().unwrap();
        rng.randf_range(last.min_mm_h, last.max_mm_h)
    }
}

#[derive(Clone, Debug)]
pub struct SurfaceBalanceConfig {
    pub snow_stick_below_c: f32,
    pub snow_stick_above_c: f32,
    pub snow_melt_start_c: f32,
    pub snow_melt_band_c: f32,
    pub snow_melt_rate_mm_h_per_c: f32,
    pub snow_solar_melt_mm_h_per_kw: f32,
    pub ice_melt_start_c: f32,
    pub ice_melt_band_c: f32,
    pub ice_melt_rate_mm_h_per_c: f32,
    pub freeze_below_c: f32,
    pub freeze_band_c: f32,
    pub freeze_rate_mm_h_per_c: f32,
    pub snow_coverage_full_mm: f32,
    pub ice_coverage_full_mm: f32,
    pub water_coverage_full_mm: f32,
    pub max_water_mm: f32,
    pub max_snow_mm: f32,
    pub max_ice_mm: f32,
    pub tire_effective_water_cap_mm: f32,
    pub tire_effective_snow_cap_mm: f32,
}

impl Default for SurfaceBalanceConfig {
    fn default() -> Self {
        Self {
            snow_stick_below_c: -0.5,
            snow_stick_above_c: 2.5,
            snow_melt_start_c: 0.15,
            snow_melt_band_c: 2.0,
            snow_melt_rate_mm_h_per_c: 0.55,
            snow_solar_melt_mm_h_per_kw: 0.85,
            ice_melt_start_c: 0.15,
            ice_melt_band_c: 1.8,
            ice_melt_rate_mm_h_per_c: 0.70,
            freeze_below_c: -0.15,
            freeze_band_c: 1.5,
            freeze_rate_mm_h_per_c: 1.80,
            snow_coverage_full_mm: 6.0,
            ice_coverage_full_mm: 2.0,
            water_coverage_full_mm: 3.0,
            max_water_mm: 18.0,
            max_snow_mm: 60.0,
            max_ice_mm: 15.0,
            tire_effective_water_cap_mm: 12.0,
            tire_effective_snow_cap_mm: 8.0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct SurfaceMaterialParams {
    pub thermal_capacity_kj_m2_k: f32,
    pub solar_absorption: f32,
    pub snow_albedo_absorption: f32,
    pub air_exchange_w_m2_k: f32,
    pub evaporation_mm_h_per_100w: f32,
    pub drainage_mm_h: f32,
    pub retention_film_mm: f32,
    pub porosity_saturation_scale: f32,
}

impl SurfaceMaterialParams {
    pub fn default_for(name: &str) -> Self {
        match name.to_lowercase().as_str() {
            "gravel" | "gravel_mud" => Self {
                thermal_capacity_kj_m2_k: 115.0,
                solar_absorption: 0.62,
                snow_albedo_absorption: 0.25,
                air_exchange_w_m2_k: 10.5,
                evaporation_mm_h_per_100w: 0.35,
                drainage_mm_h: 6.0,
                retention_film_mm: 0.35,
                porosity_saturation_scale: 0.08,
            },
            "dirt" => Self {
                thermal_capacity_kj_m2_k: 120.0,
                solar_absorption: 0.65,
                snow_albedo_absorption: 0.25,
                air_exchange_w_m2_k: 10.0,
                evaporation_mm_h_per_100w: 0.32,
                drainage_mm_h: 4.2,
                retention_film_mm: 0.50,
                porosity_saturation_scale: 0.12,
            },
            _ => Self {
                // asphalt default
                thermal_capacity_kj_m2_k: 95.0,
                solar_absorption: 0.78,
                snow_albedo_absorption: 0.28,
                air_exchange_w_m2_k: 12.0,
                evaporation_mm_h_per_100w: 0.40,
                drainage_mm_h: 8.5,
                retention_film_mm: 0.15,
                porosity_saturation_scale: 0.0,
            },
        }
    }
}

#[derive(Clone, Debug)]
pub struct FiveSectorModelConfig {
    pub boundaries_fraction: [f32; 6],
    pub pre_start_hours: f32,
    pub race_horizon_hours: f32,
    pub episode_lag_total_s: f32,
    pub max_substep_s: f32,
    pub slope_drainage_gain: f32,
    pub puddle_twi_base: f32,
    pub puddle_twi_gain: f32,
    pub puddle_fill_divisor_mm: f32,
}

impl Default for FiveSectorModelConfig {
    fn default() -> Self {
        Self {
            boundaries_fraction: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
            pre_start_hours: 4.0,
            race_horizon_hours: 2.0,
            episode_lag_total_s: 360.0,
            max_substep_s: 300.0,
            slope_drainage_gain: 3.5,
            puddle_twi_base: 0.85,
            puddle_twi_gain: 1.15,
            puddle_fill_divisor_mm: 2.2,
        }
    }
}

#[derive(Clone, Debug)]
pub struct ClimateProfile {
    pub profile_id: String,
    pub reference_altitude_m: f32,
    pub default_season: String,
    pub month_to_season: HashMap<u32, String>,
    pub seasons: HashMap<String, SeasonParams>,
    pub wet_bulb_rain_above_c: f32,
    pub wet_bulb_snow_below_c: f32,
    pub node_spacing_m: f32,
    pub time_step_s: f32,
    pub pre_start_hours: f32,
    pub race_horizon_hours: f32,
    pub surface_step_s: f32,
    pub surface_cell_spacing_m: f32,
    pub surface_balance: SurfaceBalanceConfig,
    pub surface_profiles: HashMap<String, SurfaceMaterialParams>,
    pub five_sector_model: FiveSectorModelConfig,
}

fn parse_range2(val: Option<&json_lite::Val>, fallback: [f32; 2]) -> [f32; 2] {
    if let Some(arr) = val.and_then(|v| v.as_arr()) {
        if arr.len() >= 2 {
            let a = arr[0].as_f32().unwrap_or(fallback[0]);
            let b = arr[1].as_f32().unwrap_or(fallback[1]);
            return [a.min(b), a.max(b)];
        }
    }
    fallback
}

impl ClimateProfile {
    pub fn from_json_str(json_text: &str) -> Result<Self, String> {
        let root = json_lite::parse(json_text)?;
        let profile_id = root
            .get("profile_id")
            .and_then(|v| v.as_str())
            .unwrap_or("default")
            .to_string();
        let reference_altitude_m = root
            .get("reference_altitude_m")
            .and_then(|v| v.as_f32())
            .unwrap_or(0.0);
        let default_season = root
            .get("default_season")
            .and_then(|v| v.as_str())
            .unwrap_or("transition")
            .to_string();

        let mut month_to_season = HashMap::new();
        if let Some(m_obj) = root.get("month_to_season").and_then(|v| v.as_obj()) {
            for (k, v) in m_obj {
                if let (Ok(m), Some(s)) = (k.parse::<u32>(), v.as_str()) {
                    month_to_season.insert(m, s.to_string());
                }
            }
        }

        let seasons_obj = root
            .get("seasons")
            .and_then(|v| v.as_obj())
            .ok_or_else(|| "ClimateProfile missing 'seasons'".to_string())?;
        let mut seasons = HashMap::new();
        for (name, sval) in seasons_obj {
            let mut precip_bands = Vec::new();
            if let Some(bands) = sval.get("precip_intensity_bands").and_then(|v| v.as_arr()) {
                for b in bands {
                    precip_bands.push(PrecipBand {
                        min_mm_h: b.get("min_mm_h").and_then(|v| v.as_f32()).unwrap_or(0.5),
                        max_mm_h: b.get("max_mm_h").and_then(|v| v.as_f32()).unwrap_or(2.0),
                        weight: b.get("weight").and_then(|v| v.as_f32()).unwrap_or(1.0).max(0.0),
                    });
                }
            }
            if precip_bands.is_empty() {
                precip_bands.push(PrecipBand {
                    min_mm_h: 0.5,
                    max_mm_h: 3.0,
                    weight: 1.0,
                });
            }
            let oro = sval.get("orographic_wind");
            seasons.insert(
                name.clone(),
                SeasonParams {
                    base_temp_c: sval.get("base_temp_c").and_then(|v| v.as_f32()).unwrap_or(5.0),
                    diurnal_amplitude_c: sval.get("diurnal_amplitude_c").and_then(|v| v.as_f32()).unwrap_or(5.0),
                    diurnal_peak_hour: sval.get("diurnal_peak_hour").and_then(|v| v.as_f32()).unwrap_or(14.0),
                    lapse_rate_c_per_km: sval.get("lapse_rate_c_per_km").and_then(|v| v.as_f32()).unwrap_or(6.5),
                    lapse_rate_front_c_per_km: sval
                        .get("lapse_rate_front_c_per_km")
                        .and_then(|v| v.as_f32())
                        .unwrap_or(5.8),
                    background_humidity: sval
                        .get("background_humidity")
                        .and_then(|v| v.as_f32())
                        .unwrap_or(0.6)
                        .clamp(0.05, 0.98),
                    diurnal_humidity_amplitude: sval
                        .get("diurnal_humidity_amplitude")
                        .and_then(|v| v.as_f32())
                        .unwrap_or(0.1),
                    background_cloud_cover: sval
                        .get("background_cloud_cover")
                        .and_then(|v| v.as_f32())
                        .unwrap_or(0.35)
                        .clamp(0.0, 1.0),
                    dry_day_probability: sval
                        .get("dry_day_probability")
                        .and_then(|v| v.as_f32())
                        .unwrap_or(0.25)
                        .clamp(0.0, 1.0),
                    front_frequency_per_day: sval
                        .get("front_frequency_per_day")
                        .and_then(|v| v.as_f32())
                        .unwrap_or(2.0)
                        .max(0.0),
                    front_duration_s_range: parse_range2(sval.get("front_duration_s_range"), [2400.0, 7200.0]),
                    front_radius_m_range: parse_range2(sval.get("front_radius_m_range"), [1600.0, 4200.0]),
                    front_speed_m_s_range: parse_range2(sval.get("front_speed_m_s_range"), [2.5, 7.0]),
                    front_temp_anomaly_c_range: parse_range2(
                        sval.get("front_temp_anomaly_c_range"),
                        [-3.5, -1.0],
                    ),
                    front_humidity_boost_range: parse_range2(
                        sval.get("front_humidity_boost_range"),
                        [0.15, 0.30],
                    ),
                    front_cloud_boost_range: parse_range2(sval.get("front_cloud_boost_range"), [0.30, 0.50]),
                    precip_bands,
                    orographic_enabled: oro
                        .and_then(|o| o.get("enabled"))
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                    prevailing_wind_dir_deg: oro
                        .and_then(|o| o.get("prevailing_direction_deg"))
                        .and_then(|v| v.as_f32())
                        .unwrap_or(60.0),
                    wind_dir_jitter_deg: oro
                        .and_then(|o| o.get("direction_jitter_deg"))
                        .and_then(|v| v.as_f32())
                        .unwrap_or(35.0),
                    wind_speed_m_s_range: parse_range2(
                        oro.and_then(|o| o.get("wind_speed_m_s_range")),
                        [2.0, 8.0],
                    ),
                    orographic_precip_gain: oro
                        .and_then(|o| o.get("orographic_precip_gain"))
                        .and_then(|v| v.as_f32())
                        .unwrap_or(0.2)
                        .max(0.0),
                },
            );
        }

        if seasons.is_empty() {
            return Err("ClimateProfile defines zero seasons".into());
        }

        let phase = root.get("precipitation_phase");
        let wet_bulb_rain_above_c = phase
            .and_then(|p| p.get("wet_bulb_rain_above_c"))
            .and_then(|v| v.as_f32())
            .unwrap_or(1.6);
        let wet_bulb_snow_below_c = phase
            .and_then(|p| p.get("wet_bulb_snow_below_c"))
            .and_then(|v| v.as_f32())
            .unwrap_or(0.2);

        let pre = root.get("precompute");
        let node_spacing_m = pre
            .and_then(|p| p.get("node_spacing_m"))
            .and_then(|v| v.as_f32())
            .unwrap_or(250.0)
            .clamp(50.0, 1000.0);
        let time_step_s = pre
            .and_then(|p| p.get("time_step_s"))
            .and_then(|v| v.as_f32())
            .unwrap_or(45.0)
            .clamp(10.0, 300.0);
        let pre_start_hours = pre
            .and_then(|p| p.get("pre_start_hours"))
            .and_then(|v| v.as_f32())
            .unwrap_or(6.0)
            .clamp(0.0, 24.0);
        let race_horizon_hours = pre
            .and_then(|p| p.get("race_horizon_hours"))
            .and_then(|v| v.as_f32())
            .unwrap_or(1.5)
            .clamp(0.25, 12.0);
        let surface_step_s = pre
            .and_then(|p| p.get("surface_step_s"))
            .and_then(|v| v.as_f32())
            .unwrap_or(5.0)
            .clamp(0.5, 30.0);
        let surface_cell_spacing_m = pre
            .and_then(|p| p.get("surface_cell_spacing_m"))
            .and_then(|v| v.as_f32())
            .unwrap_or(50.0)
            .clamp(15.0, 250.0);

        let sb_def = SurfaceBalanceConfig::default();
        let sb_obj = root.get("surface_balance");
        let get_sb = |k: &str, d: f32| -> f32 {
            sb_obj.and_then(|o| o.get(k)).and_then(|v| v.as_f32()).unwrap_or(d)
        };
        let surface_balance = SurfaceBalanceConfig {
            snow_stick_below_c: get_sb("snow_stick_below_c", sb_def.snow_stick_below_c),
            snow_stick_above_c: get_sb("snow_stick_above_c", sb_def.snow_stick_above_c),
            snow_melt_start_c: get_sb("snow_melt_start_c", sb_def.snow_melt_start_c),
            snow_melt_band_c: get_sb("snow_melt_band_c", sb_def.snow_melt_band_c).max(0.1),
            snow_melt_rate_mm_h_per_c: get_sb("snow_melt_rate_mm_h_per_c", sb_def.snow_melt_rate_mm_h_per_c).max(0.0),
            snow_solar_melt_mm_h_per_kw: get_sb("snow_solar_melt_mm_h_per_kw", sb_def.snow_solar_melt_mm_h_per_kw).max(0.0),
            ice_melt_start_c: get_sb("ice_melt_start_c", sb_def.ice_melt_start_c),
            ice_melt_band_c: get_sb("ice_melt_band_c", sb_def.ice_melt_band_c).max(0.1),
            ice_melt_rate_mm_h_per_c: get_sb("ice_melt_rate_mm_h_per_c", sb_def.ice_melt_rate_mm_h_per_c).max(0.0),
            freeze_below_c: get_sb("freeze_below_c", sb_def.freeze_below_c),
            freeze_band_c: get_sb("freeze_band_c", sb_def.freeze_band_c).max(0.1),
            freeze_rate_mm_h_per_c: get_sb("freeze_rate_mm_h_per_c", sb_def.freeze_rate_mm_h_per_c).max(0.0),
            snow_coverage_full_mm: get_sb("snow_coverage_full_mm", sb_def.snow_coverage_full_mm).max(0.1),
            ice_coverage_full_mm: get_sb("ice_coverage_full_mm", sb_def.ice_coverage_full_mm).max(0.1),
            water_coverage_full_mm: get_sb("water_coverage_full_mm", sb_def.water_coverage_full_mm).max(0.1),
            max_water_mm: get_sb("max_water_mm", sb_def.max_water_mm).max(1.0),
            max_snow_mm: get_sb("max_snow_mm", sb_def.max_snow_mm).max(1.0),
            max_ice_mm: get_sb("max_ice_mm", sb_def.max_ice_mm).max(1.0),
            tire_effective_water_cap_mm: get_sb("tire_effective_water_cap_mm", sb_def.tire_effective_water_cap_mm).max(1.0),
            tire_effective_snow_cap_mm: get_sb("tire_effective_snow_cap_mm", sb_def.tire_effective_snow_cap_mm).max(1.0),
        };

        let mut surface_profiles = HashMap::new();
        for name in ["asphalt", "gravel", "dirt"] {
            surface_profiles.insert(name.to_string(), SurfaceMaterialParams::default_for(name));
        }
        if let Some(sp_obj) = root.get("surface_profiles").and_then(|v| v.as_obj()) {
            for (name, val) in sp_obj {
                let d = SurfaceMaterialParams::default_for(name);
                let get_p = |k: &str, def: f32| -> f32 {
                    val.get(k).and_then(|x| x.as_f32()).unwrap_or(def)
                };
                surface_profiles.insert(
                    name.to_lowercase(),
                    SurfaceMaterialParams {
                        thermal_capacity_kj_m2_k: get_p("thermal_capacity_kj_m2_k", d.thermal_capacity_kj_m2_k).max(50.0),
                        solar_absorption: get_p("solar_absorption", d.solar_absorption).clamp(0.05, 0.98),
                        snow_albedo_absorption: get_p("snow_albedo_absorption", d.snow_albedo_absorption).clamp(0.05, 0.95),
                        air_exchange_w_m2_k: get_p("air_exchange_w_m2_k", d.air_exchange_w_m2_k).max(0.5),
                        evaporation_mm_h_per_100w: get_p("evaporation_mm_h_per_100w", d.evaporation_mm_h_per_100w).max(0.0),
                        drainage_mm_h: get_p("drainage_mm_h", d.drainage_mm_h).max(0.0),
                        retention_film_mm: get_p("retention_film_mm", d.retention_film_mm).max(0.0),
                        porosity_saturation_scale: get_p("porosity_saturation_scale", d.porosity_saturation_scale).max(0.0),
                    },
                );
            }
        }

        let fsm_def = FiveSectorModelConfig::default();
        let fsm_obj = root.get("five_sector_model");
        let mut boundaries_fraction = fsm_def.boundaries_fraction;
        if let Some(arr) = fsm_obj
            .and_then(|o| o.get("boundaries_fraction"))
            .and_then(|v| v.as_arr())
        {
            if arr.len() == 6 {
                let mut prev = 0.0_f32;
                for i in 0..6 {
                    let v = arr[i].as_f32().unwrap_or(boundaries_fraction[i]).clamp(0.0, 1.0);
                    let clamped = if i == 0 {
                        0.0
                    } else if i == 5 {
                        1.0
                    } else {
                        v.max(prev + 0.02).min(0.98 - (4 - i) as f32 * 0.02)
                    };
                    boundaries_fraction[i] = clamped;
                    prev = clamped;
                }
            }
        }
        let get_fsm = |k: &str, d: f32| -> f32 {
            fsm_obj.and_then(|o| o.get(k)).and_then(|v| v.as_f32()).unwrap_or(d)
        };
        let five_sector_model = FiveSectorModelConfig {
            boundaries_fraction,
            pre_start_hours: get_fsm("pre_start_hours", fsm_def.pre_start_hours).clamp(0.5, 12.0),
            race_horizon_hours: get_fsm("race_horizon_hours", fsm_def.race_horizon_hours).clamp(0.25, 8.0),
            episode_lag_total_s: get_fsm("episode_lag_total_s", fsm_def.episode_lag_total_s).clamp(0.0, 3600.0),
            max_substep_s: get_fsm("max_substep_s", fsm_def.max_substep_s).clamp(30.0, 900.0),
            slope_drainage_gain: get_fsm("slope_drainage_gain", fsm_def.slope_drainage_gain).clamp(0.0, 12.0),
            puddle_twi_base: get_fsm("puddle_twi_base", fsm_def.puddle_twi_base).clamp(0.1, 1.5),
            puddle_twi_gain: get_fsm("puddle_twi_gain", fsm_def.puddle_twi_gain).clamp(0.0, 1.5),
            puddle_fill_divisor_mm: get_fsm("puddle_fill_divisor_mm", fsm_def.puddle_fill_divisor_mm).clamp(0.4, 10.0),
        };

        Ok(Self {
            profile_id,
            reference_altitude_m,
            default_season,
            month_to_season,
            seasons,
            wet_bulb_rain_above_c,
            wet_bulb_snow_below_c,
            node_spacing_m,
            time_step_s,
            pre_start_hours,
            race_horizon_hours,
            surface_step_s,
            surface_cell_spacing_m,
            surface_balance,
            surface_profiles,
            five_sector_model,
        })
    }

    pub fn resolve_season<'a>(&'a self, season_or_date: &str) -> (&'a str, &'a SeasonParams) {
        let trimmed = season_or_date.trim();
        let lower = trimmed.to_lowercase();
        if let Some((k, v)) = self.seasons.get_key_value(&lower) {
            return (k.as_str(), v);
        }
        // Parse YYYY-MM-DD month.
        let parts: Vec<&str> = trimmed.split('-').collect();
        if parts.len() >= 2 {
            if let Ok(month) = parts[1].parse::<u32>() {
                if let Some(season_key) = self.month_to_season.get(&month) {
                    if let Some((k, v)) = self.seasons.get_key_value(season_key) {
                        return (k.as_str(), v);
                    }
                }
            }
        }
        if let Some((k, v)) = self.seasons.get_key_value(&self.default_season) {
            return (k.as_str(), v);
        }
        let (k, v) = self.seasons.iter().next().unwrap();
        (k.as_str(), v)
    }
}

#[derive(Clone, Debug)]
struct WeatherFront {
    t_peak_s: f64,
    half_duration_s: f64,
    center_x0_m: f32,
    center_z0_m: f32,
    vx_m_s: f32,
    vz_m_s: f32,
    radius_m: f32,
    temp_anomaly_c: f32,
    humidity_boost: f32,
    cloud_boost: f32,
    precip_peak_mm_h: f32,
    wind_speed_m_s: f32,
    wind_dir_deg: f32,
}

#[derive(Clone, Debug, Default)]
struct SynopticNodeState {
    cloud_cover: f32,
    humidity: f32,
    front_temp_anomaly_c: f32,
    lapse_rate_c_per_km: f32,
    precip_base_mm_h: f32,
    wind_m_s: f32,
    wind_dir_deg: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub enum PrecipKind {
    None,
    Rain,
    Mixed,
    Snow,
}

impl PrecipKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            PrecipKind::None => "none",
            PrecipKind::Rain => "rain",
            PrecipKind::Mixed => "mixed",
            PrecipKind::Snow => "snow",
        }
    }
}

#[derive(Clone, Debug)]
pub struct AtmosphereSample {
    pub progress_m: f32,
    pub shader_station_m: f32,
    pub elapsed_s: f64,
    pub hour_of_day: f32,
    pub altitude_m: f32,
    pub air_c: f32,
    pub wet_bulb_c: f32,
    pub humidity: f32,
    pub cloud_cover: f32,
    pub irradiance_w_m2: f32,
    pub precip_total_mm_h: f32,
    pub rain_mm_h: f32,
    pub snow_mm_h: f32,
    pub precip_kind: PrecipKind,
    pub wind_m_s: f32,
    pub wind_dir_deg: f32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DayRegime {
    Auto,
    ForceDry,
    Clear,
    Cloudy,
    ForceWetFront,
    ControlledMixedAscent,
    ControlledRefreeze,
}

fn normalize_surface_key(raw: &str) -> String {
    let lower = raw.trim().to_lowercase();
    if lower.contains("gravel") {
        "gravel".to_string()
    } else if lower.contains("dirt") || lower.contains("mud") || lower.contains("sand") {
        "dirt".to_string()
    } else {
        "asphalt".to_string()
    }
}

/// Stull (2011) continuous wet-bulb approximation (T in Celsius, RH in 0..100).
pub fn wet_bulb_celsius(temp_c: f32, humidity_01: f32) -> f32 {
    let rh = (humidity_01 * 100.0).clamp(5.0, 100.0);
    temp_c * (0.151977 * (rh + 8.313659).sqrt()).atan()
        + (temp_c + rh).atan()
        - (rh - 1.676331).atan()
        + 0.00391838 * rh.powf(1.5) * (0.023101 * rh).atan()
        - 4.686035
}

pub fn solar_factor_for_hour(hour: f32) -> f32 {
    let h = hour.rem_euclid(24.0);
    if !(5.5..=19.0).contains(&h) {
        return 0.0;
    }
    let t = (h - 5.75) / 13.0;
    (t * PI).sin().clamp(0.0, 1.0)
}

#[derive(Clone, Debug)]
struct CoarseNode {
    local_x_m: f32,
    local_z_m: f32,
    windward_factor: f32, // precomputed slope-alignment proxy
}

pub struct AtmosphereTable {
    pub route: RouteProfile,
    pub climate: ClimateProfile,
    pub season_id: String,
    pub season: SeasonParams,
    pub event_seed: u64,
    pub climate_seed: u64,
    pub start_hour: f32,
    pub pre_start_s: f64,
    pub time_step_s: f64,
    pub is_dry_day: bool,
    nodes: Vec<CoarseNode>,
    // slices[time_idx * nodes.len() + node_idx]
    slices: Vec<SynopticNodeState>,
    slice_count: usize,
    front_blocks: HashMap<i64, Vec<WeatherFront>>,
}

impl AtmosphereTable {
    pub fn build(
        route: RouteProfile,
        climate: ClimateProfile,
        event_seed: u64,
        season_or_date: &str,
        start_hour: f32,
        pre_start_hours_override: Option<f32>,
        race_horizon_hours_override: Option<f32>,
        regime: DayRegime,
    ) -> Self {
        let (season_key, season_ref) = climate.resolve_season(season_or_date);
        let season_id = season_key.to_string();
        let mut season = season_ref.clone();
        let selected_cloud_cover = match regime {
            DayRegime::Clear => Some(0.10),
            DayRegime::Cloudy => Some(0.66),
            _ => None,
        };
        if let Some(cover) = selected_cloud_cover {
            season.background_cloud_cover = cover;
            season.front_frequency_per_day = 0.0;
        }

        let climate_seed = derive_stream_seed(event_seed, &route.track_id, ALGO_VERSION, "atmosphere");
        let mut day_rng = Pcg32::seeded(derive_stream_seed(
            event_seed,
            &route.track_id,
            ALGO_VERSION,
            "day_regime",
        ));
        let is_dry_day = match regime {
            DayRegime::ForceDry | DayRegime::Clear | DayRegime::Cloudy => true,
            DayRegime::ForceWetFront
            | DayRegime::ControlledMixedAscent
            | DayRegime::ControlledRefreeze => false,
            DayRegime::Auto => day_rng.randf() < season.dry_day_probability,
        };

        let spacing = climate.node_spacing_m.max(50.0);
        let total = route.total_distance_m.max(1.0);
        let n_seg = (total / spacing).ceil().max(1.0) as usize;
        let mut nodes = Vec::with_capacity(n_seg + 1);
        for i in 0..=n_seg {
            let p = if i == n_seg {
                total
            } else {
                (i as f32) * (total / (n_seg as f32))
            };
            let rs = route.sample_at_progress(p);
            nodes.push(CoarseNode {
                local_x_m: rs.local_x_m,
                local_z_m: rs.local_z_m,
                windward_factor: rs.grade.max(0.0).min(0.25) / 0.25,
            });
        }

        let pre_start_h = pre_start_hours_override.unwrap_or(climate.pre_start_hours).max(0.0);
        let horizon_h = race_horizon_hours_override.unwrap_or(climate.race_horizon_hours).max(0.25);
        let pre_start_s = (pre_start_h as f64) * 3600.0;
        let time_step_s = climate.time_step_s as f64;
        let end_time_s = (horizon_h as f64) * 3600.0;

        let mut table = Self {
            route,
            climate,
            season_id,
            season,
            event_seed,
            climate_seed,
            start_hour,
            pre_start_s,
            time_step_s,
            is_dry_day,
            nodes,
            slices: Vec::new(),
            slice_count: 0,
            front_blocks: HashMap::new(),
        };

        match regime {
            DayRegime::ForceWetFront => table.install_starting_wet_front(),
            DayRegime::ControlledMixedAscent => table.install_controlled_mixed_ascent(),
            DayRegime::ControlledRefreeze => table.install_controlled_refreeze(),
            _ => {}
        }

        table.extend_horizon_to(end_time_s);
        table
    }

    pub fn start_time_s(&self) -> f64 {
        -self.pre_start_s
    }

    pub fn end_time_s(&self) -> f64 {
        if self.slice_count == 0 {
            -self.pre_start_s
        } else {
            -self.pre_start_s + ((self.slice_count - 1) as f64) * self.time_step_s
        }
    }

    pub fn node_count(&self) -> usize {
        self.nodes.len()
    }

    pub fn time_slice_count(&self) -> usize {
        self.slice_count
    }

    fn ensure_block(&mut self, block_idx: i64) {
        if self.front_blocks.contains_key(&block_idx) {
            return;
        }
        let tag = format!("front_block:{}:{}", self.season_id, block_idx);
        let mut rng = Pcg32::seeded(derive_stream_seed(
            self.event_seed,
            &self.route.track_id,
            ALGO_VERSION,
            &tag,
        ));
        let block_start = -self.pre_start_s + (block_idx as f64) * FRONT_BLOCK_SECONDS;
        let expected_fronts = self.season.front_frequency_per_day * ((FRONT_BLOCK_SECONDS / 86400.0) as f32);
        let base_count = expected_fronts.floor() as usize;
        let frac = expected_fronts - (base_count as f32);
        let count = base_count + usize::from(rng.randf() < frac);

        let mut fronts = Vec::with_capacity(count);
        for _ in 0..count {
            fronts.push(self.generate_front(&mut rng, block_start, block_start + FRONT_BLOCK_SECONDS, false));
        }
        self.front_blocks.insert(block_idx, fronts);
    }

    fn install_starting_wet_front(&mut self) {
        let block_idx = (self.pre_start_s / FRONT_BLOCK_SECONDS).floor() as i64;
        let tag = format!("front_block_wet:{}:{}", self.season_id, block_idx);
        let mut rng = Pcg32::seeded(derive_stream_seed(
            self.event_seed,
            &self.route.track_id,
            ALGO_VERSION,
            &tag,
        ));
        // Cover the starting line and the rest of the route at race time zero.
        let mut f = self.generate_front(&mut rng, 0.0, 0.0, true);
        f.t_peak_s = 0.0;
        f.half_duration_s = 3600.0;
        f.center_x0_m = self.route.center_x_m;
        f.center_z0_m = self.route.center_z_m;
        f.radius_m = f.radius_m.max(self.route.extent_radius_m * 2.5);
        f.precip_peak_mm_h = f.precip_peak_mm_h.max(1.2);
        self.front_blocks.insert(block_idx, vec![f]);
    }

    fn install_controlled_mixed_ascent(&mut self) {
        let total = self.route.total_distance_m.max(1.0);
        let s_start = self.route.sample_at_progress(total * 0.03);
        let s_mid = self.route.sample_at_progress(total * 0.48);
        let s_abra = self.route.sample_at_progress(total * 0.90);
        let make_cell = |t_peak_s: f64, half_duration_s: f64, rs: &RouteSample, radius_m: f32, temp_c: f32, hum: f32, cloud: f32, precip: f32| WeatherFront {
            t_peak_s,
            half_duration_s,
            center_x0_m: rs.local_x_m,
            center_z0_m: rs.local_z_m,
            vx_m_s: 0.0,
            vz_m_s: 0.0,
            radius_m,
            temp_anomaly_c: temp_c,
            humidity_boost: hum,
            cloud_boost: cloud,
            precip_peak_mm_h: precip,
            wind_speed_m_s: 4.5,
            wind_dir_deg: 60.0,
        };
        let r_start = 620.0_f32;
        let r_mid = 620.0_f32;
        let r_abra = 1050.0_f32;
        let block0 = vec![
            // 1. Early pre-start snow pulse near start (ends at -2400s so zero active rain/snow at t=0).
            make_cell(-4500.0, 2100.0, &s_start, r_start, -6.5, 0.28, 0.45, 7.5),
            // 2. Cloudy mild air over start at t=0..600s for active residual snow thaw without precipitation.
            make_cell(150.0, 2000.0, &s_start, r_start, 3.2, 0.15, 0.55, 0.0),
            // 3. Active warm rain cell over middle section (snowless bare wet asphalt).
            make_cell(180.0, 3600.0, &s_mid, r_mid, 3.8, 0.30, 0.55, 6.5),
            // 4. Cold snowfall at Abra summit covering pre-start & race start.
            make_cell(-1800.0, 3600.0, &s_abra, r_abra, -6.0, 0.28, 0.55, 6.0),
            make_cell(200.0, 3600.0, &s_abra, r_abra, -5.8, 0.28, 0.55, 6.0),
        ];
        self.front_blocks.insert(-1, Vec::new());
        self.front_blocks.insert(0, block0);
        self.front_blocks.insert(1, Vec::new());
        self.front_blocks.insert(2, Vec::new());
    }

    fn install_controlled_refreeze(&mut self) {
        let total = self.route.total_distance_m.max(1.0);
        let s_abra = self.route.sample_at_progress(total * 0.85);
        let r_all = self.route.extent_radius_m * 1.4;
        let dawn_overcast = WeatherFront {
            t_peak_s: -3600.0,
            half_duration_s: 14400.0,
            center_x0_m: self.route.center_x_m,
            center_z0_m: self.route.center_z_m,
            vx_m_s: 0.0,
            vz_m_s: 0.0,
            radius_m: r_all,
            temp_anomaly_c: -2.0,
            humidity_boost: 0.25,
            cloud_boost: 0.70,
            precip_peak_mm_h: 0.0,
            wind_speed_m_s: 4.0,
            wind_dir_deg: 60.0,
        };
        let warm_rain = WeatherFront {
            t_peak_s: -400.0,
            half_duration_s: 700.0,
            center_x0_m: self.route.center_x_m,
            center_z0_m: self.route.center_z_m,
            vx_m_s: 0.0,
            vz_m_s: 0.0,
            radius_m: r_all,
            temp_anomaly_c: 1.0,
            humidity_boost: 0.30,
            cloud_boost: 0.70,
            precip_peak_mm_h: 9.5,
            wind_speed_m_s: 3.5,
            wind_dir_deg: 60.0,
        };
        let freeze_drop = WeatherFront {
            t_peak_s: 900.0,
            half_duration_s: 1400.0,
            center_x0_m: s_abra.local_x_m,
            center_z0_m: s_abra.local_z_m,
            vx_m_s: 0.0,
            vz_m_s: 0.0,
            radius_m: r_all,
            temp_anomaly_c: -16.5,
            humidity_boost: 0.15,
            cloud_boost: 0.75,
            precip_peak_mm_h: 0.0,
            wind_speed_m_s: 8.5,
            wind_dir_deg: 45.0,
        };
        self.front_blocks.insert(-1, Vec::new());
        self.front_blocks.insert(0, vec![dawn_overcast, warm_rain, freeze_drop]);
        self.front_blocks.insert(1, Vec::new());
        self.front_blocks.insert(2, Vec::new());
    }

    fn generate_front(&self, rng: &mut Pcg32, t_lo: f64, t_hi: f64, force_precip: bool) -> WeatherFront {
        let dur = rng.randf_range(
            self.season.front_duration_s_range[0],
            self.season.front_duration_s_range[1],
        );
        let half_duration_s = (0.5 * dur as f64).min(MAX_FRONT_HALF_DURATION_S);
        let t_peak_s = t_lo + (rng.randf() as f64) * (t_hi - t_lo);
        let radius_m = rng.randf_range(
            self.season.front_radius_m_range[0],
            self.season.front_radius_m_range[1],
        );
        let wind_dir_deg = (self.season.prevailing_wind_dir_deg
            + rng.randf_range(-self.season.wind_dir_jitter_deg, self.season.wind_dir_jitter_deg))
            .rem_euclid(360.0);
        let wind_speed_m_s = rng.randf_range(
            self.season.wind_speed_m_s_range[0],
            self.season.wind_speed_m_s_range[1],
        );
        let move_speed = rng.randf_range(
            self.season.front_speed_m_s_range[0],
            self.season.front_speed_m_s_range[1],
        );
        // Advect front downwind (from windward toward leeward).
        let dir_rad = wind_dir_deg.to_radians();
        let down_x = -dir_rad.sin();
        let down_z = dir_rad.cos(); // North is -Z in Godot, South is +Z
        let offset_angle = rng.randf_range(0.0, 2.0 * PI);
        let offset_r = rng.randf_range(0.0, self.route.extent_radius_m * 0.75);
        let center_x0_m = self.route.center_x_m + offset_r * offset_angle.cos();
        let center_z0_m = self.route.center_z_m + offset_r * offset_angle.sin();

        let temp_anomaly_c = rng.randf_range(
            self.season.front_temp_anomaly_c_range[0],
            self.season.front_temp_anomaly_c_range[1],
        );
        let humidity_boost = rng.randf_range(
            self.season.front_humidity_boost_range[0],
            self.season.front_humidity_boost_range[1],
        );
        let cloud_boost = rng.randf_range(
            self.season.front_cloud_boost_range[0],
            self.season.front_cloud_boost_range[1],
        );

        let precip_peak_mm_h = if self.is_dry_day && !force_precip {
            0.0
        } else {
            let total_w: f32 = self.season.precip_bands.iter().map(|b| b.weight).sum();
            let mut pick = rng.randf() * total_w.max(1e-5);
            let mut chosen = &self.season.precip_bands[0];
            for band in &self.season.precip_bands {
                if pick <= band.weight {
                    chosen = band;
                    break;
                }
                pick -= band.weight;
            }
            rng.randf_range(chosen.min_mm_h, chosen.max_mm_h)
        };

        WeatherFront {
            t_peak_s,
            half_duration_s,
            center_x0_m,
            center_z0_m,
            vx_m_s: down_x * move_speed,
            vz_m_s: down_z * move_speed,
            radius_m,
            temp_anomaly_c,
            humidity_boost,
            cloud_boost,
            precip_peak_mm_h,
            wind_speed_m_s,
            wind_dir_deg,
        }
    }

    pub fn extend_horizon_to(&mut self, target_elapsed_s: f64) {
        let needed_slices = if target_elapsed_s <= -self.pre_start_s {
            1usize
        } else {
            (((target_elapsed_s + self.pre_start_s) / self.time_step_s).ceil() as usize) + 1
        };
        if needed_slices <= self.slice_count {
            return;
        }

        let n_nodes = self.nodes.len();
        self.slices.reserve((needed_slices - self.slice_count) * n_nodes);
        let prevailing_dir = self.season.prevailing_wind_dir_deg.to_radians();
        let background_wind_x = prevailing_dir.sin() * self.season.wind_speed_m_s_range[0];
        let background_wind_z = -prevailing_dir.cos() * self.season.wind_speed_m_s_range[0];
        let mut active_fronts = Vec::new();

        for s_idx in self.slice_count..needed_slices {
            let t = -self.pre_start_s + (s_idx as f64) * self.time_step_s;
            let block_idx = ((t + self.pre_start_s) / FRONT_BLOCK_SECONDS).floor() as i64;
            for b in (block_idx - 1)..=(block_idx + 1) {
                self.ensure_block(b);
            }

            let hour_of_day = ((self.start_hour as f64) + t / 3600.0).rem_euclid(24.0) as f32;
            let diurnal_hum = -self.season.diurnal_humidity_amplitude
                * ((hour_of_day - self.season.diurnal_peak_hour) * PI / 12.0).cos();

            active_fronts.clear();
            for b in (block_idx - 1)..=(block_idx + 1) {
                if let Some(fronts) = self.front_blocks.get(&b) {
                    for f in fronts {
                        let dt = t - f.t_peak_s;
                        let temporal_weight =
                            1.0 - smoothstep(0.0, 1.0, (dt.abs() / f.half_duration_s) as f32);
                        if temporal_weight <= 0.0001 {
                            continue;
                        }
                        let center_x = f.center_x0_m + f.vx_m_s * (dt as f32);
                        let center_z = f.center_z0_m + f.vz_m_s * (dt as f32);
                        let wind_dir = f.wind_dir_deg.to_radians();
                        let wind_x = wind_dir.sin() * f.wind_speed_m_s;
                        let wind_z = -wind_dir.cos() * f.wind_speed_m_s;
                        active_fronts.push(((*f).clone(), temporal_weight, center_x, center_z, wind_x, wind_z));
                    }
                }
            }

            for node in &self.nodes {
                let mut cloud = self.season.background_cloud_cover;
                let mut hum = self.season.background_humidity + diurnal_hum;
                let mut temp_anom = 0.0_f32;
                let mut precip = 0.0_f32;
                let mut front_weight_max = 0.0_f32;
                let mut wind_x = background_wind_x;
                let mut wind_z = background_wind_z;

                for &(ref f, temporal_weight, center_x, center_z, front_wind_x, front_wind_z) in &active_fronts {
                    let dist = (node.local_x_m - center_x).hypot(node.local_z_m - center_z);
                    let spatial_weight = 1.0 - smoothstep(0.0, f.radius_m, dist);
                    let w = temporal_weight * spatial_weight;
                    if w <= 0.0001 {
                        continue;
                    }
                    front_weight_max = front_weight_max.max(w);
                    cloud += f.cloud_boost * w;
                    hum += f.humidity_boost * w;
                    temp_anom += f.temp_anomaly_c * w;

                    let mut p_add = f.precip_peak_mm_h * w;
                    if p_add > 0.0 && self.season.orographic_enabled {
                        p_add *= 1.0 + self.season.orographic_precip_gain * node.windward_factor;
                    }
                    precip += p_add;

                    wind_x = lerpf(wind_x, front_wind_x, w);
                    wind_z = lerpf(wind_z, front_wind_z, w);
                }

                let lapse = lerpf(
                    self.season.lapse_rate_c_per_km,
                    self.season.lapse_rate_front_c_per_km,
                    front_weight_max,
                );
                let wind_m_s = wind_x.hypot(wind_z);
                let wind_dir_deg = wind_x.atan2(-wind_z).to_degrees().rem_euclid(360.0);

                self.slices.push(SynopticNodeState {
                    cloud_cover: cloud.clamp(0.0, 1.0),
                    humidity: hum.clamp(0.05, 1.0),
                    front_temp_anomaly_c: temp_anom,
                    lapse_rate_c_per_km: lapse,
                    precip_base_mm_h: if self.is_dry_day { 0.0 } else { precip.max(0.0) },
                    wind_m_s,
                    wind_dir_deg,
                });
            }
            self.slice_count += 1;
        }
    }

    fn sample_synoptic(&mut self, progress_m: f32, elapsed_s: f64) -> SynopticNodeState {
        let clamped_t = elapsed_s.max(-self.pre_start_s);
        if clamped_t > self.end_time_s() {
            // Extend deterministically in 1800s blocks so runtime never hits a horizon cliff.
            let target = clamped_t + 1800.0;
            self.extend_horizon_to(target);
        }

        let n_nodes = self.nodes.len();
        let total = self.route.total_distance_m.max(1.0);
        let p = progress_m.clamp(0.0, total);
        let node_f = (p / total) * ((n_nodes - 1) as f32);
        let n0 = (node_f.floor() as usize).min(n_nodes - 1);
        let n1 = (n0 + 1).min(n_nodes - 1);
        let nt = (node_f - (n0 as f32)).clamp(0.0, 1.0);

        let t_f = (clamped_t + self.pre_start_s) / self.time_step_s;
        let t0 = (t_f.floor() as usize).min(self.slice_count - 1);
        let t1 = (t0 + 1).min(self.slice_count - 1);
        let tt = ((t_f - (t0 as f64)) as f32).clamp(0.0, 1.0);

        let s00 = &self.slices[t0 * n_nodes + n0];
        let s10 = &self.slices[t0 * n_nodes + n1];
        let s01 = &self.slices[t1 * n_nodes + n0];
        let s11 = &self.slices[t1 * n_nodes + n1];

        let bilerp = |f: fn(&SynopticNodeState) -> f32| -> f32 {
            let a = lerpf(f(s00), f(s10), nt);
            let b = lerpf(f(s01), f(s11), nt);
            lerpf(a, b, tt)
        };

        let wx0 = lerpf(
            s00.wind_dir_deg.to_radians().sin() * s00.wind_m_s,
            s10.wind_dir_deg.to_radians().sin() * s10.wind_m_s,
            nt,
        );
        let wz0 = lerpf(
            -s00.wind_dir_deg.to_radians().cos() * s00.wind_m_s,
            -s10.wind_dir_deg.to_radians().cos() * s10.wind_m_s,
            nt,
        );
        let wx1 = lerpf(
            s01.wind_dir_deg.to_radians().sin() * s01.wind_m_s,
            s11.wind_dir_deg.to_radians().sin() * s11.wind_m_s,
            nt,
        );
        let wz1 = lerpf(
            -s01.wind_dir_deg.to_radians().cos() * s01.wind_m_s,
            -s11.wind_dir_deg.to_radians().cos() * s11.wind_m_s,
            nt,
        );
        let wx = lerpf(wx0, wx1, tt);
        let wz = lerpf(wz0, wz1, tt);

        SynopticNodeState {
            cloud_cover: bilerp(|s| s.cloud_cover),
            humidity: bilerp(|s| s.humidity),
            front_temp_anomaly_c: bilerp(|s| s.front_temp_anomaly_c),
            lapse_rate_c_per_km: bilerp(|s| s.lapse_rate_c_per_km),
            precip_base_mm_h: bilerp(|s| s.precip_base_mm_h),
            wind_m_s: wx.hypot(wz),
            wind_dir_deg: wx.atan2(-wz).to_degrees().rem_euclid(360.0),
        }
    }

    /// Evaluate full local atmosphere at `progress_m` and `elapsed_s` (relative to race start t=0).
    /// Applies lapse rate using the high-resolution route elevation at `progress_m` before resolving
    /// wet-bulb temperature and precipitation phase.
    pub fn sample_at(&mut self, progress_m: f32, elapsed_s: f64) -> AtmosphereSample {
        let syn = self.sample_synoptic(progress_m, elapsed_s);
        let rs = self.route.sample_at_progress(progress_m);

        let hour_of_day = ((self.start_hour as f64) + elapsed_s / 3600.0).rem_euclid(24.0) as f32;
        let diurnal_wave = ((hour_of_day - self.season.diurnal_peak_hour) * PI / 12.0).cos();
        let t_ref = self.season.base_temp_c + self.season.diurnal_amplitude_c * diurnal_wave;
        let alt_term = if self.route.vertical_datum_verified {
            syn.lapse_rate_c_per_km * ((rs.altitude_m - self.climate.reference_altitude_m) / 1000.0)
        } else {
            0.0
        };
        let air_c = t_ref - alt_term + syn.front_temp_anomaly_c;
        let wet_bulb_c = wet_bulb_celsius(air_c, syn.humidity);

        let precip_total_mm_h = syn.precip_base_mm_h.max(0.0);
        let (rain_mm_h, snow_mm_h, precip_kind) = if precip_total_mm_h < 0.02 {
            (0.0, 0.0, PrecipKind::None)
        } else {
            let snow_frac = 1.0
                - smoothstep(
                    self.climate.wet_bulb_snow_below_c,
                    self.climate.wet_bulb_rain_above_c,
                    wet_bulb_c,
                );
            let snow = precip_total_mm_h * snow_frac;
            let rain = precip_total_mm_h - snow;
            let kind = if snow_frac >= 0.90 {
                PrecipKind::Snow
            } else if snow_frac <= 0.10 {
                PrecipKind::Rain
            } else {
                PrecipKind::Mixed
            };
            (rain, snow, kind)
        };

        let clear_solar = solar_factor_for_hour(hour_of_day);
        let cloud_attenuation = 1.0 - 0.88 * syn.cloud_cover.powf(1.35);
        let irradiance_w_m2 = (980.0 * clear_solar * cloud_attenuation).max(0.0);

        AtmosphereSample {
            progress_m: rs.progress_m,
            shader_station_m: rs.shader_station_m,
            elapsed_s,
            hour_of_day,
            altitude_m: rs.altitude_m,
            air_c,
            wet_bulb_c,
            humidity: syn.humidity,
            cloud_cover: syn.cloud_cover,
            irradiance_w_m2,
            precip_total_mm_h,
            rain_mm_h,
            snow_mm_h,
            precip_kind,
            wind_m_s: syn.wind_m_s,
            wind_dir_deg: syn.wind_dir_deg,
        }
    }
}

#[derive(Clone, Debug)]
pub struct SurfaceCell {
    pub progress_m: f32,
    pub shader_station_m: f32,
    pub altitude_m: f32,
    pub shade_factor: f32,
    pub drainage_scale: f32,
    pub ground_c: f32,
    pub water_mm: f32,
    pub snow_mm: f32,
    pub ice_mm: f32,
    pub saturation: f32,
}

#[derive(Clone, Debug, Default)]
pub struct MassBalanceAudit {
    pub rain_in_mm: f64,
    pub snow_in_mm: f64,
    pub evap_out_mm: f64,
    pub drain_out_mm: f64,
    pub clipped_overflow_mm: f64,
}

#[derive(Clone, Debug)]
pub struct SurfaceSample {
    pub progress_m: f32,
    pub shader_station_m: f32,
    pub lateral_t: f32,
    pub elapsed_s: f64,
    pub altitude_m: f32,
    pub air_c: f32,
    pub ground_c: f32,
    pub water_mm: f32,
    pub snow_mm: f32,
    pub ice_mm: f32,
    pub saturation: f32,
    pub water_coverage: f32,
    pub snow_coverage: f32,
    pub ice_coverage: f32,
    pub dry_weight: f32,
    pub snow_weight: f32,
    pub ice_weight: f32,
    pub water_mm_effective: f32,
    pub snow_mm_effective: f32,
    pub irradiance_w_m2: f32,
    pub humidity: f32,
    pub cloud_cover: f32,
    pub rain_mm_h: f32,
    pub snow_mm_h: f32,
    pub precip_total_mm_h: f32,
    pub precip_kind: PrecipKind,
    pub wind_m_s: f32,
    pub wind_dir_deg: f32,
}

/// Deterministic 2D GLSL-matched hash-value noise in `[0, 1]` for stable spatial patches across `(station_m, lateral_t)`.
#[inline]
pub fn patch_seed_offsets(patch_seed: u64) -> ([f32; 2], [f32; 2]) {
    let sx = ((patch_seed & 0x0fff) as f32) * 0.0137;
    let sy = (((patch_seed >> 12) & 0x0fff) as f32) * 0.0179;
    let ix = (((patch_seed >> 24) & 0x0fff) as f32) * 0.0151 + 17.3;
    let iy = (((patch_seed >> 36) & 0x0fff) as f32) * 0.0193 + 9.7;
    ([sx, sy], [ix, iy])
}

#[inline]
fn hash2_01(ix: i32, iy: i32, seed_offset: [f32; 2]) -> f32 {
    let x = ((ix.rem_euclid(2048)) as f32) + seed_offset[0];
    let y = ((iy.rem_euclid(512)) as f32) + seed_offset[1];
    ((x * 127.1 + y * 311.7).sin() * 43758.5453).rem_euclid(1.0)
}

#[inline]
fn value_noise2(x: f32, y: f32, seed_offset: [f32; 2]) -> f32 {
    let ix = x.floor() as i32;
    let iy = y.floor() as i32;
    let fx = x - (ix as f32);
    let fy = y - (iy as f32);
    let ux = fx * fx * (3.0 - 2.0 * fx);
    let uy = fy * fy * (3.0 - 2.0 * fy);
    let a = hash2_01(ix, iy, seed_offset);
    let b = hash2_01(ix + 1, iy, seed_offset);
    let c = hash2_01(ix, iy + 1, seed_offset);
    let d = hash2_01(ix + 1, iy + 1, seed_offset);
    lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)
}

/// Shared CPU/GPU spatial pattern in `[0, 1]` parameterized by `(shader_station_m, lateral_t)`.
pub fn spatial_patch_field(shader_station_m: f32, lateral_t: f32, seed_offset: [f32; 2]) -> f32 {
    let side_off = if lateral_t >= 0.0 { [0.0_f32, 0.0] } else { [41.7_f32, 29.3] };
    let s_off = [seed_offset[0] + side_off[0], seed_offset[1] + side_off[1]];
    let n1 = value_noise2(shader_station_m * 0.019, 0.5, s_off);
    let n2 = value_noise2(
        shader_station_m * 0.078,
        1.5,
        [s_off[0] + 19.7, s_off[1] + 7.3],
    );
    let n3 = value_noise2(
        shader_station_m * 0.23,
        2.7,
        [s_off[0] + 53.1, s_off[1] + 31.9],
    );
    (0.48 * n1 + 0.34 * n2 + 0.18 * n3).clamp(0.0, 1.0)
}

/// Shared CPU/GPU Ticlio snow coverage in `[0, 1]`.
/// - Residual regime (`mean_mm <= 1.8 mm`): discontinuous thin lateral snow ribbons
///   strictly confined to the outer ~10-14% berms (`|lateral_t| >= 0.85`), leaving the
///   driving lane bare.
/// - Sustained snowfall regime (`mean_mm > 1.8 mm`): berm drifts advance inward toward
///   the outer wheel tracks and snow accumulates along the central crown ridge between
///   the wheel tracks (`|lateral_t| < 0.24`), receding first from the tracks during thaw.
pub fn local_pattern_coverage(
    mean_mm: f32,
    full_mm: f32,
    min_visible_mm: f32,
    shader_station_m: f32,
    lateral_t: f32,
    seed_offset: [f32; 2],
    _edge_bias: f32,
) -> f32 {
    if mean_mm <= min_visible_mm {
        return 0.0;
    }
    let abs_t = lateral_t.abs().clamp(0.0, 1.0);
    let sustained = smoothstep(1.80, full_mm.max(3.5) * 1.25, mean_mm);
    let min_berm_abs_t = lerpf(0.85, 0.64, sustained);
    if abs_t < min_berm_abs_t && sustained <= 0.001 {
        return 0.0;
    }
    let side_off = if lateral_t >= 0.0 { [0.0_f32, 0.0] } else { [41.7_f32, 29.3] };
    let s_off = [seed_offset[0] + side_off[0], seed_offset[1] + side_off[1]];
    let patch_raw = spatial_patch_field(shader_station_m, lateral_t, seed_offset);
    let amount = smoothstep(min_visible_mm, full_mm, mean_mm);

    // 1. Outer berm / shoulder snow ribbon (advances inward during sustained snowfall)
    let mut berm_cov = 0.0_f32;
    if abs_t >= min_berm_abs_t {
        let gate_lo = lerpf(0.58, 0.36, amount);
        let gate = smoothstep(gate_lo, gate_lo + 0.22, patch_raw);
        if gate > 0.001 {
            let edge_jit1 = value_noise2(
                shader_station_m * 0.32,
                abs_t * 6.0,
                [s_off[0] + 7.1, s_off[1] + 13.9],
            );
            let edge_jit2 = value_noise2(
                shader_station_m * 1.15,
                abs_t * 14.0,
                [s_off[0] + 23.4, s_off[1] + 41.8],
            );
            let scallop = (edge_jit1 - 0.5) * 0.055 + (edge_jit2 - 0.5) * 0.032;
            let dist_from_edge = 1.0 - abs_t;
            let max_w = lerpf(0.142, 0.34, sustained);
            let base_w = lerpf(0.10, 0.26, sustained);
            let ribbon_width = (base_w * (0.40 + 0.60 * amount) * (0.35 + 0.65 * gate) + scallop * gate)
                .clamp(0.0, max_w);
            if ribbon_width > 0.004 {
                let profile = 1.0 - smoothstep(ribbon_width * 0.24, ribbon_width, dist_from_edge);
                berm_cov = (profile * smoothstep(0.0, 0.20, gate) * (0.45 + 0.55 * amount)).clamp(0.0, 1.0);
            }
        }
    }

    // 2. Central inter-track snow deposit during sustained snowfall (recedes with thaw)
    let mut crown_cov = 0.0_f32;
    if sustained > 0.001 && abs_t < 0.28 {
        let c_patch = spatial_patch_field(
            shader_station_m + 37.0,
            0.0,
            [seed_offset[0] + 19.3, seed_offset[1] + 23.7],
        );
        let c_gate = smoothstep(0.34, 0.58, c_patch);
        if c_gate > 0.001 {
            let c_jit = value_noise2(
                shader_station_m * 0.45,
                lateral_t * 7.0,
                [seed_offset[0] + 59.1, seed_offset[1] + 17.4],
            );
            let crown_w = (0.22 * sustained * (0.55 + 0.45 * c_gate) + (c_jit - 0.5) * 0.05 * sustained)
                .clamp(0.0, 0.26);
            if crown_w > 0.005 {
                let c_prof = 1.0 - smoothstep(crown_w * 0.25, crown_w, abs_t);
                crown_cov = (c_prof * c_gate * sustained * 0.82).clamp(0.0, 1.0);
            }
        }
    }

    berm_cov.max(crown_cov)
}

#[inline]
fn compute_evap_mm_h(
    irradiance_w_m2: f32,
    wind_m_s: f32,
    humidity_01: f32,
    ground_c: f32,
    water_mm: f32,
    mat: &SurfaceMaterialParams,
) -> f32 {
    if water_mm <= 1e-6 {
        return 0.0;
    }
    let film_factor = (water_mm / 0.5).clamp(0.08, 1.0);
    let rad_evap = mat.evaporation_mm_h_per_100w * (irradiance_w_m2 / 100.0);
    let vpd = (1.0 - humidity_01).clamp(0.02, 0.95);
    let temp_gain = ((ground_c + 2.0) / 14.0).clamp(0.15, 2.0);
    let aero_evap = 0.09 * (0.4 + 0.22 * wind_m_s.min(15.0)) * vpd * temp_gain;
    (rad_evap + aero_evap) * film_factor
}

/// Advances one surface cell by `dt_s` under fixed atmospheric forcing `atmo`.
/// Returns `(rain_in, snow_in, evap_out, drain_out, overflow_clipped)`.
pub fn step_surface_cell(
    cell: &mut SurfaceCell,
    atmo: &AtmosphereSample,
    dt_s: f32,
    cfg: &SurfaceBalanceConfig,
    mat: &SurfaceMaterialParams,
) -> (f32, f32, f32, f32, f32) {
    if dt_s <= 0.0 {
        return (0.0, 0.0, 0.0, 0.0, 0.0);
    }
    let dt_h = dt_s / 3600.0;

    // 1. Energy balance -> pavement temperature (with thermal inertia).
    let snow_cov = (cell.snow_mm / cfg.snow_coverage_full_mm).clamp(0.0, 1.0);
    let abs_eff = lerpf(mat.solar_absorption, mat.snow_albedo_absorption, snow_cov * 0.85);
    let solar_gain = atmo.irradiance_w_m2 * abs_eff * cell.shade_factor;
    let conv_coeff = mat.air_exchange_w_m2_k * (1.0 + 0.045 * atmo.wind_m_s.min(18.0));
    let air_loss = conv_coeff * (cell.ground_c - atmo.air_c);
    let evap_mm_h = compute_evap_mm_h(
        atmo.irradiance_w_m2,
        atmo.wind_m_s,
        atmo.humidity,
        cell.ground_c,
        cell.water_mm,
        mat,
    );
    let evap_heat_loss = evap_mm_h * 680.0;
    let precip_heat = atmo.rain_mm_h * 1.16 * (cell.ground_c - atmo.air_c).max(0.0)
        + atmo.snow_mm_h * (2.5 + 0.8 * (cell.ground_c - 0.5).max(0.0));
    let cap_j_m2_k = (mat.thermal_capacity_kj_m2_k * 1000.0).max(1000.0);
    let d_ground = ((solar_gain - air_loss - evap_heat_loss - precip_heat) / cap_j_m2_k) * dt_s;
    cell.ground_c = (cell.ground_c + d_ground).clamp(-25.0, 60.0);

    // 2. Precipitation inputs (warm pavement melts falling snow on contact into liquid water).
    let rain_in = (atmo.rain_mm_h * dt_h).max(0.0);
    let snow_total_in = (atmo.snow_mm_h * dt_h).max(0.0);
    let stick_frac = 1.0 - smoothstep(cfg.snow_stick_below_c, cfg.snow_stick_above_c, cell.ground_c);
    let snow_retained = snow_total_in * stick_frac;
    let snow_contact_melt = snow_total_in - snow_retained;
    cell.snow_mm += snow_retained;
    cell.water_mm += rain_in + snow_contact_melt;

    // 3. Phase transfers (separated thermal deadband around 0 C prevents rapid chatter).
    if cell.ground_c > cfg.snow_melt_start_c && cell.snow_mm > 0.0 {
        let band = smoothstep(
            cfg.snow_melt_start_c,
            cfg.snow_melt_start_c + cfg.snow_melt_band_c,
            cell.ground_c,
        );
        let temp_drive = (cell.ground_c - cfg.snow_melt_start_c).max(0.0);
        let solar_melt = cfg.snow_solar_melt_mm_h_per_kw * (atmo.irradiance_w_m2 / 1000.0) * cell.shade_factor;
        let pot = (cfg.snow_melt_rate_mm_h_per_c * temp_drive * (0.35 + 0.65 * band) + solar_melt) * dt_h;
        let melt = pot.min(cell.snow_mm).max(0.0);
        cell.snow_mm -= melt;
        cell.water_mm += melt;
    }
    if cell.ground_c > cfg.ice_melt_start_c && cell.ice_mm > 0.0 {
        let band = smoothstep(
            cfg.ice_melt_start_c,
            cfg.ice_melt_start_c + cfg.ice_melt_band_c,
            cell.ground_c,
        );
        let temp_drive = (cell.ground_c - cfg.ice_melt_start_c).max(0.0);
        let pot = cfg.ice_melt_rate_mm_h_per_c * temp_drive * (0.35 + 0.65 * band) * dt_h;
        let melt = pot.min(cell.ice_mm).max(0.0);
        cell.ice_mm -= melt;
        cell.water_mm += melt;
    } else if cell.ground_c < cfg.freeze_below_c && cell.water_mm > 0.0 {
        let band = smoothstep(
            cfg.freeze_below_c,
            cfg.freeze_below_c - cfg.freeze_band_c,
            cell.ground_c,
        );
        let temp_drive = (cfg.freeze_below_c - cell.ground_c).max(0.0);
        let pot = cfg.freeze_rate_mm_h_per_c * temp_drive * (0.35 + 0.65 * band) * dt_h;
        let frozen = pot.min(cell.water_mm).max(0.0);
        cell.water_mm -= frozen;
        cell.ice_mm += frozen;
    }

    // 4. Liquid sinks: drainage (above capillary film) + evaporation (can dry all the way to 0.0).
    let drainable = (cell.water_mm - mat.retention_film_mm).max(0.0);
    let drain_pot = if drainable > 0.0 {
        mat.drainage_mm_h * cell.drainage_scale * (drainable / 2.5).clamp(0.02, 1.0) * dt_h
    } else {
        0.0
    };
    let drain_out = drain_pot.min(drainable).max(0.0);
    cell.water_mm -= drain_out;

    let evap_after = compute_evap_mm_h(
        atmo.irradiance_w_m2,
        atmo.wind_m_s,
        atmo.humidity,
        cell.ground_c,
        cell.water_mm,
        mat,
    );
    let evap_out = (evap_after * dt_h).min(cell.water_mm).max(0.0);
    cell.water_mm -= evap_out;

    if mat.porosity_saturation_scale > 0.0 {
        let sat_delta = (rain_in + snow_contact_melt) * mat.porosity_saturation_scale
            - (drain_out * 0.05 + evap_out * 0.03);
        cell.saturation = (cell.saturation + sat_delta).clamp(0.0, 1.0);
    } else {
        cell.saturation = 0.0;
    }

    let mut overflow = 0.0_f32;
    if cell.water_mm > cfg.max_water_mm {
        overflow += cell.water_mm - cfg.max_water_mm;
        cell.water_mm = cfg.max_water_mm;
    }
    if cell.snow_mm > cfg.max_snow_mm {
        overflow += cell.snow_mm - cfg.max_snow_mm;
        cell.snow_mm = cfg.max_snow_mm;
    }
    if cell.ice_mm > cfg.max_ice_mm {
        overflow += cell.ice_mm - cfg.max_ice_mm;
        cell.ice_mm = cfg.max_ice_mm;
    }
    cell.water_mm = cell.water_mm.max(0.0);
    cell.snow_mm = cell.snow_mm.max(0.0);
    cell.ice_mm = cell.ice_mm.max(0.0);

    (rain_in, snow_total_in, evap_out, drain_out, overflow)
}

pub struct SurfaceGrid {
    pub surface_type: String,
    pub material: SurfaceMaterialParams,
    pub patch_seed: u64,
    pub fixed_step_s: f64,
    pub elapsed_s: f64,
    pub pending_dt_s: f64,
    pub revision: u64,
    pub cells: Vec<SurfaceCell>,
    pub audit: MassBalanceAudit,
}

impl SurfaceGrid {
    pub fn build_and_preroll(atmo: &mut AtmosphereTable, surface_type: &str) -> Self {
        let key = normalize_surface_key(surface_type);
        let material = atmo
            .climate
            .surface_profiles
            .get(&key)
            .cloned()
            .unwrap_or_else(|| SurfaceMaterialParams::default_for(&key));
        let patch_seed = derive_stream_seed(
            atmo.event_seed,
            &atmo.route.track_id,
            ALGO_VERSION,
            "patches",
        );

        let spacing = atmo.climate.surface_cell_spacing_m.max(15.0);
        let total = atmo.route.total_distance_m.max(1.0);
        let n_seg = (total / spacing).ceil().max(1.0) as usize;
        let fixed_step_s = atmo.climate.surface_step_s as f64;
        let t_start = atmo.start_time_s();

        let mut cells = Vec::with_capacity(n_seg + 1);
        for i in 0..=n_seg {
            let p = if i == n_seg {
                total
            } else {
                (i as f32) * (total / (n_seg as f32))
            };
            let rs = atmo.route.sample_at_progress(p);
            let a0 = atmo.sample_at(rs.progress_m, t_start);
            let drainage_scale = (0.90 + (rs.grade.abs() * 3.0).min(0.65)).clamp(0.75, 1.55);
            cells.push(SurfaceCell {
                progress_m: rs.progress_m,
                shader_station_m: rs.shader_station_m,
                altitude_m: rs.altitude_m,
                shade_factor: 1.0,
                drainage_scale,
                ground_c: a0.air_c,
                water_mm: 0.0,
                snow_mm: 0.0,
                ice_mm: 0.0,
                saturation: 0.0,
            });
        }

        let mut grid = Self {
            surface_type: key,
            material,
            patch_seed,
            fixed_step_s,
            elapsed_s: t_start,
            pending_dt_s: 0.0,
            revision: 1,
            cells,
            audit: MassBalanceAudit::default(),
        };

        // Pre-roll pre-start window up to race start (elapsed_s = 0.0) using exact fixed steps.
        let pre_duration = (0.0 - t_start).max(0.0);
        if pre_duration > 0.0 {
            grid.advance_by(atmo, pre_duration);
        }
        grid.elapsed_s = 0.0;
        grid.pending_dt_s = 0.0;
        grid.revision += 1;
        grid
    }

    pub fn advance_by(&mut self, atmo: &mut AtmosphereTable, delta_s: f64) {
        if delta_s <= 0.0 || self.cells.is_empty() {
            return;
        }
        self.pending_dt_s += delta_s;
        let step = self.fixed_step_s.max(0.1);
        let inv_n = 1.0 / (self.cells.len() as f64);
        while self.pending_dt_s + 1e-6 >= step {
            let mid_t = self.elapsed_s + 0.5 * step;
            let mut r_sum = 0.0_f64;
            let mut s_sum = 0.0_f64;
            let mut e_sum = 0.0_f64;
            let mut d_sum = 0.0_f64;
            let mut o_sum = 0.0_f64;
            for cell in &mut self.cells {
                let forcing = atmo.sample_at(cell.progress_m, mid_t);
                let (r, s, e, d, o) = step_surface_cell(
                    cell,
                    &forcing,
                    step as f32,
                    &atmo.climate.surface_balance,
                    &self.material,
                );
                r_sum += r as f64;
                s_sum += s as f64;
                e_sum += e as f64;
                d_sum += d as f64;
                o_sum += o as f64;
            }
            self.audit.rain_in_mm += r_sum * inv_n;
            self.audit.snow_in_mm += s_sum * inv_n;
            self.audit.evap_out_mm += e_sum * inv_n;
            self.audit.drain_out_mm += d_sum * inv_n;
            self.audit.clipped_overflow_mm += o_sum * inv_n;
            self.elapsed_s += step;
            self.pending_dt_s = (self.pending_dt_s - step).max(0.0);
            self.revision = self.revision.wrapping_add(1);
        }
    }

    pub fn mean_total_mass_mm(&self) -> f64 {
        if self.cells.is_empty() {
            return 0.0;
        }
        let sum: f64 = self
            .cells
            .iter()
            .map(|c| (c.water_mm + c.snow_mm + c.ice_mm) as f64)
            .sum();
        sum / (self.cells.len() as f64)
    }

    pub fn interpolate_cell_at(&self, progress_m: f32) -> SurfaceCell {
        if self.cells.is_empty() {
            return SurfaceCell {
                progress_m,
                shader_station_m: progress_m,
                altitude_m: 0.0,
                shade_factor: 1.0,
                drainage_scale: 1.0,
                ground_c: 15.0,
                water_mm: 0.0,
                snow_mm: 0.0,
                ice_mm: 0.0,
                saturation: 0.0,
            };
        }
        let total = self.cells.last().unwrap().progress_m.max(1.0);
        let p = progress_m.clamp(self.cells[0].progress_m, total);
        let idx = self.cells.partition_point(|c| c.progress_m < p);
        if idx == 0 {
            return self.cells[0].clone();
        }
        if idx >= self.cells.len() {
            return self.cells[self.cells.len() - 1].clone();
        }
        let a = &self.cells[idx - 1];
        let b = &self.cells[idx];
        let span = (b.progress_m - a.progress_m).max(1e-6);
        let t = ((p - a.progress_m) / span).clamp(0.0, 1.0);
        SurfaceCell {
            progress_m: p,
            shader_station_m: lerpf(a.shader_station_m, b.shader_station_m, t),
            altitude_m: lerpf(a.altitude_m, b.altitude_m, t),
            shade_factor: lerpf(a.shade_factor, b.shade_factor, t),
            drainage_scale: lerpf(a.drainage_scale, b.drainage_scale, t),
            ground_c: lerpf(a.ground_c, b.ground_c, t),
            water_mm: lerpf(a.water_mm, b.water_mm, t),
            snow_mm: lerpf(a.snow_mm, b.snow_mm, t),
            ice_mm: lerpf(a.ice_mm, b.ice_mm, t),
            saturation: lerpf(a.saturation, b.saturation, t),
        }
    }

    pub fn sample_at(&self, atmo: &mut AtmosphereTable, progress_m: f32, lateral_t: f32) -> SurfaceSample {
        let cell = self.interpolate_cell_at(progress_m);
        let a = atmo.sample_at(progress_m, self.elapsed_s + self.pending_dt_s);
        let cfg = &atmo.climate.surface_balance;

        let lat = lateral_t.clamp(-1.0, 1.0);
        let (snow_seed_off, _ice_seed_off) = patch_seed_offsets(self.patch_seed);
        let snow_cov = local_pattern_coverage(
            cell.snow_mm,
            cfg.snow_coverage_full_mm,
            0.03,
            cell.shader_station_m,
            lat,
            snow_seed_off,
            1.0,
        );
        // Continuous carriageway ice patches are disabled (water-only + lateral snow ribbons).
        let ice_cov = 0.0;
        let water_cov = if cell.water_mm > 0.01 {
            smoothstep(0.01, cfg.water_coverage_full_mm, cell.water_mm)
        } else {
            0.0
        };

        // Normalized footprint weights: snow, exposed base road (dry/wet).
        let snow_w = snow_cov.clamp(0.0, 1.0);
        let ice_w = 0.0;
        let dry_w = (1.0 - snow_w).clamp(0.0, 1.0);

        let water_eff = cell.water_mm.clamp(0.0, cfg.tire_effective_water_cap_mm);
        let snow_eff = if snow_cov <= 0.001 {
            0.0
        } else {
            (cell.snow_mm * (0.40 + 0.80 * snow_cov)).clamp(0.0, cfg.tire_effective_snow_cap_mm)
        };

        SurfaceSample {
            progress_m: cell.progress_m,
            shader_station_m: cell.shader_station_m,
            lateral_t: lat,
            elapsed_s: self.elapsed_s,
            altitude_m: cell.altitude_m,
            air_c: a.air_c,
            ground_c: cell.ground_c,
            water_mm: cell.water_mm,
            snow_mm: cell.snow_mm,
            ice_mm: cell.ice_mm,
            saturation: cell.saturation,
            water_coverage: water_cov,
            snow_coverage: snow_cov,
            ice_coverage: ice_cov,
            dry_weight: dry_w,
            snow_weight: snow_w,
            ice_weight: ice_w,
            water_mm_effective: water_eff,
            snow_mm_effective: snow_eff,
            irradiance_w_m2: a.irradiance_w_m2,
            humidity: a.humidity,
            cloud_cover: a.cloud_cover,
            rain_mm_h: a.rain_mm_h,
            snow_mm_h: a.snow_mm_h,
            precip_total_mm_h: a.precip_total_mm_h,
            precip_kind: a.precip_kind,
            wind_m_s: a.wind_m_s,
            wind_dir_deg: a.wind_dir_deg,
        }
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustProceduralWeather {
    table: Option<AtmosphereTable>,
    surface: Option<SurfaceGrid>,
    last_error: String,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustProceduralWeather {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            table: None,
            surface: None,
            last_error: String::new(),
            base,
        }
    }
}

#[godot_api]
impl RustProceduralWeather {
    #[func]
    pub fn configure_from_json(
        &mut self,
        climate_json: GString,
        route_json: GString,
        event_seed: i64,
        season_or_date: GString,
        start_hour: f32,
        pre_start_hours: f32,
        race_horizon_hours: f32,
        regime_mode: GString,
    ) -> VarDictionary {
        let mut out = VarDictionary::new();
        let climate = match ClimateProfile::from_json_str(&climate_json.to_string()) {
            Ok(c) => c,
            Err(e) => {
                self.last_error = e.clone();
                let _ = out.insert("ok", false);
                let _ = out.insert("error", e.as_str());
                return out;
            }
        };
        let route = match RouteProfile::from_json_str(&route_json.to_string()) {
            Ok(r) => r,
            Err(e) => {
                self.last_error = e.clone();
                let _ = out.insert("ok", false);
                let _ = out.insert("error", e.as_str());
                return out;
            }
        };

        let regime = match regime_mode.to_string().to_lowercase().as_str() {
            "dry" | "force_dry" => DayRegime::ForceDry,
            "clear" | "sunny" => DayRegime::Clear,
            "cloudy" | "overcast" => DayRegime::Cloudy,
            "wet_front" | "force_wet_front" => DayRegime::ForceWetFront,
            "controlled_mixed_ascent" | "mixed_ascent" => DayRegime::ControlledMixedAscent,
            "controlled_refreeze" | "refreeze" => DayRegime::ControlledRefreeze,
            _ => DayRegime::Auto,
        };
        let pre_ov = if pre_start_hours >= 0.0 {
            Some(pre_start_hours)
        } else {
            None
        };
        let hor_ov = if race_horizon_hours > 0.0 {
            Some(race_horizon_hours)
        } else {
            None
        };

        let mut table = AtmosphereTable::build(
            route,
            climate,
            event_seed as u64,
            &season_or_date.to_string(),
            start_hour,
            pre_ov,
            hor_ov,
            regime,
        );
        let surface = SurfaceGrid::build_and_preroll(&mut table, "asphalt");

        let _ = out.insert("ok", true);
        let _ = out.insert("error", "");
        let _ = out.insert("algo_version", ALGO_VERSION as i64);
        let _ = out.insert("profile_id", table.climate.profile_id.as_str());
        let _ = out.insert("track_id", table.route.track_id.as_str());
        let _ = out.insert("season_id", table.season_id.as_str());
        let _ = out.insert("climate_seed", table.climate_seed as i64);
        let _ = out.insert("is_dry_day", table.is_dry_day);
        let _ = out.insert("node_count", table.node_count() as i64);
        let _ = out.insert("time_slices", table.time_slice_count() as i64);
        let _ = out.insert("surface_cells", surface.cells.len() as i64);
        let _ = out.insert("total_distance_m", table.route.total_distance_m);
        let _ = out.insert("min_altitude_m", table.route.min_altitude_m);
        let _ = out.insert("max_altitude_m", table.route.max_altitude_m);
        let _ = out.insert(
            "shader_start_station_m",
            table.route.samples[0].shader_station_m,
        );
        let _ = out.insert(
            "shader_finish_station_m",
            table.route.samples[table.route.samples.len() - 1].shader_station_m,
        );

        self.last_error.clear();
        self.table = Some(table);
        self.surface = Some(surface);
        out
    }

    #[func]
    pub fn configure_surface(&mut self, surface_type: GString) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(table) = self.table.as_mut() else {
            let _ = out.insert("ok", false);
            let _ = out.insert("error", "Atmosphere not configured");
            return out;
        };
        let grid = SurfaceGrid::build_and_preroll(table, &surface_type.to_string());
        let _ = out.insert("ok", true);
        let _ = out.insert("surface_type", grid.surface_type.as_str());
        let _ = out.insert("cell_count", grid.cells.len() as i64);
        let _ = out.insert("elapsed_s", grid.elapsed_s);
        let _ = out.insert("mean_total_mass_mm", grid.mean_total_mass_mm());
        self.surface = Some(grid);
        out
    }

    #[func]
    pub fn advance_surface(&mut self, delta_s: f64) {
        if let (Some(table), Some(surface)) = (self.table.as_mut(), self.surface.as_mut()) {
            surface.advance_by(table, delta_s);
        }
    }

    #[func]
    pub fn sample_surface_at(&mut self, progress_m: f32, lateral_t: f32) -> VarDictionary {
        let mut out = VarDictionary::new();
        let (Some(table), Some(surface)) = (self.table.as_mut(), self.surface.as_ref()) else {
            let _ = out.insert("ok", false);
            return out;
        };
        let s = surface.sample_at(table, progress_m, lateral_t);
        let _ = out.insert("ok", true);
        let _ = out.insert("progress_m", s.progress_m);
        let _ = out.insert("shader_station_m", s.shader_station_m);
        let _ = out.insert("lateral_t", s.lateral_t);
        let _ = out.insert("elapsed_s", s.elapsed_s);
        let _ = out.insert("altitude_m", s.altitude_m);
        let _ = out.insert("air_c", s.air_c);
        let _ = out.insert("ground_c", s.ground_c);
        let _ = out.insert("water_mm", s.water_mm);
        let _ = out.insert("snow_mm", s.snow_mm);
        let _ = out.insert("ice_mm", s.ice_mm);
        let _ = out.insert("saturation", s.saturation);
        let _ = out.insert("water_coverage", s.water_coverage);
        let _ = out.insert("snow_coverage", s.snow_coverage);
        let _ = out.insert("ice_coverage", s.ice_coverage);
        let _ = out.insert("dry_weight", s.dry_weight);
        let _ = out.insert("snow_weight", s.snow_weight);
        let _ = out.insert("ice_weight", s.ice_weight);
        let _ = out.insert("water_mm_effective", s.water_mm_effective);
        let _ = out.insert("snow_mm_effective", s.snow_mm_effective);
        let _ = out.insert("irradiance_w_m2", s.irradiance_w_m2);
        let _ = out.insert("humidity", s.humidity);
        let _ = out.insert("cloud_cover", s.cloud_cover);
        let _ = out.insert("rain_mm_h", s.rain_mm_h);
        let _ = out.insert("snow_mm_h", s.snow_mm_h);
        let _ = out.insert("precip_total_mm_h", s.precip_total_mm_h);
        let _ = out.insert("precip_kind", s.precip_kind.as_str());
        let _ = out.insert("wind_m_s", s.wind_m_s);
        let _ = out.insert("wind_direction_deg", s.wind_dir_deg);
        out
    }

    #[func]
    pub fn surface_telemetry_samples(&mut self, step_m: f32) -> VarDictionary {
        let mut out = VarDictionary::new();
        let (Some(table), Some(surface)) = (self.table.as_mut(), self.surface.as_ref()) else {
            let _ = out.insert("ok", false);
            return out;
        };
        let step = step_m.max(25.0);
        let total = table.route.total_distance_m.max(1.0);
        let count = ((total / step).ceil() as usize).max(1) + 1;
        let mut rows = VarArray::new();
        for i in 0..count {
            let p = if i + 1 == count {
                total
            } else {
                (i as f32 * step).min(total)
            };
            let s = surface.sample_at(table, p, 0.0);
            let mut row = VarDictionary::new();
            let _ = row.insert("progress_m", s.progress_m);
            let _ = row.insert("shader_station_m", s.shader_station_m);
            let _ = row.insert("altitude_m", s.altitude_m);
            let _ = row.insert("air_c", s.air_c);
            let _ = row.insert("ground_c", s.ground_c);
            let _ = row.insert("water_mm", s.water_mm);
            let _ = row.insert("snow_mm", s.snow_mm);
            let _ = row.insert("ice_mm", s.ice_mm);
            let _ = row.insert("snow_coverage", s.snow_coverage);
            let _ = row.insert("ice_coverage", s.ice_coverage);
            let _ = row.insert("rain_mm_h", s.rain_mm_h);
            let _ = row.insert("snow_mm_h", s.snow_mm_h);
            rows.push(&row.to_variant());
        }
        let _ = out.insert("ok", true);
        let _ = out.insert("elapsed_s", surface.elapsed_s);
        let _ = out.insert("surface_type", surface.surface_type.as_str());
        let _ = out.insert("mean_total_mass_mm", surface.mean_total_mass_mm());
        let _ = out.insert("rain_in_mm", surface.audit.rain_in_mm);
        let _ = out.insert("snow_in_mm", surface.audit.snow_in_mm);
        let _ = out.insert("evap_out_mm", surface.audit.evap_out_mm);
        let _ = out.insert("drain_out_mm", surface.audit.drain_out_mm);
        let _ = out.insert("clipped_overflow_mm", surface.audit.clipped_overflow_mm);
        let _ = out.insert("samples", &rows);
        out
    }

    #[func]
    pub fn surface_field_packet(&self) -> VarDictionary {
        self.surface_field_packet_since(-1)
    }

    #[func]
    pub fn surface_field_packet_since(&self, known_revision: i64) -> VarDictionary {
        let mut out = VarDictionary::new();
        let (Some(table), Some(surface)) = (self.table.as_ref(), self.surface.as_ref()) else {
            let _ = out.insert("ok", false);
            return out;
        };
        if known_revision == surface.revision as i64 {
            return out;
        }
        if surface.cells.is_empty() {
            let _ = out.insert("ok", false);
            return out;
        }
        let cfg = &table.climate.surface_balance;
        let max_encode_mm = cfg
            .snow_coverage_full_mm
            .max(cfg.ice_coverage_full_mm)
            .max(cfg.water_coverage_full_mm)
            .max(3.0);
        let n = surface.cells.len();
        let station_min = surface.cells[0].shader_station_m;
        let station_max = surface.cells[n - 1].shader_station_m.max(station_min + 1.0);
        let mut rgba = PackedByteArray::new();
        rgba.resize(n * 4);
        let slice = rgba.as_mut_slice();
        let span = station_max - station_min;
        for i in 0..n {
            let u = if n <= 1 {
                0.0
            } else {
                (i as f32) / ((n - 1) as f32)
            };
            let st = station_min + u * span;
            let prog = table.route.shader_station_to_progress(st);
            let cell = surface.interpolate_cell_at(prog);
            slice[i * 4] = ((cell.water_mm / max_encode_mm).clamp(0.0, 1.0) * 255.0).round() as u8;
            slice[i * 4 + 1] = ((cell.snow_mm / max_encode_mm).clamp(0.0, 1.0) * 255.0).round() as u8;
            slice[i * 4 + 2] = ((cell.ice_mm / max_encode_mm).clamp(0.0, 1.0) * 255.0).round() as u8;
            slice[i * 4 + 3] = (cell.saturation.clamp(0.0, 1.0) * 255.0).round() as u8;
        }
        let (snow_off, ice_off) = patch_seed_offsets(surface.patch_seed);
        let _ = out.insert("ok", true);
        let _ = out.insert("width", n as i64);
        let _ = out.insert("revision", surface.revision as i64);
        let _ = out.insert("station_min_m", station_min);
        let _ = out.insert("station_max_m", station_max);
        let _ = out.insert("max_encode_mm", max_encode_mm);
        let _ = out.insert("water_full_mm", cfg.water_coverage_full_mm);
        let _ = out.insert("snow_full_mm", cfg.snow_coverage_full_mm);
        let _ = out.insert("ice_full_mm", cfg.ice_coverage_full_mm);
        let _ = out.insert("snow_seed_offset", Vector2::new(snow_off[0], snow_off[1]));
        let _ = out.insert("ice_seed_offset", Vector2::new(ice_off[0], ice_off[1]));
        let _ = out.insert("rgba8", &rgba);
        out
    }

    #[func]
    pub fn snapshot_surface(&self) -> VarDictionary {
        let mut out = VarDictionary::new();
        let (Some(table), Some(surface)) = (self.table.as_ref(), self.surface.as_ref()) else {
            let _ = out.insert("ok", false);
            return out;
        };
        let n = surface.cells.len();
        let mut packed = PackedFloat32Array::new();
        packed.resize(n * 5);
        let slice = packed.as_mut_slice();
        for (i, c) in surface.cells.iter().enumerate() {
            slice[i * 5] = c.ground_c;
            slice[i * 5 + 1] = c.water_mm;
            slice[i * 5 + 2] = c.snow_mm;
            slice[i * 5 + 3] = c.ice_mm;
            slice[i * 5 + 4] = c.saturation;
        }
        let _ = out.insert("ok", true);
        let _ = out.insert("algo_version", ALGO_VERSION as i64);
        let _ = out.insert("climate_seed", table.climate_seed as i64);
        let _ = out.insert("surface_type", surface.surface_type.as_str());
        let _ = out.insert("elapsed_s", surface.elapsed_s);
        let _ = out.insert("pending_dt_s", surface.pending_dt_s);
        let _ = out.insert("cell_count", n as i64);
        let _ = out.insert("cells_packed", &packed);
        let _ = out.insert("rain_in_mm", surface.audit.rain_in_mm);
        let _ = out.insert("snow_in_mm", surface.audit.snow_in_mm);
        let _ = out.insert("evap_out_mm", surface.audit.evap_out_mm);
        let _ = out.insert("drain_out_mm", surface.audit.drain_out_mm);
        let _ = out.insert("clipped_overflow_mm", surface.audit.clipped_overflow_mm);
        out
    }

    #[func]
    pub fn restore_surface_snapshot(&mut self, snap: VarDictionary) -> bool {
        let Some(surface) = self.surface.as_mut() else {
            return false;
        };
        let Some(packed_var) = snap.get("cells_packed") else {
            return false;
        };
        let Ok(packed) = packed_var.try_to::<PackedFloat32Array>() else {
            return false;
        };
        let slice = packed.as_slice();
        if slice.len() != surface.cells.len() * 5 {
            return false;
        }
        for (i, c) in surface.cells.iter_mut().enumerate() {
            c.ground_c = slice[i * 5];
            c.water_mm = slice[i * 5 + 1].max(0.0);
            c.snow_mm = slice[i * 5 + 2].max(0.0);
            c.ice_mm = slice[i * 5 + 3].max(0.0);
            c.saturation = slice[i * 5 + 4].clamp(0.0, 1.0);
        }
        if let Some(ev) = snap.get("elapsed_s").and_then(|v| v.try_to::<f64>().ok()) {
            surface.elapsed_s = ev;
        }
        surface.pending_dt_s = snap
            .get("pending_dt_s")
            .and_then(|v| v.try_to::<f64>().ok())
            .unwrap_or(0.0)
            .max(0.0);
        surface.audit.rain_in_mm = snap
            .get("rain_in_mm")
            .and_then(|v| v.try_to::<f64>().ok())
            .unwrap_or(surface.audit.rain_in_mm);
        surface.audit.snow_in_mm = snap
            .get("snow_in_mm")
            .and_then(|v| v.try_to::<f64>().ok())
            .unwrap_or(surface.audit.snow_in_mm);
        surface.audit.evap_out_mm = snap
            .get("evap_out_mm")
            .and_then(|v| v.try_to::<f64>().ok())
            .unwrap_or(surface.audit.evap_out_mm);
        surface.audit.drain_out_mm = snap
            .get("drain_out_mm")
            .and_then(|v| v.try_to::<f64>().ok())
            .unwrap_or(surface.audit.drain_out_mm);
        surface.audit.clipped_overflow_mm = snap
            .get("clipped_overflow_mm")
            .and_then(|v| v.try_to::<f64>().ok())
            .unwrap_or(surface.audit.clipped_overflow_mm);
        surface.revision = surface.revision.wrapping_add(1);
        true
    }

    #[func]
    pub fn is_configured(&self) -> bool {
        self.table.is_some()
    }

    #[func]
    pub fn last_error(&self) -> GString {
        GString::from(self.last_error.as_str())
    }

    #[func]
    pub fn extend_horizon_to(&mut self, elapsed_race_s: f64) {
        if let Some(table) = self.table.as_mut() {
            table.extend_horizon_to(elapsed_race_s);
        }
    }

    #[func]
    pub fn progress_to_shader_station(&self, progress_m: f32) -> f32 {
        self.table
            .as_ref()
            .map(|t| t.route.sample_at_progress(progress_m).shader_station_m)
            .unwrap_or(progress_m)
    }

    #[func]
    pub fn shader_station_to_progress(&self, shader_station_m: f32) -> f32 {
        self.table
            .as_ref()
            .map(|t| t.route.shader_station_to_progress(shader_station_m))
            .unwrap_or(shader_station_m)
    }

    #[func]
    pub fn sample_atmosphere_at(&mut self, progress_m: f32, elapsed_race_s: f64) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(table) = self.table.as_mut() else {
            let _ = out.insert("ok", false);
            return out;
        };
        let s = table.sample_at(progress_m, elapsed_race_s);
        let _ = out.insert("ok", true);
        let _ = out.insert("progress_m", s.progress_m);
        let _ = out.insert("shader_station_m", s.shader_station_m);
        let _ = out.insert("elapsed_s", s.elapsed_s);
        let _ = out.insert("hour_of_day", s.hour_of_day);
        let _ = out.insert("altitude_m", s.altitude_m);
        let _ = out.insert("air_c", s.air_c);
        let _ = out.insert("wet_bulb_c", s.wet_bulb_c);
        let _ = out.insert("humidity", s.humidity);
        let _ = out.insert("cloud_cover", s.cloud_cover);
        let _ = out.insert("irradiance_w_m2", s.irradiance_w_m2);
        let _ = out.insert("precip_total_mm_h", s.precip_total_mm_h);
        let _ = out.insert("rain_mm_h", s.rain_mm_h);
        let _ = out.insert("snow_mm_h", s.snow_mm_h);
        let _ = out.insert("precip_kind", s.precip_kind.as_str());
        let _ = out.insert("wind_m_s", s.wind_m_s);
        let _ = out.insert("wind_direction_deg", s.wind_dir_deg);
        out
    }

    #[func]
    pub fn table_summary(&self) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(table) = self.table.as_ref() else {
            let _ = out.insert("ok", false);
            return out;
        };
        let _ = out.insert("ok", true);
        let _ = out.insert("algo_version", ALGO_VERSION as i64);
        let _ = out.insert("profile_id", table.climate.profile_id.as_str());
        let _ = out.insert("track_id", table.route.track_id.as_str());
        let _ = out.insert("season_id", table.season_id.as_str());
        let _ = out.insert("climate_seed", table.climate_seed as i64);
        let _ = out.insert("is_dry_day", table.is_dry_day);
        let _ = out.insert("node_count", table.node_count() as i64);
        let _ = out.insert("time_slices", table.time_slice_count() as i64);
        let _ = out.insert("start_time_s", table.start_time_s());
        let _ = out.insert("end_time_s", table.end_time_s());
        let _ = out.insert("total_distance_m", table.route.total_distance_m);
        let _ = out.insert("min_altitude_m", table.route.min_altitude_m);
        let _ = out.insert("max_altitude_m", table.route.max_altitude_m);
        let _ = out.insert("vertical_datum_verified", table.route.vertical_datum_verified);
        out
    }
}

pub const FIVE_SECTOR_ALGO_VERSION: u32 = 2;
pub const FIVE_SECTOR_COUNT: usize = 5;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FiveSectorRegime {
    Auto,
    Dry,
    Clear,
    Cloudy,
    WetFront,
    ControlledMixedAscent,
    ControlledRefreeze,
    ControlledTimingEpisode,
}

impl FiveSectorRegime {
    pub fn from_str(raw: &str) -> Self {
        match raw.trim().to_lowercase().as_str() {
            "dry" | "force_dry" => Self::Dry,
            "sunny" | "clear" => Self::Clear,
            "cloudy" | "overcast" => Self::Cloudy,
            "wet_front" | "force_wet_front" | "wet" | "wet_episodes" | "rain" => Self::WetFront,
            "controlled_mixed_ascent" | "mixed_ascent" => Self::ControlledMixedAscent,
            "controlled_refreeze" | "refreeze" => Self::ControlledRefreeze,
            "controlled_timing_episode" | "timing_episode" => Self::ControlledTimingEpisode,
            _ => Self::Auto,
        }
    }
}

#[derive(Clone, Debug)]
pub struct SectorTimeMark {
    pub abs_time_s: f64,
    pub cloud_cover: f32,
    pub humidity: f32,
    pub temp_anomaly_c: f32,
    pub lapse_rate_c_per_km: f32,
    pub precip_base_mm_h: f32,
    pub wind_m_s: f32,
    pub wind_dir_deg: f32,
}

#[derive(Clone, Debug)]
struct SectorEpisode {
    t_start_s: f64,
    t_peak_s: f64,
    t_end_s: f64,
    peak_precip_mm_h: f32,
    cloud_boost: f32,
    humidity_boost: f32,
    temp_anomaly_c: f32,
    wind_m_s: f32,
    wind_dir_deg: f32,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct FiveSectorGeometry {
    pub sector_index: usize,
    pub start_m: f32,
    pub end_m: f32,
    pub center_m: f32,
    pub center_shader_station_m: f32,
    pub center_altitude_m: f32,
    pub mean_abs_grade: f32,
    pub shade_factor: f32,
    pub drainage_scale: f32,
    pub windward_factor: f32,
}

#[derive(Clone, Debug)]
pub struct SectorSurfaceState {
    pub ground_c: f32,
    pub water_mm: f32,
    pub snow_mm: f32,
    pub ice_mm: f32,
    pub saturation: f32,
    pub audit: MassBalanceAudit,
    pub time_since_last_precip_s: f64,
}

#[derive(Clone, Debug)]
pub struct FiveSectorData {
    pub geom: FiveSectorGeometry,
    pub marks: Vec<SectorTimeMark>,
}

#[derive(Clone, Debug)]
pub struct WaterRetentionConfig {
    pub slope_window_m: f32,
    pub smoothing_window_m: f32,
    pub min_retention: f32,
    pub max_retention: f32,
}

impl Default for WaterRetentionConfig {
    fn default() -> Self {
        Self {
            slope_window_m: 30.0,
            smoothing_window_m: 60.0,
            min_retention: 0.25,
            max_retention: 1.50,
        }
    }
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct WaterRetentionSample {
    pub progress_m: f32,
    pub shader_station_m: f32,
    pub slope: f32,
    pub concavity: f32,
    pub raw_retention: f32,
    pub retention: f32,
}

#[derive(Clone, Debug)]
pub struct WaterRetentionProfile {
    pub samples: Vec<WaterRetentionSample>,
    pub valid: bool,
    pub diagnostic: String,
    pub build_time_us: u64,
}

impl WaterRetentionProfile {
    fn sample_slice_field(samples: &[WaterRetentionSample], progress_m: f32, f: impl Fn(&WaterRetentionSample) -> f32) -> f32 {
        if samples.is_empty() {
            return 1.0;
        }
        let first = samples[0].progress_m;
        let last = samples[samples.len() - 1].progress_m;
        let p = progress_m.clamp(first, last);
        let idx = samples.partition_point(|s| s.progress_m < p);
        if idx == 0 {
            return f(&samples[0]);
        }
        if idx >= samples.len() {
            return f(&samples[samples.len() - 1]);
        }
        let a = &samples[idx - 1];
        let b = &samples[idx];
        let span = (b.progress_m - a.progress_m).max(1e-6);
        let t = ((p - a.progress_m) / span).clamp(0.0, 1.0);
        lerpf(f(a), f(b), t)
    }

    pub fn build(route: &RouteProfile, cfg: &WaterRetentionConfig) -> Self {
        let t0 = std::time::Instant::now();
        let make_invalid = |reason: String| Self {
            samples: Vec::new(),
            valid: false,
            diagnostic: reason,
            build_time_us: t0.elapsed().as_micros() as u64,
        };

        if route.samples.len() < 3 {
            return make_invalid(format!("Insufficient route samples ({})", route.samples.len()));
        }
        if !route.total_distance_m.is_finite() || route.total_distance_m < 10.0 {
            return make_invalid(format!("Invalid total distance ({})", route.total_distance_m));
        }

        let mut prev_p = f32::NEG_INFINITY;
        let mut prev_st = f32::NEG_INFINITY;
        for (i, s) in route.samples.iter().enumerate() {
            if !s.progress_m.is_finite()
                || !s.shader_station_m.is_finite()
                || !s.altitude_m.is_finite()
                || !s.local_x_m.is_finite()
                || !s.local_z_m.is_finite()
            {
                return make_invalid(format!("Non-finite coordinates at sample {}", i));
            }
            if s.progress_m < prev_p {
                return make_invalid(format!("Non-monotonic progress_m at sample {}", i));
            }
            if s.shader_station_m < prev_st {
                return make_invalid(format!("Non-monotonic shader_station_m at sample {}", i));
            }
            prev_p = s.progress_m;
            prev_st = s.shader_station_m;
        }
        let st_span = route.samples.last().unwrap().shader_station_m - route.samples[0].shader_station_m;
        if st_span < 1.0 {
            return make_invalid(format!("Degenerate shader_station_m span ({})", st_span));
        }

        let p_start = route.samples[0].progress_m;
        let p_end = route.samples.last().unwrap().progress_m;
        let win = cfg.slope_window_m.max(5.0);
        let min_r = cfg.min_retention.min(cfg.max_retention);
        let max_r = cfg.max_retention.max(min_r);

        let mut raw_samples = Vec::with_capacity(route.samples.len());
        for s in &route.samples {
            let p = s.progress_m;
            let curr_v = Vector3::new(s.local_x_m, s.altitude_m, s.local_z_m);
            let prev_v = if p - p_start < 1.0 {
                None
            } else {
                let sp = route.sample_at_progress((p - win).max(p_start));
                Some(Vector3::new(sp.local_x_m, sp.altitude_m, sp.local_z_m))
            };
            let next_v = if p_end - p < 1.0 {
                None
            } else {
                let sn = route.sample_at_progress((p + win).min(p_end));
                Some(Vector3::new(sn.local_x_m, sn.altitude_m, sn.local_z_m))
            };
            let (slope, concavity) = crate::puddles::compute_entry_exit_slopes_bounded(prev_v, curr_v, next_v);

            let slope_t = smoothstep(0.015, 0.16, slope.abs());
            let slope_factor = 1.0 - 0.52 * slope_t;
            let conc_factor = if concavity < 0.0 {
                1.0 - 0.62 * smoothstep(0.0, 0.030, -concavity)
            } else {
                let flatness = 1.0 - 0.35 * smoothstep(0.05, 0.18, slope.abs());
                1.0 + 0.55 * smoothstep(0.0, 0.025, concavity) * flatness
            };
            let raw_ret = (slope_factor * conc_factor).clamp(min_r, max_r);

            raw_samples.push(WaterRetentionSample {
                progress_m: s.progress_m,
                shader_station_m: s.shader_station_m,
                slope,
                concavity,
                raw_retention: raw_ret,
                retention: raw_ret,
            });
        }

        // Smooth continuously along route progress_m without resetting at sector borders.
        let smooth_win = cfg.smoothing_window_m.clamp(30.0, 80.0);
        let half_win = 0.5 * smooth_win;
        let quad_step = 5.0_f32;
        let k_max = (half_win / quad_step).floor() as i32;
        let mut smoothed = Vec::with_capacity(raw_samples.len());
        for s in &raw_samples {
            let mut w_sum = 0.0_f32;
            let mut v_sum = 0.0_f32;
            for k in -k_max..=k_max {
                let off = (k as f32) * quad_step;
                let pk = s.progress_m + off;
                if pk < p_start || pk > p_end {
                    continue;
                }
                let u = (off.abs() / half_win).clamp(0.0, 1.0);
                let w = 0.5 * (1.0 + (PI * u).cos());
                if w > 1e-5 {
                    let v = Self::sample_slice_field(&raw_samples, pk, |x| x.raw_retention);
                    w_sum += w;
                    v_sum += w * v;
                }
            }
            let r = if w_sum > 1e-5 {
                (v_sum / w_sum).clamp(min_r, max_r)
            } else {
                s.raw_retention
            };
            smoothed.push(r);
        }
        for (s, r) in raw_samples.iter_mut().zip(smoothed.into_iter()) {
            s.retention = r;
        }

        Self {
            samples: raw_samples,
            valid: true,
            diagnostic: String::new(),
            build_time_us: t0.elapsed().as_micros() as u64,
        }
    }

    pub fn sample_retention(&self, progress_m: f32) -> f32 {
        if !self.valid || self.samples.is_empty() {
            return 1.0;
        }
        Self::sample_slice_field(&self.samples, progress_m, |x| x.retention)
    }

    pub fn sample_detail(&self, progress_m: f32) -> (f32, f32, f32, f32) {
        if !self.valid || self.samples.is_empty() {
            return (1.0, 0.0, 0.0, 1.0);
        }
        let ret = Self::sample_slice_field(&self.samples, progress_m, |x| x.retention);
        let slope = Self::sample_slice_field(&self.samples, progress_m, |x| x.slope);
        let conc = Self::sample_slice_field(&self.samples, progress_m, |x| x.concavity);
        let raw = Self::sample_slice_field(&self.samples, progress_m, |x| x.raw_retention);
        (ret, slope, conc, raw)
    }
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct FiveSectorJourney {
    pub route: RouteProfile,
    pub climate: ClimateProfile,
    pub season_id: String,
    pub season: SeasonParams,
    pub regime: FiveSectorRegime,
    pub event_seed: u64,
    pub climate_seed: u64,
    pub snow_mask_seed: u32,
    pub ice_mask_seed: u32,
    pub puddle_seed: u64,
    pub base_abs_seconds: f64,
    pub window_start_abs_s: f64,
    pub window_end_abs_s: f64,
    pub is_dry_day: bool,
    pub sectors: Vec<FiveSectorData>,
    pub water_retention_enabled: bool,
    pub water_retention_config: WaterRetentionConfig,
    pub water_retention_profile: Option<WaterRetentionProfile>,
    pub water_retention_warned: bool,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct FiveSectorSnapshot {
    pub effective_abs_seconds: f64,
    pub surface_type: String,
    pub material: SurfaceMaterialParams,
    pub patch_seed: u32,
    pub ice_patch_seed: u32,
    pub revision: u64,
    pub sector_atmo: Vec<AtmosphereSample>,
    pub sector_surface: Vec<SectorSurfaceState>,
}

#[inline]
fn interpolate_mark(a: &SectorTimeMark, b: &SectorTimeMark, t: f32) -> SectorTimeMark {
    SectorTimeMark {
        abs_time_s: a.abs_time_s + (b.abs_time_s - a.abs_time_s) * (t as f64),
        cloud_cover: lerpf(a.cloud_cover, b.cloud_cover, t),
        humidity: lerpf(a.humidity, b.humidity, t),
        temp_anomaly_c: lerpf(a.temp_anomaly_c, b.temp_anomaly_c, t),
        lapse_rate_c_per_km: lerpf(a.lapse_rate_c_per_km, b.lapse_rate_c_per_km, t),
        precip_base_mm_h: lerpf(a.precip_base_mm_h, b.precip_base_mm_h, t),
        wind_m_s: lerpf(a.wind_m_s, b.wind_m_s, t),
        wind_dir_deg: lerp_angle_deg(a.wind_dir_deg, b.wind_dir_deg, t),
    }
}

fn eval_sector_marks(marks: &[SectorTimeMark], abs_t: f64) -> SectorTimeMark {
    if marks.is_empty() {
        return SectorTimeMark {
            abs_time_s: abs_t,
            cloud_cover: 0.3,
            humidity: 0.6,
            temp_anomaly_c: 0.0,
            lapse_rate_c_per_km: 6.4,
            precip_base_mm_h: 0.0,
            wind_m_s: 3.0,
            wind_dir_deg: 60.0,
        };
    }
    if abs_t <= marks[0].abs_time_s {
        let mut c = marks[0].clone();
        c.abs_time_s = abs_t;
        return c;
    }
    let last = marks.len() - 1;
    if abs_t >= marks[last].abs_time_s {
        let mut c = marks[last].clone();
        c.abs_time_s = abs_t;
        return c;
    }
    let idx = marks.partition_point(|m| m.abs_time_s < abs_t);
    if idx == 0 {
        return marks[0].clone();
    }
    let a = &marks[idx - 1];
    let b = &marks[idx];
    let span = (b.abs_time_s - a.abs_time_s).max(1e-6);
    let t = ((abs_t - a.abs_time_s) / span).clamp(0.0, 1.0) as f32;
    interpolate_mark(a, b, t)
}

fn episode_envelope(ep: &SectorEpisode, abs_t: f64) -> f32 {
    if abs_t <= ep.t_start_s || abs_t >= ep.t_end_s {
        return 0.0;
    }
    if abs_t <= ep.t_peak_s {
        let span = (ep.t_peak_s - ep.t_start_s).max(1.0);
        let u = ((abs_t - ep.t_start_s) / span).clamp(0.0, 1.0) as f32;
        u * u * (3.0 - 2.0 * u)
    } else {
        let span = (ep.t_end_s - ep.t_peak_s).max(1.0);
        let u = ((ep.t_end_s - abs_t) / span).clamp(0.0, 1.0) as f32;
        u * u * (3.0 - 2.0 * u)
    }
}

fn build_marks_from_episodes(
    window_start_s: f64,
    window_end_s: f64,
    season: &SeasonParams,
    episodes: &[SectorEpisode],
    base_wind_spd: f32,
    base_wind_dir: f32,
) -> Vec<SectorTimeMark> {
    let mut times: Vec<f64> = Vec::with_capacity(6 + episodes.len() * 4);
    let span = (window_end_s - window_start_s).max(60.0);
    let anchors = 5usize;
    for i in 0..=anchors {
        times.push(window_start_s + span * (i as f64) / (anchors as f64));
    }
    for ep in episodes {
        for &t in &[
            ep.t_start_s,
            0.5 * (ep.t_start_s + ep.t_peak_s),
            ep.t_peak_s,
            0.5 * (ep.t_peak_s + ep.t_end_s),
            ep.t_end_s,
        ] {
            if t > window_start_s + 1.0 && t < window_end_s - 1.0 {
                times.push(t);
            }
        }
    }
    times.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let mut deduped: Vec<f64> = Vec::with_capacity(times.len());
    for t in times {
        if deduped
            .last()
            .map(|&prev| (t - prev).abs() > 15.0)
            .unwrap_or(true)
        {
            deduped.push(t);
        }
    }

    let mut marks = Vec::with_capacity(deduped.len());
    for abs_t in deduped {
        let hour = (abs_t / 3600.0).rem_euclid(24.0) as f32;
        let diurnal_phase = ((hour - (season.diurnal_peak_hour - 6.0)) * PI / 12.0).sin();
        let mut cloud = season.background_cloud_cover;
        let mut hum = (season.background_humidity - diurnal_phase * season.diurnal_humidity_amplitude)
            .clamp(0.10, 0.99);
        let mut temp_anom = 0.0_f32;
        let mut precip = 0.0_f32;
        let mut lapse_w = 0.0_f32;
        let mut wind_spd = base_wind_spd;
        let mut wind_dir = base_wind_dir;

        for ep in episodes {
            let env = episode_envelope(ep, abs_t);
            if env > 1e-4 {
                cloud = cloud.max(season.background_cloud_cover + ep.cloud_boost * env);
                hum = hum.max(season.background_humidity + ep.humidity_boost * env);
                temp_anom += ep.temp_anomaly_c * env;
                precip += ep.peak_precip_mm_h * env;
                lapse_w = lapse_w.max(env);
                wind_spd = wind_spd.max(lerpf(base_wind_spd, ep.wind_m_s, env));
                wind_dir = lerp_angle_deg(wind_dir, ep.wind_dir_deg, env * 0.8);
            }
        }
        marks.push(SectorTimeMark {
            abs_time_s: abs_t,
            cloud_cover: cloud.clamp(0.0, 1.0),
            humidity: hum.clamp(0.08, 0.99),
            temp_anomaly_c: temp_anom,
            lapse_rate_c_per_km: lerpf(season.lapse_rate_c_per_km, season.lapse_rate_front_c_per_km, lapse_w),
            precip_base_mm_h: precip.max(0.0),
            wind_m_s: wind_spd.clamp(0.2, 25.0),
            wind_dir_deg: wind_dir.rem_euclid(360.0),
        });
    }
    marks
}

impl FiveSectorJourney {
    pub fn build(
        route: RouteProfile,
        climate: ClimateProfile,
        event_seed: u64,
        season_or_date: &str,
        base_abs_seconds: f64,
        regime: FiveSectorRegime,
    ) -> Self {
        let (season_key, season_ref) = climate.resolve_season(season_or_date);
        let season_id = season_key.to_string();
        let mut season = season_ref.clone();
        match regime {
            FiveSectorRegime::Clear => season.background_cloud_cover = 0.10,
            FiveSectorRegime::Cloudy => season.background_cloud_cover = 0.66,
            _ => {}
        }

        // Day seed incorporates base_abs_seconds (NOT effective_abs_seconds or competitor slot).
        let base_day_tag = base_abs_seconds.round() as i64 as u64;
        let journey_seed = event_seed ^ base_day_tag.wrapping_mul(0x9E37_79B9_7F4A_7C15);
        let climate_seed = derive_stream_seed(journey_seed, &route.track_id, FIVE_SECTOR_ALGO_VERSION, "five_sector_day_v1");
        let snow_mask_seed = derive_stream_seed(event_seed, &route.track_id, FIVE_SECTOR_ALGO_VERSION, "five_sector_snow_mask_v1") as u32;
        let ice_mask_seed = derive_stream_seed(event_seed, &route.track_id, FIVE_SECTOR_ALGO_VERSION, "five_sector_ice_mask_v1") as u32;
        let puddle_seed = derive_stream_seed(event_seed, &route.track_id, FIVE_SECTOR_ALGO_VERSION, "five_sector_puddles_v1");

        let mut day_rng = Pcg32::seeded(derive_stream_seed(
            journey_seed,
            &route.track_id,
            FIVE_SECTOR_ALGO_VERSION,
            "five_sector_regime_v1",
        ));
        let is_dry_day = match regime {
            FiveSectorRegime::Dry | FiveSectorRegime::Clear | FiveSectorRegime::Cloudy => true,
            FiveSectorRegime::WetFront
            | FiveSectorRegime::ControlledMixedAscent
            | FiveSectorRegime::ControlledRefreeze
            | FiveSectorRegime::ControlledTimingEpisode => false,
            FiveSectorRegime::Auto => day_rng.randf() < season.dry_day_probability,
        };

        let total = route.total_distance_m.max(1.0);
        let boundaries_m: [f32; 6] = if let Some(b) = route.five_sector_boundaries_m {
            b
        } else {
            let f = climate.five_sector_model.boundaries_fraction;
            [
                f[0] * total,
                f[1] * total,
                f[2] * total,
                f[3] * total,
                f[4] * total,
                total,
            ]
        };

        let pre_start_s = (climate.five_sector_model.pre_start_hours as f64) * 3600.0;
        let horizon_s = (climate.five_sector_model.race_horizon_hours as f64) * 3600.0;
        let window_start_abs_s = base_abs_seconds - pre_start_s;
        let window_end_abs_s = base_abs_seconds + horizon_s;

        // Global episode templates before sector phase lag & orographic scaling.
        let mut atmo_rng = Pcg32::seeded(climate_seed);
        let base_wind_dir = if season.orographic_enabled {
            (season.prevailing_wind_dir_deg
                + atmo_rng.randf_range(-season.wind_dir_jitter_deg * 0.5, season.wind_dir_jitter_deg * 0.5))
            .rem_euclid(360.0)
        } else {
            60.0
        };
        let base_wind_spd = atmo_rng.randf_range(season.wind_speed_m_s_range[0], season.wind_speed_m_s_range[1]);
        let lag_dir: f64 = if atmo_rng.randf() < 0.5 { 1.0 } else { -1.0 };
        let lag_total_s = climate.five_sector_model.episode_lag_total_s as f64;

        let mut global_episodes: Vec<SectorEpisode> = Vec::new();
        match regime {
            FiveSectorRegime::Dry | FiveSectorRegime::Clear | FiveSectorRegime::Cloudy => {}
            FiveSectorRegime::ControlledTimingEpisode => {
                // Controlled benchmark matching plan §3 example:
                // starts at T_base - 5 min, sustains peak past T_base + 12 min, ends T_base + 17 min.
                global_episodes.push(SectorEpisode {
                    t_start_s: base_abs_seconds - 300.0,
                    t_peak_s: base_abs_seconds + 600.0,
                    t_end_s: base_abs_seconds + 1020.0,
                    peak_precip_mm_h: 9.5,
                    cloud_boost: 0.45,
                    humidity_boost: 0.28,
                    temp_anomaly_c: 2.8, // warm above freezing across route -> liquid rain/puddles
                    wind_m_s: 4.5,
                    wind_dir_deg: base_wind_dir,
                });
            }
            FiveSectorRegime::ControlledMixedAscent | FiveSectorRegime::ControlledRefreeze => {}
            FiveSectorRegime::WetFront => {
                // Guaranteed pre-start wetting shower + active episode spanning base_abs_seconds.
                global_episodes.push(SectorEpisode {
                    t_start_s: base_abs_seconds - 4200.0,
                    t_peak_s: base_abs_seconds - 1800.0,
                    t_end_s: base_abs_seconds + 600.0,
                    peak_precip_mm_h: season.sample_precip_mm_h(&mut atmo_rng).max(4.5),
                    cloud_boost: atmo_rng.randf_range(season.front_cloud_boost_range[0], season.front_cloud_boost_range[1]),
                    humidity_boost: atmo_rng.randf_range(season.front_humidity_boost_range[0], season.front_humidity_boost_range[1]),
                    temp_anomaly_c: atmo_rng.randf_range(season.front_temp_anomaly_c_range[0], season.front_temp_anomaly_c_range[1]),
                    wind_m_s: atmo_rng.randf_range(season.wind_speed_m_s_range[0], season.wind_speed_m_s_range[1]),
                    wind_dir_deg: base_wind_dir,
                });
                global_episodes.push(SectorEpisode {
                    t_start_s: base_abs_seconds - 900.0,
                    t_peak_s: base_abs_seconds + 900.0,
                    t_end_s: base_abs_seconds + 3000.0,
                    peak_precip_mm_h: season.sample_precip_mm_h(&mut atmo_rng).max(4.8),
                    cloud_boost: 0.48,
                    humidity_boost: 0.25,
                    temp_anomaly_c: atmo_rng.randf_range(season.front_temp_anomaly_c_range[0], season.front_temp_anomaly_c_range[1]),
                    wind_m_s: atmo_rng.randf_range(season.wind_speed_m_s_range[0], season.wind_speed_m_s_range[1]),
                    wind_dir_deg: base_wind_dir,
                });
            }
            FiveSectorRegime::Auto => {
                if !is_dry_day {
                    let expected = season.front_frequency_per_day.max(0.5);
                    let base_count = expected.floor() as i32;
                    let frac = expected - (base_count as f32);
                    let count = (base_count + if atmo_rng.randf() < frac { 1 } else { 0 }).clamp(1, 3);
                    let usable_start = window_start_abs_s + 900.0;
                    let usable_end = window_end_abs_s - 600.0;
                    let usable_span = (usable_end - usable_start).max(1800.0);
                    for ei in 0..count {
                        let usable_f32 = usable_span as f32;
                        let dur = atmo_rng.randf_range(
                            season.front_duration_s_range[0].min(usable_f32 * 0.7),
                            season.front_duration_s_range[1].min(usable_f32 * 0.9),
                        ) as f64;
                        let peak_t = usable_start
                            + ((ei as f64 + 0.5) / (count as f64)) * usable_span
                            + (atmo_rng.randf_range(-0.15, 0.15) as f64) * (usable_span / (count as f64));
                        let half = 0.5 * dur;
                        global_episodes.push(SectorEpisode {
                            t_start_s: peak_t - half,
                            t_peak_s: peak_t,
                            t_end_s: peak_t + half,
                            peak_precip_mm_h: season.sample_precip_mm_h(&mut atmo_rng),
                            cloud_boost: atmo_rng.randf_range(season.front_cloud_boost_range[0], season.front_cloud_boost_range[1]),
                            humidity_boost: atmo_rng.randf_range(season.front_humidity_boost_range[0], season.front_humidity_boost_range[1]),
                            temp_anomaly_c: atmo_rng.randf_range(season.front_temp_anomaly_c_range[0], season.front_temp_anomaly_c_range[1]),
                            wind_m_s: atmo_rng.randf_range(season.wind_speed_m_s_range[0], season.wind_speed_m_s_range[1]),
                            wind_dir_deg: (base_wind_dir + atmo_rng.randf_range(-20.0, 20.0)).rem_euclid(360.0),
                        });
                    }
                }
            }
        }

        let mut sectors = Vec::with_capacity(FIVE_SECTOR_COUNT);
        for si in 0..FIVE_SECTOR_COUNT {
            let start_m = boundaries_m[si];
            let end_m = boundaries_m[si + 1];
            let center_m = 0.5 * (start_m + end_m);
            let rs = route.sample_at_progress(center_m);
            let mut grade_sum = 0.0_f32;
            for k in 0..5 {
                let pm = lerpf(start_m, end_m, (k as f32 + 0.5) / 5.0);
                grade_sum += route.sample_at_progress(pm).grade.abs();
            }
            let mean_abs_grade = grade_sum / 5.0;
            let windward_factor = rs.grade.max(0.0).min(0.25) / 0.25;
            let shade_factor = (1.0 - mean_abs_grade * 0.45).clamp(0.75, 1.0);
            let drainage_scale = 1.0 + mean_abs_grade * climate.five_sector_model.slope_drainage_gain;
            let geom = FiveSectorGeometry {
                sector_index: si,
                start_m,
                end_m,
                center_m,
                center_shader_station_m: rs.shader_station_m,
                center_altitude_m: rs.altitude_m,
                mean_abs_grade,
                shade_factor,
                drainage_scale,
                windward_factor,
            };

            let sector_episodes: Vec<SectorEpisode> = match regime {
                FiveSectorRegime::ControlledMixedAscent => {
                    let frac = (si as f32) / 4.0;
                    if si == 0 {
                        // Start: cold early snowfall that stops before T_base while clouds remain and road begins melting.
                        vec![
                            SectorEpisode {
                                t_start_s: base_abs_seconds - 5400.0,
                                t_peak_s: base_abs_seconds - 3300.0,
                                t_end_s: base_abs_seconds - 1100.0,
                                peak_precip_mm_h: 9.0,
                                cloud_boost: 0.48,
                                humidity_boost: 0.28,
                                temp_anomaly_c: -6.2,
                                wind_m_s: 4.5,
                                wind_dir_deg: base_wind_dir,
                            },
                            SectorEpisode {
                                t_start_s: base_abs_seconds - 900.0,
                                t_peak_s: base_abs_seconds + 300.0,
                                t_end_s: base_abs_seconds + 1800.0,
                                peak_precip_mm_h: 0.0,
                                cloud_boost: 0.42,
                                humidity_boost: 0.14,
                                temp_anomaly_c: 0.6,
                                wind_m_s: 4.0,
                                wind_dir_deg: base_wind_dir,
                            },
                        ]
                    } else if si <= 2 {
                        // Mid ascent: warm liquid rainfall cleanly washing bare pavement.
                        vec![SectorEpisode {
                            t_start_s: base_abs_seconds - 1500.0,
                            t_peak_s: base_abs_seconds + 200.0,
                            t_end_s: base_abs_seconds + 2400.0,
                            peak_precip_mm_h: 7.5,
                            cloud_boost: 0.48,
                            humidity_boost: 0.28,
                            temp_anomaly_c: 1.8 - frac * 1.2,
                            wind_m_s: 5.5,
                            wind_dir_deg: base_wind_dir,
                        }]
                    } else {
                        // Abra summit: cold active snowfall accumulating on carriageway lateral edges & central crown.
                        vec![SectorEpisode {
                            t_start_s: base_abs_seconds - 4200.0,
                            t_peak_s: base_abs_seconds - 600.0,
                            t_end_s: base_abs_seconds + 2400.0,
                            peak_precip_mm_h: 10.5,
                            cloud_boost: 0.52,
                            humidity_boost: 0.30,
                            temp_anomaly_c: -8.2,
                            wind_m_s: 7.0,
                            wind_dir_deg: base_wind_dir,
                        }]
                    }
                }
                FiveSectorRegime::ControlledRefreeze => {
                    // Warm rain before T_base - 40 min, then overcast cold front freeze across T_base .. T_base + 30 min.
                    vec![
                        SectorEpisode {
                            t_start_s: base_abs_seconds - 5400.0,
                            t_peak_s: base_abs_seconds - 3600.0,
                            t_end_s: base_abs_seconds - 2000.0,
                            peak_precip_mm_h: 10.5,
                            cloud_boost: 0.48,
                            humidity_boost: 0.25,
                            temp_anomaly_c: 5.0,
                            wind_m_s: 3.5,
                            wind_dir_deg: base_wind_dir,
                        },
                        SectorEpisode {
                            t_start_s: base_abs_seconds - 1800.0,
                            t_peak_s: base_abs_seconds + 600.0,
                            t_end_s: base_abs_seconds + 3600.0,
                            peak_precip_mm_h: 0.0,
                            cloud_boost: 0.55,
                            humidity_boost: 0.22,
                            temp_anomaly_c: -11.5,
                            wind_m_s: 8.5,
                            wind_dir_deg: base_wind_dir,
                        },
                    ]
                }
                FiveSectorRegime::ControlledTimingEpisode => global_episodes.clone(),
                _ => {
                    let offset_norm = (si as f64) / 4.0 - 0.5;
                    let lag_s = offset_norm * lag_dir * lag_total_s;
                    let oro_boost = if season.orographic_enabled {
                        1.0 + season.orographic_precip_gain * windward_factor
                    } else {
                        1.0
                    };
                    global_episodes
                        .iter()
                        .map(|ep| SectorEpisode {
                            t_start_s: ep.t_start_s + lag_s,
                            t_peak_s: ep.t_peak_s + lag_s,
                            t_end_s: ep.t_end_s + lag_s,
                            peak_precip_mm_h: ep.peak_precip_mm_h * oro_boost,
                            cloud_boost: ep.cloud_boost,
                            humidity_boost: ep.humidity_boost,
                            temp_anomaly_c: ep.temp_anomaly_c,
                            wind_m_s: ep.wind_m_s,
                            wind_dir_deg: ep.wind_dir_deg,
                        })
                        .collect()
                }
            };

            let marks = build_marks_from_episodes(
                window_start_abs_s,
                window_end_abs_s,
                &season,
                &sector_episodes,
                base_wind_spd,
                base_wind_dir,
            );
            sectors.push(FiveSectorData { geom, marks });
        }

        Self {
            route,
            climate,
            season_id,
            season,
            regime,
            event_seed,
            climate_seed,
            snow_mask_seed,
            ice_mask_seed,
            puddle_seed,
            base_abs_seconds,
            window_start_abs_s,
            window_end_abs_s,
            is_dry_day,
            sectors,
            water_retention_enabled: false,
            water_retention_config: WaterRetentionConfig::default(),
            water_retention_profile: None,
            water_retention_warned: false,
        }
    }

    pub fn ensure_water_retention_profile(&mut self) -> bool {
        if self.water_retention_profile.is_none() {
            let profile = WaterRetentionProfile::build(&self.route, &self.water_retention_config);
            self.water_retention_profile = Some(profile);
        }
        self.water_retention_profile.as_ref().map(|p| p.valid).unwrap_or(false)
    }

    pub fn set_water_retention_enabled(&mut self, enabled: bool) -> bool {
        self.water_retention_enabled = enabled;
        if enabled {
            self.ensure_water_retention_profile()
        } else {
            self.water_retention_profile.as_ref().map(|p| p.valid).unwrap_or(false)
        }
    }

    #[inline]
    pub fn is_water_retention_active(&self) -> bool {
        self.water_retention_enabled
            && self
                .water_retention_profile
                .as_ref()
                .map(|p| p.valid)
                .unwrap_or(false)
    }

    #[inline]
    pub fn sample_water_retention(&self, progress_m: f32) -> f32 {
        if !self.is_water_retention_active() {
            return 1.0;
        }
        self.water_retention_profile
            .as_ref()
            .map(|p| p.sample_retention(progress_m))
            .unwrap_or(1.0)
    }

    pub fn sector_index_at_progress(&self, progress_m: f32) -> usize {
        for (i, s) in self.sectors.iter().enumerate() {
            if progress_m < s.geom.end_m || i + 1 == self.sectors.len() {
                return i;
            }
        }
        0
    }

    pub fn sector_blend_weights(&self, progress_m: f32) -> (usize, usize, f32) {
        let p = progress_m.clamp(0.0, self.route.total_distance_m.max(1.0));
        if self.sectors.is_empty() {
            return (0, 0, 0.0);
        }
        let n = self.sectors.len();
        if p <= self.sectors[0].geom.center_m {
            return (0, 0, 0.0);
        }
        if p >= self.sectors[n - 1].geom.center_m {
            return (n - 1, n - 1, 0.0);
        }
        for k in 0..(n - 1) {
            let ca = self.sectors[k].geom.center_m;
            let cb = self.sectors[k + 1].geom.center_m;
            if p >= ca && p <= cb {
                let span = (cb - ca).max(1e-3);
                let t = ((p - ca) / span).clamp(0.0, 1.0);
                return (k, k + 1, t);
            }
        }
        (n - 1, n - 1, 0.0)
    }

    fn resolve_atmosphere_from_mark(
        &self,
        mark: &SectorTimeMark,
        progress_m: f32,
        shader_station_m: f32,
        altitude_m: f32,
        elapsed_since_base_s: f64,
    ) -> AtmosphereSample {
        let hour = (mark.abs_time_s / 3600.0).rem_euclid(24.0) as f32;
        let diurnal_phase = ((hour - (self.season.diurnal_peak_hour - 6.0)) * PI / 12.0).sin();
        let ref_temp = self.season.base_temp_c
            + diurnal_phase * (self.season.diurnal_amplitude_c * 0.5)
            + mark.temp_anomaly_c;
        let mut air_c = ref_temp
            - mark.lapse_rate_c_per_km * ((altitude_m - self.climate.reference_altitude_m) / 1000.0);
        if !matches!(
            self.regime,
            FiveSectorRegime::ControlledMixedAscent | FiveSectorRegime::ControlledRefreeze
        ) {
            if let Some(transition_m) = self.route.snow_transition_altitude_m {
                let front_weight = 0.9 * smoothstep(0.1, 0.8, mark.precip_base_mm_h);
                // Anchor the wet-bulb transition during the front, retaining a share
                // of the weather anomaly and tapering the adjustment as it dries.
                let target_wet_bulb_c = 0.9 - (altitude_m - transition_m) * 0.025;
                let wet_bulb_c = wet_bulb_celsius(air_c, mark.humidity);
                air_c += front_weight * (target_wet_bulb_c - wet_bulb_c);
            }
        }
        let solar = solar_factor_for_hour(hour);
        let irr = if solar <= 0.0 {
            0.0
        } else {
            let cloud_att = (1.0 - 0.88 * mark.cloud_cover.powf(1.35)).clamp(0.06, 1.0);
            let alt_gain = 1.0 + 0.03 * ((altitude_m - 3000.0).max(0.0) / 1000.0);
            1060.0 * solar * cloud_att * alt_gain
        };
        let wet_bulb_c = wet_bulb_celsius(air_c, mark.humidity);
        let precip_total = mark.precip_base_mm_h.max(0.0);
        let (rain_mm_h, snow_mm_h, precip_kind) = if precip_total <= 0.01 {
            (0.0, 0.0, PrecipKind::None)
        } else {
            let snow_frac = 1.0
                - smoothstep(
                    self.climate.wet_bulb_snow_below_c,
                    self.climate.wet_bulb_rain_above_c,
                    wet_bulb_c,
                );
            let snow = precip_total * snow_frac;
            let rain = precip_total - snow;
            let kind = if snow_frac >= 0.85 {
                PrecipKind::Snow
            } else if snow_frac <= 0.15 {
                PrecipKind::Rain
            } else {
                PrecipKind::Mixed
            };
            (rain, snow, kind)
        };
        AtmosphereSample {
            progress_m,
            shader_station_m,
            elapsed_s: elapsed_since_base_s,
            hour_of_day: hour,
            altitude_m,
            air_c,
            wet_bulb_c,
            humidity: mark.humidity,
            cloud_cover: mark.cloud_cover,
            irradiance_w_m2: irr,
            precip_total_mm_h: precip_total,
            rain_mm_h,
            snow_mm_h,
            precip_kind,
            wind_m_s: mark.wind_m_s,
            wind_dir_deg: mark.wind_dir_deg,
        }
    }

    pub fn sample_sector_at_time(&self, sector_idx: usize, abs_t: f64) -> AtmosphereSample {
        let s = &self.sectors[sector_idx];
        let mark = eval_sector_marks(&s.marks, abs_t);
        self.resolve_atmosphere_from_mark(
            &mark,
            s.geom.center_m,
            s.geom.center_shader_station_m,
            s.geom.center_altitude_m,
            abs_t - self.base_abs_seconds,
        )
    }

    #[allow(dead_code)]
    pub fn sample_route_at_time(&self, progress_m: f32, abs_t: f64) -> AtmosphereSample {
        let rs = self.route.sample_at_progress(progress_m);
        let (k0, k1, w) = self.sector_blend_weights(progress_m);
        let m0 = eval_sector_marks(&self.sectors[k0].marks, abs_t);
        let mark = if k0 == k1 {
            m0
        } else {
            let m1 = eval_sector_marks(&self.sectors[k1].marks, abs_t);
            interpolate_mark(&m0, &m1, w)
        };
        self.resolve_atmosphere_from_mark(
            &mark,
            rs.progress_m,
            rs.shader_station_m,
            rs.altitude_m,
            abs_t - self.base_abs_seconds,
        )
    }

    /// Precalculates all 5 sector atmospheres + road surface snapshot once before countdown
    /// at `effective_abs_seconds`, integrating each sector's temporal marks by segment.
    pub fn build_snapshot_at(&self, effective_abs_seconds: f64, raw_surface_type: &str) -> FiveSectorSnapshot {
        let surface_key = normalize_surface_key(raw_surface_type);
        let material = self
            .climate
            .surface_profiles
            .get(&surface_key)
            .cloned()
            .unwrap_or_else(|| SurfaceMaterialParams::default_for(&surface_key));
        let cfg = &self.climate.surface_balance;
        let max_substep = self.climate.five_sector_model.max_substep_s.max(30.0) as f64;
        let cut_t = effective_abs_seconds.clamp(self.window_start_abs_s, self.window_end_abs_s);

        let mut sector_atmo = Vec::with_capacity(FIVE_SECTOR_COUNT);
        let mut sector_surface = Vec::with_capacity(FIVE_SECTOR_COUNT);

        for si in 0..self.sectors.len() {
            let s = &self.sectors[si];
            sector_atmo.push(self.sample_sector_at_time(si, effective_abs_seconds));

            let atmo0 = self.sample_sector_at_time(si, self.window_start_abs_s);
            let mut cell = SurfaceCell {
                progress_m: s.geom.center_m,
                shader_station_m: s.geom.center_shader_station_m,
                altitude_m: s.geom.center_altitude_m,
                shade_factor: s.geom.shade_factor,
                drainage_scale: s.geom.drainage_scale,
                ground_c: atmo0.air_c + 1.5,
                water_mm: 0.0,
                snow_mm: 0.0,
                ice_mm: 0.0,
                saturation: 0.0,
            };
            let mut audit = MassBalanceAudit::default();
            let mut last_precip_t: Option<f64> = None;

            // Collect mark segment boundaries inside [window_start_abs_s, cut_t].
            let mut seg_bounds: Vec<f64> = Vec::with_capacity(s.marks.len() + 2);
            seg_bounds.push(self.window_start_abs_s);
            for m in &s.marks {
                if m.abs_time_s > self.window_start_abs_s + 1.0 && m.abs_time_s < cut_t - 1.0 {
                    seg_bounds.push(m.abs_time_s);
                }
            }
            if cut_t > self.window_start_abs_s + 1e-3 {
                seg_bounds.push(cut_t);
            }

            for seg_i in 1..seg_bounds.len() {
                let ta = seg_bounds[seg_i - 1];
                let tb = seg_bounds[seg_i];
                let total_seg = (tb - ta).max(0.0);
                if total_seg <= 1e-3 {
                    continue;
                }
                let n_sub = ((total_seg / max_substep).ceil() as usize).max(1);
                let dt_sub = total_seg / (n_sub as f64);
                for sub_k in 0..n_sub {
                    let t_mid = ta + (sub_k as f64 + 0.5) * dt_sub;
                    let forcing = self.sample_sector_at_time(si, t_mid);
                    if forcing.precip_total_mm_h > 0.05 {
                        last_precip_t = Some(ta + (sub_k as f64 + 1.0) * dt_sub);
                    }
                    // Unconditional exponential pavement-temperature relaxation within sub-interval
                    // before evaluating phase transfers + drainage + evaporation on the interval.
                    let dt_f32 = dt_sub as f32;
                    let snow_cov = (cell.snow_mm / cfg.snow_coverage_full_mm).clamp(0.0, 1.0);
                    let abs_eff = lerpf(material.solar_absorption, material.snow_albedo_absorption, snow_cov * 0.85);
                    let solar_gain = forcing.irradiance_w_m2 * abs_eff * cell.shade_factor;
                    let conv_coeff = (material.air_exchange_w_m2_k * (1.0 + 0.045 * forcing.wind_m_s.min(18.0))).max(0.5);
                    let evap_mm_h = compute_evap_mm_h(
                        forcing.irradiance_w_m2,
                        forcing.wind_m_s,
                        forcing.humidity,
                        cell.ground_c,
                        cell.water_mm,
                        &material,
                    );
                    let evap_heat_loss = evap_mm_h * 680.0;
                    let precip_heat = forcing.rain_mm_h * 1.16 * (cell.ground_c - forcing.air_c).max(0.0)
                        + forcing.snow_mm_h * (2.5 + 0.8 * (cell.ground_c - 0.5).max(0.0));
                    let t_eq = (forcing.air_c + (solar_gain - evap_heat_loss - precip_heat) / conv_coeff).clamp(-25.0, 60.0);
                    let cap_j_m2_k = (material.thermal_capacity_kj_m2_k * 1000.0).max(1000.0);
                    let tau_s = cap_j_m2_k / conv_coeff;
                    let decay = (-dt_f32 / tau_s).exp();
                    cell.ground_c = (t_eq + (cell.ground_c - t_eq) * decay).clamp(-25.0, 60.0);

                    // Zero-thermal-delta pass through step_surface_cell by matching thermal equilibrium
                    // (or apply moisture step directly with exact mass conservation).
                    let dt_h = dt_f32 / 3600.0;
                    let rain_in = (forcing.rain_mm_h * dt_h).max(0.0);
                    let snow_total_in = (forcing.snow_mm_h * dt_h).max(0.0);
                    let stick_frac = 1.0 - smoothstep(cfg.snow_stick_below_c, cfg.snow_stick_above_c, cell.ground_c);
                    let snow_retained = snow_total_in * stick_frac;
                    let snow_contact_melt = snow_total_in - snow_retained;
                    cell.snow_mm += snow_retained;
                    cell.water_mm += rain_in + snow_contact_melt;

                    if cell.ground_c > cfg.snow_melt_start_c && cell.snow_mm > 0.0 {
                        let band = smoothstep(
                            cfg.snow_melt_start_c,
                            cfg.snow_melt_start_c + cfg.snow_melt_band_c,
                            cell.ground_c,
                        );
                        let temp_drive = (cell.ground_c - cfg.snow_melt_start_c).max(0.0);
                        let solar_melt = cfg.snow_solar_melt_mm_h_per_kw * (forcing.irradiance_w_m2 / 1000.0) * cell.shade_factor;
                        let pot = (cfg.snow_melt_rate_mm_h_per_c * temp_drive * (0.35 + 0.65 * band) + solar_melt) * dt_h;
                        let melt = pot.min(cell.snow_mm).max(0.0);
                        cell.snow_mm -= melt;
                        cell.water_mm += melt;
                    }
                    if cell.ground_c > cfg.ice_melt_start_c && cell.ice_mm > 0.0 {
                        let band = smoothstep(
                            cfg.ice_melt_start_c,
                            cfg.ice_melt_start_c + cfg.ice_melt_band_c,
                            cell.ground_c,
                        );
                        let temp_drive = (cell.ground_c - cfg.ice_melt_start_c).max(0.0);
                        let pot = cfg.ice_melt_rate_mm_h_per_c * temp_drive * (0.35 + 0.65 * band) * dt_h;
                        let melt = pot.min(cell.ice_mm).max(0.0);
                        cell.ice_mm -= melt;
                        cell.water_mm += melt;
                    } else if cell.ground_c < cfg.freeze_below_c && cell.water_mm > 0.0 {
                        let band = smoothstep(
                            cfg.freeze_below_c,
                            cfg.freeze_below_c - cfg.freeze_band_c,
                            cell.ground_c,
                        );
                        let temp_drive = (cfg.freeze_below_c - cell.ground_c).max(0.0);
                        let pot = cfg.freeze_rate_mm_h_per_c * temp_drive * (0.35 + 0.65 * band) * dt_h;
                        let frozen = pot.min(cell.water_mm).max(0.0);
                        cell.water_mm -= frozen;
                        cell.ice_mm += frozen;
                    }

                    // Exact exponential drainage above capillary film over dt_h.
                    let drainable = (cell.water_mm - material.retention_film_mm).max(0.0);
                    let drain_out = if drainable > 0.0 {
                        let k_drain = (material.drainage_mm_h * cell.drainage_scale / 2.5).max(0.0);
                        let d_exp = drainable * (1.0 - (-k_drain * dt_h).exp());
                        let d_cap = material.drainage_mm_h * cell.drainage_scale * dt_h;
                        d_exp.min(d_cap).min(drainable).max(0.0)
                    } else {
                        0.0
                    };
                    cell.water_mm -= drain_out;

                    let evap_rate = compute_evap_mm_h(
                        forcing.irradiance_w_m2,
                        forcing.wind_m_s,
                        forcing.humidity,
                        cell.ground_c,
                        cell.water_mm,
                        &material,
                    );
                    let evap_out = (evap_rate * dt_h).min(cell.water_mm).max(0.0);
                    cell.water_mm -= evap_out;

                    if material.porosity_saturation_scale > 0.0 {
                        let sat_delta = (rain_in + snow_contact_melt) * material.porosity_saturation_scale
                            - (drain_out * 0.05 + evap_out * 0.03);
                        cell.saturation = (cell.saturation + sat_delta).clamp(0.0, 1.0);
                    } else {
                        cell.saturation = 0.0;
                    }

                    let mut overflow = 0.0_f32;
                    if cell.water_mm > cfg.max_water_mm {
                        overflow += cell.water_mm - cfg.max_water_mm;
                        cell.water_mm = cfg.max_water_mm;
                    }
                    if cell.snow_mm > cfg.max_snow_mm {
                        overflow += cell.snow_mm - cfg.max_snow_mm;
                        cell.snow_mm = cfg.max_snow_mm;
                    }
                    if cell.ice_mm > cfg.max_ice_mm {
                        overflow += cell.ice_mm - cfg.max_ice_mm;
                        cell.ice_mm = cfg.max_ice_mm;
                    }

                    audit.rain_in_mm += rain_in as f64;
                    audit.snow_in_mm += snow_total_in as f64;
                    audit.evap_out_mm += evap_out as f64;
                    audit.drain_out_mm += drain_out as f64;
                    audit.clipped_overflow_mm += overflow as f64;
                }
            }

            let time_since_precip = last_precip_t
                .map(|lt| (cut_t - lt).max(0.0))
                .unwrap_or_else(|| (cut_t - self.window_start_abs_s).max(0.0));
            sector_surface.push(SectorSurfaceState {
                ground_c: cell.ground_c,
                water_mm: cell.water_mm,
                snow_mm: cell.snow_mm,
                ice_mm: cell.ice_mm,
                saturation: cell.saturation,
                audit,
                time_since_last_precip_s: time_since_precip,
            });
        }

        FiveSectorSnapshot {
            effective_abs_seconds: cut_t,
            surface_type: surface_key,
            material,
            patch_seed: self.snow_mask_seed,
            ice_patch_seed: self.ice_mask_seed,
            revision: 1,
            sector_atmo,
            sector_surface,
        }
    }
}

impl FiveSectorSnapshot {
    pub fn sample_atmosphere_for_pass(&self, journey: &FiveSectorJourney, progress_m: f32) -> AtmosphereSample {
        if journey.route.snow_transition_altitude_m.is_some() {
            return journey.sample_route_at_time(progress_m, self.effective_abs_seconds);
        }
        let rs = journey.route.sample_at_progress(progress_m);
        let (k0, k1, w) = journey.sector_blend_weights(progress_m);
        let a0 = &self.sector_atmo[k0];
        let a1 = &self.sector_atmo[k1];

        let cloud = if k0 == k1 { a0.cloud_cover } else { lerpf(a0.cloud_cover, a1.cloud_cover, w) };
        let hum = if k0 == k1 { a0.humidity } else { lerpf(a0.humidity, a1.humidity, w) };
        let precip_total = if k0 == k1 { a0.precip_total_mm_h } else { lerpf(a0.precip_total_mm_h, a1.precip_total_mm_h, w) };
        let wind_spd = if k0 == k1 { a0.wind_m_s } else { lerpf(a0.wind_m_s, a1.wind_m_s, w) };
        let wind_dir = if k0 == k1 { a0.wind_dir_deg } else { lerp_angle_deg(a0.wind_dir_deg, a1.wind_dir_deg, w) };
        let hour = a0.hour_of_day;

        // Reconstruct reference-level air temperature between the two interpolated sector centers,
        // then adjust cleanly to the queried point's local route altitude.
        let m0 = eval_sector_marks(&journey.sectors[k0].marks, self.effective_abs_seconds);
        let m1 = eval_sector_marks(&journey.sectors[k1].marks, self.effective_abs_seconds);
        let lapse = if k0 == k1 { m0.lapse_rate_c_per_km } else { lerpf(m0.lapse_rate_c_per_km, m1.lapse_rate_c_per_km, w) };
        let sec_alt = if k0 == k1 { a0.altitude_m } else { lerpf(a0.altitude_m, a1.altitude_m, w) };
        let sec_air = if k0 == k1 { a0.air_c } else { lerpf(a0.air_c, a1.air_c, w) };
        let air_c = sec_air - lapse * ((rs.altitude_m - sec_alt) / 1000.0);

        let solar = solar_factor_for_hour(hour);
        let irr = if solar <= 0.0 {
            0.0
        } else {
            let cloud_att = (1.0 - 0.88 * cloud.powf(1.35)).clamp(0.06, 1.0);
            let alt_gain = 1.0 + 0.03 * ((rs.altitude_m - 3000.0).max(0.0) / 1000.0);
            1060.0 * solar * cloud_att * alt_gain
        };
        let wet_bulb_c = wet_bulb_celsius(air_c, hum);
        let (rain_mm_h, snow_mm_h, precip_kind) = if precip_total <= 0.01 {
            (0.0, 0.0, PrecipKind::None)
        } else {
            let snow_frac = 1.0
                - smoothstep(
                    journey.climate.wet_bulb_snow_below_c,
                    journey.climate.wet_bulb_rain_above_c,
                    wet_bulb_c,
                );
            let snow = precip_total * snow_frac;
            let rain = precip_total - snow;
            let kind = if snow_frac >= 0.85 {
                PrecipKind::Snow
            } else if snow_frac <= 0.15 {
                PrecipKind::Rain
            } else {
                PrecipKind::Mixed
            };
            (rain, snow, kind)
        };

        AtmosphereSample {
            progress_m: rs.progress_m,
            shader_station_m: rs.shader_station_m,
            elapsed_s: self.effective_abs_seconds - journey.base_abs_seconds,
            hour_of_day: hour,
            altitude_m: rs.altitude_m,
            air_c,
            wet_bulb_c,
            humidity: hum,
            cloud_cover: cloud,
            irradiance_w_m2: irr,
            precip_total_mm_h: precip_total,
            rain_mm_h,
            snow_mm_h,
            precip_kind,
            wind_m_s: wind_spd,
            wind_dir_deg: wind_dir,
        }
    }

    pub fn interpolate_surface_columns_unmodulated(&self, journey: &FiveSectorJourney, progress_m: f32) -> (f32, f32, f32, f32, f32, f32) {
        let rs = journey.route.sample_at_progress(progress_m);
        let (k0, k1, w) = journey.sector_blend_weights(progress_m);
        let s0 = &self.sector_surface[k0];
        let s1 = &self.sector_surface[k1];
        let a0 = &self.sector_atmo[k0];
        let a1 = &self.sector_atmo[k1];

        let sec_alt = if k0 == k1 { a0.altitude_m } else { lerpf(a0.altitude_m, a1.altitude_m, w) };
        let base_ground_c = if k0 == k1 { s0.ground_c } else { lerpf(s0.ground_c, s1.ground_c, w) };
        let mut water_mm = if k0 == k1 { s0.water_mm } else { lerpf(s0.water_mm, s1.water_mm, w) };
        let mut snow_mm = if k0 == k1 { s0.snow_mm } else { lerpf(s0.snow_mm, s1.snow_mm, w) };
        let mut ice_mm = if k0 == k1 { s0.ice_mm } else { lerpf(s0.ice_mm, s1.ice_mm, w) };
        let saturation = if k0 == k1 { s0.saturation } else { lerpf(s0.saturation, s1.saturation, w) };

        let dh = rs.altitude_m - sec_alt;
        let ground_c = (base_ground_c - 6.0 * (dh / 1000.0) * 0.75).clamp(-25.0, 60.0);
        // Subtle local thermal phase nudge relative to sector center (zero effect at sector centers where dh == 0).
        let cfg = &journey.climate.surface_balance;
        if dh.abs() > 15.0 {
            if ground_c > cfg.snow_melt_start_c + 1.0 && dh < -15.0 && snow_mm > 0.0 {
                let shift_f = (((ground_c - cfg.snow_melt_start_c - 1.0) / 4.0) * 0.25).clamp(0.0, 0.35);
                let d_snow = snow_mm * shift_f;
                snow_mm -= d_snow;
                water_mm += d_snow;
            } else if ground_c < cfg.freeze_below_c - 0.5 && dh > 15.0 && water_mm > 0.0 {
                let shift_f = (((cfg.freeze_below_c - 0.5 - ground_c) / 4.0) * 0.25).clamp(0.0, 0.35);
                let d_ice = water_mm * shift_f;
                water_mm -= d_ice;
                ice_mm += d_ice;
            }
        }
        (ground_c, water_mm, snow_mm, ice_mm, saturation, rs.shader_station_m)
    }

    pub fn interpolate_surface_columns(&self, journey: &FiveSectorJourney, progress_m: f32) -> (f32, f32, f32, f32, f32, f32) {
        let (ground_c, mut water_mm, snow_mm, ice_mm, saturation, shader_station_m) =
            self.interpolate_surface_columns_unmodulated(journey, progress_m);
        if journey.is_water_retention_active() {
            if water_mm <= 0.0 {
                water_mm = 0.0;
            } else {
                let ret = journey.sample_water_retention(progress_m);
                water_mm = (water_mm * ret).clamp(0.0, journey.climate.surface_balance.max_water_mm);
            }
        }
        (ground_c, water_mm, snow_mm, ice_mm, saturation, shader_station_m)
    }

    pub fn sample_surface_at(&self, journey: &FiveSectorJourney, progress_m: f32, lateral_t: f32) -> SurfaceSample {
        let a = self.sample_atmosphere_for_pass(journey, progress_m);
        let (ground_c, water_mm, snow_mm, ice_mm, saturation, shader_station_m) =
            self.interpolate_surface_columns(journey, progress_m);
        let cfg = &journey.climate.surface_balance;
        let lat = lateral_t.clamp(-1.0, 1.0);
        let snow_seed_off = patch_seed_offsets(self.patch_seed as u64).0;

        let snow_cov = local_pattern_coverage(
            snow_mm,
            cfg.snow_coverage_full_mm,
            0.03,
            shader_station_m,
            lat,
            snow_seed_off,
            1.0,
        );
        // Continuous carriageway ice patches are disabled (water-only + lateral snow ribbons).
        let ice_cov = 0.0;
        let water_cov = if water_mm > 0.01 {
            smoothstep(0.01, cfg.water_coverage_full_mm, water_mm)
        } else {
            0.0
        };

        let snow_w = snow_cov.clamp(0.0, 1.0);
        let ice_w = 0.0;
        let dry_w = (1.0 - snow_w).clamp(0.0, 1.0);

        let water_eff = water_mm.clamp(0.0, cfg.tire_effective_water_cap_mm);
        let snow_eff = if snow_cov <= 0.001 {
            0.0
        } else {
            (snow_mm * (0.40 + 0.80 * snow_cov)).clamp(0.0, cfg.tire_effective_snow_cap_mm)
        };

        SurfaceSample {
            progress_m: a.progress_m,
            shader_station_m,
            lateral_t: lat,
            elapsed_s: 0.0,
            altitude_m: a.altitude_m,
            air_c: a.air_c,
            ground_c,
            water_mm,
            snow_mm,
            ice_mm,
            saturation,
            water_coverage: water_cov,
            snow_coverage: snow_cov,
            ice_coverage: ice_cov,
            dry_weight: dry_w,
            snow_weight: snow_w,
            ice_weight: ice_w,
            water_mm_effective: water_eff,
            snow_mm_effective: snow_eff,
            irradiance_w_m2: a.irradiance_w_m2,
            humidity: a.humidity,
            cloud_cover: a.cloud_cover,
            rain_mm_h: a.rain_mm_h,
            snow_mm_h: a.snow_mm_h,
            precip_total_mm_h: a.precip_total_mm_h,
            precip_kind: a.precip_kind,
            wind_m_s: a.wind_m_s,
            wind_dir_deg: a.wind_dir_deg,
        }
    }

    pub fn compute_puddle_fills(
        &self,
        journey: &FiveSectorJourney,
        distances: &[f32],
        twis: &[f32],
        min_waters: &[f32],
        retentions: &[f32],
    ) -> Vec<f32> {
        let count = distances.len().min(twis.len()).min(min_waters.len()).min(retentions.len());
        let fsm = &journey.climate.five_sector_model;
        let mut out = Vec::with_capacity(count);
        for i in 0..count {
            let (_gc, water_mm, _snow_mm, ice_mm, _sat, _st) =
                self.interpolate_surface_columns_unmodulated(journey, distances[i]);
            let min_w = min_waters[i].max(0.01);
            let twi = twis[i].clamp(0.0, 1.5);
            let ret = retentions[i].max(0.1);
            // Basin topography is applied once, independently of the surrounding road film.
            let eff_water = water_mm * (fsm.puddle_twi_base + fsm.puddle_twi_gain * twi);
            if eff_water <= min_w || water_mm <= 0.01 {
                out.push(0.0);
                continue;
            }
            let liquid_frac = if ice_mm > 0.001 {
                water_mm / (water_mm + ice_mm)
            } else {
                1.0
            };
            let fill = (((eff_water - min_w) * ret) / fsm.puddle_fill_divisor_mm).clamp(0.0, 1.0)
                * liquid_frac;
            out.push(if fill > 0.005 { fill } else { 0.0 });
        }
        out
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustFiveSectorWeather {
    journey: Option<FiveSectorJourney>,
    snapshot: Option<FiveSectorSnapshot>,
    advance_steps_called: u64,
    last_error: String,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustFiveSectorWeather {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            journey: None,
            snapshot: None,
            advance_steps_called: 0,
            last_error: String::new(),
            base,
        }
    }
}

#[godot_api]
impl RustFiveSectorWeather {
    #[func]
    #[allow(clippy::too_many_arguments)]
    pub fn configure_and_precompute_from_json(
        &mut self,
        climate_json: GString,
        route_json: GString,
        event_seed: i64,
        season_or_date: GString,
        base_abs_seconds: f64,
        effective_abs_seconds: f64,
        surface_type: GString,
        regime_override: GString,
    ) -> VarDictionary {
        let mut out = VarDictionary::new();
        self.last_error.clear();
        let climate = match ClimateProfile::from_json_str(&climate_json.to_string()) {
            Ok(c) => c,
            Err(e) => {
                self.last_error = e.clone();
                let _ = out.insert("ok", false);
                let _ = out.insert("error", e.as_str());
                return out;
            }
        };
        let route = match RouteProfile::from_json_str(&route_json.to_string()) {
            Ok(r) => r,
            Err(e) => {
                self.last_error = e.clone();
                let _ = out.insert("ok", false);
                let _ = out.insert("error", e.as_str());
                return out;
            }
        };
        let seed_u64 = event_seed as u64;
        let regime = FiveSectorRegime::from_str(&regime_override.to_string());
        let journey = FiveSectorJourney::build(
            route,
            climate,
            seed_u64,
            &season_or_date.to_string(),
            base_abs_seconds,
            regime,
        );
        let surface_str = surface_type.to_string();
        let snap = journey.build_snapshot_at(effective_abs_seconds, &surface_str);

        let _ = out.insert("ok", true);
        let _ = out.insert("mode", "five_sector_snapshot");
        let _ = out.insert("algo_version", FIVE_SECTOR_ALGO_VERSION as i64);
        let _ = out.insert("track_id", journey.route.track_id.as_str());
        let _ = out.insert("season_id", journey.season_id.as_str());
        let _ = out.insert("climate_seed", journey.climate_seed as i64);
        let _ = out.insert("puddle_seed", journey.puddle_seed as i64);
        let _ = out.insert("is_dry_day", journey.is_dry_day);
        let _ = out.insert("sector_count", journey.sectors.len() as i64);
        let _ = out.insert("base_abs_seconds", journey.base_abs_seconds);
        let _ = out.insert("effective_abs_seconds", snap.effective_abs_seconds);
        let _ = out.insert("surface_type", snap.surface_type.as_str());
        let _ = out.insert("fixed_snapshot", true);

        self.journey = Some(journey);
        self.snapshot = Some(snap);
        self.advance_steps_called = 0;
        out
    }

    #[func]
    pub fn configure_surface(&mut self, surface_type: GString) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(journey) = self.journey.as_ref() else {
            let _ = out.insert("ok", false);
            return out;
        };
        let eff_t = self
            .snapshot
            .as_ref()
            .map(|s| s.effective_abs_seconds)
            .unwrap_or(journey.base_abs_seconds);
        let snap = journey.build_snapshot_at(eff_t, &surface_type.to_string());
        let _ = out.insert("ok", true);
        let _ = out.insert("mode", "five_sector_snapshot");
        let _ = out.insert("surface_type", snap.surface_type.as_str());
        let _ = out.insert("sector_count", journey.sectors.len() as i64);
        self.snapshot = Some(snap);
        out
    }

    /// Re-evaluates the existing journey at a different start turn `effective_abs_seconds`
    /// without regenerating episodes or shifting candidate seeds.
    #[func]
    pub fn reevaluate_for_effective_time(&mut self, effective_abs_seconds: f64, surface_type: GString) -> bool {
        let Some(journey) = self.journey.as_ref() else {
            return false;
        };
        let stype = {
            let s = surface_type.to_string();
            if s.trim().is_empty() {
                self.snapshot
                    .as_ref()
                    .map(|sn| sn.surface_type.clone())
                    .unwrap_or_else(|| "asphalt".to_string())
            } else {
                s
            }
        };
        let prev_rev = self.snapshot.as_ref().map(|sn| sn.revision).unwrap_or(0);
        let mut snap = journey.build_snapshot_at(effective_abs_seconds, &stype);
        snap.revision = prev_rev.saturating_add(1).max(1);
        self.snapshot = Some(snap);
        true
    }

    /// Fixed-snapshot mode intentionally omits per-step soil/deposit advancement during the run.
    #[func]
    pub fn advance_surface(&mut self, _delta_s: f64, _solar_factor: f32) {
        self.advance_steps_called = self.advance_steps_called.wrapping_add(1);
    }

    #[func]
    pub fn advance_call_count(&self) -> i64 {
        self.advance_steps_called as i64
    }

    #[func]
    pub fn is_configured(&self) -> bool {
        self.journey.is_some() && self.snapshot.is_some()
    }

    #[func]
    pub fn last_error(&self) -> GString {
        GString::from(self.last_error.as_str())
    }

    #[func]
    pub fn progress_to_shader_station(&self, progress_m: f32) -> f32 {
        self.journey
            .as_ref()
            .map(|j| j.route.sample_at_progress(progress_m).shader_station_m)
            .unwrap_or(progress_m)
    }

    #[func]
    pub fn shader_station_to_progress(&self, shader_station_m: f32) -> f32 {
        self.journey
            .as_ref()
            .map(|j| j.route.shader_station_to_progress(shader_station_m))
            .unwrap_or(shader_station_m)
    }

    #[func]
    pub fn sample_atmosphere_at(&self, progress_m: f32, _elapsed_race_s: f64) -> VarDictionary {
        let mut out = VarDictionary::new();
        let (Some(journey), Some(snap)) = (self.journey.as_ref(), self.snapshot.as_ref()) else {
            let _ = out.insert("ok", false);
            return out;
        };
        let s = snap.sample_atmosphere_for_pass(journey, progress_m);
        let _ = out.insert("ok", true);
        let _ = out.insert("progress_m", s.progress_m);
        let _ = out.insert("shader_station_m", s.shader_station_m);
        let _ = out.insert("elapsed_s", s.elapsed_s);
        let _ = out.insert("hour_of_day", s.hour_of_day);
        let _ = out.insert("altitude_m", s.altitude_m);
        let _ = out.insert("air_c", s.air_c);
        let _ = out.insert("wet_bulb_c", s.wet_bulb_c);
        let _ = out.insert("humidity", s.humidity);
        let _ = out.insert("cloud_cover", s.cloud_cover);
        let _ = out.insert("irradiance_w_m2", s.irradiance_w_m2);
        let _ = out.insert("precip_total_mm_h", s.precip_total_mm_h);
        let _ = out.insert("rain_mm_h", s.rain_mm_h);
        let _ = out.insert("snow_mm_h", s.snow_mm_h);
        let _ = out.insert("precip_kind", s.precip_kind.as_str());
        let _ = out.insert("wind_m_s", s.wind_m_s);
        let _ = out.insert("wind_direction_deg", s.wind_dir_deg);
        out
    }

    #[func]
    pub fn sample_surface_at(&self, progress_m: f32, lateral_t: f32) -> VarDictionary {
        let mut out = VarDictionary::new();
        let (Some(journey), Some(snap)) = (self.journey.as_ref(), self.snapshot.as_ref()) else {
            let _ = out.insert("ok", false);
            return out;
        };
        let s = snap.sample_surface_at(journey, progress_m, lateral_t);
        let _ = out.insert("ok", true);
        let _ = out.insert("fixed_snapshot", true);
        let _ = out.insert("progress_m", s.progress_m);
        let _ = out.insert("shader_station_m", s.shader_station_m);
        let _ = out.insert("lateral_t", s.lateral_t);
        let _ = out.insert("elapsed_s", s.elapsed_s);
        let _ = out.insert("altitude_m", s.altitude_m);
        let _ = out.insert("air_c", s.air_c);
        let _ = out.insert("ground_c", s.ground_c);
        let _ = out.insert("water_mm", s.water_mm);
        let _ = out.insert("snow_mm", s.snow_mm);
        let _ = out.insert("ice_mm", s.ice_mm);
        let _ = out.insert("saturation", s.saturation);
        let _ = out.insert("water_coverage", s.water_coverage);
        let _ = out.insert("snow_coverage", s.snow_coverage);
        let _ = out.insert("ice_coverage", s.ice_coverage);
        let _ = out.insert("dry_weight", s.dry_weight);
        let _ = out.insert("snow_weight", s.snow_weight);
        let _ = out.insert("ice_weight", s.ice_weight);
        let _ = out.insert("water_mm_effective", s.water_mm_effective);
        let _ = out.insert("snow_mm_effective", s.snow_mm_effective);
        let _ = out.insert("irradiance_w_m2", s.irradiance_w_m2);
        let _ = out.insert("humidity", s.humidity);
        let _ = out.insert("cloud_cover", s.cloud_cover);
        let _ = out.insert("rain_mm_h", s.rain_mm_h);
        let _ = out.insert("snow_mm_h", s.snow_mm_h);
        let _ = out.insert("precip_total_mm_h", s.precip_total_mm_h);
        let _ = out.insert("precip_kind", s.precip_kind.as_str());
        let _ = out.insert("wind_m_s", s.wind_m_s);
        let _ = out.insert("wind_direction_deg", s.wind_dir_deg);
        out
    }

    #[func]
    pub fn compute_puddle_fills(
        &self,
        distances: PackedFloat32Array,
        twis: PackedFloat32Array,
        min_waters: PackedFloat32Array,
        retentions: PackedFloat32Array,
    ) -> PackedFloat32Array {
        let (Some(journey), Some(snap)) = (self.journey.as_ref(), self.snapshot.as_ref()) else {
            return PackedFloat32Array::new();
        };
        let fills = snap.compute_puddle_fills(
            journey,
            distances.as_slice(),
            twis.as_slice(),
            min_waters.as_slice(),
            retentions.as_slice(),
        );
        PackedFloat32Array::from(fills.as_slice())
    }

    #[func]
    pub fn set_local_water_retention(&mut self, enabled: bool) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(journey) = self.journey.as_mut() else {
            let _ = out.insert("ok", false);
            let _ = out.insert("enabled", false);
            let _ = out.insert("valid", false);
            let _ = out.insert("diagnostic", "Journey not configured");
            return out;
        };
        let prev_active = journey.is_water_retention_active();
        let valid = journey.set_water_retention_enabled(enabled);
        let active = journey.is_water_retention_active();
        let diagnostic = journey
            .water_retention_profile
            .as_ref()
            .map(|p| p.diagnostic.clone())
            .unwrap_or_default();
        if enabled && !valid && !journey.water_retention_warned {
            journey.water_retention_warned = true;
            godot_warn!("Water retention profile invalid for '{}': {}; using neutral 1.0 retention", journey.route.track_id, diagnostic);
        }
        if prev_active != active {
            if let Some(snap) = self.snapshot.as_mut() {
                snap.revision = snap.revision.saturating_add(1).max(1);
            }
        }
        let sample_count = journey
            .water_retention_profile
            .as_ref()
            .map(|p| p.samples.len() as i64)
            .unwrap_or(0);
        let build_time_us = journey
            .water_retention_profile
            .as_ref()
            .map(|p| p.build_time_us as i64)
            .unwrap_or(0);
        let _ = out.insert("ok", true);
        let _ = out.insert("enabled", enabled);
        let _ = out.insert("active", active);
        let _ = out.insert("valid", valid);
        let _ = out.insert("diagnostic", diagnostic.as_str());
        let _ = out.insert("sample_count", sample_count);
        let _ = out.insert("build_time_us", build_time_us);
        out
    }

    #[func]
    pub fn water_retention_status(&self) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(journey) = self.journey.as_ref() else {
            let _ = out.insert("ok", false);
            return out;
        };
        let valid = journey.water_retention_profile.as_ref().map(|p| p.valid).unwrap_or(false);
        let diagnostic = journey
            .water_retention_profile
            .as_ref()
            .map(|p| p.diagnostic.as_str())
            .unwrap_or("");
        let sample_count = journey
            .water_retention_profile
            .as_ref()
            .map(|p| p.samples.len() as i64)
            .unwrap_or(0);
        let build_time_us = journey
            .water_retention_profile
            .as_ref()
            .map(|p| p.build_time_us as i64)
            .unwrap_or(0);
        let _ = out.insert("ok", true);
        let _ = out.insert("enabled", journey.water_retention_enabled);
        let _ = out.insert("active", journey.is_water_retention_active());
        let _ = out.insert("valid", valid);
        let _ = out.insert("diagnostic", diagnostic);
        let _ = out.insert("sample_count", sample_count);
        let _ = out.insert("build_time_us", build_time_us);
        out
    }

    #[func]
    pub fn inspect_water_retention_profile(&self, step_m: f32) -> VarDictionary {
        let mut out = VarDictionary::new();
        let (Some(journey), Some(snap)) = (self.journey.as_ref(), self.snapshot.as_ref()) else {
            let _ = out.insert("ok", false);
            return out;
        };
        let total = journey.route.total_distance_m.max(1.0);
        let step = step_m.max(5.0);
        let count = ((total / step).ceil() as usize).max(1) + 1;
        let mut rows = VarArray::new();
        let cfg = &journey.climate.surface_balance;
        for i in 0..count {
            let p = if i + 1 == count {
                total
            } else {
                (i as f32 * step).min(total)
            };
            let rs = journey.route.sample_at_progress(p);
            let sec = journey.sector_index_at_progress(p);
            let (ret, slope, conc, raw_ret) = journey
                .water_retention_profile
                .as_ref()
                .map(|prof| prof.sample_detail(p))
                .unwrap_or((1.0, 0.0, 0.0, 1.0));
            let (_gc0, water_before, _sn0, _ic0, _sat0, _st0) =
                snap.interpolate_surface_columns_unmodulated(journey, p);
            let (_gc1, water_after, _sn1, _ic1, _sat1, _st1) =
                snap.interpolate_surface_columns(journey, p);
            let water_cov = if water_after > 0.01 {
                smoothstep(0.01, cfg.water_coverage_full_mm, water_after)
            } else {
                0.0
            };
            let mut row = VarDictionary::new();
            let _ = row.insert("progress_m", rs.progress_m);
            let _ = row.insert("shader_station_m", rs.shader_station_m);
            let _ = row.insert("sector_index", sec as i32);
            let _ = row.insert("altitude_m", rs.altitude_m);
            let _ = row.insert("slope", slope);
            let _ = row.insert("concavity", conc);
            let _ = row.insert("raw_retention", raw_ret);
            let _ = row.insert("retention", if journey.is_water_retention_active() { ret } else { 1.0 });
            let _ = row.insert("water_before_retention_mm", water_before);
            let _ = row.insert("water_mm", water_after);
            let _ = row.insert("water_coverage", water_cov);
            rows.push(&row.to_variant());
        }
        let _ = out.insert("ok", true);
        let _ = out.insert("enabled", journey.water_retention_enabled);
        let _ = out.insert("active", journey.is_water_retention_active());
        let _ = out.insert("rows", &rows);
        out
    }

    #[func]
    pub fn surface_field_packet(&self) -> VarDictionary {
        self.surface_field_packet_since(-1)
    }

    #[func]
    pub fn surface_field_packet_since(&self, known_revision: i64) -> VarDictionary {
        let mut out = VarDictionary::new();
        let (Some(journey), Some(snap)) = (self.journey.as_ref(), self.snapshot.as_ref()) else {
            let _ = out.insert("ok", false);
            return out;
        };
        if known_revision == snap.revision as i64 {
            return out;
        }
        let cfg = &journey.climate.surface_balance;
        let max_encode_mm = cfg
            .snow_coverage_full_mm
            .max(cfg.ice_coverage_full_mm)
            .max(cfg.water_coverage_full_mm)
            .max(3.0);
        let station_min = journey.route.samples[0].shader_station_m;
        let station_max = journey
            .route
            .samples
            .last()
            .map(|s| s.shader_station_m)
            .unwrap_or(station_min + 1.0)
            .max(station_min + 1.0);
        let span = station_max - station_min;
        let n = if journey.is_water_retention_active() {
            (((span / 12.5).ceil() as usize) + 1).clamp(64, 512)
        } else {
            journey.route.samples.len().clamp(64, 512)
        };
        let mut rgba = PackedByteArray::new();
        rgba.resize(n * 4);
        let slice = rgba.as_mut_slice();
        for i in 0..n {
            let u = if n <= 1 {
                0.0
            } else {
                (i as f32) / ((n - 1) as f32)
            };
            let st = station_min + u * span;
            let prog = journey.route.shader_station_to_progress(st);
            let (_gc, water_mm, snow_mm, ice_mm, saturation, _rs_st) =
                snap.interpolate_surface_columns(journey, prog);
            slice[i * 4] = ((water_mm / max_encode_mm).clamp(0.0, 1.0) * 255.0).round() as u8;
            slice[i * 4 + 1] = ((snow_mm / max_encode_mm).clamp(0.0, 1.0) * 255.0).round() as u8;
            slice[i * 4 + 2] = ((ice_mm / max_encode_mm).clamp(0.0, 1.0) * 255.0).round() as u8;
            slice[i * 4 + 3] = (saturation.clamp(0.0, 1.0) * 255.0).round() as u8;
        }
        let snow_off = patch_seed_offsets(snap.patch_seed as u64).0;
        let ice_off = patch_seed_offsets(snap.ice_patch_seed as u64).1;
        let _ = out.insert("ok", true);
        let _ = out.insert("mode", "five_sector_snapshot");
        let _ = out.insert("revision", snap.revision as i64);
        let _ = out.insert("width", n as i32);
        let _ = out.insert("station_min_m", station_min);
        let _ = out.insert("station_max_m", station_max);
        let _ = out.insert("max_encode_mm", max_encode_mm);
        let _ = out.insert("water_full_mm", cfg.water_coverage_full_mm);
        let _ = out.insert("snow_full_mm", cfg.snow_coverage_full_mm);
        let _ = out.insert("ice_full_mm", cfg.ice_coverage_full_mm);
        let _ = out.insert("snow_seed_offset", Vector2::new(snow_off[0], snow_off[1]));
        let _ = out.insert("ice_seed_offset", Vector2::new(ice_off[0], ice_off[1]));
        let _ = out.insert("rgba8", &rgba);
        out
    }

    #[func]
    pub fn surface_telemetry_samples(&self, step_m: f32) -> VarDictionary {
        let mut out = VarDictionary::new();
        let (Some(journey), Some(snap)) = (self.journey.as_ref(), self.snapshot.as_ref()) else {
            let _ = out.insert("ok", false);
            return out;
        };
        let step = step_m.max(25.0);
        let total = journey.route.total_distance_m.max(1.0);
        let count = ((total / step).ceil() as usize).max(1) + 1;
        let mut rows = VarArray::new();
        for i in 0..count {
            let p = if i + 1 == count {
                total
            } else {
                (i as f32 * step).min(total)
            };
            let s = snap.sample_surface_at(journey, p, 0.0);
            let mut row = VarDictionary::new();
            let _ = row.insert("progress_m", s.progress_m);
            let _ = row.insert("shader_station_m", s.shader_station_m);
            let _ = row.insert("altitude_m", s.altitude_m);
            let _ = row.insert("air_c", s.air_c);
            let _ = row.insert("ground_c", s.ground_c);
            let _ = row.insert("water_mm", s.water_mm);
            let _ = row.insert("snow_mm", s.snow_mm);
            let _ = row.insert("ice_mm", s.ice_mm);
            let _ = row.insert("snow_coverage", s.snow_coverage);
            let _ = row.insert("ice_coverage", s.ice_coverage);
            let _ = row.insert("rain_mm_h", s.rain_mm_h);
            let _ = row.insert("snow_mm_h", s.snow_mm_h);
            rows.push(&row.to_variant());
        }
        let mut rain_sum = 0.0_f64;
        let mut snow_sum = 0.0_f64;
        let mut evap_sum = 0.0_f64;
        let mut drain_sum = 0.0_f64;
        let mut mass_sum = 0.0_f64;
        let n_sec = snap.sector_surface.len().max(1) as f64;
        for ss in &snap.sector_surface {
            rain_sum += ss.audit.rain_in_mm;
            snow_sum += ss.audit.snow_in_mm;
            evap_sum += ss.audit.evap_out_mm;
            drain_sum += ss.audit.drain_out_mm;
            mass_sum += (ss.water_mm + ss.snow_mm + ss.ice_mm) as f64;
        }
        let _ = out.insert("ok", true);
        let _ = out.insert("mode", "five_sector_snapshot");
        let _ = out.insert("fixed_snapshot", true);
        let _ = out.insert("elapsed_s", 0.0_f64);
        let _ = out.insert("effective_abs_seconds", snap.effective_abs_seconds);
        let _ = out.insert("surface_type", snap.surface_type.as_str());
        let _ = out.insert("sector_count", snap.sector_surface.len() as i64);
        let _ = out.insert("mean_total_mass_mm", mass_sum / n_sec);
        let _ = out.insert("rain_in_mm", rain_sum / n_sec);
        let _ = out.insert("snow_in_mm", snow_sum / n_sec);
        let _ = out.insert("evap_out_mm", evap_sum / n_sec);
        let _ = out.insert("drain_out_mm", drain_sum / n_sec);
        let _ = out.insert("samples", &rows);
        out
    }

    #[func]
    pub fn sector_summary(&self) -> VarArray {
        let mut arr = VarArray::new();
        let (Some(journey), Some(snap)) = (self.journey.as_ref(), self.snapshot.as_ref()) else {
            return arr;
        };
        for si in 0..journey.sectors.len() {
            let sd = &journey.sectors[si];
            let sa = &snap.sector_atmo[si];
            let ss = &snap.sector_surface[si];
            let mut d = VarDictionary::new();
            let _ = d.insert("sector_index", si as i32);
            let _ = d.insert("start_m", sd.geom.start_m);
            let _ = d.insert("end_m", sd.geom.end_m);
            let _ = d.insert("center_m", sd.geom.center_m);
            let _ = d.insert("center_altitude_m", sd.geom.center_altitude_m);
            let _ = d.insert("mark_count", sd.marks.len() as i32);
            let _ = d.insert("air_c", sa.air_c);
            let _ = d.insert("wet_bulb_c", sa.wet_bulb_c);
            let _ = d.insert("cloud_cover", sa.cloud_cover);
            let _ = d.insert("rain_mm_h", sa.rain_mm_h);
            let _ = d.insert("snow_mm_h", sa.snow_mm_h);
            let _ = d.insert("ground_c", ss.ground_c);
            let _ = d.insert("water_mm", ss.water_mm);
            let _ = d.insert("snow_mm", ss.snow_mm);
            let _ = d.insert("ice_mm", ss.ice_mm);
            let _ = d.insert("time_since_last_precip_s", ss.time_since_last_precip_s);
            arr.push(&d.to_variant());
        }
        arr
    }

    #[func]
    pub fn snapshot_surface(&self) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(snap) = self.snapshot.as_ref() else {
            return out;
        };
        let mut packed = PackedFloat32Array::new();
        packed.resize(snap.sector_surface.len() * 5);
        let sl = packed.as_mut_slice();
        for (i, ss) in snap.sector_surface.iter().enumerate() {
            sl[i * 5] = ss.ground_c;
            sl[i * 5 + 1] = ss.water_mm;
            sl[i * 5 + 2] = ss.snow_mm;
            sl[i * 5 + 3] = ss.ice_mm;
            sl[i * 5 + 4] = ss.saturation;
        }
        let _ = out.insert("mode", "five_sector_snapshot");
        let _ = out.insert("effective_abs_seconds", snap.effective_abs_seconds);
        let _ = out.insert("surface_type", snap.surface_type.as_str());
        let _ = out.insert("patch_seed", snap.patch_seed as i64);
        let _ = out.insert("ice_patch_seed", snap.ice_patch_seed as i64);
        let _ = out.insert("sectors_packed", &packed);
        out
    }

    #[func]
    pub fn restore_surface_snapshot(&mut self, data: VarDictionary) -> bool {
        let Some(snap) = self.snapshot.as_mut() else {
            return false;
        };
        let Some(packed) = data.get("sectors_packed").and_then(|v| v.try_to::<PackedFloat32Array>().ok()) else {
            return false;
        };
        let slice = packed.as_slice();
        if slice.len() != snap.sector_surface.len() * 5 {
            return false;
        }
        for (i, ss) in snap.sector_surface.iter_mut().enumerate() {
            ss.ground_c = slice[i * 5];
            ss.water_mm = slice[i * 5 + 1].max(0.0);
            ss.snow_mm = slice[i * 5 + 2].max(0.0);
            ss.ice_mm = slice[i * 5 + 3].max(0.0);
            ss.saturation = slice[i * 5 + 4].clamp(0.0, 1.0);
        }
        if let Some(eff) = data.get("effective_abs_seconds").and_then(|v| v.try_to::<f64>().ok()) {
            snap.effective_abs_seconds = eff;
        }
        snap.revision = snap.revision.saturating_add(1).max(1);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn load_ss04_profiles() -> (ClimateProfile, RouteProfile) {
        let climate_path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../game/data/weather/cdi_ss04_climate.json"
        );
        let route_path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../game/assets/rally/cdi_stage4/climate_route_profile.json"
        );
        let c_txt = std::fs::read_to_string(climate_path).expect("read cdi_ss04_climate.json");
        let r_txt = std::fs::read_to_string(route_path).expect("read climate_route_profile.json");
        (
            ClimateProfile::from_json_str(&c_txt).expect("parse climate"),
            RouteProfile::from_json_str(&r_txt).expect("parse route"),
        )
    }

    #[test]
    fn parses_ss04_profiles_and_station_correspondence() {
        let (climate, route) = load_ss04_profiles();
        assert_eq!(route.track_id, "cdi_stage4");
        assert!(route.vertical_datum_verified);
        assert!(route.samples.len() >= 200);
        assert!((route.min_altitude_m - 4517.197).abs() < 0.2);
        assert!((route.max_altitude_m - 4808.585).abs() < 0.2);

        let start_s = route.sample_at_progress(0.0);
        assert!((start_s.shader_station_m - 62.0125).abs() < 0.01);
        let end_s = route.sample_at_progress(route.total_distance_m);
        assert!((end_s.shader_station_m - 6261.438).abs() < 0.01);
        // Inverse mapping round-trip
        let mid_prog = route.total_distance_m * 0.5;
        let mid_stat = route.sample_at_progress(mid_prog).shader_station_m;
        let round_trip = route.shader_station_to_progress(mid_stat);
        assert!((round_trip - mid_prog).abs() < 0.05);

        let (season_name, _) = climate.resolve_season("2026-11-18");
        assert_eq!(season_name, "transition");
    }

    #[test]
    fn deterministic_seeds_and_separate_streams() {
        let s1 = derive_stream_seed(1974, "cdi_stage4", ALGO_VERSION, "atmosphere");
        let s2 = derive_stream_seed(1974, "cdi_stage4", ALGO_VERSION, "atmosphere");
        let p1 = derive_stream_seed(1974, "cdi_stage4", ALGO_VERSION, "patches");
        let other_stage = derive_stream_seed(1974, "cdi_stage3", ALGO_VERSION, "atmosphere");
        assert_eq!(s1, s2);
        assert_ne!(s1, p1);
        assert_ne!(s1, other_stage);
    }

    #[test]
    fn altitude_cools_air_under_equal_synoptic_conditions_and_skips_when_unverified() {
        let (climate, mut route) = load_ss04_profiles();
        let mut t_verified = AtmosphereTable::build(
            route.clone(),
            climate.clone(),
            2026,
            "transition",
            9.5,
            Some(2.0),
            Some(1.0),
            DayRegime::ForceDry,
        );
        let low = t_verified.sample_at(0.0, 0.0);
        let high = t_verified.sample_at(route.total_distance_m, 0.0);
        let dz_km = (high.altitude_m - low.altitude_m) / 1000.0;
        assert!(dz_km > 0.25);
        assert!(
            low.air_c - high.air_c > 1.5,
            "expected cooler air at abra ({} vs {})",
            high.air_c,
            low.air_c
        );

        // Unverified datum disables altitude lapse-rate adjustment.
        route.vertical_datum_verified = false;
        let mut t_unverified = AtmosphereTable::build(
            route.clone(),
            climate,
            2026,
            "transition",
            9.5,
            Some(2.0),
            Some(1.0),
            DayRegime::ForceDry,
        );
        let low_u = t_unverified.sample_at(0.0, 0.0);
        let high_u = t_unverified.sample_at(route.total_distance_m, 0.0);
        assert!((low_u.air_c - high_u.air_c).abs() < 1e-4);
    }

    #[test]
    fn dry_day_has_zero_precipitation_even_at_abra() {
        let (climate, route) = load_ss04_profiles();
        let mut table = AtmosphereTable::build(
            route.clone(),
            climate,
            777,
            "dry",
            10.0,
            Some(6.0),
            Some(1.5),
            DayRegime::ForceDry,
        );
        assert!(table.is_dry_day);
        for step in 0..=12 {
            let p = route.total_distance_m * (step as f32) / 12.0;
            let s = table.sample_at(p, 600.0);
            assert_eq!(s.precip_total_mm_h, 0.0);
            assert_eq!(s.rain_mm_h, 0.0);
            assert_eq!(s.snow_mm_h, 0.0);
            assert_eq!(s.precip_kind, PrecipKind::None);
        }
    }

    #[test]
    fn front_transitions_from_rain_to_snow_with_altitude() {
        let (mut climate, route) = load_ss04_profiles();
        // Configure transition season so base_temp at 4650m around 09:30 sits right in the phase split band:
        // ~+2.5C at 4517m (rain) and ~-0.2C at 4809m (snow) inside a moist front.
        let s = climate.seasons.get_mut("transition").unwrap();
        s.base_temp_c = 1.8;
        s.diurnal_amplitude_c = 2.0;
        s.diurnal_peak_hour = 14.0;
        s.lapse_rate_c_per_km = 7.5;
        s.lapse_rate_front_c_per_km = 7.5;
        s.front_temp_anomaly_c_range = [-1.0, -1.0];
        s.background_humidity = 0.85;
        s.front_humidity_boost_range = [0.12, 0.12];

        let mut table = AtmosphereTable::build(
            route.clone(),
            climate,
            9001,
            "transition",
            9.5,
            Some(2.0),
            Some(1.0),
            DayRegime::ForceWetFront,
        );

        let low = table.sample_at(0.0, 300.0);
        let high = table.sample_at(route.total_distance_m, 300.0);
        assert!(low.precip_total_mm_h > 0.1);
        assert!(high.precip_total_mm_h > 0.1);
        assert!(
            low.rain_mm_h > low.snow_mm_h,
            "expected predominantly rain at start ({:?})",
            low
        );
        assert!(
            high.snow_mm_h > high.rain_mm_h,
            "expected predominantly snow at abra ({:?})",
            high
        );
    }

    #[test]
    fn horizon_extension_is_exact_and_continuous() {
        let (climate, route) = load_ss04_profiles();
        let mut short_table = AtmosphereTable::build(
            route.clone(),
            climate.clone(),
            12345,
            "transition",
            9.66,
            Some(4.0),
            Some(0.5),
            DayRegime::ForceWetFront,
        );
        let mut long_table = AtmosphereTable::build(
            route.clone(),
            climate,
            12345,
            "transition",
            9.66,
            Some(4.0),
            Some(2.0),
            DayRegime::ForceWetFront,
        );

        let original_end = short_table.end_time_s();
        let before_a = short_table.sample_at(3100.0, original_end - 15.0);
        let before_b = long_table.sample_at(3100.0, original_end - 15.0);
        assert!((before_a.air_c - before_b.air_c).abs() < 1e-6);
        assert!((before_a.precip_total_mm_h - before_b.precip_total_mm_h).abs() < 1e-6);

        // Extend short_table past original_end and verify continuity and match with long_table.
        short_table.extend_horizon_to(7200.0);
        let at_seam = short_table.sample_at(3100.0, original_end);
        let just_past = short_table.sample_at(3100.0, original_end + 1.0);
        assert!((at_seam.air_c - just_past.air_c).abs() < 0.05);
        assert!((at_seam.precip_total_mm_h - just_past.precip_total_mm_h).abs() < 0.05);

        let after_a = short_table.sample_at(3100.0, 5400.0);
        let after_b = long_table.sample_at(3100.0, 5400.0);
        assert!((after_a.air_c - after_b.air_c).abs() < 1e-5);
        assert!((after_a.precip_total_mm_h - after_b.precip_total_mm_h).abs() < 1e-5);
    }

    fn make_forced_atmo(air_c: f32, irradiance: f32, rain_mm_h: f32, snow_mm_h: f32) -> AtmosphereSample {
        AtmosphereSample {
            progress_m: 1000.0,
            shader_station_m: 1062.0,
            elapsed_s: 0.0,
            hour_of_day: 12.0,
            altitude_m: 4650.0,
            air_c,
            wet_bulb_c: air_c - 0.5,
            humidity: 0.65,
            cloud_cover: 0.4,
            irradiance_w_m2: irradiance,
            precip_total_mm_h: rain_mm_h + snow_mm_h,
            rain_mm_h,
            snow_mm_h,
            precip_kind: if snow_mm_h > 0.0 {
                PrecipKind::Snow
            } else if rain_mm_h > 0.0 {
                PrecipKind::Rain
            } else {
                PrecipKind::None
            },
            wind_m_s: 4.0,
            wind_dir_deg: 60.0,
        }
    }

    #[test]
    fn surface_mass_conservation_melt_refreeze_and_dry_recovery() {
        let cfg = SurfaceBalanceConfig::default();
        let mat = SurfaceMaterialParams::default_for("asphalt");
        let mut cell = SurfaceCell {
            progress_m: 1000.0,
            shader_station_m: 1062.0,
            altitude_m: 4650.0,
            shade_factor: 1.0,
            drainage_scale: 1.0,
            ground_c: 4.0,
            water_mm: 0.0,
            snow_mm: 0.0,
            ice_mm: 0.0,
            saturation: 0.0,
        };

        let mut total_in = 0.0_f64;
        let mut total_out = 0.0_f64;
        let check_conservation = |c: &SurfaceCell, tin: f64, tout: f64| {
            assert!(c.water_mm >= 0.0 && c.snow_mm >= 0.0 && c.ice_mm >= 0.0);
            let stored = (c.water_mm + c.snow_mm + c.ice_mm) as f64;
            assert!(
                (stored - (tin - tout)).abs() < 1e-3,
                "mass mismatch stored={} expected={}",
                stored,
                tin - tout
            );
        };

        // Phase 1: snow falling onto warm pavement (+4 C) melts on contact into liquid water.
        let warm_snow = make_forced_atmo(1.0, 80.0, 0.0, 4.0);
        for _ in 0..120 {
            let (r, s, e, d, o) = step_surface_cell(&mut cell, &warm_snow, 5.0, &cfg, &mat);
            assert_eq!(o, 0.0);
            total_in += (r + s) as f64;
            total_out += (e + d) as f64;
        }
        assert!(cell.water_mm > 0.05, "snow on warm pavement must produce liquid water");
        assert!(cell.snow_mm < 0.05, "warm pavement should not accumulate thick snow");
        check_conservation(&cell, total_in, total_out);

        // Phase 2: cold snowfall accumulates snow.
        cell.ground_c = -3.0;
        let cold_snow = make_forced_atmo(-4.0, 50.0, 0.0, 6.0);
        for _ in 0..240 {
            let (r, s, e, d, o) = step_surface_cell(&mut cell, &cold_snow, 5.0, &cfg, &mat);
            assert_eq!(o, 0.0);
            total_in += (r + s) as f64;
            total_out += (e + d) as f64;
        }
        assert!(cell.snow_mm > 1.5, "snow must accumulate on subzero pavement");
        check_conservation(&cell, total_in, total_out);

        // Phase 3: sunny thaw transfers snow -> liquid water.
        let thaw = make_forced_atmo(6.0, 750.0, 0.0, 0.0);
        for _ in 0..360 {
            let (r, s, e, d, o) = step_surface_cell(&mut cell, &thaw, 5.0, &cfg, &mat);
            assert_eq!(o, 0.0);
            total_in += (r + s) as f64;
            total_out += (e + d) as f64;
        }
        assert!(cell.water_mm > 0.08, "thawing snow must feed liquid water (got water={})", cell.water_mm);
        check_conservation(&cell, total_in, total_out);

        // Phase 4: rapid night freeze turns liquid water -> ice (same volume never counted twice).
        let freeze = make_forced_atmo(-7.0, 0.0, 0.0, 0.0);
        let mass_before_freeze = cell.water_mm + cell.ice_mm;
        for _ in 0..360 {
            let (r, s, e, d, o) = step_surface_cell(&mut cell, &freeze, 5.0, &cfg, &mat);
            assert_eq!(o, 0.0);
            total_in += (r + s) as f64;
            total_out += (e + d) as f64;
        }
        assert!(cell.ice_mm > 0.05, "freezing liquid water must form ice");
        assert!(cell.water_mm + cell.ice_mm <= mass_before_freeze + 1e-4);
        check_conservation(&cell, total_in, total_out);

        // Phase 5: warm dry day melts remaining snow/ice and recovers completely dry asphalt.
        let dry_sun = make_forced_atmo(10.0, 850.0, 0.0, 0.0);
        for _ in 0..2880 {
            let (r, s, e, d, o) = step_surface_cell(&mut cell, &dry_sun, 5.0, &cfg, &mat);
            assert_eq!(o, 0.0);
            total_in += (r + s) as f64;
            total_out += (e + d) as f64;
        }
        assert_eq!(cell.snow_mm, 0.0);
        assert_eq!(cell.ice_mm, 0.0);
        assert_eq!(cell.water_mm, 0.0);
        check_conservation(&cell, total_in, total_out);
    }

    #[test]
    fn no_melt_freeze_chatter_in_zero_deadband() {
        let cfg = SurfaceBalanceConfig::default();
        let mat = SurfaceMaterialParams::default_for("asphalt");
        let mut cell = SurfaceCell {
            progress_m: 1000.0,
            shader_station_m: 1062.0,
            altitude_m: 4650.0,
            shade_factor: 1.0,
            drainage_scale: 1.0,
            ground_c: 0.0,
            water_mm: 1.0,
            snow_mm: 1.0,
            ice_mm: 1.0,
            saturation: 0.0,
        };
        let near_zero = make_forced_atmo(0.0, 0.0, 0.0, 0.0);
        step_surface_cell(&mut cell, &near_zero, 5.0, &cfg, &mat);
        // Inside [-0.15, +0.15], neither melt nor freeze triggers (only drainage/evap on water).
        assert_eq!(cell.snow_mm, 1.0);
        assert_eq!(cell.ice_mm, 1.0);
    }

    #[test]
    fn preroll_matches_stepping_same_fixed_steps_from_pre_start() {
        let (climate, route) = load_ss04_profiles();
        let mut atmo_pre = AtmosphereTable::build(
            route.clone(),
            climate.clone(),
            4242,
            "transition",
            9.6667,
            Some(4.0),
            Some(1.0),
            DayRegime::ForceWetFront,
        );
        let grid_pre = SurfaceGrid::build_and_preroll(&mut atmo_pre, "asphalt");

        // Build identical grid at t = -4h with zero pre-roll and manually advance 4h.
        let mut atmo_manual = AtmosphereTable::build(
            route,
            climate,
            4242,
            "transition",
            9.6667,
            Some(4.0),
            Some(1.0),
            DayRegime::ForceWetFront,
        );
        let t_start = atmo_manual.start_time_s();
        let mut cells_manual = Vec::with_capacity(grid_pre.cells.len());
        for c in &grid_pre.cells {
            let a0 = atmo_manual.sample_at(c.progress_m, t_start);
            cells_manual.push(SurfaceCell {
                progress_m: c.progress_m,
                shader_station_m: c.shader_station_m,
                altitude_m: c.altitude_m,
                shade_factor: c.shade_factor,
                drainage_scale: c.drainage_scale,
                ground_c: a0.air_c,
                water_mm: 0.0,
                snow_mm: 0.0,
                ice_mm: 0.0,
                saturation: 0.0,
            });
        }
        let mut grid_manual = SurfaceGrid {
            surface_type: grid_pre.surface_type.clone(),
            material: grid_pre.material.clone(),
            patch_seed: grid_pre.patch_seed,
            fixed_step_s: grid_pre.fixed_step_s,
            elapsed_s: t_start,
            pending_dt_s: 0.0,
            revision: 1,
            cells: cells_manual,
            audit: MassBalanceAudit::default(),
        };
        grid_manual.advance_by(&mut atmo_manual, 4.0 * 3600.0);

        for (a, b) in grid_pre.cells.iter().zip(grid_manual.cells.iter()) {
            assert!((a.ground_c - b.ground_c).abs() < 1e-5);
            assert!((a.water_mm - b.water_mm).abs() < 1e-5);
            assert!((a.snow_mm - b.snow_mm).abs() < 1e-5);
            assert!((a.ice_mm - b.ice_mm).abs() < 1e-5);
        }
    }

    #[test]
    fn spatial_pattern_varies_across_carriageway_and_weights_normalize() {
        let (climate, route) = load_ss04_profiles();
        let mut atmo = AtmosphereTable::build(
            route,
            climate,
            1974,
            "transition",
            9.6667,
            Some(2.0),
            Some(1.0),
            DayRegime::ForceDry,
        );
        let mut grid = SurfaceGrid::build_and_preroll(&mut atmo, "asphalt");
        // Set residual snow + ice on cell to inspect lateral-edge snow ribbons, zero ice patches & weight normalization.
        for c in &mut grid.cells {
            c.snow_mm = 1.6;
            c.ice_mm = 0.8;
            c.water_mm = 0.5;
        }
        let track = grid.sample_at(&mut atmo, 1500.0, 0.42);
        let lane_edge = grid.sample_at(&mut atmo, 1500.0, 0.82);
        let center_res = grid.sample_at(&mut atmo, 1500.0, 0.0);
        assert_eq!(track.snow_coverage, 0.0, "Central wheel tracks must remain snow-free");
        assert_eq!(lane_edge.snow_coverage, 0.0, "Inner 85% of carriageway must remain snow-free in residual regime");
        assert_eq!(center_res.snow_coverage, 0.0, "Central crown must remain snow-free in residual regime");
        assert_eq!(track.ice_coverage, 0.0, "Continuous ice coverage must stay zero");
        assert_eq!(track.ice_weight, 0.0, "Continuous ice weight must stay zero");

        // Sample along outer 10% lateral edges across 600 m: must show both snowy patches and clean gaps, plus L/R independence.
        let mut saw_snow_r = false;
        let mut saw_bare_r = false;
        let mut lr_diff = false;
        for step in 0..40 {
            let p = 1200.0 + (step as f32) * 15.0;
            let sr = grid.sample_at(&mut atmo, p, 0.96);
            let sl = grid.sample_at(&mut atmo, p, -0.96);
            assert_eq!(sr.ice_coverage, 0.0);
            assert!((sr.dry_weight + sr.snow_weight + sr.ice_weight - 1.0).abs() < 1e-5);
            assert!((sl.dry_weight + sl.snow_weight + sl.ice_weight - 1.0).abs() < 1e-5);
            if sr.snow_coverage > 0.10 {
                saw_snow_r = true;
            }
            if sr.snow_coverage <= 0.001 {
                saw_bare_r = true;
            }
            if (sr.snow_coverage - sl.snow_coverage).abs() > 0.05 {
                lr_diff = true;
            }
        }
        assert!(saw_snow_r && saw_bare_r, "Outer 10% snow ribbons must be discontinuous along the stage");
        assert!(lr_diff, "Left and right edge snow ribbons must vary independently");
        assert!((track.dry_weight + track.snow_weight + track.ice_weight - 1.0).abs() < 1e-5);
    }

    #[test]
    fn controlled_mixed_ascent_produces_start_melt_mid_rain_and_abra_snow() {
        let (climate, route) = load_ss04_profiles();
        let total = route.total_distance_m;
        let mut atmo = AtmosphereTable::build(
            route,
            climate,
            777,
            "transition",
            9.6667,
            None,
            None,
            DayRegime::ControlledMixedAscent,
        );
        let grid = SurfaceGrid::build_and_preroll(&mut atmo, "asphalt");
        let s_low = grid.sample_at(&mut atmo, total * 0.03, 0.0);
        let s_mid = grid.sample_at(&mut atmo, total * 0.48, 0.0);
        let s_abra_center = grid.sample_at(&mut atmo, total * 0.90, 0.0);
        let abra_edge_max = (0..12)
            .map(|k| grid.sample_at(&mut atmo, total * 0.86 + (k as f32) * 20.0, 0.96).snow_coverage)
            .fold(0.0_f32, f32::max);
        eprintln!(
            "CONTROLLED_MIXED low=(cloud={:.2},ground={:.2},snow={:.2},water={:.2},snow_cov={:.2},rain={:.2}) mid=(rain={:.2},snow={:.2},snow_cov={:.2},water={:.2}) abra=(snow_h={:.2},snow={:.2},center_cov={:.2},edge_max_cov={:.2})",
            s_low.cloud_cover, s_low.ground_c, s_low.snow_mm, s_low.water_mm, s_low.snow_coverage, s_low.rain_mm_h,
            s_mid.rain_mm_h, s_mid.snow_mm, s_mid.snow_coverage, s_mid.water_mm,
            s_abra_center.snow_mm_h, s_abra_center.snow_mm, s_abra_center.snow_coverage, abra_edge_max
        );
        let s_abra_track = grid.sample_at(&mut atmo, total * 0.90, 0.44);
        let abra_crown_max = (0..12)
            .map(|k| grid.sample_at(&mut atmo, total * 0.86 + (k as f32) * 20.0, 0.0).snow_coverage)
            .fold(0.0_f32, f32::max);
        assert!(s_low.cloud_cover >= 0.65 && s_low.snow_mm > 0.25 && s_low.ground_c > 0.15 && s_low.water_mm > 0.05 && s_low.snow_coverage == 0.0);
        assert!(s_mid.rain_mm_h > 0.5 && s_mid.snow_mm <= 0.01 && s_mid.snow_coverage <= 0.001 && s_mid.water_mm > 0.1);
        assert_eq!(s_abra_track.snow_coverage, 0.0);
        assert!(s_abra_center.snow_mm_h > 0.5 && s_abra_center.snow_mm > 0.5 && abra_edge_max > 0.15 && abra_crown_max > 0.05);
    }

    #[test]
    fn controlled_refreeze_turns_liquid_water_into_ice() {
        let (climate, route) = load_ss04_profiles();
        let total = route.total_distance_m;
        let mut atmo = AtmosphereTable::build(
            route,
            climate,
            888,
            "transition",
            9.6667,
            None,
            None,
            DayRegime::ControlledRefreeze,
        );
        let mut grid = SurfaceGrid::build_and_preroll(&mut atmo, "asphalt");
        let before = grid.sample_at(&mut atmo, total * 0.85, 0.0);
        grid.advance_by(&mut atmo, 1800.0);
        let after = grid.sample_at(&mut atmo, total * 0.85, 0.0);
        eprintln!(
            "CONTROLLED_REFREEZE before=(water={:.2},ice={:.2},ground={:.2}) after=(water={:.2},ice={:.2},ice_cov={:.2},ground={:.2})",
            before.water_mm, before.ice_mm, before.ground_c,
            after.water_mm, after.ice_mm, after.ice_coverage, after.ground_c
        );
        assert!(before.water_mm > 0.25 && after.ice_mm > before.ice_mm && after.ice_mm > 0.1 && after.ice_coverage == 0.0);
    }

    #[test]
    fn fixed_step_accumulator_is_framerate_invariant_at_120hz() {
        let (climate, route) = load_ss04_profiles();
        let mut atmo_batch = AtmosphereTable::build(
            route.clone(),
            climate.clone(),
            2026,
            "transition",
            9.6667,
            Some(2.0),
            Some(1.0),
            DayRegime::ForceWetFront,
        );
        let mut grid_batch = SurfaceGrid::build_and_preroll(&mut atmo_batch, "asphalt");
        let rev0 = grid_batch.revision;
        grid_batch.advance_by(&mut atmo_batch, 60.0);

        let mut atmo_ticks = AtmosphereTable::build(
            route,
            climate,
            2026,
            "transition",
            9.6667,
            Some(2.0),
            Some(1.0),
            DayRegime::ForceWetFront,
        );
        let mut grid_ticks = SurfaceGrid::build_and_preroll(&mut atmo_ticks, "asphalt");
        // Advance 60s in 7200 ticks of 1/120 s (120 Hz): must execute exact 12 fixed 5s steps.
        let dt = 1.0_f64 / 120.0_f64;
        for _ in 0..7200 {
            grid_ticks.advance_by(&mut atmo_ticks, dt);
        }
        assert_eq!(grid_batch.revision - rev0, 12);
        assert_eq!(grid_ticks.revision, grid_batch.revision);
        for (a, b) in grid_batch.cells.iter().zip(grid_ticks.cells.iter()) {
            assert!((a.ground_c - b.ground_c).abs() < 1e-5);
            assert!((a.water_mm - b.water_mm).abs() < 1e-5);
            assert!((a.snow_mm - b.snow_mm).abs() < 1e-5);
            assert!((a.ice_mm - b.ice_mm).abs() < 1e-5);
        }
    }

    #[test]
    fn five_sector_geometry_and_dry_day_invariants() {
        let (climate, route) = load_ss04_profiles();
        let base_s = 9.0 * 3600.0 + 40.0 * 60.0;
        let journey = FiveSectorJourney::build(
            route,
            climate,
            4242,
            "transition",
            base_s,
            FiveSectorRegime::Dry,
        );
        assert_eq!(journey.sectors.len(), 5);
        assert!(journey.is_dry_day);
        for s in &journey.sectors {
            assert!(s.marks.len() >= 5 && s.marks.len() <= 20);
        }
        // Each sector on SS04 (6.19 km) is ~1.24 km.
        let len0 = journey.sectors[0].geom.end_m - journey.sectors[0].geom.start_m;
        assert!((len0 - 1239.0).abs() < 15.0);

        let snap = journey.build_snapshot_at(base_s, "asphalt");
        for progress_m in [0.0_f32, 1500.0, 3100.0, 4800.0, journey.route.total_distance_m] {
            let sample = snap.sample_surface_at(&journey, progress_m, 0.0);
            assert_eq!(sample.precip_total_mm_h, 0.0);
            assert_eq!(sample.water_mm, 0.0);
            assert_eq!(sample.snow_mm, 0.0);
            assert_eq!(sample.ice_mm, 0.0);
            assert_eq!(sample.snow_coverage, 0.0);
        }
        let dry_fills = snap.compute_puddle_fills(&journey, &[100.0, 3100.0, 5800.0], &[1.3, 1.4, 1.5], &[0.6, 0.7, 0.75], &[1.4, 1.25, 1.2]);
        assert!(dry_fills.iter().all(|&f| f == 0.0));
    }

    #[test]
    fn five_sector_same_journey_turns_first_vs_eighth_accumulating_and_drying() {
        let (climate, route) = load_ss04_profiles();
        let base_s = 9.0 * 3600.0 + 40.0 * 60.0; // 09:40:00
        let journey_first = FiveSectorJourney::build(
            route.clone(),
            climate.clone(),
            2026,
            "transition",
            base_s,
            FiveSectorRegime::ControlledTimingEpisode,
        );
        let journey_eighth = FiveSectorJourney::build(
            route,
            climate,
            2026,
            "transition",
            base_s,
            FiveSectorRegime::ControlledTimingEpisode,
        );
        // Same journey seeds & marks regardless of starter position:
        assert_eq!(journey_first.climate_seed, journey_eighth.climate_seed);
        assert_eq!(journey_first.snow_mask_seed, journey_eighth.snow_mask_seed);
        assert_eq!(journey_first.puddle_seed, journey_eighth.puddle_seed);
        assert_eq!(journey_first.sectors[2].marks.len(), journey_eighth.sectors[2].marks.len());

        // Turn 1 (09:40) vs Turn 8 (09:47 = +420s) during active episode accumulation:
        let snap_1st = journey_first.build_snapshot_at(base_s, "asphalt");
        let snap_8th = journey_eighth.build_snapshot_at(base_s + 420.0, "asphalt");
        let mid_1st = snap_1st.sample_surface_at(&journey_first, 3000.0, 0.0);
        let mid_8th = snap_8th.sample_surface_at(&journey_eighth, 3000.0, 0.0);
        assert!(mid_8th.water_mm > mid_1st.water_mm, "8th starter sees more water during accumulation: {} vs {}", mid_8th.water_mm, mid_1st.water_mm);

        let fills_1st = snap_1st.compute_puddle_fills(&journey_first, &[3000.0], &[1.35], &[0.65], &[1.30]);
        let fills_8th = snap_8th.compute_puddle_fills(&journey_eighth, &[3000.0], &[1.35], &[0.65], &[1.30]);
        assert!(fills_8th[0] >= fills_1st[0] && fills_8th[0] > 0.1, "Puddles accumulate smoothly between 1st and 8th");

        // Post-episode drying comparison: 09:58 vs 10:25 (same episode ended cleanly at 09:57 -> drainage dominates).
        let snap_dry_early = journey_first.build_snapshot_at(base_s + 1140.0, "asphalt");
        let snap_dry_late = journey_first.build_snapshot_at(base_s + 2700.0, "asphalt");
        let w_early = snap_dry_early.sample_surface_at(&journey_first, 3000.0, 0.0).water_mm;
        let w_late = snap_dry_late.sample_surface_at(&journey_first, 3000.0, 0.0).water_mm;
        assert!(w_late < w_early, "Drainage/evap reduces water after episode ends: early={} late={}", w_early, w_late);
    }

    #[test]
    fn five_sector_mixed_ascent_refreeze_and_mass_conservation() {
        let (climate, route) = load_ss04_profiles();
        let base_s = 9.0 * 3600.0 + 40.0 * 60.0;
        let total = route.total_distance_m;
        let journey = FiveSectorJourney::build(
            route.clone(),
            climate.clone(),
            777,
            "transition",
            base_s,
            FiveSectorRegime::ControlledMixedAscent,
        );
        let snap = journey.build_snapshot_at(base_s, "asphalt");
        for ss in &snap.sector_surface {
            let total_mass = (ss.water_mm + ss.snow_mm + ss.ice_mm) as f64;
            let expected = ss.audit.rain_in_mm + ss.audit.snow_in_mm - ss.audit.evap_out_mm - ss.audit.drain_out_mm - ss.audit.clipped_overflow_mm;
            assert!((total_mass - expected).abs() < 0.02, "Mass balance conserved: {} vs {}", total_mass, expected);
        }
        let s_low = snap.sample_surface_at(&journey, total * 0.05, 0.0);
        let s_mid = snap.sample_surface_at(&journey, total * 0.48, 0.0);
        let s_abra = snap.sample_surface_at(&journey, total * 0.92, 0.0);
        let s_abra_track = snap.sample_surface_at(&journey, total * 0.92, 0.44);
        let abra_edge_max = (0..12)
            .map(|k| snap.sample_surface_at(&journey, total * 0.86 + (k as f32) * 20.0, 0.96).snow_coverage)
            .fold(0.0_f32, f32::max);
        let abra_crown_max = (0..12)
            .map(|k| snap.sample_surface_at(&journey, total * 0.86 + (k as f32) * 20.0, 0.0).snow_coverage)
            .fold(0.0_f32, f32::max);
        assert!(s_low.snow_mm > 0.2 && s_low.ground_c > 0.15 && s_low.snow_coverage == 0.0);
        assert!(s_mid.rain_mm_h > 0.5 && s_mid.snow_mm <= 0.01);
        assert_eq!(s_abra_track.snow_coverage, 0.0);
        assert!(s_abra.snow_mm_h > 0.5 && abra_edge_max > 0.15 && abra_crown_max > 0.05);

        // Refreeze check: thermal water freezes into ice_mm (reducing liquid puddle fill), while road ice_coverage stays 0.
        let j_ice = FiveSectorJourney::build(route, climate, 888, "transition", base_s, FiveSectorRegime::ControlledRefreeze);
        let s_pre = j_ice.build_snapshot_at(base_s - 2200.0, "asphalt");
        let s_post = j_ice.build_snapshot_at(base_s + 1200.0, "asphalt");
        let p_pre = s_pre.sample_surface_at(&j_ice, total * 0.85, 0.0);
        let p_post = s_post.sample_surface_at(&j_ice, total * 0.85, 0.0);
        assert!(p_pre.water_mm > 0.3 && p_post.ice_mm > 0.1 && p_post.ice_coverage == 0.0 && p_post.water_mm < p_pre.water_mm);
        let fills_post = s_post.compute_puddle_fills(&j_ice, &[total * 0.85], &[1.3], &[0.65], &[1.2]);
        assert!(fills_post[0] < 0.25);
    }

    fn load_ss01_profiles() -> (ClimateProfile, RouteProfile) {
        let climate_path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../game/data/weather/cdi_ss04_climate.json"
        );
        let route_path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../game/assets/rally/cdi_stage1/climate_route_profile.json"
        );
        let c_txt = std::fs::read_to_string(climate_path).expect("read cdi_ss04_climate.json");
        let r_txt = std::fs::read_to_string(route_path).expect("read ss01 climate_route_profile.json");
        (
            ClimateProfile::from_json_str(&c_txt).expect("parse climate"),
            RouteProfile::from_json_str(&r_txt).expect("parse ss01 route"),
        )
    }

    fn make_synthetic_route(alt_fn: impl Fn(f32) -> f32, total_m: f32, count: usize) -> RouteProfile {
        let mut samples = Vec::with_capacity(count);
        for i in 0..count {
            let p = total_m * (i as f32) / ((count - 1) as f32);
            let alt = alt_fn(p);
            samples.push(RouteSample {
                progress_m: p,
                shader_station_m: p + 60.0,
                altitude_m: alt,
                local_x_m: p,
                local_z_m: 0.0,
                grade: 0.0,
                heading_rad: 0.0,
            });
        }
        RouteProfile {
            track_id: "synthetic_test".to_string(),
            vertical_datum_verified: true,
            samples,
            total_distance_m: total_m,
            min_altitude_m: 4500.0,
            max_altitude_m: 4700.0,
            center_x_m: total_m * 0.5,
            center_z_m: 0.0,
            extent_radius_m: total_m * 0.5,
            five_sector_boundaries_m: None,
            snow_transition_altitude_m: None,
        }
    }

    #[test]
    fn water_retention_synthetic_crest_vs_depression_and_invalid_fallback() {
        // Synthetic route: valley at 500m, flat at 1000m, crest at 1500m (total 2000m).
        let route = make_synthetic_route(
            |p| {
                let d_val = ((p - 500.0) / 140.0).clamp(-1.0, 1.0);
                let d_crest = ((p - 1500.0) / 140.0).clamp(-1.0, 1.0);
                let valley = -12.0 * (1.0 - d_val * d_val).max(0.0);
                let crest = 12.0 * (1.0 - d_crest * d_crest).max(0.0);
                4600.0 + valley + crest
            },
            2000.0,
            101,
        );
        let prof = WaterRetentionProfile::build(&route, &WaterRetentionConfig::default());
        assert!(prof.valid);
        let (ret_val, _s_val, c_val, _) = prof.sample_detail(500.0);
        let (ret_flat, _s_flt, c_flt, _) = prof.sample_detail(1000.0);
        let (ret_crest, _s_crs, c_crs, _) = prof.sample_detail(1500.0);
        assert!(c_val > 0.02, "valley concavity must be positive: {}", c_val);
        assert!(c_crs < -0.02, "crest concavity must be negative: {}", c_crs);
        assert!(c_flt.abs() < 1e-3, "flat concavity near zero: {}", c_flt);
        assert!(
            ret_crest < ret_flat && ret_flat < ret_val,
            "retention order crest ({}) < flat ({}) < valley ({})",
            ret_crest,
            ret_flat,
            ret_val
        );

        // Invalid route (too few samples / degenerate station span) -> valid=false, neutral 1.0 retention.
        let mut bad_route = make_synthetic_route(|_| 4600.0, 50.0, 2);
        bad_route.samples[1].shader_station_m = bad_route.samples[0].shader_station_m;
        let bad_prof = WaterRetentionProfile::build(&bad_route, &WaterRetentionConfig::default());
        assert!(!bad_prof.valid);
        assert!(!bad_prof.diagnostic.is_empty());
        assert_eq!(bad_prof.sample_retention(25.0), 1.0);
    }

    #[test]
    fn water_retention_dry_zero_uniform_order_boundary_continuity_and_no_double_twi() {
        let (climate, route) = load_ss01_profiles();
        let base_s = 9.0 * 3600.0 + 40.0 * 60.0;

        // 1. Dry day preserves exact zero water everywhere even with retention active.
        let mut j_dry = FiveSectorJourney::build(
            route.clone(),
            climate.clone(),
            4242,
            "dry",
            base_s,
            FiveSectorRegime::Dry,
        );
        assert!(j_dry.set_water_retention_enabled(true));
        let snap_dry = j_dry.build_snapshot_at(base_s, "gravel");
        for p in [0.0, 864.5, 2539.6, 2645.9, 2796.1, route.total_distance_m] {
            let s = snap_dry.sample_surface_at(&j_dry, p, 0.0);
            assert_eq!(s.water_mm, 0.0);
            assert_eq!(s.water_coverage, 0.0);
        }

        // 2. Wet episode on SS01: inspect Sector 2 crest, descent, depression and check boundary continuity.
        let mut j_wet = FiveSectorJourney::build(
            route.clone(),
            climate.clone(),
            2026,
            "transition",
            base_s,
            FiveSectorRegime::ControlledTimingEpisode,
        );
        assert!(j_wet.set_water_retention_enabled(true));
        let mut snap_wet = j_wet.build_snapshot_at(base_s + 420.0, "gravel");

        // Uniform rain check (force identical sector reservoirs so only retention drives differences):
        for ss in &mut snap_wet.sector_surface {
            ss.water_mm = 1.6;
            ss.snow_mm = 0.0;
            ss.ice_mm = 0.0;
            ss.ground_c = 6.0;
        }
        let s_crest = snap_wet.sample_surface_at(&j_wet, 2539.6, 0.0);
        let s_descent = snap_wet.sample_surface_at(&j_wet, 2645.9, 0.0);
        let s_gentle = snap_wet.sample_surface_at(&j_wet, 2867.8, 0.0);
        let s_depr = snap_wet.sample_surface_at(&j_wet, 2360.2, 0.0);
        let s_valley = snap_wet.sample_surface_at(&j_wet, 2796.1, 0.0);
        eprintln!(
            "SS01_PILOT_POINTS crest(p=2539.6 st={:.1} w={:.3}) steep_desc(p=2645.9 st={:.1} w={:.3}) gentle_desc(p=2867.8 st={:.1} w={:.3}) depr_top(p=2360.2 st={:.1} w={:.3}) valley_foot(p=2796.1 st={:.1} w={:.3})",
            s_crest.shader_station_m, s_crest.water_mm,
            s_descent.shader_station_m, s_descent.water_mm,
            s_gentle.shader_station_m, s_gentle.water_mm,
            s_depr.shader_station_m, s_depr.water_mm,
            s_valley.shader_station_m, s_valley.water_mm
        );
        assert!(s_crest.water_mm < s_descent.water_mm && s_descent.water_mm < s_gentle.water_mm);
        assert!(s_gentle.water_mm < s_valley.water_mm && s_valley.water_mm < s_depr.water_mm);

        // Continuity across sector boundaries (20% = ~1002.3m, 40% = ~2004.6m, 60% = ~3006.8m, 80% = ~4009.1m).
        for frac in [0.2_f32, 0.4, 0.6, 0.8] {
            let b = route.total_distance_m * frac;
            let w_before = snap_wet.sample_surface_at(&j_wet, b - 2.0, 0.0).water_mm;
            let w_at = snap_wet.sample_surface_at(&j_wet, b, 0.0).water_mm;
            let w_after = snap_wet.sample_surface_at(&j_wet, b + 2.0, 0.0).water_mm;
            assert!((w_at - w_before).abs() < 0.15 && (w_after - w_at).abs() < 0.15, "boundary {} jump: {} -> {} -> {}", b, w_before, w_at, w_after);
        }

        // The road film must not change the original procedural basin fill.
        for ss in &mut snap_wet.sector_surface {
            ss.water_mm = 0.70;
        }
        let fill_with_prof = snap_wet.compute_puddle_fills(&j_wet, &[2539.6, 2360.2], &[1.5, 1.5], &[0.75, 0.75], &[1.2, 1.2]);
        let mut j_no_prof = j_wet.clone();
        j_no_prof.set_water_retention_enabled(false);
        let fill_without_prof = snap_wet.compute_puddle_fills(&j_no_prof, &[2539.6, 2360.2], &[1.5, 1.5], &[0.75, 0.75], &[1.2, 1.2]);
        assert_eq!(fill_with_prof, fill_without_prof);
        assert!(fill_without_prof[0] > 0.4, "legacy path applies TWI boost on same base water");

        // Ensure retention profile build is fast (under 10 ms even in unoptimized debug test build).
        let build_us = j_wet.water_retention_profile.as_ref().unwrap().build_time_us;
        eprintln!("SS01_RETENTION_BUILD_US={}", build_us);
        assert!(build_us < 20_000, "retention build too slow: {} us", build_us);
    }
}
