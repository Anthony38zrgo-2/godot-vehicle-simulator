# Plan de IA de clasificación y resistencia para Rally

Estado: diseño de referencia, 1 de noviembre de 2026. Implementación activa y detalles de alcance en [README.md](README.md).

## Objetivo y alcance

Simular una parrilla histórica sin instanciar coches rivales, conducción ni físicas adicionales. Cada inscripción combina piloto, coche y equipo; tiene ritmo, condición mecánica, incidencias y resultados persistentes. Se simula antes de salir, por sectores durante el tramo y al llegar a meta. En este documento «tramo» significa una especial cronometrada; una etapa puede agrupar varias especiales y enlaces; el rally conserva el acumulado entre etapas.

La historia define tendencias, no ganadores obligatorios. Mäkinen puede destacar en grava y Munari en asfalto; un Singh más lento puede ganar por conservación. Ningún resultado histórico obliga a que se repita un abandono.

## Base actual y puntos de integración

- `game/scripts/rally/rally_stage_progress.gd`: checkpoints obligatorios, tiempo actual, último y mejor; no publica tiempos de sectores. Añadir captura de parciales sobre checkpoints seleccionados, conservando todos los controles de ruta existentes.
- `game/data/rally/russia_stage1_route.json`: geometría ordenada. Los puntos son controles de ruta, no sectores competitivos. Crear metadatos separados para sectores; usar longitud siguiendo la polilínea, nunca distancia directa salida-meta.
- `game/scripts/rally/rally_russia_stage_session.gd`: posee `course`, avanza cronometraje y publica `get_session_state()`. Aquí conectar inicio, cruce de parcial, llegada y reinicio con el coordinador de competición.
- `game/scripts/rally/rally_f1_head_up_display.gd`: pasa `course` al snapshot. Añadir `competition` para clasificación y delta.
- `game/scripts/rally/formula_hud_panels.gd`: dibuja cronómetro y mapa. La nueva tabla se ancla encima del mapa, con escala y espacio reservados para evitar superposiciones.

El coche actual es un Escort RS2000; no confundirlo con el RS1600 de los perfiles históricos. Esta parrilla será una modalidad inspirada en 1974 sobre los escenarios disponibles, no una reconstrucción documental de una inscripción real en Rusia.

## Datos de entrada

`historical_source_1974.txt` conserva el texto suministrado. `historical_profiles_1974.json` estructura 23 pilotos, 18 referencias de vehículos, equipos, ocho sistemas mecánicos y factores de contexto. Las puntuaciones de los diez pilotos de la tabla se mantienen; los otros trece tienen `ratings: null` para no inventar precisión. Antes de habilitarlos se requiere un perfil de diseño explícito y marcado como estimado.

Las asociaciones piloto/coche son candidatas; un archivo de inscripciones debe elegir una combinación por participante y evento. El equipo, soporte, coche y neumáticos pertenecen a esa inscripción, no permanentemente al piloto. Las versiones de coche o nombres ambiguos necesitan resolución antes de activarse.

Separar los futuros archivos activos en `game/data/competition/`, evitando mezclar esta función con perfiles físicos heredados:

| Archivo | Contenido |
|---|---|
| `historical_profiles_1974.json` | Perfiles históricos revisados y procedencia |
| `simulation_balance.json` | Coeficientes de diseño, dificultad, adaptación, tasas y severidades |
| `entries_1974_inspired.json` | Piloto, vehículo, equipo y soporte por inscripción |
| `stages/russia_stage1.json` | Sectores, distancias, superficie, rugosidad, saltos, agua y descensos |
| `rally_rules.json` | Orden de salida, enlaces, asistencia, penalizaciones, clasificación y desempates |

No hay tasas de avería verificadas en el texto. Dejar MTBF y tasas por kilómetro sin valor hasta su calibración; un abandono citado no permite calcular una probabilidad. El 60%, el multiplicador x3 y los 1–2 s/km se conservan como afirmaciones sin verificar, sin convertirlos automáticamente en reglas. La fuente también presenta una contradicción en los resultados Fiat de Portugal. Una revisión documental es una fase posterior, separada del diseño.

