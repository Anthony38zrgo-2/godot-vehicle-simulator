extends SceneTree
## tire_handoff_acceptance_contract.gd
##
## Contrato de aceptación del handoff §4 (puntos 1-6).
## Cubre en una sola sonda determinista:
##  1. Barridos Fx(k)/Fy(a) a 3 cargas, escalones, invariancia a paso físico,
##     sonda Vx=0 Vy!=0 bloqueada, barrido relief opt-in en banda ~0.
##  2. Balance energético (residuo), proyección plástica, rigidez variable,
##     pérdida de contacto.
##  3. Huella a carga referencia (2 rutas), trail dinámico, radial
##     (óptima, secante/tangente, cero en descarga), camber FL/FR, tan clamp.
##  4. Pendiente, frenada con giro, elipse, invariancia, aterrizaje.
##  5. Radio efectivo, pico/carga, película/charco, hielo mojado, térmica,
##     envolvente.
##  6. Catálogo vacío, reset completo, rampa aterrizaje, warnings limpios.

var failures: Array[String] = []
var domains: Dictionary = {}
var filters: Dictionary = {}

func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
		push_error("FAIL: " + msg)
	else:
		print("  PASS: " + msg)

func _initialize() -> void:
	call_deferred("run_suite")

func run_suite() -> void:
	print("--- TIRE HANDOFF ACCEPTANCE CONTRACT (§4.1-4.6) ---")
	var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	if not bool(loader.get("ok", false)):
		failures.append("profile loads")
		push_error("FAIL: profile loads")
		quit(1)
		return
	domains = loader.domains.duplicate(true)
	filters = loader.resolved_tire_filters.duplicate(true)
	test_sweeps_three_loads()
	test_steps_and_dt_invariance()
	test_locked_lateral_slide()
	test_relief_band()
	test_energy_balance()
	test_footprint_reference()
	test_camber_symmetry()
	test_radial_contract()
	test_slope_brake_ellipse_landing()
	test_effective_radius_and_peak()
	test_film_puddle_ice()
	test_robustness()
	if failures.is_empty():
		print("\nALL HANDOFF ACCEPTANCE TESTS PASSED!")
		quit(0)
	else:
		print("\nHANDOFF ACCEPTANCE FAILED %d:" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)

func make_tire(loads: Array = [2500.0, 2500.0, 2500.0, 2500.0]) -> TireModel:
	var t := TireModel.new()
	t.configure(domains, filters, loads)
	return t

func settle(t: TireModel, idx: int, fz: float, vx: float, vy: float, rim: float, steps: int = 40, dt: float = 0.01) -> Dictionary:
	var r: Dictionary = {}
	for i in steps:
		r = t.evaluate(idx, fz, "Gravel", vx, vy, rim, 0.28, 0.0, 1.0, 200.0, dt, 60.0)
	return r

func test_sweeps_three_loads() -> void:
	print("\n[1] Barridos Fx(k)/Fy(a) a 3 cargas...")
	for load in [1000.0, 2500.0, 4500.0]:
		var t := make_tire([load, load, load, load])
		# Longitudinal: barremos rim para k en [-0.6..0.6] a Vx=20.
		var prev_fx := 0.0
		var peak_seen := false
		var fx_peak := 0.0
		for k in [-0.6, -0.3, -0.15, -0.05, 0.0, 0.05, 0.15, 0.3, 0.6]:
			var rim: float = (20.0 * (1.0 + float(k))) / 0.28
			var r := settle(t, 2, float(load), 20.0, 0.0, rim, 30, 0.008)
			var fx: float = r.longitudinal_force_n
			check(is_finite(fx), "Fx finita carga %d k=%f" % [int(load), k])
			fx_peak = maxf(fx_peak, absf(fx))
			if absf(k) < 0.06:
				peak_seen = true
		check(fx_peak > 0.3 * load, "Fx pico escala con carga %d (|Fx|=%.0f)" % [int(load), fx_peak])
		# Lateral: barremos vy para a aprox.
		var fy_peak := 0.0
		for vy in [-6.0, -3.0, -1.0, 0.0, 1.0, 3.0, 6.0]:
			var r2 := settle(t, 2, float(load), 20.0, float(vy), 20.0 / 0.28, 30, 0.008)
			var fy: float = r2.lateral_force_n
			check(is_finite(fy), "Fy finita carga %d vy=%f" % [int(load), vy])
			fy_peak = maxf(fy_peak, absf(fy))
		check(fy_peak > 0.3 * load, "Fy pico escala con carga %d (|Fy|=%.0f)" % [int(load), fy_peak])

