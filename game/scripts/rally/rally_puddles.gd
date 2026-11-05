class_name RallyPuddles
extends Node3D
## Stable route-seeded virtual depressions. No random changes while driving.
const WATER_SHADER = preload("res://scripts/rally/rally_puddle.gdshader")
const TYPES := [
	{"id": "shallow", "length": 4.0, "width": 2.0, "depth_mm": 5.0, "drag": 0.8},
	{"id": "rut", "length": 9.0, "width": 0.85, "depth_mm": 9.0, "drag": 1.0},
	{"id": "deep", "length": 5.0, "width": 2.8, "depth_mm": 20.0, "drag": 1.15},
	{"id": "crossing", "length": 2.0, "width": 4.0, "depth_mm": 12.0, "drag": 1.0},
]
var provider = null
var sky_node: Node
var wetness_node: Node
var route: Array[Vector3] = []
var stage_seed: int = 0
var patches: Array[Dictionary] = []
var buckets: Dictionary = {}
var elapsed := 0.0
var built := false

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
		var water := background_water(float(patch.distance))
		patch.fill = clampf((water - 0.35) / 3.65, 0.0, 1.0)
		var material: ShaderMaterial = patch.material
		material.set_shader_parameter("fill", patch.fill)
		if is_instance_valid(sky_node):
			material.set_shader_parameter("has_sky", true)
			for parameter in ["sky_a", "sky_b", "sky_c", "weather_mix", "daylight_mix", "twilight_yaw", "yaw_b", "tint_a", "tint_b", "tint_c", "horizon_color"]:
				material.set_shader_parameter(parameter, sky_node.material.get_shader_parameter(parameter))
		var rain := 0.0
		if provider != null and provider.calendar_active:
			var state: Dictionary = provider.surface.blended_state_at_distance(float(patch.distance))
			rain = clampf(float(state.get("climate", {}).get("precipitation_mm_h", 0.0)) / 10.0, 0.0, 1.0)
		elif is_instance_valid(wetness_node):
			rain = float(wetness_node.rain_intensity)
		material.set_shader_parameter("rain", rain)
		(patch.mesh as MeshInstance3D).visible = float(patch.fill) > 0.01

func background_water(distance: float) -> float:
	if provider != null and provider.calendar_active:
		return float(provider.surface.blended_state_at_distance(distance).get("water_mm", 0.0))
	return float(wetness_node.wetness) * 4.0 if is_instance_valid(wetness_node) else 0.0

func road_hit(pos: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos - Vector3.UP * 4.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider := hit.collider as Node
	if collider == null or not bool(collider.get_meta("is_stage_road", false)):
		return {}
	return hit

func build() -> void:
	if built:
		return
	built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed
	var distance := 0.0
	var next := 14.0
	for i in range(1, route.size()):
		var segment := route[i] - route[i - 1]
		var length := segment.length()
		while next < distance + length:
			var center := route[i - 1] + segment * ((next - distance) / maxf(length, 0.001))
			var forward := segment.normalized()
			var right := forward.cross(Vector3.UP).normalized()
			center += right * rng.randf_range(-1.5, 1.5)
			var profile: Dictionary = TYPES[rng.randi_range(0, TYPES.size() - 1)]
			var hit := road_hit(center)
			if not hit.is_empty() and (hit.normal as Vector3).dot(Vector3.UP) > 0.998:
				var normal: Vector3 = hit.normal
				forward = forward.slide(normal).normalized()
				right = forward.cross(normal).normalized()
				var basis := Basis(right, normal, -forward)
				var size := Vector2(float(profile.width), float(profile.length)) * rng.randf_range(0.8, 1.2)
				var origin: Vector3 = hit.position
				var valid := true
				# Reject road edges, crests and steps instead of floating water over them.
				for uv in [Vector2(-0.5,-0.5), Vector2(0.5,-0.5), Vector2(-0.5,0.5), Vector2(0.5,0.5)]:
					var point: Vector3 = origin + right * uv.x * size.x - forward * uv.y * size.y
					var edge := road_hit(point)
					if edge.is_empty() or absf(((edge.position as Vector3) - point).dot(normal)) > 0.035:
						valid = false
						break
				if valid:
					var material := ShaderMaterial.new()
					material.shader = WATER_SHADER
					material.set_shader_parameter("patch_size", size)
					var plane := PlaneMesh.new()
					plane.size = size
					var mesh := MeshInstance3D.new()
					mesh.mesh = plane
					mesh.material_override = material
					mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mesh)
					mesh.global_transform = Transform3D(basis, origin + normal * 0.012)
					mesh.visible = false
					var patch := {"transform": mesh.global_transform, "size": size, "profile": profile, "distance": next, "fill": 0.0, "material": material, "mesh": mesh}
					patches.append(patch)
					# Spatial index includes every overlapped cell, including long ruts.
					var radius := size.length() * 0.5
					for x in range(floori((origin.x-radius)/16.0), floori((origin.x+radius)/16.0)+1):
						for z in range(floori((origin.z-radius)/16.0), floori((origin.z+radius)/16.0)+1):
							var key := Vector2i(x,z)
							if not buckets.has(key):
								buckets[key] = []
							buckets[key].append(patch)
			next += rng.randf_range(12.0, 26.0)
		distance += length
	print("RALLY_PUDDLES_READY count=", patches.size(), " seed=", stage_seed)

static func mask_at(uv: Vector2) -> float:
	var p := uv * 2.0
	var edge := 1.0 + 0.07 * sin(p.x * 11.0 + p.y * 7.0) * sin(p.y * 9.0)
	return clampf(1.0 - p.length() * edge, 0.0, 1.0)

func sample_contact(position: Vector3) -> Dictionary:
	var result := {"depth_mm": 0.0, "drag": 0.0}
	for patch in buckets.get(Vector2i(floori(position.x/16.0), floori(position.z/16.0)), []):
		var local: Vector3 = (patch.transform as Transform3D).affine_inverse() * position
		if absf(local.y) > 0.12:
			continue
		var mask := mask_at(Vector2(local.x / patch.size.x, local.z / patch.size.y))
		# Broader shallow water: footprint expands early, center depth still follows fill.
		var fill := float(patch.fill)
		var radius := pow(fill, 0.25)
		var depth := maxf(1.0 - (1.0 - mask) / maxf(radius, 0.0001), 0.0) * fill * float(patch.profile.depth_mm)
		if depth > float(result.depth_mm):
			result = {"depth_mm": depth, "drag": float(patch.profile.drag)}
	return result

static func contact_response(depth_mm: float, speed: float, wet_tire: bool, load_n: float, width: float, drag_scale: float) -> Dictionary:
	var evacuation_speed := 30.0 if wet_tire else 18.0
	var risk := smoothstep(evacuation_speed * 0.65, evacuation_speed * 1.5, absf(speed)) * smoothstep(1.0, 12.0, depth_mm)
	var support := 1.0 - risk * (0.68 if wet_tire else 0.90)
	var drag := minf(1200.0 * width * depth_mm * 0.001 * speed * speed * drag_scale, load_n * 0.45)
	return {"support": support, "drag_n": drag}
