class_name RallyTerrainWetness
extends Node

## Humedad del terreno propia del proyecto.
## TCA aporta la lluvia (intensidad y duracion); esta clase acumula, seca y aplica
## el efecto visual sobre los materiales de la pista.

const WETTABLE_NAME_FRAGMENTS := [
	"road", "gravel", "terrain",
	# Nuevos países: asfalto alpino, túneles, cruces, sendas y vías.
	"tarmac", "tunnel", "crossroad", "fin_path", "railroad", "railway",
	"bridge", "asphalt",
	# Tierra/barro: selva, taludes de erosión y suelos de bosque/campo.
	"jungle", "erosio", "forestground", "dirt", "mud", "field", "ditch",
	# Sabana africana (Kenia): hierba seca que sí se humedece.
	"savanna",
	# Do not match "snow" alone: forest snow cards stay unchanged. Snow road,
	# terrain and ditch surfaces share the same wet-ground response.
]

@export var visual_root: Node3D
@export var rain_accumulation_rate: float = 0.35
@export var dry_rate: float = 0.02
@export var maximum_roughness_drop: float = 0.5
@export var maximum_albedo_darkening: float = 0.3
@export var minimum_roughness: float = 0.05

var wetness: float = 0.0
var rain_intensity: float = 0.0
var shared_provider = null
var zone_wetness: Array[float] = [0.0, 0.0, 0.0]
var current_zone: int = 0

var _materials: Array[BaseMaterial3D] = []
var _original_roughness: Array[float] = []
var _original_albedo: Array[Color] = []
var _applied_wetness: float = -1.0
var _material_zones: Array[int] = []
var _material_distances_m: Array[float] = []
var _material_nodes: Array[MeshInstance3D] = []
var _applied_zone_wetness: Array[float] = [-1.0, -1.0, -1.0]
var _mesh_material_cache: Dictionary = {}


func _ready() -> void:
	bind_visual_root(visual_root)
	print("RALLY_TERRAIN_WETNESS materials=", _materials.size())

func bind_visual_root(new_root: Node3D) -> void:
	_materials.clear()
	_last_material_wetness.clear()
	_mesh_material_cache.clear()
	_original_roughness.clear()
	_original_albedo.clear()
	_material_zones.clear()
	_material_distances_m.clear()
	_material_nodes.clear()
	visual_root = new_root
	if visual_root != null:
		collect_materials(visual_root)
	_applied_wetness = wetness
	_applied_zone_wetness = [-1.0, -1.0, -1.0]
	apply_wetness()


func bind_shared_provider(provider) -> void:
	# Consumidor del estado físico compartido: la humedad ya no gobierna la
	# fricción por sí sola; el proveedor único alimenta visual + física.
	shared_provider = provider


func set_zone_wetness(value: float, zone_index: int = -1) -> void:
	if zone_index >= 0 and zone_index < zone_wetness.size():
		zone_wetness[zone_index] = clampf(value, 0.0, 1.0)
		current_zone = zone_index
	else:
		wetness = clampf(value, 0.0, 1.0)


func set_zone_states(water_by_zone: Array) -> void:
	for i in mini(water_by_zone.size(), zone_wetness.size()):
		zone_wetness[i] = clampf(float(water_by_zone[i]) / 4.0, 0.0, 1.0)


func assign_material_zones(route_points: Array, zone_bounds: Array) -> void:
	# Máscara espacial continua por distancia de chunk proyectada sobre la ruta.
	_material_zones.clear()
	_material_distances_m.clear()

	var route_dists: Array[float] = []
	if shared_provider != null and "route_distances" in shared_provider and not (shared_provider.route_distances as Array).is_empty():
		for rd in shared_provider.route_distances:
			route_dists.append(float(rd))
	else:
		var accum := 0.0
		route_dists.append(0.0)
		for i in range(1, route_points.size()):
			accum += (route_points[i] as Vector3).distance_to(route_points[i - 1] as Vector3)
			route_dists.append(accum)

	for n in _material_nodes.size():
		var node := _material_nodes[n]
		if node == null or not is_instance_valid(node):
			_material_zones.append(0)
			_material_distances_m.append(0.0)
			continue
		var p: Vector3 = node.to_global(node.get_aabb().get_center())
		var best := 0
		var best_d := INF
		for i in route_points.size():
			var rp: Vector3 = route_points[i]
			var d := Vector2(p.x - rp.x, p.z - rp.z).length_squared() + absf(p.y - rp.y) * 2.0
			if d < best_d:
				best_d = d
				best = i
		# zone_bounds: [b0, b1, b2, b3] en índices de nodo.
		var zi := 0
		if zone_bounds.size() == 4:
			if best >= int(zone_bounds[2]):
				zi = 2
			elif best >= int(zone_bounds[1]):
				zi = 1
		_material_zones.append(zi)
		var chunk_dist: float = route_dists[best] if best < route_dists.size() else 0.0
		_material_distances_m.append(chunk_dist)
	# Aplicar la distribución espacial continua de inmediato tras asignar distancias.
	if shared_provider != null and shared_provider.get("surface") != null:
		apply_zoned_wetness()
	# Contar para diagnóstico sin oscurecer de golpe todo el mapa.
	print("RALLY_TERRAIN_WETNESS zones assigned materials=", _materials.size())


func set_rain_intensity(value: float) -> void:
	rain_intensity = clampf(value, 0.0, 1.0)


func get_wetness() -> float:
	return wetness


