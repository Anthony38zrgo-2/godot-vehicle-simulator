# Plan de refactorización de la UI de Rally Maniac

## Objetivos

- Dar coherencia a las transiciones de pantalla, las secuencias y la respuesta de los controles en toda la UI.
- Hacer visible en el garaje el inventario completo de neumáticos seleccionado al inicio del rally y permitir reemplazos por rueda individual.
- Dar al apartado de neumáticos el mismo lenguaje visual que la maletera, para que el jugador pueda reconocer qué tiene, dónde está y qué le falta.
- Entregar, después de la refactorización, un informe de problemas de UX/UI detectados en el juego para que el usuario pueda priorizarlos.

## Uso de los addons

| Addon | Responsabilidad | Aplicaciones |
| --- | --- | --- |
| **Simple GUI Transitions** | Mostrar y ocultar raíces estables de pantallas y paneles grandes. | Menús de selección, opciones, garaje, pausa, mapa, taller y capas auxiliares del HUD. |
| **Anima** | Coordinar secuencias en paralelo, en serie o en cascada dentro de una pantalla. | Tarjetas visibles de tramos, grupos del taller y presentación de la clasificación. |
| **AnimUI** | Animar cambios locales de estado. | Foco, hover, pulsación, selección, desplegables y avisos puntuales. |

