# Inventario de agua de Kenia y vado piloto `kenya_ford_1`

Salida de la fase 2 del [plan de agua dinámica](KENYA_DYNAMIC_WATER_IMPLEMENTATION_PLAN.md).
Datos versionados en [`kenya_rivers.json`](../../data/rally/kenya_rivers.json) (`format_version: 1`).
Herramientas: `game/tests/rally/kenya_water_survey.gd` (8 etapas),
`kenya_ford_survey.gd` (vado + puente), `kenya_ford_closeup.gd` (cobertura,
orillas, cruces 2/3/5/6). Baselines previas al runtime registradas en el
turno anterior (`puddles_contract` PASS, etc.).

## 1. Inventario de las ocho especiales (medido en escena)

Superficies de agua localizadas en los GLB visuales (triángulos, cotas y
huella en espacio del tramo). La colisión existe en las 8 etapas
(`Collision_Road/Terrain_Dirt/Terrain_Grass/Barriers/...`).

| Stage | river1_1 (tris / cota Y) | river2_1 (tris / cota Y) | Otros en escena | Estado |
| --- | --- | --- | --- | --- |
| kenya_stage1 | 160 / −4.62…21.48 | 634 / −5.46…−5.17 (plano) | `jungle_river`, `jungle_river_road`, `kenya_river_1/2`, `kenya_river_road_2`, `jungle_vaterfall*` (6.4…22.3). **Sin puente.** | **piloto** `kenya_ford_1` (vado 333 mm, prog 1738.3) |
| kenya_stage2 | — | 19599 / −5.04…−0.64 | Bancos `kenya_river_1/2/4`, vados `kenya_river_road_1/2/3`, secos `kenya_river_dry_*` (+variantes `_` LOD), puentes `kenya_bridge*` (tablero −3.97) | **activo**: `ford_b` (vado 458 mm, prog 4277.8) + `reach_a` (sin vado, solo visual) |
| kenya_stage3 | 316 / −11.25…14.82 | — | `jungle_river`, `jungle_vaterfall*` | **activo**: `ford_north` (157 mm, prog 1068.2) + `ford_south` (198 mm, prog 3084.6) |
| kenya_stage4 | — | — | Ningún material de agua en malla. Texturas huérfanas en activos (`river1_1/2_1`, `kenya_river_*`, `waterfall_*`, `kenya_bridge*`): no autorizan inundar | **sin agua confirmada** |
| kenya_stage5 | — | 5837 / −4.58…−4.43 | Bancos, vados `kenya_river_road_1/2/3`, `kenya_bridge` (tablero −3.93): el cruce (prog 2552…2593) es **puente**, no vado | **activo**: `bridge` (franco 0.60 m, prog 2572.5), coche seco |
| kenya_stage6 | 463 / −10.88…12.58 | 7282 / −10.45…−7.25 | `jungle_river`, secos + LOD, `kenya_bridge*` (dos tramos), `jungle_vaterfall*` | **activo**: `ford_west` river2_1 (297 mm, prog 1222.7) + `bridge_jungle` river1_1 (puente, prog 1901.8) |
| kenya_stage7 | — | — | Sin materiales de agua en malla; texturas huérfanas como en 4 | **sin agua confirmada** |
| kenya_stage8 | — | — | Sin materiales de agua en malla; texturas huérfanas como en 4 | **sin agua confirmada** |

Reglas aplicadas desde la investigación:

- Solo `river1_1` / `river2_1` son lámina dinámica. `kenya_river_dry_*`
  exige geometría y umbral verificados; las variantes con sufijo `_`
  (stages 2 y 6) parecen LOD del mismo lecho.
- `waterfall_1/2` y `jungle_vaterfall*` son decorativas (junto a river1_1
  en 1/3/6, cotas altas): función visual, excluidas.
- `river1_2` / `river2_2` son variantes de animación del motor original,
  no contorno.
- Lechos/bancos (`kenya_river_1/2/4`, `jungle_river`) y calzadas de vado
  (`kenya_river_road_*`, `jungle_river_road`) describen fondo y orillas:
  no se inundan por nombre.
- 4/7/8: 0 triángulos de agua y 0 materiales (verificado en escena, no
  solo por la investigación del BMF).

## 2. Canales por stage (misma lógica: solo donde hay registro river)

