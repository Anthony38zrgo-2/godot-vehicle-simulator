"""Grade the SS01 selection and make opposite texture edges continuous."""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from preparar_paleta_estepa import SELECTION, grade


TARGETS = {
    "carretera": (98, 103, 118),
    "carretera_compacta": (113, 111, 122),
    "carretera_fina": (108, 110, 121),
    "carretera_gruesa": (93, 98, 111),
    "pasto_denso": (183, 154, 82),
    "pasto_ralo": (208, 175, 110),
    "pasto_oliva_local": (116, 124, 70),
    "cuneta": (153, 113, 86),
    "cuneta_02": (141, 109, 91),
    "corte_tierra_rojiza": (173, 108, 81),
    "talud": (119, 113, 132),
    "talud_02": (156, 102, 86),
    "talud_03": (141, 133, 147),
    "pedregal": (128, 117, 129),
    "pedregal_02": (142, 127, 134),
    "roca_suelta": (119, 113, 132),
    "roca_suelta_02": (134, 127, 143),
}


def edges(pixels):
    return tuple(float(np.mean(np.abs(axis[0] - axis[-1]))) for axis in (pixels, pixels.swapaxes(0, 1)))


def soften_repeating_marks(image, role):
    if role.startswith("carretera"):
        return image
    pixels = np.array(image, dtype=np.float32)
    rgb = pixels[:, :, :3]
    luminance = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    height, width = luminance.shape
    radius = max(2, round(min(width, height) * 0.085))
    padding = radius * 4
    wrapped = np.pad(luminance, padding, mode="wrap")
    blurred = Image.fromarray(np.rint(wrapped).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))
    broad = np.asarray(blurred, dtype=np.float32)[padding:padding + height, padding:padding + width]
    strength = 0.68 if role.startswith(("talud", "pedregal", "roca", "cuneta")) else 0.40
    pixels[:, :, :3] = np.clip(rgb - ((broad - broad.mean()) * strength)[:, :, None], 0, 255)
    return Image.fromarray(np.rint(pixels).astype(np.uint8))


def seamless(image):
    pixels = np.array(image, dtype=np.float32)
    before = edges(pixels)
    for axis in (pixels, pixels.swapaxes(0, 1)):
        width = max(2, round(len(axis) * 0.12))
        first = axis[:width]
        last = axis[-width:][::-1]
        weight = np.linspace(1.0, 0.0, width, dtype=np.float32)[:, None, None]
        weight = weight * weight * (3.0 - 2.0 * weight)
        correction = (last - first) * (0.5 * weight)
        first += correction
        last -= correction
    result = np.rint(pixels).astype(np.uint8)
    after = edges(result.astype(np.float32))
    if after != (0.0, 0.0):
        raise ValueError(f"Opposite edges differ after blending: {after}")
    return Image.fromarray(result), before


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGB", (1000, ((len(SELECTION) + 4) // 5) * 220), "#202029")
    labels = ImageDraw.Draw(sheet)
    report = ["textura,borde_vertical_antes,borde_horizontal_antes,ambos_despues"]
    for index, role in enumerate(SELECTION):
        filename = role + ".png"
        target = TARGETS[role] if role in TARGETS else TARGETS[role.rsplit("_", 1)[0]]
        with Image.open(args.source / filename) as original:
            result, before = seamless(soften_repeating_marks(grade(original.convert("RGBA"), target), role))
        result.save(args.output / filename)
        report.append(f"{role},{before[0]:.2f},{before[1]:.2f},0")
        tile = result.resize((40, 40), Image.Resampling.LANCZOS)
        left, top = index % 5 * 200, index // 5 * 220
        for row in range(5):
            for column in range(5):
                sheet.paste(tile, (left + column * 40, top + row * 40), tile)
        labels.text((left + 3, top + 203), role, fill="white")
    sheet.save(args.output.parent / "cobre_cobalto_mosaico.png")
    (args.output.parent / "cobre_cobalto_costuras.csv").write_text("\n".join(report) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
