# Runbook â€” RecalibraciÃ³n de suspensiÃ³n a 60 Hz (Jolt)

Implementa `SUSPENSION_RECALIBRATION_60HZ_PLAN.md`. La sonda extendida es
`tests/rally/suspension_drop_rescue_probe.gd`; este runbook fija cÃ³mo ejecutar
la campaÃ±a, aceptar candidatos y publicarlos sin tocar upgrades antes de tiempo.

## 0. Punto de partida verificado

- `project.godot`: `physics/common/physics_ticks_per_second=60`,
  `physics/3d/physics_engine="Jolt Physics"`. No cambiar durante la campaÃ±a.
- Contacto: `ShapeCast3D`, `contact_shape_count=1` (exigido por
  `profile_loader.gd`). La sonda lo verifica por perfil y lo imprime en
  `SUSPENSION_MANIFEST_CONFIRMED` + `SUSPENSION_TICK_EFFECTIVE`.
- Subpasos del neumÃ¡tico: `maximum_substep_seconds` del `coupled_world` del
  perfil (Escort: `0.0028` â†’ 6 subpasos a 60 Hz). Se registra por ejecuciÃ³n
  (`tire_substeps_per_tick`) y no se modifica entre candidatos.
- Setup de referencia: `RallySetupCatalog.defaults(domains)` (fÃ¡brica) + solo
  `fuel.initial_kg` + los 4 valores de suspensiÃ³n. Multiplicadores de
  compresiÃ³n/rebote y topes se conservan.
- CatÃ¡logo de neumÃ¡ticos: el activo del perfil (`gravel_normal` en campo de
  pruebas). Se registra como `compound` en cada traza.

| Perfil | f delantera / trasera (Hz) | zeta delantera / trasera |
| --- | --- | --- |
| Escort RS2000 (control) | 1.674 / 1.701 | 0.338 / 0.668 |
| Fulvia | 1.750 / 1.850 | 0.550 / 0.550 |
| Nueve RT base (9 variantes) | 1.700 / 1.800 | 0.500 / 0.500 |

FÃ³rmula vigente (`VehicleSuspensionModel.corner_rates`):
`k = m_refÂ·(2Ï€f)Â²`, `c = 2Â·Î¶Â·âˆš(kÂ·m_ref)Â·mult`. Reducir f un 5 % reduce k â‰ˆ9.75 %
y tambiÃ©n cambia c y la rigidez de estabilizadora (depende de k en rueda).
Cada ejecuciÃ³n imprime `SUSPENSION_CANDIDATE_RATES` con k, c y ARB efectivos
mÃ¡s `RALLY_SUSPENSION_FREQUENCY` del motor.

> CuantizaciÃ³n de garaje: el catÃ¡logo expone f con paso 0.01 Hz. La sonda aplica
> candidatos vÃ­a `apply_setup_values` (ruta de publicaciÃ³n), asÃ­ que
> `calibration.front.frequency_hz` puede mostrar 1.67 frente a un nominal
> 1.67377. El resumen guarda ambos: `f_front` pedido y `calibration` efectivo.

## 1. Manifiesto por variante (antes de tocar upgrades)

| Variante | Proving scene | Manifiesto que carga | Provenance con SHA-256 |
| --- | --- | --- | --- |
| escort | `scenes/rally/rally_proving_ground.tscn` | `data/vehicles/ford-escort-rs2000/vehicle.json` | `OPEN_FORMULA_PROVENANCE.json` |
| fulvia | `scenes/rally/rally_proving_ground_fulvia.tscn` | `data/vehicles/lancia-fulvia/vehicle.json` | `HISTORICAL_PROVENANCE.json` |
| `rt-<id>` (9) | `scenes/rally/rt/<id>_proving.tscn` | `data/vehicles/rt/<id>/vehicle.json` | `HISTORICAL_PROVENANCE.json` |

Los directorios `data/vehicles/rt/<id>-upgrade/` solo contienen
`suspension.json` suelto (sin `vehicle.json`): **no son perfiles cargables**
por `VehicleProfileLoader`. La sonda lo comprueba
(`upgrade_dir_is_standalone_profile=false`) y aborta si alguna variante
cargara otro manifiesto. No editar upgrades hasta confirmar aquÃ­ quÃ© manifiesto
consume cada variante.

## 2. Sonda extendida

Archivo: `game/tests/rally/suspension_drop_rescue_probe.gd` (SceneTree headless).

