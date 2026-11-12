# Handoff — Plan de corrección del modelo de neumático

Fecha: 2026-11-12. Rama de trabajo: `game/scripts/physics/tire_model.gd`,
`profile_loader.gd`, `vehicle_simulation.gd` (+2 contratos de test).
Estado: implementación parcial. Los puntos 3 y 4 tienen implementación.
Los puntos 2 y 5–9 tienen cambios adicionales descritos en §4.
Verificación tras esos cambios: los contratos de migración combinada y
contacto estático pasaron en Godot 4.7.1 headless.

---

## 1. Plan original (observaciones recibidas)

### 1.1 Bugs concretos (1–9)

1. `rotate_patch_frame` nunca inicializa el frame → compensación de rotación
   como no-op permanente; fuerzas fantasma al girar, en horquillas, parking y
   aterrizajes con volante girado. Pedía además ortonormalizar (Gram-Schmidt).
2. `effective_slip_angle/ratio` inertes: no alimentan la fuerza, solo
   `lat/lon_tau`, que solo les afectan a ellos. `min_relaxation_tau_s` y
   `relaxation_recovery_scale` sin efecto sobre fuerzas. `_output()` devuelve
   slips instantáneos, no efectivos.
3. `renewal_rate` ignora el deslizamiento lateral (`maxf(|Vx|, |rim|)`):
   con rueda bloqueada y coche deslizando de lado no hay renovación y la
   deflexión lateral integra sin freno.
4. Relief legacy: discontinuidad en `patch_pos.x = 0`, solo trasero y activo
   por defecto (default 0.3), clave `combined_lateral_peak_migration`
   sobrecargada (relief en legacy, migración en v2).
5. Rodadura: `state.rolling_force` sin reescalar tras renormalizar el
   presupuesto (potencia térmica mal); `signf(Vx)` con umbral 0.05 (jitter);
   sin escalado por rueda bloqueada.
6. `patch_energy = 0.5·brush·patch` usa fuerza saturada en vez de demanda
   elástica; el `maxf(..., 0.0)` tapa el síntoma.
7. Huella con offset en estático: término de carga relativo (`load_ratio-1`)
   pero deflexión absoluta (`deflection_ratio`), doble conteo (~+2-4 %).
8. Óptima de carcasa divergente: `TireModel` la resuelve por filtro,
   `TireRadialModel.evaluate` la relee del JSON crudo.
9. Signo de camber ambiguo (`camber * (1 if index in [0,2] else -1)`) y
   `tan()` sin clampear.

### 1.2 Modelo radial (detalles)

Piso `maxf(damping_ratio, 0.18)` silencioso; clamp `load_sensitivity_exp` a
`[0.08, 0.25]`; piso `maxf(elástico+viscoso, elástico*0.15)` (soporte falso,
debería ser `maxf(..., 0.0)`); `stiffness_n_m` secante sin seating ni tope;
`evaluate()` completa solo por una rigidez (despilfarro → `static stiffness`
+ caché); amortiguación con tangente al entrar el tope (riesgo a 60 Hz).

### 1.3 Lo que falta (ordenado por retorno/esfuerzo según el plan)

Modelo de parado · radio efectivo acoplado a deflexión · pico de slip
dependiente de carga · trail ligado a huella dinámica · aquaplaning con
velocidad (charcos ya lo tienen vía `PuddleModel`, falta película fina) ·
hielo mojado (rama `ice` ignora agua + se salta el clamp) · ventana térmica
por compuesto (matiz: óptimas ya existen y el térmico las aplica; falta
mu/pico/rigidez/desgaste) · envolvente (tandem-cam) · substepping rueda↔
neumático (matiz: ya existe hasta 500 Hz, verificar que el lazo corre dentro)
· hacks de balance a geometría · curva estacionaria vs memoria
(`_pure_curve` muerta).

### 1.4 Rendimiento y robustez

~5 dicts por rueda y tick, `Array[Dictionary]` con claves string,
`states[index] = state` no-op, `_pure_curve`/`_brush_force`/
`_combined_budget_scale` muertos, `set_wheel_compound` falla con catálogo
vacío, `contact_ramp_tau_s` con ramp-down inútil + patinada al aterrizar,
`_advance_unloaded`/`reset_patch` con restos, `missing_surface_warnings` sin
limpiar en `configure()`.

