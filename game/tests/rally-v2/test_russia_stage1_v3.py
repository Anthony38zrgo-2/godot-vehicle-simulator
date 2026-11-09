"""Suite de regresión obligatoria del generador v3 sobre russia_stage1.

Verifica con asserts los 6 casos del spec §5 sobre la salida de
pacenote_analyzer_v3.py (candidates + runtime). Uso:

    python game/tests/rally-v2/test_russia_stage1_v3.py [--stage-dir <dir>]

Sale con código 0 si pasan los 6 tests, 1 en caso contrario.
"""
import argparse
import json
import sys
from pathlib import Path

SEVERITY_NAMES = {1: "six", 2: "five", 3: "four", 4: "three",
                  5: "two", 6: "one", 7: "openhairpin", 8: "hairpin"}


def decode(word: int):
    """Replica decode_cmr2_slots del v2 (solo campos usados por los tests)."""
    word &= 0xFFFFFFFF
    return {
        "kind": word & 15,
        "direction": (word >> 4) & 3,
        "distance": (word >> 6) & 15,
        "length": (word >> 10) & 3,
        "turn": (word >> 12) & 7,
        "surface": (word >> 15) & 3,
        "hazard": (word >> 17) & 15,
        "caution": (word >> 21) & 3,
        "junction": (word >> 23) & 1,
        "no_cut": (word >> 24) & 1,
        "ending": (word >> 25) & 7,
        "side": (word >> 28) & 3,
    }


def bucket_range(cls: int, both_curves: bool = False):
    """Rango de gap (m) que mapea a cada clase de distancia.
    Entre dos curvas pegadas (<22 m) siempre es "into" (clase 2)."""
    if both_curves and cls == 2:
        return (0.0, 22.0)
    return {9: (180.0, 1e9), 8: (135.0, 180.0), 7: (110.0, 135.0),
            6: (85.0, 110.0), 5: (60.0, 85.0), 4: (40.0, 60.0),
            3: (22.0, 40.0), 2: (10.0, 22.0), 1: (0.0, 10.0),
            0: (0.0, 0.0)}[cls]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage-dir", type=Path,
                    default=Path(r"D:\games\rally-throphy\stage_exporter\stages\russia\stage1"))
    args = ap.parse_args()
    d = args.stage_dir
    cand = json.loads((d / "russia_stage1_pacenotes_candidates.json").read_text(encoding="utf-8"))
    run = json.loads((d / "russia_stage1_pacenotes.json").read_text(encoding="utf-8"))
    events = cand["events"]
    curves = sorted([e for e in events if e["type"] == "curve"], key=lambda e: e["s_start"])
    calls = sorted(run["curves"], key=lambda c: c["call_index"])
    failures = []

    def check(ok: bool, label: str):
        print(("PASS " if ok else "FAIL ") + label)
        if not ok:
            failures.append(label)

    # Test 1: giro ~90° nodos 131-136 -> izquierda, >=70°, one/square/openhairpin.
    t1 = [e for e in curves if e["s_start"] < 1390 and e["s_end"] > 1290 and e["direction"] == "left"]
    t1ok = [e for e in t1 if e["angle_deg"] >= 70.0
            and SEVERITY_NAMES.get(e["severity_effective"]) in ("one", "square", "openhairpin")]
    check(len(t1ok) >= 1,
          f"T1 giro 90° izq>=70° sev one/square/openhairpin (candidatos: {len(t1)})")
    check(all(e["direction"] != "right" or e["s_end"] <= 1290 or e["s_start"] >= 1390 for e in curves
              if e["angle_deg"] >= 70.0 and e["s_start"] < 1410 and e["s_end"] > 1270),
          "T1 sin giro a la derecha >=70° en la zona (corrige giro invertido de RU1)")

    # Test 2: recta nodos 204-207 -> ninguna curva two/one/openhairpin/hairpin en [2020, 2110].
    t2 = [e for e in curves if e["s_start"] < 2110 and e["s_end"] > 2020
          and e.get("severity_effective") in (5, 6, 7, 8)]
    check(len(t2) == 0, f"T2 sin horquillas fantasma en 2020-2110 (halladas: {len(t2)})")

    # Test 3: secuencia enlazada nodos 107-119 -> left seguida de right (<30 m).
    zone = [e for e in curves if e["s_start"] < 1210 and e["s_end"] > 1060]
    linked = [(a, b) for a, b in zip(zone, zone[1:])
              if a["direction"] == "left" and b["direction"] == "right"
              and 0 <= b["s_start"] - a["s_end"] < 30.0]
    check(len(linked) >= 1, f"T3 secuencia left->right enlazada en 107-119 (pares: {len(linked)})")

    # Test 4: rocas hacia s~=4309 en una llamada (hazard rocks o dont_cut).
    # NOTA: el spec dice "hazard = 12", pero 12 = slot rough.wav; la convención
    # validada v2/juego/banco es hazard = 4 (slot 35 = rocks.wav).
    zone4 = [w for w in calls if w.get("s_start", 1e9) <= 4370.0 and w.get("s_end", -1e9) >= 4200.0]
    dec4 = [(w, decode(int(w["call_word_hex"], 16))) for w in zone4]
    ok4 = any(f["hazard"] == 4 or f["no_cut"] == 1 for _, f in dec4)
    check(ok4, f"T4 rocas s~=4309 en llamada (hazard=4/dont_cut) en {len(zone4)} llamadas")

    # Test 5: coherencia de distancias (bucket sobre hueco PREVIO, no posterior).
    # Entre dos curvas pegadas (<22 m) la clase siempre es 2 ("into").
    bad5 = []
    prev_dec = None
    for i, w in enumerate(calls):
        f = decode(int(w["call_word_hex"], 16))
        if f["distance"] == 0:
            prev_dec = f
            continue
        prev_end = calls[i - 1].get("s_end", calls[i - 1].get("route_distance_m", 0.0)) if i else w.get("s_start", 0.0)
        gap = max(0.0, w.get("s_start", 0.0) - prev_end)
        both = prev_dec is not None and 1 <= prev_dec.get("kind", 0) <= 8 and 1 <= f["kind"] <= 8
        lo, hi = bucket_range(f["distance"], both_curves=both)
        if not (lo - 2.0 <= gap < hi + 2.0):
            bad5.append((w["call_index"], gap, f["distance"]))
        prev_dec = f
    check(len(bad5) == 0, f"T5 distancias = hueco previo con redondeo de bucket ({len(bad5)} fallos)")

    # Test 6: cero drops silenciosos con priority >= 70.
    # "absorbed" (integrada en su curva) y "grouped_into" (cubierta por la
    # curva agrupada) cuentan como emitidas si referencian llamadas reales.
    runtime_idx = {w["call_index"] for w in calls}
    bad6 = [e for e in events if e.get("priority", 0) >= 70
            and (e.get("status") not in ("emitted", "absorbed", "grouped_into") or not e.get("emitted_call_ids")
                 or not set(e["emitted_call_ids"]) <= runtime_idx)]
    check(len(bad6) == 0, f"T6 sin drops silenciosos priority>=70 ({len(bad6)} fallos)")

    print(f"RUSSIA_STAGE1_V3 {'PASS 6/6' if not failures else 'FAIL: ' + str(failures)}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
