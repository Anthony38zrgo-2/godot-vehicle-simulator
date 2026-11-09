class_name RallyPuddles
extends Node3D

## Stable route-seeded virtual depressions with smooth circular-biased organic contours,
## topographic wetness index (TWI), Poisson cluster generation, bimodal lateral distribution,
## conformal adaptive mesh, prefabricated PNG masks, physical hydrodynamic retarding drag and aquaplaning.

const WATER_SHADER = preload("res://scripts/rally/rally_puddle.gdshader")

const MASK_ROUND = preload("res://assets/vfx/puddles/puddle_round_organic.png")
const MASK_KIDNEY = preload("res://assets/vfx/puddles/puddle_kidney_soft.png")
const MASK_EGG = preload("res://assets/vfx/puddles/puddle_egg_asym.png")
const MASK_CLOVER = preload("res://assets/vfx/puddles/puddle_lobe_triple.png")

const TYPES := [
	{
		"id": "pothole_deep",
		"length": 3.75,
		"width": 3.25,
		"depth_mm": 48.0,
		"drag": 1.55,
		"min_water": 0.60,
		"retention": 1.40,
		"mask": MASK_ROUND,
		"lobe_scale": 1.0,
		"edge_softness": 0.12,
	},
	{
		"id": "basin_kidney",
		"length": 4.50,
		"width": 3.88,
		"depth_mm": 36.0,
		"drag": 1.35,
		"min_water": 0.70,
		"retention": 1.25,
		"mask": MASK_KIDNEY,
		"lobe_scale": 1.15,
		"edge_softness": 0.18,
	},
	{
		"id": "pond_egg",
		"length": 4.12,
		"width": 3.62,
		"depth_mm": 25.0,
		"drag": 1.20,
		"min_water": 0.75,
		"retention": 1.20,
		"mask": MASK_EGG,
		"lobe_scale": 1.05,
		"edge_softness": 0.16,
	},
	{
		"id": "pool_clover",
		"length": 4.75,
		"width": 4.25,
		"depth_mm": 14.0,
		"drag": 1.10,
		"min_water": 0.85,
		"retention": 1.10,
		"mask": MASK_CLOVER,
		"lobe_scale": 1.25,
		"edge_softness": 0.22,
	},
	{
		"id": "shallow_round",
		"length": 3.12,
		"width": 2.88,
		"depth_mm": 5.0,
		"drag": 0.80,
		"min_water": 1.15,
		"retention": 0.85,
		"mask": MASK_ROUND,
		"lobe_scale": 0.95,
		"edge_softness": 0.20,
	},
]

static var _mask_images: Dictionary = {}

var provider = null
var sky_node: Node
var wetness_node: Node
var route: Array[Vector3] = []
var stage_seed: int = 0
var patches: Array[Dictionary] = []
var buckets: Dictionary = {}
var elapsed := 0.0
var built := false


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

	for patch in patches:
		var profile: Dictionary = patch.profile
		var water := background_water(float(patch.distance))
		var min_w := float(profile.get("min_water", 0.75))

		# Zero puddles in dry conditions (water below basin threshold):
		if water <= min_w:
			patch.fill = 0.0
		else:
			var ret := float(profile.get("retention", 1.0))
			patch.fill = clampf((water - min_w) * ret / 3.0, 0.0, 1.0)

		var patch_depth := float(patch.get("depth_mm", profile.depth_mm))
		var material: ShaderMaterial = patch.material
		material.set_shader_parameter("fill", patch.fill)
		material.set_shader_parameter("max_depth_mm", patch_depth)

		if is_instance_valid(sky_node):
			material.set_shader_parameter("has_sky", true)
			for parameter in [
				"sky_a", "sky_b", "sky_c", "weather_mix", "daylight_mix",
				"twilight_yaw", "yaw_b", "tint_a", "tint_b", "tint_c", "horizon_color"
			]:
				material.set_shader_parameter(parameter, sky_node.material.get_shader_parameter(parameter))

		var rain := 0.0
		if provider != null and provider.calendar_active:
			var state: Dictionary = provider.surface.blended_state_at_distance(float(patch.distance))
			rain = clampf(float(state.get("climate", {}).get("precipitation_mm_h", 0.0)) / 10.0, 0.0, 1.0)
		elif is_instance_valid(wetness_node):
			rain = float(wetness_node.rain_intensity)
		material.set_shader_parameter("rain", rain)
		(patch.mesh as MeshInstance3D).visible = float(patch.fill) > 0.005


