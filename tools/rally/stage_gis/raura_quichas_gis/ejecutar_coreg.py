"""Fit Nuth–Kääb on the fit mask and score held-out Raura pixels."""
import json
from pathlib import Path

import numpy as np
import rasterio as rio
import xdem

BASE = Path(__file__).resolve().parent / "data/terrain"
OUT = BASE / "coreg"
GLO = BASE / "raura_copernicus_glo30_utm18s.tif"
ALOS = OUT / "raura_aw3d30_egm2008_utm18s.tif"


def metrics(residual):
    median = np.median(residual)
    return {
        "median_m": float(median),
        "nmad_m": float(1.4826 * np.median(np.abs(residual - median))),
        "rmse_m": float(np.sqrt(np.mean(residual ** 2))),
    }


def array(dem):
    return np.ma.asarray(dem.data, dtype=np.float64).filled(np.nan).squeeze()


def main():
    reference, target = (xdem.DEM(str(p), vcrs="EGM08") for p in (GLO, ALOS))
    masks = []
    for name in ("ajuste", "validacion"):
        with rio.open(OUT / f"mascara_{name}.tif") as src:
            assert (src.crs, src.transform, src.shape) == (reference.crs, reference.transform, reference.shape)
            masks.append(src.read(1) == 1)
    fit, holdout = masks
    assert not (fit & holdout).any()
    method = xdem.coreg.NuthKaab()
    method.fit(reference, target, inlier_mask=fit, random_state=42)
    aligned = method.apply(target, resample=True, resampling="bilinear")
    assert aligned.transform == reference.transform and aligned.crs == reference.crs
    ref, raw, corrected = map(array, (reference, target, aligned))
    before, after = raw - ref, corrected - ref
    paired = holdout & np.isfinite(before) & np.isfinite(after)
    if not paired.any():
        raise ValueError("No paired validation pixels")
    vertical_shift = -float(np.median(before[fit & np.isfinite(before)]))
    baseline = metrics(before[paired] + vertical_shift)
    pre, post = metrics(before[paired]), metrics(after[paired])
    shift = [float(v) for v in method.to_translations()]
    yy, xx = np.indices(paired.shape)
    block = (yy // 20) * ((paired.shape[1] + 19) // 20) + xx // 20
    blocks = []
    for key in np.unique(block[paired]):
        m = paired & (block == key)
        blocks.append({"block": int(key), "n": int(m.sum()),
                       "before": metrics(before[m]), "after": metrics(after[m])})
    report = {
        "reference": GLO.name, "target": ALOS.name, "xdem_version": xdem.__version__,
        "residual_sign": "AW3D30 minus GLO-30", "method": "NuthKaab",
        "translation_enu_m": shift, "vertical_only_shift_m": vertical_shift,
        "fit_pixels": int(fit.sum()), "holdout_pixels": int(holdout.sum()),
        "paired_pixels": int(paired.sum()),
        "holdout_before": pre, "holdout_after": post, "holdout_vertical_only": baseline,
        "reduced_absolute_bias": abs(post["median_m"]) < abs(pre["median_m"]),
        "reduced_dispersion": post["nmad_m"] < pre["nmad_m"],
        "blocks": blocks,
    }
    with rio.open(ALOS) as source:
        profile = source.profile
    with rio.open(OUT / "raura_aw3d30_nuth_kaab.tif", "w", **profile) as dst:
        dst.write(np.where(np.isfinite(corrected), corrected, profile["nodata"]).astype("float32"), 1)
        dst.update_tags(vertical_datum="EGM2008", method="xDEM NuthKaab", role="aligned AW3D30 candidate")
    (OUT / "resultado_nuth_kaab.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")
    print(json.dumps({k:v for k,v in report.items() if k != "blocks"}, indent=2))


if __name__ == "__main__":
    main()
