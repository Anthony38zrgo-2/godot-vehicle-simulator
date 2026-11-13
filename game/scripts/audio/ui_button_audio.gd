extends AudioStreamPlayer

const BUTTON_CLICK := preload("res://sounds/ui/ClicksSmall.aclick3.wav")
# Extracted from Unreal Tournament's Activates.uax (ClicksBig.start14).
const TAB_CLICK := preload("res://sounds/ui/ClicksBig.start14.wav")
# Extracted from Unreal Tournament's Activates.uax (Beeps.mactiv63).
const REPAIR_SELECTION := preload("res://sounds/ui/Beeps.mactiv63.wav")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	volume_db = -5.0
	# Extracted from Unreal Tournament's Activates.uax (ClicksSmall.aclick3).
	get_tree().node_added.connect(_connect_button)
	for button in get_tree().root.find_children("*", "BaseButton", true, false):
		_connect_button(button)


func _connect_button(node: Node) -> void:
	var button := node as BaseButton
	if button != null and not button.has_meta("custom_button_sound") and not button.pressed.is_connected(_play_click):
		button.pressed.connect(_play_click)


func _play_click() -> void:
	stream = BUTTON_CLICK
	play()


func play_tab_click() -> void:
	stream = TAB_CLICK
	play()


func play_repair_selection() -> void:
	stream = REPAIR_SELECTION
	play()
