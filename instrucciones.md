# Rally Maniac — instrucciones de implementación del menú principal

## Alcance

El arranque normal de `scripts/run_rally.ps1` debe mostrar el menú **Rally Maniac** antes de cargar un coche o una especial. El menú se implementa en Godot, dentro del mismo proceso que ejecuta el tramo.

| Botón | Primera versión |
|---|---|
| Championship | Permite elegir y correr un tramo de Rusia como entrada provisional del modo. La clasificación y la progresión de campeonato corresponden a una fase posterior. |
| Rally | Inicia el evento ruso en el tramo elegido y permite continuar por los tramos siguientes en orden hasta el final del itinerario. |
| Single Stage | Ejecuta una sesión independiente que termina tras el tramo elegido. |
| Exit | Cierra el juego. |

## 1. Pantallas y navegación

- Crear una escena `Control` en `game/scenes/rally/` con el título exacto **Rally Maniac** y los botones **Championship**, **Rally**, **Single Stage** y **Exit**, en ese orden. Usar contenedores de Godot para que los elementos se ajusten al tamaño de ventana.
- Los tres modos comparten el selector de tramo. Mostrar **Russia Stage 1** a **Russia Stage 10** en orden numérico. Cada entrada debe transportar su ID interno (`russia_stage1` a `russia_stage10`), independientemente del texto mostrado.
- Tras elegir el tramo, abrir **Select Car**. Leer `game/data/vehicles/registry.json` y usar `DisplayName` para mostrar **Lancia Fulvia HF** y **Ford Escort RS2000**. Usar la clave del registro para identificar el coche y el campo `Stage` para resolver su escena base.
- Añadir **Back** en los dos selectores. Desde el selector de coche, volver a los tramos con la selección anterior enfocada. Desde los tramos, volver al menú con el modo enfocado. Permitir navegar con ratón y teclado. Dar foco visible a un botón al abrir cada pantalla.
- Al confirmar el coche, mostrar un estado de carga y bloquear confirmaciones repetidas. Si falta la escena o algún recurso obligatorio, mostrar el error y permitir volver al selector correspondiente.

## 2. Arranque desde PowerShell

- En `scripts/run_rally.ps1`, separar la escena del menú de la escena de tramo que el lanzador resuelve actualmente por coche. Usar el menú en el lanzamiento interactivo normal y conservar el arranque directo con `-Vehicle` explícito como acceso técnico.
- Mantener las rutas actuales de `-Smoke`, `-ValidateRuntimeOnly`, `-ProvingGround` y `-ExportWindows`. Mantener también los argumentos de registro, telemetría e ID de ejecución al abrir el menú. Verificar que la telemetría de una sesión iniciada desde el menú identifica el coche y tramo realmente elegidos.
- El lanzador actualmente valida los recursos del coche seleccionado y el manifiesto de Stage 1. La selección interactiva debe comprobar la combinación efectiva al preparar la sesión, con mensajes que identifiquen el recurso que falló.

## 3. Inicio de sesión

- Transferir modo, ID de tramo y clave de coche a la sesión. Instanciar la escena base del coche y configurar el ID del tramo y el contexto de competición antes de que se ejecute `_ready()` en `rally_russia_stage_session.gd`.
- Reutilizar `RallyStageLoader.resolve()` y la inicialización de geometría, colisión, posición de salida, cronometraje y notas que ya usa la sesión. Validar el ID seleccionado y tratar un fallo de carga como error visible. Un error en otro tramo no debe iniciar Stage 1.
- Para **Rally**, inicializar el gestor del evento con un itinerario que empiece en la especial elegida. Revisar `begin_event()` y `_build_itinerary()` en `rally_event_manager.gd`. El primer ID del itinerario, el cursor, el clima, la ventana inicial y la configuración de competición deben referirse a la misma especial. Avanzar con la transición existente. Los tramos anteriores a la selección quedan fuera de ese intento.
- Para **Single Stage** y la entrada provisional de **Championship**, usar una sesión de un tramo con resultados independientes del guardado oficial de Rally. Al terminar, mostrar el resultado de la especial sin ofrecer avanzar a la siguiente. Mantener separado el modo elegido para poder implementar la progresión de Championship más adelante.
- Abrir selectores y retroceder solo debe modificar la selección del menú. Crear o guardar un evento oficial únicamente cuando se confirme el lanzamiento de Rally.

## 4. Reglajes antes de la salida

- Reutilizar el panel de garaje actual, con los ajustes y los neumáticos del coche elegido. Abrirlo automáticamente tras preparar el tramo y colocar el coche en la salida.
- Actualmente `_open_setup_window()` requiere un gestor de evento y una ventana pendiente, y `_on_garage_closed()` confirma mediante ese gestor. Dar a las sesiones de un tramo un flujo de confirmación compatible con el mismo panel. Compartir el bloqueo de salida y la aplicación de ajustes, y asociar la persistencia oficial únicamente al contexto Rally.
- Para la ventana inicial, derivar el rótulo del tramo seleccionado. El texto actual `INICIO · STAGE 1` está fijo. Mantener las ventanas de servicio y reparación del evento en sus puntos previstos.
- Mantener congelado el vehículo, deshabilitada la conducción y detenidos el reloj ambiental y la cuenta atrás mientras el panel espera confirmación. Aplicar el reglaje una sola vez al pulsar **Aceptar** y continuar con la secuencia de salida existente. Si el panel se cierra sin aplicar o el reglaje falla, mantener bloqueada la salida y permitir corregir o confirmar de nuevo.

## 5. Pruebas de aceptación

1. Ejecutar `scripts/run_rally.ps1` sin argumentos y verificar que aparece primero **Rally Maniac**, con los cuatro botones en orden. Comprobar **Exit** desde un arranque limpio.
2. Entrar en cada modo y comprobar que el selector ofrece los diez tramos rusos y que ambos coches aparecen al elegir cualquiera. Probar **Back**, foco y navegación por teclado.
3. Probar los tramos 1 y 10 con ambos coches. Comprobar el ID de sesión, la geometría y la colisión, el coche efectivo, la posición de salida y el rótulo de reglajes.
4. En las tres entradas, comprobar que el panel se abre una vez al cargar y que el coche y la cuenta atrás esperan. Confirmar un ajuste y verificar que el coche lo recibe y que arranca la secuencia normal.
5. En **Rally**, iniciar desde Stage 9 y verificar la transición a Stage 10 y el cierre del evento. Iniciar desde Stage 10 y verificar que el evento acaba allí. En **Single Stage** y **Championship**, comprobar que la especial termina sin transición y que el guardado oficial de Rally queda intacto.
6. Comprobar el comportamiento ante una escena de coche o un recurso de tramo ausente. Verificar que el mensaje identifica el fallo, que se puede retroceder y que no se carga un tramo distinto.
7. Ejecutar las comprobaciones existentes de arranque y transición (`stage_vehicle_start_contract.gd`, `russia_stage_transition_contract.gd` y el modo `-Smoke` del lanzador). Revisar el flujo completo en el cliente gráfico para comprobar foco, legibilidad y apertura de reglajes.
