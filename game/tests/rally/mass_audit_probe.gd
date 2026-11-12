extends SceneTree
## mass_audit_probe.gd — Auditoría reproducible por perfil §5 (sin cambiar calibración).
## Tabla por perfil: masas, COM, reparto, desplazamiento de recentrado e inercias.
## Ejecución: godot --headless --path game --script res://tests/rally/mass_audit_probe.gd
## Emite una línea RALLY_MASS_AUDIT <json> por perfil y un resumen final.
## No muta calibraciones; la condición de referencia (vacío/inicial/lleno)
## debe acordarse antes de cambiarlas.

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
	else:
		print("  PASS: " + label)


func _initialize() -> void:
	call_deferred("run")


func _profile_paths() -> Array[Dictionary]:
	return [
		{"profile": "res://data/vehicles/ford-escort-rs2000/vehicle.json", "asset": "res://assets/rally/ford_escort_rs2000_1971/manifest.json"},
		{"profile": "res://data/vehicles/lancia-fulvia/vehicle.json", "asset": "res://assets/rally/lancia_fulvia/manifest.json"},
		{"profile": "res://data/vehicles/rt/rt-mini-cooper-s/vehicle.json", "asset": "res://assets/rally/rt/rt-mini-cooper-s/manifest.json"},
		{"profile": "res://data/vehicles/rt/rt-lancia-stratos/vehicle.json", "asset": "res://assets/rally/rt/rt-lancia-stratos/manifest.json"},
		{"profile": "res://data/vehicles/rt/rt-alfa-giulia-gta/vehicle.json", "asset": "res://assets/rally/rt/rt-alfa-giulia-gta/manifest.json"},
		{"profile": "res://data/vehicles/rt/rt-alpine-a110/vehicle.json", "asset": "res://assets/rally/rt/rt-alpine-a110/manifest.json"},
		{"profile": "res://data/vehicles/rt/rt-fiat-abarth-1000/vehicle.json", "asset": "res://assets/rally/rt/rt-fiat-abarth-1000/manifest.json"},
		{"profile": "res://data/vehicles/rt/rt-lotus-cortina/vehicle.json", "asset": "res://assets/rally/rt/rt-lotus-cortina/manifest.json"},
		{"profile": "res://data/vehicles/rt/rt-opel-kadett/vehicle.json", "asset": "res://assets/rally/rt/rt-opel-kadett/manifest.json"},
		{"profile": "res://data/vehicles/rt/rt-saab-96-v4/vehicle.json", "asset": "res://assets/rally/rt/rt-saab-96-v4/manifest.json"},
		{"profile": "res://data/vehicles/rt/rt-volvo-amazon/vehicle.json", "asset": "res://assets/rally/rt/rt-volvo-amazon/manifest.json"},
	]


