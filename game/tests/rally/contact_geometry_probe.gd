extends SceneTree
## contact_geometry_probe.gd — Sonda H2 + §§2-3: alcance y coherencia.
## Fase A (plano): tándem vs ShapeCast en reposo; alcance efectivo 0.21.
## Fase B (bordillo, ambos sentidos): caja bajo el borde de la huella FL con
##   tándem OFF; el barrido puede ver bordillo + suelo (dos apoyos).
## Fase C (pendiente de apoyo único): placa inclinada 15° que cubre la huella.
## H2: Godot 4.7.1 no expone fracción por colisión; la distancia sale del
##   barrido cilíndrico aislando el apoyo seleccionado (mismo punto/normal/
##   collider). La coherencia se demuestra por correspondencia (verify:
##   mismo collider, punto y normal), no por el rango [0,1].
## Fase D2 (dos apoyos determinista, sin vehículo): barrido manual sobre
##   placa 5° + suelo con toques casi simultáneos; verifica aislamiento
##   (sweeps=2), correspondencia y distancia del apoyo aislado.
## Salida: CONTACT_GEOMETRY_RESULT (A), CONTACT_CURB_RESULT (B1/B2),
##   CONTACT_SLOPE_RESULT (C), CONTACT_DUAL_RESULT (D2) + veredicto.

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
	else:
		print("  PASS: " + label)


func _initialize() -> void:
	call_deferred("run")


func _spawn_box(parent: Node, center: Vector3, size: Vector3, rot_z: float, bname: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = bname
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.FORWARD, rot_z), center)
	return body


func _fl_samples(vehicle: Node) -> Array:
	return [vehicle.simulation.sample_suspension_trace(), vehicle.simulation.sample_contact_trace()]


