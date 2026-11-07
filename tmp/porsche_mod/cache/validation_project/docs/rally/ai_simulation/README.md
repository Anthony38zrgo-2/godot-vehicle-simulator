# Competición virtual de Rally

Implementación activa en `russia_stage1_ford_escort_rs2000.tscn`. No se instancian coches rivales. El vehículo del jugador conserva sus físicas Jolt.

## Uso

Ejecutar `scripts/run_rally.ps1`. Antes del primer parcial la tabla indica «Sin parcial» y permite consultar participantes y estados de salida. Durante la especial se muestran cinco filas de clasificación general encima del mapa, incluido el jugador y rivales cercanos. El delta positivo indica retraso frente al líder al mismo parcial; permanece confirmado hasta el siguiente control.

«Abandonar especial» simula todos los sectores restantes y abre resultados. Caer fuera del mundo produce abandono por salida de pista. R realiza rescate en el último control validado, conserva reloj y recorrido y añade 30 segundos. El jugador que abandona queda fuera del rally; puede reintentar como práctica o empezar otro rally.

La tabla final tiene posición general, piloto, coche-equipo, tiempo de especial, acumulado y estado. DNF/DNS muestran «—» como tiempo final. Los nombres y estados largos tienen tooltip y la tabla permite desplazamiento. «Siguiente especial — Rusia» conserva acumulados, desgaste y retirados, aplica asistencia limitada y repite el escenario disponible. No implica que se hayan portado otras especiales. «Nuevo rally» limpia el acumulado y cambia la semilla; «Reintentar especial» conserva preparación y semilla.

## Referencia y adaptación

Los diez sectores terminan en los planos originales `split_00` a `split_09`, recuperados de las mallas ocultas del FBX fuente. Los nueve primeros coinciden con los carteles `checkpoint` del GLB; el último corresponde a la meta. El GLB visual agrupa la geometría y omite los triggers invisibles, por lo que el runtime carga sus posiciones, orientación y dimensiones desde `russia_stage1_timing_gates.json`. El cruce hacia delante se barre e interpola entre frames. Los 493 puntos de rescate sirven para proyectar el progreso local y estimar ritmo; perder uno ya no bloquea el cronometraje. La meta queda después del último punto de rescate, de modo que se extiende la ruta en memoria hasta el plano real. Los diez `CPUSplit` originales se asignan a estos diez sectores reales. La escala de tiempos puede calibrarse en `game/data/competition/stages/russia_stage1.json`.

Si no hay información del jugador se utiliza el respaldo original de dificultad intermedia. Antes del primer parcial, al menos diez microsecciones y quince segundos de conducción útil permiten una estimación limitada de ritmo. Las observaciones extraordinariamente lentas/rápidas se descartan para adaptar el nivel, pero siguen contando en el reloj oficial. El primer parcial permite una calibración inicial más amplia cuando hay microsecciones limpias suficientes, para acomodar jugadores alejados del ritmo original. Después se adapta el ritmo por sectores, con límites configurables. El abandono congela esa referencia. Los tiempos publicados nunca se recalculan.

## Datos y simulación

- `game/data/competition/historical_profiles_1974.json`: investigación suministrada, sin presentarla como verificación documental independiente.
- `entries.json`: 23 inscripciones. Trece perfiles sin puntuaciones originales utilizan estimaciones de diseño identificadas explícitamente; las asignaciones ambiguas también están marcadas.
- `simulation_balance.json`: tasas por kilómetro, desgaste, habilidades, clima, visibilidad, especialidad, coche, agresividad, gestión, remontada y asistencia. Sus valores requieren calibración de conducción; no son frecuencias históricas medidas.
- `rally_trophy/trackN_stageM.json`: 50 archivos originales exportados. 42 contienen diez segmentos CPU y 8 no incluyen esa información. Estos últimos se identifican como no disponibles; el cargador rechaza utilizarlos como respaldo CPU. Cada archivo conserva texto INI, valores y hashes SHA-256 del archivo y archivo contenedor.

Regenerar respaldos con `python tools/rally/extract_stage_times.py --game-data "RUTA/Rally Trophy/Data"`. El extractor no modifica los BZF y no intenta reproducir la fórmula desconocida del ejecutable original.

Motor, transmisión, suspensión, dirección, frenos, neumáticos, electricidad y estructura conservan salud. Las probabilidades se calculan sobre exposición por distancia y se distinguen de la severidad. Los incidentes pueden añadir pérdida de tiempo, dejar daños o terminar la participación. Los eventos guardan componente, distancia, sector, severidad y pérdida. La asistencia usa capacidad del equipo y presupuesto temporal limitado; no repara automáticamente todo el coche. Una retirada permanece excluida en las siguientes especiales.