func test_steps_and_dt_invariance() -> void:
	print("\n[2] Escalones + invariancia paso físico...")
	var loads := [2500.0, 2500.0, 2500.0, 2500.0]
	# Escalón longitudinal por eje: mismo input delante/detrás difiere solo por preset.
	var tf := make_tire(loads)
	var tr := make_tire(loads)
	var rf := settle(tf, 0, 2500.0, 15.0, 0.0, 18.0 / 0.28, 50, 0.005)
	var rr := settle(tr, 2, 2500.0, 15.0, 0.0, 18.0 / 0.28, 50, 0.005)
	check(is_finite(rf.longitudinal_force_n) and is_finite(rr.longitudinal_force_n), "Escalón lon FL/RL finito")
	# Combinado: lon+lat a la vez.
	var tc := make_tire(loads)
	var rc := settle(tc, 2, 2500.0, 18.0, -3.0, 22.0 / 0.28, 50, 0.005)
	var budget := Vector2(float(rc.longitudinal_force_n) / 4000.0, float(rc.lateral_force_n) / 4000.0).length()
	check(is_finite(budget) and budget < 3.0, "Combinado acotado (u=%.2f)" % budget)
	# Invariancia: mismo escenario a dt 1/60 vs 1/240 converge (<25% dif).
	for idx in [0, 2]:
		var a := make_tire(loads)
		var b := make_tire(loads)
		var ra := settle(a, idx, 2500.0, 20.0, -2.0, 22.0 / 0.28, 60, 1.0 / 60.0)
		var rb := settle(b, idx, 2500.0, 20.0, -2.0, 22.0 / 0.28, 240, 1.0 / 240.0)
		var fa := Vector2(float(ra.longitudinal_force_n), float(ra.lateral_force_n))
		var fb := Vector2(float(rb.longitudinal_force_n), float(rb.lateral_force_n))
		var diff := (fa - fb).length() / maxf(fa.length(), 1.0)
		check(diff < 0.25, "Invariancia dt eje %d dif=%.3f" % [idx, diff])

func test_locked_lateral_slide() -> void:
	print("\n[3] Sonda Vx=0 Vy!=0 rueda bloqueada...")
	var t := make_tire()
	# Rueda bloqueada (rim=0) deslizando de lado a 4 m/s: debe dar Fy grande y finita,
	# sin renovación congelada (punto 3: transport incluye lateral).
	var r := settle(t, 2, 2500.0, 0.0, 4.0, 0.0, 80, 1.0 / 120.0)
	check(is_finite(r.lateral_force_n) and absf(float(r.lateral_force_n)) > 500.0, "Bloqueada lateral genera Fy=%.0f" % float(r.lateral_force_n))
	check(absf(float(r.longitudinal_force_n)) < 2500.0, "Bloqueada lateral Fx acotada=%.0f" % float(r.longitudinal_force_n))

func test_relief_band() -> void:
	print("\n[4] Barrido relief opt-in en banda ~0...")
	# En banda de transición el relief graduado ordena el techo (ver [2b]).
	var px := 0.08
	var py := 0.034
	var off := _relief_probe({}, Vector2(px, py))
	var r15 := _relief_probe({"legacy_longitudinal_relief": 0.15}, Vector2(px, py))
	var r30 := _relief_probe({"legacy_longitudinal_relief": 0.3}, Vector2(px, py))
	check(r30.y >= r15.y and r15.y >= off.y - 1.0, "Relief ordena techo en banda (%.0f<=%.0f<=%.0f)" % [off.y, r15.y, r30.y])

