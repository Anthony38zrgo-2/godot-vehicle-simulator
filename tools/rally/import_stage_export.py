"""Importador universal de etapas exportadas de Rally Trophy a rust-godot-vehicle-simulator.

Uso:
  # Importar una etapa específica:
  python tools/rally/import_stage_export.py --source D:/games/rally-throphy/stage_exporter/stages/russia/stage1

  # Importar todas las etapas exportadas de todos los países:
  python tools/rally/import_stage_export.py --all --source D:/games/rally-throphy/stage_exporter/stages

  # Opcional: --skip-backup para importaciones masivas limpias
"""

import argparse
import copy
import hashlib
import json
import os
import shutil
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
from pacenote_runtime import convert_notes

ROOT = Path(__file__).resolve().parents[2]


def ensure_visual_import_settings(path: Path) -> None:
    """Keep adjacent terrain chunks at source precision, as in Stage 1."""
    config = Path(str(path) + ".import")
    if config.exists():
        text = config.read_text(encoding="utf-8")
        if re.search(r"^meshes/force_disable_compression=", text, re.M):
            text = re.sub(r"^meshes/force_disable_compression=.*$",
                          "meshes/force_disable_compression=true", text, flags=re.M)
        else:
            text = text.replace("[params]", "[params]\nmeshes/force_disable_compression=true", 1)
    else:
        text = '[remap]\nimporter="scene"\ntype="PackedScene"\n\n[params]\nmeshes/force_disable_compression=true\n'
    config.write_text(text, encoding="utf-8")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def adapt_notes(active: Dict[str, Any], exported: Dict[str, Any]) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    """Si ya existe un archivo de notas con gates calibradas, adapta las curvas exportadas conservando los nodos."""
    result = copy.deepcopy(active)
    curves = sorted(exported.get("curves", []), key=lambda c: c.get("call_index", 0))
    if not curves:
        return exported, []

    words = [int(c["call_word_hex"], 16) for c in curves]
    nodes = [c.get("advisory_gate_node", 0) for c in curves]
    changes = []

    if "gates" in active and isinstance(active["gates"], list) and len(active["gates"]) > max(nodes):
        old_nodes = {g.get("call_index"): i for i, g in enumerate(active["gates"]) if g.get("call_index") is not None}
        for gate in result["gates"]:
            gate["call_index"] = None
        for curve, word, node in zip(curves, words, nodes):
            index = curve["call_index"]
            result["gates"][node]["call_index"] = index
            changes.append({
                "call_index": index,
                "curve_id": curve["curve_id"],
                "previous_word": active["calls"][index] if "calls" in active and index < len(active["calls"]) else None,
                "word": word,
                "previous_gate": old_nodes.get(index),
                "gate": node,
                "evidence": curve.get("evidence", [])
            })
        result["calls"] = words
        return result, changes
    else:
        return exported, []


