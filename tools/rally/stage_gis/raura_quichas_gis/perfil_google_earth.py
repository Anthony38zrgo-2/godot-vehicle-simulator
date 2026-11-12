"""Prepare Earth Pro tracks and compare manually recorded terrain elevations."""
import argparse
import csv
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import numpy as np
import rasterio
from rasterio.warp import transform

ROOT = Path(__file__).resolve().parent
PILOT = ROOT / "output/piloto_inicio"
SIDES = ("izquierda", "eje", "derecha")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--earth-csv", type=Path, help="Completed template with Earth heights converted to EGM2008")
    args = parser.parse_args()
    pilot = json.loads((PILOT / "propuesta.json").read_text(encoding="utf8"))
    axis = np.asarray(pilot["axis"]) + pilot["utm_origin"]
    pk = np.asarray(pilot["pk_m"])
    center = axis[:, :2]
    tangent = np.gradient(center, pk, axis=0)
    left = tangent[:, ::-1] * [-1, 1] / np.linalg.norm(tangent, axis=1)[:, None]
    stations = np.arange(0, 701, 25)
    rows = {}
    kml = ET.Element("kml", xmlns="http://www.opengis.net/kml/2.2")
    doc = ET.SubElement(kml, "Document")
    for side, offset in zip(SIDES, (5, 0, -5)):
        path = center + offset * left
        folder = ET.SubElement(doc, "Folder")
        ET.SubElement(folder, "name").text = side
        track = ET.SubElement(folder, "Placemark")
        ET.SubElement(track, "name").text = f"Perfil {side}"
        line = ET.SubElement(track, "LineString")
        ET.SubElement(line, "tessellate").text = "1"
        lon, lat = transform("EPSG:32718", "EPSG:4326", *path.T)
        ET.SubElement(line, "coordinates").text = " ".join(f"{x:.8f},{y:.8f}" for x, y in zip(lon, lat))

        points = np.column_stack([np.interp(stations, pk, component) for component in path.T])
        lon, lat = transform("EPSG:32718", "EPSG:4326", *points.T)
        with rasterio.open(ROOT / "data/terrain/coreg/raura_aw3d30_nuth_kaab.tif") as dem:
            heights = [None if np.ma.is_masked(v[0]) or not np.isfinite(v[0]) else round(float(v[0]), 3)
                       for v in dem.sample(points, masked=True)]
        markers = ET.SubElement(folder, "Folder")
        ET.SubElement(markers, "name").text = "Marcas PK"
        ET.SubElement(markers, "visibility").text = "0"
        for station, x, y, height in zip(stations, lon, lat, heights):
            marker = ET.SubElement(markers, "Placemark")
            ET.SubElement(marker, "name").text = f"PK {station} {side}"
            ET.SubElement(ET.SubElement(marker, "Point"), "coordinates").text = f"{x:.8f},{y:.8f}"
            rows[int(station), side] = dict(pk_m=int(station), lado=side, lon=round(x, 8), lat=round(y, 8),
                                          dem_egm2008_m=height, earth_egm2008_m=None,
                                          rasante_egm2008_m=round(float(np.interp(station, pk, axis[:, 2])), 3)
                                          if side == "eje" else None)
    ET.ElementTree(kml).write(PILOT / "earth_perfiles.kml", encoding="utf-8", xml_declaration=True)

    if args.earth_csv:
        seen = set()
        with args.earth_csv.open(newline="", encoding="utf-8-sig") as stream:
            for entry in csv.DictReader(stream):
                key = (int(entry["pk_m"]), entry["lado"])
                if key not in rows or key in seen:
                    parser.error(f"PK/lado inexistente o duplicado: {key}")
                seen.add(key)
                value = entry["earth_egm2008_m"].strip()
                if value:
                    height = float(value)
                    if not np.isfinite(height):
                        parser.error(f"Cota no finita: {key}")
                    rows[key]["earth_egm2008_m"] = height

    for (station, side), row in rows.items():
        earth = row["earth_egm2008_m"]
        dem = row["dem_egm2008_m"]
        grade = row["rasante_egm2008_m"]
        row["earth_menos_dem_m"] = round(earth - dem, 3) if earth is not None and dem is not None else None
        row["rasante_menos_earth_m"] = round(grade - earth, 3) if earth is not None and grade is not None else None
        lateral = [rows[station, name]["earth_egm2008_m"] for name in SIDES]
        row["rango_lateral_earth_m"] = round(max(lateral) - min(lateral), 3) if all(v is not None for v in lateral) else None
        row["revision"] = ""
        if side == "eje" and earth is not None:
            spread = row["rango_lateral_earth_m"]
            if spread is not None and spread >= 3:
                row["revision"] = "revisar eje en planta"
            elif all(rows.get((s, "eje"), {}).get("earth_egm2008_m") is not None
                     and rows[s, "eje"]["rasante_egm2008_m"] - rows[s, "eje"]["earth_egm2008_m"] >= 4
                     for s in (station - 25, station, station + 25)):
                row["revision"] = "revisar rasante alta"
    output = PILOT / ("earth_comparacion.csv" if args.earth_csv else "earth_muestras.csv")
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=next(iter(rows.values())).keys())
        writer.writeheader()
        writer.writerows(rows[key] for key in sorted(rows))
    print(f"{len(rows)} puntos; {sum(r['earth_egm2008_m'] is not None for r in rows.values())} cotas Earth; {output}")


if __name__ == "__main__":
    main()
