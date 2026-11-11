# Rally Raura — Etapa 1

Eje OSM original: 8.299,1 m. Longitud 2D UTM: 8275.7 m. Diferencia: -23.4 m.
Ajustes UTM de extremos: 5.2 m y 8.8 m.
DSM en extremos del eje: 4707.00244140625 y 4268.4287109375 m. Ver perfil_dsm.csv. Es un modelo de superficie de 30 m, no una rasante medida.
Cruces con ramal OSM: 4. Aristas del candidato incompatibles con el filtro básico de acceso/sentido: 0.
El filtro considera etiquetas presentes, sin inferir accesos que OSM no indica ni comprobar restricciones de giro.
Alternativas conectadas encontradas al retirar una arista del candidato: 0.
Este método encuentra desvíos más cortos para esas exclusiones. No enumera todos los itinerarios posibles.

Ver mapa_revision.png y los recortes Cxx.png. Verde: candidato. Naranja: alternativas. Celeste: otras vías. Morado: imagen sin datos.

## Revision visual de Sentinel-2
- C01 (PK 0.0 m, ambiguo): Empalme de servicio a 14 m de C02, apenas 1,4 pixeles Sentinel.
- C02 (PK 14.0 m, visible_parcial): La traza clara al este coincide con LM-599. El empalme exacto queda ambiguo.
- C03 (PK 8168.5 m, ambiguo): En la cantera, la imagen no separa con claridad LM-599 de las superficies removidas.
- C04 (PK 8275.7 m, visible_parcial): Se distingue un corredor hacia el suroeste. Su union exacta junto a la meta queda ambigua.

Descenso neto DSM: 439 m.
La diferencia de distancia corresponde al mismo eje medido en UTM frente a la aproximacion esferica original.
La longitud sigue provisional. Para cerrar los empalmes, usar imagen de mayor resolucion, GPX o puntos de paso.
Fuentes: © OpenStreetMap contributors, Copernicus DEM GLO-30 y Sentinel-2. Metadatos originales en data/.

Regeneración desde la carpeta del paquete: .venv/Scripts/python.exe generar_revision.py
Herramientas: Blender 5.2/bpy, Rasterio y Pillow. Se usan las convenciones GeoScene de BlenderGIS. El tooling de pacenotes analiza carreteras construidas y no se requiere para esta revisión GIS.
