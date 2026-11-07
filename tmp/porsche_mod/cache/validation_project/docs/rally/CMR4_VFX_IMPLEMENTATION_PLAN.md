# Plan de implementación — VFX del rally con texturas de CMR 04

Fecha: 2026-11-03. Estado: **Fases 1–5 completadas** (extracción/manifiesto, agua y nieve de rueda,
impactos, precipitación CMR4, contratos y validación visual con GPU); queda la Fase 6
(build/documentación).
Requisitos: `instrucciones.md`. Base: HEAD `822ffc7` más los cambios locales ya presentes en
`game/scripts/rally/rally_vehicle_vfx.gd`, `game/docs/rally/VFX.md` y `game/assets/vfx/cmr4/`
(`dust_01.png`, `dust_02.png`, `smoke_01.png` y `manifest.json`).

## 1. Resultado esperado

Sustituir los sprites de partículas del rally por los recortes originales de Colin McRae Rally 04
contenidos en `SFXNew.big`, conservando su alfa y su mezcla, sin duplicar emisiones y sin cambiar
la física de contacto:

- **Agua:** salpicaduras de contacto (`Cr_splsh`, `Rd_splsh`) y estela (`Water_1`, `Water_2`) en las
  ruedas traseras, gobernadas por humedad, velocidad, contacto y carga.
- **Polvo y humo:** mantener `Dust_01` (núcleo), `Dust_02` (estela) y `smoke_01` (asfalto) ya
  integrados, sin regresiones en seco.
- **Impactos y residuos:** chispas aditivas (`Sprk_sml`, `Sprk_big`) con el fondo negro eliminado,
  barro (`Mud_rd1`) y hojas (`leaf_01`…`leaf_03`) elegidos por el material del contacto.
- **Nieve y lluvia:** nieve levantada por las ruedas (`Snw_rd0`…`Snw_rd3`) y copo de precipitación
  (`SnwFlk_1`); lluvia con `raindrop` y `R_Fall` integrada en el adaptador meteorológico existente.
- Manifiesto reproducible con nombre original, SHA-256 del DDS y del PNG, formato y alfa.
- Contratos headless, captura visual con GPU en seco/mojado/nieve y verificación de la build de
  Windows.

## 2. Hechos verificados de la base

### 2.1 Formato y contenido de `SFXNew.big`

Archivo comprobado: `D:\ASETS\CMR4\Colin McRae Rally 04\Data\Textures\SFXNew.big`
(604 160 bytes, SHA-256 `9508cde4…d22c8a`, el mismo que ya registra el manifiesto actual).

- Firma `BIGF`; `count` y `data_offset` en `u32` little-endian en el offset 4 (`count = 62`,
  `data_offset = 2048`).
- Tabla de entradas en `0x24`, stride `0x18`: nombre ASCII de 16 bytes, tamaño `u32`, offset
  relativo `u32` (absoluto = `data_offset + relativo`).
- Los 62 recursos son DDS **sin cifrar** (`DDS ` en el primer byte de cada entrada), DXT1 o DXT5,
  con cadena de mips incluida. Es un archivo distinto del formato BIG cifrado de sonido que usa
  `tools/audio/cmr4_surfaces.py`.
- `Dust_01.dds` y `Dust_02.dds` son **byte a byte idénticos** (mismo SHA-256). El manifiesto debe
  conservar ambos nombres y dejarlo anotado.
- `Sprk_sml.dds` (16×16) y `Sprk_big.dds` (64×64) son **opacos** (alfa 255 en todo el mapa) con
  fondo negro: sin mezcla aditiva se vería el recuadro negro.

### 2.2 Sprites objetivo

| Entrada | Índice | Tamaño | Formato | Alfa (mín–máx; píxeles con alfa > 0) | Mezcla | Uso |
| --- | ---: | --- | --- | --- | --- | --- |
| `Cr_splsh.dds` | 29 | 64×64 | DXT5 | 0–229, 95,9 % | alpha | salpicadura en firme suelto |
| `Rd_splsh.dds` | 30 | 64×64 | DXT5 | 0–255, 74,8 % | alpha | salpicadura en asfalto/pista |
| `Water_1.dds` | 20 | 128×128 | DXT5 | 0–255, 75,0 % | alpha | estela de agua, núcleo |
| `Water_2.dds` | 60 | 128×128 | DXT5 | 0–198, 73,3 % | alpha | estela de agua, bruma |
| `Dust_01.dds` | 18 | 128×128 | DXT5 | 0–252, 77,0 % | alpha | polvo, núcleo (ya integrado) |
| `Dust_02.dds` | 19 | 128×128 | DXT5 | 0–252, 77,0 % | alpha | polvo, estela (ya integrado) |
| `smoke_01.dds` | 17 | 128×128 | DXT5 | 0–225, 99,5 % | alpha | humo de asfalto (ya integrado) |
| `Sprk_sml.dds` | 7 | 16×16 | DXT5 | 255 en todo el mapa | **aditiva** | chispa pequeña / roce |
| `Sprk_big.dds` | 8 | 64×64 | DXT1 | 255 en todo el mapa | **aditiva** | chispa grande / impacto duro |
| `Mud_rd1.dds` | 13 | 16×16 | DXT5 | 0–255, 72,3 % | alpha | barro |
| `leaf_01.dds` | 14 | 32×32 | DXT5 | 0–255, 64,8 % | alpha | residuo vegetal 1 |
| `leaf_02.dds` | 15 | 32×32 | DXT5 | 0–255, 22,9 % | alpha | residuo vegetal 2 |
| `leaf_03.dds` | 16 | 32×32 | DXT5 | 0–255, 21,1 % | alpha | residuo vegetal 3 |
| `Snw_rd0.dds` | 9 | 128×128 | DXT5 | 0–255, 8,6 % | alpha | nieve de rueda, variante 0 |
| `Snw_rd1.dds` | 10 | 128×128 | DXT5 | 0–255, 5,2 % | alpha | nieve de rueda, variante 1 |
| `Snw_rd2.dds` | 11 | 128×128 | DXT5 | 0–255, 2,5 % | alpha | nieve de rueda, variante 2 |
| `Snw_rd3.dds` | 12 | 128×128 | DXT5 | 0–255, 1,2 % | alpha | nieve de rueda, variante 3 |
| `SnwFlk_1.dds` | 32 | 16×16 | DXT5 | 0–247, 82,8 % | alpha | precipitación de nieve |
| `raindrop.dds` | 31 | 32×32 | DXT5 | 0–249, 28,3 % | alpha | lluvia cercana (gota) |
| `R_Fall.dds` | 55 | 64×64 | DXT5 | 0–255, 15,5 % | alpha | cortina/estela de lluvia |

