# Plan Maestro de Migración e Integración de Mapas Restantes de Rally Trophy

Este documento define el plan técnico detallado, paso a paso y libre de ambigüedades para que un agente autónomo exporte, valide, importe e integre en **Godot 4.6 (`gl_compatibility` + Jolt Physics)** todos los mapas restantes de **Rally Trophy** ubicados en `D:\games\rally-throphy`, utilizando el pipeline de `stage_exporter` y las herramientas de `D:\rust-godot-vehicle-simulator`.

> **Restricción de alcance**: Los mapas de **Rusia** (`track1` -> `russia_stage1` a `russia_stage10`) **YA ESTÁN COMPLETOS** y **NO** deben re-exportarse ni sobrescribirse. Este plan aplica exclusivamente a los **4 países / 32 etapas restantes**: **Kenia (`kenya`), Finlandia (`finland`), Suecia (`sweden`) y Suiza (`switzerland`)**.

---

## 1. Inventario Exacto de Mapas Restantes (Fuente vs Destino)

En `D:\games\rally-throphy\Program Files\JoWooD\Rally Trophy\Data\Tracks`, cada carpeta `track2`..`track5` contiene exactamente **8 etapas jugables** (`stage1.bmf`..`stage8.bmf` en `models.bzf`, y `reset1.bin`..`reset8.bin` + `stagetimes1.ini`..`stagetimes8.ini` en `data.bzf`, con `NumberOfStages = 8` en `info.ini`).

> **Nota crítica sobre `track2` vs `track4` y etapas 9–10**:
> 1. El mapeo canónico real (confirmado por `export_stage.py` en `TRACK_TO_COUNTRY` y por las texturas `SKY_<country>_*.tga` dentro de `textures.bzf`) es:
>    - `track2` = **`kenya`** (`stage1`..`stage8`) — 145 texturas en `textures.bzf`
>    - `track3` = **`finland`** (`stage1`..`stage8`) — 230 texturas en `textures.bzf`
>    - `track4` = **`sweden`** (`stage1`..`stage8`) — 174 texturas en `textures.bzf`
>    - `track5` = **`switzerland`** (`stage1`..`stage8`) — 189 texturas en `textures.bzf`
> 2. Aunque existen archivos placeholder `track2_stage9.json`, `track2_stage10.json`, etc. en `game/data/competition/rally_trophy/`, en los archivos `.bzf` originales de Rally Trophy **solo existen `stage1` a `stage8`** para `track2..track5` (solo Rusia `track1` tiene 10 etapas). Por lo tanto, el catálogo por país para Kenia, Finlandia, Suecia y Suiza es de **8 etapas por país (32 etapas en total)**.

### Tabla de Resumen Diagnóstico de las 32 Etapas

| País (`country`) | Carpeta Fuente | Track IDs Destino | Longitudes (`resetN.bin`) | Superficie Principal | Particularidades Detectadas en Geometría / Materiales |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`kenya`** | `Data/Tracks/track2` | `kenya_stage1` .. `kenya_stage8` | `2365 m` – `7009 m` | Grava africana / tierra (`gravel_mud`) | `Collision_Terrain_Sand = 0`; taludes usan `kenya_erosio_1_1..3`; chozas con techos cutout (`kenya_bighut_roofalpha`, `kenya_roundhut_roofalpha`); árboles `plane_bush`, `plane2_wood`, `plane3_wood`; `split_01` en `stage5` tiene offset vertical de `24.02 m` vs `half_height = 18.19 m`. |
| **`finland`** | `Data/Tracks/track3` | `finland_stage1` .. `finland_stage8` | `2159 m` – `4933 m` | Grava rápida / hojas / tramos de asfalto (`gravel_mud`) | `Collision_Terrain_Grass = 0` (el terreno forestal usa `fin_forestground*` y `fin_sand*` clasificados en `Dirt` y `Sand`); marcadores usan prefijo `fin_` (`fin_checkpoint`, `fin_gate_finish`, `fin_sponsors`); cercas `fin_puuaita`, `fin_fence_*`. |
| **`sweden`** | `Data/Tracks/track4` | `sweden_stage1` .. `sweden_stage8` | `1576 m` – `4885 m` | Nieve / hielo (`gravel_mud` en perfiles 1974, física invernal) | `Collision_Terrain_Sand = 0`; taludes de nieve usan `erosion_snow_1_1..3`; carreteras usan `road_snow_*`, `bridge_snow_*`, `railroad_snow`; vegetación `forest_snow_*`, `sweden_tree_plane`; `split_09` en `stage8` tiene `lat_off = 32.97 m` vs `hw = 32.27 m`. |
| **`switzerland`** | `Data/Tracks/track5` | `switzerland_stage1` .. `switzerland_stage8` | `2393 m` – `4683 m` | Asfalto alpino / puentes / túneles (`asphalt`) | `Collision_Terrain_Dirt = 0` y `Collision_Terrain_Sand = 0` (todo el terreno es `Grass`); carreteras usan `road_tarmac_*`, `road_tunnel_*`, `bridgeroad*`, `bridgemetal1`; `stage7` tiene `1787` caras en `Collision_Barriers`; `split_00` en `stage6` tiene offset vertical de `26.47 m` vs `hh = 18.32 m`. |

---

## 2. Fase 1: Ajustes Previos Obligatorios en `D:\games\rally-throphy\stage_exporter`

