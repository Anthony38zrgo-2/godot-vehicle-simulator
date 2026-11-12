# Plan de corrección del modelo de transmisión

## 1. Rueda libre del Saab 96 V4

En el modelo aislado, el perfil real del Saab en 3.ª, a gas cerrado y con
régimen equivalente de las ruedas superior al del motor, pasó de rueda libre
activa a inactiva dentro del mismo subpaso a 970 y 850 rpm. A 970 rpm, el par
neto de +1,15 Nm bastó para que el solver interpretara acelerador a fondo.

- Resolver el estado una vez por subpaso con el acelerador del conductor, la
  marcha efectiva y la diferencia de velocidad referida al primario. Hacer
  que la integración del motor y el solver consuman esa misma decisión.
  Revisar la entrada a punto muerto durante un cambio para invalidar el
  estado de forma explícita.
- Eliminar la inferencia de acelerador a partir del signo del par. Usar
  umbrales separados para desacoplar y volver a acoplar, conservando el
  estado entre ambos. Mantener compatibilidad con el margen configurado y
  fijar la separación de los umbrales con un barrido de velocidad.
- Probar el perfil del Saab a 970 y 850 rpm, con acelerador cero y régimen
  equivalente de 4.800 rpm en 3.ª. Exigir que la rueda libre siga activa tras
  el solver y que el impulso de la restricción de marcha sea cero. Con
  transmisión elástica puede quedar par transitorio por torsión almacenada.
  Probar también reapertura de gas, cruce lento de ambos umbrales, punto
  muerto y marcha atrás.

[Modelo de transmisión](../../scripts/physics/powertrain_model.gd#L358) ·
[Bucle de subpasos](../../scripts/physics/vehicle_simulation.gd#L844) ·
[Perfil del Saab](../../data/vehicles/rt/rt-saab-96-v4/powertrain.json)

## 2. Par del motor con la rueda libre activa

A 4.000 rpm, gas cerrado y rueda libre activa, el estimador dio 0 Nm y
la integración aplicó −6,97 Nm. Además, una rampa de 4.000 rpm/s modifica
directamente el régimen hacia el ralentí.

- Compartir el cálculo de los términos de par entre el estimador y el
  integrador. Distinguir el par solicitado del entregado después de aplicar
  el límite de ataque. Mantener el rozamiento interno del motor y dejar que
  la rueda libre corte su transmisión a las ruedas.
- Sustituir la rampa directa de la rueda libre por una caída gobernada por
  el par y la inercia, con aporte de ralentí explícito. Revisar su interacción
  con la recuperación de ralentí que ya existe al abrir el embrague.
- Comparar estimación e integración a 4.000 rpm con estado y entradas
  iguales, y con el límite de ataque estabilizado. Medir la caída de vueltas
  hasta ralentí, el impulso de marcha y la desaceleración en una pasada
  en pista con el Saab, con rueda libre activa y desactivada. Ajustar la
  respuesta de ralentí con esas trazas.

[Estimador de par](../../scripts/physics/powertrain_model.gd#L377) ·
[Integración de RPM](../../scripts/physics/powertrain_model.gd#L419) ·
[Límite de ataque](../../scripts/physics/powertrain_model.gd#L712)

## 3. Validación y carga de perfiles

- Validar antes de modificar el modelo. Exigir `max_torque` explícito,
  positivo y finito, una relación final efectiva positiva y finita tras
  resolver el preset, y al menos una marcha hacia delante con todas las
  relaciones positivas y finitas. Conservar el valor por defecto de la
  relación final si el campo se omite.
- Mantener el fallback actual para una curva omitida o vacía. Para curvas
  suministradas, validar pares numéricos finitos y abscisas no negativas
  estrictamente crecientes. Conservar los puntos por encima de 1 y el dominio
  actual de consulta de 0 a 1. Verificar que las curvas de los perfiles
  existentes entreguen el mismo par antes y después del cambio.
- Preparar la configuración validada en datos locales y aplicarla solo
  cuando todos los controles pasen, incluida la validación de elasticidad.
  Los errores deben identificar el campo y, para listas, el índice afectado.
- Cargar los 11 perfiles vigentes y probar entradas inválidas, incluidos
  torque ausente, relación efectiva cero, marcha negativa, valores no
  finitos y abscisas duplicadas o desordenadas. Intentar una recarga inválida
  sobre un modelo válido y comprobar que conserva configuración y estado.

[Configuración del modelo](../../scripts/physics/powertrain_model.gd#L99) ·
[Validación del cargador](../../scripts/physics/profile_loader.gd#L68)

## 4. Diferencial por eje y tipos soportados

El único LSD actúa atrás para cualquier reparto delantero inferior a 1
y pasa delante cuando el reparto llega a 1. Los perfiles actuales son
FWD o RWD puros.

- Resolver el diferencial por eje. Interpretar el bloque histórico
  `differential` como el diferencial del eje motriz en FWD y RWD. Para AWD,
  definir explícitamente el tipo y los parámetros de cada eje. Resolver
  un impulso independiente por LSD y calcular su capacidad dependiente
  del par con la fracción transmitida a su eje. Aplicar la precarga según
  la configuración de cada eje.
- Validar los tipos al cargar el perfil y al aplicar un preset.
  `clutch_lsd` y `adjustable_friction_lsd` usan el solver de fricción.
  Implementar `open` con impulso de bloqueo cero. Rechazar `spool` con
  error explícito hasta disponer de una restricción rígida y sus pruebas.
- Verificar par y velocidad diferencial en FWD y RWD con los presets
  vigentes. En un perfil AWD de prueba, barrer repartos 0,50, 0,95, 0,99
  y 1,00 con adherencia desigual en el eje delantero. Comprobar que ese
  LSD actúa antes de 1,00 y que su capacidad dependiente del par sigue
  el reparto. Comprobar también el bloqueo cero del tipo abierto y el
  rechazo de tipos desconocidos.
- Publicar resultados por eje para AWD y comprobar los consumidores de
  telemetría y presets que actualmente esperan un único diferencial.

[Selección del eje](../../scripts/physics/powertrain_model.gd#L561) ·
[Cálculo del LSD](../../scripts/physics/powertrain_model.gd#L621) ·
[Contrato de presets](../../tests/rally/differential_preset_contract.gd)

## Orden de entrega

1. Reproducir y corregir la doble decisión de rueda libre del Saab.
2. Unificar el cálculo de par y validar la caída de régimen en pista.
3. Añadir validación y carga atómica con regresión de los perfiles vigentes.
4. Introducir el diferencial por eje en un cambio separado. Validar primero
   FWD y RWD, y luego el perfil AWD de prueba.
