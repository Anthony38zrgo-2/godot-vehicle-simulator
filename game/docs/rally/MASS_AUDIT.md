# Auditoría de masas e inercias §5 + H4 (sin cambiar calibración)

Fecha: 2026-11-12 (H4: 2026-11-12). Herramienta: `game/tests/rally/mass_audit_probe.gd`
(`godot --headless --path game --script res://tests/rally/mass_audit_probe.gd`).
Emite `RALLY_MASS_AUDIT <json>` por perfil y `RALLY_MASS_REST <json>` para
Escort (referencia) y Fulvia (discrepancia). No muta calibraciones.

H4: cada estado registra por separado el tensor escalado ANTES del recorte
(`inertia_tensor_scaled`), sus momentos principales
(`inertia_principal_moments`, autovalores de Jacobi), la diagonal aplicada a
Jolt (`inertia_applied_diagonal` = `inertia_diagonal`), si hubo corrección
(`inertia_corrected`: mínimo de 10 o triangular) y la desigualdad triangular
evaluada con los momentos principales (`triangular_principal_ok`).
Las cargas de reposo se etiquetan `nominal_static_profile`
(`static_sums_nominal: true`): calculadas del perfil, no medidas en pista.

## Contrato pendiente (no cambiar sin acordar fichas)

- `target_cg_z_m` (alias `target_cgz_m`) se aplica al eje **Y local (altura)**,
  no al Z longitudinal, aunque su nombre sugiere Z. El contrato del
  inventario es "Body -Z forward, +Y up": Z = longitudinal (reparto), Y =
  altura. Valores por perfil (~0.44–0.545 m) confirman altura; una posición
  longitudinal estaría cerca de 0 entre ejes (-1.2…+1.2 m). No reubicar el
  tanque ni reinterpretar este campo sin resolver compatibilidad de perfiles.
- `front_weight_distribution` actúa sobre Z longitudinal:
  `want_z = rear_z - fdist * wheelbase`. X nunca se recentra.
- Límites de recentrado: `shift.z` en [-0.45, +0.45] m, `shift.y` en
  [-0.20, +0.20] m. Solo actúan si el target lo exige y la distancia entre
  ejes supera 0.5 m (reparto). La sonda registra `recenter_clamped` cuando el
  clamp recorta el desplazamiento pedido.
- Tanque: la estructura (`fuel_tank_and_fire_system`, p. ej. Escort z=1.05)
  y el líquido (`fuel.tank_position_local_m`, p. ej. Escort z=1.40) son
  posiciones distintas; el `resolve()` usa el líquido + slosh. Indicar en
  cada ficha qué masa/condición (vacío/inicial/lleno) representa su objetivo.
- Inercias de rueda: `autorada` = suma de componentes `rotating_wheel`
  (dato); `fallback_sustitucion` = ausencia de dato (<=0.05) → `max(0.55·m·r²,
  0.35)`; `elevada_minimo` = `max(autorada, fallback·0.5)`. Elevar I reduce
  la aceleración angular ante el mismo par (α = T/I): cuantificar antes de
  tocar la política.
- Tensor completo vs diagonal aplicada: `rally_escort_vehicle` aplica solo
  la diagonal a Jolt (`RigidBody3D.inertia`); los productos (xy, xz, yz) se
  reportan pero se descartan. Proponer ejes principales solo si las
  diferencias lo justifican y tras verificar el marco de Jolt.

## Tabla reproducible (resumen 2026-11-12)

Suma de cargas = peso total en reposo: OK en los 11 perfiles.
Triangulares: OK en los 11. Inventario no-rueda cierra con presupuesto
(≤1 kg) en los 11. Referencia Escort: OK. Discrepancias vistas: sí
(clamp y/o off/diag > 0.10 en Fulvia).

