class_name RallyPuddles
extends Node3D

## Stable route-seeded virtual depressions with smooth circular-biased organic contours,
## topographic wetness index (TWI), Poisson cluster generation, bimodal lateral distribution,
## conformal adaptive mesh, prefabricated PNG masks, physical hydrodynamic retarding drag and aquaplaning.
##
## Depth & liquid-feed contract:
## - `background_water(distance)` reads the single local liquid supply `water_mm`
##   (which already integrates rain + snow/ice melt - freezing - evaporation - drainage).
## - Reported `depth_mm` is the total basin water depth INCLUDING the base water film
##   filling the depression; downstream wheel fusion (`vehicle_simulation.gd`) takes
##   `max(base_water_mm, puddle_depth_mm)` so the base film is never added twice.
## - Water that has frozen into `ice_mm` does NOT contribute to liquid `fill`, ensuring
##   hydrodynamic puddle drag is never applied to frozen puddle ice.

const WATER_SHADER = preload("res://scripts/rally/rally_puddle.gdshader")
const WATER_DETAIL_TEX = preload("res://assets/rally/water/water_detail.jpg")

const MASK_RUT = preload("res://assets/vfx/puddles/puddle_rut.png")
const MASK_TWIN_RUT = preload("res://assets/vfx/puddles/puddle_twin_rut.png")
const MASK_GUTTER = preload("res://assets/vfx/puddles/puddle_gutter_wedge.png")
const MASK_KIDNEY = preload("res://assets/vfx/puddles/puddle_kidney_soft.png")
const MASK_POTHOLE = preload("res://assets/vfx/puddles/puddle_pothole.png")
const MASK_DOUBLE_SCAR = preload("res://assets/vfx/puddles/puddle_egg_asym.png")
const MASK_BASIN = preload("res://assets/vfx/puddles/puddle_basin.png")
const MASK_SHEET = preload("res://assets/vfx/puddles/puddle_sheet.png")
const MASK_CLOVER = preload("res://assets/vfx/puddles/puddle_lobe_triple.png")
const MASK_ROUND = preload("res://assets/vfx/puddles/puddle_round_organic.png")

## 12 rally puddle archetypes grouped across 4 families backed by 10 bathymetric PNG masks:
## - "rut"     : longitudinal wheel-track channels (asymmetric straight-line & braking pull)
## - "gutter"  : apex / shoulder / ditch traps ("Don't Cut" steep cutbank slams)
## - "pothole" : compact broken craters & washout hollows (high entry slam & avoidance)
## - "sheet"   : wide shallow aquaplaning blankets & rain glazes (sudden 4-wheel lateral loss)
const TYPES := [
	# --- Family 1: Longitudinal Wheel-Ruts ---
	{
		"id": "rut_streak_narrow",
		"family": "rut",
		"length": 4.90,
		"width": 1.60,
		"depth_mm": 11.0,
		"drag": 1.05,
		"min_water": 0.30,
		"retention": 1.18,
		"mask": MASK_RUT,
		"edge_softness": 0.14,
		"turbidity": 0.060,
		"align_to_road": true,
		"yaw_jitter": 0.16,
		"lat_min": 0.55,
		"lat_max": 1.45,
		"grid_res": 6,
	},
	{
		"id": "rut_trough_deep",
		"family": "rut",
		"length": 6.80,
		"width": 2.15,
		"depth_mm": 38.0,
		"drag": 1.45,
		"min_water": 0.25,
		"retention": 1.38,
		"mask": MASK_RUT,
		"edge_softness": 0.11,
		"turbidity": 0.075,
		"align_to_road": true,
		"yaw_jitter": 0.14,
		"lat_min": 0.55,
		"lat_max": 1.50,
		"grid_res": 7,
	},
	{
		"id": "twin_rut_split",
		"family": "rut",
		"length": 5.80,
		"width": 3.05,
		"depth_mm": 26.0,
		"drag": 1.25,
		"min_water": 0.28,
		"retention": 1.28,
		"mask": MASK_TWIN_RUT,
		"edge_softness": 0.15,
		"turbidity": 0.068,
		"align_to_road": true,
		"yaw_jitter": 0.12,
		"lat_min": 0.20,
		"lat_max": 0.90,
		"grid_res": 6,
	},
	# --- Family 2: Apex Gutters & Road Shoulders ("Don't Cut") ---
	{
		"id": "apex_gutter_trap",
		"family": "gutter",
		"length": 4.20,
		"width": 2.55,
		"depth_mm": 54.0,
		"drag": 1.65,
		"min_water": 0.22,
		"retention": 1.45,
		"mask": MASK_GUTTER,
		"edge_softness": 0.09,
		"turbidity": 0.085,
		"align_to_road": true,
		"yaw_jitter": 0.25,
		"orient_to_edge": true,
		"lat_min": 0.95,
		"lat_max": 1.90,
		"grid_res": 5,
	},
	{
		"id": "ditch_drain_channel",
		"family": "gutter",
		"length": 6.10,
		"width": 2.75,
		"depth_mm": 42.0,
		"drag": 1.50,
		"min_water": 0.24,
		"retention": 1.40,
		"mask": MASK_GUTTER,
		"edge_softness": 0.12,
		"turbidity": 0.078,
		"align_to_road": true,
		"yaw_jitter": 0.18,
		"orient_to_edge": true,
		"lat_min": 0.95,
		"lat_max": 1.95,
		"grid_res": 7,
	},
	{
		"id": "camber_crescent",
		"family": "gutter",
		"length": 4.90,
		"width": 3.05,
		"depth_mm": 30.0,
		"drag": 1.35,
		"min_water": 0.28,
		"retention": 1.28,
		"mask": MASK_KIDNEY,
		"edge_softness": 0.16,
		"turbidity": 0.068,
		"align_to_road": true,
		"yaw_jitter": 0.38,
		"orient_to_edge": true,
		"lat_min": 0.85,
		"lat_max": 1.85,
		"grid_res": 5,
	},
	# --- Family 3: Sharp Broken Potholes & Washouts ---
	{
		"id": "pothole_crater_sharp",
		"family": "pothole",
		"length": 2.65,
		"width": 2.60,
		"depth_mm": 62.0,
		"drag": 1.75,
		"min_water": 0.22,
		"retention": 1.52,
		"mask": MASK_POTHOLE,
		"edge_softness": 0.08,
		"turbidity": 0.092,
		"align_to_road": false,
		"lat_min": 0.40,
		"lat_max": 1.75,
		"grid_res": 5,
	},
	{
		"id": "pothole_double_scar",
		"family": "pothole",
		"length": 3.85,
		"width": 2.95,
		"depth_mm": 48.0,
		"drag": 1.55,
		"min_water": 0.26,
		"retention": 1.38,
		"mask": MASK_DOUBLE_SCAR,
		"edge_softness": 0.11,
		"turbidity": 0.082,
		"align_to_road": true,
		"yaw_jitter": 0.48,
		"lat_min": 0.45,
		"lat_max": 1.70,
		"grid_res": 5,
	},
	{
		"id": "washout_compression_basin",
		"family": "pothole",
		"length": 4.80,
		"width": 4.20,
		"depth_mm": 44.0,
		"drag": 1.45,
		"min_water": 0.28,
		"retention": 1.35,
		"mask": MASK_BASIN,
		"edge_softness": 0.14,
		"turbidity": 0.078,
		"align_to_road": false,
		"lat_min": 0.35,
		"lat_max": 1.55,
		"grid_res": 6,
	},
	# --- Family 4: Aquaplaning Sheets & Shallow Glazes ---
	{
		"id": "sheet_cross_flood",
		"family": "sheet",
		"length": 6.20,
		"width": 5.10,
		"depth_mm": 16.0,
		"drag": 0.95,
		"min_water": 0.34,
		"retention": 1.12,
		"mask": MASK_SHEET,
		"edge_softness": 0.22,
		"turbidity": 0.045,
		"align_to_road": true,
		"yaw_jitter": 0.45,
		"lat_min": 0.15,
		"lat_max": 1.10,
		"grid_res": 6,
	},
	{
		"id": "sprawl_multi_lobe",
		"family": "sheet",
		"length": 5.50,
		"width": 4.70,
		"depth_mm": 20.0,
		"drag": 1.12,
		"min_water": 0.32,
		"retention": 1.18,
		"mask": MASK_CLOVER,
		"edge_softness": 0.20,
		"turbidity": 0.055,
		"align_to_road": false,
		"lat_min": 0.35,
		"lat_max": 1.55,
		"grid_res": 6,
	},
	{
		"id": "skim_glaze_film",
		"family": "sheet",
		"length": 3.80,
		"width": 3.45,
		"depth_mm": 5.5,
		"drag": 0.75,
		"min_water": 0.42,
		"retention": 0.95,
		"mask": MASK_ROUND,
		"edge_softness": 0.24,
		"turbidity": 0.035,
		"align_to_road": false,
		"lat_min": 0.45,
		"lat_max": 1.75,
		"grid_res": 5,
	},
]

