# Plan de implementación: Ford Rally con físicas en GDScript

## Objetivo

Construir un simulador independiente en esta carpeta. Las ecuaciones del vehículo y sus estados térmicos vivirán en GDScript. Godot/Jolt será el único propietario de la integración del chasis, gravedad y respuesta de colisiones. No habrá puente Rust de física en ejecución.

Referencia de implementación: `D:/open-formula`, especialmente `rust/vehicle-models/src`, su consumidor `rust/rapier-vehicle-world/src` y el perfil `rust/data/vehicles/ford-escort-rs2000`. Tomar las versiones de los archivos realmente presentes, incluidos cambios locales; registrar sus hashes cuando se porten. No confundir un parámetro presente en JSON con uno utilizado por el consumidor.

## Estado actual y estructura

- `game/project.godot`: único proyecto Godot activo; el prototipo inicial se migró bajo `game/`.
- `game/data/vehicles/ford-escort-rs2000/`: perfiles activos de Open Formula separados por dominio.
- `game/assets/rally/`: modelos del Ford y escenario Rusia con sus recursos y manifiestos.
- `game/`: runtime independiente Rally en GDScript/Jolt, con HUD, controles, audio y recursos requeridos. No incluye el addon GEVP heredado.
- `scripts/run_rally.ps1`: lanzador adaptado al proyecto independiente; admite smoke, validación de runtime, campo de pruebas, Rusia y exportación Windows.
- `scripts/stage_rally_windows_export.ps1`: prepara y exporta la selección aislada de dependencias Rally.
- Este repositorio no contiene scripts Python; los recursos derivados se conservan con sus manifiestos y procedencia.

No ejecutar los scripts de staging de referencia sin revisar sus rutas y operaciones de limpieza. No copiar DLL, objetos ni cachés del proyecto de origen para satisfacer artificialmente las comprobaciones del lanzador.

## Secuencia de trabajo

1. Unificar el proyecto bajo `game/`, manteniendo la estructura de Formula90s. Mover el prototipo de raíz con sus referencias y conservar un solo `project.godot` activo. No ejecutar simultáneamente las escenas GEVP de referencia y las fuerzas del nuevo motor.
2. Implementar el cargador de perfiles en GDScript. Mantener archivos JSON separados por sistema, contratos, unidades, rutas relativas, valores por defecto, validaciones y precedencia de filtros del núcleo de referencia. El manifiesto debe resolver los dominios; no dejarlo sin uso ni introducir valores físicos constantes en el controlador.
3. Separar módulos de configuración, masas, suspensión, neumáticos, filtros, motor, embrague, transmisión, diferencial, frenos, aerodinámica, térmicas y combustible. El controlador coordina los dominios y aplica fuerzas; no concentra sus ecuaciones.
4. Resolver masa, centro de masa e inercia del inventario y combustible. Respetar convenciones de ejes y signos. Usar la posición real del centro de masa para velocidades de contacto y momentos.
5. Portar suspensión: compresión y extensión, amortiguación diferenciada, topes progresivos, barras estabilizadoras y cinemática de caída y convergencia aplicables al modelo simplificado. Eliminar las fuerzas provisionales y cargas mínimas artificiales del prototipo.
6. Implementar exactamente un rayo central por rueda y por actualización de contacto. Sin rayos laterales ni sondeos de huella adicionales. Obtener distancia, punto, normal y superficie; excluir el propio coche. Reutilizar ese contacto en subpasos internos y contar las consultas reales. Resolver colisiones de carrocería con formas Jolt separadas.
7. Portar curvas de neumático por eje, sensibilidad a carga, deslizamiento longitudinal y lateral, proyección combinada suavizada, empuje por caída, resistencia a rodadura y par autoalineante. Acoplar fuerza longitudinal y par de reacción a la velocidad angular de rueda con estabilidad a baja velocidad.
8. Mantener activos los filtros configurados: relajación por distancia con tiempo mínimo y recuperación, memoria de pérdida y recuperación de adherencia, rampa de contacto, transición de superficie y migración de picos combinados cuando sean parte del núcleo de referencia. Cada rueda conserva sus estados; avanzar una vez por paso aceptado. No limitarse al filtro parcial presente en el prototipo.
9. Portar curva de motor realmente consumida, inercia, ralentí, limitador, embrague, cambios, relaciones, marcha atrás, diferencial y reacción de transmisión. Portar frenos, reparto, freno de mano y ayudas configuradas. Eliminar el par fijo y el régimen decorativo del prototipo.
10. Portar térmicas del motor: bloque, agua y aceite, generación de calor, intercambio, refrigeración, condiciones iniciales y reducción de par por temperatura según configuración. Portar térmicas de neumático: superficie, banda, carcasa y gas según modelo activo, presión por temperatura absoluta y desgaste. Conectar sus factores a las fuerzas; no dejar temperaturas solamente informativas. Incluir temperatura y pérdida de eficacia de frenos si el modelo la utiliza.
11. Portar aerodinámica y consumo de combustible del modelo simplificado y conectar sus estados. Documentar cualquier dominio deliberadamente no representado; no indicar equivalencia completa si existe una aproximación.
12. Conectar las mallas del Ford a la suspensión y giro calculados, añadir colisiones de chasis, campo de pruebas, escenario Rusia, iluminación y cámara de seguimiento. Reutilizar entrada, fuentes, muestras de audio y HUD de `game/`.
13. Adaptar el contrato de HUD: velocidad, marcha, régimen, pedales, ayudas, combustible, temperaturas reales de motor y cuatro neumáticos. Los datos no disponibles deben mostrarse como ausentes, nunca como temperaturas inventadas. El adaptador actual espera `RallyEscortVehicle`; actualizar sus tipos y acceso al nuevo vehículo.
14. `scripts/run_rally.ps1` ya apunta al proyecto independiente, conserva selección de sesión, registros y comprobaciones; el staging Windows toma solo los recursos requeridos por Rally y no incluye extensiones nativas F1. Mantener ambos scripts sincronizados cuando cambien las dependencias activas.
15. Realizar una comprobación básica de importación, arranque, carga de JSON, mandos, ruedas y evolución térmica. Priorizar que el usuario conduzca pronto; no condicionar la entrega a equivalencia numérica exhaustiva. Documentar el comando exacto y limitaciones observadas. Ajustar con las pruebas al volante del usuario.

## Entrega y control de cambios

Antes de editar, registrar rama, HEAD y estado. Mantener cambios atómicos, añadir rutas explícitas y revisar el diff antes de cada commit. Los commits iniciales son `b4f024d` y `2c2c82c`; solo acreditan el prototipo y sus recursos.

El primer entregable completo será el Ford conducible en campo de pruebas y Rusia, con datos por dominio, filtros activos, térmicas conectadas a las físicas, un rayo central por rueda y HUD funcional, usando un solo mundo Jolt. La aprobación final de conducción corresponde al usuario. Una importación correcta no acredita conducción ni fidelidad física.
