class_name RallyTerrainWetness
extends Node

## Humedad del terreno propia del proyecto.
## TCA aporta la lluvia (intensidad y duracion); esta clase acumula, seca y aplica
## el efecto visual sobre los materiales de la pista.

const WETTABLE_NAME_FRAGMENTS := ["road", "gravel", "terrain"]

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
var _material_nodes: Array[MeshInstance3D] = []
var _applied_zone_wetness: Array[float] = [-1.0, -1.0, -1.0]


func _ready() -> void:
	bind_visual_root(visual_root)
	print("RALLY_TERRAIN_WETNESS materials=", _materials.size())

func bind_visual_root(new_root: Node3D) -> void:
	_materials.clear()
	_original_roughness.clear()
	_original_albedo.clear()
	_material_zones.clear()
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
	# Máscara espacial por instancia de chunk: cada material duplicado ya es
	# por instancia (no se modifican compartidos entre zonas).
	_material_zones.clear()
	for n in _material_nodes.size():
		var node := _material_nodes[n]
		if node == null or not is_instance_valid(node):
			_material_zones.append(0)
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
	# Contar para diagnóstico sin oscurecer de golpe todo el mapa.
	print("RALLY_TERRAIN_WETNESS zones assigned materials=", _materials.size())


func set_rain_intensity(value: float) -> void:
	rain_intensity = clampf(value, 0.0, 1.0)


func get_wetness() -> float:
	return wetness


func collect_materials(node: Node) -> void:
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
	var duplicate := material.duplicate() as BaseMaterial3D
	if duplicate == null:
		return
	mesh_instance.set_surface_override_material(surface_index, duplicate)
	_materials.append(duplicate)
	_original_roughness.append(duplicate.roughness)
	_original_albedo.append(duplicate.albedo_color)
	_material_nodes.append(mesh_instance)
	_material_zones.append(0)


func _process(delta: float) -> void:
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
	# Humedad por zona sin oscurecer de golpe todo el mapa.
	for index in _materials.size():
		var material := _materials[index]
		if not is_instance_valid(material):
			continue
		var zi := int(_material_zones[index]) if index < _material_zones.size() else current_zone
		zi = clampi(zi, 0, zone_wetness.size() - 1)
		_apply_to_material(index, material, zone_wetness[zi])


func _apply_to_material(index: int, material: BaseMaterial3D, w: float) -> void:
	var original_roughness: float = _original_roughness[index]
	var target_roughness: float = maxf(original_roughness - maximum_roughness_drop, minimum_roughness)
	material.roughness = lerpf(original_roughness, target_roughness, w)
	var original_albedo: Color = _original_albedo[index]
	var darkening := lerpf(1.0, 1.0 - maximum_albedo_darkening, w)
	material.albedo_color = Color(
		original_albedo.r * darkening,
		original_albedo.g * darkening,
		original_albedo.b * darkening,
		original_albedo.a
	)


func apply_wetness() -> void:
	for index in _materials.size():
		var material := _materials[index]
		if not is_instance_valid(material):
			continue
		var original_roughness: float = _original_roughness[index]
		var target_roughness: float = maxf(original_roughness - maximum_roughness_drop, minimum_roughness)
		material.roughness = lerpf(original_roughness, target_roughness, wetness)
		var original_albedo: Color = _original_albedo[index]
		var darkening := lerpf(1.0, 1.0 - maximum_albedo_darkening, wetness)
		material.albedo_color = Color(
			original_albedo.r * darkening,
			original_albedo.g * darkening,
			original_albedo.b * darkening,
			original_albedo.a
		)
