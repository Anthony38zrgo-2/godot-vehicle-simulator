"""Prepare a dry puna palette and a texture comparison without editing sources."""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


PALETTE = {
    "grava": (106, 103, 106),
    "pasto_denso": (124, 111, 80),
    "pasto_ralo": (139, 123, 94),
    "tierra": (126, 102, 94),
    "roca": (110, 108, 111),
}
SELECTION = {
    "carretera": "g_4a.png",
    "pasto_denso": "ter_kn1b.png",
    "pasto_ralo": "ter_kn3b.png",
    "cuneta": "g9_mg1.png",
    "talud": "kenya_rock_edge_2_2.png",
    "pedregal": "g3_mg1.png",
    "roca_suelta": "ter1_rcf.png",
    "carretera_compacta": "g_4b.png",
    "carretera_fina": "g_8c.png",
    "carretera_gruesa": "g_9c.png",
    "pasto_denso_02": "ter_kn1a.png",
    "pasto_denso_03": "kenya_terrain_grass_1_dif1.png",
    "pasto_ralo_02": "ter_gr2a.png",
    "pasto_ralo_03": "kenya_terrain_grass_to_jungle.png",
    "pasto_oliva_local": "jungle_terrain_1_dif1.png",
    "cuneta_02": "g3_mg8_3.png",
    "corte_tierra_rojiza": "g_8b.png",
    "talud_02": "kenya_rock_edge_2_1.png",
    "talud_03": "ter1_rca.png",
    "pedregal_02": "g_9b.png",
    "roca_suelta_02": "ter1_rcg.png",
}
TARGET_OVERRIDES = {
    "g_4b": (119, 115, 116),
    "g_8b": (136, 109, 99),
    "g_9b": (116, 112, 113),
    "g3_mg1": (116, 112, 110),
    "g3_mg8_3": (119, 109, 105),
    "jungle_terrain_1_dif1": (99, 100, 72),
    "kenya_rock_edge_2_1": (119, 105, 102),
    "ter1_rca": (131, 128, 123),
}


def family(name):
    if name == "g_8b":
        return "tierra"
    if name.startswith(("kenya_rock", "ter1_rc", "roc_")):
        return "roca"
    if name.startswith(("kenya_terrain_grass_to", "jungle_terrain_to", "ter_gr", "ter_kn3", "stn_gr", "gr_gr")):
        return "pasto_ralo"
    if name.startswith(("kenya_terrain_grass", "jungle_terrain", "ter_kn1")):
        return "pasto_denso"
    if name.startswith("ter_") or "_mg" in name:
        return "tierra"
    return "grava"


def grade(image, target):
    pixels = np.asarray(image, dtype=np.float32)
    rgb = pixels[:, :, :3]
    visible = pixels[:, :, 3] > 0
    if not visible.any():
        return image
    luma = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    chroma = rgb - luma[:, :, None]
    detail = luma - np.median(luma[visible])
    graded = np.array(target) + detail[:, :, None] * 0.88
    graded += (chroma - np.median(chroma[visible], axis=0)) * 0.24
    pixels[:, :, :3] = np.clip(np.rint(graded), 0, 255)
    return Image.fromarray(pixels.astype(np.uint8))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    files = sorted(args.source.rglob("*.png"))
    if not files or args.output.resolve().is_relative_to(args.source.resolve()):
        parser.error("Provide a populated source and a separate output directory.")
    sheet = Image.new("RGB", (960, 120 * ((len(files) + 4) // 5)), "#222222")
    draw = ImageDraw.Draw(sheet)
    selected = {}
    for index, path in enumerate(sorted(files, key=lambda item: (family(item.stem), item.name))):
        role = family(path.stem)
        with Image.open(path) as source:
            original = source.convert("RGBA")
        result = grade(original, TARGET_OVERRIDES.get(path.stem, PALETTE[role]))
        output = args.output / "png" / path.relative_to(args.source)
        output.parent.mkdir(parents=True, exist_ok=True)
        result.save(output)
        if path.name in SELECTION.values():
            selected[path.name] = output
        left, top = index % 5 * 192, index // 5 * 120
        for offset, image in ((0, original), (92, result)):
            thumb = image.resize((90, 88), Image.Resampling.LANCZOS)
            sheet.paste(thumb, (left + offset, top), thumb)
        draw.text((left, top + 89), path.name, fill="white")
        draw.text((left, top + 103), role, fill="#c2ae86")
    sheet.save(args.output / "comparativa.png")
    selection_dir = args.output / "seleccion_ss01"
    selection_dir.mkdir(exist_ok=True)
    mosaics = Image.new("RGB", (864, ((len(SELECTION) + 3) // 4) * 239), "#222222")
    labels = ImageDraw.Draw(mosaics)
    for index, (role, filename) in enumerate(SELECTION.items()):
        with Image.open(selected[filename]) as result:
            result.save(selection_dir / (role + ".png"))
            tile = result.resize((72, 72), Image.Resampling.LANCZOS)
        left, top = index % 4 * 216, index // 4 * 239
        for row in range(3):
            for column in range(3):
                mosaics.paste(tile, (left + column * 72, top + row * 72), tile)
        labels.text((left + 3, top + 217), role, fill="white")
        labels.text((left + 3, top + 227), filename, fill="#c2ae86")
    mosaics.save(args.output / "seleccion_mosaico.png")
    (selection_dir / "fuentes.txt").write_text(
        "".join(f"{role}.png <- {filename}\n" for role, filename in SELECTION.items()), encoding="utf-8")


if __name__ == "__main__":
    main()
