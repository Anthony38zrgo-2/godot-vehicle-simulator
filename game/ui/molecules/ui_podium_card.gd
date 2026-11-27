class_name UIPodiumCard
extends PanelContainer
## Gold / Silver / Bronze podium card for championship and rally final results.

const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")
const _Theme := preload("res://scripts/ui/core/ui_theme_builder.gd")

var rank_label: Label
var driver_label: Label
var team_label: Label
var time_label: Label
var points_label: Label
var _vbox: VBoxContainer


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _vbox != null:
		return
	_vbox = get_node_or_null("PodiumVBox") as VBoxContainer
	if _vbox == null:
		_vbox = VBoxContainer.new()
		_vbox.name = "PodiumVBox"
		_vbox.add_theme_constant_override("separation", 4)
		add_child(_vbox)

	rank_label = _vbox.get_node_or_null("RankLabel") as Label
	if rank_label == null:
		rank_label = Label.new()
		rank_label.name = "RankLabel"
		_vbox.add_child(rank_label)

	driver_label = _vbox.get_node_or_null("DriverLabel") as Label
	if driver_label == null:
		driver_label = Label.new()
		driver_label.name = "DriverLabel"
		_vbox.add_child(driver_label)

	team_label = _vbox.get_node_or_null("TeamLabel") as Label
	if team_label == null:
		team_label = Label.new()
		team_label.name = "TeamLabel"
		_vbox.add_child(team_label)

	time_label = _vbox.get_node_or_null("TimeLabel") as Label
	if time_label == null:
		time_label = Label.new()
		time_label.name = "TimeLabel"
		_vbox.add_child(time_label)

	points_label = _vbox.get_node_or_null("PointsLabel") as Label
	if points_label == null:
		points_label = Label.new()
		points_label.name = "PointsLabel"
		_vbox.add_child(points_label)


func configure(rank: int, competitor_name: String, car_team: String, total_time: String, points_text: String, is_player: bool) -> void:
	_ensure_nodes()
	var accent := _Tokens.get_color("accent_rally")
	if rank == 2:
		accent = _Tokens.get_color("podium_silver")
	elif rank == 3:
		accent = _Tokens.get_color("podium_bronze")
	elif rank > 3:
		accent = _Tokens.get_color("border_card")

	var bg := _Tokens.get_color("bg_elevated" if is_player else "bg_card")
	add_theme_stylebox_override("panel", _Theme.make_flat_panel(bg, accent, 2 if (is_player or rank == 1) else 1, _Tokens.get_radius("technical"), 14, 10))
	_Theme.apply_label(rank_label, "accent", 18, false, true)
	rank_label.add_theme_color_override("font_color", accent)
	rank_label.text = "#%d" % rank
	_Theme.apply_label(driver_label, "white" if is_player else "primary", 15, false, true)
	driver_label.text = competitor_name
	_Theme.apply_label(team_label, "muted", 11, false, false)
	team_label.text = car_team
	_Theme.apply_label(time_label, "data", 15, true, true)
	time_label.text = total_time
	_Theme.apply_label(points_label, "accent" if not points_text.is_empty() else "dim", 12, true, true)
	points_label.text = points_text
	points_label.visible = not points_text.is_empty()
