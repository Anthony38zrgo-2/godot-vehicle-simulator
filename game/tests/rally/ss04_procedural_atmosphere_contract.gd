extends SceneTree

const StageLoader = preload("res://scripts/rally/rally_stage_loader.gd")
const Scheduler = preload("res://scripts/rally/rally_weather_scheduler.gd")
const Controller = preload("res://scripts/rally/rally_weather_controller.gd")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var loader := StageLoader.new()
	var resolved := loader.resolve("cdi_stage4")
	check(not resolved.is_empty(), "cdi_stage4 resolves cleanly: " + loader.error)
	if resolved.is_empty():
		quit(1)
		return

	var manifest: Dictionary = resolved.get("manifest", {})
	var stage_cfg: Dictionary = resolved.get("stage_config", {})
	check(str(manifest.get("climate_route_profile", "")) == "climate_route_profile.json", "manifest references climate_route_profile.json")
	var proc_cfg: Dictionary = stage_cfg.get("procedural_climate", {})
	check(not proc_cfg.is_empty(), "cdi_stage4.json declares procedural_climate")
	check(bool(proc_cfg.get("enabled", false)), "Entrega D enables procedural_climate by default in SS04")

	# Verify geography and station correspondence against cdi_stage4_route.json and manifest.
	var route_profile_text := FileAccess.get_file_as_string("res://assets/rally/cdi_stage4/climate_route_profile.json")
	var route_profile: Variant = JSON.parse_string(route_profile_text)
	check(route_profile is Dictionary, "climate_route_profile.json parses")
	var rp := route_profile as Dictionary
	var geo: Dictionary = rp.get("geography", {})
	check(str(geo.get("crs", "")) == "EPSG:32718", "CRS documented as EPSG:32718")
	check(bool(geo.get("vertical_datum_verified", false)), "vertical datum verified")
	check(absf(float(geo.get("start_altitude_m", 0.0)) - 4517.2) < 0.5, "start altitude ~4517.2 m")
	check(absf(float(geo.get("finish_altitude_m", 0.0)) - 4808.6) < 0.5, "finish altitude ~4808.6 m")

	var route_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/rally/cdi_stage4_route.json"))
	check(route_doc is Dictionary, "cdi_stage4_route.json parses")
	var total_route_m := float((route_doc as Dictionary).get("total_route_length_m", 0.0))
	var corr: Dictionary = rp.get("station_correspondence", {})
	check(absf(float(corr.get("timed_finish_progress_m", 0.0)) - total_route_m) < 0.05, "finish progress matches route.json length")
	check(float(corr.get("max_piecewise_linear_residual_m", 99.0)) < 0.5, "station correspondence residual < 0.5 m")

	# Build precomputed atmosphere table via Scheduler & Controller.
	var built1 := Scheduler.build_procedural_atmosphere_for_stage("cdi_stage4", 2026, "2026-11-18", 9.6667)
	check(bool(built1.get("ok", false)), "Scheduler builds Rust procedural atmosphere: " + str(built1.get("error", "")))
	if not bool(built1.get("ok", false)):
		quit(1)
		return

	var built2 := Scheduler.build_procedural_atmosphere_for_stage("cdi_stage4", 2026, "2026-11-18", 9.6667)
	var eng1 := built1["engine"] as RefCounted
	var eng2 := built2["engine"] as RefCounted
	var s1: Dictionary = eng1.call("sample_atmosphere_at", 3100.0, 180.0)
	var s2: Dictionary = eng2.call("sample_atmosphere_at", 3100.0, 180.0)
	check(is_equal_approx(float(s1.get("air_c", 0.0)), float(s2.get("air_c", -999.0))), "deterministic air_c for same seed/date/hour")
	check(is_equal_approx(float(s1.get("precip_total_mm_h", -1.0)), float(s2.get("precip_total_mm_h", -2.0))), "deterministic precip for same seed/date/hour")

	# Verify verified station correspondence at manifest snow reference (~3162.035 m shader station -> ~3098.64 m controller progress).
	var manifest_snow_stat := float((manifest.get("source", {}) as Dictionary).get("snow_road_station_m", 3162.035))
	var mapped_prog := float(eng1.call("shader_station_to_progress", manifest_snow_stat))
	var roundtrip_stat := float(eng1.call("progress_to_shader_station", mapped_prog))
	check(absf(roundtrip_stat - manifest_snow_stat) < 0.05, "shader_station -> progress -> shader_station round-trip exact (got %.3f vs %.3f)" % [roundtrip_stat, manifest_snow_stat])
	check(absf(mapped_prog - 3098.64) < 0.5, "manifest snow shader station maps to controller route progress ~3098.64 m (got %.3f)" % mapped_prog)

	# Verify dry regime keeps zero precipitation even at the abra and cools with altitude.
	var ctl := Controller.new()
	var dry_res := ctl.configure_procedural_atmosphere("cdi_stage4", 42, "dry", 10.0, "dry")
	check(bool(dry_res.get("ok", false)), "Controller configures dry procedural atmosphere")
	var start_dry := ctl.sample_procedural_atmosphere(0.0, 300.0)
	var abra_dry := ctl.sample_procedural_atmosphere(total_route_m, 300.0)
	check(float(abra_dry.get("precip_total_mm_h", -1.0)) == 0.0, "Dry regime gives 0 mm/h at abra")
	check(float(abra_dry.get("air_c", 99.0)) < float(start_dry.get("air_c", -99.0)) - 1.5, "Abra is >1.5C cooler than start under equal conditions")
	check(absf(ctl.progress_to_shader_station(0.0) - 62.0125) < 0.05, "Controller maps start progress 0 -> shader 62.0125")

	# Verify wet-front regime and horizon extension continuity.
	var wet_res := ctl.configure_procedural_atmosphere("cdi_stage4", 99, "transition", 9.6667, "wet_front")
	check(bool(wet_res.get("ok", false)), "Controller configures wet_front procedural atmosphere")
	var start_wet := ctl.sample_procedural_atmosphere(0.0, 0.0)
	check(float(start_wet.get("precip_total_mm_h", 0.0)) >= 0.4, "Selected wet front precipitates at the starting line at race time zero")
	var mid_wet := ctl.sample_procedural_atmosphere(total_route_m * 0.5, 300.0)
	var abra_wet := ctl.sample_procedural_atmosphere(total_route_m, 300.0)
	check(float(mid_wet.get("precip_total_mm_h", 0.0)) > 0.1 or float(abra_wet.get("precip_total_mm_h", 0.0)) > 0.1, "Wet front produces precipitation")
	ctl.procedural_atmosphere.call("extend_horizon_to", 7200.0)
	var ext := ctl.sample_procedural_atmosphere(3100.0, 6000.0)
	check(bool(ext.get("ok", false)) and is_finite(float(ext.get("air_c", NAN))), "Extended horizon sample valid")

	print("SS04_PROCEDURAL_ATMOSPHERE_CONTRACT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