static var _mask_images: Dictionary = {}

var use_rust_backend: bool = true
var fixed_snapshot_mode: bool = false
var has_winter_patches: bool = false
var provider = null
var sky_node: Node
var wetness_node: Node
var route: Array[Vector3] = []
var stage_seed: int = 0
var patches: Array[Dictionary] = []
var buckets: Dictionary = {}
var elapsed := 0.0
var built := false
var _rust_field: RefCounted = null
var _rust_mask_ids: Dictionary = {}
var _rust_next_mask_id: int = 1
var _rust_fills: PackedFloat32Array = PackedFloat32Array()
var _cand_distances: PackedFloat32Array = PackedFloat32Array()
var _cand_twis: PackedFloat32Array = PackedFloat32Array()
var _cand_min_waters: PackedFloat32Array = PackedFloat32Array()
var _cand_retentions: PackedFloat32Array = PackedFloat32Array()
static var _rust_static_helper: RefCounted = null


static func get_mask_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var path := tex.resource_path
	if not _mask_images.has(path):
		_mask_images[path] = tex.get_image()
	return _mask_images[path]


func configure(points: Array[Vector3], seed_value: int, weather, wetness: Node) -> void:
	route = points.duplicate()
	stage_seed = seed_value
	provider = weather
	wetness_node = wetness


func _physics_process(delta: float) -> void:
	if not built:
		build()
	elapsed += delta
	if elapsed < 0.2:
		return
	elapsed = 0.0

	if fixed_snapshot_mode:
		_refresh_visible_reflections_only()
		return

	for patch in patches:
		var profile: Dictionary = patch.profile
		var local_state := _local_liquid_state(float(patch.distance))
		var water := float(local_state.get("water_mm", 0.0))
		var ice := float(local_state.get("ice_mm", 0.0))
		var min_w := float(profile.get("min_water", 0.75))

		# Zero puddles in dry conditions (liquid water below basin threshold).
		# Frozen water (`ice_mm`) is excluded from liquid fill so puddle drag never acts on ice.
		if water <= min_w:
			patch.fill = 0.0
		else:
			var ret := float(profile.get("retention", 1.0))
			var liquid_fraction := water / (water + ice) if ice > 0.001 else 1.0
			patch.fill = clampf((water - min_w) * ret / 3.0, 0.0, 1.0) * liquid_fraction

		var mesh := patch.mesh as MeshInstance3D
		var filled := float(patch.fill) > 0.005
		if mesh.visible != filled:
			mesh.visible = filled
		if not filled:
			continue
		var material: ShaderMaterial = patch.material
		material.set_shader_parameter("fill", patch.fill)

		if is_instance_valid(sky_node):
			_apply_sky_uniforms(material)

		var rain := float(local_state.get("rain_ratio", 0.0))
		var wind_vec: Vector2 = local_state.get("wind_vec", Vector2(1.2, 0.4)) as Vector2
		material.set_shader_parameter("rain", rain)
		material.set_shader_parameter("wind_vec", wind_vec)

	if _rust_field != null:
		var count: int = patches.size()
		if _rust_fills.size() != count:
			_rust_fills.resize(count)
		for pi in count:
			_rust_fills[pi] = float(patches[pi]["fill"])
		_rust_field.call("update_fills", _rust_fills)


func _local_liquid_state(distance: float) -> Dictionary:
	if provider != null and provider.calendar_active:
		var state: Dictionary = provider.local_surface_state_at_distance(distance) if provider.has_method("local_surface_state_at_distance") else provider.surface.blended_state_at_distance(distance)
		var climate: Dictionary = state.get("climate", {})
		var rain_mm_h := float(state.get("rain_mm_h", climate.get("rain_mm_h", -1.0)))
		if rain_mm_h < 0.0:
			var kind := str(state.get("precipitation_kind", "rain"))
			var total_p := float(climate.get("precipitation_mm_h", 0.0))
			rain_mm_h = total_p if kind == "rain" else (total_p * 0.6 if kind == "mixed" else 0.0)
		var wind_spd := float(state.get("wind_m_s", climate.get("wind_speed_m_s", climate.get("wind_m_s", 1.8))))
		var wind_deg := float(state.get("wind_direction_deg", climate.get("wind_dir_deg", 60.0)))
		var wind_rad := deg_to_rad(wind_deg)
		var wind_vec := Vector2(sin(wind_rad), cos(wind_rad)) * wind_spd
		return {
			"water_mm": maxf(float(state.get("water_mm", 0.0)), 0.0),
			"ice_mm": maxf(float(state.get("ice_mm", 0.0)), 0.0),
			"rain_ratio": clampf(rain_mm_h / 10.0, 0.0, 1.0),
			"wind_vec": wind_vec,
		}
	var w := float(wetness_node.wetness) * 4.0 if is_instance_valid(wetness_node) else 0.0
	var r := float(wetness_node.rain_intensity) if is_instance_valid(wetness_node) else 0.0
	var wspd := 1.0 + 4.5 * r if is_instance_valid(wetness_node) else 1.2
	return {
		"water_mm": maxf(w, 0.0),
		"ice_mm": 0.0,
		"rain_ratio": clampf(r, 0.0, 1.0),
		"wind_vec": Vector2(0.85, 0.52) * wspd,
	}


func background_water(distance: float) -> float:
	return float(_local_liquid_state(distance).get("water_mm", 0.0))


func road_hit(pos: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos - Vector3.UP * 4.0, 1)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider := hit.collider as Node
	if collider == null:
		return {}
	var has_meta_flag := bool(collider.get_meta("is_stage_road", false))
	var name_matches := collider.name.to_lower().begins_with("collision_road")
	if not has_meta_flag and not name_matches:
		return {}
	return hit


