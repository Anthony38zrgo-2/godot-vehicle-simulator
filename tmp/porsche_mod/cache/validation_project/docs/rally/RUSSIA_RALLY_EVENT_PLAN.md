# Plan: rally de Rusia con diez especiales

Estado: propuesta de implementación, 2026-11-02. Este documento no cambia el runtime.

## Objetivo

Disputar Rusia Stage 1–10 como una sola prueba: horario configurable, iluminación coherente, resultados acumulados, continuación tras completar o abandonar una especial y clasificación final con puntos. Mantener disponible la práctica de una especial aislada.

## Estado comprobado

- Existen manifiestos, rutas, pacenotes y configuración de competición para las diez especiales, además de diez respaldos CPU en `data/competition/rally_trophy/`. Su presencia no garantiza que todas hayan sido probadas conduciendo.
- `rally_russia_stage_session.gd` fija Stage 1 en manifiesto, ruta y pacenotes. `continue_competition()` reinicia el coche sin cambiar el escenario.
- `rally_competition.gd` ya simula rivales, sanciones, servicio y acumulados, pero `next_stage()` repite la configuración actual, no limita el rally a diez especiales y rechaza al jugador retirado.
- `rally_competition_panel.gd` tiene resultados y siguiente especial; el título fija Stage 1 y el abandono deshabilita continuar.
- La sesión habilita el reloj propio de Sky3D y configura por separado el tiempo de TCA. Hay que evitar dos autoridades temporales.
- Hay importaciones y modificaciones locales en curso. Implementar sobre ellas sin sobrescribir recursos ni regenerarlos como parte de este trabajo.

## Horarios y reloj

Propuesta inicial de dos jornadas, configurable en el menú previo:

| Jornada | Especiales | Salidas |
| --- | --- | --- |
| Sábado | 1, 2, 3, 4, 5 | 08:00, 10:00, 12:00, 14:00, 16:00 |
| Domingo | 6, 7, 8, 9, 10 | 08:00, 10:00, 12:00, 14:00, 16:00 |

También permitir un único día: 08:00, 10:00… hasta Stage 10 a las 02:00 del día siguiente. La UI debe mostrar el cambio de fecha. La fecha, latitud y estación visual serán datos del evento, independientes del reloj del PC; validar que los recursos de cielo permiten representar el horario elegido.

Separar tres conceptos:

1. Tiempo deportivo: milisegundos de conducción más sanciones; nunca depende de la velocidad del cielo.
2. Hora ambiental: reloj del evento para sol, cielo y clima. Valor inicial 1×: diez minutos reales avanzan diez minutos del mundo. Opciones 0× (hora fija), 1×, 2× y 5×.
3. Itinerario: fecha y hora de salida por especial. Al pulsar continuar se salta a su horario, sin esperar dos horas reales y sin sumar ese enlace al tiempo deportivo.

No modificar `Engine.time_scale`. Pausa, carga y pantallas de resultados detienen el reloj ambiental; la cuenta atrás y conducción lo avanzan según la configuración. Para salir exactamente a las 08:00, iniciar la cuenta atrás unos segundos antes de esa hora.

Crear `RallyEventClock` como autoridad única: desactivar el avance autónomo de Sky3D y sincronizar sus horas y las de TCA mediante adaptadores. Inspeccionar primero el API local de TCA, incluida su evolución meteorológica, para no acelerar involuntariamente lluvia o viento. Aplicar una orientación solar equivalente al entorno de respaldo.

Validar horarios absolutos crecientes y margen suficiente entre salidas. Si una especial sobrepasa la siguiente salida, impedir retroceder el reloj: mostrar conflicto y ofrecer retrasar las salidas restantes conservando sus intervalos. Registrar la revisión del itinerario; no añadir una sanción deportiva automática por este ajuste de juego.

## Configuración y responsabilidades

