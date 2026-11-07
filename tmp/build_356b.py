# Build rt-porsche-356b-2000gs — lógica tooling Rally Trophy:
# game-derived desde los INI del mod (.rtp FTC) + overrides históricos (ficha FIA #71),
# mallas/sonidos/colisión reusados de rt-porsche-356a por referencia (misma T6).
import copy, hashlib, json, math, pathlib, shutil

REPO = pathlib.Path(r"D:\rust-godot-vehicle-simulator")
NEW = "rt-porsche-356b-2000gs"
SRC = "rt-porsche-356a"
DISP = "Porsche 356B Carrera 2000 GS"
MOD = REPO / "tmp/porsche_mod"
RTP_STD = "Porsche356Carrera2000GS_by_sharbo.zip/Porsche356bT6Carrera.rtp"
RTP_FTC = "Porsche356Carrera2000GS_by_sharbo.zip/Porsche356bT6CoupeFTC_v30.rtp"

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def load(d, n):
    return json.loads((REPO / d / n).read_text(encoding="utf-8"))

def save(p, o):
    p.write_text(json.dumps(o, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# ---------- 1. receta ----------
recipe = {
    "id": NEW,
    "archive": "mods/Porsche356bT6CoupeFTC_v30.rtp",
    "archive_alternate": "mods/Porsche356bT6Carrera.rtp",
    "historical_id": "porsche-356b-2000gs",
    "display_name": DISP,
    "engine_layout": "rear",
    "geometry_policy": "native",
    "physics_policy": "game_derived",
    "crew_mass_kg": 150,
    "tools_mass_kg": 7,
    "engine_mass_kg": 140,
    "fuel_capacity_l": 55,
    "base_variant": "ftc_175bhp_1966cc",
    "mod_source": {
        "zip": "Porsche356Carrera2000GS_by_sharbo.zip",
        "rtp_ftc_sha256": sha(MOD / "Porsche356bT6CoupeFTC_v30.rtp"),
        "rtp_std_sha256": sha(MOD / "Porsche356bT6Carrera.rtp"),
        "readme": "fictional T6 Coupe body; 1966cc 130bhp std / 175bhp FTC; mesh+TGA sharbo+bugbear; physics YorT; sounds KittX",
    },
    "reuse": {
        "assets": SRC,
        "sounds": SRC,
        "collision": SRC,
        "reason": "identical T6 body/measured geometry (2.100/1.306/1.272 m); no mesh conversion, binaries untouched per assets AGENTS.md",
    },
    "build_note": "Manual profile build following physics_profile.compile_profile logic (game INI -> base, ficha overrides on top). Blender/Godot pipeline not run: meshes and bank reused by reference.",
    "physics_overrides": {
        "powertrain.json": {"powertrain": {
            "max_torque": 176.0, "max_rpm": 7200.0, "idle_rpm": 1100.0, "motor_moment": 0.102,
            "gear_ratios": [3.091, 1.765, 1.227, 0.96], "reverse_ratio": 3.09,
            "final_drive": 4.428,
            "differential": {"preload_nm": 40, "power_ramp_angle_deg": 50, "coast_ramp_angle_deg": 65,
                             "lock_pct_power": 40, "lock_pct_coast": 25,
                             "clutch_friction_coefficient": 0.11, "coast_friction_coefficient": 0.08, "clutches": 4},
            "note": "FTC game box 3.090/1.762/1.231/0.962 + EndRatio 4.86 replaced by FIA #71 rally BBBD + 4.428 (7:31); torque peak FTC 4500 kept, cut at 7200 per ficha (ficha peak 5200 noted)",
        }},
        "chassis.json": {"chassis": {"vehicle_mass": 1047.0, "front_weight_distribution": 0.40, "target_cg_z_m": 0.450}},
        "suspension.json": {"suspension": {
            "front": {"ride_frequency_hz": 1.85}, "rear": {"ride_frequency_hz": 1.95},
            "note": "FIA frequencies + 100/75 mm; rear Ausgleichfeder transverse compensating leaf, low rear ARB (reduced roll stiffness per ficha)"}},
        "brakes.json": {"brakes": {"front_brake_bias": 0.56, "max_brake_torque": 4800.0,
                                    "servo_assist": {"enabled": False, "gain": 0.82},
                                    "note": "ATE annular 282/285 mm, no servo (ficha §2.2)"}},
        "steering.json": {"steering": {"turns_lock_to_lock": 2.4, "ratio_to_one": 14.5}},
    },
}
save(REPO / "tools/rally_trophy/recipes/rt-porsche-356b-2000gs.json", recipe)
print("receta OK")

# ---------- 2. history.json ----------
hist_p = REPO / "tools/rally_trophy/data/history.json"
hist = json.loads(hist_p.read_text(encoding="utf-8"))
hist["cars"]["porsche-356b-2000gs"] = {
    "name": DISP,
    "sources": {
        "mod": {"file": RTP_FTC, "sha256": sha(MOD / "Porsche356bT6CoupeFTC_v30.rtp"),
                "note": "sharbo T6 mod: FTC 1966cc 175bhp variant used as game-derived base; std 130bhp variant archived"},
        "ficha": {"file": "porsche_356b_carrera_2_2000gs_ficha_tecnica.md",
                  "note": "FIA #71 (oct 1962) dossier: GS 130 CV/162 Nm, GS/GT Werk 155-160 CV/176 Nm, ring brakes, Ausgleichfeder"},
    },
    "facts": {
        "displacement_cc": {"value": 1966, "source": "ficha", "locator": "§1.3/§3 Type 587 92x74", "status": "documented"},
        "drive": {"value": "RWD", "source": "mod_rtp", "locator": "car.ini FrontTraction=0", "status": "documented"},
        "cylinders": {"value": 4, "source": "ficha", "locator": "§1 Type 587 boxer", "status": "documented"},
        "wheelbase_m": {"value": 2.10, "source": "ficha", "locator": "§3 tabla FIA #71", "status": "documented"},
        "track_front_m": {"value": 1.306, "source": "ficha", "locator": "§3 1.306/1.272", "status": "documented"},
        "track_rear_m": {"value": 1.272, "source": "ficha", "locator": "§3 1.306/1.272", "status": "documented"},
        "fuel_l": {"value": 55, "source": "ficha", "locator": "§3 masa operativa 55 L", "status": "documented"},
        "mass_kg": {"value": 890, "source": "ficha", "locator": "§2.3 coupe GT aluminio, vacio", "status": "documented"},
    },
    "variant_note": "1962-65 Grupo 3 GT. Game base = FTC mod (1966cc, BBBD-like box). Operating mass 1065 = 890 + 150 crew + tools + 55 L fuel; steel GS 970-1010 heavier.",
    "review": ["period rally mass and weight distribution", "competition torque curve and gearing",
               "spring and damper rates", "differential setup"],
}
save(hist_p, hist)
print("history OK")

# ---------- 3. perfil: clonar 356A ----------
prof_src = REPO / f"game/data/vehicles/rt/{SRC}"
prof_new = REPO / f"game/data/vehicles/rt/{NEW}"
prof_new.mkdir(parents=True, exist_ok=True)
for f in prof_src.glob("*.json"):
    if f.name == "HISTORICAL_PROVENANCE.json":
        continue
    shutil.copy2(f, prof_new / f.name)
print("clon OK")

# --- chassis: base 1047 con trip ---
ch = json.loads((prof_new / "chassis.json").read_text(encoding="utf-8"))
ch["chassis"]["vehicle_name"] = DISP
ch["chassis"]["vehicle_mass"] = 1047.0
ch["chassis"]["front_weight_distribution"] = 0.40
ch["chassis"]["target_cg_z_m"] = 0.450
ch["geometry"] = {"wheelbase": 2.10, "front_axle_z": -1.05, "rear_axle_z": 1.05,
                  "front_track": 1.306, "rear_track": 1.272}
byname = {x["properties"]["name"]: x for x in ch["physical_mass_inventory"]["components"]}
# engine 140 (587 +35 kg detrás del eje, ficha §3), spare 27, uprights 6x4=24
byname["engine_and_transaxle"]["properties"]["mass_kilograms"] = 140.0
byname["body_and_systems"]["properties"]["mass_kilograms"] = 706.0
byname["spare_wheels_and_tools"]["properties"]["mass_kilograms"] = 27.0
b = byname["body_and_systems"]["properties"]
b["inertia_about_center_of_mass"] = {"entries_kilogram_square_metres": [[1011.5, 0, 0], [0, 1054.0, 0], [0, 0, 250.8]]}
b["provenance"] = {"source": "Ficha §3 con tripulacion (cuerpo 85%: Ix 1190/Iy 1240/Iz 295 -> Godot x/y/z)", "mass_origin": "recalibrated_1974", "center_of_mass_origin": "recalibrated_1974", "inertia_origin": "recalibrated_1974"}
b["center_of_mass_in_attachment_metres"] = {"x": 0, "y": 0.450, "z": 0.10}
e = byname["engine_and_transaxle"]["properties"]
e["center_of_mass_in_attachment_metres"] = {"x": 0, "y": 0.40, "z": 0.55}
for k in ("driver_and_seat", "codriver_and_seat"):
    byname[k]["properties"]["center_of_mass_in_attachment_metres"] = {"x": byname[k]["properties"]["center_of_mass_in_attachment_metres"]["x"], "y": 0.57, "z": 0.05}
byname["spare_wheels_and_tools"]["properties"]["center_of_mass_in_attachment_metres"] = {"x": 0, "y": 0.43, "z": -0.10}
ch["physical_mass_inventory"]["base_budget_kilograms"] = 1047.0
save(prof_new / "chassis.json", ch)

# --- powertrain: base FTC + corte ficha ---
pw = json.loads((prof_new / "powertrain.json").read_text(encoding="utf-8"))
p = pw["powertrain"]
p["max_torque"] = 176.0; p["max_rpm"] = 7200.0; p["idle_rpm"] = 1100.0
p["motor_moment"] = 0.102
p["gear_ratios"] = [3.091, 1.765, 1.227, 0.96]
p["reverse_ratio"] = 3.09
p["final_drive"] = 4.428
for k in ("final_drive_gravel", "final_drive_tarmac", "final_drive_preset", "primary_reduction", "drop_gears", "freewheel"):
    p.pop(k, None)
ftc_curve = [(500,.40),(1000,.44),(1500,.53),(2000,.64),(2500,.74),(3000,.83),(3500,.91),(4000,.97),(4500,1.0),(5000,.99),(5500,.97),(6000,.95),(6500,.93),(7000,.89)]
p["torque_curve"] = [[round(r/7200.0, 6), v] for r, v in ftc_curve] + [[round(7500/7200.0, 6), 0.35], [round(7800/7200.0, 6), 0.0]]
p["clutch_release_seconds"] = 0.10; p["shift_time"] = 0.09; p["clutch_reengage_seconds"] = 0.18
df = p["differential"]
df.update({"preload_nm": 40.0, "power_ramp_angle_deg": 50.0, "coast_ramp_angle_deg": 65.0,
           "lock_pct_power": 40.0, "lock_pct_coast": 25.0,
           "clutch_friction_coefficient": 0.11, "coast_friction_coefficient": 0.08, "clutches": 4.0})
save(prof_new / "powertrain.json", pw)

# --- suspension: frecuencias ficha + compensadora ---
su = json.loads((prof_new / "suspension.json").read_text(encoding="utf-8"))
s = su["suspension"]
s["front"]["axle_type"] = "trailing_arm"
s["front"]["camber"] = math.radians(-1.2)
s["front"]["roll_center_height_m"] = 0.06
s["front"]["ride_frequency_hz"] = 1.85
s["rear"]["axle_type"] = "swing_axle"
s["rear"]["camber"] = math.radians(-2.0)
s["rear"]["jacking_coeff"] = 0.25
s["rear"]["droop_strap_m"] = 0.075
s["rear"]["roll_center_height_m"] = 0.10
s["rear"]["ride_frequency_hz"] = 1.95
s["rear"]["transverse_leaf"] = True
s["rear"]["leaf_symmetric_rate_n_per_m"] = 12000.0
s["rear"]["leaf_note"] = "Ausgleichfeder: soporta carga vertical del 587; NO aporta rolido (rear ARB bajo)"
s["geometry_physical"]["front"]["wheel_bump_m"] = 0.100
s["geometry_physical"]["front"]["wheel_droop_m"] = 0.075
s["geometry_physical"]["rear"]["wheel_bump_m"] = 0.100
s["geometry_physical"]["rear"]["wheel_droop_m"] = 0.075
s["geometry_physical"]["rear_arb"]["ratio"] = 0.04
save(prof_new / "suspension.json", su)

# --- steering / brakes / fuel / vehicle ---
st = json.loads((prof_new / "steering.json").read_text(encoding="utf-8"))
st["steering"]["turns_lock_to_lock"] = 2.4
st["steering"]["ratio_to_one"] = 14.5
st["steering"]["max_steering_angle"] = 0.6
save(prof_new / "steering.json", st)

br = json.loads((prof_new / "brakes.json").read_text(encoding="utf-8"))
bb = br["brakes"]
bb["servo_assist"] = {"enabled": False, "gain": 0.82}
bb["front_brake_bias"] = 0.56
bb["max_brake_torque"] = 4800.0
bb["front_disc_diameter_m"] = 0.282
bb["rear_disc_diameter_m"] = 0.285
bb.pop("manual_proportioning", None)
for ax in ("front", "rear"):
    th = bb["thermal"][ax]
    d = 0.282 if ax == "front" else 0.285
    th["rotor_outer_diameter_m"] = d
    th["rotor_ventilation"] = "ventilated"
    th["note"] = "ATE annular ring brake, fijacion periferica en llanta 15in (ficha §2.2)"
save(prof_new / "brakes.json", br)

fu = json.loads((prof_new / "fuel.json").read_text(encoding="utf-8"))
fu["fuel"]["capacity_kg"] = round(55 * 0.74, 2)
fu["fuel"]["initial_kg"] = 20
save(prof_new / "fuel.json", fu)

vh = json.loads((prof_new / "vehicle.json").read_text(encoding="utf-8"))
vh["vehicle_identifier"] = NEW
vh["profile_name"] = DISP + " — game-derived engineering profile"
save(prof_new / "vehicle.json", vh)
print("perfil OK")

# ---------- 4. escenas ----------
sc_src = REPO / f"game/scenes/rally/rt/{SRC}"
for suffix in ["", "_stage", "_proving"]:
    t = (sc_src.with_name(f"{SRC}{suffix}.tscn")).read_text(encoding="utf-8")
    t = t.replace(f"res://scenes/rally/rt/{SRC}.tscn", f"res://scenes/rally/rt/{NEW}.tscn")
    t = t.replace(f"res://data/vehicles/rt/{SRC}/vehicle.json", f"res://data/vehicles/rt/{NEW}/vehicle.json")
    t = t.replace(f'team_id = "{SRC}"', f'team_id = "{NEW}"')
    t = t.replace("Porsche 356A 1600GS Carrera GT", DISP)
    (REPO / f"game/scenes/rally/rt/{NEW}{suffix}.tscn").write_text(t, encoding="utf-8")
print("escenas OK (mallas/audio/colision 356A por referencia)")

# ---------- 5. registry ----------
reg_p = REPO / "game/data/vehicles/registry.json"
reg = json.loads(reg_p.read_text(encoding="utf-8"))
reg["vehicles"][NEW] = {
    "Id": NEW, "Assets": f"rt/{SRC}",
    "Profile": f"rt/{NEW}", "Scene": f"rt/{NEW}",
    "Stage": f"rt/{NEW}_stage", "Proving": f"rt/{NEW}_proving",
    "Provenance": "HISTORICAL_PROVENANCE.json", "SoundBank": SRC,
    "ValidateSoundHashes": False, "DisplayName": DISP,
    "ReuseNote": "assets/sounds/collision measured from rt-porsche-356a (identical T6); own physics profile",
}
save(reg_p, reg)
print("registry OK")

# ---------- 6. provenance + hashes ----------
prov = {
    "schema_version": 1, "vehicle_id": NEW, "policy": "game_derived",
    "source": "Rally Trophy mod INI (FTC 1966cc) + measured 356A asset geometry; sounds/meshes reused from rt-porsche-356a; not a certified historic tune",
    "mod_source": {"zip": "Porsche356Carrera2000GS_by_sharbo.zip",
                   "rtp_ftc_sha256": sha(MOD / "Porsche356bT6CoupeFTC_v30.rtp"),
                   "rtp_std_sha256": sha(MOD / "Porsche356bT6Carrera.rtp"),
                   "base_variant": "ftc (1966cc 175bhp, 4v 3.090/1.762/1.231/0.962, EndRatio 4.86)",
                   "alt_variant": "std (130bhp, 5v 5.91 arcade)",
                   "ini_files": ["car.ini", "Engine.ini", "Sounds.ini", "Tires.ini", "info.ini", "ai.ini"]},
    "reuse": {"assets": SRC, "sounds": SRC, "collision": SRC,
              "reason": "identical T6 body and measured pivots (2.100/1.306/1.272); binaries untouched"},
    "historical_reference": {
        "name": DISP, "group": "FIA Grupo 3 GT #71 (oct 1962)",
        "sources": {"ficha": {"file": "porsche_356b_carrera_2_2000gs_ficha_tecnica.md"}},
        "facts": {
            "displacement_cc": {"value": 1966, "source": "ficha", "locator": "Type 587 92x74", "status": "documented"},
            "drive": {"value": "RWD", "source": "mod_rtp", "locator": "car.ini FrontTraction=0", "status": "documented"},
            "cylinders": {"value": 4, "source": "ficha", "locator": "Type 587 boxer DOHC Konigswelle", "status": "documented"},
            "wheelbase_m": {"value": 2.10, "source": "ficha", "locator": "tabla FIA #71", "status": "documented"},
            "track_front_m": {"value": 1.306, "source": "ficha", "locator": "1.306/1.272", "status": "documented"},
            "track_rear_m": {"value": 1.272, "source": "ficha", "locator": "1.306/1.272", "status": "documented"},
            "fuel_l": {"value": 55, "source": "ficha", "locator": "masa operativa 55 L", "status": "documented"},
            "mass_kg": {"value": 890, "source": "ficha", "locator": "coupe GT aluminio, vacio", "status": "documented"},
        },
        "variant_note": "1962-65. Game base FTC (BBBD-like). Historic overrides: BBBD 3.091/1.765/1.227/0.960, final 4.428, 176 Nm/155 CV @6800 corte 7200 (mod peak 4500 vs ficha 5200 noted), ATE 282/285 sin servo, Ausgleichfeder.",
        "review": ["period rally mass and weight distribution", "competition torque curve and gearing",
                   "spring and damper rates", "differential setup"],
    },
    "engineering_estimates": ["Mass decomposition, crew, CG and inertia tensor",
        "Equivalent suspension rates and damping; no measured linkage reconstruction",
        "Fuel capacity unless explicitly overridden",
        "Aero, thermal, damage, tire force and filter template calibration"],
    "game_derived_fields": ["vehicle dry mass", "gear ratios", "final drive", "torque curve", "idle RPM",
                            "front/rear drive", "brake settings"],
}
save(prof_new / "HISTORICAL_PROVENANCE.json", prov)
hashes = {}
for f in sorted(prof_new.glob("*.json")):
    if f.name == "HISTORICAL_PROVENANCE.json":
        continue
    json.loads(f.read_text(encoding="utf-8"))
    hashes[f.name] = sha(f)
prov["profile_json_sha256"] = hashes
save(prof_new / "HISTORICAL_PROVENANCE.json", prov)
print("provenance+hashes OK")

# ---------- 7. validación ----------
errs = []
ch = json.loads((prof_new / "chassis.json").read_text(encoding="utf-8"))
nw = sum(x["properties"]["mass_kilograms"] for x in ch["physical_mass_inventory"]["components"] if not x["rotating_wheel"])
if abs(nw - ch["physical_mass_inventory"]["base_budget_kilograms"]) > 1.0:
    errs.append(f"mass closure {nw}")
pw = json.loads((prof_new / "powertrain.json").read_text(encoding="utf-8"))["powertrain"]
assert len(pw["gear_ratios"]) == 4 and pw["final_drive"] == 4.428
su = json.loads((prof_new / "suspension.json").read_text(encoding="utf-8"))["suspension"]
assert su["rear"]["axle_type"] == "swing_axle" and su["rear"]["ride_frequency_hz"] == 1.95
print("validación:", "ERRORES " + str(errs) if errs else "OK (cierre masa 1047.0, 4v BBBD, 4.428, 1.85/1.95 Hz)")
