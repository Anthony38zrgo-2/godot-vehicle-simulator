# Plan: diferenciación climática regional — frío de Suecia vs calor de Kenia

Objetivo: que el clima afecte de verdad a las temperaturas de cada componente, con el reparto físico acordado:

- **Neumático → manda la superficie** (`ground_c`), con el sol como carga directa sobre la banda.
- **Frenos y motor/radiador → mandan el aire** (`air_c`), con el sol como carga de vano/disco.
- **Sin país en la física**: `thermal_model.gd` nunca distingue Suecia/Kenia. La diferencia nace en el clima: `clima = estado global × perfil regional`.

## Estado actual (verificado en código)

| Hallazgo | Evidencia |
|---|---|
| "Soleado" es idéntico en Suecia y Kenia | `rally_weather_scheduler.gd:155 _resolve_climate_values()` no recibe la región; `presets.sunny.air_temperature_c = [18, 27]` global |
| `surface_profiles` idénticos entre regiones | `rally_weather_presets.json`: kenya_safari y sweden_winter comparten absorción 0.62 / capacidad 900 / intercambio 9 |
| La irradiancia nunca llega a la física | 0 referencias a `irradiance` en `game/scripts/physics` |
| `start_temperature_policy` es dato muerto | declarado en los 5 eventos, 0 consumidores (deuda documentada) |
| Neumático ya tiende al suelo | `tires.json`: `road_conductance 50-60` vs `tread_to_air 30 + convection 6` |
| Frenos ya son aire | `_brake_heat_losses()`: convección + radiación contra `T_aire`; discos nacen a `max(25, ambient)` |
| Motor ya es 1:1 con ambiente | `water_rejected = G·(Tw − Tamb)`; `G = 70 + conducto(v)`; aceite solo 12 W/K al aire |

## Principios de diseño

1. La región modula **magnitudes** (offset de aire, escala de irradiancia, perfiles de suelo); el estado aporta la **forma** (soleado/nublado/lluvia).
2. Cada componente escucha su sumidero natural: goma→suelo, frenos/motor→aire. El sol entra como carga (W), no como temperatura.
3. Sin listas de países en scripts: los valores viven en `rally_weather_presets.json` (región) y `tires.json`/`brakes.json`/`powertrain.json` (componente).
4. Valores iniciales conservadores; el balance fino se hace conduciendo, no en JSON de una sentada.

---

## Fase 1 — Región como modulador del clima (bloqueante)

Sin esto, Suecia soleada sigue saliendo a 18-27 °C y nada más importa.

1.1 `game/data/weather/rally_weather_presets.json` — en cada `regional_profiles` añadir:

```json
"air_offset_c": <float>,
"irradiance_scale": <float>
```

| Perfil | air_offset_c | irradiance_scale | Efecto en "soleado" |
|---|---|---|---|
| kenya_safari | +4.0 | 1.10 | aire 22-31 °C, sol ~800-1050 W/m² |
| sweden_winter | -12.0 | 0.85 | aire 6-15 °C (bajo cero en nublado/nieve), sol ~600-820 |
| russia_summer | 0.0 | 1.0 | sin cambio |
| finland_autumn | -2.0 | 0.95 | ligeramente más fresco |
| switzerland_alpine | 0.0 | 1.0 | sin cambio (alpino templado) |

1.2 `game/scripts/rally/rally_weather_scheduler.gd`:
- `_resolve_climate_values(rng, preset, prev_climate, regional)`: aplicar `air += air_offset_c` e `irr *= irradiance_scale` tras el muestreo (`:177-178`).
- Call site `:372` pasa `regional`.
- La liaison (`:213`, `ambient_air_c = lerpf(8, 22, solar)`) y las relajaciones `ground→air` (`:391/397/401`) usan el aire ya corregido; opcional: desplazar también `ambient_air_c` de liaison con el offset para continuidad entre especiales.

Resultado: el mismo estado "sunny" produce climas distintos por región, y el aire regional llega solo a frenos/motor (y templa el suelo vía `air_loss` en `rally_surface_model.gd`, que no se toca).

## Fase 2 — Superficie por región (el sumidero del neumático)