- `data/competition/events/russia_rally.json`: versión, ID de evento, fecha, lista ordenada explícita de diez IDs, horarios absolutos, servicio, Power Stage, jornada de bonificación, política de abandono y perfil de puntos. No ordenar nombres alfabéticamente: Stage 10 iría antes de Stage 2.
- `RallyEventManager`: estado del evento, selección de especial, resultados oficiales, transición, clasificación y cierre. Mantener `rally_competition.gd` como simulador de la especial actual y separar su adaptación de dificultad de los acumulados oficiales.
- `RallyStageLoader`: resolver manifiesto, visuales, colisión, ruta, puertas, pacenotes y respaldo CPU por ID. Reutilizar una escena de sesión genérica y descargar la especial anterior antes de cargar la siguiente; no mantener diez GLB residentes.
- `RallyEventClock`: fecha/hora y adaptadores ambientales.
- `RallyPointsRules`: cálculo puro y versionado de puntos; sin dependencias de presentación.
- UI: menú de evento/cronograma, resultados de especial/general y resultado final.

Validación previa de las diez dependencias, hashes existentes y coherencia de IDs; ante un recurso ausente mostrar la especial y causa exactas. No sustituir silenciosamente por Stage 1. Cargar la nueva configuración sin perder inscritos, semilla, acumulados ni estado mecánico que deba conservarse.

## Flujo y abandono

`Configuración → Previa → Cuenta atrás → En carrera → Resultados → Carga siguiente → Previa`; después de Stage 10, `Resultado final`.

Separar `completó especial`, `abandono de especial`, `reenganche` y `retiro definitivo del rally`. Propuesta predeterminada para satisfacer la continuación solicitada: reenganche al siguiente stage con penalización configurable. Es una adaptación de juego, no una reproducción completa del reglamento FIA.

- Al abandonar, guardar parciales y motivo, cerrar la simulación de todos los rivales y adjudicar un tiempo sustituto: máximo entre tiempo ya transcurrido y referencia total de la especial, más 300 segundos configurables. Añadir una sola vez las otras sanciones ya incurridas.
- Usar la referencia CPU validada de la especial si no hay finisher válido; documentar su procedencia en el resultado.
- Aplicar la misma política a jugador y CPU. Mantener daño y aplicar solamente el servicio configurado; el reenganche no implica reparación total gratuita.
- Permitir elegir retiro definitivo: puede avanzar como espectador, queda fuera de la clasificación final y recibe cero puntos. Si no hay ningún clasificado, declarar el rally sin ganador.
- Un abandono en Stage 10 permite cerrar el evento y recibir un tiempo adjudicado bajo el modo de juego, pero no puntos de Power Stage. Un perfil estricto puede dejarlo sin clasificación final.
- En modo oficial no permitir reintentar para reemplazar tiempos. La práctica usa una copia de estado sin escribir resultados ni puntos oficiales.

## Acumulados y puntos

Guardar por participante y especial: tiempo medido, tiempo adjudicado si corresponde, sanciones desglosadas, total oficial, estado y elegibilidad. El total general es la suma de totales oficiales de especiales cerradas; mantener valores enteros en milisegundos y nunca sumar penalizaciones dos veces.

Gana el menor total general entre clasificados. Para igualdad: comparar tiempo oficial de Stage 1, luego Stage 2, etc.; si persiste, conservar empate y compartir puntos de esa posición, saltando las posiciones ocupadas. Documentar esto como política del juego y no resolver empates por ID de piloto.

Perfil de referencia WRC 2026:

- General: 25, 17, 15, 12, 10, 8, 6, 4, 2, 1.
- Acumulado del domingo: 5, 4, 3, 2, 1.
- Power Stage: 5, 4, 3, 2, 1.
- Máximo por prueba: 35 puntos. El ganador del rally se determina por tiempo general y puede ser distinto de quien más puntos obtenga.

Propuesta: Stage 6–10 forman la jornada del domingo y Stage 10 es la Power Stage. Las bonificaciones requieren terminar válidamente las especiales de su clasificación y seguir elegible al cierre; los tiempos adjudicados no cuentan como especiales completadas para esos bonos. Esta elegibilidad es una simplificación explícita del juego y debe quedar en el perfil, junto con reenganche y desempates. Si se usa un solo día, desactivar el bono de domingo o configurar expresamente otra agrupación, marcada como personalizada.

Mostrar puntos generales, domingo, Power Stage y total por separado. Conservar un libro de puntos por evento para un futuro campeonato; repetir una carga o abrir resultados no puede volver a otorgarlos. No presentar al ganador de Rusia como campeón mundial.

