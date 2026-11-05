from __future__ import annotations

import json
import os
import shutil
import struct
import re
from pathlib import Path

from PIL import Image

from .audio_bank import pcm
from .common import REPO, read_json, write_json, sha, run, within
from .integrate import registry_entry


def glb_document(path):
    blob = Path(path).read_bytes()
    if len(blob) < 20 or blob[:4] != b"glTF" or struct.unpack_from("<I", blob, 8)[0] != len(blob):
        raise ValueError(f"Invalid GLB container: {path}")
    count, kind = struct.unpack_from("<II", blob, 12)
    if kind != 0x4E4F534A:
        raise ValueError("GLB has no JSON chunk")
    return json.loads(blob[20:20 + count])


def validate_payload(payload, recipe):
    game = Path(payload) / "game"
    identifier = recipe["id"]
    asset = game / "assets/rally/rt" / identifier
    manifest = read_json(asset / "manifest.json")
    failures = []

    def check(condition, label):
        if not condition:
            failures.append(label)

    artifacts = [manifest["chassis"], manifest["collision"]] + list(manifest["wheels"].values())
    artifacts += [{"path": p, **v} for p, v in manifest["visual_damage"]["files"].items()]
    for item in artifacts:
        path = within(asset, item["path"])
        check(path.is_file() and sha(path) == item["sha256"], "artifact hash " + item["path"])
        if path.suffix == ".glb":
            doc = glb_document(path)
            check(all(not image.get("uri", "").startswith(("/", "C:", "D:")) for image in doc.get("images", [])), "portable images " + path.name)
            check(all("uri" not in image for image in doc.get("images", [])), "embedded textures " + path.name)
        if path.suffix == ".png":
            with Image.open(path) as image:
                check(image.format == "PNG", "actual PNG encoding " + path.name)
                image.verify()
    doc = glb_document(asset / manifest["chassis"]["path"])
    nodes = {n.get("name") for n in doc.get("nodes", [])}
    for name in recipe.get("body_panels", ["body", "hood", "trunk"]) + ["interior_hi", "CockpitEye", "steering_wheel_hi", "Driver_driver_head", "DriverArm_left_frame09", "DriverArm_right_frame09"] + (["seat_driver", "seat_co_driver"] if recipe.get("interior", {}).get("require_seats", True) else []):
        check(name in nodes, "required node " + name)
    check(len(doc.get("images", [])) >= 5, "native textures embedded")
    for side in ["left", "right"]:
        node = next((n for n in doc["nodes"] if n.get("name") == f"DriverArm_{side}_frame09"), {})
        mesh = doc.get("meshes", [])[node["mesh"]] if "mesh" in node else {}
        check(len(mesh.get("extras", {}).get("targetNames", [])) == 19, "native morph poses " + side)
    geometry = manifest["geometry"]
    check(1.5 < geometry["wheelbase"] < 3.5, "plausible measured wheelbase")
    check(all(0.9 < geometry[k] < 2.1 for k in ["front_track", "rear_track"]), "plausible measured tracks")
    profile_dir = game / "data/vehicles/rt" / identifier
    provenance = read_json(profile_dir / "HISTORICAL_PROVENANCE.json")
    for name, expected in provenance["profile_json_sha256"].items():
        check(sha(within(profile_dir, name)) == expected, "physics hash " + name)
    bank = game / "sounds/banks" / identifier
    sound = read_json(bank / "manifest.json")
    for sample in sound["samples"]:
        path = within(bank, sample["file"])
        check(sha(path) == sample["sha256"], "audio hash " + sample["file"])
        data, rate, channels = pcm(path.read_bytes())
        check(rate == sample["rate_hz"] and channels == sample["channels"] and len(data) > 100, "native PCM format " + sample["file"])
    result = {"passed": not failures, "failures": failures, "geometry": geometry,
              "sample_count": len(sound["samples"]), "visual_review": "pending_human_review"}
    return result


def prepare_validation_project(repo, work_root, payloads):
    """Use a separate Godot project; never import/update the real .godot cache."""
    repo, work_root = Path(repo).resolve(), Path(work_root).resolve()
    project = work_root / "validation_project"
    if not project.exists():
        binary = {".glb", ".png", ".jpg", ".jpeg", ".wav", ".tga", ".ttf", ".ogg", ".dll", ".webp"}

        def copy(source, target):
            source, target = Path(source), Path(target)
            if source.suffix.lower() in binary:
                try:
                    os.link(source, target)
                    return str(target)
                except OSError:
                    pass
            return shutil.copy2(source, target)

        shutil.copytree(repo / "game", project, copy_function=copy,
                        ignore=shutil.ignore_patterns(".godot", "logs", "__pycache__", "*.blend", "*.blend1"))
    # Refresh text resources on resumed validation without copying unchanged assets.
    for directory in ("scripts", "tests", "scenes", "data"):
        for source in (repo / "game" / directory).rglob("*"):
            if source.is_file() and source.suffix.lower() in {".gd", ".uid", ".tscn", ".tres", ".json", ".gdshader"}:
                target = within(project, source.relative_to(repo / "game"))
                if not target.exists() or sha(source) != sha(target):
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
    shutil.copy2(repo / "game/project.godot", project / "project.godot")
    registry = read_json(repo / "game/data/vehicles/registry.json")
    for payload, recipe in payloads:
        # Unlink hardlinked binary destinations before copying rebuilt versions.
        for source in (Path(payload) / "game").rglob("*"):
            if source.is_file():
                target = within(project, source.relative_to(Path(payload) / "game"))
                if target.exists() and sha(source) == sha(target):
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                target.unlink(missing_ok=True)
                shutil.copy2(source, target)
        registry["vehicles"][recipe["id"]] = registry_entry(recipe)
    write_json(project / "data/vehicles/registry.json", registry)
    return project


def validate_runtime(project, godot, recipe, report_dir, *, render=False):
    report_dir = Path(report_dir).resolve()
    report_dir.mkdir(parents=True, exist_ok=True)
    arguments = [godot]
    if not render:
        arguments.append("--headless")
    arguments += ["--path", project, "--resolution", "1280x720", "--script", "res://tests/rally/imported_vehicle_contract.gd",
                  "--", "--rt-id=" + recipe["id"], "--rt-output=" + str(report_dir)]
    if render:
        arguments.append("--rt-render")
    output = run(arguments, report_dir / "runtime.log", timeout=180, require_marker="RT_VEHICLE_CONTRACT ")
    match = re.search(r"RT_VEHICLE_CONTRACT (\{[^\r\n]+\})", output)
    result = json.loads(match[1])
    if not result["passed"]:
        raise RuntimeError(f"Vehicle contract failed: {report_dir}")
    return result
