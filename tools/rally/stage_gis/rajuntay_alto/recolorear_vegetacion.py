"""Recolor the ten Rajuntay sprites from a stable backup of the original PNGs."""
import argparse
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
GRASS = HERE.parents[3] / "game/assets/rally/grass/CDI"
PALETTES = {
    "scn_p07_x000_y224_80x32_sprite": ("46402A", "9B8954", "C2B07D"),
    "scn_p07_x000_y000_96x64_sprite": ("46402A", "9B8954", "C2B07D"),
    "scn_p08_x192_y160_64x64_sprite": ("736B3E", "858B4B", "A49E64"),
    "scn_p11_x192_y128_64x64_sprite": ("46402A", "9B8954", "C2B07D"),
    "arbusto_beige_01": ("46402A", "877A49", "C2B07D"),
    "arbusto_beige_02": ("46402A", "91814E", "C2B07D"),
    "arbusto_verde_01": ("56533D", "7B7E68", "A5A38B"),
    "arbusto_verde_02": ("5B5741", "7B7E68", "ADAA8E"),
    "arbusto_verde_03": ("514F38", "7B7E68", "9F9F85"),
    "cactus_01": ("484D34", "777E60", "A1A688"),
}


def recolor(image, colors):
    pixels = np.array(image.convert("RGBA"))
    visible = pixels[:, :, 3] > 0
    luma = pixels[:, :, :3] @ np.array([0.2126, 0.7152, 0.0722])
    low, high = np.percentile(luma[visible], [4, 98])
    tone = np.clip((luma - low) / max(high - low, 1.0), 0, 1)
    rows = np.nonzero(visible)[0]
    height = np.clip((rows.max() - np.arange(len(pixels))) / max(rows.max() - rows.min(), 1), 0, 1)
    tone = tone * 0.75 + height[:, None] * 0.25
    stops = np.array([list(bytes.fromhex(color)) for color in colors])
    for channel in range(3):
        pixels[:, :, channel] = np.rint(np.interp(tone, [0, 0.52, 1], stops[:, channel]))
    return Image.fromarray(pixels)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backup", type=Path)
    args = parser.parse_args()
    args.backup.mkdir(parents=True, exist_ok=True)
    for name, colors in PALETTES.items():
        folder = GRASS if name.startswith("scn_") else HERE / "arbustos_png"
        source = folder / (name + ".png")
        original = args.backup / source.name
        if not original.exists():
            shutil.copy2(source, original)
        with Image.open(original) as image:
            result = recolor(image, colors)
            assert result.getchannel("A").tobytes() == image.convert("RGBA").getchannel("A").tobytes()
        result.save(source)


if __name__ == "__main__":
    main()
