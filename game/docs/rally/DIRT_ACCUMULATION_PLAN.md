# Plan v3 de acumulación de suciedad

**Estado.** Plan revisado contra el código del simulador. Implementación inicial en el simulador. La aceptación visual en conducción queda pendiente.

## Decisiones de producto

| Aspecto | Alcance |
|---|---|
| Refrigeración | Hasta −30 % de la conductancia del conducto de aire del radiador. En los Porsche 911 y 356B, el efecto térmico de la suciedad se limita a los frenos. |
| Frenos | Hasta −56,25 % de la conductancia convectiva de cada disco, incluido su conducto. El efecto sobre el fade y el desgaste procede del modelo térmico existente. |
| Lavado | Acción de 5 minutos en una ventana oficial de servicio, con tiempo disponible. La lluvia, los charcos, los ríos y la nieve conservan la suciedad acumulada. |
| Imagen | Ruedas y mitad inferior del chasis. Parabrisas, cristales y luces quedan fuera. Referencia estética PS1 y Colin McRae Rally 2.0, con manchas discretas y textura de baja resolución. |
| Ámbito | Coche del jugador. El mismo estado alimenta los gráficos y la refrigeración. |

## 1. Modelo de acumulación

Crear `VehicleDirtModel` en `game/scripts/physics/dirt_model.gd`, con parámetros cargados una vez desde `game/data/dirt/dirt_accumulation.json`. Cada zona mantiene dos valores continuos en [0, 1], uno de polvo y otro de barro. El orden de rueda sigue `WHEEL_KEYS`: delantera izquierda, delantera derecha, trasera izquierda, trasera derecha.

| Zona | Aporte | Consumidores |
|---|---|---|
| `front` | Media de las dos ruedas delanteras | Refrigeración y frontal bajo |
| `wheel[4]` | La rueda correspondiente | Disco, rueda y paso de rueda |
| `sides_low` | Media de las cuatro ruedas | Laterales bajos |
| `rear_low` | Media de ruedas traseras, con refuerzo calibrable a velocidad | Trasera baja |

Para las medias, una rueda sin apoyo aporta cero y el divisor se mantiene fijo. Así, perder contacto reduce el aporte al chasis. Acumular polvo y barro por separado permite ensuciar un coche polvoriento con barro y garantiza que añadir polvo nunca reduzca la obstrucción ya acumulada.

```text
exposición = tasa_base_s⁻¹ × factor_velocidad × factor_slip × factor_carga × dt
polvo = 1 − (1 − polvo) × exp(−exposición × tasa_polvo)
barro = 1 − (1 − barro) × exp(−exposición × tasa_barro)
nivel_visual = 1 − (1 − polvo) × (1 − barro)
fracción_barro_visual = barro / (polvo + barro)  # cero si ambos son cero
obstrucción_frontal = 1 − (1 − 0.60 × polvo_frontal) × (1 − barro_frontal)
obstrucción_disco[i] = 1 − (1 − 0.50 × polvo_rueda[i]) × (1 − barro_rueda[i])
```

- Velocidad horizontal del coche. Como punto de partida, rampa lineal hasta 25 m/s, con una pequeña zona muerta por calibrar. A velocidades mayores el aporte por segundo se mantiene y el aporte por kilómetro disminuye.
- Carga efectiva dividida por la referencia estática de cada rueda, con techo configurable. Usar contacto válido y carga positiva. Limitar `abs(slip_ratio)` antes de multiplicar el aporte. Una rueda en el aire o girando con el coche parado aporta cero.
- API prevista: `step(dt, wheel_inputs, speed)`, `cooler_clog()`, `brake_dirt(i)`, `visual_state()`, `service_clean()`, `snapshot()` y `restore()`. Mantener el estado persistente independiente de la cadencia de la física y de la presentación.

### Superficie y agua