Los DDS de los sprites alfa conservan un canal alfa útil; solo las chispas carecen de alfa real y
por eso se resuelven con aditivo, no recortando el negro. Varios DXT5 (`smoke_01`, `Dust_01`,
`Dust_02`, `Water_1`, `Water_2` y `R_Fall`) no activan `DDPF_ALPHAPIXELS` en la cabecera aunque el
bloque alfa contiene datos: el manifiesto lo registra en `dds_alpha_flag` y el PNG conserva el alfa
decodificado.

### 2.3 Runtime actual

- `game/scripts/rally/rally_vehicle_vfx.gd`: un `Node3D` por coche (escena Ford compartida), cuatro
  emisores por rueda (`wheel_cores`, `wheel_plumes`, `wheel_chips`), seis slots de impacto, vapor
  del radiador y exclusión de carrocería en el shader. Solo emiten las ruedas traseras (índices
  2 y 3) con `wheel_loads >= 60 N` y `wheel_contact_casts[index].is_colliding()`.
- `game/scripts/rally/rally_vehicle_vfx.gdshader`: billboard, `world_to_vehicle` y caja de
  exclusión alrededor del chasis. Todos los emisores de rueda usan `body_exclusion_strength = 1`.
- `update_wheel()` calcula `speed`, `slip`, `tread_speed`, `dust` y `debris`; la humedad llega de
  `RallyTerrainWetness.wetness` (búsqueda cacheada con `find_child`). El polvo/humo se atenúa con
  `(1 - 0.9 * wetness)`.
- `update_impacts()` usa `vehicle.body_contact_vfx` (posición, normal, impulso, velocidad de
  cierre, tangencial, superficie y nombre del colisionador) y una única textura Brackeys
  (`dirt_02_a.png` o `trace_01_a.png`).
- `game/scripts/rally/rally_weather_controller.gd::apply_to_adapters()` crea una sola
  `GPUParticles3D` por tipo de precipitación a partir de
  `game/data/weather/rally_weather_presets.json::precipitation_adapter`. La lluvia usa
  `RibbonTrailMesh` con `rally_rain.gdshader`; la nieve usa `QuadMesh` con un degradado
  `GradientTexture2D` y `StandardMaterial3D`. El tipo se sustituye al cambiar
  `calendar_particle_kind` (no se suman dos sistemas).
- `game/scripts/physics/vehicle_simulation.gd` ya calcula por rueda `local_water`, `local_snow`,
  `local_ground` y `local_air` en el bucle de contacto, pero **no** los guarda: `last_local_conditions`
  solo se llena desde `local_conditions_for_wheel()`, que hoy no tiene consumidores.
- `game/assets/rally/russia_stage1/russia_stage1_collision.glb` agrupa el contacto en
  `Collision_Barriers`, `Collision_Buildings`, `Collision_Props`, `Collision_Road`,
  `Collision_Terrain_Dirt`, `Collision_Terrain_Grass` y `Collision_Tree_trunks`; los grupos de
  superficie del juego son `Gravel`, `Grass`, `Dirt`, `Sand`, `Road` y `Asphalt`.
- Superficies reales de neumático en `tires.json`: `Curb`, `Dirt`, `Grass`, `Gravel`, `Road`,
  `Sand`. No existe una superficie «Snow»: la nieve se detecta por la profundidad de nieve del
  clima, no por el grupo del colisionador.

### 2.4 Empaquetado y verificación disponibles

- `scripts/stage_rally_windows_export.ps1` copia `game/assets/vfx` completo al proyecto aislado y
  el preset exporta `all_resources` incluyendo `*.json`; no hace falta tocar el staging para
  añadir PNG o el manifiesto, pero sí verificarlo.
- La build de export usa `gl_compatibility`; el proyecto de desarrollo usa `forward_plus`. La
  apariencia debe validarse con GPU en Forward+ y confirmarse en el ejecutable exportado.
- `.gitignore` ignora `*.import` y `*.uid`; los `.import` de los PNG nuevos se regeneran en local
  y en la build, no se versionan (salvo que se decida fijarlos como excepción).
- Contratos existentes: `game/tests/rally/vehicle_vfx_contract.gd`,
  `game/tests/rally/weather_runtime_regression.gd`, `game/tests/rally/dynamic_weather_tires_contract.gd`
  y la sonda visual `game/tests/rally/weather_visual_probe.gd`.

## 3. Decisiones de diseño

### D1. Extracción reproducible, runtime sin dependencias externas

Un script Python (`tools/rally/extract_cmr4_vfx.py`) lee el BIG, extrae únicamente las 20 entradas
objetivo, decodifica el nivel 0 de mip con Pillow (DXT1/DXT5), escribe PNG RGBA y actualiza
`game/assets/vfx/cmr4/manifest.json`. El runtime solo carga PNG del repositorio; nunca abre el BIG
ni `cmr4.exe`. La build de Windows no requiere la instalación de CMR4.

### D2. El manifiesto es el contrato de procedencia

Se conservan las claves actuales (`source`, `archive_sha256`, `assets[].entry`,
`assets[].dds_sha256`, `assets[].png_sha256`) y se amplían con índice de entrada, tamaño,
formato DDS, dimensiones, mips, estadísticas de alfa, tipo de mezcla y datos del generador.
Un desajuste de cualquier hash debe hacer fallar `--verify-only` y el contrato headless.

