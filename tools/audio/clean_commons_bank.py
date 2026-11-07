"""Render corrected copies of the ``commons`` bank (never overwrites by default).

Usage:
    python -m tools.audio.clean_commons_bank                     # -> tmp/commons_clean_v1
    python -m tools.audio.clean_commons_bank --ceiling -3 --no-groups
    python -m tools.audio.clean_commons_bank --in-place          # rewrites the bank

Chain, applied in this order:
  1. mean removal + 8 Hz high-pass          (DC and sub-sonic drift)
  2. role high-pass 30/35 Hz                (inaudible rumble that eats headroom)
  3. pre-attack hiss gate + lead trim       (silence before the transient)
  4. de-click fades on truncated edges      (step at buffer start/end)
  5. loop wrap repair                       (equal-power crossfade + trim)
  6. loudness match inside a variation group (random picks stop jumping in level)
  7. true-peak ceiling (attenuate only)     (headroom for the 3.5:1 bus compressor)
  8. TPDF dither -> PCM16

Everything is measured before and after; the before/after table plus a manifest
patch proposal are written next to the WAVs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from tools.audio import commons_audit as audit

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "game" / "sounds" / "banks" / "commons"
OUT = ROOT / "tmp" / "commons_clean_v1"

# Runtime loops (see rally_vehicle_audio.gd) and the one-shot played as a loop.
RUNTIME_LOOPS = {"limiter_cut_loop", "flat_tyre_mono", "damaged_rin", "bad_brakes"}
LOOPED_ONE_SHOTS = {"impact_scrape"}

# Samples the runtime picks between for the same event: they must match in level.
MATCH_GROUPS: dict[str, list[str]] = {
    "impact_small": ["impact_small_1", "impact_small_2", "impact_small_3"],
    "impact_medium": ["impact_medium_1", "impact_medium_2"],
    "impact_land": ["impact_land_1", "impact_land_2", "impact_land_3"],
    "backfire_ext": ["backfire_ext_1", "backfire_ext_2", "backfire_ext_3", "backfire_ext_4"],
    "gearbox_f2002": ["f2002_geardn", "f2002_gearup"],
}


@dataclass
class Recipe:
    stem: str
    loop: bool
    hp_hz: float
    trim_lead: bool = True
    head_fade_ms: float = 0.0
    tail_fade_ms: float = 0.0
    seam_crossfade_ms: float | None = None
    actions: list[str] = field(default_factory=list)


def build_recipe(stem: str, is_loop: bool) -> Recipe:
    if stem in RUNTIME_LOOPS:
        return Recipe(stem, True, 35.0, trim_lead=False, seam_crossfade_ms=40.0)
    if stem in LOOPED_ONE_SHOTS:
        return Recipe(stem, True, 30.0, trim_lead=False, seam_crossfade_ms=60.0)
    return Recipe(stem, False, 30.0, trim_lead=True, head_fade_ms=0.4, tail_fade_ms=3.0)


def clean_one(path: Path, recipe: Recipe) -> tuple[np.ndarray, int, list[str]]:
    wav = audit.read_wav(path)
    x = wav.mono()
    fs = wav.rate
    if wav.channels > 1:
        recipe.actions.append(f"downmix {wav.channels}->1")

    # 1-2. DC + role high-pass.
    x = audit.remove_dc(x, fs, cutoff_hz=8.0)
    x = audit.fft_filter(x, [audit.biquad_highpass(recipe.hp_hz, fs)], fs)
    recipe.actions.append(f"hpf {recipe.hp_hz:.0f} Hz")

    # 3. Gate the pre-attack hiss and trim the dead lead (keeps 1 ms pre-roll).
    if not recipe.loop:
        level = audit.onset_and_silence(x, fs)
        head_floor = x[: max(1, int(float(level["onset_s"]) * fs))]
        if head_floor.size > int(0.005 * fs) and audit.db(audit.rms(head_floor)) > -78.0:
            gated = audit.gate_head_noise(x, fs, float(level["onset_s"]), -82.0)
            if not np.array_equal(gated, x):
                x = gated
                recipe.actions.append("gate pre-attack hiss")
        if recipe.trim_lead and float(level["onset_s"]) > 0.002:
            onset_n = int(float(level["onset_s"]) * fs)
            keep = max(0, onset_n - int(0.001 * fs))
            if keep > 0:
                x = x[keep:]
                recipe.actions.append(f"trim {keep / fs * 1000:.1f} ms lead")

    # 4. De-click the edges only when they are actually truncated.
    peak_db = audit.db(float(np.max(np.abs(x)))) if x.size else -120.0
    if not recipe.loop:
        if audit.db(abs(float(x[0]))) - peak_db > -20.0 and recipe.head_fade_ms > 0:
            x = audit.fade_edges(x, fs, recipe.head_fade_ms, 0.0)
            recipe.actions.append(f"fade-in {recipe.head_fade_ms} ms")
        if audit.db(abs(float(x[-1]))) - peak_db > -25.0 and recipe.tail_fade_ms > 0:
            x = audit.fade_edges(x, fs, 0.0, recipe.tail_fade_ms)
            recipe.actions.append(f"fade-out {recipe.tail_fade_ms} ms")

    # 5. Loop wrap: crossfade the tail into the head, then trim the tail.
    if recipe.seam_crossfade_ms:
        steps = np.abs(np.diff(x))
        typical = float(np.percentile(steps, 99.0)) or 1e-9
        if abs(float(x[0] - x[-1])) > typical:
            x, repaired = audit.repair_loop_seam(x, fs, recipe.seam_crossfade_ms)
            if repaired:
                recipe.actions.append(f"loop crossfade {recipe.seam_crossfade_ms:.0f} ms")

    return x, fs, recipe.actions


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bank", type=Path, default=BANK)
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument("--ceiling", type=float, default=-3.0,
                        help="true-peak ceiling in dBFS")
    parser.add_argument("--max-reduction", type=float, default=3.0,
                        help="maximum limiter gain reduction before falling back to attenuation")
    parser.add_argument("--no-groups", action="store_true",
                        help="skip loudness matching inside variation groups")
    parser.add_argument("--in-place", action="store_true",
                        help="overwrite the bank WAVs (a backup is written first)")
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args(argv)

    bank: Path = args.bank
    paths = sorted(bank.glob("*.wav"))
    if not paths:
        print(f"No hay WAV en {bank}")
        return 1

    manifest_path = bank / "bank_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    manifest_by_name = {e["file"]: e for e in manifest.get("files", [])}

    rows: list[dict] = []
    buffers: dict[str, np.ndarray] = {}
    rates: dict[str, int] = {}

    print(f"Procesando {len(paths)} WAV")
    for path in paths:
        stem = path.stem
        before = audit.analyse(path)
        is_loop = stem in RUNTIME_LOOPS or stem in LOOPED_ONE_SHOTS or \
            bool(manifest_by_name.get(path.name, {}).get("loop", False))
        recipe = build_recipe(stem, is_loop)
        x, fs, actions = clean_one(path, recipe)
        buffers[stem] = x
        rates[stem] = fs
        rows.append({
            "file": path.name,
            "loop": is_loop,
            "actions": actions,
            "sha_before": before["sha256"],
            "before": {
                "lufs": before["event_lufs"],
                "true_peak_dbfs": before["true_peak_dbfs"],
                "sub_30_ratio": before["sub_30_ratio"],
                "seam_ratio": before["seam"].get("seam_ratio"),
                "duration_s": before["duration_s"],
            },
            "gain_db": 0.0,
            "trimmed_s": before["duration_s"] - len(x) / fs,
        })

    # 6. Group loudness match. The target is the median of the level each file can
    #    actually reach at the ceiling, so a cresty file is not pushed over it.
    if not args.no_groups:
        by_stem = {Path(r["file"]).stem: r for r in rows}
        sha_to_stems: dict[str, list[str]] = {}
        for row in rows:
            sha_to_stems.setdefault(row["sha_before"], []).append(Path(row["file"]).stem)
        for group, stems in MATCH_GROUPS.items():
            # Bit-identical aliases (backfire_1.wav == backfire_ext_1.wav) must join
            # the same group, otherwise the aliases drift apart in level.
            expanded = sorted({alias for stem in stems if stem in by_stem
                               for alias in sha_to_stems.get(by_stem[stem]["sha_before"], [stem])})
            present = [s for s in expanded if s in buffers]
            if len(present) < 2:
                continue
            achievable: dict[str, float] = {}
            for stem in present:
                level = audit.lufs_event(buffers[stem], rates[stem])
                if level <= -70:
                    continue
                headroom = min(0.0, args.ceiling - audit.db(audit.true_peak(buffers[stem])))
                achievable[stem] = level + headroom
            if len(achievable) < 2:
                continue
            target = float(np.median(list(achievable.values())))
            for stem in present:
                current = audit.lufs_event(buffers[stem], rates[stem])
                if current <= -70:
                    continue
                gain = float(np.clip(target - current, -12.0, 3.0))
                if abs(gain) < 0.05:
                    continue
                buffers[stem] = buffers[stem] * (10.0 ** (gain / 20.0))
                by_stem[stem]["gain_db"] += gain
                by_stem[stem]["actions"].append(
                    f"match {group} ({current:.1f}->{target:.1f} LUFS)")

    # 7. Lookahead limiter for the residual transient excess (max reduction capped).
    #    Loops are attenuated instead: a gain curve that differs at the wrap would
    #    add a discontinuity exactly where we just removed one.
    for row in rows:
        stem = Path(row["file"]).stem
        tp = audit.db(audit.true_peak(buffers[stem]))
        if tp <= args.ceiling + 0.01:
            continue
        if row["loop"]:
            buffers[stem] = buffers[stem] * (10.0 ** ((args.ceiling - tp) / 20.0))
            row["gain_db"] += args.ceiling - tp
            row["actions"].append(f"attenuate {tp:+.1f}->{args.ceiling:+.1f} dBFS")
            continue
        limited, reduction, trim = audit.limit_true_peak(
            buffers[stem], rates[stem], args.ceiling, lookahead_ms=2.0,
            max_reduction_db=args.max_reduction)
        buffers[stem] = limited
        row["limiter_reduction_db"] = round(reduction, 2)
        row["gain_db"] += trim
        if trim < -0.05:
            row["actions"].append(f"trim {trim:+.1f} dB (pico sobre techo)")
        row["actions"].append(f"limit {tp:+.1f}->{args.ceiling:+.1f} dBFS "
                              f"(-{reduction:.1f} dB pico)")

    # 8. Converge the group levels with attenuation only.
    if not args.no_groups:
        for group, stems in MATCH_GROUPS.items():
            present = [s for s in stems if s in buffers]
            levels = [audit.lufs_event(buffers[s], rates[s]) for s in present]
            valid = [v for v in levels if v > -70]
            if len(valid) < 2:
                continue
            target = float(np.median(valid))
            for stem, current in zip(present, levels):
                if current <= -70 or current <= target + 0.05:
                    continue
                gain = float(np.clip(target - current, -2.0, 0.0))
                buffers[stem] = buffers[stem] * (10.0 ** (gain / 20.0))
                by_stem[stem]["gain_db"] += gain
                by_stem[stem]["actions"].append(f"trim {group} ({gain:+.2f} dB)")

    # 9. Unify aliases: files that were bit-identical on input stay identical on
    #    output, so two names never drift apart or sum in phase with different EQ.
    by_stem_rows = {Path(r["file"]).stem: r for r in rows}
    aliases: dict[str, list[str]] = {}
    for row in rows:
        aliases.setdefault(row["sha_before"], []).append(Path(row["file"]).stem)
    alias_pairs = []
    for digest, stems in aliases.items():
        if len(stems) < 2:
            continue
        canonical = sorted(stems)[0]
        for stem in sorted(stems)[1:]:
            buffers[stem] = buffers[canonical].copy()
            by_stem_rows[stem]["gain_db"] = by_stem_rows[canonical]["gain_db"]
            by_stem_rows[stem]["actions"] = list(by_stem_rows[canonical]["actions"]) + \
                [f"alias de {canonical}.wav (mismo sha256)"]
            alias_pairs.append({"canonical": f"{canonical}.wav",
                                "alias": f"{stem}.wav"})

    # 10. Measure the rendered result.
    for row in rows:
        stem = Path(row["file"]).stem
        x = buffers[stem]
        peak = float(np.max(np.abs(x))) if x.size else 0.0
        freqs, power = audit.average_spectrum(x, rates[stem])
        row["after"] = {
            "lufs": audit.lufs_event(x, rates[stem]),
            "true_peak_dbfs": audit.db(audit.true_peak(x)),
            "peak": peak,
            "rms_dbfs": audit.db(audit.rms(x)),
            "dc_offset": float(np.mean(x)) if x.size else 0.0,
            "sub_30_ratio": audit.sub_30_ratio(freqs, power),
            "seam_ratio": audit.seam_metrics(x, rates[stem]).get("seam_ratio"),
            "duration_s": len(x) / rates[stem],
            "frames": int(x.size),
        }

    out: Path = bank if args.in_place else args.out
    if args.in_place:
        backup = bank / "_backup_pre_clean"
        backup.mkdir(exist_ok=True)
        for path in paths:
            (backup / path.name).write_bytes(path.read_bytes())
        print(f"Backup en {backup}")

    patch: list[dict] = []
    for row in rows:
        stem = Path(row["file"]).stem
        x = buffers[stem]
        target = out / row["file"]
        audit.write_wav_pcm16(target, x, rates[stem], 1)
        after = row["after"]
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        row["sha256_after"] = digest
        if row["file"] in manifest_by_name:
            entry = dict(manifest_by_name[row["file"]])
            entry["duration_s"] = round(after["duration_s"], 6)
            entry["peak"] = round(after["peak"], 6)
            entry["loudness_dbfs"] = round(after["rms_dbfs"], 2)
            entry["dc_offset"] = float(f"{after['dc_offset']:.1e}")
            entry["sha256"] = digest
            if entry.get("loop"):
                entry["loop_end_s"] = round(after["duration_s"], 6)
                entry["loop_start_s"] = 0.0
            entry.setdefault("synthesis", {})["processing"] = {
                "tool": "tools/audio/clean_commons_bank.py",
                "revision": 1,
                "highpass_hz": 35.0 if row["loop"] else 30.0,
                "true_peak_ceiling_dbfs": args.ceiling,
                "loudness_match_db": round(row["gain_db"], 2),
                "actions": row["actions"],
            }
            patch.append(entry)

    report = {"ceiling_dbfs": args.ceiling, "rows": rows, "manifest_patch": patch,
              "aliases": alias_pairs}
    out.mkdir(parents=True, exist_ok=True)
    if manifest and not args.in_place:
        patched = dict(manifest)
        replaced = {e["file"]: e for e in patch}
        patched["files"] = [replaced.get(e["file"], e) for e in manifest.get("files", [])]
        (out / "bank_manifest.json").write_text(json.dumps(patched, indent=2) + "\n",
                                                encoding="utf-8")
    (out / "clean_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    write_summary(out / "clean_report.md", rows, args.ceiling)

    print(f"\n{'archivo':34s} {'LUFS':>7} {'->':>6} {'TP':>7} {'->':>6} {'gain':>7}  acciones")
    for row in rows:
        print(f"{row['file']:34s} {row['before']['lufs']:7.1f} {'':>6} "
              f"{row['before']['true_peak_dbfs']:7.2f} {row['after']['true_peak_dbfs']:6.2f} "
              f"{row['gain_db']:+7.2f}  {', '.join(row['actions'])}")
    print(f"\nSalida: {out}")
    print(f"Informe: {out / 'clean_report.md'}")
    return 0


def write_summary(path: Path, rows: list[dict], ceiling: float) -> None:
    lines = ["# Limpieza del banco `commons`\n",
             f"Techo de pico real: {ceiling:.1f} dBFS. Dither TPDF, PCM16 mono 44.1 kHz.\n",
             "| archivo | LUFS antes | LUFS después | TP antes | TP después | sub30 antes | sub30 después "
             "| dur antes | dur después | ganancia dB | acciones |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(
            f"| {r['file']} | {r['before']['lufs']:.1f} | {r['after']['lufs']:.1f} "
            f"| {r['before']['true_peak_dbfs']:.2f} | {r['after']['true_peak_dbfs']:.2f} "
            f"| {r['before']['sub_30_ratio'] * 100:.1f} | {r['after']['sub_30_ratio'] * 100:.1f} "
            f"| {r['before']['duration_s']:.3f} | {r['after']['duration_s']:.3f} "
            f"| {r['gain_db']:+.2f} | {', '.join(r['actions'])} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
