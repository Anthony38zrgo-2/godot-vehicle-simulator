# Plan: selector del modelo de ruedas y suspension

Estado: propuesta posterior al commit 9ea2d5f. No implementado.

## Alcance

Dos modos completos: `custom` para el modelo GDScript actual y `jolt_vehicle` para la suspension y friccion de ruedas de JPH::VehicleConstraint. Ambos usan el mismo mundo Jolt, chasis, pista, entradas, masas, aerodinamica, combustible y presentacion. El selector cambia conjuntamente neumaticos y suspension; combinaciones parciales quedan fuera de la primera implementacion.

El proyecto ya usa Jolt para el cuerpo rigido y las consultas. VehicleBody3D/VehicleWheel3D implementan el modelo de vehiculo propio de Godot y no equivalen a JPH::VehicleConstraint. El servidor integrado de Godot 4.7.1 no publica una interfaz de vehiculos ni acceso nativo al PhysicsSystem mediante su API GDScript. Una GDExtension ordinaria no debe presumir acceso a sus cuerpos internos.

## 1. Frontera del modelo

Extraer de vehicle_simulation.gd un contrato de backend: configurar, enlazar/desenlazar chasis, recibir mandos y pares, publicar ruedas, restablecer y liberar. Mantener un adaptador `CustomWheelBackend` para suspension_model.gd, tire_model.gd y el avance angular actual. La coordinacion mantiene motor, caja, embrague, frenos, termica y aerodinamica.

Contrato comun por rueda: contacto/collider, posicion y normal, longitud/compresion de suspension, carga vertical, giro y velocidad angular, direccion, fuerzas/impulsos longitudinal y lateral, par aplicado y energia de frenado/deslizamiento. Publicar secuencia y dt del paso resuelto; convertir impulsos a fuerza con su dt real. Campos no soportados deben indicarse como no disponibles, nunca copiarse del modelo desactivado.

## 2. Acceso nativo al mismo mundo Jolt

Ruta propuesta: modulo C++ compilado con Godot 4.7.1 y la version exacta de Jolt incluida por ese tag. Exponer un nodo/adaptador de vehiculo sobre el RID del RigidBody3D existente. Resolver su cuerpo/espacio bajo las reglas de bloqueo y sincronizacion del servidor. Registrar y retirar VehicleConstraint y su PhysicsStepListener con el ciclo de vida del espacio.

La primera tarea de implementacion es cerrar el enlace RID -> JoltBody3D -> PhysicsSystem y el orden pre/post paso en esa revision. Puede requerir un parche acotado al modulo jolt_physics del motor. No crear un segundo mundo Jolt ni copiar la pista para simularla aparte. No vincular una segunda copia de Jolt contra punteros del motor.

Entregar scripts reproducibles de compilacion, binario de editor y plantillas Windows correspondientes. El lanzador seleccionara el motor con modulo para `jolt_vehicle`; `custom` podra seguir ejecutandose en el editor oficial. No sustituir silenciosamente la instalacion global existente. La exportacion debe usar la plantilla del mismo build y comprobar la disponibilidad del modulo.

## 3. Propiedad de fuerzas y giro

En `jolt_vehicle`, VehicleConstraint posee contactos, soporte vertical, suspension, friccion longitudinal/lateral y velocidad angular de ruedas. Desactivar esas contribuciones del backend custom, manteniendo la colision normal del chasis. Ningun paso puede integrar dos veces una rueda ni aplicar dos veces una fuerza de suspension o reaccion de transmision.

El controlador de ruedas nativo debe aceptar el par por rueda de nuestro tren motriz y las capacidades de frenado por rueda. Evaluar un adaptador derivado del controlador de ruedas de Jolt que conserve su resolucion de friccion, pero sustituya el avance de motor/transmision incorporado por esos pares externos. No ejecutar simultaneamente dos motores, cajas o embragues. Fijar tambien quien aplica el par de reaccion al chasis.

Preparar comandos antes del avance del espacio y publicar resultados despues. Evitar invocar GDScript o modificar nodos desde hilos trabajadores; intercambiar buffers de datos. Documentar cualquier realimentacion diferida un paso del embrague.

