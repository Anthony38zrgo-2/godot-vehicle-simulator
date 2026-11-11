# Rally Raura Stage 2 · Piloto de horquillas

El piloto usa los últimos 920 m del eje OSM aprobado, desde el PK 7.355,7 al 8.275,7. La salida y la meta de práctica están dentro del recorte para dar margen al coche. La distancia cronometrada tras suavizar el eje y la rasante es 832,6 m. El ancho provisional es 6 m de grava más arcenes de tierra de 1 m. El borde de cada talud comparte cotas y vértices de contacto con la ladera triangulada. El DSM de 30 m y el suavizado definen una rasante de prueba. La forma de las horquillas, las pendientes y la anchura necesitan revisión al volante antes de extender el proceso a la etapa completa.

Abre game/scenes/rally/raura_stage2_pilot.tscn y ejecuta la escena con F6. En el reglaje inicial, acepta para habilitar la salida con el Escort. Desde la raíz también se puede lanzar:

    godot --path game res://scenes/rally/raura_stage2_pilot.tscn

La escena tiene un parcial y una meta de práctica. Los tiempos CPU son valores sintéticos para iniciar la sesión. No hay llamadas de copiloto en el piloto.

Para regenerar desde la raíz con los insumos locales ya preparados:

    blender -b --factory-startup --python-exit-code 1 --python tools/rally/stage_gis/raura_quichas_gis/generar_piloto.py

El generador usa output/scene_input.json y output/sentinel.png, productos de generar_revision.py. Genera el .blend de autoría, dos GLB, manifiesto, ruta y datos de cronometraje. Las fuentes son OpenStreetMap contributors, Copernicus DEM GLO-30 y Sentinel-2. Sus metadatos están en data/.

Después de importar los GLB en el editor, ejecuta el contrato de física y cronometraje:

    godot --headless --path game --quit-after 900 --script res://tests/rally/raura_stage2_pilot_contract.gd

El contrato comprueba 560 rayos en calzada y arcenes, valida el parcial y la meta con un recorrido simulado y verifica una salida real del Escort con cuatro ruedas en contacto. Queda por conducir el recorrido completo y evaluar el comportamiento en las horquillas.
El lanzador apunta ahora a la etapa completa. Consulta STAGE2.md para regenerarla.
