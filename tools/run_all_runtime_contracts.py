"""
Godot Runtime Contract Validation Runner
Executes the in-engine contract test (res://tests/rally/imported_vehicle_contract.gd)
using Godot headless for all target Rally Trophy vehicles.
"""

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RUNTIME_DIR = REPO / "tmp" / "godot_runtime"
RUNTIME_DIR.mkdir(parents=True, exist_ok=True)

GODOT_BIN = shutil.which("godot")
if not GODOT_BIN or GODOT_BIN.endswith(".cmd"):
    fallback = Path(r"C:\Users\bill\AppData\Local\Programs\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe")
    if fallback.exists():
        GODOT_BIN = str(fallback)

TARGET_VEHICLES = [
    "rt-alfa-giulia-gta",
    "rt-alpine-a110",
    "rt-fiat-abarth-1000",
    "rt-lancia-stratos",
    "rt-lotus-cortina",
    "rt-mini-cooper-s",
    "rt-opel-kadett",
    "rt-saab-96-v4",
    "rt-volvo-amazon",
]


def run_contract(vehicle_id: str) -> dict:
    out_dir = RUNTIME_DIR / vehicle_id
    out_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        GODOT_BIN,
        "--headless",
        "--path",
        "game",
        "--resolution",
        "1280x720",
        "--script",
        "res://tests/rally/imported_vehicle_contract.gd",
        "--",
        f"--rt-id={vehicle_id}",
        f"--rt-output={out_dir}",
    ]

    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
    )

    log_path = out_dir / "runtime.log"
    log_path.write_text(proc.stdout + "\n" + proc.stderr, encoding="utf-8")

    match = re.search(r"RT_VEHICLE_CONTRACT\s+(\{[^\r\n]+\})", proc.stdout)
    if not match:
        return {
            "vehicle": vehicle_id,
            "passed": False,
            "failures": [f"Missing RT_VEHICLE_CONTRACT marker in output (exit={proc.returncode})"],
            "stdout": proc.stdout[-500:],
        }

    try:
        data = json.loads(match.group(1))
        return data
    except Exception as e:
        return {
            "vehicle": vehicle_id,
            "passed": False,
            "failures": [f"Failed to parse json result: {e}"],
        }


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    print(f"Starting Godot runtime contract tests for {len(TARGET_VEHICLES)} vehicles...")
    results = []
    all_passed = True

    for vid in TARGET_VEHICLES:
        print(f"  Testing {vid} in Godot Engine...", end="", flush=True)
        res = run_contract(vid)
        results.append(res)
        if res.get("passed"):
            print(" ✓ PASS")
        else:
            print(f" ✗ FAIL: {res.get('failures')}")
            all_passed = False

    summary_file = RUNTIME_DIR / "runtime_summary.json"
    summary_file.write_text(json.dumps(results, indent=2), encoding="utf-8")

    md = [
        "# Godot In-Engine Vehicle Runtime Contract Report",
        "",
        "| Vehículo | Estado | Fallos | Verificación Visual |",
        "| :--- | :---: | :--- | :--- |",
    ]
    for r in results:
        status = "**PASS**" if r.get("passed") else "**FAIL**"
        fails = ", ".join(r.get("failures", [])) if r.get("failures") else "Ninguno"
        md.append(f"| `{r['vehicle']}` | {status} | {fails} | {r.get('visual_review', 'N/A')} |")

    report_file = RUNTIME_DIR / "runtime_report.md"
    report_file.write_text("\n".join(md) + "\n", encoding="utf-8")

    print("\n" + "=" * 60)
    print("GODOT RUNTIME CONTRACT RESULTS SUMMARY")
    print("=" * 60)
    for r in results:
        sym = "✓" if r.get("passed") else "✗"
        print(f"  {sym} {r['vehicle']:<25}: {'PASS' if r.get('passed') else 'FAIL'}")
    print("=" * 60)

    if not all_passed:
        sys.exit(1)


if __name__ == "__main__":
    main()
