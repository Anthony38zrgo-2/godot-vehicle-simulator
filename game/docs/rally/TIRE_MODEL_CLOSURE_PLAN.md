# Plan de cierre del modelo de neumáticos

Complementa [TIRE_MODEL_HANDOFF.md](TIRE_MODEL_HANDOFF.md). Los umbrales de este plan son criterios de aceptación propuestos. Registrar los resultados del Escort antes de cada cambio para distinguir regresiones de variaciones deliberadas de calibración.

## 1. Cota instantánea y reset de la envolvente

**Archivos:** `tire_model.gd` y `tire_handoff_acceptance_contract.gd`.

- Conservar la carga filtrada en la respuesta transitoria. Construir una segunda elipse con la carga normal instantánea, las capacidades direccionales, la caída pospico y la rampa de contacto. Aplicarla como cota final junto a la elipse vigente. Usar el mismo factor sobre Fx neta, Fy y la rodadura que se publica para reconstruir el par y calcular calor.
- Invalidar la carga filtrada y la geometría derivada al despegar y en `reset_patch()`. Sembrar el filtro con la primera carga válida al volver a contacto. Preservar el convenio de rampa y el radio nominal sin contacto.
- Probar carga sostenida seguida de descarga de 3500 a 200 N, pérdida completa de contacto y aterrizaje de 0 a 4000 N en 5 ms con dirección girada. En cada subpaso con contacto, exigir utilización de la elipse instantánea ≤ 1.001. En aire, exigir fuerza y par nulos. Comparar dos aterrizajes idénticos precedidos por cargas distintas para detectar memoria residual.

## 2. Deflexión de respaldo y salida radial sin contacto

**Archivos:** `tire_model.gd`, `tire_radial_model.gd` y su contrato.

- Extraer la inversión de fuerza elástica a una rutina compartida para la referencia estática y el fallback. Resolver F_elástica(δ) = Fz por bisección monótona, con la presión y óptima de carcasa resueltas, seating y tope de llanta. Si la carga excede la fuerza del límite de deflexión admitido, saturar en ese límite. Dar prioridad a la deflexión que entrega el rig.
- Calcular el radio efectivo del mismo subpaso con la deflexión ya resuelta, antes de calcular slip. Preparar los coeficientes radiales una vez por solución y evitar reevaluar diccionarios dentro de la bisección.
- Cuando la fuerza radial unilateral sea cero, devolver disipación radial cero. Con contacto activo, comprobar el signo de la disipación en compresión y rebote.
- Validar inversión en el asiento, régimen principal y tope a varias presiones. Para soluciones dentro del intervalo, exigir un error de fuerza ≤ máx(1 N, 0.1 % de Fz). Cubrir carga cero, saturación, descarga rápida con fuerza y calor cero y una deflexión inyectada por el rig que prevalezca sobre el fallback.

## 3. Inicialización de los cuatro compuestos

**Archivos:** `tire_model.gd`, `thermal_model.gd` y contrato de inventario.

- Validar índice e ID antes de modificar el estado. Al recuperar un catálogo vacío, inicializar las ruedas faltantes con el compuesto activo y su ID. Si todavía no hay compuesto activo, usar como base el primer compuesto válido solicitado. Copiar cada definición por rueda y conservar las selecciones existentes. Aplicar la misma precedencia en neumático y térmico.
- Probar arranque sin catálogo ni compuesto activo, sustitución posterior de una rueda, persistencia entre etapas e ID inválido. Exigir cuatro IDs válidos y coincidentes entre ambos modelos y verificar que el intento inválido preserve las selecciones anteriores.

## 4. Balance energético cuantitativo

**Archivos:** `tire_model.gd`, `vehicle_simulation.gd` y un contrato de física.

