class_name UITokenRegistry
extends RefCounted
## Single-responsibility loader and cache for UI design tokens, fonts, presets, and StyleBoxFlat resources.

const TOKENS_PATH := "res://data/ui/tokens.json"
const PRESETS_PATH := "res://data/ui/component_presets.json"

static var _loaded := false
static var _tokens: Dictionary = {}
static var _colors: Dictionary = {}
static var _radii: Dictionary = {}
static var _spacing: Dictionary = {}
static var _font_paths: Dictionary = {}
static var _font_sizes: Dictionary = {}
static var _button_tones: Dictionary = {}
static var _presets: Dictionary = {}
static var _font_cache: Dictionary = {}
static var _stylebox_cache: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_tokens.clear()
	_colors.clear()
	_radii.clear()
	_spacing.clear()
	_font_paths.clear()
	_font_sizes.clear()
	_button_tones.clear()
	_presets.clear()
	_font_cache.clear()
	_stylebox_cache.clear()
	_ensure_loaded()


static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("UITokenRegistry: missing JSON file at %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("UITokenRegistry: invalid JSON object in %s" % path)
		return {}
	return parsed as Dictionary


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_tokens = _read_json_dict(TOKENS_PATH)
	var raw_colors: Variant = _tokens.get("colors", {})
	if raw_colors is Dictionary:
		for k in raw_colors:
			_colors[str(k)] = _parse_color_value(raw_colors[k], Color.WHITE)
	var raw_radii: Variant = _tokens.get("radii", {})
	if raw_radii is Dictionary:
		for k in raw_radii:
			_radii[str(k)] = int(raw_radii[k])
	var raw_spacing: Variant = _tokens.get("spacing", {})
	if raw_spacing is Dictionary:
		for k in raw_spacing:
			_spacing[str(k)] = int(raw_spacing[k])
	var raw_fonts: Variant = _tokens.get("fonts", {})
	if raw_fonts is Dictionary:
		for k in raw_fonts:
			_font_paths[str(k)] = str(raw_fonts[k])
	var raw_sizes: Variant = _tokens.get("font_sizes", {})
	if raw_sizes is Dictionary:
		for k in raw_sizes:
			_font_sizes[str(k)] = int(raw_sizes[k])
	var raw_tones: Variant = _tokens.get("button_tones", {})
	if raw_tones is Dictionary:
		_button_tones = raw_tones

	var preset_doc := _read_json_dict(PRESETS_PATH)
	var raw_presets: Variant = preset_doc.get("presets", {})
	if raw_presets is Dictionary:
		_presets = raw_presets


static func _parse_color_value(val: Variant, fallback: Color = Color.WHITE) -> Color:
	if val is Color:
		return val
	if val is String:
		var s := (val as String).strip_edges()
		if _colors.has(s):
			return _colors[s] as Color
		if s.begins_with("#") or Color.html_is_valid(s):
			return Color.html(s)
		return fallback
	if val is Array:
		var arr := val as Array
		if arr.size() >= 4:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		if arr.size() == 3:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), 1.0)
	return fallback


static func get_color(key_or_value: Variant, fallback: Color = Color.WHITE) -> Color:
	_ensure_loaded()
	if key_or_value is String:
		var s := (key_or_value as String).strip_edges()
		if not s.is_empty() and not _colors.has(s) and not s.begins_with("#") and not Color.html_is_valid(s):
			push_error("UITokenRegistry: unknown color token '%s'" % s)
	return _parse_color_value(key_or_value, fallback)


static func has_color(key: String) -> bool:
	_ensure_loaded()
	return _colors.has(key)


static func list_color_keys() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for k in _colors.keys():
		out.append(str(k))
	out.sort()
	return out


static func get_radius(key: String = "technical", fallback: int = 2) -> int:
	_ensure_loaded()
	return int(_radii.get(key, fallback))


static func get_spacing(key: String = "md", fallback: int = 12) -> int:
	_ensure_loaded()
	return int(_spacing.get(key, fallback))