Antes de ejecutar la exportación masiva, el agente **DEBE** corregir 5 problemas concretos en `D:\games\rally-throphy\stage_exporter\tools\` que fueron detectados al auditar los `.BMF` y `resetN.bin` de `track2..track5`. Sin estos ajustes, la exportación fallará en 2 etapas, la validación fallará en Suiza 7, algunas texturas cutout tendrán bordes negros/seam superior en etapas 2–8, y algunos portales de split no se activarán en Godot.

### 2.1. Corregir el caché de texturas por país en `tools/export_stage.py` y `tools/texture_processor.py`

**Problema**:
En `D:\games\rally-throphy\stage_exporter\tools\export_stage.py` (líneas 190–211), las texturas de `textures.bzf` se convierten a PNG durante la primera etapa exportada (`stage1`) y se guardan en `work_cache/<country>/textures_png/`. Sin embargo:
1. `is_cutout` se evalúa **únicamente** contra `stage_data.materials` de la etapa actual (`stage1`). Si una textura solo se usa con `shader_id == 5` en `stage2..stage8`, en `stage1` se procesa con `is_alpha_cutout=False` (sin sangrado RGB de 4px ni guarda transparente superior) y luego `stage2..stage8` reutilizan el PNG cacheado defectuoso.
2. `is_forest = "forest_mixed" in stem` solo detecta el nombre ruso `"forest_mixed"`, ignorando los equivalentes de otros países (`fin_forest_mixed1`, `fin_forest_ends`, `forest_snow_1`, `forest_snow_2`, `plane2_wood`, `plane3_wood`, `plane3_bush`).
3. En `D:\games\rally-throphy\stage_exporter\tools\texture_processor.py` (línea 110), `needs_top_transparent_guard` solo busca `("forest_mixed", "tree", "bush", "fence_1", "fence_2", "string")`, dejando fuera texturas con `clamp_v=True` y `shader_id=5` de los nuevos mapas que provocarían líneas oscuras flotando en el cielo (como `village_fence`, `fence_snow_1`, `fin_fence2`, `fin_forest_ends`, `kenya_bighut_roofalpha`, `kenya_roundhut_roofalpha`, `fin_field1_edge`, `fence_metal_tunnel_1`).

**Solución exacta a implementar**:
1. En `D:\games\rally-throphy\stage_exporter\tools\export_stage.py`:
   - Antes del bucle `for tex_name, tex_bytes in tex_entries.items():`, escanear **todos** los `stage*.bmf` dentro de `model_entries` (no solo el `stage_data` actual) para construir dos conjuntos a nivel de país:
     - `country_cutout_stems`: todos los `Path(m.get("tex0", "")).stem.lower()` donde `m["shader_id"] == 5` en cualquier `stage1..8.bmf` del país.
     - `country_clamp_v_cutout_stems`: todos los `Path(m.get("tex0", "")).stem.lower()` donde `m["shader_id"] == 5 and m.get("clamp_v", False)` en cualquier `stage1..8.bmf` del país.
   - Determinar `is_cutout = (stem in country_cutout_stems) or any(k in stem for k in ("tree", "bush", "forest", "fence", "audience", "wire", "string", "roofalpha"))`.
   - Determinar `is_forest = any(k in stem for k in ("forest_mixed", "forest_snow", "fin_forest", "forest_ends"))`.
2. En `D:\games\rally-throphy\stage_exporter\tools\texture_processor.py`:
   - Ampliar la firma de `process_tga_bytes(..., force_top_guard: bool = False)` o ampliar la tupla en `needs_top_transparent_guard` (línea 110) para incluir:
     ```python
     needs_top_transparent_guard = is_forest_card or force_top_guard or any(
         key in name_lower
         for key in (
             "forest_mixed", "forest_snow", "fin_forest", "forest_ends",
             "tree", "bush", "wood", "fence", "puuaita", "string",
             "roofalpha", "field1_edge",
         )
     )
     ```
   - Pasar `force_top_guard=(stem in country_clamp_v_cutout_stems)` desde `export_stage.py`.

### 2.2. Corregir intersección y dimensiones de portales en `tools/timing_gates.py`

**Problema Doble (Exportación + Runtime en Godot)**:
1. **En exportación (`timing_gates.py` línea 144)**:
   - En `kenya_stage5` (`split_01`), el cruce de la carretera ocurre en `lat_off = 5.09 m` (`half_width = 40.75 m`), pero `vert_off = 24.02 m` frente a `half_height = 18.19 m` (superando `half_height + 4.0 = 22.19 m`), lanzando `RuntimeError`.
   - En `switzerland_stage6` (`split_00`), el cruce ocurre en `lat_off = 9.00 m` (`half_width = 42.33 m`), pero `vert_off = 26.47 m` frente a `half_height = 18.32 m`, lanzando `RuntimeError`.
2. **En runtime de Godot (`game/scripts/rally/rally_stage_progress.gd` línea 174)**:
   - `RallyStageProgress.advance_timing_gates()` comprueba:
     ```gdscript
     if fraction < last_fraction or absf(crossing.dot(gate.right)) > float(gate.half_width_m) + 1.0 or absf(crossing.dot(gate.up)) > float(gate.half_height_m) + 1.0:
         break
     ```
   - En etapas como `kenya_stage5` (`split_01`, `split_04`, `split_05`, `split_06`), `sweden_stage8` (`split_03`, `split_09`) y `switzerland_stage6` (`split_00`, `split_02`), `lat_off` o `vert_off` sobre la poligonal superan `half_width_m + 1.0` o `half_height_m + 1.0` porque el centroide `origin` de la malla `split_XX` en el `.BMF` está desplazado vertical o lateralmente respecto a la calzada. Si no se ajustan `half_width_m` y `half_height_m` al exportar, **el auto nunca activará el split ni la meta en el juego**.

**Solución exacta a implementar en `D:\games\rally-throphy\stage_exporter\tools\timing_gates.py`**:
1. En `calculate_timing_gates` (líneas 135–155):
   - Ampliar la ventana de búsqueda del candidato sobre la poligonal a:
     ```python
     if lat_off <= half_width + 10.0 and vert_off <= half_height + 15.0:
         candidates.append((lat_off, vert_off, i, frac, hit))
     ```
   - Seleccionar el mejor candidato minimizando `lat_off`:
     ```python
     best_lat_off, best_vert_off, seg_i, seg_f, hit = min(candidates, key=lambda c: c[0])
     ```
   - Asegurar que `half_width` y `half_height` exportados cubran holgadamente el punto real de paso de la carretera (`hit`) para que `RallyStageProgress.advance_timing_gates()` en Godot siempre detecte el vehículo en toda la anchura/altura de la calzada:
     ```python
     half_width = float(max(half_width, best_lat_off + 8.0))
     half_height = float(max(half_height, best_vert_off + 6.0))
     ```
2. En `audit_visual_markers` (líneas 181–240 de `timing_gates.py`):
   - Actualmente solo busca subcadenas `("checkpoint", "sign_checkpoint", "gate_finish", "finish")` y clasifica `"finish"` solo si `"gate_finish"` está en `mat_name`. En Finlandia los materiales se llaman `fin_checkpoint` y `fin_gate_finish` (que contienen `"checkpoint"` y `"gate_finish"`, por lo que ya coinciden), pero conviene incluir también `"sponsors"` / `"fin_sponsors"` como referencia opcional si algún stage usa pancarta de patrocinador en salida/meta.
3. En `build_competition_document` (líneas 293–296 de `timing_gates.py`):
   - Verificar el campo `"surface"`: en `game/data/competition/historical_profiles_1974.json`, cada piloto tiene ratings para `"asphalt"` y `"gravel_mud"` (y en `rally_competition.gd` línea 293 se evalúa `ratings.get(stage.surface, ratings.gravel_mud)`).
   - Por lo tanto, en `build_competition_document`:
     ```python
     "surface": "asphalt" if country_name.lower() == "switzerland" else "gravel_mud",
     ```
     Esto hace que Suiza use automáticamente el rating `"asphalt"` de los pilotos históricos de 1974 (donde Sandro Munari y Lancia Stratos destacan en asfalto y montaña) y Kenia/Finlandia/Suecia usen `"gravel_mud"`.

### 2.3. Ajustar umbral de validación de barreras en `tools/validate_stage.py`

**Problema**:
En `D:\games\rally-throphy\stage_exporter\tools\validate_stage.py` (línea 113), existe la aserción fija:
```python
assert barrier_faces >= 2000, f"Collision_Barriers tiene muy pocas caras ({barrier_faces})"
```
En **`switzerland_stage7`**, la malla de barreras tiene exactamente **`1787` caras** (`Collision_Barriers = 1787`), lo cual es normal para esa etapa corta de `2736 m`. Además, en Finlandia `Collision_Terrain_Grass` es `0` (todo el terreno es `Dirt` + `Sand`), en Kenia/Suecia `Collision_Terrain_Sand` es `0`, y en Suiza `Dirt` y `Sand` son `0` (todo el terreno es `Grass`), lo cual ya es compatible con `assert terrain_faces > 5000` en `validate_stage.py` porque suma las 3 categorías de terreno.

**Solución exacta a implementar en `D:\games\rally-throphy\stage_exporter\tools\validate_stage.py`**:
- Cambiar la línea 113 de `assert barrier_faces >= 2000` a:
  ```python
  assert barrier_faces >= 1500, f"Collision_Barriers tiene muy pocas caras ({barrier_faces})"
  ```

### 2.4. Revisar clasificación de colisiones y UV guard-band en `tools/stage_builder.py`

En `D:\games\rally-throphy\stage_exporter\tools\stage_builder.py`:
1. **Clasificación de colisiones (`classify_collision_category`, líneas 60–115)**:
   - Las superficies de carretera de los 4 países (`jungle_road*`, `kenya_river_road*`, `kenya_road_*`, `fin_road_*`, `fin_bridge*`, `fin_path`, `fin_tarmac_cracks`, `fin_y_crossroad*`, `bridge_snow_*`, `railroad_snow`, `road_snow_*`, `bridgemetal1`, `bridgeroad*`, `metal-bridge-drivesurface-edge`, `road_crossroad`, `road_tarmac_*`, `road_tunnel_*`) ya caen correctamente en `Collision_Road`, **excepto** aquellas que no contienen `"road"`, `"bridge"`, `"crossroad"` ni `"SIDES"`:
     - Verificar que **`fin_path`**, **`fin_tarmac_cracks`** y **`railroad_snow`** se clasifiquen en **`Collision_Road`** (actualmente en `classify_collision_category`, `fin_path` cae en `Collision_Terrain_Dirt` porque contiene `"path"`, y `fin_tarmac_cracks` / `railroad_snow` contienen `"road"` o `"tarmac"` — atención: `"fin_tarmac_cracks"` NO contiene `"road"`, por lo que caería en `Collision_Terrain_Dirt` por el `return "Collision_Terrain_Dirt"` final si no se añade `"tarmac"` a la condición de `Collision_Road`!).
   - **Cambio obligatorio en `classify_collision_category` (`stage_builder.py` línea 96)**:
     Añadir `"tarmac"` y `"fin_path"` a la detección de carretera:
     ```python
     if "road" in m_low or "bridge" in m_low or "crossroad" in m_low or "tarmac" in m_low or m_low == "fin_path" or "SIDES" in m_name:
         return "Collision_Road"
     ```
2. **Exclusión de capas de blending/decals superpuestos (`classify_collision_category`, línea 81)**:
   - En Rusia se excluyeron `sand_erosion_*` y `Grass_edge*` del `.glb` de colisión estático para evitar Z-fighting / doble colisión con el terreno base, y luego `RallyTrackCollisionBuilder.build_erosion_bank_collision()` genera sus colisiones en runtime desde la malla visual.
   - En los nuevos mapas existen equivalentes de transición/borde:
     - Kenia: `kenya_erosio_1_1..3`, `kenya_rock_edge_2_1..2` (ya excluidos porque contienen `"erosio"` o `"edge"`).
     - Finlandia: `fin_field1_edge` (excluido por `"edge"`).
     - Suecia: `erosion_snow_1_1..3` (excluido por `"erosio"`).
     - Suiza: `sand_erosion_2_1..3`, `rock_edge_2_1..4` (excluidos por `"erosio"` y `"edge"`).
     - **Cuidado en Suiza**: El material `metal-bridge-drivesurface-edge` contiene `"bridge"` y `"edge"`. Como en `classify_collision_category` el `if any(k in m_low for k in ("erosio", "edge", ...)): return None` va **ANTES** del `if "road" in m_low or "bridge" in m_low:`, ¡`metal-bridge-drivesurface-edge` estaba siendo excluido (`return None`) en lugar de ir a `Collision_Road`!
   - **Cambio obligatorio en `classify_collision_category` (`stage_builder.py` líneas 80–98)**:
     Evaluar primero si `"bridge" in m_low or "road" in m_low` (o excluir `"drivesurface-edge"` del filtro `"edge"`) para que `metal-bridge-drivesurface-edge` en Suiza tenga colisión sólida en `Collision_Road`:
     ```python
     if "drivesurface" in m_low:
         return "Collision_Road"
     ```
     colocado justo antes del bloque `if any(k in m_low for k in ("tree_plane", ... "edge")): return None`.

---

## 3. Fase 2: Ejecución de Exportación y Validación en `stage_exporter`

Una vez aplicados los ajustes de la Fase 1 en `D:\games\rally-throphy\stage_exporter\tools\`:

### 3.1. Limpiar caché de texturas previo (si existiera para los nuevos países)
Para garantizar que los PNG de `kenya`, `finland`, `sweden` y `switzerland` se generen con el escaneo completo de `shader_id == 5` de las 8 etapas, usar `--force-textures` en la `stage1` de cada país (o borrar `D:\games\rally-throphy\stage_exporter\work_cache\<country>\textures_png`). **No tocar `work_cache\russia` ni `exports\russia_stage*`**.

### 3.2. Comandos de Exportación por País (32 etapas)
Ejecutar desde `D:\games\rally-throphy\stage_exporter`:

```powershell
# 1. Kenia (track2 -> kenya_stage1..8)
python tools/export_stage.py --country kenya --stage 1 --force-textures
python tools/export_stage.py --country kenya --all-stages