- Fija `Engine.physics_ticks_per_second=60` y verifica motor + tick efectivo en
  cada traza: `SUSPENSION_TICK_EFFECTIVE_GLOBAL`, `SUSPENSION_TICK_EFFECTIVE`
  (`dt_avg/min/max`, `hz_measured`, `tick_monotonic`, `contact_query_type`,
  `maximum_substep_s`, `tire_substeps_per_tick`, `compound`).
- Matriz legada preservada: 4 configs tÃ¡ndemÃ—lÃ­mite + rescate
  (`SUSPENSION_DROP_RESULT`, `SUSPENSION_RESCUE_RESULT`).
- CampaÃ±a nueva por perfil/maniobra/candidato/combustible con secuencias de
  entrada por tick sobre chasis + bujes Jolt reales:
  - `rest` (240 ticks, reposo en plano), `drop` (150, caÃ­da 0.5 m),
    `bump` (180, bache una rueda: balanceo 3Â° + cuerpo 60 mm bajo FL),
    `brake` (300: 0-120 gas 0.7, 120-240 freno 1.0),
    `corner` (360: gas 0.45 + direcciÃ³n 0.30 con rampa 30 ticks),
    `exit_ramp` (300: rampa de gas 0â†’1 en 120 ticks),
    `crest` (360: gas 0.6 desde (-15, y, -10) cruzando la rampa de -22z).
  - Cada caso parte de misma pose, velocidad 0, combustible y temperatura
    (`prepare_for_stage` + `_reset_to_transform` + 6 ticks).
  - Registra por rueda: recorrido fÃ­sico y velocidad relativa del buje, cargas,
    `elastic/damper/bump`, contactos, guiÃ±ada y deriva. CSV por ejecuciÃ³n en
    `user://suspension_60hz/<perfil>__<maniobra>__<candidato>__fuel<kg>.csv`
    (cabecera en `_write_csv`). Resumen por ejecuciÃ³n en
    `SUSPENSION_MANEUVER_SUMMARY`; divergencia vs base en
    `SUSPENSION_DIVERGENCE` (umbral 2 mm / 5 %).
- Candidatos en memoria (`--sweep`): `none` (solo base), `f` (base + 8: f por
  eje Â±5 %/Â±10 % con zeta fija), `z` (base + 8: zeta Â±0.05/Â±0.10 con f fija),
  `full` (base + 16). Combustible: `--fuel-kg` + `--fuel-sweep` (repite nominal
  y 5 kg).

### Comandos

```powershell
# LÃ­nea base rÃ¡pida (Escort, reposo) â€” validaciÃ³n de sintaxis y tick:
C:\Users\bill\AppData\Local\Programs\Godot\godot.cmd --headless --path 'D:\rust-godot-vehicle-simulator\game' --script res://tests/rally/suspension_drop_rescue_probe.gd -- --profiles=escort --maneuvers=rest --sweep=none --repeats=1

# LÃ­nea base completa (3 perfiles, 7 maniobras, 25 kg):
... -- --profiles=escort,fulvia,rt-mini-cooper-s --maneuvers=rest,drop,bump,brake,corner,exit_ramp,crest --fuel-kg=25.0 --sweep=none --repeats=1

# Barrido f con doble combustible (Escort primero, luego Fulvia):
... -- --profiles=escort --maneuvers=rest,drop,bump,brake,corner,exit_ramp,crest --sweep=f --fuel-sweep

# Barrido completo (17 candidatos Ã— maniobras Ã— combustibles):
... -- --profiles=escort --sweep=full --fuel-sweep --repeats=3
```

Los CSV quedan en el user dir de Godot
(`OS.get_user_data_dir()/suspension_60hz`). Recogerlos con:

```powershell
Get-ChildItem "$env:APPDATA\Godot\app_userdata\*\suspension_60hz" -Filter *.csv | Sort-Object Name
```

## 3. Barrido por eje (Â§2)

1. Con zeta fija, barrer f un eje a la vez: nominal, Â±5 %, Â±10 %. Ajustar
   primero el eje cuya traza diverja antes (compresiÃ³n/fuerza/apoyo).
   Elegir por recorrido disponible, frecuencia de oscilaciÃ³n, tiempo en topes
   y recuperaciÃ³n de carga. Repetir para el otro eje.