Río largo subdividido por geometría/clima: cada canal lleva su huella
verificada, su progreso climático propio y su plano base anclado al nivel
medido en su vado (`level_anchor`; la pendiente de la malla se conserva).
Cobertura particionada por huella (centroide del triángulo, franja común de
4 m) y una sola instancia por desplazamiento (propiedad por huella más
cercana): sin doble lámina ni escalones por ello. Validación:
`kenya_channels_validate.gd` (8 canales, 0 diagnósticos).

| Canal | Stage | Cruce | Medición |
| --- | --- | --- | --- |
| `kenya_ford_1` (piloto) | 1 | vado river2_1 | 333 mm en base, prog 1738.3 (ver §3) |
| `kenya_stage2_ford_b` | 2 | vado river2_1 (idx 409) | calzada −2.02 bajo lámina −1.562 → **458 mm**; prog 4277.8 (frac. 0.6295) |
| `kenya_stage2_reach_a` | 2 | sin vado (idx 124–128) | calzada ~−3.97 un metro sobre lámina −4.99; seco incluso en crecida; solo visual + control seco |
| `kenya_stage3_ford_north` | 3 | vado river1_1 (idx 101) | **157 mm** en base; prog 1068.2 (frac. 0.2525) |
| `kenya_stage3_ford_south` | 3 | vado river1_1 (idx 292) | **198 mm** en base; prog 3084.6 (frac. 0.7291) |
| `kenya_stage5_bridge` | 5 | puente (idx 241–245) | tablero −3.933 sobre lámina −4.53, franco 0.60 m; prog 2572.5; coche seco |
| `kenya_stage6_ford_west` | 6 | vado river2_1 (idx 116) | **297 mm** en base; prog 1222.7 (frac. 0.1798); independiente del river1_1 |
| `kenya_stage6_bridge_jungle` | 6 | puente sobre river1_1 (idx 180–182) | tablero ~−3.17 a 0.3 m de la ruta, lámina ~−7.65; prog 1901.8; coche seco |

Descartes documentados: stage2 idx 125 (−5.92 a 0.5 m) es un vértice bajo
aislado fuera de la superficie útil (mediana −3.97 a 2 m); no es vado.
Stage6 idx 180–182 pasa 4–5 m por encima del river1_1: puente, no vado.

## 3. Vado piloto `kenya_ford_1` (kenya_stage1, river2_1)

- **Posición / progreso / dirección:** centro (761.5, −5.755, −1321.1),
  ruta idx 168, progreso **1738.3 m** (fracción 0.3806 de 4567.4 m),
  dirección (−0.86, 0, −0.51).
- **Lámina base:** river2_1 plano, y ≈ **−5.422** en el vado (rango total
  del tramo −5.46…−5.17: pendiente casi nula, el incremento uniforme no
  genera escalones).
- **Piso de ruedas:** calzada de colisión **continua** idx 165–172 que
  desciende −3.982 → −5.448 → **−5.755** → −3.984 bajo la lámina:
  **~333 mm de agua en base** en el centro (cruce transitable), 15 mm por
  encima en la entrada (idx 167: seco en base, ~476 mm en crecida máxima).
  Sin huecos de colisión en el cruce (vértices a 0.0–2.9 m de la ruta).
- **Fondo visible:** tablero visual del vado `kenya_river_road_2` a −5.672
  (8 cm sobre la colisión, bajo la lámina): desde cámara se ve calzada bajo
  agua somera, coherente con el piso físico.
- **Orillas y cota máxima:** terreno ~−4.2 a ±9–15 m; crecida máxima
  -5.422 + 0.45 = **-4.972**, contenida con **~0.5 m de margen**.
- **Puente control:** Kenia 1 no tiene puente; control en **Kenia 5**:
  tablero −3.933 (plano), lámina −4.54…−4.50 debajo, **franco 0.60 m**,
  ruta a 4.65 m (idx 243, prog 2572.5 m). Debe registrar seco siempre.
- **Alternativa:** segundo vado candidato en river1_1 (prog ~174.5 m,
  ~170 mm en base, idx 17); river1_1 alto de stage1 (hasta 21.48) pertenece
  al tramo de cascadas, fuera del piloto.

### Puntos de comprobación reproducibles

`ford_check` (centro, idx 168), `edge_check` (entrada idx 167),
`outside_check` (idx 170, calzada −2.813) y `bridge_check` (Kenia 5) están
en `kenya_rivers.json` con posición, progreso, cotas e inmersión base.
Diagnóstico en runtime: `RALLY_RIVER_READY id=kenya_ford_1 …` (huella,
cota base, tris). Cámaras calculadas para la captura en juego:

- Fija: pos (766.1, −3.555, −1328.9) mirando al centro del vado.
- Cabina: pos (766.7, −4.605, −1318.1) (6 m antes, 1.15 m sobre calzada)
  mirando (758.1, −5.005, −1323.2).

### Referencias visuales estado actual

Pendientes de captura en juego (headless no renderiza): base / crecida /
drenaje desde cámara fija y cabina con misma trazada y velocidad,
salpicaduras, desaceleración y profundidad registrada; puente y orilla para
cortes, agua flotante o extensión fuera del cauce; coste física/render
(Kenia 1/2/6). Las poses y el protocolo están arriba; las capturas
completan la fase 2.

## 3. Pruebas

- `kenya_rivers_contract.gd` — modelo. **PASS**
- `kenya_rivers_probe.gd` — geometría/contacto sintético. **PASS**
- `kenya_channels_validate.gd` — 8 canales, 0 diagnósticos. **PASS**
- `water_detail_contract.gd` — material de río y uniform `rise_m`. **PASS**
- `puddles_contract` **PASS**, `puddles_stage_probe` **PASS**,
  `dynamic_weather_tires_contract` **PASS**,
  `weather_runtime_regression` **falla por flujo de garaje preexistente**
  (idéntico fallo con los cambios apartados; otro trabajo en curso en el
  árbol, no causado por esta entrega).

## 4. Pasos 0 y 1: propiedad por superficie y pendiente real

Dos cambios en `rally_river_channels.gd`, sin tocar el shader ni los datos.

### Paso 0 — propiedad por (malla, superficie)

La propiedad de mallas era por **MeshInstance completo**. En Kenia
`river1_1` y `river2_1` son superficies distintas del MISMO nodo
(`Track_Road_And_Terrain`), así que un canal se apropiaba de la malla
entera y el otro se quedaba sin material. Ahora la propiedad es por
`(malla, surface_idx)` y la precedencia se resuelve con la huella
(la que contiene el origen de la instancia; si no, la más cercana).

Efecto medido sobre el material activo de cada superficie:

| Stage | Superficie | Antes | Ahora |
| --- | --- | --- | --- |
| 6 | `river1_1` | material importado (sin shader) | shader de río, huella `bridge_jungle` |
| 1/2/3/5 | `river1_1`/`river2_1` | shader de río | shader de río (sin cambio) |

### Paso 1 — pendiente real y ventana de horneado

- El ajuste del plano base usaba una muestra dispersa de la malla (1 de
  cada *N* vértices). Ahora se conserva la densidad **completa** dentro de
  la huella: el ajuste por mínimos cuadrados refleja la pendiente real
  del tramo en lugar de una pendiente de ruido.
- La ventana vertical del rayo de colisión sigue al **plano base local**
  (antes: un único nivel) y se abre hasta el **rango real de la lámina**
  (`surface_min_y`/`surface_max_y`). Con la ventana fija anterior, el
  lecho de los tramos con desnivel (cascadas de `river1_1`, hasta Y 21.5)
  quedaba sin muestrear y la lámina se descartaba entera.
- Si la huella no contiene vértices de agua, el ajuste avisa por
  diagnóstico en vez de dejar un plano degenerado en el origen.

Verificación (8 canales, antes → después):

- Anclaje del vado: **exacto en los 8 canales** (`level_at(anchor) ==
  anchor.y`), luego las inmersiones calibradas no cambian.
- Máscaras de lecho: **100 % válidas** en los 8 canales (antes también).
- `kenya_stage2_ford_b`: la pendiente local medida pasa de
  `gz=-0.0312` a `gz=-0.0224` (ajuste denso); el nivel en el vado sigue
  clavado en −1.83 m.
- Desvíos en los puntos `edge_check` documentados (stage1 −163 mm,
  stage2 −512 mm, stage3 −474 mm, stage6 −127 mm): **preexistentes**, se
  midieron igual en el código original. Provienen de documentar el vértice
  de la malla importada frente al nivel del plano de referencia.

## 5. Cobertura del cauce: qué es "agua" en estos activos

Medido sobre los GLB y la colisión (sondas headless con
`RallyTrackCollisionBuilder`):

1. **La lámina `river2_1` no es agua**: su textura importada es de
   **roca/cieno** (`kenya_stage1_visual_river2_1.png`). El río del activo es
   un **lecho seco**; el agua solo existe como concepto en los vados.