## Topographic Wetness Index (TWI) along the stage centerline:
## Computes slope, vertical concavity (valleys vs crests) and curve turn direction.
static func _compute_route_topography(route_pts: Array[Vector3], allow_rust: bool = true) -> Array[Dictionary]:
	var helper: RefCounted = _get_rust_static_helper() if allow_rust else null
	if helper != null:
		var flat: PackedFloat32Array = helper.call("compute_route_topography_packed", PackedVector3Array(route_pts))
		var count_r: int = flat.size() / 4
		var fast_res: Array[Dictionary] = []
		fast_res.resize(count_r)
		for ri in count_r:
			var base_i: int = ri * 4
			fast_res[ri] = {
				"slope": flat[base_i],
				"concavity": flat[base_i + 1],
				"turn_signed": flat[base_i + 2],
				"twi": flat[base_i + 3],
			}
		return fast_res

	var result: Array[Dictionary] = []
	var n := route_pts.size()
	if n == 0:
		return result
	if n < 3:
		for i in range(n):
			result.append({
				"slope": 0.0,
				"concavity": 0.0,
				"turn_signed": 0.0,
				"twi": 1.0,
			})
		return result

	var w := clampi(n / 90, 1, 4)
	for i in range(n):
		var i_prev := maxi(0, i - w)
		var i_next := mini(n - 1, i + w)
		var p_prev := route_pts[i_prev]
		var p_curr := route_pts[i]
		var p_next := route_pts[i_next]

		var v_prev := p_curr - p_prev
		var v_next := p_next - p_curr
		var d_prev_xz := maxf(Vector2(v_prev.x, v_prev.z).length(), 0.5)
		var d_next_xz := maxf(Vector2(v_next.x, v_next.z).length(), 0.5)

		var slope_prev := v_prev.y / d_prev_xz
		var slope_next := v_next.y / d_next_xz
		var slope := 0.5 * (slope_prev + slope_next)
		var concavity := slope_next - slope_prev

		var f_prev := Vector3(v_prev.x, 0.0, v_prev.z).normalized()
		var f_next := Vector3(v_next.x, 0.0, v_next.z).normalized()
		if f_prev.length_squared() < 0.1:
			f_prev = Vector3.FORWARD
		if f_next.length_squared() < 0.1:
			f_next = f_prev
		var right_prev := f_prev.cross(Vector3.UP).normalized()
		var turn_signed := f_next.dot(right_prev)

		# Steep longitudinal slopes drain fast (> 12% slope severely penalizes puddles)
		var slope_factor := clampf(1.0 - absf(slope) / 0.12, 0.0, 1.0)
		# Depressions / bottom of descents accumulate water
		var valley_boost := clampf(1.0 + concavity * 14.0, 0.0, 1.65)
		if concavity < -0.025:
			# Crest / hill summit drains water off
			valley_boost = 0.05

		var twi := clampf(slope_factor * valley_boost, 0.0, 1.5)
		result.append({
			"slope": slope,
			"concavity": concavity,
			"turn_signed": turn_signed,
			"twi": twi,
		})
	return result


## Builds an adaptive NxN conformal mesh projected onto the actual road collision surface.
## Vertices that overhang the road edge are clamped in height and receive COLOR.r = 0.0
## to let the shader fade the water edge smoothly without floating triangles.
func _build_conformal_puddle_mesh(
	center: Vector3,
	basis: Basis,
	size: Vector2,
	grid_res: int = 5
) -> Dictionary:
	var res := clampi(grid_res, 5, 8)
	var normal := basis.y.normalized()
	var total_samples := res * res
	var valid_hits := 0
	var local_heights: Array[float] = []
	local_heights.resize(total_samples)
	var edge_weights: Array[float] = []
	edge_weights.resize(total_samples)

	for gz in range(res):
		var v_ratio := float(gz) / float(res - 1)
		var z_local := (v_ratio - 0.5) * size.y
		for gx in range(res):
			var u_ratio := float(gx) / float(res - 1)
			var x_local := (u_ratio - 0.5) * size.x
			var idx := gz * res + gx

			var world_pt := center + basis.x * x_local + basis.z * z_local
			var hit := road_hit(world_pt)
			if not hit.is_empty():
				var h_diff := ((hit.position as Vector3) - center).dot(normal)
				if absf(h_diff) <= 0.22:
					local_heights[idx] = h_diff
					edge_weights[idx] = 1.0
					valid_hits += 1
				else:
					local_heights[idx] = clampf(h_diff, -0.08, 0.08)
					edge_weights[idx] = 0.0
			else:
				local_heights[idx] = 0.0
				edge_weights[idx] = 0.0

	# At least 48% of the puddle grid must rest on valid road collision
	if valid_hits < int(ceil(float(total_samples) * 0.48)):
		return {}

	# Smooth edge heights for vertices outside the road boundary using valid neighbors
	for pass_idx in range(2):
		for gz in range(res):
			for gx in range(res):
				var idx := gz * res + gx
				if edge_weights[idx] > 0.5:
					continue
				var sum_h := 0.0
				var count_h := 0.0
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var nx := gx + dx
						var nz := gz + dz
						if nx >= 0 and nx < res and nz >= 0 and nz < res:
							var n_idx := nz * res + nx
							if edge_weights[n_idx] > 0.5:
								sum_h += local_heights[n_idx]
								count_h += 1.0
				if count_h > 0.0:
					local_heights[idx] = sum_h / count_h

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gz in range(res):
		var v_norm := float(gz) / float(res - 1)
		var z_local := (v_norm - 0.5) * size.y
		for gx in range(res):
			var u_norm := float(gx) / float(res - 1)
			var x_local := (u_norm - 0.5) * size.x
			var idx := gz * res + gx
			var y_local: float = local_heights[idx]
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(u_norm, v_norm))
			st.set_color(Color(edge_weights[idx], 1.0, 1.0, 1.0))
			st.add_vertex(Vector3(x_local, y_local, z_local))

	for gz in range(res - 1):
		for gx in range(res - 1):
			var i00 := gz * res + gx
			var i10 := i00 + 1
			var i01 := (gz + 1) * res + gx
			var i11 := i01 + 1
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i01)
			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i01)

	st.generate_normals()
	return {
		"mesh": st.commit(),
		"valid_ratio": float(valid_hits) / float(total_samples),
	}


func _select_profile_index(
	rng: RandomNumberGenerator,
	slot_index: int,
	twi: float,
	abs_turn: float,
	last_profile_idx: int,
	family_counts: Dictionary
) -> int:
	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(TYPES.size())
	var total := 0.0
	var is_curve := abs_turn > 0.025
	var is_valley := twi >= 1.15
	var is_grade := twi < 0.85

	for idx in TYPES.size():
		var p: Dictionary = TYPES[idx]
		var fam: String = str(p.get("family", "pothole"))
		var depth_mm: float = float(p.get("depth_mm", 20.0))
		var w := 1.0

		# Primary puddles lean toward deeper/defining hazards (depth >= 15 mm);
		# satellites broaden variety toward smaller craters, narrow ruts and shallow glazes.
		if slot_index == 0:
			if depth_mm < 15.0:
				w = 0.0
			elif depth_mm >= 25.0 or str(p.get("id", "")) == "sheet_cross_flood":
				w *= 1.35
		else:
			if depth_mm <= 12.0:
				w *= 2.25
			elif depth_mm <= 22.0 or str(p.get("id", "")) == "pothole_crater_sharp":
				w *= 1.45
			elif float(p.get("length", 3.0)) >= 6.2:
				w *= 0.60

		# Topographic & geometric context (favor broader natural pools & basins over thin strips)
		if is_curve and fam == "gutter":
			w *= 1.75
		elif not is_curve and fam in ["sheet", "pothole"]:
			w *= 1.30
		elif not is_curve and fam == "rut":
			w *= 1.05

		if is_valley:
			if str(p.get("id", "")) in ["washout_compression_basin", "sheet_cross_flood", "sprawl_multi_lobe", "camber_crescent"]:
				w *= 1.85
		elif is_grade:
			if fam == "sheet":
				w *= 0.85
			elif str(p.get("id", "")) in ["pothole_crater_sharp", "pothole_double_scar", "skim_glaze_film"]:
				w *= 1.35

		# Anti-repetition: suppress back-to-back identical profiles & softly balance families
		if idx == last_profile_idx:
			w *= 0.12
		var f_count := int(family_counts.get(fam, 0))
		w /= (1.0 + float(f_count) * 0.18)

		weights[idx] = w
		total += w

	var pick := rng.randf() * total
	var acc := 0.0
	for idx in TYPES.size():
		acc += weights[idx]
		if pick <= acc:
			return idx
	return TYPES.size() - 1


