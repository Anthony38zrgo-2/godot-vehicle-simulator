# Plan de implementación del agua dinámica de Kenia

## Estado y orden de ejecución

El usuario validó en juego el piloto `kenya_ford_1` de Kenia 1 y dio luz verde a planificar la ampliación. La siguiente entrega va en este orden: **Kenia 3 → Kenia 5 → Kenia 2 → Kenia 6**. En el [JSON actual](../../data/rally/kenya_rivers.json), esas cuatro especiales tienen fichas inactivas con valores provisionales. El [inventario](KENYA_RIVERS_INVENTORY.md) documenta las láminas importadas. Kenia 4, 7 y 8 quedan fuera de esta ampliación.

Usar Kenia 1 como referencia de regresión. Las tareas de ampliación empiezan en la sección siguiente. El diseño original se conserva al final como referencia para los contratos del sistema.

## Ampliación a Kenia 3, 5, 2 y 6

### A. Preparación común

- [ ] Revisar el estado del árbol y los `AGENTS.md` aplicables. Ejecutar `kenya_rivers_contract.gd` y `kenya_rivers_probe.gd` como referencia. El probe existente construye un vado sintético. Para esta ampliación, añadir un probe que cargue las especiales instaladas, use sus colisiones reales y pueda seleccionar la especial por argumento.
- [ ] Para cada especial, listar las superficies por nodo, índice de superficie, material y componente conexo en coordenadas globales. Compararlas con la ruta y el GLB de colisión. Identificar qué partes son un mismo cauce, dónde cambia la pendiente, qué zona del calendario alimenta cada sección y qué cruces son vados, puentes o simples aproximaciones.
- [ ] Registrar en el inventario, por sección, los IDs de malla, rango de progreso, cota base, cota de la calzada y orillas, dirección de flujo, subida máxima permitida y puntos de prueba con coordenadas XYZ. Para el clima usar `climate_progress_m` medido en la ruta cargada. Los valores provisionales de `0.4` de progreso y `0.45 m` de subida del JSON quedan sujetos a esa medición.
- [ ] Fijar la subida máxima tomando como límites el desborde lateral previsto y la profundidad máxima que permite completar cada vado. Ajustar `reference_rain_mm_h`, tiempos de subida y drenaje, `rainy_start_fraction` y `drag_scale` con el perfil del piloto como punto de partida. Registrar las cifras finales y su justificación por sección.

### B. Adaptar la selección y la geometría donde haga falta

- [ ] Revisar [`_discover_meshes()` y `_update_render()`](../../scripts/rally/rally_river_channels.gd). Hoy se seleccionan nodos por nombre de material y se desplaza el `MeshInstance3D` completo. Para secciones del mismo material, añadir selección por nodo y superficie, o generar mallas de agua por sección si los triángulos vienen en un solo batch. Cada triángulo visible debe pertenecer a una sola sección. Si un nodo contiene terreno u otras superficies, mover únicamente la geometría de agua. Conservar la ruta de carga del piloto.
- [ ] Comprobar el error del plano base ajustado contra los vértices originales y el nivel que usa la consulta física. Si una sección larga o curva excede la tolerancia, subdividirla o interpolar una cota que puedan evaluar tanto render como física. En uniones mojadas de un mismo río, compartir el nivel en el borde o usar una transición interpolada. Usar IDs estables en `channels` para persistir la subida de cada sección.
- [ ] Ajustar la resolución de `bed_bake_resolution` según el tamaño de celda en metros. Verificar que los rayos alcanzan el lecho con la colisión ya disponible y que, bajo un puente, se obtiene el terreno bajo el tablero. El horneado actual descarta ciertos impactos de puente por nombre. Si deja un hueco bajo un puente real, usar la clasificación de colisión disponible y continuar la consulta hasta el lecho, o preparar allí un campo de alturas verificado.
- [ ] Medir el borde mojado a nivel base y con crecida. La cobertura actual sale de los triángulos importados. Si estos terminan antes de la orilla que debe mojarse, añadir cobertura hasta la huella máxima medida y recortarla contra el lecho con la misma regla para shader y física. Probar en el contacto por rueda qué ocurre en seco meteorológico con una lámina permanente: el código actual omite la consulta cuando subida y objetivo son casi cero. Si se requiere profundidad de base en una especial nueva, corregir ese caso y comprobar explícitamente el comportamiento de Kenia 1 validado.

### C. Ejecutar por especial