### D3. Enrutado de sprites por régimen, sin solapes

Cada rueda trasera se evalúa en un único régimen por paso de física:

| Régimen | Condición | Emisores activos | Emisores apagados |
| --- | --- | --- | --- |
| Nieve | `snow_mm >= 0.25` | `wheel_snow` (Snw_rd0…3) | polvo, humo, agua, chips |
| Mojado | `wetness > 0.03` | `wheel_splash`, `wheel_water`, `wheel_mist` | polvo y humo atenuados; chips reducidos |
| Seco | resto | polvo/estela/humo/chips actuales | agua y nieve |

El régimen de nieve tiene prioridad sobre el mojado. Nunca se enciende simultáneamente el sprite
viejo y el nuevo del mismo efecto. Los impactos usan **un** slot y **una** textura por evento.

### D4. Mezcla aditiva solo para las chispas

`Sprk_sml` y `Sprk_big` se dibujan con un shader propio `blend_add` y `depth_draw_never`; el negro
del bitmap no aporta color. El resto usa el shader alfa actual con exclusión de carrocería. La
prueba visual debe confirmar que no queda ningún recuadro negro sobre asfalto ni sobre hierba.

### D5. Precipitación dentro del adaptador existente

No se crea un segundo sistema de clima. En `apply_to_adapters()`:

- **Lluvia:** cada partícula usa `raindrop` (una gota por partícula, como un copo de nieve). `R_Fall`
  es una lámina con ~20 estelas en un solo bitmap y, usada por partícula, agrupaba varias gotas en
  una zona; por eso solo se usa en una capa hija `RainFallSheet` de baja densidad (140 quads de 5 m,
  opacidad 0,10) como cortina lejana. Se desactiva el `RibbonTrailMesh`.
- **Nieve:** se sustituye el degradado por `SnwFlk_1` en un `ShaderMaterial` de sprite con la misma
  opacidad y desvanecido por distancia.
- Se conservan `amount_ratio`, dirección por viento, `global_position` y la liberación del sistema
  anterior al cambiar `precipitation_kind`; la capa `R_Fall` sincroniza su intensidad con la lluvia.

### D6. La nieve de rueda se lee por rueda, sin consultas nuevas

Se escribe `last_local_conditions[i]` en el bucle de contacto de `vehicle_simulation.gd` con los
valores `local_water`, `local_snow`, `local_ground` y `local_air` que ya se calculan. Es una
escritura de estado, no una consulta adicional. El VFX lee `snow_mm` de ahí; la humedad sigue
viniendo de `RallyTerrainWetness` para no duplicar fuentes. Si el clima no está activo, el valor es
cero y el régimen de nieve no se activa.

### D7. Presupuesto y exclusión

Se añaden tres emisores por rueda trasera (salpicadura, agua, bruma) y uno de nieve; se mantienen
los cuatro arrays de tamaño 4 para conservar la estructura y las pruebas, pero los delanteros se
apagan siempre. La caja de exclusión de carrocería se mantiene en todos los emisores de rueda y se
verifica desde cámara de persecución y de capó.

## 4. Fases de implementación

### Fase 1 — Herramienta de extracción y manifiesto

Archivos:

- Nuevo `tools/rally/extract_cmr4_vfx.py` (Python 3, Pillow).
- `game/assets/vfx/cmr4/*.png` (20 archivos) y `game/assets/vfx/cmr4/manifest.json`.

Interfaz:

```text
python tools/rally/extract_cmr4_vfx.py [--source-root RUTA] [--verify-only] [--force]
```

Comportamiento:

1. Resolver `Data/Textures/SFXNew.big` desde `--source-root`, `CMR4_ROOT` o el valor por defecto
   `D:\ASETS\CMR4\Colin McRae Rally 04`.
2. Validar `BIGF`, límites de tabla y de cada entrada; comprobar que las 20 entradas existen.
3. Decodificar el nivel 0 del DDS con Pillow y convertir a RGBA sin premultiplicar ni modificar
   los píxeles. Para DXT1 sin alfa, escribir alfa 255 y anotarlo.
4. Escribir `snake_case.png` (`Cr_splsh` → `cr_splsh.png`, `SnwFlk_1` → `snwflk_1.png`, etc.).
   Si el PNG existente ya tiene los mismos píxeles, conservarlo para no cambiar su hash; con
   `--force`, reescribirlo.
5. Verificar la ida y vuelta: releer el PNG, comprobar que sus píxeles coinciden con el DDS
   decodificado y que el canal alfa no se ha perdido en los sprites que lo tienen.
6. Calcular SHA-256 del DDS y del PNG; escribir el manifiesto con orden estable, indentación de 2
   espacios, saltos LF y salto final. `--verify-only` no escribe: compara y sale con código 1 si hay
   cualquier deriva.

Esquema del manifiesto (las claves antiguas se conservan):

```json
{
  "source": "Colin McRae Rally 04/Data/Textures/SFXNew.big",
  "archive_sha256": "9508cde4198674ff23766d71ddb7b7fe7ca1ae204951c3c8ef552df1bfd22c8a",
  "archive_format": {
    "signature": "BIGF",
    "entry_count": 62,
    "entry_table_offset": 36,
    "entry_size_bytes": 24,
    "data_offset": 2048,
    "dds_formats": ["DXT1", "DXT5"]
  },
  "generator": {
    "tool": "tools/rally/extract_cmr4_vfx.py",
    "version": 1,
    "decoder": "Pillow 12.3.0",
    "png_mode": "RGBA",
    "mip_level": 0,
    "deterministic": true
  },
  "assets": {
    "cr_splsh.png": {
      "entry": "Cr_splsh.dds",
      "entry_index": 29,
      "dds_size_bytes": 5584,
      "dds_sha256": "…",
      "dds_format": "DXT5",
      "dds_alpha_flag": false,
      "width": 64,
      "height": 64,
      "mip_levels": 5,
      "alpha": { "present": true, "min": 0, "max": 252, "coverage": 0.959 },
      "blend": "alpha",
      "png_size_bytes": 5313,
      "png_sha256": "…"
    }
  },
  "sprite_roles": {
    "cr_splsh.png": ["wheel_splash_loose"],
    "rd_splsh.png": ["wheel_splash_paved"],
    "water_1.png": ["wheel_water_core"],
    "water_2.png": ["wheel_water_mist"],
    "sprk_sml.png": ["impact_spark_small"],
    "sprk_big.png": ["impact_spark_large"],
    "mud_rd1.png": ["impact_mud", "wheel_chips_mud"],
    "snwflk_1.png": ["precipitation_snow"],
    "raindrop.png": ["precipitation_rain_near"],
    "r_fall.png": ["precipitation_rain_far"]
  },
  "notes": [
    "El archivo contiene 62 entradas; se extraen únicamente las 20 que usa el VFX.",
    "Dust_01.dds y Dust_02.dds son idénticos byte a byte en el archivo; se conservan ambos nombres.",
    "Sprk_sml.dds y Sprk_big.dds no tienen canal alfa útil; el runtime usa mezcla aditiva."
  ]
}
```

