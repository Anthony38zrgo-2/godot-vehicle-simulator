# Plan de clima por zonas y neumáticos — 2026-11-02

Estado: diseño para la siguiente iteración; no cambia el runtime actual.

## Resultado previsto

Al iniciar el juego se muestra el reglaje en la pestaña Neumáticos. El jugador elige entre grava normal y lluvia, ajusta presiones y pulsa Aceptar para iniciar el rally. Antes de arrancar se genera una sola vez el clima de sus diez especiales y se guarda en el cronograma. Tras Stage 5 reaparece el reglaje antes de Stage 6. La cuenta atrás, el reloj ambiental y el coche permanecen detenidos mientras se elige.

Cada especial tiene exactamente tres zonas equitativas por distancia recorrida, delimitadas por nodos de su ruta: dos cambios efectivos de clima. Las condiciones evolucionan gradualmente y afectan temperatura de superficie, agua, nieve y agarre en cada contacto de rueda. El pronóstico puede orientar la elección, pero la secuencia exacta generada permanece oculta al jugador.

## Base existente y cambios necesarios

- El calendario vive en `game/data/competition/events/russia_rally.json`; `rally_event_manager.gd` genera el itinerario y guarda resultados/semilla. Ampliar estos datos y su versión de guardado.
- `rally_russia_stage_session.gd` conecta Sky3D y TCA. Actualmente hay una temporada de clima global, no un itinerario espacial completo. Desactivar la selección aleatoria autónoma de TCA al usar el calendario.
- `rally_terrain_wetness.gd` modifica materiales. Su humedad todavía no gobierna la fricción: debe convertirse en un consumidor del estado físico compartido.
- `tire_model.gd` usa superficies y factores térmicos; `thermal_model.gd` utiliza temperaturas ambientales/de suelo de respaldo. Introducir condiciones locales por contacto, sin sustituir la identidad Gravel/Dirt/Road por una única superficie.
- `rally_garage_panel.gd` ya permite reglajes, presiones y servicio de neumáticos; abre en página 0 y pausa el juego. Extenderlo con selección de compuesto y apertura obligatoria antes de la cuenta atrás. La vista previa del menú no debe llamar a un inicio que escriba el guardado oficial.
- El reinicio entre especiales ya precalienta frenos/neumáticos. Adaptarlo a los objetivos térmicos del compuesto elegido; no conservar los 50/60 °C fijos para ambos.

## Catálogo y transiciones

Orden configurable de seis estados:

| Índice | ID | Presentación |
| --- | --- | --- |
| 0 | clear | Despejado; cielo abierto, baja nubosidad y menor irradiancia que Sunny |
| 1 | sunny | Soleado; mayor irradiancia efectiva |
| 2 | cloudy | Nublado |
| 3 | light_precipitation | Precipitación ligera |
| 4 | medium_precipitation | Precipitación media |
| 5 | heavy_precipitation | Precipitación intensa |

La irradiancia también depende de hora solar; Sunny de noche no crea luz solar. Despejado y Soleado comparten poca nubosidad pero son presets distintos, con rangos solapados para evitar cambios exagerados.

Dentro de un stage: siguiente índice = actual ±1; nunca 0 de diferencia. En extremos solo existe una salida válida. En estados interiores sortear avance o retroceso con pesos definidos en JSON. Son válidos Nublado → Soleado → Despejado → Soleado y Ligera → Nublado → Ligera → Media.

Entre stages: diferencia permitida de ±1 o ±2, sin permanecer igual. Con la lista anterior Soleado → Nublado es +1; Despejado → Nublado es +2. Ambos cumplen la intención del ejemplo. No forzar saltos de dos posiciones: Intensa → Media debe seguir siendo posible.

Cada preset contiene rangos y curvas de nubosidad, irradiancia, temperatura del aire, precipitación, niebla y viento, con unidades explícitas. Sortear sus valores al generar el calendario, no cada frame. Los pesos dependen del lugar/estación y pueden favorecer una evolución sin eliminar las restricciones de vecindad. Rechazar configuraciones sin una transición válida, sin sustituirlas por otro clima.

