extends SceneTree

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("FAILURE: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("--- Running Backfire Commons Contract ---")
	
	var test_vehicles := ["rt-porsche-356a", "rt-escort-rs2000", "fulvia"]
	var registry_file := FileAccess.open("res://data/vehicles/registry.json", FileAccess.READ)
	var registry: Dictionary = JSON.parse_string(registry_file.get_as_text()).get("vehicles", {})
	
	for vid in test_vehicles:
		check(registry.has(vid), "Registry has vehicle " + vid)
		var entry: Dictionary = registry.get(vid, {})
		var scene_path: String = "res://scenes/rally/" + str(entry.get("Proving", "")) + ".tscn"
		if not ResourceLoader.exists(scene_path):
			check(false, "Scene exists for " + vid + " -> " + scene_path)
			continue
		
		var packed: PackedScene = load(scene_path)
		var session = packed.instantiate()
		root.add_child(session)
		current_scene = session
		
		for frame in 60:
			await physics_frame
			if session.get("session_ready") == true:
				break
		
		var vehicle = session.get("vehicle")
		check(vehicle != null, vid + ": vehicle instantiated")
		if vehicle == null:
			session.queue_free()
			continue
			
		var audio = vehicle.get_node_or_null("VehicleAudio")
		check(audio != null, vid + ": VehicleAudio exists")
		if audio == null:
			session.queue_free()
			continue
		
		# Check configured paths
		check(audio.backfire_paths.size() >= 3, vid + ": configured backfire_paths has commons samples")
		for bp in audio.backfire_paths:
			check("commons/backfire" in str(bp), vid + ": path is in commons: " + str(bp))
		
		# Check player pools
		check(audio.backfire_players.size() >= 3, vid + ": backfire_players pool has commons samples (got " + str(audio.backfire_players.size()) + ")")
		check(audio.backfire_cabin_players.size() == audio.backfire_paths.size(), vid + ": backfire_cabin_players pool mirrors the exterior samples (got " + str(audio.backfire_cabin_players.size()) + ")")
		
		for p in audio.backfire_players:
			check(p.stream != null, vid + ": exterior player has valid stream")
			
		var cabin_bus := -1
		for p in audio.backfire_cabin_players:
			check(p.stream != null, vid + ": cabin player has valid stream")
			check(str(p.bus).ends_with("backfire_cabin"), vid + ": cabin player routed to backfire_cabin bus: " + str(p.bus))
			cabin_bus = AudioServer.get_bus_index(p.bus)
		check(cabin_bus >= 0, vid + ": cabin bus exists")
		if cabin_bus >= 0:
			var hpf_found := false
			for index in AudioServer.get_bus_effect_count(cabin_bus):
				var effect := AudioServer.get_bus_effect(cabin_bus, index)
				if effect is AudioEffectHighPassFilter and float(effect.cutoff_hz) > 100.0:
					hpf_found = true
			check(hpf_found, vid + ": cabin bus has a high-pass filter")
		
		# Test camera modes: CHASE (0) -> backfire_players, BONNET (1) -> backfire_cabin_players, COCKPIT (2) -> backfire_cabin_players
		var rig = session.get("camera_rig")
		check(rig != null, vid + ": Camera rig available")
		if rig != null:
			# Mode 0: CHASE -> exterior rear backfire
			rig.set("camera_mode", 0)
			var ext_played := false
			for attempt in 30:
				audio.backfire_event_cooldown = 0.0
				audio.play_backfire_event(1)
				for p in audio.backfire_players:
					if p.playing:
						ext_played = true
						p.stop()
						break
				if ext_played:
					break
			check(ext_played, vid + ": CHASE mode (0) plays exterior rear backfire")
			
			# Mode 1: BONNET -> exhaust samples on the HP-filtered cabin bus
			rig.set("camera_mode", 1)
			var bonnet_played := false
			for attempt in 30:
				audio.backfire_event_cooldown = 0.0
				audio.play_backfire_event(1)
				for p in audio.backfire_cabin_players:
					if p.playing:
						bonnet_played = true
						p.stop()
						break
				if bonnet_played:
					break
			check(bonnet_played, vid + ": BONNET mode (1) plays the exhaust sample on the cabin bus")
			
			# Mode 2: COCKPIT -> exhaust samples on the HP-filtered cabin bus
			rig.set("camera_mode", 2)
			var cockpit_played := false
			for attempt in 30:
				audio.backfire_event_cooldown = 0.0
				audio.play_backfire_event(1)
				for p in audio.backfire_cabin_players:
					if p.playing:
						cockpit_played = true
						p.stop()
						break
				if cockpit_played:
					break
			check(cockpit_played, vid + ": COCKPIT mode (2) plays the exhaust sample on the cabin bus")

		session.queue_free()
		await process_frame

	print("--- Backfire Commons Contract Completed ---")
	if failures.is_empty():
		print("BACKFIRE_COMMONS_CONTRACT: ALL TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		print("BACKFIRE_COMMONS_CONTRACT: FAILED with " + str(failures.size()) + " errors: " + str(failures))
		quit(1)
