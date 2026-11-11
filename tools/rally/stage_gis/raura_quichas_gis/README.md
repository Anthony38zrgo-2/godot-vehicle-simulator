# Raura → Cantera Quichas: paquete preparatorio GIS

## Puntos (derivados de los Plus Codes, no de un trazado vial verificado)

- Inicio, Nevado Raura: **57X5G6CX+WP4**, (-10.4777375, -76.750671875)
- Meta, Cantera Quichas: **57X5F7Q2+9GX**, (-10.5115125, -76.748640625)
- Distancia recta aproximada: **3.74 km**. La longitud real por carretera es desconocida.
- Área de descarga ampliada, orden OSM `(W,S,E,N)`: `-76.7900, -10.5400, -76.7100, -10.4500` (~9 x 10 km)
- GeoJSON de referencia: `aoi.geojson` y `endpoints.geojson`, en `EPSG:4326`.
- Sistema de trabajo de raster y malla: **WGS84 / UTM 18S, EPSG:32718**, metros.

## Obtener los datos reales

Necesita **internet en tu propia PC**. Este ZIP contiene el preparador, **no** los datos geográficos descargados. No se han inventado ni sintetizado DEMs, rutas OSM ni fotografías.

En una terminal con Python 3.10 o posterior:

```bash
python -m pip install -r requirements.txt
python download_geodata.py
```

Para descarga separada:

```bash
python download_geodata.py --only dem
python download_geodata.py --only osm
python download_geodata.py --only satellite
```

El programa creará:

```text
data/
  terrain/
    raura_copernicus_glo30_utm18s.tif
    dem_source.json
  roads/
    raura_quichas_highways.osm
    all_roads_wgs84.geojson
    route_osm_candidate.geojson    # SOLO SI OSM contiene conexión plausible
    route_status.json             # cuando no se encuentra ruta candidata
  satellite/
    raura_sentinel2_rgb_10m_utm18s.tif
    scene_source.json
    scene_stac_item.json
```

Si un proveedor externo falla, se registra el problema en `download_errors.json`; **no** se crea un fichero geográfico de reemplazo sintético. Puedes volver a ejecutar un tipo con `--only`.

## Origen de datos

- **DEM**: Copernicus GLO-30 Public 2021 en AWS Open Data: https://registry.opendata.aws/copernicus-dem/ . Se lee solo una ventana del COG S11/W077. Es un **DSM** de ~30m: no registra la microgeometría ni los taludes de la carretera.
- **OSM**: carretera y caminos etiquetados `highway` desde Overpass API: https://overpass-api.de/ . Se guardan tanto el XML OSM como GeoJSON. Si la red está conectada y ambos puntos quedan cerca, se genera una **ruta candidata**, no validada.
- **Imagen satelital**: Sentinel-2 Level-2A por Earth Search STAC: https://earth-search.aws.element84.com/v1 . Busca escenas de abril 2025 a noviembre 2026, con menos de 30% de nubes **en la escena**. Recorta RGB nominalmente 10m. Revisa visualmente nubes, sombras y nieve, porque la nubosidad de la escena no garantiza ausencia de nubes en la ruta.
- **Mejor ortofoto, si existe**: https://map.openaerialmap.org/ o portal IGN Perú; no está garantizada la cobertura ni la descarga por API.

## Flujo en QGIS y BlenderGIS

1. En QGIS abrir `terrain/*.tif`, `satellite/*.tif`, `roads/*.geojson`, y los endpoints. Se puede abrir `roads/*.osm` directamente en BlenderGIS.
2. **No usar `endpoints.geojson` como trazado de carretera**: contiene solamente los dos puntos; no se incluye una línea recta ficticia como ruta.
3. Inspeccionar `route_osm_candidate.geojson` si existe. Comprobar que la red siga la ruta visual y que su clasificación sea vehicular. Las rutas mineras y caminos no mapeados podrían impedir el cálculo. Dibujar o corregir el eje en QGIS/Blender.
4. Convertir el eje corregido en spline, interpolar alturas del DEM, definir perfiles transversales, arcenes, peraltes y taludes, y generar una malla de colisión controlada. **El DEM de 30m es insuficiente para reproducir baches reales.**
5. En la versión publicada, respetar atribución y condiciones de cada fuente: OSM ODbL, Copernicus DEM y Sentinel-2.

## Enlaces de acceso manual

- [Descarga directa de la tesela Copernicus GLO-30 S11/W077](https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/Copernicus_DSM_COG_10_S11_00_W077_00_DEM/Copernicus_DSM_COG_10_S11_00_W077_00_DEM.tif) (el archivo completo es mucho mayor que el recorte)
- [Overpass Turbo](https://overpass-turbo.eu/)
- [Copernicus Browser](https://browser.dataspace.copernicus.eu/)
- [OpenAerialMap](https://map.openaerialmap.org/)
