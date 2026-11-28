# Caminos del Inca · SS01 Rajuntay Alto

## Especial completa

Desde la raíz del repositorio, ejecuta `./scripts/run_cdi.ps1`. La sesión de práctica carga el Lancia Fulvia HF y abre los reglajes de salida.

La geometría cubre el eje desde PK 0+000 hasta PK 5+156,705. La salida está en PK 0+050 y la meta señalizada en PK 5+106,705. El cronometraje termina al cruzar la puerta en el sentido de carrera. Quedan 50 m de carretera nominal al otro lado de la puerta. El terreno de juego se extiende unos 58 m desde el eje y enlaza con una malla 3D continua del valle y las montañas. El perímetro deja sin muro aproximadamente 46 m en descensos que cumplen el criterio del DEM de 14 m de caída en 24 m.

Para regenerar, instala Pillow y Shapely en Python, prepara los datos y ejecuta el generador en Blender desde la raíz del repositorio.

```powershell
$generador = 'tools/rally/stage_gis/rajuntay_alto/generar_ss01.py'
python $generador --prepare 'D:\RallyManiacAssets\stages\SS01_Rajuntay_Alto\SS01_Rajuntay_Alto'
blender -b --factory-startup --python-exit-code 1 --python $generador
python tools/rally/stage_gis/rajuntay_alto/generar_sectores.py
./scripts/run_cdi.ps1 -Import
```

## Perfil de grava de Rajuntay

[perfil_grava_ss01.json](perfil_grava_ss01.json) y [perfil_grava_ss02.json](perfil_grava_ss02.json) fijan los intervalos por metros recorridos en 3D desde la salida de cada especial. `perfil_grava.py` los convierte a las estaciones del generador y aplica las variaciones de rasante antes de construir el corredor. Comprueba la pendiente añadida y el límite de diseño en los intervalos intervenidos. Las compresiones tienen una entrada más corta que la salida. El bombeo desplaza la corona suavemente durante el enlace, y el asentamiento lateral vuelve a cero antes del borde de la calzada.

Rajuntay conserva una muestra del desgaste original entre los metros 60 y 300. Chinchán concentra el desgaste más intenso entre los metros 1.510 y 1.640. Cada perfil usa una semilla propia y limita el inventario a 15 baches por cada ventana móvil de 100 m. Los inventarios se guardan en `output/baches_resueltos.json` y `output/ss02/baches_resueltos.json`. SS07 recorre Chinchán en sentido inverso y SS08 hace lo mismo con Rajuntay.

## Horizonte y vegetación

La malla regional usa el recorte ampliado de Copernicus DEM GLO-30, muestreado cada 55 m. Permanece cargada y cubre todo el valle. El fondo 3D local conserva el detalle cerca del perímetro y se desvanece sobre la malla regional. El cielo del clima se ve sobre las cumbres.

`generar_sectores.py` toma el GLB de Blender y divide únicamente el detalle visual en celdas XZ de 192 m. Conserva triángulos, posiciones, normales, UV de textura y la máscara lateral de talud. Añade el PK en `UV2.y` para elegir variantes de carretera, talud y cuneta por tramos de 215 m, con fundidos de 20 m centrados en cada límite. Godot mantiene cargados los sectores a 450 m del coche o su posición prevista tres segundos más adelante. Los sectores salen al superar 690 m, mientras que la colisión, el cronometraje y los carteles de meta permanecen residentes.

Las 15 matas de ichu del FBX Grass Pack se exportan con tarjetas cruzadas y se comparten entre las cuatro especiales. Las variantes secas, envejecidas y altas usan los ocres del ichu de Rajuntay. Las frescas usan el oliva del anterior pasto_03. Cada variante tiene una pareja con nieve horneada a partir de la altura de sus hojas. El SS04 alterna ambas versiones según su máscara de nieve y reduce la densidad en las acumulaciones. Los arbustos y cactus mantienen sus tarjetas y sus pesos de dispersión.

Rajuntay aplica un factor de densidad de 0,45 al pasto y 0,60 a los arbustos. Las matas tienen una altura base de 0,29 a 0,56 m y se ajustan por familia. La dispersión reserva un pequeño radio alrededor del público, los animales y las rocas. Las instancias de todos estos objetos, incluidas las colisiones de arbustos y rocas, se crean y se liberan con sus sectores de terreno.

El escenario coloca 50 espectadores en zonas altas de césped separadas de la calzada, incluyendo nueve junto al talud de salida y seis detrás del coche. Sus tarjetas usan el 90 % de su escala anterior. Seis rebaños de cinco animales ocupan laderas bajas. Las 200 rocas se reparten en intervalos iguales de ruta, con posición lateral y tamaño aleatorios entre cinco perfiles que favorecen las cunetas y el pie del talud. Las rocas grandes usan colisión convexa. Las caras rocosas del talud usan `rajuntay_talud_ps1.png`, una textura de 256 × 256 con roca marrón fracturada.

