# Plan de implementación — Catálogo de neumáticos v2 y capas nieve/hielo

**Estado:** plan de ejecución. No contiene implementación aplicada.
**Ámbito:** `D:\rust-godot-vehicle-simulator` (proyecto Godot en `game/`).
**Documento de entrada:** `RALLY_MANIAC_PLAN_CATALOGO_NEUMATICOS_NIEVE_HIELO.md` (instrucciones del encargo).
**Fecha de auditoría:** 2026-11-09.
**Regla de este documento:** cada afirmación de estado actual lleva `archivo:línea`. Lo que no se pudo verificar se marca **NO EJECUTADO** o **BLOQUEADO** y nunca se declara aprobado.

---

## Índice

1. [Estado de checkout auditado](#1-estado-de-checkout-auditado)
2. [Resumen ejecutivo](#2-resumen-ejecutivo)
3. [Mapa de dependencias](#3-mapa-de-dependencias)
4. [Matriz de propiedad de datos](#4-matriz-de-propiedad-de-datos)
5. [Catálogo v2](#5-catálogo-v2)
6. [Contratos de las APIs](#6-contratos-de-las-apis)
7. [Modelo de nieve, hielo y clavos](#7-modelo-de-nieve-hielo-y-clavos)
8. [Matriz de cobertura de 42 stages](#8-matriz-de-cobertura-de-42-stages)
9. [Plan fase por fase](#9-plan-fase-por-fase)
10. [Plan de pruebas](#10-plan-de-pruebas)
11. [Compatibilidad y estrategia de activación](#11-compatibilidad-y-estrategia-de-activación)
12. [Decisiones abiertas](#12-decisiones-abiertas)
13. [Checklist de Definition of Done](#13-checklist-de-definition-of-done)
14. [Lista priorizada de PRs](#14-lista-priorizada-de-prs)

---

## 1. Estado de checkout auditado

### 1.1 Identidad del árbol

| Dato | Valor | Cómo se obtuvo |
|---|---|---|
| Rama | `main` | `git branch --show-current` |
| HEAD | `49684050439cfcff7282795c89af7842a23d14f5` | `git rev-parse HEAD` |
| Asunto HEAD | `feat(fisica): migracion combinada bidireccional del pico de adherencia (v2)` | `git log --oneline -10` |
| Commits previos relevantes | `24fa866` pacenotes v3 (42 stages), `dd6096f` 32 etapas Kenya/Finlandia/Suecia/Suiza | `git log --oneline -10` |
| Estado del árbol | **SUCIO**: 164 archivos rastreados modificados + 2586 entradas sin rastrear | `git status --porcelain=v1` agrupado por código |

### 1.2 Cambios locales sin confirmar que afectan directo a este encargo

No se modificó, revirtió ni descartó ninguno. Se listan porque condicionan la línea base:

| Ruta | Por qué importa |
|---|---|
| `game/scripts/rally/rally_pause_inventory.gd` | UI de inventario de neumáticos por rueda; contiene los literales de compuesto a reemplazar (ver §3.9). |
| `game/scripts/rally/rally_escort_exterior_glass.gdshader` | No afecta física; se cita solo para completitud del inventario de cambios. |
| `game/project.godot` | Configuración del proyecto; puede alterar rutas de autoload/escenas. |
| `game/assets/rally/**/manifest.json` (**13 de los 15** vehículos: faltan `ford_escort_rs2000_1971` y `rt-porsche-356a`) | **Fuente real del radio y ancho rodante por esquina** (`vehicle_simulation.gd:150`). Su modificación cambia la línea base de paridad. |
| `tmp/porsche_mod/cache/validation_project/assets/rally/**` (13 manifiestos + 14 GLB) | **Copia espejo del árbol de assets** bajo `tmp/`. Riesgo alto de editar/grepear la copia equivocada; el runtime carga `res://assets/...`, no `tmp/`. No tocar. |
| `game/assets/rally/**/wheel_*.glb`, `chassis.glb`, `damage/*.glb` | Assets visuales; no entran al solver pero afectan `radius_metres` de los manifiestos. |
| `game/data/vehicles/**/HISTORICAL_PROVENANCE.json` (15) | Metadatos de procedencia; no consumidos por el solver. |
| `game/assets/rally/{finland_stage6,russia_stage6}/**/*.glb.import` | Reimportación de mallas; puede cambiar recuentos de triángulos que algunos tests fijan. |
| `instrucciones.md`, `tools/rally_trophy/blender_export.py`, `tmp/porsche_mod/**` | Fuera del ámbito; deben permanecer intactos. |

**Consecuencia operativa:** el agente implementador debe empezar con `git stash` **solo** si el usuario lo autoriza; este plan asume que el árbol se mantiene tal cual y que toda comparación de paridad se hace contra **este mismo árbol**, registrando el hash del árbol de trabajo y no solo el commit.

### 1.3 Comandos usados en la auditoría

```powershell
# Estado
git status --porcelain=v1 | Group-Object { $_.Substring(0,2) }
git branch --show-current; git rev-parse HEAD; git log --oneline -10

# Inventario de código y datos
Get-ChildItem game/scripts/{rally,physics} -File -Filter *.gd
Select-String -Path game/scripts/rally/*.gd,game/scripts/physics/*.gd -Pattern 'gravel_normal|gravel_wet|ALLOWED_IDS|set_wheel_compound|compound_id'
Select-String -Path game/scripts/**/*.gd -Pattern 'snow_mm|water_mm|Collision_Road|surface_group|Gravel'
Get-ChildItem game/data/tires,game/data/weather,game/data/competition/{events,stages} -Recurse -File -Filter *.json

# Evidencia de assets (GLB): nodos de colisión y materiales visuales
# Script de auditoría temporal (no versionado, borrado al terminar): parseo del chunk JSON del GLB
python tmp/glb_nodes2.py     # nodos por stage de colisión
python tmp/road_mats.py      # materiales viales por país
python tmp/glb_snow.py       # materiales snow/ice/erosion por país

# Línea base de pruebas (headless, sin tocar archivos versionados)
$env:APPDATA = "D:\rust-godot-vehicle-simulator\tmp\godot_appdata"   # redirige user:// dentro del workspace
& "...\Godot_v4.7.1-stable_win64_console.exe" --headless --path game --script res://tests/rally/<test>.gd
```

### 1.4 Línea base de pruebas ejecutada (real, no inferida)

Motor: `Godot_v4.7.1-stable_win64.official.a13da4feb` (coincide con `game/project.godot:15`).

| Test | Resultado real | Nota |
|---|---|---|
| `compound_thermal_regression.gd` | **PASS** | `THERMAL normal dry/wet=39.2476/34.0757 wet compound dry/wet=36.4371/33.2435` |
| `tire_combined_migration_contract.gd` | **PASS** | Cubre los 15 perfiles: `front` v2 desactivado, `rear` v2 activo con `m_lat=0.15`, `m_lon=0.08` |
| `tire_inventory_contract.gd` | **PASS** | Incluye roundtrip de inventario y conservación de `brake_collision_loss` / `alignment_collision_damage` |
| `dynamic_weather_tires_contract.gd` | **PASS** | Fija hoy `allowed_compound_ids == ["gravel_normal","gravel_wet"]` (línea 36) |
| `puddles_contract.gd` | **PASS** | |
| `tire_damage_contract.gd` | **PASS** | |
| `tire_hud_zones_contract.gd` | **PASS** | |
| `garage_function_contract.gd` | **PASS** | |
| `stage_vehicle_start_contract.gd` | **PASS** | |
| `stage_grass_contract.gd` | **PASS** | |
| `surface_audio_contract.gd` | **PASS** | |
| `all_countries_stage_import_contract.gd` | **PASS 32/32** | Solo las 32 etapas Kenya/Finlandia/Suecia/Suiza (`all_countries_stage_import_contract.gd:32-37`); **Rusia no está cubierta aquí** |
| `weather_runtime_regression.gd` | **FAIL** — 1 aserción: `"mid-rally garage opens"` | Ver §1.5. Es un fallo **preexistente**, no introducido por esta auditoría |

**NO EJECUTADO:** `stage_export_import_test.gd` (importa GLB pesados y fija recuentos de triángulos; quedó fuera de la ventana de auditoría). Su comando está en §10.13 y debe ejecutarse en Fase 0.

### 1.5 Fallo preexistente diagnosticado (P1)

`game/tests/rally/weather_runtime_regression.gd:72-77` avanza el cursor a `5` (especial `russia_stage6`) y espera que se abra el garaje de servicio:

```gdscript
manager.cursor = 5
manager._update_pending_window()
scene._open_setup_window()
check(scene.awaiting_setup and paused and scene.garage_panel.visible, "mid-rally garage opens")
```

Pero `game/data/competition/events/russia_rally.json → setup_windows` declara ventanas `stage1` (inicial), `2→3`, `4→5`, `6→7`, `8→9`. Con `cursor = 5` la especial actual es `russia_stage6` y la anterior `russia_stage5`, combinación que **no** existe en la lista; `rally_event_manager.gd:196-217` deja `pending_window` vacío y `rally_russia_stage_session.gd:1063-1065` retorna sin abrir nada.

Además `_open_setup_window()` abre primero el **panel de servicio** (`rally_service_panel.gd`) para ventanas no iniciales (`rally_russia_stage_session.gd:1066-1075`), de modo que `garage_panel.visible` tampoco sería cierto en el mismo frame. El test quedó anclado al plan antiguo `DYNAMIC_WEATHER_TIRES_PLAN.md:138` («Después de Stage 5»), que la implementación ya no respeta.

**Acción:** no se corrige aquí (prohibido implementar). Fase 0 debe decidir entre (a) realinear el test a las ventanas vigentes, o (b) realinear las ventanas al plan. Recomendación: (a) para el test de garage y una decisión de producto explícita para las ventanas (§12, D-7).

### 1.6 Limitaciones de la auditoría

- Los GLB de colisión **no conservan materiales** (0 `materials`, 7 nodos como máximo). La correspondencia material→geometría de colisión **no es verificable** desde el asset; solo desde el nombre del nodo. Esto condiciona el diseño de Fase 3 (§3.5, §12 D-1).
- El exportador que genera `*_collision.glb` **no está en el repositorio** (`tools/rally_trophy/` no contiene la lógica de nodos `Collision_*`; solo `tools/pacenote-tooling/v3/road_mesh_extractor.py` define la taxonomía de materiales viales). §12 D-1 lo trata como dependencia externa.
- `user://` está fuera del workspace y el sandbox de escritura lo bloquea; fue necesario redirigir `APPDATA` a `tmp/godot_appdata` para ejecutar Godot. Todo agente debe replicar ese paso (§10.0).
- Los recuentos de triángulos por etapa no se re-midieron completos; solo se verificaron por ejecución de tests.

---

## 2. Resumen ejecutivo

### 2.1 Situación real (verificada, no supuesta)

1. **El catálogo es binario y está duplicado en cinco lugares, cada uno con su propia lista de IDs.**
   `rally_compounds.json:15-105` define exactamente dos compuestos; `rally_tire_compound.gd:9` (`ALLOWED_IDS`), `tire_model.gd:45`, `thermal_model.gd:130`, `vehicle_simulation.gd:178` y `rally_tire_inventory.gd:44` repiten `["gravel_normal","gravel_wet"]` como literal. Añadir un tipo obliga a tocar cinco sitios; olvidar uno produce rechazos inconsistentes entre UI, física y guardado.

2. **Existe *fallback* silencioso, que la instrucción prohíbe.**
   `RallyTireCompound.validated_id()` (`rally_tire_compound.gd:33-34`) y los tres `set_compound` (`tire_model.gd:45`, `thermal_model.gd:130`, `vehicle_simulation.gd:178`) convierten cualquier ID desconocido en `"gravel_normal"` sin avisar. `TireModel.evaluate()` degrada aún más: si el material no existe en la tabla, cae a `"Gravel"` y luego a `"Road"` (`tire_model.gd:279-282`), y `_surface_for_collider()` cae a `"Gravel"` (`vehicle_simulation.gd:1104`).

3. **`TireParameterResolver` no existe.** No hay `game/scripts/physics/tire_parameter_resolver.gd` (listado de `game/scripts/physics/`). La composición vehículo→tipo→superficie→estado está repartida entre `TireModel.configure/evaluate`, `VehicleThermalModel._axle_tire_config` y `VehicleProfileLoader.resolve_tire_filters`. No hay un punto único donde se pueda auditar la procedencia de un parámetro.

4. **El modelo térmico muta la configuración base del coche.** `thermal_model.gd:145-166` (`_apply_compound_to_configs`) escribe 15 claves del compuesto dentro de `tire_config`, `tire_config_front` y `tire_config_rear`, que son los diccionarios derivados del `tires.json` del vehículo. Cambiar de compuesto reescribe el estado base; `reset_for_stage()` (`thermal_model.gd:169-215`) lo reconstruye desde `domains`, pero cualquier lectura posterior a `set_compound` sin `reset_for_stage` ve una base contaminada. Viola el punto 5 de las reglas no negociables.

5. **El tipo de neumático no llega de forma uniforme a la física.** `TireModel.set_wheel_compound()` (`tire_model.gd:63-69`) fija además `axle_optimal_carcass_c[index]`, mientras `VehicleThermalModel.set_wheel_compound()` (`thermal_model.gd:687-690`) no actualiza nada equivalente; el resultado es que una rueda con compuesto distinto cambia su objetivo de carcasa en el solver pero no en el modelo térmico.

6. **La clasificación de superficie es un cuello de botella real y está mal calibrada por país.** `RallyTrackCollisionBuilder.SURFACE_GROUP_BY_NODE` (`rally_track_collision_builder.gd:13-22`) mapea `collision_road → "Gravel"` **para los 42 stages**. Verificado en assets: Suiza tiene solo `road_tarmac_*`/`road_tunnel_*`/`bridgeroad*` y **no** tiene `Collision_Terrain_Dirt/Sand`; Suecia tiene `road_snow_*`; Finlandia mezcla `fin_road_dry`/`fin_road_field_1`/`fin_road_leaves` con `fin_road_tarmac`. Conclusión: hoy **Suiza corre sobre «Gravel»** (fricción 1.08, rodadura 2.2) y **Suecia también**. El metadato de etapa (`"surface": "asphalt"` en los 8 stages suizos) no gobierna nada: no aparece en ningún consumidor de física.

7. **La nieve no existe como capa física; existe como número escalar.** `rally_surface_model.gd:39,180` mantiene `snow_mm` (equivalente de agua según `rally_compounds.json:9`) y `tire_model.gd:78` lo convierte en un multiplicador único `max(1 - s*k, floor)`. No hay nieve suelta vs compactada, ni hielo, ni aguanieve, ni densidad, ni espesor geométrico, ni temperatura de superficie por material. `effective_snow_mm()` (`rally_surface_model.gd:202-203`) es código muerto: no lo llama nadie.

8. **La hidrodinámica depende de un literal de compuesto.** `vehicle_simulation.gd:817` pasa `str(compound.id) == "gravel_wet"` como booleano a `PuddleModel.contact_response`, que ajusta la velocidad de evacuación `28.0` vs `16.0` m/s (`rally_puddles.gd:601`). Añadir un tercer tipo deja los charcos en el comportamiento «normal».

9. **La UI y los textos están cableados al par binario.** `rally_garage_panel.gd:156-168` **deriva** el compuesto por voto de mayoría (`wet_count >= 2 → gravel_wet`); `:1406-1419` dibuja exactamente dos radios «GRAVA SECA»/«GRAVA MOJADA»; `rally_pause_inventory.gd:693-694` ofrece botones «+ Cargar Grava Normal»/«+ Cargar Lluvia»; `:1485` imprime «GRAVA NORMAL» o «LLUVIA INTENSA»; `:1259` dibuja 8 o 12 laminillas según un `if`. Los campos `label`, `short_label`, `advantages`, `drawbacks`, `for_gravel` e `is_asphalt_tire` del catálogo **no se leen en ningún script de producción** (solo en tests) — son datos muertos.

10. **El hash de reglas incluye el SHA-256 del catálogo de neumáticos.** `rally_weather_scheduler.gd:471-474` mete `tire_catalog` (hash del archivo completo) en `rules_hash_for()`, y `rally_event_manager.gd:536-538` rechaza la restauración si no coincide. **Editar el catálogo invalida todos los guardados existentes.** Es el P0 técnico más urgente: sin cambiarlo, la Fase 1 (datos puros) rompe partidas guardadas.

11. **Los parámetros "compartidos" hoy son copias, no una abstracción.** Los 15 `tires.json` son **byte-idénticos salvo** `radius`, `width`, `wheel_mass`, `rim_diameter_inches`; 14 de 15 son idénticos entre sí y solo `ford-escort-rs2000` difiere (`force_model` y `tire_filters` propios). Los 15 `surfaces` son idénticos. `contact_patch`, `load_sensitivity_per_newton`, `rolling_resistance_coefficient`, `pneumatic_trail_m`, `surface_transition_tau_s`, presión fría y ventana térmica global coinciden en los 15. **Esto no autoriza a moverlos** (§4.4): son calibraciones provisionales por vehículo sin prueba de que sean intencionalmente compartidas.

12. **Dos fuentes de geometría de rueda.** El radio rodante sale de `manifest.json → wheel_pivots[*].radius_metres` (`vehicle_simulation.gd:145-151`), con variación **por esquina**; el `radius` de `tires.json` solo alimenta el modelo radial (`tire_radial_model.gd:5-13`) y `maximum_tire_deflection_m` (`tire_model.gd:215`). Además `tire_model.gd:103-104,209` calcula `tire_radius` y **nunca lo usa** (código muerto).

13. **La masa de repuesto está declarada dos veces y discrepa.** `rally_compounds.json:110` fija `wheel_mass_kg: 18.0` como valor de catálogo; `chassis.json → spare_policy.wheel_mass_kg` lo sobrescribe en 14 de 15 coches con 14.0 / 18.0 / 20.0 y `ford-escort-rs2000` no define `spare_policy`, por lo que cae al 18 del catálogo (`mass_model.gd:223-232`, `rally_escort_vehicle.gd:850-853`).

14. **La frecuencia que cita la documentación no es la real.** `TIRE_PATCH_MEMORY.md:19` afirma «paso principal de 120 Hz»; el proyecto declara `common/physics_ticks_per_second=60` (`game/project.godot:29`) y el runtime lo confirma (`RALLY_SESSION_METADATA … "physics_ticks_per_second":60`), con subpasos de `≤ 2 ms` (`vehicle_simulation.gd:44,135-140`). Todo presupuesto de CPU del plan se calcula sobre 60 callbacks/s y hasta 8 subpasos.

15. **Hay datos de configuración declarados y nunca consumidos** (deuda que el plan no debe «arreglar» a ciegas): `water_exchange_w_m2_k`, `water_grip_response`, `snow_grip_response` en los 5 perfiles regionales (`rally_weather_presets.json`), `effective_snow_mm()` (`rally_surface_model.gd:202-203`), `inventory.baseline_spare_count` (`rally_compounds.json:112`), `LEGACY_SAVE_PATH` (`rally_event_manager.gd:9`) y `fitment`/`start_temperature_policy`/`for_gravel`/`is_asphalt_tire`/`label`/`short_label`/`advantages`/`drawbacks` del catálogo. Fase 1-6 los activa o los elimina; mientras tanto no son fuente de verdad.

_Última comprobación:_ contraste cruzado de §2.1.1 a §2.1.15 contra `git grep` y ejecución de tests (§1.4). Ninguna afirmación proviene de la documentación existente del repositorio; varias la contradicen (§2.1.14, §1.5).

### 2.2 Riesgos P0

| ID | Riesgo | Evidencia | Mitigación exigida |
|---|---|---|---|
| P0-1 | Editar el catálogo invalida guardados por `rules_hash` | `rally_weather_scheduler.gd:471-474`, `rally_event_manager.gd:536-538` | PR-02a: sustituir el SHA crudo por `catalog_id + catalog_version + physics_subset_hash` **antes** de tocar datos. |
| P0-2 | `_apply_compound_to_configs` muta la base del vehículo | `thermal_model.gd:145-166` | Fase 2: configuración resuelta por rueda, base inmutable, test de hash de `domains`. |
| P0-3 | Cinco listas de IDs divergentes + fallback silencioso | §2.1.1, §2.1.2 | Fase 1: una sola API `is_valid`/`resolve_alias`, error explícito. |
| P0-4 | Suiza y Suecia corren sobre fricción de grava | `rally_track_collision_builder.gd:18`, assets | Fase 3 antes de activar ninguna familia nueva (si no, `asphalt_*` y `snow_studded` se calibrarían sobre un material equivocado). |
| P0-5 | Dos implementaciones de la misma fórmula agua/nieve | `rally_tire_compound.gd:39-76` vs `tire_model.gd:71-84` | Fase 2: el resolver es la única fuente; `grip_response` se conserva solo como adaptador de test hasta eliminarlo. |
| P0-6 | Homogeneizar los 14 coches idénticos | §2.1.11 | Fase 0/2: prohibido deduplicar sin test de paridad de valores resueltos (§4.4). |
| P0-7 | La frecuencia citada en la documentación (120 Hz) no es la real (60 Hz + subpasos) | `game/project.godot:29` vs `TIRE_PATCH_MEMORY.md:19` | Fase 0: fijar 60 Hz como referencia en todos los tests y corregir la documentación (§10.11). |

### 2.3 Enfoque propuesto

Cinco capas con **una sola contribución por fenómeno**, y una regla de precedencia única:

```
L1 vehículo/eje nominal (INMUTABLE)  →  L2 tipo de neumático (catálogo)
   →  L3 material base + capas de superficie  →  L4 estado dinámico por rueda
   →  L5 solver (TireModel)  →  contabilidad energética
```

- L1 nunca se escribe: `tires.json`, `tire_filters.json`, `chassis.json`, `manifest.json → wheel_pivots`.
- L2 solo aporta **factores y bandas** reutilizables; nunca anchos, radios, presiones ni `force_model`.
- L3 aporta el material base y las capas; cada capa activa aporta **exactamente un factor**.
- L4 aporta presión, temperatura, desgaste, daño y `stud_integrity`.
- L5 conserva `patch_pos`, brush elíptico, presupuesto combinado Fx/Fy, memoria postpico y migración v2 **sin tocar su matemática**.

La centralización se hace **por sustracción de responsabilidad**, no por fusión de JSON: el catálogo pierde los campos que hoy mutan al vehículo y gana los campos que hoy están duplicados en código.

---

## 3. Mapa de dependencias

### 3.1 Flujo completo (menú/evento → solver → save/IA)

```
[menú] rally_maniac_menu.gd
   └─ selección de evento/vehículo
        └─ [evento] rally_event_manager.gd
             ├─ load_event()            ← data/competition/events/<rally>.json
             ├─ begin_event()
             │    ├─ tire_rules.default_compound_id / allowed_compound_ids   (líneas 132-137)
             │    ├─ CompoundScript.load_catalog()                           (línea 137)
             │    ├─ _build_itinerary()                                      (647-682)
             │    ├─ _generate_weather_schedule()  ← rally_weather_scheduler.gd
             │    │     └─ rules_hash_for() incluye sha del catálogo         (469-486)
             │    ├─ _register_participants(); _assign_rival_compounds()     (589-594; 277-306)
             │    └─ save()  → user://rally_event_v2.json (version 3)        (472-522)
             │
             ├─ confirm_setup(compound_id, values)                            (227-252)
             │    └─ valida contra tire_rules.allowed_compound_ids
             │
             └─ advance() / close_current_stage()  ← guardado por stage

[sesión] rally_russia_stage_session.gd
   ├─ vehicle.set_tire_compound(confirmed_compound_id)                       (146)
   ├─ thermal_model.tire_states[i].wear/damage ← mounted_tire_condition      (147-150)
   ├─ vehicle.ensure_tire_inventory()                                        (152)
   ├─ tire_inventory.restore(tire_inventory_state)                           (153-165)
   ├─ vehicle.apply_tire_inventory()                                         (165)
   ├─ _swap_stage_geometry() → track_collision.build_collision(visual_root)  (171-174, 954)
   │     └─ SURFACE_GROUP_BY_NODE + build_erosion_bank_collision
   ├─ _build_puddles(); _build_stage_grass(); place_vehicle_on_stage()       (177-179)
   ├─ _setup_event_weather() → rally_weather_controller.configure()          (137)
   └─ _open_setup_window() → garage_panel / service_panel                    (1057-1129)

[garaje] rally_garage_panel.gd
   ├─ draft_wheel_compounds (Dictionary FL/FR/RL/RR)
   ├─ draft_compound_id  ← DERIVADO por mayoría (156-168)
   ├─ close_garage(apply) → vehicle.apply_setup_values + service_tire_inventory (313-355)
   └─ confirmed_setup = {compound_id (derivado), values}

[inventario] rally_escort_vehicle.gd
   ├─ tire_inventory.mounted[4] / spares[]   ← rally_tire_inventory.gd
   ├─ fresh_tire_state()   ← RallyTireCompound.load_catalog()  (813-822)
   ├─ apply_tire_inventory()
   │     ├─ thermal_model.set_wheel_compound(i, id)   (843)
   │     ├─ tire_model.set_wheel_compound(i, id)      (844)
   │     ├─ copia TIRE_STATE_KEYS                     (845-849)
   │     └─ mass_model.set_carried_spares()           (850-853)
   └─ service_tire_inventory() / exchange_tire() / discard_spare() (857-886)

[física] vehicle_simulation.gd  (_integrate_forces, 60 Hz, subpasos ≤ 2 ms)
   ├─ ShapeCast3D por rueda → _surface_for_collider()          (1096-1104)
   ├─ _local_conditions_at_contact()                            (204-217)
   │     ├─ weather_controller.local_conditions_for_contact()   ← rally_weather_controller.gd:241-259
   │     └─ puddle_system.sample_contact()                      ← rally_puddles.gd:537-573
   ├─ PuddleModel.contact_response(..., wet_tire == "gravel_wet", ...)  (814-823)
   ├─ _solve_contact_wheel() → TireModel.evaluate()             (1165-1195)
   │     └─ mu = surface_friction × load_scale × thermal × compound_mult   (421-425)
   └─ thermal_model.advance_tire() a 30 Hz                      (881-891)

[clima] rally_weather_controller.gd → rally_surface_model.gd
   ├─ configure(for_stage_id, entry, route_path)  ← weather_schedule + route JSON
   ├─ update_vehicle_position() → blended_state_at_distance()
   ├─ advance_ambient(delta, solar)  → _step_all()  (3 zonas, pasos ≤ 5 s)
   └─ local_conditions_for_contact(surface_name, pos)  (241-259)
```

### 3.2 Grafo de lectura/escritura de datos

| Dato | Escritor(es) | Lector(es) | Riesgo detectado |
|---|---|---|---|
| `data/tires/rally_compounds.json` | nadie en runtime | 6 llamadas a `load_catalog()` (§3.3) | Releído y re-parseado en cada servicio/montaje; sin caché. |
| `tires.json` (`domains.tires`) | nadie | `TireModel.configure` (`tire_model.gd:87-255`), `VehicleThermalModel.configure` (`thermal_model.gd:59-70`), `TireRadialModel` | `_apply_compound_to_configs` **escribe** copias derivadas. |
| `tire_filters.json` | nadie | `VehicleProfileLoader.resolve_tire_filters` (`profile_loader.gd:129-187`) | Capa opcional; `combined_migration_v2_enabled` solo en `rear` de 14 coches. |
| `manifest.json → wheel_pivots` | tools de importación | `vehicle_simulation.gd:145-151` | **Modificado en el árbol**; segunda fuente de radio/ancho. |
| `chassis.json → spare_policy` | nadie | `rally_escort_vehicle.gd:850-853`, `mass_model.gd:223-232` | Discrepa del catálogo (18 vs 14/18/20). |
| `event.json → tire_rules` | nadie | `rally_event_manager.gd:132-137,232-234` | Los 5 eventos declaran lo mismo (2 IDs). |
| `event.json → setup_windows` | nadie | `rally_event_manager.gd:192-217` | Test de regresión desalineado (§1.5). |
| `weather_schedule` | `rally_weather_scheduler.gd` | `rally_weather_controller.gd`, `rally_competition.gd` | Contiene `initial_snow_mm` pero **no** capas de hielo. |
| `tire_inventory_state` (save) | `rally_russia_stage_session.gd:1194-1204`, `rally_service_panel.gd:225-228` | mismo + `rally_tire_inventory.restore` | Valida IDs con lista literal (`rally_tire_inventory.gd:44`). |
| `user://rally_event_v2.json` | `rally_event_manager.save()` | `restore()` | `rules_hash` incluye SHA del catálogo → P0-1. |

### 3.3 Puntos de lectura del catálogo (todos los consumidores reales)

| Sitio | Llamada | Frecuencia |
|---|---|---|
| `rally_tire_compound.gd:13` | definición de `load_catalog()` | — |
| `rally_event_manager.gd:137` | `begin_event()` | 1 por evento |
| `rally_event_manager.gd:573` | `restore()` | 1 por carga |
| `rally_escort_vehicle.gd:815` | `fresh_tire_state()` | **1 por neumático** creado |
| `rally_escort_vehicle.gd:827` | `ensure_tire_inventory()` | 1 por sesión |
| `rally_escort_vehicle.gd:850` | `apply_tire_inventory()` | **1 por aplicación de inventario** |
| `rally_pause_inventory.gd:645` | vista de inventario | por apertura de UI |
| `vehicle_simulation.gd:191` | `get_compound_catalog()` | por consulta externa |
| `tire_model.gd:48-49` | `set_compound()` si no hay catálogo | por cambio de compuesto |
| `thermal_model.gd:134-135` | `set_compound()` si no hay catálogo | por cambio de compuesto |

Ninguno ocurre dentro del bucle de subpasos; el riesgo de I/O por paso **hoy no existe** y el plan debe mantenerlo así (§6.4). **Corrección de frecuencia:** el proyecto corre a **60 Hz de tick** (`game/project.godot:29` → `common/physics_ticks_per_second=60`, confirmado en runtime por `RALLY_SESSION_METADATA physics_ticks_per_second:60`) con subpasos de `≤ 2 ms` (`vehicle_simulation.gd:44,135-140`), es decir ~8 subpasos por callback. `TIRE_PATCH_MEMORY.md:19` afirma «paso principal de 120 Hz»: **la documentación no coincide con la implementación** y este plan usa 60 Hz + subpasos como referencia real.

### 3.4 Dónde se decide el compuesto (autoridad real)

| Nivel | Mecanismo | Archivo:línea |
|---|---|---|
| Evento | `tire_rules.allowed_compound_ids` | `rally_event_manager.gd:232-234` |
| Evento | `tire_rules.default_compound_id` | `rally_event_manager.gd:134` |
| Borrador UI | `draft_wheel_compounds` + derivación por mayoría | `rally_garage_panel.gd:156-168` |
| Confirmación | `confirm_setup()` + ventana pendiente | `rally_event_manager.gd:227-252` |
| Montaje | `tire_inventory.mounted[i].compound_id` | `rally_escort_vehicle.gd:874-886` |
| Vehículo | `simulation.active_compound_id` | `vehicle_simulation.gd:73,177-188` |
| Rueda | `tire_model.wheel_compounds[i]`, `thermal_model.wheel_compounds[i]` | `tire_model.gd:63-69`, `thermal_model.gd:687-690` |
| IA rival | `rival_compounds[stage][pid]` | `rally_event_manager.gd:277-306` |

**Hueco crítico:** no hay autoridad única. `active_compound_id` (vehículo) y `wheel_compounds[i].id` (rueda) pueden discrepar y de hecho discrepan cuando el inventario se restaura con compuestos distintos por rueda. El plan introduce `TireTypeAssignment` como autoridad única (§6.5).

### 3.5 Dónde se decide el material de contacto

| Nivel | Mecanismo | Archivo:línea |
|---|---|---|
| Nodo de colisión → grupo | `SURFACE_GROUP_BY_NODE` + `terrain_surface_group` | `rally_track_collision_builder.gd:13-22,139-143` |
| Talud de erosión → nodo | `_erosion_bank_collision_node()` | `rally_track_collision_builder.gd:89-99` |
| Collider → nombre de superficie | `_surface_for_collider()` (busca grupo, luego `meta("surface")`, luego `"Gravel"`) | `vehicle_simulation.gd:1096-1104` |
| Nombre → parámetros | `axle_surfaces[i]` con fallback `Gravel`→`Road` | `tire_model.gd:276-290` |
| Sin contacto | se fuerza `"Gravel"` | `vehicle_simulation.gd:741` |
| Perfil térmico de suelo | `_profile_for_surface("Gravel")` **hardcodeado** | `rally_surface_model.gd:138` |

### 3.6 Cadenas de suministro de las condiciones locales

```
RallyWeatherController.local_conditions_for_contact(surface_name, pos)   :241-259
  ├─ distance = proyección sobre ruta (ventana ±4 segmentos del cursor)
  ├─ st = surface.blended_state_at_distance(distance)
  └─ devuelve: air_c, ground_c, water_mm, snow_mm, saturation, climate{...},
               precipitation_kind, surface_name, water_mm_effective,
               snow_mm_effective, route_progress_m, zone_index

VehicleSimulation._local_conditions_at_contact()   :204-217
  ├─ base: air_c=ambient, ground_c=30.0, water=0, snow=0, puddle=0
  ├─ si calendar_active: merge(weather, true)  → ground_c puede venir de la zona
  └─ si hay contacto con carga: merge puddle; water_mm = max(water_mm, depth_mm)

TireModel.evaluate(..., water_mm, snow_mm, ground_temperature_c)   :258-274
  └─ compound_water_snow_ground_factor()   :71-84
```

Dos defectos verificados aquí:
- `ground_c` por defecto **30.0** (`vehicle_simulation.gd:205`) cuando no hay calendario: un valor que nunca pasa por el modelo de superficie y que alimenta el factor de suelo y la conducción térmica.
- `water_mm` se **maximiza** con la profundidad de charco (`:215`) pero el charco también aplica soporte y arrastre por separado (`:824-831`). Es una doble fuente de agua: el factor de compuesto ve el charco, y el modelo hidrodinámico lo vuelve a aplicar. §7.6 lo corrige sin cambiar el comportamiento legacy por defecto.

### 3.7 La cadena del solver (autoridad que debe preservarse)

`TireModel.evaluate()` (`tire_model.gd:258-644`) es la única autoridad de integración. Orden real:

1. Resolver superficie objetivo y suavizar `surface_friction/stiffness/rolling` con `tau_surface` (`:276-312`).
2. Mezcla de contacto `contact_blend` (`:314-328`).
3. Slip ratio/angle objetivo y filtrado por longitud de relajación (`:330-392`).
4. `mu = surface_friction · load_scale · clamp(thermal_grip_factor) · compound_mult` (`:421-425`).
5. Capacidades `fx_capacity = mu · longitudinal_ratio · Fz`, `fy_capacity = mu · lateral_bonus · Fz` (`:433-434`).
6. Rigideces brush derivadas de capacidad/pico/longitud (`:466-471`).
7. Migración v2 bidireccional si `combined_migration_v2_enabled` (`:478-529`).
8. Memoria postpico por dirección (`:530-563`) y `slide_scale` (`:564-575`).
9. Plasticidad `max_elastic_norm = 2.65` y descarga (`:583-594`).
10. `_brush_force_elliptical()` (`:596,647-657`).
11. Rodadura restada de `fx` y **recorte final** del presupuesto (`:603-617`).
12. Potencia de fricción y telemetría (`:619-644`).

**Invariante que el plan no puede romper:** el paso 11 garantiza `‖(fx/bound_x, fy/bound_y)‖ ≤ 1`. Cualquier contribución nueva (clavos, nieve, hielo) debe entrar en `mu` (paso 4) o en las capacidades (paso 5), **nunca** como fuerza añadida después del paso 11.

### 3.8 Persistencia: cadena exacta del guardado

```
save() → { version:3, ..., confirmed_compound, draft_compound, setup_values,
           mounted_tire_condition, tire_inventory_state, vehicle_damage_state,
           weather_schedule, climate_seed, generator_version, route_hashes,
           surface_continuity, rival_compounds, rules_hash }     :472-506

restore() → valida version==3, event_id, rules_hash               :524-577
            mounted_tire_condition[i] = {wear_fraction, thermal_damage_fraction}   :1202-1204
            tire_inventory_state = {mounted[4], spares[], next_id,
                                    brake_collision_loss[4],
                                    alignment_collision_damage[4]}                :1197-1201
```

`rally_tire_inventory.restore()` (`rally_tire_inventory.gd:36-54`) valida: 4 montados, repuestos ≤ capacidad, `state` es Dictionary, `compound_id ∈ {gravel_normal, gravel_wet}`, IDs únicos y positivos. Es el único guardián de IDs en el save y usa la lista literal (P0-3).

### 3.9 Consumidores de UI y de IA que hay que tocar

| Consumidor | Literales / lógica binaria | Archivo:línea |
|---|---|---|
| Garaje, propiedad derivada | `wet_count >= 2` | `rally_garage_panel.gd:156-168` |
| Garaje, agrupación de compuesto | dos radios fijos | `rally_garage_panel.gd:1406-1419` |
| Garaje, `_all_dry/_all_wet` | mayoría | `rally_garage_panel.gd:1436-1445` |
| Garaje, tarjetas por rueda | `MOJADO`/`SECO` | `rally_garage_panel.gd:1531-1545` |
| Garaje, estado del coche | `"MOJADO" if _all_wet()` | `rally_garage_panel.gd:1452` |
| Garaje, cierre | `confirmed_setup.compound_id` derivado | `rally_garage_panel.gd:338-345` |
| Pausa/inventario, descripción | `"Lluvia" if id == gravel_wet` | `rally_pause_inventory.gd:559` |
| Pausa/inventario, carga de repuesto | dos botones literales | `rally_pause_inventory.gd:693-694` |
| Pausa/inventario, etiqueta | `"Lluv"`/`"Norm"` | `rally_pause_inventory.gd:943` |
| Pausa/inventario, gráfico | color y 8/12 laminillas | `rally_pause_inventory.gd:1254-1264` |
| Pausa/inventario, nombre | `GRAVA NORMAL`/`LLUVIA INTENSA` | `rally_pause_inventory.gd:1485-1490` |
| Servicio | guarda `tire_inventory_state` | `rally_service_panel.gd:225-228` |
| Evento, rivales | `pick_wet`, `"gravel_wet"/"gravel_normal"` | `rally_event_manager.gd:294-301` |
| Competición, factor rival | `if cid == "gravel_wet": return 0.992` | `rally_competition.gd:275-280` |
| Pronóstico | `"Grava normal"`/`"Grava lluvia"` | `rally_weather_scheduler.gd:509-512` |

---

## 4. Matriz de propiedad de datos

### 4.1 Clasificación usada

| Etiqueta | Significado |
|---|---|
| `VEHICLE_IMMUTABLE` | Geometría/masa/inerza del coche. El catálogo **nunca** lo escribe. |
| `VEHICLE_AXLE_CALIBRATION` | Calibración por eje del coche. Puede coincidir entre coches hoy y seguir siendo propiedad del coche. |
| `TYPE_SHARED` | Propiedad del tipo de neumático, reutilizable por todos los coches. |
| `SURFACE_SHARED` | Propiedad de la superficie/capa, compartida por todos los coches y tipos. |
| `CONTACT_DYNAMIC` | Se recalcula por contacto/subpaso. |
| `STATE_PER_TIRE` | Estado persistente por unidad. |
| `UNDECIDED` | No se mueve hasta tener prueba de paridad y decisión explícita. |

### 4.2 Campos de `tires.json` (15 coches)

Ruta JSON base: `game/data/vehicles/**/tires.json → tires.*`.
Consumidores: `TireModel.configure` (`tire_model.gd:87-255`), `VehicleThermalModel.configure` (`thermal_model.gd:59-70`), `TireRadialModel.evaluate` (`tire_radial_model.gd:16-87`), `profile_loader.gd:47-78`.

| Ruta JSON | Valores observados (15 coches) | Clasificación | Precedencia actual | Riesgo de migración |
|---|---|---|---|---|
| `front.radius`, `rear.radius` | 0.2500 (Mini, Abarth) … 0.3220 (Volvo); Stratos 0.3192 | `VEHICLE_IMMUTABLE` | JSON del coche | **Alto**: define `sidewall_m` y `maximum_tire_deflection_m`. Moverlo a tipo rompe el modelo radial. |
| `front.width`, `rear.width` | 0.1500 … 0.3180 | `VEHICLE_IMMUTABLE` | JSON del coche | **Alto**: entra en `geometry_scale` (`tire_radial_model.gd:32`) y en el modelo hidrodinámico (`rally_puddles.gd:610`). |
| `front.rim_diameter_inches`, `rear.*` | 13.0 en los 15 | `VEHICLE_IMMUTABLE` (hoy constante accidental) | JSON del coche | Medio: si un tipo futuro exige otra llanta, debe seguir siendo fitment del coche (§12 D-5). |
| `front.wheel_mass`, `rear.wheel_mass` | 14.0 (Fulvia) / 20.0 (13 coches) | `VEHICLE_IMMUTABLE` | `tires.json`, replicado en `chassis.spare_policy` | **Alto**: inercia de rueda y masa de repuesto. Discrepancia ya existente con el 18 del catálogo. |
| `contact_patch` | 0.2 en los 15 | `UNDECIDED` | `tires.json` global | Es el denominador de `base_relaxation_length_m` (`tire_model.gd:211`) y del `patch_ratio`. **No mover sin paridad.** |
| `load_sensitivity_per_newton` | 1.5e-05 en los 15 | `UNDECIDED` | filters eje > tires eje > tires global (`tire_model.gd:803-813`) | Afecta `load_sensitivity_exp` (`:401-406`). Compartido hoy por copia, no por diseño. |
| `rolling_resistance_coefficient` | 0.015 en los 15 | `UNDECIDED` | ídem | Podría ser `TYPE_SHARED` legítimamente (rodadura del dibujo), pero hoy también modula por superficie (`state.surface_rolling`). |
| `pneumatic_trail_m` | 0.035 global; 0.035/0.038 en filtros | `UNDECIDED` | filtros eje | Define el par autoalineante; es geometría de huella, no del compuesto. |
| `surface_transition_tau_s` | 0.08 global; 0.08/0.07 por eje | `SURFACE_SHARED` candidato | filtros eje > tires eje | Constante de mezcla superficie↔neumático; coherente como compartido, pero requiere paridad. |
| `airborne_spin_decay_torque` | 1.5 en los 15 | `UNDECIDED` | `tires.json` | Inercia/comportamiento en vuelo; probablemente del coche. |
| `surfaces.<name>.friction` | idéntico en los 15: Curb 1.05, Dirt 1.05, Grass 0.70, Gravel 1.08, Road 1.05, Sand 0.85 | `SURFACE_SHARED` (con reserva) | `tires.json` | **Es el núcleo de la fricción.** Mover a catálogo de superficies es defendible, pero hoy es calibración del coche; requiere decisión (§12 D-2). |
| `surfaces.<name>.stiffness` | Curb 4.0, Dirt 0.9, Grass 0.5, Gravel 1.0, Road 4.0, Sand 0.6 | `SURFACE_SHARED` (con reserva) | ídem | Entra en `rise_gamma` (`tire_model.gd:435-436`) y en `sqrt(stiffness/5)`; un cambio altera la forma de la curva. |
| `surfaces.<name>.rolling_resistance` | Curb 1.2, Dirt 2.0, Grass 3.5, Gravel 2.2, Road 1.0, Sand 3.0 | `SURFACE_SHARED` | ídem | |
| `surfaces.<name>.longitudinal_grip_ratio` | 0.92/1.0 en `Gravel` según eje; 1.0 el resto | `VEHICLE_AXLE_CALIBRATION` | `tires.json` + filtros | **No homogeneizar:** el delantero está limitado a 0.92 a propósito. |
| `surfaces.<name>.lateral_grip_assist` | 0.0 delante; 0.08 detrás en `Gravel`; 0.05/0.03/0.06 en Dirt/Sand/Gravel global | `VEHICLE_AXLE_CALIBRATION` | `tires.json` + filtros; delantero anulado si no es explícito (`tire_model.gd:858-863`) | **No homogeneizar.** Es el único "assist" lateral del sistema; el catálogo no debe añadir otro (§7.5). |
| `thermal.*` (24 claves) | idénticas globales en los 15: `optimal_tread_temperature_c 50`, `optimal_tread_window_c 50`, `overheat_tread_temperature_c 100`, `optimal_carcass_temperature_c 60`, capacidades 6300/18000/2200, conductancias 60/25/30/15/55/25, `slip_heat_efficiency 0.55`, `gravel_eject_k 0.25`, etc. | `UNDECIDED` | `thermal_model.gd:59-70,692-703` | **Estas son exactamente las claves que `_apply_compound_to_configs` sobreescribe.** Deben pasar a `TYPE_SHARED` **solo** mediante el resolver, sin escribir el JSON del coche. |
| `front.thermal`, `rear.thermal` | **Difieren por eje**: `carcass_hysteresis_efficiency` 0.65/0.40, `slip_heat_efficiency` 0.58/0.50, `road_conductance_w_k` 50/60 | `VEHICLE_AXLE_CALIBRATION` | `_merged_config` (`thermal_model.gd:718-723`) | **Alto:** son diferencias reales por eje; cualquier override de tipo debe ser multiplicativo o acotado, nunca sustitutivo. |
| `pressure.cold_kpa_gauge` | 180 en las 4 ruedas en los 15 | `VEHICLE_AXLE_CALIBRATION` | `tires.json` | Presión base es del coche (reglaje). El tipo puede proponer una **ventana**, no un valor. |
| `pressure.reference_temperature_c` | 25.0 en los 15 | `VEHICLE_AXLE_CALIBRATION` | ídem | |
| `pressure_mechanics.response_sensitivity` | −0.15 en los 15 | `UNDECIDED` | `_resolve_pm_scalar` (`tire_model.gd:816-826`) | |
| `pressure_mechanics.rolling_resistance_sensitivity` | −0.30 en los 15 | `UNDECIDED` | ídem | |
| `radial_model.*` | idéntico en los 15 (`carcass_stiffness_n_m 30000`, `pressure_stiffness_n_m_per_kpa 666.667`, `reference_sidewall_m 0.1149`, `reference_width_m 0.2`, `damping_ratio 0.12`, `rim_stop_*`) | `UNDECIDED` (referencias de normalización) | `tire_radial_model.gd:26-29` | `reference_width_m`/`reference_sidewall_m` son **normalizadores** de calibración, no geometría del coche. Moverlos cambiaría `geometry_scale` de todos. |
| `force_model.front`, `force_model.rear` | **2 grupos**: `ford-escort-rs2000` (rear 0.45/0.35, falloff 0.85, slide 0.97) y los otros 14 (rear 0.25/0.25, falloff 1.45, slide 0.88) | `VEHICLE_AXLE_CALIBRATION` | `tires.json` + `tire_filters.json` (`TIRE_FORCE_KEYS`) | **Prohibido por la instrucción 3.4** reemplazar por constantes. Es la calibración de equilibrio del coche. |

### 4.3 Campos de `tire_filters.json` y `suspension_filters.json`

| Documento | Grupos distintos | Contenido | Clasificación |
|---|---|---|---|
| `tire_filters.json` | **2** (`ford-escort-rs2000` propio; 14 idénticos) | `combined_migration_v2_enabled` (solo `rear`), `combined_lateral/longitudinal_peak_migration` 0.15/0.08 rear y 0.25/0.25 front, `contact_ramp_tau_s`, `min_relaxation_tau_s`, `relaxation_recovery_scale`, `slip_loss_tau_s`, `slip_recovery_tau_s`, escalares de eje, `surfaces.Gravel` por eje | `VEHICLE_AXLE_CALIBRATION` |
| `suspension_filters.json` | 1 (los 15) | filtros de suspensión | fuera de ámbito (se cita para no confundirlo) |

**Observación de consistencia:** `rt-escort-rs2000` usa la calibración genérica (los 14) mientras `ford-escort-rs2000` usa la propia, pese a ser el mismo modelo declarado. Puede ser deliberado (asset distinto) o deuda. Marcado `UNDECIDED` (§12 D-3). No se toca en este plan.

### 4.4 Regla anti-homogeneización (obligatoria para el implementador)

> Que 14 o 15 coches compartan un valor **no** es prueba de que el valor sea del tipo.
> Solo se extrae un campo a `TYPE_SHARED` si se cumplen **las tres** condiciones:
> 1. existe un test que demuestra que el valor resuelto por rueda/eje es idéntico antes y después (tolerancia 1e-9 o 0 ulp),
> 2. el campo tiene una justificación física que no depende del coche (p. ej. banda térmica del compuesto),
> 3. el campo queda como **override opcional** del coche: si el JSON del coche lo define, gana el coche.
>
> Si falta cualquiera, el campo permanece en el vehículo y el catálogo no lo lee.

### 4.5 Campos de otros documentos (para completar la propiedad)

| Ruta | Campo | Valores | Clasificación | Consumidor |
|---|---|---|---|---|
| `chassis.json` | `physical_mass_inventory.spare_policy.wheel_mass_kg` | 14.0 / 18.0 / 20.0 (14 coches; `ford-escort-rs2000` ausente) | `VEHICLE_IMMUTABLE` | `rally_escort_vehicle.gd:850-853` → `mass_model.gd:223-232` |
| `chassis.json` | `spare_policy.tools_mass_kg` | 7.0 en los 14 | `VEHICLE_IMMUTABLE` | ídem |
| `manifest.json` | `wheel_pivots.<corner>.radius_metres` | por esquina, 0.25–0.322 | `VEHICLE_IMMUTABLE` | `vehicle_simulation.gd:145-151` |
| `manifest.json` | `wheel_pivots.<corner>.width_metres` | por esquina | `VEHICLE_IMMUTABLE` | ídem (hidrodinámica, `vehicle_simulation.gd:819`) |
| `rally_compounds.json` | `inventory.capacity` | 2 | `TYPE_SHARED` (reglamento) | `rally_tire_inventory.gd:6`, `rally_escort_vehicle.gd:829-833` |
| `rally_compounds.json` | `inventory.default_spare_count` | 2 | `TYPE_SHARED` | `rally_escort_vehicle.gd:832` |
| `rally_compounds.json` | `inventory.wheel_mass_kg` | 18.0 | `UNDECIDED` (fallback) | `mass_model.gd:230` |
| `rally_compounds.json` | `inventory.tools_mass_kg` | 7.0 | `UNDECIDED` (fallback) | ídem |
| `rally_compounds.json` | `inventory.baseline_spare_count` | 2 | **no consumido** | — |
| `rally_compounds.json` | `inventory.mass_component_name` | `spare_wheels_and_tools` | `TYPE_SHARED` | `mass_model.gd:224` |
| `rally_compounds.json` | `durability_life_scale` | 0.425 | `TYPE_SHARED` (global, no por tipo) | `thermal_model.gd:459` |

### 4.6 Ejemplo trabajado: `Mini` y `Stratos` con `snow_studded` sobre `Ice`

Datos reales de `game/data/vehicles/rt/rt-mini-cooper-s/tires.json` y `.../rt-lancia-stratos/tires.json` (y sus manifiestos).

**Proviene del tipo `snow_studded` (idéntico en ambos coches) — `TYPE_SHARED`:**

| Parámetro | Valor | Estado |
|---|---|---|
| `tread_optimum_c` | `12 … 20` | TBD/experimental (§5.6) |
| `tread_window_c` | `30 … 45` | TBD/experimental |
| `carcass_optimum_c` | `35` | TBD/experimental |
| `overheat_tread_c` | `70` | TBD/experimental |
| `slip_heat_efficiency` | `0.42` | TBD/experimental |
| `wear_grip_loss`, `thermal_damage_grip_loss` | `0.30`, `0.25` | TBD/experimental |
| `f_ice_rubber` (factor de goma sobre hielo) | `0.30 … 0.38` | TBD/experimental |
| `f_ice_studded` (factor con clavos íntegros) | `0.75 … 0.92` | TBD/experimental |
| `stud_gain_ice` (ratio `f_ice_studded / f_ice_rubber`) | derivado, `2.0 … 3.0` | TBD/experimental |
| `stud_wear_per_km_bare`, `stud_wear_per_mj_slip` | TBD | TBD/experimental |
| `stud_count_per_tire`, `stud_protrusion_mm` | `TBD` (no inferir de neumáticos modernos) | TBD/experimental (§12 D-4) |
| `drainage` | `water_grip_loss_per_mm: 0.05`, `water_grip_floor: 0.80` | TBD/experimental |

**Permanece distinto en cada coche — `VEHICLE_*`:**

| Parámetro | Mini Cooper S | Lancia Stratos HF | Por qué |
|---|---|---|---|
| `front.radius` / `rear.radius` | 0.2500 / 0.2500 | 0.3192 / 0.3192 | Geometría del coche |
| `front.width` / `rear.width` | 0.1500 / 0.1500 | 0.2280 / 0.3180 | Geometría; el Stratos es más ancho detrás |
| `rim_diameter_inches` | 13.0 | 13.0 | Coincide hoy, pero es del coche |
| `wheel_mass` (f/r) | 20.0 / 20.0 | 20.0 / 20.0 | Coincide hoy; sigue siendo del coche |
| `sidewall_m` = `radius − 0.1651` | **0.0849** | **0.1541** | Derivado del radio y la llanta |
| `geometry_scale` (fórmula `tire_radial_model.gd:32-35`) | `(0.150/0.2)·(0.1149/0.0849) = 1.0150` | delantero `(0.228/0.2)·(0.1149/0.1541) = 0.8500`; trasero `(0.318/0.2)·(0.1149/0.1541) = 1.1855` | Escala la rigidez radial |
| `carcass_stiffness` efectiva a 60 °C | `30000·1.0150 = 30 450 N/m` | `25 500 N/m` (F) / `35 566 N/m` (R) | Consecuencia del anterior |
| `pressure_stiffness` a 180 kPa | `666.667·180·1.0150 = 121 802 N/m` | `102 001 N/m` (F) / `142 265 N/m` (R) | ídem |
| `maximum_tire_deflection_m` | `0.0849 m` | `0.1541 m` | Limita la deflexión (`tire_model.gd:215,357`) |
| `force_model.rear` | v2 activo, `m_lat 0.15`, `m_lon 0.08` | v2 activo, `m_lat 0.15`, `m_lon 0.08` | Coincide hoy **vía `tire_filters.json`**, no por diseño del tipo |
| `surfaces.Gravel.longitudinal_grip_ratio` | 0.92 (F) / 1.0 (R) | 0.92 (F) / 1.0 (R) | Coincide hoy; es calibración por eje |
| `pressure.cold_kpa_gauge` | 180 / 180 / 180 / 180 | 180 / 180 / 180 / 180 | Reglaje del coche |
| Masa total y reparto (vía `mass_model`) | distinta | distinta | De `chassis.json` + `manifest.json` |

**Lectura del ejemplo:** con `snow_studded` sobre `Ice`, la **banda térmica, la curva de clavos y el factor de hielo** son comunes; la **rigidez radial, la deflexión máxima, la inercia de rueda y la calibración de equilibrio** siguen siendo del coche. Un test de aceptación (§10.2) comprueba exactamente estas filas: mismos valores donde dice «tipo», valores originales donde dice «coche».

---

## 5. Catálogo v2

### 5.1 Estructura propuesta

Archivo nuevo `game/data/tires/rally_compounds_v2.json` (el v1 **no se sobrescribe** hasta la fase 6). Esquema en `game/data/tires/rally_compounds_v2.schema.json` (JSON Schema 2020-12, subconjunto).

```
format_version: 2
catalog_id: "rally_tires"
catalog_version: 2
physics_contract_version: 2         # entra en rules_hash en lugar del sha crudo
units: { ... }                      # se heredan del v1 + snow_depth_m, density
families: { gravel, asphalt, mud, snow_ice }
types: { <type_id>: { ... } }
surface_modifiers: { <base_material>: {...}, <layer>: {...} }
studs: { <preset_id>: {...} }
inventory: { capacity, default_spare_count, mass_component_name }
durability_life_scale: 0.425
aliases: { <legacy_or_alias_id>: <canonical_id> }
```

### 5.2 Los seis tipos iniciales

| `type_id` | `family` | Estado | Uso |
|---|---|---|---|
| `gravel_normal` | `gravel` | **verificado** (v1 línea 16) | Rusia, Kenia, Finlandia, Suecia (opción) |
| `gravel_wet` | `gravel` | **verificado** (v1 línea 61) | Rusia, Kenia, Finlandia |
| `asphalt_dry` | `asphalt` | nuevo | Suiza |
| `asphalt_wet` | `asphalt` | nuevo | Suiza |
| `mud` | `mud` | nuevo | barro Kenia/Finlandia (§12 D-6) |
| `snow_studded` | `snow_ice` | nuevo | Suecia |

«Familia» = agrupación física (goma/dibujo base). «Tipo» = entrada conmutables por evento. Un tipo futuro `winter_mixed` debe caber en `snow_ice` sin tocar el solver.

### 5.3 Esquema de un tipo (fragmento)

```json
{
  "snow_studded": {
    "family": "snow_ice",
    "label": "Nieve con clavos",
    "short_label": "CLAVOS",
    "fitment": { "requires": ["studs"], "min_rim_inches": 12, "max_rim_inches": 15 },
    "rubber": {
      "tread_optimum_c": 16.0,
      "tread_window_c": 38.0,
      "overheat_tread_c": 70.0,
      "carcass_optimum_c": 35.0,
      "cold_grip_ramp_c": 25.0,
      "cold_grip_floor": 0.85,
      "overheat_grip_loss": 0.30,
      "wear_grip_loss": 0.30,
      "thermal_damage_grip_loss": 0.25
    },
    "thermal": {
      "tread_zone_heat_capacity_j_k": 6000.0,
      "carcass_heat_capacity_j_k": 17500.0,
      "gas_heat_capacity_j_k": 2200.0,
      "tread_to_carcass_w_k": 58.0,
      "carcass_to_gas_w_k": 24.0,
      "tread_to_air_w_k": 28.0,
      "carcass_to_air_w_k": 14.0,
      "road_conductance_w_k": 52.0,
      "lateral_tread_conductance_w_k": 24.0,
      "slip_heat_efficiency": 0.42,
      "carcass_hysteresis_efficiency": 0.55,
      "deformation_heating_dry": 1.0,
      "deformation_heating_wet": 1.0,
      "water_cooling_gain": 1.1,
      "snow_cooling_gain": 0.85,
      "tread_temperature_scale": 1.0,
      "carcass_temperature_scale": 0.90
    },
    "drainage": {
      "water_grip_loss_per_mm": 0.05,
      "water_grip_floor": 0.80,
      "snow_grip_loss_per_mm": 0.04,
      "snow_grip_floor": 0.70,
      "water_evacuation_efficiency": 0.45
    },
    "surface_response": {
      "Gravel":  { "mu_multiplier": 0.88, "peak_lat_multiplier": 0.95 },
      "Road":    { "mu_multiplier": 0.72, "wear_multiplier": 2.6 },
      "Dirt":    { "mu_multiplier": 0.90, "wear_multiplier": 1.4 },
      "Grass":   { "mu_multiplier": 0.85, "wear_multiplier": 0.8 },
      "Sand":    { "mu_multiplier": 0.90, "wear_multiplier": 1.0 }
    },
    "layers": {
      "snow_loose":  { "mu_multiplier": 1.00, "rolling_multiplier": 1.9, "penetration_gain": 1.0 },
      "snow_packed": { "mu_multiplier": 1.05, "rolling_multiplier": 1.15 },
      "ice":         { "mu_multiplier_rubber": 0.34, "mu_multiplier_studded": 0.84 },
      "slush":       { "mu_multiplier": 0.72, "rolling_multiplier": 2.4, "drainage_cost": 1.0 }
    },
    "studs": { "preset": "period_1974_light", "integrity_initial": 1.0 },
    "wear": {
      "wear_per_j": 1.2e-08,
      "dry_wear_multiplier": 1.25,
      "wet_wear_multiplier": 0.9,
      "thermal_damage_start_c": 70.0,
      "thermal_damage_excess_reference_c": 18.0,
      "thermal_damage_exponent": 2.0,
      "thermal_damage_rate_per_s": 0.0005
    },
    "labels": {
      "advantages": "Tracción sobre hielo y nieve compactada",
      "drawbacks": "Desgaste acelerado y menor agarre sobre asfalto/grava descubiertos"
    }
  }
}
```

**Nota de honestidad física:** los valores numéricos marcados arriba son **TBD/experimental** (§5.6). No se presentan como medidos.

### 5.4 Modificadores por capa (bloque `surface_modifiers`)

```json
{
  "layers": {
    "water": {
      "enabled_when": "liquid_water_mm > 0.0",
      "factor": "clamp(1 - water_grip_loss_per_mm * liquid_water_mm, water_grip_floor, 1)",
      "owner": "type",
      "units": { "liquid_water_mm": "mm" }
    },
    "snow_loose": {
      "enabled_when": "loose_fraction > 0.0",
      "factor": "1 - snow_loose_mu_loss * loose_fraction",
      "owner": "type+surface",
      "units": { "loose_fraction": "fraction_0_1" }
    },
    "snow_packed": { "enabled_when": "packed_fraction > 0.0", "factor": "1 - snow_packed_mu_loss * packed_fraction", "owner": "type+surface" },
    "ice":         { "enabled_when": "ice_fraction > 0.0",    "factor": "lerp(f_ice_rubber, f_ice_studded, stud_effectiveness) aplicado solo sobre la fracción de hielo", "owner": "type+surface" },
    "slush":       { "enabled_when": "slush_fraction > 0.0", "factor": "1 - slush_mu_loss * slush_fraction", "owner": "type+surface" },
    "ground_cold": { "enabled_when": "surface_temperature_c < 5.0", "factor": "lerp(0.92,1.0,(T+5)/10) — idéntico al actual", "owner": "surface" }
  }
}
```

### 5.5 Migración v1 → v2 (sin cambio de física)

Cada compuesto de v1 tiene **43 claves, de las cuales 36 son numéricas** y 7 son de presentación (`label`, `short_label`, `for_gravel`, `is_asphalt_tire`, `advantages`, `drawbacks`, `pressure_response_note`). Verificado por conteo directo sobre `rally_compounds.json`. El tipo `gravel_normal`/`gravel_wet` de v2 debe reproducir **exactamente** las 36 numéricas y conservar las 7 de presentación. Procedimiento:

1. Copiar los dos bloques de v1 tal cual dentro de `types`.
2. Añadir `family`, `rubber`, `thermal`, `drainage`, `surface_response`, `layers`, `wear`, `labels` **como vistas** de las mismas claves (no renombrar in situ). El cargador expone una **vista v1** (`as_v1_fields()`) que devuelve los nombres antiguos, de modo que `TireModel` y `VehicleThermalModel` sigan leyendo `tread_optimum_c` etc. sin cambios en Fase 1.
3. `surface_response.*.mu_multiplier = 1.0` y `layers.*` sin efecto para los dos tipos heredados en Fase 1; sus pérdidas reales siguen viniendo de `water_grip_loss_per_mm`/`snow_grip_loss_per_mm` (que en Fase 2 pasan a ser la implementación del bloque `layers.water`/`layers.snow`).
4. `validate_catalog()` exige `format_version == 2`, `catalog_version` entero creciente y que `gravel_normal`/`gravel_wet` existan.

**Prueba de migración:** `tire_catalog_migration_contract.gd` compara, campo a campo, `v1["compounds"][id]` contra `v2.types[id].as_v1_fields()`; tolerancia 0 exacta en las 43 claves (36 numéricas + 7 de texto/booleano).

### 5.6 Valores TBD y procedimiento de calibración

Todo valor marcado TBD sigue esta plantilla en el JSON:

```json
{ "value": 16.0, "status": "tbd", "range": [12.0, 20.0], "source": "reasoning: compuesto blando de invierno, no medido", "procedure": "sweep_thermal_window" }
```

| Parámetro | Rango | Razonamiento (no medición) | Procedimiento de ajuste |
|---|---|---|---|
| `tread_optimum_c` (nieve) | 12–20 | El compuesto de invierno se formula para trabajar frío; por encima de la ventana la goma se ablanda y pierde bloques | Barrido 0–80 °C con `tire_grip_factor` y comparar contra `gravel_normal` a 50 °C; fijar el óptimo donde la curva cruce el 95 % de su máximo con `surface_temperature_c = −5 °C` |
| `tread_window_c` | 30–45 | Debe ser más ancha que la de grava (50) porque la temperatura de superficie invernal oscila | Ajustar hasta que `|dT| = 20 °C` desde el óptimo produzca ≤ 8 % de pérdida |
| `f_ice_rubber` | 0.30–0.38 | Goma sobre hielo es el caso peor del sistema; el valor actual de `Grass` (0.70) es demasiado alto | Barrido de frenada 30→0 km/h sobre `Ice` con `snow_studded` sin clavos; objetivo: distancia de frenado 2.2–2.8× la de `asphalt_dry` |
| `f_ice_studded` | 0.75–0.92 | Los clavos deben recuperar buena parte del agarre, sin superar nunca el techo de asfalto | Mismo barrido con `stud_integrity = 1`; objetivo: 0.9–1.3× la distancia de `asphalt_dry` |
| `stud_wear_per_km_bare` | 0.02–0.08 /km | Pérdida progresiva por kilómetro sobre superficie dura | Recorrer 50 km de `Road` y exigir `stud_integrity` entre 0.3 y 0.7 |
| `snow_density_kg_m3` | 100–400 | Nieve recién caída ≈100, compactada ≈400 | Ajustar con `snow_depth_m` observado en GLB de Suecia (pendiente, §12 D-9) |

**Regla:** ningún valor TBD puede entrar a producción marcado como verificado. `validate_catalog()` debe rechazar `status: "verified"` sin un campo `source` que referencie una medición o una cita.

### 5.7 Validación y errores

`validate_catalog(catalog) -> ValidationReport` con códigos estables:

| Código | Condición |
|---|---|
| `E_FORMAT_VERSION` | `format_version != 2` |
| `E_MISSING_TYPE` | falta `gravel_normal` o `gravel_wet` |
| `E_UNKNOWN_FAMILY` | `family` fuera del enum `{gravel, asphalt, mud, snow_ice}` |
| `E_UNKNOWN_SURFACE` | clave en `surface_response` o `layers` que no existe en el enum de materiales/capas |
| `E_RANGE` | valor fuera de `min`/`max` declarado o no finito |
| `E_FITMENT` | `fitment.min_rim_inches > max_rim_inches`, o `requires: ["studs"]` sin bloque `studs` |
| `E_TBD_UNSOURCED` | `status == "verified"` sin `source` |
| `E_ALIAS_CYCLE` | alias que apunta a sí mismo o cadena cíclica |
| `E_DUPLICATE_ID` | ID repetido entre `types` y `aliases` destino |
| `E_UNITS` | unidad declarada distinta de la del bloque `units` global |

En runtime, el cargador **no degrada**: si `validate_catalog` falla, `load_catalog()` devuelve `{ok:false, errors:[...]}` y el llamador debe abortar la sesión con mensaje visible. Se elimina el patrón actual `is_valid() ? id : "gravel_normal"`.

---

## 6. Contratos de las APIs

### 6.1 `RallyTireCatalog` (`game/scripts/rally/rally_tire_catalog.gd`, nuevo)

```gdscript
class_name RallyTireCatalog
extends RefCounted

const CATALOG_PATH := "res://data/tires/rally_compounds_v2.json"
const LEGACY_PATH := "res://data/tires/rally_compounds.json"

# Carga única por proceso, cacheada por (path, sha256 del archivo).
# Devuelve { ok, catalog, errors, hash, catalog_version }
static func load_catalog(path: String = CATALOG_PATH) -> Dictionary

# Tipo ya validado y con herencia de familia resuelta.
# Devuelve {} si el ID no existe o es alias no resoluble.
static func get_type(catalog: Dictionary, type_id: String) -> Dictionary

static func is_valid(catalog: Dictionary, type_id: String) -> bool

# Lista canónica para un evento; orden estable (catálogo).
# rules = event_doc.tire_rules
static func list_for_event(catalog: Dictionary, rules: Dictionary) -> Array[String]

# Validador completo; NUNCA sustituye IDs.
static func validate_catalog(catalog: Dictionary) -> Dictionary   # { ok, errors[] }

# Alias/migración: devuelve el ID canónico o "" si no hay regla.
static func resolve_alias(catalog: Dictionary, raw_id: String) -> String

# Vista compatible v1 para el código no migrado (Fase 1-2).
static func as_v1_fields(catalog: Dictionary, type_id: String) -> Dictionary

static func clear_cache() -> void
```

**Reglas de contrato**
- `load_catalog` es la **única** puerta de lectura de JSON de neumáticos en producción. Las 6 llamadas actuales a `RallyTireCompound.load_catalog()` se redirigen aquí.
- Caché estática con clave `hash`. Sin invalidación por frame; `clear_cache()` solo para tests.
- `get_type` devuelve `duplicate(true)`; el llamador no puede mutar el catálogo.
- Error explícito: `is_valid` **no** sustituye. Quien necesite el valor por defecto lo pide a `rules.default_compound_id` (§6.3).

### 6.2 `TireTypeAssignment` (`game/scripts/rally/rally_tire_assignment.gd`, nuevo)

Autoridad única de «qué tipo lleva cada rueda». Reemplaza la ambigüedad `active_compound_id` vs `wheel_compounds[i].id`.

```gdscript
class_name TireTypeAssignment
extends RefCounted

var per_wheel: Array[String] = ["", "", "", ""]   # índice 0..3 = FL,FR,RL,RR
var primary: String = ""                           # explícito, nunca derivado por mayoría
var source: String = ""                            # "event_default" | "garage" | "service" | "restore"

func set_all(type_id: String) -> void
func set_wheel(index: int, type_id: String) -> void
func get_wheel(index: int) -> String
func is_uniform() -> bool
func snapshot() -> Dictionary      # {per_wheel, primary, source}
func validate(catalog: Dictionary) -> Dictionary   # {ok, errors[]}
```

`primary` lo fija la UI o el evento; **no** se infiere. Si las ruedas no son uniformes, `primary` se conserva como el tipo declarado y `is_uniform()` es `false` (la UI debe mostrarlo).

### 6.3 `TireParameterResolver` (`game/scripts/physics/tire_parameter_resolver.gd`, nuevo)

Función **pura**: no escribe en `domains`, `tires.json`, catálogo ni estado del vehículo.

```gdscript
class_name TireParameterResolver
extends RefCounted

# Precalculado UNA vez por montaje/servicio. Inmutable.
class MountedTire:
    var index: int
    var type_id: String
    var axle: String                     # "front" | "rear"
    var vehicle_nominal: Dictionary      # copia profunda de tires.json (nunca se escribe)
    var force_profile: Dictionary        # resolved_filters.front/rear (nunca se escribe)
    var type: Dictionary                 # copia del tipo validado
    var thermal_envelope: Dictionary     # banda, capacidades, conductancias efectivas
    var capacities_ratio: Dictionary     # longitudinal_ratio, lateral_assist del eje
    var provenance: Dictionary           # de dónde salió cada campo

static func mount(
    index: int,
    type_id: String,
    vehicle_domains: Dictionary,
    resolved_tire_filters: Dictionary,
    catalog: Dictionary,
) -> MountedTire

# Por contacto. Devuelve factores, NO fuerzas.
static func contact(
    mounted: MountedTire,
    base_material: String,          # "Gravel"|"Dirt"|"Road"|"Grass"|"Sand"
    layers: Dictionary,             # ver §7.1
    load_n: float,
    stud_integrity: float,
    thermal_state: Dictionary,      # {tread_c, carcass_c, wear_fraction, thermal_damage_fraction}
    pressure_kpa: float,
) -> Dictionary
# -> {
#      "mu_multiplier": float,
#      "longitudinal_ratio": float,
#      "lateral_bonus": float,
#      "stiffness_multiplier": float,
#      "rolling_multiplier": float,
#      "peak_lat_multiplier": float,
#      "peak_lon_multiplier": float,
#      "falloff_multiplier": float,
#      "heat_generation_multiplier": float,
#      "wear_multiplier": float,
#      "stud_effective_fraction": float,
#      "stud_bare_exposure": float,
#      "contributions": [ {"phenomenon": "water", "source": "type:gravel_wet", "factor": 0.86} ],
#    }
```

**Invariantes verificables por test (§10.4):**
1. `contact()` no muta `mounted`, ni `vehicle_domains`, ni el catálogo (hash de los tres antes/después).
2. `contributions` no contiene dos entradas con el mismo `phenomenon` y distinto `source` (una sola contribución por fenómeno).
3. Todos los `factor` de una misma `phenomenon` están dentro del rango declarado en el catálogo.
4. `mu_multiplier` nunca deja `mu` efectivo por encima del `surface.friction` del vehículo multiplicado por `(1 + max_boost)` declarado; el boost máximo permitido es `1.0` (ningún tipo añade agarre sobre el nominal salvo clavos en hielo, y ese efecto entra en la capa `ice`, no como boost global).

### 6.4 Qué se precalcula y qué se calcula por contacto

| Etapa | Cuándo | Qué | Coste |
|---|---|---|---|
| `mount()` | al montar/cambiar neumático, al cargar stage, al restaurar inventario | tipo validado, banda térmica efectiva, `longitudinal_ratio`/`lateral_assist` del eje, `peak_*_multiplier`, `falloff_multiplier`, tabla de `layers` indexada por material | 1 por rueda; admite JSON ya cacheado |
| `contact()` | cada subpaso de física, por rueda | interpolar factores de capa, `stud_effective_fraction`, multiplicadores de desgaste/calor | O(#capas activas ≤ 4), sin allocations grandes: devolver un `Dictionary` reutilizable o un `PackedFloat32Array` de campos fijos |
| `TireModel.evaluate()` | cada subpaso | se aplica `mu_multiplier` etc. y se conserva toda la matemática actual | sin cambios de orden |

**Prohibido en el bucle de física:** `FileAccess`, `JSON.parse_string`, `duplicate(true)` del catálogo, `load()`, búsquedas lineales sobre el catálogo entero. El resolver recibe la `MountedTire` ya materializada.

### 6.5 `TireModel` — cambios de contrato (mínimos)

```gdscript
# API deprecada, se conserva como adaptador hasta Fase 6:
func set_compound(type_id: String, catalog: Dictionary = {}) -> void   # deja de validar; delega

# Nuevo:
func set_mounted(index: int, mounted: TireParameterResolver.MountedTire) -> void
func get_mounted(index: int) -> TireParameterResolver.MountedTire

# evaluate() conserva la firma pública y añade los factores del resolver:
func evaluate(index, normal_load_n, surface_name, v_long, v_lat, wheel_speed, radius,
              camber, thermal_grip_factor, pressure_kpa, delta, carcass_c,
              water_mm := 0.0, snow_mm := 0.0, ground_c := 30.0,
              layer_state: Dictionary = {}) -> Dictionary
```

- `set_compound()` deja de escribir `axle_optimal_carcass_c` (línea 68-69): ese efecto pasa al resolver, que lo entrega al modelo térmico.
- La composición exacta de `mu` (línea 421-425) se mantiene; el resolver **solo** sustituye `compound_mult` por el producto de factores de capa y añade `stiffness/rolling/peak/falloff` como multiplicadores donde ya existen esos términos.

### 6.6 `VehicleThermalModel` — cambios de contrato

```gdscript
# Nuevo: configuración resuelta por rueda, sin tocar tire_config*
func resolved_axle_config(index: int) -> Dictionary

# Nuevo: aplica el sobre de banda térmica del tipo sin mutar la base
func set_mounted(index: int, mounted: TireParameterResolver.MountedTire) -> void

# Deprecado: mantiene la firma pero deja de escribir tire_config*
func set_compound(type_id: String, catalog: Dictionary = {}) -> void
```

- `_apply_compound_to_configs()` (`thermal_model.gd:145-166`) se **elimina** y su efecto se mueve a `resolved_axle_config()`.
- `_axle_tire_config()` (`:692-703`) pasa a construir desde `tire_config_*` (base inmutable) + `mounted.thermal_envelope`. El alias mapping de la línea 696 se conserva para las claves v1 durante la transición.
- `reset_for_stage()` (`:169-215`) conserva su contrato: conserva `wear_fraction`, `thermal_damage_fraction`, `leak_per_second`, `rim_deformation`, `carcass_failure`, `pressure_loss_fraction` y reconstruye temperaturas/presiones.
- Se añade `stud_integrity` a los campos conservados (Fase 5).

### 6.7 Contrato de no-mutación (verificable)

```gdscript
# Test obligatorio en cada PR de Fase 2:
var before := [tires_doc.sha256(), filters_doc.sha256(), JSON.stringify(domains).sha256()]
resolver.contact(...)
var after := [tires_doc.sha256(), filters_doc.sha256(), JSON.stringify(domains).sha256()]
assert(before == after)
```

### 6.8 Orden de precedencia formal

```
1. fitment del coche           (¿puede montar este tipo? radio/llanta) → bloquea, no modifica
2. vehículo/eje nominal        (tires.json + tire_filters.json)         → base inmutable
3. tipo de neumático           (catálogo: bandas, factores, clavos)     → multiplica/acota, no sustituye
4. material base + capas       (superficie física, un factor por capa)  → multiplica
5. estado dinámico por rueda   (presión, T, desgaste, daño, clavos)     → multiplica
6. solver                      (brush elíptico, presupuesto Fx/Fy)      → satura
7. contabilidad              (energía, potencia, desgaste)              → consume una vez
```

Cada nivel **solo** puede reducir el efecto del anterior o acotarlo; ninguno puede introducir una fuerza lateral nueva ni exceder el presupuesto.

---

## 7. Modelo de nieve, hielo y clavos

### 7.1 Estados y unidades

`RallySurfaceModel` pasa de 5 variables por zona a un bloque con invariantes explícitas. Todo por zona (3 por etapa), con `snapshot()` versionado.

| Campo | Unidad | Rango | Invariante |
|---|---|---|---|
| `base_material` | enum `{Gravel, Dirt, Road, Grass, Sand}` | — | Exactamente uno; nunca `Snow`/`Ice` como base |
| `base_fraction` | fracción 0–1 | 0–1 | `= 1 - Σ layer_fraction`, recalculado al leer |
| `snow_loose_fraction` | fracción 0–1 | 0–1 | |
| `snow_packed_fraction` | fracción 0–1 | 0–1 | |
| `ice_fraction` | fracción 0–1 | 0–1 | |
| `slush_fraction` | fracción 0–1 | 0–1 | |
| `snow_we_mm` | mm equivalente de agua | 0–60 | **Es el `snow_mm` actual**; no se reinterpreta |
| `snow_density_kg_m3` | kg/m³ | 100–500 | |
| `snow_depth_m` | m | derivado | `= (snow_we_mm / 1000) · (1000 / snow_density_kg_m3)` |
| `liquid_water_mm` | mm | 0–15 | Es el `water_mm` actual |
| `saturation` | fracción 0–1 | 0–1 | |
| `surface_temperature_c` | °C | −25–55 | Es el `ground_c` actual |
| `ice_texture` | enum `{none, glare, rough, polished_wet}` | — | |
| `precipitation_kind` | enum `{none, rain, snow, mixed}` | — | existente |

**Invariante de suma:** `snow_loose + snow_packed + ice + slush ≤ 1 + 1e-6`. Si se supera, `normalize_layers()` reescala proporcionalmente y registra `layer_normalization_events` en telemetría (nunca silencioso: contador visible en el snapshot).

**Invariante de clasificación:** las capas son **propiedades del contacto**, no clases de colisión. `base_material` viene del collider (Fase 3); las capas vienen del estado de zona del controlador climático. Esto evita duplicar el número de cuerpos físicos y permite que dos ruedas vean capas distintas en la misma zona.

### 7.2 Conversión WE ↔ profundidad (nunca reinterpretación silenciosa)

El v1 ya declara `"snow": "mm_water_equivalent"` (`rally_compounds.json:9`) y el plan **conserva** esa semántica. La profundidad geométrica es un campo **nuevo y derivado**:

```gdscript
func snow_depth_m(state: Dictionary) -> float:
    var we_mm := clampf(float(state.get("snow_we_mm", 0.0)), 0.0, 60.0)
    var rho := clampf(float(state.get("snow_density_kg_m3", 250.0)), 100.0, 500.0)
    return we_mm * 0.001 * (1000.0 / rho)
```

Migración del save: el `snow_mm` guardado se **lee como `snow_we_mm`** con `migration: "v1_snow_mm_is_we"` registrada en el snapshot. No se multiplica ni divide por densidad al migrar. Si un save antiguo tuviera un `snow_mm` que el autor quería como profundidad, es un error de datos del save, no del modelo: se documenta y no se adivina.

### 7.3 Composición de la fricción (una sola vez por fenómeno)

```
# Nivel 3-4: el resolver devuelve factores; no fuerzas.
mu_base        = vehicle.surfaces[base_material].friction           # coche
mu_type_env    = Π f_layer(type, layer_state)   para capas activas  # tipo×capa
mu_ground      = ground_factor(surface_temperature_c)               # superficie (idéntico al actual)
mu_load        = clamp(pow(load_ratio, -load_exp), 0.60, 1.20)      # coche
mu_thermal     = clamp(tire_grip_factor, 0.05, 1.0)                 # estado (ya incluye T, desgaste, daño)

mu_eff         = mu_base * mu_type_env * mu_ground * mu_load * mu_thermal

fx_capacity    = max(mu_eff * longitudinal_ratio * Fz, 1e-6)
fy_capacity    = max(mu_eff * (1 + lateral_assist) * Fz, 1e-6)
```

Diferencias con el código actual, todas intencionales y enumeradas:
- `mu_ground` sale de `compound_water_snow_ground_factor()` al resolver (misma fórmula, `tire_model.gd:79-84`) — **no cambia** números.
- `mu_type_env` para `gravel_normal`/`gravel_wet` reproduce `water_factor · snow_factor` exactamente: `f_water = max(1 - 0.16·w, 0.55)`, `f_snow = max(1 - 0.10·s, 0.60)` (`rally_compounds.json:43-46`).
- `lateral_assist` **sigue viniendo del vehículo**; el tipo no añade asistencia lateral (§7.5).

**Prueba de no doble conteo:** `contributions` debe contener exactamente una entrada `phenomenon == "water"` por evaluación. El test lo asserta por fuerza bruta sobre 1 000 combinaciones aleatorias de `(water_mm, snow_we_mm, ice_fraction, T)`.

### 7.4 Hielo: goma + clavos dentro de la capacidad elíptica

```gdscript
# Sólo afecta a la fracción de hielo del contacto.
func ice_factor(type: Dictionary, stud_integrity: float, ice_fraction: float,
                load_n: float, ice_texture: String) -> float:
    var f_rubber := float(type.layers.ice.mu_multiplier_rubber)      # p.ej. 0.34
    var f_studded := float(type.layers.ice.mu_multiplier_studded)    # p.ej. 0.84
    var eff := stud_effectiveness(stud_integrity, ice_fraction, load_n, ice_texture)
    var f_ice := lerpf(f_rubber, f_studded, clampf(eff, 0.0, 1.0))
    # Mezcla con la fracción no-helada: una sola contribución
    return lerpf(1.0, f_ice, clampf(ice_fraction, 0.0, 1.0))

func stud_effectiveness(integrity: float, ice_fraction: float, load_n: float,
                        texture: String) -> float:
    var integrity_f := clampf(integrity, 0.0, 1.0)
    var access_f := clampf(ice_fraction, 0.0, 1.0)          # sin hielo accesible no hay ventaja
    var texture_f := {"none": 0.0, "glare": 1.0, "rough": 0.85, "polished_wet": 0.55}
                     .get(texture, 0.0)
    # La carga modera: a muy poca carga los clavos no penetran.
    var load_f := clampf(load_n / 2500.0, 0.35, 1.10)
    return integrity_f * access_f * float(texture_f) * load_f
```

- **No hay fuerza lateral extra.** El efecto es un factor sobre `mu_eff` que entra en `fy_capacity` por la vía normal.
- **No se equipara nieve compactada a hielo:** `snow_packed` tiene su propio `mu_multiplier` (≈1.05 sobre el material base, es decir *mejor* que nieve suelta) y su propio `rolling_multiplier`.
- Sobre nieve compactada, los clavos aportan solo si `ice_fraction > 0` (hielo accesible bajo la nieve); si no, `access_f = 0` y no hay bonificación.

### 7.5 Nieve suelta: resistencia al avance, no bonificación lateral

```gdscript
# Nieve suelta: más coste de rodadura y menos capacidad, pero sin "grip gratis".
rolling_multiplier *= 1.0 + float(type.layers.snow_loose.rolling_multiplier - 1.0) * loose_fraction
mu_eff            *= lerpf(1.0, float(type.layers.snow_loose.mu_multiplier), loose_fraction)
# La compactación reduce el espesor y convierte fracción suelta en compactada:
packed += loose * compaction_rate * dt
loose  -= loose * compaction_rate * dt
```

El arrastre por nieve **no** se convierte en fuerza lateral: la energía se disipa en `state.friction_power` y en la resistencia de rodadura existente (`tire_model.gd:603-608`), nunca como `fy`.

### 7.6 Aguanieve y drenaje sin duplicar agua

Hoy hay triple cómputo potencial de agua:
1. `water_mm` del compuesto (`tire_model.gd:77`),
2. `water_mm = max(water_mm, puddle_depth_mm)` (`vehicle_simulation.gd:215`),
3. `PuddleModel.contact_response` aplicando soporte/arrastre (`vehicle_simulation.gd:824-831`).

Propuesta (Fase 4, con flag):

```gdscript
# Una sola fuente por fenómeno:
#  - "water": pérdida de mu por agua libre del contacto → SOLO el resolver (capa water)
#  - "hydro": arrastre/soporte por lámina de agua  → SOLO el modelo de charcos
#
# Regla: liquid_water_mm que ve el resolver EXCLUYE la profundidad de charco.
local["liquid_water_mm_resolver"] = max(0.0, local.water_mm - local.puddle_depth_mm)
```

Y `water_evacuation_efficiency` sustituye el literal:

```gdscript
# inv_eff = 1 / eficiencia ; eficiencia ∈ (0,1]
var inv_eff := 1.0 / maxf(float(type.drainage.water_evacuation_efficiency), 0.05)
PuddleModel.contact_response(..., inv_eff, ...)     # sustituye wet_tire: bool

# Dentro de contact_response (rally_puddles.gd:601-602):
# var evac_speed := BASE_EVAC_SPEED * clampf(inv_eff, 0.5, 3.0)   # BASE_EVAC_SPEED = 16.0
```

Para **paridad exacta** en Fase 4 con los dos tipos heredados:

| Tipo | `water_evacuation_efficiency` | `inv_eff` | `evac_speed` resultante | Hoy |
|---|---|---|---|---|
| `gravel_normal` | `0.5714` (= 16/28) | `1.750` | `16.0 · 1.750 = 28.0` | `28.0` (`rally_puddles.gd:601`) |
| `gravel_wet` | `1.0` | `1.000` | `16.0 · 1.000 = 16.0` | `16.0` |

La tolerancia del test de paridad es 1e-9 sobre `evac_speed`, y además se compara el `contact_response` completo (soporte long/lat, arrastre, slam) contra la línea base de Fase 0.

### 7.7 Evolución, deshielo y congelación

```gdscript
# Hielo: no aparece sólo porque T < 0. Requiere agua líquida y déficit térmico sostenido.
func ice_formation_step(zone: Dictionary, dt_s: float) -> Dictionary:
    var t_surface := float(zone.surface_temperature_c)
    var water := float(zone.liquid_water_mm)
    var frozen := 0.0
    if t_surface < ICE_FORM_BELOW_C and water > ICE_MIN_WATER_MM:      # histéresis
        var rate := ICE_FORM_RATE_PER_S * clampf((ICE_FORM_BELOW_C - t_surface) / 5.0, 0.0, 2.0)
        frozen = minf(water, rate * dt_s)
    elif t_surface > ICE_MELT_ABOVE_C and float(zone.ice_fraction) > 0.0:
        var melt := ICE_MELT_RATE_PER_S * clampf((t_surface - ICE_MELT_ABOVE_C) / 5.0, 0.0, 2.0)
        melt = minf(float(zone.ice_fraction), melt * dt_s)
        zone.ice_fraction -= melt
        zone.liquid_water_mm += melt * ICE_FRACTION_TO_MM
    zone.liquid_water_mm -= frozen
    zone.ice_fraction = clampf(zone.ice_fraction + frozen * MM_TO_ICE_FRACTION, 0.0, 1.0)
    return zone
```

Constantes con histéresis: `ICE_FORM_BELOW_C = -1.0`, `ICE_MELT_ABOVE_C = +0.5`, `ICE_MIN_WATER_MM = 0.05`, y todas marcadas **TBD** con procedimiento (§5.6). La histéresis de 1.5 °C evita parpadeo en el punto de congelación.

### 7.8 Clavos: estado por unidad y desgaste

| Campo | Unidad | Persistencia | Inicial |
|---|---|---|---|
| `stud_integrity` | fracción 0–1 | **sí** (en `TIRE_STATE_KEYS`) | 1.0 al montar un `snow_studded` nuevo |
| `stud_lost_count` | entero | sí (informativo) | 0 |
| `stud_bare_exposure_km` | km | sí | 0 |

```gdscript
func accumulate_stud_wear(state: Dictionary, dt: float, base_material: String,
                          slip_speed_m_s: float, load_n: float, friction_power_w: float,
                          type: Dictionary) -> void:
    var control := {"type": "studs", "phys": "complex"}
    var integrity := clampf(float(state.get("stud_integrity", 1.0)), 0.0, 1.0)
    var bare := 1.0 if base_material in ["Road", "Gravel", "Dirt", "Sand"] else 0.0
    var km := maxf(absf(slip_speed_m_s), 1.0) * dt / 1000.0
    var wear := 0.0
    wear += float(type.studs.wear_per_km_bare) * bare * km
    wear += float(type.studs.wear_per_mj_slip) * maxf(friction_power_w, 0.0) * dt * 1e-6 * bare
    # Integridad monótonamente no creciente; sólo servicio la restaura.
    state.stud_integrity = clampf(integrity - wear, 0.0, 1.0)
    if bare > 0.0:
        state.stud_bare_exposure_km = float(state.get("stud_bare_exposure_km", 0.0)) + km
```

Reglas:
- **Monótonamente no creciente** en conducción; solo sube con servicio/reemplazo (`fresh_tire_state`, `service_tire_inventory`).
- Se conserva al intercambiar ruedas entre montadas y repuestos (el estado viaja con el ítem del inventario, `rally_tire_inventory.gd:8-11`).
- Se persiste en `tire_inventory_state.mounted[i].state.stud_integrity` y se restaura con el resto (`rally_russia_stage_session.gd:1197-1201`).
- La degradación **no** ocurre si la rueda no tiene contacto con carga (`normal_load_n <= 0`).
- No se asume que el número ni la protrusión de clavos modernos correspondan a coches históricos: `stud_count_per_tire` y `stud_protrusion_mm` quedan como `preset` del tipo con estado `tbd` (§12 D-4).

### 7.9 Aproximaciones y límites declarados

- Mezcla de capas **lineal por fracción** con factor multiplicativo por capa; no es un modelo de contacto de dos cuerpos ni resuelve el hundimiento real del taco.
- La nieve suelta no modela excavación ni acumulación delante de la rueda; el coste se concentra en `rolling_multiplier`.
- El hielo es un factor de fricción dependiente de textura y clavos; no modela película de agua sobre hielo (eso queda en la capa `slush`).
- La densidad de nieve es constante por zona durante una etapa; no evoluciona por compactación real.
- La disipación se mantiene en `state.friction_power` y en la variación de `patch_energy_j` (`tire_model.gd:599-633`). Con multiplicadores variables, el balance es aproximado (ya lo era: `TIRE_PATCH_MEMORY.md:15`).
- **El diseño admite `winter_mixed`** sin tocar el solver: es un tipo más con `layers.*` ya existentes; solo añade un `family` `snow_ice` y valores.

---

## 8. Matriz de cobertura de 42 stages

### 8.1 Verificación del censo real

`game/data/competition/stages/` contiene **42 configuraciones** (10 Rusia + 8 Kenia + 8 Finlandia + 8 Suecia + 8 Suiza), confirmadas por `Get-ChildItem` y por `stages_explicit_order` de los 5 eventos. Los 5 eventos declaran `regional_profile_id`: `russia_summer`, `kenya_safari`, `finland_autumn`, `sweden_winter`, `switzerland_alpine`, y los 5 perfiles existen en `game/data/weather/rally_weather_presets.json:446-976`.

**Hallazgo crítico:** el metadato de etapa está **copiado en plantilla**. Los 34 stages no suizos declaran `surface: "gravel_mud"`, `roughness: 0.55`, `water: 0.15`, `wetness: 0.35`, `jumps: 0.45`, `night: false`; los 8 suizos declaran `surface: "asphalt"` con el resto idéntico. **Suecia no declara nieve.** Y `surface` no se usa para fricción en ningún sitio; solo `rally_competition.gd:293` lo usa como clave de afinidad del piloto (`ratings.get(stage.surface, ratings.gravel_mud)`).

### 8.2 Materiales viales reales por país (verificado en los GLB visuales)

| País | Materiales viales encontrados | Base física correcta |
|---|---|---|
| Rusia | `road_gravel_1`, `road_gravel_1_dif1/2`, `road_forest`, `road_field_1`, `road_field_1_cross`, `road_logging*`, `road_crossroad*`, `road_xturn`, `road_rock_big`, `railroad_*`, `roadbar1` | **Gravel / Dirt** (sin asfalto) |
| Kenia | `kenya_road_gravel_1*`, `kenya_road_to_jungle`, `kenya_river_road_1..3`, `jungle_road*`, `jungle_river_road*`, `kenya_river_dry_crossroad*` | **Gravel / Dirt** (sin asfalto) |
| Finlandia | `fin_road_dry`, `fin_road_field_1`, `fin_road_leaves*`, **`fin_road_tarmac`, `fin_road_tarmac_tcross`, `fin_road_tarmac_ycross1/2`, `fin_tarmac_cracks`, `fin_bridge_tarmac`** | **Mezcla Gravel + Road** (hay asfalto real) |
| Suecia | `road_snow_1/2/3`, `road_snow_1to2`, `road_snow_2to1`, `road_snow_3to1`, `road_snow_1_dif1`, `road_snow_2_dif1`, `road_snow_crossroad*`, `railroad_snow` | **Gravel base + capa de nieve** (la calzada está cubierta) |
| Suiza | `road_tarmac_1`, `road_tarmac_1var1`, `road_tunnel_1`, `road_tunnel_1change`, `bridgeroad1/2`, `road_crossroad` | **Road (asfalto)** |

### 8.3 Nodos de colisión por país (verificado en los 42 GLB)

| País | Nodos presentes | Observación |
|---|---|---|
| Rusia (10) | `Barriers, Buildings*, Props, Road, Terrain_Dirt*, Terrain_Grass, Tree_trunks` | `stage9` **no** tiene `Dirt`; `Buildings` falta en `stage9` |
| Kenia (8) | `Barriers, Buildings*, Props, Road, Terrain_Dirt, Terrain_Grass, Tree_trunks` | `stage1/3/4/5/7/8` sin `Buildings` |
| Finlandia (8) | `Barriers, Buildings*, Props, Road, Terrain_Dirt, **Terrain_Sand**, Tree_trunks` | **no hay `Terrain_Grass`**; `stage2/6` sin `Buildings` |
| Suecia (8) | `Barriers, Buildings*, Props, Road, Terrain_Dirt*, Terrain_Grass, Tree_trunks` | `stage8` **no** tiene `Dirt` |
| Suiza (8) | `Barriers, Buildings*, Props, Road, **Terrain_Grass**, Tree_trunks` | **no hay `Dirt` ni `Sand`** |

`Buildings` no recibe grupo de superficie (`rally_track_collision_builder.gd:133-143`: `role = "obstacle"`), correcto.

### 8.4 Contacto resultante hoy vs esperado

| País | Contacto actual (código) | Contacto esperado tras Fase 3 |
|---|---|---|
| Rusia | `Collision_Road → Gravel` ✅; terreno `Dirt/Grass`; `sand_erosion_*` → Dirt | igual, con `base_material` explícito y telemetría |
| Kenia | `Collision_Road → Gravel` ✅; `kenya_erosio_*` → Dirt | igual |
| Finlandia | `Collision_Road → Gravel` ❌ en los tramos `fin_road_tarmac*`; `Terrain_Sand` → Sand | tramos tarmac → `Road`; resto igual |
| Suecia | `Collision_Road → Gravel` ⚠️ (calzada nevada tratada como grava seca); `erosion_snow_*` → `Grass` (fricción 0.70, rodadura 3.5) ❌ | `base_material = Gravel` + capa `snow_packed`/`snow_loose`; `erosion_snow_*` = `Grass` + capa nieve profunda |
| Suiza | `Collision_Road → Gravel` ❌ **para los 8 stages**; `sand_erosion_*` → `Collision_Terrain_Dirt` (cuerpo nuevo en un rally sin Dirt) ❌ | `base_material = Road`; taludes → `Grass`/`Rock` según material |

### 8.5 Matriz de cobertura (agrupada por país; excepciones por stage anotadas)

| País | Stages | `surface` metadato | Materiales viales reales | Nodos colisión | Contacto hoy | Clima regional | Tipos permitidos propuestos |
|---|---|---|---|---|---|---|---|
| Rusia | `russia_stage1 … stage10` | `gravel_mud` (los 10) | gravel/forest/field/logging | Road, Dirt, Grass (+Sand vía talud), Barriers, Props, Buildings | Gravel | `russia_summer` | `gravel_normal` (def), `gravel_wet`, `mud` |
| Kenia | `kenya_stage1 … stage8` | `gravel_mud` | kenya_road_gravel, jungle_road, river_road | Road, Dirt, Grass, Barriers, Props, Tree_trunks | Gravel | `kenya_safari` | `gravel_normal` (def), `gravel_wet`, `mud` |
| Finlandia | `finland_stage1 … stage8` | `gravel_mud` | fin_road_dry, field, **tarmac**, leaves | Road, Dirt, **Sand**, Barriers, Props | Gravel (también en tarmac) | `finland_autumn` | `gravel_normal` (def), `gravel_wet`, `mud`, `asphalt_dry`*, `asphalt_wet`* |
| Suecia | `sweden_stage1 … stage8` | `gravel_mud` | **road_snow_*** | Road, Dirt (*no* stage8), Grass, Barriers, Props | Gravel seco + `erosion_snow_*`→Grass | `sweden_winter` | **`snow_studded` (def)**, `gravel_normal` |
| Suiza | `switzerland_stage1 … stage8` | **`asphalt`** | **road_tarmac_*, road_tunnel_*, bridgeroad*** | Road, **Grass**, Barriers, Props; sin Dirt/Sand | **Gravel** | `switzerland_alpine` | `asphalt_dry` (def), `asphalt_wet` |

\* `asphalt_dry`/`asphalt_wet` en Finlandia quedan como opción secundaria (hay tarmac real) y requieren decisión de producto (§12 D-6).

### 8.6 Fallos de correspondencia y su solución

| # | Fallo | Evidencia | Solución |
|---|---|---|---|
| F-1 | `Collision_Road` único para todos los materiales viales | `rally_track_collision_builder.gd:18` | Fase 3: mapeo material→base gobernado por taxonomía (§9 Fase 3), con *fallback* explícito contado |
| F-2 | Suiza sin asfalto | §8.2, §8.3 | Fase 3: `switzerland_*` → `base_material = Road` |
| F-3 | Suecia sin nieve | §8.2 | Fase 4: capa inicial de nieve desde `antecedent_policy.initial_snow_mm` (ya existe: `[1.0, 8.0]` en `rally_weather_presets.json:852-855`) + `road_snow_*` como evidencia de cobertura total |
| F-4 | `erosion_snow_*` → `Grass` plano | `rally_track_collision_builder.gd:95-96` | Fase 3: `Grass` + capa `snow_loose = 1.0` (banco de nieve) |
| F-5 | `sand_erosion_*` crea `Dirt` en Suiza | `rally_track_collision_builder.gd:91-92` | Fase 3: patrón por país; en Suiza → `Grass` |
| F-6 | `_profile_for_surface("Gravel")` fijo | `rally_surface_model.gd:138` | Fase 3: perfil por `base_material` de la zona (requiere que la zona conozca su material dominante; se deriva del mapeo por país) |
| F-7 | Sin contacto → `"Gravel"` | `vehicle_simulation.gd:741` | Fase 3: usar el último material conocido de la rueda; si no hay, `"Unknown"` y el resolver devuelve factores 1.0 sin penalizar |
| F-8 | Metadato `surface` no gobierna fricción | §8.1 | Documentado. El plan **no** hace que el metadato gobierne fricción; gobierna la *oferta de tipos* (§9 Fase 6) |
| F-9 | Cobertura de superficie al salir del camino | `rally_weather_controller.gd:138-139` mantiene la proyección | Fase 4: telemetría `offroad_contacts` y test de 4 ruedas con materiales distintos (§10.7) |

---

## 9. Plan fase por fase

### Convenciones

- **Ruta** siempre relativa a `D:\rust-godot-vehicle-simulator`.
- **Rollback** siempre por *feature flag* apagado + `git revert` del PR; ningún PR debe exigir migración de datos irreversible.
- **Aceptación** siempre verificable por comando (§10.0) o por número medido.
- Cada fase es **independiente**: se puede ejecutar sin las siguientes y sin romper las anteriores.

### 9.1 Fase 0 — Auditoría y paridad

| ID | Tarea | Ruta(s) | Depende | Riesgo | Test | Rollback | Aceptación |
|---|---|---|---|---|---|---|---|
| 0.1 | Congelar línea base: commit, árbol, hashes de los 15 `tires.json`/`tire_filters.json`, `rally_compounds.json`, manifiestos | `game/docs/rally/TIRE_BASELINE_v1.json` (nuevo) | — | Bajo | `OWNERSHIP_AUDIT` script | borrar archivo | El JSON lista 15 vehículos, 4 hashes cada uno, y su `git status` de origen |
| 0.2 | Generar matriz de propiedad automática | `tools/tires/audit_ownership.py` (nuevo) → `game/docs/rally/TIRE_OWNERSHIP_MATRIX.generated.md` | 0.1 | Bajo | ejecución idempotente | borrar | El md reproduce §4 con valores reales y detecta los 2 grupos de `force_model` |
| 0.3 | Test de paridad numérica legacy (golden) | `game/tests/rally/tire_legacy_parity_contract.gd` (nuevo), `game/tests/data/tire_parity_golden_v1.json` (nuevo) | 0.1 | Medio | §10.1 | borrar | Corre en < 60 s, 0 fallos, tolerancia 1e-9 |
| 0.4 | Resolver el test rojo `weather_runtime_regression` (§1.5) | `game/tests/rally/weather_runtime_regression.gd:72-77` **o** los `setup_windows` del evento | 0.3 | Bajo | el propio test | revert | El test pasa, o queda documentado con issue y sigue rojo **solo** si el usuario lo autoriza |
| 0.5 | Ejecutar y registrar `stage_export_import_test.gd` | — | — | Bajo | §10.13 | — | Resultado PASS/FAIL real anotado en el baseline |
| 0.6 | Congelar hash de `domains` por vehículo para detectar mutaciones | dentro de 0.3 | 0.3 | Bajo | 0.3 | — | 15 hashes registrados |

**Criterio de salida de Fase 0:** existe una foto numérica reproducible del comportamiento actual, con commit + árbol + tolerancias, y los 15 coches cubiertos.

### 9.2 Fase 1 — Catálogo v2 y validación (sin cambio de física)

| ID | Tarea | Ruta(s) | Depende | Riesgo | Test | Rollback | Aceptación |
|---|---|---|---|---|---|---|---|
| 1.1 | Esquema JSON + validador | `game/data/tires/rally_compounds_v2.schema.json`, `game/scripts/rally/rally_tire_catalog.gd` | 0.3 | Medio | `tire_catalog_validation_contract.gd` | flag `tire_catalog_v2` off → usa v1 | 10 códigos de error cubiertos, 1 caso válido, 1 por código inválido |
| 1.2 | Datos v2 con los 6 tipos y **vista v1 exacta** para los 2 heredados | `game/data/tires/rally_compounds_v2.json` | 1.1 | **Alto** (números) | `tire_catalog_migration_contract.gd` | volver a v1 | Las 43 claves de `gravel_*` coinciden con v1 (36 numéricas con tol 0) |
| 1.3 | **PR-02a:** `rules_hash` deja de usar el SHA crudo del catálogo | `game/scripts/rally/rally_weather_scheduler.gd:469-486` | — | **P0** | `save_rules_hash_contract.gd` | revert | Un save v3 existente sigue restaurando **después** de cambiar datos del catálogo (`catalog_version` igual) |
| 1.4 | Sustituir las 5 listas literales por `RallyTireCatalog.is_valid` con error explícito | `rally_tire_compound.gd:9`, `tire_model.gd:45`, `thermal_model.gd:130`, `vehicle_simulation.gd:178`, `rally_tire_inventory.gd:44` | 1.1 | Medio | `tire_catalog_ids_contract.gd` | flag off | 0 literales `["gravel_normal","gravel_wet"]` en `game/scripts` (grep vacío) |
| 1.5 | `resolve_alias` + migración de IDs | `rally_tire_catalog.gd` | 1.2 | Medio | incluido en 1.1 | flag off | Alias desconocido → error; alias conocido → canónico; sin bucles |
| 1.6 | Actualizar el test que fija 2 IDs | `game/tests/rally/dynamic_weather_tires_contract.gd:36` | 1.4 | Bajo | el propio test | conformarlo a `list_for_event` | El test compara contra `list_for_event` en vez de un literal |

**Criterio de salida:** `tire_legacy_parity_contract` sigue en 0 fallos con el catálogo v2 activo; ninguna prueba de física cambia de resultado.

### 9.3 Fase 2 — Resolver y wiring conservador

| ID | Tarea | Ruta(s) | Depende | Riesgo | Test | Rollback | Aceptación |
|---|---|---|---|---|---|---|---|
| 2.1 | `TireParameterResolver.mount/contact` | `game/scripts/physics/tire_parameter_resolver.gd` (nuevo) | 1.2 | Medio | `tire_resolver_contract.gd` | flag `tire_resolver` off | `contact()` no muta nada (hash antes/después) |
| 2.2 | `TireModel` consume el resolver; conserva brush/migración/presupuesto | `game/scripts/physics/tire_model.gd:44-84,258-425` | 2.1 | **Alto** | paridad §10.1 | flag off → ruta actual intacta | Paridad 1e-9 con `gravel_*`; `combined_migration_contract` PASS |
| 2.3 | `VehicleThermalModel`: config resuelta por rueda, **base inmutable** | `thermal_model.gd:129-166,692-703` | 2.1 | **P0-2** | `thermal_no_mutation_contract.gd` | flag off | `tire_config*` no cambia tras `set_mounted` (hash) |
| 2.4 | Eliminar la escritura de `axle_optimal_carcass_c` de `set_wheel_compound` | `tire_model.gd:63-69` | 2.2 | Medio | paridad por rueda | flag off | Rueda con tipo distinto: objetivo de carcasa coherente entre solver y térmico |
| 2.5 | `TireTypeAssignment` como autoridad única | `game/scripts/rally/rally_tire_assignment.gd` (nuevo), `rally_escort_vehicle.gd:248-253,780-811` | 2.1 | Medio | `tire_assignment_contract.gd` | flag off | `primary` explícito; sin mayoría |
| 2.6 | Unificar `grip_response` (dos implementaciones) | `rally_tire_compound.gd:39-76` | 2.1 | Medio | `dynamic_weather_tires_contract` sigue PASS | mantener ambas con delegación | Una sola fórmula; la otra delega |
| 2.7 | Documentar la composición en `PHYSICS_FILTERS.md` | `game/docs/rally/PHYSICS_FILTERS.md` | 2.2 | Bajo | revisión | — | El doc describe el orden real de §6.8 |

**Criterio de salida:** `gravel_normal`/`gravel_wet` idénticos bit a bit en los 15 coches, con el resolver activo y el catálogo v2.

### 9.4 Fase 3 — Clasificación física de superficies

| ID | Tarea | Ruta(s) | Depende | Riesgo | Test | Rollback | Aceptación |
|---|---|---|---|---|---|---|---|
| 3.1 | Taxonomía material→base, por país y patrón | `game/data/surfaces/material_surface_map.json` (nuevo) | 0.2 | Medio | `surface_taxonomy_contract.gd` | flag `surface_taxonomy` off | 100 % de materiales viales de §8.2 clasificados; 0 `unknown` |
| 3.2 | `RallyTrackCollisionBuilder` usa la taxonomía y `set_meta("surface_material")` | `rally_track_collision_builder.gd:13-22,89-99,139-143` | 3.1 | **P0-4** | `surface_classification_contract.gd` | flag off → tabla actual | Suiza → `Road`; Suecia → `Gravel`+capa; Finlandia tarmac → `Road` |
| 3.3 | `_surface_for_collider` lee `meta` primero y deja de caer a `Gravel` | `vehicle_simulation.gd:1096-1104` | 3.2 | Alto | `surface_fallback_contract.gd` | flag off | Nunca devuelve `Gravel` por defecto; `Unknown` explícito y contado |
| 3.4 | `_profile_for_surface` por material de zona | `rally_surface_model.gd:134-198` | 3.2 | Medio | `surface_thermal_profile_contract.gd` | flag off | Suiza usa el perfil `Road` (capacidad 1400, absorción 0.78) |
| 3.5 | Telemetría de clasificación | `rally_telemetry_recorder.gd:194` | 3.2 | Bajo | `surface_telemetry_contract.gd` | — | Snapshot por rueda: material, fracción de capas, `unknown_count` |
| 3.6 | Tests de clasificación por etapa real | `game/tests/rally/stage_surface_matrix_contract.gd` (nuevo) | 3.2 | Medio | §10.9 | — | 42/42 con material base esperado |

**Criterio de salida:** ninguna etapa reporta `Unknown` en el corredor de ruta; Suiza deja de usar fricción de grava.

### 9.5 Fase 4 — Capas invernales y estado meteorológico

| ID | Tarea | Ruta(s) | Depende | Riesgo | Test | Rollback | Aceptación |
|---|---|---|---|---|---|---|---|
| 4.1 | Estado de capas por zona + invariantes | `rally_surface_model.gd:33-47,96-118,134-198` | 3.2 | **Alto** | `surface_layers_contract.gd` | flag `winter_layers` off | `Σ fracciones ≤ 1+1e-6`; normalización contada |
| 4.2 | WE↔profundidad + densidad | `rally_surface_model.gd` (nuevo `snow_depth_m`) | 4.1 | Medio | `snow_depth_conversion_contract.gd` | flag off | `snow_mm` v1 se lee como `snow_we_mm` sin escalar |
| 4.3 | Hielo con histéresis (formación/derretimiento) | `rally_surface_model.gd` | 4.1 | Alto | `ice_hysteresis_contract.gd` | flag off | T<−1 durante 60 s con agua → hielo; T>+0.5 → derrite; nunca hielo con T=−0.1 |
| 4.4 | Aguanieve + drenaje por propiedad | `rally_surface_model.gd`, `rally_puddles.gd:578-620`, `vehicle_simulation.gd:814-823` | 4.1 | **Alto** | `slush_drainage_contract.gd` | flag off | `evac 0.571/1.0` reproduce 16/28 m/s exactos |
| 4.5 | Continuidad entre stages y persistencia de capas | `rally_surface_model.gd:206-212`, `rally_event_manager.gd:309-315,504` | 4.1 | Medio | `surface_continuity_contract.gd` | flag off | Guardar/reanudar conserva fracciones, densidad y T |
| 4.6 | Controlador expone capas por contacto | `rally_weather_controller.gd:241-259` | 4.1 | Medio | `weather_runtime_regression` (ya sin rojo) | flag off | 4 ruedas pueden ver capas distintas |
| 4.7 | Pausa/reglaje no avanzan capas | `rally_rally_event_clock` / `advance_ambient` | 4.5 | Bajo | incluido en 4.5 | — | `dt=0` no cambia estado |

**Criterio de salida:** Suecia arranca con nieve coherente con `initial_snow_mm [1.0, 8.0]` y `initial_ground_c [−6, 2]` ya presentes en el perfil; ninguna otra etapa cambia de comportamiento.

### 9.6 Fase 5 — `snow_studded` y clavos

| ID | Tarea | Ruta(s) | Depende | Riesgo | Test | Rollback | Aceptación |
|---|---|---|---|---|---|---|---|
| 5.1 | Bloque `studs` del catálogo + preset | `rally_compounds_v2.json`, `rally_tire_catalog.gd` | 4.1 | Medio | `stud_catalog_contract.gd` | flag `studs` off | Tipo inválido sin preset → `E_FITMENT` |
| 5.2 | `stud_integrity` en estado por rueda y en `TIRE_STATE_KEYS` | `rally_escort_vehicle.gd:24,813-822,840-855` | 5.1 | Medio | `stud_state_contract.gd` | flag off | Campo presente, default 1.0, conservado en intercambios |
| 5.3 | Desgaste de clavos | `thermal_model.gd` (nuevo `accumulate_stud_wear`) o `rally_escort_vehicle.gd` | 5.2 | Medio | `stud_wear_contract.gd` | flag off | Monótono no creciente; sin contacto no degrada; servicio restaura |
| 5.4 | Integración de fricción en `mu_eff` (no fuerza extra) | `tire_parameter_resolver.gd`, `tire_model.gd:421-434` | 4.3, 5.3 | **Alto** | `stud_friction_contract.gd` §10.6 | flag off | Hielo: ventaja medible; presupuesto elíptico intacto (§10.4) |
| 5.5 | Persistencia de clavos en save | `rally_russia_stage_session.gd:1194-1204`, `rally_tire_inventory.gd:36-54` | 5.2 | Medio | `stud_persistence_contract.gd` | flag off | Roundtrip exacto; save sin el campo → 1.0 |
| 5.6 | `snow_studded` disponible en Suecia para los 15 perfiles | `sweden_rally.json: tire_rules` | 5.1 | Bajo | `sweden_tire_offer_contract.gd` | revert JSON | Los 15 perfiles resuelven el tipo sin error de fitment |

**Criterio de salida:** un mismo `snow_studded` produce ventaja en hielo y desventaja en asfalto para los 15 coches, con sus radios/anchuras intactos.

### 9.7 Fase 6 — Integración de negocio

| ID | Tarea | Ruta(s) | Depende | Riesgo | Test | Rollback | Aceptación |
|---|---|---|---|---|---|---|---|
| 6.1 | `tire_rules` por evento (6 tipos según §8.5) | `game/data/competition/events/*.json` (5) | 1.1 | Medio | `event_tire_rules_contract.gd` | revert JSON | Los 5 eventos validan; Suecia ofrece `snow_studded` |
| 6.2 | Garaje: selector desde catálogo, sin mayoría | `rally_garage_panel.gd:156-168,1406-1419,1436-1445,1513-1545` | 2.5 | Medio | `garage_compound_contract.gd` | flag `tire_ui_v2` off | N tipos listados; `label`/`short_label` leídos del catálogo |
| 6.3 | Pausa/inventario: nombres y gráficos desde catálogo | `rally_pause_inventory.gd:557-565,693-694,943,1214-1264,1483-1491` | 6.2 | Medio | `pause_inventory_contract.gd` | flag off | 0 literales de compuesto en UI |
| 6.4 | Repuestos y servicio por tipo | `rally_escort_vehicle.gd:813-886`, `rally_service_panel.gd:220-230` | 6.2 | Medio | `tire_service_contract.gd` | flag off | Repuesto con tipo y `stud_integrity` propios |
| 6.5 | Rivales: factor por tipo desde catálogo | `rally_event_manager.gd:277-306`, `rally_competition.gd:275-280` | 6.1 | Bajo | `rival_compound_contract.gd` | flag off | Sin `if id == "gravel_wet"` |
| 6.6 | Save v3 → v4 con migración explícita | `rally_event_manager.gd:472-577` | 6.1 | **Alto** | `save_migration_contract.gd` | conservar v3 | v3 restaura; v4 con tipos nuevos; tipo inválido → error visible, sin fallback |
| 6.7 | Pronóstico sin literales | `rally_weather_scheduler.gd:489-512` | 6.1 | Bajo | `forecast_contract.gd` | — | Devuelve `type_id`, la UI pone la etiqueta |

**Criterio de salida:** un jugador puede elegir `snow_studded` en Suecia con cualquier coche, verlo en pausa, guardar, reanudar y conservar clavos y desgaste.

### 9.8 Fase 7 — Calibración y aceptación

| ID | Tarea | Ruta(s) | Depende | Riesgo | Test | Rollback | Aceptación |
|---|---|---|---|---|---|---|---|
| 7.1 | Barridos de fuerza por material/capa | `tools/tires/sweep_forces.gd` (nuevo) → `game/docs/rally/TIRE_SWEEPS_WINTER.md` | 5.4 | Bajo | §10.5 | — | Curvas monótonas y continuas, sin NaN |
| 7.2 | Pruebas de conducción guiadas | manual | 7.1 | Medio | §10.11 | — | Checklist firmado por el usuario |
| 7.3 | Regresión de las 42 etapas | §10.9, §10.13 | 6.6 | Medio | contratos | — | 42/42 + 32/32 import |
| 7.4 | Presupuesto de CPU | §10.11 | 2.2 | Bajo | perfilado | flag off | ≤ +3 % en `_integrate_forces` con capas inactivas; ≤ +8 % con capas activas |
| 7.5 | Actualizar documentación existente | `DYNAMIC_WEATHER_TIRES_PLAN.md`, `PHYSICS_FILTERS.md`, `TIRE_PATCH_MEMORY.md` | 7.3 | Bajo | revisión | — | Docs reflejan el código real (§1.5, §12 D-7) |

### 9.9 División en PRs y estrategia de flags

| Flag | Alcance | Efecto al apagarse |
|---|---|---|
| `tire_catalog_v2` | catálogo + API | vuelve a `rally_compounds.json` v1 |
| `tire_resolver` | resolver + wiring | `TireModel`/`ThermalModel` usan la ruta actual |
| `surface_taxonomy` | clasificación | `SURFACE_GROUP_BY_NODE` actual |
| `winter_layers` | capas + hielo + aguanieve | `snow_mm`/`water_mm` escalares |
| `studs` | clavos | `snow_studded` se comporta como goma sin clavos |
| `tire_ui_v2` | garaje/pausa | UI binaria actual |

Los flags se leen **una vez** al configurar la sesión, no por subpaso. Deben vivir en `game/data/rally/simulation_flags.json` (nuevo) para poder activarlos por prueba sin recompilar.

**Recomendación de PRs:** Fase 1 en 2 PRs (1.1+1.2 / 1.3+1.4+1.5+1.6), Fase 2 en 2 PRs (2.1-2.3 / 2.4-2.7), Fase 3 en 2 PRs (3.1-3.2 / 3.3-3.6), Fase 4 en 3 PRs (4.1-4.2 / 4.3-4.4 / 4.5-4.7), Fase 5 en 2 PRs, Fase 6 en 3 PRs, Fase 7 en 1 PR.

---

## 10. Plan de pruebas

### 10.0 Cómo ejecutar (obligatorio, reproducible)

```powershell
# user:// está fuera del workspace: redirigir APPDATA o Godot aborta por no poder escribir logs.
$env:APPDATA = "D:\rust-godot-vehicle-simulator\tmp\godot_appdata"
$exe = "C:\Users\bill\AppData\Local\Programs\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe"
& $exe --headless --path game --script res://tests/rally/<contrato>.gd
```

Notas:
- `[exit code: 1]` puede aparecer por `NativeCommandError` de PowerShell aunque el script salga con 0; **comprobar `$LASTEXITCODE`**, no el stream de error.
- `ERROR: Failed to read the root certificate store` es ruido del entorno, no del test.

### 10.1 Paridad numérica legacy (`tire_legacy_parity_contract.gd`)

| Aspecto | Definición |
|---|---|
| Montaje | 15 perfiles (todos los `tires.json`), `gravel_normal` y `gravel_wet`, migración v2 como en `tire_filters.json` |
| Entradas | `Fz ∈ {1000, 2500, 4000, 6000} N`; `slip_ratio ∈ {−0.30,−0.15,−0.05,0,0.05,0.15,0.30,0.60}`; `slip_angle ∈ {−0.20,−0.10,−0.02,0,0.02,0.10,0.20}`; `tread_c ∈ {20, 50, 95}`; `water ∈ {0, 3, 8}`; `snow ∈ {0, 2, 6}`; ejes delantero y trasero |
| Salidas | `longitudinal_force_n`, `lateral_force_n`, `rolling_force_n`, `aligning_torque_nm`, `friction_power_w`, `combined_utilization` |
| Tolerancia | `1e-9` absoluto y `1e-7` relativo; `0` para `surface`/`slip_*` |
| Golden | `game/tests/data/tire_parity_golden_v1.json`, generado en Fase 0 y **versionado** |
| Duración | < 60 s |
| Falla si | cualquier delta supera tolerancia **o** el golden no cubre los 15 perfiles |

### 10.2 Inmutabilidad de parámetros del coche (`tire_param_immutability_contract.gd`)

- Hash de `domains["tires"]`, `domains["tire_filters"]`, `domains["chassis"]` y del manifiesto antes/después de: `mount`, `contact`, `set_mounted`, `reset_for_stage`, `service_tire_inventory`.
- Comprueba explícitamente para **Mini** y **Stratos**: `radius`, `width`, `wheel_mass`, `rim_diameter_inches`, `sidewall_m`, `geometry_scale` (§4.6), y que los dos ejes se mantienen distintos donde lo son (`width` 0.228 vs 0.318 en Stratos).
- Comprueba que `contact_patch`, `load_sensitivity_per_newton`, `force_model.rear` **no** cambiaron de propietario (siguen leyéndose del coche).

### 10.3 Mismo tipo invernal en todos los perfiles (`winter_type_availability_contract.gd`)

- Para cada uno de los 15 perfiles y cada tipo de `list_for_event(sweden)`: `mount()` devuelve `ok`.
- Ningún perfil queda excluido por radio/llanta sin que `validate_fitment` lo declare (los 15 son 13" salvo comprobación).
- Un tipo inexistente devuelve error (`E_UNKNOWN_TYPE`), **no** `gravel_normal`.

### 10.4 Presupuesto elíptico (`tire_budget_contract.gd`)

- Tras `TireModel.evaluate`, `‖(fx/limit_x, fy/limit_y)‖ ≤ 1 + 1e-6` para 10 000 combinaciones aleatorias con semilla fija.
- Incluye capas activas, clavos a integridad 0/0.5/1, y charcos.
- Reproduce el invariante ya fijado en `tire_combined_migration_contract.gd:16-19` y lo extiende a las capas nuevas.

### 10.5 Barridos Fx/Fy por superficie (`tire_surface_sweeps_contract.gd`)

- Materiales: `Gravel`, `Road`, `Dirt`, `Grass`, `Sand` × capas: `none`, `snow_loose(1.0)`, `snow_packed(1.0)`, `ice(1.0)`, `slush(1.0)`.
- Barrido `slip_ratio −1..1` (0.01) y `slip_angle −0.6..0.6` (0.01), `Fz = 3000 N`, `tread_c` en la ventana del tipo.
- Asserts: sin `NaN`/`INF`; `Fx(0)=Fy(0)=0`; continuidad (`|ΔF| < 5 %` entre muestras adyacentes); pico > postpico; `mu_ice < mu_gravel < mu_road` para goma; `mu_ice_studded > mu_ice_rubber`.
- Salida: CSV en `game/docs/rally/TIRE_SWEEPS_WINTER.md` (generado en Fase 7).

### 10.6 Clavos (`stud_contract.gd`)

| Caso | Entrada | Esperado |
|---|---|---|
| Ventaja en hielo | `ice(1.0)`, `stud_integrity` 1.0 vs 0.0, `Fz=2500` | `fx_capacity` y `fy_capacity` mayores con clavos, ambas dentro del presupuesto |
| Deterioro en terreno expuesto | 50 km simulados sobre `Road` | `stud_integrity` entre 0.3 y 0.7; estrictamente decreciente |
| Monotonía | 1 000 pasos mixtos | `stud_integrity` nunca aumenta |
| Servicio | `service_tire_inventory` | vuelve a 1.0 |
| Intercambio | `exchange_tire(0, spare_id, true)` | el estado viaja con el ítem; la rueda desmontada conserva su integridad |
| Persistencia | `snapshot` → JSON → `restore` | igualdad exacta; save sin campo → 1.0 |
| Sin hielo accesible | `snow_packed(1.0)`, `ice(0.0)` | `stud_effectiveness == 0`; sin bonificación |

### 10.7 Variación espacial y temporal (`surface_transition_forces_contract.gd`)

- Recorrer una ruta sintética con parches `Gravel → Road → Ice → snow_packed → Gravel` a 60 km/h.
- Asserts: `|ΔFx|` y `|ΔFy|` entre pasos consecutivos por debajo de un umbral derivado de `surface_transition_tau_s` (documentar el umbral calculado, no un número inventado); sin picos de un solo frame > 25 % de la capacidad.
- Cuatro contactos con materiales distintos simultáneos: cada rueda usa su propio material y su propio `contributions`.

### 10.8 Temperatura y presión por rueda (`tire_per_wheel_thermal_contract.gd`)

- Perfiles FL/FR/RL/RR distintos; cambiar el tipo de una sola rueda; `pit/service`; daños persistentes.
- Asserts: la base del vehículo no muta (§10.2); `wear`, `thermal_damage`, `leak`, `rim_deformation`, `carcass_failure`, `pressure_loss_fraction`, `stud_integrity` se conservan en `reset_for_stage`.

### 10.9 Clasificación por etapa real (`stage_surface_matrix_contract.gd`)

- Para las 42 etapas: cargar colisión, leer `meta("surface_material")` de cada cuerpo del corredor de ruta, comparar contra la tabla de §8.5.
- Asserts: Suiza = `Road`; Suecia = `Gravel` + capa de nieve > 0; Finlandia = `Road` en los tramos tarmac y `Gravel` en el resto; Rusia/Kenia = `Gravel`/`Dirt`; `unknown_count == 0`.

### 10.10 Inventario, UI e IA (`tire_business_contract.gd`)

- Selección por rueda, restricciones por evento, restauración de save v3/v4, rechazo de ID inválido con mensaje visible.
- Rival: `rival_compound_for` devuelve el tipo elegido y `_rival_compound_factor` no depende de un literal.

### 10.11 Determinismo y coste (`tire_determinism_cost_contract.gd`)

- Misma semilla + mismo estado → mismas fuerzas (comparación bit a bit de la salida serializada).
- Frecuencia real del banco de pruebas: **60 Hz de tick** (`game/project.godot:29`) con `ceil(dt / maximum_substep_seconds)` subpasos (`vehicle_simulation.gd:687-689`), `maximum_substep_seconds ≥ 0.002`. El test debe ejecutarse a `dt = 1/60` y también a `dt = 1/30` y `dt = 1/120` para demostrar independencia del framerate.
- `performance.now_usec()` alrededor de `_integrate_forces` en 600 pasos: baseline registrado en Fase 0; límites de §9.8 (7.4).
- Coste del resolver medido por separado: `contact()` debe quedar por debajo de **2 µs** por rueda en el hardware de referencia (o el 2 % del tiempo de `_integrate_forces`, lo que sea mayor). Si se supera, se mueve trabajo a `mount()`.
- Asserts estáticos: `grep` de `FileAccess`/`JSON.parse_string`/`duplicate(true)` dentro del cuerpo de `TireModel.evaluate` y `TireParameterResolver.contact` → 0 coincidencias.
- Sin reservas de memoria por paso: el resolver no debe crear `Array`/`Dictionary` nuevos por rueda y subpaso salvo el `Dictionary` de salida (documentar si se reutiliza un buffer).

### 10.12 Revisión de pruebas existentes

Todas las de §1.4 deben seguir en PASS. Inventario obligatorio antes/después: `compound_thermal_regression`, `tire_combined_migration_contract`, `tire_inventory_contract`, `dynamic_weather_tires_contract`, `puddles_contract`, `tire_damage_contract`, `tire_hud_zones_contract`, `garage_function_contract`, `stage_vehicle_start_contract`, `stage_grass_contract`, `surface_audio_contract`, `weather_runtime_regression` (tras 0.4), `all_countries_stage_import_contract`.

### 10.13 Stage import/export

```powershell
& $exe --headless --path game --script res://tests/rally/stage_export_import_test.gd
& $exe --headless --path game --script res://tests/rally/all_countries_stage_import_contract.gd
```

`stage_export_import_test.gd` fija recuentos de triángulos (`rally_track_collision_builder.gd:85-88` cita `russia Dirt == 11695 + 582`). **Cualquier cambio en `_erosion_bank_collision_node` (Fase 3.2) puede alterar esos recuentos**: el PR debe actualizarlos con justificación explícita, no silenciosamente.

### 10.14 Pruebas manuales (Fase 7)

| Prueba | Cómo | Criterio |
|---|---|---|
| Conducción en Suecia | Stage 1–3 con `snow_studded` y con `gravel_normal` | Diferencia perceptible y coherente; sin saltos al cruzar parches |
| Suiza | Stage 1–3 | El coche no se siente sobre grava; frenada estable |
| Finlandia | Stage con tarmac | Transición grava↔asfalto continua |
| Clavos | 2 stages seguidos sin servicio | El agarre en hielo decae de forma gradual, no brusca |
| UI | Garaje y pausa | Nombres del catálogo; ninguna etiqueta «GRAVA/LLUVIA» fija |
| Guardado | Salir y reanudar en ventana de servicio | Sin cambios de tipo, sin clavos regenerados |

---

## 11. Compatibilidad y estrategia de activación

### 11.1 IDs

- `gravel_normal` y `gravel_wet` **se conservan** con sus valores exactos (§5.5).
- IDs nuevos: `asphalt_dry`, `asphalt_wet`, `mud`, `snow_studded`. Sin renombres.
- `aliases` permite mapear nombres antiguos hipotéticos a canónicos, pero **solo** los declarados explícitamente; un ID desconocido es error.

### 11.2 Partidas guardadas

| Origen | Comportamiento |
|---|---|
| `user://rally_competition_v1.json` | **No hay rechazo ni migración: se ignora.** `LEGACY_SAVE_PATH` se declara en `rally_event_manager.gd:9` y **no se usa en ningún sitio** (código muerto); `rally_competition.gd:28` apunta a ese archivo por defecto, pero `rally_event_manager.gd:151` y `:390` fuerzan `sim.save_path = ""` para que no se escriba ni se lea. Consecuencia: si un jugador conserva ese archivo, no obtiene error ni aviso — simplemente empieza de cero. Fase 6 debe decidir si se informa en UI (§12 D-11). |
| `user://rally_event_v2.json` v2 | Ya rechazado con aviso de evento nuevo (`:529-531,580-587`) |
| v3 actual | **Debe seguir restaurando** en Fase 1 (PR-02a) y en Fase 6 se migra a v4 |
| v4 (tipos nuevos + `stud_integrity` + capas) | Nuevo; migración de v3 documentada: `stud_integrity = 1.0` solo si el tipo lo requiere; capas derivadas de `snow_mm`/`water_mm` con `migration` anotada |
| Tipo inválido en save | **Error explícito con mensaje**, sin fallback (§5.7) |

### 11.3 `rules_hash` (P0-1)

Cambio obligatorio y previo a cualquier edición de datos:

```gdscript
# Antes (rompe saves al tocar el catálogo):
"tire_catalog": FileAccess.get_file_as_string(tire_path).sha256_text()

# Después:
"tire_catalog_id": catalog.catalog_id,
"tire_catalog_version": catalog.catalog_version,
"tire_physics_contract": catalog.physics_contract_version,
"tire_physics_subset_hash": sha256(JSON.stringify(physics_subset(catalog)))
# physics_subset excluye labels/advantages/drawbacks/order de presentación
```

Con esto, añadir etiquetas o reordenar tipos **no** invalida partidas; cambiar un coeficiente físico **sí** (y es correcto que lo haga).

### 11.4 IA rival

- `rival_compounds` sigue siendo por etapa y participante.
- El factor debe venir de `catalog.types[cid].rival_time_factor` (nuevo campo, TBD) en lugar de `if cid == "gravel_wet": 0.992` (`rally_competition.gd:278-280`).
- No se duplican pérdidas: el factor es un **matiz** sobre la referencia ya calibrada (comentario existente en `rally_event_manager.gd:292-293`).

### 11.5 UI

- Un único origen de etiquetas: `types[*].label` / `short_label` / `labels.advantages|drawbacks` (hoy muertos, §2.1.9).
- Se elimina la derivación por mayoría. `TireTypeAssignment.primary` es explícito.
- Se conserva el idioma actual (español) en el catálogo; no se introduce i18n en esta iteración (§12 D-8).

### 11.6 Repuestos y masa

- `inventory.wheel_mass_kg` deja de ser el valor efectivo: la masa de repuesto sale de `tires.json[axle].wheel_mass` (que ya coincide con `chassis.spare_policy`). El valor de catálogo queda como *fallback* documentado (§4.5) y se corrige el `18.0` a un `null` explícito en v2 para forzar la fuente del coche.

### 11.7 Activación gradual

1. Fase 1 activa catálogo v2 en **modo lectura** con `tire_catalog_v2 = true` y `physics_contract_version` sin cambios → partidas intactas.
2. Fase 2 activa `tire_resolver` **solo** con paridad demostrada.
3. Fase 3 y 4 se activan **por evento** (`weather_rules.surface_taxonomy_enabled`, `winter_layers_enabled`), empezando por Suecia (nieve) y Suiza (asfalto) en *preview*.
4. Fase 5 se activa por evento (solo Suecia) y con `studs = true`.
5. Fase 6 activa `tire_ui_v2` al final, cuando el catálogo ya es estable.

### 11.8 Cambios de esquema resumidos

| Archivo | v1 | v2 | Migración |
|---|---|---|---|
| `data/tires/rally_compounds.json` | `format_version: 1`, 2 compuestos | se conserva **sin cambios** como referencia | no se borra en esta iteración |
| `data/tires/rally_compounds_v2.json` | — | nuevo | derivado del v1 + 4 tipos nuevos |
| `data/surfaces/material_surface_map.json` | — | nuevo | taxonomía de §8.2 |
| `data/rally/simulation_flags.json` | — | nuevo | flags de §9.9 |
| `data/competition/events/*.json` | `tire_rules` con 2 IDs | `tire_rules` con N IDs + `default_compound_id` por rally | aditivo |
| `user://rally_event_v2.json` | v3 | v4 | migración explícita, v3 soportado |

---

## 12. Decisiones abiertas

Formato: opciones, pros/contras, recomendación. Solo se marcan como **bloqueante** las que impiden empezar (§12 D-1 y D-2).

### D-1 — ¿Cómo se corrige la geometría de colisión por material? **BLOQUEANTE para Fase 3**

- **A. Regenerar los 42 `*_collision.glb` con un nodo por material** (`Collision_Road_gravel`, `Collision_Road_tarmac`, `Collision_Road_snow`).
  - Pros: correcto de raíz; el `meta` por material es exacto; sin heurísticas.
  - Contras: el exportador **no está en el repositorio** (§1.6); requiere la cadena Blender/BMF; 42 assets; riesgo de alterar recuentos de triángulos que fijan tests.
- **B. Tabla `material_surface_map.json` por país + patrón, aplicada al nombre del nodo y a `stage.surface`.**
  - Pros: sin tocar assets; reversible; se puede validar por test; desbloquea hoy.
  - Contras: granularidad por etapa, no por triángulo: en Finlandia (grava + tarmac) el `Collision_Road` seguiría siendo uno solo.
- **C. Híbrido:** B para Rusia/Kenia/Suecia/Suiza (un material dominante por etapa) y A solo para Finlandia (mezcla real).
  - Pros: mínimo riesgo con corrección real donde importa.
  - Contras: dos mecanismos que mantener.

**Recomendación: C.** Empezar con B (desbloquea Fase 3 completo), y abrir A como fase 3b para Finlandia, con el exportador como dependencia externa explícita. Si el usuario no puede recuperar el exportador, Finlandia queda con B y se documenta la limitación.

### D-2 — ¿`surfaces.*` pasa al catálogo de superficies o se queda en el vehículo? **BLOQUEANTE para Fase 1**

- **A. Se queda en el vehículo** (recomendado a corto plazo): cumple la regla anti-homogeneización; no hay riesgo.
- **B. Se mueve a `surface_modifiers` compartido** con paridad: reduce duplicación real (15 copias idénticas) pero elimina la capacidad futura de calibrar un coche por superficie.

**Recomendación: A en v2; evaluar B en una iteración posterior con test de paridad.** La instrucción 2 es explícita: no mover solo porque hoy se repita.

### D-3 — `rt-escort-rs2000` con calibración genérica vs `ford-escort-rs2000` propia

- **A. Dejarlo** (recomendado): puede ser intencional por diferencia de asset.
- **B. Igualarlos:** riesgo de alterar tiempos de referencia y tests.

**Recomendación: A**, dejando constancia en el baseline; requiere confirmación del autor del port.

### D-4 — Base histórica de clavos

- **A. Preset único `period_1974_light`** con `stud_count_per_tire` y `stud_protrusion_mm` marcados TBD y sin variación por coche (recomendado).
- **B. Preset por coche:** multiplica el trabajo y exige datos históricos que el repositorio no tiene.

**Recomendación: A.** No inventar protrusiones modernas; el `stud_effectiveness` ya modula por carga y textura.

### D-5 — Fitment: ¿puede un tipo exigir otra llanta?

- **A. No**: `fitment` solo **valida** (bloquea), nunca cambia radio/ancho/llanta (recomendado; cumple instrucción 3.10).
- **B. Sí**, con un catálogo de medidas por tipo: introduce una dimensión nueva de datos y rompe `radius`/`width` como propiedad del coche.

**Recomendación: A.**

### D-6 — ¿Qué familias se ofrecen en cada rally?

| Rally | Propuesta | Alternativa |
|---|---|---|
| Rusia | `gravel_normal`, `gravel_wet`, `mud` | sin `mud` |
| Kenia | `gravel_normal`, `gravel_wet`, `mud` | sin `mud` |
| Finlandia | `gravel_normal`, `gravel_wet`, `mud`, `asphalt_dry`*, `asphalt_wet`* | solo grava/mud |
| Suecia | `snow_studded` (def), `gravel_normal` | solo `snow_studded` |
| Suiza | `asphalt_dry` (def), `asphalt_wet` | + `gravel_normal` como elección penalizada |

`mud` es la familia con menos evidencia en el repositorio (no hay materiales «mud» explícitos; el metadato dice `gravel_mud` en 34 stages). Si se quiere reducir riesgo, **Fase 5 puede entregar solo `snow_studded` y dejar `mud` para una iteración posterior** sin cambiar el esquema.

**Recomendación:** ofrecer `mud` solo en Rusia/Kenia/Finlandia y validar con barrido; en Suecia permitir `gravel_normal` para que el jugador pueda equivocarse de forma visible.

### D-7 — Ventanas de reglaje (test rojo, §1.5)

- **A. Realinear el test** a las ventanas vigentes (2→3, 4→5, 6→7, 8→9).
- **B. Realinear las ventanas** al plan antiguo (después de stage 5).

**Recomendación: A para el test**, y B solo si el usuario confirma que el servicio de mitad de rally debe caer tras la stage 5. Es decisión de producto, no de física.

### D-8 — Idioma de las etiquetas

- **A. Mantener español** en el catálogo (recomendado). El juego está en español.
- **B. Introducir claves i18n** ahora: multiplica el alcance de Fase 6 sin beneficio inmediato.

### D-9 — Densidad de nieve y espesor geométrico

- **A. Densidad constante por zona** con `100–400 kg/m³` y TBD (recomendado).
- **B. Densidad evolutiva por compactación:** más realista, más coste y más parámetros sin datos.

**Recomendación: A**, con el campo `snow_density_kg_m3` ya presente para poder evolucionar a B sin cambiar el esquema.

### D-10 — ¿Se retira `rally_tire_compound.gd`?

- **A. Se conserva como fachada** que delega en `RallyTireCatalog` (recomendado en esta iteración; evita tocar 8 llamadas de golpe).
- **B. Se elimina** al final de Fase 6: más limpio, exige actualizar tests y `rally_pause_inventory.gd:645`.

**Recomendación: A en 1–5, B como tarea de limpieza en Fase 6.**

### D-11 — Guardado legado `rally_competition_v1.json`

- **A. Ignorarlo como hoy** (recomendado): cero riesgo, pero el jugador con un save antiguo no recibe explicación.
- **B. Detectar y avisar en UI** («guardado antiguo no compatible: inicia un evento nuevo»): requiere código en el menú de competición y un test.
- **C. Migrar v1 → v4**: imposible sin `weather_schedule` ni compuesto (§`JSON` guardado no los contiene); produciría un evento sin clima.

**Recomendación: B**, como tarea pequeña de Fase 6 (PR-23), sin tocar el flujo de `restore()`.

---

## 13. Checklist de Definition of Done

Un agente puede declarar terminado el trabajo cuando **todo** lo siguiente es cierto y verificable:

### Datos
- [ ] `game/data/tires/rally_compounds_v2.json` valida con `validate_catalog()` sin errores.
- [ ] `gravel_normal` y `gravel_wet` tienen exactamente las 43 claves de v1 (36 numéricas) con los mismos valores (test de migración, tol 0).
- [ ] Los 6 tipos existen con `family`, `rubber`, `thermal`, `drainage`, `surface_response`, `layers`, `wear`, `labels`.
- [ ] Todo valor no medido está marcado `status: "tbd"` con `range`, `source` y `procedure`.
- [ ] `game/data/surfaces/material_surface_map.json` clasifica el 100 % de los materiales viales de §8.2.

### Código
- [ ] No queda ningún literal `["gravel_normal","gravel_wet"]` en `game/scripts` (grep vacío).
- [ ] `TireParameterResolver` existe, es puro y no muta `domains`/catálogo (test de hashes).
- [ ] `VehicleThermalModel` no escribe en `tire_config`, `tire_config_front`, `tire_config_rear`.
- [ ] `TireModel` conserva `patch_pos`, brush elíptico, presupuesto combinado, memoria postpico y migración v2.
- [ ] No hay `FileAccess`/`JSON.parse_string`/`duplicate(true)` en el camino por contacto.
- [ ] `_surface_for_collider` no devuelve `"Gravel"` por defecto.
- [ ] `PuddleModel.contact_response` recibe eficiencia, no un booleano de compuesto.
- [ ] `rally_competition.gd` no compara `cid == "gravel_wet"`.

### Física
- [ ] Paridad `gravel_*` en los 15 coches: todo delta ≤ 1e-9.
- [ ] Presupuesto elíptico respetado en 10 000 casos aleatorios.
- [ ] `fx/fy` sin NaN/INF en todos los barridos.
- [ ] Una sola contribución por fenómeno (`water`, `snow`, `ice`, `slush`, `ground_cold`) verificada sobre 1 000 combinaciones.
- [ ] Clavos: ventaja en hielo, deterioro en seco, monotonía, persistencia y restauración por servicio.
- [ ] Mini y Stratos conservan radio, ancho, `sidewall_m` y `geometry_scale` de §4.6.

### Integración
- [ ] Los 5 eventos declaran sus `tire_rules` y `default_compound_id`.
- [ ] Suecia ofrece `snow_studded` y los 15 perfiles lo montan sin error.
- [ ] Suiza reporta `base_material = Road` en las 8 etapas; Suecia reporta nieve > 0 en las 8.
- [ ] Garaje y pausa leen nombres del catálogo; sin etiquetas fijas.
- [ ] Guardado v3 restaura; v4 migra; tipo inválido da error visible.

### Calidad
- [ ] Los 13 contratos de §10 existen y pasan; los 13 existentes de §1.4 siguen en PASS.
- [ ] `all_countries_stage_import_contract` 32/32 y `stage_export_import_test` en PASS o con recuentos actualizados y justificados.
- [ ] Coste: ≤ +3 % sin capas activas, ≤ +8 % con capas activas.
- [ ] `DYNAMIC_WEATHER_TIRES_PLAN.md`, `PHYSICS_FILTERS.md` y `TIRE_PATCH_MEMORY.md` actualizados al código real.
- [ ] `weather_runtime_regression` resuelto (o excepción documentada y aprobada por el usuario).

---

## 14. Lista priorizada de PRs

Cada PR es pequeño, autónomo y con condición de aceptación objetiva. Orden = orden de ejecución.

| # | Título | Cambios | Tests | Aceptación objetiva |
|---|---|---|---|---|
| **PR-01** | `chore(tires): baseline de paridad y matriz de propiedad` | `tools/tires/audit_ownership.py`, `game/tests/rally/tire_legacy_parity_contract.gd`, `game/tests/data/tire_parity_golden_v1.json`, `game/docs/rally/TIRE_BASELINE_v1.json`, `TIRE_OWNERSHIP_MATRIX.generated.md` | 0.3, 0.5 | El test de paridad pasa en < 60 s y el golden cubre 15 perfiles × 2 tipos × 3 ejes de barrido |
| **PR-02a** | `fix(rally): hash de reglas sin sha crudo del catálogo` **(P0)** | `rally_weather_scheduler.gd:469-486` | `save_rules_hash_contract.gd` | Un save v3 existente restaura después de editar `label`/`advantages` del catálogo |
| **PR-02b** | `chore(rally): resolver el test de ventana de servicio` | `weather_runtime_regression.gd:72-77` **o** `russia_rally.json:setup_windows` | el propio test | `weather_runtime_regression` en PASS o decisión D-7 registrada |
| **PR-03** | `feat(tires): esquema y validador del catálogo v2` | `rally_compounds_v2.schema.json`, `rally_tire_catalog.gd` (`load_catalog`, `get_type`, `is_valid`, `list_for_event`, `validate_catalog`, `resolve_alias`, `as_v1_fields`), `simulation_flags.json` | 1.1, 1.5 | 11 casos (1 válido + 10 errores) con código estable |
| **PR-04** | `feat(tires): datos v2 con vista v1 exacta` | `rally_compounds_v2.json` | `tire_catalog_migration_contract.gd` | 43/43 claves de `gravel_*` idénticas a v1 (36 numéricas con tol 0) |
| **PR-05** | `refactor(tires): una sola lista de IDs y error explícito` | `rally_tire_compound.gd:9,33-34`, `tire_model.gd:45`, `thermal_model.gd:130`, `vehicle_simulation.gd:178`, `rally_tire_inventory.gd:44`, `dynamic_weather_tires_contract.gd:36` | `tire_catalog_ids_contract.gd` | `grep -c 'gravel_normal","gravel_wet' game/scripts` = 0 |
| **PR-06** | `feat(fisica): TireParameterResolver puro` | `game/scripts/physics/tire_parameter_resolver.gd` | `tire_resolver_contract.gd` | `contact()` no muta nada; `contributions` con una entrada por fenómeno |
| **PR-07** | `refactor(fisica): TireModel consume el resolver sin cambiar el solver` | `tire_model.gd:44-84,258-425` | paridad §10.1 + `tire_combined_migration_contract` | Delta ≤ 1e-9 y `tire_combined_migration_contract` PASS |
| **PR-08** | `fix(fisica): configuración térmica resuelta por rueda sin mutar la base` **(P0-2)** | `thermal_model.gd:129-166,692-703`, `rally_escort_vehicle.gd:202-245` | `thermal_no_mutation_contract.gd` | Hash de `tire_config*` idéntico antes/después de `set_mounted` |
| **PR-09** | `feat(rally): TireTypeAssignment como autoridad única` | `rally_tire_assignment.gd`, `rally_escort_vehicle.gd:248-253,780-811` | `tire_assignment_contract.gd` | `primary` explícito; sin `wet_count` en producción |
| **PR-10** | `feat(rally): taxonomía material→superficie` | `material_surface_map.json`, `surface_taxonomy_contract.gd` | 3.1 | 0 materiales viales sin clasificar |
| **PR-11** | `fix(rally): clasificación de colisión por material y sin fallback a Gravel` **(P0-4)** | `rally_track_collision_builder.gd:13-22,89-99,139-143`, `vehicle_simulation.gd:1096-1104,741` | `stage_surface_matrix_contract.gd`, `surface_fallback_contract.gd` | Suiza = `Road` en 8/8; `unknown_count` = 0 en 42/42 |
| **PR-12** | `fix(rally): perfil térmico de suelo por material de zona` | `rally_surface_model.gd:134-198` | `surface_thermal_profile_contract.gd` | Suiza usa capacidad 1400 y absorción 0.78 |
| **PR-13** | `feat(rally): capas de nieve/hielo/aguanieve con invariantes` | `rally_surface_model.gd:33-47,96-198` | `surface_layers_contract.gd`, `snow_depth_conversion_contract.gd` | `Σ fracciones ≤ 1+1e-6` y normalización contada |
| **PR-14** | `feat(rally): hielo con histéresis` | `rally_surface_model.gd` | `ice_hysteresis_contract.gd` | Sin hielo a −0.1 °C; congelado a −3 °C sostenido |
| **PR-15** | `fix(rally): drenaje por eficiencia en vez de literal de compuesto` | `rally_puddles.gd:578-620`, `vehicle_simulation.gd:814-823`, catálogo (`water_evacuation_efficiency`) | `slush_drainage_contract.gd` | `16/0.571 = 28` y `16/1.0 = 16` reproducidos exactamente |
| **PR-16** | `feat(rally): persistencia de capas y continuidad entre stages` | `rally_surface_model.gd:206-212`, `rally_event_manager.gd:309-315,504` | `surface_continuity_contract.gd` | Guardar/reanudar conserva fracciones, densidad y temperatura |
| **PR-17** | `feat(tires): estado y desgaste de clavos por unidad` | `rally_escort_vehicle.gd:24,813-886`, `rally_compounds_v2.json` (`studs`) | `stud_contract.gd`, `stud_persistence_contract.gd` | Integridad monótona, servicio restaura, roundtrip exacto |
| **PR-18** | `feat(fisica): clavos dentro del presupuesto elíptico` | `tire_parameter_resolver.gd`, `tire_model.gd:421-434` | `stud_friction_contract.gd`, §10.4 | Ventaja en hielo > 0 y presupuesto ≤ 1+1e-6 en 10 000 casos |
| **PR-19** | `feat(events): tire_rules por rally con snow_studded en Suecia` | `game/data/competition/events/*.json` (5) | `event_tire_rules_contract.gd`, `sweden_tire_offer_contract.gd` | 5/5 eventos válidos; 15/15 perfiles montan `snow_studded` |
| **PR-20** | `feat(ui): selector de compuesto desde catálogo` | `rally_garage_panel.gd:156-168,1406-1419,1436-1445,1513-1545` | `garage_compound_contract.gd` | 6 tipos listados; `label` del catálogo en pantalla |
| **PR-21** | `feat(ui): inventario de pausa sin literales` | `rally_pause_inventory.gd:557-565,693-694,943,1214-1264,1483-1491` | `pause_inventory_contract.gd` | 0 comparaciones de compuesto en la UI |
| **PR-22** | `feat(rally): rivales con factor por tipo` | `rally_event_manager.gd:277-306`, `rally_competition.gd:275-280` | `rival_compound_contract.gd` | Sin `if cid == "gravel_wet"` |
| **PR-23** | `feat(rally): save v4 con migración explícita` | `rally_event_manager.gd:472-577` | `save_migration_contract.gd` | v3 restaura; v4 migra; ID inválido → error visible |
| **PR-24** | `docs(tires): calibración invernal y barridos` | `TIRE_SWEEPS_WINTER.md`, `DYNAMIC_WEATHER_TIRES_PLAN.md`, `PHYSICS_FILTERS.md`, `TIRE_PATCH_MEMORY.md` | 7.1, 7.3 | Docs describen el código real; barridos adjuntos |

### Orden y dependencias

```
PR-01 ─┬─ PR-02a ─┬─ PR-03 ── PR-04 ── PR-05
       │          │
       │          └─ PR-02b (independiente)
       └─ PR-06 ── PR-07 ── PR-08 ── PR-09
                              │
PR-10 ── PR-11 ── PR-12        │
                  │            │
                  └─ PR-13 ── PR-14 ── PR-16
                               │
                               └─ PR-17 ── PR-18 ── PR-19 ── PR-20 ── PR-21 ── PR-22 ── PR-23
                                                     │
                                                     └─ PR-24 (al final)
```

`PR-10..PR-12` (superficies) pueden ejecutarse en paralelo con `PR-06..PR-09` (resolver), pero **PR-18 exige PR-14 y PR-17**, y **PR-19 exige PR-04**.

---

### Cierre

Este documento no implementa nada. El único archivo creado es este plan. Las mediciones de §1.4 se obtuvieron ejecutando tests existentes en modo headless con `APPDATA` redirigido a `tmp/`; el resto del árbol quedó intacto. Los archivos de auditoría temporal (`tmp/glb_nodes.py`, `tmp/glb_nodes2.py`, `tmp/glb_snow.py`, `tmp/road_mats.py`, `tmp/tires_*.py`, `tmp/fm_groups.py`, `tmp/filter_hash.py`, `tmp/manifests.py`, `tmp/count_fields.py`) y el directorio `tmp/godot_appdata` se eliminaron al terminar. Verificación final: `git status --porcelain` devuelve **164** archivos rastreados modificados (los mismos que al inicio) y **2587** entradas sin rastrear (las 2586 iniciales + este plan). Ningún archivo rastreado fue modificado por la auditoría.

**Siguiente acción recomendada:** ejecutar **PR-01** y **PR-02a** antes de tocar una sola cifra del catálogo.
