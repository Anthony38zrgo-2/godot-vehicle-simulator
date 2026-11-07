import pathlib

# 1. Patch powertrain_model.gd
p = pathlib.Path(r"game/scripts/physics/powertrain_model.gd")
t = p.read_text(encoding="utf-8")

# Normalise to LF for replacement, then back to original CRLF
is_crlf = "\r\n" in t
t = t.replace("\r\n", "\n")

# Variables
old_vars = "var reverse_ratio: float = 0.0\nvar final_drive_ratio: float = 1.0"
new_vars = """var reverse_ratio: float = 0.0
var final_drive_ratio: float = 1.0
var final_drive_gravel: float = 0.0
var final_drive_tarmac: float = 0.0
var final_drive_preset: String = ""

# P0: Saab freewheel (one-way clutch on primary shaft).
var freewheel_enabled: bool = false
var freewheel_idle_rpm: float = 1000.0
var freewheel_reengage_margin_rad_s: float = 1.5
var freewheel_active: bool = false"""
assert old_vars in t, "old_vars not found"
t = t.replace(old_vars, new_vars, 1)

# configure()
old_cfg = '\tfinal_drive_ratio = float(powertrain.get("final_drive", 1.0))'
new_cfg = """\tfinal_drive_ratio = float(powertrain.get("final_drive", 1.0))
\tfinal_drive_gravel = float(powertrain.get("final_drive_gravel", 0.0))
\tfinal_drive_tarmac = float(powertrain.get("final_drive_tarmac", 0.0))
\tfinal_drive_preset = str(powertrain.get("final_drive_preset", ""))
\tif final_drive_preset == "gravel" and final_drive_gravel > 0.0:
\t\tfinal_drive_ratio = final_drive_gravel
\telif final_drive_preset == "tarmac" and final_drive_tarmac > 0.0:
\t\tfinal_drive_ratio = final_drive_tarmac
\tvar freewheel_doc: Dictionary = powertrain.get("freewheel", {})
\tfreewheel_enabled = bool(freewheel_doc.get("enabled", false))
\tfreewheel_idle_rpm = maxf(float(freewheel_doc.get("idle_rpm", 1000.0)), 400.0)
\tfreewheel_reengage_margin_rad_s = clampf(
\t\tfloat(freewheel_doc.get("reengage_margin_rad_s", 1.5)), 0.0, 10.0
\t)
\tfreewheel_active = false"""
assert old_cfg in t, "old_cfg not found"
t = t.replace(old_cfg, new_cfg, 1)

# set_final_drive_preset helper
old_comp = "func reset_compliance() -> void:"
new_comp = """func set_final_drive_preset(preset: String) -> bool:
\tif preset == "gravel" and final_drive_gravel > 0.0:
\t\tfinal_drive_ratio = final_drive_gravel
\t\tfinal_drive_preset = preset
\t\treturn true
\tif preset == "tarmac" and final_drive_tarmac > 0.0:
\t\tfinal_drive_ratio = final_drive_tarmac
\t\tfinal_drive_preset = preset
\t\treturn true
\treturn false


func reset_compliance() -> void:"""
assert old_comp in t, "old_comp not found"
t = t.replace(old_comp, new_comp, 1)

# reset_shift()
old_rs = "func reset_shift() -> void:\n\trevmatch_downshift = false"
new_rs = "func reset_shift() -> void:\n\tfreewheel_active = false\n\trevmatch_downshift = false"
assert old_rs in t, "old_rs not found"
t = t.replace(old_rs, new_rs, 1)

# gear_ratio() and freewheel helpers
old_gr = "func gear_ratio() -> float:\n\treturn _ratio_for_gear(current_gear)"
new_gr = """func gear_ratio() -> float:
\treturn _ratio_for_gear(current_gear)


func _update_freewheel(throttle: float, carrier_omega_rad_s: float) -> void:
\tif not freewheel_enabled:
\t\tfreewheel_active = false
\t\treturn
\tif current_gear <= 0:
\t\tfreewheel_active = false
\t\treturn
\tvar engine_omega := engine_rpm * TAU / 60.0
\tvar equiv_omega := carrier_omega_rad_s * gear_ratio() * final_drive_ratio
\tfreewheel_active = (
\t\tthrottle < 0.1
\t\tand equiv_omega > engine_omega + freewheel_reengage_margin_rad_s
\t)


func is_freewheeling() -> bool:
\treturn freewheel_active"""
assert old_gr in t, "old_gr not found"
t = t.replace(old_gr, new_gr, 1)

# engine_torque_at_rpm
old_tq = """\tvar variable_drag := rpm_fraction * peak_torque_nm * variable_drag_ratio * lerpf(
\t\t0.15,
\t\t1.0,
\t\tclosed_throttle,
\t)
\tvar constant_brake := peak_torque_nm * constant_brake_ratio * closed_throttle"""
new_tq = """\tvar freewheeling_now := freewheel_active
\tif freewheeling_override >= 0.0:
\t\tfreewheeling_now = freewheeling_override > 0.5
\tvar variable_drag := 0.0
\tvar constant_brake := 0.0
\tif not (freewheeling_now and freewheel_enabled):
\t\tvariable_drag = rpm_fraction * peak_torque_nm * variable_drag_ratio * lerpf(
\t\t\t0.15,
\t\t\t1.0,
\t\t\tclosed_throttle,
\t\t)
\t\tconstant_brake = peak_torque_nm * constant_brake_ratio * closed_throttle"""
assert old_tq in t, "old_tq not found"
t = t.replace(old_tq, new_tq, 1)

