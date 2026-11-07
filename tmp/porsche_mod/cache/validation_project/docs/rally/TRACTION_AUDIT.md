# Auditoría de tracción del Ford sobre grava

Se repitieron las salidas rectas en primera con el acoplamiento GDScript actualizado y la curva de par del perfil Rust. Los coeficientes del neumático no se modificaron. Cada pedal se midió en una escena nueva, sin cambiar de marcha ni activar TCS; la tabla usa la muestra a los 2.9 s.

Comandos reproducibles:

    & 'D:\Formula90s\.tools\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path game --script res://tests/rally/traction_audit.gd
    & 'D:\Formula90s\.tools\godot\Godot_v4.7.1-stable_win64_console.exe' --headless --path game --script res://tests/rally/traction_audit.gd -- --russia

## Resultado actual

| Escena | Pedal | km/h | Slip interno trasero | Par motriz/rueda | Reacción/rueda |
|---|---:|---:|---:|---:|---:|
| Campo plano | 35% | 20.2 | 6.9% | 334 Nm | 299 Nm |
| Campo plano | 65% | 38.8 | 16.3% | 714 Nm | 633 Nm |
| Campo plano | 100% | 42.7 | 37.4% | 684 Nm | 684 Nm |
| Rusia | 35% | 24.8 | 6.7% | 343 Nm | 306 Nm |
| Rusia | 65% | 42.9 | 16.9% | 728 Nm | 643 Nm |
| Rusia | 100% | 47.8 | 29.2% | 852 Nm | 875 Nm |

El slip reportado es el índice interno (velocidad periférica - velocidad longitudinal) / max(magnitud de ambas, 1 m/s); no es el cociente convencional referido solo a la velocidad de avance. Las seis muestras conservaron cuatro consultas de contacto.

## Cambio de acoplamiento

GDScript ahora usa la reacción longitudinal de los neumáticos del paso anterior al resolver el par del embrague. Integra las RPM libres del motor, la curva de par normalizada del JSON, la rampa positiva de par, el arrastre y freno del motor, el desembrague anti-calado al ralentí, el desembrague durante el cambio, el límite de par del embrague y la inercia del conjunto reflejada en las ruedas motrices. El cálculo sigue rust/vehicle-physics-engine/src/powertrain.rs, incluida la interpolación por tramos de torque_curve; el juego no carga Rust en ejecución.

La inercia reflejada incluye motor y caja en el avance angular de cada rueda motriz. El consumidor activo sigue siendo GDScript y Godot/Jolt conserva la integración del chasis.

## Comparación con la auditoría anterior

| Escena | Pedal | Slip anterior | Slip actual | Velocidad anterior | Velocidad actual |
|---|---:|---:|---:|---:|---:|
| Campo plano | 35% | 7.4% | 6.9% | 18.3 km/h | 20.2 km/h |
| Campo plano | 65% | 29.5% | 16.3% | 42.8 km/h | 38.8 km/h |
| Campo plano | 100% | 36.7% | 37.4% | 43.6 km/h | 42.7 km/h |
| Rusia | 35% | 7.7% | 6.7% | 24.5 km/h | 24.8 km/h |
| Rusia | 65% | 14.1% | 16.9% | 48.0 km/h | 42.9 km/h |
| Rusia | 100% | 27.3% | 29.2% | 48.9 km/h | 47.8 km/h |

El ajuste corrige el exceso de par de la versión anterior: en plano a fondo, el par motriz y la reacción quedan equilibrados en la muestra; en Rusia a fondo, la reacción supera ligeramente el par y la rueda deja de acelerarse. A pedal parcial baja el slip en el campo plano y la salida al 35% recupera velocidad. En Rusia al 65% la velocidad final es menor y el slip es algo mayor; el acoplamiento corregido no hace que todos los puntos de conducción ganen velocidad.

A fondo todavía aparece mucho slip (37.0% interno en plano y 28.6% en Rusia). El tren motriz ya no entrega par sostenido por encima de la reacción disponible en esas muestras; el neumático opera cerca de su límite y conserva bastante fuerza post-pico según el perfil. No debe confundirse ese slip persistente con un sensor de contacto mal calibrado.

## Adecuación y límites del neumático

El perfil usa Gravel.friction=1.08, frente a Road.friction=1.05; el pico longitudinal está en 0.20 de slip y la curva conserva 0.95 de su pico después del deslizamiento máximo. No hay un multiplicador de grava cercano a cero. Es un modelo genérico de fuerza combinada con superficie, carga, presión y temperatura, no una curva medida de un neumático de rally sobre esa grava. No representa hundimiento ni deformación granular, así que no puede certificarse como modelo de competición calibrado.

No se aumentó el grip ni se activó TCS para ocultar el patinamiento. La próxima calibración física requiere una curva neumático-superficie medida y revisar el reparto dinámico de cargas. El run de Rusia escribió sus resultados y finalizó con una advertencia de 26 instancias de escena pendientes (ObjectDB instances were leaked).
