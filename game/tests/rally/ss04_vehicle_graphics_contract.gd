extends SceneTree

const CollisionBuilder = preload("res://scripts/rally/rally_track_collision_builder.gd")
const TireModel = preload("res://scripts/physics/tire_model.gd")
const Controller = preload("res://scripts/rally/rally_weather_controller.gd")
const SectorStream = preload("res://scripts/rally/rally_visual_sector_stream.gd")
const TireTracks = preload("res://scripts/rally/rally_tire_tracks.gd")
const RallyTireCompoundScript = preload("res://scripts/rally/rally_tire_compound.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("SS04_C_FAIL: " + label)


func _initialize() -> void:
	call_deferred("run")


var _domains: Dictionary = {}
var _filters: Dictionary = {}


func _make_tire(compound_id: String) -> TireModel:
	if _domains.is_empty():
		var loader := VehicleProfileLoader.load_profile("res://data/vehicles/ford-escort-rs2000/vehicle.json")
		_domains = loader.domains.duplicate(true)
		_filters = loader.resolved_tire_filters.duplicate(true)
	var t := TireModel.new()
	t.configure(_domains, _filters, [3500.0, 3500.0, 3500.0, 3500.0])
	t.set_compound(compound_id)
	return t


func _peak_braking_and_lateral(
	tire: TireModel,
	water_mm: float,
	snow_mm: float,
	ground_c: float,
	snow_cov: float,
	ice_cov: float,
	ice_mm: float = 0.0,
) -> Dictionary:
	# Evaluate steady braking slip and cornering slip separately on Road (asphalt).
	var cid := str(tire.active_compound_id)
	var t_brake := _make_tire(cid)
	var r_brake: Dictionary = {}
	for _i in 30:
		r_brake = t_brake.evaluate(
			0, 3500.0, "Road", 20.0, 0.0, 42.0, 0.31, 0.0, 1.0, 200.0, 0.01, 60.0,
			water_mm, snow_mm, ground_c, "", ice_mm, snow_cov, ice_cov
		)
	var t_corner := _make_tire(cid)
	var r_corner: Dictionary = {}
	for _i in 30:
		r_corner = t_corner.evaluate(
			0, 3500.0, "Road", 20.0, 3.2, 64.5, 0.31, 0.0, 1.0, 200.0, 0.01, 60.0,
			water_mm, snow_mm, ground_c, "", ice_mm, snow_cov, ice_cov
		)
	return {
		"fx_brake": absf(float(r_brake.get("longitudinal_force_n", 0.0))),
		"fy_corner": absf(float(r_corner.get("lateral_force_n", 0.0))),
		"mu_eff": float(t_brake.states[0].get("compound_mult", 0.0)),
	}


func _verify_tire_blending() -> void:
	var dry_tire := _make_tire("asphalt_dry")
	var wet_tire := _make_tire("asphalt_wet")
	var stud_tire := _make_tire("snow_studded")

	# Dry exposed Road vs Wet vs Thin snow (~0.34 coverage) vs Full snow vs Ice.
	var res_dry := _peak_braking_and_lateral(dry_tire, 0.0, 0.0, 2.0, 0.0, 0.0)
	var res_wet := _peak_braking_and_lateral(dry_tire, 1.5, 0.0, 2.0, 0.0, 0.0)
	var res_thin := _peak_braking_and_lateral(dry_tire, 0.0, 0.6, 2.0, 0.34, 0.0)
	var res_full_snow := _peak_braking_and_lateral(dry_tire, 0.0, 1.8, -1.0, 1.0, 0.0)
	var res_ice := _peak_braking_and_lateral(dry_tire, 0.0, 0.0, -3.0, 0.0, 1.0, 0.8)

	var brake_ratio := float(res_thin["fx_brake"]) / maxf(float(res_dry["fx_brake"]), 1.0)
	var corner_ratio := float(res_thin["fy_corner"]) / maxf(float(res_dry["fy_corner"]), 1.0)
	print("SS04_C_TIRE thin_brake_ratio=%.3f thin_corner_ratio=%.3f full_snow=%.3f ice=%.3f" % [
		brake_ratio,
		corner_ratio,
		float(res_full_snow["fx_brake"]) / maxf(float(res_dry["fx_brake"]), 1.0),
		float(res_ice["fx_brake"]) / maxf(float(res_dry["fx_brake"]), 1.0),
	])
	check(absf(brake_ratio - 0.80) <= 0.05, "Thin snow braking grip near 0.80 dry (got %.3f)" % brake_ratio)
	check(absf(corner_ratio - 0.80) <= 0.05, "Thin snow cornering grip near 0.80 dry (got %.3f)" % corner_ratio)
	check(float(res_dry["fx_brake"]) > float(res_thin["fx_brake"]), "Dry > Thin snow braking")
	check(float(res_thin["fx_brake"]) > float(res_full_snow["fx_brake"]), "Thin snow > Full snow braking")
	check(float(res_full_snow["fx_brake"]) > float(res_ice["fx_brake"]), "Full snow > Ice braking")
	check(float(res_dry["fy_corner"]) > float(res_wet["fy_corner"]), "Dry > Wet cornering")

	# Check zero double-penalization: changing snow_mm between 0.5 and 1.5 at fixed coverage=1.0
	# stays governed by snow_packed_grip_scale without applying snow_grip_loss_per_mm twice.
	var packed_a := _peak_braking_and_lateral(dry_tire, 0.0, 0.5, 1.0, 1.0, 0.0)
	var packed_b := _peak_braking_and_lateral(dry_tire, 0.0, 1.8, 1.0, 1.0, 0.0)
	check(absf(float(packed_a["mu_eff"]) - float(packed_b["mu_eff"])) < 0.001, "Snow not double-penalized at full coverage")

	# Compound dependence: studded beats dry on snow/ice, dry beats studded on exposed tarmac.
	var stud_dry := _peak_braking_and_lateral(stud_tire, 0.0, 0.0, 2.0, 0.0, 0.0)
	var stud_ice := _peak_braking_and_lateral(stud_tire, 0.0, 0.0, -3.0, 0.0, 1.0, 0.8)
	var wet_wet := _peak_braking_and_lateral(wet_tire, 2.0, 0.0, 2.0, 0.0, 0.0)
	check(float(res_dry["mu_eff"]) > float(stud_dry["mu_eff"]), "Asphalt dry > studded on exposed road")
	check(float(stud_ice["mu_eff"]) > float(res_ice["mu_eff"]), "Studded > asphalt dry on ice")
	check(float(wet_wet["mu_eff"]) > float(res_wet["mu_eff"]), "Asphalt wet beats dry on wet surface")


func _verify_shader_and_tracks() -> void:
	var ctl := Controller.new()
	var ok := ctl.configure_procedural(
		"cdi_stage4",
		"res://data/rally/cdi_stage4_route.json",
		1974,
		"transition",
		9.6667,
		"asphalt",
		"dry"
	)
	check(ok, "Dry procedural config succeeds")
	var pkt := ctl.surface_field_packet()
	check(bool(pkt.get("ok", false)), "Surface field packet ok")
	var stream := SectorStream.new()
	check(stream.load_cdi_asphalt(-1.0, true), "load_cdi_asphalt succeeds in procedural mode with berm snow")
	stream.sync_procedural_surface(pkt)
	check(stream.is_procedural_surface_enabled(), "SectorStream switched to procedural surface")
	var mat := stream._asphalt_material
	check(mat != null, "Asphalt material created")
	if mat != null:
		check(bool(mat.get_shader_parameter("procedural_surface_enabled")), "Shader procedural_surface_enabled active")
		check(float(mat.get_shader_parameter("snow_station_m")) < 0.0, "Legacy snow_station_m disabled")
		check(mat.get_shader_parameter("surface_field_tex") != null, "Shader surface_field_tex bound")
	check(stream._ticlio_snow_textures != null, "Berm snow textures kept loaded for roadside coherence")

	# Track marks per wheel patch vs exposed wet tarmac vs ice.
	var tracks := TireTracks.new()
	check(tracks.variant_for("road", 0.0, 0, "", 0.0, 0.0) == 0, "Dry/wet exposed road uses asphalt track")
	check(tracks.variant_for("road", 0.0, 0, "", 0.35, 0.0) == 2, "Snowy patch uses snow track")
	check(tracks.variant_for("road", 0.0, 0, "", 0.0, 0.40) == 4, "Icy patch uses ice scratch track")
	tracks.free()
	stream.free()


func _verify_ss04_session() -> void:
	var packed := load("res://scenes/rally/cdi_stage4.tscn") as PackedScene
	check(packed != null, "cdi_stage4 scene loads")
	if packed == null:
		return
	var session := packed.instantiate() as RallyRussiaStageSession
	session.track_id = "cdi_stage4"
	session.session_mode = "single_stage"
	session.practice_mode = false
	session.event_seed = 4242
	session.procedural_climate_override = 1
	root.add_child(session)
	var wait_frames := 0
	while not session.session_ready and wait_frames < 240:
		await physics_frame
		wait_frames += 1
	check(session.session_ready, "SS04 session ready in procedural mode (waited %d frames)" % wait_frames)
	check(session.event_weather.procedural_active, "Session event_weather in procedural mode")
	check(session.track_collision.procedural_ss04_asphalt_mode, "Session track_collision stripped SS04 road_snow_cdi")
	var stream := session.track_visual.get_node_or_null("VisualSectorStream") as SectorStream
	check(stream != null and stream.is_procedural_surface_enabled(), "Session VisualSectorStream in procedural surface mode")
	var road_bodies := get_nodes_in_group("Road")
	var road_snow_packed_count := 0
	for b in road_bodies:
		if str(b.get_meta("winter_layer_id", "")) == "snow_packed":
			road_snow_packed_count += 1
	check(not road_bodies.is_empty(), "SS04 procedural has Road group bodies")
	check(road_snow_packed_count == 0, "SS04 procedural Road has zero snow_packed bodies (got %d)" % road_snow_packed_count)

	# Verify non-SS04 snow stages (Sweden) still classify road_snow_* as snow_packed even if flag enabled.
	var sweden_path := "res://assets/rally/sweden_stage1/sweden_stage1_collision.glb"
	if ResourceLoader.exists(sweden_path):
		var sw_builder := CollisionBuilder.new()
		sw_builder.procedural_ss04_asphalt_mode = true
		sw_builder.collision_scene_path = sweden_path
		sw_builder.terrain_surface_group = "Gravel"
		root.add_child(sw_builder)
		check(sw_builder.build_collision(), "Sweden collision builds")
		var sw_snow := false
		for ch in sw_builder.get_children():
			if str(ch.get_meta("winter_layer_id", "")) == "snow_packed":
				sw_snow = true
				break
		check(sw_snow, "Sweden preserves snow_packed physical layer")
		sw_builder.queue_free()

	# Advance physics a few frames and verify wheel local_conditions carry procedural fields.
	session.vehicle.freeze = false
	for _i in 4:
		await physics_frame
	var local0 := session.vehicle.simulation._local_conditions_at_contact("Road", session.vehicle.global_position, true)
	check(local0.has("snow_coverage") and float(local0["snow_coverage"]) >= 0.0, "Single contact carries snow_coverage")
	check(local0.has("ice_coverage") and float(local0["ice_coverage"]) >= 0.0, "Single contact carries ice_coverage")

	session.queue_free()
	await process_frame
	await process_frame


func run() -> void:
	_verify_tire_blending()
	_verify_shader_and_tracks()
	await _verify_ss04_session()
	print("SS04_VEHICLE_GRAPHICS_CONTRACT ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