Usar la superficie de la rueda y las condiciones locales que ya recibe la simulación. Priorizar `mud_factor` en `Dirt/Gravel` y usar una transición de saturación como respaldo cuando el proveedor no publique ese dato. Un cero publicado es válido, en particular en grava compacta mojada. Si la capa de adaptación hoy convierte datos ausentes en cero, conservar la distinción al normalizar el contacto. Evitar volver a muestrear el clima desde el modelo.

| Contacto | Tasa relativa de referencia | Transición al barro |
|---|---:|---|
| `Gravel` | 0.30–0.60 según `loose_gravel_coverage` | Transición según `mud_factor` |
| `Dirt` | 0.45 | Transición según `mud_factor` |
| `Sand` | 0.45 | 0 inicialmente |
| `Grass` | 0.08 | Parcial al mojarse, con tope propio |
| `Road` y alias configurados de asfalto | 0.015 seco, hasta 0.03 mojado | 0 |
| `SnowDeep`, superficie desconocida y contacto inválido | 0 | 0 |

En suelo terroso, repartir la tasa entre `tasa_polvo = tasa_seca × (1 − m)` y `tasa_barro = tasa_húmeda × m`, con `m` en [0, 1] y tasa húmeda máxima de 1.00. El agua de fondo permite modular el asfalto mojado. La profundidad adicional de charco o río no convierte por sí sola su superficie en barro. El generador Rust ya reduce el barro por nieve en sus muestras. Si el respaldo usa saturación o existe un parche local que no entra en esas muestras, reducir el aporte del sustrato según esa cobertura sin contar dos veces la misma nieve.

### Calibración inicial reproducible

Partir de **0.005 s⁻¹** a 25 m/s, con carga estática, slip cero y sin refuerzo trasero. A 10 km (400 s), el modelo da estos niveles por zona bajo condiciones uniformes. Son referencias matemáticas para el primer ajuste.

| Superficie | Nivel a 10 km |
|---|---:|
| Barro pleno | 86 % |
| Grava fina | 70 % |
| Grava compacta | 45 % |
| Asfalto seco / mojado | 3 % / 6 % |

Registrar además el resultado en 10 km con trazas reales de velocidad, cargas y superficies mixtas. Ajustar la tasa y los umbrales por separado. La primera gobierna la mecánica y los segundos, la visibilidad.

## 2. Integración física y térmica

En [vehicle_simulation.gd](../../scripts/physics/vehicle_simulation.gd), integrar una vez por tick externo, después de que la suspensión publique `wheel_loads` y `wheel_slips` y antes de las actualizaciones térmicas. Para ese punto ya existen `last_local_conditions` y las superficies por rueda. Usar `set_dirt_factors(cooler_clog, brake_dirt)` en [thermal_model.gd](../../scripts/physics/thermal_model.gd), con cero como valor inicial y cuatro factores de freno en el mismo orden de ruedas. Conservar las cadencias actuales de frenos/neumáticos (30 Hz) y motor (20 Hz).

La sesión habilita acumulación desde el inicio válido del tramo hasta meta o retiro, también en práctica y tramo suelto. Vincularlo a la transición que abre y cierra el intento. Contemplar el tick de rescate, la cuenta atrás, la pausa y las pantallas congeladas. Después de restaurar o lavar, publicar los factores térmicos y el estado visual de inmediato, aunque el coche siga detenido.

- **Radiador.** Aplicar `(base + conductancia_ducto × (1 − 0.30 × obstrucción)) × factor_daño`. El término base se conserva frente a suciedad. A velocidad cero, el conducto calculado por `_cooling_duct()` aporta cero.
- **Frenos.** Aplicar `1 − 0.5625 × obstrucción_disco[i]` a la conductancia que suma convección natural/forzada y conducto. Radiación y carga solar conservan su formulación. La prueba del 56,25 % se hace sobre conductancia a iguales condiciones de entrada, y el ensayo de frenado mide temperatura, fade y desgaste.
- **Porsche 911 y 356B.** La suciedad solo afecta térmicamente a los frenos. Se conserva la acumulación visual en chasis y ruedas.

## 3. Presentación PS1

