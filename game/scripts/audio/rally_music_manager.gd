extends Node

## Gestor persistente de música del menú, garaje, pausa y resultados.
## - Menú / Garaje-reglajes / Servicio / Resultados-competición (menu_theme.mp3):
##   misma pista en continuo, sin fade in y sin corte entre ellos (menú <->
##   garaje, servicio <-> garaje, resultados <-> garaje). Solo arranca desde 0
##   si estaba en silencio (tras rally, o primera entrada).
## - Pausa en carrera (garage_theme.mp3 = DM-Tempest2.mp3): solo para el menú de
##   pausa; cada apertura corta y reinicia desde el inicio, sin fade in.
## - Entrada a rally: corte inmediato (stop). Transición entre etapas: el tema
##   del menú sigue sonando para no cortar resultados -> garaje/servicio.
## Nota: results_theme.ogg se sigue cargando por compatibilidad pero ya no se
## usa para ningún panel (todos usan el tema del menú salvo la pausa).

const MENU_MUSIC_PATH := "res://sounds/music/menu_theme.mp3"
const GARAGE_MUSIC_PATH := "res://sounds/music/garage_theme.mp3"
const RESULTS_MUSIC_PATH := "res://sounds/music/results_theme.ogg"
const DEFAULT_VOLUME_DB := -3.0
const GARAGE_VOLUME_DB := -4.0
const RESULTS_VOLUME_DB := -4.0
# Duraciones heredadas: ya no se usan (sin fades). Se conservan por compat.
const MENU_FADE_IN_DURATION := 0.8
const CROSSFADE_DURATION := 2.0
const RESULTS_FADE_IN_DURATION := 2.0
const RESULTS_FADE_OUT_DURATION := 1.0
const RACE_FADE_OUT_DURATION := 1.0
const PAUSE_FADE_IN_DURATION := 1.2
const PAUSE_FADE_OUT_DURATION := 0.8
const DIP_OUT_DURATION := 0.6
const SILENCE_DB := -40.0

# Alias heredado: antes había un único `player` (menú). Se mantiene apuntando
# al reproductor del menú para no romper accesos externos.
var player: AudioStreamPlayer
var menu_player: AudioStreamPlayer
var garage_player: AudioStreamPlayer
var results_player: AudioStreamPlayer
var menu_stream: AudioStream
var garage_stream: AudioStream
var results_stream: AudioStream
var current_context: String = "none"

var _menu_tween: Tween
var _garage_tween: Tween
var _results_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_music_bus()
	menu_player = _make_player("MenuMusicPlayer")
	garage_player = _make_player("GarageMusicPlayer")
	results_player = _make_player("ResultsMusicPlayer")
	player = menu_player
	_load_streams()


