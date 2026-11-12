# Rally Raura Stage 2 — investigación del eje, la rasante y el encaje en la ladera

## Problema que hay que resolver

En el piloto de la bajada Nevado Raura → Cantera Quichas, la plataforma se percibe demasiado expuesta hacia el valle. Las referencias de Street View de la LM-599 muestran cortes rocosos próximos a la calzada, tramos con una franja irregular de tierra o roca antes de la caída y sectores con un borde exterior elevado o una depresión somera. En la salida, la carretera parece más encajada en el monte que en el juego. La vista aérea de Laguna Putusay Alta permite seguir la huella clara de la calzada entre afloramientos y distinguir ramales cerca del inicio.

La observación admite tres causas que pueden coexistir. El eje horizontal puede quedar demasiado hacia el valle. La rasante puede pasar por encima de la plataforma real. También puede faltar relieve lateral entre la calzada y la ladera general, aunque el eje y la cota central sean razonables. Una captura a altura de conductor permite reconocer estas formas, pero la perspectiva por sí sola no permite medir cuánto mover o bajar el camino.

El alcance inicial es PK 0–700 m del piloto `raurastart_stage2`. La rasante actual usa el perfil existente del stage y el piloto llega a PK 701,712. El experimento con textura exterior derivada de la imagen satelital queda para después de resolver la geometría. El objetivo de este documento es investigar y recomendar correcciones localizadas, con evidencia por PK y por lado.

## Coordenadas y referencias

Las coordenadas de esta tabla están en WGS84, orden latitud, longitud. En GeoJSON y KML los pares se guardan en orden longitud, latitud. Trabajar en planta en UTM 18S, EPSG:32718.

| Referencia | Latitud | Longitud | Uso |
|---|---:|---:|---|
| Inicio nominal, 57X5G6CX+WP4 | -10.47773750 | -76.750671875 | Centro del Plus Code |
| Primer punto del eje GIS | -10.47769730 | -76.75064650 | Centro de la captura Earth 4K |
| Street View de salida | -10.47752190 | -76.75064090 | Rumbo de cámara 146,48° |
| Street View más adelante | -10.48344720 | -76.74878810 | Rumbo de cámara 200,37° |
| Meta nominal, 57X5F7Q2+9GX | -10.51151250 | -76.748640625 | Centro del Plus Code |
| Último punto del eje GIS | -10.51157530 | -76.74859070 | Extremo del trazado GIS |

El segundo panorama cae cerca del **PK GIS 745,2 m**, a 4,0 m del eje GIS. Al proyectarlo sobre el piloto recortado, el punto más cercano es el extremo en PK 701,7, a 27,5 m. Por tanto, usarlo como referencia de continuidad aguas abajo y evitar asignarle un PK interior por proximidad en línea recta. El panorama de salida cae cerca del PK 5,5 del piloto por proyección, con 17,7 m de distancia lateral. Estos valores sirven para asociar las vistas y no convierten la posición de la cámara en un punto de control del eje.

