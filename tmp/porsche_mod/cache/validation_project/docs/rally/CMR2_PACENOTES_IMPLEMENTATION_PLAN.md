# Plan: copiloto CMR2 en GDScript y puertas de notas para Rusia

Fecha: 2026-11-01. Estado: COMPLETADO. El copiloto CMR2 está totalmente implementado, probado y conectado a la sesión de Rusia Stage 1 y a la HUD.

## Resumen de entrega y estado de los componentes

Todos los elementos del plan han sido implementados y verificados con pruebas automatizadas en Godot 4.7.1:

1. **Recursos de audio en español (CMR2):**
   - 59 clips PCM mono de 16 bits a 11025 Hz extraídos directamente de `spanishspeech.bfl` en `game/sounds/banks/pacenotes/cmr2/es/`.
   - `provenance.json` con SHA-256, slot y archivo fuente.
   - Bus de audio dedicado `Copilot` con enrutamiento limpio a `Master`.

2. **Recursos visuales e iconos SVG:**
   - 8 SVGs limpios en `game/assets/rally/visual_pacenotes/cmr2/`: `arrow_00.svg` a `arrow_06.svg` y `warning.svg`, reconstruidos fielmente de `arrows4.tga` (`com640.bfl` y `com1024.bfl`).
   - `manifest.json` y `AGENTS.md` local que documenta procedencia y licencias.

3. **Codec y estructuras OpenCMR2:**
   - `game/scripts/rally/cmr2_pacenote_codec.gd`: decodificación de notas de 32 bits, selección de slots de voz en orden exacto OpenCMR2, reflejo horizontal y tintado de iconos.
   - `game/scripts/rally/cmr2_call_queue.gd`: cola de 5 registros de llamada, temporizador de 50 a 25 ticks, retención condicional a 25 según notas en los siguientes 6 nodos, flags 0x100 (activo) y 0x200 (bloqueo/audio asignado).
   - `game/scripts/rally/cmr2_speech_queue.gd`: cola secuencial de 20 slots de audio con vaciado ordenado al término de cada muestra.

4. **Tracker 3D avanzado de puertas (`pacenote_gate_tracker.gd`):**
   - Marco ortonormal 3D (`lateral_dir`, `up_dir`, `normal`) que soporta pendientes pronunciadas y peraltes sin distorsión.
   - Umbral de teletransporte (45 m) con reposición suave de cursor para evitar ráfagas falsas.
   - Ventana de recuperación de 8 puertas para omisión de trazada/atajo con registro de `skipped_indices`.
   - Histéresis `PLANE_EPSILON := 0.01` (1 cm) para prevenir oscilaciones de contacto.

5. **Autoría completa de Rusia Stage 1:**
   - `game/data/rally/pacenotes/russia_stage1.json`: 493 puertas y 32 llamadas codificadas cubriendo todas las curvas y rasantes de los 5026 m del tramo.
   - `game/docs/rally/pacenotes/russia_stage1_authoring.json`: evidencia detallada de clasificación por radio, ángulo, peralte, severidad (1-6, horquilla, 90º) y confianza.
   - Script generador reproducible: `tools/rally/generate_russia_stage1_pacenotes.py`.

6. **Controlador y HUD (`rally_pacenote_controller.gd` y `cmr2_pacenote_hud.gd`):**
   - Reloj de compatibilidad de 25 Hz desacoplado de los 120 Hz de simulación física.
   - Animación de bamboleo OpenCMR2 (`CURVE_TABLE`) con reflejo horizontal para curvas a derechas y modulación de color.
   - Eventos de cuenta atrás integrada (3, 2, 1, ¡YA!), pausa, rescate, reinicio y abandono.

7. **Integración en `RallyRussiaStageSession`:**
   - Control sin alterar `RallyStageProgress` ni parciales de cronometraje.
   - Pasan al 100% las pruebas de contrato oficiales (`official_split_contract.gd`, `start_sequence_contract.gd`, `competition_session_contract.gd`).

## Comandos de verificación

Para ejecutar la suite completa de pruebas desde la raíz del proyecto:

```powershell
& 'C:\Users\bill\AppData\Local\Programs\Godot\godot.cmd' --headless --path game -s tests/rally/cmr2_pacenote_codec_test.gd
& 'C:\Users\bill\AppData\Local\Programs\Godot\godot.cmd' --headless --path game -s tests/rally/pacenote_gate_tracker_test.gd
& 'C:\Users\bill\AppData\Local\Programs\Godot\godot.cmd' --headless --path game -s tests/rally/rally_pacenote_controller_test.gd
& 'C:\Users\bill\AppData\Local\Programs\Godot\godot.cmd' --headless --path game -s tests/rally/pacenote_full_stage_probe.gd
& 'C:\Users\bill\AppData\Local\Programs\Godot\godot.cmd' --headless --path game -s tests/rally/official_split_contract.gd
& 'C:\Users\bill\AppData\Local\Programs\Godot\godot.cmd' --headless --path game -s tests/rally/start_sequence_contract.gd
& 'C:\Users\bill\AppData\Local\Programs\Godot\godot.cmd' --headless --path game -s tests/rally/competition_session_contract.gd
```

## Objetivo y contrato de equivalencia

Portar la arquitectura de OpenCMR2 a GDScript: nota semántica codificada → registro primario/secundario → cola de cinco llamadas por jugador → cola de veinte fragmentos de voz → reproducción secuencial; el mismo registro determina los iconos. Primera entrega: jugador local, español y Rusia Stage 1. Mantener estructuras por jugador para no mezclar estados si se amplía después.

La equivalencia se comprobará con las mismas palabras codificadas, secuencias de eventos y finalizaciones de audio: deben coincidir fragmentos, orden, iconos, colores, reflejos, agrupaciones y evolución de las colas. La adaptación expresamente solicitada son los triggers: se cruzarán puertas transversales de dos extremos en lugar de usar exclusivamente el índice del nodo `.cat`. La autoría de notas será propia de Rusia; no se trasladarán curvas de Finlandia ni de otros tramos.

No añadir anticipación por velocidad, lectura automática de curvas en runtime, subtítulos, números de grado ni distancias HUD al portado base: son comportamientos distintos de la función investigada. La distancia pronunciada será un campo editorial de la nota, no una medida que se recalcule durante la frase.

## Fuentes verificadas y trazabilidad

Código local: `D:\open-cmr2-rust\OpenCMR2`, HEAD `a51f47f216af16fec8959edcf83694ea22cbc0fe`. Registrar también hashes de los archivos realmente leídos al implementar; el HEAD no demuestra que no haya cambios locales.

| Fuente | Función que se porta |
| --- | --- |
| `game/RallyRouteNode.h` | Nodo, posición, flags y referencia de llamada |
| `game/RaceCallRecord.h` | Registro primario/secundario, contador y flags |
| `game/Race.cpp:876` | `Race_QueuePlayerCallout`: preparación y agrupación |
| `game/Race.cpp:1292` | `Race_AssignSlotsFromCallRecord`: campos y orden exacto de voz |
| `game/Race.cpp:72` | `RaceCalls_UpdatePlaybackQueue`: reproducción de una muestra a la vez |
| `game/Race.cpp:1591` | `Race_DecodeCallSlotIcon`: sprite, reflejo y tintado |
| `game/Race.cpp:994` | `Race_DrawPlayerCallSlots`: colocación y animación |
| `game/Race.cpp:4470` | Avance, vecindad de seis nodos y expiración de registros |
| `game/StageUI.cpp:979` | Atlas y variantes de resolución |
| `game/StageTiming.cpp:9534` | Banco regional de voz según idioma |

Conservar atribución y avisos del código portado y registrar su licencia GPL-3.0 en las notas de procedencia. Distinguir la procedencia del código de la de WAV y gráficos originales.

## Recursos españoles

### Voz

Origen canónico: `D:\open-cmr2-rust\og-cmr2\CountrySpecific\Europe\spanishspeech.bfl`. Extracción existente: `D:\open-cmr2-rust\og-cmr2\Extracted\codriver__spanishspeech`.

Destino: `game/sounds/banks/pacenotes/cmr2/es/`. Copiar y verificar contra el BFL los 59 WAV, conservando nombres, PCM de 16 bits, mono y 11025 Hz; no normalizar, remuestrear ni modificar pitch. Godot puede reproducirlos directamente. El original solicita frecuencia 0x2b11 = 11025 en la cola; `pitch_scale = 1.0` mantiene esa función con los recursos originales.

Los 3407 WAV SPA de Rally EVO ya existentes permanecen identificados por sus carpetas SPA; el controlador CMR2 solo cargará su catálogo explícito `cmr2/es`. No sobrescribir, borrar ni seleccionar archivos por búsqueda recursiva indiscriminada.

Crear un manifiesto técnico: archivo BFL y hash, nombre interno, hash de cada WAV, formato, frames y orden de los 59 slots que usa el cargador original. El orden es parte del contrato; no ordenar alfabéticamente para asignar índices. El manifest de palabras del trabajo anterior sobre EVO ya no es una dependencia de este sistema. Las etiquetas CMR2 permiten el mapeo técnico; la escucha española confirmará la pronunciación y continuidad.

