# Agua de Kenya: investigación del 2026-11-10

## Resultado

Las superficies originales del agua están en los BMF y en los GLB instalados. El problema confirmado es su clasificación como alpha cutout: `river1_1` y `river2_1` se exportan con `alphaMode: MASK`, `alphaCutoff: 0.38`. El ajustador de materiales en ejecución vuelve a imponer `TRANSPARENCY_ALPHA_SCISSOR` con ese umbral. El alfa de las texturas originales representa semitransparencia; al convertirlo en descarte binario, desaparece casi toda la superficie.

No se modificaron los assets ni el comportamiento durante esta investigación. Falta validar visualmente una corrección en Godot.

## Evidencia original y límites

- Fuente real verificada: `D:\games\rally-throphy\Program Files\JoWooD\Rally Trophy\Data\Tracks\track2\models.bzf`. Los ocho `stageN.BMF` de la caché de Kenya coinciden byte por byte con los recursos descomprimidos del paquete.
- En esta instalación, track2 es Kenya y track4 es Suecia. La tabla de países del `AGENTS.md` externo contiene esos dos países intercambiados; se contrastaron los materiales originales, sin asumir esa tabla.
- Los límites y cotas del agua están en los vértices y triángulos de los batches con materiales `river1_1` y `river2_1`. No hace falta inventar un plano rectangular ni deducir una altura global del río.
- Los materiales `kenya_river_*`, `jungle_river` y los de carretera describen también lecho y orillas. Existen materiales explícitos `kenya_river_dry_*`: el nombre «river» por sí solo no autoriza a inundar una zona.

Triángulos de las superficies de agua, contados directamente en TRACK del BMF y en los índices del GLB:

| Stage | river1_1 original / GLB | river2_1 original / GLB |
| --- | ---: | ---: |
| 1 | 160 / 160 | 634 / 634 |
| 2 | 0 / 0 | 19605 / 19599 |
| 3 | 316 / 316 | 0 / 0 |
| 4 | 0 / 0 | 0 / 0 |
| 5 | 0 / 0 | 5837 / 5837 |
| 6 | 463 / 463 | 7288 / 7282 |
| 7 | 0 / 0 | 0 / 0 |
| 8 | 0 / 0 | 0 / 0 |

Las diferencias de seis triángulos en 2 y 6 son pequeñas frente a la superficie conservada; no explican su desaparición general. Su causa concreta no se investigó. La ausencia de estos dos materiales en 4, 7 y 8 tampoco prueba por sí sola que todos sus cauces deban estar secos.

## Transparencia

En `track2/textures.bzf`, los TGA originales tienen estos rangos de alfa, confirmados también en las conversiones PNG:

| Textura | Alfa original (0–255) | Píxeles con alfa >= 97 en PNG |
| --- | ---: | ---: |
| river1_1 | 10–117 | 15.86% |
| river2_1 | 10–128 | 0.34% |

El umbral 0.38 equivale a 96.9/255: elimina aproximadamente el 84.14% y el 99.66% de los píxeles, respectivamente, antes de considerar filtrado y mipmaps. Estos porcentajes describen texeles, no una medida exacta del área visible en pantalla.

Aunque el alfa de los colores de vértice del BMF es cero, los dos materiales examinados del GLB de stage1 usan `COLOR_0` VEC3 (RGB), sin canal alfa. No hay evidencia de que el alfa de vértice esté anulando el agua instalada.

## Puntos responsables y corrección propuesta

1. `D:\games\rally-throphy\stage_exporter\tools\stage_builder.py`, `get_or_create_material`: interpreta todo `shader_id == 5` como cutout.
2. `D:\games\rally-throphy\stage_exporter\tools\gltf_postprocessor.py`, `patch_stage_glb`: fuerza MASK/0.38 para esa clasificación.
3. `game/scripts/rally/rally_stage_visual_material_adjuster.gd`: incluye `river1_1` y `river2_1` en `CUTOUT_MATERIAL_NAMES`, y vuelve a forzar alpha scissor en ejecución.

La corrección debe distinguir esos materiales de río de la vegetación, conservar su transparencia gradual en la exportación y en ejecución, y respetar sus triángulos originales como contorno y nivel. Para recuperar movimiento, deben investigarse además las variantes originales `river1_2` y `river2_2`; no se verificó aquí cómo las combina o anima el motor original. Regenerar desde la fuente, actualizar manifiestos y comprobar desde cabina los vados, las orillas y la ordenación de transparencia.