La malla del talud exporta en UV2 la distancia normalizada desde la carretera al borde exterior. Godot usa esa máscara, la pendiente y ruido suave para fundir tierra, roca y pasto. La calzada comparte la tierra del arcén en su borde. La ladera y el terreno intermedio usan la misma proyección en coordenadas de mundo para que la mezcla continúe entre sectores.

El conversor de utilería exporta 21 sprites de público, siete de animales y 20 mallas de roca de los dos packs. Para contar espectadores y animales por separado, la dispersión usa figuras individuales y variantes de pastoreo.

Para regenerar el terreno regional y los sectores, instala Rasterio, NumPy y Pillow en Python. Ejecuta los siguientes comandos tras preparar `scene_input.json` con `generar_ss01.py --prepare`.

```powershell
$horizonte = 'tools/rally/stage_gis/rajuntay_alto/generar_horizonte.py'
python $horizonte --prepare
python tools/rally/stage_gis/rajuntay_alto/generar_ss01.py --prepare 'D:\RallyManiacAssets\stages\SS01_Rajuntay_Alto\SS01_Rajuntay_Alto' --extend-valley
blender -b --factory-startup --python-exit-code 1 --python tools/rally/stage_gis/rajuntay_alto/generar_ss01.py
python tools/rally/stage_gis/rajuntay_alto/generar_sectores.py
blender -b --factory-startup --python-exit-code 1 --python tools/rally/stage_gis/rajuntay_alto/generar_vegetacion.py
blender -b --factory-startup --python-exit-code 1 --python tools/rally/stage_gis/rajuntay_alto/generar_props.py
./scripts/run_cdi.ps1 -Import
```

La especial sigue la spline corregida de Rajuntay Alto hacia el sureste, en dirección a Ticlio. Los insumos están en `D:\RallyManiacAssets\stages\SS01_Rajuntay_Alto\SS01_Rajuntay_Alto`. El CSV aporta el eje y el kilometraje en UTM 18S. El DEM GLO-30 y Sentinel aportan relieve y cobertura. La grilla de 2,5 m procede de remuestreo o inferencia.

## Geometría y recorrido

- Generar los 5.156,705 m del eje existente. Interpolar la puerta de salida en el PK 0+050 y la de meta en el PK 5+106,705 sobre `s_corrected_m`. Quedan 50 m de carretera detrás de la salida y 50 m más allá de meta. La distancia cronometrada nominal según el CSV es 5.056,705 m. Recalcular la distancia 3D sobre la rasante final para los datos de juego.
- Adaptar la preparación GIS y el generador de [Raura](../raura_quichas_gis/STAGE2.md) con configuración de Rajuntay para calzada, rasante, cunetas, taludes y baches. Usar mallas visual y física y pasar la auditoría de costuras. Reutilizar la textura de grava de Raura y configurar la superficie de conducción como grava.
- Medir **30 m a cada lado desde el borde de la calzada** como margen nominal de maniobra. En terreno recuperable, situar el muro invisible al límite exterior de ese margen y extender la malla visual donde lo requiera la cámara. Resolver localmente horquillas y solapes del corredor para que el muro no cruce otro segmento de carretera.
- En barrancos, conservar la caída y dejar abierta su salida física. Mantener el talud visible desde la cámara durante la aproximación y al salir de la calzada. Las protecciones de barranco quedan para una fase posterior.

## Materiales de terreno

El [atlas preliminar](rajuntay_materiales_atlas_v1.png) toma la trama seca de las dos muestras de pasto y la paleta apagada de la foto de Rajuntay. Arriba, de izquierda a derecha, van pasto denso y pasto ralo con tierra. Abajo van pedregal gris para cortes y tierra compacta con piedra fina para terraplenes.

Las celdas de 128 × 128 se usan como materiales independientes. La mezcla de pasto denso, pasto ralo y pedregal se define por pendiente y ruido. El pasto procedural se coloca sobre el terreno exterior, fuera de la calzada y los taludes de la cuneta.

## Piloto, paisaje e integración

1. El piloto de 700 m permitió revisar baches, colisión y margen lateral antes de extender el generador al eje completo.
2. Revisar la transición entre el terreno detallado y la malla regional desde persecución y mirada lateral en una pasada completa. Medir el coste de renderizado al cargar sectores.
3. La escena completa integra ruta, cronometraje y tres parciales. La prueba `res://tests/rally/cdi_finish_contract.gd` verifica que el cronómetro y la competición sigan abiertos hasta cruzar la puerta y que haya grava con colisión tras la meta. Queda la conducción de aceptación para revisar las caídas, las recuperaciones y el horizonte a lo largo de la especial.

