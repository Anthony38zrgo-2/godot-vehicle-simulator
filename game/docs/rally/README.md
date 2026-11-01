# Ford Escort Rally: modelo GDScript

## Ejecución

Desde la raíz del repositorio:

```powershell
.\scripts\run_rally.ps1 -ProvingGround
.\scripts\run_rally.ps1
```

El lanzador busca Godot junto al proyecto y en la carpeta `.tools/godot` de `Formula90s` vecina, además de `GODOT_BIN` y `PATH`. Para otra instalación se puede indicar `-GodotPath "C:\ruta\a\Godot.exe"`.

La primera sesión abre el campo de pruebas; la segunda abre Rusia Stage 1. El vehículo usa un único `RigidBody3D`. Jolt aplica gravedad, integra el chasis y resuelve sus colisiones. `FordRallyVehicleSimulation` consulta exactamente un rayo central por rueda en cada callback de física y reutiliza esos cuatro contactos durante sus subpasos de giro de rueda.

La ruta antigua `res://scenes/rally/ford_rally_prototype.tscn` queda como alias del campo de pruebas; no conserva el controlador provisional ni sondeos de rueda duplicados.

La cámara trasera conserva su desplazamiento y campo visual; no interpola una distancia que la deje atrás ni aplica zoom por velocidad. El escape mantiene una capa audible al cruzar bajas RPM y el proyecto solicita 40 ms de latencia de salida para reducir chasquidos de mezcla.

## Fuentes y precedencia

`data/vehicles/ford-escort-rs2000/vehicle.json` es el manifiesto activo. El cargador resuelve sus trece dominios por rutas relativas, valida SI y los ejes `forward=-Z`, `right=+X`, `up=+Y`, y calcula SHA-256 de cada documento cargado. `OPEN_FORMULA_PROVENANCE.json` registra HEAD y hashes de las fuentes leídas en `D:/open-formula`; no modifica ese repositorio.

Los filtros de `tire_filters.json` sobrescriben solo las claves presentes sobre `tires.force_model`; las demás conservan el valor de `tires.json`. Su `surface_transition_tau_s` tiene precedencia sobre el dominio de neumáticos.

El `coupled_world.json` copiado tiene el objeto `coupled_world` anidado y no contiene `vehicle_topology`. La versión actual de `rapier-vehicle-world/src/vehicle_profile.rs` busca `vehicle_topology` en la raíz y rechaza este documento. Por eso ese consumidor no sirve como prueba de que tales dominios estuvieran activos en Rapier. GDScript carga y traduce los documentos disponibles por separado; esta sesión no enlaza ni ejecuta Rust.

## Traducciones activas y límites