| Orden | Entrada actual | Trabajo específico | Prueba para cerrar la especial |
| --- | --- | --- | --- |
| 1 | Kenia 3 · `kenya_stage3_river` · `river1_1`, 316 triángulos | Verificar si la lámina es una pieza y si intercepta la calzada. Si es continua, conservar una sección. Medir los bordes y la subida admisible en la sección transversal más estrecha. | Probar un cruce real si existe y un punto fuera de la lámina. Si el cauce queda al margen de la ruta, verificar la crecida desde la orilla y registrar la ausencia de vado. |
| 2 | Kenia 5 · `kenya_stage5_river` · `river2_1`, 5 837 triángulos | Identificar vados y puentes dentro de la huella. Medir el fondo y el tablero por separado. Dividir la superficie si hay componentes desconectados o si el plano base deja discrepancias. | En un vado confirmado, repetir la trazada con base y crecida. En un puente confirmado, comprobar agua visible debajo y profundidad cero en cada rueda por encima de la lámina. |
| 3 | Kenia 2 · `kenya_stage2_river` · `river2_1`, 19 605 triángulos en BMF | Dividir el río largo según componentes, pendiente y zonas climáticas. Asignar a cada sección sus propios triángulos, cota base, referencia de lluvia y rejilla local. Revisar las uniones y medir el coste de preparación al cargar la especial. | Simular lluvia distinta en dos secciones mientras el coche se mantiene en un punto fijo. Verificar niveles locales, continuidad en las uniones mojadas y contacto coherente en cada cruce confirmado. Comparar carga y coste por frame con la referencia. |
| 4 | Kenia 6 · `kenya_stage6_river` · `river1_1` y `river2_1`, 463 y 7 288 triángulos en BMF | Identificar los componentes de cada material y medir si se conectan. Dar estados independientes a cauces separados. Si confluyen, compartir la cota en el borde o interpolar el nivel en la unión y resolver la cobertura solapada. | Probar ambos cauces, su unión si existe y sus cruces confirmados. Con intensidades diferentes, verificar que no aparece un escalón en una confluencia ni se duplica la profundidad al consultar el contacto. Comparar rendimiento con la referencia. |

Para cada especial, completar A y los puntos aplicables de B, actualizar sus entradas en el JSON, activar los cauces medidos y ejecutar la validación de D antes de avanzar a la siguiente. Si la escena difiere del inventario, registrar la diferencia con coordenadas y decidir la subdivisión a partir de lo medido.

### D. Validación y entrega

1. **Datos y escena.** El probe de cada especial debe confirmar los IDs activos y el registro `RALLY_RIVER_READY`, con triángulos, cota y referencia climática válidos. Comparar el nivel visual y la profundidad reconstruida en los puntos medidos. Usar el objetivo de 20 mm del piloto en los vados y registrar el error medido.
2. **Conducción.** En práctica, repetir la misma trazada y velocidad con nivel base, lluvia ligera, crecida sostenida y drenaje. Registrar cota, lluvia local, altura del contacto, `river_depth_mm` y `river_channel_id`. Confirmar progresión del arrastre y de las salpicaduras, transitabilidad a la subida máxima y profundidad cero sobre tableros por encima del agua. Adjuntar capturas desde cabina y una cámara fija junto a la orilla.
3. **Competición y persistencia.** Probar el clima local por sección, el congelamiento en pausa, la conservación del nivel al rescatar, el restablecimiento al reintentar y la restauración al reanudar una partida. Recorrer una transición real entre especiales y otra hacia un tramo sin cauces para comprobar que no se heredan materiales, niveles ni contactos.
4. **Regresión.** Volver a ejecutar los contratos de ríos y clima y los probes de parches indicados abajo. Repetir el vado de Kenia 1 como control. En Kenia 2 y 6 registrar tiempos de carga, coste de horneado y tiempo de frame con la misma configuración de referencia.
5. **Cierre.** Actualizar el JSON y el inventario con el estado de cada especial, las cotas calibradas, puntos probados y resultados. Dejar identificados los cauces descartados o pendientes con la razón observada.

## Diseño original del piloto

### 1. Resultado y alcance

Convertir las superficies de agua de las ocho especiales de Kenia en cauces con profundidad visual y física. Los ríos permanentes conservan su nivel base en tiempo seco. La lluvia líquida sostenida eleva gradualmente el nivel y amplía el área mojada donde el relieve lo permite. Al cesar la lluvia, el cauce drena hacia su nivel base. En un vado, el coche encuentra la misma lámina que ve el jugador.

La primera entrega fue el vado piloto de `kenya_stage1`. Activar un cauce seco requiere verificar su geometría y su umbral de entrada de agua. Cascadas y elementos decorativos se tratan según su función visual.

