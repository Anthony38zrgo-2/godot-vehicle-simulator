# Informe de ingeniería de sonido — banco `commons`

**Alcance:** los 27 WAV de `game/sounds/banks/commons` (2,9 MB, 33,92 s en total), su
`bank_manifest.json` y la cadena que los reproduce (`rally_vehicle_audio.gd`,
`seamless_vehicle_loop.gd`, `audio_mixer.json`, `ensure_vehicle_bus.gd`).

**Herramientas:** `tools/audio/analyze_commons_bank.py` (auditoría objetiva) y
`tools/audio/clean_commons_bank.py` (render no destructivo). Todo en numpy puro:
loudness ITU-R BS.1770-4 con gating, pico real a 4×, análisis por bandas de octava,
detección de clicks de loop, clipping plano e integridad de manifiesto.

---

## 0. Resumen en cinco líneas

1. El banco **no está roto**, pero está **desalineado consigo mismo**: los 22 one-shots
   llegan casi todos a −1 dBFS de pico real y el compresor de bus (umbral −0,45 dBFS,
   3,5:1) se dispara con eventos aislados → bombeo del motor y del escape.
2. Las **variantes del mismo evento no coinciden en volumen**: hasta **6,35 LU** entre los
   `backfire_ext`, **4,40 LU** entre las tomas de tierra, **1,80 LU** entre los `impact_small`.
   La selección aleatoria suena como un fallo, no como variedad.
3. **9 archivos de 27 son duplicados bit a bit** en 4 grupos: la "variación" no existe.
4. Las capas de impacto por severidad están **invertidas** tras aplicar la ganancia de
   runtime: la toma de tierra "dura" suena **más floja** que la media.
5. Hay **sub-bajo inaudible** (hasta el 14 % de la energía por debajo de 30 Hz) que gasta
   headroom y ensucia el compresor, y **loops mal cerrados** (`impact_scrape`, 2,35 s de
   one-shot reproducido en bucle continuo).

La cadena de limpieza aplicada deja: **0 one-shots por encima de −1,5 dBFS** (antes 14),
**pico real máximo −3,00 dBFS** (antes +0,03, es decir, clipping digital), dispersión de
grupo **≤0,4 LU** en todos los grupos de impacto, y el loop de `impact_scrape` con un
cierre de **0,02×** el paso típico (antes 1,61×).

---

## 1. Cómo suena esto en el juego (contexto de mezcla)

La cadena real de reproducción no es la obvia, y eso cambia el diagnóstico:

| Etapa | Qué hace | Consecuencia |
|---|---|---|
| `SeamlessVehicleLoop.load_pcm` | lee el RIFF a mano, exige **PCM16, 1–2 canales**; no usa el `.import` | la compresión QOA de Godot **no** toca estos samples |
| `load_looping_stream` | aplica **512 muestras (11,6 ms)** de crossfade al cerrar el loop | el click de `impact_scrape` está parcialmente enmascarado; lo audible es el **reinicio del decaimiento cada 2,35 s** |
| `load_event_stream` | aplica la **rampa de release** de `audio_mixer.json` (40–65 ms en impactos) | el corte de cola de los one-shots queda tapado; el ataque no |
| `AudioStreamPlayer3D` | atenuación por distancia, `unit_size` 8–24 | el pico del sample **no** es el pico en el oyente |
| Bus `Vehicle` | compresor **−0,45 dBFS, 3,5:1, attack 5 ms, release 120 ms**, salida −1,5 dB | cualquier suma de voces cerca de 0 dBFS **bombea la mezcla entera** |

> Esto es lo importante: en este proyecto el pico del sample **sí** llega a la mezcla.
> Con 4 ruedas golpeando + scrape + motor + escape, cuatro one-shots a −1 dBFS suman
> fácilmente por encima de −0,45 dBFS y el compresor del bus mete un ducking de 120 ms
> justo en el momento del impacto. Ese es el defecto "que afecta a toda la mezcla".

---

## 2. Estado medido

