# Inventario para fine-tuning de vehículos Rally Trophy

Estado: los nueve vehículos necesitan fine-tuning completo. Este inventario recoge únicamente datos ya presentes en el repositorio; los valores existentes no implican calibración ni validación histórica.

## Alcance común pendiente

- Definir y contrastar la variante y condiciones de masa; afinar reparto de peso, centro de gravedad e inercias.
- Afinar curva de par y potencia, relaciones, diferencial, embrague y respuesta de motor.
- Afinar suspensión, dirección, frenos, neumáticos, aerodinámica y contacto con el suelo; verificar el comportamiento por superficie.
- Validar los resultados en conducción, telemetría y condiciones representativas. La presencia de parámetros en los JSON solo indica que existe una configuración.

## rt-alfa-giulia-gta

**Estado:** necesita fine-tuning completo.

**Información disponible:**

- Nombre: Alfa Romeo Giulia Sprint GTA.
- Política y origen: game_derived; Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune.
- Variante: FIA Group T GTA, not the alternative GT fiche or GTA Junior.
- Datos registrados (nombre = valor; origen y localizador figuran en el archivo de procedencia):
  - `displacement_cc`: 1570 (documented).
  - `drive`: RWD (documented).
  - `cylinders`: 4 (documented).
  - `wheelbase_m`: 2.35 (documented).
  - `track_front_m`: 1.31 (documented).
  - `fuel_l`: 46 (documented).
  - `engine_layout`: front (documented).
- Perfil existente: `game/data/vehicles/rt/rt-alfa-giulia-gta/` (aerodynamics.json, brakes.json, chassis.json, coupled_world.json, damage.json, driving_assistance.json, fuel.json, powertrain.json, steering.json, suspension.json, suspension_filters.json, tire_filters.json, tires.json, underfloor_contact.json, vehicle.json).
- Procedencia: `game/data/vehicles/rt/rt-alfa-giulia-gta/HISTORICAL_PROVENANCE.json`.
- Receta de importación: `tools/rally_trophy/recipes/rt-alfa-giulia-gta.json`.

**Inventario de masas y reparto configurados**

Fuente: `game/data/vehicles/rt/rt-alfa-giulia-gta/chassis.json`; combustible: `game/data/vehicles/rt/rt-alfa-giulia-gta/fuel.json`. Los valores corresponden al perfil actual y requieren afinación.

- `vehicle_mass`: **895.0 kg**; `vehicle_mass_excludes_wheel_assemblies`: `true`. Presupuesto base del inventario: **895.0 kg**.
- Reparto nominal `front_weight_distribution`: **50% delantero / 50% trasero**; altura objetivo `target_cg_z_m`: **0.47 m**.
- Combustible: inicial **20 kg**, capacidad **29.6 kg**, densidad **0.74 kg/L**; posición local del tanque `(x, y, z)` en metros: `{'x': 0, 'y': 0.4, 'z': 0.8400000333786011}`.
- No hay una masa histórica estructurada en `historical_reference.facts` para este coche.