2. Con f elegida, barrer zeta en pasos de 0.05 hasta Â±0.10. Usar caÃ­da y bache
   para rebotes sucesivos y alternancia de fuerza entre ticks. Conservar
   multiplicadores de compresiÃ³n/rebote.
3. Combinar mejores de ambos ejes. Repetir frenada/curva/cresta (cabeceo,
   balanceo, margen lateral trasero, tracciÃ³n). Si empeora, probar puntos
   intermedios. Todo en memoria; no escribir disco aÃºn.
4. Repetir con perfiles activos restantes. Confirmar cada candidato con
   combustible bajo y nominal. Escort de control para detectar cambios del banco.

Si la primera divergencia aparece en consulta de contacto, tope o restricciÃ³n
y persiste con cambios moderados de f/Î¶, investigar ese mecanismo a 60 Hz
antes de seguir buscando valores.

## 4. AceptaciÃ³n (Â§3)

AutomÃ¡tico por ejecuciÃ³n (`_acceptance_checks`):

- Reposo estable, fuerzas finitas, envolvente que decae
  (`peak_second_half <= peak_first_half + 2 mm`), sin pÃ©rdidas repetidas de
  apoyo en plano. Asentamiento: posiciÃ³n Â±5 mm y velocidad < 0.20 m/s durante
  20 ticks (tick 25 en Escort/reposo/25 kg).
- CaÃ­da/bache: envolvente que decae y apoyo estable; descarga trasera acotada
  (< 60 ticks). Se registran impactos de tope (`bump_stop_wheel_ticks`).
- Curva/cresta: pico de guiÃ±ada, duraciÃ³n de descarga trasera, recuperaciÃ³n de
  fuerza lateral, distancia de frenada y velocidad de salida. El candidato debe
  reducir el sÃ­ntoma reproducido; tolerancias = repetibilidad de la lÃ­nea base
  (`--repeats=3`, tolerancia â‰¥ 3Ïƒ o 1 % relativo).

Primera entrega (Fulvia, 2026-11-13): ver
`SUSPENSION_RECALIBRATION_60HZ_FULVIA_DELIVERY.md`. El banco del Fulvia a
60 Hz no asienta (buje 19 kg + radial 180 kN/m: anomalÃ­a tick 1â€“2, rueda 0;
estable a 120 Hz). Barridos f Â±5/Â±10 % y Î¶ 0.45â€“0.65 sin estabilizar:
valores publicados sin cambio (1.75/1.85 Hz, Î¶ 0.55/0.55), hash verificado,
contratos de simulaciÃ³n y neumÃ¡ticos en PASS.
Segunda prueba (Fulvia, impulso radial, 2026-11-13): ver
`SUSPENSION_RECALIBRATION_60HZ_FULVIA_DIAG2.md`. Balance mÂ·Î”v = Î£J exacto
en ticks 1â€“5 (el radial domina el primer rebote, el damper amplifica
despuÃ©s; la junta domina desde el tick 6); limitador solo estrecha la
ventana de supervivencia; caÃ­da/bache con limitador siguen explotando
(142/127 kN). Sin recomendaciÃ³n; siguiente intervenciÃ³n: fuerza radial /
restricciÃ³n del buje.
Tercera prueba (Fulvia, integraciÃ³n radial, 2026-11-13): ver
`SUSPENSION_RECALIBRATION_60HZ_FULVIA_DIAG3.md`. Paso radial implÃ­cito +
lÃ­mite de impulso del amortiguador: pasa reposo, caÃ­da y bache a 60 Hz
(3/3 repeticiones); cada cambio por separado, no. Contratos en PASS con el
cÃ³digo final; f/Î¶ y hashes intactos. Cuarta prueba (Fulvia, aterrizaje equivalente + manejo, 2026-11-13): ver
`SUSPENSION_RECALIBRATION_60HZ_FULVIA_DIAG4.md`. Aterrizaje alineado por
primer contacto cargado a igual velocidad: impl60 pasa 3/3 dentro de la
dispersión del control base120; manejo equivalente en frenada/cresta,
divergencia transitoria en curva con n=1, confirmada sistemática 5/5 y atribuida al algoritmo implícito (impl120 también trompea; ver §5 del acta). Mantener 60 Hz y la
combinación bajo interruptor; no integrar al runtime; f/ζ y hashes intactos.
Estado previo (Escort):
`rest` Escort/base/25 kg pasa (tick 60 Hz, monotÃ³nico,
envolvente 0.014â†’0.003, 0 pÃ©rdidas, asienta tick 25). Contratos
`suspension_correction` y `vehicle_simulation_correction` en PASS.