El código GT2 y [Dreamcast](../../shaders/dreamcast_vehicle.gdshader) tiene transformaciones de vértice distintas. Probar primero una **máscara integrada en los materiales base**, con la lógica común en un `.gdshaderinc`. Mantener el tratamiento de color e iluminación de cada preset y atenuar el reflejo solo en los píxeles cubiertos. Esta vía evita una segunda pasada coplanar y permite excluir superficies del mismo mesh, como cristal o luces.

Si ambos presets no admiten esa integración con cambios acotados, comparar con `material_overlay` sobre mallas elegibles. Esa vía exige reproducir el cálculo de `POSITION` y los parámetros de cada preset, respetar los overlays existentes y medir coste y parpadeo en movimiento. Validar cada opción con el renderizador Mobile de `project.godot`.

- Cinco estados por zona. Umbrales iniciales de transición en **0.02, 0.25, 0.50 y 0.85**. La última etapa se alcanza en un tramo de barro de referencia sin esperar que el nivel exponencial llegue exactamente a 1. Usar máscaras anidadas para que una etapa nueva conserve las manchas de las anteriores.
- Textura de máscara de 32×32 o 64×64, muestreo nearest, bordes binarios y paleta de pocos tonos. En GT2, aprovechar su dithering y cuantización RGB555. Usar el espacio local de la rueda para que la mancha gire con ella.
- Calcular altura y posiciones de pasos de rueda en un espacio común del coche, usando el AABB del chasis limpio en reposo. Convertir las posiciones desde cada malla a ese espacio y conservar la referencia con variantes dañadas. La mitad superior y el parabrisas tienen máscara cero. Aplicar variación dentada por debajo de ese límite y separar frontal, laterales, trasera y pasos de rueda.
- Usar una paleta base de polvo y otra de barro. Cuantizar también la mezcla de colores y actualizar parámetros al cambiar una etapa, un escalón de color o una malla. Los tintes regionales se pueden calibrar después. Elegirlos por evento para evitar recolorear suciedad ya acumulada al cruzar sectores.
- Enlazar mallas de carrocería, ruedas y variantes sanas/dañadas desde la ruta de presentación. [rally_escort_visual_damage.gd](../../scripts/rally/rally_escort_visual_damage.gd) alterna visibilidad y reemplaza materiales de superficie en daño, reparación y luces. El enlace debe sobrevivir a esas rutas, al cockpit y al cambio de preset. Usar parámetros por instancia donde los admita el material. Si se usan materiales duplicados, conservar el aislamiento por vehículo y por rueda.
- Tomar como presupuesto inicial **cero pasadas extra** con máscara integrada y medir el coste de fragmentos frente al coche limpio. Para el prototipo con overlay, registrar las llamadas de dibujo adicionales en ambos presets antes de aceptar esa ruta.

## 4. Persistencia, servicio y diagnóstico

### Ciclo de vida

Usar un bloque opcional `dirt` con versión propia en `vehicle_damage_state`. [rally_escort_vehicle.gd](../../scripts/rally/rally_escort_vehicle.gd) expone el snapshot y la restauración, [rally_russia_stage_session.gd](../../scripts/rally/rally_russia_stage_session.gd) los transporta al cerrar el tramo y cargar el coche, y [rally_event_manager.gd](../../scripts/rally/rally_event_manager.gd) mantiene el guardado del evento. Guardar canales continuos. Derivar etapas, paletas y factores al restaurar.

| Situación | Comportamiento propuesto |
|---|---|
| Nuevo evento o sesión independiente | Arranca limpio. Una partida anterior sin el bloque `dirt` también arranca limpia. |
| Rescate, reinicio físico o preparación de otro tramo | Conserva el estado. Esto incluye el reintento dentro de la misma sesión de práctica. |
| Transición y reanudación de evento | Restaura los valores guardados antes de conducir. Usar los puntos de guardado existentes. |
| Datos incompletos o inválidos | Validar versión, tipo, finitud y cuatro ruedas. Usar cero para entradas ausentes o inválidas sin impedir cargar el resto del evento. |
| Cambio de llantas/neumáticos, reparación o kit rápido | Conserva los canales por esquina del coche. El freno y el paso de rueda pertenecen a esa esquina. |
| Lavado confirmado | Reinicia todos los canales y actualiza presentación, factores térmicos y snapshot. |

