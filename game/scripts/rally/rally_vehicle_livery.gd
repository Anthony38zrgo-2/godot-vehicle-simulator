class_name RallyVehicleLivery
extends RefCounted
## Catálogo oficial de 16 liveries PSX (receta Porsche 911 stylized_shadow_dither_psx_v1)
## y servicio de horneado offscreen de 1 sola pasada a ImageTexture (RGB8 + mipmaps)
## para coste 0 de shader de livery por frame durante el renderizado 3D.

const CATALOG_PATH := "res://data/vehicles/liveries.json"
const DEFAULT_LIVERY_ID := "rojo_brillante"
const BAKE_SHADER := preload("res://scripts/rally/rally_livery_bake.gdshader")
const MAX_BAKED_CACHE := 4

static var _catalog_cache: Dictionary = {}
static var _data_map_cache: Dictionary = {}
static var _baked_cache: Dictionary = {}
static var _baked_order: Array[String] = []
static var _request_seq: int = 0


static func load_catalog(force_reload: bool = false) -> Dictionary:
	if not force_reload and not _catalog_cache.is_empty():
		return _catalog_cache
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("RallyVehicleLivery: no se encontró el catálogo en " + CATALOG_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if parsed is Dictionary:
		_catalog_cache = parsed
		return _catalog_cache
	push_warning("RallyVehicleLivery: catálogo JSON inválido en " + CATALOG_PATH)
	return {}


static func get_liveries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cat := load_catalog()
	var raw: Variant = cat.get("liveries", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				out.append(item)
	return out


static func get_livery(livery_id: String) -> Dictionary:
	var wanted := livery_id.strip_edges().to_lower()
	for entry in get_liveries():
		if str(entry.get("id", "")).to_lower() == wanted:
			return entry
	return {}


static func is_valid_livery(livery_id: String) -> bool:
	return not get_livery(livery_id).is_empty()


static func get_vehicle_config(car_key: String) -> Dictionary:
	var cat := load_catalog()
	var vehicles: Variant = cat.get("vehicles", {})
	if vehicles is Dictionary and vehicles.has(car_key):
		var cfg: Variant = vehicles[car_key]
		if cfg is Dictionary:
			return cfg
	return {}


static func default_livery_for(car_key: String) -> String:
	var cfg := get_vehicle_config(car_key)
	var def_id := str(cfg.get("default_livery", "")).strip_edges().to_lower()
	if not def_id.is_empty() and is_valid_livery(def_id):
		return def_id
	var all := get_liveries()
	if not all.is_empty():
		return str(all[0].get("id", DEFAULT_LIVERY_ID))
	return DEFAULT_LIVERY_ID


static func resolve_car_key_from_vehicle(vehicle: Node) -> String:
	if vehicle == null:
		return ""
	var profile_path := str(vehicle.get("rally_profile_path")).strip_edges().to_lower()
	var manifest_path := str(vehicle.get("asset_manifest_path")).strip_edges().to_lower()
	var reg_path := "res://data/vehicles/registry.json"
	if FileAccess.file_exists(reg_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(reg_path))
		if parsed is Dictionary:
			var vehicles: Dictionary = parsed.get("vehicles", {})
			for key in vehicles:
				var v: Dictionary = vehicles[key]
				var prof := str(v.get("Profile", "")).to_lower()
				var assets := str(v.get("Assets", "")).to_lower()
				if (not prof.is_empty() and profile_path.contains("/%s/" % prof)) \
						or (not assets.is_empty() and manifest_path.contains("/%s/" % assets)):
					return str(key)
	return ""


static func clear_data_map_cache() -> void:
	_data_map_cache.clear()


static func clear_caches() -> void:
	_data_map_cache.clear()
	_baked_cache.clear()
	_baked_order.clear()


static func _load_data_map(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _data_map_cache.has(path):
		return _data_map_cache[path] as Texture2D
	# Mantener acotado el caché de mapas fuente (máximo 2 vehículos a la vez)
	if _data_map_cache.size() >= 2:
		_data_map_cache.clear()
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		_data_map_cache[path] = tex
	return tex


static func _cache_baked(cache_key: String, tex: ImageTexture) -> void:
	if tex == null:
		return
	_baked_cache[cache_key] = tex
	_baked_order.erase(cache_key)
	_baked_order.append(cache_key)
	while _baked_order.size() > MAX_BAKED_CACHE:
		var oldest: String = _baked_order.pop_front()
		_baked_cache.erase(oldest)


static func build_shader_params(car_key: String, livery_id: String) -> Dictionary:
	var resolved_id := livery_id.strip_edges().to_lower()
	if resolved_id.is_empty() or not is_valid_livery(resolved_id):
		resolved_id = default_livery_for(car_key)
	var livery := get_livery(resolved_id)
	if livery.is_empty():
		return {"enabled": false}

	var vcfg := get_vehicle_config(car_key)
	var hex_str := str(livery.get("hex", "#D51E22"))
	var col := Color.from_string(hex_str, Color("#D51E22"))
	var st_arr: Array = livery.get("shadow_tint", [44, 14, 54])
	var st_vec := Vector3(
		float(st_arr[0]) / 255.0 if st_arr.size() > 0 else 0.17,
		float(st_arr[1]) / 255.0 if st_arr.size() > 1 else 0.055,
		float(st_arr[2]) / 255.0 if st_arr.size() > 2 else 0.21
	)
	var dir_from_arr: Array = livery.get("dir_from", [-0.50, 0.88])
	var baked_ao_only := bool(vcfg.get("baked_ao_only", false))
	var dir_to_arr: Array = [1.0, 1.0] if baked_ao_only else livery.get("dir_to", [0.64, 1.0])
	var band_arr: Array = livery.get("shadow_band", [0.56, 0.96])
	var eff_arr: Array = vcfg.get("effective_res", [512, 512])

	# Detalles únicos (p. ej. franja verde del Lotus Cortina): se preservan en su livery original
	# (mask_threshold = 0.80 excluye canal R=0.60) y se pintan sólidos en el resto (threshold = 0.30).
	var preserve_on := str(vcfg.get("preserve_accent_on_livery", "")).strip_edges().to_lower()
	var mask_threshold := 0.80 if (not preserve_on.is_empty() and resolved_id == preserve_on) else 0.30

	var data_map_path := str(vcfg.get("data_map", ""))
	var data_tex := _load_data_map(data_map_path)

	return {
		"enabled": true,
		"car_key": car_key,
		"livery_id": resolved_id,
		"hex": hex_str,
		"materials": vcfg.get("materials", []),
		"color_srgb": Vector3(col.r, col.g, col.b),
		"shadow_tint_srgb": st_vec,
		"shadow_tint_strength": 0.0 if baked_ao_only else float(livery.get("shadow_tint_strength", 0.40)),
		"ao_strength": float(livery.get("ao_strength", 0.52)),
		"dir_from": Vector2(float(dir_from_arr[0]), float(dir_from_arr[1])),
		"dir_to": Vector2(float(dir_to_arr[0]), float(dir_to_arr[1])),
		"shadow_gamma": float(livery.get("shadow_gamma", 1.08)),
		"saturation": 1.0 if baked_ao_only else float(livery.get("saturation", 1.04)),
		"dither_base": float(livery.get("dither_base", 0.0)),
		"dither_shadow_boost": float(livery.get("dither_shadow_boost", 0.86)),
		"shadow_band": Vector2(float(band_arr[0]), float(band_arr[1])),
		"dither_dark_floor": float(livery.get("dither_dark_floor", 0.45)),
		"effective_res": Vector2(float(eff_arr[0]), float(eff_arr[1])),
		"paint_rgb555": bool(vcfg.get("paint_rgb555", true)),
		"mask_threshold": mask_threshold,
		"data_map": data_tex,
	}


static func _assign_baked_texture(mats: Array, tex: Texture2D) -> void:
	if tex == null:
		return
	for m in mats:
		var sm := m as ShaderMaterial
		if sm == null or not is_instance_valid(sm):
			continue
		if bool(sm.get_shader_parameter("use_pixel_albedo")):
			sm.set_shader_parameter("pixel_albedo", tex)
		else:
			sm.set_shader_parameter("base_texture", tex)


static func bake_and_apply(tree: SceneTree, mats: Array, params: Dictionary) -> void:
	if mats.is_empty():
		return
	var car_key := str(params.get("car_key", ""))
	var livery_id := str(params.get("livery_id", ""))
	var hex_str := str(params.get("hex", ""))
	var col_srgb: Vector3 = params.get("color_srgb", Vector3.ONE)
	_request_seq += 1
	var req_id := _request_seq

	for m in mats:
		var sm := m as ShaderMaterial
		if sm == null:
			continue
		sm.set_meta("livery_enabled", true)
		sm.set_meta("livery_id", livery_id)
		sm.set_meta("livery_hex", hex_str)
		sm.set_meta("livery_color_srgb", col_srgb)
		sm.set_meta("livery_request_id", req_id)

	var cache_key := "%s::%s::%.2f" % [car_key, livery_id, float(params.get("mask_threshold", 0.30))]
	if _baked_cache.has(cache_key):
		var cached := _baked_cache[cache_key] as Texture2D
		if cached != null:
			_assign_baked_texture(mats, cached)
			return

	# En modo headless no existe renderizador GPU para leer el SubViewport
	if tree == null or tree.root == null or DisplayServer.get_name().to_lower() == "headless":
		return

	var first_sm := mats[0] as ShaderMaterial
	var orig_tex: Texture2D = null
	if first_sm != null and first_sm.has_meta("original_albedo_texture"):
		orig_tex = first_sm.get_meta("original_albedo_texture") as Texture2D
	var data_tex := params.get("data_map", null) as Texture2D
	var bake_size := Vector2i(512, 512)
	if data_tex != null:
		bake_size = Vector2i(maxi(data_tex.get_width(), 64), maxi(data_tex.get_height(), 64))
	elif orig_tex != null:
		bake_size = Vector2i(maxi(orig_tex.get_width(), 64), maxi(orig_tex.get_height(), 64))

	# Menu previews can request the first bake while the root is adding its children.
	_run_gpu_bake.call_deferred(tree, mats, orig_tex, params, bake_size, cache_key, req_id)


static func _run_gpu_bake(
	tree: SceneTree,
	mats: Array,
	orig_tex: Texture2D,
	params: Dictionary,
	bake_size: Vector2i,
	cache_key: String,
	req_id: int
) -> void:
	if not is_instance_valid(tree) or tree.root == null:
		return
	var vp := SubViewport.new()
	vp.name = "_LiveryBakeVP_%d" % req_id
	vp.size = bake_size
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	var rect := ColorRect.new()
	rect.position = Vector2.ZERO
	rect.size = Vector2(bake_size)
	var bmat := ShaderMaterial.new()
	bmat.shader = BAKE_SHADER
	if orig_tex != null:
		bmat.set_shader_parameter("orig_tex", orig_tex)
	var data_tex := params.get("data_map", null) as Texture2D
	bmat.set_shader_parameter("use_livery_data_map", data_tex != null)
	if data_tex != null:
		bmat.set_shader_parameter("livery_data_map", data_tex)
	bmat.set_shader_parameter("livery_color_srgb", params.get("color_srgb", Vector3.ONE))
	bmat.set_shader_parameter("livery_shadow_tint_srgb", params.get("shadow_tint_srgb", Vector3(0.17, 0.055, 0.21)))
	bmat.set_shader_parameter("livery_shadow_tint_strength", float(params.get("shadow_tint_strength", 0.40)))
	bmat.set_shader_parameter("livery_ao_strength", float(params.get("ao_strength", 0.52)))
	bmat.set_shader_parameter("livery_dir_from", params.get("dir_from", Vector2(-0.50, 0.88)))
	bmat.set_shader_parameter("livery_dir_to", params.get("dir_to", Vector2(0.64, 1.0)))
	bmat.set_shader_parameter("livery_shadow_gamma", float(params.get("shadow_gamma", 1.08)))
	bmat.set_shader_parameter("livery_saturation", float(params.get("saturation", 1.04)))
	bmat.set_shader_parameter("livery_dither_base", float(params.get("dither_base", 0.0)))
	bmat.set_shader_parameter("livery_dither_shadow_boost", float(params.get("dither_shadow_boost", 0.86)))
	bmat.set_shader_parameter("livery_shadow_band", params.get("shadow_band", Vector2(0.56, 0.96)))
	bmat.set_shader_parameter("livery_dither_dark_floor", float(params.get("dither_dark_floor", 0.45)))
	bmat.set_shader_parameter("livery_effective_res", params.get("effective_res", Vector2(512.0, 512.0)))
	bmat.set_shader_parameter("livery_paint_rgb555", bool(params.get("paint_rgb555", true)))
	bmat.set_shader_parameter("livery_mask_threshold", float(params.get("mask_threshold", 0.30)))
	rect.material = bmat
	vp.add_child(rect)
	tree.root.add_child(vp)

	await tree.process_frame
	await RenderingServer.frame_post_draw

	var baked_tex: ImageTexture = null
	if is_instance_valid(vp) and vp.get_texture() != null:
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGB8)
			img.generate_mipmaps()
			baked_tex = ImageTexture.create_from_image(img)
			_cache_baked(cache_key, baked_tex)

	if is_instance_valid(vp):
		vp.queue_free()

	if baked_tex == null:
		return

	# Aplicar solo a materiales que sigan esperando esta petición (evita flicker en clics rápidos)
	var live_mats: Array = []
	for m in mats:
		var sm := m as ShaderMaterial
		if sm != null and is_instance_valid(sm) and int(sm.get_meta("livery_request_id", -1)) == req_id:
			live_mats.append(sm)
	if not live_mats.is_empty():
		_assign_baked_texture(live_mats, baked_tex)


static func apply_to_vehicle(vehicle_node: Node, car_key: String, livery_id: String) -> int:
	if vehicle_node == null:
		return 0
	var resolved_key := car_key.strip_edges()
	if resolved_key.is_empty():
		resolved_key = resolve_car_key_from_vehicle(vehicle_node)
	var params := build_shader_params(resolved_key, livery_id)
	if not bool(params.get("enabled", false)):
		return 0
	var chassis := vehicle_node.get_node_or_null("Chassis")
	if chassis != null and chassis.has_method("apply_livery_parameters"):
		return int(chassis.call("apply_livery_parameters", params))
	return 0
