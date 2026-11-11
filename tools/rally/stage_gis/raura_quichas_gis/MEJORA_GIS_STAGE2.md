# Rally Raura · Stage 2 · Datos GIS y propuesta de mejora

La etapa baja de Nevado Raura a Cantera Quichas. El Stage 1 queda reservado para la subida, con trazado por definir.

## Coordenadas y trazado

Latitud y longitud en WGS 84 (EPSG:4326). GeoJSON guarda longitud primero. Este y Norte en WGS 84 / UTM 18S (EPSG:32718), en metros y redondeados al milímetro.

| Punto | Latitud | Longitud | Este UTM | Norte UTM | Referencia |
|---|---:|---:|---:|---:|---|
| Salida solicitada · Nevado Raura | -10.4777375 | -76.750671875 | 308393.076 | 8841233.942 | Plus Code 57X5G6CX+WP4 |
| Salida del eje aprobado | -10.4776973 | -76.7506465 | 308395.830 | 8841238.404 | Nodo OSM 5396244052 |
| Meta solicitada · Cantera Quichas | -10.5115125 | -76.748640625 | 308636.232 | 8837499.146 | Plus Code 57X5F7Q2+9GX |
| Meta del eje aprobado | -10.5115753 | -76.7485907 | 308641.736 | 8837492.229 | Nodo OSM 5351308851 |

El eje aprobado usa los nodos OSM, a 5,2 y 8,8 m de los puntos solicitados en UTM. Mide **8.275,7 m en planta**. La ruta jugable actual mide **8.124,1 m en 3D** tras ajustar el eje y suavizar la rasante, con unos **439 m de descenso neto**. [Puntos solicitados](endpoints.geojson) · [Eje aprobado](data/roads/route_osm_candidate.geojson) · [Estado del Stage 2](STAGE2.md)

Área de captura WGS 84, en orden oeste, sur, este, norte: **[-76.7900, -10.5400, -76.7100, -10.4500]**. [AOI GeoJSON](aoi.geojson)

## Fuentes GIS

