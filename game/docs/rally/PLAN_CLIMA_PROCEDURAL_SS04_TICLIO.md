# Caminos del Inca · Orden de salida y clima precalculado en cinco sectores

## Objetivo

El orden deportivo determina la hora de largada del jugador. Esa hora determina el clima que encuentra y cuánto agua, nieve o hielo quedó en la calzada antes de su salida. SS04 Ticlio es el tramo piloto. El orden de salida se aplica a todo el rally de Caminos del Inca, y el modelo de cinco sectores queda disponible para otros tramos mediante configuración.

El modo procedural actual de Ticlio calcula 26 nodos atmosféricos y 125 muestras de superficie. Avanza el balance de la carretera durante la pasada. Este plan lo sustituye, para el modo nuevo, por **cinco sectores atmosféricos** y una **instantánea de la calzada precalculada en Rust**. Durante la especial, cambia el clima visible al avanzar por la ruta. Los depósitos y el llenado de los charcos se conservan para toda esa pasada. La IA ocupa puestos en la lista de salida y conserva su cálculo actual de tiempos.

## 1. Orden de salida de Caminos del Inca

### Reglas deportivas

| Momento | Orden |
| --- | --- |
| **SS01** | Clasificación vigente del campeonato, con el líder primero. Si aún no existe clasificación aplicable a los inscritos, sortear la lista una sola vez. Si solo algunos inscritos tienen clasificación, salen primero en orden de campeonato y luego se sortean los demás. |
| **SS02 y siguientes** | Clasificación oficial **acumulada del rally** al cierre de la especial anterior, con el líder primero. Usar los tiempos oficiales, penalizaciones y desempates de la clasificación existente. |

La lista contiene los competidores habilitados para tomar la salida. El auto cero queda fuera del cómputo. Para retirados o reincorporados, usar su elegibilidad deportiva antes de asignar puestos; si un participante habilitado carece de puesto acumulado, ubicarlo después de los clasificados conservando su orden relativo anterior. El sorteo inicial usa un flujo determinista separado del meteorológico y se guarda con el evento.

### Integración con el itinerario

1. En el [perfil del evento CDI](../../data/competition/events/cdi_rally.json), declarar las reglas de la tabla y un intervalo de salida en segundos, con posibilidad de sobrescribirlo por especial. El intervalo es un parámetro deportivo de CDI a definir. Usar 60 s en ejemplos y pruebas controladas.
2. En [RallyEventManager](../../scripts/rally/rally_event_manager.gd), resolver SS01 después de tener la lista de inscritos y el itinerario. Para cada SS siguiente, resolver la lista una vez que se hayan contabilizado los resultados oficiales de todos los participantes de la anterior y antes de preparar el tramo siguiente. Reutilizar la clasificación acumulada existente. La lista de la siguiente especial se congela cuando queda publicada.
3. Conservar la hora del itinerario como hora del primer competidor. Calcular la hora efectiva sumando los intervalos de los puestos anteriores. Con intervalo uniforme, `hora_efectiva = hora_base + (puesto - 1) × intervalo_s`. Usar segundos absolutos del evento, con fecha y cambio de día, para que el reloj y el precálculo compartan la misma referencia.
4. Guardar por especial la lista, la hora base, el intervalo aplicado y el puesto y hora efectiva del jugador. Mostrar al jugador su turno y hora en la preparación. La [sesión de rally](../../scripts/rally/rally_russia_stage_session.gd) usa la hora efectiva para iniciar directamente la cuenta atrás. La espera previa es tiempo simulado y no requiere que el jugador espere ni que los rivales conduzcan.
5. Reiniciar o reanudar usa la lista ya guardada. Para guardados anteriores sin listas, resolver las especiales pendientes con los resultados disponibles. Si el jugador ya está dentro de una especial iniciada con el sistema anterior, conservar su referencia temporal hasta que la cierre. En modo individual, sin lista de inscritos, usar la hora configurada de la sesión como hora efectiva.

**Ejemplo.** El itinerario de SS04 marca las 09:40. Si el jugador está octavo en el acumulado al cerrar SS03, su hora efectiva es 09:47 con el intervalo de ejemplo. Si lidera tras SS03, larga a las 09:40.

## 2. Jornada precalculada en cinco sectores

### Entradas locales

- [cdi_ss04_climate.json](../../data/weather/cdi_ss04_climate.json) define parámetros editables por temporada, como temperatura a una cota de referencia, variación diurna, humedad, gradiente térmico, patrones de precipitación y tiempos aproximados de acumulación y secado. Los valores son parámetros de simulación calibrables. Todo se genera sin conexión, con las semillas del evento y los perfiles empaquetados.
- [climate_route_profile.json](../../assets/rally/cdi_stage4/climate_route_profile.json) aporta el perfil del DEM, las cotas absolutas, la pendiente, el rumbo y la correspondencia entre el progreso de carrera y la coordenada de la calzada. Hay que conservar esa correspondencia al cambiar la resolución visual o cargar otro sector de malla.
- El gestor entrega identificador de evento y especial, semilla, estación o fecha, hora base y hora efectiva. La **jornada** se deriva de semilla, especial, perfil, fecha y hora base. El puesto solo selecciona el momento en el que se consulta esa jornada. Cambiar de puesto con la misma semilla mantiene las posiciones y características del frente.

