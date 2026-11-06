import json
import glob
from pathlib import Path

ROOT = Path(".")

# 1. Update commons/bank_manifest.json
commons_manifest_path = ROOT / "game/sounds/banks/commons/bank_manifest.json"
if commons_manifest_path.exists():
    with open(commons_manifest_path, "r", encoding="utf-8") as f:
        commons_manifest = json.load(f)
    
    existing_files = {entry["file"] for entry in commons_manifest.get("files", [])}
    
    new_entries = [
        {
            "dc_offset": 0.0,
            "duration_s": 0.474,
            "file": "backfire_ext_1.wav",
            "loop": False,
            "loop_end_s": None,
            "loop_start_s": None,
            "loudness_dbfs": -12.0,
            "peak": 0.95,
            "provenance": "Porsche 356A 1600GS Carrera GT AC mod: FMOD backfire sample 1; exterior rear exhaust detonation",
            "role": "backfire_exhaust",
            "sha256": "defad887897217ea1ba7dde34f67c760662f0995166fa85b888be642a8435d64"
        },
        {
            "dc_offset": 0.0,
            "duration_s": 0.474,
            "file": "backfire_ext_2.wav",
            "loop": False,
            "loop_end_s": None,
            "loop_start_s": None,
            "loudness_dbfs": -12.0,
            "peak": 0.95,
            "provenance": "Porsche 356A 1600GS Carrera GT AC mod: FMOD backfire sample 3; exterior rear exhaust detonation",
            "role": "backfire_exhaust",
            "sha256": "defad887897217ea1ba7dde34f67c760662f0995166fa85b888be642a8435d64"
        },
        {
            "dc_offset": 0.0,
            "duration_s": 0.474,
            "file": "backfire_ext_3.wav",
            "loop": False,
            "loop_end_s": None,
            "loop_start_s": None,
            "loudness_dbfs": -12.0,
            "peak": 0.95,
            "provenance": "Porsche 356A 1600GS Carrera GT AC mod: FMOD backfire sample 7; exterior rear exhaust detonation variation",
            "role": "backfire_exhaust",
            "sha256": "de1b797637059ee182256ac891f1bb1164bb726beea19f4a7c1fa185362ffc06"
        },
        {
            "dc_offset": 0.0,
            "duration_s": 0.430,
            "file": "backfire_ext_4.wav",
            "loop": False,
            "loop_end_s": None,
            "loop_start_s": None,
            "loudness_dbfs": -12.0,
            "peak": 0.95,
            "provenance": "Porsche 356A 1600GS Carrera GT AC mod: FMOD backfire sample 9; exterior rear exhaust deep boom detonation",
            "role": "backfire_exhaust",
            "sha256": "b303ded774000b9c3541a5b747d3f8f902b51909f19ca1e3c597034b07f5979c"
        },
        {
            "dc_offset": 0.0,
            "duration_s": 0.159,
            "file": "backfire_5.wav",
            "loop": False,
            "loop_end_s": None,
            "loop_start_s": None,
            "loudness_dbfs": -14.0,
            "peak": 0.95,
            "provenance": "Porsche 356A 1600GS Carrera GT AC mod: FMOD backfire sample 5; cockpit and bonnet low-frequency dry thump",
            "role": "backfire_cockpit_bonnet",
            "sha256": "9bedeedff982c8fa0fd10fc289747d103efd764724b4dfaeb5a21e05e523fec9"
        },
        {
            "dc_offset": 0.0,
            "duration_s": 0.159,
            "file": "backfire_int.wav",
            "loop": False,
            "loop_end_s": None,
            "loop_start_s": None,
            "loudness_dbfs": -14.0,
            "peak": 0.95,
            "provenance": "Porsche 356A 1600GS Carrera GT AC mod: FMOD backfire sample 5 alias; cockpit and bonnet low-frequency dry thump",
            "role": "backfire_cockpit_bonnet",
            "sha256": "9bedeedff982c8fa0fd10fc289747d103efd764724b4dfaeb5a21e05e523fec9"
        }
    ]
    
    for entry in new_entries:
        if entry["file"] not in existing_files:
            commons_manifest["files"].append(entry)
            
    with open(commons_manifest_path, "w", encoding="utf-8") as f:
        json.dump(commons_manifest, f, indent=2)
    print("Updated commons bank_manifest.json")

# 2. Wire all vehicle manifests to commons backfires
COMMONS_BACKFIRE_EXT = [
    "res://sounds/banks/commons/backfire_ext_1.wav",
    "res://sounds/banks/commons/backfire_ext_2.wav",
    "res://sounds/banks/commons/backfire_ext_3.wav",
    "res://sounds/banks/commons/backfire_ext_4.wav"
]
COMMONS_BACKFIRE_INT = [
    "res://sounds/banks/commons/backfire_5.wav"
]

