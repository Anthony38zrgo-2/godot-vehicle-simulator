"""Render before/after plates for a cleaned bank (Pillow, evidence for the report).

Usage:
    python -m tools.audio.render_commons_ab
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from tools.audio import commons_audit as audit
from tools.audio.analyze_commons_bank import spectrogram_image, waveform_block

ROOT = Path(__file__).resolve().parents[2]
BEFORE = ROOT / "game" / "sounds" / "banks" / "commons"
AFTER = ROOT / "tmp" / "commons_clean_v1"
OUT = ROOT / "tmp" / "commons_audio_audit" / "plots"

# Files where the change is worth looking at: sub-bass removal, clipping, loop wrap.
SUBJECTS = ["impact_small_1", "impact_land_2", "backfire_9", "impact_scrape"]


def render(before: Path, after: Path, out: Path) -> Path | None:
    from PIL import Image, ImageDraw, ImageFont

    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 15)
        small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 12)
    except OSError:
        font = small = ImageFont.load_default()

    width, wave_h, spec_h, label_h, gap = 620, 55, 115, 20, 8
    block_h = label_h + wave_h + spec_h + gap
    sheet = Image.new("RGB", (width * 2 + 40, block_h * len(SUBJECTS) + 40), (10, 10, 12))
    draw = ImageDraw.Draw(sheet)
    draw.text((16, 8), "antes (izquierda) / despues (derecha) - mismo escalado por archivo",
              fill=(220, 220, 230), font=font)

    y = 32
    for stem in SUBJECTS:
        src = before / f"{stem}.wav"
        dst = after / f"{stem}.wav"
        if not src.exists() or not dst.exists():
            continue
        wav_a = audit.read_wav(src)
        wav_b = audit.read_wav(dst)
        xa, xb = wav_a.mono(), wav_b.mono()
        scale = max(float(np.max(np.abs(xa))), float(np.max(np.abs(xb)))) or 1.0

        for column, (wav, x) in enumerate(((wav_a, xa), (wav_b, xb))):
            x0 = 16 + column * (width + 8)
            draw.text((x0, y), f"{wav.path.name}  {audit.db(np.max(np.abs(x))):.1f} dBFS pico",
                      fill=(235, 235, 240), font=font)
            sheet.paste(waveform_block(x / scale, width, wave_h), (x0, y + label_h))
            sheet.paste(spectrogram_image(x / scale, wav.rate, width, spec_h),
                        (x0, y + label_h + wave_h))
            draw.text((x0, y + label_h + wave_h + spec_h + 1), "30 Hz -> Nyquist (log)",
                      fill=(120, 120, 130), font=small)
        y += block_h

    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, default=BEFORE)
    parser.add_argument("--after", type=Path, default=AFTER)
    parser.add_argument("--out", type=Path, default=OUT / "04_antes_despues.png")
    args = parser.parse_args(argv)
    target = render(args.before, args.after, args.out)
    print(f"Imagen: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
