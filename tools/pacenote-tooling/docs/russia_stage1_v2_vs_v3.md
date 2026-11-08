# Comparativa pacenotes russia_stage1: v2 vs v3 (con pases v3.1 de densidad y voz + consolidación)

Fecha: 2026-11-08. Generado contra `stage1.BMF` + `russia_stage1_route.json`.

| Métrica | v2 (`pacenote_analyzer_v2.py`) | v3 (`rally_road_reconstruction_v2/…`) |
|---|---|---|
| Llamadas runtime | 22 (18 curvas + 4 peligros) | **51** (44 curvas + peligros/crestas/jumps; palabra única por evento) |
| Descartadas | 14 | 0 (todo auditado: absorbidas, agrupadas o de baja prioridad) |
| Detección | Auto + tabla calibrada RU1 | 100% geométrica (sin tablas) |
| Giro 131–136 | Tabla: `right` R22 88.5° (invertido) | Detectado `left` 96.5° `openhairpin` |
| Recta 2020–2110 | Sin horquillas | Sin horquillas (verificado) |
| Rocas s≈4309 | — | `HAZ` d_edge 0.12 m → `hazard=4` (+`no_cut` si <1.2 m) |
| Distancias | `next`/`prev` entre curvas | `to_current`; `into` solo <22 m entre curvas, si no 0 (el gate ya posiciona) |
| Densidad | ~1/230 m | ~1/98 m (original CMR2: ~1/95 m de media) |
| Voz compuesta | — | Caution hoisting + cooldown 85 m/4.5 s + dedup de hazards (≤65 m), sin multi-palabra |
| Test suite | — | `game/tests/rally-v2/test_russia_stage1_v3.py` **PASS 6/6** |

Notas:
- v3 usa `hazard=4` (slot 35 = `rocks.wav`) para rocas, no `hazard=12` (slot 42 =
  `rough.wav`): el §4.2/E del spec arrastra un error; v2, el codec del juego y el
  banco de voces coinciden en 4 = rocks.
- `into`/`and` siguen los buckets v2 del entero de 32 bits (clase 2 = into si
  10 ≤ gap < 22, clase 1 = and si gap < 10): la palabra no tiene bit de link.
- La densidad (51 vs 22) combina detección sensible del spec con palancas de
  emisión: agrupado de curvas del mismo sentido (<55 m), peligros sueltos de
  roca/poste/zanja solo si rozan (<1.2 m) o son gate/junction, crestas con NMS
  + cambio real de pendiente (las sueltas no se cantan), `dont_cut` < 1.2 m,
  junctions solo si la curva gira >= 55°, y distancias numéricas solo < 40 m
  (con repeat ≥ 22 m). validate_stage: `[ALL CHECKS PASSED]`.
