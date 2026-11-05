from __future__ import annotations

import argparse
import json
from pathlib import Path

from .common import REPO, PACKAGE, DEFAULT_SOURCE, write_json, read_json
from .doctor import discover


def main(argv=None):
    parser = argparse.ArgumentParser(description="Reproducible Rally Trophy car imports")
    parser.add_argument("command", choices=["doctor", "scan", "build", "batch", "validate", "history"])
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--repo", type=Path, default=REPO)
    parser.add_argument("--cache", type=Path, default=REPO / "build/rally_trophy")
    parser.add_argument("--recipe", type=Path, action="append")
    parser.add_argument("--recipes", type=Path, default=PACKAGE / "recipes")
    parser.add_argument("--ids", nargs="+")
    parser.add_argument("--all", action="store_true", help="Explicitly select every recipe (also the batch default)")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--blender")
    parser.add_argument("--godot")
    parser.add_argument("--converter")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--resume", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--save-blend", action="store_true")
    args = parser.parse_args(argv)
    if args.command == "history":
        data = read_json(PACKAGE / "data/history.json")
        if args.out:
            write_json(args.out, data)
        else:
            print(json.dumps(data, indent=2, ensure_ascii=True))
        return 0
    if args.command == "scan":
        from .catalog import inventory
        catalog = inventory(args.source)
        output = args.out or args.cache / "catalog.json"
        write_json(output, catalog)
        print(f"{catalog['archive_count']} archives: {output}")
        return 0
    chain = discover(args.source, blender=args.blender, godot=args.godot, converter=args.converter)
    if args.command == "doctor":
        print(json.dumps(chain, indent=2))
        return 0 if chain["ready"] else 1
    if not chain["ready"]:
        parser.error("Toolchain unavailable; run doctor and set --blender/--godot/--converter")
    recipes = args.recipe or sorted(args.recipes.glob("*.json"))
    if args.ids:
        recipes = [path for path in recipes if read_json(path)["id"] in args.ids]
        missing = set(args.ids) - {read_json(path)["id"] for path in recipes}
        if missing:
            parser.error("Unknown recipe ids: " + ", ".join(sorted(missing)))
    if args.command == "build" and len(recipes) != 1:
        parser.error("build requires exactly one --recipe or --ids selection")
    if not recipes or not 1 <= args.jobs <= 8:
        parser.error("Select at least one recipe and --jobs between 1 and 8")
    from .pipeline import batch
    report = batch(recipes, args.source, args.cache, chain, jobs=args.jobs, resume=args.resume,
        validate=args.validate or args.command == "validate" or args.render, render=args.render,
        publish=args.publish, replace=args.replace, repo=args.repo, save_blend=args.save_blend)
    print("Report: " + str(args.cache / "REPORT.md"))
    return 0 if report["passed"] else 1
