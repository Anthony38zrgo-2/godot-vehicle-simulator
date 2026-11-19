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
var _grass_gis: Texture2D
var _grass_gis_bounds: Vector4
var _terrain_materials := {}


func load_rajuntay_palette() -> bool:
	_grass_gis = load(CDI_TEXTURES + "pastizal_gis.png") as Texture2D
	var bounds: Variant = JSON.parse_string(FileAccess.get_file_as_string(CDI_TEXTURES + "pastizal_gis.json"))
	if _grass_gis == null or not bounds is Array or bounds.size() != 4 or bounds[2] <= 0 or bounds[3] <= 0:
		return false
	_grass_gis_bounds = Vector4(bounds[0], bounds[1], bounds[2], bounds[3])
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
	var point := _vehicle.global_position
	var velocity := _vehicle.linear_velocity * LOOK_AHEAD_S
	_tick(Vector2(point.x, point.z), Vector2(point.x + velocity.x, point.z + velocity.z))
	_update_regional_lighting(_delta)


var _light_refresh := 0.0
var _lights: Array[Node] = []


## Feeds the dynamic sun, sky ambient and horizon haze to the regional DEM shader,
## which no longer bakes lighting into COLOR_0.
func _update_regional_lighting(delta: float) -> void:
	var material: ShaderMaterial = _terrain_materials.get(4)
	if material == null:
		return
	_light_refresh -= delta
	if _light_refresh <= 0.0 or _lights.any(func(l: Node) -> bool: return not is_instance_valid(l)):
		_lights = get_tree().root.find_children("*", "DirectionalLight3D", true, false)
		_light_refresh = 2.0
	var sun: DirectionalLight3D = null
	for node in _lights:
		var light := node as DirectionalLight3D
		if light != null and light.visible and (sun == null or light.light_energy > sun.light_energy):
			sun = light
	if sun != null:
		var color := sun.light_color * sun.light_energy
		material.set_shader_parameter("sun_dir", sun.global_basis.z.normalized())
		material.set_shader_parameter("sun_color", Vector3(color.r, color.g, color.b))
	var env := get_world_3d().environment if get_world_3d() != null else null
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
		var blend := _terrain_blend_for(str(terrain.name)) if terrain_palette != null else null
		if blend != null:
			for surface in terrain.mesh.get_surface_count():
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
	var mode := -1
	if mesh_name == "Ladera DSM":
		mode = 0
	elif mesh_name.begins_with("Terrain_Dirt_"):
		mode = 1
	elif mesh_name == "Road":
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
	if mode < 3:
		material.set_shader_parameter("terrain_mode", mode)
	_terrain_materials[mode] = material
	return material