## SS02 Quebrada Chinchán

El evento de `run_cdi.ps1` empieza en Rajuntay Alto. Al cruzar su puerta de meta, el panel de resultados permite continuar a Quebrada Chinchán con la clasificación acumulada. La salida del SS02 está programada a las 08:20 en el itinerario del juego.

El SS02 usa la spline y los rásteres de Quebrada Chinchán. El proceso genera la calzada de grava, la colisión residente, el terreno regional y los sectores de 192 m. La máscara Sentinel/DEM se alinea al origen del SS02. Las texturas de terreno y los modelos de vegetación y utilería se comparten con Rajuntay, y su dispersión se calcula sobre la nueva ruta. Las puertas quedan a 50 m de los extremos del eje de origen.

```powershell
$gis = 'tools/rally/stage_gis/rajuntay_alto'
$source = 'D:\RallyManiacAssets\stages\SS02_Quebrada_Chinchan\SS02_Quebrada_Chinchan'
python "$gis/generar_ss01.py" --ss02 --prepare $source
python "$gis/generar_horizonte.py" --ss02 --prepare
python "$gis/generar_ss01.py" --ss02 --prepare $source --extend-valley
blender -b --factory-startup --python-exit-code 1 --python "$gis/generar_ss01.py" -- --ss02
python "$gis/generar_sectores.py" --ss02
python "$gis/generar_mascara_pastizal.py" --ss02 $source game/assets/rally/cdi_stage2/puna_seca
./scripts/run_cdi.ps1 -Import
```

Godot ejecuta el contrato de cronometraje y transición con `godot --headless --path game --script res://tests/rally/cdi_finish_contract.gd`.

## SS03 Chinchán Asfalto y SS04 Abra Ticlio

La secuencia del evento es SS01, SS02, área de servicio, SS03 y SS04. El servicio reserva 30 minutos de reparación y abre después el garaje para confirmar reglajes y cambiar neumáticos del inventario. Las horas de salida de SS03 y SS04 son 09:15 y 09:40.

Chinchán Asfalto tiene 6,24 km cronometrados sobre asfalto. Abra Ticlio tiene 6,19 km cronometrados. En Ticlio, la calzada cambia de asfalto a nieve compactada en el km 3,10 del recorrido cronometrado. El generador corta allí los cuerpos de colisión. El material visual de asfalto se mezcla con nieve a lo largo de unos 90 m, con acumulación desde los bordes y huellas visibles. La nieve de la calzada se mantiene después de la meta.

[perfil_asfalto_ss03.json](perfil_asfalto_ss03.json) y [perfil_asfalto_ss04.json](perfil_asfalto_ss04.json) especifican la rasante, el bombeo y las bolsas de baches por distancia 3D desde la salida. Los baches están espaciados dentro de esas bolsas y ocupan una sola rodada. Ticlio concentra las bolsas en el asfalto. Sobre nieve compactada tiene una ondulación ancha y una rodada suave. SS06 y SS05 usan, respectivamente, las mismas mallas de Chinchán y Ticlio en reversa.

Los materiales de calzada y acero usan las texturas de game/assets/rally/CDI/asfalto_estepa. En SS03 y SS04, el generador detecta arcenes con caída sostenida hacia afuera a 8 y 20 m de la calzada. Los tramos de al menos 14 m reciben guardarraíles con módulos y terminales texturizados. Su visual se carga por sectores y su colisión continua queda residente.

En Ticlio, el terreno de detalle, el fondo local y el DEM regional comparten la distribución de nieve por altitud, pendiente y exposición. Las siete texturas de roca y nieve viven en `game/assets/rally/CDI/nieve_ticlio`. Las acumulaciones crecen en cunetas y zonas suaves y dejan expuestos los cortes empinados. En la calzada, la cobertura sigue creciendo al ascender después de la transición visual y es mayor junto al arcén. Los guardarraíles de SS03 y SS04 tienen una escala vertical de 0,70 aplicada desde la base de cada módulo, también en la colisión.

Para regenerar estos tramos, usa la receta del SS02 con la bandera y la carpeta de origen correspondientes. La carpeta de la última orden de Python es `game/assets/rally/cdi_stage3/puna_seca` o `game/assets/rally/cdi_stage4/puna_seca`.

| Bandera | Carpeta de origen bajo `D:\RallyManiacAssets\stages` |
| --- | --- |
| `--ss03` | `SS03_Chinchan_Asfalto\SS03_Chinchan_Asfalto` |
| `--ss04` | `SS04_Abra_Ticlio\SS04_Abra_Ticlio` |