# signature of engine_torque_at_rpm
old_tq_sig = "func engine_torque_at_rpm(rpm: float, throttle: float, thermal_derating: float = 1.0) -> float:"
new_tq_sig = "func engine_torque_at_rpm(rpm: float, throttle: float, thermal_derating: float = 1.0, freewheeling_override: float = -1.0) -> float:"
assert old_tq_sig in t, "old_tq_sig not found"
t = t.replace(old_tq_sig, new_tq_sig, 1)

# advance()
old_adv = "\tvar dt := maxf(delta, 0.00001)\n\tshift_phase_seconds += dt"
new_adv = "\tvar dt := maxf(delta, 0.00001)\n\t_update_freewheel(throttle, carrier_omega_rad_s)\n\tshift_phase_seconds += dt"
assert old_adv in t, "old_adv not found"
t = t.replace(old_adv, new_adv, 1)

old_adv_rpm = "\tif thermal_derating > 0.0 and engine_rpm < idle_rpm and clutch_engagement < 0.05:\n\t\tengine_rpm = move_toward(engine_rpm, idle_rpm, 1500.0 * dt)"
new_adv_rpm = """\tif freewheel_enabled and freewheel_active:
\t\tengine_rpm = move_toward(engine_rpm, freewheel_idle_rpm, 4000.0 * dt)
\tif thermal_derating > 0.0 and engine_rpm < idle_rpm and clutch_engagement < 0.05:
\t\tengine_rpm = move_toward(engine_rpm, idle_rpm, 1500.0 * dt)"""
assert old_adv_rpm in t, "old_adv_rpm not found"
t = t.replace(old_adv_rpm, new_adv_rpm, 1)

# solve_rotation()
old_rot = """\tvar synchronizing := shift_phase == "synchronizing" and shift_phase_seconds >= 0.0 and pending_gear != 0
\tvar ratio := (_ratio_for_gear(pending_gear) if synchronizing else gear_ratio()) * final_drive_ratio
\tvar geared := current_gear != 0 and absf(ratio) > 0.000001
\tvar connected := geared or synchronizing"""
new_rot = """\tvar synchronizing := shift_phase == "synchronizing" and shift_phase_seconds >= 0.0 and pending_gear != 0
\tvar ratio := (_ratio_for_gear(pending_gear) if synchronizing else gear_ratio()) * final_drive_ratio
\tvar geared := current_gear != 0 and absf(ratio) > 0.000001
\tvar _carrier_now := 0.0
\tfor _ci in 4:
\t\t_carrier_now += (front_torque_split * 0.5 if _ci < 2 else (1.0 - front_torque_split) * 0.5) * spins[_ci]
\t_update_freewheel(1.0 if engine_torque_nm > 0.0 else 0.0, _carrier_now)
\tif freewheel_enabled and freewheel_active:
\t\tvar _equiv := _carrier_now * ratio
\t\tif engine_omega + freewheel_reengage_margin_rad_s >= _equiv:
\t\t\tfreewheel_active = false
\tvar connected := (geared or synchronizing) and not (freewheel_enabled and freewheel_active)"""
assert old_rot in t, "old_rot not found"
t = t.replace(old_rot, new_rot, 1)

if is_crlf:
    t = t.replace("\n", "\r\n")
p.write_text(t, encoding="utf-8")
print("powertrain_model.gd patched OK")


# 2. Patch vehicle_simulation.gd
q = pathlib.Path(r"game/scripts/physics/vehicle_simulation.gd")
s = q.read_text(encoding="utf-8")
is_crlf_s = "\r\n" in s
s = s.replace("\r\n", "\n")

old_sim_fd = """\tpowertrain_model.final_drive_ratio = float(
\t\tpowertrain.get("final_drive", powertrain_model.final_drive_ratio)
\t)"""
new_sim_fd = """\tpowertrain_model.final_drive_gravel = float(powertrain.get("final_drive_gravel", powertrain_model.final_drive_gravel))
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
assert old_sim_fd in s, "old_sim_fd not found"
s = s.replace(old_sim_fd, new_sim_fd, 1)

old_sim_pub = """\t\t"autoblip_active": powertrain_model.autoblip_active,
\t\t"autoblip_target_rpm": powertrain_model.autoblip_target_rpm,
\t\t"autoblip_throttle": powertrain_model.autoblip_throttle,"""
new_sim_pub = """\t\t"autoblip_active": powertrain_model.autoblip_active,
\t\t"autoblip_target_rpm": powertrain_model.autoblip_target_rpm,
\t\t"autoblip_throttle": powertrain_model.autoblip_throttle,
\t\t"freewheel_active": powertrain_model.freewheel_active,
\t\t"freewheel_enabled": powertrain_model.freewheel_enabled,
\t\t"final_drive": powertrain_model.final_drive_ratio,"""
assert old_sim_pub in s, "old_sim_pub not found"
s = s.replace(old_sim_pub, new_sim_pub, 1)

old_sim_prep = "func _prepare_powertrain(delta: float, inputs: Dictionary) -> void:"
new_sim_prep = """func set_final_drive_preset(preset: String) -> bool:
\treturn powertrain_model.set_final_drive_preset(preset)


func _prepare_powertrain(delta: float, inputs: Dictionary) -> void:"""
assert old_sim_prep in s, "old_sim_prep not found"
s = s.replace(old_sim_prep, new_sim_prep, 1)

if is_crlf_s:
    s = s.replace("\n", "\r\n")
q.write_text(s, encoding="utf-8")
print("vehicle_simulation.gd patched OK")