# 2. Finlandia (track3 -> finland_stage1..8)
python tools/export_stage.py --country finland --stage 1 --force-textures
python tools/export_stage.py --country finland --all-stages

# 3. Suecia (track4 -> sweden_stage1..8)
python tools/export_stage.py --country sweden --stage 1 --force-textures
python tools/export_stage.py --country sweden --all-stages

# 4. Suiza (track5 -> switzerland_stage1..8)
python tools/export_stage.py --country switzerland --stage 1 --force-textures
python tools/export_stage.py --country switzerland --all-stages
```

### 3.3. Comandos de Validación en `stage_exporter`
Validar cada país con `validate_stage.py` (que verifica existencia de los 9 artefactos por etapa, `mesh_compression == False`, `extras.surface_group`, normales unitarias, `ALPHA_CUTOUT_05`, ausencia de texturas `clamp_v` con píxeles opacos en `y=0`, 10 gates ordenados y pacenotes):

```powershell
python tools/validate_stage.py --country kenya --all
python tools/validate_stage.py --country finland --all
python tools/validate_stage.py --country sweden --all
python tools/validate_stage.py --country switzerland --all
```

Todas las 32 etapas deben imprimir `[OK] Validación exitosa para <country>_stage<N>!`.

---

## 4. Fase 3: Importación a Godot (`D:\rust-godot-vehicle-simulator`)

### 4.1. Ejecutar `tools/rally/import_stage_export.py` para los 4 países
El script [`import_stage_export.py`](file:///d:/rust-godot-vehicle-simulator/tools/rally/import_stage_export.py) ya soporta `--all-stages --country <country>` y realiza automáticamente:
1. Validación estricta del paquete exportado (GLBs, `manifest.json`, `route.json`, `gates.json`, `<track_id>.json`, `pacenotes.json`, `stage_report.md`).
2. Copia de `<track_id>_visual.glb`, `<track_id>_collision.glb` y `manifest.json` a `game/assets/rally/<track_id>/`.
3. Copia de las texturas PNG desde `work_cache/<country>/textures_png/<tex>.png` hacia `game/assets/rally/<track_id>/<track_id>_visual_<tex>.png` para que Godot las resuelva localmente sin perder referencias.
4. Escritura/actualización de `game/assets/rally/<track_id>/<track_id>_visual.glb.import` forzando `meshes/force_disable_compression=true` bajo `[params]`, **crítico para evitar grietas (seams) entre chunks adyacentes de terreno/carretera** por cuantización de vértices.
5. Copia de `route.json` (`game/data/rally/<track_id>_route.json`), `gates.json` (`game/data/rally/<track_id>_timing_gates.json`), `<track_id>.json` (`game/data/competition/stages/<track_id>.json`), `pacenotes.json` (`game/data/rally/pacenotes/<track_id>.json`) y `stage_report.md` (`game/docs/rally/<track_id>_stage_report.md`).

Ejecutar desde `D:\rust-godot-vehicle-simulator`:

```powershell
python tools/rally/import_stage_export.py --source-root "D:\games\rally-throphy\stage_exporter\exports" --country kenya --all-stages
python tools/rally/import_stage_export.py --source-root "D:\games\rally-throphy\stage_exporter\exports" --country finland --all-stages
python tools/rally/import_stage_export.py --source-root "D:\games\rally-throphy\stage_exporter\exports" --country sweden --all-stages
python tools/rally/import_stage_export.py --source-root "D:\games\rally-throphy\stage_exporter\exports" --country switzerland --all-stages
```

### 4.2. Ejecutar Importación Headless de Godot (`.godot/imported/`)
Una vez copiados los `.glb` y `.png` en `game/assets/rally/<track_id>/`, es **obligatorio** ejecutar el pase de importación de Godot en modo headless y single-threaded para que genere todos los recursos `.scn`, `.ctex` y complete los `.import` (sin esto, `ResourceLoader.exists()` o `load()` pueden fallar o causar glitches de texturas no importadas):

```powershell
& "C:\Program Files\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" --headless --single-threaded-scene --path "D:\rust-godot-vehicle-simulator\game" --import
```
*(Si el ejecutable de Godot está en una ruta distinta, resolverla con la misma lógica que [`scripts/run_rally.ps1`](file:///d:/rust-godot-vehicle-simulator/scripts/run_rally.ps1)).*

Verificar tras el `--import` que ningún archivo `game/assets/rally/<country>_stage*/<country>_stage*_visual.glb.import` haya perdido `meshes/force_disable_compression=true`. Si Godot reescribió el `.import` con `meshes/force_disable_compression=false`, volver a ejecutar `import_stage_export.py` para fijar `meshes/force_disable_compression=true` y correr `--import` una segunda vez para regenerar los `.scn` sin compresión de malla.

---

## 5. Fase 4: Adaptación del Runtime de Godot para Evitar Glitches Visuales y Físicos

Los scripts actuales de Godot fueron diseñados originalmente alrededor de `russia_stage1..10`. Para que `kenya`, `finland`, `sweden` y `switzerland` funcionen sin caídas a través del suelo, sin bordes negros en vegetación/vallas, y con físicas/eventos completos, el agente debe actualizar los siguientes archivos en `D:\rust-godot-vehicle-simulator\game\`:

### 5.1. [`game/scripts/rally/rally_track_collision_builder.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_track_collision_builder.gd) — Colisiones de Taludes (Erosion Banks) y Superficies