def import_single_stage(stage_source_dir: Path, backup_dir: Optional[Path] = None) -> Dict[str, Any]:
    manifest_path = stage_source_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"manifest.json no encontrado en {stage_source_dir}")

    manifest = read_json(manifest_path)
    track_id = manifest.get("track_id")
    if not track_id:
        raise ValueError(f"Falta 'track_id' en {manifest_path}")

    # 1. Definir destinos en la estructura de rust-godot-vehicle-simulator
    assets_dir = ROOT / "game" / "assets" / "rally" / track_id
    routes_dir = ROOT / "game" / "data" / "rally"
    competition_dir = ROOT / "game" / "data" / "competition" / "stages"
    pacenotes_dir = ROOT / "game" / "data" / "rally" / "pacenotes"
    docs_pacenotes_dir = ROOT / "game" / "docs" / "rally" / "pacenotes"
    docs_metadata_dir = ROOT / "game" / "docs" / "rally" / "metadata"

    for d in [assets_dir, routes_dir, competition_dir, pacenotes_dir, docs_pacenotes_dir, docs_metadata_dir]:
        d.mkdir(parents=True, exist_ok=True)

    # 2. Verificar y preparar copias de modelos GLB
    files_to_copy = []
    for kind in ("visual", "collision"):
        item = manifest.get(kind)
        if not item:
            continue
        filename = item["path"]
        src = stage_source_dir / filename
        if not src.exists():
            raise FileNotFoundError(f"Archivo {kind} no existe: {src}")
        actual_sha = sha256_file(src)
        if actual_sha != item["sha256"]:
            raise ValueError(f"Hash SHA256 corrupto en {src}: esperado {item['sha256']}, actual {actual_sha}")
        dst = assets_dir / filename
        files_to_copy.append((src, dst))

    # Actualizar ruta absoluta del .blend en el manifest destino
    blend_rel = manifest.get("source", {}).get("blend", "")
    if blend_rel:
        src_blend = stage_source_dir / blend_rel
        if src_blend.exists():
            manifest["source"]["blend"] = str(src_blend)
    manifest["source"]["import_source_manifest_sha256"] = sha256_file(manifest_path)

    # 3. Preparar archivos de datos y documentación
    writes = {
        assets_dir / "manifest.json": manifest
    }

    # Trayectoria (route.json)
    src_route = stage_source_dir / f"{track_id}_route.json"
    dst_route = routes_dir / f"{track_id}_route.json"
    if src_route.exists():
        files_to_copy.append((src_route, dst_route))

    # Timing Gates
    src_tg = stage_source_dir / f"{track_id}_timing_gates.json"
    dst_tg = competition_dir / f"{track_id}_timing_gates.json"
    if src_tg.exists():
        files_to_copy.append((src_tg, dst_tg))

    # Competición (competition.json -> track_id.json)
    src_comp = stage_source_dir / f"{track_id}_competition.json"
    dst_comp = competition_dir / f"{track_id}.json"
    if src_comp.exists():
        files_to_copy.append((src_comp, dst_comp))

    # Pacenotes
    src_pace = stage_source_dir / f"{track_id}_pacenotes.json"
    dst_pace = pacenotes_dir / f"{track_id}.json"
    if src_pace.exists():
        pace_data = read_json(src_pace)
        if pace_data.get("curves"):
            route_data = read_json(stage_source_dir / f"{track_id}_route.json")
            writes[docs_pacenotes_dir / f"{track_id}_authoring.json"] = pace_data
            writes[dst_pace] = convert_notes(pace_data, route_data, track_id)
        elif dst_pace.exists():
            active_notes = read_json(dst_pace)
            adapted, changes = adapt_notes(active_notes, pace_data)
            adapted["source"] = {
                "export": str(stage_source_dir),
                "authoring_sha256": sha256_file(stage_source_dir / f"{track_id}_pacenotes_authoring.json") if (stage_source_dir / f"{track_id}_pacenotes_authoring.json").exists() else ""
            }
            writes[dst_pace] = adapted
        else:
            writes[dst_pace] = pace_data

    # Documentación de pacenotes (Authoring y Candidates)
    src_auth = stage_source_dir / f"{track_id}_pacenotes_authoring.json"
    dst_auth = docs_pacenotes_dir / f"{track_id}_authoring.json"
    if src_auth.exists():
        writes[dst_auth] = read_json(src_auth)

    src_cand = stage_source_dir / f"{track_id}_pacenotes_candidates.json"
    dst_cand = docs_pacenotes_dir / f"{track_id}_candidates.json"
    if src_cand.exists():
        writes[dst_cand] = read_json(src_cand)

    # Metadatos originales
    src_meta = stage_source_dir / f"{track_id}_original_metadata.json"
    dst_meta = docs_metadata_dir / f"{track_id}_original_metadata.json"
    if src_meta.exists():
        writes[dst_meta] = read_json(src_meta)

    # Texturas PNG preprocesadas de caché (si existen en work_cache)
    country_part = track_id.split("_")[0]
    possible_cache_tex = stage_source_dir.parents[2] / "work_cache" / country_part / "textures_png"
    copied_textures = 0
    if possible_cache_tex.exists():
        for png_file in possible_cache_tex.glob("*.png"):
            target_tex = assets_dir / f"{track_id}_visual_{png_file.name}"
            files_to_copy.append((png_file, target_tex))
            copied_textures += 1

    # 4. Backup de archivos existentes
    if backup_dir:
        all_targets = [dst for _, dst in files_to_copy] + list(writes.keys())
        for target in all_targets:
            if target.exists():
                saved = backup_dir / target.relative_to(ROOT)
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, saved)

    # 5. Ejecutar escrituras y copias
    for src, dst in files_to_copy:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

    for path, doc in writes.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    ensure_visual_import_settings(assets_dir / f"{track_id}_visual.glb")

    return {
        "track_id": track_id,
        "files_copied": len(files_to_copy),
        "documents_written": len(writes),
        "textures_copied": copied_textures,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=False, default=None, type=Path, help="Ruta al directorio de stage exportado o directorio raíz de stages")
    parser.add_argument("--source-root", required=False, default=None, type=Path, help="Alias de --source (compatibilidad con plan de migración)")
    parser.add_argument("--country", required=False, default=None, type=str, help="Filtrar por país (kenya, finland, sweden, switzerland, russia)")
    parser.add_argument("--all", action="store_true", help="Buscar recursivamente e importar todas las etapas en --source")
    parser.add_argument("--all-stages", dest="all_stages", action="store_true", help="Alias de --all (compatibilidad con plan de migración)")
    parser.add_argument("--no-backup", action="store_true", help="No crear carpeta de respaldo temporal")
    parser.add_argument("--skip-backup", dest="no_backup", action="store_true", help="Alias de --no-backup")
    args = parser.parse_args()

    raw_source = args.source or args.source_root
    if raw_source is None:
        parser.error("Se requiere --source o --source-root")
    source = Path(raw_source).resolve()
    # Compatibilidad plan: --source-root <stages> --country kenya -> <stages>/kenya.
    # Aceptar también layout legacy .../exports mapeándolo a .../stages.
    if str(source).replace("\\", "/").endswith("/exports"):
        alt = source.parent / "stages"
        if alt.exists():
            print(f"[Compat] --source-root exports no existe; usando {alt}")
            source = alt.resolve()
    if args.country:
        c = args.country.lower()
        if source.name.lower() != c:
            cand = source / c
            if cand.exists():
                source = cand.resolve()
            else:
                # Permitir --source-root <stages> sin subdir y filtrar después por track_id.
                pass
    if not source.exists():
        raise FileNotFoundError(f"Origen no encontrado: {source}")

    backup_dir = None
    if not args.no_backup:
        backup_dir = Path(tempfile.mkdtemp(prefix="rally_stage_import_backup_"))
        print(f"[Backup] Respaldos guardados en: {backup_dir}")

    stages_to_import = []
    do_all = bool(args.all or getattr(args, "all_stages", False))
    if do_all or (source / "manifest.json").exists() is False:
        # Buscar todas las subcarpetas con manifest.json
        for m_file in source.glob("**/manifest.json"):
            stages_to_import.append(m_file.parent)
    else:
        stages_to_import.append(source)

    # Filtrar por país si se pidió --country pero el source aún es el raíz.
    if args.country:
        c = args.country.lower()
        if source.name.lower() != c:
            filtered = []
            for p in stages_to_import:
                # Caso estándar stages/<country>/stageN.
                if p.parent.name.lower() == c:
                    filtered.append(p)
                    continue
                try:
                    tid = read_json(p / "manifest.json").get("track_id", "")
                    if tid.startswith(c + "_stage"):
                        filtered.append(p)
                except Exception:
                    pass
            if filtered:
                stages_to_import = filtered

    if not stages_to_import:
        raise ValueError(f"No se encontraron etapas con manifest.json en: {source}")

    print(f"\n=======================================================")
    print(f"  IMPORTANDO {len(stages_to_import)} ETAPAS A {ROOT}")
    print(f"=======================================================")

    success_count = 0
    for stage_dir in sorted(stages_to_import):
        try:
            res = import_single_stage(stage_dir, backup_dir=backup_dir)
            print(f"[OK] {res['track_id']:25s} | Copiados: {res['files_copied']} archivos, {res['documents_written']} docs, {res['textures_copied']} texturas")
            success_count += 1
        except Exception as e:
            print(f"[ERROR en {stage_dir.name}]: {e}")

    print(f"\n[FINALIZADO] {success_count}/{len(stages_to_import)} etapas importadas correctamente.")
    if backup_dir:
        print(f"Directorio de backup: {backup_dir}\n")


if __name__ == "__main__":
    main()
