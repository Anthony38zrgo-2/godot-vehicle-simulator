# Rally Raura · Piloto de rasante OSQP

El piloto cubre el PK horizontal 4.456,94–5.155,25 m del eje jugable, con 698,31 m en planta y 700,94 m de recorrido 3D. Incluye la horquilla de ramas cercanas próxima al PK 4+890 del eje OSM de referencia. El eje XY y la huella de la calzada y los arcenes se mantienen fijos respecto a la base generada. La rasante se ajusta en Z y conserva las cotas y pendientes de los dos empalmes.

## Resultado de rasante

| Métrica | Actual | OSQP |
|---|---:|---:|
| Pendiente máxima absoluta | 21,79 % | 17,67 % |
| Cambio de pendiente RMS por 10 m | 2,62 puntos porcentuales | 2,02 puntos porcentuales |
| Percentil 95 del cambio por 10 m | 3,87 puntos porcentuales | 3,50 puntos porcentuales |
| Ascenso acumulado | 5,03 m | 5,25 m |

El cambio máximo de cota fue 0,45 m. Se fijó una pendiente máxima de diseño de 22 % y un máximo de cambio de 3,5 puntos porcentuales por 10 m. El objetivo pondera el perfil jugable, la proximidad al GLO-30 y la continuidad de pendiente. AW3D30 ya alineado se usa para bajar la confianza donde ambos DSM discrepan.

## Corredor

Se tomó como referencia el enfoque por secciones de [AQGIS-Sivil3D](https://github.com/pypadopoulos-HY/AQGIS-Sivil3D). Se usaron taludes independientes de corte (0,90 m/m) y relleno (0,65 m/m) desde el arcén y se buscó la primera intersección con el GLO-30 interpolado. Son parámetros de prueba. El complemento QGIS no se ejecutó.

De 712 lados de sección, 56 encontraron un encuentro compatible dentro de la huella fija, 233 lo encontraron fuera, 419 no lo encontraron dentro de 36 m y 4 dieron un cruce que no permitía un empalme continuo en el borde. Los lados sin encuentro compatible conservan un borde limitado y se unen a la malla exterior común mediante la transición graduada del generador. Esas zonas requieren un segundo piloto con huella lateral variable o resolución conjunta de las ramas. Las cifras son diagnósticos previos a la transición de 20 m en ambos empalmes.

El generador comprobó la ausencia de secciones invertidas y que cada arista del perímetro coincide con la malla de terreno. En Godot pasaron 450 rayos de contacto en la calzada y el arcén, cuatro puertas de cronometraje simuladas y el arranque del Escort con cuatro ruedas en contacto. Falta conducir el piloto completo y evaluar la transición lateral.

## Probar y reproducir

Desde la raíz:

    .\scripts\run_rally_raura.ps1 -PilotOsqp

La colección oculta «Rasante anterior (comparacion)» en Blender muestra el eje base. Los productos de comparación están en output/piloto_osqp/. perfil.csv contiene el perfil actual, optimizado y las dos referencias DEM. comparacion.json guarda las métricas. propuesta.json contiene las secciones, el encuentro estimado y el estado de cada lado por PK.

Preparar la base con generar_revision.py si faltan los datos de escena. En el entorno de tools/xdem instalar OSQP 1.1.3 si aún no está disponible. Ejecutar:

    blender -b --factory-startup --python-exit-code 1 --python tools/rally/stage_gis/raura_quichas_gis/generar_stage2.py -- --pilot-survey
    .\tools\xdem\.venv\Scripts\python.exe .\tools\rally\stage_gis\raura_quichas_gis\optimizar_piloto_osqp.py
    blender -b --factory-startup --python-exit-code 1 --python tools/rally/stage_gis/raura_quichas_gis/generar_stage2.py -- --pilot-osqp
    .\scripts\run_rally_raura.ps1 -PilotOsqp -Import

Contrato de Godot:

    godot --headless --path game --quit-after 900 --script res://tests/rally/raura_stage2_contract.gd -- --pilot-osqp

## Variante con relieve

La variante conserva el recorrido y las puertas del piloto OSQP. Aplica peralte gradual según curvatura, con límite de 4 %, y una depresión redondeada del lado del corte donde hay espacio. Los rangos, densidades, grupos y zonas se editan en [desgaste_piloto.json](desgaste_piloto.json). El inventario resultante se guarda en output/piloto_osqp/baches_resueltos.json. El banco de velocidades y la calibración al volante quedan pendientes. En los taludes se redondean los dos extremos de cada sección dentro del ancho disponible, con pequeñas deformaciones de hasta 15 cm que se anulan en las costuras. La malla del terreno cercano reduce la pendiente al acercarse al borde. Los sectores estrechos reciben menos deformación.

La calzada usa filas separadas como máximo 20 cm, 40 bandas transversales, dos rodadas variables y 51 baches de borde gradual con semilla 20261111. El relieve se desvanece hacia los bordes de calzada y los extremos del piloto. La depresión total se limita a 13 cm. La superficie visual y la de colisión se construyen a partir de los mismos vértices y caras.

    .\scripts\run_rally_raura.ps1 -PilotRelieve

Para comparar con la rasante sin este relieve, usa -PilotOsqp. Regenera la variante desde la misma propuesta del piloto:

    blender -b --factory-startup --python-exit-code 1 --python tools/rally/stage_gis/raura_quichas_gis/generar_stage2.py -- --pilot-relief

La escena Blender está en output/piloto_osqp/raura_stage2_piloto_relieve.blend. El contrato de Godot con --pilot-relief verificó 450 contactos de calzada y arcén, los baches, el arranque y el cronometraje. Queda por comparar el comportamiento al volante con el mismo reglaje y la misma velocidad.