### 2. Preparar e inventariar

- [x] Revisar `git status --short` y los `AGENTS.md` aplicables. Leer [la investigación de las mallas de Kenia](KENYA_WATER_INVESTIGATION.md) y [la documentación de los parches](../../scripts/rally/PUDDLES.md). Registrar los resultados de las pruebas de referencia antes de cambiar el runtime.
- [x] Localizar las superficies en las escenas importadas y verificar sus transformaciones en el espacio del tramo. Partir de `river1_1` y `river2_1`, documentadas en las especiales 1, 2, 3, 5 y 6. Revisar 4, 7 y 8 en escena y en sus activos. Registrar por especial cauces, lechos secos, cascadas, vados, puentes y zonas sin agua dinámica confirmada.
- [ ] Elegir un vado transitable de Kenia 1 y un puente cercano o de otra especial como control. Registrar posición, progreso de ruta, dirección, altura de calzada y sección transversal de orilla a orilla. Tomar referencias visuales desde cabina y cámara exterior en el estado actual.
- [x] Comparar malla visual y GLB de colisión en el vado. Identificar el piso que soporta las ruedas y el fondo que debe verse desde cámara. Registrar huecos, cruces de superficies a distintas alturas y diferencias relevantes entre visual y colisión. Medir una cota máxima que siga contenida por las orillas y preserve el cruce previsto.

**Salida de esta fase:** inventario de las ocho especiales y un vado piloto con geometría, cotas y puntos de comprobación reproducibles.

### 3. Preparar datos por cauce

- [ ] Crear un recurso versionado por especial bajo `game/data/rally/` con un ID estable por cauce, referencias a sus superficies, huella máxima, geometría de nivel base, referencia de clima en metros de progreso y parámetros de crecida. Usar coordenadas de la escena del tramo y convertirlas en un único punto de carga. Permitir subdividir un río largo por geometría o clima.
- [ ] Mantener la pendiente longitudinal de la malla original. Para cada punto XZ dentro de la huella, definir la altura base interpolada y sumar el incremento del cauce. En límites entre secciones del mismo río, compartir los extremos o interpolar el incremento en una franja común para evitar escalones.
- [ ] Delimitar la huella máxima con las orillas verificadas. Crear una malla de cobertura hasta ese límite y preparar un campo de altura del lecho a partir de terreno, orillas y calzada del vado. Puede hornearse en una rejilla local con máscara de validez y altura en metros. Elegir resolución suficiente para el borde del vado, documentarla y medir el error contra la geometría. En zonas con puente, excluir el tablero del horneado del lecho y conservarlo para la consulta de contacto del coche.
- [ ] Validar IDs, coordenadas, huellas, referencias y parámetros finitos al cargar. Los límites deben admitir superficies cóncavas y distinguir áreas solapadas en altura. Ante datos inválidos, emitir un diagnóstico por cauce y conservar su material actual, con la consulta dinámica desactivada para ese cauce.

Campos mínimos propuestos por cauce: `id`, huella y malla de cobertura, campo del lecho, referencia de altura base, progreso climático, subida máxima en metros, intensidad de lluvia de referencia en mm/h, tiempos de respuesta y drenaje en segundos de simulación y, si procede, umbral para activar el cauce seco. Guardar también los puntos de verificación del vado y puente. Los valores de juego salen de la calibración del piloto.

### 4. Calcular la crecida

