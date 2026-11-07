import pathlib
p = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\scripts\physics\powertrain_model.gd")
t = p.read_text(encoding="utf-8")

# 1. engine_torque_at_rpm: zero drag when freewheeling
old = "\tvar variable_drag := rpm_fraction * peak_torque_nm * variable_drag_ratio * lerpf(\n\t\t0.15,\n\t\t1.0,\n\t\tclosed_throttle,\n\t)\n\tvar constant_brake := peak_torque_nm * constant_brake_ratio * closed_throttle"
new = "\t# P0 freewheel: zero engine braking while overrunning (Blomqvist technique).\n\tvar freewheeling_now := freewheel_active\n\tif freewheeling_override >= 0.0:\n\t\tfreewheeling_now = freewheeling_override > 0.5\n\tvar variable_drag := 0.0\n\tvar constant_brake := 0.0\n\tif not (freewheeling_now and freewheel_enabled):\n\t\tvariable_drag = rpm_fraction * peak_torque_nm * variable_drag_ratio * lerpf(\n\t\t\t0.15,\n\t\t\t1.0,\n\t\t\tclosed_throttle,\n\t\t)\n\t\tconstant_brake = peak_torque_nm * constant_brake_ratio * closed_throttle"
assert old in t, "block1 not found"
t = t.replace(old, new, 1)

# 2. advance(): update freewheel at start + pull to freewheel idle
old2 = "\tvar dt := maxf(delta, 0.00001)\n\tshift_phase_seconds += dt"
new2 = "\tvar dt := maxf(delta, 0.00001)\n\t_update_freewheel(throttle, carrier_omega_rad_s)\n\tshift_phase_seconds += dt"
assert old2 in t, "block2 not found"
t = t.replace(old2, new2, 1)

old3 = "\tif thermal_derating > 0.0 and engine_rpm < idle_rpm and clutch_engagement < 0.05:\n\t\tengine_rpm = move_toward(engine_rpm, idle_rpm, 1500.0 * dt)"
new3 = "\tif freewheel_enabled and freewheel_active:\n\t\tengine_rpm = move_toward(engine_rpm, freewheel_idle_rpm, 4000.0 * dt)\n\tif thermal_derating > 0.0 and engine_rpm < idle_rpm and clutch_engagement < 0.05:\n\t\tengine_rpm = move_toward(engine_rpm, idle_rpm, 1500.0 * dt)"
assert old3 in t, "block3 not found"
t = t.replace(old3, new3, 1)

# 3. autoblip: use total ratio
old4 = "\tvar target_omega := _ratio_for_gear(pending_gear) * final_drive_ratio * carrier_omega"
new4 = "\tvar target_omega := total_ratio_for_gear(pending_gear) * carrier_omega"
assert old4 in t, "block4 not found"
t = t.replace(old4, new4, 1)

# 4. solve_rotation: use total ratio + freewheel decouple
old5 = "\tvar synchronizing := shift_phase == \"synchronizing\" and shift_phase_seconds >= 0.0 and pending_gear != 0\n\tvar ratio := (_ratio_for_gear(pending_gear) if synchronizing else gear_ratio()) * final_drive_ratio\n\tvar geared := current_gear != 0 and absf(ratio) > 0.000001\n\tvar connected := geared or synchronizing"
new5 = "\tvar synchronizing := shift_phase == \"synchronizing\" and shift_phase_seconds >= 0.0 and pending_gear != 0\n\tvar ratio := (total_ratio_for_gear(pending_gear) if synchronizing else total_ratio())\n\tvar geared := current_gear != 0 and absf(ratio) > 0.000001\n\t# P0 freewheel: decouple gear torque while overrunning; engine braking is\n\t# already zeroed in engine_torque_at_rpm, wheels spin free.\n\tvar _carrier_now := 0.0\n\tfor _ci in 4:\n\t\t_carrier_now += (front_torque_split * 0.5 if _ci < 2 else (1.0 - front_torque_split) * 0.5) * spins[_ci]\n\t_update_freewheel(1.0 if engine_torque_nm > 0.0 else 0.0, _carrier_now)\n\t# NOTE: solve_rotation has no throttle input; keep the latched freewheel\n\t# state from advance() unless clearly re-engaged (engine caught wheels).\n\tif freewheel_enabled and freewheel_active:\n\t\tvar _equiv := _carrier_now * ratio\n\t\tif engine_omega + freewheel_reengage_margin_rad_s >= _equiv:\n\t\t\tfreewheel_active = false\n\tvar connected := (geared or synchronizing) and not (freewheel_enabled and freewheel_active)"
assert old5 in t, "block5 not found"
t = t.replace(old5, new5, 1)

# 5. reset_shift should clear freewheel latch
old6 = "func reset_shift() -> void:\n\trevmatch_downshift = false"
new6 = "func reset_shift() -> void:\n\tfreewheel_active = false\n\trevmatch_downshift = false"
assert old6 in t, "block6 not found"
t = t.replace(old6, new6, 1)

# 6. set_preset helper + lock pct conversion helper at end of configure helpers (append before reset_compliance)
old7 = "func reset_compliance() -> void:"
new7 = """func set_final_drive_preset(preset: String) -> bool:
\tif preset == "gravel" and final_drive_gravel > 0.0:
\t\tfinal_drive_ratio = final_drive_gravel
\t\tfinal_drive_preset = preset
\t\treturn true
\tif preset == "tarmac" and final_drive_tarmac > 0.0:
\t\tfinal_drive_ratio = final_drive_tarmac
\t\tfinal_drive_preset = preset
\t\treturn true
\treturn false


# P1: documentary helper — approximate ramp angle from lock % for tooling.
# butt Brutalist mapping used by the 1974 recalibration docs:
# 0% -> 85deg (open), 25% -> 65deg, 35-45% -> 45-55deg, 60-65% -> 30-35deg.
static func suggested_ramp_for_lock_pct(lock_pct: float) -> float:
\tvar p := clampf(lock_pct, 0.0, 100.0)
\tif p <= 0.5:
\t\treturn 85.0
\tif p <= 15.0:
\t\treturn 75.0
\tif p <= 27.5:
\t\treturn 65.0
\tif p <= 37.5:
\t\treturn 55.0
\tif p <= 47.5:
\t\treturn 45.0
\tif p <= 57.5:
\t\treturn 37.5
\treturn 30.0


func reset_compliance() -> void:"""
assert old7 in t, "block7 not found"
t = t.replace(old7, new7, 1)

p.write_text(t, encoding="utf-8")
print("powertrain patched OK")
