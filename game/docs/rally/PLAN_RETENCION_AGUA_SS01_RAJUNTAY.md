# Plan de implementación de la retención local de agua en SS01 Rajuntay Alto

## Objetivo y alcance

Mantener los cinco sectores de clima de CDI y añadir variación continua a la película de agua dentro de cada sector. Bajo lluvia moderada, una cresta expuesta debe poder quedar casi seca, una bajada debe verse y sentirse húmeda y una depresión debe poder tener un charco. El contraste debe ser legible desde la cámara de persecución y corresponder con el contacto de cada rueda.

El piloto se habilitará solo en `cdi_stage1` y en el modo `five_sector_snapshot`. El perfil se calculará al preparar el tramo y será fijo durante esa pasada, igual que el snapshot de superficie. El alcance cubre agua líquida, su efecto visual y el contacto. La evolución espacial de nieve y hielo, el peralte como factor de retención, el secado por tráfico y el flujo de agua entre celdas quedan para fases posteriores.

## Punto de partida en el código

| Componente | Comportamiento actual | Cambio previsto |
| --- | --- | --- |
| [Configuración de Rajuntay Alto](../../data/competition/stages/cdi_stage1.json) | SS01 usa `five_sector_snapshot` y un perfil climático de ruta con 204 muestras en unos 5 km. | Habilitar el perfil de retención en la configuración de esta etapa. |
| [Clima y superficie nativos](../../../rust/rally_native/src/procedural_weather.rs) | `interpolate_surface_columns` mezcla agua, nieve y hielo entre centros de sector y ajusta las fases según la diferencia de altitud. `sample_surface_at`, el paquete visual y el llenado de charcos consultan esas columnas. | Aplicar la retención longitudinal al agua líquida resultante y conservar las otras columnas. |
| [Topografía nativa de charcos](../../../rust/rally_native/src/puddles.rs) y [colocación de charcos](../../scripts/rally/rally_puddles.gd) | La pendiente y la concavidad alimentan el índice topográfico de humedad (TWI). El índice guía la colocación y también amplifica el llenado en el snapshot. | Compartir las medidas topográficas y mantener el TWI en la colocación. En el modo nuevo, el llenado recibirá la película ya modulada. |
| [Textura de superficie](../../scripts/rally/cdi_procedural_surface.gdshaderinc) y [streaming visual](../../scripts/rally/rally_visual_sector_stream.gd) | El canal rojo de una textura de una fila codifica agua por estación del shader. Los materiales de carretera reciben la textura por revisión. | Publicar el agua local en ese canal y verificar que el material de grava de SS01 lo aplique. |
| [Proyección de contacto](../../scripts/rally/rally_weather_controller.gd) y [simulación de vehículo](../../scripts/physics/vehicle_simulation.gd) | Cada rueda consulta la superficie en su posición. La simulación combina la película con la profundidad de charco o cauce y usa ambos datos para calcular la respuesta. | Conservar la consulta por rueda y verificar la transición de agarre entre película y agua estancada. |

## 1. Medir la topografía y construir el perfil

1. Comparar la correspondencia entre los puntos de la ruta de conducción, el perfil climático y la estación usada por el shader. En SS01, el perfil climático empieza aproximadamente en la estación 61,5 m aunque el progreso comienza en 0 m. Verificar inicio, final y varias curvas cerradas, además de comprobar que el mapeo sea monótono. Usar `progress_to_shader_station` y su inversa al cruzar entre ambas coordenadas.
2. Extraer del puente nativo de charcos el cálculo geométrico de pendientes de entrada y salida. Reutilizarlo con una separación fija en metros para el perfil de superficie. La API `compute_route_topography_packed` conservará su ventana actual, sus valores y el orden de salida; el índice de charcos también conservará el giro y la convención de signo. Una comparación antes y después de la extracción debe dar las mismas muestras y candidatos.
3. Para el perfil inicial, usar posiciones de la ruta climática con su altitud y distancias horizontales. Su separación media ronda 25 m. Se puede muestrear el campo resultante cada 10–15 m para renderizarlo, pero esa interpolación no añade detalle topográfico. Si la ruta climática omite una depresión relevante, probar la ruta de conducción, que tiene 633 puntos, después de verificar su alineación con la ruta climática. Evitar un emparejamiento ingenuo por índice o por cercanía en planta cuando haya curvas próximas.
4. Tomar pendientes hacia delante y hacia atrás con una ventana inicial de alrededor de 30 m a cada lado. La diferencia entre ambas será positiva en una depresión y negativa en una cresta. Reducir la retención con la pendiente absoluta, reducirla más en crestas y aumentarla en depresiones suaves. Usar transiciones continuas y comprobar que la ventana no convierta el primer o el último punto en depresiones artificiales.
5. Suavizar el resultado a lo largo de toda la ruta en una ventana inicial de unos 60 m, ajustable dentro de 30–80 m. Aplicar el suavizado por distancia, con interpolación continua entre muestras y sin reiniciarlo al cruzar una frontera climática. Empezar con `1,0` como valor neutro y límites de prueba de `0,25` a `1,50`. Estos límites sirven para calibrar contraste y deberán ajustarse con mediciones de SS01.
6. Guardar el perfil derivado con la geometría de la etapa y reutilizarlo al preparar o restaurar un snapshot. Si el perfil es inválido, usar retención neutra y el cálculo de llenado anterior; emitir un diagnóstico una vez durante la preparación. Medir el tiempo de preparación y verificar que el muestreo por rueda se reduzca a interpolar datos existentes.

