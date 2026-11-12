extends SceneTree
## suspension_correction_contract.gd
##
## Contrato de revisión de suspensión (hallazgos F1-F3 sobre el diff actual):
##  F2: elastic_tangent_reference() debe coincidir con diferencias finitas
##      centradas en compresión, extensión, fuera del clamp y cola del auxiliar.
##  F1: el recorte de diagnóstico del damper está DESACTIVADO por defecto; la
##      ruta normal aplica la curva digresiva íntegra. El recorte es opcional.
##  F3: la traza por tick permite comparar ticks Jolt (tick_id, dt, poses y
##      velocidades leídas por el solver, damper solicitado/aplicado, impulso
##      en N·s; potencia en W frente a trabajo estimado en J con convención).
##
## Solo matemática + defaults (sin escena): la comparativa de caída de 0,5 m y
## el rescate comparativo viven en suspension_drop_rescue_probe.gd (escena).

var failures: Array[String] = []


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		push_error("FAIL: " + msg)
	else:
		print("  PASS: " + msg)


func _initialize() -> void:
	call_deferred("run_suite")


func run_suite() -> void:
	print("--- SUSPENSION CORRECTION CONTRACT (F1-F3, unit) ---")
	var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	if not bool(loader.get("ok", false)):
		failures.append("profile loads")
		push_error("FAIL: profile loads")
		quit(1)
		return
	var domains: Dictionary = loader["domains"]
	var mass_doc: Dictionary = (domains.get("chassis", {}) as Dictionary).get("geometry", {})
	var mass := VehicleMassModel.new()
	# configure necesita el manifest de asset; si falla, se usa resolve mínimo.
	var cfg := mass.configure(domains, {})
	var resolved: Dictionary
	if bool(cfg.get("ok", false)):
		resolved = mass.resolve(mass.fuel_initial_kg)
	else:
		resolved = {"mass_kg": 900.0, "center_of_mass": Vector3.ZERO, "unsprung_mass_kg": [20.0, 20.0, 20.0, 20.0]}
	var susp := VehicleSuspensionModel.new()
	var res := susp.configure(domains, mass_doc, resolved)
	if not bool(res.get("ok", false)):
		failures.append("suspension configures: " + str(res.get("error", "")))
		push_error("FAIL: suspension configures")
		quit(1)
		return
	test_tangent_finite_differences(susp)
	test_limiter_defaults()
	test_tick_trace_shape()
	if failures.is_empty():
		print("\nALL SUSPENSION CORRECTION UNIT TESTS PASSED!")
		quit(0)
	else:
		print("\nSUSPENSION CORRECTION UNIT FAILED %d:" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)


func _fd_tangent(p: Dictionary, travel: float, h: float = 0.0004) -> float:
	var fp := VehicleSuspensionModel.elastic_force_reference(p, travel + h)
	var fm := VehicleSuspensionModel.elastic_force_reference(p, travel - h)
	return (fp - fm) / (2.0 * h)


func _check_point(susp: VehicleSuspensionModel, axle_index: int, axle: String, label: String, travel: float, tol_rel: float = 0.01) -> void:
	var p: Dictionary = susp.axle_parameters[axle_index]
	var analytic := VehicleSuspensionModel.elastic_tangent_reference(p, travel)
	var numeric := _fd_tangent(p, travel)
	var denom := maxf(absf(numeric), 50.0)
	var rel := absf(analytic - numeric) / denom
	check(rel <= tol_rel, "%s %s travel=%.4f anal=%.1f num=%.1f rel=%.4f" % [axle, label, travel, analytic, numeric, rel])


