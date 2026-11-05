extends Node3D

const EXTERIOR_GLASS := preload("res://scripts/rally/rally_escort_exterior_glass.gdshader")
const DAMAGE_MESHES := preload("res://assets/rally/ford_escort_rs2000_1971/damage/escort_damage.glb")
const BROKEN_LIGHT := preload("res://assets/rally/ford_escort_rs2000_1971/damage/lights_damaged.png")
const BROKEN_GLASS := preload("res://assets/rally/ford_escort_rs2000_1971/damage/windows_damaged.png")
const BROKEN_GLASS_INSIDE := preload("res://assets/rally/ford_escort_rs2000_1971/damage/interior_windows_damaged.png")

const MESH_DAMAGE := {"body": "body", "hood": "hood", "trunk": "trunk", "interior": "windshield"}

var headlights_requested := false

@onready var _headlights := {"headlight_left": $HeadlightLeft, "headlight_right": $HeadlightRight}

var _healthy: Dictionary = {}
var _damaged: Dictionary = {}
var _surfaces: Dictionary = {}
var _broken: Dictionary = {}
var _dirty := false
var _cockpit_view := false
var _exterior_windows: Array[Dictionary] = []


func _ready() -> void:
	var chassis := get_node("../Chassis")
	var variants := DAMAGE_MESHES.instantiate() as Node3D
	add_child(variants)
	for part in MESH_DAMAGE:
		var source_name: String = "interior_hi" if part == "interior" else part
		var clean := chassis.find_child(source_name, true, false) as MeshInstance3D
		var crash := variants.find_child(part + "_crash_mesh", true, false) as MeshInstance3D
		crash.hide()
		_healthy[part] = clean
		_damaged[part] = crash
		_bind_part(part, clean, crash)
	_update_exterior_glass()


func _bind_part(part: String, clean: MeshInstance3D, crash: MeshInstance3D) -> void:
	var materials: Dictionary = {}
	for i in clean.mesh.get_surface_count():
		var material := clean.get_active_material(i)
		materials[material.resource_name] = material
		if part == "body":
			_bind_exterior_surface(clean, i, material)
	for i in crash.mesh.get_surface_count():
		var name := crash.mesh.surface_get_material(i).resource_name.trim_suffix(".001")
		var source_name := "windows" if name == "windshield_interior" else name
		var material: Material = materials.get(source_name)
		assert(material != null, "Missing original Escort material: " + source_name)
		crash.set_surface_override_material(i, material)
		if name == "windshield_interior":
			_bind_surface("windshield", crash, i, material, BROKEN_GLASS_INSIDE)
		elif part == "body":
			_bind_exterior_surface(crash, i, material)


func _bind_exterior_surface(mesh: MeshInstance3D, surface: int, material: Material) -> void:
	match material.resource_name:
		"#E1 headlight_left":
			_bind_surface("headlight_left", mesh, surface, material, BROKEN_LIGHT)
		"#E1 headlight_right":
			_bind_surface("headlight_right", mesh, surface, material, BROKEN_LIGHT)
		"#E1 window front", "#E1 window leftside", "#E1 window rightside", "#E1 window back":
			var glass := material as StandardMaterial3D
			var binding := {
				"mesh": mesh,
				"surface": surface,
				"original": mesh.get_surface_override_material(surface),
				"tinted": _make_tinted_glass(glass.albedo_texture, false),
			}
			if material.resource_name == "#E1 window front":
				var cracked := glass.duplicate() as StandardMaterial3D
				cracked.albedo_texture = BROKEN_GLASS
				binding["cracked"] = cracked
				binding["tinted_cracked"] = _make_tinted_glass(BROKEN_GLASS, true)
			_exterior_windows.append(binding)


func _make_tinted_glass(texture: Texture2D, cracked: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = EXTERIOR_GLASS
	material.set_shader_parameter("glass_texture", texture)
	material.set_shader_parameter("cracked", cracked)
	return material


func set_cockpit_view(enabled: bool) -> void:
	if _cockpit_view != enabled:
		_cockpit_view = enabled
		_update_exterior_glass()


func _update_exterior_glass() -> void:
	for binding in _exterior_windows:
		var cracked: bool = _broken.has("windshield") and binding.has("cracked")
		var key := "cracked" if cracked else "original"
		if not _cockpit_view:
			key = "tinted_cracked" if cracked else "tinted"
		binding.mesh.set_surface_override_material(binding.surface, binding[key])


func _bind_surface(part: String, mesh: MeshInstance3D, surface: int, original: StandardMaterial3D, texture: Texture2D) -> void:
	var broken := original.duplicate() as StandardMaterial3D
	broken.albedo_texture = texture
	var binding := {"mesh": mesh, "surface": surface, "material": broken}
	if _headlights.has(part):
		broken.emission_enabled = false
		var lit := original.duplicate() as StandardMaterial3D
		lit.emission_enabled = true
		lit.emission = Color(1.0, 0.90, 0.73)
		lit.emission_energy_multiplier = 1.6
		binding["lit"] = lit
		binding["off"] = mesh.get_surface_override_material(surface)
	if not _surfaces.has(part):
		_surfaces[part] = []
	_surfaces[part].append(binding)


func set_headlights_requested(enabled: bool) -> void:
	if headlights_requested != enabled:
		headlights_requested = enabled
		_dirty = true


func register_impact(point: Vector3, normal: Vector3, severity: float, config: Dictionary) -> void:
	if config.is_empty():
		return
	var front := point.z < -1.25 and normal.z > 0.35
	var roof := point.y > 0.92 and normal.y < -0.35
	if front:
		if absf(point.x) >= 0.25 and point.y > 0.25 and point.y < 0.8:
			var lamp := "headlight_left" if point.x < 0.0 else "headlight_right"
			_mark_broken(lamp, severity, config)
		_mark_broken("hood", severity, config)
	var hard_front := front and severity >= float(config.get("windshield_frontal", 0.55))
	if hard_front or roof or (point.y > 0.78 and point.z < -0.20 and normal.z > 0.35):
		_mark_broken("windshield", severity, config)
	if point.z > 1.25 and normal.z < -0.35:
		_mark_broken("trunk", severity, config)
	_mark_broken("body", severity, config)


func _mark_broken(part: String, severity: float, config: Dictionary) -> void:
	var threshold_key := "headlight" if part.begins_with("headlight") else part
	if severity >= float(config.get(threshold_key, INF)) and not _broken.has(part):
		_broken[part] = true
		_dirty = true


func _process(_delta: float) -> void:
	if not _dirty:
		return
	_dirty = false
	_update_exterior_glass()
	for part in MESH_DAMAGE:
		var damaged := _broken.has(MESH_DAMAGE[part])
		_healthy[part].visible = not damaged
		_damaged[part].visible = damaged
	for part in _broken:
		if not _headlights.has(part):
			for binding in _surfaces.get(part, []):
				binding.mesh.set_surface_override_material(binding.surface, binding.material)
	for part in _headlights:
		var broken := _broken.has(part)
		var lit := headlights_requested and not broken
		_headlights[part].visible = lit
		for binding in _surfaces.get(part, []):
			var material: Material = binding.material if broken else (binding.lit if lit else binding.off)
			binding.mesh.set_surface_override_material(binding.surface, material)
