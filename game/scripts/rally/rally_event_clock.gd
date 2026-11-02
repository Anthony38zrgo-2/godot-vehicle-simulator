class_name RallyEventClock
extends RefCounted
## Autoridad única del reloj del evento.
## Separa tiempo deportivo (ms, lo lleva la sesión) de hora ambiental
## (fecha/hora del mundo para sol, cielo y clima).
## 1x significa: 10 minutos reales avanzan 10 minutos del mundo.

const ALLOWED_RATES := [0.0, 1.0, 2.0, 5.0]

var event_date: String = "2026-06-13"
var event_seconds: float = 8.0 * 3600.0
var rate: float = 1.0
var paused: bool = true
var itinerary_log: Array = []
var sky_node: Node = null
var tca_node: Node = null
# Guardar velocidades autónomas originales para no acelerar lluvia/viento
# más de lo que pida la tasa del evento.
var _sky_minutes_per_day: float = 24.0
var _tca_multiplier: float = 100.0

func configure(start_date: String, start_seconds: float, initial_rate: float = 1.0) -> void:
	event_date = start_date
	event_seconds = start_seconds
	set_rate(initial_rate)
	itinerary_log.append({"op": "configure", "date": event_date, "seconds": event_seconds})

func set_rate(next_rate: float) -> void:
	rate = next_rate if next_rate in ALLOWED_RATES else 1.0

func attach_adapters(sky: Node, tca: Node, sky_minutes_per_day: float = 24.0) -> void:
	sky_node = sky
	tca_node = tca
	_sky_minutes_per_day = maxf(sky_minutes_per_day, 0.1)
	if sky_node != null:
		var sky_mpd: Variant = sky_node.get("minutes_per_day")
		if sky_mpd != null:
			_sky_minutes_per_day = maxf(float(sky_mpd), 0.1)
		sky_node.set("game_time_enabled", false)
		_tca_multiplier = _tca_rate_to_multiplier(rate)
		_apply_to_adapters()
	if tca_node != null and tca_node.get("time_speed_multiplier") != null:
		_tca_multiplier = float(tca_node.get("time_speed_multiplier"))
		# Congelamos el avance autónomo: el reloj manda por saltos y ticks.
		tca_node.set("time_speed_multiplier", 0.0)

func detach_adapters() -> void:
	if sky_node != null and is_instance_valid(sky_node):
		sky_node.set("game_time_enabled", true)
	if tca_node != null and is_instance_valid(tca_node):
		tca_node.set("time_speed_multiplier", _tca_multiplier)
	sky_node = null
	tca_node = null

func set_paused(is_paused: bool) -> void:
	paused = is_paused

func tick(delta_seconds: float, driving: bool) -> void:
	# Pausa, carga y resultados detienen el reloj; cuenta atrás y
	# conducción lo avanzan según la configuración.
	if paused or not driving:
		return
	if is_zero_approx(rate):
		return
	event_seconds += delta_seconds * rate
	_normalize_day()
	_apply_to_adapters()

func jump_to(date: String, seconds: float, reason: String = "itinerary") -> void:
	# El salto de enlace cambia fecha/hora ambiental sin sumar deportivo.
	event_date = date
	event_seconds = seconds
	_normalize_day()
	itinerary_log.append({"op": "jump", "date": event_date, "seconds": event_seconds, "reason": reason})
	_apply_to_adapters()

func hour_of_day() -> float:
	return event_seconds / 3600.0

func formatted() -> String:
	var total := int(event_seconds)
	return "%02d:%02d" % [total / 3600, (total / 60) % 60]

func _normalize_day() -> void:
	while event_seconds >= 86400.0:
		event_seconds -= 86400.0
		event_date = _shift_date(event_date, 1)
	while event_seconds < 0.0:
		event_seconds += 86400.0
		event_date = _shift_date(event_date, -1)

func _shift_date(iso: String, delta_days: int) -> String:
	# Suma simple de días sobre calendario gregoriano para el rango del evento.
	var parts := iso.split("-")
	if parts.size() != 3:
		return iso
	var y := int(parts[0])
	var m := int(parts[1])
	var d := int(parts[2]) + delta_days
	var month_days := [31, 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	while d > month_days[m - 1]:
		d -= month_days[m - 1]
		m += 1
		if m > 12:
			m = 1
			y += 1
	while d < 1:
		m -= 1
		if m < 1:
			m = 12
			y -= 1
		d += month_days[m - 1]
	return "%04d-%02d-%02d" % [y, m, d]

func _tca_rate_to_multiplier(next_rate: float) -> float:
	# Un día de TCA dura los mismos minutos reales que un día de Sky3D.
	return (86400.0 / (_sky_minutes_per_day * 60.0)) * maxf(next_rate, 0.01)

func _apply_to_adapters() -> void:
	if sky_node != null and is_instance_valid(sky_node):
		sky_node.set("current_time", clampf(hour_of_day(), 0.0, 23.9998))
	if tca_node != null and is_instance_valid(tca_node):
		# Avance manual coherente: fijamos hora sin reactivar evolución autónoma.
		tca_node.set("time_of_day", fmod(event_seconds, 86400.0))
