"""Prep + convert mod mesh (outside BZF pipeline): TGA->PNG, BMF->FBX, list objects."""
import shutil, subprocess, sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, r"D:\rust-godot-vehicle-simulator\tools")
from rally_trophy.common import sha
from rally_trophy.convert import convert_model

REPO = Path(r"D:\rust-godot-vehicle-simulator")
WORK = REPO / "tmp/porsche_mod/build"
SRC = WORK / "source"
SRC.mkdir(parents=True, exist_ok=True)
EXT = REPO / "tmp/porsche_mod/extracted/ftc"
for f in EXT.iterdir():
    if f.suffix.lower() in (".tga", ".bmf", ".ini"):
        shutil.copy2(f, SRC / f.name)

# TGA -> PNG (pipeline png_textures logic)
for tga in sorted(SRC.glob("*.tga")):
    png = tga.with_suffix(".png")
    with Image.open(tga) as im:
        name = tga.stem.lower()
        if name in ("interior_hi", "interior_lo", "body"):
            # Discard broken 0-alpha or unused spec-mask alpha
            im.convert("RGB").save(png, format="PNG")
            print("png (RGB opaque):", png.name)
        else:
            im.convert("RGBA").save(png, format="PNG")
            print("png (RGBA):", png.name)

# model.BMF -> model_out.fbx
CONV = r"D:\games\rally-throphy\FlatOutW32BGMTool\FlatOutW32BGMTool_gcp.exe"
out = convert_model(CONV, SRC / "model.BMF", WORK / "converter")
print("FBX OK:", out, out.stat().st_size)