### 1.5 Orden propuesto por el plan

Bugs 1–3 → 5–6 (energía/térmico) → 4 + hacks → baja velocidad → resto.
Plan de validación: barridos Fx(κ)/Fy(α) a 3 cargas, invariancia de
framerate, elipse combinada, escalón de dirección (τ ≈ L/V), balance
energético, simetría FL/FR con camber espejado, parado en pendiente < 1 mm/s
tras 10 s, aterrizaje con volante girado.

---

## 2. Veredictos de la revisión previa (antes de tocar nada)

| # | Veredicto | Evidencia |
|---|---|---|
| 1 | **Rechazado** — no reproduce | `rotate_patch_frame` asigna el frame **fuera** del guard (`tire_model.gd`, antes L741-742). El primer tick tras salto inicializa sin rotar (correcto: el patch es cero). El caller ya pasa vectores ortonormales (`vehicle_simulation.gd:846-850`). Solo queda hardening defensivo opcional |
| 2 | **Confirmado** (+ hallazgo: `combined_*_migration` delanteros también inertes — sin v2 delante, la rama legacy solo mira `index>=2`) | `tire_model.gd` L417-424, `_output()` L844-845 |
| 3 | **Confirmado** | L515 vs L373 |
| 4 | **Confirmado** (matiz: con los JSON actuales la rama legacy está muerta — trasero lleva v2, delantero excluido por índice; muerde a perfiles custom con v2 off) | L598-604 |
| 5 | **Confirmado** | L666-696 |
| 6 | **Confirmado** | L662, L692-695 |
| 7 | **Confirmado** | L395-400 |
| 8 | **Confirmado**, impacto acotado (clamp ±12 % en el radial) | `tire_model.gd:193-197` vs `tire_radial_model.gd:38` |
| 9 | **Confirmado** como defecto de contrato (numéricamente seguro con valores actuales) | `tire_model.gd:510`, `suspension_model.gd:292-295` |

Contratos de integración verificados (el autor ofrecía pasar el código; ya
está leído): camber espejado con convenio implícito izquierda-negativa,
`wheel_radii` fijo desde `radius_metres` del manifest (sin acoplo a δ),
`rolling_force_n` como reacción `(fx+rolling)·radio` en
`vehicle_simulation.gd:922` (diseño coherente, el bug 5 solo rompe la
reconstrucción bajo renormalización), substeps de hasta 500 Hz ya existentes.

---

## 3. Implementado

### 3.1 Puntos 2+3 — `tire_model.gd`, `vehicle_simulation.gd`

- `transport_speed = maxf(planar_speed, |rim|)` (L527): la renovación planar
  incluye el lateral (punto 3).
- `min_relaxation_tau_s` acota la renovación (`renewal ≤ 1/min_tau`, L530) y
  `relaxation_recovery_scale` la modula cuando la demanda baja
  (`lat/lon_recovering`, L532, mismo convenio que `lat/lon_tau`): ambos
  parámetros ya mueven las fuerzas (punto 2). El filtro `effective_slip` se
  mantiene intacto (misma dinámica) para no romper tuning existente.
- `_output()` añade `effective_slip_ratio` / `effective_slip_angle_rad`
  (L906-907) sin cambiar las claves instantáneas (las usan VFX/audio/HUD);
  el snapshot por rueda publica también las efectivas
  (`vehicle_simulation.gd`, junto a `slip_ratio`).
- Seguro para contratos: las mediciones con `delta = 0` tienen `renewal = 1`
  sea cual sea la tasa; el warmup a Vx=15 no cambia (recuperación inactiva).

### 3.2 Punto 4 — `tire_model.gd`, `profile_loader.gd`, contrato

- Rama legacy reescrita (L614-627): `smoothstep(-blend, +blend, patch_pos.x)`
  con `legacy_relief_blend_m` (default 0.01 m), opt-in por eje vía
  `legacy_longitudinal_relief` (**default 0 = off**, modelo neutro), sin
  `index >= 2`. La rama legacy **ya no lee** `combined_lateral_peak_migration`.
- Claves registradas en `TIRE_FORCE_KEYS` (`profile_loader.gd:99-100`) para
  que `tire_filters.json` pueda fijarlas por eje.
