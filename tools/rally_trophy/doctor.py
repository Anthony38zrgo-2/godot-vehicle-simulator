from __future__ import annotations

import importlib.util
import os
import shutil
from pathlib import Path

from .archives import find_data
from .common import DEFAULT_SOURCE


def discover(source=DEFAULT_SOURCE, *, blender=None, godot=None, converter=None):
    source = Path(source).resolve()

    def choose(explicit, env, candidates, commands):
        paths = [explicit, os.environ.get(env)] + list(candidates)
        paths += [shutil.which(command) for command in commands]
        for value in paths:
            if value and Path(value).is_file():
                return str(Path(value).resolve())
        return None

    result = {"source": str(source)}
    try:
        result["data"] = str(find_data(source))
    except FileNotFoundError as exc:
        result["source_error"] = str(exc)
    result["blender"] = choose(blender, "BLENDER_BIN",
        sorted(Path("C:/Program Files/Blender Foundation").glob("Blender */blender.exe"), reverse=True), ["blender"])
    result["godot"] = choose(godot, "GODOT_BIN",
        sorted((Path.home() / "AppData/Local/Programs/Godot").glob("*/*console.exe"), reverse=True), ["godot4", "godot"])
    result["converter"] = choose(converter, "RT_CONVERTER",
        [parent / "FlatOutW32BGMTool/FlatOutW32BGMTool_gcp.exe" for parent in (source, *source.parents)], [])
    result["python_dependencies"] = {name: importlib.util.find_spec(module) is not None
                                        for name, module in [("numpy", "numpy"), ("Pillow", "PIL")]}
    result["ready"] = all(result.get(k) for k in ["data", "blender", "godot", "converter"]) and all(result["python_dependencies"].values())
    result["note"] = "Blender imports use --factory-startup; no user addon installation or current Blender session required."
    return result
