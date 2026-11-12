# Plan de revisión y corrección de la suspensión Rally

## 1. Estado de los hubs y filtros

- Inventariar lectores y escritores de recorrido, velocidad, contacto, memoria
  de filtros y recorrido de barra. Revisar las dos rutas de consulta de suelo,
  los perfiles y los contratos antes de retirar campos.
- Hacer que el rig sea el único escritor del estado físico por tick. En la
  rama sin impacto, registrar la ausencia de contacto y retirar la llamada
  redundante a `set_airborne()` una vez comprobado que sus escrituras no
  llegan a ningún consumidor. Distinguir impacto geométrico de carga positiva.
- Retirar la ruta antigua de `update_contact()` si el inventario confirma que
  carece de consumidores. Documentar qué claves de filtro se aceptan por
  compatibilidad y cuáles intervienen en el cálculo actual.
- Comparar trazas antes y después en reposo, descarga, vuelo y recontacto,
  con tándem y ShapeCast. El cambio debe conservar las muestras de recorrido,
  velocidad, carga y fuerza de barra que consume el vehículo.

[Consulta de contacto](../../scripts/physics/vehicle_simulation.gd#L738) ·
[Muestreo del rig](../../scripts/physics/unsprung_suspension_rig.gd#L119)

## 2. Teletransporte y primer tick físico

- Registrar el último tick previo al reset, el callback de rescate y los
  primeros ticks posteriores. Capturar poses y velocidades del chasis y hubs,
  compresión, velocidad relativa del amortiguador, fuerza y carga radial.
- Probar reset de sesión y rescate desde una pose con suspensión comprimida,
  con el coche en movimiento. Comparar la primera muestra válida con un
  vehículo recién colocado en el mismo destino y con el mismo estado inicial.
  Separar el asentamiento por gravedad o contacto del arrastre de estado previo.
- Limpiar en el reset los campos publicados que puedan conservar la muestra
  anterior. Cambiar la API de teletransporte solo si la traza demuestra que la
  pose o velocidad del nodo y del cuerpo de Jolt divergen en el primer solve.
- Aceptar cuando los hubs estén en la pose esperada al reanudar y la primera
  fuerza de amortiguador corresponda a la velocidad relativa medida.

[Reset del rig](../../scripts/physics/unsprung_suspension_rig.gd#L71) ·
[Rescate en el callback](../../scripts/rally/rally_escort_vehicle.gd#L404)

## 3. Calibración de muelle y reparto lateral

- Documentar que `ride_frequency_hz` tiene prioridad cuando se declara. Registrar
  por eje la masa suspendida de referencia, la frecuencia efectiva, el wheel
  rate y los coeficientes de amortiguamiento. Verificar el caso que usa la
  rigidez explícita como respaldo.
- Medir en plano las cuatro cargas de neumático y los recorridos tras el
  asentamiento. Usar una COM centrada como control y repetir con un
  desplazamiento lateral conocido en ambos sentidos. Mantener fijos combustible,
  masas de hub, neumáticos y reglaje, y registrar las vías delantera y trasera.
- Contrastar la suma de cargas y sus momentos con el peso y la COM del vehículo
  completo. Evaluar el reparto por esquina junto con la precarga de muelle y la
  contribución de la barra. Si se decide ajustar la precarga, conservar el
  equilibrio total y longitudinal y comprobar que las frecuencias vigentes
  se mantengan dentro de la tolerancia acordada.

[Precarga y frecuencia](../../scripts/physics/suspension_model.gd#L44) ·
[COM del chasis](../../scripts/rally/rally_escort_vehicle.gd#L387)

## 4. Progresividad y desasentado

- Graficar fuerza elástica y rigidez tangente frente a recorrido en compresión
  y extensión. Aislar amortiguador, barra y topes al medir la curva. Registrar
  la fuerza a recorrido neutro y el comportamiento al entrar en la cola
  exponencial y al aproximarse al final de extensión.
- Confirmar si el coeficiente `0.15` debe describir la ley de fuerza o una
  progresividad objetivo de rigidez tangente. Conservar la curva actual como
  referencia y comparar las curvas candidatas antes de elegir una.
- Definir por tipo de muelle cuándo se desasienta y si debe conservar apoyo de
  un auxiliar. Verificar continuidad de fuerza, precarga neutra y respuesta en
  descarga y recontacto antes de sustituir la cola exponencial.

[Ley elástica y desasentado](../../scripts/physics/suspension_model.gd#L213)

## 5. Estabilidad, orden de integración y juntas

- Instrumentar el tick de Jolt y el estado de ambos cuerpos que lee el rig.
  Registrar velocidad relativa, fuerza de amortiguador, impulso aplicado y
  trabajo por tick. Con esa traza, comprobar si la respuesta de chasis y hub
  corresponde al mismo paso. Inventariar también los ejes y límites efectivos
  de las juntas.
- Ensayar asentamiento, excitación vertical y caída controlada con un Escort
  y un vehículo de hub ligero, como el Fulvia. Comparar primero a la frecuencia
  de producción de cada perfil y repetir a 60, 120 y 240 Hz como diagnóstico.
  Controlar la frecuencia efectiva en cada ejecución y mantener fijos los
  parámetros. Medir altura de reposo, frecuencia y decaimiento de la
  oscilación, pico de carga y activación de límites.
- Si aparece un fallo reproducible, comparar una corrección a la vez. Evaluar
  un límite de impulso del amortiguador si la traza muestra inversión de
  velocidad por amortiguación, o revisar la aplicación cruzada si demuestra
  desfase entre cuerpos. Evaluar un motor de junta en una rama de prueba si
  persiste el problema. Exigir una mejora medible y repetir los casos de
  producción antes de cambiar la frecuencia o el método de integración.

[Frecuencia por perfil](../../scripts/rally/rally_escort_vehicle.gd#L123) ·
[Orden de integración](../../scripts/physics/vehicle_simulation.gd#L762) ·
[Juntas del rig](../../scripts/physics/unsprung_suspension_rig.gd#L44)

## Orden de entrega

1. Capturar trazas de referencia y simplificar las escrituras redundantes.
2. Validar el reset y corregir el estado residual que se observe.
3. Medir el reparto estático y las curvas elásticas. Registrar las decisiones
   de calibración antes de cambiar perfiles o fuerzas.
4. Ejecutar el banco de estabilidad. Abrir un cambio separado para cada
   corrección física que justifiquen las mediciones.
