# Acabado exterior del Lancia Stratos HF en CDI

El Stratos es el modelo de referencia para trasladar este acabado a los demás coches. Combina una carrocería de baja densidad, pintura de calle en 16 colores, bandas de luz calculadas en Godot, ópticas de aspecto fotográfico y detalles pequeños modelados en Blender. Esta guía describe la configuración actual y las medidas que se deben recalibrar para cada malla.

## Archivos y herramientas

| Recurso | Ubicación y función |
| --- | --- |
| Modelo original | `D:/RallyManiacAssets/cars/1965-2002-rally-cars/source/Cars/Lancia Stratos.fbx`. Aporta el exterior y la ubicación de las ruedas originales para medir el ajuste. |
| Generador de exteriores | `D:/RallyManiacAssets/tools/build_cdi_fbx_exteriors.py`. Importa, ajusta, hornea y exporta el modelo. |
| Refinamiento de malla | `D:/RallyManiacAssets/tools/refine_stratos_mesh.py`. Proyecta juntas sobre las UV, suelda y bisela la malla, asigna materiales y construye las manijas y el limpiaparabrisas. |
| Atlas y máscaras | `D:/RallyManiacAssets/tools/cdi_stratos_road_atlas.py`. Define las regiones según las UV del Stratos y coloca el detalle de las ópticas. |
| Carpeta de trabajo | `D:/RallyManiacAssets/cdi_fbx_psx/rt-lancia-stratos/`. Contiene `fitted.blend`, `lightmap.png`, `source_optics.png`, `source_front_signals.png`, los productos intermedios y `exterior_psx.blend`. |
| Recursos del coche en Godot | [Carrocería, texturas y manifiesto](../../assets/rally/rt/rt-lancia-stratos/manifest.json) · [Escena del Stratos](../../scenes/rally/rt/rt-lancia-stratos.tscn) |
| Pinturas y sombreado | [Catálogo](../../data/vehicles/liveries.json) · [Generador del mapa RGBA](../../../tools/generate_vehicle_livery_maps.py) · [Horneado al elegir pintura](../../scripts/rally/rally_livery_bake.gdshader) · [Iluminación 3D](../../scripts/rally/rally_toon_lighting.gdshaderinc) |

## 1. Ajuste y cierre de la carrocería

1. Importar el FBX con el exterior y sus cuatro ruedas separados. Convertir la orientación al sistema de Godot, con `X` hacia la derecha, `Y` hacia arriba y `−Z` hacia delante.
2. Medir los ejes y la envolvente del FBX. El generador remapea por tramos la longitud entre ambos ejes y los extremos, interpola la vía y hace coincidir los pasos de rueda con el punto alto de los neumáticos del proyecto. Para el Stratos se usan **2,179917 m de batalla**, **1,405909 m de vía delantera** y **1,46004 m de vía trasera**. Los pivotes y las ruedas de ejecución se toman del manifiesto del juego.
3. Soldar vértices coincidentes a **0,0002 m** antes del bisel. Las UV son atributos por esquina de cara y conservan sus costuras. La malla anterior estaba dividida en esas costuras y el bisel dejó huecos entre los pontones y los recubrimientos de rueda. Comprobar que cada arista de la chapa tiene dos caras antes y después del bisel.
4. En el Stratos se biselan aristas con un ángulo de al menos **26°**, limitadas a pasos de rueda, bordes del capó y carcasas de faros. Usar **4 mm**, un segmento y límite de solapamiento. Volver a verificar el GLB agrupando los vértices coincidentes por posición. El formato de exportación puede duplicarlos para representar UV, normales o materiales distintos.

Las posiciones, el ancho del bisel y las regiones de selección dependen de la malla. Al pasar a otro coche, revisar el ajuste de sus propias ruedas desde ambos lados y desde un ángulo bajo.

## 2. Atlas limpio, juntas y ópticas

El atlas se construye desde cero sobre las UV existentes del Stratos. La pintura parte de un tono uniforme y la máscara excluye cristales, gomas, faros, parrilla, escape y bajos. Esta separación evita que las variantes de pintura tiñan las ópticas o dejen restos del color predeterminado cerca de una costura.