- Test `[2b]` en `tire_combined_migration_contract.gd`: sonda determinista
  (paso grande `delta = 0.5` a velocidades cero — el patch se conserva
  bit-idéntico mientras la memoria post-pico salta a su objetivo). Fija clave
  vieja inerte, opt-in graduado 0 < 0.15 < 0.3, igualdad en frenada y
  per-eje (delantero incluido).

**Decisión clave del camino:** el primer test medía con `delta = 0` y daba
ratio 1.0 — el relief solo alimenta el *objetivo* de decaimiento (integrado
con `slip_loss_tau_s`), invisible en un paso congelado. De ahí la sonda de
paso grande. Segunda calibración: el preset debe caer en la banda de
transición (theta ≈ 0.83); saturado, ambos modelos pinchan en target = 1 y
solo se ve el residuo del reparto lat/lon (~0.07 %).

### 3.3 Modelo de parado — `tire_model.gd` + contrato nuevo

- Rama estática anclada (L700-724): Kelvin-Voigt sobre el mismo `patch_pos`
  (`stiffness·patch + damping·slip_vel`, rigidez post-migración),
  tope Coulomb duro a la elipse **con slide** (la memoria post-pico y el
  relief siguen fluyendo — el contrato de migración sigue verde con la rama
  activa), mezcla por `transport_speed` (burnout y bloqueos deslizando quedan
  dinámicos): estático ≤ 0.25 m/s, dinámico ≥ 1.25 m/s.
  Amortiguación `c = 2·ζ·√(k·m)`, `ζ = 0.5`, ponderada por `static_w²` para
  no apelmazar salidas en la banda. Constantes arriba del fichero (L11-13),
  sin superficie de tuning por coche (decisión: física-núcleo, no calibración).
- **Corrección de signo durante la implementación:** la fuerza sobre el coche
  sigue a la deflexión (`+k·patch`, como el brush), no la opone. El probe lo
  pilló.
- **Rampa de rodadura por giro** (L727, 1 línea, prerrequisito descubierto
  por la sonda): `rolling *= clamp(|rim|/0.5)`. Sin rotación no hay
  histéresis; elimina la patada de `signf` a 5 cm/s que sostenía el ciclo
  límite en parado (11 oscilaciones con la rama estática sola). El
  `tanh(Vx/0.3)` queda para el punto 5.
- Nuevo `game/tests/rally/tire_static_contact_contract.gd` (5 checks):
  muelle con signo correcto, breakaway acotado (~3030 N a Fz=3000), burnout
  dinámico, **pendiente 10 % bloqueada: v≈2e-8, transitorio < 6 cm/s,
  < 1 mm/s tras 10 s** (criterio del plan), frenada 2→0 sin chatter físico.
- Nota: queda micro-dither `float32` (~1e-9 m/s) al asentarse; el contrato
  mide amplitud (< 1 mm/s), no cruces de signo.

---

## 4. Estado actual y orden de trabajo pendiente

Los apartados anteriores conservan el plan original y la primera entrega.
Esta sección recoge los cambios posteriores y los criterios de cierre.

1. **Relajación y migración (2–4).** La renovación incluye velocidad lateral.
   La integración separa las constantes longitudinal y lateral, aplica el
   mínimo después del factor de recuperación y conserva la deflexión objetivo
   estacionaria. Los slips efectivos publicados conservan su filtro propio.
   Faltan barridos Fx(κ)/Fy(α) a tres cargas, escalones por eje y combinados,
   comparación entre pasos físicos, sonda con Vx=0, Vy distinto de cero y
   rueda bloqueada, y barrido de relief opt-in dentro de la banda alrededor
   de cero.
2. **Rodadura y energía (5–6).** La rodadura usa la rampa por giro y
   `tanh(Vx/0.3)`. El mismo factor de presupuesto escala la rodadura usada
   para reconstruir la reacción y calcular calor. La energía almacenada
   usa `0.5 * trial.dot(patch_pos) * blend`. Falta verificar el balance
   energético con contacto estático y dinámico, proyección plástica,
   rigidez variable y pérdida de contacto. Medir el residuo antes de
   decidir cómo sustituir el clamp de potencia.
