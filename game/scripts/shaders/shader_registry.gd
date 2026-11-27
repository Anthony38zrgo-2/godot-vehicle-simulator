class_name ShaderRegistry
extends RefCounted
## Single-responsibility loader and cache for logical shader_id -> Shader resources and uniform schemas.

const REGISTRY_PATH := "res://data/shaders/shader_registry.json"

static var _loaded := false
static var _paths: Dictionary = {}
static var _shaders: Dictionary = {}
static var _uniform_schemas: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_paths.clear()
	_shaders.clear()
	_uniform_schemas.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(REGISTRY_PATH):
		push_error("ShaderRegistry: missing registry JSON at %s" % REGISTRY_PATH)
		return
	var text := FileAccess.get_file_as_string(REGISTRY_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("ShaderRegistry: invalid JSON in %s" % REGISTRY_PATH)
		return
	var shaders_dict: Variant = parsed.get("shaders", {})
	if not (shaders_dict is Dictionary):
		push_error("ShaderRegistry: 'shaders' must be a JSON object")
		return
	for key in shaders_dict:
		var path := str(shaders_dict[key])
		if not path.is_empty():
			_paths[str(key)] = path


static func list_shader_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key in _paths.keys():
		ids.append(str(key))
	ids.sort()
	return ids


static func has_shader(shader_id: String) -> bool:
	_ensure_loaded()
	return _paths.has(shader_id)


static func get_shader_path(shader_id: String) -> String:
	_ensure_loaded()
	return str(_paths.get(shader_id, ""))


static func get_shader(shader_id: String) -> Shader:
	_ensure_loaded()
	if _shaders.has(shader_id):
		return _shaders[shader_id] as Shader
	var path := get_shader_path(shader_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("ShaderRegistry: shader_id '%s' path not found: '%s'" % [shader_id, path])
		return null
	var shader := load(path) as Shader
	if shader == null:
		push_error("ShaderRegistry: failed to load Shader resource for '%s' at '%s'" % [shader_id, path])
		return null
	_shaders[shader_id] = shader
	return shader


static func get_shader_uniforms(shader_id: String) -> Dictionary:
	_ensure_loaded()
	if _uniform_schemas.has(shader_id):
		return _uniform_schemas[shader_id]
	var shader := get_shader(shader_id)
	var schema := {}
	if shader != null:
		for entry in shader.get_shader_uniform_list():
			if entry is Dictionary and entry.has("name"):
				schema[str(entry["name"])] = entry
	_uniform_schemas[shader_id] = schema
	return schema


static func has_uniform(shader_id: String, uniform_name: String) -> bool:
	return get_shader_uniforms(shader_id).has(uniform_name)