1. **Glitch crítico evitado — Caída a través de taludes laterales en Kenia, Finlandia, Suecia y Suiza (`build_erosion_bank_collision`)**:
   - Actualmente, `build_erosion_bank_collision()` (líneas 165–176) solo genera colisión desde la malla visual para materiales que empiezan por `"sand_erosion_"`:
     ```gdscript
     if material == null or not material.resource_name.to_lower().begins_with("sand_erosion_"):
         continue
     ```
   - Como `stage_builder.py` excluye del `.glb` de colisión todos los materiales con `"erosio"` y `"edge"`, en **Kenia** (`kenya_erosio_1_1..3`, `kenya_rock_edge_2_1..2`), **Suecia** (`erosion_snow_1_1..3`), **Finlandia** (`fin_field1_edge`) y **Suiza** (`rock_edge_2_1..4`), ¡esos taludes y bordes de roca junto a la carretera no tendrían colisión alguna y el coche atravesaría el suelo visual al salirse medio metro de la calzada!
   - **Cambio requerido en `build_erosion_bank_collision()`**:
     Crear un helper `_is_erosion_or_edge_bank_material(mat_name: String) -> bool` que devuelva `true` si `mat_name.to_lower()` empieza con o contiene:
     - `"sand_erosion_"` (`russia`, `switzerland`)
     - `"kenya_erosio_"` o `"kenya_rock_edge_"` (`kenya`)
     - `"erosion_snow_"` (`sweden`)
     - `"rock_edge_"` (`switzerland`)
     - `"fin_field1_edge"` (`finland`)
     Y asignar el grupo de superficie adecuado (p. ej. `"Sand"` para `sand_erosion_`, `"Dirt"` para `kenya_erosio_` / `fin_field1_edge`, `"Grass"` para `erosion_snow_`, `"Gravel"` para `rock_edge_`).

