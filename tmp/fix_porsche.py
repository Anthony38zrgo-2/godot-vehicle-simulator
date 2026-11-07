import json, pathlib
d = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\rt\rt-porsche-356a")
ch = json.loads((d / "chassis.json").read_text(encoding="utf-8"))
byname = {x["properties"]["name"]: x for x in ch["physical_mass_inventory"]["components"]}
byname["body_and_systems"]["properties"]["mass_kilograms"] = 581.0
ch["physical_mass_inventory"]["base_budget_kilograms"] = 915.0
(d / "chassis.json").write_text(json.dumps(ch, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("porsche fixed")