func background_water(distance: float) -> float:
	if provider != null and provider.calendar_active:
		return float(provider.surface.blended_state_at_distance(distance).get("water_mm", 0.0))
	return float(wetness_node.wetness) * 4.0 if is_instance_valid(wetness_node) else 0.0


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
static func _compute_route_topography(route_pts: Array[Vector3]) -> Array[Dictionary]:
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


## Builds a 5x5 conformal mesh projected onto the actual road collision surface.
## Vertices that overhang the road edge are clamped in height and receive COLOR.r = 0.0
## to let the shader fade the water edge smoothly without floating triangles.
func _build_conformal_puddle_mesh(
	center: Vector3,
	basis: Basis,
	size: Vector2
) -> Dictionary:
	const GRID_RES := 5
	var normal := basis.y.normalized()
	var total_samples := GRID_RES * GRID_RES
	var valid_hits := 0
	var local_heights: Array[float] = []
	local_heights.resize(total_samples)
	var edge_weights: Array[float] = []
	edge_weights.resize(total_samples)

	for gz in range(GRID_RES):
		var v_ratio := float(gz) / float(GRID_RES - 1)
		var z_local := (v_ratio - 0.5) * size.y
		for gx in range(GRID_RES):
			var u_ratio := float(gx) / float(GRID_RES - 1)
			var x_local := (u_ratio - 0.5) * size.x
			var idx := gz * GRID_RES + gx

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
		for gz in range(GRID_RES):
			for gx in range(GRID_RES):
				var idx := gz * GRID_RES + gx
				if edge_weights[idx] > 0.5:
					continue
				var sum_h := 0.0
				var count_h := 0.0
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var nx := gx + dx
						var nz := gz + dz
						if nx >= 0 and nx < GRID_RES and nz >= 0 and nz < GRID_RES:
							var n_idx := nz * GRID_RES + nx
							if edge_weights[n_idx] > 0.5:
								sum_h += local_heights[n_idx]
								count_h += 1.0
				if count_h > 0.0:
					local_heights[idx] = sum_h / count_h

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for gz in range(GRID_RES):
		var v_norm := float(gz) / float(GRID_RES - 1)
		var z_local := (v_norm - 0.5) * size.y
		for gx in range(GRID_RES):
			var u_norm := float(gx) / float(GRID_RES - 1)
			var x_local := (u_norm - 0.5) * size.x
			var idx := gz * GRID_RES + gx
			var y_local: float = local_heights[idx]
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(u_norm, v_norm))
			st.set_color(Color(edge_weights[idx], 1.0, 1.0, 1.0))
			st.add_vertex(Vector3(x_local, y_local, z_local))

	for gz in range(GRID_RES - 1):
		for gx in range(GRID_RES - 1):
			var i00 := gz * GRID_RES + gx
			var i10 := i00 + 1
			var i01 := (gz + 1) * GRID_RES + gx
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

	var topo := _compute_route_topography(route)
	var distance := 0.0
	var next_cluster_dist := 14.0
	var cluster_id := 0

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

			for k in range(cluster_count):
				var profile_idx := (patches.size() + rng.randi_range(0, 1)) % TYPES.size()
				if k > 0 and twi < 1.15:
					profile_idx = rng.randi_range(2, TYPES.size() - 1)
				var profile: Dictionary = TYPES[profile_idx]

				# Wider scale distribution: small local dips to large flooded areas
				var scale := rng.randf_range(0.72, 1.35) if k == 0 else rng.randf_range(0.36, 0.90)
				var lon_offset := 0.0 if k == 0 else rng.randf_range(-8.5, 8.5)

				var side := preferred_side
				if k > 0:
					side = -preferred_side if rng.randf() < 0.58 else preferred_side

				# Bimodal lateral distribution: wheel rut (0.65..1.55 m) or road shoulder (1.45..2.35 m)
				var lat_mag := rng.randf_range(0.65, 1.55) if rng.randf() < 0.65 else rng.randf_range(1.45, 2.35)
				var lateral_offset := side * lat_mag

				var candidate_origin := seg_center + forward * lon_offset + right * lateral_offset
				var hit := road_hit(candidate_origin)
				if hit.is_empty():
					continue

				var center: Vector3 = hit.position
				var normal: Vector3 = (hit.normal as Vector3).normalized()
				if normal.dot(Vector3.UP) < 0.78:
					continue

				var too_close := false
				for prev_c in placed_centers:
					if prev_c.distance_to(center) < 2.65:
						too_close = true
						break
				if too_close:
					continue

				# 25% larger nominal size with wide independent X/Y aspect jitter
				var size := Vector2(
					float(profile.width) * scale * rng.randf_range(0.78, 1.28),
					float(profile.length) * scale * rng.randf_range(0.78, 1.28)
				)
				var yaw := rng.randf_range(0.0, TAU)
				var patch_right := forward.cross(normal).normalized()
				if patch_right.length_squared() < 0.01:
					patch_right = right
				var patch_forward := normal.cross(patch_right).normalized()
				var basis := Basis(patch_right, normal, -patch_forward).rotated(normal, yaw).orthonormalized()

				var conformal := _build_conformal_puddle_mesh(center, basis, size)
				if conformal.is_empty():
					continue

				placed_centers.append(center)
				# Highly variable per-instance depth and organic edge warping
				var instance_depth_mm := float(profile.depth_mm) * rng.randf_range(0.72, 1.28) * (0.88 if k > 0 else 1.0)
				var shape_params := Vector4(
					rng.randf_range(-0.32, 0.32),
					rng.randf_range(-0.28, 0.28),
					rng.randf_range(0.76, 1.24),
					rng.randf_range(0.0, TAU)
				)
				var uv_scale := Vector2(
					-1.0 if rng.randf() > 0.5 else 1.0,
					-1.0 if rng.randf() > 0.5 else 1.0
				)
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
					"distance": next_cluster_dist,
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

			var step_min := 16.0 if is_short_test_route else 34.0
			var step_max := 28.0 if is_short_test_route else 74.0
			next_cluster_dist += rng.randf_range(step_min, step_max) / clampf(twi, 0.65, 1.35)

		distance += seg_len

	print("RALLY_PUDDLES_READY count=", patches.size(), " seed=", stage_seed, " clusters=", cluster_id)


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


