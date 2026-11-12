extends SceneTree
## tire_static_contact_contract.gd
##
## Regression & acceptance suite for the low-speed anchored contact in
## TireModel: below ~1 m/s tread transport the brush memory blends toward a
## ground-anchored Coulomb spring-damper (Kelvin-Voigt on patch_pos with the
## post-migration brush stiffness, damping on slip velocity, hard-capped to
## the slide-aware friction ellipse). Rolling without wheel rotation is cut.
##
## Acceptance criteria:
## 1. Rest, small deflection: spring force follows the patch (holding sign).
## 2. Rest, huge preset: Coulomb-bounded breakaway (finite, near the cap).
## 3. Burnout (rim >> 0, V = 0): stays on the dynamic branch (drive force).
## 4. Parked on a slope, locked wheels: holds with < 1 mm/s after 10 s.
## 5. Rolling stop into hold: stops, settles, no physical chatter.

var failures: Array[String] = []
var domains: Dictionary = {}
var filters: Dictionary = {}


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)
	else:
		print("  PASS: " + message)


func _initialize() -> void:
	call_deferred("run_suite")


func run_suite() -> void:
	print("--- TIRE STATIC CONTACT CONTRACT ---")
	var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
	if not bool(loader.get("ok", false)):
		failures.append("Escort RS2000 profile must load")
		push_error("FAIL: Escort RS2000 profile must load")
		quit(1)
		return
	domains = loader.domains.duplicate(true)
	filters = loader.resolved_tire_filters.duplicate(true)
	test_rest_sign()
	test_breakaway_cap()
	test_burnout_dynamic()
	test_slope_hold()
	test_rolling_stop()
	if failures.is_empty():
		print("\nALL TIRE STATIC CONTACT TESTS PASSED!")
		quit(0)
	else:
		print("\nTIRE STATIC CONTACT CONTRACT FAILED with %d errors:" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)


func make_tire() -> TireModel:
	var tire := TireModel.new()
	tire.configure(domains, filters, [3000.0, 3000.0, 3000.0, 3000.0])
	return tire


func step(tire: TireModel, vx: float, rim: float, dt: float) -> Dictionary:
	return tire.evaluate(2, 3000.0, "Gravel", vx, 0.0, rim, 0.32, 0.0, 1.0, 200.0, dt, 60.0)


func test_rest_sign() -> void:
	print("\n[1] Rest spring follows the patch...")
	var tire := make_tire()
	tire.states[2].patch_pos = Vector2(0.010, 0.005)
	var r := tire.evaluate(2, 3000.0, "Gravel", 0.0, 0.0, 0.0, 0.32, 0.0, 1.0, 200.0, 1.0 / 120.0, 60.0)
	check(float(r.longitudinal_force_n) > 0.0 and float(r.lateral_force_n) > 0.0,
		"Rest force follows patch deflection (holding spring)")


func test_breakaway_cap() -> void:
	print("\n[2] Rest breakaway is Coulomb-bounded...")
	var tire := make_tire()
	tire.states[2].patch_pos = Vector2(0.5, 0.2)
	tire.states[2].contact_blend = 1.0
	tire.states[2].surface_initialized = true
	tire.states[2].surface_friction = 1.0
	tire.states[2].surface_stiffness = 1.0
	tire.states[2].surface_rolling = 2.0
	var r := tire.evaluate(2, 3000.0, "Gravel", 0.0, 0.0, 0.0, 0.32, 0.0, 1.0, 200.0, 1.0 / 120.0, 60.0)
	var f := Vector2(float(r.longitudinal_force_n), float(r.lateral_force_n))
	check(f.length() > 1500.0 and f.length() < 4500.0,
		"Breakaway force is capped near mu*Fz, got |F|=%f" % f.length())


func test_burnout_dynamic() -> void:
	print("\n[3] Burnout stays dynamic...")
	var tire := make_tire()
	var dt := 1.0 / 120.0
	var r: Dictionary = {}
	for i in 60:
		r = step(tire, 0.0, 20.0 / 0.32, dt)
	check(float(r.longitudinal_force_n) > 1500.0,
		"Spinning wheel at zero speed still drives (dynamic branch)")


func test_slope_hold() -> void:
	print("\n[4] Parked on a slope holds (10 s, locked wheels)...")
	var tire := make_tire()
	var dt := 1.0 / 120.0
	var m := 3000.0 / 9.81
	var pull := m * 9.81 * 0.17
	var v := 0.0
	var vmax := 0.0
	var vmax_late := 0.0
	for i in int(10.0 / dt):
		var r := step(tire, v, 0.0, dt)
		v += (pull + float(r.longitudinal_force_n)) / m * dt
		vmax = maxf(vmax, absf(v))
		if float(i) * dt > 5.0:
			vmax_late = maxf(vmax_late, absf(v))
	check(absf(v) < 0.001 and vmax_late < 0.001,
		"Parked holds: v_final=%f vmax_late=%f (< 1 mm/s)" % [v, vmax_late])
	check(vmax < 0.15, "Slope transient stays small, vmax=%f" % vmax)


func test_rolling_stop() -> void:
	print("\n[5] Rolling stop settles without chatter...")
	var tire := make_tire()
	var dt := 1.0 / 120.0
	var m := 3000.0 / 9.81
	var v := 2.0
	var vmax_mid := 0.0
	var vmax_last := 0.0
	for i in int(4.0 / dt):
		var r := step(tire, v, 0.0, dt)
		v += float(r.longitudinal_force_n) / m * dt
		var t := float(i) * dt
		if t > 2.0 and t <= 3.0:
			vmax_mid = maxf(vmax_mid, absf(v))
		if t > 3.0:
			vmax_last = maxf(vmax_last, absf(v))
	check(absf(v) < 0.03 and vmax_mid < 0.001 and vmax_last < 0.001,
		"Stop settles: v_final=%f mid=%f last=%f" % [v, vmax_mid, vmax_last])
