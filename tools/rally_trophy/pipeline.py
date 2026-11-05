from __future__ import annotations

import concurrent.futures
import hashlib
import json
import os
import shutil
import threading
from pathlib import Path

from PIL import Image

from .archives import extract, get, find_data
from .audio_bank import build_bank
from .common import PACKAGE, REPO, read_json, write_json, sha, code_hash, run, safe_id, within
from .config_parser import parse_config, vector
from .convert import adapt_arm_batches, convert_model
from .integrate import write_scenes, install
from .physics_profile import compile_profile
from .validate import validate_payload, prepare_validation_project, validate_runtime

DRIVER_LOCK = threading.Lock()


def png_textures(directory):
    report = []
    for source in Path(directory).iterdir():
        if source.suffix.lower() != ".tga":
            continue
        target = source.with_suffix(".png")
        with Image.open(source) as image:
            image.convert("RGBA").save(target, format="PNG")
        with Image.open(target) as image:
            if image.format != "PNG":
                raise ValueError(f"PNG signature mismatch: {target}")
            image.verify()
        report.append({"source": source.name, "source_sha256": sha(source), "output": target.name, "sha256": sha(target)})
    return report


def prepare_driver(data, number, cache, toolchain, fingerprint):
    source = data / f"Drivers/driver{number}.bzf"
    identity = hashlib.sha256((sha(source) + fingerprint + sha(toolchain["converter"])).encode()).hexdigest()[:20]
    directory = Path(cache) / "drivers" / identity
    with DRIVER_LOCK:
        state = directory / "complete.json"
        if state.is_file():
            previous = read_json(state)
            if all((directory / name).is_file() and sha(directory / name) == digest for name, digest in previous["outputs"].items()):
                return directory
        files = extract(source, directory)
        png_textures(directory)
        for source_name, target_name in [("Driver.bmf", "Driver.BMF"), ("co_Driver.BMF", "co_Driver.BMF")]:
            blob = get(files, source_name)
            if blob is None:
                raise ValueError(f"driver{number}: missing {source_name}")
            model = directory / target_name
            model.write_bytes(blob)
            convert_model(toolchain["converter"], model, directory / "converter")
        for side in ["left", "right"]:
            model = directory / f"arm_{side}_lo_static.BMF"
            model.write_bytes(adapt_arm_batches(get(files, f"arm_{side}_lo.BMF")))
            convert_model(toolchain["converter"], model, directory / "converter")
        write_json(state, {"source_sha256": sha(source), "outputs": {p.name: sha(p) for p in directory.iterdir() if p.suffix.lower() in {".fbx", ".png"}}})
    return directory


def load_recipe(path):
    recipe = read_json(path)
    safe_id(recipe["id"])
    for key in ["archive", "historical_id", "engine_layout", "geometry_policy", "physics_policy", "display_name"]:
        if key not in recipe:
            raise ValueError(f"Missing recipe field: {key}")
    if recipe["physics_policy"] != "game_derived":
        raise ValueError("Use game_derived plus explicit physics_overrides; historical facts are never silently applied")
    if recipe["geometry_policy"] not in {"native", "historical_uniform"}:
        raise ValueError("Invalid geometry policy")
    if recipe["engine_layout"] not in {"front", "mid", "rear"}:
        raise ValueError("Invalid engine layout")
    return recipe


def build_one(recipe_path, source, cache, toolchain, *, resume=True, save_blend=False, fingerprint=None):
    recipe = load_recipe(recipe_path)
    data = find_data(source)
    archive = within(data / "Cars", recipe["archive"])
    code = fingerprint or code_hash()
    history = read_json(PACKAGE / "data/history.json")["cars"][recipe["historical_id"]]
    signature = hashlib.sha256(json.dumps({"recipe": recipe, "history": history, "source_sha256": sha(archive),
        "code": code, "blender": sha(toolchain["blender"]), "converter": sha(toolchain["converter"]),
        "drivers": {str(n): sha(data / f"Drivers/driver{n}.bzf") for n in (1, 2) if (data / f"Drivers/driver{n}.bzf").is_file()},
        "save_blend": save_blend}, sort_keys=True).encode()).hexdigest()
    work = Path(cache).resolve() / "cars" / recipe["id"] / signature[:20]
    state = work / "complete.json"
    payload = work / "payload"
    if resume and state.is_file() and (not save_blend or (work / "vehicle.blend").is_file()):
        try:
            audit = validate_payload(payload, recipe)
        except (ValueError, OSError, KeyError):
            audit = {"passed": False}
        if audit["passed"]:
            return {"id": recipe["id"], "status": "cached", "work": str(work), "payload": str(payload),
                    "recipe": recipe, "audit": audit, "fingerprint": signature}
    work.mkdir(parents=True, exist_ok=True)
    files = extract(archive, work / "source")
    texture_report = png_textures(work / "source")
    configs = {name: parse_config(get(files, name) or b"") for name in ["info.ini", "car.ini", "Engine.ini", "Sounds.ini", "Tires.ini"]}
    car = configs["car.ini"]["values"]
    for key in ["DriverLoc", "CoDriverLoc", "InteriorLoc"]:
        vector(car, key)
    write_json(work / "source_configs.json", configs)
    number = int(car["DriverType"])
    if number not in (1, 2):
        raise ValueError(f"Unsupported driver type: {number}")
    driver = prepare_driver(data, number, cache, toolchain, code)
    convert_model(toolchain["converter"], work / "source/model.BMF", work / "converter")
    game = payload / "game"
    asset = game / "assets/rally/rt" / recipe["id"]
    asset.mkdir(parents=True, exist_ok=True)
    provenance = {"archive": str(archive), "archive_sha256": sha(archive), "driver_archive": str(data / f"Drivers/driver{number}.bzf"),
        "driver_archive_sha256": sha(data / f"Drivers/driver{number}.bzf"), "generator": "tools/rally_trophy",
        "pipeline_code_sha256": code, "recipe": recipe, "blender_sha256": sha(toolchain["blender"]),
        "converter_sha256": sha(toolchain["converter"])}
    job = {"source_dir": str(work / "source"), "driver_dir": str(driver), "asset_dir": str(asset),
        "report_path": str(work / "component_report.json"), "recipe": recipe, "car_config": car, "provenance": provenance}
    if recipe["geometry_policy"] == "historical_uniform":
        field = history.get("facts", {}).get("wheelbase_m", {})
        if history.get("reference_scope") in {"related_variant", "identity_uncertain"} and not recipe.get("allow_related_reference_scaling"):
            raise ValueError("Historical scaling for an uncertain variant requires allow_related_reference_scaling")
        if field.get("status") != "documented" or not field.get("value"):
            raise ValueError("Historical scaling requires a documented wheelbase for this variant")
        job["historical_wheelbase_m"] = field["value"]
    if save_blend:
        job["save_blend"] = str(work / "vehicle.blend")
    write_json(work / "job.json", job)
    run([toolchain["blender"], "--background", "--factory-startup", "--python", PACKAGE / "blender_export.py", "--", work / "job.json"],
        work / "blender.log", timeout=300, require_marker="RT_EXPORT_SUCCESS " + recipe["id"])
    assets = read_json(asset / "manifest.json")
    compile_profile(recipe, configs, assets, history, game / "data/vehicles/rt" / recipe["id"])
    build_bank(files, configs["Sounds.ini"]["values"], configs["Engine.ini"]["values"], recipe, game / "sounds/banks" / recipe["id"], provenance)
    write_scenes(recipe, payload, assets)
    audit = validate_payload(payload, recipe)
    write_json(work / "filesystem_validation.json", audit)
    if not audit["passed"]:
        raise ValueError("Filesystem audit failed: " + "; ".join(audit["failures"]))
    result = {"id": recipe["id"], "status": "built", "work": str(work), "payload": str(payload),
              "recipe": recipe, "audit": audit, "fingerprint": signature, "texture_report": texture_report}
    write_json(state, result)
    return result