static func get_font_size(key: String = "body", fallback: int = 13) -> int:
	_ensure_loaded()
	return int(_font_sizes.get(key, fallback))


static func has_font(key: String) -> bool:
	_ensure_loaded()
	return _font_paths.has(key)


static func list_font_keys() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for k in _font_paths.keys():
		out.append(str(k))
	out.sort()
	return out


static func get_font(key: String) -> Font:
	_ensure_loaded()
	if _font_cache.has(key):
		return _font_cache[key] as Font
	var path := str(_font_paths.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("UITokenRegistry: missing font resource for key '%s' at '%s'" % [key, path])
		return null
	var font := load(path) as Font
	if font != null:
		_font_cache[key] = font
	return font


static func has_tone(tone: String) -> bool:
	_ensure_loaded()
	return _button_tones.has(tone)


static func get_tone_spec(tone: String) -> Dictionary:
	_ensure_loaded()
	var raw: Variant = _button_tones.get(tone, _button_tones.get("chrome", {}))
	var out := {}
	if raw is Dictionary:
		for k in raw:
			out[str(k)] = get_color(raw[k])
	return out


static func get_flat_stylebox(
	bg: Color,
	border_col: Color,
	border_w: int = 1,
	corner_r: int = 2,
	pad_h: int = -1,
	pad_v: int = -1,
	border_left: int = -1,
	border_top: int = -1,
	border_right: int = -1,
	border_bottom: int = -1,
	pad_left: int = -1
) -> StyleBoxFlat:
	## Returns a cached StyleBoxFlat keyed by exact visual parameters to prevent per-frame allocations.
	_ensure_loaded()
	var key := "%s|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [
		bg.to_html(true),
		border_col.to_html(true),
		border_w,
		corner_r,
		pad_h,
		pad_v,
		border_left,
		border_top,
		border_right,
		border_bottom,
		pad_left,
	]
	if _stylebox_cache.has(key):
		return _stylebox_cache[key] as StyleBoxFlat
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_col
	if border_left >= 0 or border_top >= 0 or border_right >= 0 or border_bottom >= 0:
		sb.border_width_left = maxi(0, border_left)
		sb.border_width_top = maxi(0, border_top)
		sb.border_width_right = maxi(0, border_right)
		sb.border_width_bottom = maxi(0, border_bottom)
	else:
		sb.set_border_width_all(maxi(0, border_w))
	sb.set_corner_radius_all(maxi(0, corner_r))
	sb.shadow_size = 0
	sb.anti_aliasing = true
	if pad_h >= 0:
		sb.content_margin_left = pad_h
		sb.content_margin_right = pad_h
	if pad_left >= 0:
		sb.content_margin_left = pad_left
	if pad_v >= 0:
		sb.content_margin_top = pad_v
		sb.content_margin_bottom = pad_v
	_stylebox_cache[key] = sb
	return sb


static func get_stylebox_cache_size() -> int:
	return _stylebox_cache.size()


static func list_preset_ids() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for k in _presets.keys():
		out.append(str(k))
	out.sort()
	return out


static func has_preset(preset_id: String) -> bool:
	_ensure_loaded()
	return _presets.has(preset_id)


static func resolve_preset(preset_id: String) -> Dictionary:
	_ensure_loaded()
	if not _presets.has(preset_id):
		push_error("UITokenRegistry: unknown preset '%s'" % preset_id)
		return {}
	var chain: Array[Dictionary] = []
	var visited := {}
	var cursor := preset_id
	while not cursor.is_empty():
		if visited.has(cursor):
			push_error("UITokenRegistry: inheritance cycle in preset '%s'" % cursor)
			break
		visited[cursor] = true
		var entry: Variant = _presets.get(cursor, {})
		if not (entry is Dictionary) or (entry as Dictionary).is_empty():
			push_error("UITokenRegistry: missing parent preset '%s'" % cursor)
			break
		chain.push_front(entry as Dictionary)
		cursor = str((entry as Dictionary).get("extends", ""))
	var merged := {}
	for item in chain:
		for k in item:
			if str(k) != "extends":
				merged[str(k)] = item[k]
	return merged
