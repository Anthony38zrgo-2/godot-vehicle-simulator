"""
Parser de modelos 3D y escenarios .BMF de Rally Trophy.
Extrae materiales, texturas, chunks de terreno (TRACK) y jerarquía de objetos (HIERARCHY/MESH).
Identifica gates de cronometraje (split_00..09, start, gate_finish).
"""

import io
import struct
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any


def read_cstring(f: io.BytesIO) -> str:
    chars = []
    while True:
        b = f.read(1)
        if not b or b == b"\x00":
            break
        chars.append(b)
    return b"".join(chars).decode("latin1", errors="replace")


class BMFStage:
    def __init__(self):
        self.materials: List[Dict[str, Any]] = []
        self.track_chunks: List[Dict[str, Any]] = []
        self.hierarchy_meshes: List[Dict[str, Any]] = []
        self.timing_gates: List[Dict[str, Any]] = []
        self.track_header: Optional[Tuple] = None
        self.bounding_box: List[List[float]] = [[1e9, -1e9], [1e9, -1e9], [1e9, -1e9]]


def parse_bmf(raw_or_path) -> BMFStage:
    if isinstance(raw_or_path, (str, Path)):
        with open(raw_or_path, "rb") as f:
            data = f.read()
    elif isinstance(raw_or_path, bytes):
        data = raw_or_path
    else:
        data = raw_or_path.read()

    stage = BMFStage()
    f = io.BytesIO(data)

    head = f.read(4)
    if head == b"(c) ":
        read_cstring(f)
        filesize = struct.unpack("<I", f.read(4))[0]
    else:
        filesize = struct.unpack("<I", head)[0]

    in_hierarchy = False
    cur_mesh: Optional[Dict[str, Any]] = None

    while f.tell() < len(data):
        token = read_cstring(f)
        if not token:
            break

        if token in ("MAIN", "INFO"):
            f.read(4)
        elif token == "BMF":
            read_cstring(f)  # exporter string
            f.read(4)
        elif token == "MATERIALLIST":
            f.read(8)
        elif token == "MATERIAL":
            ints1 = struct.unpack("<5i", f.read(20))
            flts = struct.unpack("<16f", f.read(64))
            ints2 = struct.unpack("<2i", f.read(8))
            mat_name = read_cstring(f)
            tex0 = read_cstring(f)
            tex1 = read_cstring(f)
            tex2 = read_cstring(f)
            f.read(4)  # trailer

            shader_id = ints1[2]
            flags = ints2[0]

            clamp_u = bool(flags & 0x0004)
            clamp_v = bool(flags & 0x0008)
            two_sided = bool(flags & 0x2000) or ("twoside" in mat_name.lower())

            stage.materials.append({
                "index": len(stage.materials),
                "name": mat_name,
                "shader_id": shader_id,
                "flags": flags,
                "clamp_u": clamp_u,
                "clamp_v": clamp_v,
                "two_sided": two_sided,
                "tex0": tex0,
                "tex1": tex1,
                "tex2": tex2,
                "diffuse_rgba": (flts[0], flts[1], flts[2], flts[3]),
                "ambient_rgba": (flts[4], flts[5], flts[6], flts[7]),
                "specular_rgba": (flts[8], flts[9], flts[10], flts[11]),
            })
        elif token == "TRACK":
            stage.track_header = struct.unpack("<11i", f.read(44))
        elif token == "HIERARCHY":
            in_hierarchy = True
            f.read(8)
            read_cstring(f)  # SCENE
            read_cstring(f)  # scene name
            f.read(4 + 64 + 0x50 + 4)
        elif token == "MESH":
            mesh_name = read_cstring(f)
            tmp = struct.unpack("<I", f.read(4))[0]
            matrix = struct.unpack("<16f", f.read(64))
            pos_extra = struct.unpack("<3f", f.read(12))
            rest = f.read(14 * 4 + 8)

            cur_mesh = {
                "name": mesh_name,
                "tmp": tmp,
                "matrix": matrix,
                "pos_extra": pos_extra,
                "models": [],
            }
            stage.hierarchy_meshes.append(cur_mesh)
        elif token == "MODEL":
            m_hdr = struct.unpack("<I3f3f4fI", f.read(4 + 12 + 12 + 16 + 4))
            batches = []
            while True:
                pos_before = f.tell()
                st = read_cstring(f)
                if st != "BATCH2":
                    f.seek(pos_before)
                    break
                hdr = f.read(12)
                mat_id, v_cnt, p_cnt = struct.unpack("<3I", hdr)
                v_raw = f.read(v_cnt * 36)
                i_raw = f.read(p_cnt * 6)
                f.read(4)  # trailer

                verts = []
                norms = []
                colors = []
                uvs = []
                for vi in range(v_cnt):
                    x, y, z, nx, ny, nz, col, u, v = struct.unpack("<3f3fI2f", v_raw[vi * 36 : (vi + 1) * 36])
                    verts.append((x, y, z))
                    norms.append((nx, ny, nz))
                    # col es 0xAARRGGBB en DirectX
                    b_col = (col & 0xFF) / 255.0
                    g_col = ((col >> 8) & 0xFF) / 255.0
                    r_col = ((col >> 16) & 0xFF) / 255.0
                    a_col = ((col >> 24) & 0xFF) / 255.0
                    colors.append((r_col, g_col, b_col, a_col))
                    uvs.append((u, v))

                raw_indices = struct.unpack(f"<{p_cnt * 3}H", i_raw)
                faces = []
                for pi in range(p_cnt):
                    i0, i1, i2 = raw_indices[pi * 3], raw_indices[pi * 3 + 1], raw_indices[pi * 3 + 2]
                    faces.append((i0, i1, i2))

                batches.append({
                    "mat_id": mat_id,
                    "verts": verts,
                    "norms": norms,
                    "colors": colors,
                    "uvs": uvs,
                    "faces": faces,
                })

            model_data = {"header": m_hdr, "batches": batches}
            if not in_hierarchy:
                stage.track_chunks.append(model_data)
            else:
                if cur_mesh is not None:
                    cur_mesh["models"].append(model_data)
        elif token == "LIGHT":
            read_cstring(f)
            f.read(0xC6 - 6)
        elif token == "CAMERA2":
            read_cstring(f)
            f.read(0xA5 - 9)
        else:
            f.read(4)

    # Identificar y extraer timing gates
    for m in stage.hierarchy_meshes:
        name_lower = m["name"].lower()
        is_split = name_lower.startswith("split_")
        is_start = name_lower.startswith("start")
        is_finish = "finish" in name_lower
        uses_null = any(
            b["mat_id"] < len(stage.materials) and stage.materials[b["mat_id"]]["name"].lower().startswith("nul")
            for model in m["models"]
            for b in model["batches"]
        )

        if is_split or (is_finish and uses_null) or (is_start and uses_null):
            m["is_timing_trigger"] = True
            stage.timing_gates.append(m)
        else:
            m["is_timing_trigger"] = False

    return stage
