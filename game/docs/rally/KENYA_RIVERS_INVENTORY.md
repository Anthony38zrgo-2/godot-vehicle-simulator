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
  −5.422 + 0.45 = **−4.972**, contenida con **~0.5 m de margen**.
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
- Regresión existente: `puddles_contract` **PASS**,
  `dynamic_weather_tires_contract` **PASS**, `puddles_stage_probe` **PASS**,
  `weather_runtime_regression` **falla por flujo de garaje preexistente**
  (idéntico fallo con los cambios apartados; otro trabajo en curso en el
  árbol, no causado por esta entrega).
