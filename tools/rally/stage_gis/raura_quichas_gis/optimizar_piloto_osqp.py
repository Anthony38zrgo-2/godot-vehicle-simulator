"""Optimize the fixed Raura pilot axis and design independent side slopes."""
import csv
import sys
import json
from pathlib import Path

import numpy as np
import osqp
import rasterio
from scipy import sparse
from scipy.interpolate import RegularGridInterpolator
from scipy.optimize import brentq

BASE = Path(__file__).resolve().parent
OUT = BASE / ("output/piloto_inicio" if "--inicio" in sys.argv else "output/piloto_osqp")
DEM = BASE / "data/terrain"


def sampler(path, origin):
    with rasterio.open(path) as dataset:
        z = dataset.read(1, masked=True).filled(np.nan)
        t = dataset.transform
        x = t.c + t.a * (np.arange(dataset.width) + 0.5) - origin[0]
        y = t.f + t.e * (np.arange(dataset.height) + 0.5) - origin[1]
    grid = RegularGridInterpolator((x, y), z.T - origin[2], bounds_error=False, fill_value=np.nan)
    return grid


def profile_metrics(z, grade, curvature):
    g, c = grade @ z, curvature @ z
    return {"max_grade_pct": float(100 * np.max(np.abs(g))),
            "rms_grade_change_pct_per_10m": float(1000 * np.sqrt(np.mean(c**2))),
            "p95_grade_change_pct_per_10m": float(1000 * np.percentile(np.abs(c), 95)),
            "uphill_m": float(np.maximum(0, np.diff(z)).sum())}


def optimize(axis, pk, terrain, other):
    initial = axis[:, 2]
    step = np.diff(pk)
    n = len(pk)
    grade = sparse.diags([-1 / step, 1 / step], [0, 1], shape=(n-1, n), format="csc")
    scale = 2 / (step[:-1] + step[1:])
    curvature = sparse.diags([-scale, scale], [0, 1], shape=(n-2, n-1), format="csc") @ grade
    # The DSM describes the slope around the road. Downweight disagreement and
    # cap its pull so a cliff pixel cannot drive the fitted road into the bank.
    agreement = np.isfinite(other) & np.isfinite(terrain)
    disagreement = np.where(agreement, np.abs(terrain - other), np.inf)
    weight = 0.35 / (1.0 + (disagreement / 3.0)**2)
    target = initial + np.where(np.isfinite(terrain), np.clip(terrain - initial, -3, 3), 0)
    identity = sparse.eye(n, format="csc")
    anchors = [0, 1, n-2, n-1]
    P = 2 * (sparse.diags(1 + weight) + 12000 * (curvature.T @ curvature))
    q = -2 * (initial + weight * target)
    constraints = sparse.vstack((identity, grade, curvature), format="csc")
    low = np.r_[initial - 4.0, np.full(n-1, -0.22), np.full(n-2, -0.0035)]
    high = np.r_[initial + 4.0, np.full(n-1, 0.22), np.full(n-2, 0.0035)]
    low[anchors] = high[anchors] = initial[anchors]
    solver = osqp.OSQP()
    solver.setup(P=sparse.triu(P, format="csc"), q=q, A=constraints, l=low, u=high,
                 eps_abs=1e-7, eps_rel=1e-7, max_iter=40000, polishing=True, verbose=False)
    result = solver.solve(raise_error=False)
    if result.info.status != "solved":
        raise ValueError(f"Pilot grade constraints: {result.info.status}")
    z = result.x
    feasibility = max(float(np.max(low-constraints @ z)), float(np.max(constraints @ z-high)))
    if feasibility > 1e-5:
        raise ValueError(f"Constraint violation: {feasibility}")
    return z, {"solver": result.info.status, "max_constraint_violation": feasibility,
               "maximum_z_change_m": float(np.max(np.abs(z-initial))),
               "before": profile_metrics(initial, grade, curvature),
               "after": profile_metrics(z, grade, curvature)}


