extends SceneTree


func _initialize() -> void:
	call_deferred("verify")


func check_manifest() -> void:
	var base := "res://assets/vfx/cmr2/"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "manifest.json"))
	assert(str(manifest.archive_sha256).length() == 64)
	var assets: Dictionary = manifest.files
	assert(assets.has_all(["rain.png", "splat.png", "backfire_atlas.png"]) and assets.size() == 3)
	for name in assets:
		var path := base + str(name)
		var entry: Dictionary = assets[name]
		assert(FileAccess.get_sha256(path) == entry.png_sha256)
		var texture := load(path) as Texture2D
		assert(texture != null)
		assert(texture.get_size() == Vector2(entry.size[0], entry.size[1]))


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
	assert(vfx.wheel_particles.particles.size() == 400 and vfx.impact_pool.size() == 6)
	vfx.clear_wheel_bursts()
	vehicle.backfire_triggered.emit()
	var flash := active_wheel_particles(vfx)
	assert(flash.size() == 1 and flash[0].texture == vfx.BACKFIRE)
	var flash_batch: MultiMesh = vfx.wheel_particles.batches[vfx.BACKFIRE]
	var flash_material := flash_batch.mesh.surface_get_material(0) as ShaderMaterial
	assert(flash_material.get_shader_parameter("sprite_frames") == 4.0)
	vfx.clear_wheel_bursts()
	var sim = vehicle.simulation
	var index := -1
	for i in [2, 3]:
		if sim.wheel_loads[i] > 60.0 and sim.wheel_contact_casts[i].is_colliding():
			index = i
			break
	assert(index >= 0, "Real Jolt wheel casts must reach the proving ground")
	vehicle.freeze = true
	for front in [0, 1]:
		vfx.update_wheel(front, 0.0)
	assert(active_wheel_particles(vfx).is_empty(), "Front wheels skip rolling dust")
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
		var particles := active_wheel_particles(vfx)
		if surface == "Grass":
			assert(particles.size() == 2)
			assert(particles[0].texture in vfx.LEAVES)
			var foliage_pool = vfx.wheel_particles
			var profile: Dictionary = foliage_pool.TYPES[foliage_pool.Kind.LEAF]
			assert(profile.cmr2_ids == [0x10, 0x11])
			assert(profile.size.is_equal_approx(Vector2.ONE * foliage_pool.LEAF_SIZE))
			assert(profile.color.g > profile.color.b and profile.color != Color.WHITE and profile.alpha == 1.0)
			var foliage_batch: MultiMesh = foliage_pool.batches[particles[0].texture]
			var foliage_material := foliage_batch.mesh.surface_get_material(0) as ShaderMaterial
			assert(foliage_material.get_shader_parameter("opaque_sprite_mask") == true)
			assert(foliage_material.get_shader_parameter("sprite_frames") == 1.0)
			for tick in 11:
				vfx.advance_wheel_particles(0.0)
			var grass := active_wheel_particles(vfx).filter(func(p): return p.kind in [foliage_pool.Kind.GRASS, foliage_pool.Kind.GRASS_SHORT])
			assert(not grass.is_empty(), "Sustained grass contact emits the grass types")
		else:
			var burst: int = int(vfx.SURFACES[surface.to_lower()].get("burst", 0))
			assert(particles.size() == (2 + burst if surface == "Gravel" else 1 + burst), "Burst por superficie en %s" % surface)
			var pool = vfx.wheel_particles
			if surface == "Gravel":
				for particle in particles.slice(0, 1):
					assert(particle.kind == pool.Kind.GRAVEL_SPRAY and particle.texture in vfx.SNOW_ROLL)
				for particle in particles.slice(1):
					assert(particle.kind == pool.Kind.DUST and particle.texture == vfx.GRAVEL_DUST)
			else:
				var dust = particles[0]
				assert(dust.texture == vfx.DUST_CORE)
				assert(dust.kind == vfx.SURFACES[surface.to_lower()].dust_kind)
				assert(pool.TYPES[dust.kind].color != Color.WHITE)
				var frame: int = pool.dust_frame(dust)
				pool.step(Vector3.ZERO)
				assert(pool.dust_frame(dust) == frame)
				pool.step(Vector3.ZERO)
				assert(pool.dust_frame(dust) == (frame + 1) % 8)
		var emitted := active_wheel_particles(vfx).size()
		vfx.update_wheel(index, 0.0)
		assert(active_wheel_particles(vfx).size() == emitted, "Wheel emission respects its tick countdown")

	vfx.clear_wheel_bursts()
	sim.wheel_surfaces[index] = "Gravel"
	vfx.update_wheel(index, 1.0)
	var wet := active_wheel_particles(vfx)
	assert(wet.size() == 5)
	for i in 4:
		assert(wet[i].texture == vfx.SPLASH_LOOSE)
	assert(wet[4].texture == vfx.WATER_CORE)
	assert(wet[0].ticks != wet[4].ticks, "Splashes and water have separate lifetimes")
	vfx.clear_wheel_bursts()
	sim.wheel_surfaces[index] = "Road"
	sim.wheel_slips[index] = Vector2.ZERO
	vfx.update_wheel(index, 0.0)
	assert(active_wheel_particles(vfx).is_empty())
	vfx.clear_wheel_bursts()
	sim.last_local_conditions[index] = { "snow_mm": 1.0 }
	vfx.update_wheel(index, 1.0)
	assert(active_wheel_particles(vfx).size() == 1)
	sim.last_local_conditions[index] = { "snow_mm": 0.0 }

	vfx.clear_wheel_bursts()
	sim.wheel_surfaces[index] = "Gravel"
	sim.wheel_slips[index] = Vector2(0.5, 0.3)
	vfx.update_wheel(index, 0.0)
	var pool = vfx.wheel_particles
	var normal_spray := active_wheel_particles(vfx)
	assert(normal_spray.size() == 5 and normal_spray[0].kind == pool.Kind.GRAVEL_SPRAY)
	var tire: Dictionary = sim.thermal_model.tire_states[index]
	tire.pressure_loss_fraction = 1.0
	tire.carcass_failure = 0.99
	vfx.clear_wheel_bursts()
	vfx.update_wheel(index, 0.0)
	assert(active_wheel_particles(vfx)[0].kind == pool.Kind.GRAVEL_SPRAY)
	tire.carcass_failure = 1.0
	for iteration in 2:
		vfx.clear_wheel_bursts()
		sim.last_local_conditions[index] = {"snow_mm": 1.0}
		vfx.update_wheel(index, 1.0)
		var spray := active_wheel_particles(vfx)
		assert(spray.size() == 6, "Unseated tire emits balanced sparks")
		assert(spray.filter(func(p): return p.kind == pool.Kind.BEAD_YELLOW).size() == 3)
		assert(spray.filter(func(p): return p.kind == pool.Kind.BEAD_ORANGE).size() == 3)
		for particle in spray:
			assert(particle.texture == vfx.SMALL_SPARK and particle.ticks == 18)
		assert(pool.batches[vfx.SMALL_SPARK].mesh.surface_get_material(0).shader == vfx.ADDITIVE_SHADER)
	tire.carcass_failure = 0.0
	tire.pressure_loss_fraction = 0.0
	sim.last_local_conditions[index] = {"snow_mm": 0.0}
	for i in 405:
		pool.emit_particle(pool.Kind.ROCK, vfx.GRAVEL[0], contact_point, Vector3.ZERO, contact_point, Vector3.UP)
	assert(active_wheel_particles(vfx).size() == 400, "Capacity is shared and bounded")
	vfx.clear_wheel_bursts()
	sim.wheel_loads[index] = 0.0
	vfx.update_wheel(index, 1.0)
	assert(active_wheel_particles(vfx).is_empty())
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
	assert(spark_texture == vfx.SPARK)
	assert(
		is_equal_approx(float(spark_material.get_shader_parameter("body_exclusion_strength")), 0.0),
		"Impact sprites must not be clipped by the body box",
	)
	spark_contact.impulse_ns = vehicle.mass * 0.4
	spark_contact.speed_ms = 2.5
	var small_spark_material := trigger_impact(vfx, spark_contact, 0.0)
	var small_spark_texture := small_spark_material.get_shader_parameter("particle_texture") as Texture2D
	assert(small_spark_texture == vfx.SMALL_SPARK)
	# Mud on wet dirt and leaves on vegetation keep the alpha shader.
	var mud_contact := {
		"position": Vector3.ZERO, "normal": Vector3.UP,
		"impulse_ns": vehicle.mass * 0.5, "speed_ms": 2.2, "tangent_ms": 2.0,
		"surface": "Dirt", "collider_name": "collision_terrain_dirt",
	}
	var mud_material := trigger_impact(vfx, mud_contact, 0.8)
	var mud_texture := mud_material.get_shader_parameter("particle_texture") as Texture2D
	assert(mud_texture == vfx.MUD_CLOD)
	assert(mud_material.shader.resource_path.ends_with("rally_vehicle_vfx.gdshader"))
	var leaf_contact := {
		"position": Vector3.ZERO, "normal": Vector3.UP,
		"impulse_ns": vehicle.mass * 0.5, "speed_ms": 2.0, "tangent_ms": 1.0,
		"surface": "Grass", "collider_name": "collision_tree_trunks",
	}
	var leaf_material := trigger_impact(vfx, leaf_contact, 0.0)
	var leaf_texture := leaf_material.get_shader_parameter("particle_texture") as Texture2D
	assert(leaf_texture in vfx.LEAVES)
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

	# Rain splat and windshield weather verification
	vfx.clear_wheel_bursts()
	vfx.rain_splat_ticks = 0
	sim.last_local_conditions[2] = {"climate": {"precipitation_mm_h": 10.0}, "precipitation_kind": "rain"}
	vfx._update_rain_splats(sim.last_local_conditions[2].climate)
	var splats: Array = vfx.wheel_particles.particles.filter(func(p): return p.ticks > 0 and p.kind == vfx.WHEEL_PARTICLES.Kind.RAIN_SPLAT)
	assert(splats.size() >= 1, "Rain splats must emit on precipitation")
	var splat_batch: MultiMesh = vfx.wheel_particles.batches[vfx.RAIN_SPLAT]
	var splat_material := splat_batch.mesh.surface_get_material(0) as ShaderMaterial
	assert(
		is_equal_approx(float(splat_material.get_shader_parameter("body_exclusion_strength")), 0.0),
		"Rain splat sprites must not be clipped by the body box",
	)
	var vis: Node = vehicle.get_node_or_null("VisualDamage")
	assert(vis != null and vis._windshield_rain_material != null, "Windshield rain shader must be initialized")
	assert(is_equal_approx(float(vis._windshield_rain_material.get_shader_parameter("rain_intensity")), clampf(10.0 / 12.0, 0.0, 1.0)))
	# Unloading wheel 2 over a bump must not reset windshield rain intensity to zero
	sim.last_local_conditions[2] = {}
	vfx._update_rain_splats({})
	assert(
		is_equal_approx(float(vis._windshield_rain_material.get_shader_parameter("rain_intensity")), clampf(10.0 / 12.0, 0.0, 1.0)),
		"Windshield rain must not flicker off when wheel 2 unloads momentarily",
	)
	vis._process(0.05)
	assert(float(vis._windshield_rain_material.get_shader_parameter("rain_scroll")) > 0.0, "Windshield rain scroll phase must advance smoothly")

	vfx.reset_effects()
	print("RALLY_VFX_CONTRACT_OK real_contacts surfaces wetness skid airborne impact_cooldown pool_reset spray snow sparks mud leaves rain_splats windshield")
	scene.queue_free()
	await process_frame
	quit()


func active_wheel_particles(vfx: RallyVehicleVFX) -> Array:
	return vfx.wheel_particles.particles.filter(func(p): return p.ticks > 0)
