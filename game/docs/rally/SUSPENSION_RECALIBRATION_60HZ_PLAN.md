# Plan de recalibración de suspensión con Jolt a 60 Hz

## Alcance y punto de partida

Fijar Jolt a 60 Hz durante toda la campaña y comprobar el tick efectivo en cada traza. Usar ShapeCast3D, el catálogo actual, los mismos subpasos del neumático y el mismo setup de referencia por coche. Calibrar únicamente `front/rear.ride_frequency_hz` y `front/rear.damping_ratio` de los perfiles activos. Confirmar el manifiesto que carga cada variante antes de tocar directorios de upgrades.

| Perfil | Frecuencia natural delantera / trasera (Hz) | Relación de amortiguamiento delantera / trasera |
| --- | --- | --- |
| Escort RS2000 | 1.674 / 1.701 | 0.338 / 0.668 |
| Fulvia | 1.750 / 1.850 | 0.550 / 0.550 |
| Nueve RT base | 1.700 / 1.800 | 0.500 / 0.500 |

El Escort sirve de control con su calibración actual. Los RT parten de cuatro valores comunes, pero se ajustarán por vehículo porque cambian las masas, la geometría y las cargas por esquina. Completar primero el Fulvia. La extensión a otros perfiles es una etapa posterior.

La frecuencia natural configurada es una referencia de la suspensión, distinta del tick del motor físico. `VehicleSuspensionModel.corner_rates` calcula la rigidez en rueda como k = m_ref × (2πf)² y los coeficientes de compresión y rebote como c = 2ζ√(k × m_ref) × su multiplicador. Reducir f un 5 % reduce k aproximadamente un 9.75 % y también cambia c. Registrar ambos coeficientes efectivos y la rigidez resultante de la estabilizadora, cuyo cálculo depende de la rigidez en rueda.

## Instrucciones para el agente — primera entrega, Fulvia

1. Cargar `game/data/vehicles/lancia-fulvia/vehicle.json` en una escena de pruebas Jolt con el chasis y los cuatro bujes del runtime. Adaptar `suspension_drop_rescue_probe.gd` para seleccionar el Fulvia y ejecutar entradas por tick. Al iniciar cada pasada, registrar y comprobar `profile_id`, Jolt, `Engine.physics_ticks_per_second == 60` y `tandem_cam_enabled == false`. Partir de una sesión limpia y del setup de fábrica con combustible y temperaturas iniciales iguales entre pasadas.
2. Guardar la línea base con f delantera/trasera de 1.750/1.850 Hz y ζ delantera/trasera de 0.550/0.550. Repetir reposo, caída de 0.5 m y bache unilateral al menos tres veces. Añadir frenada recta y salida de curva lisa y sobre cresta. Identificar el primer tick anómalo y la primera rueda afectada. Si el banco no reproduce el síntoma, incorporar la maniobra del tramo reportado antes de elegir una calibración.
3. Probar un parámetro por vez, comenzando por el eje donde diverge la traza. Barrer f a ±5 % y ±10 % de su nominal. Con la mejor f por eje, barrer ζ en 0.45, 0.50, 0.55, 0.60 y 0.65. Reiniciar la escena para cada candidato y mantener constantes neumáticos, geometría, multiplicadores de amortiguación y masa inicial. Aplicar los candidatos en memoria y verificar los valores efectivos después de cargar el setup.
4. Comparar las trazas de base y candidato por rueda. Usar recorrido, fuerza del amortiguador, topes, duración de pérdida de apoyo y tiempo de asentamiento para seleccionar el ajuste. Confirmar el candidato combinado con combustible nominal y bajo. Exigir que el fallo reproducido desaparezca y que frenada y salida de curva queden dentro de las tolerancias fijadas con la línea base. Si el fallo persiste o nace en contacto o restricciones, documentar el primer tick y la evidencia antes de ampliar el alcance.
5. Al cerrar esta entrega, escribir únicamente los cuatro valores aceptados en `game/data/vehicles/lancia-fulvia/suspension.json` y actualizar la entrada `profile_json_sha256.suspension.json` de `HISTORICAL_PROVENANCE.json` en ese mismo directorio. Repetir la prueba desde disco, ejecutar los contratos `vehicle_simulation_correction_contract.gd` y `tire_closure_plan_contract.gd`, y entregar valores antes/después, trazas, resultados y cualquier validación en pista pendiente. Mantener esta entrega acotada al Fulvia.

