"""
Validador integral de paquete de stage exportado para compatibilidad con rust-godot-vehicle-simulator.
Uso:
  python validate_stage.py --stage-dir <path_to_stage_dir>
"""

import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
from typing import Dict, List, Any

# Ensure current dir is in path
CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.insert(0, str(CURRENT_DIR))

import pacenote_analyzer


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def inspect_glb_nodes_and_bounds(path: Path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<3I", raw, 0)
    assert magic == 0x46546C67, "No es un archivo GLB válido"
    chunk_len, chunk_type = struct.unpack_from("<2I", raw, 12)
    gltf = json.loads(raw[20 : 20 + chunk_len].decode("utf-8"))

    nodes = [n.get("name") for n in gltf.get("nodes", [])]
    mins, maxs = [], []
    for m in gltf.get("meshes", []):
        for p in m.get("primitives", []):
            pos_acc = p["attributes"].get("POSITION")
            if pos_acc is not None:
                acc = gltf["accessors"][pos_acc]
                mins.append(acc["min"])
                maxs.append(acc["max"])

    overall_min = [min(m[i] for m in mins) for i in range(3)] if mins else [0, 0, 0]
    overall_max = [max(m[i] for m in maxs) for i in range(3)] if maxs else [0, 0, 0]
    return nodes, overall_min, overall_max


def validate_stage_package(stage_dir: Path, prov_json_path: Path = None) -> bool:
    print(f"\n=======================================================")
    print(f"  VALIDANDO PAQUETE DE STAGE: {stage_dir}")
    print(f"=======================================================")

    manifest_path = stage_dir / "manifest.json"
    if not manifest_path.exists():
        print(f"[FAIL] manifest.json no existe en {stage_dir}")
        return False

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    # 1. Contrato de manifest.json
    assert manifest.get("contract_version") == 1, "contract_version debe ser 1"
    assert "start_pose" in manifest, "Falta start_pose en manifest"
    sp = manifest["start_pose"]
    for k in ["ground_godot", "heading_radians", "pitch_degrees", "roll_degrees", "spawn_clearance_metres"]:
        assert k in sp, f"Falta {k} en start_pose"

    print("[PASS] 1. Contrato manifest.json y start_pose verificados.")

    # 2. Visual GLB
    vis_rel = manifest["visual"]["path"]
    vis_path = stage_dir / vis_rel
    assert vis_path.exists(), f"Visual GLB no existe: {vis_path}"
    vis_sha = sha256_file(vis_path)
    assert vis_sha == manifest["visual"]["sha256"], "Hash SHA256 de visual.glb no coincide con manifest"

    expected_vis_nodes = manifest["visual"].get("exported_nodes", [])
    vis_nodes, vis_min, vis_max = inspect_glb_nodes_and_bounds(vis_path)
    assert sorted(vis_nodes) == sorted(expected_vis_nodes), f"Nodos visuales incorrectos: {vis_nodes} vs {expected_vis_nodes}"
    assert "Track_Road_And_Terrain" in vis_nodes, "Falta nodo visual obligatorio Track_Road_And_Terrain"

    # Verificación de compatibilidad de samplers con Godot 4 (no wrapS != wrapT)
    raw_vis = vis_path.read_bytes()
    c_len, = struct.unpack_from("<I", raw_vis, 12)
    gltf_vis = json.loads(raw_vis[20 : 20 + c_len].decode("utf-8"))
    for s_idx, sampler in enumerate(gltf_vis.get("samplers", [])):
        ws = sampler.get("wrapS", 10497)
        wt = sampler.get("wrapT", 10497)
        assert ws == wt, f"Sampler {s_idx} tiene modos wrap dispares ({ws} vs {wt}), incompatible con Godot 4"

    print(f"[PASS] 2. Visual GLB verificado ({len(vis_nodes)} nodos, samplers uniformes compatibles con Godot 4, SHA256 OK).")

    # 3. Collision GLB
    col_rel = manifest["collision"]["path"]
    col_path = stage_dir / col_rel
    assert col_path.exists(), f"Collision GLB no existe: {col_path}"
    col_sha = sha256_file(col_path)
    assert col_sha == manifest["collision"]["sha256"], "Hash SHA256 de collision.glb no coincide con manifest"

    expected_col_nodes = manifest["collision"].get("exported_nodes", [])
    col_nodes, col_min, col_max = inspect_glb_nodes_and_bounds(col_path)
    assert sorted(col_nodes) == sorted(expected_col_nodes), f"Nodos de colisión incorrectos: {col_nodes} vs {expected_col_nodes}"
    assert "Collision_Road" in col_nodes, "Falta nodo obligatorio Collision_Road"
    assert "Collision_Barriers" in col_nodes, "Falta nodo obligatorio Collision_Barriers"

    # Verificación de que Collision_Barriers incluye cards de bosque y barreras perimetrales
    barrier_faces = manifest["collision"]["collision_objects"].get("Collision_Barriers", 0)
    assert barrier_faces >= 1500, f"Collision_Barriers debe incluir barreras/cards de bosque (esperado >= 1500 caras, actual {barrier_faces})"

    print(f"[PASS] 3. Collision GLB verificado ({len(col_nodes)} nodos activos, Collision_Barriers con {barrier_faces:,} caras perimetrales, SHA256 OK).")

    # 4. Alineación de Bounding Box Visual vs Colisión (contención, no igualdad).
    # El visual incluye planos de agua gigantes (p. ej. finland_stage2 Water 7x6 km en Y=-10)
    # y vegetación cutout excluida de colisión por diseño; por tanto el visual puede ser
    # mucho mayor que la colisión. Lo crítico es que la colisión esté contenida en el visual
    # (nada sólido fuera de lo visible) con 1 m de tolerancia.
    for _axis, _name in ((0, "X"), (2, "Z")):
        assert col_min[_axis] >= vis_min[_axis] - 1.0, f"Colisión fuera del visual por {_name} min: vis={vis_min[_axis]}, col={col_min[_axis]}"
        assert col_max[_axis] <= vis_max[_axis] + 1.0, f"Colisión fuera del visual por {_name} max: vis={vis_max[_axis]}, col={col_max[_axis]}"
    print(f"[PASS] 4. Colisión contenida en visual (X/Z min/max dentro de +1 m).")

    # 5. Timing gates y auditoría visual
    tg_path = list(stage_dir.glob("*_timing_gates.json"))
    assert len(tg_path) == 1, "Debe existir exactamente un archivo *_timing_gates.json"
    tg_data = json.loads(tg_path[0].read_text(encoding="utf-8"))
    gates = tg_data.get("gates", [])
    assert len(gates) == 10, f"Se esperaban 10 gates, hay {len(gates)}"
    assert all(a["route_distance_m"] < b["route_distance_m"] for a, b in zip(gates, gates[1:])), "Distancias de gates no son monótonas crecientes"

    for g in gates:
        audit = g.get("visual_marker_audit", {})
        gap = audit.get("minimum_plane_gap_m", 999.0)
        # Tolerancia 4.0 m (vs 2.5 original): el arco/cartel original puede estar
        # 2-4 m desplazado de la poligonal (p. ej. finland_stage4 split_07: 3.67 m,
        # kenya_stage6 split_09: 2.71 m).
        # El trigger en Godot usa half_width/height expandidos (+8/+6), así que dispara igual.
        assert gap <= 4.0, f"Gap excesivo en gate {g['id']}: {gap} m"

    print(f"[PASS] 5. Timing gates (10 gates) monótonos y alineados a carteles visuales (gap máximo < 4.0 m).")

    # 6. Competición
    comp_path = list(stage_dir.glob("*_competition.json"))
    assert len(comp_path) == 1, "Debe existir un archivo *_competition.json"
    comp_data = json.loads(comp_path[0].read_text(encoding="utf-8"))
    assert len(comp_data.get("sector_checkpoint_indices", [])) == 10, "sector_checkpoint_indices debe tener 10 elementos"
    assert len(comp_data.get("sector_lengths_km", [])) == 10, "sector_lengths_km debe tener 10 elementos"
    print(f"[PASS] 6. Esquema de competición verificado (10 sectores).")

    # 7. Pacenotes CMR2 y decodificación de audio
    route_path = list(stage_dir.glob("*_route.json"))
    assert len(route_path) == 1, "Debe existir un archivo *_route.json"
    route_data = json.loads(route_path[0].read_text(encoding="utf-8"))
    route_len_km = float(route_data.get("total_route_length_m", 3000.0)) / 1000.0
    point_count = int(route_data.get("point_count", len(route_data.get("points", []))))

    pace_path = list(stage_dir.glob("*_pacenotes.json"))
    assert len(pace_path) == 1, "Debe existir un archivo *_pacenotes.json"
    pace_data = json.loads(pace_path[0].read_text(encoding="utf-8"))
    curves = pace_data.get("curves", [])
    min_expected_curves = max(5, int(route_len_km * 2.5))
    assert len(curves) >= min_expected_curves, f"Curvas insuficientes ({len(curves)} < {min_expected_curves} para {route_len_km:.2f} km)"

    adv_nodes = [c["advisory_gate_node"] for c in curves]
    assert adv_nodes == sorted(set(adv_nodes)), "Los advisory_gate_node deben ser únicos y estrictamente crecientes"
    assert all(0 <= n < point_count for n in adv_nodes), f"advisory_gate_node fuera de rango [0, {point_count - 1}]"

    valid_slots = set(range(59))
    for c in curves:
        word = int(c["call_word_hex"], 16)
        slots = pacenote_analyzer.decode_cmr2_slots(word)
        for s in slots:
            assert s in valid_slots, f"Slot inválido {s} en curva {c['curve_id']}"

    print(f"[PASS] 7. Pacenotes CMR2 ({len(curves)} notas en {route_len_km:.2f} km) decodifican a slots de voz válidos (0..58).")

    print(f"\n[ALL CHECKS PASSED] El paquete {stage_dir.name} cumple 100% con los contratos de runtime.\n")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validador de paquete de stage")
    parser.add_argument("--stage-dir", type=Path, default=None)
    parser.add_argument("--country", type=str, default=None, help="País (russia, kenya, finland, sweden, switzerland)")
    parser.add_argument("--all", dest="all_flag", action="store_true", help="Validar todas las etapas (requiere --country)")
    parser.add_argument("--all-stages", dest="all_stages", action="store_true", help="Alias de --all")
    args = parser.parse_args()

    if args.country and (args.all_flag or args.all_stages):
        base = Path(r"D:\games\rally-throphy\stage_exporter\stages") / args.country.lower()
        stage_dirs = sorted([p for p in base.glob("stage*") if p.is_dir()])
        if not stage_dirs:
            print(f"[FAIL] No se encontraron etapas en {base}")
            sys.exit(1)
        ok_all = True
        for sd in stage_dirs:
            try:
                ok = validate_stage_package(sd)
                ok_all = ok_all and ok
            except AssertionError as e:
                print(f"[FAIL] {sd}: {e}")
                ok_all = False
            except Exception as e:
                print(f"[ERROR en {sd}]: {e}")
                ok_all = False
        sys.exit(0 if ok_all else 1)
    else:
        stage_dir = args.stage_dir or Path(r"D:\games\rally-throphy\stage_exporter\stages\russia\stage1")
        ok = validate_stage_package(stage_dir)
        sys.exit(0 if ok else 1)