**Salida de esta fase.** Una inspección por distancia que muestre estación del shader, sector, pendiente, concavidad y retención. Identificar en ese perfil una cresta, una bajada y una depresión del mismo sector antes de ajustar efectos visuales o fricción.

## 2. Integrar la película con el snapshot de cinco sectores

1. Añadir una opción de configuración local a la etapa, desactivada por defecto. Pasarla por el mismo flujo que configura `five_sector_snapshot`. Probar la configuración tanto en etapa individual como en evento, con la hora efectiva que produce el calendario.
2. En `interpolate_surface_columns`, calcular primero el estado actual por mezcla de sectores y ajuste térmico local. Aplicar después, solo si el perfil está activo, `agua_local_mm = agua_líquida_resultante_mm × retención_local`. Limitar el resultado al rango representable y usar cero exacto cuando no haya agua líquida disponible. El multiplicador aproxima drenaje y acumulación a escala de tramo; no integra el transporte de agua entre puntos.
3. Usar el valor resultante para `water_mm` y derivar las variables existentes de cobertura y agua efectiva desde esa misma película, manteniendo los límites que ya aplica el neumático. Conservar la semántica de saturación del terreno y del resumen por sector. Añadir temporalmente a la inspección por distancia el agua antes de la retención y la película final.
4. Mantener el formato actual de guardado. El snapshot serializa las reservas de los cinco sectores; la película local se vuelve a calcular con la geometría de la etapa y las reservas restauradas. Al restaurar, la revisión debe invalidar la textura y los llenados de charcos que dependan de ella. Comparar una partida nueva con una restaurada bajo la misma configuración.

## 3. Compartir el resultado con el shader

1. Alimentar el canal rojo de `surface_field_packet_since` con la misma película que consulta la rueda. Mantener la textura de una fila y las coordenadas de estación del shader. Con el ancho actual, SS01 parte de unas 204 muestras para unos 5 km. Para el piloto, probar un ancho calculado por longitud y limitado a 512, con un objetivo de unos 12,5 m por muestra. Conservar el ancho anterior en los tramos sin el perfil.
2. Comparar la lectura de CPU con una decodificación del paquete que reproduzca la interpolación lineal y la corrección a centros de texel del shader. La cuantización de una muestra en `RGBA8` introduce hasta medio paso, con paso igual a `max_encode_mm / 255`. Evaluar por separado el error espacial entre texeles. Si se pierden películas finas que sí afectan el neumático, medir primero si conviene una escala propia para el canal rojo o más precisión, manteniendo la compatibilidad con los demás canales.
3. Comprobar el material de grava de SS01, los límites entre sectores visuales cargados por streaming y el reinicio de la etapa. Ajustar el oscurecimiento y la rugosidad del material si la película medida tiene poca lectura desde la cámara. La cobertura visual debe responder al campo local, incluida la diferencia entre lluvia activa y suelo que conserva agua después de que pare.

## 4. Ajustar el llenado y el contacto con charcos

1. Mantener la colocación determinista, el TWI de selección, la forma, el umbral y la retención de cada cuenca. Cuando el perfil longitudinal esté activo, usar `agua_local_mm` como agua disponible para el llenado y omitir la multiplicación anterior por `puddle_twi_base + puddle_twi_gain × TWI`. Mantener la atenuación por fracción líquida donde haya hielo. En el camino sin perfil, conservar la fórmula anterior completa.
2. Comparar el llenado antes y después para la misma semilla. Verificar que las depresiones sigan teniendo candidatos activos con lluvia moderada y que una cresta no active charcos solo por un cambio de escala. Calibrar primero el contraste de la película y después los umbrales del llenado si la pasada lo requiere.
3. Revisar tanto el contacto escalar como el camino de cuatro ruedas. Actualmente el agua combinada se calcula con un máximo y luego se resta la profundidad de charco para estimar la película. Probar puntos antes del borde, en el borde y en el centro de una máscara. Si aparece una discontinuidad perceptible, conservar explícitamente la película de fondo para la respuesta del neumático y coordinarla con el efecto de agua estancada para que la misma lámina no se contabilice dos veces. Mantener el contrato existente de los cauces.
4. Registrar para esa prueba, por rueda, el progreso, la película local, la profundidad del charco y la respuesta de agarre o arrastre. Comprobar que una rueda que queda fuera de la máscara no recibe el arrastre aplicado a la que entra.

