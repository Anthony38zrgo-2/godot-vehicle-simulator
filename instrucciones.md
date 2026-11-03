# Reemplazo de VFX del rally con texturas de CMR4

Extraer los DDS de `D:\ASETS\CMR4\Colin McRae Rally 04\Data\Textures\SFXNew.big` y convertirlos a PNG RGBA de forma que conserven su alfa. Guardar los recursos en `game/assets/vfx/cmr4/` y ampliar el manifiesto con los nombres originales y hashes del DDS y del PNG.

- **Salpicaduras y rocío.** Usar `Cr_splsh` y `Rd_splsh` para salpicaduras cerca del punto de contacto, y `Water_1` y `Water_2` para la estela de agua. Emitir desde las ruedas traseras con contacto y carga. Escalar con humedad y velocidad. Mantener la supresión de polvo y humo en mojado.
- **Polvo y humo.** Conservar el reemplazo ya integrado. Usar `Dust_01` para el núcleo, `Dust_02` para la estela y `smoke_01` para ambas capas en deslizamiento sobre asfalto.
- **Chispas y residuos.** Reemplazar los sprites de roces e impactos por `Sprk_sml` y `Sprk_big` para chispas, `Mud_rd1` para barro y `leaf_01` a `leaf_03` para residuos vegetales. Probar mezcla aditiva para que el fondo negro de las chispas desaparezca. Seleccionar el efecto por el material de contacto.
- **Nieve y lluvia.** Usar `Snw_rd0` a `Snw_rd3` para nieve levantada por las ruedas y `SnwFlk_1` para precipitación de nieve. Usar `raindrop` y `R_Fall` para la precipitación de lluvia. Integrar los sprites en el sistema meteorológico existente.

Reutilizar los contactos, emisores y datos de clima del simulador. Evitar emisiones duplicadas al sustituir los efectos. Verificar el contrato de VFX, la inclusión de los recursos en la build de Windows y la apariencia en Godot con GPU en seco, mojado y nieve. Comprobar que el spray cese al perder contacto y que los efectos de las ruedas queden fuera del habitáculo.
