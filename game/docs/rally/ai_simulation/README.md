# Competición virtual de Rally

Implementación activa en `russia_stage1_ford_escort_rs2000.tscn`. No se instancian coches rivales. El vehículo del jugador conserva sus físicas Jolt.

## Uso

Ejecutar `scripts/run_rally.ps1`. Antes del primer parcial la tabla indica «Sin parcial» y permite consultar participantes y estados de salida. Durante la especial se muestran cinco filas de clasificación general encima del mapa, incluido el jugador y rivales cercanos. El delta positivo indica retraso frente al líder al mismo parcial; permanece confirmado hasta el siguiente control.

«Abandonar especial» simula todos los sectores restantes y abre resultados. Caer fuera del mundo produce abandono por salida de pista. R realiza rescate en el último control validado, conserva reloj y recorrido y añade 30 segundos. El jugador que abandona queda fuera del rally; puede reintentar como práctica o empezar otro rally.

La tabla final tiene posición general, piloto, coche-equipo, tiempo de especial, acumulado y estado. DNF/DNS muestran «—» como tiempo final. Los nombres y estados largos tienen tooltip y la tabla permite desplazamiento. «Siguiente especial — Rusia» conserva acumulados, desgaste y retirados, aplica asistencia limitada y repite el escenario disponible. No implica que se hayan portado otras especiales. «Nuevo rally» limpia el acumulado y cambia la semilla; «Reintentar especial» conserva preparación y semilla.

## Referencia y adaptación

Los diez sectores se capturan en controles obligatorios de la ruta, con cruce barrido e interpolación temporal. Se asignaron los diez `CPUSplit` originales de Rusia 1 a sectores de longitud aproximadamente igual: esta correspondencia es una aproximación de diseño, no una recuperación verificada de los puntos de cronometraje originales. La escala de tiempos puede calibrarse en `game/data/competition/stages/russia_stage1.json`.

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