## 5. PublicaciÃ³n

Solo tras aceptar en pista (tramo del fallo) y con tolerancias fijadas:

1. Escribir los 4 valores aceptados en `suspension.json` del perfil
   (`front/rear.ride_frequency_hz`, `front/rear.damping_ratio`). No tocar
   geometrÃ­a, joints, topes ni multiplicadores.
2. Actualizar su SHA-256 en la provenance correspondiente:
   - Escort: `data/vehicles/ford-escort-rs2000/UPDATE_HASHES.ps1`
     (bloque `profile_json_sha256` en `OPEN_FORMULA_PROVENANCE.json`).
   - Fulvia / RT: editar `HISTORICAL_PROVENANCE.json`
     (`profile_json_sha256."suspension.json"`) con el hash del archivo
     resultante, p. ej.:
     `powershell -c "(Get-FileHash suspension.json -Algorithm SHA256).Hash.ToLowerInvariant()"`.
3. Reverificar hashes (recargar perfil; `VehicleProfileLoader.load_profile`
   debe dar `ok` y la provenance debe coincidir).
4. Ejecutar contratos de simulaciÃ³n y neumÃ¡ticos:
   `suspension_correction_contract.gd`, `vehicle_simulation_correction_contract.gd`
   y el de cierre de neumÃ¡ticos vigente.
5. Repetir las maniobras con los perfiles cargados desde disco
   (`--sweep=none`) y adjuntar CSV + resÃºmenes a la calibraciÃ³n.

Referencias: `scripts/physics/suspension_model.gd`
(`VehicleSuspensionModel.corner_rates`), `scripts/physics/vehicle_simulation.gd`
(`sample_suspension_trace`, `sample_tick_trace`, `sample_contact_trace`,
`apply_setup_values`), `scripts/rally/rally_setup_catalog.gd`,
`docs/rally/SUSPENSION_FREQUENCY.md` y `docs/rally/SUSPENSION_CORRECTION_PLAN.md`.


## Segunda prueba del Fulvia â€” impulso radial y rebote del buje

**Objetivo.** Reproducir la pÃ©rdida de apoyo de FL en el tick 2 y explicar el salto de velocidad del buje entre los ticks 1 y 2. El [reporte de entrega](SUSPENSION_RECALIBRATION_60HZ_FULVIA_DELIVERY.md) apunta al acoplamiento entre el neumÃ¡tico radial, el buje de 19 kg y el amortiguador de suspensiÃ³n. Verificar esa hipÃ³tesis con impulsos medidos antes de diseÃ±ar una correcciÃ³n.

