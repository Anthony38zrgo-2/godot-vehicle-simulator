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

**Por afinar o confirmar:**

- period rally mass and weight distribution.
- competition torque curve and gearing.
- spring and damper rates.
- differential setup.
- Contrastar la configuración actual de los JSON con la variante de referencia y validar el comportamiento en pista.
