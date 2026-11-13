# Acta — Segunda prueba del Fulvia: impulso radial y rebote del buje

Plan §segunda-prueba. Jolt de producción a 60 Hz; 120 Hz solo como control
diagnóstico. Fulvia de disco, ShapeCast3D, 20 kg, neutra, plano, controles a
cero, mismo spawn y estado térmico. f = 1.75/1.85 Hz, ζ = 0.55/0.55.
Calibración y hashes de producción intactos
(`suspension.json` SHA-256 `cbf6b978…d06a7387`, verificado antes y después).

## 1. Instrumentación (solo traza + interruptores de sonda)

- `scripts/physics/unsprung_suspension_rig.gd`: `impulse_trace` por rueda y
  tick (pre-estado a igual fase del callback, desglose radial y de suspensión
  por término del solver, fuerzas axiales sobre el eje de guía con signo del
  buje, impulsos J = F·dt) y `radial_viscous_scale` (1.0 = producción).
- `scripts/physics/tire_radial_model.gd`: parámetro `viscous_scale = 1.0`
  (bit-idéntico por defecto) aplicado al término viscoso en fuerza y
  disipación, conservando elástica, tope de llanta y unilateralidad.
- `game/tests/rally/fulvia_spawn_diagnostic.gd`: 3 pasadas limpias a 60 Hz +
  3 a 120 Hz (control), variantes `base/limiter/novisc/settled`, CSV por
  frecuencia+variante+repetición (`fulvia_spawn_hz*`, `fulvia_impulse_hz*`).
- `game/tests/rally/suspension_drop_rescue_probe.gd`: `--diag=base/limiter/
  novisc`, `--settle120` (asienta a 120 Hz, captura pose, re-arranca a 60 Hz
  con velocidades reiniciadas) y re-asentado con la variante activa antes de
  la pose de referencia.

## 2. Balance de impulsos de FL, ticks 0–10 (60 Hz, base, m = 19 kg)

m·Δv frente a ΣJ conocidos; residual = restricciones + solver.

| n | pre_v → post_v (m/s) | J_susp | J_rad | J_grav | ΣJ | m·Δv | residual |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | −0.16 → −2.71 | −45.3 | 0.0 | −3.1 | −48.4 | −48.4 | ≈0 |
| 2 | −2.71 → +7.10 | +78.8 | +110.7 | −3.1 | +186.5 | +186.5 | ≈0 |
| 3 | +7.10 → −9.59 | −314.1 | 0.0 | −3.1 | −317.2 | −317.2 | ≈0 |
| 4 | −9.59 → +25.10 | +375.9 | +286.4 | −3.1 | +659.1 | +659.1 | ≈0 |
| 5 | +25.10 → −42.10 | −1273.8 | 0.0 | −3.1 | −1276.9 | −1276.9 | ≈0 |
| 6 | −42.10 → +457.22 | +10127.2 | +2143.5 | −3.1 | +12267.6 | +9487.1 | −2780.5 (−29 %) |
| 7+ | — | — | — | — | — | — | domina restricción |

Ticks 1–5 cierran a ~0.00001 %. Desde el tick 6 (recorrido pegado a topes y
juntas) el residual de junta/solver domina (hasta −446 %). Conclusión: la
correspondencia fuerza(n)→velocidad(n+1) es exacta mientras la junta no
interviene; después, atribuir el rebote a una sola fuerza es incorrecto.

Reconstrucción del primer impacto (rueda 0, tick 2 ≡ solve 2): recorrido
físico −0.0425 m, distancia de apoyo 0.2896 m → road_compression −0.0096 m →
deflexión (−0.0096) − (−0.0425) = **0.0329 m** (13 mm de penetración inicial +
caída del buje). Radial: elástica 4907.6 + viscosa 1736.6 + tope 0.0 =
**6644.2 N**; suspensión: damper −6029.5 (rebote) + elástica 1300.9.

## 3. Rebote 1→2: el radial domina, el damper amplifica después

Tick 2 (FL −2.71 → +7.10 m/s, Δv +9.81): J_rad +110.7 (59 %) + J_damper +78.8
(42 %). El primer impulso radial es el que invierte al buje; el amortiguador
acompaña y en los ticks 3–5 toma el relevo (−314, +376, −1274 N·s).

