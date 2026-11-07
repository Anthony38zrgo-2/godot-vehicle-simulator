"""Run the real Blender export for the mod mesh (outside BZF batch)."""
import json, sys
from pathlib import Path
sys.path.insert(0, r"D:\rust-godot-vehicle-simulator\tools")
from rally_trophy.archives import find_data
from rally_trophy.common import read_json, write_json, sha, run, code_hash
from rally_trophy.config_parser import parse_config, vector
from rally_trophy.pipeline import prepare_driver, load_recipe

REPO = Path(r"D:\rust-godot-vehicle-simulator")
WORK = REPO / "tmp/porsche_mod/build"
SRC = WORK / "source"
ASSET = REPO / "game/assets/rally/rt/rt-porsche-356b-2000gs"

recipe = load_recipe(REPO / "tools/rally_trophy/recipes/rt-porsche-356b-2000gs.json")
data = find_data(r"D:\games\rally-throphy")
toolchain = {
    "blender": r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe",
    "converter": r"D:\games\rally-throphy\FlatOutW32BGMTool\FlatOutW32BGMTool_gcp.exe",
}
driver = prepare_driver(data, 2, WORK / "cache", toolchain, code_hash())
print("driver OK:", driver)

ext = REPO / "tmp/porsche_mod/extracted/ftc"
configs = {n: parse_config((ext / n).read_bytes()) for n in ["info.ini", "car.ini", "Engine.ini", "Sounds.ini", "Tires.ini"]}
car = configs["car.ini"]["values"]
for key in ["DriverLoc", "CoDriverLoc", "InteriorLoc"]:
    vector(car, key)
write_json(WORK / "source_configs.json", configs)

provenance = {"mod": "Porsche356bT6CoupeFTC_v30.rtp", "generator": "tools/rally_trophy (manual mod job)",
              "pipeline_code_sha256": code_hash(), "recipe": recipe,
              "note": "FTC mesh by sharbo+bugbear; driver2 from game Drivers/driver2.bzf"}
job = {"source_dir": str(SRC), "driver_dir": str(driver), "asset_dir": str(ASSET),
       "report_path": str(WORK / "component_report.json"), "recipe": recipe,
       "car_config": car, "provenance": provenance}
write_json(WORK / "job.json", job)
run([toolchain["blender"], "--background", "--factory-startup", "--python",
     REPO / "tools/rally_trophy/blender_export.py", "--", WORK / "job.json"],
    WORK / "blender.log", timeout=300, require_marker="RT_EXPORT_SUCCESS rt-porsche-356b-2000gs")
print("EXPORT OK")