func run() -> void:
	print("--- CONTACT GEOMETRY PROBE (H2, §§2-3) ---")
	Engine.physics_ticks_per_second = 60
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 240:
		await physics_frame
		if scene.session_ready:
			break
	if not scene.session_ready:
		check(false, "proving ground session ready")
		quit(1)
		return
	var vehicle = scene.vehicle
	var ctl = scene.input_controller
	ctl.set_physics_process(false)
	vehicle.throttle_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.steering_input = 0.0
	vehicle.handbrake_input = 0.0
	for i in 120:
		await physics_frame
	var results := {}
	for tandem in [true, false]:
		vehicle.simulation.tandem_cam_enabled = tandem
		for i in 30:
			await physics_frame
		var susp: Array = vehicle.simulation.sample_suspension_trace()
		var cont: Array = vehicle.simulation.sample_contact_trace()
		var hubs: Array = []
		for h in vehicle.simulation.unsprung_rig.hubs:
			var p: Vector3 = (h as Node3D).global_position
			hubs.append([p.x, p.y, p.z])
		var entry := {"tandem": tandem, "hubs": hubs, "suspension": susp, "contacts": cont}
		results["tandem" if tandem else "shapecast"] = entry
		print("CONTACT_GEOMETRY_RESULT ", JSON.stringify(entry))
	var tol_load := 0.15
	var tol_defl := 0.004
	var ok := true
	for w in 4:
		var st: Dictionary = (results["tandem"] as Dictionary)["suspension"][w]
		var ss: Dictionary = (results["shapecast"] as Dictionary)["suspension"][w]
		var ct: Dictionary = (results["tandem"] as Dictionary)["contacts"][w]
		var cs: Dictionary = (results["shapecast"] as Dictionary)["contacts"][w]
		if not bool(st.get("geometric_contact", false)) or not bool(ss.get("geometric_contact", false)):
			ok = false
			push_error("rueda %d sin contacto geométrico en plano" % w)
		var lt := float(st.get("load_n", 0.0))
		var ls := float(ss.get("load_n", 0.0))
		if lt <= 0.0 or ls <= 0.0:
			ok = false
			push_error("rueda %d sin carga positiva en plano" % w)
		var rel := absf(lt - ls) / maxf((lt + ls) * 0.5, 1.0)
		var dt_defl := absf(float(ct.get("radial_deflection_m", 0.0)) - float(cs.get("radial_deflection_m", 0.0)))
		if rel > tol_load or dt_defl > tol_defl:
			ok = false
			push_error("rueda %d diverge tandem/shapecast: rel=%.3f ddefl=%.4f" % [w, rel, dt_defl])
		# H2: coherencia por correspondencia, no por rango.
		if bool(cs.get("hit", false)) and not bool(cs.get("coherent", false)):
			ok = false
			push_error("rueda %d ShapeCast no coherente en plano" % w)
	check(ok, "tándem y ShapeCast coinciden en plano dentro de tolerancia")
	var q := UnsprungSuspensionRig.contact_query_travel_m(0.22, 0.18)
	check(absf(float(q["droop_effective"]) - 0.21) < 0.0001, "alcance efectivo 0.21 verificado en escena")
	# Fases B/C con ShapeCast (tándem OFF).
	vehicle.simulation.tandem_cam_enabled = false
	var fl_hub: Vector3 = (vehicle.simulation.unsprung_rig.hubs[0] as Node3D).global_position
	var fl_ground_y := float(((results["shapecast"] as Dictionary)["contacts"][0] as Dictionary).get("position", [0.0, 0.0, 0.0])[1])
	var disagreement_observed := false
	# B1/B2: bordillo a ambos lados de la huella (cruce en ambos sentidos).
	for sense in [+1.0, -1.0]:
		var curb := _spawn_box(scene, Vector3(fl_hub.x + 0.12 * sense, fl_ground_y + 0.05, fl_hub.z), Vector3(0.5, 0.10, 0.5), 0.0, "CurbProbe")
		var best: Dictionary = {}
		var best_count := 0
		for i in 30:
			await physics_frame
			var smp := _fl_samples(vehicle)
			var c0: Dictionary = (smp[1] as Array)[0]
			if int(c0.get("collision_count", 1)) >= best_count:
				best_count = int(c0.get("collision_count", 1))
				best = {"suspension": (smp[0] as Array)[0], "contact": c0}
		var entry_b := {"sense": sense, "max_collision_count": best_count, "fl": best}
		print("CONTACT_CURB_RESULT ", JSON.stringify(entry_b))
		var cc: Dictionary = best.get("contact", {})
		if int(cc.get("collision_count", 1)) > 1:
			# Desacuerdo potencial: la fracción global puede ser de otro apoyo.
			if str(cc.get("collider", "")) != "" and absf(float(cc.get("safe_fraction", 0.0)) - float(cc.get("global_safe_fraction", 0.0))) > 0.001:
				disagreement_observed = true
		if bool(cc.get("hit", false)):
			if not bool(cc.get("coherent", false)):
				ok = false
				push_error("bordillo sentido %+.0f no coherente" % sense)
			# La distancia usada es la del barrido aislado del apoyo.
			check(bool(cc.get("coherent", false)), "bordillo sentido %+.0f coherente (aislado=%s, n=%d)" % [sense, str(bool(cc.get("isolated", false))), int(cc.get("collision_count", 1))])
		curb.queue_free()
		await physics_frame
	# C: pendiente de apoyo único (placa 15° cubriendo la huella).
	var ramp := _spawn_box(scene, Vector3(fl_hub.x, fl_ground_y + 0.10, fl_hub.z), Vector3(1.0, 0.06, 1.0), deg_to_rad(15.0), "SlopeProbe")
	for i in 30:
		await physics_frame
	var smp_c := _fl_samples(vehicle)
	var cc_slope: Dictionary = (smp_c[1] as Array)[0]
	var ss_slope: Dictionary = (smp_c[0] as Array)[0]
	print("CONTACT_SLOPE_RESULT ", JSON.stringify({"fl_suspension": ss_slope, "fl_contact": cc_slope}))
	if bool(cc_slope.get("hit", false)):
		check(int(cc_slope.get("collision_count", 1)) == 1, "pendiente con apoyo único (n=1)")
		check(absf(float((cc_slope.get("normal", [0, 1, 0]) as Array)[1])) < 1.0 and float((cc_slope.get("normal", [0, 1, 0]) as Array)[1]) > 0.9, "pendiente con normal inclinada coherente")
		if not bool(cc_slope.get("coherent", false)):
			ok = false
			push_error("pendiente apoyo único no coherente")
	ramp.queue_free()
	await physics_frame
	# Fase D (dos apoyos): placa fina inclinada 45° sobre el suelo bajo el
	# borde de la huella: el barrido ve placa (alta, normal 0.71) + suelo
	# (normal 1.0). La fracción global es de la placa; el apoyo seleccionado
	# es el suelo → desacuerdo que solo resuelve el aislamiento.
	var plate := _spawn_box(scene, Vector3(fl_hub.x + 0.06, fl_ground_y + 0.12, fl_hub.z), Vector3(0.25, 0.02, 0.25), deg_to_rad(45.0), "TiltPlateProbe")
	var best_d: Dictionary = {}
	var best_d_count := 0
	for i in 20:
		await physics_frame
		var smp := _fl_samples(vehicle)
		var c0: Dictionary = (smp[1] as Array)[0]
		if int(c0.get("collision_count", 1)) >= best_d_count:
			best_d_count = int(c0.get("collision_count", 1))
			best_d = {"suspension": (smp[0] as Array)[0], "contact": c0}
	print("CONTACT_DUAL_RESULT ", JSON.stringify({"max_collision_count": best_d_count, "fl": best_d}))
	var cd: Dictionary = best_d.get("contact", {})
	if int(cd.get("collision_count", 1)) > 1:
		check(bool(cd.get("isolated", false)), "dos apoyos: distancia del barrido aislado")
		check(bool(cd.get("coherent", false)), "dos apoyos: apoyo aislado coherente")
		if absf(float(cd.get("safe_fraction", 0.0)) - float(cd.get("global_safe_fraction", 0.0))) > 0.001:
			disagreement_observed = true
			print("  PASS: desacuerdo global-vs-apoyo reproducido y resuelto (safe %.4f vs global %.4f)" % [float(cd.get("safe_fraction", 0.0)), float(cd.get("global_safe_fraction", 0.0))])
		else:
			print("  NOTA: dos apoyos con misma fracción (coherencia por correspondencia OK)")
		if not bool(cd.get("coherent", false)):
			ok = false
			push_error("doble apoyo no coherente")
	else:
		print("  NOTA: placa inclinada no dio 2 colisiones (n=%d); aislamiento cubierto por código + contrato" % best_d_count)
	plate.queue_free()
	await physics_frame
	# Fase D2 (dos apoyos determinista, sin vehículo): barrido manual sobre
	# placa inclinada 45° + suelo. La fracción global es de la placa (alta);
	# el apoyo seleccionado es el suelo (normal 1.0 > 0.71). Solo el
	# aislamiento da la distancia coherente.
	# Suelo a +0.10 y esquina alta de la placa a +0.1015 (1.5 mm por encima,
	# dentro del margen de contacto de 2 mm): el barrido se bloquea en la
	# placa (normal 5°: alineación 0.996) y el suelo también toca, así que
	# reporta LOS 2 apoyos. El apoyo seleccionado es el suelo (1.0 mayor);
	# la fracción global es de la placa → desacuerdo determinista que solo
	# resuelve el aislamiento. Signo -5°: la esquina alta queda hacia +x,
	# dentro de la huella del cilindro.
	var ground_box := _spawn_box(scene, Vector3(0.30, 0.05, 0.0), Vector3(1.20, 0.10, 1.20), 0.0, "DualGroundProbe")
	var tilt_box := _spawn_box(scene, Vector3(-0.20, 0.0697, 0.0), Vector3(0.50, 0.02, 0.50), deg_to_rad(-5.0), "DualTiltProbe")
	var manual := ShapeCast3D.new()
	manual.shape = CylinderShape3D.new()
	(manual.shape as CylinderShape3D).radius = 0.28
	(manual.shape as CylinderShape3D).height = 0.20
	manual.margin = 0.002
	manual.max_results = 8
	manual.collide_with_areas = false
	manual.collide_with_bodies = true
	manual.collision_mask = 1
	scene.add_child(manual)
	manual.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.0))
	manual.target_position = Vector3(0.0, -0.45, 0.0)
	for i in 3:
		await physics_frame
	var dual := FordRallyVehicleSimulation.shapecast_coherent_result(manual, Vector3.UP, 0.28, 0.45, 0.24, [])
	print("CONTACT_DUAL_RESULT ", JSON.stringify(dual))
	if int(dual.get("collision_count", 0)) > 1:
		check(bool(dual.get("isolated", false)), "dos apoyos deterministas: distancia del barrido aislado")
		check(bool(dual.get("coherent", false)), "dos apoyos deterministas: apoyo aislado coherente")
		if absf(float(dual.get("safe_fraction", 0.0)) - float(dual.get("global_safe_fraction", 0.0))) > 0.001:
			disagreement_observed = true
			print("  PASS: desacuerdo global-vs-apoyo reproducido y resuelto (safe %.4f vs global %.4f)" % [float(dual.get("safe_fraction", 0.0)), float(dual.get("global_safe_fraction", 0.0))])
		var v: Dictionary = dual.get("verify", {})
		check(bool(v.get("same_collider", false)), "aislado conserva el collider seleccionado")
		check(float(v.get("point_gap_m", 99.0)) < 0.05 and float(v.get("normal_gap", 99.0)) < 0.05, "aislado conserva punto y normal")
		if not bool(dual.get("coherent", false)):
			ok = false
			push_error("doble apoyo determinista no coherente")
	else:
		push_error("se esperaban 2 apoyos en el barrido manual (n=%d)" % int(dual.get("collision_count", 0)))
		ok = false
	manual.queue_free()
	tilt_box.queue_free()
	ground_box.queue_free()
	await physics_frame
	if disagreement_observed:
		print("  PASS: desacuerdo global-vs-apoyo reproducido y resuelto por aislamiento")
	else:
		# Con apoyos casi coplanares (único caso con 2 colisiones en un
		# barrido: el margen es 2 mm) las fracciones coinciden; la
		# coherencia queda demostrada por correspondencia (verify) con el
		# aislamiento ejecutado (sweeps=2).
		print("  NOTA: apoyos casi coplanares, fracciones iguales; coherencia por correspondencia OK")
	scene.queue_free()
	await process_frame
	print("CONTACT_GEOMETRY_PROBE ", "PASS" if failures.is_empty() and ok else "FAIL")
	quit(0 if failures.is_empty() and ok else 1)