`LUFS` = loudness del evento (BS.1770-4, sin gating para los archivos cortos — es la misma
base que usan las comparaciones de grupo); `TP` = pico real a 4×; `centro` = centroide
espectral; `sub30` = proporción de energía por debajo de 30 Hz.

| archivo | s | LUFS | TP dBFS | crest dB | centro Hz | sub30 % | seam × |
|---|---|---|---|---|---|---|---|
| impact_small_1 | 0,58 | −12,3 | −1,01 | 10,2 | 583 | **14,0** | – |
| impact_small_2 | 0,62 | −12,6 | −0,99 | 12,0 | 1651 | 3,3 | – |
| impact_small_3 | 0,55 | −14,2 | −1,00 | 13,6 | 1585 | 6,4 | – |
| impact_medium_1 | 0,80 | −14,2 | −0,95 | 13,4 | **1851** | 1,9 | – |
| impact_medium_2 | 0,79 | −15,5 | −1,00 | 13,4 | **438** | 0,4 | – |
| impact_large | 1,13 | −15,7 | −0,92 | 14,2 | 911 | 0,4 | – |
| impact_land_1 | 0,50 | −14,2 | −0,99 | 13,3 | 1377 | 0,0 | – |
| impact_land_2 | 0,82 | **−9,8** | −0,42 | 9,4 | 1552 | 6,2 | – |
| impact_land_3 | 0,92 | −14,2 | −0,84 | 11,5 | **414** | **8,6** | – |
| impact_scrape | 2,35 | −14,4 | −3,00 | 14,5 | 4107 | 0,0 | **1,61** |
| backfire_ext_1/2 | 0,47 | −16,8 | −2,10 | 14,3 | 682 | 0,4 | – |
| backfire_ext_3 | 0,47 | −16,8 | −2,10 | 14,3 | 682 | 0,4 | – |
| backfire_ext_4 | 0,43 | **−10,4** | −0,86 | 7,8 | **167** | 1,5 | – |
| backfire_5 / backfire_int | 0,16 | −9,5 | **+0,03** | 8,3 | 200 | 0,1 | – |
| f2002_gearup | 0,30 | −17,9 | −5,68 | 10,9 | 236 | 1,3 | – |
| f2002_geardn | 0,19 | −16,1 | −3,56 | 10,0 | 103 | 0,5 | – |
| neutral_first_gear_transition | 0,74 | **−23,1** | −3,00 | 19,6 | 678 | 1,1 | – |
| tyre_contact | 0,36 | −15,2 | **−0,10** | 14,0 | 205 | 0,6 | – |
| limiter_cut_loop | 7,35 | **−9,4** | −0,72 | 8,5 | 722 | 0,2 | 0,17 |
| flat_tyre_mono | 8,81 | −20,8 | −3,82 | 15,1 | 273 | 2,6 | 0,03 |
| damaged_rin | 2,47 | −19,0 | −4,17 | 15,8 | 1358 | 0,0 | 0,02 |
| bad_brakes | 1,08 | −19,2 | −9,36 | 11,6 | 1772 | 0,0 | 0,24 |

(`backfire_1/7/9` son bit a bit iguales a `ext_1/3/4`; se omiten por repetir fila.)

Los 14 one-shots por encima de −1,5 dBFS de pico real: todos los impactos, los backfire y
`tyre_contact`. El máximo del banco es **+0,03 dBFS** (`backfire_5`): el pico de muestra ya
está a 0 dBFS (clipping digital) y la interpolación a 4× todavía lo supera.

---

## 3. Los problemas que llegan a la mezcla

### P1 — Techo de pico y compresor de bus (crítico)

Todos los one-shots fueron normalizados a 0,89–1,0 de pico, sin margen. Medido:

- 14 de 22 one-shots por encima de −1,5 dBFS TP.
- `backfire_5` / `backfire_int`: **+0,03 dBFS** y **23 tramos planos** en el pico → el
  material ya estaba limitado en origen y después se sobreelevó. Suena a "thump" con
  distorsión de limitador, no a explosión.
