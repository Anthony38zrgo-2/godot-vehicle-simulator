# Fulvia de Rally Trophy

El coche predeterminado sigue siendo el Fulvia. El modelo actual sustituye al
PSX inicial y al DFF/TXD de GTA; procede del mismo juego y pipeline del Escort.

```powershell
.\scripts\run_rally.ps1
.\scripts\run_rally.ps1 -ProvingGround
.\scripts\run_rally.ps1 -Smoke
.\scripts\run_rally.ps1 -Vehicle escort
```

## Procedencia y regeneración

Archivo original: `D:/games/rally-throphy/Program Files/JoWooD/Rally Trophy/Data/Cars/car_13.bzf`.
`info.ini` lo identifica como Lancia Fulvia Coupe HF, 1969. No se interpreta toda
su ficha como documentación histórica: declara 1598 cm³, frente a los 1584 cm³
recogidos por la ficha FIA usada para el perfil físico.

Las fuentes y generadores están en
`D:/games/rally-throphy/exports_flatout/lancia-fulvia/`:

1. `prepare_source.py`: extrae BZF, convierte las texturas de daño TGA a PNG y
   exporta `model.BMF` con FlatOutW32BGMTool, instalado junto al juego.
2. `inspect_source.py`: importa FBX con la misma conversión métrica del Escort,
   guardando `source_import.blend` e inventario de mallas y materiales.
3. `interior_components.json`: inventario de componentes conectados del interior
   bajo; permite recuperar los dos asientos y las siete piezas de jaula.
4. `export_runtime.py`: genera chasis, cuatro ruedas, variantes de daño, colisiones
   y manifiesto; guarda `lancia_fulvia_runtime.blend` con texturas empaquetadas.

El respaldo del modelo anterior está en `before_rally_trophy/`, fuera del repositorio.
El juego original no se modifica. Los hashes de origen y artefactos están en el
manifiesto visual; los de los dominios físicos, en `HISTORICAL_PROVENANCE.json`.

## Implementación compartida

Controlador, simulación, cámaras, HUD, audio espacial, daños mecánicos, inventario
 y reparaciones usan los mismos scripts del Escort. Los assets están separados en
`game/assets/rally/lancia_fulvia/` y la física propia en
`game/data/vehicles/lancia-fulvia/`.

La escena usa directamente `rally_escort_visual_damage.gd`. Sus recursos de choque
 y texturas son configurables por vehículo: el Fulvia aporta sus propias formas
`body_crash`, `hood_crash`, `trunk_crash` y el interior con cristales rotos. Comparte
umbrales de impacto, roturas de luces y parabrisas, persistencia y reparación. Se
conservan las formas discretas originales del juego, sin deformación continua.

El interior contiene salpicadero, volante, indicadores, limpiaparabrisas, asientos
 y jaula originales. Piloto y copiloto proceden de `driver1.bzf`, compartido por
ambos coches en Rally Trophy, y se colocan según DriverLoc/CoDriverLoc del Fulvia.
Las manos conservan las 19 poses originales como morph targets. Volante y brazos
usan `RallyCockpitAnimation`; la cabeza del piloto se oculta en primera persona.

CHASE, BONNET y COCKPIT están habilitadas. El ancla interior usa InteriorLoc más
0.10 m de desplazamiento de suspensión, aplicado también a carrocería y asientos.
Hay una sola cubierta interior de techo; se excluyen carrocería/ruedas LOD y
cristales interiores redundantes.

## Geometría y física

Se mantienen las medidas nativas de Rally Trophy. Los centros se miden sobre las
cuatro ruedas de alta resolución y se utilizan tanto en los visuales como en Jolt:

| Medida del modelo Rally Trophy | Metros |
| --- | ---: |
| Batalla | 2.480 |
| Trocha delantera | 1.220 |
| Trocha trasera | 1.220 |
| Radio de neumático | 0.280 |
| Anchura de neumático | 0.200 |

La geometría del juego difiere de la ficha histórica FIA 3006: batalla de 2.330 m y
vías de 1.390/1.350 m. No se presentan las medidas del asset como mediciones de un
Fulvia real. Centros, suspensión, radio, anchura e inercia de ruedas se actualizan
para coincidir con el montaje importado. La colisión se deriva del helper
 decodificado de `model.BMF`, con la misma altura de suspensión que los visuales.

Se conserva la reconstrucción física anterior: V4 de 1584 cm³, curva aproximada
de 160 CV, cinco marchas, diferencial delantero y ayudas desactivadas. Relaciones,
curva de par, inercias, CG y suspensión son estimaciones documentadas. El inventario
inicial suma 945 kg con tripulación y equipo, antes del combustible. Jolt usa un
chasis y cuatro cuerpos no suspendidos de 19 kg, con mínimo de 120 Hz para este
perfil. El solver sigue sin reproducir el acoplamiento real del eje y las ballestas.

## Banco propio FulviaHF

Regenerar desde la raíz:

```powershell
python tools/audio/rally_trophy_fulvia.py
```

`game/sounds/banks/FulviaHF/` contiene 19 WAV:

- Ocho grabaciones originales EE/EX de motor y escape, byte por byte.
- Seis capas de retención filtradas a partir de esas grabaciones.
- Tres transiciones de escape derivadas, sin afirmar que sean detonaciones grabadas.
- Dos tonos de caja genéricos sintetizados, sin presentarlos como sonidos originales.

Los centros de RPM de carga proceden de Sounds.ini; las superposiciones y el
ralentí se adaptan al simulador. No se afirma haber medido las RPM exactas de las
grabaciones. El manifiesto guarda hashes, formato, duración, origen y compensación
RMS. Las muestras originales mantienen su frecuencia y bytes.

`rally_vehicle_audio.gd` selecciona el banco con `engine_bank_manifest_path`.
Comparte mezclador, filtros de cabina, fuentes 3D, superficies e impactos, pero
motor/escape, retención, transiciones y caja usan archivos propios y buses separados.
El silbido sigue el eje delantero. Contacto, cambios y limitador siguen compartidos.
El lanzador valida hashes y el staging Windows incluye ambos bancos y las copias
PCM que necesita el cargador RIFF.

## Comprobaciones

`fulvia_import_contract.gd` verifica perfiles/diferenciales, centros de rueda,
masa, cámaras, ancla de ojo, ocultación de cabeza, volante y brazos, texturas,
cuatro variantes de daño, cristales, reparación/restauración, 19 WAV con hashes y
PCM válidos y mezcla continua entre 1100 y 7600 RPM con tres aperturas de acelerador.
También prueba arranque estable y transición a Stage 2 conservando el coche.

```powershell
& $env:GODOT_BIN --headless --path game --script res://tests/rally/fulvia_import_contract.gd
```

La ejecución gráfica guarda `user://fulvia_import_preview.png` y
`user://fulvia_cockpit_preview.png`. Se comprobaron importación, contrato, smoke
de ambos coches y vistas reales en Godot. Quedan aceptación de manejo prolongada,
escucha subjetiva del banco en pista y comprobación del ejecutable exportado.

La auditoría completa `escort_audio_contract.gd` detecta diez muestras existentes
 distintas de su hash de origen y siete archivos ausentes del banco Escort. Esta
importación no modifica esos WAV ni su manifiesto. Su prueba funcional de conducción
pasa; no se declara aprobada la auditoría de integridad del banco anterior.
