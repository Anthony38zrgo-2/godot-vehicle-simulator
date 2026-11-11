# Cielo Tropospheric Boxes

El tramo de Rusia usa el mismo sistema de cubemaps en Dreamcast y en modo normal. El reloj del evento determina la fase solar. En competición, el clima local suavizado controla la nubosidad y la niebla. En práctica, los cambios del preset TCA se suavizan durante varios segundos. El campo de pruebas usa un cielo despejado fijo al mediodía.

| Condición | Cubemap |
| --- | --- |
| Despejado | `day_1` |
| Nublado | `cloudy_1` |
| Muy cubierto o con precipitación intensa | `verycloudy_4` |
| Amanecer | `day_2` |
| Atardecer | `dusk_3`, orientado hacia el oeste |
| Noche | `night_2`, atenuado cuando se cubre el cielo |

El shader mezcla dos cubemaps por nubosidad y usa una tercera muestra cuando la mezcla de día y crepúsculo coincide con la de nubosidad. La iluminación del terreno se ajusta en paralelo y el color de la niebla cubre la mitad inferior sin información de Source. Las caras están comprimidas en VRAM, con mipmaps. El controlador carga solo las seis variantes que usa.

El pack es de Hsyenoh05. La carpeta `res://assets/weather/tropospheric/` conserva la licencia, los hashes y 25 variantes completas. `night_1` tiene cuatro caras laterales vacías y se excluye de la conversión. Para regenerar las tiras con Python y Pillow desde la raíz del proyecto:

```powershell
py tools/rally/convert_tropospheric_boxes.py "C:/ruta/tropospheric_boxes_1-2v.zip"
godot --headless --path game --import
```

Los archivos `.png.import` se versionan para que Godot reconozca cada tira como cubemap. Para validar en el tramo:

```powershell
godot --headless --path game --script res://tests/rally/tropospheric_sky_contract.gd
godot --headless --path game --script res://tests/rally/weather_runtime_regression.gd
godot --path game --resolution 1280x720 --script res://tests/rally/tropospheric_sky_contract.gd -- --tropospheric-capture
```

El último comando escribe las capturas en `%TEMP%`. Agrega `--normal` después de `--` para el modo normal, o `--no-tca` para probar la inicialización sin TCA.

## Selección por hora
El catálogo WINDOWS del controlador aplica los rangos de data/weather/mapping-time-of-day.csv conservando los nombres originales. La selección es determinista por evento, tramo y fecha. Cada grupo filtra candidatos por hora; si falta cobertura usa la variante temporalmente más cercana. Amanecer reutiliza day_2 provisionalmente. Los cielos cubiertos sin hora se limitan a 10–17. El crepúsculo de tarde mezcla hacia hora azul entre 18 y 19:30. Se cargan las 25 variantes; esto aumenta memoria respecto al catálogo anterior. Los cambios entre variantes de un grupo son directos y requieren revisión visual; las mezclas por nubosidad y crepúsculo siguen activas.