func collect_materials(node: Node) -> void:
	# Solo BaseMaterial3D de la malla base: las láminas de cauce usan
	# ShaderMaterial por instancia (surface override) y no se recolectan,
	# así el rebindeo nunca pisa sus parámetros.
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		for surface_index in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface_index)
			if material is BaseMaterial3D and matches_name(material as BaseMaterial3D):
				register_material(mesh_instance, surface_index, material as BaseMaterial3D)
	for child in node.get_children():
		collect_materials(child)


func matches_name(material: BaseMaterial3D) -> bool:
	var material_name := material.resource_name.to_lower()
	for fragment in WETTABLE_NAME_FRAGMENTS:
		if material_name.contains(fragment):
			return true
	return false


func register_material(mesh_instance: MeshInstance3D, surface_index: int, material: BaseMaterial3D) -> void:
	var mesh_key := "%d_%d" % [mesh_instance.get_instance_id(), material.get_instance_id()]
	if _mesh_material_cache.has(mesh_key):
		var existing: BaseMaterial3D = _mesh_material_cache[mesh_key]
		mesh_instance.set_surface_override_material(surface_index, existing)
		return

	var duplicate := material.duplicate() as BaseMaterial3D
	if duplicate == null:
		return
	_mesh_material_cache[mesh_key] = duplicate
	mesh_instance.set_surface_override_material(surface_index, duplicate)
	_materials.append(duplicate)
	_original_roughness.append(duplicate.roughness)
	_original_albedo.append(duplicate.albedo_color)
	_material_nodes.append(mesh_instance)
	_material_zones.append(0)
	_material_distances_m.append(0.0)


var _visual_elapsed := 0.0
var _last_material_wetness: Dictionary = {}


func _process(delta: float) -> void:
	_visual_elapsed += delta
	if _visual_elapsed < 0.2:
		return
	delta = _visual_elapsed
	_visual_elapsed = 0.0
	if shared_provider != null and shared_provider.get("calendar_active"):
		# Consumidor del proveedor único: no acumula por su cuenta.
		_sync_from_provider()
		return
	if rain_intensity > 0.01:
		wetness = minf(wetness + rain_intensity * rain_accumulation_rate * delta, 1.0)
	else:
		wetness = maxf(wetness - dry_rate * delta, 0.0)
	if absf(wetness - _applied_wetness) < 0.002:
		return
	_applied_wetness = wetness
	apply_wetness()


func _sync_from_provider() -> void:
	if shared_provider == null:
		return
	var snap: Array = shared_provider.surface.snapshot() if shared_provider.surface != null else []
	if snap.size() == 3:
		var changed := false
		for i in 3:
			var w := clampf(float((snap[i] as Dictionary).get("water_mm", 0.0)) / 4.0, 0.0, 1.0)
			if absf(w - zone_wetness[i]) > 0.004:
				changed = true
			zone_wetness[i] = w
		var cz := int(shared_provider.current_zone) if "current_zone" in shared_provider else 0
		current_zone = clampi(cz, 0, 2)
		wetness = zone_wetness[current_zone]
		if changed or _applied_zone_wetness != zone_wetness:
			_applied_zone_wetness = zone_wetness.duplicate(true)
			apply_zoned_wetness()
	else:
		if absf(wetness - _applied_wetness) >= 0.002:
			_applied_wetness = wetness
			apply_wetness()


func apply_zoned_wetness() -> void:
	# Humedad continua por distancia de chunk o por zona según disponibilidad.
	var distance_cache: Dictionary = {}
	var has_surface: bool = shared_provider != null and shared_provider.get("surface") != null
	for index in _materials.size():
		var material := _materials[index]
		if not is_instance_valid(material):
			continue
		var w: float
		if has_surface and index < _material_distances_m.size():
			var dist_m: float = _material_distances_m[index]
			var bucket := floori(dist_m / 25.0)
			if not distance_cache.has(bucket):
				distance_cache[bucket] = shared_provider.surface.blended_state_at_distance(float(bucket) * 25.0 + 12.5)
			var blended: Dictionary = distance_cache[bucket]
			w = clampf(float(blended.get("water_mm", 0.0)) / 4.0, 0.0, 1.0)
		else:
			var zi := int(_material_zones[index]) if index < _material_zones.size() else current_zone
			zi = clampi(zi, 0, zone_wetness.size() - 1)
			w = zone_wetness[zi]
		_apply_to_material(index, material, w)


func _apply_to_material(index: int, material: BaseMaterial3D, w: float) -> void:
	if _last_material_wetness.has(index) and absf(float(_last_material_wetness[index]) - w) < 0.01:
		return
	_last_material_wetness[index] = w
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	var original_roughness: float = _original_roughness[index]
	var target_roughness: float = maxf(original_roughness - maximum_roughness_drop, minimum_roughness)
	material.roughness = lerpf(original_roughness, target_roughness, w)

	# Brillo especular controlado mediante metallic_specular sin alterar specular_mode en runtime
	# (evita recompilación y cambio de variante de pipeline de shader en GPU):
	if material.specular_mode != BaseMaterial3D.SPECULAR_DISABLED:
		material.metallic_specular = lerpf(0.0, 0.42, w) if w > 0.02 else 0.0
	else:
		material.metallic_specular = 0.0

	var original_albedo: Color = _original_albedo[index]
	var dark := lerpf(1.0, 1.0 - maximum_albedo_darkening, w)
	material.albedo_color = Color(
		original_albedo.r * dark,
		original_albedo.g * dark,
		original_albedo.b * dark,
		original_albedo.a
	)


func apply_wetness() -> void:
	for index in _materials.size():
		var material := _materials[index]
		if not is_instance_valid(material):
			continue
		_apply_to_material(index, material, wetness)
