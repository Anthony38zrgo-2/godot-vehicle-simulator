# Recalibración histórica 1974 — masa CON tripulación (base_budget excluye
# combustible y ruedas, incluye cunas/uprights 20 kg + tripulación 150 kg).
# Dossier: C:\Users\bill\Downloads\dossier_historico_rally_1974_rbr_ngp.md §1-2.
# Convención inercias dossier: Ixx Pitch / Iyy Roll / Izz Yaw -> Godot x=pitch,
# y=yaw, z=roll => Ix=d.Ixx, Iy=d.Izz, Iz=d.Iyy (cuerpo lleva 85%).
import json, math, pathlib

RT = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\rt")
BASES = {
    "lancia-fulvia": pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\lancia-fulvia"),
    "ford-escort-rs2000": pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\ford-escort-rs2000"),
}

CFG = {
 # id: base_con_trip, fdist, cgz_mm, wb, ft, rt, tq, maxrpm, idle, gears, final, gravel, tarmac, preset, primary, fw, preload, pramp, cramp, lockP, lockC, muP, muC, clutch, bump, droop, camF_deg, camR_deg, axleF, axleR, jackR, strapR, leafF, leafRate, panhardR, rcF, rcR, turns, ratio, servo(bool/gain), bias, maxBrake, Ixx, Iyy, Izz
 "rt-alfa-giulia-gta":        dict(base=895,  fdist=0.50, cgz=470, wb=2.350, ft=1.325, rt=1.285, tq=168, maxrpm=7500, idle=1000, gears=[2.54,1.70,1.26,1.00,0.85], final=4.78, gravel=4.78, tarmac=4.55, preset="gravel", primary=1.0, fw=False, preload=40, pramp=45, cramp=65, lockP=45, lockC=25, muP=0.11, muC=0.08, clutch=4, bump=0.090, droop=0.075, camF=-1.2, camR=-0.5, axleF="double_wishbone", axleR="live_axle_leaf", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=0.0, rcF=0.07, rcR=0.02, turns=3.0, ratio=16.8, servo=(True,1.0), bias=0.55, maxBrake=5000, Ixx=1190, Iyy=305, Izz=1230),
 "rt-alpine-a110":             dict(base=855,  fdist=0.36, cgz=425, wb=2.100, ft=1.358, rt=1.337, tq=190, maxrpm=7200, idle=1000, gears=[3.07,2.25,1.68,1.30,1.03], final=4.125, gravel=4.125, tarmac=3.78, preset="gravel", primary=1.0, fw=False, preload=45, pramp=45, cramp=55, lockP=45, lockC=30, muP=0.11, muC=0.09, clutch=4, bump=0.090, droop=0.065, camF=-1.2, camR=-3.7, axleF="double_wishbone", axleR="swing_axle", jackR=0.35, strapR=0.065, leafF=False, leafRate=0.0, panhardR=0.0, rcF=0.06, rcR=0.10, turns=2.5, ratio=13.5, servo=(True,1.0), bias=0.55, maxBrake=5500, Ixx=920, Iyy=245, Izz=950),
 "rt-escort-rs2000":           dict(base=965,  fdist=0.52, cgz=485, wb=2.410, ft=1.370, rt=1.395, tq=220, maxrpm=8700, idle=1100, gears=[2.99,1.76,1.31,1.14,1.00], final=5.14, gravel=5.14, tarmac=4.11, preset="gravel", primary=1.0, fw=False, preload=70, pramp=30, cramp=45, lockP=65, lockC=45, muP=0.14, muC=0.12, clutch=4, bump=0.135, droop=0.100, camF=-1.5, camR=-0.5, axleF="macpherson", axleR="live_axle_4link_panhard", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=40000.0, rcF=0.06, rcR=0.12, turns=2.2, ratio=13.2, servo=(True,1.0), bias=0.55, maxBrake=5500, Ixx=1260, Iyy=335, Izz=1310, note="RS1600 BDA Gr.4"),
 "rt-fiat-abarth-1000":        dict(base=775,  fdist=0.40, cgz=445, wb=2.000, ft=1.210, rt=1.220, tq=104, maxrpm=8000, idle=1100, gears=[3.09,2.05,1.48,1.14,0.92], final=4.62, gravel=4.62, tarmac=4.11, preset="gravel", primary=1.0, fw=False, preload=30, pramp=50, cramp=70, lockP=40, lockC=20, muP=0.10, muC=0.07, clutch=4, bump=0.075, droop=0.055, camF=-1.5, camR=-2.3, axleF="double_wishbone", axleR="swing_axle", jackR=0.25, strapR=0.055, leafF=False, leafRate=0.0, panhardR=0.0, rcF=0.06, rcR=0.10, turns=2.6, ratio=14.5, servo=(True,1.0), bias=0.55, maxBrake=4500, Ixx=710, Iyy=210, Izz=740, aero_wing=True),
 "rt-lancia-fulvia":           dict(base=930,  fdist=0.61, cgz=475, wb=2.330, ft=1.390, rt=1.335, tq=172, maxrpm=7500, idle=900, gears=[2.749,2.035,1.565,1.260,1.00], final=4.78, gravel=4.78, tarmac=4.10, preset="gravel", primary=1.0, fw=False, preload=25, pramp=55, cramp=85, lockP=35, lockC=0, muP=0.10, muC=0.03, clutch=4, bump=0.095, droop=0.075, camF=-2.75, camR=-0.5, axleF="transverse_leaf_wishbone", axleR="live_axle_leaf", jackR=0.0, strapR=99.0, leafF=True, leafRate=20000.0, panhardR=0.0, rcF=0.05, rcR=0.10, turns=2.9, ratio=16.5, servo=(True,1.0), bias=0.60, maxBrake=5000, Ixx=1180, Iyy=310, Izz=1210, eng_z=-0.85, body_z=-0.10),
 "rt-lancia-stratos":          dict(base=1040, fdist=0.41, cgz=430, wb=2.180, ft=1.430, rt=1.460, tq=270, maxrpm=7700, idle=1000, gears=[3.14,2.24,1.76,1.42,1.15], final=3.824, gravel=3.824, tarmac=3.421, preset="gravel", primary=1.10, fw=False, preload=50, pramp=45, cramp=65, lockP=40, lockC=25, muP=0.10, muC=0.08, clutch=4, bump=0.115, droop=0.090, camF=-1.2, camR=-1.0, axleF="double_wishbone", axleR="macpherson", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=0.0, rcF=0.06, rcR=0.09, turns=3.3, ratio=17.0, servo=(False,0.82), bias=0.55, maxBrake=6000, Ixx=940, Iyy=330, Izz=980, eng_z=0.47, body_z=0.12, manual_prop=True),
 "rt-lotus-cortina":           dict(base=1065, fdist=0.52, cgz=510, wb=2.565, ft=1.310, rt=1.295, tq=165, maxrpm=6500, idle=900, gears=[2.50,1.64,1.23,1.00], final=4.44, gravel=4.44, tarmac=3.90, preset="gravel", primary=1.0, fw=False, preload=45, pramp=45, cramp=65, lockP=45, lockC=25, muP=0.11, muC=0.08, clutch=4, bump=0.110, droop=0.085, camF=-1.2, camR=-0.5, axleF="macpherson", axleR="live_axle_leaf", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=0.0, rcF=0.07, rcR=0.11, turns=2.7, ratio=15.0, servo=(True,1.0), bias=0.55, maxBrake=4500, Ixx=1280, Iyy=320, Izz=1330),
 "rt-mini-cooper-s":           dict(base=765,  fdist=0.61, cgz=440, wb=2.036, ft=1.235, rt=1.210, tq=132, maxrpm=7000, idle=900, gears=[2.573,1.722,1.255,1.00], final=4.33, gravel=4.33, tarmac=3.93, preset="gravel", primary=1.0, fw=False, preload=20, pramp=55, cramp=80, lockP=35, lockC=10, muP=0.09, muC=0.05, clutch=4, bump=0.065, droop=0.045, camF=-1.7, camR=-1.2, axleF="double_wishbone", axleR="trailing_arm", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=0.0, rcF=0.06, rcR=0.09, turns=2.3, ratio=13.0, servo=(True,1.0), bias=0.58, maxBrake=4000, Ixx=680, Iyy=215, Izz=710, eng_z=-0.55, body_z=-0.12),
 "rt-opel-kadett":             dict(base=960,  fdist=0.52, cgz=515, wb=2.416, ft=1.320, rt=1.325, tq=200, maxrpm=6800, idle=900, gears=[2.99,1.76,1.30,1.00], final=4.75, gravel=4.75, tarmac=4.22, preset="gravel", primary=1.0, fw=False, preload=60, pramp=32, cramp=50, lockP=60, lockC=40, muP=0.13, muC=0.11, clutch=4, bump=0.115, droop=0.090, camF=-1.2, camR=-0.5, axleF="transverse_leaf_wishbone", axleR="live_axle_4link_panhard", jackR=0.0, strapR=99.0, leafF=True, leafRate=25000.0, panhardR=35000.0, rcF=0.05, rcR=0.12, turns=3.0, ratio=16.5, servo=(True,1.0), bias=0.55, maxBrake=4500, Ixx=1390, Iyy=345, Izz=1440),
 "rt-porsche-356a":            dict(base=915,  fdist=0.41, cgz=455, wb=2.100, ft=1.306, rt=1.272, tq=145, maxrpm=7000, idle=900, gears=[3.09,1.76,1.23,0.96], final=4.428, gravel=4.428, tarmac=4.428, preset="", primary=1.0, fw=False, preload=35, pramp=55, cramp=65, lockP=35, lockC=25, muP=0.10, muC=0.08, clutch=4, bump=0.095, droop=0.070, camF=-1.2, camR=-2.6, axleF="trailing_arm", axleR="swing_axle", jackR=0.25, strapR=0.070, leafF=False, leafRate=0.0, panhardR=0.0, rcF=0.06, rcR=0.10, turns=2.4, ratio=14.5, servo=(True,1.0), bias=0.55, maxBrake=4200, Ixx=1080, Iyy=275, Izz=1120, eng_z=0.55, body_z=0.10),
 "rt-saab-96-v4":              dict(base=962,  fdist=0.61, cgz=525, wb=2.498, ft=1.270, rt=1.270, tq=195, maxrpm=6400, idle=1000, gears=[2.64,1.60,1.19,0.92], final=5.83, gravel=5.83, tarmac=5.14, preset="gravel", primary=1.0, fw=True, preload=25, pramp=55, cramp=85, lockP=35, lockC=0, muP=0.10, muC=0.03, clutch=4, bump=0.130, droop=0.100, camF=-1.2, camR=-0.5, axleF="double_wishbone", axleR="live_axle_leaf", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=0.0, rcF=0.07, rcR=0.11, turns=2.25, ratio=14.0, servo=(True,1.0), bias=0.60, maxBrake=4500, Ixx=1340, Iyy=330, Izz=1380, eng_z=-0.60, body_z=-0.10),
 "rt-volvo-amazon":            dict(base=1250, fdist=0.52, cgz=545, wb=2.600, ft=1.330, rt=1.330, tq=172, maxrpm=6000, idle=800, gears=[2.54,1.67,1.26,1.00], final=4.88, gravel=4.88, tarmac=4.56, preset="gravel", primary=1.0, fw=False, preload=55, pramp=45, cramp=55, lockP=45, lockC=30, muP=0.11, muC=0.09, clutch=4, bump=0.135, droop=0.105, camF=-1.2, camR=-0.5, axleF="double_wishbone", axleR="live_axle_leaf", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=0.0, rcF=0.07, rcR=0.11, turns=3.2, ratio=17.5, servo=(True,1.0), bias=0.55, maxBrake=5800, Ixx=1780, Iyy=420, Izz=1850),
}

