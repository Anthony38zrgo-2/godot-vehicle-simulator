extends Node3D
class_name RallyVisualSectorStream
## Streams pre-cut terrain meshes while the stage's simulation stays resident.

const LOAD_RADIUS_M := 450.0
const RELEASE_RADIUS_M := 690.0
const START_RADIUS_M := 150.0
const LOOK_AHEAD_S := 3.0
const MAX_REQUESTS := 2
const CDI_TERRAIN := preload("res://scripts/rally/cdi_terrain_blend.gdshader")
const CDI_BACKDROP := preload("res://scripts/rally/cdi_terrain_backdrop.gdshader")
const CDI_REGIONAL := preload("res://scripts/rally/cdi_terrain_regional.gdshader")
const CDI_ASPHALT := preload("res://scripts/rally/cdi_asfalto_estepa.gdshader")
const CDI_ASPHALT_TEXTURES := "res://assets/rally/CDI/asfalto_estepa/"
const ASPHALT_LAYERS := [
	"j_tm1", "j_tm6", "j_tml1", "j_tml2", "j_tml3", "j_tml4", "j_tml5", "j_tml6",
	"j_tm1_nieve_parches", "j_tm1_nieve_roderas",
]
const CDI_TEXTURES := "res://assets/rally/cdi_stage1/puna_seca/"
const CDI_LAYERS := [
	"carretera", "carretera_compacta", "carretera_fina", "carretera_gruesa",
	"pasto_denso", "pasto_denso_02", "pasto_denso_03",
	"pasto_ralo", "pasto_ralo_02", "pasto_ralo_03", "pasto_oliva_local",
	"cuneta", "cuneta_02", "corte_tierra_rojiza",
	"talud", "talud_02", "talud_03", "pedregal", "pedregal_02",
]

var _vehicle: RigidBody3D
var _sectors: Array[Dictionary] = []
var _pending := {}
var _active := {}
var _failed := {}
var _content := {}
var _sector_dir := ""
var _cell_m := 256.0
var terrain_palette: Texture2DArray
var use_cdi_gravel_road := true
var road_wetness: RallyTerrainWetness
var _asphalt_material: ShaderMaterial
var _ticlio_snow_textures: Texture2DArray
var _ticlio_snow_coverage: Texture2D
var _ticlio_snow_pixels: Image
var _guardrail_materials := {}
var sky_node: Node = null
var _grass_gis: Texture2D
var _grass_gis_pixels: Image
var _grass_gis_bounds: Vector4
var _terrain_materials := {}
var _ticlio_drainage_material: StandardMaterial3D
var _procedural_surface_enabled: bool = false
var _surface_field_image: Image
var _surface_field_texture: ImageTexture
var _surface_field_revision: int = -1
var _last_procedural_packet: Dictionary = {}
var use_rust_backend: bool = true
var _rust_gis: RefCounted = null


func load_cdi_palette(stage_dir: String) -> bool:
	var mask_dir := stage_dir.path_join("puna_seca")
	_grass_gis = load(mask_dir.path_join("pastizal_gis.png")) as Texture2D
	var bounds: Variant = JSON.parse_string(FileAccess.get_file_as_string(mask_dir.path_join("pastizal_gis.json")))
	if _grass_gis == null or not bounds is Array or bounds.size() != 4 or bounds[2] <= 0 or bounds[3] <= 0:
		return false
	_grass_gis_pixels = _grass_gis.get_image()
	if _grass_gis_pixels == null or (_grass_gis_pixels.is_compressed() and _grass_gis_pixels.decompress() != OK):
		return false
	_grass_gis_bounds = Vector4(bounds[0], bounds[1], bounds[2], bounds[3])
	var sampler := _ensure_rust_gis()
	if sampler != null:
		var rgba_grass := _to_rgba8_image(_grass_gis_pixels)
		sampler.call("set_grass_gis", rgba_grass.get_width(), rgba_grass.get_height(), rgba_grass.get_data(), _grass_gis_bounds)
		if _ticlio_snow_pixels != null:
			var rgba_snow := _to_rgba8_image(_ticlio_snow_pixels)
			sampler.call("set_snow_coverage", rgba_snow.get_width(), rgba_snow.get_height(), rgba_snow.get_data(), _grass_gis_bounds)
	var layers: Array[Image] = []
	for layer in CDI_LAYERS:
		var texture := load(CDI_TEXTURES + layer + ".png") as Texture2D
		if texture == null:
			return false
		var pixels := texture.get_image()
		if pixels.is_compressed() and pixels.decompress() != OK:
			return false
		pixels.clear_mipmaps()
		pixels.convert(Image.FORMAT_RGBA8)
		pixels.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		pixels.generate_mipmaps()
		layers.append(pixels)
	var palette := Texture2DArray.new()
	if palette.create_from_images(layers) != OK:
		return false
	terrain_palette = palette
	return true


