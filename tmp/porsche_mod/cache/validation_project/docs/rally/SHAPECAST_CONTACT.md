# Contacto volumetrico de las ruedas

El Ford usa cuatro nodos ShapeCast3D creados al preparar el vehiculo. Cada forma es un CylinderShape3D con el radio y ancho del manifiesto (0.28 m y 0.20 m), con su eje orientado transversalmente al coche. La direccion, toe y camber actuales orientan cada barrido. Los nodos son consultas; no se agregan cuerpos rigidos ni se duplican fuerzas de contacto con colliders de rueda.

Cada barrido parte del centro neutral desplazado hacia arriba por el recorrido de compresion mas 0.02 m de separacion inicial. Desciende hasta el limite de extension, con margen de consulta de 0.002 m. Se excluye el RID del propio chasis y se usa su mascara de colision. Se selecciona entre los resultados la normal con mayor componente de soporte en el eje vertical del coche (producto escalar mayor a 0.1). Las paredes casi verticales no se usan como soporte de suspension; la interaccion completa de flancos de rueda con paredes sigue fuera de este modelo.

La suspension recibe `radio + longitud_barrido * fraccion_segura - elevacion_inicial`. Asi un punto de contacto desplazado lateralmente no altera artificialmente el recorrido. Se conserva la ley de fuerzas del neumatico y suspension existente; la forma detecta volumen pero no simula por si misma deformacion de goma.

Los nodos tienen enabled=false y se actualizan explicitamente mediante force_shapecast_update en el callback de integracion. Esto evita una actualizacion automatica adicional. El contador representa cuatro barridos de rueda, no el numero interno de consultas realizadas por ShapeCast3D/Jolt para cada barrido.

Frecuencia: project.godot configura 120 physics ticks por segundo. En una ejecucion de Rusia Stage 1 con Godot 4.7.1, el registro RALLY_CONTACT_FREQUENCY acumulo 120 callbacks y mostro dt=0.00833333376795053 s e integration_hz=119.999993741513. Es frecuencia del tiempo de simulacion, no una garantia de FPS ni de coste de CPU en todas las situaciones. Las muestras finales del registro mostraron cuatro ruedas en contacto. No se ha realizado aceptacion de conduccion sobre obstaculos.

Comandos usados para compilar/cargar scripts y comprobar el arranque:

    Godot_v4.7.1-stable_win64_console.exe --headless --path game --editor --quit
    .\scripts\run_rally.ps1 -QuitAfterFrames 300

Log: game/logs/rally/rally_godot_20261029_181518.log.
