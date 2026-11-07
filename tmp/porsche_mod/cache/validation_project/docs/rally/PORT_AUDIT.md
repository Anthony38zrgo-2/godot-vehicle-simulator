# Auditor√≠a del port independiente

Referencia le√≠da: `D:/open-formula`, HEAD `a8a0bd171d79ffb9a466d13aff747a8158692164`, incluidos los archivos locales. `PRESENTATION_AUDIO_PROVENANCE.json` registra hashes de las fuentes consultadas y de los nuevos recursos. El simulador usa GDScript y los sistemas internos de Godot; no carga DLL ni extensiones Rust.

## Contrato y comportamiento

- `vehicle_simulation.gd` publica secuencia, generaci√≥n de sesi√≥n, tiempo, controles aplicados, motor, combustible, ayudas y cuatro ruedas despu√©s del paso aceptado. HUD y audio leen esa publicaci√≥n.
- Se mantienen cuatro rayos de contacto por callback, con exclusi√≥n del coche. La reacci√≥n del neum√°tico se recalcula en subpasos de rueda usando el mismo contacto. Cada prueba parte del estado inicial del filtro y solo se conserva el √∫ltimo resultado; los filtros avanzan un tiempo `dt`, no `N * dt`. Fuerzas y potencia t√©rmica aplicadas son los promedios de esos subpasos.
- El motor conserva la ley realmente ejecutada en `vehicle-models/src/powertrain.rs`: par√°bola de par, freno motor, limitador y RPM acopladas directamente al eje cuando el embrague est√° conectado. La capacidad m√°xima de embrague declarada tampoco es utilizada por ese consumidor Rust. No se presenta como un embrague con deslizamiento din√°mico.
- Se corrigi√≥ el bloqueo de cambios autom√°ticos: el controlador manual respeta el modo autom√°tico y la caja puede solicitar sus propios cambios.
- Se conservan las aproximaciones de ARB, suspensi√≥n por rayos e inercia diagonal descritas en README. Jolt integra el chasis y resuelve impactos.

## HUD Formula

La referencia visual es `FormulaHud.cpp`, `FormulaHudData.h` y `FormulaHudLayout.cpp` del renderizador OSG de Open Formula. Se usan su composici√≥n a 1920√ó1080, paleta, escala de controles y tama√±o del panel principal. La escala RPM se obtiene del l√≠mite real del Ford y ya no repite etiquetas al adaptar un dial de F1.

Agua y aceite se integran en el panel principal con l√≠mites del perfil. El panel de ruedas muestra banda, carcasa, gas, presi√≥n manom√©trica, desgaste, disco y eficacia de frenos. Interior/centro/exterior permanecen `--`: el modelo simplificado tiene una banda √∫nica. Tampoco se fabrica una temperatura de llanta. Ayudas no disponibles se muestran `--`. Los pedales muestran lo aplicado despu√©s del suavizado.

Actualizaci√≥n de cronometraje: el reloj comienza en Go del sem√°foro. Se recuperaron los planos originales split_00 a split_09 del FBX fuente, contrastados con los carteles checkpoint y gate_finish del GLB visual. Los nodos reset1.bin gu√≠an el progreso local, sin exigir visitar cada punto dentro de un radio de 8 m. Se detectan nueve parciales y la meta real, que est√° despu√©s del √∫ltimo nodo de rescate. R realiza rescate con penalizaci√≥n de 30 s; una salida anticipada a√±ade 10 s. Contrato y pruebas: ai_simulation/README.md.

## Audio reinterpretado

`vehicle_audio_mix_policy.gd` traduce las reglas de `state.rs` y `mixer.rs`: ganancia por acelerador, margen de mezcla, superficie y deslizamiento, transici√≥n N/1, levantada de acelerador y borde de limitador. La banda del Ford conserva sus muestras y ventanas RPM; no recibe grabaciones de motor V10.

`seamless_vehicle_loop.gd` decodifica PCM16 y suaviza el cierre del bucle con la ventana de 512/44100 segundos del n√∫cleo Rust. Las voces continuas permanecen reproduci√©ndose; no se reinician por frame. Aplica envolventes de ataque, ca√≠da, sustain y release a los eventos PCM configurados.

`audio_mixer.json` es la copia del archivo activo de Open Formula. Sus vol√∫menes, EQ, reverberaciones habilitadas, saturaci√≥n, salida y umbral de limitador se interpretan usando buses y efectos de Godot. El escape recibe adem√°s acelerador, carga y pulso de retenci√≥n. El bus `Vehicle` combina todas las fuentes antes de salida.

Las adaptaciones ac√∫sticas est√°n identificadas: EQ a las bandas de Godot m√°s pr√≥ximas, reverb mediante una correspondencia de decay a room size, saturaci√≥n ATAN en lugar del algoritmo de v√°lvula Rust y un tono arm√≥nico de transmisi√≥n ligado al eje. El umbral V10 de petardeo se normaliza al r√©gimen m√°ximo del Ford. Gravel usa la cama de arena del banco com√∫n. El limitador f√≠sico reduce la capa de motor; no se atribuye una muestra de acento de limitador inexistente al banco del Ford. No hay equivalencia PCM ni reproducci√≥n √≠ntegra del sintetizador V10.

## Comprobaciones ejecutadas

Desde la ra√≠z:

```powershell
.\scripts\run_rally.ps1 -Smoke
& 'D:\Formula90s\.tools\godot\Godot_v4.7.1-stable_win64_console.exe' --path game --script res://tests/rally/presentation_audio_contract.gd
& 'D:\Formula90s\.tools\godot\Godot_v4.7.1-stable_win64_console.exe' --path game --script res://tests/rally/presentation_audio_contract.gd -- --russia-preview
.\scripts\stage_rally_windows_export.ps1 -RepositoryRoot 'D:\rust-godot-vehicle-simulator' -GodotPath 'D:\Formula90s\.tools\godot\Godot_v4.7.1-stable_win64_console.exe' -StageOnly
```

