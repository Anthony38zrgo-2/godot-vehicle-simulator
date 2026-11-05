from __future__ import annotations

import shutil
import struct
import subprocess
from pathlib import Path


def adapt_arm_batches(data):
    """Convert known native BATCH arm frames to the converter's BATCH2 layout."""
    output, offset, count = bytearray(), 0, 0
    while True:
        index = data.find(b"BATCH\0", offset)
        if index < 0:
            output.extend(data[offset:])
            break
        output.extend(data[offset:index])
        material, vertices, faces = struct.unpack_from("<3I", data, index + 6)
        start = index + 18
        end = start + vertices * 44 + faces * 8
        if end > len(data) or vertices > 65535:
            raise ValueError("Invalid native arm BATCH bounds")
        output.extend(b"BATCH2\0" + struct.pack("<3I", material, vertices, faces))
        for vertex in range(vertices):
            output.extend(data[start + vertex * 44:start + vertex * 44 + 36])
        start += vertices * 44
        for face in range(faces):
            triangle = struct.unpack_from("<4H", data, start + face * 8)
            if triangle[3] or max(triangle[:3]) >= vertices:
                raise ValueError("Unexpected native arm triangle format")
            output.extend(struct.pack("<3H", *triangle[:3]))
        offset, count = end, count + 1
    if not count:
        raise ValueError("No native arm frames found")
    return bytes(output)


def convert_model(binary, model, workspace):
    """Isolate the converter's executable directory and shared log/output side effects."""
    binary, model, workspace = Path(binary), Path(model), Path(workspace)
    workspace.mkdir(parents=True, exist_ok=True)
    local = workspace / binary.name
    if not local.exists():
        for item in binary.parent.iterdir():
            if item.is_file() and item.suffix.lower() in {".exe", ".dll", ".ini", ".cfg"}:
                shutil.copy2(item, workspace / item.name)
    result = subprocess.run([str(local.resolve()), str(model.resolve()), "-export_fbx", "-text_materials"],
        input="\n", text=True, encoding="utf-8", errors="replace", stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, cwd=workspace, timeout=180)
    log = model.with_name(model.stem + "_conversion.log")
    log.write_text(result.stdout, encoding="utf-8")
    output = model.with_name(model.stem + "_out.fbx")
    if result.returncode or not output.is_file() or output.stat().st_size < 100 or "Model export finished" not in result.stdout:
        raise RuntimeError(f"BMF conversion failed: {log}")
    return output