Criterio de aceptación de la fase:

- `--verify-only` sale con 0 dos veces consecutivas.
- El manifiesto contiene las 20 entradas con los dos hashes.
- Los PNG son RGBA; los que tienen alfa conservan píxeles con alfa 0 y > 0.
- Las 3 entradas actuales (`dust_01.png`, `dust_02.png`, `smoke_01.png`) se conservan con su nombre,
  su DDS y, si los píxeles no cambian, su mismo hash PNG.

**Estado: completada (2026-11-03).**

- `tools/rally/extract_cmr4_vfx.py` extrajo 20 PNG (17 nuevos y los 3 ya existentes, cuyos hashes
  PNG se conservaron). `manifest.json` registra 62 entradas de archivo, 20 assets, DDS y PNG con
  SHA-256, formato, mips, alfa y mezcla.
- `--verify-only` pasa de forma idempotente: dos ejecuciones seguidas no cambian el manifiesto.
- Godot 4.7.1 importó las 20 texturas sin `SCRIPT ERROR`; los `.import` generados usan
  `compress/mode=0` y `mipmaps/generate=false`. La comprobación en runtime confirmó tamaño,
  SHA-256 y presencia de alfa en los 20 assets (`PHASE1_TEXTURE_CHECK PASS`).
- `vehicle_vfx_contract.gd` sigue pasando: la importación no alteró el runtime de VFX.

### Fase 2 — Emisores de rueda: agua y nieve

Archivo principal: `game/scripts/rally/rally_vehicle_vfx.gd`.
Archivos auxiliares: `game/scripts/rally/rally_vehicle_vfx.gdshader` (sin cambios funcionales) y
`game/scripts/physics/vehicle_simulation.gd` (escritura de `last_local_conditions`).

Cambios:

1. Constantes de precarga para los sprites CMR4 (las tres ya existentes se conservan):
   `SPLASH_LOOSE`, `SPLASH_PAVED`, `WATER_CORE`, `WATER_MIST`, `SNOW_ROLL` (cuatro texturas),
   `MUD`, `LEAVES` (tres) y `SPARK_SMALL`/`SPARK_BIG`.
2. `make_emitter()` acepta un parámetro de mezcla (alfa/aditiva) y un nombre de shader; sigue
   usando el mismo `QuadMesh`, `ParticleProcessMaterial`, curva de escala y rampa de color. Los
   materiales se añaden a `particle_materials` para la actualización de `world_to_vehicle`.
3. Nuevos arrays por rueda: `wheel_splash`, `wheel_water`, `wheel_mist`, `wheel_snow`, con
   `amount`, `lifetime` y tamaños iniciales:

   | Emisor | amount | lifetime | tamaño (m) | gravedad | color/alfa inicial |
   | --- | ---: | ---: | --- | --- | --- |
   | splash | 16 | 0,55 s | 0,15–0,35 | −5,5 | blanco azulado, 0,65 |
   | water | 22 | 0,85 s | 0,25–0,70 | −3,5 | blanco frío, 0,55 |
   | mist | 26 | 1,35 s | 0,55–1,15 | +0,2 | blanco grisáceo, 0,35 |
   | snow | 30 | 0,70 s | 0,18–0,45 | −4,5 | blanco, 0,85 |

4. `update_wheel(index, wetness)`:

   - Mantener el early-return actual (`index < 2`, carga < 60 N, sin cast, fuera de `SURFACES`).
   - Leer `snow_mm` de `sim.last_local_conditions[index]`.
   - Elegir régimen: nieve → mojado → seco. Apagar explícitamente los emisores de los otros
     regímenes.
   - Agua: `speed_norm = smoothstep(1.5, 16.0, max(speed, tread_speed))`,
     `load_factor = clampf(wheel_loads[index] / maxf(vehicle.mass * 9.81 * 0.8, 1.0), 0.25, 1.0)`,
     `spray = clampf(intensity * wetness * speed_norm * load_factor * (0.6 + 0.4 * slip), 0.0, 1.0)`.
     `splash` usa `spray * 1.15`; `water` usa `spray`; `mist` usa `spray * 0.9`.
   - Textura de salpicadura: `Rd_splsh` en `road/asphalt/tarmac/curb`, `Cr_splsh` en el resto.
   - Posición: salpicadura en `contact + normal * 0.04`; agua/bruma detrás del contacto
     (`contact - horizontal_velocity * 0.3`) y con dirección `normal + opuesta a la velocidad`.
   - Nieve: `snow_norm = clampf(snow_mm / 3.0, 0.0, 1.0)`,
     `snow_strength = intensity * snow_norm * smoothstep(1.5, 12.0, speed) * (0.7 + 0.3 * slip)`.
     Variante de textura por rueda y tiempo (rotación lenta entre las cuatro para que se vean las
     cuatro; si la revisión visual muestra parpadeo, fijar una variante por rueda). En este régimen
     el polvo, el humo, el agua y los chips quedan apagados.
   - Mojado: atenuar polvo y humo con `(1 - wetness)` (mínimo 0 en humedad total) y los chips con
     `(1 - 0.5 * wetness)`; el resto del cálculo de polvo/chips se conserva.
