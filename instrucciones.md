# Handoff Técnico: Exportación Masiva de Etapas de Rally Trophy a Godot 4

Este documento describe de manera exhaustiva el procedimiento paso a paso para exportar **las 42 etapas de los 5 rallies** de *Rally Trophy (2001)* desde sus archivos originales (`.bzf`, `.bmf`, `.bin`, `.txt`), procesarlas a formatos modernos (`.glb`, `.blend`, `.json`) e importarlas de forma estructurada y validada en este simulador (`d:\rust-godot-vehicle-simulator`).

---

## 1. Inventario y Mapeo de Pistas del Juego

En la instalación de *Rally Trophy* (`D:\games\rally-throphy\Program Files\JoWooD\Rally Trophy\Data\Tracks`), los rallies están organizados en carpetas `track1` a `track5`. El mapeo real de países y su conteo de etapas es:

| Pista | País | Identificador | Etapas | Tipo de Superficie Dominante |
| :--- | :--- | :--- | :---: | :--- |
| **track1** | **Rusia** | `russia` | 10 (`stage1` .. `stage10`) | Grava rápida, tierra batida, zanjas profundas, bosque boreal denso. |
| **track2** | **Kenia** | `kenya` | 8 (`stage1` .. `stage8`) | Pistas de sabana polvorienta, selva, barro espeso y pasos de ríos. |
| **track3** | **Finlandia** | `finland` | 8 (`stage1` .. `stage8`) | Pistas forestales muy rápidas, rasantes continuos con saltos y lagos. |
| **track4** | **Suecia** | `sweden` | 8 (`stage1` .. `stage8`) | Carreteras estrechas cubiertas de nieve compacta y placas de hielo. |
| **track5** | **Suiza** | `switzerland` | 8 (`stage1` .. `stage8`) | Carreteras de montaña de asfalto estrecho, horquillas y muros de roca. |
| **TOTAL** | **5 países** | — | **42 etapas** | — |

---

## 2. Arquitectura de las Herramientas

La suite de exportación e importación se compone de dos subsistemas sincronizados:

### A. Pipeline de Exportación (`D:\games\rally-throphy\stage_exporter\tools\`)
- **[bzf.py](file:///D:/games/rally-throphy/stage_exporter/tools/bzf.py)**: Extractor BZF de alto rendimiento con descompresión zlib en memoria (lee `data.bzf`, `models.bzf`, `textures.bzf` sin escribir archivos temporales).
- **[bmf_parser.py](file:///D:/games/rally-throphy/stage_exporter/tools/bmf_parser.py)**: Parser binario DirectX 8 para la geometría del tramo (`StageN.bmf`), desglosando vértices, normales, colores por vértice, UVs, flags de clamping, chunks de terreno y jerarquías de mallas.
- **[texture_processor.py](file:///D:/games/rally-throphy/stage_exporter/tools/texture_processor.py)**: Conversor de texturas TGA a PNG optimizado. Aplica dilatación de color RGB (*Alpha Bleeding*) hacia zonas transparentes para evitar halos en mipmaps y añade un *guard-band* transparente (`alpha = 0`) en las 3 filas superiores de texturas de vegetación/bosque.
- **[stage_builder.py](file:///D:/games/rally-throphy/stage_exporter/tools/stage_builder.py)**: Script ejecutado en modo headless dentro de **Blender 5.2 LTS**:
  - Aplica soldado de normales en costuras entre chunks contiguos.
  - Clampea geométricamente las UVs en el eje no repetitivo (`V` o `U` a `[0.005, 0.995]`) para compensar que Godot 4 no soporta modos de wrap independientes por eje en `StandardMaterial3D`.
  - Construye 5 categorías visuales (`Track_Road_And_Terrain`, `Foliage_And_Vegetation`, `Buildings_And_Structures`, `Fences_And_Barriers`, `Props_And_Markers`).
  - Construye 8 categorías físicas de colisión (`Collision_Road`, `Collision_Terrain_Grass`, `Collision_Terrain_Dirt`, `Collision_Terrain_Sand`, `Collision_Barriers`, `Collision_Buildings`, `Collision_Props`, `Collision_Tree_trunks`).
  - Genera mallas de **doble cara** (ambos sentidos de giro de caras) en `Collision_Barriers` para que los cards de bosque y vallas nunca sean atravesados por culling físico.
  - Realiza raycast tridimensional hacia la carretera para determinar el `start_pose` exacto de spawn con cálculo de orientación, pitch y roll.
- **[gltf_postprocessor.py](file:///D:/games/rally-throphy/stage_exporter/tools/gltf_postprocessor.py)**: Parcheador binario del glTF/GLB visual. Configura samplers glTF uniformes (`REPEAT/REPEAT` para texturas que se repiten; `CLAMP/CLAMP` únicamente para props aislados), activa `doubleSided` en vegetación y fija `alphaMode = "MASK"` con threshold `0.38`.
- **[timing_gates.py](file:///D:/games/rally-throphy/stage_exporter/tools/timing_gates.py)**: Extrae los 493+ puntos de trayectoria de `resetN.bin`, proyecta y calcula los 10 gates parciales (`split_00..09`), audita su gap métrico contra los carteles 3D visuales y genera el documento de competición con tiempos de referencia CPU de `stagetimesN.ini`.
- **[pacenote_analyzer.py](file:///D:/games/rally-throphy/stage_exporter/tools/pacenote_analyzer.py)**: Analizador cinemático 3D de ruta. Clasifica curvaturas, pendientes verticales (rasantes), cruces, obstáculos próximos y codifica las llamadas en palabras binarias de 32 bits compatibles con el códec de audio de *Colin McRae Rally 2.0 (CMR2)*.
- **[export_stage.py](file:///D:/games/rally-throphy/stage_exporter/tools/export_stage.py)**: Orquestador maestro por línea de comandos que ejecuta secuencialmente los pasos 1 al 8.
- **[validate_stage.py](file:///D:/games/rally-throphy/stage_exporter/tools/validate_stage.py)**: Suite de validación con 7 pruebas que aseguran el cumplimiento estricto del contrato antes de entregar cualquier etapa.

### B. Pipeline de Importación (`D:\rust-godot-vehicle-simulator\tools\rally\`)
- **[import_stage_export.py](file:///D:/rust-godot-vehicle-simulator/tools/rally/import_stage_export.py)**: Importador universal para este proyecto Godot. Valida los hashes SHA256 contra el manifiesto, crea respaldos automáticos en `AppData/Local/Temp/`, distribuye ordenadamente los archivos en `game/assets/`, `game/data/` y `game/docs/`, y copia las texturas PNG procesadas para acelerar la importación en Godot.

---

## 3. Estructura de Destino en el Simulador

Cada etapa importada se ubica de forma consistente en la arquitectura del proyecto:

```
D:\rust-godot-vehicle-simulator\
├── game\
│   ├── assets\rally\<track_id>\                 # Recursos 3D y manifiesto de runtime
│   │   ├── <track_id>_visual.glb                # Malla visual optimizada y parcheada
│   │   ├── <track_id>_collision.glb             # Malla de colisión dividida por superficie
│   │   ├── <track_id>_visual_<textura>.png      # Texturas PNG preprocesadas (alpha bleeding)
│   │   └── manifest.json                        # Contrato v1 (start_pose, hashes, roles)
│   │
│   ├── data\
│   │   ├── rally\
│   │   │   ├── <track_id>_route.json            # Puntos 3D de trayectoria y distancia acumulada
│   │   │   └── pacenotes\
│   │   │       └── <track_id>.json              # Pacenotes CMR2 de runtime (palabras hex 32-bit)
│   │   │
│   │   └── competition\stages\
│   │       ├── <track_id>.json                  # Configuración de competición y tiempos CPU
│   │       └── <track_id>_timing_gates.json     # 10 gates parciales auditados métricamente
│   │
│   └── docs\rally\
│       ├── metadata\
│       │   └── <track_id>_original_metadata.json# Metadatos originales de Rally Trophy (clima, niebla)
│       └── pacenotes\
│           ├── <track_id>_authoring.json        # Registro de evidencia de pacenotes (ángulos, radios)
│           └── <track_id>_candidates.json       # Candidatos brutos de rasantes y obstáculos
```

*Donde `<track_id>` sigue el formato estándar: `<pais>_<etapa>`, por ejemplo: `russia_stage1`, `kenya_stage3`, `sweden_stage2`.*

---

## 4. Guía de Ejecución Paso a Paso

### Paso 1: Preparación del Entorno
Asegurarse de contar con las herramientas requeridas:
1. **Python 3.10+**: con `Pillow` y `numpy` instalados:
   ```powershell
   pip install pillow numpy
   ```
2. **Blender 5.2 LTS** (o 4.3): Disponible en `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` o registrado en la variable de entorno `PATH`.
3. **Godot Engine 4.7.x**: Disponible como `godot` o `godot.cmd`.

---

### Paso 2: Exportación de Etapas

#### Opción A: Exportar una etapa individual para pruebas
Para exportar una etapa específica (por ejemplo, Kenia Stage 1 o Suecia Stage 2):
```powershell
cd D:\games\rally-throphy\stage_exporter\tools
python export_stage.py --country kenya --stage stage1
python export_stage.py --country sweden --stage stage2
```
*Si se modifican las rutinas de textura y se desea forzar la regeneración de los PNGs en caché, agregar `--force-textures`.*

#### Opción B: Exportar un país completo (Recomendado para control por bloques)
Para exportar país por país y verificar su progreso:
```powershell
cd D:\games\rally-throphy\stage_exporter\tools

# 1. Rusia (10 etapas)
1..10 | ForEach-Object { python export_stage.py --country russia --stage "stage$_" }

# 2. Kenia (8 etapas)
1..8  | ForEach-Object { python export_stage.py --country kenya --stage "stage$_" }

# 3. Finlandia (8 etapas)
1..8  | ForEach-Object { python export_stage.py --country finland --stage "stage$_" }

# 4. Suecia (8 etapas)
1..8  | ForEach-Object { python export_stage.py --country sweden --stage "stage$_" }

# 5. Suiza (8 etapas)
1..8  | ForEach-Object { python export_stage.py --country switzerland --stage "stage$_" }
```

#### Opción C: Exportar las 42 etapas en un solo comando
```powershell
cd D:\games\rally-throphy\stage_exporter\tools
python export_stage.py --all
```
*Tiempo estimado: ~15 a 18 minutos para las 42 etapas (aprox. 22-25 segundos por etapa).*

---

### Paso 3: Validación Automática de la Exportación

Antes de importar, es obligatorio verificar que los paquetes exportados cumplan el 100% de los contratos de runtime (integridad de hash SHA256, samplers glTF uniformes, mallas de colisión cerradas y monotonía de timing gates):

#### Validar una etapa individual:
```powershell
cd D:\games\rally-throphy\stage_exporter\tools
python validate_stage.py --stage-dir "D:\games\rally-throphy\stage_exporter\stages\kenya\stage1"
```

#### Validar masivamente todas las etapas exportadas:
```powershell
cd D:\games\rally-throphy\stage_exporter\tools
Get-ChildItem -Path "D:\games\rally-throphy\stage_exporter\stages" -Recurse -Filter "manifest.json" | ForEach-Object {
    python validate_stage.py --stage-dir $_.DirectoryName
}
```

---

### Paso 4: Importación al Proyecto Godot

Utilizar el script universal [import_stage_export.py](file:///D:/rust-godot-vehicle-simulator/tools/rally/import_stage_export.py), el cual valida hashes, genera un respaldo temporal automático en `%TEMP%` y distribuye cada recurso en su carpeta correspondiente.

#### Opción A: Importar una etapa individual
```powershell
cd D:\rust-godot-vehicle-simulator
python tools/rally/import_stage_export.py --source "D:\games\rally-throphy\stage_exporter\stages\kenya\stage1"
```

#### Opción B: Importar masivamente todas las etapas
```powershell
cd D:\rust-godot-vehicle-simulator
python tools/rally/import_stage_export.py --all --source "D:\games\rally-throphy\stage_exporter\stages"
```

---

### Paso 5: Reimportación Headless en Godot 4

Una vez copiados los archivos al proyecto, ejecutar Godot en modo headless para que compile los recursos `.glb`, genere los `.scn` cacheados en `.godot/imported/` y registre los nuevos archivos `.import`:

```powershell
cd D:\rust-godot-vehicle-simulator
godot --headless --path game --editor --quit
```

---

## 5. Integración en el Runtime del Juego

Para cargar y conducir cualquiera de las etapas importadas en el simulador:

1. **Configuración de Sesión ([rally_russia_stage_session.gd](file:///D:/rust-godot-vehicle-simulator/game/scripts/rally/rally_russia_stage_session.gd))**:
   El runtime utiliza tres rutas fundamentales definidas a partir del `track_id`:
   ```gdscript
   var track_id := "kenya_stage1" # O cualquier etapa exportada

   # 1. Manifiesto visual y de colisión:
   var manifest_path := "res://assets/rally/%s/manifest.json" % track_id

   # 2. Trayectoria para cálculo de progreso:
   course.configure("res://data/rally/%s_route.json" % track_id)

   # 3. Pacenotes CMR2 y audio del copiloto:
   pacenotes.configure("res://data/rally/pacenotes/%s.json" % track_id)

   # 4. Competición y parciales:
   competition.configure("res://data/competition/stages/%s.json" % track_id)
   ```

2. **Construcción Física ([rally_track_collision_builder.gd](file:///D:/rust-godot-vehicle-simulator/game/scripts/rally/rally_track_collision_builder.gd))**:
   - `RallyTrackCollisionBuilder` lee `manifest.json` e instancia `russia_stage1_collision.glb` (o el del stage activo).
   - Asigna automáticamente los roles de superficie (`terrain`, `barrier`, `obstacle`) y configura `backface_collision = true` en `ConcavePolygonShape3D` para las barreras perimetrales.

3. **Ajuste de Shaders y Materiales ([rally_stage_visual_material_adjuster.gd](file:///D:/rust-godot-vehicle-simulator/game/scripts/rally/rally_stage_visual_material_adjuster.gd))**:
   - Aplica shading tipo Dreamcast/Gouraud (`SHADING_MODE_PER_VERTEX`).
   - Activa `FLAG_USE_TEXTURE_REPEAT = true` para evitar que las mallas de bosque o carreteras se estiren.
   - Aplica `TRANSPARENCY_ALPHA_SCISSOR` con backlight suave en vegetación para emular la mezcla de corte original de PowerVR2.

---

## 6. Solución de Problemas y Puntos Críticos

| Problema Potencial | Causa Raíz | Solución Aplicada en el Pipeline |
| :--- | :--- | :--- |
| **Franjas horizontales en cards de bosque o carreteras** | Godot 4 no admite `wrapS` y `wrapT` independientes; si uno es `CLAMP_TO_EDGE`, desactiva la repetición en ambos ejes. | `gltf_postprocessor.py` fuerza `REPEAT/REPEAT` si al menos un eje se repite, mientras que `stage_builder.py` clampea la coordenada geométrica `V` a `[0.005, 0.995]`. |
| **Coche atraviesa los cards de bosque al salir de pista** | `forest_mixed` estaba excluido de la colisión y los planos verticales sufrían de backface culling físico. | `stage_builder.py` enruta todos los muros de bosque/selva (`forest_mixed*`, `fin_forest_mixed*`, `forest_snow*`, `forest_ends*`, `plane2_wood`, `plane3_wood`, `fin_puuaita`) a `Collision_Barriers`, duplica los triángulos con ambos windings y activa `backface_collision = true` en Godot. |
| **Puentes, cruces, pasos a nivel y vados de ríos en otros países** | Materiales específicos de país (`fin_bridge1`, `bridge_snow_2`, `bridgemetal1`, `kenya_river_*`, `railway_*`, `crossroad`) podían quedar sin colisión. | Auditados los 42 `.BMF`: puentes, túneles, cruces y vías van a `Collision_Road`; lechos de ríos de Kenia y laderas van a `Collision_Terrain_Dirt`/`Grass`; cabañas, castillos, pilas de troncos y vehículos aparcados van a `Collision_Buildings`/`Props`. |
| **Etapas sin las 8 categorías simultáneas (ej. sin arena o sin edificios)** | 39 de las 42 etapas no contienen las 8 superficies a la vez (ej. etapas sin `Collision_Terrain_Sand` o `Collision_Buildings`). | `export_stage.py` registra dinámicamente en `manifest.collision.exported_nodes` solo los nodos con geometría activa (`> 0` caras) y `validate_stage.py` valida contra dicha lista exigiendo siempre `Collision_Road` (`>= 11.516` caras) y `Collision_Barriers` (`>= 2.000` caras). |
| **Detección de materiales cutout en los 5 países** | `RallyStageVisualMaterialAdjuster` tenía una lista fija de nombres de Rusia. | Ahora detecta automáticamente cualquier material importado con `TRANSPARENCY_ALPHA_SCISSOR` desde el GLB (`shader_id == 5`), aplicando iluminación y `FLAG_USE_TEXTURE_REPEAT` en los 5 países. |
| **Líneas negras o sangrado en copas de los árboles** | Mipmaps mezclan la base opaca con la parte superior al repetir en V. | `texture_processor.py` garantiza un guard-band de 3 filas con `alpha = 0` arriba y dilatación RGB (*alpha bleeding*) en todas las texturas de bosque y vallas de los 5 países. |
| **Error `Route changed: existing gate geometry cannot be reused`** | La geometría de parciales manual previa no coincide con la ruta cruda. | `import_stage_export.py` actualiza la ruta directamente e importa las pacenotes y parciales generados desde el extractor oficial. |
| **Desalineación visual vs colisión** | Inconsistencia de matrices o pivotes al exportar desde Blender. | `stage_builder.py` exporta ambos GLB en una sola pasada con las mismas transformaciones mundiales, y `validate_stage.py` audita que el delta sea `< 0.05 m`. |
| **Respaldos de seguridad** | Sobreescritura accidental de archivos de datos personalizados. | `import_stage_export.py` realiza una copia completa previa en `%TEMP%/rally_stage_import_backup_*`. |

---

## 7. Verificación Final de la Entrega

Al finalizar la exportación e importación completa, el estado del proyecto debe mostrar:
1. Las 42 carpetas de etapas en `game/assets/rally/` conteniendo sus respectivos `.glb` y `manifest.json`.
2. Las 42 rutas JSON en `game/data/rally/`.
3. Las 42 pacenotes JSON en `game/data/rally/pacenotes/`.
4. Los 42 documentos de competición y timing gates en `game/data/competition/stages/`.
5. Ejecución limpia del test headless de Godot:
   ```powershell
   godot --headless --path game --editor --quit
   ```
   *Debe terminar con código de salida `0` sin errores de importación.*