def design_side(row, index, sample):
    shoulder, outer = (1, 0) if index == 0 else (5, 6)
    start = row[shoulder]
    direction = row[outer, :2] - start[:2]
    safe = float(np.linalg.norm(direction))
    direction /= safe
    ground_start = float(sample(start[:2]).item())
    if not np.isfinite(ground_start):
        return {"type": "nodata", "ideal_m": None, "safe_m": safe, "status": "nodata"}
    cut = ground_start >= start[2]
    grade = 0.90 if cut else -0.65

    def residual(distance):
        terrain = float(sample(start[:2] + distance * direction).item())
        return start[2] + grade * distance - terrain

    previous, last = 0.0, residual(0.0)
    ideal = 0.0 if abs(last) < 1e-6 else None
    if ideal is None:
        for distance in np.arange(0.5, 36.5, 0.5):
            value = residual(distance)
            if not np.isfinite(value):
                break
            if last * value <= 0:
                ideal = float(brentq(residual, previous, distance))
                break
            previous, last = distance, value
    # Keep the existing footprint for the first comparison. The ring has
    # already been checked for folds and intersections, including hairpins.
    # If the ideal encounter is outside it, the exterior mesh will blend it.
    at_boundary = float(sample(row[outer, :2]).item())
    if ideal is not None and ideal <= safe and np.isfinite(at_boundary):
        # Do not move the ring when the terrain intersects inside the strip.
        # Continue across the short remaining space to the terrain boundary.
        target = at_boundary
        status = "encuentro_en_franja"
    else:
        target = start[2] + grade * safe
        status = "limite_de_huella" if ideal is not None else "sin_encuentro"
    # Control the slope of the straight mesh strip even if a curved DSM
    # profile crosses it then moves away again before the outer edge.
    lower = start[2] - 0.65 * safe
    upper = start[2] + 0.90 * safe
    row[outer, 2] = np.clip(target, lower, upper)
    if status == "encuentro_en_franja" and abs(row[outer, 2] - target) > 0.01:
        status = "encuentro_no_continuo"
    return {"type": "corte" if cut else "relleno", "ideal_m": ideal, "safe_m": safe,
            "status": status, "outer_z_m": float(row[outer, 2])}


def main():
    base = json.loads((OUT / "base.json").read_text(encoding="utf8"))
    axis, pk, sections = (np.asarray(base[k], dtype=float) for k in ("axis", "pk_m", "sections"))
    glo = sampler(DEM / "raura_copernicus_glo30_utm18s.tif", base["utm_origin"])
    alos = sampler(DEM / "coreg/raura_aw3d30_nuth_kaab.tif", base["utm_origin"])
    terrain, other = glo(axis[:, :2]), alos(axis[:, :2])
    if "--rasante-original" in sys.argv:
        z = axis[:, 2].copy()
        result = {"solver": "existing stage profile", "maximum_z_change_m": 0.0}
    else:
        z, result = optimize(axis, pk, terrain, other)
    designed = axis.copy()
    designed[:, 2] = z
    new_rows = sections.copy()
    new_rows[:, :, 2] += (z - axis[:, 2])[:, None]
    diagnostics = []
    for i, row in enumerate(new_rows):
        # Fade the side treatment into the existing geometry at both joins.
        fade = min(1, (pk[i]-pk[0])/20, (pk[-1]-pk[i])/20)
        original = row[[0, 6], 2].copy()
        sides = [design_side(row, side, glo) for side in range(2)]
        row[[0, 6], 2] = original + fade * (row[[0, 6], 2] - original)
        for side, outer in enumerate((0, 6)):
            sides[side]["applied_outer_z_m"] = float(row[outer, 2])
            sides[side]["transition_weight"] = float(fade)
        diagnostics.append(sides)
    assert np.array_equal(sections[:, :, :2], new_rows[:, :, :2])
    assert np.array_equal(axis[:, :2], designed[:, :2])
    assert np.max(np.abs(z[[0, 1, -2, -1]] - axis[[0, 1, -2, -1], 2])) < 1e-5
    counts = {}
    for pair in diagnostics:
        for side in pair:
            status = side["status"]
            counts[status] = counts.get(status, 0) + 1
    result.update({"pk_range_m": [float(pk[0]), float(pk[-1])],
                   "xy_max_change_m": 0.0, "side_status_before_fade": counts})
    output = dict(base, axis=designed.tolist(), base_axis=axis.tolist(), sections=new_rows.tolist(),
                  metrics=result, daylight=diagnostics)
    (OUT / "propuesta.json").write_text(json.dumps(output, indent=2, allow_nan=False) + "\n", encoding="utf8")
    (OUT / "comparacion.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    with (OUT / "perfil.csv").open("w", newline="", encoding="utf8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["pk_m", "actual_egm08_m", "osqp_egm08_m", "glo30_egm08_m", "aw3d30_egm08_m"])
        datum = base["utm_origin"][2]
        for s, old, new, dem, second in zip(pk, axis[:, 2], z, terrain, other):
            writer.writerow([round(s, 3), *[round(v+datum, 4) if np.isfinite(v) else ""
                                           for v in (old,new,dem,second)]])
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