5. `stop_wheels()` y `reset_effects()` incluyen los nuevos arrays; `stop_wheels()` se usa al
   congelar, perder contacto, resetear o desactivar el VFX.
6. `vehicle_simulation.gd`: tras calcular `local_water`, `local_snow`, `local_ground` y `local_air`,
   guardar
   `last_local_conditions[i] = {"water_mm": local_water, "snow_mm": local_snow, "ground_c": local_ground, "air_c": local_air, "surface_name": str(contact["surface"])}`.
   No cambia ninguna fuerza ni ninguna condición de contacto.

Criterio de aceptación:

- En seco no aparece ningún emisor de agua ni de nieve.
- Con `wetness = 1` y velocidad, aparecen salpicadura y estela; al poner `wheel_loads = 0` o perder
  el `ShapeCast`, todos los emisores de agua/nieve se apagan en el mismo paso.
- `snow_mm` alto enciende la nieve de rueda y apaga polvo/humo/agua.
- La exclusión de carrocería sigue activa en todos los emisores (`body_exclusion_strength = 1.0`).

**Estado: completada (2026-11-03).**

- `rally_vehicle_vfx.gd`: cuatro emisores nuevos por rueda (`wheel_splash`, `wheel_water`,
  `wheel_mist`, `wheel_snow`), régimen exclusivo nieve → mojado → seco, escalado por humedad,
  velocidad, carga y deslizamiento, y corte inmediato al perder contacto o carga.
- `vehicle_simulation.gd`: `last_local_conditions[i]` guarda `water_mm`, `snow_mm`, `ground_c`,
  `air_c` y `surface_name` con los valores que el modelo de neumático ya calculaba por contacto.
- `vehicle_vfx_contract.gd`: añade comprobaciones de ruedas delanteras, sequedad, agua, escalado
  por humedad, texturas `Cr_splsh`/`Rd_splsh`, pérdida de carga, rueda parada, régimen de nieve
  con `Snw_rd*` y reset. Resultado: `RALLY_VFX_CONTRACT_OK` con `spray snow`.
- `weather_runtime_regression.gd` y `dynamic_weather_tires_contract.gd` siguen pasando.
- Una captura rápida con GPU (Forward+) confirmó que los emisores de agua y nieve renderizan en
  seco, mojado y nieve. La calibración fina de tamaños/opacidades y la exclusión desde capó quedan
  para la Fase 5.

### Fase 3 — Impactos, chispas, barro y hojas

Archivos: `rally_vehicle_vfx.gd`, nuevo `game/scripts/rally/rally_vehicle_vfx_add.gdshader`.

1. `update_impacts()` clasifica el contacto en un diccionario de efecto, usando la superficie y
   `collider_name` (en minúsculas):

   | Clase | Detección | Sprite | Mezcla | Notas |
   | --- | --- | --- | --- | --- |
   | Duro / metálico | `road/asphalt/tarmac/curb` o `barrier`, `props`, `building` en el nombre | `Sprk_sml` o `Sprk_big` según severidad | aditiva | solo con tangencial > 4 m/s e `wetness < 0.6`; si está muy mojado, residuo |
   | Vegetación | `tree` en el nombre o superficie `grass` | `leaf_01`…`leaf_03` | alpha | variante por evento, tinte verde/otoño |
   | Barro | superficie `dirt` con `wetness >= 0.35`, o `mud` | `Mud_rd1` | alpha | tinte marrón |
   | Suelto seco | `gravel`, `sand`, `dirt` seco | `dirt_02_a.png` (Brackeys) | alpha | se conserva la calidad de la grava |

2. `emit_impact()` recibe la clase, la textura, el tamaño y la mezcla. Para las chispas:
   - `Sprk_sml` con `quad.size ≈ (0.18, 0.55)` y `Sprk_big` con `(0.35, 0.9)`; la severidad elige.
   - Material con `rally_vehicle_vfx_add.gdshader`: `render_mode blend_add, depth_draw_never,
     cull_disabled, unshaded;`, misma facturación de billboard y misma exclusión de carrocería.
   - `ALBEDO = sample.rgb`, `ALPHA = sample.a * visibility`; el negro del bitmap no se dibuja.
   - Sin mezclar `trace_01_a.png` para chispas (se elimina del pool).
3. Chips de rueda: `grass` usa una de las hojas; `dirt` mojado o `mud` usa `Mud_rd1`; el resto
   conserva `dirt_02_a.png`.
4. El contador `emitted_impacts`, el cooldown 0,22/0,35 s y la reutilización de los seis slots no
   cambian; cada evento escribe su textura antes de `restart()` para no heredar la del anterior.

Criterio de aceptación:

- Un raspe en barrera en seco produce exactamente una chispa aditiva y no deja recuadro negro.
- Un impacto en tierra mojada produce `Mud_rd1`; uno en árbol/hierba produce una hoja; un impacto
  blando en grava seca conserva el sprite Brackeys.
- Los contactos sostenidos no duplican emisiones (cooldown) y el pool sigue limitado a seis.

**Estado: completada (2026-11-03).**

- Nuevo `game/scripts/rally/rally_vehicle_vfx_add.gdshader` (`blend_add`, `depth_draw_never`,
  `unshaded`) con el mismo billboard y la misma exclusión de carrocería que el shader alfa.
- `classify_impact()` elige un único sprite por contacto: `Sprk_sml`/`Sprk_big` aditivas en
  contactos duros secos con tangencial > 4 m/s, `Mud_rd1` en `Dirt` mojado o `Mud`,
  `leaf_01`…`leaf_03` en vegetación/hierba y `dirt_02_a` como residuo seco. Los chips de rueda
  usan hojas en hierba y `Mud_rd1` en barro o tierra mojada.
- `emit_impact_effect()` intercambia el shader del slot, escribe textura, tamaño y color, y conserva
  el cooldown (0,22 s para chispas) y el pool de seis. `emit_impact()` mantiene su firma para el
  contrato existente.