2.1 `rally_weather_presets.json` — diferenciar `surface_profiles` dentro de cada región (hoy copiados 1:1):

- **kenya_safari** (retener calor en el suelo):
  - `Road.solar_absorption` 0.78 → 0.85; `Gravel` 0.62 → 0.68
  - `air_exchange_w_m2_k` × 0.85 en todos (9→8, 10→8.5): el suelo caliente se deshace menos rápido
- **sweden_winter** (suelo frío que persiste):
  - `solar_absorption` 0.62/0.78 → 0.35/0.45 (nieve refleja)
  - `air_exchange_w_m2_k` 9/10 → 11/12 (el suelo sigue al aire frío)
  - `thermal_capacity_kj_m2_k` × 0.8 (el frío se instala rápido)
- resto de regiones: sin cambios.

2.2 No tocar `rally_surface_model.gd`: ya consume los perfiles.

Resultado esperado: suelo de Kenia al sol 35-45 °C; suelo de Suecia -5…+2 °C sostenido.

## Fase 3 — Neumático: suelo dominante + sol directo

3.1 `game/data/vehicles/ford-escort-rs2000/tires.json` (3 bloques `thermal`):

| Parámetro | Actual | Nuevo | Por qué |
|---|---|---|---|
| road_conductance_w_k | 50/60/55 | 80/90/85 | el suelo fija el equilibrio de la banda |
| tread_to_air_w_k | 30 | 18 | el aire pasa a secundario |
| carcass_to_air_w_k | 15 | 9 | ídem para carcasa |
| convection_velocity_gain_w_k | 6.0 | 8.0 | la velocidad sigue enfriando algo, sin dominar |

3.2 `game/scripts/physics/thermal_model.gd` `advance_tire()`: carga solar directa a la banda:

```
zone_heat += tread_solar_absorption * irradiance_w_m2 * tread_solar_area_m2
```

Nuevos campos en `tires.json.thermal`: `tread_solar_absorption: 0.8`, `tread_solar_area_m2: 0.025` por zona → ~18 W/rueda con sol de Kenia (~900 W/m²), ~0 en Suecia nublado.

3.3 Plomería de irradiancia (hoy no llega a la física):
- `vehicle_simulation._local_conditions_at_contact()` ya mergea el clima de la zona: exponer `irradiance_w_m2` en el dict local (default 0 sin weather controller).
- `advance_tire(..., irradiance_w_m2: float = 0.0)` nuevo parámetro al final de la firma.

3.4 Nieve: el enfriamiento actual (7.0 W/K·mm × `snow_cooling_gain`) se mantiene. Si Suecia debe castigar más, subir la constante a 9.0 en un ajuste posterior (decisión de balance, fuera de esta fase).

Resultado: banda anclada al suelo (80-90 W/K vs 18 de aire). Suecia: difícil calentar. Kenia al sol: difícil bajar (suelo caliente + 18 W solares).

## Fase 4 — Frenos: aire dominante, más sensibles al ambiente

4.1 `game/data/vehicles/ford-escort-rs2000/brakes.json`:
- `rotor_radiation_ambient_view_factor` 0.4/0.3 → 0.6 (la radiación es puramente contra el ambiente y pesa en parado/lento, donde Kenia debe sufrir).
- Sin cambios de masa térmica (conserva inercia real).

4.2 `thermal_model.gd _brake_heat_losses()`: soak solar al disco, relevante solo parado/lento:

```
solar_w = rotor_radiation_emissivity * view_factor * irradiance_w_m2 * area * solar_soak_k
```

con `solar_soak_k` nuevo campo (`brakes.json.thermal`, ~0.02) y gate por velocidad (`smoothstep` decaído por encima de ~8 m/s) → ~15 W en Kenia sol, 0 en movimiento rápido y en Suecia.

4.3 Comportamiento en frío ya correcto: los discos nacen a `max(initial, ambient)` y `cold_efficiency 0.85` hasta 150 °C. En Suecia el warm-up se alarga solo, sin código nuevo.

## Fase 5 — Motor/radiador: aire dominante

5.1 `game/data/vehicles/ford-escort-rs2000/powertrain.json`:
- `oil_sump_cooling_conductance_watts_per_kelvin` 12 → 22 (el aceite siente el ambiente).
- `base_cooling_conductance_watts_per_kelvin` 70 → 85 (parado/lento más sensible al aire frío/caliente).

