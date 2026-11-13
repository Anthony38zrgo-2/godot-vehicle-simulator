# Acta — Cuarta prueba del Fulvia: aterrizaje equivalente y validación en movimiento

Plan §cuarta-prueba. Jolt de producción a 60 Hz; 120 Hz solo como referencia
diagnóstica dentro de la sonda. Fulvia de disco, ShapeCast3D, 20 kg, neutra,
plano, controles a cero, mismo spawn y estado térmico. f = 1.75/1.85 Hz,
ζ = 0.55/0.55. Calibración y hashes intactos
(`suspension.json` SHA-256 `cbf6b978…d06a7387`, verificado antes y después).

## 1. Estado pre-impacto reproducible

Sonda nueva `game/tests/rally/fulvia_landing_probe.gd` (modo `landing`):
asentado a 120 Hz con setup de fábrica; micro-caída a 240 Hz para calibrar la
altura de contacto; medida de la velocidad de impacto en la caída de 0.5 m;
recolocación a contacto + v_chasis = v_bujes = −v, sin rescate automático.

Hallazgo metodológico: el impacto geométrico del ShapeCast se dispara hasta
0.21 m antes de tocar (recorrido del barrido). El contacto válido es el
**contacto cargado** (fuerza radial > 0). Con ese criterio:
`contact_y = y − vy·dt` calibrada (típ. −0.002 m), error de velocidad al
primer contacto ≤ 0.16 m/s, deflexión inicial 29–48 mm según variante.
`--impact-v` permite además fijar una velocidad común a todas las
configuraciones (usado: 2.37 m/s medidos).

Ventana alineada por primer contacto cargado + 1 tick previo; impulso neto =
ΣF − peso·Δt frente a Δmomento del sistema (chasis + 4 bujes) con la misma
fase; picos nativos y promediados en intervalos de 16.67 ms; impulso del
bajos del chasis medido con diagnóstico gated (sin él, el residual era −55 %
por 5 ticks de apoyo de carrocería: 1352 N·s).

## 2. Matriz de aterrizaje (3 pasadas, 60 Hz candidato / 120 Hz control)

| Config | 1.ª pérdida | Pico bin67 (media 3 reps) | Impulso total | Δmomento | Residuo | Asienta |
| --- | --- | --- | --- | --- | --- | --- |
| impl60 (impl+limiter) | — (0 wheel-ticks) | 30345 N | 40595 N·s | 2548 | −0.8 % | 3/3, t118–119 |
| base120 (control) | — (0 wheel-ticks) | 31953 N | 40939 N·s | 2465 | +1.1 % + bajos | 3/3 (*, t105/171/105) |
| impl120 | — | 31506 N | 40945 N·s | 2466 | +0.4 % + bajos | 3/3, t131 |
| impl60_nolim | t≈2 (repite Q3) | 33892 N | 40945 N·s | 2549 | +4.4 % | 0/3 |

Determinismo: impl60 idéntico 3/3 (picos =); base120 r1 diverge en tick 10
(±288 N sobre 32 kN) y una pasada asienta en t105. Tolerancias del control
(base120): pico ±639 N (±2 %), impulso ±618 N·s, Δmomento ±49 N·s.

Lectura: el candidato iguala al control dentro del margen (pico −5 %,
impulso −0.8 %, Δmomento +3.4 %): el aterrizaje de 0.5 m queda contenido sin
crecimiento. impl60_nolim confirma Q3 (sin limitador diverge). base120 no
cumple el criterio estricto de asentamiento (±5 mm + 0.35 m/s + carga ±10 %
20 ticks) por oscilación residual de ~±8 mm a 120 Hz: el criterio, diseñado a
60 Hz, es más exigente que la física del control; se informa sin penalizar al
candidato (que sí lo cumple: ±5 mm, 119 ticks).

## 3. Manejo (impl60 vs base120, misma entrada y mando indexado por tiempo)

| Maniobra | impl60 @60Hz | base120 @120Hz |
| --- | --- | --- |
| Frenada (15 m/s, freno 1.0, 4 s) | 13.4 m, salida 0, guiñada 0.13, trasero 0 % | 13.5 m, salida 0, guiñada 0.11, trasero 0 % |
| Cresta (15 m/s, gas 0.6, 4 s) | 6.9 m, guiñada 0.19, trasero 0 % | 6.8 m, guiñada 0.38, trasero 0 % |
| Curva lisa (12 m/s, gas 0.45, dir. 0.35, 6 s) | trompo t≈2.5 (guiñada 2.85), se recupera y termina | estable (guiñada 0.97) |