func _make_player(node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = "Music"
	p.volume_db = SILENCE_DB
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


func _ensure_music_bus() -> void:
	var idx := -1
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == "Music":
			idx = i
			break
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")


func _load_single_stream(path: String) -> AudioStream:
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null and FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			if path.to_lower().ends_with(".ogg"):
				var ogg := AudioStreamOggVorbis.new()
				ogg.data = bytes
				stream = ogg
			else:
				var mp3 := AudioStreamMP3.new()
				mp3.data = bytes
				stream = mp3
	_apply_loop(stream)
	return stream


func _apply_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


func _load_streams() -> void:
	if menu_stream == null:
		menu_stream = _load_single_stream(MENU_MUSIC_PATH)
	if garage_stream == null:
		garage_stream = _load_single_stream(GARAGE_MUSIC_PATH)
	if results_stream == null:
		results_stream = _load_single_stream(RESULTS_MUSIC_PATH)


func _kill_all_tweens() -> void:
	if _menu_tween != null and _menu_tween.is_valid():
		_menu_tween.kill()
	if _garage_tween != null and _garage_tween.is_valid():
		_garage_tween.kill()
	if _results_tween != null and _results_tween.is_valid():
		_results_tween.kill()


func _stop_immediate(p: AudioStreamPlayer) -> void:
	if p != null and is_instance_valid(p) and p.playing:
		p.stop()


func _play_immediate(p: AudioStreamPlayer, stream: AudioStream, volume_db: float) -> void:
	if p == null or not is_instance_valid(p) or stream == null:
		return
	# Corte + reinicio desde el inicio, sin fade in: volumen final directo.
	if p.playing:
		p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.play()


# Menú / garaje / servicio / resultados comparten el tema del menú en
# continuo: si ya suena, sigue sin cortarse ni reiniciarse (solo fija
# contexto y volumen final, sin fade). Solo arranca desde 0 si estaba
# en silencio o sonaba otra pista (p. ej. tras rally o transición con corte).
func _enter_menu_context(context: String) -> void:
	if menu_stream == null:
		_load_streams()
	if menu_stream == null or menu_player == null:
		return
	_kill_all_tweens()
	_stop_immediate(garage_player)
	_stop_immediate(results_player)
	current_context = context
	if menu_player.playing and menu_player.stream == menu_stream:
		menu_player.volume_db = DEFAULT_VOLUME_DB
	else:
		_play_immediate(menu_player, menu_stream, DEFAULT_VOLUME_DB)


func _fade_player(p: AudioStreamPlayer, target_db: float, duration: float, stop_after: bool, slot: String) -> void:
	# Sin uso: se conserva por compatibilidad. La norma actual es corte
	# inmediato + arranque a volumen final (sin fade in / sin crossfade).
	if p == null or not is_instance_valid(p):
		return
	if slot == "menu":
		if _menu_tween != null and _menu_tween.is_valid():
			_menu_tween.kill()
	elif slot == "garage":
		if _garage_tween != null and _garage_tween.is_valid():
			_garage_tween.kill()
	else:
		if _results_tween != null and _results_tween.is_valid():
			_results_tween.kill()
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(p, "volume_db", target_db, maxf(duration, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if stop_after:
		tw.tween_callback(func() -> void:
			if is_instance_valid(p):
				p.stop()
		)
	if slot == "menu":
		_menu_tween = tw
	elif slot == "garage":
		_garage_tween = tw
	else:
		_results_tween = tw


# Sin uso: se conserva por compatibilidad (antes dip entre resultados<->garaje).
func _dip_player(p: AudioStreamPlayer, target_db: float, slot: String) -> void:
	if p == null or not is_instance_valid(p):
		return
	if slot == "menu":
		if _menu_tween != null and _menu_tween.is_valid():
			_menu_tween.kill()
	elif slot == "garage":
		if _garage_tween != null and _garage_tween.is_valid():
			_garage_tween.kill()
	else:
		if _results_tween != null and _results_tween.is_valid():
			_results_tween.kill()
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(p, "volume_db", SILENCE_DB, maxf(DIP_OUT_DURATION, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "volume_db", target_db, maxf(CROSSFADE_DURATION, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if slot == "menu":
		_menu_tween = tw
	elif slot == "garage":
		_garage_tween = tw
	else:
		_results_tween = tw


func play_menu_music() -> void:
	# Menú principal: sigue sin corte si el tema ya sonaba (viene de
	# garaje/servicio); arranca desde 0 solo si estaba en silencio.
	_enter_menu_context("menu")


func stop_menu_music() -> void:
	_kill_all_tweens()
	_stop_immediate(menu_player)
	if current_context == "menu":
		current_context = "none"


func on_enter_garage() -> void:
	# Garaje-reglajes usa el tema del menú en continuo: sin corte si ya sonaba.
	_enter_menu_context("garage")


func on_enter_service() -> void:
	# Servicio usa el tema del menú en continuo: sin corte si ya sonaba.
	_enter_menu_context("service")


func on_enter_results() -> void:
	# Resultados-competición usa el tema del menú en continuo: sin corte.
	_enter_menu_context("results")


# Transición entre etapas (misma escena, cambio de geometría): el tema del
# menú sigue sin cortarse para enlazar resultados -> garaje/servicio.
func on_begin_stage_transition() -> void:
	_kill_all_tweens()
	_stop_immediate(garage_player)
	_stop_immediate(results_player)
	if menu_player != null and is_instance_valid(menu_player):
		if menu_stream == null:
			_load_streams()
		if menu_player.playing and menu_player.stream == menu_stream:
			menu_player.volume_db = DEFAULT_VOLUME_DB
		elif menu_stream != null:
			_play_immediate(menu_player, menu_stream, DEFAULT_VOLUME_DB)
	current_context = "transition"


func on_start_rally() -> void:
	# Al empezar el rally: corte inmediato, sin fade out arrastrado.
	_kill_all_tweens()
	_stop_immediate(menu_player)
	_stop_immediate(garage_player)
	_stop_immediate(results_player)
	current_context = "race"


func on_pause_opened() -> void:
	if garage_stream == null:
		_load_streams()
	if garage_stream == null or garage_player == null:
		return
	# Pausa: DM-Tempest2 siempre se reinicia desde 0, sin fade in,
	# aunque ya estuviera en pausa (re-pulsar pausa = reinicio).
	_kill_all_tweens()
	_stop_immediate(menu_player)
	_stop_immediate(results_player)
	current_context = "pause"
	_play_immediate(garage_player, garage_stream, GARAGE_VOLUME_DB)


func on_pause_closed() -> void:
	if current_context != "pause":
		return
	# Al reanudar: corte inmediato para que la próxima pausa reinicie.
	_kill_all_tweens()
	_stop_immediate(garage_player)
	current_context = "race"


func is_playing_menu_music() -> bool:
	return menu_player != null and menu_player.playing and menu_player.stream == menu_stream and (current_context == "menu" or current_context == "garage" or current_context == "service" or current_context == "results" or current_context == "transition")


func is_playing_garage_music() -> bool:
	# Garaje-reglajes y servicio usan el tema del menú; pausa usa DM-Tempest2.
	if current_context == "garage" or current_context == "service":
		return menu_player != null and menu_player.playing and menu_player.stream == menu_stream
	if current_context == "pause":
		return garage_player != null and garage_player.playing and garage_player.stream == garage_stream
	return false


func is_playing_results_music() -> bool:
	# Resultados-competición usa el tema del menú. Se acepta el stream
	# heredado por compatibilidad con partidas/tests antiguos.
	if current_context != "results":
		return false
	if menu_player != null and menu_player.playing and menu_player.stream == menu_stream:
		return true
	return results_player != null and results_player.playing and results_player.stream == results_stream
