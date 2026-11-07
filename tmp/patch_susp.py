import pathlib
p = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\scripts\physics\suspension_model.gd")
t = p.read_text(encoding="utf-8")

old = "var road_height_max_rate_m_s: float = 0.0"
new = """# P0/P1 1974 axle architecture (documents historic linkage, keeps geometric
# solver backward compatible when absent).
var front_axle_type: String = "equivalent"
var rear_axle_type: String = "equivalent"
var front_roll_center_height_m: float = 0.0
var rear_roll_center_height_m: float = 0.0
var front_jacking_coeff: float = 0.0
var rear_jacking_coeff: float = 0.0
var front_droop_strap_m: float = 99.0
var rear_droop_strap_m: float = 99.0
var front_transverse_leaf: bool = false
var rear_transverse_leaf: bool = false
var front_leaf_symmetric_rate_n_per_m: float = 0.0
var rear_leaf_symmetric_rate_n_per_m: float = 0.0
var front_panhard_stiffness_n_per_m: float = 0.0
var rear_panhard_stiffness_n_per_m: float = 0.0
var road_height_max_rate_m_s: float = 0.0"""
assert old in t
t = t.replace(old, new, 1)

# Parse new fields in configure(): after front_arb/rear_arb fetch, add arch parsing.
old2 = "\tfront_arb_stiffness_n_per_m = float(front_suspension.get(\"spring_rate_N_per_m\", 0.0)) * float(\n\t\tfront_arb.get(\"ratio\", 0.0)\n\t)"
new2 = """\tfront_axle_type = str((suspension_doc.get("front", {}) as Dictionary).get("axle_type", (suspension_doc.get("front", {}) as Dictionary).get("axle_architecture", physical.get("front", {}).get("axle_type", "equivalent"))))
\trear_axle_type = str((suspension_doc.get("rear", {}) as Dictionary).get("axle_type", (suspension_doc.get("rear", {}) as Dictionary).get("axle_architecture", physical.get("rear", {}).get("axle_type", "equivalent"))))
\tfront_roll_center_height_m = float((suspension_doc.get("front", {}) as Dictionary).get("roll_center_height_m", physical.get("front", {}).get("roll_center_height_m", 0.0)))
\trear_roll_center_height_m = float((suspension_doc.get("rear", {}) as Dictionary).get("roll_center_height_m", physical.get("rear", {}).get("roll_center_height_m", 0.0)))
\tfront_jacking_coeff = float((suspension_doc.get("front", {}) as Dictionary).get("jacking_coeff", (suspension_doc.get("front", {}) as Dictionary).get("jacking_coefficient", physical.get("front", {}).get("jacking_coeff", 0.0))))
\trear_jacking_coeff = float((suspension_doc.get("rear", {}) as Dictionary).get("jacking_coeff", (suspension_doc.get("rear", {}) as Dictionary).get("jacking_coefficient", physical.get("rear", {}).get("jacking_coeff", 0.0))))
\tfront_droop_strap_m = float((suspension_doc.get("front", {}) as Dictionary).get("droop_strap_m", physical.get("front", {}).get("droop_strap_m", 99.0)))
\trear_droop_strap_m = float((suspension_doc.get("rear", {}) as Dictionary).get("droop_strap_m", physical.get("rear", {}).get("droop_strap_m", 99.0)))
\tfront_transverse_leaf = bool((suspension_doc.get("front", {}) as Dictionary).get("transverse_leaf", physical.get("front", {}).get("transverse_leaf", false)))
\trear_transverse_leaf = bool((suspension_doc.get("rear", {}) as Dictionary).get("transverse_leaf", physical.get("rear", {}).get("transverse_leaf", false)))
\tfront_leaf_symmetric_rate_n_per_m = float((suspension_doc.get("front", {}) as Dictionary).get("leaf_symmetric_rate_n_per_m", physical.get("front", {}).get("leaf_symmetric_rate_n_per_m", 0.0)))
\trear_leaf_symmetric_rate_n_per_m = float((suspension_doc.get("rear", {}) as Dictionary).get("leaf_symmetric_rate_n_per_m", physical.get("rear", {}).get("leaf_symmetric_rate_n_per_m", 0.0)))
\tfront_panhard_stiffness_n_per_m = float((suspension_doc.get("front", {}) as Dictionary).get("panhard_stiffness_n_per_m", physical.get("front", {}).get("panhard_stiffness_n_per_m", 0.0)))
\trear_panhard_stiffness_n_per_m = float((suspension_doc.get("rear", {}) as Dictionary).get("panhard_stiffness_n_per_m", physical.get("rear", {}).get("panhard_stiffness_n_per_m", 0.0)))
\tfront_arb_stiffness_n_per_m = float(front_suspension.get("spring_rate_N_per_m", 0.0)) * float(\n\t\tfront_arb.get("ratio", 0.0)\n\t)"""
assert old2 in t, "cfg block not found"
t = t.replace(old2, new2, 1)