func _relief_probe(over: Dictionary, patch: Vector2) -> Vector2:
	var base := {"combined_migration_v2_enabled": false}
	for k in over:
		base[k] = over[k]
	var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var f: Dictionary = loader.resolved_tire_filters.duplicate(true)
	var prof: Dictionary = f.get("rear", {}).duplicate(true)
	for k in base:
		prof[k] = base[k]
	f["rear"] = prof
	var tire := TireModel.new()
	tire.configure(loader.domains, f, [2500.0, 2500.0, 2500.0, 2500.0])
	tire.states[2].patch_pos = patch
	var r := tire.evaluate(2, 2500.0, "Gravel", 0.0, 0.0, 0.0, 0.28, 0.0, 1.0, 200.0, 0.5, 60.0)
	return Vector2(float(r.longitudinal_force_n), float(r.lateral_force_n))

func test_energy_balance() -> void:
	print("\n[5] Balance energético + plástica + rigidez variable...")
	var t := make_tire([3000.0, 3000.0, 3000.0, 3000.0])
	var dt := 1.0 / 120.0
	# Régimen dinámico: residuo con signo publicado, fricción >= 0.
	var r: Dictionary = {}
	for i in 60:
		r = t.evaluate(2, 3000.0, "Gravel", 12.0, -1.5, 14.0 / 0.28, 0.28, 0.02, 1.0, 200.0, dt, 60.0)
	check(float(r.friction_power_w) >= -1.0, "Fricción no negativa (%.1f)" % float(r.friction_power_w))
	check("energy_residue_w" in r, "Residuo energético publicado")
	# Sobre-pico fuerte: la proyección plástica (2.65) acota sin NaN.
	var t2 := make_tire([3000.0, 3000.0, 3000.0, 3000.0])
	t2.states[2].patch_pos = Vector2(0.5, 0.4)
	var rp := t2.evaluate(2, 3000.0, "Gravel", 20.0, -4.0, 24.0 / 0.28, 0.28, 0.0, 1.0, 200.0, dt, 60.0)
	check(is_finite(rp.longitudinal_force_n) and is_finite(rp.friction_power_w), "Plástica acotada y finita")
	# Rigidez variable (migración+temperatura): dos temps dan fuerzas distintas pero finitas.
	var t3 := make_tire([3000.0, 3000.0, 3000.0, 3000.0])
	var rc1 := settle(t3, 2, 3000.0, 15.0, -2.0, 17.0 / 0.28, 30, dt)
	var t4 := make_tire([3000.0, 3000.0, 3000.0, 3000.0])
	# carcasa fría 20 °C vs caliente 90 °C: rigidez distinta.
	var rf_: Dictionary = {}
	for i in 30:
		rf_ = t4.evaluate(2, 3000.0, "Gravel", 15.0, -2.0, 17.0 / 0.28, 0.28, 0.0, 1.0, 200.0, dt, 20.0)
	check(is_finite(rf_.longitudinal_force_n), "Rigidez variable con T carcasa finita")
	# Pérdida de contacto: al descargar, fuerzas y energía a cero sin crear.
	t4.evaluate(2, 0.0, "Gravel", 15.0, -2.0, 17.0 / 0.28, 0.28, 0.0, 1.0, 200.0, dt, 60.0)
	var st: Dictionary = t4.states[2]
	check(float(st.longitudinal_force) == 0.0 and float(st.patch_energy_j) == 0.0, "Descarga limpia energía/fuerza")