func _load_surface_layers(paths: Array[String], size: int = 0) -> Texture2DArray:
	var layers: Array[Image] = []
	for path in paths:
		var texture := load(path) as Texture2D
		if texture == null:
			return null
		var pixels := texture.get_image()
		if pixels.is_compressed() and pixels.decompress() != OK:
			return null
		pixels.clear_mipmaps()
		pixels.convert(Image.FORMAT_RGBA8)
		if size > 0 and pixels.get_size() != Vector2i(size, size):
			pixels.resize(size, size, Image.INTERPOLATE_LANCZOS)
		pixels.generate_mipmaps()
		layers.append(pixels)
	var textures := Texture2DArray.new()
	return textures if textures.create_from_images(layers) == OK else null


func load_cdi_asphalt(snow_station: float, keep_ticlio_roadside_snow: bool = false) -> bool:
	var asphalt_paths: Array[String] = []
	for layer in ASPHALT_LAYERS:
		asphalt_paths.append(CDI_ASPHALT_TEXTURES + layer + ".png")
	var textures := _load_surface_layers(asphalt_paths)
	if textures == null:
		return false
	if snow_station >= 0.0 or keep_ticlio_roadside_snow:
		var ice_paths: Array[String] = []
		for index in range(1, 8):
			ice_paths.append("res://assets/rally/CDI/nieve_ticlio/terreno_%02d.png" % index)
		for index in range(1, 3):
			ice_paths.append("res://assets/rally/sweden_stage2/sweden_stage2_visual_terrain_snow_%d.png" % index)
		_ticlio_snow_textures = _load_surface_layers(ice_paths, 128)
		_ticlio_snow_coverage = load("res://assets/rally/cdi_stage4/puna_seca/nieve_gis.png") as Texture2D
		if _ticlio_snow_textures == null or _ticlio_snow_coverage == null:
			return false
		_ticlio_snow_pixels = _ticlio_snow_coverage.get_image()
		if _ticlio_snow_pixels.is_compressed() and _ticlio_snow_pixels.decompress() != OK:
			return false
		var sampler := _ensure_rust_gis()
		if sampler != null and _grass_gis_bounds.z > 0.0 and _grass_gis_bounds.w > 0.0:
			var rgba_snow := _to_rgba8_image(_ticlio_snow_pixels)
			sampler.call("set_snow_coverage", rgba_snow.get_width(), rgba_snow.get_height(), rgba_snow.get_data(), _grass_gis_bounds)
	_asphalt_material = ShaderMaterial.new()
	_asphalt_material.shader = CDI_ASPHALT
	_asphalt_material.set_shader_parameter("surface_textures", textures)
	_asphalt_material.set_shader_parameter("snow_station_m", -1.0 if keep_ticlio_roadside_snow else snow_station)
	_asphalt_material.set_shader_parameter("procedural_surface_enabled", _procedural_surface_enabled)
	if _surface_field_texture != null:
		_asphalt_material.set_shader_parameter("surface_field_tex", _surface_field_texture)
	for layer in ["arm_1a", "arm_1b", "arm_1a_reverse"]:
		var texture := load(CDI_ASPHALT_TEXTURES + layer + ".png") as Texture2D
		if texture == null:
			return false
		var rail := StandardMaterial3D.new()
		rail.albedo_texture = texture
		rail.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		rail.alpha_scissor_threshold = 0.5
		rail.cull_mode = BaseMaterial3D.CULL_DISABLED
		rail.disable_fog = true
		rail.roughness = 0.64
		_guardrail_materials[layer] = rail
	return true


