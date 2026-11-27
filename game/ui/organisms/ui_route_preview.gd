class_name UIRoutePreview
extends Control
## Unified 2D stage route preview supporting standard trajectory, 5-sector weather/surface coloring,
## start/finish markers, highlight state, and optional elevation profile strip.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")

@export var padding_px: float = 14.0
@export var show_background_well: bool = false
@export var show_elevation_strip: bool = false

var normalized_points: PackedVector2Array = PackedVector2Array()
var aspect_ratio: float = 1.0
var is_highlighted: bool = false
var sector_colors: Array[Color] = []
var elevations_m: PackedFloat32Array = PackedFloat32Array()
var title_overlay: String = ""


func _init(pts: PackedVector2Array = PackedVector2Array(), asp: float = 1.0) -> void:
	normalized_points = pts
	aspect_ratio = asp
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 140)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func set_route(pts: PackedVector2Array, asp: float = 1.0, sectors: Array[Color] = [], elevs: PackedFloat32Array = PackedFloat32Array()) -> void:
	normalized_points = pts
	aspect_ratio = asp
	sector_colors = sectors
	elevations_m = elevs
	queue_redraw()


func set_highlight(val: bool) -> void:
	if is_highlighted != val:
		is_highlighted = val
		queue_redraw()


func _draw() -> void:
	if show_background_well:
		var sb := _Tokens.get_flat_stylebox(_Tokens.get_color("bg_well"), _Tokens.get_color("border_subtle"), 1, _Tokens.get_radius("technical"))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
	if normalized_points.size() < 2:
		return

	var elev_h := 34.0 if (show_elevation_strip and elevations_m.size() >= 2) else 0.0
	var pad := padding_px
	var avail_w := size.x - pad * 2.0
	var avail_h := size.y - pad * 2.0 - elev_h
	if avail_w <= 10.0 or avail_h <= 10.0:
		return

	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in normalized_points:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var extent := max_p - min_p
	extent.x = maxf(extent.x, 0.001)
	extent.y = maxf(extent.y, 0.001)

	var fit_scale := minf(avail_w / extent.x, avail_h / extent.y)
	var draw_size := extent * fit_scale
	var offset := Vector2(pad, pad) + (Vector2(avail_w, avail_h) - draw_size) * 0.5 - min_p * fit_scale

	var screen_pts := PackedVector2Array()
	screen_pts.resize(normalized_points.size())
	for i in normalized_points.size():
		screen_pts[i] = offset + normalized_points[i] * fit_scale

	var glow_col := Color(0.95, 0.75, 0.25, 0.35) if is_highlighted else Color(1.0, 1.0, 1.0, 0.08)
	draw_polyline(screen_pts, glow_col, 5.0, true)

	if sector_colors.size() >= 2 and screen_pts.size() >= sector_colors.size() + 1:
		var n_sec := sector_colors.size()
		for s in n_sec:
			var i0 := int(floor(float(s) / float(n_sec) * float(screen_pts.size() - 1)))
			var i1 := int(ceil(float(s + 1) / float(n_sec) * float(screen_pts.size() - 1)))
			i1 = mini(i1, screen_pts.size() - 1)
			if i1 > i0:
				var seg := PackedVector2Array()
				for k in range(i0, i1 + 1):
					seg.append(screen_pts[k])
				draw_polyline(seg, sector_colors[s], 2.8, true)
	else:
		var core_col := Color("#f8df9e") if is_highlighted else Color("#c4d7e6")
		draw_polyline(screen_pts, core_col, 2.2, true)

	draw_circle(screen_pts[0], 4.5, _Tokens.get_color("status_success"))
	draw_circle(screen_pts[0], 2.0, Color.WHITE)
	draw_circle(screen_pts[-1], 4.5, _Tokens.get_color("status_danger"))
	draw_circle(screen_pts[-1], 2.0, Color.WHITE)

	if elev_h > 0.0:
		_draw_elevation_strip(Rect2(pad, size.y - elev_h - 4.0, avail_w, elev_h - 4.0))


func _draw_elevation_strip(rect: Rect2) -> void:
	var min_e := INF
	var max_e := -INF
	for e in elevations_m:
		min_e = minf(min_e, e)
		max_e = maxf(max_e, e)
	var span := maxf(max_e - min_e, 1.0)
	var pts := PackedVector2Array()
	var n := elevations_m.size()
	for i in n:
		var fx := float(i) / float(maxi(1, n - 1))
		var fy := (elevations_m[i] - min_e) / span
		pts.append(Vector2(rect.position.x + fx * rect.size.x, rect.end.y - fy * rect.size.y))
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), _Tokens.get_color("border_subtle"), 1.0)
	if pts.size() >= 2:
		draw_polyline(pts, _Tokens.get_color("accent_rally"), 1.8, true)