func build() -> void:
	if built:
		return
	built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed

	var total_length := 0.0
	for i in range(1, route.size()):
		total_length += route[i - 1].distance_to(route[i])
	var is_short_test_route := total_length < 320.0

	var topo := _compute_route_topography(route, use_rust_backend)
	var distance := 0.0
	var next_cluster_dist := 14.0
	var cluster_id := 0
	var last_profile_idx := -1
	var family_counts: Dictionary = {"rut": 0, "gutter": 0, "pothole": 0, "sheet": 0}

	for i in range(1, route.size()):
		var seg := route[i] - route[i - 1]
		var seg_len := seg.length()
		if seg_len <= 0.01:
			continue

		while next_cluster_dist < distance + seg_len:
			var t := (next_cluster_dist - distance) / seg_len
			var seg_center := route[i - 1].lerp(route[i], t)
			var forward := seg.normalized()
			var right := forward.cross(Vector3.UP).normalized()
			if right.length_squared() < 0.01:
				right = Vector3.RIGHT

			var topo_idx := mini(i, topo.size() - 1)
			var node_topo: Dictionary = topo[topo_idx]
			var twi := float(node_topo.get("twi", 1.0))
			if twi < 0.18 and not is_short_test_route:
				next_cluster_dist += rng.randf_range(12.0, 20.0)
				continue

			var turn_signed := float(node_topo.get("turn_signed", 0.0))
			var preferred_side := -1.0 if rng.randf() < 0.5 else 1.0
			if absf(turn_signed) > 0.025:
				preferred_side = signf(turn_signed) if rng.randf() < 0.75 else -signf(turn_signed)

			var cluster_count := rng.randi_range(1, 5) if rng.randf() < 0.85 else 1
			var placed_centers: Array[Vector3] = []
			var placed_lons: Array[float] = []
			var placed_sides: Array[float] = []
			var cluster_mode := rng.randi_range(0, 2) # 0: longitudinal rut/gutter chain, 1: diagonal camber runoff, 2: main basin + satellites

			for k in range(cluster_count):
				var profile_idx := _select_profile_index(
					rng, k, twi, absf(turn_signed), last_profile_idx, family_counts
				)
				var profile: Dictionary = TYPES[profile_idx]
				var family: String = str(profile.get("family", "pothole"))

				# Pareto multi-scale size distribution: macro hazards, chained companions, and broader satellites
				var scale := 1.0
				if k == 0:
					scale = rng.randf_range(0.95, 1.56)
				elif k <= 2:
					scale = rng.randf_range(0.76, 1.28)
				else:
					scale = rng.randf_range(0.58, 0.94)

				var side := preferred_side
				var lon_offset := 0.0
				if k > 0:
					if cluster_mode == 0:
						# Longitudinal chain along the same wheel track or ditch (occasional staggered cross-track)
						side = preferred_side if rng.randf() < 0.76 else -preferred_side
						var dir_sign := 1.0 if (k % 2 == 1) else -1.0
						lon_offset = dir_sign * rng.randf_range(4.2 + float(k) * 1.8, 10.5 + float(k) * 3.0)
					elif cluster_mode == 1:
						# Diagonal camber drainage sequence (upstream shoulder/gutter feeding offset lane pool)
						side = -preferred_side if (k % 2 == 1) else preferred_side
						lon_offset = (float(k) * rng.randf_range(4.5, 8.2)) * (1.0 if rng.randf() < 0.65 else -1.0)
					else:
						# Main depression + asymmetric trailing satellite splash pockets
						side = preferred_side if rng.randf() < 0.68 else -preferred_side
						lon_offset = rng.randf_range(-11.5, 11.5)
					# Strict anti-symmetry: puddles on opposite sides of the road must be longitudinally staggered (>= 4.2m)
					for pi in placed_lons.size():
						if placed_sides[pi] != side and absf(lon_offset - placed_lons[pi]) < 4.2:
							lon_offset = placed_lons[pi] + (4.4 + rng.randf_range(0.8, 4.5)) * (1.0 if lon_offset >= placed_lons[pi] else -1.0)

				# Family-aware lateral band: center-spanning sheets, wheel-ruts, or outer shoulders/ditches
				var lat_min := float(profile.get("lat_min", 0.55))
				var lat_max := float(profile.get("lat_max", 1.95))
				var lat_mag := rng.randf_range(lat_min, lat_max)
				var lateral_offset := side * lat_mag

				var candidate_origin := seg_center + forward * lon_offset + right * lateral_offset
				var hit := road_hit(candidate_origin)
				if hit.is_empty() and absf(lateral_offset) > 1.25:
					# Fallback inward on narrower road segments so outer gutters still bind cleanly
					lateral_offset *= 0.72
					candidate_origin = seg_center + forward * lon_offset + right * lateral_offset
					hit = road_hit(candidate_origin)
				if hit.is_empty():
					continue

				var center: Vector3 = hit.position
				var normal: Vector3 = (hit.normal as Vector3).normalized()
				if normal.dot(Vector3.UP) < 0.78:
					continue

				var min_sep := 1.45 if k >= 3 else 2.45
				var too_close := false
				for prev_c in placed_centers:
					if prev_c.distance_to(center) < min_sep:
						too_close = true
						break
				if too_close:
					continue

				# Wide independent X/Y aspect jitter biased against overly thin strips
				var aspect_x := rng.randf_range(0.98, 1.48) if bool(profile.get("align_to_road", false)) else rng.randf_range(0.88, 1.45)
				var aspect_y := rng.randf_range(0.78, 1.26) if bool(profile.get("align_to_road", false)) else rng.randf_range(0.76, 1.30)
				var size := Vector2(
					float(profile.width) * scale * aspect_x,
					float(profile.length) * scale * aspect_y
				)
				var yaw := 0.0
				if bool(profile.get("align_to_road", false)):
					var jitter := float(profile.get("yaw_jitter", 0.22))
					yaw = rng.randf_range(-jitter, jitter)
				else:
					yaw = rng.randf_range(0.0, TAU)
				var patch_right := forward.cross(normal).normalized()
				if patch_right.length_squared() < 0.01:
					patch_right = right
				var patch_forward := normal.cross(patch_right).normalized()
				var basis := Basis(patch_right, normal, -patch_forward).rotated(normal, yaw).orthonormalized()

				var grid_res := int(profile.get("grid_res", 5))
				var conformal := _build_conformal_puddle_mesh(center, basis, size, grid_res)
				if conformal.is_empty():
					continue

				placed_centers.append(center)
				placed_lons.append(lon_offset)
				placed_sides.append(side)
				last_profile_idx = profile_idx
				family_counts[family] = int(family_counts.get(family, 0)) + 1

				# Highly variable per-instance depth and organic domain-warp parameters
				var instance_depth_mm := float(profile.depth_mm) * rng.randf_range(0.74, 1.28) * (0.88 if k > 0 else 1.0)
				var shape_params := Vector4(
					rng.randf_range(-0.52, 0.52),
					rng.randf_range(-0.48, 0.48),
					rng.randf_range(0.85, 1.55),
					rng.randf_range(0.0, TAU)
				)
				var flip_x := side if bool(profile.get("orient_to_edge", false)) else (-1.0 if rng.randf() > 0.5 else 1.0)
				var flip_y := -1.0 if rng.randf() > 0.5 else 1.0
				var uv_scale := Vector2(flip_x, flip_y)
				var mask_tex: Texture2D = profile.get("mask", MASK_ROUND)
				var mask_img := get_mask_image(mask_tex)

				var material := ShaderMaterial.new()
				material.shader = WATER_SHADER
				material.set_shader_parameter("patch_size", size)
				material.set_shader_parameter("puddle_mask", mask_tex)
				material.set_shader_parameter("use_mask_texture", true)
				material.set_shader_parameter("uv_scale", uv_scale)
				material.set_shader_parameter("shape_params", shape_params)
				material.set_shader_parameter("max_depth_mm", instance_depth_mm)
				material.set_shader_parameter("edge_softness", float(profile.get("edge_softness", 0.18)))
				material.set_shader_parameter("turbidity_rate", float(profile.get("turbidity", 0.065)))
				material.set_shader_parameter("water_detail_tex", WATER_DETAIL_TEX)

				var mesh_instance := MeshInstance3D.new()
				mesh_instance.name = "Puddle_%03d_%s" % [patches.size(), String(profile.id)]
				mesh_instance.mesh = conformal.mesh
				mesh_instance.material_override = material
				mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mesh_instance)
				mesh_instance.global_transform = Transform3D(basis, center + normal * 0.014)
				mesh_instance.visible = false

				var patch := {
					"transform": mesh_instance.global_transform,
					"size": size,
					"profile": profile,
					"family": family,
					"distance": next_cluster_dist,
					"twi": twi,
					"fill": 0.0,
					"material": material,
					"mesh": mesh_instance,
					"shape_params": shape_params,
					"mask_image": mask_img,
					"uv_scale": uv_scale,
					"lateral_offset": lateral_offset,
					"yaw": yaw,
					"cluster_id": cluster_id,
					"depth_mm": instance_depth_mm,
				}
				patches.append(patch)

				var radius := size.length() * 0.55
				for x in range(floori((center.x - radius) / 16.0), floori((center.x + radius) / 16.0) + 1):
					for z in range(floori((center.z - radius) / 16.0), floori((center.z + radius) / 16.0) + 1):
						var key := Vector2i(x, z)
						if not buckets.has(key):
							buckets[key] = []
						buckets[key].append(patch)

			if not placed_centers.is_empty():
				cluster_id += 1

			if is_short_test_route:
				next_cluster_dist += rng.randf_range(16.0, 28.0) / clampf(twi, 0.65, 1.35)
			else:
				# Multi-scale drainage rhythm: denser puddle sequences in wet drainage swales, wider gaps on well-drained grades
				var drain_wave := 0.5 + 0.5 * sin(next_cluster_dist * 0.014 + float(stage_seed % 997) * 0.13) * cos(next_cluster_dist * 0.0057)
				var step_min := 18.0 if (drain_wave > 0.48 or twi >= 1.02) else 34.0
				var step_max := 38.0 if (drain_wave > 0.48 or twi >= 1.02) else 66.0
				next_cluster_dist += rng.randf_range(step_min, step_max) / clampf(twi, 0.65, 1.35)

		distance += seg_len

	_sync_patches_to_rust()
	_rebuild_candidate_arrays()
	if provider != null and bool(provider.get("five_sector_snapshot_active")):
		apply_fixed_snapshot_fills()
	print("RALLY_PUDDLES_READY count=", patches.size(), " seed=", stage_seed, " clusters=", cluster_id)