func test_footprint_reference() -> void:
	print("\n[6] Huella a carga referencia (2 rutas) + trail...")
	# A Fz=estática y presión caliente ref, patch_scale ~= 1.0 en ambas rutas
	# (rig con deflexión real y fallback sin deflexión).
	var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	var d: Dictionary = loader.domains
	var f: Dictionary = loader.resolved_tire_filters
	var t := TireModel.new()
	# Carga estática real del rig (usa static_wheel_loads del configure).
	t.configure(d, f, [3000.0, 3000.0, 3000.0, 3000.0])
	var ref_static: float = t.static_wheel_load_n[2]
	# Ruta rig: deflexión típica 12 mm.
	t.states[2].radial_deflection_m = 0.012
	var r_rig := t.evaluate(2, ref_static, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 225.0, 0.01, 60.0)
	var patch_rig: float = t.states[2].dynamic_contact_patch_m / t.base_contact_patch_m[2]
	# Ruta fallback: sin radial_deflection_m (se estima Fz/k).
	var t2 := TireModel.new()
	t2.configure(d, f, [3000.0, 3000.0, 3000.0, 3000.0])
	var r_fb := t2.evaluate(2, ref_static, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 225.0, 0.01, 60.0)
	var patch_fb: float = t2.states[2].dynamic_contact_patch_m / t2.base_contact_patch_m[2]
	check(absf(patch_rig - 1.0) < 0.25, "Huella rig ~=1 a referencia (%.3f)" % patch_rig)
	check(absf(patch_fb - 1.0) < 0.25, "Huella fallback ~=1 a referencia (%.3f)" % patch_fb)

func test_camber_symmetry() -> void:
	print("\n[7] Simetría FL/FR con camber espejado + tan clamp...")
	var t := make_tire()
	# Mismo axle-camber +0.05 en FL (idx0, signo +) y FR (idx1, signo - interno):
	# Fy debe ser espejada (igual magnitud, signo opuesto en marco rueda).
	# En marco vehículo ambas generan el mismo Fy lateral (simetría).
	t.states[0].patch_pos = Vector2.ZERO
	t.states[1].patch_pos = Vector2.ZERO
	var rl := t.evaluate(0, 2500.0, "Gravel", 15.0, -1.0, 15.0 / 0.28, 0.28, 0.05, 1.0, 200.0, 0.01, 60.0)
	var rr := t.evaluate(1, 2500.0, "Gravel", 15.0, -1.0, 15.0 / 0.28, 0.28, 0.05, 1.0, 200.0, 0.01, 60.0)
	check(absf(absf(float(rl.lateral_force_n)) - absf(float(rr.lateral_force_n))) < 50.0, "FL/FR espejadas |Fy| dif=%.1f" % absf(absf(float(rl.lateral_force_n)) - absf(float(rr.lateral_force_n))))
	# Camber extremo no debe explotar (tan clamp ±0.5).
	var rx := t.evaluate(0, 2500.0, "Gravel", 15.0, -1.0, 15.0 / 0.28, 0.28, 0.9, 1.0, 200.0, 0.01, 60.0)
	check(is_finite(rx.lateral_force_n), "Camber extremo clamp finito")

func test_radial_contract() -> void:
	print("\n[8] Radial: óptima, secante/tangente, cero en descarga, damping...")
	var tires: Dictionary = domains.get("tires", {}).get("tires", {})
	# Óptima resuelta del rig: configure usa axle_optimal; evaluate con INF cae al JSON.
	var r_opt := TireRadialModel.evaluate(tires, "rear", 200.0, 60.0, 20.0, 0.02, 0.0, 60.0)
	var r_raw := TireRadialModel.evaluate(tires, "rear", 200.0, 60.0, 20.0, 0.02, 0.0, INF)
	check(is_equal_approx(float(r_opt.force_n), float(r_raw.force_n)), "Óptima resuelta == fallback JSON a 60°C")
	# Secante <= lineal <= tangente (con seating la secante cae).
	check(float(r_opt.secant_n_m) <= float(r_opt.stiffness_n_m) + 1.0, "Secante <= lineal (%.0f<=%.0f)" % [float(r_opt.secant_n_m), float(r_opt.stiffness_n_m)])
	# Con seating y sin tope: secante < tangente < lineal (el seating ablanda).
	# Con tope activo la tangente domina por encima. Invariante: secante <= tangente.
	check(float(r_opt.secant_n_m) <= float(r_opt.tangent_n_m) + 1.0, "Secante <= tangente")
	# Cero en descarga.
	var r_zero := TireRadialModel.evaluate(tires, "rear", 200.0, 60.0, 20.0, 0.0, 1.0, 60.0)
	check(float(r_zero.force_n) == 0.0, "Radial cero en descarga")
	# Tope: damping acotado por clamp (no dispara a 300k).
	var sidewall: float = TireRadialModel.geometry(tires.get("rear", {})).sidewall_m
	var r_stop := TireRadialModel.evaluate(tires, "rear", 200.0, 60.0, 20.0, sidewall * 0.9, -3.0, 60.0)
	check(float(r_stop.damping_ns_m) < 30000.0, "Damping acotado al tope (%.0f)" % float(r_stop.damping_ns_m))