| Componente | Masa (kg) | Centro local (x, y, z) m | Inercia alrededor del centro (kg·m²) | Origen de masa |
|---|---:|---|---|---|
| `body_and_systems` | 593.0 | (0, 0.47, 0.02) | `[[1011.5, 0, 0], [0, 1045.5, 0], [0, 0, 259.2]]` | `recalibrated_1974` |
| `engine_and_transaxle` | 105.0 | (0, 0.42, -0.3) | `[[12, 0, 0], [0, 15, 0], [0, 0, 10]]` | `estimated` |
| `driver_and_seat` | 75.0 | (-0.3, 0.59, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `codriver_and_seat` | 75.0 | (0.3, 0.59, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `spare_wheels_and_tools` | 27.0 | (0, 0.45, -0.02) | `[[3, 0, 0], [0, 5, 0], [0, 0, 3]]` | `estimated` |
| `FrontLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontLeft` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |
| `FrontRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontRight` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |
| `RearLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearLeft` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |
| `RearRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearRight` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |

- Suma aritmética de todos los componentes listados: **975 kg**; componentes con `rotating_wheel`: **80 kg**. Esta suma se presenta como inventario, sin asumir por sí sola la masa efectiva en ejecución.
- Repuesto y herramientas: `{'mass_component_name': 'spare_wheels_and_tools', 'tools_mass_kg': 7.0, 'wheel_mass_kg': 20.0}`; llanta y neumático por rueda: `[20.0, 20.0, 20.0, 20.0]` kg.
- `estimated` identifica estimaciones de componentes, no mediciones; `recalibrated_1974` identifica el origen consignado en el perfil. Confirmar condiciones de masa, reparto real, combustible, piezas y datos de inercia antes del ajuste.

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.

## rt-alpine-a110

**Estado:** necesita fine-tuning completo.

**Información disponible:**

- Nombre: Alpine Renault A110 1600.
- Política y origen: game_derived; Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune.
- Variante: 1970 base FIA fiche; game lists 1596 cc. Later extensions change displacement. Mass excludes fuel and tools.
- Datos registrados (nombre = valor; origen y localizador figuran en el archivo de procedencia):
  - `displacement_cc`: 1565 (documented).
  - `drive`: RWD (documented).
  - `cylinders`: 4 (documented).
  - `wheelbase_m`: 2.1 (documented).
  - `track_front_m`: 1.353 (documented).
  - `track_rear_m`: 1.337 (documented).
  - `fuel_l`: 30 (documented).
  - `mass_kg`: 685 (documented).
- Perfil existente: `game/data/vehicles/rt/rt-alpine-a110/` (aerodynamics.json, brakes.json, chassis.json, coupled_world.json, damage.json, driving_assistance.json, fuel.json, powertrain.json, steering.json, suspension.json, suspension_filters.json, tire_filters.json, tires.json, underfloor_contact.json, vehicle.json).
- Procedencia: `game/data/vehicles/rt/rt-alpine-a110/HISTORICAL_PROVENANCE.json`.
- Receta de importación: `tools/rally_trophy/recipes/rt-alpine-a110.json`.

**Inventario de masas y reparto configurados**

Fuente: `game/data/vehicles/rt/rt-alpine-a110/chassis.json`; combustible: `game/data/vehicles/rt/rt-alpine-a110/fuel.json`. Los valores corresponden al perfil actual y requieren afinación.

- `vehicle_mass`: **855.0 kg**; `vehicle_mass_excludes_wheel_assemblies`: `true`. Presupuesto base del inventario: **855.0 kg**.
- Reparto nominal `front_weight_distribution`: **36% delantero / 64% trasero**; altura objetivo `target_cg_z_m`: **0.425 m**.
- Combustible: inicial **20 kg**, capacidad **29.6 kg**, densidad **0.74 kg/L**; posición local del tanque `(x, y, z)` en metros: `{'x': 0, 'y': 0.4, 'z': -0.6824999690055847}`.
- Referencia histórica `mass_kg`: **685 kg**, estado `documented`, fuente `fia`, localizador: PDF page 2, base form.

| Componente | Masa (kg) | Centro local (x, y, z) m | Inercia alrededor del centro (kg·m²) | Origen de masa |
|---|---:|---|---|---|
| `body_and_systems` | 553.0 | (0, 0.425, 0.02) | `[[782.0, 0, 0], [0, 807.5, 0], [0, 0, 208.2]]` | `recalibrated_1974` |
| `engine_and_transaxle` | 105.0 | (0, 0.375, 0.4) | `[[12, 0, 0], [0, 15, 0], [0, 0, 10]]` | `estimated` |
| `driver_and_seat` | 75.0 | (-0.3, 0.545, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `codriver_and_seat` | 75.0 | (0.3, 0.545, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `spare_wheels_and_tools` | 27.0 | (0, 0.405, -0.02) | `[[3, 0, 0], [0, 5, 0], [0, 0, 3]]` | `estimated` |
| `FrontLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontLeft` | 20.0 | (0, 0, 0) | `[[1.0435039886912938, 0, 0], [0, 0.6261023932147762, 0], [0, 0, 0.6261023932147762]]` | `estimated` |
| `FrontRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontRight` | 20.0 | (0, 0, 0) | `[[1.0435039886912938, 0, 0], [0, 0.6261023932147762, 0], [0, 0, 0.6261023932147762]]` | `estimated` |
| `RearLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearLeft` | 20.0 | (0, 0, 0) | `[[1.0435039886912938, 0, 0], [0, 0.6261023932147762, 0], [0, 0, 0.6261023932147762]]` | `estimated` |
| `RearRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearRight` | 20.0 | (0, 0, 0) | `[[1.0435039886912938, 0, 0], [0, 0.6261023932147762, 0], [0, 0, 0.6261023932147762]]` | `estimated` |

- Suma aritmética de todos los componentes listados: **935 kg**; componentes con `rotating_wheel`: **80 kg**. Esta suma se presenta como inventario, sin asumir por sí sola la masa efectiva en ejecución.
- Repuesto y herramientas: `{'mass_component_name': 'spare_wheels_and_tools', 'tools_mass_kg': 7.0, 'wheel_mass_kg': 20.0}`; llanta y neumático por rueda: `[20.0, 20.0, 20.0, 20.0]` kg.
- `estimated` identifica estimaciones de componentes, no mediciones; `recalibrated_1974` identifica el origen consignado en el perfil. Confirmar condiciones de masa, reparto real, combustible, piezas y datos de inercia antes del ajuste.

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.

## rt-fiat-abarth-1000

**Estado:** necesita fine-tuning completo.

**Información disponible:**

- Nombre: Fiat 600 Abarth.
- Política y origen: game_derived; Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune.
- Variante: FIA Fiat-Abarth 1000 Berlina reference, not generic Fiat 600 specs.
- Datos registrados (nombre = valor; origen y localizador figuran en el archivo de procedencia):
  - `displacement_cc`: 982 (documented).
  - `drive`: RWD (documented).
  - `cylinders`: 4 (documented).
  - `wheelbase_m`: 2.0 (documented).
  - `track_front_m`: 1.15 (documented).
  - `track_rear_m`: 1.16 (documented).
  - `fuel_l`: 27 (documented).
  - `engine_layout`: rear (documented).
- Perfil existente: `game/data/vehicles/rt/rt-fiat-abarth-1000/` (aerodynamics.json, brakes.json, chassis.json, coupled_world.json, damage.json, driving_assistance.json, fuel.json, powertrain.json, steering.json, suspension.json, suspension_filters.json, tire_filters.json, tires.json, underfloor_contact.json, vehicle.json).
- Procedencia: `game/data/vehicles/rt/rt-fiat-abarth-1000/HISTORICAL_PROVENANCE.json`.
- Receta de importación: `tools/rally_trophy/recipes/rt-fiat-abarth-1000.json`.

**Inventario de masas y reparto configurados**

Fuente: `game/data/vehicles/rt/rt-fiat-abarth-1000/chassis.json`; combustible: `game/data/vehicles/rt/rt-fiat-abarth-1000/fuel.json`. Los valores corresponden al perfil actual y requieren afinación.

- `vehicle_mass`: **775.0 kg**; `vehicle_mass_excludes_wheel_assemblies`: `true`. Presupuesto base del inventario: **775.0 kg**.
- Reparto nominal `front_weight_distribution`: **40% delantero / 60% trasero**; altura objetivo `target_cg_z_m`: **0.445 m**.
- Combustible: inicial **20 kg**, capacidad **29.6 kg**, densidad **0.74 kg/L**; posición local del tanque `(x, y, z)` en metros: `{'x': 0, 'y': 0.4, 'z': -0.6694999814033509}`.
- No hay una masa histórica estructurada en `historical_reference.facts` para este coche.

| Componente | Masa (kg) | Centro local (x, y, z) m | Inercia alrededor del centro (kg·m²) | Origen de masa |
|---|---:|---|---|---|
| `body_and_systems` | 473.0 | (0, 0.445, 0.02) | `[[603.5, 0, 0], [0, 629.0, 0], [0, 0, 178.5]]` | `recalibrated_1974` |
| `engine_and_transaxle` | 105.0 | (0, 0.395, 0.4) | `[[12, 0, 0], [0, 15, 0], [0, 0, 10]]` | `estimated` |
| `driver_and_seat` | 75.0 | (-0.3, 0.565, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `codriver_and_seat` | 75.0 | (0.3, 0.565, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `spare_wheels_and_tools` | 27.0 | (0, 0.425, -0.02) | `[[3, 0, 0], [0, 5, 0], [0, 0, 3]]` | `estimated` |
| `FrontLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontLeft` | 20.0 | (0, 0, 0) | `[[0.6874999590218074, 0, 0], [0, 0.4124999754130844, 0], [0, 0, 0.4124999754130844]]` | `estimated` |
| `FrontRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontRight` | 20.0 | (0, 0, 0) | `[[0.6874999590218074, 0, 0], [0, 0.4124999754130844, 0], [0, 0, 0.4124999754130844]]` | `estimated` |
| `RearLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearLeft` | 20.0 | (0, 0, 0) | `[[0.6874999590218074, 0, 0], [0, 0.4124999754130844, 0], [0, 0, 0.4124999754130844]]` | `estimated` |
| `RearRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearRight` | 20.0 | (0, 0, 0) | `[[0.6874999590218074, 0, 0], [0, 0.4124999754130844, 0], [0, 0, 0.4124999754130844]]` | `estimated` |

- Suma aritmética de todos los componentes listados: **855 kg**; componentes con `rotating_wheel`: **80 kg**. Esta suma se presenta como inventario, sin asumir por sí sola la masa efectiva en ejecución.
- Repuesto y herramientas: `{'mass_component_name': 'spare_wheels_and_tools', 'tools_mass_kg': 7.0, 'wheel_mass_kg': 20.0}`; llanta y neumático por rueda: `[20.0, 20.0, 20.0, 20.0]` kg.
- `estimated` identifica estimaciones de componentes, no mediciones; `recalibrated_1974` identifica el origen consignado en el perfil. Confirmar condiciones de masa, reparto real, combustible, piezas y datos de inercia antes del ajuste.

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.

## rt-lancia-stratos

**Estado:** necesita fine-tuning completo.

**Información disponible:**

- Nombre: Lancia Stratos HF.
- Política y origen: game_derived; Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune.
- Variante: 1974 Group 4 homologation; game labels 1972. Confirm period-specific tune before calibration.
- Datos registrados (nombre = valor; origen y localizador figuran en el archivo de procedencia):
  - `displacement_cc`: 2418 (documented).
  - `drive`: RWD (documented).
  - `cylinders`: 6 (documented).
  - `wheelbase_m`: 2.18 (documented).
  - `track_front_m`: 1.43 (documented).
  - `track_rear_m`: 1.46 (documented).
  - `fuel_l`: 80 (documented).
- Perfil existente: `game/data/vehicles/rt/rt-lancia-stratos/` (aerodynamics.json, brakes.json, chassis.json, coupled_world.json, damage.json, driving_assistance.json, fuel.json, powertrain.json, steering.json, suspension.json, suspension_filters.json, tire_filters.json, tires.json, underfloor_contact.json, vehicle.json).
- Procedencia: `game/data/vehicles/rt/rt-lancia-stratos/HISTORICAL_PROVENANCE.json`.
- Receta de importación: `tools/rally_trophy/recipes/rt-lancia-stratos.json`.

**Inventario de masas y reparto configurados**

Fuente: `game/data/vehicles/rt/rt-lancia-stratos/chassis.json`; combustible: `game/data/vehicles/rt/rt-lancia-stratos/fuel.json`. Los valores corresponden al perfil actual y requieren afinación.

- `vehicle_mass`: **1040.0 kg**; `vehicle_mass_excludes_wheel_assemblies`: `true`. Presupuesto base del inventario: **1040.0 kg**.
- Reparto nominal `front_weight_distribution`: **41% delantero / 59% trasero**; altura objetivo `target_cg_z_m`: **0.43 m**.
- Combustible: inicial **20 kg**, capacidad **29.6 kg**, densidad **0.74 kg/L**; posición local del tanque `(x, y, z)` en metros: `{'x': 0, 'y': 0.4, 'z': 0.7349999666213989}`.
- No hay una masa histórica estructurada en `historical_reference.facts` para este coche.

| Componente | Masa (kg) | Centro local (x, y, z) m | Inercia alrededor del centro (kg·m²) | Origen de masa |
|---|---:|---|---|---|
| `body_and_systems` | 693.0 | (0, 0.43, 0.12) | `[[799.0, 0, 0], [0, 833.0, 0], [0, 0, 280.5]]` | `recalibrated_1974` |
| `engine_and_transaxle` | 150.0 | (0, 0.38, 0.47) | `[[12, 0, 0], [0, 15, 0], [0, 0, 10]]` | `estimated` |
| `driver_and_seat` | 75.0 | (-0.3, 0.55, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `codriver_and_seat` | 75.0 | (0.3, 0.55, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `spare_wheels_and_tools` | 27.0 | (0, 0.41, -0.12) | `[[3, 0, 0], [0, 5, 0], [0, 0, 3]]` | `estimated` |
| `FrontLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontLeft` | 20.0 | (0, 0, 0) | `[[1.1207752085990588, 0, 0], [0, 0.6724651251594352, 0], [0, 0, 0.6724651251594352]]` | `estimated` |
| `FrontRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontRight` | 20.0 | (0, 0, 0) | `[[1.1207752085990588, 0, 0], [0, 0.6724651251594352, 0], [0, 0, 0.6724651251594352]]` | `estimated` |
| `RearLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearLeft` | 20.0 | (0, 0, 0) | `[[1.1207752085990588, 0, 0], [0, 0.6724651251594352, 0], [0, 0, 0.6724651251594352]]` | `estimated` |
| `RearRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearRight` | 20.0 | (0, 0, 0) | `[[1.1207752085990588, 0, 0], [0, 0.6724651251594352, 0], [0, 0, 0.6724651251594352]]` | `estimated` |

- Suma aritmética de todos los componentes listados: **1120 kg**; componentes con `rotating_wheel`: **80 kg**. Esta suma se presenta como inventario, sin asumir por sí sola la masa efectiva en ejecución.
- Repuesto y herramientas: `{'mass_component_name': 'spare_wheels_and_tools', 'tools_mass_kg': 7.0, 'wheel_mass_kg': 20.0}`; llanta y neumático por rueda: `[20.0, 20.0, 20.0, 20.0]` kg.
- `estimated` identifica estimaciones de componentes, no mediciones; `recalibrated_1974` identifica el origen consignado en el perfil. Confirmar condiciones de masa, reparto real, combustible, piezas y datos de inercia antes del ajuste.

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.

## rt-lotus-cortina

**Estado:** necesita fine-tuning completo.

**Información disponible:**

- Nombre: Ford Lotus Cortina Mk1.
- Política y origen: game_derived; Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune.
- Variante: Game lists 1598 cc; fiche specifies 1558 cc.
- Datos registrados (nombre = valor; origen y localizador figuran en el archivo de procedencia):
  - `displacement_cc`: 1558 (documented).
  - `drive`: RWD (documented).
  - `cylinders`: 4 (documented).
  - `wheelbase_m`: 2.499 (documented).
  - `track_front_m`: 1.31 (documented).
  - `track_rear_m`: 1.275 (documented).
  - `fuel_l`: 36.35 (documented).
  - `mass_kg`: 751 (documented).
  - `suspension_front`: independent coil (documented).
  - `suspension_rear`: live axle with A-frame and coils (documented).
- Perfil existente: `game/data/vehicles/rt/rt-lotus-cortina/` (aerodynamics.json, brakes.json, chassis.json, coupled_world.json, damage.json, driving_assistance.json, fuel.json, powertrain.json, steering.json, suspension.json, suspension_filters.json, tire_filters.json, tires.json, underfloor_contact.json, vehicle.json).
- Procedencia: `game/data/vehicles/rt/rt-lotus-cortina/HISTORICAL_PROVENANCE.json`.
- Receta de importación: `tools/rally_trophy/recipes/rt-lotus-cortina.json`.

**Inventario de masas y reparto configurados**

Fuente: `game/data/vehicles/rt/rt-lotus-cortina/chassis.json`; combustible: `game/data/vehicles/rt/rt-lotus-cortina/fuel.json`. Los valores corresponden al perfil actual y requieren afinación.

- `vehicle_mass`: **1065.0 kg**; `vehicle_mass_excludes_wheel_assemblies`: `true`. Presupuesto base del inventario: **1065.0 kg**.
- Reparto nominal `front_weight_distribution`: **52% delantero / 48% trasero**; altura objetivo `target_cg_z_m`: **0.51 m**.
- Combustible: inicial **20 kg**, capacidad **29.6 kg**, densidad **0.74 kg/L**; posición local del tanque `(x, y, z)` en metros: `{'x': 0, 'y': 0.4, 'z': 0.9099999666213988}`.
- Referencia histórica `mass_kg`: **751 kg**, estado `documented`, fuente `fia`, localizador: PDF page 6, base form.

| Componente | Masa (kg) | Centro local (x, y, z) m | Inercia alrededor del centro (kg·m²) | Origen de masa |
|---|---:|---|---|---|
| `body_and_systems` | 763.0 | (0, 0.51, 0.02) | `[[1088.0, 0, 0], [0, 1130.5, 0], [0, 0, 272.0]]` | `recalibrated_1974` |
| `engine_and_transaxle` | 105.0 | (0, 0.46, -0.3) | `[[12, 0, 0], [0, 15, 0], [0, 0, 10]]` | `estimated` |
| `driver_and_seat` | 75.0 | (-0.3, 0.63, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `codriver_and_seat` | 75.0 | (0.3, 0.63, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `spare_wheels_and_tools` | 27.0 | (0, 0.49, -0.02) | `[[3, 0, 0], [0, 5, 0], [0, 0, 3]]` | `estimated` |
| `FrontLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontLeft` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |
| `FrontRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontRight` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |
| `RearLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearLeft` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |
| `RearRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearRight` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |

- Suma aritmética de todos los componentes listados: **1145 kg**; componentes con `rotating_wheel`: **80 kg**. Esta suma se presenta como inventario, sin asumir por sí sola la masa efectiva en ejecución.
- Repuesto y herramientas: `{'mass_component_name': 'spare_wheels_and_tools', 'tools_mass_kg': 7.0, 'wheel_mass_kg': 20.0}`; llanta y neumático por rueda: `[20.0, 20.0, 20.0, 20.0]` kg.
- `estimated` identifica estimaciones de componentes, no mediciones; `recalibrated_1974` identifica el origen consignado en el perfil. Confirmar condiciones de masa, reparto real, combustible, piezas y datos de inercia antes del ajuste.

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.

## rt-mini-cooper-s

**Estado:** necesita fine-tuning completo.

**Información disponible:**

- Nombre: Mini Cooper S.
- Política y origen: game_derived; Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune.
- Variante: Fiche 1964; catalogue output 78 bhp at 5800 rpm, not rally tune.
- Datos registrados (nombre = valor; origen y localizador figuran en el archivo de procedencia):
  - `displacement_cc`: 1275 (documented).
  - `drive`: FWD (documented).
  - `cylinders`: 4 (documented).
  - `wheelbase_m`: 2.035 (documented).
  - `track_front_options_m`: [1.207, 1.242] (documented).
  - `track_rear_options_m`: [1.176, 1.203] (documented).
  - `fuel_options_l`: [25, 50] (documented).
  - `mass_kg`: 620 (documented).
  - `suspension_front`: independent rubber cones (documented).
  - `suspension_rear`: independent rubber cones (documented).
  - `engine_layout`: front transverse (documented).
  - `catalogue_power_bhp`: 78 (documented).
  - `catalogue_power_rpm`: 5800 (documented).
- Perfil existente: `game/data/vehicles/rt/rt-mini-cooper-s/` (aerodynamics.json, brakes.json, chassis.json, coupled_world.json, damage.json, driving_assistance.json, fuel.json, powertrain.json, steering.json, suspension.json, suspension_filters.json, tire_filters.json, tires.json, underfloor_contact.json, vehicle.json).
- Procedencia: `game/data/vehicles/rt/rt-mini-cooper-s/HISTORICAL_PROVENANCE.json`.
- Receta de importación: `tools/rally_trophy/recipes/rt-mini-cooper-s.json`.

**Inventario de masas y reparto configurados**

Fuente: `game/data/vehicles/rt/rt-mini-cooper-s/chassis.json`; combustible: `game/data/vehicles/rt/rt-mini-cooper-s/fuel.json`. Los valores corresponden al perfil actual y requieren afinación.

- `vehicle_mass`: **765.0 kg**; `vehicle_mass_excludes_wheel_assemblies`: `true`. Presupuesto base del inventario: **765.0 kg**.
- Reparto nominal `front_weight_distribution`: **61% delantero / 39% trasero**; altura objetivo `target_cg_z_m`: **0.44 m**.
- Combustible: inicial **20 kg**, capacidad **29.6 kg**, densidad **0.74 kg/L**; posición local del tanque `(x, y, z)` en metros: `{'x': 0, 'y': 0.4, 'z': 0.7350000500679016}`.
- Referencia histórica `mass_kg`: **620 kg**, estado `documented`, fuente `fia`, localizador: PDF page 6, base form.

| Componente | Masa (kg) | Centro local (x, y, z) m | Inercia alrededor del centro (kg·m²) | Origen de masa |
|---|---:|---|---|---|
| `body_and_systems` | 463.0 | (0, 0.44, -0.12) | `[[578.0, 0, 0], [0, 603.5, 0], [0, 0, 182.8]]` | `recalibrated_1974` |
| `engine_and_transaxle` | 105.0 | (0, 0.39, -0.55) | `[[12, 0, 0], [0, 15, 0], [0, 0, 10]]` | `estimated` |
| `driver_and_seat` | 75.0 | (-0.3, 0.56, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `codriver_and_seat` | 75.0 | (0.3, 0.56, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `spare_wheels_and_tools` | 27.0 | (0, 0.42, 0.12) | `[[3, 0, 0], [0, 5, 0], [0, 0, 3]]` | `estimated` |
| `FrontLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontLeft` | 20.0 | (0, 0, 0) | `[[0.6874999590218074, 0, 0], [0, 0.4124999754130844, 0], [0, 0, 0.4124999754130844]]` | `estimated` |
| `FrontRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontRight` | 20.0 | (0, 0, 0) | `[[0.6874999590218074, 0, 0], [0, 0.4124999754130844, 0], [0, 0, 0.4124999754130844]]` | `estimated` |
| `RearLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearLeft` | 20.0 | (0, 0, 0) | `[[0.6874999590218074, 0, 0], [0, 0.4124999754130844, 0], [0, 0, 0.4124999754130844]]` | `estimated` |
| `RearRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearRight` | 20.0 | (0, 0, 0) | `[[0.6874999590218074, 0, 0], [0, 0.4124999754130844, 0], [0, 0, 0.4124999754130844]]` | `estimated` |

- Suma aritmética de todos los componentes listados: **845 kg**; componentes con `rotating_wheel`: **80 kg**. Esta suma se presenta como inventario, sin asumir por sí sola la masa efectiva en ejecución.
- Repuesto y herramientas: `{'mass_component_name': 'spare_wheels_and_tools', 'tools_mass_kg': 7.0, 'wheel_mass_kg': 20.0}`; llanta y neumático por rueda: `[20.0, 20.0, 20.0, 20.0]` kg.
- `estimated` identifica estimaciones de componentes, no mediciones; `recalibrated_1974` identifica el origen consignado en el perfil. Confirmar condiciones de masa, reparto real, combustible, piezas y datos de inercia antes del ajuste.

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.

## rt-opel-kadett

**Estado:** necesita fine-tuning completo.

**Información disponible:**

- Nombre: Opel Kadett Rallye.
- Política y origen: game_derived; Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune.
- Variante: 1970 Kadett B 1900 fiche; game labels 1969 and Car.ini header says 1100 SR. Identity requires review.
- Datos registrados (nombre = valor; origen y localizador figuran en el archivo de procedencia):
  - `displacement_cc`: 1897 (documented).
  - `drive`: RWD (documented).
  - `cylinders`: 4 (documented).
  - `wheelbase_m`: 2.416 (documented).
  - `track_front_m`: 1.252 (documented).
  - `track_rear_m`: 1.282 (documented).
  - `fuel_l`: 40 (documented).
  - `mass_kg`: 810 (documented).
  - `din_curb_mass_kg`: 850 (documented).
- Perfil existente: `game/data/vehicles/rt/rt-opel-kadett/` (aerodynamics.json, brakes.json, chassis.json, coupled_world.json, damage.json, driving_assistance.json, fuel.json, powertrain.json, steering.json, suspension.json, suspension_filters.json, tire_filters.json, tires.json, underfloor_contact.json, vehicle.json).
- Procedencia: `game/data/vehicles/rt/rt-opel-kadett/HISTORICAL_PROVENANCE.json`.
- Receta de importación: `tools/rally_trophy/recipes/rt-opel-kadett.json`.

**Inventario de masas y reparto configurados**

Fuente: `game/data/vehicles/rt/rt-opel-kadett/chassis.json`; combustible: `game/data/vehicles/rt/rt-opel-kadett/fuel.json`. Los valores corresponden al perfil actual y requieren afinación.

- `vehicle_mass`: **960.0 kg**; `vehicle_mass_excludes_wheel_assemblies`: `true`. Presupuesto base del inventario: **960.0 kg**.
- Reparto nominal `front_weight_distribution`: **52% delantero / 48% trasero**; altura objetivo `target_cg_z_m`: **0.515 m**.
- Combustible: inicial **20 kg**, capacidad **29.6 kg**, densidad **0.74 kg/L**; posición local del tanque `(x, y, z)` en metros: `{'x': 0, 'y': 0.4, 'z': 0.8400000333786011}`.
- Referencia histórica `mass_kg`: **810 kg**, estado `documented`, fuente `fia`, localizador: PDF page 5, base form.
- Referencia histórica `din_curb_mass_kg`: **850 kg**, estado `documented`, fuente `fia`, localizador: PDF page 5, base form.

| Componente | Masa (kg) | Centro local (x, y, z) m | Inercia alrededor del centro (kg·m²) | Origen de masa |
|---|---:|---|---|---|
| `body_and_systems` | 658.0 | (0, 0.515, 0.02) | `[[1181.5, 0, 0], [0, 1224.0, 0], [0, 0, 293.2]]` | `recalibrated_1974` |
| `engine_and_transaxle` | 105.0 | (0, 0.465, -0.3) | `[[12, 0, 0], [0, 15, 0], [0, 0, 10]]` | `estimated` |
| `driver_and_seat` | 75.0 | (-0.3, 0.635, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `codriver_and_seat` | 75.0 | (0.3, 0.635, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `spare_wheels_and_tools` | 27.0 | (0, 0.495, -0.02) | `[[3, 0, 0], [0, 5, 0], [0, 0, 3]]` | `estimated` |
| `FrontLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontLeft` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |
| `FrontRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontRight` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |
| `RearLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearLeft` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |
| `RearRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearRight` | 20.0 | (0, 0, 0) | `[[0.8624000073432594, 0, 0], [0, 0.5174400044059556, 0], [0, 0, 0.5174400044059556]]` | `estimated` |

- Suma aritmética de todos los componentes listados: **1040 kg**; componentes con `rotating_wheel`: **80 kg**. Esta suma se presenta como inventario, sin asumir por sí sola la masa efectiva en ejecución.
- Repuesto y herramientas: `{'mass_component_name': 'spare_wheels_and_tools', 'tools_mass_kg': 7.0, 'wheel_mass_kg': 20.0}`; llanta y neumático por rueda: `[20.0, 20.0, 20.0, 20.0]` kg.
- `estimated` identifica estimaciones de componentes, no mediciones; `recalibrated_1974` identifica el origen consignado en el perfil. Confirmar condiciones de masa, reparto real, combustible, piezas y datos de inercia antes del ajuste.

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.

## rt-saab-96-v4

**Estado:** necesita fine-tuning completo.

**Información disponible:**

- Nombre: Saab 96 V4.
- Política y origen: game_derived; Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune.
- Variante: Group 1 1498 cc homologation dated 1966, matching game displacement and 1967 model period. The separate 1971 Group 2 1698 cc fiche does not establish the game's tune.
- Datos registrados (nombre = valor; origen y localizador figuran en el archivo de procedencia):
  - `displacement_cc`: 1498 (documented).
  - `drive`: FWD (documented).
  - `cylinders`: 4 (documented).
  - `wheelbase_m`: 2.498 (documented).
  - `track_front_m`: 1.22 (documented).
  - `track_rear_m`: 1.22 (documented).
  - `fuel_l`: 40 (documented).
  - `mass_kg`: 812 (documented).
- Perfil existente: `game/data/vehicles/rt/rt-saab-96-v4/` (aerodynamics.json, brakes.json, chassis.json, coupled_world.json, damage.json, driving_assistance.json, fuel.json, powertrain.json, steering.json, suspension.json, suspension_filters.json, tire_filters.json, tires.json, underfloor_contact.json, vehicle.json).
- Procedencia: `game/data/vehicles/rt/rt-saab-96-v4/HISTORICAL_PROVENANCE.json`.
- Receta de importación: `tools/rally_trophy/recipes/rt-saab-96-v4.json`.

**Inventario de masas y reparto configurados**

Fuente: `game/data/vehicles/rt/rt-saab-96-v4/chassis.json`; combustible: `game/data/vehicles/rt/rt-saab-96-v4/fuel.json`. Los valores corresponden al perfil actual y requieren afinación.

- `vehicle_mass`: **962.0 kg**; `vehicle_mass_excludes_wheel_assemblies`: `true`. Presupuesto base del inventario: **962.0 kg**.
- Reparto nominal `front_weight_distribution`: **61% delantero / 39% trasero**; altura objetivo `target_cg_z_m`: **0.525 m**.
- Combustible: inicial **20 kg**, capacidad **29.6 kg**, densidad **0.74 kg/L**; posición local del tanque `(x, y, z)` en metros: `{'x': 0, 'y': 0.4, 'z': 0.8399998664855957}`.
- Referencia histórica `mass_kg`: **812 kg**, estado `documented`, fuente `fia`, localizador: PDF page 5, 1498 cc base form.

| Componente | Masa (kg) | Centro local (x, y, z) m | Inercia alrededor del centro (kg·m²) | Origen de masa |
|---|---:|---|---|---|
| `body_and_systems` | 660.0 | (0, 0.525, -0.1) | `[[1139.0, 0, 0], [0, 1173.0, 0], [0, 0, 280.5]]` | `recalibrated_1974` |
| `engine_and_transaxle` | 105.0 | (0, 0.475, -0.6) | `[[12, 0, 0], [0, 15, 0], [0, 0, 10]]` | `estimated` |
| `driver_and_seat` | 75.0 | (-0.3, 0.645, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `codriver_and_seat` | 75.0 | (0.3, 0.645, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `spare_wheels_and_tools` | 27.0 | (0, 0.505, 0.1) | `[[3, 0, 0], [0, 5, 0], [0, 0, 3]]` | `estimated` |
| `FrontLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontLeft` | 20.0 | (0, 0, 0) | `[[0.8624000073432704, 0, 0], [0, 0.5174400044059622, 0], [0, 0, 0.5174400044059622]]` | `estimated` |
| `FrontRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontRight` | 20.0 | (0, 0, 0) | `[[0.8624000073432704, 0, 0], [0, 0.5174400044059622, 0], [0, 0, 0.5174400044059622]]` | `estimated` |
| `RearLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearLeft` | 20.0 | (0, 0, 0) | `[[0.8624000073432704, 0, 0], [0, 0.5174400044059622, 0], [0, 0, 0.5174400044059622]]` | `estimated` |
| `RearRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearRight` | 20.0 | (0, 0, 0) | `[[0.8624000073432704, 0, 0], [0, 0.5174400044059622, 0], [0, 0, 0.5174400044059622]]` | `estimated` |

- Suma aritmética de todos los componentes listados: **1042 kg**; componentes con `rotating_wheel`: **80 kg**. Esta suma se presenta como inventario, sin asumir por sí sola la masa efectiva en ejecución.
- Repuesto y herramientas: `{'mass_component_name': 'spare_wheels_and_tools', 'tools_mass_kg': 7.0, 'wheel_mass_kg': 20.0}`; llanta y neumático por rueda: `[20.0, 20.0, 20.0, 20.0]` kg.
- `estimated` identifica estimaciones de componentes, no mediciones; `recalibrated_1974` identifica el origen consignado en el perfil. Confirmar condiciones de masa, reparto real, combustible, piezas y datos de inercia antes del ajuste.

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.

## rt-volvo-amazon

**Estado:** necesita fine-tuning completo.

**Información disponible:**

- Nombre: Volvo 122 Amazon.
- Política y origen: game_derived; Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune.
- Variante: 1966 two-door 122 S reference; game labels 1962.
- Datos registrados (nombre = valor; origen y localizador figuran en el archivo de procedencia):
  - `displacement_cc`: 1778 (documented).
  - `drive`: RWD (documented).
  - `cylinders`: 4 (documented).
  - `wheelbase_m`: 2.6 (documented).
  - `track_front_m`: 1.315 (documented).
  - `track_rear_m`: 1.315 (documented).
  - `fuel_l`: 45 (documented).
  - `mass_kg`: 1013 (documented).
  - `suspension_front`: independent coil (documented).
  - `suspension_rear`: rigid axle with coils (documented).
- Perfil existente: `game/data/vehicles/rt/rt-volvo-amazon/` (aerodynamics.json, brakes.json, chassis.json, coupled_world.json, damage.json, driving_assistance.json, fuel.json, powertrain.json, steering.json, suspension.json, suspension_filters.json, tire_filters.json, tires.json, underfloor_contact.json, vehicle.json).
- Procedencia: `game/data/vehicles/rt/rt-volvo-amazon/HISTORICAL_PROVENANCE.json`.
- Receta de importación: `tools/rally_trophy/recipes/rt-volvo-amazon.json`.

**Inventario de masas y reparto configurados**

Fuente: `game/data/vehicles/rt/rt-volvo-amazon/chassis.json`; combustible: `game/data/vehicles/rt/rt-volvo-amazon/fuel.json`. Los valores corresponden al perfil actual y requieren afinación.

- `vehicle_mass`: **1250.0 kg**; `vehicle_mass_excludes_wheel_assemblies`: `true`. Presupuesto base del inventario: **1250.0 kg**.
- Reparto nominal `front_weight_distribution`: **52% delantero / 48% trasero**; altura objetivo `target_cg_z_m`: **0.545 m**.
- Combustible: inicial **20 kg**, capacidad **29.6 kg**, densidad **0.74 kg/L**; posición local del tanque `(x, y, z)` en metros: `{'x': 0, 'y': 0.4, 'z': 0.927500033378601}`.
- Referencia histórica `mass_kg`: **1013 kg**, estado `documented`, fuente `fia`, localizador: PDF page 5, base form.

| Componente | Masa (kg) | Centro local (x, y, z) m | Inercia alrededor del centro (kg·m²) | Origen de masa |
|---|---:|---|---|---|
| `body_and_systems` | 948.0 | (0, 0.545, 0.02) | `[[1513.0, 0, 0], [0, 1572.5, 0], [0, 0, 357.0]]` | `recalibrated_1974` |
| `engine_and_transaxle` | 105.0 | (0, 0.495, -0.3) | `[[12, 0, 0], [0, 15, 0], [0, 0, 10]]` | `estimated` |
| `driver_and_seat` | 75.0 | (-0.3, 0.665, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `codriver_and_seat` | 75.0 | (0.3, 0.665, 0.05) | `[[8, 0, 0], [0, 6, 0], [0, 0, 5]]` | `estimated` |
| `spare_wheels_and_tools` | 27.0 | (0, 0.525, -0.02) | `[[3, 0, 0], [0, 5, 0], [0, 0, 3]]` | `estimated` |
| `FrontLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontLeft` | 20.0 | (0, 0, 0) | `[[1.1405240836033397, 0, 0], [0, 0.6843144501620038, 0], [0, 0, 0.6843144501620038]]` | `estimated` |
| `FrontRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_FrontRight` | 20.0 | (0, 0, 0) | `[[1.1405240836033397, 0, 0], [0, 0.6843144501620038, 0], [0, 0, 0.6843144501620038]]` | `estimated` |
| `RearLeft_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearLeft` | 20.0 | (0, 0, 0) | `[[1.1405240836033397, 0, 0], [0, 0.6843144501620038, 0], [0, 0, 0.6843144501620038]]` | `estimated` |
| `RearRight_upright` | 5.0 | (0, 0, 0) | `[[0.1, 0, 0], [0, 0.1, 0], [0, 0, 0.1]]` | `estimated` |
| `wheel_RearRight` | 20.0 | (0, 0, 0) | `[[1.1405240836033397, 0, 0], [0, 0.6843144501620038, 0], [0, 0, 0.6843144501620038]]` | `estimated` |

- Suma aritmética de todos los componentes listados: **1330 kg**; componentes con `rotating_wheel`: **80 kg**. Esta suma se presenta como inventario, sin asumir por sí sola la masa efectiva en ejecución.
- Repuesto y herramientas: `{'mass_component_name': 'spare_wheels_and_tools', 'tools_mass_kg': 7.0, 'wheel_mass_kg': 20.0}`; llanta y neumático por rueda: `[20.0, 20.0, 20.0, 20.0]` kg.
- `estimated` identifica estimaciones de componentes, no mediciones; `recalibrated_1974` identifica el origen consignado en el perfil. Confirmar condiciones de masa, reparto real, combustible, piezas y datos de inercia antes del ajuste.

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.
