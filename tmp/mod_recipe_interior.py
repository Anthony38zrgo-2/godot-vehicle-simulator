import json, pathlib
p = pathlib.Path(r"D:\rust-godot-vehicle-simulator\tools\rally_trophy\recipes\rt-porsche-356b-2000gs.json")
r = json.loads(p.read_text(encoding="utf-8"))
r["interior"] = {"seat_face_counts": [42, 44],
                 "note": "sharbo interior_lo: 44-face driver (left) + 42-face co-driver (right) buckets"}
p.write_text(json.dumps(r, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("receta interior OK")
