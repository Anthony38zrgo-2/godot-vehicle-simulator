import pathlib
# --- brake_model.gd ---
p = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\scripts\physics\brake_model.gd")
t = p.read_text(encoding="utf-8")
old = "var pedal_exponent: float = 1.32"
new = """# P1 1974: servo assist + manual proportioning valve (Stratos: no servo).
var servo_assist_enabled: bool = True
var servo_gain: float = 1.0
var manual_proportioning: bool = False
var front_disc_diameter_m: float = 0.0
var rear_disc_diameter_m: float = 0.0
var pedal_exponent: float = 1.32"""
assert old in t
t = t.replace(old, new, 1)
old2 = "\tpedal_exponent = clampf(float(brakes.get(\"pedal_exponent\", 1.32)), 1.0, 2.2)"
new2 = """\tvar servo_doc: Dictionary = brakes.get("servo_assist", {})
\tservo_assist_enabled = bool(servo_doc.get("enabled", brakes.get("servo_assisted", True)))
\tservo_gain = clampf(float(servo_doc.get("gain", brakes.get("servo_gain", 1.0))), 0.3, 1.6)
\tif not servo_assist_enabled and not brakes.has("servo_gain") and not servo_doc.has("gain"):
\t\tservo_gain = 0.82
\tmanual_proportioning = bool(brakes.get("manual_proportioning", brakes.get("manual_bias_valve", False)))
\tfront_disc_diameter_m = maxf(float(brakes.get("front_disc_diameter_m", 0.0)), 0.0)
\trear_disc_diameter_m = maxf(float(brakes.get("rear_disc_diameter_m", 0.0)), 0.0)
\tpedal_exponent = clampf(float(brakes.get("pedal_exponent", 1.32)), 1.0, 2.2)"""
assert old2 in t
t = t.replace(old2, new2, 1)
old3 = "\tvar target_service := pow(clampf(brake_input, 0.0, 1.0), pedal_exponent)"
new3 = "\tvar target_service := pow(clampf(brake_input, 0.0, 1.0), pedal_exponent) * servo_gain"
assert old3 in t
t = t.replace(old3, new3, 1)
p.write_text(t, encoding="utf-8")
print("brake patched OK")

