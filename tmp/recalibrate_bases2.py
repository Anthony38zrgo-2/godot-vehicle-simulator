# Bases: aplicar powertrain/suspension/steering/brakes con mismo esquema que RT.
import json, math, pathlib
BASES = {
    "lancia-fulvia": pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\lancia-fulvia"),
    "ford-escort-rs2000": pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\ford-escort-rs2000"),
}
BASE_CFG = {
 "lancia-fulvia":      dict(tq=172, maxrpm=7500, idle=900, gears=[2.749,2.035,1.565,1.260,1.00], final=4.78, gravel=4.78, tarmac=4.10, preset="gravel", primary=1.0, fw=False, preload=25, pramp=55, cramp=85, lockP=35, lockC=0, muP=0.10, muC=0.03, clutch=4, bump=0.095, droop=0.075, camF=-2.0, camR=-0.5, axleF="transverse_leaf_wishbone", axleR="live_axle_leaf", jackR=0.0, strapR=99.0, leafF=True, leafRate=20000.0, panhardR=0.0, rcF=0.05, rcR=0.10, turns=2.9, ratio=16.5, servo=(True,1.0), bias=0.60, maxBrake=5000),
 "ford-escort-rs2000": dict(tq=205, maxrpm=7300, idle=900, gears=[2.54,1.66,1.26,1.00], final=4.63, gravel=4.63, tarmac=3.77, preset="gravel", primary=1.0, fw=False, preload=55, pramp=40, cramp=55, lockP=50, lockC=35, muP=0.12, muC=0.10, clutch=4, bump=0.125, droop=0.095, camF=-1.5, camR=-0.5, axleF="macpherson", axleR="live_axle_4link_panhard", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=40000.0, rcF=0.06, rcR=0.12, turns=2.4, ratio=14.0, servo=(True,1.0), bias=0.55, maxBrake=5500),
}
def load(d, name):
    return json.loads((d / name).read_text(encoding="utf-8"))
def save(d, name, obj):
    (d / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
for vid, c in BASE_CFG.items():
    d = BASES[vid]
    pw = load(d, "powertrain.json"); p = pw["powertrain"]
    p["max_torque"] = float(c["tq"]); p["max_rpm"] = float(c["maxrpm"]); p["idle_rpm"] = float(c["idle"])
    p["gear_ratios"] = [float(x) for x in c["gears"]]
    p["final_drive"] = float(c["final"])
    p["final_drive_gravel"] = float(c["gravel"]); p["final_drive_tarmac"] = float(c["tarmac"])
    p["final_drive_preset"] = c["preset"]
    p.pop("primary_reduction", None); p.pop("drop_gears", None); p.pop("freewheel", None)
    df = p["differential"]
    df["preload_nm"] = float(c["preload"]); df["power_ramp_angle_deg"] = float(c["pramp"]); df["coast_ramp_angle_deg"] = float(c["cramp"])
    df["lock_pct_power"] = float(c["lockP"]); df["lock_pct_coast"] = float(c["lockC"])
    df["clutch_friction_coefficient"] = float(c["muP"]); df["coast_friction_coefficient"] = float(c["muC"])
    df["clutches"] = float(c["clutch"])
    save(d, "powertrain.json", pw)
    su = load(d, "suspension.json"); s = su["suspension"]
    for ax in ("front", "rear"):
        trim = s[ax]
        trim["axle_type"] = c["axleF"] if ax == "front" else c["axleR"]
        trim["camber"] = math.radians(float(c["camF"] if ax == "front" else c["camR"]))
        if ax == "rear":
            trim["jacking_coeff"] = float(c["jackR"]); trim["droop_strap_m"] = float(c["strapR"]); trim["roll_center_height_m"] = float(c["rcR"])
            if float(c["panhardR"]) > 0: trim["panhard_stiffness_n_per_m"] = float(c["panhardR"])
        else:
            trim["roll_center_height_m"] = float(c["rcF"])
            if c["leafF"]:
                trim["transverse_leaf"] = True; trim["leaf_symmetric_rate_n_per_m"] = float(c["leafRate"])
    gp = s["geometry_physical"]
    for ax in ("front", "rear"):
        gp[ax]["wheel_bump_m"] = float(c["bump"]); gp[ax]["wheel_droop_m"] = float(c["droop"])
    save(d, "suspension.json", su)
    st = load(d, "steering.json")
    st["steering"]["turns_lock_to_lock"] = float(c["turns"]); st["steering"]["ratio_to_one"] = float(c["ratio"])
    save(d, "steering.json", st)
    br = load(d, "brakes.json"); bbr = br["brakes"]
    en, gain = c["servo"]
    bbr["servo_assist"] = {"enabled": bool(en), "gain": float(gain)}
    bbr["front_brake_bias"] = float(c["bias"]); bbr["max_brake_torque"] = float(c["maxBrake"])
    save(d, "brakes.json", br)
    print("ok", vid)