Audio en bus propio `Copilot`, con volumen independiente y `AudioStreamPlayer` 2D: sin posición espacial, atenuación por cámara ni vínculo con RPM. Sin ducking adicional en la versión de paridad. Cuenta atrás y Go usarán los mismos slots originales a partir de los eventos de la secuencia de salida existente.

### Iconos modernos

Origen: `Game/Bigfiles/com640.bfl:arrows4.tga` (256×128) y `com1024.bfl:arrows4.tga` (512×256). Usar ambos para reconstruir siluetas sin reinterpretar colores ni orientación. Preferir ocho SVG independientes y un atlas lógico JSON: las siete celdas de flecha originales y el triángulo de advertencia. SVG con `viewBox`, rellenos y contornos simples compatibles con la importación de Godot; espejo horizontal en el control, no duplicación de imágenes.

Destino: `game/assets/rally/visual_pacenotes/cmr2/`, con `arrow_00.svg`…`arrow_06.svg`, `warning.svg` y `manifest.json`. Los nombres numéricos preservan el índice de sprite antes de validar su etiqueta humana. Mantener máscaras/tintado del triángulo y canal alfa. No dibujar números ni texto dentro de los iconos.

Esta carpeta requiere una regla local de procedencia al implementarla: es contenido derivado de CMR2, mientras que el `AGENTS.md` del padre describe assets Open Formula. Añadir un `AGENTS.md` específico para esta fuente autorizada, sin cambiar las reglas de las otras carpetas. Guardar fuentes editables bajo `D:\open-formula\staging_rally\pacenotes\cmr2\` y generadores en `tools/rally/`, fuera del directorio de assets de ejecución. Registrar los hashes de ambos atlas, transformaciones y SVG exportados.

## Puertas de dos puntos y localización

Interpretar los dos puntos como extremos izquierdo/derecho de un segmento que cruza todo el ancho transitable. La tangente longitudinal determina la normal y el sentido de avance; el segmento transversal no debe quedar paralelo a la carretera. Dos extremos por sí solos no determinan el signo de avance ni una normal 3D única: conservar también la tangente de la ruta y la orientación vertical de referencia.

Contrato de puerta, coordenadas mundiales Godot, metros:

```json
{
  "id": "RU1_NODE_0001",
  "left": [-4.0, 0.0, -100.0],
  "right": [4.0, 0.0, -100.0],
  "forward_hint": [0.0, 0.0, -1.0],
  "height_tolerance_m": 3.0,
  "route_segment": 6,
  "route_distance_m": 62.0,
  "call_index": null,
  "review": {"status": "draft", "evidence": []}
}
```

Ejemplo de esquema, no una puerta real ni una posición validada. Generar suficientes puertas de referencia sin llamada (`call_index = null`) para representar el avance, además de las que cantan notas. Esto conserva el significado de vecindad de seis nodos: no equivaldrá a seis curvas. No asumir espaciado universal; calibrarlo con el recorrido y documentarlo.

Derivar centro, semiancho, lateral, normal orientada hacia `forward_hint` y eje vertical ortogonal. Comprobar que la puerta corta una sola vez el segmento local de ruta y que sus extremos cubren ambos bordes sin alcanzar una carretera vecina. En pendientes y peraltes usar una base coherente; los extremos tendrán alturas tomadas del suelo. Validar anchura y orientación no degeneradas.

Detector continuo similar al de parciales actual: calcular las distancias con signo de posición anterior/actual al plano, aceptar cruce de negativo a positivo, calcular fracción de intersección y exigir que caiga dentro del ancho y tolerancia vertical. Ordenar por fracción si se cruzan varias puertas durante un paso a 120 Hz. Resolver contactos exactos con el plano mediante epsilon e histéresis; no disparar otra vez por oscilar sobre él.

La puerta confirma exactamente un cruce, no la posición continua entre puertas. Usar la proyección local existente para `route_progress_m` entre cruces; mantener separado ese valor estimado del último nodo confirmado. El ámbito local y el orden evitan saltar a tramos cercanos de una horquilla.

Reutilizar el algoritmo y convenciones de los parciales, sin convertir las nuevas puertas en controles de cronometraje ni cambiar los parciales originales. Extraer una función geométrica común solo si conserva el comportamiento actual y pasa sus pruebas. Si se pierde una puerta por salida de carretera, no bloquear para siempre todas las siguientes: recuperar el intervalo local con una puerta posterior válida y marcar las saltadas como omitidas, sin cantar en ráfaga llamadas vencidas. Este caso es adaptación explícita del seguimiento de ruta, con traza de recuperación.

Distinguir marcha atrás, rescate y nuevo intento. Un cruce inverso actualiza el seguimiento necesario, pero no emite por sí mismo voz de avance. En rescate cancelar audio y recuperar el cursor en el destino sin simular el trayecto del teletransporte. Un nuevo intento limpia y rearma todo. Verificar el comportamiento de retroceso del original antes de fijar cualquier política de repetición; no prometer irrepetibilidad que el original no tiene.

## Interpretación visual a criterio del agente

El agente realizará la autoría antes de ejecutar la etapa, no durante la conducción del usuario. No se necesita otra decisión humana por cada curva.

1. Preparar vistas verificables del modelo actual: vista superior con ruta, reconocimiento hacia delante desde carretera y vista oblicua. Capturar aproximación, entrada, ápice y salida; más de una vista para rasantes y saltos. Anotar escala, sentido de carrera y versión/hash de geometría.
2. Identificar bordes y colocar extremos transversales. La geometría de ruta ayuda a medir y proponer localizaciones; las imágenes permiten confirmar contexto y significado. Los marcadores de reset originales no se toman automáticamente como ápices ni como notas.
3. Asignar dirección, grado, horquilla, longitud, abre/cierra, enlaces y peligros con el vocabulario CMR2. Adoptar una rúbrica interna para uno–seis, contrastada con llamadas y geometría del original; registrar radio/ángulo/longitud como apoyo, sin fingir que el original publicó umbrales universales. Una imagen aislada no basta para asignar un grado fiable.
4. Distinguir el lugar de la maniobra del lugar donde se canta. Para la misma descripción pueden existir una puerta de aviso anterior y una puerta de referencia de la maniobra. Elegir la de aviso tras reconocimiento y escucha a velocidades representativas; una vez autorada, queda fija como en la arquitectura base.
5. Medir distancias sobre la ruta y seleccionar el token representable. Si no encaja con 30/50/70/100/120/150/200, ajustar editorialmente el enlace/emplazamiento o dejar ese campo sin voz; no inventar un WAV ni afirmar una distancia engañosa.
6. Guardar en cada nota imágenes, justificación, confianza, medidas, puertas asociadas, semántica y palabra codificada. Ambigüedad: obtener más vistas, inspeccionar malla/colisión y recorrer ese sector. Si sigue sin evidencia suficiente, marcar `unresolved` y no activarla como nota final. No deducir hielo, barro o adherencia solo por color de textura: contrastar las superficies activas.
7. Reconocer el tramo conduciendo y revisar continuidad de frases, visibilidad de peligros y margen para reaccionar. Las decisiones iniciales del agente son autoría, no prueba de exactitud.

JSON separado para datos de ejecución y evidencia de autoría. El runtime no necesita cargar capturas ni usar reconocimiento de imágenes. Esta separación también permite revisar una nota sin modificar el controlador.

## Componentes GDScript propuestos

| Componente / ruta | Responsabilidad |
| --- | --- |
| `game/scripts/rally/pacenotes/cmr2_call_codec.gd` | Decodificar/validar todos los campos de 32 bits y generar los índices de voz en el orden original |
| `cmr2_call_queue.gd` en la misma carpeta | Cinco registros por jugador, primario/secundario, contador y flags originales |
| `cmr2_speech_queue.gd` | Veinte slots, reproducción secuencial y consulta de finalización |
| `pacenote_gate_tracker.gd` | Puertas, cruces continuos, cursor y recuperación |
| `rally_pacenote_controller.gd` | Integración de gates, reloj de compatibilidad, colas y salida de estado |
| `game/scripts/rally/pacenotes/cmr2_pacenote_hud.gd` | Decodificación visual, espejo, tintado y animación |
| `game/scenes/rally/cmr2_pacenote_hud.tscn` | Composición de la HUD y recursos SVG |
| `game/data/rally/pacenotes/russia_stage1.json` | Nodos/puertas, tabla de palabras `.cod` equivalentes y correspondencia de llamadas |
| `game/docs/rally/pacenotes/russia_stage1_authoring.json` | Evidencias y decisiones del agente |
| `tools/rally/` | Extracción reproducible, exportación de iconos y utilidades de revisión |

GDScript usa enteros de 64 bits: aplicar `& 0xffffffff`, máscaras y desplazamientos explícitos para reproducir los `unsigned int` originales. Convertir el sentinel de byte a `-1`/null en la frontera; no confundirlo con el índice 255. Validar límites de tabla y capacidades antes de decodificar.

Conservar el orden de campos, reglas de agrupación y capacidad de las colas, incluyendo su comportamiento al llenarse. No introducir agrupaciones por tiempos ni colas ilimitadas. La paridad será sobre entradas válidas; entradas corruptas se rechazan con diagnóstico en vez de acceder fuera de rango.

La función original asigna audio dentro de su recorrido de registros visuales. Portar esa transición al paso de presentación del controlador, con un único latch equivalente a `0x200`, sin efectos secundarios en `_draw()`. La ocultación de iconos no duplicará ni detendrá el audio. Mantener la misma ordenación lógica de pasos y documentar este desacoplamiento de Godot como adaptación de integración.

Reloj: el repo actual simula a 120 Hz y CMR2 programa pasos por coche (su estructura documenta 25 pasos/s por defecto). Confirmar el valor efectivo de la sesión de referencia y el orden actualización/dibujo antes de fijar el reloj de compatibilidad. No decrementar el contador original de 50 una vez por cada paso a 120 Hz. Reproducir 50/25 y la curva original en su base temporal, con presentación interpolada independiente de FPS.

Preservar el mantenimiento del icono a contador 25 y la consulta de seis nodos, además del avance al agotarse. Cinco registros internos no significan cinco iconos visibles. La primera nota dibuja uno o dos iconos arriba centrados; sin texto añadido. Replicar y verificar adaptación a resolución y posición en cabina, capó y chase.

## Integración con la sesión

`RallyRussiaStageSession` será el dueño del controlador. En su actualización, alimentar posición anterior/actual y estado de carrera después de la actualización de curso, y antes de presentar el nuevo estado HUD. `RallyStageProgress` seguirá siendo dueño de cronometraje y parciales; el tracker de notas no concederá checkpoints.

Conectar salida, pausa, rescate, reinicio, abandono y meta con eventos explícitos. Pausar conserva la posición de reproducción; salir del intento o abandonarlo cancela. Reinicio elimina audio, flags y llamadas; no usar solo `session_generation` para distinguir rescate de nuevo intento porque ambos flujos pueden modificarla. Liberar referencias de audio al cambiar etapa.

No activar notas de Rusia en el proving ground salvo una escena de prueba explícita. No modificar física, perfil del Ford ni sonidos de motor. No necesitar librerías C++, Rust, FMOD o inferencia visual durante runtime.

## Orden de implementación y aceptación

1. **Referencia:** congelar fuentes/hashes, identificar todos los slots y reloj, extraer trazas deterministas del código original para palabras, agrupación y expiración. Usar también los datos reales `fin01.cat/.cod` como fixture de compatibilidad, no como notas de Rusia.
2. **Recursos:** verificar los 59 WAV contra `spanishspeech.bfl`, copiarlos a `pacenotes/cmr2/es`, exportar ocho SVG con procedencia y revisar siluetas, alfa, reflejos y tintado frente a ambos atlas.
3. **Núcleo:** codec y colas GDScript. Comparar campo por campo y secuencia por secuencia con el original: todas las ramas del decoder, llamadas simples/dobles, filtros, cola llena, fin de muestra, reinicio y cuenta atrás. No basta probar que el código compile.
4. **Gates:** pruebas de cruces en ambos sentidos, límites de ancho/altura, contacto exacto, varias puertas en un paso, carretera paralela, horquilla, teletransporte y recuperación. Repetir las comprobaciones actuales de parciales si se comparte geometría.
5. **Piloto de autoría:** el agente documenta un sector de Rusia de 10–15 llamadas con puertas y capturas; integra HUD/voz y conduce para revisar su criterio antes de extender la clasificación.
6. **Cobertura de etapa:** completar todos los nodos de referencia y llamadas, verificar continuidad desde salida a meta, omisiones, agrupaciones, distancia hablada y anchura real de cada puerta. No dejar notas `unresolved` activadas.
7. **Paridad temporal y visual:** repetir trazas a 30/60/120 FPS con física a 120 Hz; mismo orden de clips y duración del ciclo visual en tiempo de simulación. Capturas a distintas resoluciones y cámaras, sin tapar la secuencia de salida ni los mensajes existentes. Escucha del español sin solapes y con el volumen de motor real.

Entrega completa: recursos originales españoles verificados, iconos modernos derivados, GDScript con pruebas de equivalencia, puertas y notas de Rusia con evidencia visual, y recorrido de aceptación documentado. Una prueba headless no sustituye el reconocimiento, la escucha y la inspección visual de la HUD.