# --- vehicle_simulation.gd ---
q = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\scripts\physics\vehicle_simulation.gd")
s = q.read_text(encoding="utf-8")
old = "var maximum_steering_angle_rad: float = 0.5585053606381855"
new = """var maximum_steering_angle_rad: float = 0.5585053606381855
# P1 1974 documentary steering metadata (turns lock-to-lock + rack ratio).
var steering_turns_lock_to_lock: float = 0.0
var steering_ratio_to_one: float = 0.0"""
assert old in s
s = s.replace(old, new, 1)
old2 = "\tmaximum_steering_angle_rad = float(\n\t\tsteering.get(\"max_steering_angle\", maximum_steering_angle_rad)\n\t)"
new2 = """\tmaximum_steering_angle_rad = float(
\t\tsteering.get("max_steering_angle", maximum_steering_angle_rad)
\t)
\tsteering_turns_lock_to_lock = float(steering.get("turns_lock_to_lock", steering.get("turns", 0.0)))
\tsteering_ratio_to_one = float(steering.get("ratio_to_one", steering.get("ratio", 0.0)))"""
assert old2 in s
s = s.replace(old2, new2, 1)
# apply_setup_values: refresh new powertrain/brake/steering fields live
old3 = "\tpowertrain_model.final_drive_ratio = float(\n\t\tpowertrain.get(\"final_drive\", powertrain_model.final_drive_ratio)\n\t)"
new3 = """\tpowertrain_model.primary_reduction_ratio = maxf(float(powertrain.get("primary_reduction", (powertrain.get("drop_gears", {}) as Dictionary).get("ratio", powertrain_model.primary_reduction_ratio))), 0.2)
\tpowertrain_model.final_drive_gravel = float(powertrain.get("final_drive_gravel", powertrain_model.final_drive_gravel))
\tpowertrain_model.final_drive_tarmac = float(powertrain.get("final_drive_tarmac", powertrain_model.final_drive_tarmac))
\tvar _preset := str(powertrain.get("final_drive_preset", ""))
\tif _preset == "gravel" and powertrain_model.final_drive_gravel > 0.0:
\t\tpowertrain_model.final_drive_ratio = powertrain_model.final_drive_gravel
\telif _preset == "tarmac" and powertrain_model.final_drive_tarmac > 0.0:
\t\tpowertrain_model.final_drive_ratio = powertrain_model.final_drive_tarmac
\telse:
\t\tpowertrain_model.final_drive_ratio = float(
\t\t\tpowertrain.get("final_drive", powertrain_model.final_drive_ratio)
\t\t)
\tvar _fw: Dictionary = powertrain.get("freewheel", {})
\tif not _fw.is_empty():
\t\tpowertrain_model.freewheel_enabled = bool(_fw.get("enabled", powertrain_model.freewheel_enabled))
\t\tpowertrain_model.freewheel_idle_rpm = maxf(float(_fw.get("idle_rpm", powertrain_model.freewheel_idle_rpm)), 400.0)"""
assert old3 in s
s = s.replace(old3, new3, 1)
old4 = "\tbrake_model.front_brake_bias = clampf(float(brakes.get(\"front_brake_bias\", 0.5)), 0.0, 1.0)"
new4 = """\tvar _servo: Dictionary = brakes.get("servo_assist", {})
\tif not _servo.is_empty():
\t\tbrake_model.servo_assist_enabled = bool(_servo.get("enabled", brake_model.servo_assist_enabled))
\t\tbrake_model.servo_gain = clampf(float(_servo.get("gain", brake_model.servo_gain)), 0.3, 1.6)
\tbrake_model.front_brake_bias = clampf(float(brakes.get("front_brake_bias", 0.5)), 0.0, 1.0)"""
assert old4 in s
s = s.replace(old4, new4, 1)
old5 = "\tmaximum_steering_angle_rad = float(\n\t\tsteering.get(\"max_steering_angle\", maximum_steering_angle_rad)\n\t)\n\tvar aero: Dictionary"
new5 = """\tmaximum_steering_angle_rad = float(
\t\tsteering.get("max_steering_angle", maximum_steering_angle_rad)
\t)
\tsteering_turns_lock_to_lock = float(steering.get("turns_lock_to_lock", steering_turns_lock_to_lock))
\tsteering_ratio_to_one = float(steering.get("ratio_to_one", steering_ratio_to_one))
\tvar aero: Dictionary"""
assert old5 in s
s = s.replace(old5, new5, 1)
# published_state: add new telemetry (after autoblip block)
old6 = "\t\t\"autoblip_throttle\": powertrain_model.autoblip_throttle,"
new6 = """\t\t\"autoblip_throttle\": powertrain_model.autoblip_throttle,
\t\t\"freewheel_active\": powertrain_model.freewheel_active,
\t\t\"freewheel_enabled\": powertrain_model.freewheel_enabled,
\t\t\"primary_reduction\": powertrain_model.primary_reduction_ratio,
\t\t\"final_drive\": powertrain_model.final_drive_ratio,
\t\t\"steering_turns\": steering_turns_lock_to_lock,
\t\t\"steering_ratio\": steering_ratio_to_one,
\t\t\"front_axle_type\": suspension_model.front_axle_type,
\t\t\"rear_axle_type\": suspension_model.rear_axle_type,"""
assert old6 in s
s = s.replace(old6, new6, 1)
# helper to switch gravel/tarmac preset at runtime (assistance)
old7 = "func _prepare_powertrain(delta: float, inputs: Dictionary) -> void:"
new7 = """func set_final_drive_preset(preset: String) -> bool:
\treturn powertrain_model.set_final_drive_preset(preset)


func _prepare_powertrain(delta: float, inputs: Dictionary) -> void:"""
assert old7 in s
s = s.replace(old7, new7, 1)
q.write_text(s, encoding="utf-8")
print("simulation patched OK")

