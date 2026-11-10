# Importar coches de Rally Trophy

Desde la raíz del repo, instala las dependencias de Python con
`python -m pip install -r tools/rally_trophy/requirements.txt`. Usa una copia
local de Rally Trophy con los BZF originales, Blender, Godot compatible con
el proyecto y FlatOutW32BGMTool con soporte para exportar BMF a FBX.
No hace falta abrir Blender ni instalar complementos. `doctor` muestra los
ejecutables detectados; puedes fijarlos con `--blender`, `--godot` y `--converter`.

```powershell
python -m tools.rally_trophy doctor --source D:\games\rally-throphy
python -m tools.rally_trophy scan
python -m tools.rally_trophy batch --all --jobs 3 --validate
python -m tools.rally_trophy build --ids rt-lancia-stratos --render
python -m tools.rally_trophy batch --ids rt-mini-cooper-s rt-alpine-a110 --validate --publish
.\scripts\run_rally.ps1 -Vehicle rt-mini-cooper-s
```

Por defecto, la tanda escribe en `build/rally_trophy`. El informe
`REPORT.md` y su equivalente `batch_report.json` recogen los resultados por
coche. Cada entrada remite a sus logs, manifiestos, geometría medida y
evidencia de Godot. Una tanda continúa si falla un coche y devuelve código
distinto de cero si falla alguno. La caché verifica los archivos antes de
reutilizarlos. Usa `--no-resume` para repetir una conversión.

`--validate` carga cada vehículo en una copia de prueba del proyecto.
`--render` también genera capturas para inspección. Revisa el cockpit, manos,
asientos, ruedas, daño, reparación y mezcla de audio en pista antes de dar por
bueno el resultado visual. `--publish` instala únicamente candidatos que
pasaron la validación, en rutas propias, y añade su entrada al registro sin
cambiar el coche por defecto. Reemplazar una importación previa exige
`--replace`. El Fulvia y el Escort existentes conservan sus identificadores.

## Cómo pasarle una tanda a un agente

> Ejecuta doctor y scan. Genera y valida los IDs solicitados con las recetas
> incluidas. Conserva las distancias entre ejes y trochas medidas del modelo
> por defecto. Para cada fallo, adjunta el log y resuelve el caso en su receta
> si es específico del coche. Revisa las capturas y las diferencias entre la
> variante del juego y la ficha FIA. Publica solo los IDs solicitados que
> pasen, e informa de los datos históricos y pruebas de conducción pendientes.

Las 22 recetas corresponden a 11 familias, con una variante de juego mejorada
por familia. `python -m tools.rally_trophy history` devuelve el catálogo
histórico con ficha, variante, notas de discrepancia y datos pendientes.
`scan` da el inventario de la instalación concreta. Las fichas FIA describen
el vehículo homologado: las cifras de masa, cilindrada y potencia dependen de
la variante, el año y las extensiones. Los perfiles generados derivan de los
INI del juego y documentan las estimaciones por separado. La carrocería y la
física usan la misma geometría medida; para escalar de forma uniforme se
requiere una batalla documentada y una receta explícita. El escalado uniforme
no garantiza reproducir ambas trochas.

Los WAV nativos conservan sus bytes. El manifiesto separa las grabaciones
originales de las capas de retención derivadas y el sonido de transmisión
sintetizado. Las herramientas no requieren ni incluyen una copia del juego.

## Ajustar una receta

- `semantic_aliases`: lista de nombres candidatos por pieza original.
- `interior`: selección de componentes de la malla interior de baja resolución;
  el inventario `component_report.json` muestra caras y límites. Solo se
  desactiva la exigencia de asientos separados cuando la malla de origen no
  permite identificarlos de forma fiable, como en el Stratos.
- `body_panels`: piezas con variantes de daño nativas. En el Stratos la
  carrocería es una pieza; el parabrisas conserva su daño independiente.
- `collision_source`: los Escort y Saab carecen del helper esperado en
  `model.BMF`; sus recetas autorizan cascos convexos estimados a partir del
  exterior. Esta aproximación se registra en el manifiesto.
- `physics_overrides`: objetos por archivo de dominio, p. ej.
  `{"powertrain.json":{"powertrain":{"final_drive":4.44}}}`. Documenta
  la preparación concreta y su fuente antes de introducir valores históricos.
- `geometry_policy`: `native` usa la geometría medida, `historical_uniform`
  requiere una batalla documentada; las referencias de variante incierta
  requieren además `allow_related_reference_scaling`.

Si Blender falla antes de exportar, consulta `blender.log` y el informe de
componentes antes de modificar reglas globales. Para una tanda de revisión,
conserva el informe, los manifiestos y las capturas bajo `build/rally_trophy`.
