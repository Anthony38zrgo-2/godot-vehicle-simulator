"""Own bank from byte-identical 356A recordings + scene/registry rewiring + full runtime validation."""
import json, sys
from pathlib import Path
sys.path.insert(0, r"D:\rust-godot-vehicle-simulator\tools")
from rally_trophy.common import read_json, write_json
from rally_trophy.pipeline import load_recipe
from rally_trophy.validate import prepare_validation_project, validate_runtime

REPO = Path(r"D:\rust-godot-vehicle-simulator")
NEW, SRC = "rt-porsche-356b-2000gs", "rt-porsche-356a"

# 1. bank manifest: own id, same recordings
mp = REPO / f"game/sounds/banks/{NEW}/manifest.json"
m = json.loads(mp.read_text(encoding="utf-8"))
m["vehicle_id"] = NEW
m["source"] = {"reused_from": SRC, "note": "Byte-identical Konigswelle-era flat recordings from rt-porsche-356a; mod KittX WAVs archived for a future 2000GS bank refresh"}
txt = mp.read_text(encoding="utf-8").replace(
    f"res://sounds/banks/{SRC}/", f"res://sounds/banks/{NEW}/")
mp.write_text(txt, encoding="utf-8")
m = json.loads(mp.read_text(encoding="utf-8"))
m["vehicle_id"] = NEW
m["source"] = {"reused_from": SRC, "note": "Byte-identical recordings from rt-porsche-356a; mod KittX WAVs archived for a future 2000GS bank refresh"}
mp.write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("bank OK")

# 2. vehicle scene -> own bank
sp = REPO / f"game/scenes/rally/rt/{NEW}.tscn"
t = sp.read_text(encoding="utf-8")
t = t.replace(f"res://sounds/banks/{SRC}/manifest.json", f"res://sounds/banks/{NEW}/manifest.json")
sp.write_text(t, encoding="utf-8")

# 3. registry -> own bank, validated hashes
reg_p = REPO / "game/data/vehicles/registry.json"
reg = json.loads(reg_p.read_text(encoding="utf-8"))
reg["vehicles"][NEW]["SoundBank"] = NEW
reg["vehicles"][NEW]["ValidateSoundHashes"] = True
reg_p.write_text(json.dumps(reg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# 4. recipe reuse note
rp = REPO / "tools/rally_trophy/recipes/rt-porsche-356b-2000gs.json"
r = json.loads(rp.read_text(encoding="utf-8"))
r["reuse"]["sounds"] = NEW
r["reuse"]["sound_note"] = "own bank dir with byte-identical 356A recordings (contract requires own bank path); mod WAVs archived"
rp.write_text(json.dumps(r, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# 5. payload mirroring install() layout
payload = REPO / "tmp/porsche_mod/payload"
import shutil
if payload.exists():
    shutil.rmtree(payload)
g = payload / "game"
for rel in [f"assets/rally/rt/{NEW}", f"data/vehicles/rt/{NEW}", f"sounds/banks/{NEW}"]:
    shutil.copytree(REPO / "game" / rel, g / rel)
for sfx in ["", "_stage", "_proving"]:
    (g / "scenes/rally/rt").mkdir(parents=True, exist_ok=True)
    shutil.copy2(REPO / f"game/scenes/rally/rt/{NEW}{sfx}.tscn", g / f"scenes/rally/rt/{NEW}{sfx}.tscn")
print("payload OK")

# 6. filesystem audit (assets + profile hashes + audio hashes)
from rally_trophy.validate import validate_payload
recipe = load_recipe(REPO / "tools/rally_trophy/recipes/rt-porsche-356b-2000gs.json")
audit = validate_payload(payload, recipe)
print("AUDIT:", "PASSED" if audit["passed"] else ("FAILED: " + "; ".join(audit["failures"])))
print("samples:", audit.get("sample_count"), "geo:", {k: round(v, 3) for k, v in audit.get("geometry", {}).items()})

# 7. headless Godot runtime contract (import + drive the B model)
project = prepare_validation_project(REPO, REPO / "tmp/porsche_mod/cache", [(payload, recipe)])
print("validation project:", project)
godot = r"C:\Users\bill\AppData\Local\Programs\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe"
res = validate_runtime(project, godot, recipe, REPO / "tmp/porsche_mod/review")
print("RUNTIME:", "PASSED" if res["passed"] else ("FAILED: " + str(res.get("failures"))))