- `vehicle_vfx_contract.gd` verifica chispa grande/pequeña, barro, hoja, contacto duro mojado sin
  chispa y chips por material. Resultado: `RALLY_VFX_CONTRACT_OK ... sparks mud leaves`.
- Captura GPU (Forward+): la chispa aditiva no deja recuadro negro, y barro y hoja se dibujan con
  el shader alfa.

### Fase 4 — Precipitación de lluvia y nieve

Archivos: `game/scripts/rally/rally_weather_controller.gd`, nuevo
`game/scripts/rally/rally_weather_sprite.gdshader`,
`game/data/weather/rally_weather_presets.json`.

1. Shader de sprite de precipitación: billboard, `blend_mix`, `depth_draw_never`,
   `cull_disabled`, `unshaded`; uniforms `particle_texture`, `opacity`, `tint_color`,
   `near_start_m`, `near_end_m`, `far_start_m`, `far_end_m` y `ambient_luma`.
   `ALPHA = texture.a * opacity * fade_distancia * COLOR.a`, `ALBEDO = tint * ambient_luma`.
2. Lluvia en `apply_to_adapters()`:
   - Preload `r_fall.png` y `raindrop.png`.
   - `particles.trail_enabled = false`, `particles.draw_passes = 1`; `draw_pass_1` = `raindrop` con
     `QuadMesh` alargado (`raindrop_width_m` × `raindrop_height_m`, 0,07 × 0,80 m), opacidad 0,8,
     `rain_lifetime_s = 0,9` y `rain_amount_scale = 1,8` para que las gotas individuales se vean
     sin volver a agruparse.
   - Capa hija `RainFallSheet`: `GPUParticles3D` propio de 140 quads de 5 m con `R_Fall`, opacidad
     0,10, desvanecido cercano 6–12 m y lejano 35–70 m; su `amount_ratio` se sincroniza con la
     lluvia principal. No sustituye la lluvia de gotas: añade profundidad lejana.
   - Conservar `amount_ratio` global por `precipitation_mm_h`, la dirección por viento y el
     `global_position`.
   - Al cambiar de tipo se libera el sistema anterior (incluida la capa hija).
3. Nieve:
   - Preload `snwflk_1.png`.
   - `draw_passes = 1`, `QuadMesh` con tamaño `snow_size_m` (0,24 m), `ShaderMaterial` con
     `SnwFlk_1`, `snow_opacity`, desvanecido por distancia y un piso de luminancia 0,72 para que
     los copos mantengan contraste bajo la irradiancia de tormenta.
   - Mantener `amount`, `lifetime`, `randomness` y el proceso de la escena TCA.
4. Añadir a `visual_response` (sin eliminar claves usadas):
   `raindrop_width_m`, `raindrop_height_m`, `raindrop_opacity`, `rain_amount_scale`,
   `rain_lifetime_s`, `raindrop_near_fade_*`, `raindrop_far_fade_*`, `rain_sheet_amount`,
   `rain_sheet_ratio`, `rain_sheet_size_m`, `rain_sheet_opacity`, `rain_sheet_near_fade_*`,
   `rain_sheet_far_fade_*`, `snow_far_fade_start_m`, `snow_far_fade_end_m`; se reutilizan
   `snow_size_m` y `snow_opacity`.
   `rain_width_m` y `rain_trail_seconds` quedan documentadas como no usadas por el nuevo camino de
   lluvia (se conservan para no romper compatibilidad de datos).
5. No se modifica `game/addons/TCA_Weather_System`; el adaptador del proyecto sigue construyendo
   los materiales. Así el addon conserva su procedencia.

Criterio de aceptación:

- Con `precipitation_kind = "rain"`, la lluvia principal usa `raindrop` (una gota por partícula) y
  existe una capa `RainFallSheet` con `R_Fall` de baja densidad.
- Con `precipitation_kind = "snow"`, la textura de nieve es `SnwFlk_1` y `Snw_rd*` no se usa en
  precipitación.
- Cambiar de lluvia a nieve no deja dos sistemas emitiendo.

**Estado: completada (2026-11-03).**

- Nuevo `game/scripts/rally/rally_weather_sprite.gdshader`: billboard, fades de distancia, textura,
  opacidad, tinte y luminancia ambiental.
- `rally_weather_controller.gd`: la lluvia principal es `raindrop` por partícula; `R_Fall` vive en
  la capa hija `RainFallSheet`. La nieve usa `SnwFlk_1`; el sistema anterior se apaga antes de
  `queue_free()`. El adaptador actualiza la luminancia de todos los pases con
  `get_draw_pass_mesh()`.
- Verificación del síntoma reportado: `r_fall.png` contiene ~20 estelas en un solo bitmap; el
  agrupamiento desaparece al usar una gota por partícula.
- `rally_weather_presets.json`: parámetros de gota, vida/cantidad y capa `R_Fall`;
  `snow_size_m = 0.24`, `snow_opacity = 0.8`.
- Nuevo `weather_precipitation_sprite_contract.gd`: verifica una gota por partícula, la capa
  `R_Fall`, `SnwFlk_1`, tamaño de nieve, liberación del sistema anterior y retorno a lluvia.
  Resultado: `WEATHER_PRECIPITATION_SPRITE_CONTRACT PASS`.
- `weather_runtime_regression.gd` y `dynamic_weather_tires_contract.gd` siguen pasando.
- Capturas GPU: lluvia intensa con gotas individuales y capa lejana `R_Fall`, y nieve con
  `SnwFlk_1`. La calibración fina de densidad/opacidad queda para la Fase 5.

### Fase 5 — Pruebas y verificación visual