## 5. Validación y aceptación

### Pruebas automatizadas

- **Rust.** Verificar el signo de la concavidad con una cresta y una depresión sintéticas, la retención neutra si falta un perfil válido, el agua cero en seco, el orden de retención bajo lluvia uniforme y la continuidad al cruzar límites climáticos. Comparar el llenado con y sin perfil usando un caso que detecte la aplicación doble de TWI.
- **Integración de SS01.** Con semilla y hora fijas, comprobar que la superficie se configura en el modo previsto, proyectar contactos en los tres puntos de interés y contrastar su película con los datos decodificados de la textura. Repetir tras restaurar el snapshot para comprobar que ruedas, textura y charcos vuelven a reflejar el mismo estado. Verificar que el clima seco conserva agua cero donde no han existido lluvia ni deshielo.
- **Regresiones.** Compilar la extensión y verificar que Godot carga la biblioteca recién compilada. Ejecutar los contratos existentes de charcos, clima y neumáticos y SS04. Revisar el coste de preparación y confirmar que una revisión estable no genera subidas de textura ni recálculo de topografía durante la carrera.

Comandos de referencia desde la raíz, después de preparar la extensión y los recursos que usa Godot. Usar el ejecutable local de Godot si `godot` no está en PATH.

```powershell
cargo test --manifest-path rust/Cargo.toml -p rally_native
godot --headless --path game --script res://tests/rally/puddles_contract.gd --quit-after 120
godot --headless --path game --script res://tests/rally/dynamic_weather_tires_contract.gd --quit-after 120
godot --headless --path game --script res://tests/rally/ss04_surface_puddles_contract.gd
```

### Pasada de conducción en SS01

1. Elegir un sector con agua líquida y con los tres puntos topográficos identificados. Fijar semilla, hora efectiva, preset de lluvia moderada, coche y neumáticos. Registrar también los puntos en metros de progreso y estación del shader.
2. Recorrerlos con la cámara de persecución con trazada y velocidad comparables. La cresta debe leerse casi seca, la bajada húmeda y la depresión debe incluir al menos un charco visible en una trayectoria alcanzable. Repetir con dos trazadas en la depresión para pasar dentro y fuera de la máscara.
3. Comparar vídeo o capturas con telemetría por rueda. Debe cumplirse `película_cresta < película_bajada < película_depresión` en los puntos elegidos. La pérdida adicional de agarre y el arrastre de agua estancada deben coincidir con el contacto de la rueda dentro del charco. Revisar que no aparezcan escalones en las fronteras de clima o de streaming.
4. Repetir con el perfil desactivado usando la misma configuración y con un caso seco sin precipitación previa. Registrar los resultados de forma que se puedan repetir después de cambios de material o de neumático.

## Orden de entrega y siguiente fase

1. **Perfil y diagnóstico.** Extraer la geometría compartida, comprobar que los candidatos de charcos son reproducibles y localizar los tres puntos piloto.
2. **Película y render.** Activar SS01, pasar el agua local al muestreo de las ruedas y a la textura, y comprobar que la grava muestra el contraste esperado.
3. **Charcos y aceptación.** Retirar la doble aplicación topográfica en el llenado de SS01, verificar los contactos y completar la pasada reproducible y la regresión de SS04.

El piloto se considera aceptado cuando coinciden el contraste visual y los contactos medidos en una pasada de SS01, con las regresiones automatizadas resueltas. Para una segunda fase, extender el mismo muestreo compartido a nieve y hielo usando sus máscaras longitudinales y laterales actuales. Calibrar la persistencia con la temperatura del suelo y la disponibilidad de agua, por ejemplo hielo tras deshielo y recongelación. Ampliar a otras etapas después de verificar sus rutas, materiales y condiciones de invierno.

## Referencias de implementación

- [Apex GP: campo de agua compartido entre física y render](https://github.com/jolbol1/apex-gp/blob/main/src/weather/weather.js#L895).
- [LibreCorsa: factor topográfico para agua local](https://github.com/KhazP/librecorsa/blob/main/src/lib/sim/weather.ts#L885).
- [RoadSurf: temperatura de la carretera y reservas de agua, nieve y hielo](https://github.com/fmidev/RoadSurf/blob/master/README.md).