## Generación y cronograma JSON

El JSON de definición de evento incorpora `weather_rules`, catálogo de presets, política regional, `surface_profiles`, referencias a dos compuestos y ventanas de reglaje. Los números de nodos, límites de transición, curvas de grip y coeficientes térmicos son datos; el código solo ejecuta algoritmos genéricos.

Flujo: cargar/validar definición y rutas → recoger elección de neumáticos → Aceptar → generar el itinerario climático de todo el rally → guardar atómicamente → cargar primera especial → aplicar condiciones iniciales → habilitar cuenta atrás.

Usar una semilla climática derivada de la semilla del rally y un identificador de propósito independiente de la IA. Un rally nuevo sortea una semilla nueva, registrada en el guardado; fijar semilla sigue disponible para reproducir fallos. Reanudar o reabrir el reglaje no vuelve a sortear. Guardar los valores resueltos, además de semilla, versión del generador y hash de reglas/rutas: la semilla sola no protege de cambios de algoritmo.

Propuesta de bloque de configuración, integrado en el calendario existente:

```json
{
  "weather_rules": {
    "generator_version": 1,
    "seed_policy": "new_event_random_persisted",
    "ordered_states": ["clear", "sunny", "cloudy", "light_precipitation", "medium_precipitation", "heavy_precipitation"],
    "within_stage_allowed_steps": [-1, 1],
    "between_stages_allowed_steps": [-2, -1, 1, 2],
    "zones": {
      "count": 3,
      "placement": "equal_route_distance_thirds",
      "boundary_distance_fractions": [0.0, 0.3333333333333333, 0.6666666666666666, 1.0],
      "minimum_length_m": 250.0,
      "blend_fraction_of_zone": 0.25,
      "maximum_blend_distance_m": 150.0
    },
    "preset_catalog_path": "res://data/weather/rally_weather_presets.json",
    "regional_profile_id": "russia_summer"
  },
  "tire_rules": {
    "compound_catalog_path": "res://data/tires/rally_compounds.json",
    "allowed_compound_ids": ["gravel_normal", "gravel_wet"],
    "default_compound_id": "gravel_normal",
    "fitment": "same_compound_all_wheels",
    "start_temperature_policy": "selected_compound_optimum"
  },
  "setup_windows": [
    {"before_stage_id": "russia_stage1", "initial_tab": "tires", "confirmation_required": true},
    {"after_stage_id": "russia_stage5", "before_stage_id": "russia_stage6", "initial_tab": "tires", "confirmation_required": true}
  ]
}
```

Los valores son candidatos de diseño, pendientes de calibración; estos bloques no deben añadirse al JSON activo hasta que exista el consumidor. Las referencias de catálogo se crearán en implementación.

Cada entrada del cronograma generado guarda `stage_id`, fecha/hora, hash de ruta, perfil regional, compuesto montado, condiciones iniciales por zona y lista de zonas: `start_node`, `end_node_exclusive`, distancias derivadas, `weather_state_id`, valores climáticos resueltos y longitud de mezcla. Primera zona comienza en 0; la última incluye el final; no hay huecos ni solapamientos de propiedad. Las franjas de mezcla son una interpolación de condiciones, no otra zona.

Dividir la longitud total de la ruta en tres tercios iguales: límites al 0 %, 33⅓ %, 66⅔ % y 100 %. Ajustar los dos límites interiores a los nodos existentes más próximos por distancia acumulada, sin desplazamiento aleatorio; la única desigualdad admisible es la discretización de esos nodos. No dividir por cantidad de nodos, porque su separación puede ser irregular. Requerir exactamente tres zonas y dos cambios. Si una ruta no admite el mínimo de longitud configurado o los límites caen en el mismo nodo, informar incompatibilidad; no modificar silenciosamente el número de zonas. Las ventanas de reglaje referencian IDs del cronograma y se validan contra su orden.