### Modelo atmosférico en Rust

1. Cada ruta configura cinco tramos consecutivos desde largada hasta meta. En Ticlio, tomar como primera aproximación cinco fracciones iguales de los 6,19 km, de unos 1,24 km cada una. Permitir mover los límites desde el perfil para ajustar la transición cerca del abra. Cada sector tiene una muestra de referencia en su centro. Entre centros se interpolan los valores; desde el primer y último centro hasta los extremos se conserva su valor de referencia. Los sectores climáticos son independientes de los sectores de carga de malla.
2. En [procedural_weather.rs](../../../rust/rally_native/src/procedural_weather.rs), generar para cada sector una curva temporal pequeña, compuesta por marcas de inicio, pico y fin de uno o pocos episodios de precipitación. Permitir un episodio previo a la salida de la primera tripulación y un desfase progresivo entre sectores. Cada marca describe nubosidad, humedad, temperatura de referencia e intensidad. Interpolar entre marcas. Reservar una variante seca incluso en la cumbre. Reutilizar [PCG32](../../../rust/rally_native/src/rng.rs) y derivar semillas independientes para jornada, nieve, hielo y reparto de charcos.
3. Ajustar la temperatura con la cota de la ruta en el punto consultado mediante el gradiente configurable. Resolver lluvia, aguanieve y nieve con una transición térmica y de humedad. Aprovechar la función de bulbo húmedo existente si encaja en el núcleo simplificado. La cota modifica la fase de un frente húmedo. Un sector sin precipitación sigue seco aunque esté bajo cero.
4. Evaluar los cinco sectores a la hora efectiva del jugador y guardar sus valores. En carrera, [rally_weather_controller.gd](../../scripts/rally/rally_weather_controller.gd) proyecta el vehículo sobre la ruta, interpola esos valores, aplica el ajuste de cota local y entrega precipitación y nubosidad a los adaptadores existentes. La meteorología visible cambia por posición durante esta primera versión. Las marcas temporales se usan al preparar la pasada. Conservar la selección inicial de lluvia, si existe, como condición meteorológica de inicio del evento o de la sesión individual, separada del cálculo de agua en el suelo.

## 3. Instantánea de la calzada a la hora de largada

### Cálculo único antes de la salida

En cada sector, evaluar la precipitación anterior a la hora efectiva. Integrar los episodios por sus segmentos de tiempo para obtener los aportes aproximados de lluvia y nieve. Estimar el estado inicial con estos aportes, el tiempo desde que dejó de precipitar y la temperatura aproximada del pavimento. Una primera implementación puede resolver el balance en cada intervalo entre marcas y al corte de la largada, con un número acotado de operaciones. No requiere recorrer seis horas a intervalos de cinco segundos.

- **Agua líquida.** Sumar lluvia y deshielo. Aplicar retención y pérdida por drenaje y secado según el perfil de superficie, la pendiente y el tiempo desde el episodio. El agua puede subir mientras llueve y bajar después.
- **Nieve.** Retener una fracción del aporte sólido si la calzada está fría y reducirla con tiempo templado. Mantener nieve residual cuando el cielo ya está nublado o despejado.
- **Hielo.** Convertir parte del agua previa en hielo si hubo enfriamiento suficiente. Restar esa masa del agua líquida. Distinguir cantidad en milímetros de cobertura visible o fracción de huella.
- **Detalle espacial.** Interpolar los valores entre sectores, ajustar la clasificación térmica con la cota local y reutilizar las máscaras de nieve y hielo dependientes de la semilla, la estación y el ancho. El detalle de las máscaras puede mantener una resolución mayor que los cinco sectores. Cuando la cobertura es cero, el shader muestra la calzada base y sus marcas.

### Charcos ya llenos al iniciar

1. Reutilizar la colocación existente de [RallyPuddles](../../scripts/rally/rally_puddles.gd), incluidas sus máscaras, tipos, raycasts y sesgo hacia sitios bajos. Preparar las mallas candidatas y su llenado **antes de habilitar la cuenta atrás**. La lista de candidatos se deriva del tramo y se puede reutilizar con otra hora de salida.
2. Evaluar el agua de cada candidato en la instantánea y aplicar una retención local según su tipo y la topografía disponible. Así, algunos puntos bajos forman charcos mientras la película media de un sector es delgada. Si el historial es seco o el líquido se congeló, el candidato no aparece. El umbral de visibilidad y el nivel de llenado deben producir charcos perceptibles cuando haya acumulación suficiente.
3. Guardar un valor normalizado de llenado por candidato y usarlo para el shader y el muestreo nativo por rueda. Si la profundidad del charco ya incluye la película de agua, usar la mayor de ambas en el contacto para evitar sumarlas dos veces. Conservar el arrastre y la salpicadura asociados al agua líquida.
4. Subir la textura o los parámetros de cobertura una vez por pasada. Los sectores que entren por streaming reutilizan el mismo recurso. En el modo nuevo, la sesión omite el avance de depósitos y el recalculado periódico de llenados. Los reflejos y el aspecto de la precipitación pueden seguir reaccionando al cielo local sin cambiar el nivel de agua.