| Insumo | Procedencia y uso |
|---|---|
| **Red OSM** | Recorte de la API 0.6 de OpenStreetMap mediante /api/0.6/map y el bbox anterior. El XML local conserva 30 vías etiquetadas highway, sus nodos y etiquetas. Usar el eje aprobado guardado para reproducir la etapa, ya que una consulta futura puede devolver otra red. [OSM XML](data/roads/raura_quichas_highways.osm) · [Red GeoJSON](data/roads/all_roads_wgs84.geojson) · [Atribución OSM](https://www.openstreetmap.org/copyright) |
| **DEM / DSM** | Copernicus DEM GLO-30 Public, identificado como 2021 en los metadatos locales. Tesela Copernicus_DSM_COG_10_S11_00_W077_00_DEM, recortada y reproyectada a EPSG:32718. GeoTIFF de 294 × 334 píxeles a 30 m, NoData −9999. Sirve de referencia para la ladera. A esa resolución no se pueden medir con precisión los arcenes o la rasante de una calzada de 4–6 m. [GeoTIFF](data/terrain/raura_copernicus_glo30_utm18s.tif) · [Metadatos y URL original](data/terrain/dem_source.json) |
| **Imagen auxiliar** | Sentinel-2 L2A, escena S2A_18LUP_20260807_1_L2A del 7 de agosto de 2026, 15:36:13.348 UTC, vía Earth Search v1. RGB de 882 × 1.001 píxeles a 10 m en EPSG:32718, con zonas sin datos. [GeoTIFF](data/satellite/raura_sentinel2_rgb_10m_utm18s.tif) · [Metadatos STAC](data/satellite/scene_stac_item.json) |

**Segunda fuente incorporada:** ALOS AW3D30 v3.2 (JAXA / OpenTopography), tesela S011W077. El recorte UTM usa exactamente la cuadrícula de GLO-30 y los 98.196 píxeles tienen cobertura común. AW3D30 conserva alturas EGM96 y GLO-30 usa EGM2008. El recorte solo reproyecta en planta. Antes de comparar cotas hay que transformar la referencia vertical y revisar las zonas estables. [Tesela original](data/terrain/ALPSMLC30_S011W077_DSM.tif) · [Recorte UTM](data/terrain/raura_aw3d30_utm18s.tif) · [Procedencia y hashes](data/terrain/aw3d30_source.json)

SHA-256 de los insumos originales:

~~~text
57577e9302cac990a8e91e60940b34fac1f7fff6d922dfe51a29bb2ce3530701  raura_copernicus_glo30_utm18s.tif
fa9aa6b9b7434e50d871447d77971c105c9f8123c7d39e1b656e28a0cd5152c3  raura_quichas_highways.osm
feea7d0992e8475abe80b557369c2a423f1ed2d093e6e1abc767827e12bdbfaf  route_osm_candidate.geojson
16a360d89a600c0bb689587fe5ead40487b15b7ef2757e321c762c507b1a2846  raura_sentinel2_rgb_10m_utm18s.tif
~~~

## Plan reformulado · 11 de noviembre de 2026

El eje OSM aprobado fija **por dónde pasa** la etapa. El DSM describe **el relieve circundante**. La rasante, el ancho, el peralte y el movimiento de tierras constituyen **el diseño de la vía para el simulador**. Guardar por separado las tres capas y su procedencia. Una malla sin grietas demuestra continuidad geométrica, pero el DSM de 30 m sigue sin observar directamente la plataforma de 4–6 m.

El complemento científico aportado se usó como referencia metodológica. El piloto se hará en una variante de 500–800 m, con una horquilla de ramas próximas y un sector con corte o relleno importante. Mantener como control el Stage 2 jugable y su método actual. Las fases 1 y 2 pueden avanzar con los datos locales. Ya hay un segundo DSM local para comparar. La referencia vertical ya se normalizó y están preparadas las máscaras candidatas de ajuste y validación.

### 1. Auditar y preparar el DEM

- **Conservar el GLO-30 original.** Generar un manifiesto con SHA-256, CRS horizontal y vertical, unidades, época, transformación, resolución y NoData. EPSG:32718 identifica el CRS horizontal. El datum vertical debe verificarse en los metadatos del producto antes de comparar cotas con otro DEM o con GNSS. Registrar las conversiones y grillas PROJ que se usen.
- **Con un solo DEM**, auditar cobertura, vacíos, nieve y hielo visibles, pendientes y valores atípicos. Producir una máscara de calidad y un perfil de referencia. Usar interpolación bilineal como control. PCHIP es una variante que se puede medir, sin asumir que resuelve el relieve subpíxel. Las muestras que dependen de NoData quedan señaladas.
- **Si llega otro DEM compatible o control altimétrico**, normalizar datum y unidades, confirmar solape y distinguir si el producto mide superficie o terreno desnudo. Para xDEM/Nuth–Kääb, ajustar en terreno estable, excluyendo nieve cambiante, glaciares, zonas interpoladas y sectores con cambios de superficie. Reservar bloques espaciales de terreno estable para comprobar el resultado. Registrar desplazamientos Este/Norte/Z, mediana y NMAD de residuos antes y después, cobertura y tamaño de muestra. Aceptar la corrección solo si mejora el control reservado sin introducir sesgos espaciales relevantes. Conservar el GLO-30 si el ajuste no resulta defendible.
- **Cuantificar confianza por tramo.** El desacuerdo entre DEM es evidencia relativa: pueden compartir sesgos o fuentes. Separar calidad observada, incertidumbre estimada y ausencia de datos. Dejar el variograma y las simulaciones de error para cuando haya suficientes residuos de terreno estable o control independiente. [xDEM: co-registro](https://xdem.readthedocs.io/en/stable/coregistration.html) · [Método de Nuth y Kääb](https://doi.org/10.5194/tc-5-271-2011)

### 2. Auditar el eje OSM y su relación con la pista actual

- **Congelar el XML y el GeoJSON aprobados.** Importar el XML local con OSMnx o reutilizar el lector local si preserva IDs y etiquetas. Reconstruir conectividad por nodos compartidos. Revisar sentido, superficie, acceso, puentes, túneles y nivel cuando estén etiquetados. Los cruces en planta sin nodo compartido quedan como candidatos a revisión, sin conectar automáticamente las ramas.
- **Conservar tres referencias:** puntos solicitados, eje OSM aprobado y eje de juego actual. Proyectar a UTM 18S y calcular longitudes 2D comparables para ambos ejes. Medir por separado la longitud 3D. Para el Stage 2, invertir la transformación de origen local declarada por el generador o el .blend, y verificar salida y meta al recuperar UTM. Los 8.275,7 m del OSM en planta y los 8.124,1 m de la ruta de juego en 3D no permiten calcular por sí solos cuánto se recortaron las curvas.
- **Construir correspondencia PK a PK en orden.** Usar tramos o anclas de la misma rama y una correspondencia monótona. Un punto vecino en planta puede pertenecer al otro brazo de una horquilla. Reportar desplazamiento lateral, diferencias de longitud por sector, recortes y empalmes. Revisar los máximos sobre Sentinel-2, conservando las zonas sin cobertura y las dudas por resolución.
- **Congelar XY para la primera comparación.** El piloto toma el eje de juego como base para aislar el efecto de rasante y taludes. Si la auditoría muestra una desviación inaceptable del eje aprobado, resolverla primero como variante separada y documentar el PK afectado. No redefinir la ruta con una nueva búsqueda de camino más corto.

### 3. Diseñar la rasante con SciPy y OSQP

- Remuestrear el eje del piloto cada 2 m por distancia horizontal. Comparar tres perfiles: calzada actual, DSM interpolado y rasante optimizada. Usar SciPy para matrices dispersas de pendiente y cambio de pendiente en función de la distancia real. Ajustar con OSQP un QP que penalice la separación ponderada de las referencias y las oscilaciones cortas. CVXPY es opcional para comparar formulaciones. Si se adoptan restricciones cónicas o cuadráticas, elegir un solver compatible.
- Separar anclas y restricciones duras de preferencias con holgura. Fijar cota y pendiente en los dos empalmes. Tomar el 22 % como parámetro inicial de diseño y controlar también el cambio de pendiente. Dar menos peso a cotas DSM dudosas. Hacer una comprobación de factibilidad antes de exportar. Si el problema es inviable, informar los PK y las restricciones conflictivas y conservar el perfil anterior hasta resolverlos. [Documentación del solver OSQP](https://osqp.org/docs/solver/index.html)
- Etiquetar las muestras como observadas, inferidas o sintéticas según su fuente. El eje cartográfico y el DSM son observaciones de distinta naturaleza. Las cotas optimizadas siguen siendo de diseño. Registrar desviaciones verticales; convertirlas en volúmenes solo al integrar superficies o áreas transversales.

### 4. Construir el corredor y validar el piloto

1. **Calzada → arcén → talud → encuentro con el terreno.** Usar AQGIS-Sivil3D como prototipo externo de secciones por PK, corte/relleno, TIN y líneas de encuentro. Está clonado y empaquetado en tools; la comparación con su algoritmo queda condicionada a disponer de QGIS y probarlo con el piloto. CorridorRoad queda como segunda referencia de diseño. [AQGIS-Sivil3D](https://github.com/pypadopoulos-HY/AQGIS-Sivil3D) · [CorridorRoad](https://github.com/ganadara135/CorridorRoad)
2. **Separar ambos lados.** Generar calzada y arcén desde la rasante, y buscar el encuentro de cada talud de corte o relleno con el terreno. Guardar líneas de borde como aristas obligatorias. Refinar el terreno cerca de la vía, conservando resolución más baja lejos del corredor. Si dos taludes se solapan, generar una superficie compartida respetando ambas plataformas. Señalar los sectores donde se necesite ajustar rasante, arcén o una estructura de contención.
3. **Comparar por etapas.** Primero, rasante actual frente a optimizada con los mismos XY. Segundo, corredor actual frente al corredor por secciones usando una misma rasante. Medir cambio de pendiente en igual tramo y espaciado, desviación de cota, volumen de corte y relleno en m³ y secciones sin encuentro. Verificar en Blender costuras, triángulos degenerados, inversiones y solapes. En Godot comprobar contacto en bordes, estabilidad de suspensión y cámara durante una pasada por calzada y arcén.
4. **Entregar antes de extender.** Guardar manifiesto de datos, máscara DEM, ejes separados, tabla de correspondencia PK, perfiles y secciones, .blend comparativo, GLB visual y de colisión e informe por PK. Exigir continuidad en cota y pendiente de empalmes, mejora cuantificada frente al control y revisión al volante. Los 0,82 puntos porcentuales medios entre muestras de unos 8 m corresponden a la etapa actual completa; recalcular la línea base para la ventana elegida. [Generador actual](generar_stage2.py)

**Primer paso ejecutable con lo que hay:** producir la auditoría de GLO-30 y la correspondencia entre OSM y el eje de juego, y elegir el piloto con esos resultados. xDEM está disponible para el diagnóstico; el ajuste entre DEM queda pendiente de ejecutar y validar en bloques reservados. [Preparación del co-registro](data/terrain/coreg/README.md) Esta revisión define el método, sin ejecutar una corrección del DEM, un solver ni una nueva exportación.

El primer [piloto de rasante OSQP](PILOTO_OSQP.md) ya está disponible como variante separada. Incluye perfiles comparables, diagnóstico de encuentros laterales y un lanzamiento en Godot.