- `backfire_9` / `backfire_ext_4`: **15 tramos planos** (clipped a 0,902 y luego
  normalizado). El clipping viaja dentro del sample.
- `tyre_contact`: −0,10 dBFS con **2 canales** (el único estéreo del banco).

Un one-shot a −1 dBFS en un bus con compresor a −0,45 dBFS no tiene colchón: cualquier
suma, cualquier reverb send, cualquier ganancia de 3D lo manda al limitador.

### P2 — Las variantes no coinciden en volumen (crítico)

| grupo | dispersión antes | dispersión después de la limpieza |
|---|---|---|
| `backfire_ext` | **6,35 LU** | 0,00 |
| `impact_land` | **4,40 LU** | 0,36 |
| `impact_small` | 1,80 LU | 0,24 |
| `gearbox_f2002` | 1,81 LU | 0,00 |
| `impact_medium` | 1,36 LU | 0,03 |

6,35 LU entre cuatro archivos que el código elige al azar es un salto de más de 6 dB entre
un petardazo y el siguiente. No es "variedad", es un bug de mezcla.

### P3 — La capa de severity está invertida (crítico)

Con las ganancias de runtime (`-24 / -21 / -18 dB` para las tomas de tierra y `-12 / -9 / -6`
para los impactos por tamaño):

| evento | LUFS efectivo antes | después de la limpieza |
|---|---|---|
| impact_land_1 (caída <4 m/s) | −38,2 | −40,5 |
| impact_land_2 (4–7 m/s) | **−30,8** | −37,5 |
| impact_land_3 (>7 m/s) | **−32,2** | −34,9 |
| impact_small (<40 km/h) | −24,3 / −24,6 / −26,2 | −28,3 / −28,3 / −28,5 |
| impact_medium (40–70) | −23,2 / −24,5 | −26,8 / −26,8 |
| impact_large (>70) | −21,7 | −22,1 |

La caída **fuerte** (`land_3`) sonaba 1,4 dB más floja que la **media** (`land_2`), cuando
debería estar 3 dB por encima. Con el sample corregido el orden crece con la caída
(−40,5 / −37,5 / −34,9) y las tres quedan a la misma distancia de 3 dB que marca el código.

### P4 — Nueve archivos son el mismo archivo (crítico de contenido)

| sha256 | archivos |
|---|---|
| `bf7b7dcf…` | `backfire_1`, `backfire_ext_1`, `backfire_ext_2` |
| `0e771e7d…` | `backfire_7`, `backfire_ext_3` |
| `0a53416e…` | `backfire_9`, `backfire_ext_4` |
| `9bedeedf…` | `backfire_5`, `backfire_int` |

`BACKFIRE_SAMPLE_PATHS` tiene 4 rutas pero **solo 2 sonidos distintos**. Cuando dos voces
del pool coinciden en el tiempo suenan idénticas y suman en fase (+6 dB en el transitorio
si están alineadas). Y tres de esos archivos (`backfire_1/7/9`) no los referencia ningún
código: son copias sobrantes de la importación del Porsche.

### P5 — Sub-bajo inaudible que gasta headroom

`impact_small_1` tiene el **14 %** de su energía por debajo de 30 Hz; `impact_land_3` el 8,6 %.
En un monitor de 5" o en el altavoz de un portátil eso no se reproduce, pero **sí** cuenta
en el pico y **sí** excita el compresor. El EQ de runtime ya corta 62–125 Hz, pero no toca
por debajo de 40 Hz.

### P6 — Loops mal resueltos

- `impact_scrape` es un one-shot de 2,35 s con decaimiento, reproducido por
  `continuous_player()` en **loop cerrado**: cada 2,35 s se reinicia el decaimiento. El
  crossfade de 11,6 ms del runtime maquilla el click pero no la repetición. Además el
  cierre crudo mide **1,61×** el paso típico.
- El manifiesto declara `impact_scrape` con `duration_s: 2,5867` y el archivo mide
  **2,348**: el WAV se re-renderizó y el manifiesto no se regeneró.
