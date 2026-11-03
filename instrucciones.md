# Daños simcade del Ford Escort RS2000

## Alcance y estado

Implementar daños acumulativos del radiador y del motor en Rusia Etapa 1 (`russia_stage1`). Internamente ambos estados se almacenan como fracción normalizada (`0.0` a `1.0`) y se presentan en el HUD de `0` a `100%`. Empiezan en cero al iniciar o reiniciar la etapa (`RallyEscortVehicle.prepare_for_stage()` / `VehicleThermalModel.reset_for_stage()`). La pausa (`rally_pause_inventory.gd`) y la recolocación/rescate en pista (`on_vehicle_reset_requested()` / `reset_to_pose()`) conservan el daño acumulado. El coche debe poder terminar la etapa aun con daños graves.

El commit `bf57682` contiene el estado previo publicado. Ya existe un borrador local de `game/data/vehicles/ford-escort-rs2000/damage.json` con sintaxis validada que debe ampliarse con los parámetros de zonas, curvas y vapor descritos abajo. Queda integrar el perfil, la física, el HUD y el vapor, y validar en juego.

## Perfil del coche

Registrar `damage.json` bajo `domains.damage` en `game/data/vehicles/ford-escort-rs2000/vehicle.json`. Cargarlo con `VehicleProfileLoader` (`game/scripts/physics/profile_loader.gd`) e incluirlo automáticamente en `domain_hashes` (usado también por `RallyGaragePanel._database_context()`). Mantener `damage` fuera de `REQUIRED_DOMAINS` para que los perfiles antiguos o sin este dominio conserven el comportamiento anterior con daño cero y factores en `1.0`. Si el dominio está presente, validar en `VehicleProfileLoader`:

- `schema_version >= 1` y valores numéricos finitos.
- `collision` y `landing`: `0.0 < minimum_speed_m_s < full_severity_speed_m_s`, `maximum_radiator_damage` y `maximum_engine_damage` en `[0.0, 1.0]`, `severity_exponent > 0.0`, y pesos de zona en `[0.0, 1.0]`.
- `thermal`: `minimum_cooling_factor` y `minimum_torque_factor` en `(0.0, 1.0]`, `damage_start_c < full_rate_temperature_c`, `grace_seconds >= 0.0` y `maximum_damage_per_second >= 0.0`.
- `steam`: `0.0 <= start_damage < continuous_damage < heavy_damage <= 1.0`.

El JSON define umbrales, curvas, máximos por evento, límites geométricos y pesos por zona, refrigeración residual, límites de par, exposición térmica y parámetros de vapor. Los porcentajes en vivo (`radiator_damage`, `engine_damage`, `overheat_exposure_s`) pertenecen al estado de la sesión en `VehicleThermalModel` y se publican en el snapshot de motor (`get_engine_thermal_state_snapshot()` y `published_state["engine"]`).

## Choques y aterrizajes

- Recoger los contactos de carrocería en `RallyEscortVehicle._integrate_forces()` (`game/scripts/rally/rally_escort_vehicle.gd`). Medir la velocidad relativa de acercamiento sobre la normal (`closing_speed = maxf(0.0, -rel_velocity.dot(normal))`, descartando velocidades de separación), el impulso (`state.get_contact_impulse(index).length()`) y la posición en el espacio local del coche (`state.transform.affine_inverse() * state.get_contact_collider_position(index)`), con `-Z` hacia delante (`bounds_world_metres` del Escort: `z ∈ [-1.84, 2.19]`, `x ∈ [-0.81, 0.81]`, `y ∈ [0.005, 1.29]`; ejes en `z = -1.205` y `z = +1.205`).
- Separar los contactos con obstáculos de los apoyos en terreno usando `collider.get_meta("collision_role", "")` (`"barrier"` / `"obstacle"` frente a `"terrain"` en `RallyTrackCollisionBuilder`) y la orientación de la normal (`absf(normal.y) < 0.5` indica impacto contra pared/obstáculo incluso si el objeto pertenece al grupo de superficie). Exigir un impulso mínimo proporcional a la masa (`impulse >= mass * min_impulse_speed_m_s`) para ignorar roces leves.
- Agrupar los contactos del mismo golpe en un único evento de choque (resolviendo el contacto o agregado de mayor severidad del impacto) y aplicar el daño una sola vez. Mantener un bloqueo de contacto activo por fuente/zona y permitir otro evento únicamente tras separarse durante varios frames físicos consecutivos (o tras vencer una histéresis de separación). Un aterrizaje seguido de un choque contra una barrera evalúa dos canales distintos (`landing` y `collision`) y puede producir dos eventos independientes.
- Ponderar choques por zona local (`x`, `y`, `z`):
  - **Morro (`nose`)**: `z <= -1.25` y altura media (`y >= 0.22`). Es la zona más vulnerable del radiador (peso `1.0` radiador, `0.65` motor en impacto frontal fuerte).
  - **Bajos delanteros (`front_underbody`)**: `z < -0.35` y parte baja del chasis (`y < 0.28`, teniendo en cuenta que `build_collision_shapes()` eleva el plano inferior de colisión a `minimum_collision_y ≈ 0.14 m`). Pesa más para el motor/cárter (`0.55` radiador, `1.0` motor).
  - **Costado (`side`)**: predominio lateral (`absf(x) > 0.55` y `z ∈ [-1.25, 1.35]`) o normal lateral. Efecto menor en ambos (`0.20` radiador, `0.20` motor).
  - **Cola (`rear`)**: `z > 1.35`. Efecto mínimo en el tren delantero (`0.08` radiador, `0.12` motor).