5.2 `thermal_model.gd advance_engine()`: calor solar al vano (como en frenos):

```
generated_heat += solar_heat_gain_w_per_kw_m2 * irradiance_w_m2
```

nuevo campo `engine_config.thermal` (~0.08 W por W/m² → ~70 W con sol de Kenia). Es poco frente a los 12 kW de idle, pero sube el techo en paradas al sol.

5.3 El efecto principal llega gratis con la Fase 1: en equilibrio `Tw = Tamb + P/G` → +10 °C de aire = +10 °C de agua. Kenia soleado (aire 22-31) acerca al derate (105) y al daño (110); Suecia lo aleja.

## Fase 6 — Temperatura de salida a tramo (activar dato muerto)

6.1 Consumir `start_temperature_policy` (hoy declarado en los 5 eventos y sin lector). Implementar en el precalentamiento (`fresh_tire_state` / `reset_for_stage` de `rally_escort_vehicle.gd` + `RallyTireCompound.start_temperatures`, que hoy es código muerto):

- `selected_compound_optimum` (actual implícito): arranque al óptimo del compuesto.
- `environment_weighted` (nuevo): `tread = lerpf(ambiente_zona, óptimo, 0.4)` — la goma sale fría en Suecia y caliente en Kenia. La presión en frío sale sola por la ley del gas (ya implementada).

6.2 Cambiar a `environment_weighted` en `sweden_rally.json` y `kenya_rally.json`; el resto se queda en `selected_compound_optimum` (sin cambio de comportamiento en Rusia/Finlandia/Suiza).

6.3 A futuro (fuera de este plan): usar `environment_weighted` con exposición parcial en tramos intermedios.

---

## Qué NO se toca

- `tire_model.gd` (grip) ni las escalas `road_grip_scale`/`loose_grip_scale` de los compuestos.
- Overlays de nieve/hielo (`winter_layer_id`, `SnowDeep`).
- GLB, manifiestos de exportación, ni `surface_mapping`.
- Catálogo de compuestos (`rally_compounds.json`) — etiquetas y grip ya están.
- Eventos salvo `start_temperature_policy` en Suecia/Kenia (Fase 6).
- `rally_surface_model.gd` — solo cambian los datos de entrada.

## Orden, dependencias y riesgos

- **Orden**: 1 → 2 → 3 → (4 ∥ 5) → 6. La Fase 1 es bloqueante para todo lo demás.
- **Riesgo de balance (Fase 3)**: subir `road_conductance` reduce la inercia térmica propia de la goma también en rallies templados. Mitigación: valores moderados (80-90, no 120) y ajuste manual conduciendo Rusia como caso de control.
- **Riesgo de datos**: los presets de estado son globales y compartidos; por eso los moduladores viven en `regional_profiles` y no se duplican los estados por país.
- **Riesgo de doble conteo del sol**: el suelo ya absorbe irradiancia (`solar_gain` en `rally_surface_model`); la carga solar de goma/freno/vano es aditiva y física (superficies distintas), pero sus coeficientes deben ser pequeños para no exagerar.
- **Validación manual** (sin tests automatizados por indicación expresa): HUD térmico en Kenia soleado (agua cerca del derate, discos que no bajan en parado, banda caliente) y Suecia nevada (bandas frías, warm-up largo, agua fría). Rusia como control de que no rompe el caso templado.

## Tabla resumen de efectos esperados

| Componente | Sumidero | Suecia (nieve/nublado) | Kenia (sol) |
|---|---|---|---|
| Banda del neumático | suelo + sol | suelo -5…+2 → difícil calentar, `snow_cooling` ayuda | suelo 35-45 + 18 W solares → difícil bajar |
| Carcasa/presión | suelo (vía tread) | presión baja por gas frío | presión alta en caliente |
| Disco de freno | aire + sol | aire ~0-5 °C → warm-up largo | aire 22-31 + soak solar → no baja en parado |
| Agua/aceite | aire (+ sol vano) | aire bajo → agua lejos del derate | aire 22-31 → agua ~+10 °C sobre hoy, cerca del derate |