- `damaged_rin.wav` (213 KB, role `wheel_damage_rim`) **no lo usa nadie**:
  `WHEEL_DAMAGE_SAMPLES = ["flat_tyre_mono", "bad_brakes"]`.

### P7 — Integridad del banco

- El manifiesto declara **6 WAV que no existen**: `gear_up_1..3` y `gear_down_1..3`. El
  código no los carga (usa `f2002_gearup/geardn`), pero cualquier validador de manifiesto
  que se escriba mañana va a fallar.
- `peak` declarado 0,950 vs medido 0,785 (`backfire_ext_1..3`), 0,902 (`ext_4`), **1,000**
  (`backfire_5`): los archivos se renormalizaron sin regenerar el manifiesto.
- Los 27 `.import` tienen `compress/mode=2` (QOA) y `edit/loop_mode=0`. Hoy es inocuo
  porque el runtime lee el RIFF crudo y fija `LOOP_FORWARD` por código, pero es una
  trampa: cualquier uso futuro de `load()` sobre estos WAV aplicaría QOA (lossy) o
  perdería el loop.

---

## 4. Opinión como diseñador de sonido, familia por familia

**Impactos de carrocería (`impact_small/medium/large`).** Vienen de Rush Rally 3, son
grabaciones de choque con cola larga y mucha caja (0,55–1,13 s). En un rally de los 70 con
motor atmosférico y escape con carácter, la cola del choque compite con el escape y con la
reverb, y la mezcla se embarra justo en el golpe. Yo **acortaría la cola a 0,35–0,5 s** con
una ventana suave (no un fade duro) y dejaría la cola larga para el tier grande, que es el
único donde el "resto" del choque aporta información.

El problema de diseño más gordo: **no son variaciones del mismo sonido**. `impact_small_1`
tiene centroide 583 Hz (golpe sordo, casi todo sub) y `impact_small_2` 1651 Hz (crack
seco); `impact_medium_1` 1851 Hz y `impact_medium_2` 438 Hz. Elegir al azar entre un golpe
sordo y un crack cambia el material del coche, no la intensidad. Recomendación: fijar una
**familia tímbrica por material** (chapa, plástico, fibra) y usarla como eje de variación,
con la intensidad como eje independiente. Sin regrabar, se puede aproximar con EQ estático
por variante (un low-shelf de +2 dB en las que son demasiado brillantes), pero es maquillaje.

**Tomas de tierra (`impact_land`).** Son tres grabaciones distintas de CMR2 (`land1/2/3`),
no tres intensidades del mismo golpe, y suenan muy distintas entre sí (centroide 414 / 1377 /
1552 Hz). `land_3` (la dura) es la **más oscura** y la **más floja**: perceptual y
técnicamente invertido. Lo que haría: reordenar por centroide (dura = más cuerpo y menos
brillo, pero también más nivel), y como mínimo igualar loudness — ya está hecho.

**Petardos (`backfire_*`).** El set tiene un fallo de contenido serio: 4 rutas y 2 sonidos.
Además `backfire_ext_4` es un boom de 167 Hz (muy distinto de los 682 Hz de los otros tres)
y está 6,35 LU por encima; `backfire_5` (cabina) está a 0 dBFS y clipped. Un petardo de
escape debería ser: ataque corto (5–15 ms), cuerpo 80–200 Hz, cola de 200–400 ms, y
**nunca** un DC/clip. Lo que haría con material nuevo: 4 disparos reales del mismo escape y
el mismo micrófono, normalizados al mismo LUFS; y para cabina, una versión low-pass a
~250 Hz del mismo disparo (que es lo que hace el oído dentro del coche), no un thump de
otro origen.