1. **Repetir el arranque instrumentado.** Extender [fulvia_spawn_diagnostic.gd](../../tests/rally/fulvia_spawn_diagnostic.gd). Mantener Jolt de producciÃ³n a 60 Hz. Usar el Fulvia de disco, ShapeCast3D, 20 kg, marcha neutra, superficie plana, controles a cero y el mismo spawn y estado tÃ©rmico de la primera entrega. Conservar f = 1.75/1.85 Hz y Î¶ = 0.55/0.55. Ejecutar tres pasadas limpias de 240 ticks a 60 Hz y tres a 120 Hz como control diagnÃ³stico dentro de la sonda. Comparar las dos frecuencias a igual tiempo simulado. Guardar cada CSV con frecuencia, variante y repeticiÃ³n en el nombre para preservar las trazas anteriores.
2. **Medir el primer impacto.** Instrumentar [UnsprungSuspensionRig.solve](../../scripts/physics/unsprung_suspension_rig.gd) mediante la traza de diagnÃ³stico. Para los ticks 0â€“10, registrar por rueda masa del buje, eje de la guÃ­a, velocidad del buje y de su anclaje en el chasis, contacto geomÃ©trico y cargado, distancia del ShapeCast, recorrido fÃ­sico, deformaciÃ³n radial, velocidad de compresiÃ³n antes y despuÃ©s del clamp y presiÃ³n efectiva. Separar fuerza elÃ¡stica radial, aporte viscoso, tope de llanta y fuerza unilateral final. Registrar los componentes de suspensiÃ³n aplicados al buje, incluidos muelle, amortiguador, estabilizadora y topes segÃºn los tÃ©rminos del solver. Guardar el estado inicial y el final a la misma fase del callback en ticks consecutivos. Confirmar la correspondencia entre la fuerza del tick n y la velocidad observada en n+1.
3. **Cerrar el balance axial.** Proyectar todas las fuerzas sobre el mismo eje de guÃ­a tomado al inicio del intervalo y usar signos del buje. Calcular por tÃ©rmino J = F Ã— dt, y comparar su suma, incluida gravedad y cualquier otra fuerza conocida, con m Ã— Î”v observado. Usar la componente realmente aplicada al buje del vector normal radial. Anotar el residual como impulso sin explicar, que puede incluir la reacciÃ³n de las restricciones y del solver. Verificar si domina antes de atribuir el rebote a una sola fuerza. Si la primera carga radial es alta, reconstruir su deformaciÃ³n a partir de distancia de apoyo y recorrido fÃ­sico para comprobar si ya nace de una penetraciÃ³n inicial.
4. **Aislar la amplificaciÃ³n a 60 Hz.** Repetir con el limitador diagnÃ³stico de impulso del amortiguador de suspensiÃ³n activado, dejando el resto igual. Si se necesita separar el tÃ©rmino viscoso radial, aÃ±adir una variante de sonda que lo anule temporalmente conservando la parte elÃ¡stica, el tope y la proyecciÃ³n unilateral. Hacer cada cambio en una pasada distinta y medir si cambia el primer impulso radial, el primer rebote o solo su amplificaciÃ³n posterior. Si la carga inicial apunta a la pose, aÃ±adir como comparaciÃ³n un arranque desde la pose asentada a 120 Hz con velocidades reiniciadas. Registrar esa condiciÃ³n por separado. Los controles de diagnÃ³stico se aplican Ãºnicamente en la sonda.
5. **Entregar evidencia y decisiÃ³n.** Adjuntar el balance de impulsos de FL en los ticks 0â€“10, los CSV completos de las cuatro ruedas y una tabla por variante con primer tick de pÃ©rdida de apoyo, pico de carga, pico de velocidad axial, permanencia en topes y altura final del chasis. Una variante que se asiente en reposo debe repetirse en caÃ­da de 0.5 m y bache unilateral antes de recomendarla. Identificar si la siguiente intervenciÃ³n corresponde a la geometrÃ­a inicial, la fuerza radial, el amortiguador de suspensiÃ³n o la restricciÃ³n del buje. Mantener esta entrega como diagnÃ³stico del Fulvia y dejar la calibraciÃ³n y los hashes de producciÃ³n intactos.

Comandos base para las dos primeras pasadas. Ampliar la sonda para guardar archivos distintos por repeticiÃ³n.

```powershell
godot --headless --path game --script res://tests/rally/fulvia_spawn_diagnostic.gd -- --hz=60 --ticks=240
godot --headless --path game --script res://tests/rally/fulvia_spawn_diagnostic.gd -- --hz=120 --ticks=240
```

## Tercera prueba del Fulvia â€” integraciÃ³n radial a 60 Hz

Partir del [segundo diagnÃ³stico](SUSPENSION_RECALIBRATION_60HZ_FULVIA_DIAG2.md). En el solve 2 de FL, el impulso radial fue +110.7 NÂ·s y el de suspensiÃ³n +78.8 NÂ·s. El limitador del amortiguador permitiÃ³ asentar el coche en reposo, pero persistieron 142 kN en caÃ­da y 127 kN en bache. La variante sin viscosidad radial y el arranque desde pose asentada tambiÃ©n divergieron.

