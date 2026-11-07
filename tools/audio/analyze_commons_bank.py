"""Audit every WAV in the shared ``commons`` bank and emit objective findings.

Usage:
    python -m tools.audio.analyze_commons_bank
    python -m tools.audio.analyze_commons_bank --bank game/sounds/banks/commons --plots

Writes ``<out>/commons_audit.json`` and ``<out>/commons_audit.md`` plus optional
contact sheets under ``<out>/plots``. Read-only with respect to the bank.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np

from tools.audio import commons_audit as audit

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "game" / "sounds" / "banks" / "commons"
OUT = ROOT / "tmp" / "commons_audio_audit"

# Variation groups: samples the runtime picks between for the same event.
# Mix stability depends on them being loudness- and timbre-consistent.
GROUPS: dict[str, list[str]] = {
    "impact_small": ["impact_small_1", "impact_small_2", "impact_small_3"],
    "impact_medium": ["impact_medium_1", "impact_medium_2"],
    "impact_large": ["impact_large"],
    "impact_land": ["impact_land_1", "impact_land_2", "impact_land_3"],
    "backfire_ext": ["backfire_ext_1", "backfire_ext_2", "backfire_ext_3", "backfire_ext_4"],
    "backfire_cabin": ["backfire_5", "backfire_int"],
    "gearbox_f2002": ["f2002_gearup", "f2002_geardn"],
    "wheel_damage_loop": ["flat_tyre_mono", "damaged_rin", "bad_brakes"],
}

# Roles that the runtime plays as a continuous loop (verified against
# rally_vehicle_audio.gd: load_looping_stream / wheel damage players).
RUNTIME_LOOPS = {
    "limiter_cut_loop",
    "flat_tyre_mono",
    "damaged_rin",
    "bad_brakes",
    "impact_scrape",  # 2.6 s one-shot played through continuous_player()
}

# Per-file runtime gain from game/data/rally/audio_mixer.json (linear volume)
# and the extra dB offsets applied in rally_vehicle_audio.gd.
RUNTIME_GAIN_DB = {
    "impact_small_1": -12.0,
    "impact_small_2": -12.0,
    "impact_small_3": -12.0,
    "impact_medium_1": -9.0,
    "impact_medium_2": -9.0,
    "impact_large": -6.0,
    "impact_land_1": -24.0,
    "impact_land_2": -21.0,
    "impact_land_3": -18.0,
}

# Thresholds are explicit so the report can be audited and tuned.
LIMITS = {
    "hot_true_peak_dbfs": -0.3,
    "one_shot_ceiling_dbfs": -1.5,
    "group_loudness_spread_lu": 1.5,
    "seam_ratio_warn": 2.5,
    "seam_ratio_critical": 6.0,
    "seam_rms_step_db": 4.0,
    "lead_silence_warn_ms": 30.0,
    "lead_silence_info_ms": 15.0,
    "head_step_dbfs": -20.0,
    "tail_step_rel_db": -25.0,
    "sub_30_ratio": 0.05,
    "dc_dbfs": -45.0,
    "hum_prominence_db": 12.0,
    "noise_floor_dbfs": -65.0,
    "manifest_duration_tol_s": 0.010,
    "manifest_peak_tol": 0.005,
}


def load_manifest(bank: Path) -> dict:
    path = bank / "bank_manifest.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def manifest_index(manifest: dict) -> dict[str, dict]:
    return {entry["file"]: entry for entry in manifest.get("files", [])}


def find_duplicates(entries: list[dict]) -> dict[str, list[str]]:
    by_hash: dict[str, list[str]] = {}
    for entry in entries:
        by_hash.setdefault(entry["sha256"], []).append(entry["file"])
    return {h: files for h, files in by_hash.items() if len(files) > 1}


def flag_file(entry: dict, is_loop: bool) -> list[dict]:
    """High-signal per-file defects. Bank-wide aggregates live in bank_findings."""
    flags: list[dict] = []

    def add(level: str, code: str, message: str) -> None:
        flags.append({"level": level, "code": code, "message": message})

    if not entry["runtime_loadable"]:
        add("critical", "not_runtime_loadable",
            f"El cargador PCM del juego rechaza este WAV ({entry['runtime_reason']}).")

    if entry["true_peak_dbfs"] >= LIMITS["hot_true_peak_dbfs"]:
        add("warn", "hot_true_peak",
            f"Pico real {entry['true_peak_dbfs']:+.2f} dBFS: no hay margen para el remuestreo "
            f"44.1->48 kHz ni para la suma de voces simultaneas.")

    if entry["flat_top_runs"] > 0:
        add("warn", "flat_top",
            f"{entry['flat_top_runs']} tramos planos en el pico: el origen ya estaba limitado "
            f"o recortado.")

    if entry["sub_30_ratio"] > LIMITS["sub_30_ratio"]:
        add("warn", "sub_rumble",
            f"{entry['sub_30_ratio'] * 100:.1f} % de la energia esta por debajo de 30 Hz "
            f"(no se reproduce en altavoces pequenos y consume headroom).")

    if entry["hum_prominence_db"] > LIMITS["hum_prominence_db"]:
        add("warn", "mains_hum",
            f"Componente de red electrica {entry['hum_prominence_db']:.0f} dB sobre el fondo.")

    floor = entry["noise_floor_dbfs"]
    if floor > LIMITS["noise_floor_dbfs"] and (entry["head_region_s"] > 0.02 or
                                              entry["tail_region_s"] > 0.02):
        add("warn", "noise_floor",
            f"El silencio previo/posterior no esta limpio ({floor:.1f} dBFS): suena como hiss "
            f"al disparar y se acumula con la reverb.")

    lead_ms = entry["lead_silence_s"] * 1000.0
    if lead_ms > LIMITS["lead_silence_warn_ms"]:
        add("warn", "lead_silence",
            f"{lead_ms:.0f} ms de silencio antes del ataque: el golpe llega tarde y desalinea "
            f"el impacto visual.")
    elif lead_ms > LIMITS["lead_silence_info_ms"]:
        add("info", "lead_silence",
            f"{lead_ms:.0f} ms de silencio antes del ataque.")

    if not is_loop and entry["head_step_rel_db"] > LIMITS["head_step_dbfs"]:
        add("warn", "head_step",
            f"El primer sample entra a {entry['head_step_rel_db']:+.0f} dB del pico: el ataque "
            f"empieza en mitad de la onda y genera un escalon al disparar.")

    if not is_loop and entry["tail_step_rel_db"] > LIMITS["tail_step_rel_db"]:
        add("info", "tail_step",
            f"El buffer corta a {entry['tail_step_rel_db']:+.0f} dB del pico (el runtime aplica "
            f"rampa de release en la mayoria de claves, pero no en todas).")

    if entry["dc_offset_dbfs"] > LIMITS["dc_dbfs"]:
        add("info", "dc_offset", f"Offset DC a {entry['dc_offset_dbfs']:.1f} dBFS.")

    if is_loop:
        seam = entry["seam"]
        if seam.get("seam_ratio", 0.0) > LIMITS["seam_ratio_critical"]:
            add("critical", "loop_seam_click",
                f"Salto de {abs(seam['seam_step']) * 32768:.0f} LSB al cerrar el loop "
                f"({seam['seam_ratio']:.1f}x el paso tipico): click audible cada vuelta.")
        elif seam.get("seam_ratio", 0.0) > LIMITS["seam_ratio_warn"]:
            add("warn", "loop_seam_step",
                f"Discontinuidad de {seam['seam_ratio']:.1f}x el paso tipico al cerrar el loop.")
        if abs(seam.get("seam_head_tail_rms_db", 0.0)) > LIMITS["seam_rms_step_db"]:
            add("warn", "loop_level_step",
                f"El cierre queda {seam['seam_head_tail_rms_db']:+.1f} dB respecto al inicio: "
                f"pulso de amplitud en cada vuelta.")

    return flags


def group_checks(by_stem: dict[str, dict]) -> list[dict]:
    findings = []
    for group, files in GROUPS.items():
        present = [by_stem[f] for f in files if f in by_stem]
        if len(present) < 2:
            continue
        loud = [(e["file"], e["event_lufs"]) for e in present if e["event_lufs"] > -70]
        if len(loud) < 2:
            continue
        values = [value for _, value in loud]
        spread = max(values) - min(values)
        if spread > LIMITS["group_loudness_spread_lu"]:
            findings.append({
                "level": "critical" if spread > 3.0 else "warn",
                "code": "group_loudness_spread",
                "group": group,
                "spread_lu": round(spread, 2),
                "message": (f"{group}: {spread:.2f} LU de diferencia entre variantes "
                            f"({', '.join(f'{n} {v:.1f}' for n, v in loud)}). "
                            f"La seleccion aleatoria salta de volumen."),
            })
        cents = [(e["file"], e["centroid_hz"]) for e in present]
        lo = min(c for _, c in cents)
        hi = max(c for _, c in cents)
        if lo > 0 and hi / lo > 2.0:
            findings.append({
                "level": "info",
                "code": "group_timbre_spread",
                "group": group,
                "message": (f"{group}: centroide espectral {lo:.0f}-{hi:.0f} Hz "
                            f"({hi / lo:.1f}x). Timbre poco coherente entre variantes."),
            })
    return findings


def tier_findings(rows: list[dict]) -> list[dict]:
    """Velocity tiers must get louder as the tier grows, once runtime gain applies."""
    findings = []
    tier = [r for r in rows if r["file"].startswith("impact_land")]
    if len(tier) >= 2:
        values = [r["lufs_after_gain"] for r in tier]
        if any(values[i] > values[i + 1] + 0.5 for i in range(len(values) - 1)):
            detail = ", ".join(f"{r['file']} {r['lufs_after_gain']:.1f}" for r in tier)
            findings.append({
                "level": "critical",
                "code": "tier_layering_inverted",
                "group": "impact_land",
                "message": (f"impact_land: tras la ganancia de runtime el nivel no crece con la "
                            f"caida ({detail}). Una toma de tierra fuerte suena mas floja que "
                            f"una media."),
            })

    # A small crash must stay below a medium one, and medium below large.
    order = ["impact_small", "impact_medium", "impact_large"]
    sizes = []
    for prefix in order:
        tier_rows = [r for r in rows if r["file"].startswith(prefix)]
        if tier_rows:
            sizes.append((prefix, max(r["lufs_after_gain"] for r in tier_rows)))
    if len(sizes) >= 2:
        values = [v for _, v in sizes]
        if any(values[i] > values[i + 1] + 0.5 for i in range(len(values) - 1)):
            detail = ", ".join(f"{n} {v:.1f}" for n, v in sizes)
            findings.append({
                "level": "critical",
                "code": "impact_size_layering_inverted",
                "message": (f"El nivel efectivo no crece con la severidad del impacto ({detail}). "
                            f"Un choque leve suena igual o mas fuerte que uno grave."),
            })
    return findings


def runtime_audition(by_stem: dict[str, dict]) -> list[dict]:
    """Effective level each sample reaches after the runtime gain stage."""
    rows = []
    for name, gain_db in RUNTIME_GAIN_DB.items():
        e = by_stem.get(name)
        if e is None:
            continue
        rows.append({
            "file": name,
            "lufs_source": round(e["event_lufs"], 2),
            "runtime_gain_db": gain_db,
            "lufs_after_gain": round(e["event_lufs"] + gain_db, 2),
        })
    return rows


def manifest_drift(manifest: dict, files_on_disk: set[str]) -> dict:
    listed = {entry["file"] for entry in manifest.get("files", [])}
    return {
        "listed_missing_on_disk": sorted(listed - files_on_disk),
        "on_disk_not_listed": sorted(files_on_disk - listed),
    }


def manifest_integrity(manifest: dict, by_name: dict[str, dict]) -> list[dict]:
    """Detect WAVs edited after their manifest entry was generated."""
    findings = []
    for entry in manifest.get("files", []):
        measured = by_name.get(entry["file"])
        if measured is None:
            continue
        expected_sha = entry.get("sha256")
        if expected_sha and expected_sha != measured["sha256"]:
            findings.append({
                "level": "critical",
                "code": "manifest_sha_mismatch",
                "file": entry["file"],
                "message": (f"El WAV no coincide con el sha256 del manifiesto: el sample se "
                            f"edito y el manifiesto quedo desactualizado."),
            })
        expected_dur = entry.get("duration_s")
        if isinstance(expected_dur, (int, float)) and \
                abs(float(expected_dur) - measured["duration_s"]) > LIMITS["manifest_duration_tol_s"]:
            findings.append({
                "level": "warn",
                "code": "manifest_duration_mismatch",
                "file": entry["file"],
                "message": (f"Duracion declarada {float(expected_dur):.3f}s vs medida "
                            f"{measured['duration_s']:.3f}s."),
            })
        expected_peak = entry.get("peak")
        if isinstance(expected_peak, (int, float)) and \
                abs(float(expected_peak) - measured["peak"]) > LIMITS["manifest_peak_tol"]:
            findings.append({
                "level": "warn",
                "code": "manifest_peak_mismatch",
                "file": entry["file"],
                "message": (f"Pico declarado {float(expected_peak):.3f} vs medido "
                            f"{measured['peak']:.3f}."),
            })
    return findings


def bank_findings(entries: list[dict]) -> list[dict]:
    findings = []
    one_shots = [e for e in entries if not e["loop"]]
    hot = [e for e in one_shots if e["true_peak_dbfs"] > LIMITS["one_shot_ceiling_dbfs"]]
    if hot:
        findings.append({
            "level": "critical",
            "code": "bank_peak_ceiling",
            "message": (f"{len(hot)}/{len(one_shots)} one-shots terminan por encima de "
                        f"{LIMITS['one_shot_ceiling_dbfs']:.1f} dBFS de pico real; el compresor "
                        f"de bus (umbral -0.45 dBFS, 3.5:1) se dispara con eventos aislados y "
                        f"bombea el motor y el escape."),
        })
    rates = {(e["sample_rate"], e["bits"], e["channels"]) for e in entries}
    if len(rates) > 1:
        stereo = [e["file"] for e in entries if e["channels"] > 1]
        findings.append({
            "level": "warn",
            "code": "bank_format_mixed",
            "message": (f"Formatos mezclados en el banco: {sorted(rates)}. "
                        f"Estereo: {', '.join(stereo) or 'ninguno'}."),
        })
    return findings



# --------------------------------------------------------------------------- #
# Plots (Pillow, optional)
# --------------------------------------------------------------------------- #


def _colour(value: float) -> tuple[int, int, int]:
    """Compact inferno-like ramp for spectrograms."""
    v = min(max(value, 0.0), 1.0)
    r = int(255 * min(1.0, max(0.0, 1.6 * v - 0.15)))
    g = int(255 * min(1.0, max(0.0, 1.35 * v ** 1.6 - 0.05)))
    b = int(255 * min(1.0, max(0.0, 0.55 * abs(math.sin(math.pi * (v * 0.75 + 0.12))))))
    return r, g, b


def spectrogram_image(x: np.ndarray, fs: int, width: int, height: int,
                      nfft: int = 1024) -> "object":
    from PIL import Image

    hop = max(1, (x.size - nfft) // width) if x.size > nfft else 1
    freqs = np.fft.rfftfreq(nfft, 1.0 / fs)
    # Log-frequency rows from 30 Hz to Nyquist.
    rows = np.geomspace(30.0, max(fs / 2 - 1, 31.0), height)[::-1]
    row_idx = np.searchsorted(freqs, rows).clip(0, freqs.size - 1)
    win = np.hanning(nfft)
    columns = np.zeros((height, width), dtype=np.float32)
    for col in range(width):
        start = int(col * hop)
        seg = x[start:start + nfft]
        if seg.size < nfft:
            seg = np.pad(seg, (0, nfft - seg.size))
        mag = np.abs(np.fft.rfft(seg * win)) + 1e-12
        db = 20.0 * np.log10(mag / (nfft / 4))
        columns[:, col] = db[row_idx]
    lo, hi = -85.0, 0.0
    norm = (np.clip(columns, lo, hi) - lo) / (hi - lo)
    rgba = [tuple(_colour(float(v)) ) for v in norm.ravel()]
    img = Image.new("RGB", (width, height))
    img.putdata(rgba)
    return img


def waveform_block(x: np.ndarray, width: int, height: int) -> "object":
    from PIL import Image, ImageDraw

    img = Image.new("RGB", (width, height), (18, 18, 22))
    draw = ImageDraw.Draw(img)
    draw.line([(0, height // 2), (width, height // 2)], fill=(45, 45, 55))
    if x.size == 0:
        return img
    per = max(1, x.size // width)
    for col in range(width):
        chunk = x[col * per:(col + 1) * per]
        if chunk.size == 0:
            break
        lo, hi = float(np.min(chunk)), float(np.max(chunk))
        draw.line([(col, int(height / 2 * (1 - hi))), (col, int(height / 2 * (1 - lo)))],
                  fill=(120, 200, 255))
    return img


def render_sheets(paths: list[Path], out_dir: Path) -> list[Path]:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Pillow no disponible: se omiten los gráficos.")
        return []

    out_dir.mkdir(parents=True, exist_ok=True)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 15)
        small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 12)
    except OSError:
        font = small = ImageFont.load_default()

    width, wave_h, spec_h, label_h = 900, 60, 130, 22
    groups = {
        "01_impacts": [p for p in paths if p.stem.startswith("impact_")],
        "02_backfire_gearbox": [p for p in paths
                                if p.stem.startswith(("backfire", "f2002", "tyre_contact"))],
        "03_loops": [p for p in paths
                     if p.stem in {"limiter_cut_loop", "flat_tyre_mono", "damaged_rin",
                                   "bad_brakes"}],
    }
    written = []
    for name, files in groups.items():
        if not files:
            continue
        block_h = label_h + wave_h + spec_h + 14
        sheet = Image.new("RGB", (width + 20, block_h * len(files) + 10), (10, 10, 12))
        draw = ImageDraw.Draw(sheet)
        y = 6
        for path in sorted(files):
            wav = audit.read_wav(path)
            x = wav.mono()
            peak = float(np.max(np.abs(x))) or 1.0
            draw.text((10, y), f"{path.name}  {wav.duration:.2f}s  peak "
                               f"{audit.db(peak):.1f} dBFS  {wav.rate} Hz",
                      fill=(235, 235, 240), font=font)
            y += label_h
            sheet.paste(waveform_block(x / peak if peak else x, width, wave_h), (10, y))
            y += wave_h
            sheet.paste(spectrogram_image(x / peak if peak else x, wav.rate, width, spec_h), (10, y))
            y += spec_h
            draw.text((10, y), "30 Hz -> Nyquist (log), -85..0 dB", fill=(120, 120, 130),
                      font=small)
            y += 14
        target = out_dir / f"{name}.png"
        sheet.save(target)
        written.append(target)
    return written


# --------------------------------------------------------------------------- #
# Report
# --------------------------------------------------------------------------- #


def fmt(value, digits=2) -> str:
    if isinstance(value, float):
        if not math.isfinite(value):
            return "-inf"
        return f"{value:.{digits}f}"
    return str(value)


def write_markdown(path: Path, entries: list[dict], findings: list[dict],
                   drift: dict, duplicates: dict, audition: list[dict], bank: Path,
                   by_stem: dict[str, dict]) -> None:
    lines: list[str] = []
    lines.append("# Auditoría objetiva del banco `commons`\n")
    lines.append(f"Banco: `{bank.as_posix()}`\n")
    lines.append(f"Archivos medidos: {len(entries)}\n")
    critical = sum(1 for f in findings if f["level"] == "critical")
    warn = sum(1 for f in findings if f["level"] == "warn")
    info = sum(1 for f in findings if f["level"] == "info")
    lines.append(f"Hallazgos: {critical} críticos, {warn} avisos, {info} informativos.\n")

    lines.append("\n## Métricas por archivo\n")
    lines.append("| archivo | s | LUFS | evLUFS | peak | TP | crest | centro Hz | sub30 % "
                 "| seam x | inicio dB | fin dB | fondo dBFS |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for e in sorted(entries, key=lambda i: i["file"]):
        seam = e["seam"].get("seam_ratio")
        seam_cell = f"{seam:.2f}" if (seam is not None and e["loop"]) else "n/a"
        lines.append(
            f"| {e['file']} | {e['duration_s']:.2f} | {fmt(e['lufs'], 1)} "
            f"| {fmt(e['event_lufs'], 1)} | {e['peak_dbfs']:.1f} "
            f"| {e['true_peak_dbfs']:.2f} | {e['crest_db']:.1f} | {e['centroid_hz']:.0f} "
            f"| {e['sub_30_ratio'] * 100:.1f} | {seam_cell} "
            f"| {e['start_db']:.0f} | {e['end_db']:.0f} | {e['noise_floor_dbfs']:.0f} |")

    lines.append("\n## Hallazgos\n")
    for finding in findings:
        target = f" `{finding['file']}`" if finding.get("file") else ""
        lines.append(f"- **{finding['level'].upper()}** `{finding['code']}`{target} — "
                     f"{finding['message']}")

    lines.append("\n## Variación entre muestras del mismo evento\n")
    lines.append("| grupo | archivos | LUFS min..max | dispersión LU | centroide Hz |")
    lines.append("|---|---|---|---|---|")
    for group, files in GROUPS.items():
        present = [by_stem[f] for f in files if f in by_stem]
        if not present:
            continue
        loud = [e["event_lufs"] for e in present if e["event_lufs"] > -70]
        cents = [e["centroid_hz"] for e in present]
        if loud:
            lines.append(f"| {group} | {len(present)} | {min(loud):.1f}..{max(loud):.1f} "
                         f"| {max(loud) - min(loud):.2f} | {min(cents):.0f}..{max(cents):.0f} |")

    lines.append("\n## Duplicados bit a bit\n")
    if duplicates:
        for digest, files in duplicates.items():
            lines.append(f"- `{digest[:12]}` -> {', '.join(files)}")
    else:
        lines.append("- ninguno")

    lines.append("\n## Deriva manifiesto <-> disco\n")
    lines.append(f"- listados en el manifiesto pero ausentes: {drift['listed_missing_on_disk']}")
    lines.append(f"- presentes en disco pero no listados: {drift['on_disk_not_listed']}")

    lines.append("\n## Nivel efectivo tras la ganancia de runtime\n")
    lines.append("| archivo | LUFS fuente | ganancia dB | LUFS tras ganancia |")
    lines.append("|---|---|---|---|")
    for row in audition:
        lines.append(f"| {row['file']} | {row['lufs_source']:.2f} | {row['runtime_gain_db']:+.1f} "
                     f"| {row['lufs_after_gain']:.2f} |")

    lines.append("\n## Bandas (dB relativos a la energía total)\n")
    header = "| archivo | " + " | ".join(name for name, _, _ in audit.BANDS) + " |"
    lines.append(header)
    lines.append("|---" * (len(audit.BANDS) + 1) + "|")
    for e in sorted(entries, key=lambda i: i["file"]):
        cells = " | ".join(f"{e['band_db'][name]:.1f}" for name, _, _ in audit.BANDS)
        lines.append(f"| {e['file']} | {cells} |")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bank", type=Path, default=BANK)
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument("--plots", action="store_true")
    args = parser.parse_args(argv)

    bank: Path = args.bank
    paths = sorted(bank.glob("*.wav"))
    if not paths:
        print(f"No hay WAV en {bank}")
        return 1

    print(f"Analizando {len(paths)} WAV en {bank}")
    entries = []
    for path in paths:
        entry = audit.analyse(path)
        entries.append(entry)
        print(f"  {path.name:34s} {entry['duration_s']:6.3f}s  LUFS {fmt(entry['lufs'], 1):>7}  "
              f"TP {entry['true_peak_dbfs']:6.2f} dBFS")

    by_name = {e["file"]: e for e in entries}
    by_stem = {Path(e["file"]).stem: e for e in entries}
    manifest = load_manifest(bank)
    manifest_roles = manifest_index(manifest)

    findings: list[dict] = []
    for entry in entries:
        stem = Path(entry["file"]).stem
        manifest_entry = manifest_roles.get(entry["file"], {})
        is_loop = (stem in RUNTIME_LOOPS) or bool(manifest_entry.get("loop", False))
        entry["loop"] = is_loop
        entry["manifest_role"] = manifest_entry.get("role")
        entry["flags"] = flag_file(entry, is_loop)
        for flag in entry["flags"]:
            flag["file"] = entry["file"]
            findings.append(flag)

    group_findings = group_checks(by_stem)
    findings.extend(group_findings)

    audition = runtime_audition(by_stem)
    findings.extend(tier_findings(audition))

    duplicates = find_duplicates(entries)
    if duplicates:
        groups_text = "; ".join(", ".join(files) for files in duplicates.values())
        findings.append({
            "level": "critical",
            "code": "duplicate_asset",
            "message": (f"{sum(len(v) for v in duplicates.values())} archivos en "
                        f"{len(duplicates)} grupos son identicos bit a bit ({groups_text}): "
                        f"la variacion aleatoria no varia y, si dos voces coinciden en el "
                        f"tiempo, suman en fase."),
        })

    drift = manifest_drift(manifest, {e["file"] for e in entries})
    if drift["listed_missing_on_disk"]:
        findings.append({
            "level": "critical",
            "code": "manifest_missing_file",
            "message": ("El manifiesto declara WAV que no existen en disco: "
                        + ", ".join(drift["listed_missing_on_disk"])),
        })
    if drift["on_disk_not_listed"]:
        findings.append({
            "level": "warn",
            "code": "manifest_orphan_file",
            "message": ("WAV en disco sin entrada en el manifiesto: "
                        + ", ".join(drift["on_disk_not_listed"])),
        })

    findings.extend(manifest_integrity(manifest, by_name))
    findings.extend(bank_findings(entries))

    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    payload = {
        "bank": str(bank.relative_to(ROOT)) if bank.is_relative_to(ROOT) else str(bank),
        "limits": LIMITS,
        "entries": entries,
        "findings": findings,
        "groups": GROUPS,
        "manifest_drift": drift,
        "duplicates": duplicates,
        "runtime_audition": audition,
    }
    (out / "commons_audit.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    write_markdown(out / "commons_audit.md", entries, findings, drift,
                   duplicates, audition, bank, by_stem)

    if args.plots:
        written = render_sheets(paths, out / "plots")
        print(f"Gráficos: {len(written)}")

    critical = sum(1 for f in findings if f["level"] == "critical")
    warn = sum(1 for f in findings if f["level"] == "warn")
    print(f"\nHallazgos: {critical} críticos, {warn} avisos, "
          f"{sum(1 for f in findings if f['level'] == 'info')} informativos")
    print(f"Informe: {out / 'commons_audit.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
