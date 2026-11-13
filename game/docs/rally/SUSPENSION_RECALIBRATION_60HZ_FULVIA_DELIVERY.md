# Acta de entrega — Recalibración 60 Hz, primera entrega (Fulvia)

Aplica `SUSPENSION_RECALIBRATION_60HZ_PLAN.md` (§Instrucciones del agente,
primera entrega, Fulvia). Alcance acotado al Fulvia; el resto de perfiles es
etapa posterior.

## 0. Punto de partida (sin cambios publicados)

`game/data/vehicles/lancia-fulvia/suspension.json` (disco, verificado):

| Eje | `ride_frequency_hz` | `damping_ratio` |
| --- | --- | --- |
| Delantero | 1.75 | 0.55 |
| Trasero | 1.85 | 0.55 |

SHA-256 `suspension.json` = `cbf6b978aaeeb401788a893790185df4d8aafe3ba07963305baa4358d06a7387`,
coincide con `HISTORICAL_PROVENANCE.json → profile_json_sha256.suspension.json`
(verificado antes y después de la campaña; el fichero no se modificó).
`profile_id = lancia_fulvia_1600_hf`, Jolt, `physics_ticks_per_second = 60`,
`contact_query_type = ShapeCast3D × 1`, `maximum_substep_s = 0.0028`
(6 subpasos/tick), compuesto `gravel_normal`, combustible 20 kg (fábrica),
ambiente 25 °C / carcasa 60 °C iniciales iguales entre pasadas.
Cabecera por pasada: `SUSPENSION_PASS_HEADER` (profile_id, Jolt, 60 Hz,
`tandem_cam_enabled == false`, `session_generation` incremental).

## 1. Línea base (desde disco, 20 kg)

Sonda: `game/tests/rally/fulvia_spawn_diagnostic.gd` (spawn desde tick 0) y
`game/tests/rally/suspension_drop_rescue_probe.gd`
(`--profiles=fulvia --fuel-kg=20.0`, base 1.75/1.85 Hz, ζ 0.55/0.55):

- `rest`, `drop` (0.5 m), `bump` (unilateral) × 3 repeticiones: deterministas.
- `brake`, `corner`, `exit_ramp`, `crest` × 1.
- Todas las pasadas: tick efectivo 60 Hz (`hz_measured = 60.0`,
  `tick_monotonic = true`), fuerzas finitas a nivel de registro.

Resultado: el banco NO asienta. Reposo con ~790/960 wheel-ticks en topes y
960/960 pérdidas de apoyo; caída/bache con descarga trasera total
(150/150, 180/180); frenada/distancias y velocidades de salida absurdas
(brake 1263 m, exit 147–330 m/s: el coche vuela).

## 2. Primer tick anómalo y primera rueda (60 Hz, spawn tick 0)

`user://suspension_60hz/fulvia_spawn_hz60.csv` (fábrica, 20 kg, marcha 0):

| Tick | Hecho (4 ruedas) |
| --- | --- |
| 0 | Spawn a y = 0.017 m, todo cero, contacto geométrico sí, carga 0. |
| 1 | Deflexión radial 33/33/18/18 mm → carga 6644/6631/3733/3720 N (≈2.4× la estática) con bujes de 19 kg. |
| 2 | **Primera anomalía: rueda 0 (FL) pierde apoyo tras contactar** (`support_loss`). Rebote: vel. +7.7/+7.7/+4.9/+4.9 m/s, damper +13.2/+13.1/+9.6/+9.5 kN, carga 0. |
| 3 | Reimpacto: deflexión 74/74/64/63 mm → 17.2/17.0/14.8/14.6 kN, damper −22.6/−22.4/−18.9/−18.7 kN. |
| 4 | Recorrido pegado al tope (+0.22 m), vel. 24–26 m/s, damper +44/+44/+46/+45 kN, topes +18/+21/+18/+21 kN. |
| 5 | Deflexión 0.32 m → **carga 128–131 kN (≈45× estática)**, damper −99/−99/−122/−120 kN. |
| 6–7 | Vel. 460–500 m/s, damper 0.8–1.2 MN, chasis y 0.17 → 0.99 m. |
| 240 | Chasis a **y = 420 m**. |