1. **Reproducir los controles.** Conservar Jolt global a 60 Hz, ShapeCast3D, perfil Fulvia de disco y el mismo combustible y setup. Repetir base y limitador en arranque, caÃ­da de 0.5 m y bache unilateral. Capturar el primer y segundo impacto sin rescate automÃ¡tico en la sonda. Usar 120 Hz solo como referencia diagnÃ³stica con el mismo escenario y comparar a igual tiempo simulado.
2. **Probar un paso radial implÃ­cito como variante de sonda.** Mantener la curva radial y los parÃ¡metros actuales. Resolver el impulso normal unilateral del intervalo usando la deformaciÃ³n y velocidad predichas al final del paso. En plano, usar como punto de partida `v_final = v_libre + J_rad / m_buje` y `deflexion_final = max(0, deflexion_inicial - dt * v_final)`, con velocidad positiva al separar y `v_libre` incluyendo los impulsos conocidos de suspensiÃ³n y gravedad. Buscar una raÃ­z acotada de `J_rad = dt * F_rad(deflexion_final, -v_final)`, reutilizando el modelo radial y su tope de llanta. Declarar cÃ³mo se trata la apertura del contacto dentro del paso y verificar por separado apoyo nulo y recontacto. Validar primero en plano y conservar la proyecciÃ³n existente al extender la prueba al bache. Aplicar el impulso al buje una sola vez por tick mediante la fuerza equivalente `J_rad / dt`. Usar la carga media correspondiente en el modelo tangencial durante esa variante y registrar ambas magnitudes. Repetir llamadas al modelo con la misma pose y velocidad no constituye una integraciÃ³n por subpasos.
3. **Separar el radial de la amplificaciÃ³n del amortiguador.** Ejecutar una matriz a 60 Hz con radial actual/implÃ­cito y limitador apagado/encendido. Usar tres repeticiones por combinaciÃ³n para arranque, caÃ­da y bache. Registrar por rueda carga e impulso radial, deflexiÃ³n, velocidad axial, impulso del amortiguador, duraciÃ³n del contacto, topes y residual de junta. Revisar el solve 2 de FL y el segundo impacto del aterrizaje antes de interpretar los picos posteriores.
4. **Verificar la respuesta fÃ­sica.** Exigir reposo estable, asentamiento tras caÃ­da y bache, ausencia de divergencia y carga unilateral no negativa. Comparar con el control a 120 Hz la carga estÃ¡tica por esquina, altura asentada, recorrido y el impulso acumulado durante el aterrizaje. Comparar picos sobre ventanas de tiempo equivalentes. Una reducciÃ³n del pico acompaÃ±ada de pÃ©rdida de apoyo prolongada o recorrido pegado al tope no pasa. Si el radial implÃ­cito mejora el primer impacto y el residual de junta sigue dominando antes de estabilizar, instrumentar la restricciÃ³n del buje antes de ajustar otros coeficientes.
5. **Entregar la decisiÃ³n.** Adjuntar CSV y tabla de las cuatro combinaciones con primer evento anÃ³malo, picos, impulso acumulado y tiempo de asentamiento. Indicar si la variante radial pasa con el limitador apagado, si necesita ambos cambios o si queda bloqueada por la junta. Mantener el prototipo optativo y preservar los valores de frecuencia natural, amortiguamiento y hashes de producciÃ³n. Si pasa el banco, repetir frenada, curva y cresta antes de proponer una integraciÃ³n al runtime.

## Cuarta prueba del Fulvia â€” aterrizaje equivalente y validaciÃ³n en movimiento