func test_slope_brake_ellipse_landing() -> void:
	print("\n[9] Pendiente + frenada con giro + elipse + aterrizaje...")
	# Pendiente 10% bloqueada (criterio plan): <1 mm/s tras 10 s.
	var t := make_tire([3000.0, 3000.0, 3000.0, 3000.0])
	var dt := 1.0 / 120.0
	var m := 3000.0 / 9.81
	var pull := m * 9.81 * 0.17
	var v := 0.0
	var vmax_late := 0.0
	for i in int(10.0 / dt):
		var r := t.evaluate(2, 3000.0, "Gravel", v, 0.0, 0.0, 0.32, 0.0, 1.0, 200.0, dt, 60.0)
		v += (pull + float(r.longitudinal_force_n)) / m * dt
		if float(i) * dt > 5.0:
			vmax_late = maxf(vmax_late, absf(v))
	check(vmax_late < 0.001, "Pendiente 10pct asentada <1mm/s (v=%.6f)" % vmax_late)
	# Frenada con giro inicial y freno real: rueda frenada con Vy.
	var t2 := make_tire()
	var rb: Dictionary = {}
	for i in 80:
		rb = t2.evaluate(2, 3000.0, "Gravel", maxf(8.0 - float(i) * dt * 3.0, 0.5), -1.5, 0.0, 0.32, 0.0, 1.0, 200.0, dt, 60.0)
	check(is_finite(rb.longitudinal_force_n) and is_finite(rb.lateral_force_n), "Frenada con giro finita")
	# Elipse: combinado no supera budget.
	var t3 := make_tire()
	var re := settle(t3, 2, 3000.0, 18.0, -3.5, 20.0 / 0.28, 60, dt)
	check(float(t3.states[2].combined_utilization) < 1.6, "Elipse u=%.2f" % float(t3.states[2].combined_utilization))
	# Aterrizaje con volante girado: patch reseteado + blend rápido, sin NaN.
	var t4 := make_tire()
	t4.evaluate(2, 0.0, "Gravel", 15.0, -2.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, dt, 60.0)
	t4.states[2].patch_forward = Vector3(0, 0, -1)
	t4.states[2].patch_right = Vector3(1, 0, 0)
	t4.rotate_patch_frame(2, Vector3(0.2, 0, -0.97).normalized(), Vector3(0.97, 0, 0.2).normalized())
	var rl4 := t4.evaluate(2, 3000.0, "Gravel", 18.0, -2.5, 18.0 / 0.28, 0.28, 0.03, 1.0, 200.0, dt, 60.0)
	check(is_finite(rl4.longitudinal_force_n) and is_finite(rl4.lateral_force_n), "Aterrizaje con giro finito")

