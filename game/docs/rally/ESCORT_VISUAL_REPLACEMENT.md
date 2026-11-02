Estado: se volvió temporalmente al RS2000 para revisar su interior. El Castrol se conserva como variante independiente. Véase [RS2000_REAR_GEOMETRY_AUDIT.md](RS2000_REAR_GEOMETRY_AUDIT.md).

# Reemplazo visual del Escort

La variante `game/scenes/rally/ford_escort_castrol.tscn` ensambla en Godot una carrocería, cuatro ruedas, un piloto animado y un copiloto independiente. El nombre de escena y el identificador físico RS2000 se conservan porque los consumidores del simulador los utilizan; la carpeta visual `ford_escort_rs1600` es la solicitada para esta conversión. No se afirma que el coche Castrol sea una reconstrucción histórica del RS1600.

## Archivos entregados

- `game/assets/rally/ford_escort_rs1600/ford_escort_rs1600.blend`: fuente editable del coche, con dos asientos y ruedas.
- `ford_escort_rs1600.glb`: coche completo independiente para consultar o reutilizar.
- `ford_escort_rs1600_chassis.glb` y cuatro `ford_escort_rs1600_wheel_*.glb`: piezas utilizadas por la escena física.
- `game/assets/rally/drivers/driver_animated.blend` y `.glb`: piloto con 19 muestras de dirección por brazo.
- `game/assets/rally/drivers/co_driver.blend` y `.glb`: copiloto independiente.
- Los manifiestos de ambas carpetas registran archivos, hashes, procedencia y montaje.

Los `.blend` contienen materiales y texturas empaquetadas. Godot carga los GLB; la importación automática de `.blend` está desactivada y los fuentes Blender se excluyen del paquete de ejecución.

## Procedencia y elección de las dos alternativas

`asw-lf-ford-escort-rs-mk2.zip` contiene un coche Assetto Corsa denominado RS1800 Mk2 en sus metadatos y un personaje `copiloto.kn5`. El KN5 principal termina en `__AC_SHADERS_PATCH_KN5ENC_v1__`: su lectura directa produce geometría deformada y texturas de sustitución de 70 bytes. Esa conversión fue descartada; no se presenta como modelo válido. El personaje independiente sí se pudo importar correctamente.

La carrocería utilizada procede de `234649-ford-escort-tun.zip`: se extrajeron los chunks RenderWare DFF y TXD del contenedor `INS_BASE` del archivo `.mmrc`. No se ejecutó el instalador `.exe`. Es el Escort Castrol con dorsal 25 de esa segunda alternativa.

Herramientas auxiliares utilizadas: [DragonFF](https://github.com/Parik27/DragonFF) para DFF/TXD y [KN5 Blender Tools](https://github.com/nazariyKul/kn5-blender-tools) para el personaje. Los commits de las herramientas están registrados en los manifiestos. Sus fuentes se utilizaron desde cachés de construcción, no se añadieron como código de runtime del juego.

## Preparación y ensamblado

Se normalizó el coche al contacto de ruedas existente: batalla 2,41 m, vía 1,28 m y radio visual de 0,28 m. El perfil físico, masas, motor y colisión se conservan; el cambio es visual. Se descartaron del modelo renderizado las mallas de colisión/sombra de GTA, se separó el volante y se corrigió la transparencia de los cristales.

El material de asiento del interior ya contiene geometría a ambos lados. Se separaron `seat_driver` y `seat_co_driver`; la auditoría de sus caras, vértices y límites figura en el manifiesto. No fue necesario duplicar el asiento.

El modelo es de conducción a la derecha. La escena coloca `Chassis/Driver` y `Chassis/CoDriver` mediante nodos distintos, y define `Chassis/CockpitEye` para que la cámara coincida con el puesto real. Ningún GLB de coche contiene a los ocupantes.

Se generó el piloto a partir del personaje suministrado, excluyendo el objeto de notas del copiloto. Sus brazos usan la geometría nueva, con el agarre neutro ajustado al volante. Se transfirieron las deformaciones de las 19 muestras originales mediante cuatro vecinos de superficie y caída de influencia en el hombro. Se mantienen nombres `steer_00` a `steer_18`, neutro 09 e interpolación existente. Es retarget geométrico, no una copia de huesos de topología distinta. El copiloto conserva su pose independiente.

El volante nuevo usa su eje local Y en Godot: corresponde al eje local Z del pivote generado en Blender. La propiedad `steering_wheel_axis` evita que el giro incline el aro. La cámara oculta el casco del piloto durante la vista de cabina, como antes.

## Regeneración y comprobaciones

Scripts de conversión: `D:/open-formula/staging_rally/cars/escort_mk2_replacement/`. `inspect_dff.py` importa los chunks extraídos del segundo paquete, `build_replacement.py` genera coche y personajes, y `audit_final_car.py` registra límites y asientos desde el Blender final. Los archivos originales se conservan en Downloads; el generador usa el área de preparación `build/escort_replacement_source` y los importadores en `build/dragonff` y `build/kn5_importer`.

Comprobaciones realizadas:

- `scripts/run_rally.ps1 -Smoke`: contacto, conducción, dirección y perfil físico.
- `godot --headless --path game --script res://tests/rally/cockpit_contract.gd`: manifiesto activo, ensamblado separado, dos asientos, geometría nueva en los brazos, 19 poses, eje de volante, cámara y controles.
- `godot --path game --rendering-method gl_compatibility --script res://tests/rally/cockpit_contract.gd -- --capture-cockpit`: revisión de neutro y ambos extremos de dirección.
- `replacement_visual_probe.gd`: revisión del exterior y de ambos ocupantes montados en Godot. Las capturas se guardan en `user://escort_replacement_*.png`.

El empaquetado incluye los recursos nuevos y verifica sus hashes. La aceptación de conducción y las preferencias de apariencia siguen siendo una comprobación visual del usuario.
