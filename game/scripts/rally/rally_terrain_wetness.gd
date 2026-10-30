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

var _materials: Array[BaseMaterial3D] = []
var _original_roughness: Array[float] = []
var _original_albedo: Array[Color] = []
var _applied_wetness: float = -1.0


func _ready() -> void:
	if visual_root != null:
		collect_materials(visual_root)
	print("RALLY_TERRAIN_WETNESS materials=", _materials.size())


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


func _process(delta: float) -> void:
	if rain_intensity > 0.01:
		wetness = minf(wetness + rain_intensity * rain_accumulation_rate * delta, 1.0)
	else:
		wetness = maxf(wetness - dry_rate * delta, 0.0)
	if absf(wetness - _applied_wetness) < 0.002:
		return
	_applied_wetness = wetness
	apply_wetness()


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
