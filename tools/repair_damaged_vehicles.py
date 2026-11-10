#!/usr/bin/env python3
"""
Orchestrator to audit and repair damaged vehicle GLBs,
update manifest.json SHA-256 hashes, and verify contract compliance.
"""

import hashlib
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))
AUDIT_DIR = REPO / "tmp" / "glb_audit"
RT_ASSETS = REPO / "game" / "assets" / "rally" / "rt"
RECIPES_DIR = REPO / "tools" / "rally_trophy" / "recipes"


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def update_rt_manifest(vehicle_id: str):
    asset_dir = RT_ASSETS / vehicle_id
    manifest_path = asset_dir / "manifest.json"
    if not manifest_path.is_file():
        return

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    # Update chassis
    chassis_rel = manifest["chassis"]["path"]
    chassis_file = asset_dir / chassis_rel
    if chassis_file.is_file():
        manifest["chassis"]["sha256"] = sha256_file(chassis_file)
        manifest["chassis"]["size_bytes"] = chassis_file.stat().st_size

    # Update wheels
    for wkey, winfo in manifest.get("wheels", {}).items():
        wfile = asset_dir / winfo["path"]
        if wfile.is_file():
            winfo["sha256"] = sha256_file(wfile)
            winfo["size_bytes"] = wfile.stat().st_size

    # Update visual_damage files
    vdamage = manifest.get("visual_damage", {}).get("files", {})
    for dpath_str, dinfo in vdamage.items():
        dfile = asset_dir / dpath_str
        if dfile.is_file():
            dinfo["sha256"] = sha256_file(dfile)
            if "size_bytes" in dinfo:
                dinfo["size_bytes"] = dfile.stat().st_size

    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Updated manifest.json for {vehicle_id}")


def validate_rt_contracts(exclude_ids: set[str]) -> list[dict]:
    from tools.rally_trophy.validate import validate_payload

    results = []
    for recipe_file in sorted(RECIPES_DIR.glob("*.json")):
        recipe = json.loads(recipe_file.read_text(encoding="utf-8"))
        vid = recipe["id"]
        if vid in exclude_ids:
            continue
        res = validate_payload(REPO, recipe)
        results.append({"vehicle_id": vid, "passed": res["passed"], "failures": res["failures"]})
    return results


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    print("=== STEP 1: Initial Batch Audit ===")
    subprocess.run([sys.executable, str(REPO / "tools" / "audit_all_vehicles.py")], check=True)

    summary_path = AUDIT_DIR / "audit_summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    failed_glbs = [g for g in summary["glbs"] if g["status"] == "FAIL"]

    print(f"\nFound {len(failed_glbs)} GLB files with FAIL status.")
    if failed_glbs:
        jobs_path = AUDIT_DIR / "repair_jobs.json"
        jobs_path.write_text(json.dumps(failed_glbs, indent=2), encoding="utf-8")

        print("\n=== STEP 2: Running Blender Surgical Repair Worker ===")
        worker = REPO / "tools" / "blender_repair_glb_worker.py"
        cmd = [
            "blender",
            "-b",
            "--factory-startup",
            "--python",
            str(worker),
            "--",
            str(jobs_path),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        print(proc.stdout)
        if proc.returncode != 0:
            print(proc.stderr, file=sys.stderr)
            sys.exit(1)

        repair_report = json.loads((AUDIT_DIR / "repair_worker_report.json").read_text(encoding="utf-8"))
        modified_vehicles = {r["vehicle_id"] for r in repair_report if r["repaired"]}

        print("\n=== STEP 3: Updating Manifest SHA-256 Hashes ===")
        for vid in sorted(modified_vehicles):
            if vid.startswith("rt-"):
                update_rt_manifest(vid)

        print("\n=== STEP 4: Re-running Batch Audit (Post-Repair Verification) ===")
        subprocess.run([sys.executable, str(REPO / "tools" / "audit_all_vehicles.py")], check=True)

    print("\n=== STEP 5: Verifying RT Vehicle Contracts ===")
    contract_results = validate_rt_contracts(set())
    all_passed = True
    for cr in contract_results:
        status = "PASS" if cr["passed"] else f"FAIL ({cr['failures']})"
        print(f"  Contract {cr['vehicle_id']:<25}: {status}")
        if not cr["passed"]:
            all_passed = False

    if not all_passed:
        sys.exit(1)
    print("\nAll vehicle GLB repairs and contract validations succeeded!")


if __name__ == "__main__":
    main()
