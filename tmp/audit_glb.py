import json, struct, pathlib
base = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\assets\rally\rt\rt-porsche-356b-2000gs")
ref = pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\assets\rally\rt\rt-porsche-356a")

def inspect(p, label):
    b = p.read_bytes()
    magic, ver, total = struct.unpack_from("<4sII", b, 0)
    cnt, kind = struct.unpack_from("<II", b, 12)
    doc = json.loads(b[20:20+cnt])
    imgs = doc.get("images", [])
    uris = []
    for i in imgs:
        uris.append(i.get("uri", "<embedded>"))
    print(f"--- {label} ---")
    print(f"  magic={magic} version={ver} file_len={len(b)} header_total={total} match={total==len(b)}")
    print(f"  nodes={len(doc.get('nodes',[]))} meshes={len(doc.get('meshes',[]))} materials={len(doc.get('materials',[]))} images={len(imgs)}")
    print(f"  image uris: {uris[:8]}")
    ext = [u for u in uris if u != "<embedded>"]
    if ext:
        print(f"  !! EXTERNAL TEXTURE REFS: {ext[:5]}")
    names = [n.get("name","?") for n in doc.get("nodes",[])]
    print(f"  node names: {names[:30]}")
    return doc

b = inspect(base / "chassis.glb", "356B chassis")
print()
a = inspect(ref / "chassis.glb", "356A chassis")
print()
inspect(base / "damage/damage.glb", "356B damage")
print()
inspect(ref / "damage/damage.glb", "356A damage")
print()
for w in ["wheel_front_left", "wheel_front_right", "wheel_rear_left", "wheel_rear_right"]:
    docb = inspect(base / f"{w}.glb", f"356B {w}")
    print()

# required nodes for the contract / scene
required = ["body", "interior", "interior_hi", "CockpitEye", "steering_wheel_hi",
            "Driver_driver_head", "DriverArm_left_frame09", "DriverArm_right_frame09"]
bnames = {n.get("name","") for n in b.get("nodes", [])}
print("REQUIRED NODES EN 356B CHASSIS:")
for r in required:
    print(f"  {'OK ' if r in bnames else 'MISSING'} {r}")