| perfil | sprung inicial kg | total inicial kg | COM inicial (x,y,z) | fdist susp/inicial | shift (y,z) | clamp | I diag inicial | off/diag |
|---|---|---|---|---|---|---|---|---|
| ford_escort_rs2000_1971 | 925 | 1120 | (-0.001, 0.504, -0.009) | 0.504/0.483 | (0.0024, 0.0479) | true | (866, 990, 172) | 0.052 |
| lancia_fulvia_1600_hf | 930 | 1006 | (0.003, 0.473, -0.240) | 0.603/0.595 | (-0.0257, -0.0053) | false | (653, 771, 129) | 0.172 |
| rt-mini-cooper-s | 765 | 865 | (0, 0.439, -0.161) | 0.579/0.568 | (-0.0164, -0.0476) | false | (653, 691, 222) | 0.022 |
| rt-lancia-stratos | 1040 | 1140 | (0, 0.429, 0.200) | 0.408/0.417 | (-0.0098, 0.0342) | true | (858, 904, 320) | 0.016 |
| rt-alfa-giulia-gta | 895 | 995 | (0, 0.468, 0.019) | 0.492/0.493 | (-0.0140, 0.0145) | false | (1069, 1115, 299) | 0.005 |
| rt-alpine-a110 | 855 | 955 | (0, 0.424, 0.271) | 0.371/0.384 | (-0.0146, 0.2221) | true | (847, 885, 248) | 0.008 |
| rt-fiat-abarth-1000 | 775 | 875 | (0, 0.444, 0.186) | 0.407/0.417 | (-0.0162, 0.1316) | true | (665, 703, 218) | 0.010 |
| rt-lotus-cortina | 1065 | 1165 | (0, 0.508, -0.034) | 0.513/0.512 | (-0.0117, -0.0431) | true | (1150, 1205, 312) | 0.008 |
| rt-opel-kadett | 960 | 1060 | (0, 0.513, -0.029) | 0.512/0.511 | (-0.0130, -0.0359) | false | (1241, 1296, 333) | 0.003 |
| rt-saab-96-v4 | 962 | 1062 | (0, 0.522, -0.241) | 0.596/0.587 | (-0.0130, -0.1379) | true | (1227, 1273, 320) | 0.017 |
| rt-volvo-amazon | 1250 | 1350 | (0, 0.543, -0.037) | 0.514/0.513 | (-0.0099, -0.0485) | false | (1576, 1648, 397) | 0.001 |

Notas: Fulvia muestra el mayor off/diag (0.17, producto yz ≈ -20) y es el
candidato para mostrar la discrepancia; Alpine/Fiat tienen el mayor shift.z
(0.22/0.13 m por objetivos de reparto 0.36/0.40). Todas las ruedas usan
inercia `autorada` (ninguna sustitución por ausencia en estos perfiles).

## Reposo nominal H4 (2026-11-12, combustible registrado)

Condición `initial`: Escort 25.00 kg, Fulvia 20.00 kg. Suma nominal = peso
en ambos (err 0.0). La distribución estática es simétrica por eje (precarga
con reparto solo longitudinal desde COM suspendido), así que los momentos
difieren del COM total (no suspendido + combustible): se reportan.

| perfil | suma nominal (N) | peso (N) | Mz estático | Mz COM total | Mx estático | Mx COM total |
|---|---|---|---|---|---|---|
| escort_referencia | 10976.0 | 10976.0 | 449.28 | 449.28 | 0.0 | -7.64 |
| fulvia_discrepancia | 9858.8 | 9858.8 | -2328.68 | -2187.83 | -0.0 | 30.46 |

Fulvia muestra la discrepancia (momento longitudinal -6.4% por reparto
suspendido vs total). Escort coincide en Mz; Mx refleja el offset del
piloto (cargas simétricas vs COM.x ≠ 0): limitación conocida, documentada.

## Condición de referencia (a acordar)

No cambiar calibraciones hasta acordar si los objetivos de ficha
(`front_weight_distribution`, `target_cg_z_m`, `vehicle_mass`) corresponden
a vacío, carga inicial o lleno, y si el COM objetivo incluye no suspendido.
La sonda ya registra las tres condiciones por perfil.