BASE_CFG = {
 "lancia-fulvia":              dict(base=930,  fdist=0.61, cgz=475, wb=2.330, ft=1.390, rt=1.335, tq=172, maxrpm=7500, idle=900, gears=[2.749,2.035,1.565,1.260,1.00], final=4.78, gravel=4.78, tarmac=4.10, preset="gravel", primary=1.0, fw=False, preload=25, pramp=55, cramp=85, lockP=35, lockC=0, muP=0.10, muC=0.03, clutch=4, bump=0.095, droop=0.075, camF=-2.0, camR=-0.5, axleF="transverse_leaf_wishbone", axleR="live_axle_leaf", jackR=0.0, strapR=99.0, leafF=True, leafRate=20000.0, panhardR=0.0, rcF=0.05, rcR=0.10, turns=2.9, ratio=16.5, servo=(True,1.0), bias=0.60, maxBrake=5000, Ixx=1180, Iyy=310, Izz=1210, eng_z=-0.85, body_z=-0.10),
 "ford-escort-rs2000":         dict(base=1015, fdist=0.52, cgz=505, wb=2.410, ft=1.320, rt=1.340, tq=205, maxrpm=7300, idle=900, gears=[2.54,1.66,1.26,1.00], final=4.63, gravel=4.63, tarmac=3.77, preset="gravel", primary=1.0, fw=False, preload=55, pramp=40, cramp=55, lockP=50, lockC=35, muP=0.12, muC=0.10, clutch=4, bump=0.125, droop=0.095, camF=-1.5, camR=-0.5, axleF="macpherson", axleR="live_axle_4link_panhard", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=40000.0, rcF=0.06, rcR=0.12, turns=2.4, ratio=14.0, servo=(True,1.0), bias=0.55, maxBrake=5500, Ixx=1360, Iyy=350, Izz=1410),
}