## Ejecución espacial

Crear un controlador de clima del evento que lea el cronograma ya generado y un modelo de superficie por zona. La posición proyectada sobre la ruta identifica la zona: no usar el tiempo deportivo ni depender de haber atravesado todas las puertas de pacenotes. La búsqueda debe tolerar salida de carretera, rescate y reincorporación. Usar continuidad de segmento para distinguir curvas cercanas y puentes, incluyendo altura.

Mezclar los valores del estado anterior al nuevo a lo largo de una franja de distancia alrededor del límite, con smoothstep. Al quedarse parado no oscila el estado objetivo. Al retroceder se consulta la posición real, sin volver a sortear ni rebobinar agua, temperatura o nieve. Suavizar visualmente teletransportes/rescates para no provocar un salto brusco de cielo; los contactos consultan inmediatamente la zona correcta.

Sky3D y TCA son adaptadores visuales/sonoros; no generan una segunda secuencia. Un único proveedor físico alimenta materiales, precipitación, termodinámica y fricción. Representar la humedad por zona: no oscurecer de golpe todos los materiales de todo el mapa. Usar máscara espacial o parámetros por instancia de chunk sin modificar materiales compartidos entre zonas. Puede haber un cielo local dominante, sin exigir múltiples cielos simultáneos.

## Temperatura y humedad de la superficie

Usar el término temperatura de superficie: Rusia es mayoritariamente grava/tierra, aunque el sistema admite asfalto. Cada superficie define absorción solar, capacidad térmica, intercambio con aire/agua, drenaje, evaporación y respuesta al agua/nieve.

Estado local: temperatura del aire y suelo en °C, agua superficial en mm, saturación del suelo, nieve acumulada en mm equivalentes de agua y nieve efectiva sobre el contacto. Humedad relativa del aire es otro dato; no equivale a carretera mojada.

La temperatura evoluciona por balance de energía: aporte solar menos intercambio con aire, lluvia/nieve y evaporación. El agua aumenta por precipitación/deshielo y disminuye por drenaje/evaporación. Nublado después de lluvia deja el piso mojado; Soleado no lo seca instantáneamente. Inicializar cada zona con condiciones antecedentes sorteadas/configuradas para no esperar varios minutos a que exista agua. Evolucionar todas las zonas según el reloj ambiental común, incluyendo las no visitadas, mediante pasos físicos acotados independientes del FPS.

Durante pausas/reglaje/carga no avanzar el estado. Los saltos de horario entre stages actualizan los antecedentes de la siguiente especial con integración acotada o solución estable; no simular dos horas con un único dt.

**Continuidad entre stages:** el clima visible y el estado del suelo son variables distintas. La siguiente especial puede empezar nublada con carretera mojada por lluvia anterior; también puede empezar con precipitación ligera sobre una carretera todavía seca o apenas húmeda, que se moja progresivamente. Entre especiales la superficie puede conservar su condición, empeorar o mejorar según el tiempo ambiental transcurrido, los antecedentes meteorológicos y el drenaje/secado de cada zona. Cambiar de stage no reinicia automáticamente humedad, saturación, nieve ni temperatura a un valor dictado por el clima de salida.

Las rutas distintas mantienen estados locales propios, vinculados mediante un contexto meteorológico regional compartido. No copiar literalmente la última zona del stage anterior sobre todas las zonas del nuevo. El generador debe resolver antecedentes regionales para el intervalo entre especiales y usarlos para evolucionar las condiciones iniciales de cada zona de la siguiente ruta. Persistir esos antecedentes y sus resultados; reanudar no los vuelve a sortear. Si dos especiales reutilizan un mismo tramo físico, una referencia de superficie compartida permite conservar su estado real sin duplicarlo. La relación regional o de tramo compartido debe declararse en JSON.

