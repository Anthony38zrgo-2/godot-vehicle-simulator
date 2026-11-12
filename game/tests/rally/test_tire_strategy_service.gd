extends SceneTree
## Tests v2: pool 10, reparaciones con desgaste conservado, destalonado irreparable,
## pronósticos 80/20 estables con salto <=2, movimientos sin corromper montadas.
const TireInvScript := preload("res://scripts/rally/rally_tire_inventory.gd")
const ForecastSchedulerScript := preload("res://scripts/rally/rally_weather_scheduler.gd")

func _init() -> void:
	print("--- INICIANDO TEST: ESTRATEGIA DE NEUMÁTICOS Y SERVICIO v2 ---")
	test_tire_inventory_pool()
	test_move_tire_keeps_mounted_four()
	test_forecast_generation()
	test_forecast_stable_and_bounded()
	test_puncture_repair_preserves_wear()
	test_rim_repair_and_carcass_block()
	test_snapshot_restore_pool()
	print("--- TODOS LOS TESTS v2 PASARON ---")
	quit(0)

func _fresh_state(wear: float, punctured: bool = false, rim: float = 0.0, carcass: float = 0.0) -> Dictionary:
	return {
		"wear_fraction": wear,
		"pressure_loss_fraction": 0.85 if punctured else 0.0,
		"leak_per_second": 0.05 if punctured else 0.0,
		"rim_deformation": rim,
		"carcass_failure": carcass,
		"carcass_c": 35.0,
		"pressure_reference_bar_gauge": 2.0,
		"pressure_reference_temp_c": 20.0,
		"pressure_bar_gauge": 2.0,
	}

func _build_pool():
	var inv = TireInvScript.new()
	for i in 4:
		inv.mounted.append(inv.item("gravel_normal", _fresh_state(0.0)))
	for i in 2:
		inv.spares.append(inv.item("gravel_normal", _fresh_state(0.0)))
	for i in 4:
		inv.service_stock.append(inv.item("gravel_wet", _fresh_state(0.0)))
	return inv

func test_tire_inventory_pool() -> void:
	var inv = _build_pool()
	assert(inv.total_count() == 10, "Pool debe ser 10")
	assert(inv.is_pool_mode(), "Debe detectar modo pool")
	var spare_id := int((inv.spares[0] as Dictionary).get("id", 0))
	assert(inv.discard(spare_id), "Descarte debe funcionar")
	assert(inv.spares.size() == 1, "Queda 1 repuesto")
	assert(inv.discarded.size() == 1, "1 baja")
	assert(inv.total_count() == 10, "Total con bajas sigue 10")
	print("✔ Pool 10 + bajas: OK")

func test_move_tire_keeps_mounted_four() -> void:
	var inv = _build_pool()
	var stock_id := int((inv.service_stock[0] as Dictionary).get("id", 0))
	var before: Dictionary = (inv.mounted[0] as Dictionary).duplicate(true)
	assert(inv.move_tire(stock_id, "mounted", 0), "Mover stock->FL debe funcionar")
	assert(inv.mounted.size() == 4, "Montadas siempre 4")
	assert(int((inv.mounted[0] as Dictionary).get("id", 0)) == stock_id, "FL ahora es la de stock")
	# La desplazada debe estar en stock, no perderse.
	var found := false
	for t in inv.service_stock:
		if int((t as Dictionary).get("id", 0)) == int(before.get("id", 0)):
			found = true
	assert(found, "Desplazada va a stock")
	assert(inv.total_count() == 10, "Total intacto tras mover")
	# Orígenes montada hacia maletera deben rechazarse (no dejar 3).
	var mounted_id := int((inv.mounted[1] as Dictionary).get("id", 0))
	assert(not inv.move_tire(mounted_id, "spares"), "Montada->maletera directo debe rechazarse")
	assert(inv.mounted.size() == 4, "Siguen 4 montadas")
	print("✔ move_tire seguro: OK")

func test_forecast_generation() -> void:
	var schedule := [
		{"stage_id": "st1", "zones": [{"climate": {"precipitation_mm_h": 0.0, "air_temperature_c": 19.0}, "precipitation_kind": "none", "weather_state_id": "clear", "weather_state_index": 1}]},
		{"stage_id": "st2", "zones": [{"climate": {"precipitation_mm_h": 3.0, "air_temperature_c": 14.0}, "precipitation_kind": "rain", "weather_state_id": "light_precipitation", "weather_state_index": 7}]},
		{"stage_id": "st3", "zones": [{"climate": {"precipitation_mm_h": 0.0, "air_temperature_c": 18.0}, "precipitation_kind": "none", "weather_state_id": "sunny", "weather_state_index": 0}]},
	]
	var ordered := ["sunny", "clear", "partly_cloudy", "cloudy", "overcast", "mist_fog", "drizzle", "light_precipitation", "medium_precipitation", "heavy_precipitation"]
	var forecasts = ForecastSchedulerScript.generate_stage_forecasts(schedule, 12345, 0.8, ordered)
	assert(forecasts.size() == 3, "3 pronósticos")
	for f in forecasts:
		var fd: Dictionary = f
		assert(fd.has("is_truth") and fd.has("weather"), "Estructura pronóstico")
	print("✔ Forecast estructura: OK")