- **Masa:** suma el inventario físico y el combustible restante. Con 25 kg iniciales resulta 1095 kg; los componentes no asociados a ruedas deben cerrar el presupuesto base de 990 kg. Centro de masa e inercia se recomponen, incluido el tanque, al consumirse combustible. Godot recibe solo la diagonal del tensor compuesto; sus productos cruzados no se representan.
- **Suspensión:** usa tasas de muelle, amortiguación de compresión/rebote, topes, recorrido, caída y convergencia del dominio geométrico. La fuerza estática se reparte según el centro de masa; compresión adicional cambia la carga. Los filtros de distancia de carretera, velocidad de amortiguador y recorrido ARB mantienen estado por rueda.
- **Barras estabilizadoras:** el documento solo tiene `front_arb.ratio` y `rear_arb.ratio`, no tasas N/m consumidas por el cargador Rapier. GDScript los interpreta explícitamente como fracción de la tasa de muelle del eje (5600 N/m delante y 1920 N/m detrás). Es una aproximación local, no una medida del Escort.
- **Neumáticos:** fuerza longitudinal/lateral por eje, superficie, sensibilidad de carga, deslizamiento combinado suavizado, relajación, memoria post-pico, migración de picos, camber, resistencia a la rodadura y par autoalineante. Los estados térmicos y filtros se avanzan una vez por callback, no por subpaso.
- **Tren motriz:** GDScript integra las RPM libres del motor y el par del embrague, con realimentación de reacciones de neumático del paso anterior, límite de embrague, desembrague anti-calado, rampa positiva de par e inercia de motor/transmisión reflejada en las ruedas motrices. El acoplamiento y la interpolación de torque_curve siguen rust/vehicle-physics-engine/src/powertrain.rs sin cargar Rust en ejecución. Se consumen la curva y los parámetros de arrastre/freno del JSON; Godot/Jolt conserva la integración del chasis.
- **Frenos:** par máximo, reparto y freno de mano trasero vienen del perfil. La temperatura de disco y su fade usan el modelo sencillo activo de `VehicleInternalState`; el modelo de dos nodos y conductos detallado de `brakes.json` no es cargado por el perfil Rapier ni se afirma aquí como activo.
- **Térmicas y combustible:** bloque, agua, aceite, reducción de par, banda/carcasa/gas del neumático, presión por temperatura absoluta, desgaste, temperatura/fade de freno y consumo actualizan fuerzas o masa. Se usa la ley de consumo del estado interno de referencia (1.05e-7 litros por julio mecánico positivo).
- **Aerodinámica:** se traduce el arrastre cuadrático y el arrastre de conductos de refrigeración. No se añade carga aerodinámica vertical.
- **Contacto inferior:** `underfloor_contact.json` se carga y conserva para trazabilidad, pero sus sondeos de despeje no se ejecutan: añadirían consultas de contacto fuera del único rayo autorizado por rueda. Los cascos y cajas del Ford y las colisiones de escenario dejan la resolución rígida a Jolt.
- **Suspensión visual:** las cuatro mallas se mueven con la extensión, compresión, caída, convergencia, giro y velocidad angular calculados. Son visuales, no cuerpos físicos separados.
- **Ayudas:** se aplican suavizado de pedales/dirección y embrague automático según el perfil. TCS, estabilidad y ABS permanecen desactivados porque el dominio declara `*_available=false`; el cambio de transmisión automática sí se puede solicitar en ejecución.

Estas decisiones producen una sesión conducible como primer modelo, no una equivalencia numérica completa de la suspensión multibody de Rapier ni una reconstrucción medida del Escort. La aceptación final de conducción y el ajuste fino corresponden a pruebas al volante.

La comparaci�n actualizada de HUD, audio, transmisi�n y pruebas est� en [PORT_AUDIT.md](PORT_AUDIT.md). La presentaci�n y el audio consumen una publicaci�n com�n del paso f�sico. Rusia incluye minimapa y tiempos de tramo con los nodos de origen; las zonas de neum�tico que el modelo no publica permanecen ausentes.


Audio del Ford (2026-11-01): motor y escape conservan sus crossfades Rally Trophy. Se eliminan los refuerzos simultáneos rs/rt-cos, dos silbidos adicionales, detidle y los pops periódicos al ralentí. Queda un silbido de transmisión; fm/rm-cos entran al soltar gas mediante una rampa entre 1.5 y 3 veces las RPM de ralentí, a mitad de su ganancia anterior. Los det1–4 se conservan únicamente como eventos al levantar a altas RPM. chatter.wav y backfire.wav fueron retirados del banco; el segundo ya no tenía referencia activa. Son decisiones locales de mezcla, pendientes de aceptación auditiva en conducción. Superficies, neumáticos, impactos y ambiente conservan su mezcla.


## Superficies CMR4 (2026-11-01)

El banco independiente `sounds/banks/surfaces/manifest.json` sustituye rodadura CMR2 y tyre_scrub de commons. Grava usa grv_er11/grv_es1; hierba grs_er11/grs_es1; tierra drt_er11/drt_es1. Asfalto usa tar_er21, tar_s2, tar_p2 y tar_l2. Los números identifican conjuntos/variantes de la configuración original, no bandas de velocidad verificadas. Arena y rumble conservan los WAV anteriores bajo surfaces/legacy. Barro, nieve, hielo, mul y eventos especiales están inventariados pero inactivos.

