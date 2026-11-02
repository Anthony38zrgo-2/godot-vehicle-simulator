class_name Cmr2PacenoteHud
extends Control

const Cmr2PacenoteCodec = preload("res://scripts/rally/cmr2_pacenote_codec.gd")

# Port of Race_DrawPlayerCallSlots (Race.cpp:994-1215, GPL-3.0)
const SVG_DIR := "res://assets/rally/visual_pacenotes/cmr2/"
const ICON_FILES := [
	"arrow_00.svg",
	"arrow_01.svg",
	"arrow_02.svg",
	"arrow_03.svg",
	"arrow_04.svg",
	"arrow_05.svg",
	"arrow_06.svg",
	"warning.svg"
]

const CURVE_TABLE: Array[int] = [
	0, 0xc, 0x19, 0x4c, 0x99, 0x100, 0x180, 0x219, 0x2cc, 0x399, 0x400
]

var textures: Array[Texture2D] = []
var primary_rect: TextureRect
var secondary_rect: TextureRect
var container: HBoxContainer

var current_primary_call: int = 0
var current_secondary_call: int = 0
var current_countdown: int = 0
var mirror: bool = false

func _init() -> void:
	_load_textures()
	_ensure_nodes()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_nodes()

func _ensure_nodes() -> void:
	if container != null:
		return
	_setup_nodes()

func _load_textures() -> void:
	if not textures.is_empty():
		return
	textures.clear()
	for f: String in ICON_FILES:
		var svg_path: String = SVG_DIR + f
		var png_path: String = svg_path.replace(".svg", ".png")
		var tex: Texture2D = null
		if ResourceLoader.exists(svg_path):
			tex = load(svg_path) as Texture2D
		elif ResourceLoader.exists(png_path):
			tex = load(png_path) as Texture2D
		elif FileAccess.file_exists(svg_path):
			var abs_svg := ProjectSettings.globalize_path(svg_path)
			var img := Image.load_from_file(abs_svg)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
		elif FileAccess.file_exists(png_path):
			var abs_png := ProjectSettings.globalize_path(png_path)
			var img := Image.load_from_file(abs_png)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
		textures.append(tex)

func _setup_nodes() -> void:
	container = HBoxContainer.new()
	container.name = "IconContainer"
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	primary_rect = TextureRect.new()
	primary_rect.name = "PrimaryIcon"
	primary_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	primary_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	primary_rect.custom_minimum_size = Vector2(80, 80)
	primary_rect.pivot_offset = Vector2(40, 40)
	primary_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(primary_rect)

	secondary_rect = TextureRect.new()
	secondary_rect.name = "SecondaryIcon"
	secondary_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	secondary_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	secondary_rect.custom_minimum_size = Vector2(80, 80)
	secondary_rect.pivot_offset = Vector2(40, 40)
	secondary_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(secondary_rect)

	primary_rect.visible = false
	secondary_rect.visible = false

func update_hud(record: Dictionary, is_mirror: bool = false) -> void:
	_ensure_nodes()
	mirror = is_mirror
	if record.is_empty() or (record.get("flags", 0) & 0x100) == 0:
		primary_rect.visible = false
		secondary_rect.visible = false
		return

	var primary_id: int = record.get("primary_call_id", 0)
	var secondary_id: int = record.get("secondary_call_id", 0)
	var countdown: int = record.get("flags", 0) & 0xff
	current_primary_call = primary_id
	current_secondary_call = secondary_id
	current_countdown = countdown

	# Layout position: top center
	var viewport_size := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var top_margin := viewport_size.y * 0.05
	container.size = Vector2(viewport_size.x, 90)
	container.position = Vector2(0, top_margin)

	var has_second: bool = secondary_id != 0
	_render_icon(primary_rect, primary_id, countdown, has_second, false)
	if has_second:
		_render_icon(secondary_rect, secondary_id, countdown, true, true)
		secondary_rect.visible = true
	else:
		secondary_rect.visible = false

func _render_icon(rect: TextureRect, call_id: int, countdown: int, has_two: bool, is_second: bool) -> void:
	var info: Dictionary = Cmr2PacenoteCodec.icon(call_id, mirror)
	if not info.visible:
		rect.visible = false
		return

	var idx: int = info.index
	if idx >= 0 and idx < textures.size() and textures[idx] != null:
		rect.texture = textures[idx]
		rect.visible = true
	else:
		rect.visible = false
		return

	rect.modulate = info.tint

	# Animation wobble based on OpenCMR2 Race.cpp:1138-1165
	var n := 50 - countdown
	var wobble_angle := 0.0
	if has_two:
		if is_second:
			if n < 20:
				wobble_angle = 1.0
			elif n < 30:
				wobble_angle = -float(CURVE_TABLE[30 - n]) / 1024.0
			elif n < 40:
				wobble_angle = 0.0
			elif n < 50:
				wobble_angle = -float(CURVE_TABLE[n - 40]) / 1024.0
			else:
				wobble_angle = 1.0
		else:
			if n < 10:
				wobble_angle = -float(CURVE_TABLE[10 - n]) / 1024.0
			elif n < 20:
				wobble_angle = 0.0
			elif n < 30:
				wobble_angle = -float(CURVE_TABLE[n - 20]) / 1024.0
			else:
				wobble_angle = 1.0
	else:
		if n >= 40:
			wobble_angle = -float(CURVE_TABLE[n - 40]) / 1024.0
		elif n > 10:
			wobble_angle = 0.0
		else:
			wobble_angle = float(CURVE_TABLE[10 - n]) / 1024.0

	var width_scale := cos(wobble_angle * PI * 0.5)
	var x_scale: float = (-1.0 if info.flip else 1.0) * width_scale
	rect.scale = Vector2(x_scale, 1.0)
