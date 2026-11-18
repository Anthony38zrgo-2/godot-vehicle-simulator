"""Recolor the ten Rajuntay sprites from a stable backup of the original PNGs."""
import argparse
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
GRASS = HERE.parents[3] / "game/assets/rally/grass/CDI"
PALETTES = {
    "scn_p07_x000_y224_80x32_sprite": ("665C52", "B5AD93", "E4DAC2"),
    "scn_p07_x000_y000_96x64_sprite": ("64564C", "A79B83", "D5C8AD"),
    "scn_p08_x192_y160_64x64_sprite": ("565E53", "9FA58F", "CED1B9"),
    "scn_p11_x192_y128_64x64_sprite": ("665C52", "BBB49C", "E9E0CB"),
    "arbusto_beige_01": ("84706F", "B8A09A", "E2CABE"),
    "arbusto_beige_02": ("897471", "C1A69B", "E8D2C4"),
    "arbusto_verde_01": ("304B43", "658575", "A1B3A0"),
    "arbusto_verde_02": ("344F46", "6D8D7C", "A7B9A6"),
    "arbusto_verde_03": ("2D4842", "5D7E70", "98AD9E"),
    "cactus_01": ("2D5452", "4F8C7E", "A5C8AE"),
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