**Caja (`f2002_gearup/geardn`).** Son de un mod de Ferrari F2002 (F1 2002): un clunk
metálico seco, centroide 103–236 Hz, con cola muy corta. En un Escort o un 356 suena
"moderno" y algo sintético, pero funciona como mecánica. El problema es que **no casan con
`neutral_first_gear_transition`**, que mide **−23,1 LUFS** (unos 7,5 LU por debajo de la
mediana de los one-shots) y se le aplica **HPF a 1 kHz + LPF a 6 kHz** con volumen 0,41: el
contacto neutral/primera es un "tick" fino, casi inaudible al lado del motor. Si ese evento
tiene que leer como enganche de transmisión, necesita cuerpo (150–400 Hz), no un high-pass a
1 kHz.
Yo lo dejaría pasar por un HPF a 180 Hz y subiría el volumen a ~0,6; o mejor, lo
re-renderizaría con la fuente completa sin el filtro.

**Contacto de neumático (`tyre_contact`).** Estéreo (el resto es mono), pico a −0,10 dBFS y
centroide 205 Hz. Para un evento 3D posicional, el estéreo no aporta (Godot lo pliega) y sí
cuesta 2× memoria; el pico tampoco tiene sentido con un `-10 dB` de ganancia en código.
Mono + −3 dBFS.

**Loops de daño (`flat_tyre_mono`, `damaged_rin`, `bad_brakes`).** Timbres muy separados
(273 / 1358 / 1772 Hz de centroide) con un presupuesto de ganancia compartido
(`WHEEL_DAMAGE_GAIN_BUDGET = 0,46`): la rueda pinchada va a sonar siempre como "wub" grave
y el rin como siseo agudo, y cuando coinciden el agudo se come al grave. `bad_brakes` ya
lleva HPF a 400 Hz y `flat_tyre` LPF a 1800 Hz, lo cual dice que alguien ya detectó el
problema: es una solución de mezcla, no de sample. `damaged_rin` está sin usar; o se usa,
o se borra.

**Limitador (`limiter_cut_loop`).** Es el asset más caliente del banco (−9,4 LUFS): 7,35 s
con solo el 0,2 % de energía bajo 30 Hz, pero un cuerpo 40–200 Hz muy fuerte. Medido: al
quitar el sub-sónico el pico real sube **2,5 dB** (de −0,72 a +1,8), señal de que ese sub
estaba compensando los picos. Después de la limpieza queda a −14,2 LUFS (−4,75 dB) con
TP −3,00. Si no se compensa en `LIMITER_GAIN` (0,225), el corte de limitador va a sonar
menos presente que antes.

---

## 5. La cadena de Python que aplicaría

Archivo: `tools/audio/clean_commons_bank.py`. Orden y por qué:

1. **Media fuera + HPF a 8 Hz** — quita DC y sub-sónico puro. Medido: los backfire declaran
   `dc_offset: 0.0` en el manifiesto pero miden entre **−47,7 y −52,1 dBFS** de DC: la
   corrección que sí lleva el resto del banco nunca se les aplicó. Aporta poco en absoluto,
   pero es gratis y deja el pico honesto.
2. **HPF de rol: 30 Hz one-shots / 35 Hz loops** (Butterworth 2º orden, Q 0,707).
   Transparente por encima de 60 Hz (−0,5 dB a 60 Hz, −0,06 dB a 100 Hz) pero elimina el
   rango que no se reproduce y sí suma en el pico.
3. **Gate del hiss pre-ataque y recorte del silencio inicial** (solo one-shots).
   *En este banco no han disparado en ningún archivo*: los 27 atacan en la primera muestra
   (silencio inicial medido ≤10 ms en todos, y sin región de fondo antes del ataque). Es
   decir, la alineación temporal del banco ya estaba bien; el paso queda en la cadena para
   importar material nuevo, donde es lo primero que se rompe.
4. **De-click solo si el borde está cortado**: fade-in de 0,4 ms cuando el primer sample
   entra a menos de −20 dB del pico (disparó en `backfire_9` / `backfire_ext_4`, que
   arrancaban a −3 dB del pico, en mitad de la onda); fade-out de 3 ms cuando el buffer
   corta a menos de −25 dB del pico (no disparó en ninguno: las colas ya terminan bajo).
   No se toca nada que no esté roto.