## Modelo de ritmo adaptable

1. Dividir inicialmente cada especial en 3–5 sectores usando puntos válidos de la ruta. Cada sector tendrá dificultad y características; no un tiempo fijo obligatorio.
2. Construir una referencia inicial con una pasada válida del jugador o una estimación por longitud y dificultad. Guardar origen y confianza. Para la primera partida sin referencia, usar una estimación provisional de velocidad y anunciar clasificación provisional hasta el primer parcial.
3. Medir ritmo limpio del jugador por sector. Excluir pausas y menús; filtrar paradas, rescates y pérdidas extraordinarias para que un accidente del jugador no ralentice artificialmente a todos. El tiempo oficial sí conserva esas pérdidas. Sin telemetría suficiente, reutilizar la referencia anterior con menor confianza.
4. Ajustar suavemente el nivel común de la parrilla hacia ese ritmo limpio. Como hipótesis inicial: actualización EWMA de 0,2 y límite del 2% por sector futuro. Son parámetros de diseño por calibrar, no datos históricos. Normalizar diferencias de dificultad entre sectores antes de comparar ritmo por kilómetro.
5. Sobre esa referencia aplicar habilidad, afinidad de superficie, coche, clima, fatiga, estrategia y forma del día. Una forma común al tramo y pequeñas variaciones correlacionadas entre sectores evitan resultados aleatorios incoherentes.
6. Los candidatos fuertes tendrán una distribución de rendimiento cercana al jugador, con posibilidad de vencerlo o perder por poco. No todos se mantienen cerca: los perfiles débiles, los daños y las especialidades deben producir diferencias reales.

Una expresión implementable:

`tiempo_sector = referencia_adaptada_sector × exp(efecto_piloto + efecto_coche + efecto_contexto + efecto_forma + efecto_daño) + pérdidas_por_incidentes`

Los efectos positivos aumentan el tiempo; mayor habilidad debe reducir su efecto. Coeficientes y límites se definen en balance y se comprueban con simulaciones. La remontada cambia estrategia y riesgo dentro de límites; no resta segundos de forma gratuita. La gestión reduce desgaste; la agresividad decide cuánto atacar; la probabilidad de error se calcula aparte con habilidad, terreno, fatiga y visibilidad.

**Regla de coherencia:** adaptar únicamente sectores todavía no simulados ni publicados. Al cruzar el jugador un parcial, actualizar el nivel con su ritmo limpio, simular una sola vez ese sector de los rivales y publicar el resultado. Los siguientes sectores permanecen pendientes. El total final es la suma de los parciales comprometidos; nunca se reconstruye para fabricar un final ajustado.

Esta primera versión ofrece comparación virtual al mismo punto de recorrido, independiente del orden de salida real. No pretende que todos los coches estén cruzando físicamente ese parcial al mismo instante. Una futura simulación de horarios podrá adelantar rivales, pero sus tiempos comprometidos tampoco podrán adaptarse retroactivamente.

## Fiabilidad, incidentes y persistencia

Cada coche conserva salud de motor, transmisión, suspensión, dirección, frenos, neumáticos, electricidad y estructura. Guardar también fatiga del piloto, daños activos, reparaciones y penalizaciones.

Antes de la especial: aplicar desgaste arrastrado, preparación y asistencia permitida. Resolver averías previas una sola vez. Una avería reparable puede implicar reparación y retraso; una no resuelta impide salir. En primera especial con coche preparado, un DNS será raro y derivado de una tasa específica de preparación, no de repetir la probabilidad de abandono del tramo.

Durante el sector: acumular exposición por kilómetros, rugosidad, saltos, agua, carga térmica y ritmo. Para un riesgo por distancia usar `p = 1 - exp(-lambda_efectiva × km)`; modelar riesgos térmicos o eléctricos por tiempo cuando corresponda. No sortear averías por frame. Las tasas son valores de diseño y no se derivan directamente de una puntuación de habilidad.