[Street View de salida](https://maps.app.goo.gl/H6dczzkZSsdm9aGL7) · [Street View más adelante](https://maps.app.goo.gl/yiohfXSzh6pXUfPXA) · [Puntos nominales](endpoints.geojson)

### Ejes y kilometrajes

- [Candidato OSM](data/roads/route_osm_candidate.geojson) y [escena GIS](output/scene_input.json). La escena contiene el origen UTM y la polilínea local. El eje GIS mide **8.275,7 m en planta**. El candidato original registra 8.299,1 m con su método de cálculo.
- El [Stage 2 de juego](STAGE2.md) mide **8.124,1 m en 3D** después de ajustar el eje en horquillas. Registrar en cada informe qué versión del eje y qué PK se empleó.
- [Geometría base](output/piloto_inicio/base.json) y [propuesta del piloto](output/piloto_inicio/propuesta.json). Para reconstruir XY en UTM, sumar las dos primeras componentes de `utm_origin` a `axis`. La tercera componente de ese origen permite recuperar la cota absoluta. El archivo incluye secciones transversales y PK del piloto. La propuesta actual registra 0 m de cambio en XY y 0 m de cambio máximo de rasante respecto de su base.
- Desde la raíz, `.scriptsun_rally_raura.ps1` abre el piloto. `-StageCompleto` selecciona la bajada completa.

## Fuentes y límites de precisión

| Fuente | Datos disponibles | Qué se puede comprobar |
|---|---|---|
| Copernicus DEM GLO-30 público | DSM de 30 m, EGM2008, UTM 18S | Relieve general y pendiente de ladera. [Metadatos](data/terrain/dem_source.json) |
| JAXA ALOS AW3D30 v3.2 | DSM de 30 m, originalmente EGM96. Conversión a EGM2008 y co-registro con xDEM contra GLO-30 | Acuerdo entre modelos y sensibilidad de las cotas a la fuente. [Metadatos](data/terrain/aw3d30_source.json) · [Co-registro](data/terrain/coreg/README.md) |
| Sentinel-2 L2A | Escena S2A_18LUP_20260807_1_L2A del 7 de agosto de 2026. RGB de 10 m en UTM 18S | Contexto de lagunas, laderas y cobertura. Una calzada de 4–6 m ocupa menos de un píxel. [Metadatos](data/satellite/scene_source.json) |
| Google Earth Pro | JPEG de 3840 × 2160 centrado en la salida, con crédito Airbus visible. En la vista del cliente se observó 23 de julio de 2023 como fecha de imagen bajo el cursor | Huella visible, ramales, afloramientos y relación con lagunas. Registrar fecha por sector si cambia. Los píxeles del JPEG y su resolución de exportación no establecen precisión métrica. [Captura](output/raura_earth_pk0000_4k.jpg) |
| Street View | Panoramas y capturas aportadas de marzo de 2026 | Lectura de la sección aparente, roca, cuneta y borde valle. Orientar cada vista antes de asignar izquierda y derecha en sentido de carrera. |

La conversión de AW3D30 aplicó `H08 = H96 + N96 − N08` con las grillas de geoide correspondientes. Nuth–Kääb estimó +6,67 m Este, −0,10 m Norte y +0,72 m vertical para AW3D30. En los 3.184 píxeles reservados, la mediana del residuo AW3D30 menos GLO-30 pasó de −0,702 a −0,276 m, el NMAD de 3,326 a 1,427 m y el RMSE de 4,393 a 3,831 m. Son métricas de acuerdo entre DSM a escala de ladera. La máscara de ajuste excluye el entorno de 60 m de la red OSM y cotas de 4.700 m o más, así que esas métricas no validan la calzada de salida. [Resultados](data/terrain/coreg/resultado_nuth_kaab.json)

## Estado del tooling de Google Earth

- El repositorio externo está clonado en `tools/google_earth_pro_downloader`, commit `dfb79d9`. Automatiza la interfaz por coordenadas de pantalla. La calibración de botones, atajos y diálogos en Windows sigue pendiente. La captura de salida se obtuvo con el exportador de Google Earth Pro.
- [KML de todo el stage](output/raura_stage2_earth.kml) y [CSV de capturas](output/raura_stage2_earth.csv) contienen 43 puntos cada 200 m más la meta. Hay un JPEG exportado. Todavía falta comprobar encuadre, solape y fecha en capturas consecutivas.
- [perfil_google_earth.py](perfil_google_earth.py) genera un [KML del piloto](output/piloto_inicio/earth_perfiles.kml) con eje y offsets de ±5 m en planta, más [87 puntos cada 25 m](output/piloto_inicio/earth_muestras.csv). Se verificó la importación en Earth Pro. La distancia de cada línea lateral puede diferir de la distancia del eje, por lo que se deben asociar las lecturas por las marcas de PK o por coordenadas.
- El script toma AW3D30 corregido con muestreo por píxel y la rasante del eje desde `propuesta.json`. Con `--earth-csv` incorpora cotas registradas en `earth_egm2008_m` y calcula residuos y rango lateral. La [comparación actual](output/piloto_inicio/earth_comparacion.csv) tiene **cero cotas de Earth**. El aviso de rasante alta se verificó con datos sintéticos.
- En las 29 muestras del eje, rasante menos AW3D30 corregido tiene mínimo −10,00 m, mediana −2,01 m y máximo +2,79 m. Esta comprobación describe la diferencia con ese DSM de 30 m. Por sí sola no respalda una rebaja general de la rasante.
- El rango lateral de 3 m y el exceso de rasante de 4 m en tres estaciones consecutivas son umbrales exploratorios del script. Son avisos para inspección. El muestreo de ±5 m puede caer dentro de la misma celda de 30 m o cruzar un borde de píxel abruptamente.

## Investigación propuesta

### 1. Verificar la planta con imagen de mayor resolución

Georreferenciar el JPEG en QGIS con puntos de control distribuidos alrededor de la calzada y a ambos lados de la ladera. Usar una ortofoto con georreferencia conocida o puntos medidos. Reservar puntos independientes y registrar sus residuos, sobre todo cerca del tramo que se quiere corregir. Evitar usar el eje OSM como control del ajuste, porque es el trazado que se está evaluando. Si la referencia disponible es Sentinel, limitar la conclusión a la ubicación general. Verificar orientación, posible inclinación de cámara y deformación del JPEG antes de tratarlo como imagen métrica.

Digitalizar ambos bordes donde sean distinguibles. Medir el desplazamiento firmado entre el eje del piloto y el centro de la huella en secciones por PK. Anotar incertidumbre local, ramales, sombras y sectores sin borde visible. Una corrección XY requiere un desplazamiento coherente que supere la incertidumbre del ajuste y de la digitación.

### 2. Obtener cotas reales de Earth Pro y verificar su procedencia

Abrir el KML del piloto, habilitar terreno y consultar **Mostrar perfil de elevación** para cada línea. Verificar unidades y contrastar primero PK 0, una curva y un sector de control en las tres trazas. Registrar coordenada, PK, lado, lectura original, unidades, origen, referencia vertical confirmada y método de extracción. Antes de poblar `earth_egm2008_m`, comprobar el datum y aplicar la transformación documentada que corresponda. Si no se puede confirmar, conservar la lectura original para inspeccionar la forma relativa del perfil y dejar pendiente la comparación absoluta. [Ayuda de Google Earth Pro](https://support.google.com/earth/answer/148134?hl=es-us)

La extracción automática a CSV desde el gráfico sigue por verificar. Un piloto de transcripción manual permite comprobar posición, resolución de lectura y repetibilidad antes de automatizar. La cota de la capa de terreno de Earth es una estimación en la posición de la línea. Investigar resolución efectiva y procedencia antes de considerarla una fuente independiente de los DSM locales. Para confirmar una rebaja de la calzada del orden de metros, buscar GNSS de campo con referencia vertical, un levantamiento vial o un modelo fotogramétrico/LiDAR que resuelva la plataforma.

Desde la raíz del repo, generar la plantilla y comparar una copia completada:

```powershell
$rauraGis = 'tools/rally/stage_gis/raura_quichas_gis'
& "$rauraGis/.venv/Scripts/python.exe" "$rauraGis/perfil_google_earth.py"
& "$rauraGis/.venv/Scripts/python.exe" "$rauraGis/perfil_google_earth.py" --earth-csv "$rauraGis/output/piloto_inicio/earth_lecturas_egm2008.csv"
```

El segundo comando presupone que se creó esa copia con cotas convertidas. El script regenera la plantilla cuando se ejecuta sin argumentos y escribe un CSV de comparación separado al recibir lecturas.

### 3. Aislar el problema lateral con una variante en Blender

Partir del [.blend del piloto](output/piloto_inicio/raura_stage2_piloto_relieve.blend). Comparar primero el piloto actual contra una variante que modifica solo los laterales. En el lado monte, representar el pie y la altura aparente del corte rocoso donde la evidencia lo sitúe. En el lado valle, modelar la franja previa a la caída con el ancho, continuidad y tipo de borde que se aprecien por sector. Diferenciar berma, roca natural y depresión lateral. Usar la dirección de carrera para identificar los lados.

Comparar cámaras a altura de conductor, planta y cortes transversales en los mismos PK. Si la evidencia justifica un cambio XY, ensayarlo localmente con transiciones suaves. Si hay cotas independientes que indican un exceso vertical sostenido, ensayar una corrección localizada de rasante con SciPy/OSQP y revisar pendiente y continuidad en ambos empalmes. Documentar por separado la contribución de cada cambio para saber cuál resolvió la percepción de carretera expuesta.

Antes de exportar una variante, ejecutar la auditoría de [costuras](auditar_costuras.py). Registrar fallos por PK y lado, revisar que la colisión corresponda a la geometría que se conduce y comprobar el encaje en Godot antes de extenderlo al resto de la bajada.

## Entregables de la investigación

- Proyecto QGIS o GeoTIFF de referencia con puntos de control, puntos reservados y error local documentado.
- CSV de lecturas de Earth con procedencia, unidades y datum, más comparación reproducible contra AW3D30 corregido, GLO-30 y la rasante.
- Tabla por PK con tramo, lado, evidencia, desplazamiento horizontal estimado, diferencia vertical, incertidumbre y acción sugerida.
- Comparación visual del piloto base y la variante lateral. Si se propone mover el eje o la rasante, incluir una vista adicional con ese cambio aislado y el resultado de la auditoría de malla.

La decisión debe poder justificarse por sector. Si la huella aérea respalda el eje y la corrección lateral recupera el encaje de las referencias, procede ajustar el corredor. Si la discrepancia horizontal supera el error local, procede estudiar un movimiento de eje. Si las cotas de la plataforma respaldan una discrepancia vertical, procede estudiar una corrección de rasante. Con la evidencia actual, las tres hipótesis siguen abiertas.

