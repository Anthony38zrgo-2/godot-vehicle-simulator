extends Control
## Menú previo del evento de Rusia: dificultad, semilla, jornadas, horario
## inicial, intervalo, horarios individuales, multiplicador ambiental y
## política de abandono. Vista previa completa del itinerario. Congela las
## reglas al comenzar para que la competición sea reproducible.
signal event_start_requested(choices: Dictionary)

const EventManagerScript := preload("res://scripts/rally/rally_event_manager.gd")

var difficulty_option: OptionButton
var seed_edit: SpinBox
var days_option: OptionButton
var rate_option: OptionButton
var preview: Label
var manager = null

func _ready() -> void:
	manager = EventManagerScript.new()
	manager.load_event()
	_build_ui()
	_refresh_preview()

func _build_ui() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	difficulty_option = OptionButton.new()
	for i in [1, 2, 3]:
		difficulty_option.add_item("Dificultad %d" % i, i)
	box.add_child(difficulty_option)
	seed_edit = SpinBox.new()
	seed_edit.min_value = 1
	seed_edit.max_value = 99999
	seed_edit.value = 1974
	box.add_child(seed_edit)
	days_option = OptionButton.new()
	days_option.add_item("Dos jornadas", 0)
	days_option.add_item("Un día", 1)
	box.add_child(days_option)
	rate_option = OptionButton.new()
	for r in [0.0, 1.0, 2.0, 5.0]:
		rate_option.add_item("%dx" % r, int(r * 10))
	box.add_child(rate_option)
	preview = Label.new()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(preview)
	var start := Button.new()
	start.text = "Comenzar Rally de Rusia (10 especiales)"
	start.pressed.connect(_on_start)
	box.add_child(start)
	difficulty_option.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	days_option.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	rate_option.item_selected.connect(func(_i: int) -> void: _refresh_preview())

func _choices() -> Dictionary:
	return {
		"difficulty": difficulty_option.get_selected_id(),
		"seed": int(seed_edit.value),
		"single_day": days_option.get_selected_id() == 1,
		"ambient_rate": float(rate_option.get_selected_id()) / 10.0,
	}

func _refresh_preview() -> void:
	var tmp = EventManagerScript.new()
	tmp.load_event()
	tmp.begin_event(_choices())
	var lines: Array = []
	for entry in tmp.itinerary:
		lines.append("%s · %s %s" % [entry.get("stage_id", ""), entry.get("date", ""), entry.get("start", "")])
	preview.text = "\n".join(lines)

func _on_start() -> void:
	event_start_requested.emit(_choices())