SurfaceMix pondera las cuatro ruedas por carga y conserva como máximo dos superficies. Rodadura y deslizamiento tienen ganancias base 0.15 y 0.135, transiciones de 80 ms y pitch moderado. El deslizamiento reduce hasta un 70% la rodadura. Solo un rol de deslizamiento domina por superficie; en materiales sueltos skid sustituye peel/lock con la misma muestra. Los umbrales y ganancias son aproximaciones locales. La mezcla se apaga progresivamente sin contacto y por debajo de 2 km/h. Solo se usan voces exteriores; no hay cámara interior real.

Extracción/preparación/verificación: `python -m tools.audio.cmr4_surfaces extract`, `prepare`, `verify`. Requiere Python y numpy. Las 59 fuentes PCM16 mono 22050 Hz se conservan en bank_sources/cmr4/surfaces; hashes y roles se registran junto al archivo original y la configuración. La preparación quita DC, ajusta RMS con techo de pico de muestra de -1 dBFS y hornea un fundido de bucle de 120 ms; no garantiza un techo true-peak. El reproductor no aplica un segundo fundido. La exportación incluye el banco y sus copias RIFF .pcm.

Validación: `surface_audio_contract.gd` verifica mezcla, límite de superficies, silencio detenido/en aire, sustitución de rodadura por slip, suavizado y carga real de voces. Smoke y hashes se comprueban por separado. La aceptación auditiva en conducción queda pendiente; la muestra offline se reproduce con `python -m tools.audio.preview_surfaces` y no incluye espacialización, motor ni ambiente.

Arena sobre carrocería: `python -m tools.audio.synthesize_sand_impact` genera un one-shot original PCM16 mono 22050 Hz de 0.72 s, semilla 43017, pico -9 dBFS. Procedencia y SHA-256 en surfaces/synthetic/manifest.json. Contacto Sand o Gravel, desde 12 km/h, presencia ponderada por carga y velocidad; voz única, intervalos 0.85–1.50 s, ganancia máxima 0.10 antes del bus 0.55 y atenuación 3D. HPF 300 / LPF 4500 Hz; cockpit atenúa y filtra como las demás superficies. Aproximación acústica local; no sustituye la rodadura.


## Escort RS1600 CMR4 (2026-11-01)
El banco activo es `sounds/banks/EscortRS1600`, extraído con `python -m tools.audio.cmr4_escort`.
Conserva 35 WAV originales PCM16 mono y hashes SHA-256; motor/escape ~32 kHz y efectos 22050 Hz, sin resamplear.
Las 22 voces continuas usan stat como ralentí y cinco capas thr/idle como carga/retención, con fundido por acelerador.
Centros estimados: 1050, 1800, 3000, 4200, 5500 y 6800 RPM. No son RPM medidas ni curvas FL/NMAP decodificadas.
whinelo/hi se cruzan por velocidad de eje; gearup1-4 para subidas, clunk para reducciones y loadoff1-4 para eventos al soltar.
Estos últimos no se presentan como detonaciones de combustión verificadas. Ignition/stall quedan inventariados, sin evento de arranque/calado conectado.
El RS1600 es una aproximación acústica al Pinto RS2000 del vehículo; la aceptación auditiva en conducción sigue pendiente.
Commons conserva neutral, limitador e impactos; superficies conserva rodadura y deslizamiento. El banco anterior queda archivado sin referencias activas.

Validación: `escort_audio_contract.gd` pasó (35 hashes/PCM nativos, 22 capas, eventos y barrido 1050–7500 RPM a acelerador 0/0.5/1, sin huecos silenciosos). `run_rally.ps1 -Smoke` pasó. Godot advierte 76 instancias ObjectDB al salir. El contrato antiguo `presentation_audio_contract.gd` no es ejecutable con el controlador actual: referencia `engine_players`, propiedad retirada; no se usa como evidencia de aceptación auditiva.

Cambios WRC9: wrc9_shifts contiene 32 PCM16 decodificados del EscortMKII1800.bank con nombres, indices y hashes. gearbox_force01-04 son la capa mecanica general de subida (asignacion local); gear_down01-03 para reduccion. P206 onboard y M3E30R cockpit solo se disparan en camera_mode 2 y se detienen al salir. Los dos eventos F2002 de commons permanecen superpuestos y se mantiene el ajuste previo de ganancia 0.75. Motor, escape y whine conservan CMR4.