def load(d, name):
    return json.loads((d / name).read_text(encoding="utf-8"))

def save(d, name, obj):
    (d / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

def tune_profile(d, c):
    # ---- chassis ----
    ch = load(d, "chassis.json")
    ch["chassis"]["vehicle_mass"] = float(c["base"])
    ch["chassis"]["front_weight_distribution"] = float(c["fdist"])
    ch["chassis"]["target_cg_z_m"] = float(c["cgz"]) / 1000.0
    # documentary geometry (true wheelbase lives in 3D asset pivots)
    wb = float(c["wb"]); ft = float(c["ft"]); rt_ = float(c["rt"])
    ch["geometry"]["wheelbase"] = wb
    ch["geometry"]["front_track"] = ft
    ch["geometry"]["rear_track"] = rt_
    ch["geometry"]["front_axle_z"] = -wb / 2.0
    ch["geometry"]["rear_axle_z"] = wb / 2.0
    inv = ch["physical_mass_inventory"]
    inv["base_budget_kilograms"] = float(c["base"])
    comps = inv["components"]
    byname = {x["properties"]["name"]: x for x in comps}
    eng_m = float(byname["engine_and_transaxle"]["properties"]["mass_kilograms"])
    spare_m = float(byname["spare_wheels_and_tools"]["properties"]["mass_kilograms"])
    body_m = float(c["base"]) - eng_m - 75.0 - 75.0 - spare_m - 20.0
    assert body_m > 200, (d, body_m)
    b = byname["body_and_systems"]["properties"]
    b["mass_kilograms"] = round(body_m, 1)
    # body inertia: dossier (Ix=pitch, Iy=yaw, Iz=roll) * 0.85
    ix = round(float(c["Ixx"]) * 0.85, 1); iy = round(float(c["Izz"]) * 0.85, 1); iz = round(float(c["Iyy"]) * 0.85, 1)
    b["inertia_about_center_of_mass"] = {"entries_kilogram_square_metres": [[ix,0,0],[0,iy,0],[0,0,iz]]}
    b["provenance"] = {"source": "Dossier 1974 §2.1 con tripulacion (cuerpo 85% inercia total; resto componentes + ejes paralelos)", "mass_origin": "recalibrated_1974", "center_of_mass_origin": "recalibrated_1974", "inertia_origin": "recalibrated_1974"}
    cgz = float(c["cgz"]) / 1000.0
    bz = float(c.get("body_z", 0.02)); ez = float(c.get("eng_z", -0.30 if c["fdist"] >= 0.5 else 0.40))
    b["center_of_mass_in_attachment_metres"] = {"x": 0, "y": round(cgz, 3), "z": round(bz, 3)}
    e = byname["engine_and_transaxle"]["properties"]
    e["center_of_mass_in_attachment_metres"] = {"x": 0, "y": round(cgz - 0.05, 3), "z": round(ez, 3)}
    for k in ("driver_and_seat", "codriver_and_seat"):
        byname[k]["properties"]["center_of_mass_in_attachment_metres"] = {"x": byname[k]["properties"]["center_of_mass_in_attachment_metres"]["x"], "y": round(cgz + 0.12, 3), "z": 0.05}
    byname["spare_wheels_and_tools"]["properties"]["center_of_mass_in_attachment_metres"] = {"x": 0, "y": round(cgz - 0.02, 3), "z": round(-bz, 3)}
    save(d, "chassis.json", ch)

    # ---- powertrain ----
    pw = load(d, "powertrain.json")
    p = pw["powertrain"]
    p["max_torque"] = float(c["tq"]); p["max_rpm"] = float(c["maxrpm"]); p["idle_rpm"] = float(c["idle"])
    p["gear_ratios"] = [float(x) for x in c["gears"]]
    p["final_drive"] = float(c["final"])
    p["final_drive_gravel"] = float(c["gravel"]); p["final_drive_tarmac"] = float(c["tarmac"])
    if c["preset"]: p["final_drive_preset"] = c["preset"]
    elif "final_drive_preset" in p: del p["final_drive_preset"]
    if abs(float(c["primary"]) - 1.0) > 1e-9:
        p["primary_reduction"] = float(c["primary"])
        p["drop_gears"] = {"ratio": float(c["primary"]), "note": "Stratos 33/30 = 1.10, cambio en asistencia 15 min"}
    else:
        p.pop("primary_reduction", None); p.pop("drop_gears", None)
    if c["fw"]:
        p["freewheel"] = {"enabled": True, "idle_rpm": 1000.0, "reengage_margin_rad_s": 1.5, "note": "Saab rueda libre: 0% retencion, re-enganche instantaneo"}
    else:
        p.pop("freewheel", None)
    df = p["differential"]
    df["preload_nm"] = float(c["preload"]); df["power_ramp_angle_deg"] = float(c["pramp"]); df["coast_ramp_angle_deg"] = float(c["cramp"])
    df["lock_pct_power"] = float(c["lockP"]); df["lock_pct_coast"] = float(c["lockC"])
    df["clutch_friction_coefficient"] = float(c["muP"]); df["coast_friction_coefficient"] = float(c["muC"])
    df["clutches"] = float(c["clutch"])
    save(d, "powertrain.json", pw)

    # ---- suspension ----
    su = load(d, "suspension.json")
    s = su["suspension"]
    for ax, key in (("front", "F"), ("rear", "R")):
        trim = s[ax]
        trim["axle_type"] = c["axleF"] if ax == "front" else c["axleR"]
        trim["camber"] = math.radians(float(c["camF"] if ax == "front" else c["camR"]))
        if ax == "rear":
            trim["jacking_coeff"] = float(c["jackR"])
            trim["droop_strap_m"] = float(c["strapR"])
            trim["roll_center_height_m"] = float(c["rcR"])
            if float(c["panhardR"]) > 0: trim["panhard_stiffness_n_per_m"] = float(c["panhardR"])
            else: trim.pop("panhard_stiffness_n_per_m", None)
        else:
            trim["roll_center_height_m"] = float(c["rcF"])
            if c["leafF"]:
                trim["transverse_leaf"] = True
                trim["leaf_symmetric_rate_n_per_m"] = float(c["leafRate"])
            else:
                trim.pop("transverse_leaf", None); trim.pop("leaf_symmetric_rate_n_per_m", None)
            if ax == "front" and "jacking_coeff" in trim: del trim["jacking_coeff"]
    gp = s["geometry_physical"]
    for ax in ("front", "rear"):
        g = gp[ax]
        g["wheel_bump_m"] = float(c["bump"]); g["wheel_droop_m"] = float(c["droop"])
        if ax == "rear" and float(c["strapR"]) < 90.0:
            g["wheel_droop_m"] = min(float(c["droop"]), float(c["strapR"]))
    save(d, "suspension.json", su)

    # ---- steering ----
    st = load(d, "steering.json")
    st["steering"]["turns_lock_to_lock"] = float(c["turns"])
    st["steering"]["ratio_to_one"] = float(c["ratio"])
    save(d, "steering.json", st)

    # ---- brakes ----
    br = load(d, "brakes.json")
    bbr = br["brakes"]
    en, gain = c["servo"]
    bbr["servo_assist"] = {"enabled": bool(en), "gain": float(gain)}
    if c.get("manual_prop"): bbr["manual_proportioning"] = True
    else: bbr.pop("manual_proportioning", None)
    bbr["front_brake_bias"] = float(c["bias"])
    bbr["max_brake_torque"] = float(c["maxBrake"])
    save(d, "brakes.json", br)

    # ---- aero (Abarth capó-spoiler) ----
    if c.get("aero_wing"):
        ae = load(d, "aerodynamics.json")
        rw = ae["aero"]["model"]["rear_wing"]
        rw["area_m2"] = 0.28; rw["incidence_deg"] = 10.0
        rw["min_angle_deg"] = 0.0; rw["max_angle_deg"] = 15.0
        rw["polar"] = [{"angle_deg": 0.0, "cd": 0.02, "cl": 0.05}, {"angle_deg": 10.0, "cd": 0.08, "cl": 0.30}, {"angle_deg": 15.0, "cd": 0.12, "cl": 0.38}]
        rw["position_m"] = [0.0, 0.55, 1.55]
        save(d, "aerodynamics.json", ae)

    # ---- thermal/damage fragilidad (P2, sin código nuevo) ----
    try:
        th = load(d, "powertrain.json")  # thermal vive en powertrain.json
        t = th["powertrain"]["thermal"]
        if d.name == "rt-alpine-a110":
            t["water_critical_temperature_celsius"] = 108.0
            t["water_hot_derating_temperature_celsius"] = 98.0
            t["water_optimal_maximum_temperature_celsius"] = 90.0
            save(d, "powertrain.json", th)
        elif d.name == "rt-lancia-stratos":
            pass
    except Exception as ex:
        print("thermal skip", d, ex)
    try:
        dm = load(d, "damage.json")
        wc = dm.get("wheel_collision", {})
        if d.name in ("rt-lancia-stratos", "rt-alpine-a110") and "alignment_start_speed_m_s" in wc:
            wc["alignment_start_speed_m_s"] = round(float(wc["alignment_start_speed_m_s"]) * 0.85, 2)
            wc["alignment_full_speed_m_s"] = round(float(wc["alignment_full_speed_m_s"]) * 0.85, 2)
            save(d, "damage.json", dm)
    except Exception as ex:
        print("damage skip", d, ex)

done = []
for vid, c in CFG.items():
    tune_profile(RT / vid, c); done.append(vid)
print("RECALIBRADOS:", len(done))
for v in done: print(" -", v)
