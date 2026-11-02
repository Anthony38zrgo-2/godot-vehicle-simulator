"""Manually import a validated stage1 export; preserve active timing and gate geometry.

Run from any directory: python tools/rally/import_stage_export.py --source PATH
Backups are retained outside the repository and printed at completion.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def adapt_notes(active, exported):
    result = copy.deepcopy(active)
    curves = sorted(exported["curves"], key=lambda c: c["call_index"])
    if [c["call_index"] for c in curves] != list(range(len(curves))):
        raise ValueError("call_index must be unique and contiguous")
    words = [int(c["call_word_hex"], 16) for c in curves]
    if any(not 0 <= word <= 0xffffffff for word in words):
        raise ValueError("Invalid CMR2 word")
    nodes = [c["advisory_gate_node"] for c in curves]
    if any(type(n) is not int or not 0 <= n < len(result["gates"]) for n in nodes):
        raise ValueError("Advisory gate outside active route")
    if nodes != sorted(set(nodes)):
        raise ValueError("Advisory gates must be unique and ordered")
    changes = []
    old_nodes = {g["call_index"]: i for i, g in enumerate(active["gates"]) if g.get("call_index") is not None}
    for gate in result["gates"]:
        gate["call_index"] = None
    for curve, word, node in zip(curves, words, nodes):
        index = curve["call_index"]
        result["gates"][node]["call_index"] = index
        changes.append({"call_index": index, "curve_id": curve["curve_id"],
                        "previous_word": active["calls"][index] if index < len(active["calls"]) else None,
                        "word": word, "previous_gate": old_nodes.get(index), "gate": node,
                        "evidence": curve.get("evidence", [])})
    result["calls"] = words
    return result, changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    manifest = read(source / "manifest.json")
    if manifest["track_id"] != "russia_stage1":
        raise ValueError("Only Russia Stage 1 is supported")
    assets = ROOT / "game/assets/rally/russia_stage1"
    notes_path = ROOT / "game/data/rally/pacenotes/russia_stage1.json"
    route_path = ROOT / "game/data/rally/russia_stage1_route.json"
    if read(route_path)["points"] != read(source / "russia_stage1_route.json")["points"]:
        raise ValueError("Route changed: existing gate geometry cannot be reused")
    copies = []
    for kind in ("visual", "collision"):
        item = manifest[kind]
        filename = f"russia_stage1_{kind}.glb"
        if item["path"] != filename:
            raise ValueError("Unexpected artifact path")
        src = source / filename
        if sha(src) != item["sha256"] or src.stat().st_size != item["size_bytes"]:
            raise ValueError(f"Artifact verification failed: {src}")
        copies.append((src, assets / filename))
    blend = source / manifest["source"]["blend"]
    if sha(blend) != manifest["source"]["blend_sha256"]:
        raise ValueError("Blend hash mismatch")
    manifest["source"]["blend"] = str(blend)
    manifest["source"]["import_source_manifest_sha256"] = sha(source / "manifest.json")
    active = read(notes_path)
    adapted, changes = adapt_notes(active, read(source / "russia_stage1_pacenotes.json"))
    adapted["source"] = {"export": str(source), "authoring_sha256": sha(source / "russia_stage1_pacenotes_authoring.json")}
    docs = ROOT / "game/docs/rally/pacenotes"
    report = {"source": str(source), "route_points_unchanged": len(read(route_path)["points"]),
              "gate_geometry_preserved": True, "changes": changes,
              "note": "Semantic words and advisory nodes imported verbatim; exporter evidence is not new visual/listening validation."}
    writes = {assets / "manifest.json": manifest, notes_path: adapted,
              docs / "russia_stage1_export_import.json": report,
              docs / "russia_stage1_authoring.json": read(source / "russia_stage1_pacenotes_authoring.json")}
    # All validation precedes mutations. Preserve each replaced file externally.
    backup = Path(tempfile.mkdtemp(prefix="rally_stage1_before_import_"))
    for target in [dst for _, dst in copies] + list(writes):
        if target.exists():
            saved = backup / target.relative_to(ROOT)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, saved)
    for src, dst in copies:
        shutil.copy2(src, dst)
    for path, document in writes.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Imported 2 GLBs, {len(changes)} calls and {len(adapted['gates'])} existing gates. Backup: {backup}")


if __name__ == "__main__":
    main()