1. **Contrato de VFX** (`game/tests/rally/vehicle_vfx_contract.gd`), ampliado:
   - Manifiesto: parsear `manifest.json`, comprobar que existen las 20 entradas, que cada
     `png_sha256` coincide con `FileAccess.get_sha256()` del PNG y que `Dust_01`/`Dust_02`
     comparten hash y tienen nota de duplicado.
   - Texturas: cargar las 20, comprobar dimensiones esperadas y que las que tienen alfa
     conservan `detect_alpha() != ALPHA_NONE`; verificar que `sprk_*` son opacas.
   - Topología: arrays de rueda de tamaño 4 y `impact_pool` de 6.
   - Agua: en seco apagada; con humedad y velocidad encendida; al perder carga o contacto apagada;
     la humedad total reduce polvo/humo por debajo del 20 % del seco.
   - Nieve: `snow_mm` alto enciende `wheel_snow`, usa una textura `Snw_rd*` y apaga polvo/humo/agua.
   - Impactos: evento en barrera → shader aditivo y textura de chispa; evento en `dirt` mojado →
     `Mud_rd1`; evento en `tree_trunks`/`grass` → `leaf_*`; grava seca → Brackeys; cooldown y pool
     intactos; ninguna clase usa dos texturas en el mismo evento.
   - Reset: `reset_effects()` deja apagados todos los emisores nuevos.
2. **Contrato de precipitación** (nuevo `game/tests/rally/weather_precipitation_sprite_contract.gd`):
   reproducir el escenario de `weather_runtime_regression.gd`, forzar `current_blend` a lluvia y
   llamar a `apply_to_adapters()`; comprobar una gota `raindrop` por partícula y la capa hija
   `RainFallSheet` con `R_Fall`. Repetir con nieve y comprobar `SnwFlk_1`. Comprobar que no se
   duplica el sistema al cambiar de tipo.