2. **Clasificación de grupos de superficie para físicas de neumáticos**:
   - Verificar cómo el vehículo lee los grupos `"Road"`, `"Gravel"`, `"Grass"`, `"Dirt"`, `"Sand"`. En `RallyTrackCollisionBuilder.surface_group_for_collider_name()`, `Collision_Road` mapea a `"Gravel"` (con tag secundario `"Road"` añadido en `create_static_body`). Esto mantiene compatibilidad total con `RallyTerrainWetness`, `RallyPuddles` y el modelo térmico/de agarre del vehículo.

### 5.2. [`game/scripts/rally/rally_stage_visual_material_adjuster.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_stage_visual_material_adjuster.gd) — Materiales Cutout, Culling y Clamping UV

1. **Ampliar `CUTOUT_MATERIAL_NAMES` (líneas 9–25)**:
   Actualmente solo contiene nombres de Rusia. Añadir todos los materiales `shader_id == 5` de los 4 nuevos países para que reciban `TRANSPARENCY_ALPHA_SCISSOR`, `alpha_scissor_threshold = 0.5`, `DEPTH_DRAW_ALWAYS`, `CULL_DISABLED` y textura con filtro `NEAREST`:
   - **Kenia**: `"kenya_audience"`, `"kenya_bighut_roofalpha"`, `"kenya_roundhut_pale"`, `"kenya_roundhut_roofalpha"`, `"plane2_bush"`, `"plane2_wood"`, `"plane3_bush"`, `"plane3_wood"`, `"plane_bush"`, `"plane_bush2"`, `"river1_1"`, `"river2_1"`, `"rope"`, `"village_fence"`
   - **Finlandia**: `"fin_fence_1_1"`, `"fin_fence_1_2"`, `"fin_fence_metal"`, `"fin_field1_edge"`, `"fin_forest_mixed1"`, `"fin_pole_wires"`, `"fin_powerline_insulation"`, `"fin_puuaita"`, `"fin_string_red"`, `"fin_trees_leaves"`, `"forest_ends"`, `"forest_ends2"`, `"water"`
   - **Suecia**: `"fence_snow_1"`, `"forest_snow_1"`, `"forest_snow_1_end"`, `"forest_snow_2"`, `"forest_snow_2_end"`, `"polyn_1_wire"`, `"sweden_tree_plane"`
   - **Suiza**: `"fence_metal_2"`, `"fence_metal_tunnel_1"`, `"mountain_tree_plane"`, `"waterfall_1"`, `"waterfall_2"`
   - **Comunes**: `"audience_4"`, `"fence_metal"`, `"string_red"` (ya presentes en Rusia o compartidos).