Añadir al cronograma `surface_continuity` con política de antecedentes, perfil regional, referencias de superficie compartida si existen y coeficientes de evolución definidos por perfil. Cada especial resuelta registra por zona agua, saturación, nieve y temperatura iniciales, hora de referencia y antecedentes que las produjeron. Las etiquetas conservar/mejorar/empeorar son resultados derivados y pueden diferir por variable: una carretera puede secarse mientras se enfría. No asignarlas al azar como sustituto del balance físico ni obligar a que el grip evolucione siempre en la misma dirección.

## Temperatura de superficie en el minimapa

Mostrar junto al minimapa una lectura explícita «Superficie: 18 °C», diferenciada de la temperatura del aire y de los neumáticos. Consultar el mismo proveedor local que alimenta los contactos y el grip; no deducirla del icono de clima. Usar la temperatura de la zona correspondiente a la proyección actual del coche sobre la ruta, con la misma interpolación espacial en límites de zona. Al salir de carretera, mantener esa referencia proyectada; al rescatar o cambiar de stage actualizarla al punto de reincorporación o salida.

La configuración de HUD en JSON define visibilidad, unidad, precisión y frecuencia de actualización de esta lectura. Mostrar «—» si no existe un dato válido, evitando presentar cero como temperatura real. La temperatura indicada es la del corredor de ruta del minimapa; si una rueda pisa una superficie lateral distinta, la física puede usar su condición local específica. El indicador no revela las condiciones futuras de zonas aún no recorridas.

El tipo de precipitación depende de perfil regional, altura y temperatura local, con umbrales/histéresis configurables. El perfil inicial de Rusia veraniega favorece lluvia; perfiles fríos permiten nieve. Sin hielo ni neumático de clavos en esta iteración: la nieve ligera/moderada sí debe afectar grip y enfriamiento, con la limitación de que los dos neumáticos disponibles no representan un equipo especializado de nieve.

## Dos compuestos y grip

`gravel_normal`: buen rendimiento en grava seca, mayor sensibilidad al agua, mayor pérdida de calor por agua y menor ventana térmica útil bajo lluvia. `gravel_wet`: mejor respuesta sobre grava mojada, trabaja a temperaturas más bajas y acumula más calor en seco por deformación del dibujo, con degradación de grip por sobretemperatura.

No imponer «llueve = neumático frío» o «sol = neumático caliente». Es un balance: temperatura del suelo/aire, agua del contacto, potencia por deslizamiento, velocidad y compuesto. El normal debe tender a enfriarse en la prueba mojada prevista; el de lluvia debe tender a sobrecalentarse en una prueba seca sostenida. Ambos pueden calentarse bajo derrape intenso. El agua residual enfría aunque haya dejado de llover.

Catálogo por compuesto: objetivos/ventanas térmicas de banda y carcasa, capacidad térmica, generación por deformación/deslizamiento, intercambio con agua/aire/suelo, curvas de fricción según temperatura de superficie, agua y nieve, desgaste y presión. Mantener neumático de lluvia apto para grava; no introducir un neumático de asfalto bajo ese nombre.

Por contacto de rueda: resolver material real y condiciones de zona → respuesta de compuesto/agua/nieve/temperatura del suelo → combinar una sola vez con la curva base de superficie y el factor térmico del neumático. Aplicar a fuerzas longitudinales y laterales, conservando límites combinados de adherencia. Evitar duplicar la reducción mojada en varios niveles. El modelo térmico recibe exactamente esas mismas condiciones locales.

Los objetivos iniciales son específicos del compuesto y se aplican tras montar neumáticos al inicio de cada stage, en línea con el reinicio ya solicitado. No sostenerlos artificialmente durante la conducción. El rescate con R conserva temperatura, compuesto y desgaste; no regala neumáticos nuevos. Los reglajes de presión se conservan y el cálculo de presión usa temperatura de gas coherente.

## Pantalla inicial y servicio intermedio

Integrar el inicio real de la sesión con el reglaje: no basta con construir un menú que ninguna escena llama. Mostrar Neumáticos primero al iniciar un rally nuevo, con dos opciones, sus ventajas, presiones y pronóstico resumido de la próxima mitad del rally. La selección es un borrador hasta Aceptar; no lanzar cuenta atrás, consumir combustible ni comenzar el cronómetro antes de confirmar.

