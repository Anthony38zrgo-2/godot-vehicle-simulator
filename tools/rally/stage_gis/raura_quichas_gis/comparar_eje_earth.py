"""Compare a manually digitized Earth Pro path with the Raura GIS axis."""
import argparse
import csv
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import numpy as np
from rasterio.warp import transform

ROOT = Path(__file__).resolve().parent


def stations(points):
    return np.r_[0, np.cumsum(np.linalg.norm(np.diff(points, axis=0), axis=1))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kml", type=Path, help="Earth Pro export containing one LineString")
    parser.add_argument("--csv", type=Path, required=True)
    args = parser.parse_args()
    lines = ET.parse(args.kml).findall(".//{*}LineString/{*}coordinates")
    if len(lines) != 1 or not lines[0].text:
        parser.error("Exporta una sola ruta KML.")
    coordinates = np.array([[float(v) for v in item.split(",")[:2]] for item in lines[0].text.split()])
    if len(coordinates) < 2 or not np.isfinite(coordinates).all():
        parser.error("La ruta necesita al menos dos coordenadas válidas.")
    candidate = np.column_stack(transform("EPSG:4326", "EPSG:32718", *coordinates.T))
    candidate = candidate[np.r_[True, np.linalg.norm(np.diff(candidate, axis=0), axis=1) > 0]]
    if len(candidate) < 2:
        parser.error("La ruta necesita dos puntos distintos.")
    scene = json.loads((ROOT / "output/scene_input.json").read_text(encoding="utf8"))
    axis = np.array(scene["route"])[:, :2] + scene["origin"]
    axis_pk = stations(axis)
    candidate_pk = stations(candidate)
    segments = np.diff(candidate, axis=0)
    lengths = np.diff(candidate_pk)
    with args.csv.open("w", newline="", encoding="utf8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["pk_gis_m", "pk_kml_m", "offset_izquierda_m", "distancia_m", "revision"])
        previous = -1
        for pk in np.arange(0, 801, 25):
            index = min(np.searchsorted(axis_pk, pk, side="right") - 1, len(axis) - 2)
            direction = axis[index + 1] - axis[index]
            direction /= np.linalg.norm(direction)
            point = axis[index] + direction * (pk - axis_pk[index])
            fractions = np.clip(np.sum((point - candidate[:-1]) * segments, axis=1) / lengths**2, 0, 1)
            offsets = candidate[:-1] + fractions[:, None] * segments - point
            nearest = int(np.argmin(np.linalg.norm(offsets, axis=1)))
            match = candidate_pk[nearest] + fractions[nearest] * lengths[nearest]
            delta = offsets[nearest]
            signed = direction[0] * delta[1] - direction[1] * delta[0]
            review = []
            if match <= previous:
                review.append("orden o ramal ambiguo")
            if match <= 0.01 or match >= candidate_pk[-1] - 0.01:
                review.append("extremo de cobertura")
            writer.writerow([pk, round(match, 2), round(signed, 2),
                             round(float(np.linalg.norm(delta)), 2), " / ".join(review)])
            previous = match


if __name__ == "__main__":
    main()