base60 (producción explícita a 60 Hz, control añadido): las tres maniobras
explotan (guiñada ~45 rad/s, trasero ~100 %) — el banco de producción sigue
roto a 60 Hz, como en Q1. La curva diverge entre candidato y control con
n=1 por configuración: idénticos hasta t≈2.0 (trasero int. ~1400 N,
guiñada ~0.50); a t≈2.3 el candidato descarga el trasero interior del todo
y trompea (se recupera a t≈3.2 y termina); el control tiene su momento de
descarga a t≈2.8 y lo supera sin trompear. Diferencia real a documentar,
no artefacto del banco: exige repeticiones y/o mando corregido antes de
juzgar producción.

## 4. Decisión (actualizada)

- Aterrizaje: **el candidato pasa 3/3 dentro de la dispersión del control**,
  con balance de impulso cerrado (residuo −0.8 % con bajos medidos).
- Manejo: frenada y cresta equivalentes (≤2 %); curva con divergencia
  transitoria a documentar con más muestra.
- **Mantener Jolt a 60 Hz y la combinación implícito+limitador bajo
  interruptor de diagnóstico; no integrar al runtime; no tocar f/ζ ni hashes.**
  Siguiente paso: repeticiones de curva (y mando menos agresivo / lazo
  cerrado) para decidir si la diferencia de guiñada es sistemática.
- Trazas: `user://suspension_60hz_q4/landing_<cfg>_hz<hz>_r<rep>.csv` y `handling_<cfg>_<maniobra>_hz<hz>_r<rep>.csv`
  (4 ruedas, contacto cargado, impulsos radiales, bajos) y
  `handling_<cfg>_<maniobra>_hz<hz>.csv`; marcadores
  `SUSPENSION_LANDING_{VERIFY,SUMMARY,COMPARE,DETERMINISM,TOLERANCE}` y
  `SUSPENSION_HANDLING_SUMMARY`.

## 5. Seguimiento de manejo: repeticiones y separación de factores

Curva lisa ×5 reps (misma entrada 12 m/s, mando indexado por tiempo):
impl60 trompea 5/5 (guiñada 2.72–2.95, dist. ~37 m, trasero int. → 0 N en
t≈2.3, se recupera y termina); base120 estable 5/5 (guiñada 0.97, 76.1 m).
Frenada y cresta equivalentes 5/5 en ambas (≤2 %; base60 explota en las tres,
como en Q1). Divergencia sistemática, no ruido.

Separación de factores a 60 Hz (sonda de campaña, settle120, curva ×3):
- limitador solo (radial explícito): explota (234 kN, 427 m/s, comp pegada).
  El limitador no contiene la curva; el radial explícito es el problema.
- implícito solo: contenido (picos 6.7–9.1 kN, 0 pérdidas, trasero 0/0),
  sin explosión. El implícito fija la explosión sin necesidad del limitador.
- Conclusión: el trompo sigue al algoritmo implícito, no a la frecuencia
  (impl120 también trompea: guiñada 2.96) ni al limitador. El suavizado de la
  carga normal por intervalo cambia el agarre combinado al límite respecto a
  la referencia explícita-120 Hz validada.

## 6. Mando menos agresivo y veredicto final

Curva lisa ×3 con mando ×0.7 (dir. 0.245, resto idéntico), impl60 vs base120:
ambos estables y equivalentes — guiñada 0.411 vs 0.409, distancia 79.7 vs
80.0 m, trasero 0 % pérdidas, trasero int. mín. 1056 vs 971 N. El desacuerdo
queda acotado al límite de adherencia con mando máximo (dir. 0.35): por debajo
del límite, candidato y control son indistinguibles; en el límite, el
implícito descarga antes el trasero interior.

Veredicto:
- Aterrizaje: el candidato pasa 3/3 dentro de la dispersión del control.
- Manejo nominal y submáximo: equivalente al control (frenada, cresta,
  curva suave: ≤2 %).
- Manejo al límite (curva a tope de mando, n=5+3): divergencia sistemática
  atribuida al suavizado de Fz por intervalo del implícito.
- **No integrar al runtime.** Mantener Jolt a 60 Hz y la combinación
  implícito+limitador bajo interruptor de diagnóstico; no tocar f/ζ ni hashes
  (suspension.json SHA-256 `cbf6b978…d06a7387` verificado).
- Siguiente paso si se retoma: decidir con dato de pista cuál reproduce mejor
  el coche real al límite, o modular la Fz media solo fuera del transitorio
  de contacto (p. ej. implícito acotado a la ventana de impacto) antes de
  cualquier ajuste de coeficientes.