Separar aparición, severidad y consecuencia: un pinchazo añade parada y puede permitir continuar; una pérdida de potencia ralentiza sectores posteriores; un palier puede impedir continuar; una salida puede ser recuperable o terminal. Si una avería ocurre dentro del sector, aplicar su pérdida desde la distancia del suceso y cortar la simulación allí cuando sea terminal. Evitar cobrar la misma pérdida como daño, parada y penalización duplicadas.

Después: consolidar resultado y daños, comprobar enlaces y controles horarios cuando estén habilitados, y resolver asistencia según presupuesto, tiempo y capacidad del equipo. No restaurar salud automáticamente al cambiar de tramo. Un abandono excluye de las siguientes especiales salvo que las reglas activen explícitamente reincorporación; por defecto no habrá esa regla.

## Estados y clasificación

Separar `start_status` (pending/started/dns), `stage_status` (pending/running/finished/dnf), `rally_status` (active/retired/excluded) y `condition` (healthy/damaged). Guardar causas con código, componente, severidad, sector, distancia y pérdida en milisegundos. Así «Completado — amortiguador roto» no equivale a abandono.

El coche que termina una especial y se retira después en el enlace conserva su tiempo de especial y muestra su retirada del rally. Un DNS en una especial posterior tampoco borra resultados previos.

Guardar tiempos como enteros en milisegundos. `stage_elapsed_ms` contiene conducción y demoras en el tramo; las penalizaciones se registran aparte, con ámbito y sin doble conteo. `rally_total_ms` suma tiempos válidos y penalizaciones aplicables. Un DNF/DNS no recibe un tiempo final inventado: usar `null` y mostrar «—»; conservar su último parcial y acumulado anterior como historial, no como total clasificable.

Clasificaciones separadas: especial por tiempo de especial y penalizaciones de esa especial; general por acumulado entre participantes elegibles. Por defecto, retirados y no salidos aparecen al final con posición «—». En empates exactos, aplicar regla declarada de primera especial que desempate; si persiste, empate deportivo y orden visual estable por ID.

## HUD y resultados

Encima del mapa: panel compacto con «GENERAL · Parcial 2/4» y posibilidad de alternar a «TRAMO». Mostrar líder, rivales cercanos y jugador resaltado; máximo cinco filas. Cada comparación usa el mismo parcial. Antes del primer parcial: «Sin parcial». Entre parciales mantener el último delta confirmado; si se añade una predicción continua, distinguirla como estimada.

`delta = tiempo_jugador_al_parcial - tiempo_referencia_al_mismo_parcial`: positivo significa que el jugador va detrás; negativo, delante. En general añadir acumulado previo y penalizaciones conocidas. Indicar claramente referencia al líder o al rival seleccionado. Los abandonos se excluyen de las posiciones activas sin eliminar su registro.

Al finalizar cada especial y al cerrar una etapa, presentar la tabla sencilla pedida; el cierre de etapa puede reutilizarla con la última especial y el acumulado actualizado:

| Posición | Piloto | Coche - equipo | Tiempo del stage | Tiempo acumulado | Estado |
|---|---|---|---|---|---|
| 1 | Jugador | Escort RS2000 - Privado | 04:12.350 | 12:31.800 | Completado |
| 2 | Sandro Munari | Stratos HF - Lancia | 04:13.100 | 12:33.200 | Completado — pérdida de potencia |
| — | Markku Alén | 124 Abarth - Fiat | — | — | Abandono — palier roto, sector 3 |
| — | Roger Clark | Escort RS1600 - Ford | — | — | No tomó la salida — fallo de encendido |

Ejemplo ilustrativo, no resultado histórico. En vista general, Posición significa general; en vista tramo, significa especial. Mantener las seis columnas sin añadir complejidad a la presentación; una fila expandible opcional puede explicar penalizaciones y eventos.

## Arquitectura propuesta