- Registrar por subpaso el trabajo de contacto con Fx de contacto reconstruida mediante Fx neta + rodadura, velocidad de deslizamiento de llanta con el radio efectivo y la componente lateral con el signo del marco. Integrar rodadura por separado. Registrar energía elástica antes y después, y separar los cambios por proyección plástica, rigidez, mezcla de contacto y descarte al despegar. Si se incluye trabajo por momento autoalineante, declararlo como término separado con su velocidad angular conjugada.
- Medir el residual de cierre en julios sobre la ventana completa y el residual firmado por subpaso. Obtener los términos desde cambios de estado o mecanismos independientes. Un residuo calculado por diferencia y contabilizado automáticamente como calor cerraría la ecuación por construcción. Mantener el descarte al despegar separado del calor.
- Cubrir rodadura libre, carga y descarga elástica, frenada con rueda bloqueada, slip combinado sostenido, transición estático/dinámica, cambio de rigidez y despegue. Comparar h nominal, h/2 y h/4. Como objetivo inicial, exigir error acumulado ≤ máx(1 J, 1 % del trabajo absoluto integrado), convergencia al reducir h y disipación acumulada no negativa por mecanismo. Registrar el máximo residual por paso para detectar picos ocultos por cancelación.

## 5. Aceptación con vehículo completo en Jolt

**Archivos:** `vehicle_simulation.gd` y un contrato de escena con el vehículo de producción.

- Preparar una escena controlada con rampa del 10 %, tramo plano y un desnivel de altura conocida. Usar el Escort y repetir con un perfil de tracción distinta. Registrar entradas, velocidades del chasis, giro por rueda, Fz instantánea, fuerza, presupuesto de agarre y estado de contacto. Ejecutar a 60 y 120 Hz externos con el mismo límite de subpaso interno.
- **Pendiente.** Sostener 10 s con el freno real. Exigir velocidad del chasis < 1 mm/s durante el último segundo y registrar desplazamiento y pico transitorio.
- **Frenada.** Partir con ruedas girando, aplicar freno y repetir con dirección fija. Exigir detención, ausencia de inversión sostenida de giro tras parar y utilización instantánea ≤ 1.001 por rueda.
- **Aterrizaje.** Despegar y aterrizar con dirección aplicada. Exigir fuerza nula en aire, cota instantánea durante la recuperación y ausencia de valores no finitos. Comparar distancia de frenado e impulso lateral de aterrizaje entre frecuencias. Usar un 5 % como tolerancia inicial y documentar cualquier ajuste con datos de la escena.

## 6. Envolvente espacial tandem-cam

**Archivos:** adquisición de contacto en `vehicle_simulation.gd`, consumidor radial en `unsprung_suspension_rig.gd` y contrato de escena.

- Prototipar una envolvente longitudinal de dos apoyos geométricos separados a partir de la longitud de huella. Evaluar el perfil del suelo en el marco de rodadura y combinar ambos apoyos en una altura efectiva continua. Mantener separados distancia de detección, radio geométrico y radio efectivo de rodadura. Definir el comportamiento si solo un apoyo tiene contacto y al cruzar bordes entre superficies.
- Activar el prototipo con una opción de comparación. Medir primero con el filtro temporal actual y después con la geometría activa. Revisar cuánto filtrado temporal sigue haciendo falta para evitar retraso duplicado. Medir el coste de consultas por rueda y por tick. Activada por defecto al cierre (`tandem_cam_enabled := true`, conmutable a ShapeCast legacy); la revisión del filtrado temporal duplicado queda como medición pendiente en escena.
- Comparar piso plano, escalón, bache corto, cresta y bordillo a dos velocidades y en ambos sentidos. En plano, exigir carga de equilibrio dentro del 1 % respecto a la referencia. En el obstáculo, comprobar que el inicio y la duración de la respuesta se correspondan con las posiciones de los apoyos al graficar contra distancia recorrida. Exigir pérdida de contacto al quedar ambos apoyos en aire y repetir las pruebas de cota, energía y vehículo completo.

## Secuencia de entrega

Implementar 1–3 con sus regresiones, medir y cerrar 4, establecer la referencia de vehículo en 5 y comparar el prototipo de 6 contra esa referencia. Actualizar el handoff con resultados medidos y diferencias por perfil. Tandem-cam activada por defecto al cierre; queda pendiente la medición en escena del filtrado temporal duplicado.