Simple GUI Transitions documenta restricciones para cambiar su configuración en ejecución y deslizar contenedores. Usar un fundido en la raíz estable y dejar las listas dinámicas dentro. Conservar la navegación, la visibilidad final y el foco en el código del juego. Durante el cambio de pantalla, impedir que las acciones de confirmar o volver se ejecuten dos veces. [Simple GUI Transitions](https://github.com/murikistudio/simple-gui-transitions)

Aplicar Anima a los elementos visibles y ejecutar las cascadas al entrar o cuando exista un cambio de contenido que lo justifique. Cancelar la secuencia si se abandona la pantalla. [Anima para Godot 4](https://anima.ceceppa.me/docs/quickstart/)

AnimUI alterna con cada llamada a `play()`. Combinar primero las señales de hover, foco y selección en el estado visual que corresponda y llamar al addon solo cuando cambie ese estado. Usar `reset_immediate()` al reciclar un control. Confirmar la licencia del archivo distribuido antes de incorporarlo al repositorio. [AnimUI](https://code-main.itch.io/anim-ui)

Asignar cada animación a su propio nodo. Si un `Container` controla la geometría, aplicar escala o desplazamiento a un hijo visual. Probar como punto de partida 80–120 ms para microinteracciones y 140–200 ms para un cambio completo de pantalla. Con movimiento reducido, omitir desplazamientos y cascadas y conservar el mismo orden de foco y la misma respuesta a las acciones.

## Inventario de neumáticos en el garaje

El [garaje actual](../../scripts/rally/rally_garage_panel.gd) muestra un recuento del stock de asistencia, pero prepara el servicio por compuesto y cantidad de repuestos. El [modelo de inventario](../../scripts/rally/rally_tire_inventory.gd) ya identifica cada rueda y dispone de operaciones de movimiento e intercambio. Antes de cambiar la vista, reproducir el problema desde la selección inicial del rally y seguir los IDs por la inicialización, la apertura del garaje y la restauración entre etapas. Así se puede determinar en qué punto se pierde visibilidad o disponibilidad.

### Vista y acciones

1. Mostrar en una vista las **cuatro ruedas montadas**, los **repuestos de la maletera** y el **stock de asistencia**. Identificar la posición de montaje y mostrar por rueda su ID, compuesto y estado, incluido el desgaste disponible, los daños y si es utilizable. Mostrar las plazas vacías, el stock agotado y las acciones bloqueadas con un motivo visible.
2. Reutilizar de la [maletera](../../scripts/rally/rally_pause_inventory.gd) las tarjetas, los indicadores de daño, los estados de selección y la forma de señalar plazas vacías. Mantener la sección de stock de asistencia diferenciada por ubicación e indicar cuándo se puede utilizar según las reglas del evento. Revisar las operaciones que ya expone el [panel de asistencia](../../scripts/rally/rally_service_panel.gd).
3. Permitir seleccionar una rueda disponible por ID y después su posición de montaje. Antes de aplicar, mostrar la rueda entrante, la saliente y el destino de esta última. Habilitar el flujo con ratón, teclado y mando. Si el destino no admite la rueda saliente, explicar el motivo y permitir escoger un destino válido según las reglas del inventario.
4. Preparar los cambios en un borrador. Al cancelar, descartar los cambios de ese borrador. Al aplicar, validar las operaciones y actualizar el inventario y el vehículo como un solo cambio. Una validación fallida debe dejar el estado previo intacto. Reutilizar las operaciones del modelo y respetar los límites de la maletera y del inventario del evento. Conservar IDs, desgaste, daño y ubicación de las ruedas que se mueven.
5. Guardar y restaurar el inventario a través de la persistencia del evento. Comprobar que los cambios se reflejan al volver a abrir el garaje y al pasar al siguiente tramo. Mantener el comportamiento de práctica y las reglas de servicio aplicables a cada modo. [Sesión de rally](../../scripts/rally/rally_russia_stage_session.gd)

Integrar las animaciones cuando funcione el intercambio. Simple GUI Transitions abre el apartado, AnimUI responde al foco y a la selección, y Anima puede presentar los grupos al entrar. La confirmación debe reflejar de inmediato el nuevo inventario.

## Orden de implementación

1. **Compatibilidad y piloto.** Probar versiones fijas de los addons con la compilación del proyecto, que declara Godot 4.7. Verificar la importación, el arranque y el comportamiento con el árbol pausado. Implementar el recorrido **menú principal → selección de tramo → volver** en el menú real, que construye sus pantallas en GDScript. Usar los tres addons y verificar que la selección y el foco se recuperan al volver. [Configuración](../../project.godot) · [Menú](../../scripts/rally/rally_maniac_menu.gd)
2. **Garaje e inventario.** Completar la corrección funcional, validar la persistencia y probar el flujo compartido con maletera y asistencia. Aplicar las animaciones del apartado y revisar también el marco del visor 3D y la ficha técnica del garaje.
3. **Menús restantes y carga.** Extender el patrón a selección de coche, clima y opciones. Conservar el desplazamiento existente del carrusel. Para entrar al tramo, fundir sobre el flujo de carga existente y revelar la sesión cuando esté lista.
4. **Pausa, mapa, taller y resultados.** Animar los cambios de panel. La pausa debe responder de inmediato y sus animaciones deben completar con el árbol pausado. Probar el taller desde pausa y entre etapas. Mostrar el tiempo y las penalizaciones desde el primer instante de resultados, y revelar la clasificación sin retrasar **Continuar**. [Pausa](../../scripts/rally/rally_pause_inventory.gd) · [Taller](../../scripts/rally/rally_service_workshop.gd) · [Resultados](../../scripts/rally/rally_competition_panel.gd)
5. **HUD en carrera.** Cubrir el HUD de rally, el retro y los paneles de fórmula. Actualizar cronómetro, marchas, notas del copiloto y alertas críticas de inmediato. Usar AnimUI en avisos puntuales y Simple GUI Transitions en capas completas que se abren a petición del jugador, como la ayuda de controles. [HUD retro](../../features/retro_hud) · [Notas](../../scripts/rally/cmr2_pacenote_hud.gd) · [HUD de fórmula](../../scripts/rally/formula_hud_panels.gd)
6. **Regresión y revisión UX/UI.** Ejecutar los casos funcionales, hacer una pasada en juego y entregar el informe de hallazgos posterior a la refactorización.

## Verificación y aceptación

| Área | Comprobación |
| --- | --- |
| Navegación | Recorrer con ratón, teclado y mando. Repetir Atrás y Confirmar durante una transición. Verificar una sola ejecución por acción y foco visible al volver. |
| Inventario inicial | Empezar un rally con varios compuestos. Comparar los IDs y las ubicaciones del inventario inicial con el garaje, la maletera y la asistencia. |
| Intercambios | Montar una rueda de la maletera y usar otra de asistencia cuando esté permitido. Confirmar el destino de la saliente y comprobar que se conservan el estado y los IDs. Repetir con maletera llena, stock agotado, rueda inutilizable y servicio bloqueado. |
| Cancelación y persistencia | Cancelar un intercambio, aplicar otro y reabrir el garaje. Pasar al siguiente tramo y volver a cargar el evento para comprobar que se restaura el inventario aplicado. |
| Sesión completa | Ir de menú a resultados con pausa y reanudación en mitad del tramo. Comprobar las dos entradas al taller y el modo de movimiento reducido. |
| Presentación y rendimiento | Revisar legibilidad, foco, recortes y navegación al cambiar el tamaño de ventana. Comparar el tiempo de cuadro con la UI previa en el mismo tramo y durante cambios de pantalla. |

Reutilizar los contratos y las pruebas visuales de menú, clima, garaje, mapa de pausa, taller y resultados. Añadir cobertura al flujo del garaje en modo de inventario de rally si los contratos existentes no cubren el reemplazo desde asistencia, la cancelación o la persistencia. Registrar por separado el resultado de las pruebas automatizadas y lo observado en juego. [Pruebas de rally](../../tests/rally)

## Informe de UX/UI posterior a la refactorización

El agente recorrerá en juego la selección inicial, la carga, la conducción, la pausa, la maletera, el garaje, el taller, los resultados y la asistencia entre etapas. Revisará si el jugador puede saber qué tiene, qué le falta, qué puede usar, por qué se bloquea una acción y qué ocurrirá al confirmar. También observará la visibilidad del foco, la legibilidad en carrera, la coherencia de los controles y las esperas introducidas por las animaciones.

Entregar un informe con una entrada por problema observado. Cada entrada incluirá pantalla y dispositivo de entrada, pasos para reproducirlo, comportamiento observado, impacto para el jugador, prioridad y propuesta de corrección. Añadir evidencia visual cuando ayude a entender el hallazgo. Indicar qué recorridos se pudieron verificar y cuáles quedaron pendientes, para que el usuario pueda decidir qué abordar después.