func _apply_procedural_uniforms(mat: ShaderMaterial, packet: Dictionary) -> void:
	if mat == null or packet.is_empty():
		return
	var width := int(packet.get("width", 0))
	mat.set_shader_parameter("procedural_surface_enabled", true)
	if mat == _asphalt_material:
		mat.set_shader_parameter("snow_station_m", -1.0)
	if _surface_field_texture != null:
		mat.set_shader_parameter("surface_field_tex", _surface_field_texture)
	mat.set_shader_parameter(
		"surface_station_range_m",
		Vector2(float(packet.get("station_min_m", 0.0)), float(packet.get("station_max_m", 1.0))),
	)
	mat.set_shader_parameter("surface_field_width", float(width))
	mat.set_shader_parameter("surface_max_encode_mm", float(packet.get("max_encode_mm", 3.5)))
	mat.set_shader_parameter(
		"surface_full_mm",
		Vector3(
			float(packet.get("water_full_mm", 3.0)),
			float(packet.get("snow_full_mm", 3.5)),
			float(packet.get("ice_full_mm", 1.8)),
		),
	)
	var snow_off: Vector2 = packet.get("snow_seed_offset", Vector2.ZERO) as Vector2
	var ice_off: Vector2 = packet.get("ice_seed_offset", Vector2(17.3, 9.7)) as Vector2
	mat.set_shader_parameter(
		"surface_seed_offsets",
		Vector4(snow_off.x, snow_off.y, ice_off.x, ice_off.y),
	)


func surface_field_revision() -> int:
	return _surface_field_revision if _surface_field_texture != null else -1


func sync_procedural_surface(packet: Dictionary, force: bool = false) -> void:
	if packet.is_empty() or not bool(packet.get("ok", false)):
		return
	var rev := int(packet.get("revision", -1))
	if not force and rev == surface_field_revision():
		return
	var width := int(packet.get("width", 0))
	var rgba := packet.get("rgba8", PackedByteArray()) as PackedByteArray
	if width < 2 or rgba.size() != width * 4:
		return
	_procedural_surface_enabled = true
	_last_procedural_packet = packet
	_surface_field_revision = rev
	if _surface_field_image == null or _surface_field_image.get_width() != width:
		_surface_field_image = Image.create_from_data(width, 1, false, Image.FORMAT_RGBA8, rgba)
		_surface_field_texture = ImageTexture.create_from_image(_surface_field_image)
	else:
		_surface_field_image.set_data(width, 1, false, Image.FORMAT_RGBA8, rgba)
		_surface_field_texture.update(_surface_field_image)
	if _asphalt_material != null:
		_apply_procedural_uniforms(_asphalt_material, packet)
	var gravel_road: ShaderMaterial = _terrain_materials.get(2)
	if gravel_road != null:
		_apply_procedural_uniforms(gravel_road, packet)


func is_procedural_surface_enabled() -> bool:
	return _procedural_surface_enabled


static func _to_rgba8_image(img: Image) -> Image:
	var out: Image = img
	if out.is_compressed() or out.get_format() != Image.FORMAT_RGBA8:
		out = img.duplicate() as Image
		if out.is_compressed():
			out.decompress()
		if out.get_format() != Image.FORMAT_RGBA8:
			out.convert(Image.FORMAT_RGBA8)
	return out


func _ensure_rust_gis() -> RefCounted:
	if not use_rust_backend or not ClassDB.class_exists(&"RustGisSampler"):
		return null
	if _rust_gis == null:
		_rust_gis = ClassDB.instantiate(&"RustGisSampler") as RefCounted
	return _rust_gis


