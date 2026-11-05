extends SceneTree


func _initialize() -> void:
	call_deferred("verify")


func check_manifest() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/cmr4/manifest.json"))
	assert(parsed is Dictionary, "CMR4 manifest must parse")
	var manifest: Dictionary = parsed
	var assets: Dictionary = manifest.get("assets", {})
	assert(assets.size() == 26, "CMR4 manifest must list the 26 textures")
	assert(str(manifest.get("archive_sha256", "")).length() == 64)
	for name in assets.keys():
		var path := "res://assets/vfx/cmr4/" + str(name)
		assert(FileAccess.file_exists(path), "Missing " + path)
		var entry: Dictionary = assets[name]
		assert(
			FileAccess.get_sha256(path) == str(entry.get("png_sha256", "")),
			"PNG hash mismatch " + str(name),
		)
		var texture := load(path) as Texture2D
		assert(texture != null, "Cannot load " + str(name))
		var image := texture.get_image()
		assert(image.get_width() == int(entry.get("width", -1)), "Width mismatch " + str(name))
		assert(image.get_height() == int(entry.get("height", -1)), "Height mismatch " + str(name))
		var has_alpha := image.detect_alpha() != Image.ALPHA_NONE
		assert(
			has_alpha == bool(entry.get("alpha", {}).get("present", false)),
			"Alpha mismatch " + str(name),
		)
		if str(entry.get("blend", "alpha")) == "additive":
			assert(not has_alpha, "Additive sprite must be opaque " + str(name))
	assert(
		assets["dust_01.png"]["dds_sha256"] == assets["dust_02.png"]["dds_sha256"],
		"Dust duplicates must share the source hash",
	)
	assert(assets["sprk_sml.png"]["blend"] == "additive")
	assert(assets["sprk_big.png"]["blend"] == "additive")
	var notes := ""
	for note in manifest.get("notes", []):
		notes += str(note)
	assert("idénticos" in notes, "The Dust duplicate must be documented")


func trigger_impact(vfx, contact: Dictionary, wetness: float) -> ShaderMaterial:
	vfx.vehicle.body_contact_vfx.clear()
	vfx.vehicle.body_contact_vfx.append(contact)
	vfx.impact_busy.fill(0.0)
	vfx.impact_cooldown = 0.0
	vfx.update_impacts(wetness)
	for i in vfx.impact_pool.size():
		if vfx.impact_busy[i] > 0.0:
			var quad := vfx.impact_pool[i].draw_pass_1 as QuadMesh
			return quad.material as ShaderMaterial
	return null