## 4. Mapeo del perfil

Usar -Z adelante y +Y arriba explicitamente: Jolt tiene valores por defecto con +Z adelante. Reutilizar el inventario de masa y las dimensiones de ruedas. Transformar anclajes y longitudes al marco local que pide VehicleConstraint; no confundir el centro neutral de rueda con el anclaje superior de suspension.

Mapear recorrido, precarga, rigidez y amortiguacion. Preferir modo de rigidez fisica si esta disponible en la version incluida; si se requieren frecuencia y razon de amortiguamiento, derivarlas de k, c y masa efectiva: f=sqrt(k/m_eff)/(2*pi), zeta=c/(2*sqrt(k*m_eff)). No usar directamente la masa total para cada esquina. Documentar diferencias como bump/rebound separados, topes y geometria dinamica que Jolt no represente de forma equivalente.

Mapear curvas longitudinal/lateral de Jolt con unidades explicitas: slip relativo a velocidad longitudinal y curva lateral en grados en los ajustes del controlador. El modelo custom normaliza slip con max(|v|,|omega*r|,1); convertir o publicar ambas convenciones, sin reutilizar los numeros como si fueran iguales. Friccion de superficie, temperatura, presion y desgaste deben afectar el coeficiente una sola vez.

## 5. Termica y presentacion

Consumir trabajo de frenado y friccion del backend activo. Si la API de Jolt no expone el trabajo realmente aplicado, instrumentar el controlador nativo donde resuelve el freno; no estimarlo con la capacidad maxima cuando el disco esta bloqueado. Conservar los modelos termicos actuales fuera del backend, incluida su realimentacion de fade y grip.

Usar el snapshot comun para HUD, camara, audio, telemetria y mallas de ruedas. Adaptar las lecturas directas de suspension_model/tire_model en el garaje y el vehiculo. Las opciones de configuracion sin equivalente se mostraran como no disponibles en ese modo.

## 6. Selector

Guardar `wheel_physics_backend = custom | jolt_vehicle` en preferencias de sesion y permitir override `run_rally.ps1 -WheelPhysicsBackend Custom|Jolt`. Default inicial: custom. Mostrar el modo activo en garaje y metadatos de registro.

Permitir cambiar desde garaje con la simulacion pausada y el coche detenido. Desenlazar el backend anterior, retirar constraints/listeners, reconstruir el nuevo y restablecerlo en una pose de salida conocida. Preservar configuracion, combustible y temperaturas; reiniciar memorias internas de contacto, impulsos y slip. No prometer transferencia exacta de estado de solver durante una maniobra. Si falta el modulo, explicar el motivo y ofrecer volver a custom; no presentar un fallback silencioso como Jolt.

## Entrega

Orden: cerrar acceso nativo y build -> contrato/adaptador custom -> backend Jolt y mapeo -> termica/snapshot -> selector/garaje/lanzador/exportacion. No crear ni ejecutar tests en este alcance, siguiendo la restriccion del usuario. Las revisiones de codigo, compilacion y calculos se documentaran sin presentarlas como aceptacion de conduccion.

## Fuentes oficiales consultadas

- Godot 4.7.1 JoltPhysicsServer3D: https://github.com/godotengine/godot/blob/4.7.1-stable/modules/jolt_physics/jolt_physics_server_3d.h
- Godot VehicleBody3D implementation: https://github.com/godotengine/godot/blob/4.7.1-stable/scene/3d/physics/vehicle_body_3d.cpp
- Jolt VehicleConstraint: https://github.com/jrouwe/JoltPhysics/blob/master/Jolt/Physics/Vehicle/VehicleConstraint.h
- Jolt WheeledVehicleController: https://github.com/jrouwe/JoltPhysics/blob/master/Jolt/Physics/Vehicle/WheeledVehicleController.h
- Jolt VehicleController and Wheel: https://github.com/jrouwe/JoltPhysics/tree/master/Jolt/Physics/Vehicle

Los headers master de Jolt orientan el diseno; al implementar se deben fijar las firmas y capacidades de la version incorporada en Godot, sin mezclar versiones.
