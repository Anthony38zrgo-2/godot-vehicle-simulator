extends SceneTree

## Contrato headless del agua dinámica de Kenia (fase 8.1 del plan).
## Modelo de primer orden por cauce con clima EN EL PROGRESO FIJO del cauce:
## seco, lluvia ligera, tormenta, drenaje, tope, dos deltas de simulación,
## pausa, dos secciones con clima distinto, determinismo, independencia de la
## posición del coche, snapshots antiguos, reintento, reanudación, rescate y
## carga de otra especial. Sin escena ni GLB (canales sintéticos).

const Channels = preload("res://scripts/rally/rally_river_channels.gd")

var failures: Array[String] = []


class FakeWeather:
	extends RefCounted
	var calendar_active := true
	var route_total_m := 10000.0
	var mode := "dry"

	func liquid_rain_at_distance(progress_m: float) -> float:
		match mode:
			"dry":
				return 0.0
			"light":
				return 2.5
			"storm":
				return 15.0
			"split":
				return 2.5 if progress_m < 5000.0 else 15.0
		return 0.0

	func blended_state_at_distance(_d: float) -> Dictionary:
		return {"climate": {"precipitation_mm_h": 0.0}, "precipitation_kind": "none"}


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func make_two_section(provider: FakeWeather) -> Channels:
	var rivers := Channels.new()
	root.add_child(rivers)
	rivers.provider = provider
	rivers.add_test_channel({"id": "ford_a", "progress_m": 2500.0})
	rivers.add_test_channel({"id": "ford_b", "progress_m": 7500.0})
	return rivers


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# Seco: nivel base permanente, sin residuo.
	var provider := FakeWeather.new()
	provider.mode = "dry"
	var rivers := make_two_section(provider)
	rivers.initialize_levels()
	check(absf(rivers.rise_of("ford_a")) < 0.0005, "seco inicia en nivel base")
	rivers.advance(300.0)
	check(absf(rivers.rise_of("ford_a")) < 0.0005, "seco conserva nivel base")

	# Lluvia ligera vs tormenta: curvas distinguibles.
	provider.mode = "light"
	rivers.advance(600.0)
	var light_rise := rivers.rise_of("ford_a")
	check(absf(light_rise - 0.45 * (2.5 / 12.0)) < 0.01, "ligera alcanza su objetivo parcial")
	provider.mode = "storm"
	rivers.advance(600.0)
	var storm_rise := rivers.rise_of("ford_a")
	check(storm_rise > light_rise + 0.2, "tormenta y ligera distinguibles")
	# Tope: respeta cota máxima.
	check(absf(storm_rise - 0.45) < 0.005, "tormenta respeta cota maxima")

	# Drenaje: retrocede al escampar sin residuo.
	provider.mode = "dry"
	rivers.advance(900.0)
	check(absf(rivers.rise_of("ford_a")) < 0.001, "drenaje vuelve a base sin residuo")

	# Dos deltas de simulación: mismo resultado.
	provider.mode = "storm"
	rivers.initialize_levels()
	rivers.advance(60.0)
	var co_msg := rivers.rise_of("ford_a")
	var rivers2 := make_two_section(provider)
	rivers2.initialize_levels()
	for i in 600:
		rivers2.advance(0.1)
	check(absf(rivers2.rise_of("ford_a") - co_msg) < 0.002, "independiente del delta de simulacion")

	# Pausa: sin advance no hay crecida (congelada en reglaje/pausa/resultados).
	var frozen := rivers2.rise_of("ford_a")
	check(absf(rivers2.rise_of("ford_a") - frozen) < 0.000001, "pausa congela la crecida")

	# Determinismo: misma lluvia, mismo resultado.
	var rivers3 := make_two_section(provider)
	rivers3.initialize_levels()
	rivers3.advance(60.0)
	check(absf(rivers3.rise_of("ford_a") - co_msg) < 0.000001, "determinista ante misma historia")

	# Dos secciones con clima distinto responden a su ubicación.
	provider.mode = "split"
	var rivers4 := make_two_section(provider)
	rivers4.initialize_levels()
	rivers4.advance(600.0)
	check(rivers4.rise_of("ford_b") > rivers4.rise_of("ford_a") + 0.2, "cada cauce responde a su clima")

	# Independencia de la posición del coche.
	var before := rivers4.rise_of("ford_a")
	rivers4.sample_contact(Vector3(0, -1, 0))
	rivers4.sample_contact(Vector3(8000, -1, 9000))
	check(absf(rivers4.rise_of("ford_a") - before) < 0.000001, "consultar no altera el clima del rio")

	# Reintento: restaura la condición inicial del intento.
	rivers4.store_initial()
	provider.mode = "storm"
	rivers4.advance(300.0)
	rivers4.restore_initial()
	check(absf(rivers4.rise_of("ford_a") - before) < 0.0005, "reintento restaura condicion inicial")

	# Reanudación: el nivel acumulado se conserva.
	var saved: Dictionary = rivers4.snapshot()
	var rivers5 := make_two_section(provider)
	rivers5.restore_snapshot(saved)
	check(absf(rivers5.rise_of("ford_a") - rivers4.rise_of("ford_a")) < 0.000001, "reanudar conserva nivel")

	# Snapshots antiguos o IDs ausentes: inicialización determinista.
	var rivers6 := make_two_section(provider)
	provider.mode = "dry"
	rivers6.restore_snapshot({})
	check(absf(rivers6.rise_of("ford_a")) < 0.0005, "snapshot vacio inicia en base en seco")
	provider.mode = "storm"
	rivers6.restore_snapshot({"version": 99, "channels": {}})
	check(absf(rivers6.rise_of("ford_a") - 0.45 * 0.5) < 0.01, "version desconocida usa fraccion calibrada en lluvia")

	# Umbral de cauce seco: por debajo no activa.
	var rivers7 := Channels.new()
	root.add_child(rivers7)
	rivers7.provider = provider
	provider.mode = "light"
	rivers7.add_test_channel({"id": "dry_creek", "progress_m": 100.0, "activation_threshold_mm_h": 5.0})
	rivers7.initialize_levels()
	rivers7.advance(600.0)
	check(absf(rivers7.rise_of("dry_creek")) < 0.0005, "cauce seco bajo umbral registra seco")
	provider.mode = "storm"
	rivers7.advance(600.0)
	check(rivers7.rise_of("dry_creek") > 0.3, "cauce seco sobre umbral responde")

	# Otra especial sin cauce confirmado: consulta seca, sin controlador activo.
	var rivers8 := Channels.new()
	root.add_child(rivers8)
	rivers8.provider = provider
	rivers8.configure("kenya_stage4", null, provider)
	check(rivers8.active_channel_count() == 0, "etapa sin agua confirmada no activa cauces")
	check(float(rivers8.sample_contact(Vector3.ZERO).get("depth_mm", -1.0)) == 0.0, "etapa sin cauce registra seco")

	# Reglas de precipitación: nieve fuera, mixto explícito.
	check(Channels._liquid_from_state({"climate": {"precipitation_mm_h": 10.0}, "precipitation_kind": "snow"}) == 0.0, "nieve fuera de escorrentia")
	check(absf(Channels._liquid_from_state({"climate": {"precipitation_mm_h": 10.0}, "precipitation_kind": "mixed"}) - 6.0) < 0.0001, "mixto con fraccion liquida explicita")
	check(absf(Channels._liquid_from_state({"climate": {"precipitation_mm_h": 7.0}, "precipitation_kind": "rain"}) - 7.0) < 0.0001, "lluvia integra")

	# Adaptador de práctica: cubre las opciones reales (soleado/nublado/lluvia/aleatorio + alias).
	check(Channels.practice_rain_for_choice("sunny") == 0.0, "practica soleado seco")
	check(Channels.practice_rain_for_choice("cloudy") == 0.0, "practica nublado seco")
	check(Channels.practice_rain_for_choice("nublado") == 0.0, "practica nublado alias seco")
	check(Channels.practice_rain_for_choice("medium_precipitation") > 3.0, "practica lluvia moja")
	check(Channels.practice_rain_for_choice("lluvia") > 0.0, "practica lluvia alias moja")
	check(Channels.practice_rain_for_choice("random") == 0.0, "practica aleatorio determinista seco")
	check(Channels.practice_rain_for_choice("clear") == 0.0, "single_stage clear seco")

	for r in [rivers, rivers2, rivers3, rivers4, rivers5, rivers6, rivers7, rivers8]:
		r.unbind()
		r.queue_free()
	print("KENYA_RIVERS_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
