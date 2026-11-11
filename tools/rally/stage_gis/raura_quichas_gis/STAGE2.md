# Rally Raura · Stage 2

La etapa baja de Nevado Raura a Cantera Quichas. El eje OSM aprobado mide 8.275,7 m en planta. La ruta de juego mide 8.124,1 m en 3D tras ajustar el eje en las horquillas. El descenso neto es de unos 439 m.

La calzada de grava mide entre 4,08 y 6 m. La rasante usa el DSM de 30 m con una pendiente de diseño máxima del 22 %. La rasante suaviza los cambios de pendiente en varias pasadas y conserva las cotas de los extremos. El arcén se une a una franja graduada que vuelve al DSM en hasta 72 m. Hay 12 m adicionales de calzada antes de la salida y después de la meta.

Desde la raíz del repositorio:

    .\scripts\run_rally_raura.ps1

Acepta el reglaje inicial para salir con el Escort. Hay tres parciales y meta. Los tiempos CPU son referencias sintéticas para la sesión individual. El archivo de autoría es output/raura_stage2.blend y contiene la imagen Sentinel empaquetada.

Para regenerar, prepara output/scene_input.json y output/sentinel.png con generar_revision.py y ejecuta:

    blender -b --factory-startup --python-exit-code 1 --python tools/rally/stage_gis/raura_quichas_gis/generar_stage2.py
    .\scripts\run_rally_raura.ps1 -Import

Los importadores GLB tienen desactivada la compresión de mallas y la generación de LOD para conservar la unión entre calzada y terreno.

Para validar el arranque, superficies y cronometraje:

    godot --headless --path game --quit-after 900 --script res://tests/rally/raura_stage2_contract.gd

Fuentes: © OpenStreetMap contributors, Copernicus DEM GLO-30 y Sentinel-2. Metadatos originales en data/.

La calzada usa grava fina de HandPainted con huellas de tierra compactada. Los arcenes y taludes usan cascajo más grueso, con roca gris en cortes pronunciados. Las tres texturas fuente están en textures/. Para regenerar solo el modelo visual y el .blend, añade -- --visual-only al comando de Blender de arriba.

En las muestras de ruta separadas aproximadamente 8 m, el cambio medio de pendiente bajó de 2,42 a 0,82 puntos porcentuales. El ascenso acumulado bajó de 147,5 a 65,6 m y el desnivel neto sigue en unos 439 m.
La bajada completa incorpora cunetas redondeadas, peralte gradual y perfiles JSON de desgaste. El inventario generado está en output/baches_stage2_resueltos.json. El generador completo aplica estas secciones por defecto. El paso longitudinal se refina a 20 cm cerca de los baches.
Antes de exportar, generar_stage2.py comparte los segmentos refinados de calzada con la primera banda del arcen. El contorno del terreno usa los mismos bordes y las secciones completas de los extremos. auditar_costuras.py comprueba caras, aristas, vertices sin uso y el emparejamiento dirigido de cada costura visual y fisica. Si falla, informa PK, lado, objeto y coordenadas.

Los primeros 700 m aplican desgaste_inicio_stage2.json. El perfil agrega baches asimétricos, labios continuos, rodadas con bordes y piedras expuestas. En los últimos 20 m del sector vuelve progresivamente al relieve original. El resto de la etapa usa el perfil y la semilla anteriores.