func get_rust_gis() -> RefCounted:
	return _rust_gis if use_rust_backend else null


func get_sectors_for_rust() -> Dictionary:
	var paths: Array[String] = []
	var grid_coords := PackedInt32Array()
	var rects_flat := PackedFloat32Array()
	var count: int = _sectors.size()
	paths.resize(count)
	grid_coords.resize(count * 2)
	rects_flat.resize(count * 4)
	for i in count:
		var s: Dictionary = _sectors[i] as Dictionary
		var path: String = str(s["path"])
		paths[i] = path
		var fname: String = path.get_file()
		var gx: int = -2147483648
		var gz: int = -2147483648
		if fname.begins_with("sector_") and fname.ends_with(".glb"):
			var stem: String = fname.substr(7, fname.length() - 11)
			var parts: PackedStringArray = stem.split("_")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				gx = int(parts[0])
				gz = int(parts[1])
		grid_coords[i * 2] = gx
		grid_coords[i * 2 + 1] = gz
		var r: Rect2 = s["rect"] as Rect2
		rects_flat[i * 4] = r.position.x
		rects_flat[i * 4 + 1] = r.position.y
		rects_flat[i * 4 + 2] = r.size.x
		rects_flat[i * 4 + 3] = r.size.y
	return {
		"cell_m": _cell_m,
		"paths": paths,
		"grid_coords": grid_coords,
		"rects_flat": rects_flat,
	}


func snow_coverage_at(point: Vector3) -> float:
	if _ticlio_snow_pixels == null:
		return 0.0
	if use_rust_backend and _rust_gis != null:
		return float(_rust_gis.call("snow_coverage_at", point))
	var uv := (Vector2(point.x, point.z) - Vector2(_grass_gis_bounds.x, _grass_gis_bounds.y)) 		/ Vector2(_grass_gis_bounds.z, _grass_gis_bounds.w)
	var edge := minf(minf(uv.x, uv.y), minf(1.0 - uv.x, 1.0 - uv.y))
	if edge <= 0.0:
		return 0.0
	# Match the shader's bilinear sampling at texel centers.
	var size := _ticlio_snow_pixels.get_size()
	var texel := uv * Vector2(size) - Vector2(0.5, 0.5)
	var base := Vector2i(texel.floor())
	var a := base.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var b := (base + Vector2i.ONE).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var fraction := texel - texel.floor()
	var top := lerpf(_ticlio_snow_pixels.get_pixel(a.x, a.y).r, _ticlio_snow_pixels.get_pixel(b.x, a.y).r, fraction.x)
	var bottom := lerpf(_ticlio_snow_pixels.get_pixel(a.x, b.y).r, _ticlio_snow_pixels.get_pixel(b.x, b.y).r, fraction.x)
	return lerpf(top, bottom, fraction.y) * smoothstep(0.0, 0.025, edge)


## Bilinear sample of pastizal_gis.png matching cdi_terrain_layers.gdshaderinc.
## R = dense(0)->sparse(1), G = olive/moist, B = mineral/scree, A = in-bounds weight.
func grass_gis_at(point: Vector3) -> Color:
	if _grass_gis_pixels == null:
		return Color(0.45, 0.06, 0.15, 0.0)
	if use_rust_backend and _rust_gis != null:
		return _rust_gis.call("grass_gis_at", point) as Color
	var uv := (Vector2(point.x, point.z) - Vector2(_grass_gis_bounds.x, _grass_gis_bounds.y)) \
		/ Vector2(_grass_gis_bounds.z, _grass_gis_bounds.w)
	var edge_m := minf(minf(uv.x, 1.0 - uv.x) * _grass_gis_bounds.z,
		minf(uv.y, 1.0 - uv.y) * _grass_gis_bounds.w)
	if edge_m <= 0.0:
		return Color(0.45, 0.06, 0.15, 0.0)
	var size := _grass_gis_pixels.get_size()
	var texel := uv * Vector2(size) - Vector2(0.5, 0.5)
	var base := Vector2i(texel.floor())
	var a := base.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var b := (base + Vector2i.ONE).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var fraction := texel - texel.floor()
	var top := _grass_gis_pixels.get_pixel(a.x, a.y).lerp(_grass_gis_pixels.get_pixel(b.x, a.y), fraction.x)
	var bottom := _grass_gis_pixels.get_pixel(a.x, b.y).lerp(_grass_gis_pixels.get_pixel(b.x, b.y), fraction.x)
	var sample := top.lerp(bottom, fraction.y)
	sample.a = smoothstep(0.0, 180.0, edge_m)
	return sample


