# Actualiza profile_json_sha256 en HISTORICAL_PROVENANCE.json (equivale al .ps1).
import hashlib, json, pathlib
roots = [pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\rt")]
dirs = sorted([d for r in roots for d in r.iterdir() if d.is_dir()])
dirs.append(pathlib.Path(r"D:\rust-godot-vehicle-simulator\game\data\vehicles\lancia-fulvia"))
for d in dirs:
    prov_p = d / "HISTORICAL_PROVENANCE.json"
    veh_p = d / "vehicle.json"
    if not prov_p.exists() or not veh_p.exists():
        print("skip", d); continue
    prov = json.loads(prov_p.read_text(encoding="utf-8"))
    veh = json.loads(veh_p.read_text(encoding="utf-8"))
    names = set(prov.get("profile_json_sha256", {}).keys())
    for v in veh.get("domains", {}).values():
        names.add(str(v))
    names.add("vehicle.json")
    hashes = {}
    for n in sorted(names):
        p = d / n
        assert p.is_file(), (d, n)
        json.loads(p.read_text(encoding="utf-8"))  # valida JSON
        hashes[n] = hashlib.sha256(p.read_bytes()).hexdigest()
    prov["profile_json_sha256"] = hashes
    prov_p.write_text(json.dumps(prov, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("hashes", d.name, len(hashes))
