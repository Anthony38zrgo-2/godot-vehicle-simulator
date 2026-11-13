extends SceneTree

var failures: Array[String] = []
var identifier := ""
var output_directory := ""
var render := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rt-id="):
			identifier = argument.trim_prefix("--rt-id=")
		elif argument.begins_with("--rt-output="):
			output_directory = argument.trim_prefix("--rt-output=")
		elif argument == "--rt-render":
			render = true
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func finish() -> void:
	var result := {"vehicle": identifier, "passed": failures.is_empty(), "failures": failures,
		"visual_review": "pending_human_review", "rendered": render}
	print("RT_VEHICLE_CONTRACT ", JSON.stringify(result))
	if not output_directory.is_empty():
		var file := FileAccess.open(output_directory.path_join("runtime.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "\t"))
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	var registry: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/registry.json"))
	if not registry is Dictionary or not registry.get("vehicles", {}).has(identifier):
		check(false, "vehicle registered")
		finish()
		return
	var entry: Dictionary = registry.vehicles[identifier]
	check(load("res://scenes/rally/" + str(entry.Stage) + ".tscn") is PackedScene, "stage scene loads")
	var packed = load("res://scenes/rally/" + str(entry.Proving) + ".tscn") as PackedScene
	if packed == null:
		check(false, "proving scene loads")
		finish()
		return
	var session = packed.instantiate()
	root.add_child(session)
	current_scene = session
	for i in 600:
		await physics_frame
		if session.session_ready:
			break
	check(session.session_ready, "session ready")
	var car = session.vehicle
	if car == null or not car._physics_ready:
		check(false, "physics ready")
		finish()
		return
	check(car.rally_profile.profile_id == identifier, "independent profile selected")
	var geometry: Dictionary = car.rally_asset_manifest.geometry
	check(absf(car.simulation.wheelbase_m - float(geometry.wheelbase)) < 0.0001, "wheelbase matches measured model")
	for axle in [0, 2]:
		var track: float = absf(car.simulation.wheel_positions_local[axle + 1].x - car.simulation.wheel_positions_local[axle].x)
		check(absf(track - float(geometry.front_track if axle == 0 else geometry.rear_track)) < 0.0001, "wheel track matches model")
	var cockpit = car.get_node("CockpitAnimation")
	check(cockpit.arms.size() == 2, "two animated arms")
	if cockpit.arms.size() == 2:
		check(cockpit._pose_indices[0].size() == 19 and cockpit._pose_indices[1].size() == 19, "19 native steering poses")
		var rest: Basis = cockpit.steering_wheel.basis
		cockpit.update_steering_pose(0.7)
		check(not cockpit.steering_wheel.basis.is_equal_approx(rest), "steering wheel animation")
		# Rally Trophy wheels lie in local XZ. Turning must keep the rim normal fixed.
		var turned: Basis = cockpit.steering_wheel.basis
		check(turned.y.is_equal_approx(rest.y), "wheel rotates about its local shaft")
		cockpit.update_steering_pose(0.0)
	var rig = session.camera_rig
	rig.camera_mode = rig.Mode.CHASE
	for mode in [rig.Mode.BONNET, rig.Mode.COCKPIT, rig.Mode.CHASE]:
		rig.toggle_camera_mode()
		check(rig.camera_mode == mode, "three available cameras")
		if cockpit.driver_head != null:
			check(cockpit.driver_head.visible == (mode != rig.Mode.COCKPIT), "driver head follows camera")
	var damage = car.get_node("VisualDamage")
	check(damage._damaged.has("body") and damage._damaged.has("interior") and damage._healthy.size() == damage._damaged.size(), "native damage variants")
	check(damage.broken_light != null and damage.broken_glass != null and damage.broken_glass_inside != null, "damage textures available")
	check(damage._healthy.body.get_active_material(0).albedo_texture != null, "textured body")
	check(damage._healthy.interior.get_active_material(0).albedo_texture != null, "textured cockpit")
	var cfg: Dictionary = car.simulation.domains.damage.get("visual", {})
	damage.register_impact(Vector3(-0.55, 0.45, -1.8), Vector3.BACK, 1.0, cfg)
	damage.register_impact(Vector3(0, 0.5, 1.8), Vector3.FORWARD, 1.0, cfg)
	damage._process(0)
	var snapshot: Dictionary = damage.damage_snapshot()
	for part in damage._damaged:
		check(damage._damaged[part].visible and not damage._healthy[part].visible, "damage switches " + part)
	var repair: Array[String] = ["body", "hood", "trunk", "windshield", "headlight_left", "headlight_right"]
	damage.repair_parts(repair)
	damage._process(0)
	check(damage.damage_snapshot().is_empty(), "repair clears damage")
	damage.restore_damage(snapshot)
	damage._process(0)
	check(damage._damaged.body.visible, "saved damage restored")
	damage.repair_parts(repair)
	damage._process(0)
	var audio = car.get_node("VehicleAudio")
	var gt3_banks := {
		"rt-mini-cooper-s": ["mini-cooper", 6, 6],
		"rt-lancia-stratos": ["stratos-rally-car", 6, 6],
		"rt-alfa-giulia-gta": ["civic-type-r", 8, 8],
		"rt-alpine-a110": ["vitz-rs", 8, 8],
		"rt-fiat-abarth-1000": ["civic-sir-ii", 9, 8],
		"rt-lotus-cortina": ["motor-sport-elise", 6, 5],
		"rt-opel-kadett": ["mx-5-18-rs", 8, 8],
		"rt-volvo-amazon": ["new-beetle-20", 6, 6],
		"rt-saab-96-v4": ["peugeot-206-s16", 7, 7],
	}
	var bank: Array = gt3_banks[identifier]
	check(audio.engine_bank_manifest_path == "res://sounds/banks/gt3-bank/" + bank[0] + "/manifest.json", "GT3 bank selected")
	check(audio.engine_voices.size() == bank[1] and audio.exhaust_voices.size() == bank[2], "GT3 engine and exhaust layers loaded")
	check(audio.coast_engine_voices.is_empty() and audio.coast_exhaust_voices.is_empty(), "GT3 uses continuous layers on coast")
	audio.set_physics_process(false)
	audio.update_view_balance()
	for throttle in [0.0, 0.5, 1.0]:
		audio.acoustic = {"throttle": throttle, "load": throttle}
		for fraction in [0.0, 0.15, 0.30, 0.5, 0.75, 1.0]:
			var rpm := lerpf(car.idle_rpm, car.max_rpm, fraction)
			audio.smoothed_revolutions = rpm
			audio.update_layer(audio.engine_voices, rpm, 1.0)
			audio.update_layer(audio.exhaust_voices, rpm, 1.0)
			audio.update_retention_audio(1.0)
			var energy := 0.0
			for voice in audio.engine_voices + audio.exhaust_voices + audio.coast_engine_voices + audio.coast_exhaust_voices:
				check(is_finite(voice.player.volume_linear) and is_finite(voice.player.pitch_scale), "finite audio mix")
				energy += voice.player.volume_linear * voice.player.volume_linear
			check(energy > 0.000001, "continuous RPM coverage")
	audio.set_physics_process(true)
	car.shift(1)
	Input.action_press(InputBindings.THROTTLE)
	await create_timer(1.5).timeout
	check(car.linear_velocity.dot(-car.global_basis.z) > 0.3, "forward acceleration")
	Input.action_release(InputBindings.THROTTLE)
	Input.action_press(InputBindings.BRAKES)
	await create_timer(0.35).timeout
	check(car.brake_input > 0.5, "brake input")
	Input.action_release(InputBindings.BRAKES)
	await create_timer(0.5).timeout
	check(car.global_position.is_finite() and car.linear_velocity.length() < 40, "finite stable motion")
	check(car.simulation.contact_query_count == 4, "one wheel query per wheel")
	if render and DisplayServer.get_name() != "headless":
		for item in session.find_children("*", "CanvasItem", true, false):
			(item as CanvasItem).hide()
		car.freeze = true
		var camera := Camera3D.new()
		session.add_child(camera)
		camera.global_position = car.global_transform * Vector3(3.5, 1.7, -4.5)
		camera.look_at(car.global_position + Vector3(0, 0.5, 0))
		camera.current = true
		await capture("exterior.png")
		damage.restore_damage(snapshot)
		damage._process(0)
		await capture("damage.png")
		damage.repair_parts(repair)
		damage._process(0)
		camera.queue_free()
		rig.camera.current = true
		rig.camera_mode = rig.Mode.COCKPIT
		rig.snap_to_target()
		await capture("cockpit.png")
	finish()

func capture(filename: String) -> void:
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output_directory.path_join(filename))
	check(result == OK, "screenshot saved: " + filename)