- `RallyCompetitionCatalog`: carga y valida perfiles, entradas y balance. Rechaza IDs inválidos, puntuaciones fuera de rango y parámetros sin calibrar en entradas activas.
- `RallyPaceModel`: estimación del jugador, confianza y ritmo por sector.
- `RallyReliabilityModel`: desgaste, fallos y consecuencias.
- `RallyCompetitionSimulation`: coordina fases, eventos y compromiso de parciales; sin dependencias de nodos físicos.
- `RallyClassification`: calcula resultados de especial y general.
- `RallyCompetitionStore`: guarda versión, semilla, estados RNG, parciales, eventos, daños y acumulados en `user://` mediante escritura temporal y sustitución segura.
- Adaptador en la sesión: publica `competition` y señales de salida, parcial, final y reinicio.
- Panel HUD y pantalla de resultados: consumen snapshots; no sortean resultados ni ejecutan reglas deportivas.

Usar flujos RNG independientes por inscripción, tramo y subsistema con derivación estable de semilla. Añadir un rival no debe cambiar los incidentes de los existentes. Guardar versiones de datos y algoritmo para que una partida se pueda reproducir.

Reinicio: en práctica rehacer intento desde la misma instantánea inicial y semilla; no permitir reroll de DNS o daños cada vez que se pulsa R. En competición, un rescate se resuelve con la regla de penalización y no resetea el rally. Definir este comportamiento antes de conectar el reinicio actual basado en `session_generation`.

## Secuencia de implementación y aceptación

1. **Contrato de datos y balance:** validar JSON, resolver perfiles incompletos e inscripciones, definir reglas y metadatos de sectores. Aceptación: parrilla sin referencias rotas; valores históricos y estimados identificables.
2. **Motor puro por sectores:** ritmo adaptable, RNG reproducible, tiempos comprometidos y clasificación. Aceptación: misma semilla y mismas entradas producen los mismos resultados; ningún parcial cambia después de publicarse.
3. **Resistencia:** preparación, DNS, desgaste, fallos leves/terminales y asistencia. Aceptación: completar dañado, abandonar o no salir produce resultados distintos y persiste al siguiente tramo.
4. **Integración del tramo actual:** señales de checkpoints, tiempos interpolados al cruce cuando sea posible y finalización una sola vez. Detectar cruces entre frames para no depender solo de estar dentro del radio a alta velocidad. Mantener protección contra atajos. Aceptación: parciales estrictamente crecientes, pausa sin avance y reinicio coherente.
5. **Presentación:** tabla encima del mapa, delta confirmado, tabla final de seis columnas. Aceptación visual en 1280×720, 1920×1080 y formato ultrapanorámico, nombres largos, muchos abandonos y distintas escalas.
6. **Rally de varias especiales:** persistencia, acumulados, enlaces y servicio. Aceptación: guardar/cargar conserva todos los parciales y no duplica penalizaciones ni eventos.
7. **Calibración:** ejecutar lotes de miles de rallies por superficie, longitud y dificultad; medir margen al jugador, dispersión, retiradas por sistema y efecto de la gestión. Hacer luego pruebas jugadas para evaluar justicia y legibilidad. Las comprobaciones automáticas no sustituyen esa aceptación.

Casos esenciales: jugador muy rápido/lento; parada larga sin arrastrar el ritmo rival; accidente en último sector; todos los rivales retirados; DNS en segunda especial; daño leve al cruzar meta; retirada en enlace tras completar; empate; guardar justo tras parcial; cambio de FPS; reinicio repetido; perfil histórico incompleto.

Primera entrega jugable recomendada: Rusia, 3–5 sectores, un subconjunto de pilotos con puntuaciones completas y coches virtuales, ritmo adaptable, DNS/DNF/daño leve, tabla sobre mapa y resultados. La persistencia de rally y asistencia se incorpora a continuación. Los coches virtuales requieren perfiles numéricos de simulación, pero no modelos 3D ni nuevas físicas.