## 4. Tabla por variante (240 ticks, reposo desde spawn salvo indicación)

| Hz | Variante | 1.ª pérdida apoyo (rueda) | Pico carga | Pico vel. axial | Topes FL | y final/máx |
| --- | --- | --- | --- | --- | --- | --- |
| 60 | base ×3 | tick 2 (FL) | 130 kN–1.28 MN | 751–760 m/s | 189–190 | 146–420 m |
| 60 | limiter | tick 2 (FL, transitorio) | 7673 N | 4.6 m/s | 0 | 0.00 / 0.02 m |
| 60 | novisc (viscoso ×0) | tick 2 (FL) | 111.8 kN | 764.8 m/s | 184 | 5.70 / 30.03 m |
| 60 | settled (pose 120 Hz) | tick 3 (FL) | 758.2 kN | 746.9 m/s | 190 | 197.36 m |
| 120 | base ×3 | — (sin anomalía) | 4041 N | 1.3 m/s | 0 | −0.02 / 0.02 m |
| 120 | limiter / novisc | — (sin anomalía) | 3896 / 4021 N | 1.3 m/s | 0 | −0.01 – −0.02 m |

- **limiter**: primer impulso radial idéntico (J_rad +110.7, sin cambio);
  primer rebote reducido un 31 % (Δv 6.77 frente a 9.81; J_damper 21.1 frente
  a 78.8); amplificación posterior suprimida → asienta. Solo cambia la
  amplificación, no el primer impulso ni el primer rebote completo.
- **novisc**: J_rad 81.8 (solo elástica) + J_damper 78.8 → Δv 8.29; explota
  igual (más lento, yMáx 30 m). La elástica sola basta como disparador.
- **settled**: explota desde la pose asentada (J_rad 84 → 252 N·s en los
  ticks 243–245) → la pose inicial no es la causa.

## 5. Caída 0.5 m y bache con limitador (antes de recomendar)

Exigido por el plan para cualquier variante que asiente en reposo:

- Desde re-asentado con limitador: caída 142 kN / 0.5 m, bache 127 kN;
  comp pegado, sin asentamiento en 150–180 ticks.
- Desde pose asentada a 120 Hz + limitador: caída **142 kN**, bache **127 kN**;
  tras el aterrizaje (t≈11, 7.6 kN) el segundo impacto (t≈17, 110 kN →
  Δv ≈ +95 m/s en un tick) relanza el ciclo; el limitador solo acota el
  amortiguador (a v = 95 m/s el propio tope permite 95 kN: evita la inversión,
  no la magnitud). La caída de 3.6 m de la primera medida era un artefacto
  de pose lanzada + rescate de sesión a −25 m (documentado, no válido).
- **Decisión: no recomendar.** El limitador estrecha la ventana de
  supervivencia (transitorio de spawn) pero no contiene aterrizajes: el
  impulsor es el radial sin acotar sobre 19 kg a dt = 16.7 ms.

## 6. Intervención siguiente (fuera de los 4 knobs)

Por este orden: **fuerza radial** (término y/o subpasos del contacto para el
buje ligero a 60 Hz; el tope `rim_stop` a 300 kN/m y la tangente ya llevan
mitigaciones parciales de 60 Hz en el propio modelo) → **restricción del
buje** (reacción de junta dominante desde el tick 6; el límite de impulso
actual solo mira masas traslacionales) → geometría de consulta y pose
(descartadas como causa: la explosión se reproduce desde la pose asentada).
Calibración f/ζ y hashes de producción: intactos, sin cambio justificado.
Validación en tramo: pendiente del fix del mecanismo.

Trazas: `user://suspension_60hz/fulvia_spawn_hz{60,120}_{base,limiter,novisc,
settled}_r{0..2}.csv`, `fulvia_impulse_hz*` (4 ruedas, todos los ticks),
`user://suspension_60hz_limiter{,2,_limset}/fulvia__{drop,bump}__base__fuel20.csv`;
logs `fulvia_diag2_campaign.log`, `fulvia_limiter_dropbump*.log`,
`fulvia_spawn_120.log`, `tire_closure.log`, `fulvia_spawn_hz60_base_r0.csv`
(30 ticks, balance impreso).
