# Plan de Corrección Técnico: Inventario de Neumáticos, Garaje y UX-UI (Handoff para Agente)

**Fecha de diagnóstico base:** 2026-11-12  
**Motor y proyecto:** Godot `4.7.1` (`d:\rust-godot-vehicle-simulator\game`)  
**Relación con `UI_REFACTOR_PLAN.md`:** Este documento reemplaza las dependencias de addons de [UI_REFACTOR_PLAN.md](UI_REFACTOR_PLAN.md). **No importar ni instalar addons externos** (`Simple GUI Transitions`, `Anima` y `AnimUI` quedan descartados por decisión del usuario). Toda transición o microinteracción debe hacerse en GDScript nativo (p. ej. `Tween`) sobre el sistema de temas propio.

---

## 1. Reglas Operativas para el Agente Ejecutor

1. **Ejecutar por fases en orden estricto (`Fase 1 -> Fase 2 -> Fase 3 -> Fase 4`)** para evitar retrabajo sobre la UI antes de cerrar el modelo de inventario y los bloqueos de flujo.
2. **Prohibido romper el pool cerrado de 10 ruedas**: tras confirmar la distribución inicial (`4` montadas + `0..2` repuestos + `4..6` en parque de asistencia), el número total de ruedas entre `mounted`, `spares`, `service_stock` y `discarded` en [RallyTireInventory](../../scripts/rally/rally_tire_inventory.gd#L5-L15) debe mantenerse trazable por ID único (`#1..#10`), conservando compuesto, desgaste, estado térmico/presión, pinchazos, daño de aro y destalonado.
3. **Respetar todas las reglas de evento**: los costes y ventanas de [russia_rally.json](../../data/competition/events/russia_rally.json#L203-L254) (`allowed_compound_ids`, `fitment`, `service_costs`, `repair_minutes = 30`, `repair_penalty_seconds_per_minute = 10`, descanso nocturno Stage 5 -> 6 sin reparación) deben aplicarse de forma estricta sin atajos desde el garaje ni desde pausa.
4. **No usar rutas de bypass**: toda operación de movimiento entre `mounted`, `spares`, `service_stock` y `discarded` debe pasar por [move_tire()](../../scripts/rally/rally_tire_inventory.gd#L90-L147) / [swap_mounted()](../../scripts/rally/rally_tire_inventory.gd#L150-L162) con validación previa y rollback limpio al cancelar.
5. **Verificación continua**: después de cada fase, ejecutar en headless los contratos de `game/tests/rally/` usando `Godot_v4.7.1-stable_win64_console.exe` y registrar `PASS`/`FAIL`/`WARNING`.

---

## 2. Estado Base Verificado (Contratos Headless)

| Script de contrato | Estado actual | Detalle observado en ejecución headless |
|---|---|---|
| [tire_inventory_contract.gd](../../tests/rally/tire_inventory_contract.gd) | **PASS** | Pasa; reporta `WARNING: 76 ObjectDB instances were leaked at exit` |
| [test_tire_strategy_service.gd](../../tests/rally/test_tire_strategy_service.gd) | **PASS** | `TODOS LOS TESTS v2 PASARON` |
| [tire_closure_plan_contract.gd](../../tests/rally/tire_closure_plan_contract.gd) | **PASS** | Pasa (incluye warnings esperados de pruebas negativas) |
| [tire_handoff_acceptance_contract.gd](../../tests/rally/tire_handoff_acceptance_contract.gd) | **PASS** | `ALL HANDOFF ACCEPTANCE TESTS PASSED!` |
| [garage_function_contract.gd](../../tests/rally/garage_function_contract.gd) | **PASS** | Pasa (`WARNING: Rally garage: Confirma reglajes para continuar.`) |
| [service_workshop_contract.gd](../../tests/rally/service_workshop_contract.gd) | **PASS** | Pasa; reporta `10 ObjectDB instances leaked` y `4 resources still in use` |
| [russia_event_contract.gd](../../tests/rally/russia_event_contract.gd) | **PASS** | `RUSSIA_EVENT_CONTRACT PASS` |
| [car_select_gui_contract.gd](../../tests/rally/car_select_gui_contract.gd) | **PASS** | `CAR_SELECT_GUI_CONTRACT PASS` |
| [weather_select_menu_contract.gd](../../tests/rally/weather_select_menu_contract.gd) | **PASS** | Pasa; reporta `2 ObjectDB instances leaked` y `1 resources still in use` |
| [rally_final_results_contract.gd](../../tests/rally/rally_final_results_contract.gd) | **PASS** | Pasa; reporta `2 ObjectDB instances leaked` y `1 resources still in use` |
| [rally_maniac_menu_contract.gd](../../tests/rally/rally_maniac_menu_contract.gd) | **PASS (>15s)** | Expira a `15s` (`TIMEOUT`); pasa limpio sin errores con ventana de `35s` |
| [pause_map_contract.gd](../../tests/rally/pause_map_contract.gd#L33) | **FAIL + HANG** | `Assertion failed` en `:33` (garaje abierto en `practice_mode` bloquea pausa; no llama a `quit()`) |
| [damage_system_contract.gd](../../tests/rally/damage_system_contract.gd#L32) | **FAIL (3 checks)** | Falla en `:32` (`domain_hashes must include damage`), `:115` (`reset_for_stage must reset damage to 0`), `:322` (`Should not repair if radiator damage < 5%`) |
| [competition_session_contract.gd](../../tests/rally/competition_session_contract.gd#L68-L87) | **FAIL (3 checks)** | Falla en `:68`, `:70` (`clock runs after green while parked`) y `:87` (`rescue applies one penalty without retirement`) + `76 ObjectDB leaked` |
| [russia_stage_transition_contract.gd](../../tests/rally/russia_stage_transition_contract.gd) | **TIMEOUT (25s)** | Bloqueado tras `RALLY_STAGE_TRANSITION_READY stage=russia_stage3` (`tick_id: 723`) |

---

## 3. Fase 1 (P0 — Crítico): Flujo Inicial y Cierre del Inventario de 10 Neumáticos

### `[P0-01]` Desbloquear arranque y pausa en `practice_mode` y `single_stage`
* **Archivos:** [rally_russia_stage_session.gd](../../scripts/rally/rally_russia_stage_session.gd#L238-L239), [rally_pause_inventory.gd](../../scripts/rally/rally_pause_inventory.gd#L342), [pause_map_contract.gd](../../tests/rally/pause_map_contract.gd#L33)
* **Problema actual:** `RallyRussiaStageSession._ready()` llama a `_open_setup_window()` cuando `practice_mode` o `session_mode == "single_stage"` es `true`, estableciendo `awaiting_setup = true` y abriendo `garage_panel`. Como `RallyPauseInventory.allowed()` exige `not session.awaiting_setup` y `not session.garage_panel.visible`, pulsar `JOY_BUTTON_START` o pausa falla en el arranque de práctica y rompe `pause_map_contract.gd:33`.
* **Qué hacer:**
  * Revisar el flujo de inicio esperado para `practice_mode` y `single_stage` (ver contratos `pause_map_contract.gd`, `competition_session_contract.gd` y `garage_function_contract.gd`).
  * Evitar bloquear automáticamente el tramo con `awaiting_setup = true` en `practice_mode` salvo que el modo requiera explicitamente setup obligatorio previo (o diferenciar entre setup de rally oficial vs práctica libre con garaje opcional por botón `G`).
* **Aceptación:** `pause_map_contract.gd` pasa sin timeout y la pausa abre desde el primer frame tras el inicio en práctica.

### `[P0-02]` Rediseñar gestión de neumáticos del Garaje para operar por ID de rueda (y permitir cambios del mismo compuesto)
* **Archivos:** [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L140), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L1893-L1906), [rally_escort_vehicle.gd](../../scripts/rally/rally_escort_vehicle.gd#L1026-L1031), [rally_tire_inventory.gd](../../scripts/rally/rally_tire_inventory.gd#L90-L162)
* **Problema actual:** `service_tire_inventory()` solo busca una rueda nueva si `wanted != str(tire_inventory.mounted[i].compound_id)`. Es imposible en el Garaje cambiar una rueda montada desgastada o pinchada por otra rueda sana del **mismo compuesto** presente en `service_stock` o `spares`. Además, el Garaje no muestra la lista real de ruedas individuales de `service_stock` ni sus IDs/estados.
* **Qué hacer:**
  * En la pestaña Estrategia / Ruedas del Garaje (`mode == "rally"` con pool activo), mostrar en una sola vista con borrador transaccional:
    1. **4 ruedas montadas (`FL`, `FR`, `RL`, `RR`)** con su `#ID`, compuesto, `%` de desgaste restante/usado, presión e indicadores de daño (`FUGA`, `ARO`, `DESTALONADO`).
    2. **Repuestos en maletera (`0..2`)** y plazas vacías.
    3. **Stock en parque de asistencia (`service_stock`)** y bajas (`discarded`), diferenciados visualmente y con motivo claro cuando una rueda es inutilizable o el servicio no está permitido (`not session.may_service_tires()`).
  * Permitir seleccionar cualquier rueda utilizable de `service_stock` o `spares` por ID y asignarla a cualquiera de las 4 posiciones montadas o al maletero (incluyendo reemplazo por el **mismo compuesto**), previsualizando la rueda entrante, la saliente y el destino de la saliente antes de aplicar.
  * Descartar cambios si el jugador cancela; aplicar atómicamente vía `RallyTireInventory.move_tire()` / `swap_mounted()` al confirmar.
* **Aceptación:** Desde una ventana de servicio, el jugador puede sustituir `FL` `gravel_normal` (desgastada o pinchada) por otra `gravel_normal` sana de `service_stock` conservando los IDs y desplazando la usada correctamente.

### `[P0-03]` Corregir `_find_best_pool_tire()` para excluir ruedas pinchadas o con aro deformado
* **Archivo:** [rally_escort_vehicle.gd](../../scripts/rally/rally_escort_vehicle.gd#L1061-L1077), [rally_tire_inventory.gd](../../scripts/rally/rally_tire_inventory.gd#L5-L6)
* **Problema actual:** `_find_best_pool_tire(compound_id)` solo filtra `not tire_inventory.is_carcass_destroyed(td)` y escoge por menor `wear_fraction`. Si una rueda en stock o repuesto está pinchada (`leak_per_second > 0` / `pressure_loss_fraction > 0`) o tiene aro deformado (`rim_deformation > 0.005`), pero menos desgaste de goma que una sana, la monta igualmente.
* **Qué hacer:**
  * En selección automática por compuesto, exigir que el candidato esté sano: `not is_carcass_destroyed(td) and not is_punctured(td) and not is_rim_damaged(td)`.
  * Definir política explícita si solo quedan ruedas con `FUGA`/`ARO` reparables (o rechazar montaje automático con mensaje claro al jugador invitando a reparar antes en `RallyServicePanel`).
* **Aceptación:** Prueba unitaria verifica que `_find_best_pool_tire()` nunca escoge una rueda con fuga o daño de aro habiendo otra sana, y rechaza o alerta cuando no hay candidatos sanos.

### `[P0-04]` Eliminar el fallo silencioso cuando el compuesto solicitado no tiene stock
* **Archivos:** [rally_escort_vehicle.gd](../../scripts/rally/rally_escort_vehicle.gd#L1030-L1031), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L333-L357), [rally_event_manager.gd](../../scripts/rally/rally_event_manager.gd#L251-L350)
* **Problema actual:** Cuando `_find_best_pool_tire(wanted)` devuelve `{}`, `service_tire_inventory()` hace `continue` en silencio. La rueda anterior sigue montada físicamente, pero el borrador del Garaje y `RallyEventManager` registran el compuesto no disponible como confirmado.
* **Qué hacer:**
  * Deshabilitar en la UI los selectores de compuestos sin existencias utilizables mostrando el motivo (`"Sin stock disponible"`).
  * Hacer que `service_tire_inventory()` devuelva resultado estructurado (`{ok: bool, error: String, ...}`) y abortar `close_garage(true)` con aviso visible antes de persistir o confirmar en `RallyEventManager` si falla la validación.
* **Aceptación:** Ninguna acción puede desincronizar los compuestos montados reales de `tire_inventory.mounted` frente a `confirmed_setup` / `confirmed_compound_id`.

### `[P0-05]` Eliminar asignación ciega `pop_back()` de repuestos y botones muertos `+ <compuesto>` en Pausa
* **Archivos:** [rally_escort_vehicle.gd](../../scripts/rally/rally_escort_vehicle.gd#L1041-L1048), [rally_pause_inventory.gd](../../scripts/rally/rally_pause_inventory.gd#L555-L560), [rally_pause_inventory.gd](../../scripts/rally/rally_pause_inventory.gd#L736-L739)
* **Problema actual:**
  1. Cambiar la cantidad de repuestos en Garaje hace `spares.pop_back()` / `service_stock.pop_back()` a ciegas sin respetar compuesto ni estado.
  2. `RallyPauseInventory.show_inventory()` muestra botones `+ <compound>` siempre que `session.may_service_tires() and spares.size() < capacity`, pero `load_spare()` rechaza cualquier pulsación en modo pool (`"Pool de 10: sin reposición en tramo..."`), dejando controles falsos/inertes.
* **Qué hacer:**
  * Sustituir el ajuste numérico ciego de `0/1/2` en Garaje cuando está en modo pool por asignación explícita de slots de maletera (eligiendo qué ID del stock va a `Spare 1` / `Spare 2`).
  * En `RallyPauseInventory.show_inventory()`: ocultar los botones `+ <compound>` en modo pool cuando no proceda crear ruedas nuevas, o enlazar esa sección con el selector válido de parque si `session.may_service_tires()` está activo (sin botones muertos que siempre dan error).
* **Aceptación:** No existen botones visibles en Pausa/Inventario que rechacen sistemáticamente toda interacción en modo pool, y el jugador siempre elige exactamente qué ID entra/sale del maletero.

### `[P0-06]` Permitir reparación y gestión sobre `service_stock` en `RallyServicePanel`
* **Archivos:** [rally_service_panel.gd](../../scripts/rally/rally_service_panel.gd#L279-L288), [rally_service_panel.gd](../../scripts/rally/rally_service_panel.gd#L356-L366), [russia_rally.json](../../data/competition/events/russia_rally.json#L213)
* **Problema actual:** Entre etapas, `RallyServicePanel` ofrece checkboxes de reparación (`cost_inflate = 2` min, `cost_rim = 5` min) para `mounted` y `spares`, mientras que `service_stock` se renderiza como simple `Label` de solo lectura mediante `_add_stock_row()`. Las ruedas dañadas guardadas en el parque quedan irreparables para el resto del rally.
* **Qué hacer:**
  * Dotar a las filas de `service_stock` con pinchazo o aro deformado de los mismos checkboxes interactivos de reparación (`Inflar/sellar`, `Reparar aro`) contabilizando sus minutos contra el presupuesto de la ventana (`repair_minutes = 30`, penalización `10 s/min` si excede).
  * Opcionalmente, coordinar con el Garaje/Taller para que los cambios de rueda (`wheel_change = 1` min en `tire_rules.service_costs`) computen coherentemente si se realizan en ventana de servicio.
* **Aceptación:** Si una rueda con fuga o aro doblado fue movida a `service_stock`, puede repararse en el siguiente servicio intermedio y volver a quedar lista para uso.

### `[P0-07]` Añadir navegación por teclado y mando a `RallyTireStrategyScreen` y corregir `_reconcile_pool()`
* **Archivo:** [rally_tire_strategy_screen.gd](../../scripts/rally/rally_tire_strategy_screen.gd#L198-L200), [rally_tire_strategy_screen.gd](../../scripts/rally/rally_tire_strategy_screen.gd#L260-L269)
* **Problema actual:** `_gui_input()` descarta todo evento que no sea `InputEventMouseButton`, bloqueando al 100% a usuarios de teclado y mando en el reparto inicial de 10 ruedas. Además, `_reconcile_pool()` agrega `def_cid` en `spare_compounds` y recorta `service_extra_compounds.pop_back()` en vez de mover las piezas seleccionadas.
* **Qué hacer:**
  * Implementar foco explícito y navegación por teclado (`Flechas` / `WASD` / `Tab` / `Enter` / `Espacio` / `Esc`) y mando (`D-Pad` / `A` / `B` / `LB` / `RB`) sobre los grupos: ruedas montadas, maletero (0/1/2), distribución del stock de asistencia y botón de confirmar.
  * Corregir `_reconcile_pool()` para transferir explícitamente compuestos desde el parque disponible hacia los repuestos (y viceversa) sin inventar `def_cid` si había otros elegidos.
* **Aceptación:** Se puede completar íntegramente la selección de las 10 ruedas en la Etapa 1 usando solo teclado o solo mando, además de ratón.

### `[P0-08]` Corregir foco roto y mutación fantasma en pestaña Estrategia de `RallyGaragePanel`
* **Archivo:** [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L140), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L372), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L765-L767), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L1893-L1906)
* **Problema actual:** `STRATEGY_PATHS` solo lista `["fuel.initial_kg"]`, impidiendo navegar con teclado/mando hacia compuestos, repuestos y botones del pie. Al mismo tiempo, pulsar `Enter`/`Espacio`/`JOY_BUTTON_A` en `page == 2` invierte `new_tires_service`, variable oculta e ignorada en modo pool, pero evaluada en `_has_unapplied_changes()` (disparando el diálogo falso `"Cambios sin aplicar"` al pulsar `ESC`).
* **Qué hacer:**
  * Extender la matriz de navegación de `page == 2` a todos los controles interactivos del inventario por ID, selector de combustible y botones `CANCELAR` / `APLICAR`.
  * En modo pool, no mutar ni leer `new_tires_service`; usar el estado real del borrador de inventario en `_has_unapplied_changes()`.
* **Aceptación:** Abrir Garaje -> ir a Estrategia -> pulsar `Enter`/`A` o `ESC` sin hacer cambios reales no genera avisos falsos ni mutaciones ocultas, y todos los controles de neumáticos son alcanzables con D-Pad/flechas.

---

## 4. Fase 2 (P1 — Alto): Reglas de Servicio, Persistencia, Taller, Resultados y HUD

### `[P1-01]` Blindar `RallyGaragePanel.open_garage()` y `close_garage(true)` contra reglas de servicio y estado residual
* **Archivos:** [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L275-L357), [rally_vehicle_input_controller.gd](../../scripts/rally/rally_vehicle_input_controller.gd#L88-L90)
* **Problema actual:** `open_garage()` no resetea `mandatory_confirmation`, `compound_change_allowed` ni `allowed_compound_ids` heredados de una apertura previa. Además `close_garage(true)` ejecuta `vehicle.service_tire_inventory(...)` sin validar `session.may_service_tires()`, permitiendo cambiar neumáticos en mitad del tramo en modos donde la asistencia está prohibida.
* **Qué hacer:**
  * Resetear flags de restricción en `open_garage()` cuando no provenga de `open_garage_for_event()`, y consultar `session.may_service_tires()` antes de habilitar o aplicar cualquier cambio de compuestos/ruedas en `close_garage(true)`.
  * Mostrar visualmente candado/motivo en los controles bloqueados fuera de ventana de servicio.
  * Asegurar en `RallyVehicleInputController` / handler que `garage_menu_requested` respete restricciones de pausa o controles deshabilitados cuando proceda.

### `[P1-02]` Evitar doble servicio y pisado de estrategias mixtas en `_on_garage_closed()`
* **Archivos:** [rally_russia_stage_session.gd](../../scripts/rally/rally_russia_stage_session.gd#L1334-L1376), [rally_escort_vehicle.gd](../../scripts/rally/rally_escort_vehicle.gd#L257-L258), [rally_escort_vehicle.gd](../../scripts/rally/rally_escort_vehicle.gd#L939)
* **Problema actual:** `_on_garage_closed()` llama a `vehicle.apply_setup_snapshot(setup.values)` (que internamente llama a `service_tire_inventory()` otra vez), y después ejecuta `vehicle.set_tire_compound(event_manager.confirmed_compound_id)` —que solo toma `draft_compound_id` de `FL` (`rally_garage_panel.gd:161`)— antes de `apply_tire_inventory()`. Además el mensaje del HUD en `:1376` solo imprime `comp_label.to_upper()`.
* **Qué hacer:**
  * Aplicar `tire_inventory` por una única vía atómica sin llamadas redundantes ni `set_tire_compound(FL)` que puedan sobrescribir montajes mixtos.
  * En el banner de confirmación del HUD (`:1376`), si las 4 ruedas no comparten compuesto, mostrar resumen real (p. ej. `"MIXTO: FL/FR ... · RL/RR ..."`).

### `[P1-03]` Completar guardado/carga SQLite de estrategia por 4 ruedas y repuestos
* **Archivo:** [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L950-L969), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L1012-L1025)
* **Problema actual:** `save_setup()` solo persiste `draft_values` (sin `draft_wheel_compounds` ni `draft_spare_wheels`), y `load_setup()` intenta aplicar `strategy.wheel_compound.*` a través de `apply_setup_values()` (que los ignora) olvidando totalmente `strategy.spare_wheels`.
* **Qué hacer:**
  * Definir claramente qué debe persistir un preset de reglaje mecánico en SQLite: si incluye compuestos deseados por esquina/repuesto, serializarlos explícitamente en `save_setup()` y validarlos contra `allowed_compound_ids` y `service_stock` real en `load_setup()` antes de cargar el borrador (avisando si el stock actual no cubre el preset).

### `[P1-04]` Arreglar clic en `mouse-down` y pérdida de foco al cambiar de país en `RallyManiacMenu`
* **Archivo:** [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L842-L847), [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L996-L1020)
* **Problema actual:** Las tarjetas de etapa disparan `_on_stage_selected()` tanto en `btn.pressed` como en `gui_input` al presionar el botón izquierdo (`mouse-down`), impidiendo cancelar un clic erróneo. Además, `_on_country_selected()` destruye y reconstruye `screen_stage_select` y deshabilita el botón del país activo sin llamar a `grab_focus()`.
* **Qué hacer:**
  * Eliminar el disparo extra en `MOUSE_BUTTON_LEFT` dentro de `gui_input` y confiar únicamente en `btn.pressed` (con guardia anti-doble-ejecución durante transiciones).
  * Tras reconstruir `screen_stage_select` en `_on_country_selected()`, enfocar automáticamente un control válido visible (primer botón de tramo o siguiente país habilitado).

### `[P1-05]` Unificar entrada de Garaje y resolver colisión de `JOY_BUTTON_START`
* **Archivos:** [input_profile.json](../../data/input/input_profile.json#L125-L130), [input_profile.json](../../data/input/input_profile.json#L182-L186), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L523-L524)
* **Problema actual:** `"Toggle Garage"` solo tiene asignación en teclado (`G`), dejando sin acceso al usuario exclusivo de mando cuando no está en menú obligatorio; mientras que `JOY_BUTTON_START` abre Pausa en pista pero **aplica/cierra** dentro del Garaje (`close_garage(true)`), contradiciendo el rol estándar de cancelar/volver/pausar.
* **Qué hacer:**
  * Añadir botón de mando coherente o acceso desde Pausa para abrir el Garaje cuando corresponda.
  * Cambiar la confirmación en `RallyGaragePanel` para que use botón `A`/botón `"APLICAR"` (o `X`/`Y` dedicado con leyenda visible en pie), evitando usar `JOY_BUTTON_START` para confirmar cambios destructivos o de setup.

### `[P1-06]` Arreglar `RallyServiceWorkshop`: limpieza de foco visual, navegación 2D y estilos de estado
* **Archivo:** [rally_service_workshop.gd](../../scripts/rally/rally_service_workshop.gd#L93-L95), [rally_service_workshop.gd](../../scripts/rally/rally_service_workshop.gd#L219-L224), [rally_service_workshop.gd](../../scripts/rally/rally_service_workshop.gd#L329-L355)
* **Problema actual:** `cancel_transfer()` limpia `held = -1` pero no restaura `b.modulate = Color.WHITE`, congelando visualmente el resaltado del slot seleccionado. Además `_input()` recorre `buttons` como array 1D lineal sin corresponder al plano 2D del tablero, y los botones solo definen el StyleBox `"normal"`.
* **Qué hacer:**
  * Restaurar colores de todos los botones en `cancel_transfer()`.
  * Implementar vecinos espaciales explícitos (`focus_neighbor_left/right/top/bottom` o tabla 2D) entre ruedas montadas, repuestos, radiador y descarte.
  * Definir estilos consistentes `"normal"`, `"hover"`, `"focus"`, `"pressed"` y `"disabled"` sobre cada slot interactivo.

### `[P1-07]` Reportar `DESTALONADO` y desgaste transparente en `RallyPauseInventory._update_telemetry_panel()`
* **Archivo:** [rally_pause_inventory.gd](../../scripts/rally/rally_pause_inventory.gd#L829-L840)
* **Problema actual:** El panel de telemetría solo imprime `[FUGA]`, `[ARO]` o `%.0f%%` si el desgaste supera el `50%`, y omite completamente `carcass_failure` (`DESTALONADO`). Un neumático destalonado con `< 50%` de desgaste, sin fuga y sin daño de aro grave puede figurar como `[OK]`.
* **Qué hacer:**
  * Comprobar `is_carcass_destroyed(td)` antes que el resto y mostrar `[DESTALONADO]` en rojo crítico; mostrar siempre el `%` de vida/desgaste restante sin ocultarlo por debajo del `50%`.

### `[P1-08]` Corregir prioridad de `Enter`/`A` sobre el botón `"Taller"` en `RallyCompetitionPanel`
* **Archivos:** [rally_competition_panel.gd](../../scripts/rally/rally_competition_panel.gd#L401-L416), [rally_competition_panel.gd](../../scripts/rally/rally_competition_panel.gd#L766-L767), [rally_russia_stage_session.gd](../../scripts/rally/rally_russia_stage_session.gd#L808-L823)
* **Problema actual:** Aunque `present()` asigna el foco a `workshop_button`, `_unhandled_input()` captura `ui_accept` y emite `next_requested` siempre que `next_button.visible` es `true`, y descarta `ui_cancel` (`ESC`). Si el foco cae al `Tree` de clasificación o fuera de un `Button`, pulsar `Enter`/`A` salta el taller y pasa de tramo.
* **Qué hacer:**
  * Solo disparar `next_requested` en `_unhandled_input()` cuando ningún control con prioridad (`workshop_button`, `retry_button` o un botón activo) tenga el foco; asignar navegación D-Pad/Tab clara entre `workshop_button`, `retry_button` y `next_button` sin atrapar el foco dentro del `Tree` (`focus_mode = FOCUS_NONE` si es solo lectura).

### `[P1-09]` Reemplazar barras falsas en `RallyGaragePanel` por telemetría real
* **Archivo:** [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L1562-L1570), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L1996-L2004)
* **Problema actual:** La página Quick dibuja una barra de neumáticos con `var fraction := 0.65` fijo y `filled = false`, y la pestaña Estrategia dibuja la barra térmica también con `filled = false`.
* **Qué hacer:**
  * Alimentar la vista Quick con la salud media/mínima real de `tire_inventory.mounted` (vida útil, alertas activas) y pasar `filled = true` (con barra de progreso cromática correcta) en las barras de vida y ventana térmica.

### `[P1-10]` Anclar HUD de Fórmula al borde derecho para 21:9 / 32:9
* **Archivos:** [formula_hud_panels.gd](../../scripts/rally/formula_hud_panels.gd#L48-L49), [formula_hud_panels.gd](../../scripts/rally/formula_hud_panels.gd#L88-L94), [retro_hud_display.gd](../../scripts/rally/retro_hud_display.gd#L368)
* **Problema actual:** `TIMING_RECT := Rect2(1620, 24, 276, 132)` y `DAMAGE_RECT := Rect2(1620, 482, 276, 150)` usan coordenada `x = 1620` fija de `1920x1080` sin adaptarse a `size.x`, a diferencia de `RetroHudDisplay._draw_cards_ribbon()`.
* **Qué hacer:**
  * Calcular dinámicamente `x = max(size.x - margin - panel_w, ...)` respecto al rectángulo visible real de `FormulaHudPanels` en cada `NOTIFICATION_RESIZED` / `_draw()`.

---

## 5. Fase 3 (P2 — Medio): Sistema de Diseño, Idioma, Legibilidad y Datos

### `[P2-01]` Adoptar `RallyUITheme` como fuente única en toda la UI (+ transiciones nativas)
* **Archivos:** [rally_ui_theme.gd](../../scripts/rally/rally_ui_theme.gd#L1-L209), [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L1294), [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L1500), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd), [rally_tire_strategy_screen.gd](../../scripts/rally/rally_tire_strategy_screen.gd#L9), [rally_pause_inventory.gd](../../scripts/rally/rally_pause_inventory.gd)
* **Qué hacer:**
  * Reemplazar paletas dispersas, botones extruidos Win98/Aero, `_style_red_gold_button` y `_style_flat_button` (incluida la inconsistencia entre los `"◀ Back"` de Coche y Clima) por fábricas y tokens centralizados de `RallyUITheme` (`"Flat Precision"` / `WB_*`).
  * Implementar un helper nativo ligero basado en `Tween` (fade/escala de 120–180 ms, `PAUSE_MODE_PROCESS`, con soporte a preferencia de movimiento reducido y bloqueo anti-doble-clic durante la transición), sustituyendo la dependencia descartada de addons.

### `[P2-02]` Retirar o archivar `RallyEventMenu` huérfano
* **Archivos:** [rally_event_menu.gd](../../scripts/rally/rally_event_menu.gd#L1-L79), [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L1782-L1796)
* **Problema actual:** `rally_event_menu.gd` tiene controles Godot sin estilo ni márgenes y `0` referencias activas.
* **Qué hacer:** Confirmar si algún script de soporte o escena oculta lo referencia; si no se utiliza en ningún flujo de runtime ni prueba, eliminarlo o moverlo a archivo legado para evitar confusión técnica.

### `[P2-03]` Unificar idioma a español y actualizar pies de atajos
* **Archivos:** [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L702-L711), [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L957), [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L1292), [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L1327), [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L1498), [rally_maniac_menu.gd](../../scripts/rally/rally_maniac_menu.gd#L1577-L1655), [rally_competition_panel.gd](../../scripts/rally/rally_competition_panel.gd#L365), [rally_competition_panel.gd](../../scripts/rally/rally_competition_panel.gd#L814), [rally_competition_panel.gd](../../scripts/rally/rally_competition_panel.gd#L973)
* **Qué hacer:**
  * Traducir o unificar al español las cadenas en inglés de `RallyManiacMenu`: `"Championship"` -> `"Campeonato"`, `"Rally"` -> `"Rally"`, `"Single Stage"` -> `"Tramo Único"`, `"Exit"` -> `"Salir"`, `"SELECT STAGE"` -> `"SELECCIONAR TRAMO"`, `"SELECT CAR"` -> `"SELECCIONAR COCHE"`, `"Select Starting Weather"` / `"SELECT WEATHER"` -> `"CLIMA INICIAL"`, `"◀ Back"` -> `"◀ Volver"`. Revisar contratos que busquen textos exactos de botón (p. ej. `rally_maniac_menu_contract.gd`, `car_select_gui_contract.gd`, `weather_select_menu_contract.gd`) y actualizar textos o usar nombres estables de nodo / metadatos si los tests buscan por texto.
  * Actualizar `shortcuts_label` en `RallyCompetitionPanel` para incluir la tecla/botón de `[Taller]` cuando esté disponible y glifos equivalentes de mando (`A`/`B`/`X`).

### `[P2-04]` Corregir coloración real de errores en `RallyGaragePanel._show_notice()`
* **Archivo:** [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L327), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L346), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L1016), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L1068-L1073), [rally_garage_panel.gd](../../scripts/rally/rally_garage_panel.gd#L1210-L1215)
* **Qué hacer:** Guardar explícitamente el flag booleano `notice_is_error` pasado a `_show_notice(message, is_error)` en lugar de adivinarlo buscando subcadenas en `_notice_is_error()`, garantizando que errores como `"Compuesto no permitido en este evento."` o `"Confirma reglajes para continuar."` se rendericen en `C_ROSE`.

### `[P2-05]` Adaptar diseño de `RallyTireStrategyScreen` y desahogar `_draw_tires()` en HUD
* **Archivos:** [rally_tire_strategy_screen.gd](../../scripts/rally/rally_tire_strategy_screen.gd#L9), [rally_tire_strategy_screen.gd](../../scripts/rally/rally_tire_strategy_screen.gd#L178-L185), [formula_hud_panels.gd](../../scripts/rally/formula_hud_panels.gd#L315-L348)
* **Qué hacer:**
  * Escalar limpiamente `RallyTireStrategyScreen` usando contenedores Godot o escala proporcional centrada para soportar `16:9`, `16:10`, `21:9` y ventanas pequeñas sin cortar tarjetas en `_draw_stock_selection()`.
  * En `FormulaHudPanels._draw_tires()` (`TIRES_W = 300`), dar mayor holgura vertical/horizontal o priorización de alertas para que posición (`FL/FR/RL/RR`), `kPa`, `"ALIN."`, `"ARO"` y `"PINCHADO"`/`"FUGA"`/`"DESTAL."` no se solapen ni recorten cuando coincidan varios daños.

### `[P2-06]` Corregir descripciones erróneas de asfalto en `rally_compounds.json`
* **Archivo:** [rally_compounds.json](../../data/tires/rally_compounds.json#L187-L188), [rally_compounds.json](../../data/tires/rally_compounds.json#L241)
* **Qué hacer:** Cambiar `"Buen rendimiento en grava seca..."` en `asphalt_dry` y `"Mejor respuesta sobre grava mojada..."` en `asphalt_wet` por descripciones correctas de asfalto seco y asfalto mojado.

---

## 6. Fase 4: Reparación de Contratos Rotos, Nuevas Pruebas y Fugas de Memoria

### `[TEST-01]` Reparar contratos actualmente rotos o bloqueados
1. **[pause_map_contract.gd](../../tests/rally/pause_map_contract.gd#L33)**: Debe pasar limpiamente tras `[P0-01]`; además añadir `quit(1)` en los caminos de fallo de aserción para evitar que Godot headless quede colgado.
2. **[competition_session_contract.gd](../../tests/rally/competition_session_contract.gd#L68-L87)**: Inspeccionar y corregir por qué fallan `"clock runs after green while parked"` (`:68`, `:70`, probable relación directa con `practice_mode` abriendo el garaje en `_ready()`) y `"rescue applies one penalty without retirement"` (`:87`).
3. **[damage_system_contract.gd](../../tests/rally/damage_system_contract.gd#L32)**: Inspeccionar y corregir las 3 aserciones fallidas al final del test (`:32` `domain_hashes must include damage`, `:115` `reset_for_stage must reset damage to 0`, `:322` `Should not repair if radiator damage < 5%`). Revisar si se debe corregir la implementación del sistema de daños, la firma de `domain_hashes`, o actualizar el contrato si la regla cambió intencionadamente.
4. **[russia_stage_transition_contract.gd](../../tests/rally/russia_stage_transition_contract.gd)**: Perfilar qué bloquea el avance después de `RALLY_STAGE_TRANSITION_READY stage=russia_stage3` (`tick_id: 723`) y eliminar el bloqueo o ajustar el avance simulado hasta pasar en verde.
5. **[rally_maniac_menu_contract.gd](../../tests/rally/rally_maniac_menu_contract.gd)**: Optimizar cargas repetidas de escena o documentar/ajustar el timeout mínimo a `35s` si el test carga 3 veces escenas completas de tramo.

### `[TEST-02]` Limpieza de fugas `ObjectDB` / `resources still in use`
* Ejecutar con `--verbose` los scripts que hoy filtran objetos al salir:
  * `tire_inventory_contract.gd` (`76 ObjectDB`)
  * `competition_session_contract.gd` (`76 ObjectDB`)
  * `service_workshop_contract.gd` (`10 ObjectDB`, `4 resources`)
  * `weather_select_menu_contract.gd` (`2 ObjectDB`, `1 resource`)
  * `rally_final_results_contract.gd` (`2 ObjectDB`, `1 resource`)
* Liberar con `free()` / `queue_free()` los nodos, recursos temporales o señales cíclicas antes de `quit()`.

### `[TEST-03]` Añadir cobertura automática para las correcciones de inventario y UX-UI
Agregar casos en los contratos de `game/tests/rally/` que verifiquen automáticamente:
1. Cambio de una rueda montada desgastada o pinchada por otra sana del **mismo compuesto** desde `service_stock` en `RallyGaragePanel`, conservando IDs y ubicaciones tras guardar, salir y abrir el siguiente tramo.
2. `_find_best_pool_tire()` excluyendo ruedas con `is_punctured()` / `is_rim_damaged()` y rechazando cambios sin stock disponible sin desincronizar `confirmed_compound_id` ni `tire_inventory`.
3. Reparación de ruedas ubicadas en `service_stock` desde `RallyServicePanel` descontando los minutos correctos.
4. Bloqueo estricto de `may_service_tires()` al abrir Garaje en mitad de tramo sin ventana de servicio.
5. Persistencia SQLite (guardar y cargar 4 compuestos + repuestos en modo pool y modo libre).
6. Navegación 100% teclado y mando en `RallyTireStrategyScreen`, `RallyGaragePanel` (pestaña Estrategia), `RallyServiceWorkshop`, `RallyManiacMenu` (incluyendo cambio de país sin perder foco) y `RallyCompetitionPanel` (`workshop_button` con prioridad sobre `next_requested` cuando tiene foco).

---

## 7. Checklist Final de Aceptación antes de Cerrar

- [ ] Todos los contratos nuevos y existentes en `game/tests/rally/` ejecutan hasta terminar (`PASS`) sin `TIMEOUT`, sin `Assertion failed` y sin `ERROR:` de engine o script.
- [ ] Recorrido manual completo en juego real: **Menú principal -> Selección de tramo/coche/clima -> Estrategia inicial (10 ruedas con mando/teclado y ratón) -> Etapa 1 -> Pausa / Telemetría / Maletera -> Fin de etapa (`Taller`) -> Etapa 2 -> Servicio intermedio (reparar rueda en `service_stock` + cambiar por mismo compuesto en Garaje) -> Guardar/Cargar preset SQLite -> Etapa 3 -> Resultados finales**.
- [ ] Cero inconsistencias visuales entre botones/paneles (`RallyUITheme` unificado) y HUD legible en `16:9` y `21:9`.