def batch(recipes, source, cache, toolchain, *, jobs=1, resume=True, validate=False, render=False, publish=False, replace=False, repo=REPO, save_blend=False):
    ids = [read_json(path)["id"] for path in recipes]
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate vehicle IDs in batch")
    if publish and not validate:
        raise ValueError("Publishing requires --validate; use build output for unvalidated inspection")
    cache = Path(cache).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    results = []
    fingerprint = code_hash()

    def execute(path):
        try:
            return build_one(path, source, cache, toolchain, resume=resume, save_blend=save_blend, fingerprint=fingerprint)
        except Exception as exc:
            return {"id": Path(path).stem, "status": "failed", "error": str(exc)}

    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        for result in pool.map(execute, recipes):
            results.append(result)
            print(f"{result['id']}: {result['status']}" + (" — " + result["error"] if "error" in result else ""), flush=True)
    good = [r for r in results if r["status"] != "failed"]
    if validate and good:
        project = prepare_validation_project(repo, cache, [(r["payload"], r["recipe"]) for r in good])
        try:
            command = [toolchain["godot"], "--headless", "--path", project, "--import"]
            try:
                run(command, cache / "godot_import.log", timeout=600)
            except RuntimeError:
                # Editor shutdown can fail after initial import on Windows. A second
                # invocation must still exit cleanly before testing or publishing.
                run(command, cache / "godot_import_retry.log", timeout=600)
        except Exception as exc:
            for result in good:
                result.update(status="failed", error=str(exc))
        else:
            for result in good:  # A Godot project/cache is never imported concurrently.
                try:
                    result["runtime"] = validate_runtime(project, toolchain["godot"], result["recipe"], Path(result["work"]) / "review", render=render)
                    result["status"] = "validated"
                    if publish:
                        install(result["payload"], result["recipe"], repo, replace=replace)
                        result["status"] = "published"
                except Exception as exc:
                    result.update(status="failed", error=str(exc))
    report = {"schema_version": 1, "results": results, "passed": all(r["status"] != "failed" for r in results),
              "default_vehicle_changed": False, "visual_acceptance": "pending_human_review"}
    write_json(cache / "batch_report.json", report)
    write_report(cache / "REPORT.md", report)
    return report


def write_report(path, report):
    lines = ["# Rally Trophy batch report", "", "Visual acceptance remains pending human review.", "",
             "Measured values in metres. FIA figures are reference variants, and may differ from the game.",
             "", "| Vehicle | Status | Measured wheelbase / front / rear | FIA reference | Evidence/error |",
             "| --- | --- | --- | --- | --- |"]
    history = read_json(PACKAGE / "data/history.json")["cars"]
    for result in report["results"]:
        evidence = result.get("error", result.get("work", ""))
        geo = result.get("audit", {}).get("geometry", {})
        measured = " / ".join(f"{geo[k]:.3f}" for k in ("wheelbase", "front_track", "rear_track")) if geo else "-"
        historic = history.get(result.get("recipe", {}).get("historical_id"), {})
        facts = historic.get("facts", {})
        reference = " / ".join(str(facts.get(k, facts.get(k.replace("_m", "_options_m"), {})).get("value", "-"))
                               for k in ("wheelbase_m", "track_front_m", "track_rear_m"))
        fia = historic.get("sources", {}).get("fia")
        if fia:
            reference += f" ([{fia['homologation']}]({fia['page']}))"
        lines.append(f"| {result['id']} | {result['status']} | {measured} | {reference} | {str(evidence).replace('|', '/')} |")
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")