## 1. Reproducir y medir la línea base

- Extender en la fase de implementación la sonda headless de caída y rescate para seleccionar perfil y reproducir secuencias de entrada por tick. Cargar la escena real de chasis y bujes Jolt. Guardar CSV por tick y un resumen por perfil, maniobra y candidato.
- Empezar por reposo en plano, caída simétrica de 0.5 m y bache de una rueda. Añadir frenada recta, curva lisa con gas constante, salida con rampa de gas y salida sobre cresta. Repetir cada caso desde la misma pose, velocidad, combustible y temperatura inicial.
- Registrar recorrido físico y velocidad relativa del buje, cargas por rueda, fuerzas de muelle, amortiguador y tope, pérdidas de contacto, guiñada y deriva de carrocería. Anotar el primer tick en que divergen recorrido, fuerza o apoyo y medir picos, tiempo de asentamiento y duración de la descarga.
- Verificar que la prueba reproduce el síntoma antes de afinar. Si la primera divergencia aparece en una consulta de contacto, un tope o una restricción y persiste con cambios moderados de f y ζ, investigar ese mecanismo a 60 Hz antes de seguir buscando valores.

## 2. Ajustar por eje

1. Barrer f en un eje a la vez con ζ fija. Probar nominal, ±5 % y ±10 % como puntos exploratorios. Ajustar primero el eje cuya traza diverja antes. Elegir candidatos por recorrido disponible, frecuencia de oscilación medida, tiempo en topes y recuperación de carga. Repetir para el otro eje.
2. Con f elegida, barrer ζ en incrementos de 0.05 alrededor del valor de partida, hasta ±0.10 en la primera pasada. Usar caída y bache para detectar rebotes sucesivos y alternancia de fuerza entre ticks. Conservar los multiplicadores de compresión y rebote durante esta comparación.
3. Combinar los mejores candidatos de ambos ejes. Repetir frenada, curva y cresta para revisar cabeceo, balanceo, margen lateral trasero y tracción. Si la combinación empeora la respuesta, probar puntos intermedios alrededor de los mejores candidatos. Aplicar las variantes en memoria durante la búsqueda.
4. Repetir con los perfiles activos restantes. Confirmar cada candidato con combustible bajo y nominal. Usar el Escort de control para detectar cambios en el banco de pruebas.

## 3. Aceptación y publicación

- Exigir reposo estable, fuerzas finitas, ausencia de oscilación creciente y ausencia de pérdidas repetidas de apoyo en plano. En caída y bache, exigir que la envolvente de oscilación decaiga y que el vehículo vuelva a un apoyo estable. Registrar impactos de tope y comparar su frecuencia con la línea base.
- En curva y cresta, comprobar que el candidato reduce el síntoma reproducido. Registrar el pico de guiñada, la duración de la descarga trasera y el tiempo de recuperación de fuerza lateral. Comparar también distancia de frenada y velocidad de salida. Establecer tolerancias a partir de la repetibilidad de la línea base antes de elegir valores.
- Registrar por auto los cuatro valores anteriores y propuestos, las rigideces y coeficientes efectivos y los resultados de las maniobras. Confirmar el manejo en el tramo donde se reportó el fallo antes de dar la calibración por aceptada.
- Escribir los valores aceptados en `suspension.json`, actualizar su SHA-256 en el manifiesto de procedencia correspondiente y volver a verificar los hashes. Ejecutar los contratos de simulación y neumáticos y repetir las maniobras con los perfiles cargados desde disco.

Referencias del proyecto — [Cálculo de rigidez y amortiguación](../../scripts/physics/suspension_model.gd), [sonda de caída y rescate](../../tests/rally/suspension_drop_rescue_probe.gd) y [plan de corrección de suspensión](SUSPENSION_CORRECTION_PLAN.md).