static func sample_image_mask(img: Image, uv: Vector2, uv_scale: Vector2) -> float:
	if img == null:
		return 0.0
	var muv := uv * uv_scale + Vector2(0.5, 0.5)
	if muv.x < 0.0 or muv.x > 1.0 or muv.y < 0.0 or muv.y > 1.0:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var px := clampi(int(muv.x * float(w - 1)), 0, w - 1)
	var py := clampi(int(muv.y * float(h - 1)), 0, h - 1)
	return img.get_pixel(px, py).r


func sample_contact(position: Vector3) -> Dictionary:
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
			mask = sample_image_mask(img, uv, patch.get("uv_scale", Vector2.ONE))
		else:
			mask = mask_at(uv, patch.shape_params)

		var fill := float(patch.fill)
		if fill <= 0.001 or mask <= 0.18:
			continue

		var patch_depth := float(patch.get("depth_mm", patch.profile.depth_mm))
		var water_mask := clampf((mask - 0.18) / 0.82, 0.0, 1.0)
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


## Computes physical hydrodynamic response: retarding drag force, entry slam,
## wheel rotational braking torque, steering pull and differentiated aquaplaning support.
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
	var risk := smoothstep(evac_speed * 0.60, evac_speed * 1.30, abs_speed) * smoothstep(1.5, 12.0, depth_mm)

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
	var max_drag := load_n * 0.8125
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
