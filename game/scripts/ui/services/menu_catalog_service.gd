class_name MenuCatalogService
extends RefCounted
## Pure Data-Driven loader for declarative menu JSON catalogs under res://data/ui/menus/.

const BASE_DIR := "res://data/ui/menus/"

static var _cache: Dictionary = {}


static func reload() -> void:
	_cache.clear()


static func load_catalog(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name] as Dictionary
	var path := BASE_DIR + name + ".json"
	if not FileAccess.file_exists(path):
		push_error("MenuCatalogService: missing catalog JSON at %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("MenuCatalogService: invalid JSON in %s" % path)
		return {}
	_cache[name] = parsed
	return parsed as Dictionary


static func get_countries_stages() -> Dictionary:
	return load_catalog("countries_stages")


static func get_main_menu() -> Dictionary:
	return load_catalog("main_menu")


static func get_weather_options() -> Dictionary:
	return load_catalog("weather_options")


static func get_garage_layout() -> Dictionary:
	return load_catalog("garage_layout")


static func get_service_parts() -> Dictionary:
	return load_catalog("service_parts")


static func get_pause_actions() -> Dictionary:
	return load_catalog("pause_actions")


static func get_stage_metadata(stage_id: String) -> Dictionary:
	var doc := get_countries_stages()
	var meta: Variant = doc.get("stage_metadata", {})
	if meta is Dictionary and (meta as Dictionary).has(stage_id):
		return (meta as Dictionary)[stage_id] as Dictionary
	var cdi: Variant = doc.get("cdi_stages", {})
	if cdi is Dictionary and (cdi as Dictionary).has(stage_id):
		return (cdi as Dictionary)[stage_id] as Dictionary
	return {}