### Lavado de 5 minutos

Implementar la acción en [rally_service_panel.gd](../../scripts/rally/rally_service_panel.gd), que gestiona la ventana oficial con minutos, penalización y guardado. El taller rápido usa otras reglas y no tiene ese presupuesto. Mostrar el lavado como acción de coste fijo. `_add_row()` calcula minutos a partir del porcentaje de daño, por lo que registrar solo un coste base de 5 ahí daría un precio variable.

- Seleccionar **LAVADO** reserva 5 minutos. Habilitarlo cuando exista suciedad y el total de la selección, incluido el lavado, quepa en la ventana. Al modificar otras selecciones, actualizar su disponibilidad y volver a validar antes de mutar el estado. Las reparaciones solas conservan su política actual de exceso con penalización.
- Confirmar una sola vez por ventana. Persistir juntos el estado de coche resultante, la penalización si corresponde y la asistencia a la ventana. `RallyEventManager.save()` devuelve un booleano. Si falla el guardado, permanecer en la pantalla con la operación restaurada o preparada para reintento sin aplicar las acciones dos veces. Definir y probar esa ruta antes de habilitar el botón.
- Lavar solo modifica el estado de suciedad. Temperaturas y daños que el coche ya sufrió se conservan. Las reparaciones seleccionadas se aplican por su camino habitual.

### Telemetría

Añadir un bloque de suciedad con cobertura por zona y factores efectivos `dirt_cooler` / `dirt_brakes[4]` al snapshot de diagnóstico. Durante la calibración, registrar superficie, velocidad y carga de la rueda en los probes. En el servicio, mostrar el coste fijo y la disponibilidad del lavado. Evaluar el indicador permanente del HUD después de verificar en conducción que aporta una decisión al jugador.

## 5. Verificación y orden de entrega

| Fase | Entrega | Verificación para avanzar |
|---|---|---|
| 1 | Modelo, configuración y conexión al tick | Contrato reproducible de 10 km con los cuatro casos de referencia. Orden de tasas, equivalencia aproximada a 60/120 Hz y asimetría izquierda/derecha. Reposo, contacto en el aire, charco, río, nieve, rescate y final de intento. Acumulación monótona y etapa final alcanzable. |
| 2 | Ciclo de vida y servicio | Tramo A → servicio → tramo B con y sin lavado. Reabrir guardado en ambos casos. Probar guardados previos, un total de exactamente 5 min disponibles, 4 min disponibles, selección duplicada y fallo de guardado seguido de reintento. Ejercitar reinicio físico, reparación y cambio de ruedas. |
| 3 | Radiador y frenos | Con obstrucción 1, conducto de agua al 70 % y convección de cada disco al 43,75 %. Combinar con daño de radiador, verificar disco limpio del lado opuesto y comprobar efectos en frenadas repetidas. Comparar contra la línea base limpia. |
| 4 | Porsche | Confirmar factor de radiador cero y penalización por disco sucio en los dos perfiles. |
| 5 | Presentación GT2 y Dreamcast | Capturas de estados 0–4 y secuencia en movimiento. Revisar mitad superior, cristales, ruedas girando, daño y reparación, cockpit, cambio de preset y aislamiento entre dos coches. Medir frame time y llamadas de dibujo contra el coche limpio en Mobile. |

Usar como regresiones los contratos de clima, daño, taller, estrategia de neumáticos y gráficos que ya existen en `game/tests/rally/`. Reservar la aceptación en juego para tres pasadas comparables de asfalto, grava y barro, con una parada de servicio y observación desde cámara de persecución. La revisión visual en conducción y el ajuste con trazas reales quedan pendientes.