2. **Evitar repetir texturas que fueron exportadas con `CLAMP_TO_EDGE` (línea 85)**:
   - En [`rally_stage_visual_material_adjuster.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_stage_visual_material_adjuster.gd#L85):
     ```gdscript
     if is_cutout or not material_name.begins_with("sign_"):
         material.set_flag(BaseMaterial3D.FLAG_USE_TEXTURE_REPEAT, true)
     ```
   - `gltf_postprocessor.py` configura cuidadosamente en el `.glb` qué materiales usan `CLAMP_TO_EDGE` (`33071`, cuando `clamp_u and clamp_v`) y cuáles usan `REPEAT` (`10497`). Cuando Godot importa el `.glb`, ya asigna `FLAG_USE_TEXTURE_REPEAT = false` a los materiales con `CLAMP_TO_EDGE` (como `checkpoint`, `fin_checkpoint`, `gate_finish`, `fin_gate_finish`, `sponsors`, `fin_sponsors`, `sign_*`, `russian_tree_plane`, `sweden_tree_plane`, `mountain_tree_plane`, `audience_4`, `kenya_audience`).
   - Si `RallyStageVisualMaterialAdjuster` fuerza `FLAG_USE_TEXTURE_REPEAT = true` en `is_cutout` o en pancartas que no empiezan con `"sign_"` (`checkpoint`, `fin_checkpoint`, `gate_finish`, `sponsors`), puede causar wrapping en los bordes de árboles individuales, público o pancartas de meta.
   - **Cambio recomendado**: No sobrescribir `FLAG_USE_TEXTURE_REPEAT` a `true` si el material importado del `.glb` ya viene con `material.get_flag(BaseMaterial3D.FLAG_USE_TEXTURE_REPEAT) == false`, o excluir explícitamente pancartas/carteles (`"sign_"`, `"checkpoint"`, `"fin_checkpoint"`, `"gate_finish"`, `"fin_gate_finish"`, `"sponsors"`, `"fin_sponsors"`). Verify que el contrato [`game/tests/rally/stage_visual_settings_contract.gd`](file:///d:/rust-godot-vehicle-simulator/game/tests/rally/stage_visual_settings_contract.gd) siga pasando (ese contrato verifica que `"forest_mixed_1"` tenga `FLAG_USE_TEXTURE_REPEAT == true`, lo cual es cierto porque `forest_mixed_1` tiene `clamp_u=False, clamp_v=True`, por lo que `gltf_postprocessor.py` lo exporta con `REPEAT` y UV V clampeado a `[0.005, 0.995]`).

### 5.3. [`game/scripts/rally/rally_terrain_wetness.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_terrain_wetness.gd) y [`game/scripts/rally/rally_stage_grass.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_stage_grass.gd)

1. **`RallyTerrainWetness` (`_classify_surface`)**:
   - Actualmente clasifica materiales por palabras clave (`"road"`, `"asphalt"`, `"bridge"`, `"sand"`, `"grass"`, `"field"`, `"forest"`, `"dirt"`, `"mud"`, `"gravel"`, `"rock"`, `"cliff"`, `"stone"`).
   - Añadir palabras clave de los nuevos países en `_classify_surface`:
     - En `"road"`: añadir `"tarmac"`, `"tunnel"`, `"crossroad"`, `"fin_path"`, `"railroad"`.
     - En `"grass"`: añadir `"savanna"`, `"snow"` (para que en Suecia la nieve no se oscurezca como barro húmedo; o dar a `"snow"` un oscurecimiento mínimo por humedad).
     - En `"dirt"`: añadir `"jungle"`, `"erosio"`, `"forestground"`.
2. **`RallyStageGrass`**:
   - `RallyStageGrass.build()` lanza rayos contra colisionadores en el grupo `"Grass"`.
   - En **Finlandia**, `Collision_Terrain_Grass` tiene `0` caras (el suelo forestal es `Dirt` y `Sand`), por lo que `RallyStageGrass` colocará `0` matas (`placed == 0`) y retornará limpiamente sin error.
   - En **Suecia**, el terreno nevado está en `Collision_Terrain_Grass` (`snow_1`, `snow_2`, `forest_snow_*`). Para evitar que aparezcan matas de hierba verde/seca de verano sobre la nieve de Suecia, en [`rally_russia_stage_session.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_russia_stage_session.gd#L275) (`_build_stage_grass()`), omitir la generación de `StageGrass` cuando `session_track_id.begins_with("sweden_")` (y opcionalmente en Finlandia donde `grass=0`).

### 5.4. [`game/scripts/rally/rally_stage_loader.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_stage_loader.gd) — Soporte Multi-País en el Catálogo

1. En [`rally_stage_loader.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_stage_loader.gd):
   - Añadir constantes de catálogo por país:
     ```gdscript
     const COUNTRY_STAGE_COUNTS := {
         "russia": 10,
         "kenya": 8,
         "finland": 8,
         "sweden": 8,
         "switzerland": 8,
     }
     ```
   - Añadir helper `track_id_for_country_index(country: String, stage_index_1_based: int) -> String` que valide el rango `1..COUNTRY_STAGE_COUNTS[country]` y devuelva `"%s_stage%d" % [country, stage_index_1_based]`. Mantener `track_id_for_index(stage_index_1_based)` intacto para compatibilidad con los contratos de Rusia.
   - Añadir helper `catalog_for_country(country: String) -> Array[String]` y `all_countries_catalog() -> Array[String]`.
   - En `validate_catalog(track_ids: Array)`:
     Actualmente (líneas 104–113) exige que `track_ids` tenga exactamente 10 elementos y que sean `russia_stage1..10`. Actualizar `validate_catalog` (o añadir `validate_country_catalog(country: String, track_ids: Array = []) -> bool`) para que:
     - Si `track_ids` es vacío, valide por defecto `russia_stage1..10` (preservando retrocompatibilidad con `russia_event_contract.gd`).
     - Si se le pasa un array de `track_ids` de un país (p. ej. `kenya_stage1..8`) o los 42 tracks del juego (`10 + 8*4 = 42`), valide que cada `track_id` tenga el formato `<country>_stage<N>`, no haya duplicados, y que `resolve(id)` sea exitoso para todos.

### 5.5. Eventos de Competición, Clima Regional y Menú Principal

1. **Crear los 4 archivos de evento en `game/data/competition/events/`**:
   Siguiendo exactamente la estructura de [`game/data/competition/events/russia_rally.json`](file:///d:/rust-godot-vehicle-simulator/game/data/competition/events/russia_rally.json), crear:
   - `game/data/competition/events/kenya_rally.json` (`event_id: "kenya_rally"`, 8 etapas `kenya_stage1..8`, `regional_profile_id: "kenya_safari"`, parques de servicio cada 2–3 etapas).
   - `game/data/competition/events/finland_rally.json` (`event_id: "finland_rally"`, 8 etapas `finland_stage1..8`, `regional_profile_id: "finland_autumn"`).
   - `game/data/competition/events/sweden_rally.json` (`event_id: "sweden_rally"`, 8 etapas `sweden_stage1..8`, `regional_profile_id: "sweden_winter"`).
   - `game/data/competition/events/switzerland_rally.json` (`event_id: "switzerland_rally"`, 8 etapas `switzerland_stage1..8`, `regional_profile_id: "switzerland_alpine"`).

2. **Añadir perfiles climáticos regionales en [`game/data/weather/rally_weather_presets.json`](file:///d:/rust-godot-vehicle-simulator/game/data/weather/rally_weather_presets.json)**:
   Bajo `"regional_profiles"` (donde hoy existe `"russia_summer"`), añadir `"kenya_safari"`, `"finland_autumn"`, `"sweden_winter"` (con `favors: "snow"` y temperaturas bajo cero o cercanas a 0 °C) y `"switzerland_alpine"` (o mapear a `"russia_summer"` como fallback seguro si no se desea alterar la física invernal), manteniendo la misma estructura de `surface_profiles` (`Gravel`, `Dirt`, `Road`, `Grass`, `Sand`) y `antecedent_policy`.

3. **Actualizar [`game/scripts/rally/rally_event_manager.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_event_manager.gd) y [`game/scripts/rally/rally_maniac_menu.gd`](file:///d:/rust-godot-vehicle-simulator/game/scripts/rally/rally_maniac_menu.gd)**:
   - En `RallyEventManager`: permitir que `load_event(path)` funcione con eventos de 8 etapas (`kenya_rally.json`, `finland_rally.json`, `sweden_rally.json`, `switzerland_rally.json`) además del de 10 etapas (`russia_rally.json`), usando `validate_country_catalog` en lugar de asumir siempre 10 etapas de Rusia.
   - En `RallyManiacMenu`: habilitar la selección de país/evento (`Russia`, `Kenya`, `Finland`, `Sweden`, `Switzerland`) y actualizar la lista de etapas en Single Stage / Practice / Rally según el país seleccionado (`stage1..10` para Rusia, `stage1..8` para los otros 4 países).

---

## 6. Fase 5: Pruebas de Aceptación y Contratos de Verificación

El agente **NO** debe dar la tarea por terminada hasta que pasen todas las verificaciones siguientes:

### 6.1. Verificación de Integridad de Archivos Importados (32 etapas nuevas + 10 de Rusia intactas)
Para cada `<country>` en `("kenya", "finland", "sweden", "switzerland")` y `<N>` en `1..8` (`<track_id> = <country>_stage<N>`):
- [ ] Existe `game/assets/rally/<track_id>/<track_id>_visual.glb` y su `.import` contiene `meshes/force_disable_compression=true`.
- [ ] Existe `game/assets/rally/<track_id>/<track_id>_collision.glb` y su `.import`.
- [ ] Existe `game/assets/rally/<track_id>/manifest.json` con `schema_version == 1`, `start_pose.ground_godot` y `counts.timing_gates == 10`.
- [ ] Existen todas las texturas locales `game/assets/rally/<track_id>/<track_id>_visual_<tex>.png` y sus `.import`.
- [ ] Existe `game/data/rally/<track_id>_route.json` (`points >= 50`).
- [ ] Existe `game/data/rally/<track_id>_timing_gates.json` (`10` gates: `split_00..split_08` + `split_09` finish).
- [ ] Existe `game/data/competition/stages/<track_id>.json` (`timing_gates` no vacío, `ai_reference.target_ms` con 10 splits crecientes).
- [ ] Existe `game/data/rally/pacenotes/<track_id>.json`.
- [ ] Existe `game/docs/rally/<track_id>_stage_report.md`.

### 6.2. Contrato Headless de Carga, Colisión y Spawn para las 32 Etapas
Actualizar o crear un test de contrato en `game/tests/rally/all_countries_stage_import_contract.gd` (basado en [`game/tests/rally/stage_export_import_test.gd`](file:///d:/rust-godot-vehicle-simulator/game/tests/rally/stage_export_import_test.gd) y [`game/tests/rally/stage_vehicle_start_contract.gd`](file:///d:/rust-godot-vehicle-simulator/game/tests/rally/stage_vehicle_start_contract.gd)) que recorra las 32 etapas (`kenya_stage1..8`, `finland_stage1..8`, `sweden_stage1..8`, `switzerland_stage1..8`) y verifique en Godot headless:
1. `stage_loader.resolve(track_id)` devuelve `ok == true` y todos los recursos existen en `ResourceLoader`.
2. `RallyTrackCollisionBuilder` construye los `StaticBody3D` desde `<track_id>_collision.glb` + taludes de erosión (`build_erosion_bank_collision`) con `get_child_count() >= 3`.
3. `RallyStageProgress.configure(route)` y `configure_timing_gates(stage.timing_gates)` devuelven `true`, y al simular el paso por el `route_position` de los 10 `timing_gates`, **los 10 portales se disparan en orden hasta `finished == true`**.
4. Un raycast vertical desde `start_pose.ground_godot + Vector3(0, 3.0, 0)` hacia abajo impacta contra la colisión de `Collision_Road` a menos de `0.6 m` de la altura esperada, garantizando que el vehículo no spawnea en el vacío ni enterrado en ninguna de las 32 etapas.

Ejecutar el contrato con:
```powershell
& "C:\Program Files\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" --headless --single-threaded-scene --path "D:\rust-godot-vehicle-simulator\game" --script "res://tests/rally/all_countries_stage_import_contract.gd"
```

### 6.3. Ejecución de la Suite de Contratos Existente (No Regresión en Rusia)
Ejecutar la suite de contratos del repositorio para confirmar que Rusia y los sistemas base siguen en verde:
```powershell
python tools/run_all_runtime_contracts.py
```
