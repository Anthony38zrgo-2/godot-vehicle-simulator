extends SceneTree

class TestEvent:
	extends "res://scripts/rally/rally_event_manager.gd"
	func save() -> bool:
		return true

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func check_differential(profile: String, front: bool) -> void:
	var loaded := VehicleProfileLoader.load_profile(profile)
	check(loaded.ok, "profile loads: " + profile)
	if not loaded.ok:
		return
	var model := VehiclePowertrainModel.new()
	check(model.configure(loaded.domains).ok, "powertrain configures")
	model.set_gear(0)
	model.clutch_engagement = 0.0
	var spins: Array[float] = [12.0, -12.0, 12.0, -12.0]
	var inertia: Array[float] = [0.6, 0.6, 0.6, 0.6]
	var zeros: Array[float] = [0.0, 0.0, 0.0, 0.0]
	model.solve_rotation(0.002, spins, inertia, zeros, zeros)
	var axle := 0 if front else 2
	var free_axle := 2 if front else 0
	check(absf(spins[axle] - spins[axle + 1]) < 24.0, "LSD resists driven axle slip")
	check(is_equal_approx(spins[free_axle], 12.0) and is_equal_approx(spins[free_axle + 1], -12.0), "LSD leaves undriven axle free")
	check(is_equal_approx(spins[axle] + spins[axle + 1], 0.0), "LSD conserves pair angular momentum")

func run() -> void:
	check_differential("res://data/vehicles/lancia-fulvia/vehicle.json", true)
	check_differential("res://data/vehicles/ford-escort-rs2000/vehicle.json", false)
	var manager := TestEvent.new()
	check(manager.begin_event(), "event begins")
	var session = load("res://scenes/rally/russia_stage1_lancia_fulvia.tscn").instantiate()
	session.begin_event_session(manager, "russia_stage1")
	session.weather_enabled = false
	root.add_child(session)
	current_scene = session
	for i in 1200:
		await physics_frame
		if session.session_ready:
			break
	check(session.session_ready, "Fulvia stage ready")
	var vehicle = session.vehicle
	check(vehicle.rally_profile.profile_id == "lancia_fulvia_1600_hf", "selected Fulvia profile")
	check(vehicle.maximum_forward_gear == 5, "five forward gears")
	check(vehicle.simulation.powertrain_model.front_torque_split == 1.0, "front drive")
	check(Engine.physics_ticks_per_second >= 120, "light hub stable world rate")
	check(is_equal_approx(vehicle.simulation.mass_model.inventory_mass_kg, 945.0), "mass inventory closes including crew")
	check(session.garage_panel.vehicle == vehicle, "garage binds Fulvia")
	var geometry: Dictionary = vehicle.rally_asset_manifest.geometry
	check(absf(vehicle.simulation.wheelbase_m - 2.480) < 0.0001, "native Rally Trophy wheelbase 2.480 m")
	for axle in [0, 2]:
		var track: float = absf(vehicle.simulation.wheel_positions_local[axle + 1].x - vehicle.simulation.wheel_positions_local[axle].x)
		check(absf(track - float(geometry.front_track if axle == 0 else geometry.rear_track)) < 0.0001, "measured track matches simulation")
		check(absf(track - 1.2200001) < 0.0001, "native Rally Trophy wheel track")
	check_psx_mesh(vehicle.get_node_or_null("Chassis/FulviaPSXExterior") as MeshInstance3D, "chassis")
	var wheel_nodes := ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]
	for i in wheel_nodes.size():
		var node_name: String = wheel_nodes[i]
		var pivot := vehicle.get_node(node_name) as Node3D
		var hub: Vector3 = vehicle.simulation.wheel_positions_local[i]
		hub.y += vehicle.simulation.unsprung_rig.q[i]
		check(pivot.position.distance_to(hub) < 0.001, "visible wheel follows hub at spawn: " + node_name)
		var wheel := pivot.get_node("WheelVisual/WheelMesh")
		var meshes: Array[Node] = wheel.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() == 1, "one PSX wheel mesh: " + node_name)
		if meshes.size() == 1:
			var tire := meshes[0] as MeshInstance3D
			check_psx_mesh(tire, node_name)
			check(tire.to_global(tire.get_aabb().get_center()).distance_to(pivot.global_position) < 0.001,
				"tire mesh centered on spindle: " + node_name)
	check(not vehicle.cockpit_camera_enabled, "PSX Fulvia cockpit temporarily disabled")
	check(vehicle.get_node_or_null("CockpitAnimation") == null, "PSX chassis has no cockpit animation")
	check(vehicle.get_node_or_null("VisualDamage") == null, "PSX Fulvia visual damage temporarily disabled")
	check_audio(vehicle)
	var rig = session.camera_rig
	rig.camera_mode = rig.Mode.CHASE
	for expected in [rig.Mode.BONNET, rig.Mode.CHASE]:
		rig.toggle_camera_mode()
		check(rig.camera_mode == expected, "PSX Fulvia skips cockpit view")
	var escort = load("res://scenes/rally/ford_escort_rs2000_1971.tscn").instantiate()
	root.add_child(escort)
	escort.freeze = true
	rig.set_vehicle(escort)
	rig.camera_mode = rig.Mode.BONNET
	rig.toggle_camera_mode()
	check(rig.camera_mode == rig.Mode.COCKPIT, "Escort retains cockpit")
	rig.set_vehicle(vehicle)
	check(rig.camera_mode == rig.Mode.CHASE, "switching to PSX Fulvia exits cockpit view")
	escort.queue_free()
	if session.awaiting_setup:
		session.garage_panel.close_garage(true)
	await create_timer(0.5).timeout
	check(vehicle.global_position.is_finite() and vehicle.linear_velocity.length() < 5.0, "stage start stable")
	if DisplayServer.get_name() != "headless":
		for item in session.find_children("*", "CanvasItem", true, false):
			(item as CanvasItem).hide()
		var camera := Camera3D.new()
		session.add_child(camera)
		camera.global_position = vehicle.global_transform * Vector3(3.7, 1.7, -4.5)
		camera.look_at(vehicle.global_position + Vector3(0, 0.5, 0))
		camera.current = true
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "user://fulvia_import_preview.png"
		root.get_texture().get_image().save_png(path)
		print("FULVIA_PREVIEW ", ProjectSettings.globalize_path(path))
		camera.queue_free()
	await session.load_event_stage("russia_stage2")
	check(session.session_ready and session.session_track_id == "russia_stage2", "stage transition ready")
	check(session.vehicle == vehicle and vehicle.rally_profile.profile_id == "lancia_fulvia_1600_hf", "stage transition preserves Fulvia")
	print("FULVIA_IMPORT_CONTRACT ", JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func check_psx_mesh(instance: MeshInstance3D, label: String) -> void:
	check(instance != null and instance.mesh != null, "PSX mesh imported: " + label)
	if instance == null or instance.mesh == null:
		return
	var material := instance.get_active_material(0) as BaseMaterial3D
	check(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"PSX baked lighting: " + label)
	if material != null:
		var atlas := material.albedo_texture
		check(atlas != null and atlas.get_size() == Vector2(512, 512), "PSX atlas imported: " + label)
		check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "PSX nearest sampling: " + label)

