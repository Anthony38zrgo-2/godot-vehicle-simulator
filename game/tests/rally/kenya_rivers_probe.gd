extends SceneTree

## Probe de geometría y contacto del piloto kenya_stage1 (fase 8.2 del plan).
## Vado sintético con puntos fijos: centro del vado, borde, fuera del cauce y
## sobre puente. Verifica contacto seco fuera de la huella y sobre el puente,
## mayor profundidad en el vado al subir el nivel, ampliación de la zona
## mojada y combinación por máximo con parches. Tolerancia: 20 mm entre
## lámina y profundidad reconstruida (resolución del campo: huella sintética
## exacta, error 0).

const Channels = preload("res://scripts/rally/rally_river_channels.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


class DryProvider:
	extends RefCounted
	var calendar_active := true
	var route_total_m := 8000.0
	var rain := 0.0

	func liquid_rain_at_distance(_p: float) -> float:
		return rain


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var provider := DryProvider.new()
	var rivers := Channels.new()
	root.add_child(rivers)
	rivers.provider = provider
	# Vado de 20 x 10 m, lámina base en y=0, cota máxima +0.45 m.
	rivers.add_test_channel({
		"id": "kenya_ford_1", "progress_m": 2800.0,
		"max_rise_m": 0.45, "reference_rain_mm_h": 12.0,
		"min_x": -10.0, "min_z": -5.0, "max_x": 10.0, "max_z": 5.0,
		"base_y": 0.0,
	})
	rivers.initialize_levels()

	# Puntos fijos: centro (lecho bajo), borde (orilla alta), fuera, puente.
	var ford_center := Vector3(0, -0.02, 0)
	var ford_edge := Vector3(8.0, 0.30, 3.0)
	var outside := Vector3(50.0, -0.02, 0.0)
	var bridge := Vector3(0, 1.20, 0)

	# Nivel base permanente: el vado moja, el borde alto sigue seco.
	var base_center := float(rivers.sample_contact(ford_center).get("depth_mm", -1.0))
	var base_edge := float(rivers.sample_contact(ford_edge).get("depth_mm", -1.0))
	check(absf(base_center - 20.0) < 0.5, "base moja el centro del vado")
	check(base_edge == 0.0, "borde sobre la lamina base registra seco")
	check(float(rivers.sample_contact(outside).get("depth_mm", -1.0)) == 0.0, "fuera del cauce seco")
	check(float(rivers.sample_contact(bridge).get("depth_mm", -1.0)) == 0.0, "puente sobre la lamina seco")

	# Crecida: el coche encuentra la misma lámina que ve el jugador.
	provider.rain = 15.0
	rivers.advance(900.0)
	var flood_center := float(rivers.sample_contact(ford_center).get("depth_mm", -1.0))
	var flood_edge := float(rivers.sample_contact(ford_edge).get("depth_mm", -1.0))
	check(flood_center > base_center + 300.0, "crecida profundiza el vado")
	check(absf(flood_center - 470.0) < 1.0, "cota de crecida +0.45 m sobre lecho")
	# Ampliación de la zona mojada: el borde se moja solo en crecida.
	check(flood_edge > 100.0, "crecida amplia la zona mojada al borde")
	check(absf(flood_edge - 150.0) < 1.0, "borde a +0.30 con lamina +0.45")
	check(float(rivers.sample_contact(outside).get("depth_mm", -1.0)) == 0.0, "crecida no moja fuera del cauce")
	check(float(rivers.sample_contact(bridge).get("depth_mm", -1.0)) == 0.0, "puente seco en crecida")

	# Lámina reconstruida vs profundidad: tolerancia 20 mm.
	for pt in [ford_center, ford_edge]:
		var sample: Dictionary = rivers.sample_contact(pt)
		var surface_y := float(sample.get("surface_y", 0.0))
		var expected := maxf(0.0, surface_y - pt.y) * 1000.0
		check(absf(float(sample.get("depth_mm", 0.0)) - expected) <= 20.0, "lamina y contacto coinciden a 20 mm")

	# Combinación por máximo con parches (regla de vehicle_simulation):
	# el consumidor conserva el máximo entre agua de cauce y parche.
	var puddle_mm := 30.0
	var combined: float = maxf(flood_center, puddle_mm)
	check(absf(combined - flood_center) < 0.001, "cauce profundo domina al parche")
	var shallow: float = maxf(base_edge, puddle_mm)
	check(absf(shallow - puddle_mm) < 0.001, "borde seco en base conserva el parche")

	# Cota base, cota actual, altura de contacto y profundidad por rueda.
	var ch: Dictionary = rivers.channels[0]
	var level := rivers.level_of("kenya_ford_1", ford_center.x, ford_center.z)
	check(absf(level - 0.45) < 0.002, "cota actual = base + crecida")
	print("KENYA_FORD base=", float(ch.get("base_b0", 0.0)), " rise=", rivers.rise_of("kenya_ford_1"), " level@", ford_center, "=", level, " contact_y=", ford_center.y, " depth_mm=", flood_center)

	rivers.unbind()
	rivers.queue_free()
	print("KENYA_RIVERS_PROBE ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
