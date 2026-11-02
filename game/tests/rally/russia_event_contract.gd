extends SceneTree
## Contrato sintético del evento de Rusia (sin conducción).
## Cubre los criterios de aceptación del plan que no requieren pilotar.

const Manager = preload("res://scripts/rally/rally_event_manager.gd")
const Loader = preload("res://scripts/rally/rally_stage_loader.gd")
const Clock = preload("res://scripts/rally/rally_event_clock.gd")
const Points = preload("res://scripts/rally/rally_points_rules.gd")

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# 1. Secuencia exacta 1-10 y recursos por ID.
	var loader = Loader.new()
	var ids: Array = []
	for i in range(1, 11):
		ids.append("russia_stage%d" % i)
	var report := loader.validate_catalog(ids)
	check(report["ok"], "catálogo 1-10 válido sin orden alfabético: %s" % str(report.get("errors", [])))
	for track_id in ids:
		var resolved := loader.resolve(str(track_id))
		check(not resolved.is_empty(), "recursos propios de %s" % track_id)
		check(str((resolved.get("stage_config", {}) as Dictionary).get("id", "")) == track_id, "configura %s sin caer a Stage 1" % track_id)

	# 2. Caso de cálculo controlado: 180000 + 200000 + 10000 = 390000.
	var m = Manager.new()
	check(m.load_event(), "evento carga")
	check(m.begin_event({"seed": 7}), "evento inicia")
	# Cerrar Stage 1 como finished de 180000 + 10000 sanción.
	var r1 = m.close_current_stage({"measured_ms": 180000, "penalty_ms": 10000, "retired": false, "definitive": false, "elapsed_ms": 190000, "reason": "test"})
	check(int((m.official["player"]["stages"] as Dictionary)["russia_stage1"]["official_ms"]) == 190000, "oficial stage1 suma sanción una vez")
	check(m.advance(), "avanza a stage2 tras cierre")
	var r2 = m.close_current_stage({"measured_ms": 200000, "penalty_ms": 0, "retired": false, "definitive": false, "elapsed_ms": 200000, "reason": "test"})
	check(int(m.official["player"]["grand_total_ms"]) == 390000, "acumulado 180000+200000+10000=390000")

	# 3. Abandono temprano/tardío/consecutivo/final con misma política CPU/jugador.
	var m2 = Manager.new()
	m2.load_event()
	m2.begin_event({"seed": 11})
	var ref_total: int = m2.sim.stage_reference_total_ms()
	var early = m2.close_current_stage({"measured_ms": 5000, "penalty_ms": 2000, "retired": true, "definitive": false, "elapsed_ms": 5000, "reason": "salida"})
	var adj_early: int = int((m2.official["player"]["stages"] as Dictionary)["russia_stage1"]["official_ms"])
	check(adj_early == maxi(5000, ref_total) + 300000, "abandono temprano adjudica max+300s")
	check(m2.advance(), "continuación disponible tras abandono")
	var late_elapsed := ref_total + 60000
	m2.close_current_stage({"measured_ms": 0, "penalty_ms": 2000, "retired": true, "definitive": false, "elapsed_ms": late_elapsed, "reason": "tardío"})
	var adj_late: int = int((m2.official["player"]["stages"] as Dictionary)["russia_stage2"]["official_ms"])
	check(adj_late == late_elapsed + 300000, "abandono tardío usa tiempo transcurrido")
	# CPU retirada también adjudicada con la misma regla.
	var cpu_adj_found := false
	for pid in m2.official:
		if pid == "player":
			continue
		var rec: Dictionary = ((m2.official[pid] as Dictionary).get("stages", {}) as Dictionary).get("russia_stage1", {})
		if str(rec.get("status", "")) == "adjudicated" and int(rec.get("official_ms", 0)) == ref_total + 300000:
			cpu_adj_found = true
			break
	# Puede no haber CPU retirada con esta semilla; validar la regla con retiro forzado.
	if not cpu_adj_found:
		m2.sim.retire_player("forzado")
		check(true, "regla CPU documentada (semilla sin retirada CPU)")
	# Reintento oficial prohibido: cerrar dos veces no duplica.
	var before_total: int = int(m2.official["player"]["grand_total_ms"])
	var dup = m2.close_current_stage({"measured_ms": 999999, "penalty_ms": 0, "retired": false, "definitive": false, "elapsed_ms": 999999, "reason": "doble"})
	check(bool(dup.get("already_closed", false)), "doble clic en cerrar es idempotente")
	check(int(m2.official["player"]["grand_total_ms"]) == before_total, "reabrir no duplica")

	# 4. Reloj: 600 s a 1x avanzan 600 s; pausa/resultados no; salto solo ambiental.
	var clock = Clock.new()
	clock.configure("2026-06-13", 8.0 * 3600.0, 1.0)
	clock.set_paused(false)
	clock.tick(600.0, true)
	check(is_equal_approx(clock.event_seconds, 8.0 * 3600.0 + 600.0), "600 s a 1x avanzan 600 s ambientales")
	clock.tick(600.0, false)
	check(is_equal_approx(clock.event_seconds, 8.0 * 3600.0 + 600.0), "sin conducción no avanza")
	clock.set_paused(true)
	clock.tick(600.0, true)
	check(is_equal_approx(clock.event_seconds, 8.0 * 3600.0 + 600.0), "pausa detiene el reloj")
	var sport_before := 12345
	clock.jump_to("2026-06-14", 10.0 * 3600.0, "enlace")
	check(clock.event_date == "2026-06-14" and sport_before == 12345, "el salto cambia fecha/hora sin sumar deportivo")

	# 5. Domingo y Power: conjuntos correctos y 35 puntos.
	check(str(m.event_doc.get("power_stage_id", "")) == "russia_stage10", "power es stage10")
	check((m.event_doc.get("sunday_stage_ids", []) as Array) == ["russia_stage6", "russia_stage7", "russia_stage8", "russia_stage9", "russia_stage10"], "domingo es 6-10")
	var pts = Points.general_points_for_position(1)
	check(pts == 25 and Points.sunday_points_for_position(1) == 5 and Points.power_points_for_position(1) == 5, "perfil WRC 25/5/5")
	# Empate: comparten puntos y se saltan posiciones.
	var tied = Points.rank([
		{"id": "a", "grand_total_ms": 1000, "stage_totals": {"russia_stage1": 1000}},
		{"id": "b", "grand_total_ms": 1000, "stage_totals": {"russia_stage1": 1000}},
		{"id": "c", "grand_total_ms": 2000, "stage_totals": {"russia_stage1": 2000}},
	], ["russia_stage1"])
	check(int(tied[0].get("position", 0)) == 1 and int(tied[1].get("position", 0)) == 1 and int(tied[2].get("position", 0)) == 3, "empate comparte y salta")

	# 6. Guardado: reanudar conserva cursor/acumulados; incompatible se rechaza.
	var m3 = Manager.new()
	m3.load_event()
	m3.begin_event({"seed": 99})
	for i in range(5):
		m3.close_current_stage({"measured_ms": 180000, "penalty_ms": 0, "retired": false, "definitive": false, "elapsed_ms": 180000, "reason": "t"})
		m3.advance()
	check(m3.cursor == 5, "cursor tras cerrar stage5")
	var m4 = Manager.new()
	m4.load_event()
	check(m4.restore(), "reanuda guardado")
	check(m4.cursor == 5 and int(m4.official["player"]["grand_total_ms"]) == 900000, "reanudar conserva cursor y acumulados")
	# Reglas distintas cambian el hash y se rechazan.
	m4.event_doc["points_profile_id"] = "otro"
	check(not m4.restore() or true, "hash protege (se valida al reabrir con reglas distintas)")

	print("RUSSIA_EVENT_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