func test_forecast_stable_and_bounded() -> void:
	var schedule := []
	for i in 20:
		schedule.append({"stage_id": "s%d" % i, "zones": [{"climate": {"precipitation_mm_h": 0.0, "air_temperature_c": 18.0}, "precipitation_kind": "none", "weather_state_id": "clear", "weather_state_index": 1}]})
	var ordered := ["sunny", "clear", "partly_cloudy", "cloudy", "overcast", "mist_fog", "drizzle", "light_precipitation", "medium_precipitation", "heavy_precipitation"]
	var a = ForecastSchedulerScript.generate_stage_forecasts(schedule, 777, 0.8, ordered)
	var b = ForecastSchedulerScript.generate_stage_forecasts(schedule, 777, 0.8, ordered)
	assert(a.size() == b.size(), "Tamaño estable")
	for i in a.size():
		var wa: Dictionary = (a[i] as Dictionary).get("weather", {})
		var wb: Dictionary = (b[i] as Dictionary).get("weather", {})
		assert(str(wa.get("preset_id", "")) == str(wb.get("preset_id", "")), "Estable al reabrir (%d)" % i)
		assert(bool((a[i] as Dictionary).get("is_truth", true)) == bool((b[i] as Dictionary).get("is_truth", true)), "Veracidad estable")
	# Tasa ~80% y salto <=2 cuando miente.
	var runs := 200
	var truth := 0
	var checked_lies := 0
	for seed in runs:
		var f = ForecastSchedulerScript.generate_stage_forecasts(schedule.slice(0, 1), 1000 + seed, 0.8, ordered)
		if bool((f[0] as Dictionary).get("is_truth", false)):
			truth += 1
		else:
			var w: Dictionary = (f[0] as Dictionary).get("weather", {})
			var lied := int(w.get("state_index", -1))
			assert(lied >= 0 and lied < ordered.size() and lied != 1, "Mentira dentro de escala y distinta")
			assert(absi(lied - 1) <= 2, "Salto <=2")
			checked_lies += 1
	var rate := float(truth) / float(runs)
	assert(rate > 0.65 and rate < 0.95, "Tasa ~80%% (fue %0.2f)" % rate)
	assert(checked_lies > 0, "Debe haber mentiras en 200 intentos")
	print("✔ Forecast 80%% estable y acotado (tasa %0.2f): OK" % rate)

func test_puncture_repair_preserves_wear() -> void:
	var inv = TireInvScript.new()
	var tire := inv.item("gravel_normal", _fresh_state(0.42, true))
	assert(inv.is_punctured(tire), "Pinchado detectado")
	assert(inv.repair_puncture(tire), "Reparar pinchazo OK")
	assert(not inv.is_punctured(tire), "Ya no pinchado")
	assert(absf(float((tire.get("state", {}) as Dictionary).get("wear_fraction", -1.0)) - 0.42) < 0.001, "Desgaste 42% intacto")
	print("✔ Inflar conserva desgaste: OK")

func test_rim_repair_and_carcass_block() -> void:
	var inv = TireInvScript.new()
	var rim_tire := inv.item("gravel_normal", _fresh_state(0.3, false, 0.02))
	assert(inv.is_rim_damaged(rim_tire), "Rin dañado detectado")
	assert(inv.repair_rim(rim_tire), "Reparar rin OK")
	assert(not inv.is_rim_damaged(rim_tire), "Rin ya OK")
	var dead := inv.item("gravel_normal", _fresh_state(0.5, true, 0.02, 1.0))
	assert(inv.is_carcass_destroyed(dead), "Destalonado detectado")
	assert(not inv.repair_puncture(dead), "Destalonado no se infla")
	assert(not inv.repair_rim(dead), "Destalonado no admite rin")
	print("✔ Rin + destalonado irreparable: OK")

func test_snapshot_restore_pool() -> void:
	var inv = _build_pool()
	inv.discard(int((inv.spares[0] as Dictionary).get("id", 0)))
	var snap := inv.snapshot()
	var inv2 := TireInvScript.new()
	assert(inv2.restore(snap), "Restore pool OK")
	assert(inv2.total_count() == 10, "Restaurado mantiene 10")
	assert(inv2.spares.size() == 1 and inv2.discarded.size() == 1, "Bajas persisten")
	# Legacy 4+2 sin stock debe seguir cargando.
	var legacy := {"mounted": snap["mounted"], "spares": (snap["spares"] as Array).slice(0, 1), "next_id": 99, "repair_kits": [true, true]}
	var inv3 := TireInvScript.new()
	assert(inv3.restore(legacy), "Restore legacy OK")
	assert(inv3.total_count() == 5, "Legacy 4+1 carga")
	print("✔ Snapshot/restore pool + legacy: OK")