- [ ] Crear un controlador de cauces de alcance de etapa. Mantener por sección un incremento `rise_m` y exponer la cota resultante a la malla y a las consultas físicas. Mantener el cálculo de nivel independiente del render.
- [ ] En competición consultar el clima **en el progreso fijo del cauce**. Añadir al controlador meteorológico una consulta de solo lectura basada en `surface.blended_state_at_distance(progress_m)` de [rally_surface_model.gd](../../scripts/rally/rally_surface_model.gd). Usar `climate.precipitation_mm_h` y resolver el tipo de precipitación con las reglas del controlador existente. La nieve queda fuera de la escorrentía de esta entrega. Si el clima mixto carece de fracción líquida, dejar su tratamiento explícito y probado.
- [ ] En práctica usar la selección de clima de la sesión, incluida la ruta de TCA que corresponda, y convertir sus estados o intensidad a mm/h en un único adaptador. Comprobar que `clear`, nublado y lluvia coincidan con las opciones que realmente expone la práctica. La saturación del suelo y la profundidad de los charcos pueden servir para diagnóstico. La entrada del modelo es lluvia líquida.
- [ ] Implementar un modelo de primer orden. Para un río permanente, calcular `target_m = max_rise_m * clamp(rain_mm_h / reference_rain_mm_h, 0, 1)`. Para un cauce seco aplicar primero el umbral de activación y definir la cota base en relación con su lecho. Actualizar con `rise_m = lerp(rise_m, target_m, 1 - exp(-dt_s / tau_s))`, usando un tiempo de respuesta al subir y otro al drenar. Aplicar límites y redondear a la cota base dentro de una tolerancia pequeña para evitar residuos al cabo del drenaje.
- [ ] Avanzar todos los cauces activos según el tiempo simulado. En competición usar la ventana de avance y la escala de `event_clock` de [rally_russia_stage_session.gd](../../scripts/rally/rally_russia_stage_session.gd:655). En práctica usar el delta de simulación bajo las mismas condiciones de actividad de la sesión. Verificar que el menú de reglaje, pausa y resultados congelan la crecida. La posición del coche no modifica el clima asignado a ningún río.
- [ ] Inicializar desde historial de lluvia líquida si el calendario lo suministra como tal. El antecedente actual de [rally_weather_scheduler.gd](../../scripts/rally/rally_weather_scheduler.gd) incluye datos de agua previa sobre el suelo y del intervalo entre especiales. Para la primera entrega, cuando falte historial de lluvia, usar una condición inicial determinista: nivel base en seco y una fracción calibrada del objetivo en un inicio lluvioso. Documentar esa fracción por perfil y conservar el nivel acumulado al reanudar.

### 5. Integrar el ciclo de vida de la etapa

- [ ] Registrar las superficies después de `_swap_stage_geometry()` y del ajuste de materiales. Inicializar la crecida después de que el clima de la etapa esté configurado o restaurado, antes de habilitar la conducción. Cubrir tanto `_ready()` como `load_event_stage()` en la sesión compartida.
- [ ] Al cambiar de etapa, desconectar el proveedor del vehículo antes de liberar mallas y datos. Al rescatar o recolocar el coche, conservar el estado de los cauces. En un nuevo intento, restaurar la condición inicial guardada para ese intento. Al reanudar una partida, restaurar el estado guardado para esa especial.
- [ ] Añadir al mecanismo de snapshots de superficie un campo opcional versionado con los incrementos por ID, asociado a la especial. Revisar `_setup_event_weather()`, el cierre de etapa, `_exit_tree()` y la ruta de reintento para usar el estado correspondiente. Partidas antiguas o IDs ausentes deben inicializarse como en el paso 4. Confirmar que una especial ajena a Kenia funciona sin instanciar un controlador de cauces.

### 6. Renderizar la lámina y sus bordes

- [ ] Añadir un shader de cauce tomando de [rally_puddle.gdshader](../../scripts/rally/rally_puddle.gdshader) la respuesta óptica a profundidad y las ondulaciones. Escalar la absorción y turbidez a profundidades de río. Usar la lluvia local para los impactos sobre la lámina y, si se añade movimiento de corriente, orientar el desplazamiento de textura por la dirección definida para el cauce.
- [ ] Desplazar la malla verticalmente con la cota calculada. Recortar el agua cuando la altura del lecho alcance o supere la lámina y suavizar el borde en una franja estrecha. Validar que solo se moja terreno comunicado con el cauce dentro de la huella delimitada. La transparencia puede variar con profundidad, con el fondo aún visible en aguas someras.
- [ ] Sustituir el material solo en superficies registradas y evitar dibujar a la vez la lámina importada y la de cobertura. Revisar [rally_stage_visual_material_adjuster.gd](../../scripts/rally/rally_stage_visual_material_adjuster.gd) y el rebindeo de `RallyTerrainWetness` para proteger el shader y sus parámetros. Usar un material por instancia donde los niveles deban ser independientes. Si el shader mueve vértices, ampliar los límites de visibilidad por la subida máxima.
- [ ] Probar con el renderer que usa la sesión normal. Revisar reflejos, bordes someros, oclusión bajo puentes y ordenación con partículas, vegetación y cascadas. El campo de altura del lecho permite calcular la profundidad óptica incluso cuando una lectura de profundidad de pantalla resulta inadecuada.

### 7. Integrar el agua en el contacto por rueda