func configure(index_path: String, vehicle: RigidBody3D, spawn: Vector3, cell_m: float) -> bool:
	_vehicle = vehicle
	_sector_dir = index_path.get_base_dir()
	_cell_m = cell_m
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if not data is Dictionary or data.get("sectors", []).is_empty():
		push_error("Invalid terrain sector index: " + index_path)
		return false
	for sector: Dictionary in data.sectors:
		var lower: Array = sector.minimum
		var upper: Array = sector.maximum
		_sectors.append({
			"path": index_path.get_base_dir().path_join(str(sector.file)),
			"rect": Rect2(lower[0], lower[2], upper[0] - lower[0], upper[2] - lower[2]),
		})
	var start := Vector2(spawn.x, spawn.z)
	var required: Array[String] = []
	for sector in _sectors:
		if _distance_sq(start, sector.rect) <= START_RADIUS_M * START_RADIUS_M:
			required.append(sector.path)
	if required.is_empty():
		push_error("No terrain sector covers the stage start")
		return false
	while not required.is_empty():
		_tick(start, start)
		for i in range(required.size() - 1, -1, -1):
			if _failed.has(required[i]):
				return false
			if _active.has(required[i]):
				required.remove_at(i)
		await get_tree().process_frame
	_update_regional_lighting(0.0)
	set_process(true)
	print("RALLY_VISUAL_STREAM_READY active=", _active.size(), " total=", _sectors.size())
	return true


func sector_for_point(point: Vector3) -> String:
	var short_name := "sector_%d_%d.glb" % [floori(point.x / _cell_m), floori(point.z / _cell_m)]
	var preferred := _sector_dir.path_join(short_name)
	var nearest := INF
	var selected := ""
	for sector in _sectors:
		if sector.path == preferred:
			return preferred
		var distance := _distance_sq(Vector2(point.x, point.z), sector.rect)
		if distance < nearest:
			nearest = distance
			selected = sector.path
	return selected


func register_content(path: String, factory: Callable) -> void:
	if not _content.has(path):
		_content[path] = []
	_content[path].append(factory)
	if _active.has(path):
		factory.call(_active[path].get_node("SectorObjects"))


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if _asphalt_material != null and not _procedural_surface_enabled and is_instance_valid(road_wetness):
		_asphalt_material.set_shader_parameter("wetness", road_wetness.get_wetness())
	var point := _vehicle.global_position
	var velocity := _vehicle.linear_velocity * LOOK_AHEAD_S
	_tick(Vector2(point.x, point.z), Vector2(point.x + velocity.x, point.z + velocity.z))
	_update_regional_lighting(_delta)


var _light_refresh := 0.0
var _lights: Array[Node] = []