Cadena causal: radial (kt = 180000 N/m, ct = 1100 Ns/m) × buje 19 kg a
dt = 16.7 ms → Δv ≈ 6 m/s por tick → el amortiguador digresivo (c≈3356/2397,
codo 0.15 m/s) devuelve decenas de kN al buje ligero → explosión acoplada.
A 120 Hz (`--hz=120`, mismo setup): **sin anomalía en 240 ticks**,
asentado en y ≈ −0.016 m con cargas 1700–3200 N y recorridos ±5 mm
(`fulvia_spawn_hz120.csv`). La nota de provenance
("120 Hz minimum Jolt world step for the lighter 19 kg hub assemblies")
queda confirmada empíricamente.

## 3. Barridos f y ζ a 60 Hz (persisten con cambios moderados)

- f por eje ±5 %/±10 % (ζ fija), `rest`: 9 candidatos → todos con recorrido
  pegado al tope, ~710–800 wheel-ticks en topes, ~943–960 pérdidas, sin
  asentar (picos de hasta 293 kN).
- ζ 0.45/0.50/0.60/0.65 por eje (f nominal), `rest`+`drop`: 18 ejecuciones →
  idéntico colapso (picos de hasta 1.55 MN, p. ej. `zR_m10` en caída).
- Conclusión §2–§4 del plan: la divergencia nace en el mecanismo de
  contacto/radial + buje ligero (tick 1–2) y **persiste con cambios moderados
  de f y ζ**. Se documenta el primer tick y la evidencia antes de ampliar el
  alcance; no se elige calibración f/ζ.

## 4. Decisión de publicación (paso 5)

- Valores aceptados = línea base (1.75/1.85 Hz, ζ 0.55/0.55): **sin cambio
  justificado dentro de los 4 knobs**. `suspension.json` no se modifica;
  su SHA-256 sigue coincidiendo con la provenance (verificado arriba).
- No se tocó ningún directorio `*-upgrade` (verificado: no son perfiles
  cargables, sin `vehicle.json`).
- Contratos desde disco: `vehicle_simulation_correction_contract.gd` → PASS;
  `tire_closure_plan_contract.gd` → ALL TIRE CLOSURE PLAN TESTS PASSED.
- Repetición desde disco: la propia línea base se ejecutó con perfiles
  cargados desde disco (el fichero nunca se escribió durante la campaña).

## 5. Trazas y reproducción

- CSV por tick: `user://suspension_60hz/fulvia_spawn_hz60.csv`,
  `fulvia_spawn_hz120.csv`, `fulvia__rest|drop|bump__base_r[0-2]__fuel20.csv`,
  `fulvia__rest__f[F|R]_[m|p][05|10]__fuel20.csv`,
  `fulvia__rest|drop__z[F|R]_[m|p][05|10]__fuel20.csv`,
  `fulvia__brake|corner|exit_ramp|crest__base__fuel20.csv`.
- Logs: `fulvia_baseline_static.log`, `fulvia_baseline_driving.log`,
  `fulvia_sweep_f_rest.log`, `fulvia_sweep_z.log`, `fulvia_spawn_120.log`,
  `tire_closure.log` (en `%TEMP%` de la máquina de campaña).
- Comandos:
  - `godot --headless --path game --script res://tests/rally/fulvia_spawn_diagnostic.gd -- --hz=60 --ticks=240`
  - `godot --headless --path game --script res://tests/rally/suspension_drop_rescue_probe.gd -- --profiles=fulvia --maneuvers=rest,drop,bump --fuel-kg=20.0 --sweep=none --repeats=3`
  - `... -- --profiles=fulvia --maneuvers=rest --fuel-kg=20.0 --sweep=f`
  - `... -- --profiles=fulvia --maneuvers=rest,drop --fuel-kg=20.0 --sweep=z`

## 6. Validación pendiente y propuesta

- En pista (tramo reportado): pendiente; sin banco estable a 60 Hz no hay
  calibración que confirmar en manejo.
- Mecanismo a investigar (fuera de los 4 knobs): acoplamiento radial/buje
  ligero a dt = 16.7 ms (amortiguación radial, tratamiento por subpasos del
  contacto, límite de impulso radial análogo al del damper, o revisión del
  alcance de ShapeCast). Candidata mínima: reproducir el diagnóstico de
  spawn con instrumentación del impulso radial por tick antes de reabrir la
  búsqueda f/ζ.