func verify() -> void:
	check_manifest()
	var scene = load("res://scenes/rally/rally_proving_ground.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 240:
		await physics_frame
	var vehicle = scene.get_node("FordEscortRS2000")
	var vfx = vehicle.get_node("VehicleVFX")
	vfx.set_physics_process(false)
	assert(vfx.wheel_bursts.size() == 20 and vfx.impact_pool.size() == 6)
	var wheel_quad := vfx.wheel_bursts[0].draw_pass_1 as QuadMesh
	var wheel_material := wheel_quad.material as ShaderMaterial
	assert(wheel_material.get_shader_parameter("body_exclusion_strength") == 1.0)
	var sim = vehicle.simulation
	var index := -1
	for i in [2, 3]:
		if sim.wheel_loads[i] > 60.0 and sim.wheel_contact_casts[i].is_colliding():
			index = i
			break
	assert(index >= 0, "Real Jolt wheel casts must reach the proving ground")
	vehicle.freeze = true
	for front in [0, 1]:
		vfx.update_wheel(front, 1.0)
	assert(vfx.wheel_burst_busy.count(0.0) == 20)
	vehicle.linear_velocity = Vector3(0, 0, -15)
	# Both axles can leave marks independently of the rear-only particle emitters.
	var contact_point: Vector3 = sim.wheel_contact_points[index]
	vfx.tire_tracks.clear_tracks()
	sim.wheel_surfaces[index] = "asphalt"
	sim.last_local_conditions[index] = { "snow_mm": 0.0 }
	sim.wheel_slips[index] = Vector2(0.4, 0.0)
	vfx.update_tire_track(index)
	sim.wheel_contact_points[index] = contact_point + Vector3(0.0, 0.0, 0.5)
	vfx.update_tire_track(index)
	assert(vfx.tire_tracks.counts[index % 2] == 1, "Loaded slipping wheel should leave a mark")
	sim.wheel_slips[index] = Vector2.ZERO
	vfx.update_tire_track(index)
	assert(vfx.tire_tracks.active[index], "Rolling contact must retain track continuity")
	sim.wheel_contact_points[index] = contact_point
	vfx.tire_tracks.clear_tracks()
	sim.wheel_slips[index] = Vector2(0.24, 0.12)
	for surface in ["Gravel", "Dirt", "Sand", "Grass"]:
		vfx.clear_wheel_bursts()
		sim.wheel_surfaces[index] = surface
		sim.last_local_conditions[index] = { "snow_mm": 0.0 }
		vfx.update_wheel(index, 0.0)
		if surface == "Grass":
			assert(vfx.wheel_burst_busy.count(0.0) == 19)
			assert(wheel_burst_texture(vfx, 0).contains("leaf_"))
		else:
			assert(vfx.wheel_burst_busy.count(0.0) == 19)
			assert(wheel_burst_texture(vfx, 0).ends_with("dust_01.png"))
			assert(vfx.wheel_bursts[0].amount == 1)
			assert(vfx.wheel_bursts[0].draw_pass_1.size == Vector2(3.0, 3.0))
		assert(vfx.wheel_cooldowns[index] >= float(vfx.SURFACES[surface.to_lower()].interval))
		var available: int = vfx.wheel_burst_busy.count(0.0)
		vfx.update_wheel(index, 0.0)
		assert(vfx.wheel_burst_busy.count(0.0) == available, "No extra burst before the cadence allows it")

	vfx.clear_wheel_bursts()
	sim.wheel_surfaces[index] = "Gravel"
	vfx.update_wheel(index, 1.0)
	assert(wheel_burst_texture(vfx, 0).ends_with("cr_splsh.png"))
	assert(wheel_burst_texture(vfx, 1).ends_with("water_1.png"))
	assert(vfx.wheel_burst_busy.count(0.0) == 18)
	vfx.clear_wheel_bursts()
	sim.wheel_surfaces[index] = "Grass"
	vfx.update_wheel(index, 1.0)
	assert(wheel_burst_texture(vfx, 0).ends_with("cr_splsh.png"))
	assert(wheel_burst_texture(vfx, 1).contains("leaf_"))
	assert(vfx.wheel_burst_busy.count(0.0) == 18)

	vfx.clear_wheel_bursts()
	sim.wheel_surfaces[index] = "Road"
	sim.wheel_slips[index] = Vector2.ZERO
	vfx.update_wheel(index, 0.0)
	assert(vfx.wheel_burst_busy.count(0.0) == 20)
	vfx.clear_wheel_bursts()
	vfx.update_wheel(index, 1.0)
	assert(wheel_burst_texture(vfx, 0).ends_with("rd_splsh.png"))
	vfx.clear_wheel_bursts()
	sim.last_local_conditions[index] = { "snow_mm": 1.0 }
	vfx.update_wheel(index, 1.0)
	assert(vfx.wheel_burst_busy.count(0.0) == 19)
	assert(wheel_burst_texture(vfx, 0).contains("snw_rd"))
	sim.last_local_conditions[index] = { "snow_mm": 0.0 }

	vfx.clear_wheel_bursts()
	sim.wheel_surfaces[index] = "Gravel"
	sim.wheel_slips[index] = Vector2(0.5, 0.3)
	vfx.update_wheel(index, 0.0)
	assert(vfx.wheel_bursts[1].amount == 2)
	assert(vfx.wheel_bursts[1].process_material is ShaderMaterial)
	vfx.clear_wheel_bursts()
	sim.wheel_surfaces[index] = "Dirt"
	vfx.update_wheel(index, 1.0)
	assert(vfx.wheel_bursts[0].amount == 3)
	assert(vfx.wheel_bursts[1].process_material is ParticleProcessMaterial)
	assert(wheel_burst_texture(vfx, 2).ends_with("mud_rd1.png"))
	vfx.clear_wheel_bursts()
	sim.wheel_surfaces[index] = "Gravel"
	sim.wheel_slips[index] = Vector2.ZERO
	vfx.soften_wheel_intersections = false
	vfx.update_wheel(index, 0.0)
	assert(wheel_material.get_shader_parameter("soft_intersection_metres") == 0.0)
	vfx.clear_wheel_bursts()
	vfx.soften_wheel_intersections = true
	vfx.update_wheel(index, 0.0)
	assert(wheel_material.get_shader_parameter("soft_intersection_metres") > 0.0)
	vfx.wheel_burst_busy.fill(1.0)
	vfx.wheel_cooldowns.fill(0.0)
	vfx.update_wheel(index, 1.0)
	assert(vfx.wheel_burst_busy.count(1.0) == 20, "Occupied slots must never be overwritten")
	vfx.clear_wheel_bursts()
	sim.wheel_loads[index] = 0.0
	vfx.update_wheel(index, 1.0)
	assert(vfx.wheel_burst_busy.count(0.0) == 20)
	vehicle.body_contact_vfx.clear()
	vehicle.body_contact_vfx.append({"position": Vector3.ZERO, "normal": Vector3.UP, "impulse_ns": 0.0, "speed_ms": 0.0, "tangent_ms": 0.0, "surface": "Gravel", "collider_name": "collision_road"})
	vfx.update_impacts(0.0)
	assert(vfx.emitted_impacts == 0)
	vehicle.body_contact_vfx[0].impulse_ns = vehicle.mass
	vehicle.body_contact_vfx[0].speed_ms = 4.0
	vfx.update_impacts(0.0)
	assert(vfx.emitted_impacts == 1)
	vfx.update_impacts(0.0)
	assert(vfx.emitted_impacts == 1, "Sustained contacts must respect the cooldown")
	# Hard contact in the dry: one additive spark, big at high severity.
	var spark_contact := {
		"position": Vector3.ZERO, "normal": Vector3.UP,
		"impulse_ns": vehicle.mass * 3.0, "speed_ms": 3.0, "tangent_ms": 8.0,
		"surface": "Road", "collider_name": "collision_barriers",
	}
	var spark_material := trigger_impact(vfx, spark_contact, 0.0)
	assert(spark_material != null)
	assert(spark_material.shader.resource_path.ends_with("rally_vehicle_vfx_add.gdshader"))
	var spark_texture := spark_material.get_shader_parameter("particle_texture") as Texture2D
	assert(spark_texture != null and spark_texture.resource_path.ends_with("sprk_big.png"))
	assert(
		is_equal_approx(float(spark_material.get_shader_parameter("body_exclusion_strength")), 0.0),
		"Impact sprites must not be clipped by the body box",
	)
	spark_contact.impulse_ns = vehicle.mass * 0.4
	spark_contact.speed_ms = 2.5
	var small_spark_material := trigger_impact(vfx, spark_contact, 0.0)
	var small_spark_texture := small_spark_material.get_shader_parameter("particle_texture") as Texture2D
	assert(small_spark_texture != null and small_spark_texture.resource_path.ends_with("sprk_sml.png"))
	# Mud on wet dirt and leaves on vegetation keep the alpha shader.
	var mud_contact := {
		"position": Vector3.ZERO, "normal": Vector3.UP,
		"impulse_ns": vehicle.mass * 0.5, "speed_ms": 2.2, "tangent_ms": 2.0,
		"surface": "Dirt", "collider_name": "collision_terrain_dirt",
	}
	var mud_material := trigger_impact(vfx, mud_contact, 0.8)
	var mud_texture := mud_material.get_shader_parameter("particle_texture") as Texture2D
	assert(mud_texture != null and mud_texture.resource_path.ends_with("mud_rd1.png"))
	assert(mud_material.shader.resource_path.ends_with("rally_vehicle_vfx.gdshader"))
	var leaf_contact := {
		"position": Vector3.ZERO, "normal": Vector3.UP,
		"impulse_ns": vehicle.mass * 0.5, "speed_ms": 2.0, "tangent_ms": 1.0,
		"surface": "Grass", "collider_name": "collision_tree_trunks",
	}
	var leaf_material := trigger_impact(vfx, leaf_contact, 0.0)
	var leaf_texture := leaf_material.get_shader_parameter("particle_texture") as Texture2D
	assert(leaf_texture != null and leaf_texture.resource_path.contains("leaf_"))
	assert(leaf_material.shader.resource_path.ends_with("rally_vehicle_vfx.gdshader"))
	# A wet hard contact never picks a spark.
	var wet_hard_material := trigger_impact(vfx, spark_contact, 0.9)
	var wet_hard_texture := wet_hard_material.get_shader_parameter("particle_texture") as Texture2D
	assert(wet_hard_texture != null)
	assert(not wet_hard_texture.resource_path.contains("sprk_"))
	assert(wet_hard_material.shader.resource_path.ends_with("rally_vehicle_vfx.gdshader"))
	vfx.impact_busy.fill(0.0)
	vfx.impact_cooldown = 0.0
	vfx.emitted_impacts = 0
	for i in 20:
		vfx.emit_impact(Vector3.ZERO, Vector3.UP, Color.WHITE, 0.5, true)
	assert(vfx.emitted_impacts == 6, "The pool must cap overlapping impact effects")
	vfx.reset_effects()
	print("RALLY_VFX_CONTRACT_OK real_contacts surfaces wetness skid airborne impact_cooldown pool_reset spray snow sparks mud leaves")
	scene.queue_free()
	await process_frame
	quit()


func wheel_burst_texture(vfx: RallyVehicleVFX, slot: int) -> String:
	var quad := vfx.wheel_bursts[slot].draw_pass_1 as QuadMesh
	var material := quad.material as ShaderMaterial
	return material.get_shader_parameter("particle_texture").resource_path