func energy(voices: Array) -> float:
	var sum := 0.0
	for voice in voices:
		sum += voice.player.volume_linear * voice.player.volume_linear
	return sum

func check_audio(vehicle: Node) -> void:
	var audio = vehicle.get_node("VehicleAudio")
	check(audio.engine_bank_manifest_path == "res://sounds/banks/gt3-bank/trueno-gt-apex/manifest.json", "RR3 Trueno GT3 audio bank")
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(audio.engine_bank_manifest_path))
	check(bank.samples.size() == 39, "Trueno GT3 bank inventory complete")
	for sample in bank.samples:
		var path: String = sample.get("path", audio.engine_bank_manifest_path.get_base_dir().path_join(str(sample.file)))
		check(FileAccess.get_sha256(path) == sample.sha256, "audio source hash: " + sample.file)
		var stream := SeamlessVehicleLoop.load_pcm(path, false)
		check(stream != null and stream.mix_rate == int(sample.rate_hz), "PCM decodes: " + sample.file)
	check(audio.engine_voices.size() == 7 and audio.exhaust_voices.size() == 5, "Trueno engine and exhaust layers loaded")
	check(audio.coast_engine_voices.is_empty() and audio.coast_exhaust_voices.is_empty(), "Trueno uses continuous layers on coast")
	check(audio.whine_players.size() == bank.whine.size() and audio.backfire_players.size() == bank.backfire.size(), "dedicated auxiliary layers loaded")
	audio.set_physics_process(false)
	audio.update_view_balance()
	for throttle in [0.0, 0.5, 1.0]:
		audio.acoustic = {"throttle": throttle, "load": throttle}
		for rpm in [1100.0, 1500.0, 2000.0, 2500.0, 3000.0, 4250.0, 5000.0, 6500.0, 7600.0]:
			audio.smoothed_revolutions = rpm
			audio.update_layer(audio.engine_voices, rpm, 1.0)
			audio.update_layer(audio.exhaust_voices, rpm, 1.0)
			audio.update_retention_audio(1.0)
			check(energy(audio.engine_voices) + energy(audio.coast_engine_voices) > 0.000001, "engine RPM coverage")
			for voice in audio.engine_voices + audio.exhaust_voices + audio.coast_engine_voices + audio.coast_exhaust_voices:
				check(is_finite(voice.player.volume_linear) and is_finite(voice.player.pitch_scale), "finite audio blend")
	audio.set_physics_process(true)