5. **Reparación del cierre de loop** (solo loops): crossfade equal-power de 40 ms (60 ms en
   `impact_scrape`, que es un one-shot en bucle) y recorte de la cola. Sobre `impact_scrape`
   el indicador de discontinuidad pasa de **1,61× a 0,02×**. En los otros tres loops no
   disparó porque su cierre ya estaba bien (0,02–0,24×).
6. **Igualado de loudness por grupo** (mediana de lo alcanzable con el techo): la selección
   aleatoria deja de saltar. Los aliases bit a bit se fuerzan a ser idénticos también a la
   salida.
7. **Limitador de pico con lookahead 2 ms, reducción máx. 3 dB** — no un normalizador: baja
   **solo el exceso del transitorio**, así el nivel percibido no cae con el techo. Los loops
   se atenúan en bloque (una curva de ganancia que cambia en el cierre volvería a abrir el
   loop).
8. **Techo de pico real −3,00 dBFS** (atenuación/limitación según el caso) → 2 dB de margen
   sobre el umbral del compresor de bus.
9. **Dither TPDF a 16 bits** al cuantizar: sin esto, las colas a −60 dBFS se llenan de
    distorsión de cuantización correlacionada, que es exactamente lo que se oye como
    "granulado" en las reverberaciones largas.

Todas las constantes están en `LIMITS`/`build_recipe`, y cada acción queda registrada por
archivo en `clean_report.json` (con ganancia aplicada, reducción de limitador y sha256).

---

## 6. Resultado medido

| métrica | antes | después |
|---|---|---|
| one-shots > −1,5 dBFS TP | 14 / 22 | **0 / 22** |
| pico real máximo del banco | **+0,03 dBFS** | −3,00 dBFS |
| dispersión `backfire_ext` | 6,35 LU | **0,00** |
| dispersión `impact_land` | 4,40 LU | **0,36** |
| dispersión `impact_small` | 1,80 LU | **0,24** |
| dispersión `impact_medium` | 1,36 LU | **0,03** |
| dispersión `gearbox_f2002` | 1,81 LU | **0,00** |
| `impact_scrape` cierre de loop | 1,61× | **0,02×** |
| energía <30 Hz `impact_small_1` | 14,0 % | 3,4 % |
| energía <30 Hz `impact_land_3` | 8,6 % | 2,2 % |
| DC máximo | −47,7 dBFS | −57,9 dBFS |
| canales | 1 estéreo | todos mono |
| duración total | 33,92 s | 33,86 s |

Detalle completo en `tmp/commons_clean_v1/clean_report.md`. La reauditoría del banco limpio
(`tmp/commons_audio_audit_after/commons_audit.md`) no encuentra nuevos defectos: lo que
queda son los dos problemas de contenido que el DSP no puede resolver (duplicados y los 6
WAV ausentes del manifiesto) más la dispersión de timbre entre variantes, que es una
decisión de contenido y no de procesado.

### Compensación opcional en `audio_mixer.json`

La limpieza **baja el nivel** de varias claves (es el precio de los 2 dB de margen). Si
quieres recuperar la presencia anterior sin rehacer el balance:

| clave | compensación sugerida |
|---|---|
| `impact_small_1..3` | **+3,5 dB** (0,55 → 0,83) |
| `impact_medium_1..2` | **+3,0 dB** (0,68 → 0,96) |
| `impact_large` | +0,5 dB |
| `impact_land_1..3` | **+3,0 dB** a las tres (mantiene la escalera de 3 dB) |
| `backfire_ext_1..4` (constante `BACKFIRE_VOLUME_DB`) | **+2,0 dB** (−10,0 → −8,0) |
| `BACKFIRE_CABIN_VOLUME_DB` | **+6,0 dB** (−6,0 → 0,0) |
| `LIMITER_GAIN` | +3,0 dB (0,225 → 0,318) |
| `neutral_first_gear_transition` volumen | 0,41 → 0,60 y bajar el HPF de 1 kHz a ~180 Hz |
| `tyre_contact`, `impact_scrape` | sin cambio |