- Detectar la toma de tierra combinando los contactos de las cuatro ruedas (`simulation.suspension_model.contact_active` / `wheel_loads`) y los contactos de la carrocería (`state.get_contact_count()`), ya que en saltos limpios las ruedas (`ShapeCast3D`) tocan suelo antes o sin que colisione el `RigidBody3D` del chasis:
  - Mientras las 4 ruedas y la carrocería están en el aire, registrar el estado aéreo y conservar la velocidad vertical de caída previa al toque (`fall_speed_m_s = maxf(0.0, -state.linear_velocity.y)` del último paso en el aire).
  - En el primer paso que recupera soporte en suelo, resolver la primera zona que recibe carga (si llegan varios contactos en el mismo paso, usar la distribución de carga normal inicial de ruedas delanteras/traseras e impulso vertical de carrocería, o el cabeceo `pitch` del chasis, para decidir la zona dominante).
  - Distinguir en aterrizaje: **ruedas delanteras (`front_wheels`)**, **morro (`nose`)**, **bajos delanteros (`front_underbody`)**, **cola (`rear`)** y **ruedas traseras (`rear_wheels`)**. Un golpe directo de carrocería (`nose` / `front_underbody`) pesa más (`0.85–1.0`) que un apoyo equivalente absorbido por las ruedas (`0.25–0.45`).
- Compartir el evento de aterrizaje con `rally_vehicle_audio.gd` a través de `body_contact_audio["landing_speed_ms"]` (para que el audio de aterrizaje suene también cuando el coche aterriza sobre las ruedas sin golpear el chasis) y conservar `2,5 / 4,0 / 7,0 m/s` (`LAND_MIN_MS`, `LAND_MID_MS`, `LAND_HIGH_MS`) como referencias iniciales de gravedad sonora. Los apoyos suaves (`< 2,5 m/s`) y los roces sostenidos no suman daño. Las tomas duras suman desgaste gradual durante la etapa.

Valores iniciales del JSON:
- **Choque (`collision`)**: entre `4,0` y `23,0 m/s`, con máximos por evento de `0.55` (55 puntos) de radiador y `0.26` (26 puntos) de motor antes de ponderar por zona (`severity = pow(clamp((v - min) / (full - min), 0, 1), severity_exponent)`).
- **Aterrizaje (`landing`)**: entre `2,5` y `9,0 m/s`, con máximos de `0.10` (10 puntos) de radiador y `0.08` (8 puntos) de motor antes de ponderar por zona.
- Ajustar la curva y los pesos conduciendo.

## Refrigeración y motor

- En `VehicleThermalModel.advance_engine()` (`game/scripts/physics/thermal_model.gd`), aplicar el factor de radiador a la conductancia total de refrigeración del agua:
  `radiator_cooling_factor = lerpf(1.0, minimum_cooling_factor, radiator_damage)`
  `water_cooling_conductance_w_k = (base_conductance + float(water_flow.conductance)) * radiator_cooling_factor`
  A `100%` de daño (`radiator_damage = 1.0`), el objetivo inicial es conservar un `45%` de capacidad (`minimum_cooling_factor = 0.45`).