**Ejemplo.** Si un episodio comienza a las 09:35, quien larga a las 09:40 consulta cinco minutos de lluvia y quien sale a las 09:47 consulta doce. Si el episodio ya terminó y el drenaje domina, la segunda hora puede dar menos charcos. Ambos consultan el mismo episodio y los mismos candidatos. La distinción sale del turno, sin una opción de «lluvia reciente».

## 4. Integración y compatibilidad

- **Responsabilidades.** El gestor del evento resuelve el orden y las horas. El módulo Rust genera la jornada y la instantánea. Godot aplica el reloj, el cielo, la precipitación y los materiales, y conecta el muestreo por rueda. Los resultados de la IA siguen usando su ruta actual.
- **Superficie base.** Ticlio mantiene asfalto como base física y sonora. [El modelo de neumáticos](../../scripts/physics/tire_model.gd) combina las condiciones locales con compuesto y carga. Mantener como referencia provisional un agarre de alrededor del 80 % del seco para una capa fina de nieve en una comparación controlada. La grava y la tierra pueden usar el mismo modelo con sus propios parámetros y materiales.
- **Visuales compartidos.** [El streaming visual](../../scripts/rally/rally_visual_sector_stream.gd) y [el shader de asfalto](../../scripts/rally/cdi_asfalto_estepa.gdshader) se alimentan de la misma instantánea que usa [la física](../../scripts/physics/vehicle_simulation.gd). Mantener el sistema de coordenadas a través de los límites de malla y resolver la proyección de la rueda en horquillas con la referencia de progreso del vehículo.
- **Persistencia.** Guardar versión del generador y perfiles, identificadores, semilla, referencia del evento y hora efectiva. Regenerar la misma instantánea al recargar con esos datos. Mantener identificadores estables para los candidatos de charcos. Versionar el modo del guardado para que una sesión previa conserve el comportamiento con el que se inició.
- **Activación.** Habilitar primero el modo nuevo en SS04. Mantener la configuración climática vigente en tramos que aún no lo adopten. Extenderlo luego por perfiles de ruta y material. Mantener un modo anterior seleccionable durante la comparación de resultados y coste.

## 5. Fases de implementación

| Fase | Entregable |
| --- | --- |
| **A. Orden y reloj** | Configuración deportiva de CDI, asignación de turnos, hora efectiva en la preparación de la especial y persistencia. Validar SS01 con y sin clasificación, y el orden tras cada cierre de especial. |
| **B. Jornada de cinco sectores** | Generador Rust con entradas locales, episodios reproducibles y consulta a la hora efectiva. Integrar cielo y precipitación local en SS04. |
| **C. Calzada fija y charcos** | Instantánea de largada, llenado nativo de candidatos antes de la cuenta atrás y cobertura compartida para el shader y las ruedas. Desactivar el balance continuo para este modo. |
| **D. Calibración y adopción** | Ajustar retención y aspecto de agua, nieve e hielo en SS04. Tras validar en asfalto, adoptar en un tramo de grava usando perfiles y el mismo generador. |

## 6. Validación

- **Orden y tiempo.** Verificar líder del campeonato primero en SS01, sorteo reproducible si falta clasificación y líder del acumulado primero en cada SS posterior. Incluir una penalización que cambie la lista. Comprobar horarios, cambio de fecha y persistencia al reiniciar o reanudar.
- **Misma jornada, distintos turnos.** Con la misma semilla y un episodio controlado, comparar primero y octavo durante acumulación y durante secado. Debe cambiar la instantánea con la hora sin desplazar los candidatos ni regenerar el frente. Con los mismos datos completos, repetir estado idéntico.
- **Charcos y superficie.** Verificar que una jornada húmeda de referencia muestra desde la largada charcos en puntos de retención y que la rueda detecta la profundidad correspondiente. Comparar con asfalto húmedo sin charcos y con una jornada seca. Confirmar que los llenados y la máscara de depósitos permanecen estables durante la pasada y al cruzar sectores de malla.
- **Clima y montaña.** Comprobar transiciones suaves entre los cinco sectores, lluvia más abajo y nieve en zonas altas si las condiciones lo permiten, cielo nublado con nieve residual y una jornada sin nieve incluso en el abra. Comparar la cobertura que se ve con la que recibe cada rueda.
- **Coste y regresión.** Comparar el tiempo de preparación y el trabajo climático durante la especial con el modo procedural vigente. Confirmar que en el modo nuevo se elimina el balance de suelo por pasos y la reconstrucción periódica del campo. Verificar que el cronometraje del jugador y el cálculo de resultados de la IA siguen funcionando con la nueva hora de largada.