# --- profile_loader.gd: validate new optional blocks ---
r = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\scripts\physics\profile_loader.gd")
u = r.read_text(encoding="utf-8")
old = "\tvar powertrain: Dictionary = domains[\"powertrain\"].get(\"powertrain\", {})"
new = """\tvar powertrain: Dictionary = domains["powertrain"].get("powertrain", {})
\tvar _pw_check := _validate_powertrain_1974_extensions(powertrain)
\tif not bool(_pw_check.get("ok", false)):
\t\treturn _pw_check
\tvar _susp_check := _validate_suspension_1974_extensions(domains["suspension"].get("suspension", {}))
\tif not bool(_susp_check.get("ok", false)):
\t\treturn _susp_check
\tvar _steer_check := _validate_steering_1974_extensions(domains["steering"].get("steering", {}))
\tif not bool(_steer_check.get("ok", false)):
\t\treturn _steer_check
\tvar _brake_check := _validate_brake_1974_extensions(domains["brakes"].get("brakes", {}))
\tif not bool(_brake_check.get("ok", false)):
\t\treturn _brake_check"""
assert old in u
u = u.replace(old, new, 1)
old2 = "static func _read_json(path: String) -> Dictionary:"
new2 = """static func _validate_powertrain_1974_extensions(powertrain: Dictionary) -> Dictionary:
\tvar pr := float(powertrain.get("primary_reduction", 1.0))
\tif not is_finite(pr) or pr < 0.2 or pr > 3.0:
\t\treturn _failure("powertrain.primary_reduction must be in [0.2, 3.0].")
\tvar drop: Dictionary = powertrain.get("drop_gears", {})
\tif not drop.is_empty():
\t\tvar dr := float(drop.get("ratio", 1.0))
\t\tif not is_finite(dr) or dr < 0.2 or dr > 3.0:
\t\t\treturn _failure("powertrain.drop_gears.ratio must be in [0.2, 3.0].")
\tfor key in ["final_drive_gravel", "final_drive_tarmac"]:
\t\tif powertrain.has(key):
\t\t\tvar f := float(powertrain.get(key, 0.0))
\t\t\tif not is_finite(f) or f < 1.0 or f > 8.0:
\t\t\t\treturn _failure("powertrain." + key + " must be in [1.0, 8.0].")
\tif powertrain.has("final_drive_preset") and not str(powertrain.get("final_drive_preset", "")) in ["", "gravel", "tarmac"]:
\t\treturn _failure("powertrain.final_drive_preset must be '', 'gravel' or 'tarmac'.")
\tvar fw: Dictionary = powertrain.get("freewheel", {})
\tif not fw.is_empty():
\t\tvar idle := float(fw.get("idle_rpm", 1000.0))
\t\tif not is_finite(idle) or idle < 400.0 or idle > 2500.0:
\t\t\treturn _failure("powertrain.freewheel.idle_rpm must be in [400, 2500].")
\tvar diff: Dictionary = powertrain.get("differential", {})
\tfor key in ["lock_pct_power", "lock_pct_coast", "lock_pct_traction", "lock_pct_retention"]:
\t\tif diff.has(key):
\t\t\tvar lp := float(diff.get(key, -1.0))
\t\t\tif not is_finite(lp) or lp < 0.0 or lp > 100.0:
\t\t\t\treturn _failure("powertrain.differential." + key + " must be in [0, 100].")
\treturn {"ok": True}


static func _validate_suspension_1974_extensions(suspension: Dictionary) -> Dictionary:
\tvar allowed := ["equivalent", "equivalent_unverified", "macpherson", "double_wishbone", "swing_axle", "trailing_arm", "live_axle_leaf", "live_axle_4link_panhard", "transverse_leaf_wishbone", "strut_coil"]
\tfor axle in ["front", "rear"]:
\t\tvar trim: Dictionary = suspension.get(axle, {})
\t\tvar atype := str(trim.get("axle_type", trim.get("axle_architecture", "equivalent")))
\t\tif not atype in allowed:
\t\t\treturn _failure("suspension." + axle + ".axle_type '" + atype + "' unknown.")
\t\tfor key in ["roll_center_height_m", "jacking_coeff", "jacking_coefficient", "droop_strap_m", "leaf_symmetric_rate_n_per_m", "panhard_stiffness_n_per_m"]:
\t\t\tif trim.has(key) and not is_finite(float(trim.get(key, 0.0))):
\t\t\t\treturn _failure("suspension." + axle + "." + key + " must be finite.")
\tvar phys: Dictionary = suspension.get("geometry_physical", {})
\tfor axle in ["front", "rear"]:
\t\tvar geo: Dictionary = phys.get(axle, {})
\t\tfor key in ["roll_center_height_m", "jacking_coeff", "droop_strap_m"]:
\t\t\tif geo.has(key) and not is_finite(float(geo.get(key, 0.0))):
\t\t\t\treturn _failure("suspension.geometry_physical." + axle + "." + key + " must be finite.")
\treturn {"ok": True}


static func _validate_steering_1974_extensions(steering: Dictionary) -> Dictionary:
\tif steering.has("turns_lock_to_lock"):
\t\tvar t := float(steering.get("turns_lock_to_lock", 0.0))
\t\tif not is_finite(t) or t < 1.0 or t > 6.0:
\t\t\treturn _failure("steering.turns_lock_to_lock must be in [1.0, 6.0].")
\tif steering.has("ratio_to_one"):
\t\tvar rr := float(steering.get("ratio_to_one", 0.0))
\t\tif not is_finite(rr) or rr < 8.0 or rr > 25.0:
\t\t\treturn _failure("steering.ratio_to_one must be in [8, 25].")
\treturn {"ok": True}


static func _validate_brake_1974_extensions(brakes: Dictionary) -> Dictionary:
\tvar servo: Dictionary = brakes.get("servo_assist", {})
\tif not servo.is_empty():
\t\tvar g := float(servo.get("gain", 1.0))
\t\tif not is_finite(g) or g < 0.3 or g > 1.6:
\t\t\treturn _failure("brakes.servo_assist.gain must be in [0.3, 1.6].")
\treturn {"ok": True}


static func _read_json(path: String) -> Dictionary:"""
# NOTE: profile_loader is GDScript, not python — fix booleans below via replace
assert old2 in u
u = u.replace(old2, new2, 1)
u = u.replace('{"ok": True}', '{"ok": true}')
u = u.replace("True)", "true)")
r.write_text(u, encoding="utf-8")
print("loader patched OK")