func _load_asset(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func run() -> void:
	print("--- MASS AUDIT (§5) ---")
	var reference_ok := false
	var discrepant_found := false
	for entry in _profile_paths():
		var path: String = str(entry["profile"])
		var loaded := VehicleProfileLoader.load_profile(path)
		if not bool(loaded.get("ok", false)):
			check(false, "carga " + path + ": " + str(loaded.get("error", "")))
			continue
		var domains: Dictionary = loaded["domains"]
		var profile_id := str(loaded.get("profile_id", path))
		var mass := VehicleMassModel.new()
		var cfg := mass.configure(domains, _load_asset(str(entry["asset"])))
		if not bool(cfg.get("ok", false)):
			check(false, profile_id + " configura: " + str(cfg.get("error", "")))
			continue
		var geometry: Dictionary = (domains.get("chassis", {}) as Dictionary).get("geometry", {})
		var audit := mass.audit_report(geometry)
		# Verificación de sumas: inventario no rueda vs presupuesto.
		var closes := absf(float(audit["non_wheel_inventory_mass_kg"]) - float(audit["base_budget_kg"])) <= 1.0
		# Momentos en reposo: suma de cargas estáticas = peso total (plano).
		var susp := VehicleSuspensionModel.new()
		var resolved_empty: Dictionary = mass.resolve(0.0)
		var sres := susp.configure(domains, geometry, resolved_empty)
		var static_ok := false
		if bool(sres.get("ok", false)):
			var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
			var sum_n := 0.0
			for v in susp.static_corner_loads_n:
				sum_n += float(v)
			var expected := float(resolved_empty.get("vehicle_total_mass_kg", 0.0)) * gravity
			static_ok = absf(sum_n - expected) / maxf(expected, 1.0) < 0.01
		var triangular_ok := true
		var triangular_principal_ok := true
		for label in ["empty", "initial", "full"]:
			triangular_ok = triangular_ok and bool((audit["states"] as Dictionary)[label].get("triangular_ok", false))
			triangular_principal_ok = triangular_principal_ok and bool((audit["states"] as Dictionary)[label].get("triangular_principal_ok", false))
		print("RALLY_MASS_AUDIT ", JSON.stringify({"profile": profile_id, "audit": audit}))
		check(closes, profile_id + " inventario cierra con presupuesto")
		check(static_ok, profile_id + " suma de cargas = peso total en reposo")
		check(triangular_ok, profile_id + " desigualdades triangulares OK")
		check(triangular_principal_ok, profile_id + " triangular con momentos principales OK")
		if profile_id == "ford_escort_rs2000_1971":
			reference_ok = closes and static_ok and triangular_ok
		# Discrepancia: recentrado con tope, off-diagonal grande o sustitución.
		var off_max := 0.0
		for label in ["empty", "initial", "full"]:
			off_max = maxf(off_max, float(((audit["states"] as Dictionary)[label] as Dictionary).get("off_norm", 0.0)))
		var diag_min := minf(
			float((((audit["states"] as Dictionary)["initial"] as Dictionary)["inertia_diagonal"] as Array)[0]),
			minf(
				float((((audit["states"] as Dictionary)["initial"] as Dictionary)["inertia_diagonal"] as Array)[1]),
				float((((audit["states"] as Dictionary)["initial"] as Dictionary)["inertia_diagonal"] as Array)[2])
			)
		)
		var discrepant := bool(audit.get("recenter_clamped", false)) or (diag_min > 0.0 and off_max / diag_min > 0.10)
		if discrepant:
			discrepant_found = true
			print("  NOTA discrepancia ", profile_id, " clamp=", audit.get("recenter_clamped", false), " off/diag=", off_max / maxf(diag_min, 1.0))
	# Medición en reposo H4: Escort (referencia) y Fulvia (discrepancia).
	# Cargas estáticas NOMINALES (calculadas del perfil, no medidas en pista)
	# con condición de combustible registrada; suma vs peso y momentos vs COM.
	for rest_entry in [
		{"profile": "res://data/vehicles/ford-escort-rs2000/vehicle.json", "asset": "res://assets/rally/ford_escort_rs2000_1971/manifest.json", "tag": "escort_referencia"},
		{"profile": "res://data/vehicles/lancia-fulvia/vehicle.json", "asset": "res://assets/rally/lancia_fulvia/manifest.json", "tag": "fulvia_discrepancia"},
	]:
		_rest_measurement(str(rest_entry["profile"]), str(rest_entry["asset"]), str(rest_entry["tag"]))
	if failures.is_empty():
		print("\nALL MASS AUDIT CHECKS PASSED!")
	else:
		print("\nMASS AUDIT FAILED %d:" % failures.size())
		for f in failures:
			print("  - ", f)
	print("REFERENCIA escort OK=", reference_ok, " DISCREPANCIA vista=", discrepant_found)
	quit(0 if failures.is_empty() else 1)


## Reposo nominal H4: configura suspensión con el resolve a combustible
## inicial, suma cargas nominales vs peso total y momentos vs COM total.
## La distribución estática es simétrica por eje (precarga con reparto solo
## longitudinal desde COM suspendido), así que el momento lateral refleja el
## offset de COM (p. ej. piloto) y el longitudinal difiere del COM total
## (no suspendido + combustible): se reportan, no se exige igualdad.
func _rest_measurement(profile_path: String, asset_path: String, tag: String) -> void:
	var loaded := VehicleProfileLoader.load_profile(profile_path)
	if not bool(loaded.get("ok", false)):
		check(false, tag + " carga: " + str(loaded.get("error", "")))
		return
	var domains: Dictionary = loaded["domains"]
	var mass := VehicleMassModel.new()
	if not bool(mass.configure(domains, _load_asset(asset_path)).get("ok", false)):
		check(false, tag + " masa configura")
		return
	var fuel_kg := mass.fuel_initial_kg
	var fuel_condition := "initial_%.2fkg" % fuel_kg
	var resolved := mass.resolve(fuel_kg)
	var geometry: Dictionary = (domains.get("chassis", {}) as Dictionary).get("geometry", {})
	var susp := VehicleSuspensionModel.new()
	if not bool(susp.configure(domains, geometry, resolved).get("ok", false)):
		check(false, tag + " suspensión configura")
		return
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.80665))
	var sum_n := 0.0
	for v in susp.static_corner_loads_n:
		sum_n += float(v)
	var total_mass := float(resolved.get("vehicle_total_mass_kg", 0.0))
	var weight := total_mass * gravity
	var total_com: Vector3 = resolved.get("total_center_of_mass", Vector3.ZERO)
	var wx := mass.wheel_centres_local
	var mz_static := 0.0
	var mx_static := 0.0
	for i in 4:
		var l := float(susp.static_corner_loads_n[i])
		mz_static += l * float((wx[i] as Vector3).z)
		mx_static += l * float((wx[i] as Vector3).x)
	var mz_expected := weight * total_com.z
	var mx_expected := weight * total_com.x
	var entry := {
		"tag": tag,
		"fuel_condition": fuel_condition,
		"fuel_kg": fuel_kg,
		"load_source": "nominal_static_profile",
		"static_sums_nominal": true,
		"sum_loads_n": sum_n,
		"weight_n": weight,
		"sum_rel_err": absf(sum_n - weight) / maxf(weight, 1.0),
		"moment_z_static": mz_static,
		"moment_z_total_com": mz_expected,
		"moment_x_static": mx_static,
		"moment_x_total_com": mx_expected,
		"total_com": [total_com.x, total_com.y, total_com.z],
	}
	print("RALLY_MASS_REST ", JSON.stringify(entry))
	check(absf(sum_n - weight) / maxf(weight, 1.0) < 0.01, tag + " reposo nominal suma = peso (" + fuel_condition + ")")