func _rebuild_candidate_arrays() -> void:
	var n := patches.size()
	_cand_distances.resize(n)
	_cand_twis.resize(n)
	_cand_min_waters.resize(n)
	_cand_retentions.resize(n)
	for i in n:
		var p: Dictionary = patches[i]
		var prof: Dictionary = p["profile"] as Dictionary
		_cand_distances[i] = float(p.get("distance", 0.0))
		_cand_twis[i] = float(p.get("twi", 1.0))
		_cand_min_waters[i] = float(prof.get("min_water", 0.75))
		_cand_retentions[i] = float(prof.get("retention", 1.0))


func apply_fixed_snapshot_fills() -> bool:
	if not built:
		build()
	if provider == null or not bool(provider.get("five_sector_snapshot_active")):
		fixed_snapshot_mode = false
		return false
	if _cand_distances.size() != patches.size():
		_rebuild_candidate_arrays()
	var fills: PackedFloat32Array = provider.call(
		"compute_puddle_fills", _cand_distances, _cand_twis, _cand_min_waters, _cand_retentions
	)
	var count := patches.size()
	var localized_snow := str(provider.get("stage_id")) == "cdi_stage1"
	has_winter_patches = false
	if _rust_fills.size() != count:
		_rust_fills.resize(count)
	for i in count:
		var fill := fills[i] if i < fills.size() else 0.0
		var patch: Dictionary = patches[i]
		var winter_kind := 0
		var winter_depth_mm := 0.0
		if localized_snow:
			var surface: Dictionary = provider.local_surface_state_at_distance(_cand_distances[i])
			var snow_mm := float(surface.get("snow_mm", 0.0))
			var retention := _cand_retentions[i]
			# Deep basins shelter snow earlier than shallow, exposed hollows.
			var shelter := smoothstep(5.0, 48.0, float(patch.depth_mm))
			var snow_threshold_mm := lerpf(5.0, 1.5, shelter)
			if snow_mm * retention >= snow_threshold_mm:
				winter_kind = 1
				winter_depth_mm = clampf(snow_mm * retention, 0.0, 30.0)
		if winter_kind != 0:
			fill = 0.0
			has_winter_patches = true
		patch["winter_kind"] = winter_kind
		patch["winter_depth_mm"] = winter_depth_mm
		patch["fill"] = fill
		_rust_fills[i] = fill
		var mesh := patch["mesh"] as MeshInstance3D
		var filled := fill > 0.005 or winter_kind != 0
		if mesh != null and mesh.visible != filled:
			mesh.visible = filled
		var mat := patch["material"] as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("fill", fill)
			mat.set_shader_parameter("winter_kind", winter_kind)
			mat.set_shader_parameter("winter_depth_mm", winter_depth_mm)
	if _rust_field != null:
		_rust_field.call("update_fills", _rust_fills)
	fixed_snapshot_mode = true
	_refresh_visible_reflections_only()
	return true