Referencia oficial consultada: [FIA WRC 2026, reglamento deportivo, artículos 3.3 y 50](https://api.fia.com/system/files/documents/wrc_2026_sr_version_13_january_2026.pdf). Versionar el perfil y revisar elegibilidad reglamentaria si se decide ofrecer un modo de fidelidad FIA completa.

## UI y persistencia

- Antes del rally: elegir dificultad, semilla, jornadas, horario inicial, intervalo, horarios individuales, multiplicador ambiental y política de abandono; vista previa completa del itinerario. Congelar reglas al comenzar para que la competición sea reproducible.
- Previa: «Rusia · Especial 2/10 · Sábado 10:00», distancia, condiciones, clasificación actual y botón de salida.
- Resultados: pestañas especial/general, diferencias con líder, sanciones y estado; mostrar próximo horario y botón «Continuar a Stage N» tras completar o abandonar. Al final de jornada, indicar servicio y nueva fecha.
- Final: ganador o ausencia de clasificados, podio, tiempos, estados, desglose de puntos y acceso al historial de diez especiales. Sustituir el botón siguiente por «Ver resultado final» en Stage 10.
- Guardado nuevo versionado con ID de evento, hash de reglas/itinerario, cursor, reloj, inscritos, semilla, estado mecánico, resultados y registro de puntos. Escribir archivo temporal y reemplazar tras validar. Conservar el guardado v1 como legado, sin inventar resultados de especiales que antes repetían Stage 1.
- Cierre de especial y transición deben ser idempotentes: guardar el resultado una vez con clave evento/participante/especial, preparar siguiente carga y actualizar cursor al confirmar. Si falla la carga, permitir reintentar sin duplicar tiempos ni servicio. Aplicar el mismo criterio al cierre y otorgamiento de puntos.
- Tras cierre de la aplicación durante conducción, proponer reanudar como abandono con reenganche o seguir la política de interrupción definida; no restaurar un coche en coordenadas incompatibles con otra especial.

## Implementación por entregas

1. **Datos y carga genérica.** Validar catálogo 1–10; eliminar rutas fijas de sesión/UI; demostrar que Stage 2 carga sus propios recursos y spawn. Mantener práctica aislada.
2. **Evento y clasificación.** Manager, historial oficial, carga siguiente, finalización en Stage 10, abandono/reenganche y servicio común a CPU/jugador.
3. **Cronograma ambiental.** Reloj único, editor de horarios y sincronización Sky3D/TCA/respaldo. Verificar 08:00 → 10:00 sin espera real y escala 1× durante conducción.
4. **Resultados y puntuación.** Pantallas, ranking general/domingo/Power Stage, elegibilidad, libro de puntos y guardado recuperable.
5. **Validación integrada.** Recorrido sintético completo y revisión visual/conducción en los diez stages antes de dar el modo por terminado.

## Criterios de aceptación

- Secuencia exacta 1–10, sin repetir Stage 1, sin Stage 11 y con recursos/puertas/pacenotes correspondientes en cada carga.
- Caso de cálculo controlado: dos especiales de 180000 y 200000 ms, más 10000 ms de sanción total, producen 390000 ms acumulados.
- Abandono temprano, tardío, consecutivo y final: tiempo adjudicado correcto, continuación disponible y sanciones sumadas una sola vez. Comprobar CPU bajo las mismas reglas.
- Reabrir resultados, doble clic en continuar, fallo de carga y reinicio tras guardar no duplican resultados, reparaciones ni puntos.
- Un ensayo de 600 segundos a 1× avanza 600 segundos ambientales y deportivos durante conducción; pausa/resultados no avanzan ninguno. El salto de enlace cambia únicamente fecha/hora ambiental.
- Domingo y Power Stage usan conjuntos correctos; un ganador de las tres clasificaciones recibe 35 puntos. Probar menos de diez finishers, empates, retiros definitivos y ningún clasificado.
- Reanudar antes/después de cerrar Stage 5 y Stage 10 conserva cursor, fecha, acumulados y puntos. Rechazar guardados incompatibles con mensaje claro.
- Ejecutar contratos de competición y sesión existentes tras adaptarlos. Añadir pruebas puras de acumulación, elegibilidad, reloj y persistencia; verificar aparte iluminación, clima, carga de memoria y UI a distintas resoluciones. Las pruebas automáticas no sustituyen la conducción de cada especial.