2. **La cinta importada es un zigzag con huecos**: son 634 triángulos
  alternos de ~5 × 2.5 m a lo largo de 1.120 m. El agua necesita superficie
   continua, así que no puede dibujarse sobre ella.
3. **La colisión del cauce lleva una tapa plana**: `Collision_Terrain_Dirt`
   tiene triángulos planos a −5.42 (nivel del agua) **encima** del valle
   (lecho a −6.32, verificado en los cortes de z = −1321 y −1540). El
   barrido de 634 triángulos de la lámina no encuentra **ningún** lecho por
   debajo de −5.6: fuera de los vados no hay hondonada que inundar.
4. El "vado" de Kenia 1 es, en la colisión, una hondonada pequeña en
   **(755.5, −1306.5)** con el lecho a **−5.651** (la calzada de colisión
   solo baja a −5.157; el −5.755 documentado era la calzada **visual**).

### Solución implementada: capa de agua encima, no sustitución

Antes, la capa dinámica **sustituía** el material importado de toda la
superficie del cauce. El shader descarta donde no hay agua, así que dentro
de la huella (65 × 60 m en el vado) el río se quedaba **sin textura**:
de ahí el "seco abruptamente" que se veía.

Ahora:

- La lámina importada **se conserva intacta**: el lecho seco mantiene su
  aspecto en todo el recorrido y el río nunca aparece en negro.
- Encima, cada cauce dibuja una **malla de cobertura** propia (rejilla
  sobre la huella, a la cota del plano base, con la resolución del campo
  de lecho). El shader recorta esa malla contra el lecho horneado, así que
  solo queda pintada el agua real.
- La capa se eleva `WATER_RENDER_BIAS_M` (5 cm) respecto a la lámina
  importada, que es opaca; esa elevación **no** cuenta en el cálculo de
  profundidad, así que el agua que ve el jugador y la que siente el coche
  coinciden.
- El campo de lecho se filtra en lineal (`filter_linear`): con el filtrado
  nearest el borde del agua salía escalonado por celda de 1 m.

Consecuencia: el agua dinámica solo aparece donde la **colisión** tiene
hondonada. En Kenia 1 son ~9 m² (la hondonada del vado). Cubrir el río
entero exige quitar la tapa plana de la colisión (tarea de activo, no de
código): hasta entonces, cualquier cauce nuevo solo pintaría donde el
terreno de colisión esté por debajo de la lámina.

### Tapa de la colisión retirada (solución aplicada)

La tapa plana que cerraba el cauce se elimina **al construir la colisión**
(`rally_track_collision_builder.gd`):

1. `_collect_water_levels()` rasteriza la lámina importada (el agua real de
   la escena) en una rejilla de 0.5 m: cada celda guarda su nivel.
2. Al construir el cuerpo del terreno, los triángulos **planos** (desnivel
   < 15 cm) que están **al nivel del agua** se descartan. El valle real
   (paredes y fondo) no es plano, así que se conserva.
3. Solo se aplica al terreno: la calzada mantiene su superficie y las
   barreras no se tocan.

Triángulos de tapa retirados por etapa: Kenia 1 = 761, Kenia 2 = 19 452,
Kenia 3 = 288, Kenia 5 = 5 837, Kenia 6 = 7 654.

**Criterio: la tapa se retira como hoja conectada.** La tapa exportada es una
lámina continua al nivel del agua que cubre el valle. Si solo se retiran
los triángulos que coinciden con el nivel del agua, quedan fragmentos
sueltos: en Kenia 2 la tapa está 145 mm por encima del nivel en un tramo
y ese bloque se quedaba en pie, forman **un muro de 53 cm en mitad del
cauce**, justo al otro lado de la calzada del vado (x = 2393, z = −1507):
imposibilizaba cruzar el río. Por eso, desde los triángulos semilla (planos
y al nivel del agua) se extiende la retirada a los vecinos que también son
planos y están cerca del nivel: se retira la hoja entera y el valle queda
limpio.

Perfil transversal del vado de Kenia 2 (colisión con y sin retirada):

| x | Original | Con retirada (hoja) |
| --- | --- | --- |
| 2333 | −2.007 | −2.447 (valle) |
| 2353 | −1.794 | −2.374 (valle) |
| 2381-2389 | −1.63 … −1.55 | calzada −2.053 … −1.977 |
| 2393 | −1.449 | −1.844 (muro eliminado) |
| 2413 | −1.284 | −1.820 |
| 2417 | −1.165 | −1.165 (orilla) |

Efecto medido (celdas del lecho con agua por encima, tras retirar la
tapa):