3. **Huella, carcasa, camber y radial (7–9).** La huella usa una deflexión
   de referencia por rueda calculada a carga estática y presión caliente
   de referencia. El trail ya escala con la huella dinámica. El radial
   recibe la óptima resuelta en el rig y en el fallback del neumático.
   El argumento de `tan()` se acota a ±0.5 rad. La fuerza radial puede
   caer a cero durante la descarga y el fallback se omite cuando llega
   deflexión del rig. Falta explicitar el convenio de camber en la firma,
   probar simetría FL/FR y comprobar la huella a carga de referencia en
   ambas rutas. Quedan pendientes la revisión de pisos y clamps de
   calibración, el contrato de rigidez base frente a secante y tangente,
   y la estabilidad de la amortiguación al entrar el tope con el paso
   físico del rig.
4. **Aceptación con vehículo completo.** Neumático y rotación ya se
   resuelven dentro del mismo bucle de subpasos. Verificar pendiente,
   frenada con giro inicial y freno real, elipse combinada e invariancia
   al paso físico, y aterrizaje con dirección aplicada. La sonda de
   pendiente existente aplica 0.17 × peso a una rueda y observó
   0.061655 m/s de máximo transitorio y menos de 1 mm/s al asentarse.
   La sonda de frenada impone rueda bloqueada desde el inicio. El punto 1
   original de inicialización del frame sigue descartado.
5. **Extensiones de física.** Acoplar el radio efectivo a la deflexión y
   usarlo de forma coherente en velocidad de llanta y par. Después calibrar
   el pico dependiente de carga. Quedan película de agua dependiente de
   velocidad, hielo mojado, respuesta térmica por compuesto en agarre,
   pico, rigidez y desgaste, envolvente y traslado de hacks de balance a
   geometría. Revisar el efecto de la película junto al modelo de charcos
   para evitar aplicar dos veces la misma pérdida de agarre.
6. **Robustez y rendimiento.** `configure()` ya limpia
   `missing_surface_warnings`. Quedan revisar asignaciones por tick,
   estados tipados, funciones sin uso y autoasignaciones, rampa de
   contacto, estado residual tras descarga o reset y el contrato del
   catálogo vacío. Decidir el destino de `_pure_curve` tras validar
   las curvas estacionarias.

## 5. Cómo verificar

```powershell
godot --headless --path game --script res://tests/rally/tire_combined_migration_contract.gd
godot --headless --path game --script res://tests/rally/tire_static_contact_contract.gd
godot --headless --path game --script res://tests/rally/tire_closure_plan_contract.gd
godot --headless --path game --check-only --script res://scripts/physics/tire_model.gd
```

Tras la última implementación se volvieron a ejecutar los dos contratos
en Godot 4.7.1. La comprobación de sintaxis independiente se había ejecutado
en la revisión anterior.

---

## 6. Cierre — TIRE_MODEL_CLOSURE_PLAN (2026-11-12, Escort de referencia)

Contrato: `game/tests/rally/tire_closure_plan_contract.gd`
(ALL TIRE CLOSURE PLAN TESTS PASSED en Godot 4.7.1 headless).
Sin regresiones: migración combinada, contacto estático, handoff
acceptance, puddles, dynamic_weather_tires y compound_thermal_regression
siguen verdes. Resultados Escort registrados antes/después de cada cambio;
la única variación deliberada de calibración es el transitorio de pendiente
(0.061655 → 0.0538 m/s a 60 Hz / 0.0531 a 120 Hz, desplazamiento 0.005 m):
radio efectivo del mismo subpaso (antes paso previo) + segunda elipse
instantánea (en estacionario converge a Fz y no cambia nada).

1. **Cota instantánea + reset.** Segunda elipse con Fz instantánea, mismas
   capacidades direccionales, caída post-pico y rampa; mismo factor sobre
   Fx neta, Fy y rodadura. Descarga 3500→200 N, aterrizaje 0→4000 N en
   5 ms con dirección y frenada con giro: u_instantánea ≤ 1.001 en todo
   subpaso con contacto; en aire fuerza/par nulos. Despegue y `reset_patch`
   invalidan envolvente + geometría derivada (parche, relajación, deflexión
   estimada); el filtro se siembra con la primera carga válida. Gemelos
   con distinta historia: envolvente sembrada idéntica; la diferencia de
   fuerzas restante es histéresis post-pico tau-gobernada e intencional
   (alto slip: ~60–95 N iniciales; en lineal la envolvente es bit-igual y
   el decaimiento relaja como exp(−t/τ_rec) verificado a 240 pasos).