El smoke exige avance hacia delante, entrada, primera marcha, contactos y evoluci√≥n t√©rmica. El contrato comprueba publicaci√≥n coherente, offset fijo de c√°mara, ausencia de bandas RPM mudas, voces en bucle, pol√≠tica de mezcla, cambios autom√°ticos, rechazo de atajos, registro/reinicio de tiempos y se√±al PCM real del bus WASAPI. Guarda evidencia JSON y capturas del HUD en `game/logs/rally/`.

Las pruebas y el arranque aislado pasan. La primera importaci√≥n aislada tuvo un cierre nativo de Godot al importar fuentes; el staging usa escena de un hilo y permite un solo reintento de ese c√≥digo de cierre, conservando la cach√© parcial. No se ocultan errores de GDScript.

La latencia solicitada es 40 ms; WASAPI public√≥ aproximadamente 10 ms efectivos en esta m√°quina. El modo headless contin√∫a avisando de objetos retenidos al cerrar. La captura del bus acredita generaci√≥n de audio, no certifica ausencia de cortes en el dispositivo ni una escucha subjetiva. No se ha completado una conducci√≥n manual de todo el tramo ni una comparaci√≥n num√©rica exhaustiva contra Open Formula.

## CorrecciÛn de selecciÛn de pitch

El fallback de pesos nulos seleccionaba errÛneamente el ralentÌ cuando RPM + offset de acelerador superaba 9500. Ahora elige la referencia m·s cercana, manteniendo la capa alta de 6000 RPM hasta el limitador y su margen. Se restaurÛ adem·s `ExhaustSound1` de Sounds.ini: reutiliza EX_Idle6.wav con referencia de reproducciÛn 2000, separada de la capa de ralentÌ. Esto sustituye la extensiÛn provisional del ralentÌ hasta 3000 RPM. Las referencias son calibraciones de reproducciÛn heredadas; no mediciones espectrales de las grabaciones.

`audio_pitch_probe.gd` registra primera marcha a 35% y 100% de acelerador. Antes, a ~9700 RPM ac˙sticas predominaba el ralentÌ a ◊3.5. DespuÈs predomina la capa 6000 a ~◊1.62. La fÌsica permanece igual: a fondo las ruedas llevan r·pidamente el motor cerca del limitador. La captura y la regresiÛn no sustituyen una escucha comparativa.


## CorrecciÛn de fondo y uniformidad de mezcla

La aproximaciÛn de saturaciÛn ATAN se retirÛ del bus general y de las rutas de efectos: no equivale al DSP de v·lvula Rust y alteraba el balance. Se conserva EQ/reverb/limitador. El tono senoidal provisional de transmisiÛn se eliminÛ. La cama de superficie entra gradualmente seg˙n velocidad real, con menor nivel; el scrub de asfalto no se reproduce sobre grava. Las fuentes auxiliares sin seÒal ˙til se pausan, adem·s del control por impulso y potencia de arrastre de carrocerÌa.

`audio_sample_levels.json` registra el RMS de cada WAV y una compensaciÛn solo atenuadora hacia -12 dB RMS. Los WAV de origen permanecen intactos. Los cruces tienen pesos de potencia constante, suavizados en amplitud y renormalizados; se evita la caÌda de energÌa del fundido lineal anterior. La curva de volumen se calibra con una envolvente Ford y carga, eliminando el apilamiento de tres ganancias por acelerador. La reducciÛn artificial a 0.35 en cada entrada al limitador fue retirada: la fÌsica ya publica su corte y aquella reducciÛn creaba saltos de ~9 dB.

ComprobaciÛn gr·fica WASAPI: `--path game --script res://tests/rally/audio_level_sweep.gd`. Con motor y escape silenciados, el RMS de fondo parado fue ~1.68e-11. A carga fija y entre 1800 y 9700 RPM, la variaciÛn capturada fue 2.11 dB para motor y 0.52 dB para escape. Es una mediciÛn de energÌa PCM, no una garantÌa de igual sonoridad perceptiva ni de ausencia de fallos del dispositivo. Los resultados completos est·n en `logs/rally/audio_level_sweep.json`. Esta calibraciÛn sustituye la aproximaciÛn anterior; no se afirma igualdad de amplitud con la mezcla Rust.

## ClasificaciÛn del roce en Rusia

La conducciÛn de prueba sobre el escenario Rusia revelÛ un caso que el campo plano no mostraba: el roce de carrocerÌa con terreno activaba `impact_scrape.wav` casi al m·ximo (ganancia 0.617). Ahora las colisiones del escenario tienen rol terrain/barrier/obstacle; solo el terreno recibe el grupo Gravel. La potencia de arrastre de terreno se conserva como `ground_drag_power_w`, separada de `scrape_power_w` que alimenta el roce de obst·culos. No se modifica la geometrÌa ni se anula la respuesta fÌsica.

El probe admite `-- --russia` y registra ganancias de fuentes auxiliares junto a los contactos. En el mismo recorrido de salida la ganancia met·lica m·xima fue ~4.16e-14, con cero impactos. `barrier_scrape_contract.gd` comprueba un contacto lateral real: produjo roce y una ganancia de ~0.62; la prueba pasÛ con cuatro consultas de rueda. Estas comprobaciones cubren la salida del tramo y la barrera de prueba, no todo el recorrido.