| Stage | Celdas mojadas |
| --- | --- |
| 1 | 6 992 / 32 333 |
| 2 | 2 222 / 7 188 |
| 3 | 1 233 / 7 166 |
| 5 | 1 550 / 3 297 |
| 6 | 3 545 / 6 840 |

La ruta sigue apoyada en la colisión en las cinco etapas (desnivel máximo
entre la ruta y el suelo: 14.5 cm en Kenia 5) y **no hay ningún punto de
ruta sin suelo**: el coche no cae al cauce.

### Barrido de fragmentos en las cinco etapas

Se comparó la colisión actual con la original en una rejilla de 3 m sobre
toda la lámina importada de cada cauce, contando picos locales (escalones
> 25 cm) y huecos:

| Stage | Picos actuales | Picos originales | Fragmentos en pie | Huecos actuales | Huecos originales |
| --- | --- | --- | --- | --- | --- |
| 1 | 532 | 532 | 0 | 6 | 6 |
| 2 | 4 393 | 4 393 | 0 | 34 | 34 |
| 3 | 106 | 106 | 0 | 6 | 6 |
| 5 | 1 261 | 1 261 | 0 | 11 | 11 |
| 6 | 2 028 | 2 028 | 0 | 23 | 23 |

Los picos son **exactamente los mismos** que en la colisión original (son
las paredes del valle, terreno natural) y los huecos también (vienen del
export). La retirada de la tapa no introduce ni un escalón ni un hueco
nuevo en ninguna de las cinco etapas.

Clearance de los puentes tras la retirada (el lecho ha bajado, así que el
agua queda más lejos del tablero):

| Puente | Tablero | Nivel del agua | Fondo del cauce | Holgura |
| --- | --- | --- | --- | --- |
| `kenya_stage5_bridge` | −3.933 | −4.530 | −5.780 | 1.25 m |
| `kenya_stage6_bridge_jungle` | −2.950 | −7.650 | −10.355 | 2.71 m |

Profundidad medida en el punto más bajo del cruce (calzada de colisión
frente al nivel del agua):

| Vado | Calzada | Nivel del agua | Profundidad |
| --- | --- | --- | --- |
| `kenya_ford_1` | −5.739 | −5.448 | 292 mm |
| `kenya_stage2_ford_b` | −2.016 | −1.595 | 421 mm |
| `kenya_stage3_ford_north` | −7.206 | −7.013 | 193 mm |
| `kenya_stage3_ford_south` | −11.380 | −11.179 | 201 mm |
| `kenya_stage6_ford_west` | −7.642 | −7.297 | 345 mm |

### Lectura del campo de lecho con la V invertida

`bed_tex` se hornea fila a fila (gz desde `min_z`), pero Godot lee las
texturas con la V invertida: el shader muestreaba el lecho **espejado en
Z**, así que el agua salía desplazada o se descartaba. Se corrige
muestreando `vec2(fuv.x, 1.0 - fuv.y)`.

### Modelo del agua en el vado: `max_rise_m` y topes del arrastre

`max_rise_m` se mantiene en **0.45 m** en los dieciséis canales (deben
compartirlo: si un tramo subiera más que sus vecinos, la superficie del
agua daría escalones).

Lo que puede **estancar** el coche en un vado no es la subida por lluvia,
sino dos topes del modelo de agua (`rally_puddles.gd`,
`PuddleModel.contact_response`), que se mantienen en sus valores
originales:

| Parámetro | Valor | Significado |
| --- | --- | --- |
| `WATER_GRIP_DEPTH_SATURATION_MM` | 12 mm | La pérdida de agarre (aquaplaning) satura a los 12 mm: a partir de ahí el agua se comporta igual sea charco o río. |
| `WATER_DRAG_MAX_LOAD_FRACTION` | 0.8125 | Tope del arrastre como fracción de la carga normal de la rueda (+25 % de fuerza de reacción). Con el `effective_friction` del grava (1.05) el agua consume el 77 % del presupuesto de rozamiento y al coche le queda el 23 % de tracción. |

Medición del vado de Kenia 1 (base 437 mm y crecida 887 mm; ancho de
rueda 0.2 m, carga normal 2 500 N, `drag_scale` 1.25, evacuación 16 m/s):