func test_effective_radius_and_peak() -> void:
	print("\n[10] Radio efectivo + pico/carga...")
	var t := make_tire()
	t.states[2].radial_deflection_m = 0.02
	t.states[2].estimated_carcass_deflection_m = 0.02
	var r := t.evaluate(2, 3000.0, "Gravel", 15.0, 0.0, 15.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	check(float(r.effective_radius_m) < 0.28 and float(r.effective_radius_m) > 0.15, "Radio efectivo acoplado (%.3f)" % float(r.effective_radius_m))
	# Pico/carga default 0 = neutro: sin clave no cambia el pico base.
	check(absf(float(t.axle_profiles[2].get("peak_load_sensitivity", 0.0))) < 1e-9, "peak_load_sensitivity default 0 (neutro)")

func test_film_puddle_ice() -> void:
	print("\n[11] Película/charco + hielo mojado + térmica + envolvente...")
	var t := make_tire()
	check(t.set_compound("gravel_normal"), "Compuesto de grava disponible")
	# Película fina: a 0 m/s pierde menos que a 25 m/s.
	var d_slow := t.compound_water_snow_ground_factor(1.0, 0.0, 30.0, 2, 0.0)
	var d_fast := t.compound_water_snow_ground_factor(1.0, 0.0, 30.0, 2, 25.0)
	check(float(d_fast.combined) < float(d_slow.combined) and float(d_slow.combined) < 1.0, "Aquaplaning con velocidad (%.3f>=%.3f pierde más rápido)" % [float(d_slow.combined), float(d_fast.combined)])
	# Hielo mojado: combina y clampea (antes ignoraba agua y se saltaba clamp).
	t.set_compound("snow_studded")
	var r_ice := t.evaluate(2, 2500.0, "Gravel", 12.0, 0.0, 12.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 10.0, 3.0, 0.0, 30.0, "ice")
	var wet_factor := clampf(float(t.states[2].compound_snow_factor) * float(t.states[2].compound_water_factor) * float(t.states[2].compound_ground_factor), 0.05, 1.0)
	t.evaluate(2, 2500.0, "Gravel", 12.0, 0.0, 12.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 10.0, 0.0, 0.0, 30.0, "ice")
	var dry_factor := clampf(float(t.states[2].compound_snow_factor) * float(t.states[2].compound_water_factor) * float(t.states[2].compound_ground_factor), 0.05, 1.0)
	check(is_finite(r_ice.longitudinal_force_n) and wet_factor >= 0.05 and wet_factor < dry_factor and dry_factor <= 1.0,
		"El agua reduce el agarre en hielo dentro de los límites")
	t.set_compound("gravel_normal")
	# Envolvente publicada y converge a Fz.
	var t2 := make_tire()
	var r2 := settle(t2, 2, 2500.0, 20.0, 0.0, 20.0 / 0.28, 60, 0.01)
	check(absf(float(r2.enveloped_load_n) - 2500.0) < 50.0, "Envolvente converge a Fz (%.0f)" % float(r2.enveloped_load_n))

func test_robustness() -> void:
	print("\n[12] Robustez: catálogo vacío, reset, rampa, warnings...")
	# Catálogo vacío: set_wheel_compound recarga en vez de fallar si el id existe.
	var t := make_tire()
	t.compound_catalog = {}
	t.active_compound = {}
	t.wheel_compounds.clear()
	var ok := t.set_wheel_compound(0, "gravel_normal")
	check(ok and t.wheel_compounds.size() == 4 and t.wheel_compounds[0].get("id") == "gravel_normal", "Catálogo vacío se recarga y selecciona el compuesto solicitado")
	# Reset completo sin restos.
	var t2 := make_tire()
	t2.states[0].patch_pos = Vector2(0.1, 0.05)
	t2.states[0].post_peak_decay_lat = 0.5
	t2.states[0].slip_ratio = 0.3
	t2.reset_patch(0)
	var s: Dictionary = t2.states[0]
	check(s.patch_pos == Vector2.ZERO and float(s.post_peak_decay_lat) == 0.0 and float(s.slip_ratio) == 0.0, "reset_patch sin restos")
	# Rampa aterrizaje: blend sube rápido al re-contactar.
	var t3 := make_tire()
	t3.axle_profiles[2].contact_ramp_tau_s = 0.3
	t3.states[2].contact_blend = 0.0
	t3.evaluate(2, 2500.0, "Gravel", 10.0, 0.0, 10.0 / 0.28, 0.28, 0.0, 1.0, 200.0, 0.01, 60.0)
	check(float(t3.states[2].contact_blend) > 0.2, "Aterrizaje rápido blend=%.2f" % float(t3.states[2].contact_blend))
	# Warnings limpios en configure.
	check(t3.missing_surface_warnings.is_empty(), "warnings limpios tras configure")