Alternativa recomendada: **no compensar** y quedarse con los 2 dB de margen. En un juego
donde el motor y el escape ya van al límite, ocho eventos simultáneos con 2 dB menos suenan
mejor que un bus que bombea.

---

## 7. Lo que el DSP no arregla

1. **El clipping de `backfire_5` / `backfire_int`** (23 tramos planos a 0 dBFS) y de
   `backfire_9` / `ext_4` (15 tramos). Bajar el nivel no recupera la onda: hay que
   **re-exportar desde el FMOD original** o aceptar que esos dos sonidos tienen distorsión.
2. **Los duplicados**: `backfire_ext_1 == ext_2` no es un problema de DSP, es un set de
   samples incompleto. Con dos sonidos idénticos no hay variación posible; hay que traer 2
   disparos más del mismo escape.
3. **Los 6 WAV del manifiesto que no existen** (`gear_up/down_1..3`): o se generan, o se
   borran las entradas.
4. **`damaged_rin` sin usar**: o se añade a `WHEEL_DAMAGE_SAMPLES`, o se elimina del banco
   (213 KB y una entrada de manifiesto que nadie consume).
5. **La coherencia tímbrica de las familias** (centroides de 414 a 1851 Hz). El EQ estático
   disimula; un set coherente requiere seleccionar/grabar material del mismo origen.
6. **`impact_scrape` como loop**: el crossfade arregla el cierre, pero un decaimiento
   reiniciado cada 2,35 s sigue siendo audible como pulso. La solución de diseño es
   retrigger aleatorio con 2 voces solapadas, o un loop real de scrape.
7. **QOA en los `.import`**: hoy no afecta (el runtime lee el RIFF), pero conviene poner
   `compress/mode=0` en este banco: son 2,9 MB, y QOA sobre transitorios de impacto es
   tirar calidad a cambio de nada.

---

## 8. Cómo ejecutarlo

```powershell
# 1. Auditoría (no toca nada): informe + JSON + gráficos
python -m tools.audio.analyze_commons_bank --plots

# 2. Render de la limpieza a una carpeta aparte (con manifiesto parcheado)
python -m tools.audio.clean_commons_bank
#    -> tmp/commons_clean_v1/  (WAV + bank_manifest.json + clean_report.md/.json)

# 3. Reauditar el resultado
python -m tools.audio.analyze_commons_bank `
  --bank tmp/commons_clean_v1 --out tmp/commons_audio_audit_after

# 4. Comparativa visual antes/después
python -m tools.audio.render_commons_ab

# 5. Aplicar sobre el banco real (hace backup en _backup_pre_clean/)
python -m tools.audio.clean_commons_bank --in-place

# Variantes
python -m tools.audio.clean_commons_bank --ceiling -2.0      # 1 dB más de nivel, 1 dB menos de margen
python -m tools.audio.clean_commons_bank --no-groups         # solo limpieza, sin igualar niveles
```

---

## Anexo — definiciones y umbrales

- **LUFS**: ITU-R BS.1770-4, bloques de 400 ms con solape 75 %, gating absoluto −70 LUFS y
  relativo −10 LU. Para archivos <400 ms se mide el evento completo sin gating
  (`evLUFS` en el informe generado).
- **Pico real**: sobremuestreo 4× por FFT (interpolación sinc) del archivo completo; es el
  pico que verá el remuestreo 44,1→48 kHz de la salida.
- **Crest**: pico − RMS, en dB.
- **Seam ×**: `|x[0] − x[−1]|` dividido por el percentil 99 del paso entre muestras
  consecutivas. ≤1 es un cierre indistinguible del contenido; >2,5 es audible; >6 es click
  seguro.
- **Tramo plano**: ≥3 muestras consecutivas a menos de 1 LSB del pico, con |x| > 0,9995·pico.
- **Umbrales de aviso** (en `LIMITS`): pico real ≥ −0,3 dBFS, sub-30 Hz >5 %, DC >−45 dBFS,
  ruido de cabeza/cola >−65 dBFS, silencio inicial >30 ms, escalón de entrada >−20 dB del
  pico, dispersión de grupo >1,5 LU.