| v | Arrastre | Agarre lat. | Agarre long. | Tracción libre |
| --- | --- | --- | --- | --- |
| 11-32 km/h | 2 031 N (tope) | 1.000 | 1.000 | 23 % |
| 43 km/h | 2 031 N (tope) | 0.889 | 0.906 | 23 % |
| 58 km/h | 2 031 N (tope) | 0.430 | 0.515 | 23 % |
| 72 km/h | 2 031 N (tope) | 0.074 | 0.212 | 23 % |

El cruce lento sigue siendo controlable (agarre pleno hasta ~32 km/h) y
por encima el coche desliza: es el comportamiento buscado de un vado.

**Pendiente de decidir:** con estos topes, la base (437 mm) y la crecida
(887 mm) se comportan igual en agarre (ambas por encima de la
saturación) y el arrastre está en su tope en ambas. Si el vado resulta
demasiado exigente en juego, las palancas son:
- Bajar el tope del arrastre (más Ellison libre para conducir).
- Subir la saturación de agarre (penalización progresiva con la
  profundidad, en vez de aplanarse a los 12 mm) — afecta también a los
  charcos de los demás países.
- Bajar la profundidad base del vado: viene del activo (la calzada visual
  baja a −5.93); bajarla exigiría bajar el nivel del agua por debajo de la
  lámina importada (−5.42), que es opaca y taparía el agua.

### Recalibración de niveles

El nivel de cada cauce pasa a ser el de la **lámina importada** (antes
estaba 12-24 cm más bajo, lo que dejaba la capa dinámica enterrada bajo
la cinta opaca). La lámina de `river2_1` es prácticamente plana en todo
el cauce (mediana −5.434 por tramo), así que los nueve tramos comparten
nivel y no hay escalones entre ellos.

| Canal | Nivel antes | Nivel ahora | Inmersión de referencia |
| --- | --- | --- | --- |
| `kenya_ford_1` | −5.575 | −5.422 | 292 mm (calzada al fondo del cruce) |
| `kenya_stage1_river2_s1..s8` | — | −5.434 | sin vado |
| `kenya_stage2_ford_b` | −1.830 | −1.594 | 421 mm |
| `kenya_stage6_ford_west` | −7.414 | −7.297 | 345 mm |
| resto | sin cambio | sin cambio | sin cambio |

Tras retirar la tapa, el vado de Kenia 1 queda con la calzada de colisión
bajando hasta **−5.859** en el punto más bajo (el mismo punto donde la
calzada visual `kenya_river_road_2` baja a −5.93): con el agua a −5.422
son **437 mm** de agua en el centro del cruce y el coche baja al canal y
sube por la otra orilla.

### El cauce partido en nueve tramos (Kenia 1)

Con un solo cauce (el vado, 65 × 60 m) el agua dinámica solo existía en
ese parche: un **lago diminuto y desconectado**, con el resto del río
seco. `river2_1` son 1.120 m de cauce serpenteante, así que se divide en
ocho tramos más (`kenya_stage1_river2_s1..s8`) con huella solapada 20 m
para que las uniones no dejen huecos. Cada tramo tiene su referencia
climática (el punto de ruta más cercano) y su propia malla de cobertura.

Superficie mojada por tramo (celdas del lecho con agua por encima):

| Tramo | Celdas mojadas | Área |
| --- | --- | --- |
| `kenya_ford_1` | 1 037 | 1 037 m² |
| `s1` | 788 | 788 m² |
| `s2` | 847 | 847 m² |
| `s3` | 668 | 668 m² |
| `s4` | 484 | 484 m² |
| `s5` | 452 | 452 m² |
| `s6` | 687 | 687 m² |
| `s7` | 954 | 954 m² |
| `s8` | 1 005 | 1 005 m² |
| **total** | **6 922** | **6 922 m²** |

Cobertura sobre los 634 puntos del cauce: **609 con agua (96 %)**. Los 25
restantes no son huecos: el lecho sube por encima del nivel (−5.34 a
−5.38 frente a −5.434) → son **rápidos** donde el río aflora.

### Bloqueo pendiente para la cobertura completa

Dos canales de la misma etapa comparten **la misma superficie**:

| Stage | Canal A | Canal B | Superficie | Resultado |
| --- | --- | --- | --- | --- |
| 2 | `kenya_stage2_ford_b` | `kenya_stage2_reach_a` | `river2_1` | la capa se reparte por huella: cada cauce pinta su tramo |
| 3 | `kenya_stage3_ford_north` | `kenya_stage3_ford_south` | `river1_1` | ídem |

Con la malla de cobertura por cauce el conflicto desaparece: cada cauce
tiene su propia malla y su propio material, y la lámina importada ya no
se toca.

