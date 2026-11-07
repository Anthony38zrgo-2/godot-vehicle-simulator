"""Bisect 356B suspension: apply one variant, caller tests, restore."""
import json, pathlib, shutil, sys

P = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\rt\rt-porsche-356b-2000gs\suspension.json")
BAK = P.with_suffix(".json.bak")

variant = sys.argv[1] if len(sys.argv) > 1 else "show"

if variant == "restore":
    shutil.copy2(BAK, P)
    print("restored")
    sys.exit(0)

if not BAK.exists():
    shutil.copy2(P, BAK)
doc = json.loads(BAK.read_text(encoding="utf-8"))
s = doc["suspension"]

if variant == "travel":
    # historico dossier 100/75 -> modelo usa bump como umbral de tope
    for ax in ("front", "rear"):
        s["geometry_physical"][ax]["wheel_bump_m"] = 0.22
        s["geometry_physical"][ax]["wheel_droop_m"] = 0.18
elif variant == "noleaf":
    s["rear"].pop("transverse_leaf", None)
    s["rear"].pop("leaf_symmetric_rate_n_per_m", None)
    s["rear"].pop("leaf_note", None)
elif variant == "nojack":
    for k in ("jacking_coeff", "droop_strap_m", "roll_center_height_m"):
        s["rear"].pop(k, None)
        s["front"].pop(k, None)
elif variant == "arb":
    s["geometry_physical"]["rear_arb"]["ratio"] = 0.08
elif variant == "freq":
    s["front"]["ride_frequency_hz"] = 1.7
    s["rear"]["ride_frequency_hz"] = 1.8
elif variant == "all":
    for ax in ("front", "rear"):
        s["geometry_physical"][ax]["wheel_bump_m"] = 0.22
        s["geometry_physical"][ax]["wheel_droop_m"] = 0.18
    s["rear"].pop("transverse_leaf", None)
    s["rear"].pop("leaf_symmetric_rate_n_per_m", None)
    s["rear"].pop("leaf_note", None)
    for k in ("jacking_coeff", "droop_strap_m", "roll_center_height_m"):
        s["rear"].pop(k, None)
    s["front"].pop("roll_center_height_m", None)
    s["geometry_physical"]["rear_arb"]["ratio"] = 0.08
    s["front"]["ride_frequency_hz"] = 1.7
    s["rear"]["ride_frequency_hz"] = 1.8

P.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("applied", variant)
