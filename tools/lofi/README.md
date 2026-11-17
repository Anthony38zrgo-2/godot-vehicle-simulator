# Image2Lofi para GLB

Requiere Python con Pillow. Adapta la reducción Lanczos, la saturación 1.1
y la cuantización de Image2Lofi a texturas embebidas en GLB 2.0. Guarda el PNG
a la resolución reducida y conserva el canal alfa remuestreado. Las texturas
de color usan nearest con mipmaps. Los mapas de datos quedan intactos por
defecto. Los archivos con `_wheel_` en el nombre usan 64 px para el difuso.

Desde la raíz del repositorio, en PowerShell:

    $source = 'game/assets/rally/ford_mustang_1967_289_2v'
    $inputs = (Get-ChildItem $source -Filter '*.glb').FullName
    python tools/lofi/image2lofi_glb.py $inputs --output build/lofi/mustang/psx
    python tools/lofi/image2lofi_glb.py $inputs --output build/lofi/mustang/psx_dither --dither

`--size` controla la dimensión máxima del difuso y `--colors` limita la
paleta RGB. `--ao-size 512` permite evaluar una copia con AO reducido.

Para generar las tres capturas en Blender, ejecuta:

    blender -b --factory-startup --python-exit-code 1 --python tools/lofi/render_mustang.py -- $source build/lofi/mustang

Para repetir la prueba con el barniz moderado:

    python tools/lofi/image2lofi_glb.py $inputs --output build/lofi/mustang/psx_matte --matte-material PalominoSpecial67_Bodymat
    blender -b --factory-startup --python-exit-code 1 --python tools/lofi/render_mustang.py -- $source build/lofi/mustang psx_matte

## AO horneado en el difuso

Requiere también NumPy. Usa el chasis original con AO en UV2 y la variante
`psx_matte` como base para el resto de materiales. Si la auditoría detecta
solapamientos incompatibles, usa el atlas de AO como UV de color en las
primitivas de pintura.

    $name = 'ford_mustang_1967_289_2v_chassis.glb'
    $root = 'build/lofi/mustang'
    python tools/lofi/bake_paint_ao.py "$source/$name" "$root/psx_matte/$name" "$root/psx_ao_bayer32/$name"
    Copy-Item "$root/psx_matte/*wheel*.glb" "$root/psx_ao_bayer32"
    blender -b --factory-startup --python-exit-code 1 --python tools/lofi/render_mustang.py -- $source $root psx_ao_bayer32
