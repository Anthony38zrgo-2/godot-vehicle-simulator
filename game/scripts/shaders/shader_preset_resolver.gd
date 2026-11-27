class_name ShaderPresetResolver
extends RefCounted
## Resolves Data-Driven JSON shader presets, inheritance chains, quality profiles, and vehicle visuals.

const _ShaderRegistry := preload("res://scripts/shaders/shader_registry.gd")

const PRESETS_DIR := "res://data/shaders/presets"
const QUALITY_PROFILES_PATH := "res://data/shaders/visual_quality_profiles.json"
const DIRT_PALETTES_PATH := "res://data/shaders/presets/dirt_palettes.json"

static var _loaded := false
static var _presets: Dictionary = {}
static var _quality_profiles: Dictionary = {}
static var _default_quality_profile := "gt2_clean"
static var _active_quality_profile := ""
static var _dirt_palettes: Dictionary = {}
static var _vehicle_visuals_cache: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_presets.clear()
	_quality_profiles.clear()
	_dirt_palettes.clear()
	_vehicle_visuals_cache.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_presets_dir()
	_load_quality_profiles()
	_load_dirt_palettes()


static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func _load_presets_dir() -> void:
	var dir := DirAccess.open(PRESETS_DIR)
	if dir == null:
		push_error("ShaderPresetResolver: missing presets dir %s" % PRESETS_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var data := _read_json_dict("%s/%s" % [PRESETS_DIR, fname])
			var presets: Variant = data.get("presets", {})
			if presets is Dictionary:
				for preset_id in presets:
					if presets[preset_id] is Dictionary:
						_presets[str(preset_id)] = presets[preset_id]
		fname = dir.get_next()
	dir.list_dir_end()


static func _load_quality_profiles() -> void:
	var data := _read_json_dict(QUALITY_PROFILES_PATH)
	_default_quality_profile = str(data.get("default_profile", "gt2_clean"))
	if _active_quality_profile.is_empty():
		_active_quality_profile = _default_quality_profile
	var profiles: Variant = data.get("profiles", {})
	if profiles is Dictionary:
		_quality_profiles = profiles


static func _load_dirt_palettes() -> void:
	var data := _read_json_dict(DIRT_PALETTES_PATH)
	var palettes: Variant = data.get("palettes", {})
	if palettes is Dictionary:
		_dirt_palettes = palettes


static func list_preset_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key in _presets.keys():
		ids.append(str(key))
	ids.sort()
	return ids


static func has_preset(preset_id: String) -> bool:
	_ensure_loaded()
	return _presets.has(preset_id)


static func set_active_quality_profile(profile_id: String) -> void:
	_ensure_loaded()
	if _quality_profiles.has(profile_id):
		_active_quality_profile = profile_id
	else:
		push_warning("ShaderPresetResolver: unknown visual quality profile '%s'" % profile_id)


static func get_active_quality_profile() -> String:
	_ensure_loaded()
	return _active_quality_profile


static func get_quality_overrides(profile_id: String = "") -> Dictionary:
	_ensure_loaded()
	var pid := profile_id if not profile_id.is_empty() else _active_quality_profile
	var prof: Variant = _quality_profiles.get(pid, {})
	if prof is Dictionary:
		var ov: Variant = prof.get("overrides", {})
		if ov is Dictionary:
			return ov
	return {}


static func resolve_preset(preset_id: String, apply_quality_profile: bool = false) -> Dictionary:
	_ensure_loaded()
	if not _presets.has(preset_id):
		push_error("ShaderPresetResolver: unknown preset_id '%s'" % preset_id)
		return {}
	var chain: Array[Dictionary] = []
	var visited := {}
	var cursor := preset_id
	while not cursor.is_empty():
		if visited.has(cursor):
			push_error("ShaderPresetResolver: inheritance cycle detected at '%s'" % cursor)
			break
		visited[cursor] = true
		var entry: Dictionary = _presets.get(cursor, {})
		if entry.is_empty():
			push_error("ShaderPresetResolver: missing parent preset '%s'" % cursor)
			break
		chain.push_front(entry)
		cursor = str(entry.get("extends", ""))

	var shader_id := ""
	var merged_params := {}
	for entry in chain:
		var sid := str(entry.get("shader_id", ""))
		if not sid.is_empty():
			shader_id = sid
		var p: Variant = entry.get("params", {})
		if p is Dictionary:
			for k in p:
				merged_params[str(k)] = p[k]

	if apply_quality_profile and not shader_id.is_empty():
		var schema := _ShaderRegistry.get_shader_uniforms(shader_id)
		var q_ov := get_quality_overrides()
		for k in q_ov:
			if schema.has(str(k)):
				merged_params[str(k)] = q_ov[k]

	return {
		"preset_id": preset_id,
		"shader_id": shader_id,
		"params": merged_params,
	}


static func get_dirt_palette(palette_id: String = "andean_default") -> Dictionary:
	_ensure_loaded()
	var raw: Variant = _dirt_palettes.get(palette_id, _dirt_palettes.get("andean_default", {}))
	return raw.duplicate(true) if raw is Dictionary else {}


static func load_vehicle_visuals(vehicle_id: String) -> Dictionary:
	if _vehicle_visuals_cache.has(vehicle_id):
		return _vehicle_visuals_cache[vehicle_id]
	var candidates := [
		"res://data/vehicles/rt/%s/visuals.json" % vehicle_id,
		"res://data/vehicles/%s/visuals.json" % vehicle_id,
	]
	var result := {}
	for path in candidates:
		if FileAccess.file_exists(path):
			result = _read_json_dict(path)
			break
	_vehicle_visuals_cache[vehicle_id] = result
	return result


static func coerce_value_for_uniform(value: Variant, uniform_entry: Dictionary) -> Variant:
	var target_type := int(uniform_entry.get("type", TYPE_NIL))
	return coerce_value_to_type(value, target_type)


static func coerce_value_to_type(value: Variant, target_type: int) -> Variant:
	if value is String and target_type == TYPE_COLOR:
		return Color.html(value)
	if value is Array:
		var arr := value as Array
		match target_type:
			TYPE_COLOR:
				if arr.size() >= 4:
					return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
				if arr.size() == 3:
					return Color(float(arr[0]), float(arr[1]), float(arr[2]), 1.0)
			TYPE_VECTOR4:
				if arr.size() >= 4:
					return Vector4(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
			TYPE_VECTOR3:
				if arr.size() >= 3:
					return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
			TYPE_VECTOR2:
				if arr.size() >= 2:
					return Vector2(float(arr[0]), float(arr[1]))
	if target_type == TYPE_INT and (value is float or value is int):
		return int(value)
	if target_type == TYPE_FLOAT and (value is int or value is float):
		return float(value)
	if target_type == TYPE_BOOL and (value is bool or value is int or value is float):
		return bool(value)
	return value
