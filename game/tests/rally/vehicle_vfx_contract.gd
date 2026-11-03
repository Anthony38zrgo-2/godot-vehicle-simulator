extends SceneTree


func _initialize() -> void:
	call_deferred("verify")


func check_manifest() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/cmr4/manifest.json"))
	assert(parsed is Dictionary, "CMR4 manifest must parse")
	var manifest: Dictionary = parsed
	var assets: Dictionary = manifest.get("assets", {})
	assert(assets.size() == 20, "CMR4 manifest must list the 20 sprites")
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
	assert(vfx.wheel_plumes.size() == 4 and vfx.impact_pool.size() == 6)
	assert(
		vfx.wheel_splash.size() == 4 and vfx.wheel_water.size() == 4
		and vfx.wheel_mist.size() == 4 and vfx.wheel_snow.size() == 4
	)
	var wheel_quad := vfx.wheel_plumes[2].draw_pass_1 as QuadMesh
	var wheel_material := wheel_quad.material as ShaderMaterial
	assert(
		is_equal_approx(float(wheel_material.get_shader_parameter("body_exclusion_strength")), 1.0),
		"Wheel particles must be clipped inside the cabin",
	)
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
		assert(not vfx.wheel_cores[front].emitting)
		assert(not vfx.wheel_plumes[front].emitting)
		assert(not vfx.wheel_chips[front].emitting)
		assert(not vfx.wheel_splash[front].emitting)
		assert(not vfx.wheel_water[front].emitting)
		assert(not vfx.wheel_mist[front].emitting)
		assert(not vfx.wheel_snow[front].emitting)
	vehicle.linear_velocity = Vector3(0, 0, -15)
	sim.wheel_slips[index] = Vector2(0.3, 0.15)
	for surface in ["Gravel", "Dirt", "Sand", "Grass"]:
		sim.wheel_surfaces[index] = surface
		sim.last_local_conditions[index] = { "snow_mm": 0.0 }
		vfx.update_wheel(index, 0.0)
		assert(vfx.wheel_plumes[index].emitting)
		assert(vfx.wheel_chips[index].emitting)
		assert(not vfx.wheel_splash[index].emitting)
		assert(not vfx.wheel_water[index].emitting)
		assert(not vfx.wheel_mist[index].emitting)
		assert(not vfx.wheel_snow[index].emitting)
	sim.wheel_surfaces[index] = "Gravel"
	sim.last_local_conditions[index] = { "snow_mm": 0.0 }
	vfx.update_wheel(index, 0.0)
	var dry: float = vfx.wheel_plumes[index].amount_ratio
	vfx.update_wheel(index, 1.0)
	assert(vfx.wheel_splash[index].emitting)
	assert(vfx.wheel_water[index].emitting)
	assert(vfx.wheel_mist[index].emitting)
	assert(not vfx.wheel_snow[index].emitting)
	assert(vfx.wheel_plumes[index].amount_ratio < dry * 0.2)
	var wet_trail: float = vfx.wheel_water[index].amount_ratio
	vfx.update_wheel(index, 0.25)
	assert(
		vfx.wheel_water[index].amount_ratio < wet_trail * 0.5,
		"Spray must scale with wetness",
	)
	# The contact splash uses a different source sprite for paved and loose ground.
	vfx.update_wheel(index, 1.0)
	var splash_quad := vfx.wheel_splash[index].draw_pass_1 as QuadMesh
	var splash_material := splash_quad.material as ShaderMaterial
	var loose_texture := splash_material.get_shader_parameter("particle_texture") as Texture2D
	assert(loose_texture != null and loose_texture.resource_path.ends_with("cr_splsh.png"))
	sim.wheel_surfaces[index] = "Road"
	sim.wheel_slips[index] = Vector2.ZERO
	vfx.update_wheel(index, 1.0)
	var paved_texture := splash_material.get_shader_parameter("particle_texture") as Texture2D
	assert(paved_texture != null and paved_texture.resource_path.ends_with("rd_splsh.png"))
	assert(not vfx.wheel_plumes[index].emitting and not vfx.wheel_chips[index].emitting)
	sim.wheel_loads[index] = 0.0
	vfx.update_wheel(index, 1.0)
	assert(not vfx.wheel_splash[index].emitting, "Spray must stop when the wheel is unloaded")
	assert(not vfx.wheel_water[index].emitting)
	assert(not vfx.wheel_mist[index].emitting)
	sim.wheel_loads[index] = 4000.0
	vehicle.linear_velocity = Vector3.ZERO
	sim.wheel_spins[index] = 0.0
	sim.wheel_slips[index] = Vector2.ZERO
	sim.wheel_surfaces[index] = "Gravel"
	vfx.update_wheel(index, 1.0)
	assert(not vfx.wheel_water[index].emitting, "A stationary wheel must not spray")
	# Snow on the ground replaces dust, smoke and water in the same update.
	vehicle.linear_velocity = Vector3(0, 0, -15)
	sim.wheel_slips[index] = Vector2(0.3, 0.15)
	sim.last_local_conditions[index] = { "snow_mm": 6.0 }
	vfx.update_wheel(index, 1.0)
	assert(vfx.wheel_snow[index].emitting, "Snow on the ground must lift snow")
	var snow_quad := vfx.wheel_snow[index].draw_pass_1 as QuadMesh
	var snow_material := snow_quad.material as ShaderMaterial
	var snow_texture := snow_material.get_shader_parameter("particle_texture") as Texture2D
	assert(snow_texture != null and snow_texture.resource_path.contains("snw_rd"))
	assert(not vfx.wheel_cores[index].emitting)
	assert(not vfx.wheel_plumes[index].emitting)
	assert(not vfx.wheel_chips[index].emitting)
	assert(not vfx.wheel_splash[index].emitting)
	assert(not vfx.wheel_water[index].emitting)
	assert(not vfx.wheel_mist[index].emitting)
	sim.last_local_conditions[index] = { "snow_mm": 0.0 }
	vfx.update_wheel(index, 0.0)
	assert(not vfx.wheel_snow[index].emitting)
	# Wheel chips follow the contact material.
	sim.wheel_surfaces[index] = "Grass"
	sim.wheel_slips[index] = Vector2(0.3, 0.15)
	vfx.update_wheel(index, 0.0)
	var chips_quad := vfx.wheel_chips[index].draw_pass_1 as QuadMesh
	var chips_material := chips_quad.material as ShaderMaterial
	var grass_chips := chips_material.get_shader_parameter("particle_texture") as Texture2D
	assert(grass_chips != null and grass_chips.resource_path.contains("leaf_"))
	sim.wheel_surfaces[index] = "Dirt"
	vfx.update_wheel(index, 1.0)
	var mud_chips := chips_material.get_shader_parameter("particle_texture") as Texture2D
	assert(mud_chips != null and mud_chips.resource_path.ends_with("mud_rd1.png"))
	sim.wheel_surfaces[index] = "Gravel"
	vfx.update_wheel(index, 0.0)
	var gravel_chips := chips_material.get_shader_parameter("particle_texture") as Texture2D
	assert(gravel_chips != null and gravel_chips.resource_path.ends_with("dirt_02_a.png"))
	sim.wheel_surfaces[index] = "Road"
	sim.wheel_slips[index] = Vector2.ZERO
	vfx.update_wheel(index, 0.0)
	assert(not vfx.wheel_plumes[index].emitting and not vfx.wheel_chips[index].emitting)
	sim.wheel_slips[index] = Vector2(0.5, 0.2)
	vfx.update_wheel(index, 0.0)
	assert(vfx.wheel_plumes[index].emitting)
	sim.wheel_loads[index] = 0.0
	vfx.update_wheel(index, 0.0)
	assert(not vfx.wheel_plumes[index].emitting and not vfx.wheel_chips[index].emitting)
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
	assert(not vfx.wheel_plumes[index].emitting)
	assert(not vfx.wheel_splash[index].emitting)
	assert(not vfx.wheel_water[index].emitting)
	assert(not vfx.wheel_mist[index].emitting)
	assert(not vfx.wheel_snow[index].emitting)
	print("RALLY_VFX_CONTRACT_OK real_contacts surfaces wetness skid airborne impact_cooldown pool_reset spray snow sparks mud leaves")
	scene.queue_free()
	await process_frame
	quit()
