# Acta — Tercera prueba del Fulvia: integración radial a 60 Hz

Plan §tercera-prueba. Jolt de producción a 60 Hz (120 Hz solo referencia
diagnóstica), ShapeCast3D, Fulvia de disco, 20 kg, neutra, plano, controles a
cero, mismo spawn y estado térmico. f = 1.75/1.85 Hz, ζ = 0.55/0.55.
Calibración y hashes de producción intactos
(`suspension.json` SHA-256 `cbf6b978…d06a7387`, verificado antes y después).

## 1. Prototipo (solo sonda, producción intacta)

- `tire_radial_model.gd`: parámetro `viscous_scale = 1.0` (bit-idéntico).
- `unsprung_suspension_rig.gd`: `radial_implicit_enabled = false` por defecto;
  `solve_radial_impulse()` — raíz acotada de J = dt·cos·F(δf, cf) con
  δf = max(0, δ0 − dt·vf), cf = −vf, vf = v_libre + J/m (v en separación,
  positiva al separar); reapertura declarada (J = 0 si δf(0) ≤ 0), fallback a
  explícito acotado, tope de llanta reutilizado. Llamadas repetidas al modelo
  con misma pose/velocidad = iteración de función, no subpasos.
- Aplicación una vez por tick como fuerza equivalente J/dt al buje;
  `normal_loads` = carga media F = J/(dt·cos) (la usa el modelo tangencial;
  se registran instantánea y media); proyección lateral sin cambios.

## 2. Matriz 60 Hz (3 repeticiones; arranque 240 ticks, caída/bache desde pose asentada a 120 Hz)

| Variante | Reposo: 1.ª pérdida / pico / vel / topes / y final | Caída 0.5 m: pico / comp / pérdidas / descarga | Bache: pico / comp / pérdidas |
| --- | --- | --- | --- |
| base | t2 / 130 kN–1.28 MN / 751–760 m/s / 189–190 / 146–420 m | 340 k–1.9 MN / 0.22 / ~580 / 64–95 | 340 k–1.6 MN / 0.22 / ~710 / 131–154 |
| limiter | t2 transitorio / 7.7 kN / 4.6 / 0 / 0.00 m | 110–160 kN / 0.22 / ~550 / 107–108 | 127 kN / 0.22 / ~700 / 149–151 |
| implicit | — / 3849 N / 0.62 / 0 / −0.020 m | mixto: 8307 N + 2×(1.2–1.9 MN) / — / — | 0.5–0.9 MN, diverge |
| **implicit+limiter** | **— / 3770 N / 0.62 / 0 / −0.014 m** | **8243–8277 N / 0.114→0.028 / 37–40 / 9–10** | **10–11 kN / 0.124–0.142→0.018–0.019 / 69–78, asienta t139–140** |

120 Hz referencia (base/limiter/implicit, ×3): sin anomalía, picos 3.8–4.0 kN,
y ≈ −0.016 m. Determinista por repetición en todas las variantes.

Respuestas al plan: el primer impulso radial NO cambia con el limitador
(J_rad +110.7 idéntico en tick 2); el primer rebote baja un 31 % y solo la
amplificación posterior queda contenida. Sin viscoso (J_rad 81.8 solo
elástica) diverge igual → la elástica basta como disparador. Desde pose
asentada diverge igual → la pose no es la causa. Implícito solo: a veces
contiene la caída (r1: 8307 N, descarga 12/11) pero diverge en el resto → no
robusto. **Solo implicit+limiter pasa las tres maniobras las tres veces.**

## 3. Balance y física (FL, ticks 0–10, implícito 60 Hz)

Raíz convergente (típ. <48 iteraciones, sin fallback, apertura declarada en
separación). Tick 2: J_rad 20.4 frente a 110.7 explícito; Δv +0.34 frente a
+9.8; cierre m·Δv = ΣJ a ~1e-5 todos los ticks. Reconstrucción: δ0 = 33 mm
→ J = dt·F(δf, cf) autoconsistente en lugar de dt·F(δ0, c0).

Comparación física con 120 Hz (base): estática por esquina idéntica (mismo
setup: 2905/2023 N), altura asentada −0.014 frente a −0.016 m, recorrido final
±5 mm (criterio de asentamiento cumplido en bache t139–140), impulso de
tierra del aterrizaje ≈ momento de la caída (0.5 m → 3410 N·s; exceso medido
íntegro sin amplificación), pico total 26.9 kN frente a 13.1 kN del apoyo
suave a 120 Hz (factor ~2 por la energía de caída, sin divergencia).

## 4. Decisión

- **Pasa con ambos cambios (implícito + limitador); ninguno basta solo.**
  Queda bloqueada por junta la variante explícita en todos los casos.
- No se tocan f/ζ ni hashes: `suspension.json` y su SHA-256 intactos.
- Contratos con el código final: `vehicle_simulation_correction` PASS,
  `tire_closure_plan` ALL TESTS PASSED.
- Recomendación: integrar el paso radial implícito + límite de impulso del
  amortiguador al runtime (optativo, por defecto producción) y repetir
  frenada, curva y cresta antes de cualquier ajuste de coeficientes.
  Validación en tramo: pendiente.

Trazas: `user://suspension_60hz/fulvia_spawn_hz{60,120}_{base,limiter,implicit,
implicit_limiter}_r{0..2}.csv` + `fulvia_impulse_*` (4 ruedas, todos los
ticks, con `rad_F_inst/mean`, `rad_J_imp`, `rad_iters/fallback/opening`),
`user://suspension_60hz_t3{_base,_limiter,_implicit,_implimit,_clean_*}/
fulvia__{drop,bump}__base_r{0..2}__fuel20.csv`; logs `fulvia_t3_*.log`,
`fulvia_diag2_campaign.log`.