1. **Fijar el caso de prueba.** Reutilizar la sonda de caÃ­da del tercer diagnÃ³stico. Iniciar cada pasada en una instancia limpia, con el mismo perfil, ShapeCast3D, combustible, presiÃ³n y temperatura, actitud, estado de los cuatro bujes y plano de contacto. Preparar un estado justo antes del impacto, con separaciÃ³n pequeÃ±a y velocidad vertical medida en la caÃ­da de 0.5 m. Guardar y verificar esa pose y las velocidades de chasis y bujes al primer contacto. Si la fase del tick altera la velocidad de impacto, corregir la preparaciÃ³n o reportar la diferencia antes de comparar.
2. **Ejecutar tres configuraciones.** Comparar radial implÃ­cito con limitador a 60 Hz, base a 120 Hz y radial implÃ­cito con limitador a 120 Hz. Hacer tres pasadas por configuraciÃ³n. Los 120 Hz se aplican dentro de la sonda. Repetir tambiÃ©n el caso implÃ­cito sin limitador a 60 Hz que dio resultados mixtos. Registrar identificador de pasada, orden de inicializaciÃ³n y primer tick divergente si aparecen resultados distintos bajo la misma configuraciÃ³n. Guardar las trazas originales con nombres Ãºnicos.
3. **Comparar a partir del contacto.** Alinear por primer contacto y tiempo simulado. Medir por rueda carga estÃ¡tica y mÃ¡xima, recorrido mÃ¡ximo, tiempo en topes, pÃ©rdida de apoyo, velocidad de rebote y tiempo de asentamiento. Integrar la carga sobre la misma ventana temporal para obtener impulso en NÂ·s. Reportar tambiÃ©n el impulso neto vertical del coche descontando el peso en esa ventana y contrastarlo con el cambio de momento. Comparar picos promediados sobre intervalos comunes de 16.67 ms y adjuntar los picos nativos. AsÃ­ se contrasta aterrizaje con aterrizaje y se distingue la sensibilidad a la frecuencia de la sensibilidad al algoritmo.
4. **Decidir con las trazas.** Exigir que las tres pasadas del candidato a 60 Hz recuperen el apoyo y se asienten, con cargas finitas y sin oscilaciÃ³n creciente. Acordar las tolerancias de comparaciÃ³n a partir de la dispersiÃ³n del control antes de evaluar el candidato. Si la discrepancia excede ese margen, identificar si empieza en la apertura del contacto, la carga radial aplicada, el recorte del amortiguador o la reacciÃ³n de la junta. Conservar las diferencias numÃ©ricas aunque el coche se asiente.
5. **Probar manejo si pasa el aterrizaje.** Repetir frenada recta, curva lisa y salida sobre cresta desde la misma velocidad de entrada y con una secuencia de mandos indexada por tiempo simulado. Comparar a 60 Hz candidato y 120 Hz base la distancia de frenado, velocidad de salida, guiÃ±ada y tiempo de recuperaciÃ³n de carga trasera. Entregar CSV, tabla por pasada y decisiÃ³n sobre el candidato. Mantener Jolt de producciÃ³n a 60 Hz y la combinaciÃ³n bajo el interruptor de diagnÃ³stico durante esta campaÃ±a. Dejar el ajuste de frecuencia natural y amortiguamiento para despuÃ©s de validar el mecanismo.

## Quinta prueba del Fulvia — subpasos acoplados a 180 y 360 Hz

1. Prototipar en la sonda del Fulvia un único integrador con 3 o 6 subpasos por tick de Jolt a 60 Hz. Usar el mismo método, ShapeCast3D y calibración en ambas variantes. En cada subpaso avanzar la pose y velocidad predichas del chasis y los bujes, respetar el eje de las guías y recalcular recorrido, amortiguación, deformación radial, Fz, fuerzas tangenciales y giro de rueda. Alimentar el neumático con la Fz de ese subpaso. Documentar cómo se actualiza el apoyo desde la pose predicha y cómo se aproximan las restricciones entre ticks de Jolt.
2. Acumular los impulsos lineales y angulares con el intervalo de cada subpaso y transferirlos una vez por tick a los cuerpos de Jolt. Aplicar las reacciones de suspensión a chasis y bujes con signos opuestos. Usar el estado local solo para predecir y resincronizarlo desde Jolt al siguiente tick. Registrar la diferencia entre velocidad predicha y observada, y descontar gravedad y otras fuerzas conocidas al calcular el residual de las juntas.
3. Reutilizar fulvia_landing_probe.gd y el estado de impacto de DIAG4 a 2.37 m/s. Repetir también la curva lisa a 12 m/s, gas 0.45 y dirección 0.35 durante 6 s. Hacer tres pasadas de aterrizaje y cinco de curva por variante con estado inicial y mandos por tiempo simulado equivalentes. Conservar el explícito a 120 Hz de DIAG4 como referencia diagnóstica. Mantener iguales los interruptores de radial y amortiguador entre 180 y 360 Hz y registrar su estado.
4. Alinear las trazas por primer contacto cargado en el aterrizaje y por inicio del mando en curva. Comparar impulso vertical en una ventana común, picos de Fz sobre intervalos de 16.67 ms, recorrido, rebote, asentamiento, descarga trasera interior, guiñada y deriva. Guardar CSV por subpaso y por tick. En curva, localizar qué señal se separa primero entre las variantes y contrastar el residual de junta en ese instante.
5. Definir tolerancias antes de revisar el candidato, usando la repetibilidad y la relevancia física de cada métrica. Considerar 180 Hz viable si ambas variantes se asientan, completan la curva sin trompo y muestran resultados comparables también frente al control. Si solo 360 Hz pasa o las trazas difieren materialmente, revisar primero la predicción, el contacto y la reacción de las juntas. Si ambas trompean de forma similar, comparar la secuencia Fz, Fy y guiñada con el control antes de atribuir el fallo a la frecuencia. Entregar tabla, CSV y decisión. Mantener la prueba optativa y Jolt de producción a 60 Hz.