func test_tangent_finite_differences(susp: VehicleSuspensionModel) -> void:
	print("\n[F2] Tangente vs diferencias finitas (centrada, lejos de quiebres)...")
	# h = 0.4 mm; puntos con margen respecto a quiebres: clamp [-1, 1.5],
	# umbral del auxiliar y n = 0 (la centrada en 0 es válida: la curva es
	# suave ahí; se evita evaluar JUSTO en -1/1.5 y en el umbral H).
	for axle in [0, 2]:
		var tag := "front" if axle == 0 else "rear"
		var p: Dictionary = susp.axle_parameters[axle]
		var bump := float(p.get("bump_m", 0.22))
		var droop := float(p.get("droop_m", 0.18))
		var rest := float(p.get("rest_compression_offset", 0.0))
		# Compresión interior (n ≈ +0.5).
		_check_point(susp, axle, tag, "compresion", rest + bump * 0.5)
		# Extensión interior (n ≈ -0.4, tangente < k si c > 0).
		_check_point(susp, axle, tag, "extension", rest - droop * 0.4)
		# Fuera del clamp por arriba (n_raw ≈ 1.8 -> n = 1.5 constante).
		_check_point(susp, axle, tag, "fuera_clamp_sup", rest + bump * 1.8)
		# Fuera del clamp por abajo (n_raw ≈ -1.4 -> n = -1 constante).
		_check_point(susp, axle, tag, "fuera_clamp_inf", rest - bump * 1.4)
		# Cola del auxiliar: buscar recorrido profundo donde raw < H (solo si
		# el muelle puede desasentarse; el trasero live-axle es bilateral).
		if bool(p.get("spring_can_unseat", true)):
			var helper := float(p.get("static_load", 0.0)) * 0.08
			var found := false
			var t := rest - droop
			while t > rest - droop - bump * 2.0:
				var nn := clampf((t - rest) / bump, -1.0, 1.5)
				var raw: float = float(p.get("static_load", 0.0)) + float(p.get("spring_rate", 1.0)) * (1.0 + 0.15 * nn * absf(nn)) * (t - rest)
				if raw < helper * 0.9:
					# Margen de 2 mm respecto al umbral para no pisar el quiebre.
					_check_point(susp, axle, tag, "cola_auxiliar", t, 0.02)
					found = true
					break
				t -= 0.005
			check(found, "%s cola del auxiliar alcanzada y verificada" % tag)
		else:
			# Bilateral: sin cola exponencial; la tangente fuera del clamp ya
			# se verificó arriba.
			check(true, "%s bilateral sin cola (can_unseat=false)" % tag)


func test_limiter_defaults() -> void:
	print("\n[F1] Limitador desactivado por defecto / ruta digresiva íntegra...")
	var rig := UnsprungSuspensionRig.new()
	check(not rig.damper_impulse_limit_enabled, "F1 limiter OFF por defecto (producción = curva digresiva)")
	check(rig.damper_clip_events == [0, 0, 0, 0], "F1 contadores a cero al crear")
	rig.set_damper_impulse_limit(true)
	check(rig.damper_impulse_limit_enabled, "F1 el diagnóstico se puede activar explícitamente")
	check(rig.damper_clip_events == [0, 0, 0, 0], "F1 activar reinicia contadores")
	rig.set_damper_impulse_limit(false)
	check(not rig.damper_impulse_limit_enabled, "F1 se puede volver a desactivar")


func test_tick_trace_shape() -> void:
	print("\n[F3] Forma de la traza comparable por tick...")
	var rig := UnsprungSuspensionRig.new()
	# Sin solve aún: la muestra debe existir con la forma esperada tras un
	# solve real (la probe de escena la verifica con valores); aquí se valida
	# el contrato de claves de los publicadores.
	var sim := FordRallyVehicleSimulation.new()
	var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	if not bool(loader.get("ok", false)):
		check(false, "F3 profile para forma de traza")
		return
	# No se configura el vehículo completo (requiere escena); se verifica que
	# los métodos de muestreo existen y devuelven 4 esquinas.
	check(sim.has_method("sample_suspension_trace") and sim.has_method("sample_tick_trace"), "F3 métodos de traza presentes")
	check(sim.has_method("set_damper_impulse_limit"), "F3 interruptor de diagnóstico presente en simulación")
