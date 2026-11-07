"""Finalize 356B with its own measured mesh: profile tweaks, scenes, registry, validate."""
import json, sys, hashlib, shutil
from pathlib import Path
sys.path.insert(0, r"D:\rust-godot-vehicle-simulator\tools")
from rally_trophy.common import read_json
from rally_trophy.validate import validate_payload
from rally_trophy.pipeline import load_recipe

REPO = Path(r"D:\rust-godot-vehicle-simulator")
NEW, SRC = "rt-porsche-356b-2000gs", "rt-porsche-356a"
DISP = "Porsche 356B Carrera 2000 GS"
prof = REPO / f"game/data/vehicles/rt/{NEW}"
am = read_json(REPO / f"game/assets/rally/rt/{NEW}/manifest.json")
geo, piv = am["geometry"], am["wheel_pivots"]

def load(n): return json.loads((prof / n).read_text(encoding="utf-8"))
def save(n, o): (prof / n).write_text(json.dumps(o, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# 1. chassis documentary geometry -> measured B mesh
ch = load("chassis.json")
ch["geometry"] = {"wheelbase": geo["wheelbase"], "front_axle_z": geo["front_axle_z"],
                  "rear_axle_z": geo["rear_axle_z"], "front_track": geo["front_track"],
                  "rear_track": geo["rear_track"]}
save("chassis.json", ch)

# 2. tires measured (pipeline compile_profile logic)
ti = load("tires.json")
for ax in ("front", "rear"):
    p = piv[f"{ax}_left"]
    ti["tires"][ax].update(radius=p["radius_metres"], width=p["width_metres"])
save("tires.json", ti)
print("tires medidos:", round(piv["front_left"]["radius_metres"], 3), round(piv["front_left"]["width_metres"], 3))

# 3. scenes -> own asset dir, damage_parts body+interior
for suffix in ["", "_stage", "_proving"]:
    sp = REPO / f"game/scenes/rally/rt/{NEW}{suffix}.tscn"
    t = sp.read_text(encoding="utf-8")
    for old in ["chassis.glb", "damage/damage.glb", "wheel_front_left.glb", "wheel_front_right.glb",
                "wheel_rear_left.glb", "wheel_rear_right.glb", "damage/lights_damaged.png",
                "damage/windows_damaged.png", "damage/interior_windows_damaged.png"]:
        t = t.replace(f"res://assets/rally/rt/{SRC}/{old}", f"res://assets/rally/rt/{NEW}/{old}")
    t = t.replace('damage_parts = PackedStringArray("body", "hood", "trunk", "interior")',
                  'damage_parts = PackedStringArray("body", "interior")')
    sp.write_text(t, encoding="utf-8")

# 4. registry Assets -> own
reg_p = REPO / "game/data/vehicles/registry.json"
reg = json.loads(reg_p.read_text(encoding="utf-8"))
reg["vehicles"][NEW]["Assets"] = f"rt/{NEW}"
reg["vehicles"][NEW].pop("ReuseNote", None)
reg["vehicles"][NEW]["AssetNote"] = "own T6 mesh exported from sharbo mod (Blender pipeline); sounds still from rt-porsche-356a"
reg_p.write_text(json.dumps(reg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# 5. provenance hashes
prov = load("HISTORICAL_PROVENANCE.json")
hashes = {}
for f in sorted(prof.glob("*.json")):
    if f.name == "HISTORICAL_PROVENANCE.json":
        continue
    json.loads(f.read_text(encoding="utf-8"))
    hashes[f.name] = hashlib.sha256(f.read_bytes()).hexdigest()
prov["profile_json_sha256"] = hashes
prov["reuse"]["assets"] = f"{NEW} (own export)"
prov["reuse"]["reason"] = "T6 mesh exported from sharbo FTC mod via Blender pipeline; measured 2.106/1.295/1.265 m; sounds+audio bank still reused from rt-porsche-356a"
save("HISTORICAL_PROVENANCE.json", prov)

# 6. recipe reuse block update
rp = REPO / "tools/rally_trophy/recipes/rt-porsche-356b-2000gs.json"
r = json.loads(rp.read_text(encoding="utf-8"))
r["reuse"]["assets"] = NEW
r["reuse"]["reason"] = "own Blender export from FTC model.BMF (body_panels=[body], collision exterior, seats 42/44); sounds still reused from rt-porsche-356a"
rp.write_text(json.dumps(r, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# 7. validate_payload (filesystem audit, same as pipeline)
payload = REPO / "tmp/porsche_mod/payload_check"
if payload.exists():
    shutil.rmtree(payload)
game = payload / "game"
shutil.copytree(REPO / f"game/assets/rally/rt/{NEW}", game / f"assets/rally/rt/{NEW}")
recipe = load_recipe(REPO / "tools/rally_trophy/recipes/rt-porsche-356b-2000gs.json")
audit = validate_payload(payload, recipe)
print("AUDIT:", "PASSED" if audit["passed"] else ("FAILED: " + "; ".join(audit["failures"])))
print("geometry medida:", {k: round(v, 3) for k, v in geo.items()})