## Returns `Vector2(snow_depth_mm, drag_scale)` for active localized snow patches (`winter_kind == 1`).
func sample_snow_patch(position: Vector3) -> Vector2:
	var best_depth := 0.0
	var best_drag := 1.0
	var key := Vector2i(floori(position.x / 16.0), floori(position.z / 16.0))
	for patch: Dictionary in buckets.get(key, []):
		if int(patch.get("winter_kind", 0)) != 1:
			continue
		var local: Vector3 = (patch.transform as Transform3D).affine_inverse() * position
		if absf(local.y) > 0.20:
			continue
		var uv := Vector2(local.x / patch.size.x, local.z / patch.size.y)
		var img: Image = patch.get("mask_image")
		var mask := sample_image_mask(img, uv, patch.uv_scale, patch.shape_params) if img != null else mask_at(uv, patch.shape_params)
		var depth := clampf((mask - 0.18) / 0.82, 0.0, 1.0) * float(patch.winter_depth_mm)
		if depth > best_depth:
			best_depth = depth
			var prof: Dictionary = patch.get("profile", {}) as Dictionary
			best_drag = float(prof.get("drag", 1.0))
	return Vector2(best_depth, best_drag)


func sample_winter_patch(position: Vector3) -> Vector2:
	return Vector2(sample_snow_patch(position).x, 0.0)


func _apply_sky_uniforms(material: ShaderMaterial) -> void:
	var sky_mat := sky_node.get("material") as ShaderMaterial
	if sky_mat != null:
		material.set_shader_parameter("has_sky", true)
		for parameter in [
			"sky_a", "sky_b", "sky_c", "weather_mix", "daylight_mix",
			"twilight_yaw", "yaw_b", "tint_a", "tint_b", "tint_c", "horizon_color"
		]:
			material.set_shader_parameter(parameter, sky_mat.get_shader_parameter(parameter))
	var sun := sky_node.get("sun") as DirectionalLight3D
	var moon := sky_node.get("moon") as DirectionalLight3D
	var light: DirectionalLight3D = sun if (sun != null and is_instance_valid(sun)) else null
	if moon != null and is_instance_valid(moon) and (light == null or moon.light_energy > light.light_energy):
		light = moon
	if light != null:
		var dir := light.global_basis.z
		if not dir.is_zero_approx():
			material.set_shader_parameter("sun_dir", dir.normalized())
		var col := light.light_color * light.light_energy
		material.set_shader_parameter("sun_color", Vector3(col.r, col.g, col.b))


func _refresh_visible_reflections_only() -> void:
	var has_sky := is_instance_valid(sky_node) and sky_node.get("material") != null
	for patch in patches:
		if float(patch["fill"]) <= 0.005:
			continue
		var material: ShaderMaterial = patch["material"]
		if material == null:
			continue
		if has_sky:
			_apply_sky_uniforms(material)
		var local_state := _local_liquid_state(float(patch["distance"]))
		material.set_shader_parameter("rain", float(local_state.get("rain_ratio", 0.0)))
		material.set_shader_parameter("wind_vec", local_state.get("wind_vec", Vector2(1.2, 0.4)) as Vector2)


## Shared CPU/Rust/GPU bathymetric shoreline threshold in [0.18, 0.62].
## At low fill, standing water is confined to the deepest pit (mask > 0.62);
## as fill -> 1.0, the shoreline advances outward to the full basin rim (0.18).
static func shore_threshold_for_fill(fill: float) -> float:
	var t := clampf(fill, 0.0, 1.0)
	var f := t * (1.35 - 0.35 * t)
	return lerpf(0.62, 0.18, f)


## Smooth rounded organic procedural mask without sharp pinches
static func mask_at(uv: Vector2, shape_params: Vector4 = Vector4.ZERO) -> float:
	var p := uv * 2.0
	p.x += (p.y * 0.20) * shape_params.y
	p.x *= (1.0 + p.y * 0.15 * shape_params.x)
	var phase := shape_params.w
	var w1 := sin(p.y * 2.2 + phase) * 0.08 * shape_params.z
	var w2 := cos(p.x * 2.0 + phase * 1.2) * 0.08 * shape_params.z
	var warped := p + Vector2(w1, w2)
	var r := warped.length()
	var theta := atan2(warped.y, warped.x)
	var r_bound := 0.86 + 0.05 * sin(2.0 * theta + phase);
	return clampf(1.0 - (r / r_bound), 0.0, 1.0)


static func warp_mask_uv(uv: Vector2, uv_scale: Vector2, shape_params: Vector4 = Vector4.ZERO) -> Vector2:
	var p := uv * uv_scale
	var px := p.x * (1.0 + p.y * 0.34 * shape_params.x) + (p.y * p.y - 0.06) * 0.28 * shape_params.y
	var py := p.y * (1.0 - p.x * 0.18 * shape_params.y) + (p.x * p.x - 0.05) * 0.16 * shape_params.x
	var r2 := clampf(p.dot(p) * 4.0, 0.0, 1.0)
	var w1 := (sin(py * 5.8 + shape_params.w) + 0.55 * cos(px * 11.2 - shape_params.w * 1.7)) * 0.038 * shape_params.z * r2
	var w2 := (cos(px * 5.4 + shape_params.w * 1.3) + 0.55 * sin(py * 10.6 + shape_params.w * 0.8)) * 0.038 * shape_params.z * r2
	return Vector2(px + w1 + 0.5, py + w2 + 0.5)


static func sample_image_mask(
	img: Image,
	uv: Vector2,
	uv_scale: Vector2,
	shape_params: Vector4 = Vector4.ZERO
) -> float:
	if img == null:
		return 0.0
	var muv := warp_mask_uv(uv, uv_scale, shape_params)
	if muv.x < 0.0 or muv.x > 1.0 or muv.y < 0.0 or muv.y > 1.0:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var px := clampi(int(muv.x * float(w - 1)), 0, w - 1)
	var py := clampi(int(muv.y * float(h - 1)), 0, h - 1)
	return img.get_pixel(px, py).r


func sample_contact(position: Vector3) -> Dictionary:
	if use_rust_backend and _rust_field != null:
		var packed: PackedFloat32Array = _rust_field.call("sample_contact_packed", position)
		var depth_mm: float = packed[0]
		if depth_mm <= 0.0:
			return {
				"depth_mm": 0.0,
				"drag": 0.0,
				"fill": 0.0,
				"max_depth_mm": 0.0,
				"profile_id": "none",
			}
		var idx: int = int(packed[4])
		var pid: String = "none"
		if idx >= 0 and idx < patches.size():
			pid = str((patches[idx]["profile"] as Dictionary)["id"])
		return {
			"depth_mm": depth_mm,
			"drag": packed[1],
			"fill": packed[2],
			"max_depth_mm": packed[3],
			"profile_id": pid,
		}

	var result := {
		"depth_mm": 0.0,
		"drag": 0.0,
		"fill": 0.0,
		"max_depth_mm": 0.0,
		"profile_id": "none",
	}
	var key := Vector2i(floori(position.x / 16.0), floori(position.z / 16.0))
	for patch in buckets.get(key, []):
		var local: Vector3 = (patch.transform as Transform3D).affine_inverse() * position
		if absf(local.y) > 0.20:
			continue
		var uv := Vector2(local.x / patch.size.x, local.z / patch.size.y)
		var mask := 0.0
		var img: Image = patch.get("mask_image")
		if img != null:
			mask = sample_image_mask(img, uv, patch.get("uv_scale", Vector2.ONE), patch.get("shape_params", Vector4.ZERO))
		else:
			mask = mask_at(uv, patch.shape_params)

		var fill := float(patch.fill)
		if fill <= 0.001:
			continue
		var shore_thresh := shore_threshold_for_fill(fill)
		if mask <= shore_thresh:
			continue

		var patch_depth := float(patch.get("depth_mm", patch.profile.depth_mm))
		var water_mask := clampf((mask - shore_thresh) / (1.0 - shore_thresh), 0.0, 1.0)
		var depth := water_mask * fill * patch_depth
		if depth > float(result.depth_mm):
			result = {
				"depth_mm": depth,
				"drag": float(patch.profile.drag),
				"fill": fill,
				"max_depth_mm": patch_depth,
				"profile_id": str(patch.profile.id),
			}
	return result