Después de Stage 5: Resultados → Continuar al servicio → Reglaje en Neumáticos → Aceptar → cargar/iniciar Stage 6. El cambio de compuesto solo está habilitado en las ventanas definidas por JSON. El reglaje general permitido en otras pantallas sigue sus propias restricciones. El reenganche tras abandonar Stage 5 también pasa por el servicio; no se lo salta.

Al reanudar un rally en curso, no forzar una nueva elección fuera de servicio ni regenerar clima. Si se cerró durante una ventana, restaurar la ventana pendiente. Guardar compuesto confirmado, valores de reglaje y estado de confirmación para no duplicar cambios ni servicio con un doble clic.

## Persistencia y rivales

Versionar definición, catálogos y guardado. Persistir calendario climático completo, estados físicos de zonas, progreso de transición, selección de neumáticos y ventanas atendidas. Los archivos antiguos sin clima/compuesto requieren una migración explícita o inicio de un evento nuevo con aviso; nunca alterar silenciosamente una prueba oficial ya empezada.

Los rivales simulados deben recibir factores de superficie/clima y decisiones de compuesto coherentes por sector, sin multiplicar pérdidas ya incorporadas en tiempos CPU mojados. Registrar si la referencia es seca o mojada y calibrar contra ella. No necesitan cuatro contactos físicos, pero sí el mismo calendario y reglas de compuesto; sus decisiones se generan con otra corriente de semilla.

## Entregas y aceptación

1. **Esquema y generador:** catálogos, restricciones, rutas y cronograma resuelto. Probar miles de semillas: diez stages, exactamente tres zonas equitativas por distancia y dos cambios por stage, límites interiores en los nodos más próximos a los tercios de ruta, ningún vecino repetido, pasos internos ±1 y externos ±1/±2, cobertura completa de nodos. Semilla/reglas iguales producen el mismo resultado; reabrir o aceptar dos veces no lo cambia.
2. **Controlador climático:** cielo/precipitación/sonido con fuente única, mezcla por distancia y correcta recuperación al retroceder/rescatar. Verificar día/noche y variantes de lluvia/nieve regional.
3. **Modelo local de superficie:** continuidad de agua, temperatura y nieve; secado gradual y estabilidad a distintos dt. Verificar que una zona no visitada también evoluciona y que una pausa no lo hace.
4. **Compuestos y física:** conectar condiciones de cada contacto al grip y al modelo térmico. Pruebas controladas con misma carga/velocidad: normal se enfría en mojado respecto a seco; lluvia acumula calor y pierde grip en seco respecto a mojado; temperatura del suelo altera transferencia térmica y grip. Frenado/aceleración/curva respetan la curva combinada, sin aplicar dos veces la humedad.
5. **Reglaje y evento:** apertura inicial y servicio Stage 5→6, Aceptar inicia la salida, bloqueo fuera de ventana, reinicios correctos por compuesto y rescate sin servicio térmico. Reanudar conserva clima, compuesto, tiempo oficial y ventana pendiente.
6. **Validación integrada:** recorrido de diez especiales, rivales y puntos sin regresión; conducción/listening/inspección visual de transiciones. Probar continuidad entre stages con Nublado/mojado, precipitación ligera/seco inicial y antecedentes que conserven, sequen o mojen más la siguiente ruta; comprobar que pausa/reanudación no cambian los resultados. Validar temperatura de superficie en minimapa frente al proveedor físico en las tres zonas, sus límites, salida de carretera, rescate y cambio de especial, incluyendo ausencia de datos. Revisar coste del modelo local y asegurar que la generación del calendario ocurre una vez, no durante cada callback de física.

La aceptación visual y de conducción debe confirmar que los dos cambios por stage resultan distinguibles pero graduales, y que la diferencia entre compuestos se siente sin forzar comportamientos térmicos instantáneos.