## Guardado

`user://rally_competition_v1.json` conserva preparación, semilla, versión de datos, resultados, incidencias, salud, historial y acumulado. Se escribe a un temporal y se sustituye el destino. La aleatoriedad deriva de inscripción, especial, sector y propósito; cambiar el orden del listado no cambia los sucesos. La iteración de componentes es estable también después de cargar JSON.

Se guarda al comenzar, publicar un parcial, rescatar, finalizar y cerrar normalmente la escena. Si se carga una especial interrumpida después de haber empezado, el jugador aparece retirado y se simula lo restante: no se intenta reanudar su coche con una posición física incompleta. Guardados con otra versión de datos se rechazan. Las pruebas usan archivos separados y no alteran el rally del usuario.

## Comprobaciones

`godot --headless --path game --script res://tests/rally/competition_contract.gd`: 1000 semillas, DNS/daños/DNF, adaptación, congelación de parciales, guardado y continuación reproducible, independencia del orden, tiempos nulos al abandonar, acumulados, estimación previa al parcial y cruces a alta velocidad.

`godot --headless --path game --script res://tests/rally/competition_session_contract.gd`: escena real, señales de botones, controles, resultados de 24 participantes, reintento, meta, siguiente especial, nuevo rally y rescate con penalización.

`godot --path game --rendering-method gl_compatibility --script res://tests/rally/competition_visual_probe.gd`: capturas de HUD y resultados en 720p y 1080p bajo `user://`. La validación de dificultad y naturalidad requiere conducción; los tests no la sustituyen. La escena sigue notificando instancias ObjectDB sin liberar al salir.

## Semáforo y penalizaciones de salida

Después de cargar y colocar el coche, el semáforo aparece 0,5 s con las dos luces apagadas. A los 0,5/1,5/2,5 s suenan tres clics con roja y «Ready». A los 3,5 s cambia a verde, aparece «Go!» y suena la bocina. El reloj empieza en ese instante, aunque el coche no se mueva. Cada nuevo intento o especial repite la secuencia. Abrir el garaje pausa también la cuenta.

Desplazarse más de 0,75 m en horizontal antes de verde produce una única sanción de 10 s por salida anticipada. La tolerancia evita confundir el asentamiento de suspensión con una salida. Se conservan los controles de ruta atravesados antes de verde y el tiempo permanece en cero hasta «Go!». La sanción aparece inmediatamente encima del mapa, se conserva en el guardado y se suma una vez al parcial, al tiempo de especial y al acumulado.

La clasificación compacta permite desplazar la lista de todos los participantes y muestra posición, piloto, número/tiempo de su último parcial oficial y penalizaciones. Los parciales oficiales incluyen las sanciones; la columna «Penal.» las desglosa y no supone volver a sumarlas. Los rivales también pueden tener sanciones de salida simuladas; las averías y salidas recuperadas son pérdidas de tiempo de conducción, no sanciones deportivas. Al terminar, las sanciones también se identifican en Estado.

Los sonidos originales sintetizados están en `game/sounds/rally_start/`. Se regeneran con `python tools/rally/generate_start_sounds.py` (PCM mono de 16 bits a 48 kHz). El empaquetado conserva copias RIFF `.pcm` para cargarlos sin depender de WAV fuente importados.

Prueba de secuencia, límites temporales, salida falsa y parciales penalizados: `godot --headless --path game --script res://tests/rally/start_sequence_contract.gd`.

## Recuperación y comprobación de parciales originales

`tools/rally/extract_stage_gates.py` se ejecuta con Blender en segundo plano, con parámetros `--fbx`, `--glb`, `--route` y `--output`. Exporta los vértices originales de los diez planos de material `nul_1`, la conversión a coordenadas Godot, el cruce con la ruta y hashes de los archivos fuente. También verifica que cada plano tenga carteles visuales próximos en el GLB. La menor separación entre geometría de cartel y plano es inferior a 0,7 m en los nueve parciales y 1,4 m en meta.

Los cruces se ordenan por estos planos, no por radios de 8 m alrededor de cada nodo de rescate ni por fracciones iguales de longitud. Se mantiene control local del progreso para rechazar teletransportes. El minimapa marca los puntos de parcial; cada captura actualiza la IA y muestra un aviso con tiempo y delta.

`godot --headless --path game --script res://tests/rally/official_split_contract.gd` recorre la ruta real incluyendo una desviación lateral de 12 m, comprueba nueve parciales, meta real, propagación inmediata a la IA, tiempos crecientes, ausencia de dobles capturas y rechazo de teletransporte. Es una comprobación de recorrido programado, no una conducción manual.