- [ ] Añadir una consulta de solo lectura `sample_contact(world_position)` al controlador de cauces. Buscar por huella con un índice espacial sencillo y consultar la altura de la lámina en XZ. Usar únicamente el contacto cargado que ya resolvió la rueda en Jolt. Dentro de una zona válida y mojada, devolver `max(0, surface_y - contact_y) * 1000` en mm. El puente queda seco mientras el contacto esté sobre la lámina. Cuando haya geometría apilada, asociar la consulta al cauce y al nivel de lecho válidos para ese contacto.
- [ ] Integrar en `_local_conditions_at_contact()` de [vehicle_simulation.gd](../../scripts/physics/vehicle_simulation.gd:266). Combinar el agua de cauce y parche tomando el máximo y propagar los parámetros del origen elegido. Conservar el máximo entre ese resultado y `water_mm` climático para los consumidores actuales. Revisar cómo llegan la profundidad y el arrastre a neumáticos, telemetría y [rally_vehicle_vfx.gd](../../scripts/rally/rally_vehicle_vfx.gd). Mantener los contratos que leen `puddle_depth_mm` y `puddle_drag` o migrar juntos sus consumidores.
- [ ] Calibrar la respuesta mecánica del cauce. `RallyPuddles.contact_response()` aplica un arrastre que crece con la profundidad y la velocidad. Mantener la profundidad física para visualización y telemetría, con una profundidad efectiva o fuerza acotada para el modelo de vado. Comprobar que entrada y salida son progresivas y que el cruce lento sigue siendo controlable. La lámina es una consulta y una superficie de render. El lecho y la calzada conservan sus colisiones.
- [ ] Limitar el trabajo por rueda a búsqueda e interpolación. Hornear el lecho fuera del bucle de física, evitar recorridos de todos los triángulos en cada contacto y publicar el mismo estado de nivel para render y física.

### 8. Pruebas de referencia

1. **Modelo.** Añadir un contrato headless con seco, lluvia ligera, tormenta, drenaje, tope, dos deltas de simulación, pausa y dos secciones con clima distinto. Verificar determinismo, independencia de la posición del coche y compatibilidad con snapshots antiguos. Probar reintento, reanudación, rescate y carga de otra especial.
2. **Geometría y contacto.** Crear un probe de Kenia 1 con puntos fijos en centro del vado, borde, fuera del cauce y sobre puente. Verificar contacto seco fuera de la huella y sobre el puente, mayor profundidad en el vado al subir el nivel, ampliación de la zona mojada y combinación por máximo cuando exista un parche. Registrar cota base, cota actual, altura del contacto y profundidad por rueda. Fijar una tolerancia antes de la prueba según la resolución del campo de alturas, con objetivo inicial de hasta 20 mm entre lámina y profundidad reconstruida en los puntos del vado.
3. **Regresión.** Ejecutar desde la raíz con el binario Godot del proyecto. Sustituir la ruta del ejemplo por la instalación disponible, consultando `scripts/run_rally.ps1` para resolverla. Añadir a esta secuencia los nuevos contratos y el probe.

   ```powershell
   $godot = $env:GODOT_BIN
   & $godot --headless --path game --script res://tests/rally/puddles_contract.gd
   & $godot --headless --path game --script res://tests/rally/puddles_stage_probe.gd
   & $godot --headless --path game --script res://tests/rally/weather_runtime_regression.gd
   & $godot --headless --path game --script res://tests/rally/dynamic_weather_tires_contract.gd
   ```

4. **Inspección en juego.** Ejecutar `scripts/run_rally.ps1`, abrir el piloto desde el menú y repetir el vado con la misma trazada y velocidad. Capturar el nivel base, la crecida y el drenaje desde una cámara fija y desde cabina. Comparar salpicaduras, desaceleración y profundidad registrada. Pasar por el puente y recorrer la orilla para detectar cortes, agua flotante o extensión fuera del cauce. Comparar el coste de física y render con la referencia en la misma configuración, especialmente en Kenia 2 y 6.

### 9. Criterios de cierre

- [ ] Un vado se ve más profundo y el coche registra más agua después de lluvia sostenida. Ambos efectos retroceden al escampar.
- [ ] Lluvia ligera y tormenta producen curvas distinguibles. Cada cauce respeta su cota máxima y responde al clima de su ubicación.
- [ ] Un puente por encima de la lámina, las zonas fuera del cauce y los cauces secos por debajo de su umbral registran contacto seco por parte del proveedor de río.
- [ ] Las ocho especiales tienen inventario y estado de validación. Las que llevan agua dinámica cuentan con datos de calibración y pruebas registradas.
- [ ] Pasan los contratos de clima y parches y las comprobaciones de persistencia. Quedan adjuntos logs de los probes y capturas de la revisión en juego, con cualquier limitación observada.