- Usar la temperatura resultante (`water_temperature_c`) para la pérdida térmica temporal de par existente (`_update_torque_derating()`). El perfil actual del Escort (`powertrain.json`) empieza a reducir par de agua a `105 °C`, marca `115 °C` como temperatura crítica y define `minimum_hot_engine_torque_fraction = 0.85`.
- Acumular daño permanente de motor por sobretemperatura cuando `water_temperature_c > damage_start_c` (`110 °C`):
  - Incrementar el tiempo de exposición `overheat_exposure_s` mientras el agua supere `110 °C`. Al bajar de `110 °C`, detener la acumulación de daño y descargar progresivamente el contador de exposición (p. ej. a razón de `2.0 s` por segundo debajo del umbral, o reiniciarlo al enfriarse bajo `108 °C`) para evitar que oscilaciones breves en el borde reinicien o disparen en falso la ventana de gracia.
  - Tras superar `grace_seconds` (`6,0 s`) de exposición continua sobre `110 °C`, acumular daño en `engine_damage` escalando la tasa con el exceso de temperatura entre `damage_start_c` (`110 °C`) y `full_rate_temperature_c` (`120 °C` inicial), limitada a `maximum_damage_per_second = 0.015` (`1,5` puntos por segundo).
  - Al enfriarse, se detiene la acumulación permanente y se recupera la pérdida temporal por calor (`thermal_torque_fraction` vuelve hacia `1.0`), pero el daño permanente acumulado en `engine_damage` se conserva. Los golpes directos y el calor suman al mismo estado `engine_damage`.
- Aplicar el efecto permanente al par disponible en `_update_torque_derating()`:
  - Combinar el factor térmico temporal (`thermal_torque_fraction`, que baja hasta `0.85` en caliente) con el factor permanente por daño de motor (`permanent_torque_fraction = lerpf(1.0, permanent_minimum_torque_factor, engine_damage)`) de modo que `available_engine_torque_fraction = clampf(thermal_torque_fraction * permanent_torque_fraction, minimum_torque_factor, 1.0)` (o calibrando `permanent_minimum_torque_factor ≈ 0.70` y el piso combinado en `minimum_torque_factor = 0.60`), conservando aproximadamente el `60%` del par sano en condiciones equivalentes de daño máximo y sobrecalentamiento.
  - Mantener intacto el corte por falta de combustible en `FordRallyVehicleSimulation._prepare_powertrain()` (`thermal_model.engine_torque_factor() if thermal_model.fuel_remaining_litres > 0.0 else 0.0`).
  - Limitar `radiator_damage` y `engine_damage` a `0.0–1.0` (`0–100%`) y reiniciarlos únicamente en el flujo de nueva etapa (`reset_for_stage()`).

## HUD

Añadir un bloque independiente al HUD de rally en `game/scripts/rally/formula_hud_panels.gd`, anclado a la derecha y centrado verticalmente en el lienzo de diseño `1920×1080` (p. ej. `DAMAGE_RECT := Rect2(1620, 482, 276, 116)`, libre de colisión con `TIMING_RECT` en `y = 24..156`, el botón de pausa en `y = 12..48` y el bloque de combustible en `y = 896..1056`).

- Mantener el lenguaje visual del HUD actual (`_glass`, `C_FACE`, `_bevel`, campos `_sunken` en `C_FIELD`, etiquetas en `BOLD` y porcentajes en `DIN_BOLD`).
- Mostrar dos barras horizontales con porcentaje numérico visible (`0%` a `100%`): **`RADIADOR`** arriba y **`MOTOR`** abajo.
- Una barra vacía representa `0%` de daño y se llena de izquierda a derecha conforme sube el porcentaje, modulando el color según severidad (`< 25%` verde/azul nominal, `25–50%` dorado/ámbar, `50–75%` naranja cálido, `>= 75%` rojo crítico).
- El bloque muestra el daño acumulado (`radiator_damage` y `engine_damage`) mientras el indicador térmico existente (`WATER` y `OIL` en `RetroHudDisplay`) sigue mostrando la temperatura en grados.

## Vapor del radiador

Anclar un emisor 3D (`GPUParticles3D`) a la parrilla delantera del Escort (posición local de referencia `Vector3(0.0, 0.48, -1.76)`) e integrarlo en `RallyVehicleVFX` (`game/scripts/rally/rally_vehicle_vfx.gd`). Usar vapor blanco/gris claro con intensidad modulada por `radiator_damage`, temperatura del refrigerante (`water_temperature_c`) y carga de motor (`load`).