3. **Sonda visual con GPU** (nuevo `game/tests/rally/vfx_visual_probe.gd`):
   - Cargar `rally_proving_ground.tscn`, esperar contactos reales, congelar el coche y controlar
     el VFX manualmente (física del VFX desactivada) para tener emisiones deterministas.
   - Capturas en `%TEMP%\rally_vfx_visual\`: seco en grava, mojado con salpicadura/estela, nieve de
     rueda, chispa aditiva, barro y hoja, y una vista lateral de cabina para comprobar que la
     exclusión de carrocería no deja partículas dentro del habitáculo.
   - Capturas de lluvia y nieve CMR4 con `weather_visual_probe.gd` y revisión de los PNG.
4. Ejecutar además los contratos existentes que tocan el clima o el coche:
   `weather_runtime_regression.gd`, `dynamic_weather_tires_contract.gd`,
   `stage_visual_settings_contract.gd` y `vehicle_vfx_contract.gd`.

Comandos previstos:

```powershell
$godot = $env:GODOT_BIN
& $godot --headless --path game --script res://tests/rally/vehicle_vfx_contract.gd --quit-after 1000
& $godot --headless --path game --script res://tests/rally/weather_precipitation_sprite_contract.gd --quit-after 1000
& $godot --headless --path game --script res://tests/rally/weather_runtime_regression.gd --quit-after 2000
& $godot --headless --path game --script res://tests/rally/dynamic_weather_tires_contract.gd --quit-after 2000
# Captura visual: sin --headless, con GPU y Forward+
& $godot --path game --rendering-method forward_plus --script res://tests/rally/vfx_visual_probe.gd
& $godot --path game --rendering-method forward_plus --script res://tests/rally/weather_visual_probe.gd
```

**Estado: completada (2026-11-03).**

- `vehicle_vfx_contract.gd` incorpora la comprobación del manifiesto (20 PNG, hashes, dimensiones,
  alfa) y de la exclusión (ruedas `1.0`, impactos `0.0`). Resultado:
  `RALLY_VFX_CONTRACT_OK ... sparks mud leaves`.
- Nuevo `vfx_visual_probe.gd`: 12 capturas (seco/mojado/nieve en persecución y cerca, chispas,
  barro, hoja y vista lateral de cabina). Todas se revisaron con `read_image`.
- Calibración derivada de la revisión visual:
  - El origen del vehículo está a ras de suelo; el margen suave de la caja de exclusión
    (0,20 m / `smoothstep` 0,55) ocultaba las partículas a ras de suelo. Se redujo a 0,05 m /
    `smoothstep` 0,15 y los impactos quedan exentos (`body_exclusion_strength = 0`).
  - `depth_draw_opaque` → `depth_draw_never` en el shader de partículas para evitar recortes
    rectangulares por escritura de profundidad.
  - Fade de borde UV del 8 % para eliminar los rectángulos que dejaban las texturas de agua.
  - La lluvia se corrigió antes de esta fase: una gota `raindrop` por partícula y `R_Fall` como
    capa lejana.
- Contratos: VFX, precipitación, `weather_runtime_regression` y `dynamic_weather_tires_contract`
  → PASS.
- `stage_visual_settings_contract.gd` falla por expectativas previas de humedad/especular: espera
  un factor uniforme 0,85 y `SPECULAR_DISABLED` con `wetness = 0.5`, mientras
  `rally_terrain_wetness.gd` aplica 0,838/0,856/0,892 y Schlick. Esos archivos no se tocaron en
  este trabajo; es una regresión previa fuera del alcance del VFX y se deja registrada.
- La captura es estática (coche congelado): polvo y agua se acumulan en el mismo punto. La
  validación en movimiento se hará con la build de la Fase 6.

### Fase 6 — Build de Windows, documentación y cierre

1. `.\scripts\run_build.ps1` (importa, compila todos los GDScript, valida el lanzador, exporta).
   Si no se quiere exportar todavía: `.\scripts\run_build.ps1 -ImportOnly` y después
   `.\scripts\stage_rally_windows_export.ps1 -RepositoryRoot . -GodotPath $env:GODOT_BIN -StageOnly`.
2. Comprobar la inclusión:
   - `build\rally_export_project\assets\vfx\cmr4\` contiene los 20 PNG y `manifest.json`.
   - `build\rally_export_project\.godot\imported\` contiene los `.ctex` de los sprites nuevos.
   - `dist\rally_windows\rally_export_manifest.json` lista cada `assets/vfx/cmr4/*.png` y el
     manifiesto con su SHA-256.
   - La importación del proyecto aislado no imprime `SCRIPT ERROR` ni `Parse Error`.
3. Actualizar `game/docs/rally/VFX.md`:
   - Tabla de sprites CMR4 y su efecto, mezcla y condición.
   - Modelo de spray (humedad, velocidad, carga, contacto y corte al despegar).
   - Nieve de rueda y precipitación; integración en el adaptador.
   - Enrutado de impactos por material y explicación de la mezcla aditiva.
   - Presupuesto de partículas actualizado, exclusión de carrocería y procedencia/manifiesto.
   - Comandos de verificación y nota de `forward_plus` (desarrollo) frente a `gl_compatibility`
     (export).
4. No se versionan los `.import` (regla existente); si la revisión detecta que Godot comprime los
   sprites con pérdida, añadir una excepción en `.gitignore` para
   `game/assets/vfx/cmr4/*.png.import` y fijarlos con `compress/mode=0` y `detect_3d/compress_to=0`.
5. Revisar `git status`: solo deben aparecer la herramienta, los PNG, el manifiesto, los scripts,
   los tests, los datos de clima y la documentación previstos.

## 5. Matriz de requisitos → implementación → prueba

| Requisito de `instrucciones.md` | Implementación | Prueba |
| --- | --- | --- |
| DDS → PNG RGBA con alfa y manifiesto con nombres/hashes | Fase 1 | `--verify-only` + contrato de manifiesto |
| Salpicadura y estela con `Cr_splsh`, `Rd_splsh`, `Water_1`, `Water_2` | Fase 2 | contrato de agua + captura mojada |
| Ruedas traseras con contacto y carga; escala con humedad/velocidad | Fase 2 | gating del contrato; `wheel_loads = 0` |
| Suprimir polvo/humo en mojado | Fase 2 | comparación seco/mojado |
| `Dust_01`, `Dust_02`, `smoke_01` sin regresión | Base + Fase 2 | contrato existente ampliado |
| Chispas `Sprk_sml`/`Sprk_big` aditivas | Fase 3 | shader aditivo + captura sobre asfalto |
| `Mud_rd1` para barro y `leaf_01..03` para vegetación | Fase 3 | clasificación de impactos |
| Efecto según material de contacto | Fase 3 | eventos con distintos `surface`/`collider_name` |
| Nieve de rueda `Snw_rd0..3` y `SnwFlk_1` | Fases 2 y 4 | régimen de nieve + captura |
| Lluvia `raindrop` y `R_Fall` integrada en el clima | Fase 4 | contrato de precipitación + captura |
| Reutilizar contactos/emisores/clima; sin duplicar | Diseño D3/D5 | early-returns y pruebas de no duplicado |
| Contrato de VFX, build de Windows y apariencia GPU | Fases 5 y 6 | build + contratos + capturas |
| Spray cesa al perder contacto | Fase 2 | assert en contrato |
| Efectos de rueda fuera del habitáculo | D7 | captura lateral de cabina y persecución |

## 6. Riesgos y mitigaciones

| Riesgo | Mitigación |
| --- | --- |
| La lluvia con `R_Fall` por partícula agrupaba gotas | Verificado: `R_Fall` es una lámina de ~20 estelas. Se usa una gota `raindrop` por partícula y `R_Fall` solo en la capa lejana `RainFallSheet` |
| El shader de precipitación en `gl_compatibility` | Verificar en la build de la Fase 6; el camino estándar usa `draw_pass_1` y una capa hija, sin depender de más de un pase |
| Los cuatro `Snw_rd*` parecen fotogramas de una animación y parpadean al rotarlos | Usar una variante fija por rueda y validar; si convence la animación, construir el atlas 2×2 en runtime desde los cuatro PNG originales (sin archivo derivado) |
| El zoom de cámara sobre sprites de 16×16 revela pixelado | Mantener tamaños pequeños, filtro lineal y revisar en capturas cercanas; no aumentar resolución artificialmente |
| Las partículas de agua atraviesan el habitáculo | Ruedas con `body_exclusion_strength = 1`; impactos con `0`; verificado con vista lateral de cabina |
| Recortes rectangulares por profundidad o por el borde de la textura | `depth_draw_never` y fade de borde UV del 8 %; corregido en la Fase 5 |
| `last_local_conditions` se escribe por frame y cambia el estado de física | Es una escritura de un diccionario ya calculado; no altera fuerzas ni contactos; los contratos de física deben seguir pasando |
| El manifiesto y los PNG se desincronizan | `--verify-only` en la herramienta y comprobación de hashes en el contrato de VFX |
| La build no incluye los recursos nuevos | Verificar el staging y el manifiesto de exportación; el staging ya copia `assets/vfx` completo |

## 7. Criterios de aceptación finales

1. `python tools/rally/extract_cmr4_vfx.py --verify-only` termina con 0 y el manifiesto tiene las
   20 entradas con hashes de DDS y PNG.
2. `vehicle_vfx_contract.gd` y `weather_precipitation_sprite_contract.gd` pasan en headless.
3. `weather_runtime_regression.gd` y `dynamic_weather_tires_contract.gd` siguen pasando.
4. La sonda visual con GPU genera capturas de seco, mojado, nieve, chispas, barro/hojas y
   lluvia/nieve; se revisan y no hay partículas dentro del habitáculo ni spray con la rueda en el
   aire.
5. `.\scripts\run_build.ps1` termina; el staging contiene los PNG y el manifiesto, y el manifiesto
   de exportación los lista con sus hashes. La importación no muestra errores de script.
6. `game/docs/rally/VFX.md` documenta sprites, mezclas, condiciones, presupuesto, integración
   meteorológica, procedencia y comandos de verificación.

## 8. Orden de trabajo sugerido

1. Fase 1 (herramienta + manifiesto + importación local).
2. Fase 2 (agua y nieve de rueda + `last_local_conditions`).
3. Fase 3 (chispas aditivas, barro y hojas).
4. Fase 4 (lluvia y nieve en el adaptador).
5. Fase 5 (contratos y capturas; calibrar tamaños/opacidades).
6. Fase 6 (build, documentación y revisión de `git status`).
