# Bases detalladas: solo documentales + powertrain/susp/steer/brakes + lastre.
import json, math, pathlib
RT = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\rt")
BASES = {
    "lancia-fulvia": pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\lancia-fulvia"),
    "ford-escort-rs2000": pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\ford-escort-rs2000"),
}
BASE_CFG = {
 "lancia-fulvia":      dict(base=930,  fdist=0.61, cgz=475, wb=2.330, ft=1.390, rt=1.335, tq=172, maxrpm=7500, idle=900, gears=[2.749,2.035,1.565,1.260,1.00], final=4.78, gravel=4.78, tarmac=4.10, preset="gravel", primary=1.0, fw=False, preload=25, pramp=55, cramp=85, lockP=35, lockC=0, muP=0.10, muC=0.03, clutch=4, bump=0.095, droop=0.075, camF=-2.0, camR=-0.5, axleF="transverse_leaf_wishbone", axleR="live_axle_leaf", jackR=0.0, strapR=99.0, leafF=True, leafRate=20000.0, panhardR=0.0, rcF=0.05, rcR=0.10, turns=2.9, ratio=16.5, servo=(True,1.0), bias=0.60, maxBrake=5000),
 "ford-escort-rs2000": dict(base=1015, fdist=0.52, cgz=505, wb=2.410, ft=1.320, rt=1.340, tq=205, maxrpm=7300, idle=900, gears=[2.54,1.66,1.26,1.00], final=4.63, gravel=4.63, tarmac=3.77, preset="gravel", primary=1.0, fw=False, preload=55, pramp=40, cramp=55, lockP=50, lockC=35, muP=0.12, muC=0.10, clutch=4, bump=0.125, droop=0.095, camF=-1.5, camR=-0.5, axleF="macpherson", axleR="live_axle_4link_panhard", jackR=0.0, strapR=99.0, leafF=False, leafRate=0.0, panhardR=40000.0, rcF=0.06, rcR=0.12, turns=2.4, ratio=14.0, servo=(True,1.0), bias=0.55, maxBrake=5500),
}
def load(d, name):
    return json.loads((d / name).read_text(encoding="utf-8"))
def save(d, name, obj):
    (d / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
for vid, c in BASE_CFG.items():
    d = BASES[vid]
    ch = load(d, "chassis.json")
    ch["chassis"]["vehicle_mass"] = float(c["base"])
    ch["chassis"]["front_weight_distribution"] = float(c["fdist"])
    ch["chassis"]["target_cg_z_m"] = float(c["cgz"]) / 1000.0
    wb = float(c["wb"])
    ch["geometry"]["wheelbase"] = wb
    ch["geometry"]["front_track"] = float(c["ft"])
    ch["geometry"]["rear_track"] = float(c["rt"])
    ch["geometry"]["front_axle_z"] = -wb / 2.0
    ch["geometry"]["rear_axle_z"] = wb / 2.0
    inv = ch["physical_mass_inventory"]
    cur = float(inv["base_budget_kilograms"])
    delta = float(c["base"]) - cur
    byname = {x["properties"]["name"]: x for x in inv["components"]}
    b = byname["bodywork_and_cage"]["properties"]
    old_m = float(b["mass_kilograms"])
    b["mass_kilograms"] = round(old_m + delta, 1)
    try:
        ent = b["inertia_about_center_of_mass"]["entries_kilogram_square_metres"]
        f = (old_m + delta) / max(old_m, 1.0)
        b["inertia_about_center_of_mass"] = {"entries_kilogram_square_metres": [[round(ent[0][0]*f,1),0,0],[0,round(ent[1][1]*f,1),0],[0,0,round(ent[2][2]*f,1)]]}
    except Exception as ex:
        print("inertia skip", vid, ex)
    inv["base_budget_kilograms"] = float(c["base"])
    save(d, "chassis.json", ch)
    pw = load(d, "powertrain.json")
    # base fulvia/escort tienen esquema powertrain distinto: actualizar por claves si existen
    txt = json.dumps(pw)
    print("== ", vid, "powertrain keys:", list(pw.keys()))
    save(d, "chassis.json", ch)
print("bases chassis OK")