| Daño | Emisión |
| --- | --- |
| Menos de 25% | Sin emisión visible (`emitting = false`) |
| 25 a menos de 50% | Bocanadas ligeras e intermitentes (pulsos modulados en el tiempo) |
| 50 a menos de 75% | Emisión continua y moderada |
| 75 a 100% | Emisión densa y sostenida |

Detalles técnicos de integración:
- **Exclusión de carrocería en el shader**: `rally_vehicle_vfx.gdshader` aplica una máscara `exterior_visibility` que anula el `ALPHA` dentro de una caja alrededor del chasis (`z ∈ [-2.05, 2.05]`) para que el polvo de las ruedas no atraviese el habitáculo. Como la parrilla (`z ≈ -1.76`) cae dentro de esa caja, añadir un `uniform float body_exclusion_strength = 1.0` (o `uniform bool use_body_exclusion = true`) en `rally_vehicle_vfx.gdshader` y desactivarlo o reducirlo en el material exclusivo del emisor de vapor para que sea visible desde su nacimiento en la parrilla.
- **Dinámica y cámara**: Suavizar las transiciones de emisión (`lerpf` temporal). Reducir la emisión con el agua fría (`< 75 °C`) y aumentarla cuando el refrigerante supera la ventana óptima (`> 95–110 °C`) y bajo carga (`load`). A baja velocidad el vapor sube por flotabilidad (`+Y`); en marcha la dirección e impulso inicial se inclinan hacia atrás (`+Z` local / `-velocity` mundial) proporcionalmente a la velocidad del coche.
- **Legibilidad en cámara de capó**: La cámara `BONNET` (`RallyChaseCameraRig.bonnet_offset_metres = Vector3(0.0, 1.02, -0.55)`) mira directamente por encima del capó. Limitar la densidad/opacidad máxima y aplicar un factor de atenuación adicional cuando `camera_mode == Mode.BONNET` para no cegar la vista del tramo.
- Parametrizar en `damage.json` los umbrales (`start_damage`, `continuous_damage`, `heavy_damage`), la posición local, la intensidad máxima, la escala en cámara de capó y la influencia térmica. Reiniciar el emisor en `reset_effects()` y al iniciar una etapa.

## Implementación y aceptación

1. **Perfil y estado de sesión**: Registrar `damage.json` en `vehicle.json`, validar en `VehicleProfileLoader` (carga, hashes, valores límite y compatibilidad con perfiles sin `damage`), e inicializar/reiniciar estados en `VehicleThermalModel` y `RallyEscortVehicle`.
2. **Contactos, aterrizajes y audio**: Conectar impactos de carrocería y tomas de tierra (ruedas + chasis) en `rally_escort_vehicle.gd` y `rally_vehicle_audio.gd`. Verificar choque frontal, bajos delanteros, lateral y trasero, impacto sostenido sin duplicación, separación y segundo choque, y tomas de morro, bajos y cola con gravedad equivalente.
3. **Modelo térmico y par**: Conectar `radiator_damage` a `water_cooling_conductance_w_k` y la exposición sobre `110 °C` (> `6 s`) a `engine_damage` y al par disponible en `thermal_model.gd`. Comparar coche sano y dañado bajo la misma carga. Comprobar que el calor breve (< `6 s`) no suma daño permanente, el calor sostenido sí, el enfriamiento recupera solo la fracción temporal de par y el corte por falta de combustible sigue anulando el par.
4. **HUD y vapor**: Integrar el panel derecho (`RADIADOR` / `MOTOR`) en `formula_hud_panels.gd` y el emisor de parrilla en `rally_vehicle_vfx.gd` / `rally_vehicle_vfx.gdshader`. Comprobar porcentajes, posición del HUD sin solapes, transiciones por tramo de daño y densidad en cámara de persecución (`CHASE`) y capó (`BONNET`), tanto en frío como bajo carga.
5. **Calibración en Rusia Etapa 1**: Comparar una pasada limpia, saltos fuertes repetidos y un choque frontal seguido de conducción bajo carga. La pasada limpia debe mantener el daño en niveles despreciables y permitir competir, los saltos duros deben acumular daño gradualmente y el choque fuerte debe tener un efecto térmico y mecánico perceptible sin impedir terminar la etapa. Registrar por separado las comprobaciones automáticas (contratos headless en `game/tests/rally/`) y la validación conduciendo.

