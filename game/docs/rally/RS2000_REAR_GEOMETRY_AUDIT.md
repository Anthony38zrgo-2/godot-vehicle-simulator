# RS2000: revisión del interior trasero

El RS2000 original queda temporalmente activo en `ford_escort_rs2000_1971.tscn`. La conversión Castrol se conserva en `ford_escort_castrol.tscn`, con sus archivos, personajes y montajes independientes.

## Hallazgos

No había dos coches instanciados ni una segunda carrocería física visible. Había una composición del exterior/interior de alta resolución con parches adicionales: `interior_rear_tub`, dos lunas laterales traseras, una luneta y un revestimiento de techo. Los parches de vidrio formaban otra capa, aproximadamente 3–5 cm hacia dentro de las superficies de carrocería en sus distancias medianas, por lo que se veían dos marcos y contornos traseros.

La geometría de la cubeta anterior coincide con el Ford verificado de `car_12.bzf`: 58 de sus 65 vértices coinciden exactamente con `interior_lo`; los restantes corresponden al recorte. No coincide con la extracción anterior del otro donante. Los dos asientos coinciden 26/26 vértices cada uno con el Ford original más 0,1 m en vertical. La cubeta anterior, en cambio, coincidía sin ese desplazamiento. El atlas de textura antiguo y el Ford verificado coinciden en un 98,9% de píxeles RGB; la variación principal es la decoración de la rueda de repuesto. Estos datos no sustentan atribuir esa pieza a otro coche.

El problema visible era la mezcla de representaciones y su ajuste, no otra colisión física. Al ocultar la cubeta, la carrocería existente ya cerraba el compartimento trasero; añadir encima la cubeta de baja resolución superponía una segunda representación.

## Corrección

- Se retiraron la cubeta y las tres capas extra de vidrio trasero.
- Se usa una sola geometría de cristales: los materiales de las ventanas de la carrocería se ven desde ambos lados.
- Se recuperaron únicamente las siete barras de jaula del Ford original, sin suelo/paredes de baja resolución ni otro juego de asientos. Se les aplica el mismo desplazamiento vertical de 0,1 m que a los asientos.
- El revestimiento del techo deriva ahora de la propia carrocería de alta resolución, desplazado 8 mm hacia dentro y visible solo por su cara interior. No usa una segunda forma de techo de otro nivel de detalle.

La fuente regenerada es `D:/open-formula/staging_rally/cars/ra-escort-rs2000/ford_escort_rs2000_1971_rear_clean.blend`. Los generadores y verificadores están en esa carpeta. El GLB y manifiesto anteriores permanecen en `rear_cleanup_before`.

## Verificación

[RS2000_REAR_GEOMETRY_AUDIT.json](RS2000_REAR_GEOMETRY_AUDIT.json) registra que carrocería, capó, maletero, ambos asientos y los ocupantes conservan exactamente sus posiciones y cantidades de triángulos. Las 19 poses de cada brazo conservan sus posiciones originales, con error máximo de vértice de 0 m. El hash de colisión permanece intacto. La separación máxima del revestimiento nuevo respecto a la carrocería es 0,007994 m.

La prueba de cabina valida también la variante Castrol con `-- --castrol-preview`. `rs2000_rear_visual_probe.gd` captura antes/después dentro de Godot en `user://rs2000_rear_*.png`. La revisión visual se realizó desde el interior hacia la luneta y desde fuera por detrás. No equivale a una revisión manual de todos los ángulos durante una conducción completa.
