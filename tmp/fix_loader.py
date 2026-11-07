import pathlib
q = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\scripts\physics\profile_loader.gd")
u = q.read_text(encoding="utf-8")
u = u.replace(
    'if powertrain.has("final_drive_preset") and not str(powertrain.get("final_drive_preset", "")) in ["", "gravel", "tarmac"]:',
    'if powertrain.has("final_drive_preset") and not (str(powertrain.get("final_drive_preset", "")) in ["", "gravel", "tarmac"]):',
)
u = u.replace("if not atype in allowed:", "if not (atype in allowed):")
q.write_text(u, encoding="utf-8")
print("ok")