static func _get_rust_static_helper() -> RefCounted:
	if _rust_static_helper == null and ClassDB.class_exists(&"RustPuddleField"):
		_rust_static_helper = ClassDB.instantiate(&"RustPuddleField") as RefCounted
	return _rust_static_helper


func _ensure_rust_mask_id(img: Image) -> int:
	if img == null or _rust_field == null:
		return 0
	var key: String = img.resource_path
	if key.is_empty():
		key = str(img.get_instance_id())
	if _rust_mask_ids.has(key):
		return int(_rust_mask_ids[key])
	var send_img: Image = img
	if send_img.is_compressed():
		send_img = img.duplicate() as Image
		send_img.decompress()
	var fmt: Image.Format = send_img.get_format()
	if fmt != Image.FORMAT_RGBA8 and fmt != Image.FORMAT_R8:
		send_img = send_img.duplicate() as Image
		send_img.convert(Image.FORMAT_RGBA8)
	var mask_id: int = _rust_next_mask_id
	_rust_next_mask_id += 1
	_rust_field.call("register_mask", mask_id, send_img.get_width(), send_img.get_height(), send_img.get_data())
	_rust_mask_ids[key] = mask_id
	return mask_id


func _sync_patches_to_rust() -> void:
	if not use_rust_backend or not ClassDB.class_exists(&"RustPuddleField"):
		_rust_field = null
		return
	if _rust_field == null:
		_rust_field = ClassDB.instantiate(&"RustPuddleField") as RefCounted
	else:
		_rust_field.call("clear_patches")
	var n: int = patches.size()
	if n == 0:
		_rust_fills.resize(0)
		return
	var inv_bx := PackedVector3Array()
	var inv_by := PackedVector3Array()
	var inv_bz := PackedVector3Array()
	var inv_origins := PackedVector3Array()
	var world_centers := PackedVector3Array()
	var sizes := PackedVector2Array()
	var uv_scales := PackedVector2Array()
	var shape_params := PackedFloat32Array()
	var max_depths := PackedFloat32Array()
	var drags := PackedFloat32Array()
	var mask_ids := PackedInt32Array()
	var fills := PackedFloat32Array()
	inv_bx.resize(n)
	inv_by.resize(n)
	inv_bz.resize(n)
	inv_origins.resize(n)
	world_centers.resize(n)
	sizes.resize(n)
	uv_scales.resize(n)
	shape_params.resize(n * 4)
	max_depths.resize(n)
	drags.resize(n)
	mask_ids.resize(n)
	fills.resize(n)
	for i in n:
		var patch: Dictionary = patches[i]
		var xf: Transform3D = patch["transform"] as Transform3D
		var inv_xf: Transform3D = xf.affine_inverse()
		inv_bx[i] = inv_xf.basis.x
		inv_by[i] = inv_xf.basis.y
		inv_bz[i] = inv_xf.basis.z
		inv_origins[i] = inv_xf.origin
		var normal: Vector3 = xf.basis.y.normalized()
		world_centers[i] = xf.origin - normal * 0.014
		sizes[i] = patch["size"] as Vector2
		uv_scales[i] = patch.get("uv_scale", Vector2.ONE) as Vector2
		var sp: Vector4 = patch["shape_params"] as Vector4
		var base_sp: int = i * 4
		shape_params[base_sp] = sp.x
		shape_params[base_sp + 1] = sp.y
		shape_params[base_sp + 2] = sp.z
		shape_params[base_sp + 3] = sp.w
		var prof: Dictionary = patch["profile"] as Dictionary
		max_depths[i] = float(patch.get("depth_mm", prof["depth_mm"]))
		drags[i] = float(prof["drag"])
		mask_ids[i] = _ensure_rust_mask_id(patch.get("mask_image") as Image)
		fills[i] = float(patch.get("fill", 0.0))
	_rust_fills = fills
	_rust_field.call(
		"set_patches",
		inv_bx,
		inv_by,
		inv_bz,
		inv_origins,
		world_centers,
		sizes,
		uv_scales,
		shape_params,
		max_depths,
		drags,
		mask_ids,
		fills,
	)


func sample_4wheels(positions: PackedVector3Array, loaded_mask: int) -> PackedFloat32Array:
	if use_rust_backend and _rust_field != null:
		return _rust_field.call("sample_4wheels", positions, loaded_mask) as PackedFloat32Array
	var out := PackedFloat32Array()
	out.resize(8)
	var count: int = mini(positions.size(), 4)
	for i in count:
		if (loaded_mask & (1 << i)) == 0:
			continue
		var c: Dictionary = sample_contact(positions[i])
		out[i * 2] = float(c["depth_mm"])
		out[i * 2 + 1] = float(c["drag"])
	return out