## Feeds the dynamic sun, sky ambient and horizon haze to the regional DEM shader,
## reading directly from the stage's tropospheric sky so isolated SubViewport preview
## lights (pause workshop, garage, tire strategy) can never hijack the mountain lighting.
func _update_regional_lighting(delta: float) -> void:
	var material: ShaderMaterial = _terrain_materials.get(4)
	if material == null:
		return
	var sky: Node = sky_node if is_instance_valid(sky_node) else null
	if sky == null:
		var root := get_tree().current_scene if get_tree() != null else null
		if root != null:
			sky = root.find_child("RallyTroposphericSky", true, false)
			sky_node = sky
	var sun: DirectionalLight3D = null
	var env: Environment = null
	if sky != null:
		var sky_sun := sky.get("sun") as DirectionalLight3D
		var sky_moon := sky.get("moon") as DirectionalLight3D
		if sky_sun != null and is_instance_valid(sky_sun):
			sun = sky_sun
		if sky_moon != null and is_instance_valid(sky_moon) and (sun == null or sky_moon.light_energy > sun.light_energy):
			sun = sky_moon
		env = sky.get("environment") as Environment
	else:
		_light_refresh -= delta
		if _light_refresh <= 0.0 or _lights.any(func(l: Node) -> bool: return not is_instance_valid(l)):
			var scope := get_tree().current_scene if get_tree() != null else null
			_lights = scope.find_children("*", "DirectionalLight3D", true, false) if scope != null else []
			_light_refresh = 2.0
		var my_world := get_world_3d()
		for node in _lights:
			var light := node as DirectionalLight3D
			if light == null or light.is_queued_for_deletion() or not light.is_visible_in_tree():
				continue
			if my_world != null and light.get_world_3d() != my_world:
				continue
			if sun == null or light.light_energy > sun.light_energy:
				sun = light
	if sun != null and is_instance_valid(sun):
		var dir := sun.global_basis.z
		if not dir.is_zero_approx():
			material.set_shader_parameter("sun_dir", dir.normalized())
		var color := sun.light_color * sun.light_energy
		material.set_shader_parameter("sun_color", Vector3(color.r, color.g, color.b))
	if env == null and get_world_3d() != null:
		env = get_world_3d().environment
	if env != null:
		var ambient := env.ambient_light_color * env.ambient_light_energy
		material.set_shader_parameter("ambient_color", Vector3(ambient.r, ambient.g, ambient.b))
		var haze := env.fog_light_color
		material.set_shader_parameter("haze_color", Vector3(haze.r, haze.g, haze.b))


func _distance_sq(point: Vector2, rect: Rect2) -> float:
	var nearest := point.clamp(rect.position, rect.end)
	return point.distance_squared_to(nearest)