manifest_patterns = [
    "game/sounds/banks/**/manifest.json"
]

updated_count = 0
for mpath in glob.glob("game/sounds/banks/**/manifest.json", recursive=True):
    p = Path(mpath)
    # Skip non-vehicle banks
    if "surfaces" in p.parts or "commons" in p.parts:
        continue
    
    with open(p, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    # Check if this is a vehicle bank manifest (has vehicle_id or engine or calibration)
    if "vehicle_id" in data or "engine" in data or "calibration" in data or "policy" in data:
        data["backfire"] = COMMONS_BACKFIRE_EXT
        data["backfire_interior"] = COMMONS_BACKFIRE_INT
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        print(f"Wired {p} to commons backfire")
        updated_count += 1

print(f"Total vehicle sound banks wired: {updated_count}")

# 3. Update generator scripts so re-running them keeps the commons backfires
# A: tools/rally_trophy/audio_bank.py
rt_audio_bank = Path("tools/rally_trophy/audio_bank.py")
if rt_audio_bank.exists():
    rt_code = rt_audio_bank.read_text(encoding="utf-8")
    old_rt_bf = """    manifest = {"schema_version": 1, "vehicle_id": recipe["id"], "source": provenance, "samples": samples,
                **definitions, "whine": whine, "backfire": backfire,"""
    new_rt_bf = """    commons_backfire_ext = [
        "res://sounds/banks/commons/backfire_ext_1.wav",
        "res://sounds/banks/commons/backfire_ext_2.wav",
        "res://sounds/banks/commons/backfire_ext_3.wav",
        "res://sounds/banks/commons/backfire_ext_4.wav",
    ]
    commons_backfire_int = [
        "res://sounds/banks/commons/backfire_5.wav",
    ]
    manifest = {"schema_version": 1, "vehicle_id": recipe["id"], "source": provenance, "samples": samples,
                **definitions, "whine": whine, "backfire": commons_backfire_ext, "backfire_interior": commons_backfire_int,"""
    if old_rt_bf in rt_code:
        rt_code = rt_code.replace(old_rt_bf, new_rt_bf)
        rt_audio_bank.write_text(rt_code, encoding="utf-8")
        print("Updated tools/rally_trophy/audio_bank.py")

# B: tools/audio/rally_trophy_fulvia.py
fulvia_gen = Path("tools/audio/rally_trophy_fulvia.py")
if fulvia_gen.exists():
    f_code = fulvia_gen.read_text(encoding="utf-8")
    old_f_bf = "'backfire':[base+f'fulvia_lift_{i+1}.wav' for i in range(3)]}"
    new_f_bf = "'backfire':['res://sounds/banks/commons/backfire_ext_1.wav','res://sounds/banks/commons/backfire_ext_2.wav','res://sounds/banks/commons/backfire_ext_3.wav','res://sounds/banks/commons/backfire_ext_4.wav'],'backfire_interior':['res://sounds/banks/commons/backfire_5.wav']}"
    if old_f_bf in f_code:
        f_code = f_code.replace(old_f_bf, new_f_bf)
        fulvia_gen.write_text(f_code, encoding="utf-8")
        print("Updated tools/audio/rally_trophy_fulvia.py")

# C: tools/rally/import_porsche_356a.py
porsche_gen = Path("tools/rally/import_porsche_356a.py")
if porsche_gen.exists():
    p_code = porsche_gen.read_text(encoding="utf-8")
    old_p_bf = """        definitions["backfire"].append(base_res + fname)"""
    # Keep extracted files in samples list for hash checking, but wire backfire and backfire_interior to commons
    old_p_manifest = """"exhaust_position": [0.0, 0.20, 1.50],
        "calibration": "Porsche 356A 1600GS Carrera GT Fuhrmann engine & backfire native samples."
    }"""
    new_p_manifest = """"exhaust_position": [0.0, 0.20, 1.50],
        "backfire": [
            "res://sounds/banks/commons/backfire_ext_1.wav",
            "res://sounds/banks/commons/backfire_ext_2.wav",
            "res://sounds/banks/commons/backfire_ext_3.wav",
            "res://sounds/banks/commons/backfire_ext_4.wav",
        ],
        "backfire_interior": [
            "res://sounds/banks/commons/backfire_5.wav",
        ],
        "calibration": "Porsche 356A 1600GS Carrera GT Fuhrmann engine & backfire native samples."
    }"""
    if old_p_manifest in p_code:
        p_code = p_code.replace(old_p_manifest, new_p_manifest)
        porsche_gen.write_text(p_code, encoding="utf-8")
        print("Updated tools/rally/import_porsche_356a.py")