# Store per-axle arch in axle_parameters dict: extend dict literal
old3 = "\t\t\t\"camber\": float(corner_tune.get(\"camber\", 0.0)),"
new3 = "\t\t\t\"axle_type\": front_axle_type if i < 2 else rear_axle_type,\n\t\t\t\"roll_center_height_m\": front_roll_center_height_m if i < 2 else rear_roll_center_height_m,\n\t\t\t\"jacking_coeff\": front_jacking_coeff if i < 2 else rear_jacking_coeff,\n\t\t\t\"droop_strap_m\": front_droop_strap_m if i < 2 else rear_droop_strap_m,\n\t\t\t\"camber\": float(corner_tune.get(\"camber\", 0.0)),"
assert old3 in t
t = t.replace(old3, new3, 1)

# suspension_forces: apply droop strap clamp + transverse leaf symmetric + jacking/roll-center ARB scale
old4 = "\tfor i in 4:\n\t\tvar p: Dictionary = axle_parameters[i]\n\t\tvar travel := compression[i]"
new4 = """\t# P0: transverse leaf symmetric stiffness (Kadett/Fulvia front).
\tvar front_avg := (compression[0] + compression[1]) * 0.5 if contact_active[0] or contact_active[1] else 0.0
\tvar rear_avg := (compression[2] + compression[3]) * 0.5 if contact_active[2] or contact_active[3] else 0.0
\tfor i in 4:
\t\tvar p: Dictionary = axle_parameters[i]
\t\tvar travel := compression[i]
\t\tvar strap := float(p.get("droop_strap_m", 99.0))
\t\tif strap < 90.0:
\t\t\ttravel = maxf(travel, -strap)"""
assert old4 in t
t = t.replace(old4, new4, 1)

old5 = "\t\tvar force := elastic_force + damper_force"
new5 = """\t\tvar force := elastic_force + damper_force
\t\t# P0: transverse leaf adds symmetric rate (stiff vs symmetric bumps).
\t\tif i < 2 and front_transverse_leaf and front_leaf_symmetric_rate_n_per_m > 0.0:
\t\t\tforce += front_leaf_symmetric_rate_n_per_m * front_avg
\t\tif i >= 2 and rear_transverse_leaf and rear_leaf_symmetric_rate_n_per_m > 0.0:
\t\t\tforce += rear_leaf_symmetric_rate_n_per_m * rear_avg"""
assert old5 in t
t = t.replace(old5, new5, 1)

old6 = "\tvar front_roll := filtered_arb_travel[0] - filtered_arb_travel[1]\n\tvar rear_roll := filtered_arb_travel[2] - filtered_arb_travel[3]\n\tvar front_arb := front_arb_stiffness_n_per_m * front_roll\n\tvar rear_arb := rear_arb_stiffness_n_per_m * rear_roll"
new6 = """\tvar front_roll := filtered_arb_travel[0] - filtered_arb_travel[1]
\tvar rear_roll := filtered_arb_travel[2] - filtered_arb_travel[3]
\t# P0/P1: roll-center height stiffens geometric roll resistance; swing-axle
\t# jacking amplifies the effective ARB transfer (stable approximation of
\t# body lift without full lateral-force coupling, done in unsprung rig).
\tvar front_arb_scale := (1.0 + front_jacking_coeff * 1.5) * (1.0 + clampf((front_roll_center_height_m - 0.08) * 1.2, -0.25, 0.6))
\tvar rear_arb_scale := (1.0 + rear_jacking_coeff * 1.5) * (1.0 + clampf((rear_roll_center_height_m - 0.08) * 1.2, -0.25, 0.6))
\tvar front_arb := front_arb_stiffness_n_per_m * front_arb_scale * front_roll
\tvar rear_arb := rear_arb_stiffness_n_per_m * rear_arb_scale * rear_roll
\t# Panhard lateral location adds a small roll-stabilising transfer.
\tfront_arb += front_panhard_stiffness_n_per_m * 0.02 * front_roll
\trear_arb += rear_panhard_stiffness_n_per_m * 0.02 * rear_roll"""
assert old6 in t
t = t.replace(old6, new6, 1)

p.write_text(t, encoding="utf-8")
print("suspension patched OK")
