"""Purge stale imports, Godot --import, runtime contract, bring back fresh .imports."""
import shutil, sys
from pathlib import Path
sys.path.insert(0, r"D:\rust-godot-vehicle-simulator\tools")
from rally_trophy.common import run
from rally_trophy.pipeline import load_recipe
from rally_trophy.validate import prepare_validation_project, validate_runtime

REPO = Path(r"D:\rust-godot-vehicle-simulator")
NEW = "rt-porsche-356b-2000gs"
godot = r"C:\Users\bill\AppData\Local\Programs\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe"

# 1. purge copied .import (stale 356A uid/source_file)
bank = REPO / f"game/sounds/banks/{NEW}"
n = 0
for f in bank.rglob("*.import"):
    f.unlink(); n += 1
print("purged imports:", n)

# 2. rebuild payload from current repo state
payload = REPO / "tmp/porsche_mod/payload"
if payload.exists():
    shutil.rmtree(payload)
g = payload / "game"
for rel in [f"assets/rally/rt/{NEW}", f"data/vehicles/rt/{NEW}", f"sounds/banks/{NEW}"]:
    shutil.copytree(REPO / "game" / rel, g / rel, ignore=shutil.ignore_patterns("*.import"))
(g / "scenes/rally/rt").mkdir(parents=True, exist_ok=True)
for sfx in ["", "_stage", "_proving"]:
    shutil.copy2(REPO / f"game/scenes/rally/rt/{NEW}{sfx}.tscn", g / f"scenes/rally/rt/{NEW}{sfx}.tscn")

recipe = load_recipe(REPO / "tools/rally_trophy/recipes/rt-porsche-356b-2000gs.json")
cache = REPO / "tmp/porsche_mod/cache"
project = prepare_validation_project(REPO, cache, [(payload, recipe)])
print("project:", project)

# 3. import step exactly like pipeline batch() (600s + one retry)
for attempt, log in enumerate([cache / "godot_import.log", cache / "godot_import_retry.log"]):
    try:
        run([godot, "--headless", "--path", project, "--import"], log, timeout=600)
        break
    except RuntimeError as e:
        print("import attempt", attempt, "needs retry:", e)
else:
    raise SystemExit("import failed twice")

# 4. runtime contract
res = validate_runtime(project, godot, recipe, REPO / "tmp/porsche_mod/review")
print("RUNTIME:", "PASSED" if res["passed"] else ("FAILED: " + str(res.get("failures"))))

# 5. bring fresh .import files back to the repo (convention: committed like 356A)
for rel in [f"assets/rally/rt/{NEW}", f"sounds/banks/{NEW}"]:
    for f in (project / rel).rglob("*.import"):
        target = REPO / "game" / rel / f.relative_to(project / rel)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, target)
        print("import back:", target.relative_to(REPO))
