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
