import hashlib
import json
import os
from pathlib import Path
import struct

REPO = Path(__file__).resolve().parent.parent


def get_sha256(path: Path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest(), path.stat().st_size


def patch_glb(glb_path: Path) -> bool:
    data = glb_path.read_bytes()
    magic, version, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, f"Not a GLB: {glb_path}"

    json_len, json_type = struct.unpack("<II", data[12:20])
    json_bytes = data[20 : 20 + json_len]
    gltf = json.loads(json_bytes.decode("utf-8"))

    bin_header_offset = 20 + json_len
    bin_len, bin_type = struct.unpack(
        "<II", data[bin_header_offset : bin_header_offset + 8]
    )
    bin_bytes = data[bin_header_offset + 8 : bin_header_offset + 8 + bin_len]

    changed = False
    for m in gltf.get("materials", []):
        m_name = m.get("name", "").lower()
        if "tire" in m_name and "alpha" in m_name:
            if m.get("alphaMode") != "MASK" or m.get("alphaCutoff") != 0.5:
                print(
                    f"  {glb_path.name}: material '{m.get('name')}' alphaMode {m.get('alphaMode')} -> MASK (0.5)"
                )
                m["alphaMode"] = "MASK"
                m["alphaCutoff"] = 0.5
                changed = True

    if not changed:
        return False

    new_json_str = json.dumps(gltf, separators=(",", ":"))
    new_json_bytes = new_json_str.encode("utf-8")
    pad = (4 - (len(new_json_bytes) % 4)) % 4
    new_json_bytes += b" " * pad

    new_total_len = 12 + 8 + len(new_json_bytes) + 8 + len(bin_bytes)
    new_header = struct.pack("<III", magic, version, new_total_len)
    new_json_chunk = (
        struct.pack("<II", len(new_json_bytes), json_type) + new_json_bytes
    )
    new_bin_chunk = struct.pack("<II", len(bin_bytes), bin_type) + bin_bytes

    glb_path.write_bytes(new_header + new_json_chunk + new_bin_chunk)
    return True


def update_manifest(manifest_path: Path):
    if not manifest_path.is_file():
        return
    d = json.loads(manifest_path.read_text(encoding="utf-8"))
    m_dir = manifest_path.parent
    wheels = d.get("wheels", {})
    updated = False
    for wk, winfo in wheels.items():
        w_path = m_dir / winfo["path"]
        if w_path.is_file():
            sha, size = get_sha256(w_path)
            if winfo.get("sha256") != sha or winfo.get("size_bytes") != size:
                print(
                    f"  Manifest {manifest_path.name} {wk}: sha {winfo.get('sha256')[:8]}.. -> {sha[:8]}.. ({size} bytes)"
                )
                winfo["sha256"] = sha
                winfo["size_bytes"] = size
                updated = True
    if updated:
        manifest_path.write_text(
            json.dumps(d, indent=2) + "\n", encoding="utf-8"
        )
        print(f"  Saved updated {manifest_path}")


def patch_blender_export():
    p = REPO / "tools/rally_trophy/blender_export.py"
    with open(p, "rb") as f:
        text = f.read().decode("utf-8")
    old_code = (
        '        alpha = "window" in material.name.lower() or "tire_alpha" in material.name.lower()\r\n'
        '        if alpha:\r\n'
        '            links.new(tex.outputs["Alpha"], shader.inputs["Alpha"])\r\n'
        '            shader.inputs["Roughness"].default_value = 0.18'
    )
    new_code = (
        '        is_tire_alpha = "tire_alpha" in material.name.lower() or "tire alpha" in material.name.lower()\r\n'
        '        alpha = "window" in material.name.lower() or is_tire_alpha\r\n'
        '        if alpha:\r\n'
        '            links.new(tex.outputs["Alpha"], shader.inputs["Alpha"])\r\n'
        '            shader.inputs["Roughness"].default_value = 0.18\r\n'
        '            if is_tire_alpha:\r\n'
        '                material.blend_method = "CLIP"\r\n'
        '                material.alpha_threshold = 0.5'
    )
    if old_code in text:
        text = text.replace(old_code, new_code)
        with open(p, "wb") as f:
            f.write(text.encode("utf-8"))
        print(f"Patched {p}")


def main():
    print("=== Patching Wheel GLBs (alphaMode: MASK) ===")

    # Search in both game/assets/rally/rt and cache
    roots = [
        REPO / "game/assets/rally/rt",
        REPO / "tmp/porsche_mod/cache/validation_project/assets/rally/rt",
    ]

    affected_vehicles = set()

    for root in roots:
        if not root.is_dir():
            continue
        for vdir in sorted(root.glob("rt-*")):
            for glb in sorted(vdir.glob("wheel_*.glb")):
                if patch_glb(glb):
                    affected_vehicles.add(vdir.name)

    print(
        f"\n=== Updating Manifests for {len(affected_vehicles)} vehicles ==="
    )
    for vid in sorted(affected_vehicles):
        m1 = REPO / "game/assets/rally/rt" / vid / "manifest.json"
        update_manifest(m1)
        m2 = (
            REPO
            / "tmp/porsche_mod/cache/validation_project/assets/rally/rt"
            / vid
            / "manifest.json"
        )
        update_manifest(m2)

    patch_blender_export()
    print("\nWheel alpha patch complete.")


if __name__ == "__main__":
    main()