func _tick(point: Vector2, look_ahead: Vector2) -> void:
	var candidates: Array[Dictionary] = []
	var keep := {}
	for sector in _sectors:
		var here := _distance_sq(point, sector.rect)
		var future := _distance_sq(look_ahead, sector.rect)
		var path: String = sector.path
		if here <= RELEASE_RADIUS_M * RELEASE_RADIUS_M or future <= LOAD_RADIUS_M * LOAD_RADIUS_M:
			keep[path] = true
		var already_requested := _active.has(path) or _pending.has(path) or _failed.has(path)
		if minf(here, future) <= LOAD_RADIUS_M * LOAD_RADIUS_M and not already_requested:
			candidates.append({"path": path, "priority": minf(here, future + 10000.0)})
	for path: String in _active.keys():
		if not keep.has(path):
			_active[path].queue_free()
			_active.erase(path)
	for path: String in _pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_pending.erase(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			_failed[path] = true
			push_error("Could not load terrain sector: " + path)
			continue
		var packed := ResourceLoader.load_threaded_get(path) as PackedScene
		if packed == null:
			_failed[path] = true
			push_error("Invalid terrain sector scene: " + path)
			continue
		if keep.has(path):
			_attach_sector(path, packed)
			break # Limit instantiation and rendering uploads to one sector per frame.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.priority < b.priority)
	for candidate in candidates:
		if _pending.size() >= MAX_REQUESTS:
			break
		var path: String = candidate.path
		if DisplayServer.get_name() == "headless":
			# The dummy renderer can race while threaded imports create RIDs.
			# Keep headless validation on the main thread, one sector per frame.
			var packed := load(path) as PackedScene
			if packed != null:
				_attach_sector(path, packed)
			else:
				_failed[path] = true
				push_error("Invalid terrain sector scene: " + path)
			break
		if ResourceLoader.load_threaded_request(path, "PackedScene") == OK:
			_pending[path] = true
		else:
			_failed[path] = true
			push_error("Could not queue terrain sector: " + path)


func _attach_sector(path: String, packed: PackedScene) -> void:
	var instance := packed.instantiate()
	var adjuster := RallyStageVisualMaterialAdjuster.new()
	adjuster.adjust_node(instance)
	adjuster.free()
	tune_materials(instance)
	add_child(instance)
	_active[path] = instance
	var objects := Node3D.new()
	objects.name = "SectorObjects"
	instance.add_child(objects)
	for factory: Callable in _content.get(path, []):
		factory.call(objects)


func tune_materials(root: Node) -> void:
	for terrain in root.find_children("*", "MeshInstance3D", true, false):
		if terrain.name == "Guardarrail":
			for surface in terrain.mesh.get_surface_count():
				var original: Material = terrain.mesh.surface_get_material(surface)
				var rail: Material = _guardrail_materials.get(original.resource_name) if original != null else null
				if rail != null:
					terrain.set_surface_override_material(surface, rail)
			continue
		var blend := _terrain_blend_for(str(terrain.name)) if terrain_palette != null else null
		if blend != null:
			for surface in terrain.mesh.get_surface_count():
				var original: Material = terrain.mesh.surface_get_material(surface)
				if original != null and original.resource_name == "ticlio_v_drainage":
					if _ticlio_drainage_material == null:
						_ticlio_drainage_material = StandardMaterial3D.new()
						_ticlio_drainage_material.albedo_texture = load("res://assets/rally/cdi_stage4/cuneta_v.png") as Texture2D
						_ticlio_drainage_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
						_ticlio_drainage_material.roughness = 0.95
					terrain.set_surface_override_material(surface, _ticlio_drainage_material)
				else:
					terrain.set_surface_override_material(surface, blend)
			continue
		for surface in terrain.mesh.get_surface_count():
			var original := terrain.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var material := original.duplicate() as StandardMaterial3D
			material.disable_fog = true
			if terrain.name == "Rajuntay Regional DEM":
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.vertex_color_use_as_albedo = true
			elif terrain.name == "Rajuntay DEM fondo":
				material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
				material.distance_fade_min_distance = 340.0
				material.distance_fade_max_distance = 125.0
			terrain.set_surface_override_material(surface, material)


func _terrain_blend_for(mesh_name: String) -> ShaderMaterial:
	if mesh_name == "Road" and _asphalt_material != null:
		return _asphalt_material
	var mode := -1
	if mesh_name == "Ladera DSM":
		mode = 0
	elif mesh_name.begins_with("Terrain_Dirt_"):
		mode = 1
	elif mesh_name == "Road" and use_cdi_gravel_road:
		mode = 2
	elif mesh_name == "Rajuntay DEM fondo":
		mode = 3
	elif mesh_name == "Rajuntay Regional DEM":
		mode = 4
	if mode < 0:
		return null
	if _terrain_materials.has(mode):
		return _terrain_materials[mode]
	var material := ShaderMaterial.new()
	material.shader = CDI_REGIONAL if mode == 4 else (CDI_BACKDROP if mode == 3 else CDI_TERRAIN)
	material.set_shader_parameter("terrain_palette", terrain_palette)
	material.set_shader_parameter("grass_gis", _grass_gis)
	material.set_shader_parameter("grass_gis_bounds", _grass_gis_bounds)
	material.set_shader_parameter("ticlio_snow_enabled", _ticlio_snow_textures != null)
	if _ticlio_snow_textures != null:
		material.set_shader_parameter("ticlio_snow_textures", _ticlio_snow_textures)
		material.set_shader_parameter("ticlio_snow_coverage", _ticlio_snow_coverage)
	if mode < 3:
		material.set_shader_parameter("terrain_mode", mode)
	if mode == 2 and _procedural_surface_enabled and not _last_procedural_packet.is_empty():
		_apply_procedural_uniforms(material, _last_procedural_packet)
	_terrain_materials[mode] = material
	return material