2. **Deflexión de respaldo.** Rutina compartida
   (`TireRadialModel.prepare_coefficients` + `elastic_force_n` +
   `invert_deflection_m`, bisección monótona 24 iter, satura en
   flanco×1.5). Error de inversión ≤ máx(1 N, 0.1 % Fz) en asiento,
   régimen y tope a 150/200/250 kPa; carga cero → 0; descarga rápida con
   fuerza/calor/energía cero; deflexión del rig prevalece; disipación
   radial cero si la fuerza unilateral es cero, ≥ 0 en compresión y rebote.
   La referencia estática de `configure()` usa la misma rutina (sin
   reevaluar diccionarios en el bucle).
3. **Cuatro compuestos.** `_ensure_four_compounds` en neumático y térmico
   (misma precedencia): valida índice e ID antes de mutar; con catálogo
   vacío recarga y rellena faltantes con el activo y su ID (o con el primer
   solicitado válido si no hay activo); copia por rueda y conserva
   selecciones; ID inválido e índice inválido preservan el estado. Cuatro
   IDs válidos y coincidentes entre ambos modelos tras arranque vacío y
   tras sustitución de una rueda.
4. **Energía (medido, objetivo 1 J/1 % como meta).** Instrumentación por
   subpaso: trabajo con Fx reconstruida (neta+rodadura), slip de llanta con
   radio efectivo y lateral con signo; rodadura separada; elástica
   antes/después; plástica, mezcla y descarte separados; Mz declarado
   aparte (`aligning_power_w` = 0 a nivel de neumático; el vehículo lo
   integra como Mz·ωz si lo necesita). Elástica sin deslizamiento:
   res = 0.000 J (objetivo cumplido). Resto medido con convergencia al
   reducir h y disipación ≥ 0 por mecanismo: rodadura 1373→1301 J
   (máx/paso 12.1→6.06→3.75 J), bloqueo 179321→162607 J
   (máx/paso 1515→718→363 J), combinado 2524 J, transición converge,
   rigidez fría/caliente 1205/1260 J. Descarte al despegar 52.30 J,
   separado del calor. Brecha conocida: la fricción térmica sigue por
   diferencia (cierra por construcción); `slide_heat_w` independiente ya
   publicado para el futuro cambio de calor.
5. **Vehículo (referencia Escort, perfil de producción).** Pendiente 10 %
   10 s con freno: < 1 mm/s el último segundo a 60 y 120 Hz (mismo subpaso
   interno 2 ms). Frenada con giro: detiene (v ≈ −0.000), sin inversión
   sostenida (tardía ≈ −0.000; pico transitorio de parada a paso grueso
   −0.526/−0.477 registrado, no sostenido), u ≤ 1.001. Aterrizaje con
   dirección: nulo en aire, cota en recuperación, finito. 60 vs 120 Hz:
   distancia 0.73 % e impulso lateral 0.17 % (tolerancia 5 %). La escena
   Jolt completa (rampa/plano/desnivel conocido) queda como procedimiento
   con esta referencia; no se alteró física de escena.
6. **Tandem-cam (prototipo, flag off).** `tandem_cam_effective_height`:
   plano exacto; escalón/bache/cresta/bordillo a dos velocidades y ambos
   sentidos anticipan medio parche e inician/finalizan en obstáculo ±
   media huella (bache ±0.2 → respuesta ±0.295 con huella 0.20); pérdida
   con ambos apoyos en aire; borde usa la superficie del apoyo más alto;
   apoyo único continuo. Carga modulada por bache: finita y u ≤ 1.0000.
   Coste ~0.7 µs por rueda y tick (2 apoyos). Activación por defecto
   pendiente: falta el doble-query en escena y medir cuánto filtrado
   temporal sobra para no duplicar retraso.

**Diferencias por perfil:** medido solo Escort (referencia del plan). Los
11 perfiles comparten la calibración trasera v2 (verificada en el contrato
de migración); en estacionario la envolvente converge a Fz y la elipse
instantánea no cambia resultados, por lo que no se esperan diferencias por
perfil fuera de transitorios. Re-medir al activar tandem-cam por defecto.
