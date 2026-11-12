# Plan de corrección de simulación, garaje y masas Rally

## 1. Presión tras aplicar un reglaje (hallazgo 7)

- Usar una sola función del modelo térmico para recalcular la presión
  manométrica desde la referencia en frío, la temperatura del gas, la presión
  atmosférica y la pérdida acumulada. Mantener separado el avance de la fuga.
- Llamar al cálculo común desde `advance_tire_pressure()`, el ajuste en vivo
  y `apply_setup_values()`. El garaje debe actualizar la referencia en frío
  y reflejar la pérdida existente en la misma llamada.
- **Aceptación.** Con referencia de 1,80 bar, gas a la temperatura de referencia
  y pérdida del 50 %, aplicar un reglaje válido ajeno a presión. La rueda
  debe marcar 0,90 bar inmediatamente y en el siguiente tick sin avance de
  fuga. Repetir con una referencia nueva, gas caliente y una rueda sana.
  Verificar que pérdida, fuga y temperatura persisten en la rueda montada.

[Reglaje de presión](../../scripts/physics/vehicle_simulation.gd#L569) ·
[Modelo térmico](../../scripts/physics/thermal_model.gd#L493)

## 2. Alcance de contacto en extensión (hallazgo 4)

- Reproducir el caso con una superficie plana a alturas conocidas entre el
  droop nominal y el límite efectivo del joint. Registrar posición real del
  hub, alcance de consulta, impacto geométrico, deformación y carga radial.
  Ejecutar el mismo ensayo con tándem y ShapeCast.
- Derivar el alcance de ambas consultas del mismo límite de extensión que
  usa la junta, incluido su margen actual de 30 mm. Mantener la distancia
  referida al centro neutro. Considerar una tolerancia adicional solo si la
  resolución de la consulta en el borde la justifica.
- **Aceptación.** Detectar el apoyo alcanzable hasta el límite efectivo
  dentro de la tolerancia medida. Un impacto sin penetración puede tener
  carga cero. Comprobar que una superficie fuera del alcance físico queda
  sin carga y que la deformación en el tramo nominal coincide con la base.

[Alcance de consulta](../../scripts/physics/vehicle_simulation.gd#L706) ·
[Margen de la junta](../../scripts/physics/unsprung_suspension_rig.gd#L18)

## 3. Distancia y punto del ShapeCast (hallazgo 5)

- Capturar fracción segura, candidatos de contacto y apoyo seleccionado en
  plano, pendiente, bordillo y con dos superficies. Registrar punto, normal,
  collider y distancia usada por la ley radial. Reproducir el desacuerdo
  antes de cambiar la selección.
- Si se confirma, resolver la altura de contacto y el punto de fuerza con
  el mismo apoyo y la geometría del cilindro. Verificar qué información da
  el barrido y ensayar una consulta adicional si hace falta aislar el
  collider. La proyección de un punto como si proviniera de un rayo no basta
  para obtener la altura del centro del cilindro en pendiente.
- **Aceptación.** El punto, la normal y el collider corresponden al apoyo
  usado para calcular la distancia. Conservar la respuesta en plano y
  pendiente de apoyo único, y comparar deformación y saltos de carga al
  cruzar el borde en ambos sentidos.

[Selección de candidatos y fracción segura](../../scripts/physics/vehicle_simulation.gd#L724)

## 4. Commit atómico del garaje (hallazgo 6)

- Mantener el reglaje candidato en `staging` hasta completar la operación
  del preset que puede fallar. Revisar que el método del modelo valide antes
  de escribir el runtime. Publicar dominios, ID activo y valores aceptados
  cuando se hayan superado los pasos que devuelven error.
- **Aceptación.** Cubrir un preset inválido rechazado por el catálogo y
  forzar por separado un rechazo en la validación del modelo tras resolver el
  preset. Capturar antes y después dominios, ID activo, configuración de
  diferencial por eje y un reglaje ajeno al LSD. Todo debe coincidir tras
  ambos rechazos. En el caso válido, los dominios y el runtime deben reflejar
  el mismo preset.

[Staging y commit](../../scripts/physics/vehicle_simulation.gd#L444) ·
[Contrato de presets](../../tests/rally/differential_preset_contract.gd)

## 5. Recentrado e inercias (hallazgos 15, 17 y 18)

- Auditar por perfil el inventario suspendido antes y después del recentrado,
  las cuatro masas de hub, la posición del tanque y la COM total. Registrar
  reparto delantero calculado con depósito vacío, carga inicial y lleno.
  Indicar qué masa y condición representan el objetivo de cada ficha.
- Verificar qué referencia física y qué eje representa `target_cg_z_m`.
  La implementación actual lo aplica al eje Y local. Resolver el contrato
  del campo y la compatibilidad de perfiles antes de cambiar su significado
  o reubicar el tanque. Documentar cuándo actúan los límites de recentrado.
- Registrar por rueda inercia autorada, fallback y valor efectivo. Distinguir
  sustitución por ausencia de dato de elevación por mínimo. Cuantificar el
  efecto sobre la aceleración angular antes de modificar esa política.
- Comparar tensor completo y diagonal aplicada, incluidos productos de
  inercia, momentos principales y desigualdades triangulares tras aplicar
  los multiplicadores. Proponer uso de ejes principales solo si las
  diferencias medidas lo justifican y tras verificar el marco de Jolt.
- **Aceptación de la auditoría.** Tabla reproducible por perfil con masas,
  COM, reparto, desplazamiento de recentrado e inercias. Verificar sumas y
  momentos en reposo sobre plano para un perfil de referencia y uno que
  muestre una discrepancia. Acordar la condición de referencia antes de
  cambiar calibraciones.

[Recentrado e inercia de rueda](../../scripts/physics/mass_model.gd#L144) ·
[Aplicación de masa e inercia al chasis](../../scripts/rally/rally_escort_vehicle.gd#L394)

## 6. Cálculo compartido de suspensión (hallazgo 19)

- Extraer el cálculo común de rigidez, amortiguamiento, barra y tope. Pasar
  explícitamente la masa de referencia, frecuencia, factores y valores de
  diseño. Mantener los deltas de altura y de multiplicador de tope del
  garaje y la precedencia de la frecuencia declarada.
- Usar en el garaje la masa de referencia ya calibrada. Mantener la
  configuración de geometría y joints fuera de este cálculo. Si más
  adelante se editan bump o droop en vivo, actualizar de forma coordinada
  parámetros, alcance de contacto y límites de las juntas.
- **Aceptación.** Comparar valores por esquina antes y después del refactor
  al cargar el perfil, reaplicar el reglaje de fábrica y aplicar cambios
  válidos de frecuencia, amortiguamiento, barra, altura y topes. Repetir
  con combustible consumido y comprobar que reaplicar el mismo reglaje
  conserva masa de referencia y valores de diseño.

[Configuración inicial](../../scripts/physics/suspension_model.gd#L143) ·
[Actualización del garaje](../../scripts/physics/vehicle_simulation.gd#L474)

## Orden de entrega

1. Corregir la presión y el orden de commit del garaje en cambios separados.
2. Crear los casos de extensión y apoyos múltiples. Resolver primero el
   alcance y luego la coherencia geométrica del ShapeCast.
3. Auditar masa e inercias y registrar las decisiones de calibración.
4. Extraer el cálculo de suspensión con regresiones de carga y garaje.