## Computes physical hydrodynamic response: retarding drag force, entry slam,
## wheel rotational braking torque, steering pull and differentiated aquaplaning support.
##
## Saturations:
## - WATER_GRIP_DEPTH_SATURATION_MM: depth at which the aquaplaning risk is
##   complete (12 mm). Any water deeper than that behaves like deep water
##   for grip purposes, so a road puddle and a river ford share the same
##   aquaplaning curve once the tyre is submerged.
## - WATER_DRAG_MAX_LOAD_FRACTION: cap of the retarding force as a fraction
##   of the wheel's normal load (+25% maximum retarding reaction force).
const WATER_GRIP_DEPTH_SATURATION_MM := 12.0
const WATER_DRAG_MAX_LOAD_FRACTION := 0.8125
static func contact_response(
	depth_mm: float,
	speed: float,
	evacuation: Variant,
	load_n: float,
	width: float,
	drag_scale: float,
	delta_depth_s: float = 0.0,
	wheel_radius: float = 0.28
) -> Dictionary:
	if depth_mm <= 0.001 or absf(speed) <= 0.001:
		return {
			"support": 1.0,
			"support_longitudinal": 1.0,
			"support_lateral": 1.0,
			"drag_n": 0.0,
			"slam_n": 0.0,
			"wheel_torque_nm": 0.0,
			"steering_pull_nm": 0.0,
			"vertical_dip_m": 0.0,
		}

	var abs_speed := absf(speed)
	# Numeric evacuation property from the catalog; bool callers remain compatible.
	var evac_speed := (28.0 if evacuation else 16.0) if evacuation is bool else maxf(float(evacuation), 0.1)
	var wet_factor := clampf((evac_speed - 16.0) / 12.0, 0.0, 1.0)
	var depth_t := clampf((depth_mm - 1.5) / (WATER_GRIP_DEPTH_SATURATION_MM - 1.5), 0.0, 1.0)
	var depth_u := pow(depth_t, 0.72)
	var depth_norm := depth_u * depth_u * (3.0 - 2.0 * depth_u)
	var speed_risk := maxf(smoothstep(evac_speed * 0.42, evac_speed * 1.25, abs_speed), 0.18 * smoothstep(4.0, 14.0, abs_speed))
	var risk := speed_risk * depth_norm

	# Differentiated aquaplaning support: lateral cornering grip drops faster than longitudinal braking
	var support_long := 1.0 - risk * lerpf(0.80, 0.55, wet_factor)
	var support_lat := 1.0 - risk * lerpf(0.94, 0.75, wet_factor)
	var support := minf(support_long, support_lat)

	# Continuous hydrodynamic displacement drag + viscous shearing (+25% force scale)
	var continuous_drag := (150.0 * abs_speed + 2750.0 * abs_speed * abs_speed) * width * depth_mm * 0.001 * drag_scale

	# Entry slam impulse: sharp deceleration spike when tire first plunges into water wedge (+25% force & cap)
	var slam_drag := 0.0
	if delta_depth_s > 0.0:
		slam_drag = 22.5 * width * minf(delta_depth_s, 200.0) * abs_speed * drag_scale
		slam_drag = minf(slam_drag, load_n * 0.3125)

	# Cap total drag at 81.25% of wheel normal load (+25% maximum retarding reaction force)
	var max_drag := load_n * WATER_DRAG_MAX_LOAD_FRACTION
	var total_drag := minf(continuous_drag + slam_drag, max_drag)

	# Rotational braking torque on tire tread
	var wheel_torque_nm := total_drag * 0.75 * wheel_radius

	# Steering pull torque (scrub radius moment on steered wheels)
	var steering_pull_nm := total_drag * 0.07

	# Vertical depression into the physical pothole / rut
	var vertical_dip_m := clampf(depth_mm * 0.001 * 0.45, 0.0, 0.018)

	return {
		"support": support,
		"support_longitudinal": support_long,
		"support_lateral": support_lat,
		"drag_n": total_drag,
		"slam_n": slam_drag,
		"continuous_drag_n": continuous_drag,
		"wheel_torque_nm": wheel_torque_nm,
		"steering_pull_nm": steering_pull_nm,
		"vertical_dip_m": vertical_dip_m,
	}


static func contact_response_packed(
	depth_mm: float,
	speed: float,
	evacuation: Variant,
	load_n: float,
	width: float,
	drag_scale: float,
	delta_depth_s: float = 0.0,
	wheel_radius: float = 0.28
) -> PackedFloat32Array:
	var evac_speed: float = (28.0 if evacuation else 16.0) if evacuation is bool else maxf(float(evacuation), 0.1)
	var helper: RefCounted = _get_rust_static_helper()
	if helper != null:
		return helper.call(
			"contact_response_packed",
			depth_mm,
			speed,
			evac_speed,
			load_n,
			width,
			drag_scale,
			delta_depth_s,
			wheel_radius,
		) as PackedFloat32Array
	var d: Dictionary = contact_response(depth_mm, speed, evac_speed, load_n, width, drag_scale, delta_depth_s, wheel_radius)
	var out := PackedFloat32Array()
	out.resize(9)
	out[0] = float(d.get("support", 1.0))
	out[1] = float(d.get("support_longitudinal", 1.0))
	out[2] = float(d.get("support_lateral", 1.0))
	out[3] = float(d.get("drag_n", 0.0))
	out[4] = float(d.get("slam_n", 0.0))
	out[5] = float(d.get("continuous_drag_n", 0.0))
	out[6] = float(d.get("wheel_torque_nm", 0.0))
	out[7] = float(d.get("steering_pull_nm", 0.0))
	out[8] = float(d.get("vertical_dip_m", 0.0))
	return out


const SNOW_DRAG_MAX_LOAD_FRACTION := 0.95
static func snow_contact_response(
	depth_mm: float,
	speed: float,
	load_n: float,
	width: float,
	drag_scale: float,
	delta_depth_s: float = 0.0,
	wheel_radius: float = 0.28
) -> Dictionary:
	if depth_mm <= 0.001 or absf(speed) <= 0.001:
		return {
			"support": 1.0,
			"support_longitudinal": 1.0,
			"support_lateral": 1.0,
			"drag_n": 0.0,
			"slam_n": 0.0,
			"continuous_drag_n": 0.0,
			"wheel_torque_nm": 0.0,
			"steering_pull_nm": 0.0,
			"vertical_dip_m": 0.0,
		}

	var abs_speed := absf(speed)
	var depth_factor := smoothstep(1.5, 24.0, depth_mm)
	var support_long := 1.0 - 0.14 * depth_factor
	var support_lat := 1.0 - 0.22 * depth_factor
	var support := minf(support_long, support_lat)

	var low_speed_ramp := smoothstep(0.0, 2.0, abs_speed)
	var continuous_drag := (9500.0 * low_speed_ramp + 1800.0 * abs_speed + 3600.0 * abs_speed * abs_speed) * width * depth_mm * 0.001 * drag_scale

	var slam_drag := 0.0
	if delta_depth_s > 0.0:
		slam_drag = 34.0 * width * minf(delta_depth_s, 200.0) * abs_speed * drag_scale
		slam_drag = minf(slam_drag, load_n * 0.45)

	var max_drag := load_n * SNOW_DRAG_MAX_LOAD_FRACTION
	var total_drag := minf(continuous_drag + slam_drag, max_drag)
	var wheel_torque_nm := total_drag * 0.95 * wheel_radius
	var steering_pull_nm := total_drag * 0.11
	var vertical_dip_m := clampf(depth_mm * 0.001 * 0.30, 0.0, 0.012)

	return {
		"support": support,
		"support_longitudinal": support_long,
		"support_lateral": support_lat,
		"drag_n": total_drag,
		"slam_n": slam_drag,
		"continuous_drag_n": continuous_drag,
		"wheel_torque_nm": wheel_torque_nm,
		"steering_pull_nm": steering_pull_nm,
		"vertical_dip_m": vertical_dip_m,
	}


static func snow_contact_response_packed(
	depth_mm: float,
	speed: float,
	load_n: float,
	width: float,
	drag_scale: float,
	delta_depth_s: float = 0.0,
	wheel_radius: float = 0.28
) -> PackedFloat32Array:
	var helper: RefCounted = _get_rust_static_helper()
	if helper != null and helper.has_method(&"snow_contact_response_packed"):
		return helper.call(
			"snow_contact_response_packed",
			depth_mm,
			speed,
			load_n,
			width,
			drag_scale,
			delta_depth_s,
			wheel_radius,
		) as PackedFloat32Array
	var d: Dictionary = snow_contact_response(depth_mm, speed, load_n, width, drag_scale, delta_depth_s, wheel_radius)
	var out := PackedFloat32Array()
	out.resize(9)
	out[0] = float(d.get("support", 1.0))
	out[1] = float(d.get("support_longitudinal", 1.0))
	out[2] = float(d.get("support_lateral", 1.0))
	out[3] = float(d.get("drag_n", 0.0))
	out[4] = float(d.get("slam_n", 0.0))
	out[5] = float(d.get("continuous_drag_n", 0.0))
	out[6] = float(d.get("wheel_torque_nm", 0.0))
	out[7] = float(d.get("steering_pull_nm", 0.0))
	out[8] = float(d.get("vertical_dip_m", 0.0))
	return out