- **Juntas de puertas, capó y tapa trasera.** Definir los recorridos sobre el coche y proyectarlos con rayos contra la malla. Interpolar las coordenadas UV dentro de cada triángulo y cortar el trazo cuando salta de isla. El atlas dibuja una línea fina en luminancia con un filo ligeramente más claro. Los valores nominales de la chapa son `248`, con hasta `−69` en el centro de una junta y hasta `+7` en su borde. Revisar que la línea siga la pieza a ambos lados y que sea legible a escala de cámara.
- **Oclusión ambiental (AO).** Hornear en Cycles un mapa de **1024 × 1024**, con **12 muestras**, **8 px** de margen y distancia de AO **0,22 m** para este modelo. El pulido sustituye puntos aislados que quedan más de **21 niveles** por debajo de la mediana local de **5 × 5**, limitado al interior de la máscara de pintura.
- **Faros escamoteables y pilotos traseros.** La hoja fotográfica generada `source_optics.png` aporta reflector, estrías y el contraste entre ámbar y rojo. Se recortan las lentes circulares y se ajustan a sus islas UV, con una transición corta hacia el bisel oscuro. Las ópticas conservan sus colores con las 16 pinturas.
- **Direccionales delanteras.** La hoja `source_front_signals.png` aporta dos franjas fotográficas, ámbar arriba y lente estriada clara abajo en el coche. Se muestrean por separado, se rotan para las UV de la fascia y se aplican a los dos rectángulos en el atlas final de **1024 × 1024**. Revisarlas en una vista frontal cercana y a la distancia normal de juego.
- **Limpiaparabrisas y manijas.** El Stratos lleva un limpiaparabrisas central en reposo. El script proyecta sus puntos sobre la curvatura del cristal y construye pivote, brazo de metal oscuro y escobilla de goma. Las separaciones nominales son **20 mm** para el brazo y **10 mm** para la escobilla. Las manijas usan una base oscura y una pieza corta con acabado metálico. Ajustar posición, dimensiones y número a la carrocería de cada coche.

### Cobertura de las 16 variantes

El mapa de datos de pintura usa **R** para la máscara, **G** para AO, **B** para la luz direccional horneada y **A** para la luminancia de juntas. El Stratos usa `baked_ao_only = true`. En el horneado de pintura, la respuesta direccional queda en `[1.0, 1.0]`, el tinte de sombra en `0.0` y la saturación en `1.0`.

La carrocería, los detalles del exterior y el conjunto cristal/junta comparten un atlas. Los tres materiales deben recibir la misma textura recoloreada y la misma máscara de pintura. Así un borde con pintura que caiga en una cara del material del cristal también toma el color seleccionado. Una parte con máscara a cero conserva sus píxeles de origen. Para detectar una fuga del atlas predeterminado, probar primero **Negro** contra los bordes que en origen eran **Celeste**.

## 3. Iluminación por bandas y materiales en Godot

### Pintura

Las bandas salen de la altura local de la carrocería. El perfil usa un zócalo de **0,26 m** y un hombro nominal de **0,90 m** que baja hacia el morro y la cola. Por eso las bandas continúan de la puerta a las aletas aunque sus UV estén separadas. La luz ajusta ligeramente el umbral, y la orientación de las superficies superiores da al capó un tono amplio.

| Ajuste actual | Valor de partida del Stratos |
| --- | --- |
| Tonos de abajo a arriba | `0.16 → 0.35 → 0.60 → 0.91` |
| Alturas normalizadas de las transiciones | `0.23–0.245`, `0.47–0.485`, `0.70–0.72` |
| Superficies superiores | `0.73–0.94` según orientación a la luz |
| Reflejo móvil de pintura | Fuerza `0.42`, umbral angular `0.942–0.967`. Se aplica al hombro y a las zonas que reciben luz |
| Brillos de pintura y vidrio | Cuatro niveles contando el cero, con tramado ordenado **2 × 2** en las transiciones |

### Cristales, juntas y lamas

- **Cristales.** La máscara `rt-lancia-stratos_glass_reflection.png` pesa los extremos curvos del parabrisas en rojo y la banda alta de las ventanillas en verde. El shader calcula el reflejo según la orientación del vidrio y el punto de vista. El centro del parabrisas queda oscuro. La junta mate se obtiene dejando un margen de seguridad dentro del contorno UV y excluyendo las zonas de pintura del reflejo.
- **Lamas traseras.** `Stratos_Rear_Louvers` activa un relleno tenue solo en las caras superiores de las lamas. El shader obtiene la normal real de la cara, mide la distancia al borde trasero de cada lama y realza ese filo. Los bordes están en `Z = 0.793, 0.912, 1.020, 1.131` m en el Stratos. Esta diferencia se mantiene incluso en sombra vertical. Para otro coche hay que medir sus lamas y revisar la forma de su panel de fondo.

