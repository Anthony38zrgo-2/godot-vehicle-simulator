"""
Audit all car JSON files in the project for hash mismatches:
1. Asset manifests (game/assets/rally/**/manifest.json)
2. Provenance files (game/data/vehicles/**/HISTORICAL_PROVENANCE.json, OPEN_FORMULA_PROVENANCE.json)
3. Sound bank manifests (game/sounds/banks/**/manifest.json)
"""

import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def fsha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def check_asset_manifests():
    manifests = list((REPO / "game/assets/rally").glob("*/manifest.json")) + list(
        (REPO / "game/assets/rally/rt").glob("*/manifest.json")
    )
    results = []
    for m_path in manifests:
        d = json.loads(m_path.read_text(encoding="utf-8"))
        m_dir = m_path.parent
        diffs = []

        # Chassis
        if "chassis" in d and "path" in d["chassis"] and "sha256" in d["chassis"]:
            cf = m_dir / d["chassis"]["path"]
            if cf.is_file():
                act = fsha(cf)
                if act != d["chassis"]["sha256"]:
                    diffs.append(("chassis", d["chassis"]["path"], d["chassis"]["sha256"], act, cf.stat().st_size))

        # Wheels
        for wk, wv in d.get("wheels", {}).items():
            if "path" in wv and "sha256" in wv:
                wf = m_dir / wv["path"]
                if wf.is_file():
                    act = fsha(wf)
                    if act != wv["sha256"]:
                        diffs.append(("wheel", wv["path"], wv["sha256"], act, wf.stat().st_size))

        # Collision
        if "collision" in d and "path" in d["collision"] and "sha256" in d["collision"]:
            cof = m_dir / d["collision"]["path"]
            if cof.is_file():
                act = fsha(cof)
                if act != d["collision"]["sha256"]:
                    diffs.append(("collision", d["collision"]["path"], d["collision"]["sha256"], act, cof.stat().st_size))

        # Visual damage files
        vd = d.get("visual_damage", {}).get("files", {})
        for fk, fv in vd.items():
            if isinstance(fv, dict) and "sha256" in fv:
                # Could be relative to m_dir or under damage/
                vdf = m_dir / fk
                if not vdf.is_file():
                    vdf = m_dir / "damage" / fk
                if vdf.is_file():
                    act = fsha(vdf)
                    if act != fv["sha256"]:
                        diffs.append(("visual_damage", fk, fv["sha256"], act, vdf.stat().st_size))

        if diffs:
            results.append({"manifest": m_path, "diffs": diffs})
    return results


def check_provenance():
    prov_files = list((REPO / "game/data/vehicles").rglob("*PROVENANCE.json"))
    results = []
    for pf in prov_files:
        d = json.loads(pf.read_text(encoding="utf-8"))
        p_dir = pf.parent
        diffs = []
        if "profile_json_sha256" in d:
            for fname, exp_hash in d["profile_json_sha256"].items():
                tfile = p_dir / fname
                if tfile.is_file():
                    act_hash = fsha(tfile)
                    if act_hash != exp_hash:
                        diffs.append((fname, exp_hash, act_hash))
        if diffs:
            results.append({"provenance": pf, "diffs": diffs})
    return results


def check_sound_banks():
    bank_files = list((REPO / "game/sounds/banks").rglob("manifest.json"))
    results = []
    for bf in bank_files:
        d = json.loads(bf.read_text(encoding="utf-8"))
        b_dir = bf.parent
        diffs = []
        for sample in d.get("samples", []):
            if "sha256" not in sample:
                continue
            sf = b_dir / sample["file"]
            if sf.is_file():
                act = fsha(sf)
                if act != sample["sha256"]:
                    diffs.append((sample["file"], sample["sha256"], act))
        if diffs:
            results.append({"bank": bf, "diffs": diffs})
    return results


if __name__ == "__main__":
    print("=== Checking Asset Manifests ===")
    asset_diffs = check_asset_manifests()
    for item in asset_diffs:
        rel = item["manifest"].relative_to(REPO).as_posix()
        print(f"Mismatch in {rel}:")
        for cat, path, exp, act, sz in item["diffs"]:
            print(f"  [{cat}] {path}: manifest={exp} actual={act} (size={sz})")

    print("\n=== Checking Vehicle Physics Provenance ===")
    prov_diffs = check_provenance()
    for item in prov_diffs:
        rel = item["provenance"].relative_to(REPO).as_posix()
        print(f"Mismatch in {rel}:")
        for fname, exp, act in item["diffs"]:
            print(f"  {fname}: recorded={exp} actual={act}")

    print("\n=== Checking Sound Banks ===")
    sound_diffs = check_sound_banks()
    for item in sound_diffs:
        rel = item["bank"].relative_to(REPO).as_posix()
        print(f"Mismatch in {rel}:")
        for fname, exp, act in item["diffs"]:
            print(f"  {fname}: recorded={exp} actual={act}")

    if not asset_diffs and not prov_diffs and not sound_diffs:
        print("\nAll JSON hashes across all vehicles are 100% UP TO DATE!")
