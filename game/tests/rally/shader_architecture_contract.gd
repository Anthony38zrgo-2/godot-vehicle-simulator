extends SceneTree
## Contract test verifying SOLID shader organization, compilation, Data-Driven JSON presets,
## global shader uniforms, and Mobile renderer instance-uniform budget.

const ShaderRegistry := preload("res://scripts/shaders/shader_registry.gd")
const ShaderPresetResolver := preload("res://scripts/shaders/shader_preset_resolver.gd")
const ShaderMaterialFactory := preload("res://scripts/shaders/shader_material_factory.gd")
const ShaderEnvironmentBus := preload("res://scripts/shaders/shader_environment_bus.gd")

const EXPECTED_GLOBALS := [
	&"rally_sun_dir",
	&"rally_sun_color",
	&"rally_ambient_color",
	&"rally_haze_color",
	&"rally_wind_vec",
	&"rally_rain_intensity",
	&"rally_sky_horizon",
	&"rally_sky_mix",
	&"rally_sky_tint_a",
	&"rally_sky_tint_b",
	&"rally_sky_tint_c",
	&"rally_sky_enabled",
]


func _initialize() -> void:
	var errors: Array[String] = []

	# 1. Registry completeness & shader compilation
	var shader_ids := ShaderRegistry.list_shader_ids()
	if shader_ids.is_empty():
		errors.append("ShaderRegistry is empty")
	for sid in shader_ids:
		var path := ShaderRegistry.get_shader_path(sid)
		if not path.begins_with("res://shaders/"):
			errors.append("Shader '%s' is outside res://shaders/: %s" % [sid, path])
			continue
		var shader := ShaderRegistry.get_shader(sid)
		if shader == null:
			errors.append("Failed to load shader '%s' at %s" % [sid, path])
			continue
		var rid := shader.get_rid()
		if not rid.is_valid():
			errors.append("Shader '%s' produced invalid RID" % sid)

	# 2. JSON preset validation & ShaderMaterialFactory instantiation
	var preset_ids := ShaderPresetResolver.list_preset_ids()
	if preset_ids.is_empty():
		errors.append("ShaderPresetResolver found zero presets")
	for pid in preset_ids:
		var resolved := ShaderPresetResolver.resolve_preset(pid, false)
		var sid := str(resolved.get("shader_id", ""))
		if sid.is_empty() or not ShaderRegistry.has_shader(sid):
			errors.append("Preset '%s' references unknown shader_id '%s'" % [pid, sid])
			continue
		var schema := ShaderRegistry.get_shader_uniforms(sid)
		var params: Dictionary = resolved.get("params", {})
		for uname in params:
			if not schema.has(str(uname)):
				errors.append("Preset '%s' sets unknown uniform '%s' on shader '%s'" % [pid, uname, sid])
		var mat := ShaderMaterialFactory.create_from_preset(pid, {}, true)
		if mat == null or mat.shader == null:
			errors.append("ShaderMaterialFactory failed for preset '%s'" % pid)

	# 3. Vehicle-specific Data-Driven visuals config (Lancia Stratos)
	var stratos_vis := ShaderPresetResolver.load_vehicle_visuals("rt-lancia-stratos")
	if stratos_vis.is_empty():
		errors.append("Missing res://data/vehicles/rt/rt-lancia-stratos/visuals.json")
	else:
		var louver_cfg: Dictionary = stratos_vis.get("louver", {})
		var louver_sid := str(louver_cfg.get("shader_id", ""))
		if louver_sid != "vehicle.louver" or not ShaderRegistry.has_shader(louver_sid):
			errors.append("Stratos visuals.json louver.shader_id invalid: '%s'" % louver_sid)
		var stratos_mat := ShaderMaterialFactory.create_from_preset(
			"vehicle.toon.lancia_stratos_body",
			stratos_vis.get("banded_paint", {})
		)
		if stratos_mat == null:
			errors.append("Failed to build Stratos body material from visuals.json")

	# 4. Global shader uniforms declared in project.godot
	for req_g in EXPECTED_GLOBALS:
		if not ProjectSettings.has_setting("shader_globals/" + String(req_g)):
			errors.append("Missing global shader parameter in project.godot: %s" % req_g)
	ShaderEnvironmentBus.update_weather(Vector2(1.5, -0.5), 0.25)

	# 5. Godot Mobile renderer limits instance uniforms to 16 per shader
	var dirt_text := FileAccess.get_file_as_string("res://shaders/lib/vehicle/dirt_overlay.gdshaderinc")
	var inst_count := 0
	for line in dirt_text.split("\n"):
		if line.strip_edges().begins_with("instance uniform "):
			inst_count += 1
	if inst_count > 16:
		errors.append("dirt_overlay.gdshaderinc exceeds 16 instance uniforms (%d)" % inst_count)

	# 6. No dead spherical reflection varyings in vehicle_gt2.gdshader
	var gt2_text := FileAccess.get_file_as_string("res://shaders/vehicle/vehicle_gt2.gdshader")
	for dead_sym in ["v_env_uv", "v_fresnel", "v_sky_facing"]:
		if gt2_text.contains(dead_sym):
			errors.append("Dead spherical reflection symbol '%s' still present in vehicle_gt2.gdshader" % dead_sym)

	# 7. Zero legacy/orphan shaders outside res://shaders/ and res://addons/ or directly in res://shaders/ root
	_scan_stray_shaders("res://", errors)
	var shaders_root := DirAccess.open("res://shaders")
	if shaders_root != null:
		shaders_root.list_dir_begin()
		var item := shaders_root.get_next()
		while not item.is_empty():
			if not shaders_root.current_is_dir() and (item.ends_with(".gdshader") or item.ends_with(".gdshaderinc")):
				errors.append("Root-level uncategorized shader in res://shaders/: %s" % item)
			elif shaders_root.current_is_dir() and item == "soft-toon-godot-shader-free-shader":
				errors.append("Orphan shader directory still exists: res://shaders/%s" % item)
			item = shaders_root.get_next()
		shaders_root.list_dir_end()

	if errors.is_empty():
		print("PASS: shader_architecture_contract (%d shaders, %d presets)" % [shader_ids.size(), preset_ids.size()])
		quit(0)
	else:
		for e in errors:
			push_error(e)
		print("FAIL: shader_architecture_contract (%d errors)" % errors.size())
		quit(1)


func _scan_stray_shaders(path: String, errors: Array[String]) -> void:
	if path.begins_with("res://shaders") or path.begins_with("res://addons") or path.begins_with("res://.godot"):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := (path + name) if path.ends_with("/") else (path + "/" + name)
		if dir.current_is_dir():
			_scan_stray_shaders(full, errors)
		elif name.ends_with(".gdshader") or name.ends_with(".gdshaderinc"):
			errors.append("Loose shader outside res://shaders/: %s" % full)
		name = dir.get_next()
	dir.list_dir_end()