### Resolución, tramado y color

| Parámetro | Ajuste activo |
| --- | --- |
| Color del atlas de pintura | **RGB888**, con `paint_rgb555 = false` tanto en la exportación como en el selector |
| Atlas final y cuadrícula efectiva | **1024 × 1024** y **512 × 512**, respectivamente |
| Tamaño del tramado horneado | `dither_cell_scale = 2`, equivalente a **4 × 4 texeles del atlas por celda**. La matriz ordenada tiene **4 × 4 celdas**. |
| Intensidad del tramado | En la variante Celeste, `dither_base = 0`, `dither_shadow_boost = 0.86`, `shadow_band = [0.56, 0.96]`. La intensidad es independiente del tamaño de celda. |
| Oclusión de Celeste | `ao_strength = 0.52`, `shadow_gamma = 1.06` |
| Cuadrícula de pantalla | **480 × 360**, ajuste de vértices **0,22** y deformación afín UV **0,18**, con entrada gradual entre **0,9 y 2,6 m** de profundidad |
| Filtrado | Vecino más cercano con mipmaps para el albedo |

El exportador activa el tramado a 8 bits en `ps1kit` y aplica `pattern_scale = 2` sobre el tamaño efectivo. Godot usa la misma escala para indexar su matriz cuando se cambia de color. El tramado de reflejos en pantalla tiene una cuadrícula y una intensidad propias.

## 4. Regenerar y revisar

La exportación probada usa Blender **5.2.0 LTS** disponible como `blender` en PATH, Python con **Pillow, NumPy y OpenCV**, y el `ps1kit` local en `D:/RallyManiacAssets/tools`. La opción `--blender` admite una ruta explícita al ejecutable. Las hojas de ópticas deben existir en la carpeta de trabajo antes de exportar.

Desde la raíz de este repositorio, con `GODOT_BIN` configurado para la instalación local:

```powershell
python -u D:/RallyManiacAssets/tools/build_cdi_fbx_exteriors.py --repo . --work D:/RallyManiacAssets/cdi_fbx_psx --cars rt-lancia-stratos --reuse-bake
& $env:GODOT_BIN --headless --path game --editor --import --quit
```

`--reuse-bake` reutiliza `fitted.blend` y `lightmap.png`. Retirarlo cuando cambien el FBX, el ajuste de la carrocería o las UV. El generador instala el GLB y el mapa de pintura, y actualiza el tamaño y SHA-256 del GLB en el manifiesto. Al generar un atlas para un coche nuevo, producir también su máscara de reflejo, cargarla en la escena y apuntar a los materiales que realmente exporta Blender.

### Lista de comprobación para el siguiente coche

- **Geometría.** Confirmar batalla, vías, pivotes y envolvente. Inspeccionar pasos de rueda delanteros y traseros y comprobar la incidencia de dos caras por arista de la chapa exportada.
- **Atlas y máscara.** Probar el color predeterminado, Blanco y Negro. Buscar residuos en bordes de cristales, molduras, paneles y ópticas. Si un punto solo se ve en otro color, revisar qué material recibe el atlas recoloreado. Si aparece en todos, localizar la cara y el texel que lo producen.
- **Iluminación.** Comparar dos pinturas con la misma cámara y luz. Revisar hombro, costado y zócalo. Probar también una sombra vertical sobre las lamas para comprobar que conservan el contraste.
- **Escala.** Revisar reflejos, juntas, ópticas y tramado en primer plano y a distancia de persecución. Confirmar que RGB888 se aplica tanto al atlas como al horneado de las variantes.
- **Entrega.** Comprobar los hashes del manifiesto y revisar el diff de los mapas generados. En un cambio localizado de geometría u ópticas, una regeneración puede introducir una diferencia ajena en el mapa de pintura. Conservar la versión validada si la máscara y los datos de pintura quedan fuera del cambio.

El Stratos se revisó en capturas estáticas de Godot, incluidas vistas delantera y trasera, pinturas oscuras y una prueba de sombra vertical sobre las lamas. La lectura del tramado de 4 × 4 en movimiento desde la cámara de persecución queda pendiente.
