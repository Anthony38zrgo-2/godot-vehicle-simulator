import pathlib
p = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\scripts\physics\mass_model.gd")
t = p.read_text(encoding="utf-8")

old = "\tvar fuel: Dictionary = domains.get(\"fuel\", { }).get(\"fuel\", { })"
new = """\t# P1 1974: documentary targets. front_weight_distribution and target_cg_z_m
\t# auto-center the sprung inventory so the JSON recalibration takes effect
\t# even when the 3D asset pivots differ. Body-attached components are
\t# shifted rigidly in Z (distribution) and Y (CG height); uprights/wheels
\t# stay at their hubs. Inertia multipliers stay manual.
\tvar header_fdist := float(chassis_header.get("front_weight_distribution", -1.0))
\tvar header_cgz := float(chassis_header.get("target_cg_z_m", chassis_header.get("target_cgz_m", -1.0)))
\tif (header_fdist >= 0.05 and header_fdist <= 0.95) or header_cgz > 0.05:
\t\tvar _sprung_mass := 0.0
\t\tvar _wcom := Vector3.ZERO
\t\tfor _c in chassis_components:
\t\t\t_sprung_mass += float(_c.get("mass_kg", 0.0))
\t\t\t_wcom += (_c.get("position") as Vector3) * float(_c.get("mass_kg", 0.0))
\t\tif _sprung_mass > 0.0:
\t\t\tvar _cur := _wcom / _sprung_mass
\t\t\tvar _shift := Vector3.ZERO
\t\t\tif header_fdist >= 0.05 and header_fdist <= 0.95 and wheel_centres_local.size() == 4:
\t\t\t\tvar _fz := (wheel_centres_local[0].z + wheel_centres_local[1].z) * 0.5
\t\t\t\tvar _rz := (wheel_centres_local[2].z + wheel_centres_local[3].z) * 0.5
\t\t\t\tvar _wb := absf(_rz - _fz)
\t\t\t\tif _wb > 0.5:
\t\t\t\t\tvar _want_z := _rz - header_fdist * _wb
\t\t\t\t\t# Wheel-centre frame vs body frame can differ per asset;
\t\t\t\t\t# clamp the auto-shift so a documentary target never
\t\t\t\t\t# teleports the inventory on a mismatched rig.
\t\t\t\t\t_shift.z = clampf(_want_z - _cur.z, -0.45, 0.45)
\t\t\tif header_cgz > 0.05:
\t\t\t\t_shift.y = clampf(header_cgz - _cur.y, -0.20, 0.20)
\t\t\tif _shift.length_squared() > 0.00000001:
\t\t\t\tfor _c in chassis_components:
\t\t\t\t\t_c["position"] = (_c.get("position") as Vector3) + _shift
\t\t\tprint("RALLY_MASS_RECENTER ", JSON.stringify({"fdist": header_fdist, "cgz": header_cgz, "shift": [_shift.x, _shift.y, _shift.z]}))
\tvar fuel: Dictionary = domains.get("fuel", {}).get("fuel", {})"""
assert old in t
t = t.replace(old, new, 1)
p.write_text(t, encoding="utf-8")
print("mass patched OK")
