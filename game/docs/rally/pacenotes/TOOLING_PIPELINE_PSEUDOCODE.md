# Tooling de Pacenotes CMR2 — Pipeline completo en pseudocódigo

> Documento de referencia del tooling versionado en `tools/pacenote-tooling/` + runtime en `game/`.
> Fuente canónica externa: `D:\games\rally-throphy\stage_exporter\tools\` (snapshot local en este repo).
> Objetivo: explicar **qué hace cada pieza, en qué orden, con qué datos**, en pseudocódigo detallado.

---

## 1. Mapa del tooling

```
tools/pacenote-tooling/
  v1/pacenote_analyzer.py            # Generador original: heurística sobre resetN.bin (~22 llamadas/stage)
  v2/pacenote_analyzer_v2.py         # Curvatura remuestreada + tabla RU1 + planificador de ritmo (~22 en RU1)
  v3/
    road_mesh_extractor.py           # Capa 1: malla vial real desde .BMF -> espacio Godot
    road_spatial_index.py            # Índice espacial + utilidades triángulo/punto
    road_cross_sections.py           # Cortes ortogonales cada 2 m + bordes L(s)/R(s)
    road_corridor_solver.py          # Recorte contra barreras + resolución de cruces
    road_centerline.py               # Eje C(s) + trazada óptima P*(s)
    road_geometry_analyzer.py        # Derivadas: kappa, heading, grade, camber, mu
    road_validator.py                # Anomalías + road_geometry.json + GLB debug
    pacenote_analyzer_v3.py          # Orquestador: curvas + obstáculos + velocidades + scheduler
  deps/bmf_parser.py                 # Parser .BMF: MATERIALES, TRACK chunks, HIERARCHY, timing gates
  runtime/pacenote_runtime.py         # convert_notes(): authoring -> runtime Godot (gates + calls)
  validation/validate_stage.py       # Validador de paquete (9 artefactos, gates, CMR2, UV clamp)
  tests/test_russia_stage1_v3.py      # Suite regresión 6/6 obligatoria en russia_stage1
  docs/russia_stage1_v2_vs_v3.md      # Comparativa v2 vs v3 + desviaciones del spec

tools/rally/
  pacenote_runtime.py                # Copia operativa de convert_notes() usada por el importador
  import_stage_export.py             # Importador universal stage_exporter -> game/
  analyze_russia_route.py            # Análisis geométrico auxiliar de ruta
  generate_russia_stage1_pacenotes.py# Generador legacy documentado (russia_stage1, evidencia authoring)
  extract_pacenote_icons.py / remaster_cmr2_copilot.py / extract_stage_gates.py ...

game/ (runtime Godot, sin Python)
  scripts/rally/cmr2_pacenote_codec.gd      # pack/decode palabra 32-bit <-> slots de voz
  scripts/rally/rally_pacenote_controller.gd# Orquesta detección + colas + voz + HUD
  scripts/rally/pacenote_gate_tracker.gd    # Cruces de puertas transversales 3D
  scripts/rally/cmr2_call_queue.gd           # Cola 5 registros, contador 50->25, flags 0x100/0x200
  scripts/rally/cmr2_speech_queue.gd         # Cola 20 slots voz, reproducción secuencial
  scripts/rally/cmr2_pacenote_hud.gd         # Iconos, espejo, tintado, animación CURVE_TABLE
  data/rally/pacenotes/russia_stage1.json    # Runtime: { calls[], gates[] }
  docs/rally/pacenotes/russia_stage1_authoring.json   # Evidencia trazable por evento
  docs/rally/pacenotes/russia_stage1_candidates.json  # Todos los candidatos (emitidos + agrupados + dropeados)
```

Orden de uso canónico (v3):

```text
1. python tools/rally_road_reconstruction_v2/pacenote_analyzer_v3.py
     --route-json stages/russia/stage1/russia_stage1_route.json
     --bmf work_cache/russia/stage1.BMF
     --output-dir stages/russia/stage1
     --country russia --stage stage1
     [--geo-json stages/russia/stage1/russia_stage1_road_geometry.json]
2. python tools/validate_stage.py --stage-dir stages/russia/stage1
3. python game/tests/rally-v2/test_russia_stage1_v3.py --stage-dir stages/russia/stage1
4. python tools/rally/import_stage_export.py --source <stage_exporter>/stages/russia/stage1
```

---

## 2. Convenciones de datos que todo el pipeline comparte

### 2.1 Sistemas de coordenadas

```pseudocodigo
# BMF/DirectX (mano izquierda, +Z avance)  ->  Godot (mano derecha, +Y arriba, -Z avance)
FUNCION convertir_DX_a_Godot(v):
    RETORNAR (v.x, v.y, -v.z)   # + invertir winding order para conservar normales +Y
```

### 2.2 Estaciones `s` y `station`

```pseudocodigo
# Toda la geometría v3 vive en estaciones uniformes cada STEP_M = 2.0 m
s[i] = i * 2.0                                    # distancia curvilínea a lo largo del eje
station = i                                       # índice entero de estación
guide_node = nearest_route_node(s)                # índice al route.json original (trazabilidad)
s_start, s_apex, s_end = estaciones de inicio/ápice/fin de un evento
```

### 2.3 Palabra CMR2 de 32 bits

```pseudocodigo
word = kind[0:4] | direction[4:6] | distance[6:10] | length[10:12]
     | turn[12:15] | surface[15:17] | hazard[17:21] | caution[21:23]
     | junction[23] | no_cut[24] | ending[25:28] | side[28:30]

# Semántica validada en juego:
#   kind      1..8 = six,five,four,three,two,one,openhairpin,hairpin ; 0 = peligro suelto
#   direction 1 = left, 2 = right
#   distance  0..9 = clase de hueco previo (ver §7.3); 1="and", 2="into"
#   length    1 = long (>=80 m), 2 = verylong (>=135 m)
#   turn      1 = tightens, 2 = opens, 3 = narrows/turn-junction
#   hazard    1 = jump, 2 = crest, 4 = rocks, 5 = post, 6 = gate, 7 = ditch
#   caution   1 = caution, 2 = double-caution
#   side      1 = inside, 2 = outside (solo hazards 4,5,7 ligados a curva)
#   no_cut/junction/ending/surface según codec
```

### 2.4 Los tres JSON por stage

```pseudocodigo
*_pacenotes.json = runtime = {
    stage, generator: "pacenote_analyzer_v3",
    calls: ["0x........", ...],          # una palabra hex por llamada, orden call_index
    curves: [{ call_word_hex, call_index, curve_id, advisory_gate_node,
               route_distance_m, s_start, s_end, kind_str, direction, link }]
}
*_pacenotes_authoring.json = { stage, generator, events: [...] }   # solo eventos EMITIDOS + evidencia
*_pacenotes_candidates.json = { stage, generator, events: [...] }  # TODOS: emitted/absorbed/grouped/dropped
```

---

## 3. v1 — Generador original (heurística sobre resets)

> Archivo: `v1/pacenote_analyzer.py` (628 líneas). ~22 llamadas/stage.

```pseudocodigo
PROCEDIMIENTO v1_analizar(reset_bins, objetos_3D, ruta):
    # ENTRADA: resetN.bin (posiciones de reset), perfil vertical, objetos físicos
    curvas = []
    PARA cada segmento entre resets consecutivos:
        R      = estimar_radio_horizontal(segmento)
        angulo = giro_total_rumbo(segmento)
        long   = longitud(segmento)
        SI es_recta(angulo, R): CONTINUAR
        sev = severidad_por_radio(R)          # tabla 1..8 propia
        mods = []
        SI radio_salida >> radio_entrada: mods += ["opens"]
        SI radio_salida << radio_entrada: mods += ["tightens"]
        SI long >= 80:  mods += ["long"]
        SI long >= 135: mods += ["verylong"]
        # Perfil vertical
        SI convexo_fuerte_con_caida(pendiente): peligro = crest/jump
        # Objetos: rocas, cruces, vallas, puertas, postes, graneros
        PARA cada objeto CERCANO a la curva (distancia lateral + dy):
            vincular(objeto -> curva, inside/outside, dont_cut si invade trazada)
        curvas += { direction, s_start/apex/end, R, angulo, sev, mods, peligros }

    # Codec (idéntico en v1/v2/v3, ver §8)
    PARA cada curva:
        fields = { kind: sev, direction, length, turn, hazard, caution, ... }
        word = pack_cmr2_word(**fields)
    # Aviso fijo ~50 m antes de la entrada (sin planificador temporal)
    PARA cada curva:
        advisory_node = nodo_ruta_anterior_a(entry - 50 m)
    EXPORTAR runtime + authoring + candidates
```

---

## 4. v2 — Curvatura remuestreada + planificador de ritmo

> Archivo: `v2/pacenote_analyzer_v2.py` (1313 líneas). ~22 en russia_stage1.

Diferencias clave vs v1 (documentadas en cabecera):

```pseudocodigo
PROCEDIMIENTO v2_analizar(ruta_3D, objetos, config: PaceConfig):
    # 4.1 REMUESTREO: ya no depende del espaciado de nodos
    polilinea = remuestrear(ruta, paso = config.resample_m ≈ 3 m)
    rumbo_suavizado = suavizar_yaw(polilinea, ventana = config.smooth_m ≈ 9 m)
    kappa[s] = d_theta / d_s   # curvatura por estación, con histéresis r_on/r_off

    # 4.2 PERFIL DE VELOCIDAD ESPERADA (límite lateral + accel/frenada)
    v_lim[s] = sqrt(mu * g / |kappa[s]|)
    v[s] = forward_pass(v_lim, accel) + backward_pass(v_lim, frenada)

    # 4.3 PLANIFICADOR: el aviso depende de velocidad + duración de frase
    PARA cada evento en orden s:
        dur_frase = suma_duracion_slots(decode(word)) + gaps
        t_evento  = tiempo_en(s_evento)              # desde perfil v(s)
        t_aviso   = t_evento - (t_lead(sev) + dur_frase)
        s_aviso   = invertir_tiempo(t_aviso)
        SI s_aviso viola lead_min/max: CLAMP
        SI bloque_anterior.solapa(t_aviso):
            INTENTAR: retrasar_actual (encadenar) → acortar_por_niveles → descartar
            NUNCA descartar si priority >= 70 (peligro crítico)

    # 4.4 PELIGROS: prioridad por gravedad, no por orden de mesh
    PRIORIDAD = jump(90) > cruce > portón > rocas > poste > crest
    peligros_en_recta = ENTRADAS PROPIAS con kind=0 (solo hazard/surface)
    salto/crest = física v²·kv/g con velocidad esperada (no umbral fijo de pendiente)
    caution escala a 2 (salto antes de curva cerrada, rocas inside en curva cerrada...)
    correcciones: wrap yaw ±π, filtro "tree" que no mate "street*"
```

---

## 5. v3 — Pipeline completo (el canónico actual)

> Orquestador: `v3/pacenote_analyzer_v3.py` (~1300 líneas). 51 llamadas en russia_stage1 (~1/98 m; CMR2 original ~1/95 m).
> Firma: `analyze_and_build_pacenotes(route_points, bmf_stage, output_dir, country, stage, cfg, geo_json?)`

```pseudocodigo
PROCEDIMIENTO v3_pipeline(route_points, bmf_stage, cfg: V3Config):
    # ── FASE 1. Geometría (reutiliza JSON si se aporta, o reconstruye) ──
    SI geo_json existe:
        geo  = CARGAR(geo_json)
        mesh = extract_road_mesh(bmf_stage)          # §5.1
        center,left,right = columnas de geo.sections
    SINO:
        mesh = extract_road_mesh(bmf_stage)          # §5.1 malla vial + barreras
        doc  = CrossSections(mesh).build(route)      # §5.2 cortes cada 2 m
        sol  = CorridorSolver(barreras).solve(doc)   # §5.3 recorte + cruces
        cl   = build_centerline(sol.sections)        # §5.4 eje C(s) + trazada P*(s)
        mats = [superficie_central por sección]
        an   = analyze_geometry(C, P*, L, R, mats)   # §5.5 kappa, heading, grade, camber, mu
        geo  = build_road_geometry(id, sol, cl, an, route)  # §5.6 + anomalías

    # ── FASE 2. Curvas + severidad efectiva ──
    curvas = detect_curves(geo, cfg)                  # §6.1 multi-ápice, core-trim
    numerar(curvas, "EVT_%03d")
    speeds = compute_speed_profiles(geo, cfg)        # §6.4 tres escenarios + t(s)
    apply_effective_severity(curvas, geo, speeds, cfg)# §6.3 +1 bajada/peralte/frenada
    curvas, agrupadas = group_consecutive_curves(curvas, gap=55 m)  # §6.2 densidad
    PARA cada curva: kind_str, priority, speed_ms, speed_scenarios{cons,nom,fast}

    # ── FASE 3. Obstáculos + junctions + verticales ──
    obstaculos = extract_obstacles(bmf, center, left, right, cfg)  # §6.5 TRACK+HIERARCHY
    link_obstacles(obstaculos, curvas, cfg)          # inside/outside, dont_cut
    junctions  = detectar_rachas_is_junction(geo)    # §6.6, filtrar si no hay giro >=55°
    verticales = detect_vertical(geo, speeds, cfg)   # §6.7 gamma = v²·|kv|/g, NMS 45 m

    # ── FASE 4. Secuencia + planificación temporal + emisión ──
    seq = build_main_sequence(curvas, junctions, verticales, obstaculos_sueltos)  # §7.1
    runtime, dropped = plan_and_emit(seq, route_cum, t(s), s_grid, cfg)           # §7.2
    # dentro de plan_and_emit: repack distancias §7.3, caution hoisting §7.4,
    #   cooldowns §7.5, degradación por niveles §7.6
    absorbed = marcar_absorbidos(curvas, obstaculos) # el peligro viaja en palabra de su curva
    EXPORTAR runtime + authoring + candidates         # §7.7
    RETORNAR run_doc
```

### 5.1 `road_mesh_extractor` — malla vial desde el .BMF

```pseudocodigo
PROCEDIMIENTO extract_road_mesh(bmf_stage):
    PARA cada chunk en bmf_stage.track_chunks:
        PARA cada batch en chunk.batches:
            mat = bmf_stage.materials[batch.mat_id].name
            cat = classify_material(mat)   # core | junction | shoulder | barrier | ditch | other
            SI cat en {core, junction, shoulder}:
                guardar triángulos + materiales + categorías + UVs
            SI cat == barrier:
                guardar segmentos_barrera (aristas XZ para raycast)
    PARA cada mesh en bmf_stage.hierarchy_meshes:   # objetos colocados (rocas, postes...)
        aplicar matrix + pos_extra a sus batches y clasificar igual
    CONVERTIR todo a Godot (x, y, -z) + invertir winding
    RETORNAR { road_triangles, road_materials, road_categories, road_uvs, barrier_segments }

FUNCION classify_material(nombre):
    SI "gate" y "fence" en nombre: RETORNAR "other"   # portones checkpoint, no muros
    SI match(BARRIER_WALL_MATERIALS): RETORNAR "barrier"     # roadbar1, fences, walls...
    SI match(CORE_ROAD_MATERIALS):    RETORNAR "core"        # road_gravel_1, road_snow_*, fin_road_*...
    SI match(JUNCTION_ROAD_MATERIALS):RETORNAR "junction"    # *cross*, road_crossroad_*...
    SI es_arcen_vial(nombre):         RETORNAR "shoulder"    # *_dif* con "road" en nombre
    SINO: RETORNAR "other"
```

### 5.2 `road_cross_sections` — cortes cada 2 m

```pseudocodigo
CONSTANTES: STEP_M=2.0, HALF_RANGE_M=20.0, SAMPLE_DX_M=0.25, MAX_FRAME_KAPPA=1/12

PROCEDIMIENTO CrossSections.build(route):
    guia = resample_route(route, STEP_M)                    # estaciones uniformes
    tang = smoothed_frame_tangents(guia.XZ)                # B-spline, k acotada (bucle s*=1.6)
    PARA cada estación i con centro guia[i], tangente t, normal n=perp(t):
        MUESTREAR x en [-20..+20] paso 0.25 m a lo largo de n:
            punto = centro + x*n
            tri   = RoadSpatialIndex.query(punto)           # triángulo vial bajo el punto
            SI no hay tri: MARCAR hueco (has_corridor=false)
            SINO: registrar material, UV, Y baricéntrica
        borde_L/R = COMBINAR(frontera_material, UV_cinta, salto_Y)
        ancho[i] = |R - L|
    RETORNAR { sections: [{ s_m, center, left_edge, right_edge, width_m, ... }] }
```

### 5.3 `road_corridor_solver` — barreras y cruces

```pseudocodigo
PROCEDIMIENTO CorridorSolver(barrier_segments).solve(sections):
    PARA cada sección con bordes (L, R):
        hit_L = raycast_XZ(origen=centro, dir=-normal, max=|centro-L|) contra barreras
        hit_R = raycast_XZ(origen=centro, dir=+normal, max=|centro-R|) contra barreras
        SI hit: RECORTAR borde al impacto (el muro manda sobre el material)
        SI ensanchamiento brusco DW_DS > 0.35 y material==junction:
            MARCAR is_junction=true, clamp ancho a 1.45× mediana local
    RETORNAR sections_resueltas
```

### 5.4 `road_centerline` — eje + trazada óptima

```pseudocodigo
# P*(s_i) = C(s_i) + alpha_i·(R-L), alpha ∈ [-0.35,+0.35] (15% margen a bordes)
PROCEDIMIENTO build_centerline(sections):
    C = smooth_centerline(puntos_medios, anchos)   # Savitzky-Golay orden 3, ventana ~11 m,
                                                   # restringido al tercio central (0.15·W)
    P* = solve_racing_line(C, L, R, obstaculos)     # mínimos cuadrados acotados:
                                                   #   min ||T·alpha + c||² + 1e-3·||alpha||²
                                                   # obstáculos interiores → cota 0 en ±8 m
    RETORNAR { center: C, opt_line: P* }
```

### 5.5 `road_geometry_analyzer` — derivadas y física

```pseudocodigo
# Convención: kappa > 0 = DERECHA, kappa < 0 = IZQUIERDA; rumbo = unwrap(atan2(dx, -dz))
PROCEDIMIENTO analyze_geometry(C, P*, L, R, materiales):
    heading_rad   = rumbo(P*) por estación
    kappa_center  = d(heading_C)/ds        # curvatura del eje
    kappa_opt     = d(heading_P*)/ds       # curvatura de la trazada (la que manda)
    kappa_vertical= d(pendiente)/ds        # convexo <0 descarga, cóncavo >0 comprime
    grade_pct     = 100·dz_horizontal/ds
    camber_deg    = peralte lateral (signado contra curvatura)
    grip_mu       = tabla §3.5.5: nieve 0.55 < arena 0.60 < tierra 0.76
                                < grava 0.85 < asfalto 0.95 (por nombre material)
    RETORNAR columnas por estación
```

### 5.6 `road_validator` — anomalías y `road_geometry.json`

```pseudocodigo
PROCEDIMIENTO build_road_geometry(stage_id, solved, centerline, analysis, route_points):
    PARA cada estación i:
        guide_node[i] = nearest_route_node(s=i·2 m)   # trazabilidad a route.json
        confidence = "high" SI has_corridor y sin flags
                     "medium" SI flags menores / junction con corredor
                     "low"    SI sin corredor
        sección = { s_m, guide_node, has_corridor, center, left_edge, right_edge,
                    opt_line, width_m, heading_rad, kappas, grade, camber, mu,
                    is_junction, anomaly_flags, confidence }
    anomalias = { junction_clamps, mesh_gaps, sharp_width_jumps(dW/ds > 0.35) }
    (opcional) ESCRIBIR GLB debug con trimesh
    RETORNAR { stage_id, step_m: 2.0, sections: [...] }
```

---

## 6. Detección de eventos (v3, `pacenote_analyzer_v3.py`)

### 6.1 `detect_curves` — segmentación multi-ápice

```pseudocodigo
CONFIG: k_enter=1/260, k_exit=1/400, bridge_gap=24 m, trim_frac=0.18,
        min_angle 10°/6.5°, peak_min_dist=45 m, peak_prominencia=1/90,
        split_valley 25% + 30 m, tighten=0.68, open=1.48

PROCEDIMIENTO detect_curves(geo, cfg):
    kc = kappa_center por estación
    active[i] = |kc[i]| >= k_enter
    regiones = rachas_contiguas(active con histéresis k_exit, MISMO signo)
    FUSIONAR regiones mismo sentido separadas < 24 m SIN giro opuesto fuerte en el hueco
    PARA cada región [r0..r1]:
        direccion = right SI kc[pico] > 0 SINO left
        picos = find_peaks(|kc|, distancia_min=45 m, prominencia=1/90)
        SI sin picos: picos = [argmax]
        bounds = [r0] + valles_entre_picos(profundos<25% y largos>=30 m) + [r1]
        PARA cada [q0..q1] entre bounds:
            ev = _build_curve(...) ; SI válido: curvas += ev
    ENLAZAR left<->right con gap<30 m → link="into" (provisional)
    ORDENAR por s_start ; RETORNAR curvas

PROCEDIMIENTO _build_curve(q0, q1):
    núcleo = _core_trim(q0,q1): recorta donde |kc| < max(18%·pico, 1/320)
    SI núcleo degenerado: RETORNAR NULL
    ang_total = |rumbo(q1)-rumbo(q0)|          # giro TOTAL (no solo núcleo)
    SI ang < 10° Y (ang_opt < 6.5° Y R_opt_min > 210 m): RETORNAR NULL  # recta ancha
    apex = argmax(|kc| en núcleo)
    R_geom = 0.65·R_apex + 0.35·R_medio        # combina ápice y media
    sev_geo = severity_for_radius(R_geom)       # 160/110/75/50/32/20/12 → 1..8
    mitades: R_first vs R_second
        SI R_second < 0.68·R_first Y sube severidad: mods += ["tightens"]
        SI R_second > 1.48·R_first:             mods += ["opens"]
    SI longitud >= 135: mods += ["verylong"] ; ELIF >= 80: mods += ["long"]
```

### 6.2 `group_consecutive_curves` — control de densidad

```pseudocodigo
PROCEDIMIENTO group_consecutive_curves(curvas, gap_m=55):
    PARA cada curva en orden s:
        SI anterior.mismo_sentido Y hueco < 55 m:
            anterior.s_end = curva.s_end ; recalcular longitud/ángulo
            SI curva más severa: HEREDAR radios/severidad/ápice/velocidades
            FUSIONAR modifiers ; review += "absorbe {id}" ; merged_ids += id
            curva.status = "grouped_into"  # auditada, no perdida
        SINO: curva.merged_ids = [id] ; kept += curva
    priority = min(95, 35 + 6·sev)
```

### 6.3 `apply_effective_severity` — la física sube la nota

```pseudocodigo
PROCEDIMIENTO apply_effective_severity(curvas, geo, speeds, cfg):
    PARA cada curva:
        p85 = percentil85(grade en [s_start-35 m .. s_end])
        SI p85 <= -9%:  sev += 1 ; mods += ["steep_drop_exit"]   # bajada fuerte
        camber_efectivo en apex (signado contra curvatura)
        SI camber <= -4.5°: sev += 1                            # contraperalte
        demanda_frenada = v_nominal(60 m antes) - min(v_nominal en curva)
        SI demanda >= 12.5 m/s: sev += 1
        SI ang < 100° Y sev == 8: sev = 7                       # square≠hairpin
        priority = min(95, 35 + 6·sev)
```

### 6.4 `compute_speed_profiles` — 3 escenarios + `t(s)`

```pseudocodigo
PROCEDIMIENTO compute_speed_profiles(geo, cfg):
    PARA (tag, grip, vmax) en [(cons,0.85,44),(nom,1.00,50),(fast,1.15,56)]:
        v_curva[s] = sqrt(grip·mu[s]·g / max(|kappa_opt[s]|, eps)) ; cap a vmax
        forward:  v[i] = min(v_curva[i], sqrt(v[i-1]² + 2·(acc - g·sin(slope))·2 m))
        backward: v[i] = min(v[i],     sqrt(v[i+1]² + 2·(brk + g·sin(slope))·2 m))
        SI tag==nominal: t(s) = cumsum(2·2 m / (v[i]+v[i+1]))     # tiempo nominal por s
    RETORNAR { conservative, nominal, fast, t }
```

### 6.5 `extract_obstacles` + `link_obstacles` — peligros pegados al borde

```pseudocodigo
PATRONES (fnmatch sobre material/nombre):
  rock: rock_big_*, stone_*, rock_snow_*, ...      post: pylon_1, phoneline, sign_splimit...
  ditch: *ditch_*, sand_erosion_*                  gate: fence_gate_1, haybarn_*, house_2...
  junction: roadbar1, road_crossroad_*, sign_hardturn...   troncos = roadside_furniture (no postes)

PROCEDIMIENTO extract_obstacles(bmf, center, L, R, cfg):
    índice = cKDTree(center.XZ)
    _collect(verts, etiqueta):
        PARA cada vértice:
            estación = nearest(center) ; bordes L/R de esa estación
            d_edge = min(|v-L|, |v-R|) en XZ
            UMBRALES: post<=1.8 m, rock<=3.2 m, otros<=4.5 m ; |dy|<=3.5 m
            SI pasa: raw += { s, station, side(left/right por signo lateral),
                             d_edge, label, pos }
    RECOGER de TRACK chunks (batches, mat directo) + HIERARCHY (con matrix+pos_extra,
            match por material O por nombre de mesh)
    CLUSTERIZAR por categoría: eps rock/post/ditch=12 m, gate/junction=18 m
        evento = { id HAZ_*, type, s=mediana, s_min/max, side=mayoría,
                   d_edge=min, count, label }
    RE-ETIQUETAR HAZ_001... por posición ; RETORNAR eventos

PROCEDIMIENTO link_obstacles(obstaculos, curvas, cfg):
    PARA cada obstáculo:
        ventana = [s_start_curva - (50 m si sev>=5 SINO 30 m) .. s_end + 12 m]
        SI obstáculo.s en ventana:
            linked_curve = curva.id
            relative_side = "inside" SI mismo lado que dirección SINO "outside"
            SI mismo_lado Y d_edge <= 1.2 m Y tipo en {rock,post,ditch}:
                dont_cut = true ; priority = 85
```

### 6.6 Junctions del corredor

```pseudocodigo
rachas = estaciones contiguas con is_junction=true  →  { id JCT_*, s_start/end/s, fields:{junction:1,caution:1} }
FILTRAR: conservar SOLO si hay curva anfitriona con ángulo >= 55° en ±25 m
         (si el coche sigue recto, el ensanche lateral no se canta)
         → host.is_junction_turn = true
```

### 6.7 `detect_vertical` — un evento por rasante/salto (NMS)

```pseudocodigo
CONFIG: crest_gamma=0.38, jump_gamma=0.75, NMS_dist=45 m, min_delta_grade=4.5%, lookahead 12 m

PROCEDIMIENTO detect_vertical(geo, speeds, cfg):
    gamma[s] = v_fast[s]² · max(-kappa_vertical[s],0) / (g·cos(grade))  # solo convexo
    picos = find_peaks(gamma, altura>=0.38, distancia>=45 m)
    PARA cada pico i:
        delta = max(grade[i-12..i]) - min(grade[i..i+12])
        SI delta < 4.5%: CONTINUAR                       # bache menor, no rasante
        SI gamma >= 0.75 Y (delta>=8% O salida<=-8%): evento jump (priority 90)
        SINO: evento crest (priority 70)
```

---

## 7. Secuencia, planificación y emisión

### 7.1 `build_main_sequence` — qué entra en la frase final

```pseudocodigo
PROCEDIMIENTO build_main_sequence(curvas, junctions, verticales, obstaculos, cfg):
    seq = curvas (kind="curve")
        + junctions válidas (kind="junction", priority 80)
        + verticales no absorbidas (kind="hazard")
        + obstáculos SUELTOS (linked_curve==NULL, no absorbidos):
              fields = standalone_fields(obstáculo)   # §7.1.1
    ORDENAR por (s_start, -priority) ; RETORNAR seq

FUNCION standalone_fields(ob):   # peligro suelto: kind=0, palabra propia
    gate:     { surface:2, hazard:6, turn:3, caution:1 }
    rock:     { hazard:4 }            post: { hazard:5 }   ditch: { hazard:7 }
    junction: { junction:1, caution:1 }
    SI tipo en {rock,post,ditch} Y d_edge <= 1.2: { no_cut:1, caution:1 }
```

### 7.2 `plan_and_emit` — scheduler en dominio `t(s)`

```pseudocodigo
PROCEDIMIENTO plan_and_emit(seq, route_cum, t_of_s, s_grid, cfg):
    CALCULAR gap_prev_m por evento (hueco al anterior emitido)
    runtime=[] ; dropped=[] ; prev_end_t=-inf ; prev_node=-1 ; call_idx=0
    PARA cada evento e en seq:
        words = _compose_words(e)          # §7.2.1 UNA palabra por evento (+ top hazard)
        SI vacío: e.status="dropped" ; CONTINUAR
        dur = Σ speech_duration(word) + 0.15·(n-1)
        t_evt  = t(s_evt) ; t_lead = 1.2 + 0.3·sev + max(demanda_frenada,0)/6
        t_trig = t_evt - (t_lead + dur)  →  s_trig = t⁻¹(t_trig)
        CLAMP s_trig a [s_evt-260 m, s_evt-40 m]     # lead_min/max
        node = ceil(route_cum → s_trig) ; FORZAR estrictamente creciente
        SI solapa con bloque anterior (t_node < prev_end_t + 0.8 s):
            1) anticipar anterior hasta 1.8 s + marcar "into"
            2) SINO degradar por niveles (§7.6); SI no degradable:
                   priority>=70 → "forced_chain_critical" (se encadena igual)
                   SINO → status="dropped"
        SI t_node > latest_t (= t_evt - 1.5 - dur): degradar 1 nivel preventivo
        EMITIR words con call_index, advisory_gate_node, route_distance_m, t_trigger
        e.status="emitted" ; e.emitted_call_ids=[...] ; runtime += words
        prev_end_t = t_node + dur ; prev_node = node
    repack_distances(runtime)      # §7.3
    caution_hoisting(runtime)      # §7.4
    cooldowns(runtime, cfg)        # §7.5 (caution 85 m/4.5 s, hazard 65 m) + re-pack final
    RETORNAR (runtime, dropped)
```

#### 7.2.1 `_compose_words` — una palabra limpia por evento

```pseudocodigo
FUNCION _compose_words(e):
    SI e.kind == "curve":
        f = { kind: sev, direction, length:(long/verylong), turn:(tightens/opens) }
        SI is_junction_turn: f.junction = 1
        SI tiene hazards vinculados: ELEGIR top (dont_cut primero, luego priority)
            f.hazard/surface/side/no_cut/caution según top (side solo si hazard 4,5,7)
            e.linked_hazard_ids=[top.id]   # resto → "absorbed" auditado
        ELIF crest_en_curva: f += { hazard:2, surface:1 }
        RETORNAR [{ word: pack(**f), fields:f, event_id, s_start/end }]
    SINO:  # junction / hazard / suelto
        RETORNAR [{ word: pack(**e.fields), ... }]
```

### 7.3 Repack de `distance` (clases 0–9 por hueco PREVIO)

```pseudocodigo
FUNCION _distance_class(gap_m, ambas_curvas=false):
    gap>=180→9 ; >=135→8 ; >=110→7 ; >=85→6 ; >=60→5 ; >=40→4 ; >=22→3
    >=10→2 ; gap<10 y ambas_curvas→2 ("into" forzado entre curvas pegadas) ; SINO→1 ("and")
    # link hablado: clase 2="into", 1="and", resto=NULL (frase separada)

PROCEDIMIENTO repack_distances(runtime):
    # Se recalcula DESPUÉS de emitir, sobre la adyacencia REAL emitida
    PARA cada palabra w (con su s_start/s_end):
        gap = s_start[w] - s_end[w-1]   (0 si es la primera)
        w.fields.distance = _distance_class(gap, ambas_curvas)
        w.link = "into"/"and"/NULL
```

### 7.4 Caution hoisting en cadenas

```pseudocodigo
# Si palabras van unidas (distance 1/2 = "and"/"into"), forman UNA frase:
# el caution máximo sube a la primera palabra y se borra del resto.
PROCEDIMIENTO caution_hoisting(runtime):
    DETECTAR cadenas [i..j] con distance[i+1..j] en {1,2}
    max_caut = max(caution en cadena)
    SI hay curva kind>=5 en cadena Y ≥2 cautions: max_caut = 2
    cadena[0].caution = max_caut ; cadena[1..].caution = 0
```

### 7.5 Cooldowns anti-redundancia + re-empaquetado

```pseudocodigo
PROCEDIMIENTO cooldowns(runtime, cfg):
    PARA cada palabra w en orden:
        # 3a. caution repetido en 85 m / 4.5 s → suprimir (salvo escalada 1→2)
        SI w.caution>0 Y (s - last_caution_s < 85 O t - last_caution_t < 4.5)
                       Y w.caution <= last_caution_lvl: w.caution = 0
        SINO: last_caution = (s, t, lvl)
        # 3b. mismo hazard estático (rocks=4/post=5/ditch=7) hace <65 m → suprimir
        #     (hazard+side+no_cut+surface a 0) salvo curva actual más cerrada
        SI w.hazard en {4,5,7} Y s - last_hz < 65 Y kind <= last_curve_kind:
            w.hazard=w.side=w.no_cut=w.surface = 0
        w.word = pack_cmr2_word(**w.fields)   # re-empaquetar palabra final limpia
        w.link = "into"/"and" según distance
```

### 7.6 Degradación por niveles (cuando dos frases se pisan)

```pseudocodigo
PROCEDIMIENTO _apply_deg_level(evento, words):
    nivel = evento.deg_level
    SI nivel>=1: length=0 ; turn opens→0          # quita "long/opens"
    SI nivel>=2: length=0 ; side→0 salvo no_cut o hazard rocks
    SI nivel>=3: tightens→0 ; sev+=1 (kind sube, frase más corta y urgente)
    RE-EMPAQUETAR words

FUNCION _degrade(evento, words, cfg):
    PARA nivel en 1..3:
        evento.deg_level = nivel ; _apply_deg_level ; review += "degraded_L{nivel}"
        RETORNAR true                             # v3 siempre conserva (no descarta aquí)
```

### 7.7 `export_documents` — los tres JSON

```pseudocodigo
PROCEDIMIENTO export_documents(runtime, candidates, authoring, country, stage, out_dir):
    runtime.json   = { stage, generator, calls:[hex...],
                       curves:[{call_word_hex, call_index, curve_id: EVT_%03d,
                                advisory_gate_node, route_distance_m, s_start/end,
                                kind_str, direction, link}] }
    authoring.json = { stage, generator, events: authoring }    # emitidos + evidencia
    candidates.json= { stage, generator, events: candidates }   # TODOS los estados
```

---

## 8. Codec CMR2 (compartido v1/v2/v3 + Godot)

> Python: `pack_cmr2_word/decode_cmr2_slots/speech_duration` en v1/v2.
> Godot: `game/scripts/rally/cmr2_pacenote_codec.gd` (`speech_slots`, `icon`).

```pseudocodigo
FUNCION pack_cmr2_word(kind, direction, distance, length, turn, surface,
                       hazard, caution, junction, no_cut, ending, side):
    RETORNAR (kind&15) | (direction&3)<<4 | (distance&15)<<6 | (length&3)<<10
           | (turn&7)<<12 | (surface&3)<<15 | (hazard&15)<<17 | (caution&3)<<21
           | (junction&1)<<23 | (no_cut&1)<<24 | (ending&7)<<25 | (side&3)<<28

FUNCION decode_cmr2_slots(word, mirror=false):   # orden EXACTO OpenCMR2
    SI palabra centinela (kind==6, resto 0): RETORNAR []   # slot vacío, sin voz
    slots = []
    SI kind==9: slots += [55]                             # (reservado)
    SI 1<=distance<=14: slots += [min(13+distance, 22)]   # "30/50/70/100/..."
    SI caution en {1,2}: slots += [{1:26, 2:27}]
    SI length  en {1,2}: slots += [{1:10, 2:28}]          # "long/verylong"
    SI junction==1:      slots += [29]                    # "junction"
    SI 1<=kind<=8: slots += [{1:5,2:4,3:3,4:2,5:1,6:0,7:6,8:7}]  # six..hairpin
    SI direction en {1,2}: slots += [izq/der, con mirror si ESPEJO]
    SI turn en {1,2,3}: slots += [{1:12,2:11,3:30}]       # tightens/opens/narrows
    SI surface en {1,2}: slots += [{1:23,2:31}]           # slippery/narrow surface
    SI 1<=hazard<=15: slots += [tabla hazard→slot]        # 25 jump,24 crest,35 rocks,
                                                          # 36 post,33 gate,37 ditch...
    SI side en {1,2}: slots += [{1:44,2:45}]              # inside/outside
    SI no_cut==1: slots += [46]                           # "don't cut"
    SI 1<=ending<=7: slots += [46+ending]
    RETORNAR slots

FUNCION speech_duration(slots):   # para el planificador temporal
    RETORNAR base_sec(0.35) + Σ duracion_slot(slot)   # tabla por slot en v2/v3
```

---

## 9. `pacenote_runtime.convert_notes` — authoring → runtime Godot

> `tools/pacenote-tooling/runtime/pacenote_runtime.py` (56 líneas; copia operativa en `tools/rally/pacenote_runtime.py`).

```pseudocodigo
FUNCION convert_notes(authoring, route, track_id):
    points = route.points  (validar: ≥2 puntos, ternas finitas, sin segmentos degenerados)
    dist_acum[0]=0 ; dist_acum[i]=dist_acum[i-1]+|p[i]-p[i-1]|
    curves = authoring.curves ORDENADAS por call_index
    VALIDAR call_index == 0..N-1 contiguos y únicos, word en (0, 0xFFFFFFFF]
    gates=[] ; calls=[] ; prev_dist=-1
    PARA cada curve:
        word  = int(curve.call_word_hex, 16)
        entry = curve.route_distance_m
        SI tiene advisory_gate_node: dist = dist_acum[node]   # nodo fijado por scheduler
        SINO: dist = max(0, entry - lead_distance_m(50 por defecto))
        VALIDAR prev_dist < dist <= total Y dist <= entry+1   # ordenadas, únicas, antes de entrar
        seg = bisect(dist_acum, dist)-1                        # segmento de ruta que la contiene
        dir = tangente_unitaria(p[seg]→p[seg+1]) ; VALIDAR no vertical
        lat = normal_horizontal(dir) ; centro = interpolación en dist
        gates += { id: "{track}_CALL_%03d", left: centro-6·lat, right: centro+6·lat,
                   forward_hint: dir, height_tolerance_m: 3.5,
                   route_segment: seg, route_distance_m: dist,
                   lead_distance_m: entry-dist, curve_id, call_index }
        calls += [word] ; prev_dist = dist
    RETORNAR { stage_id, route_point_count, total_distance_m, calls, gates,
               conversion: { version:1, gate_width_m:12.0, height_tolerance_m:3.5 } }
# La puerta es un segmento transversal de 12 m que cruza todo el ancho transitable.
```

---

## 10. `validate_stage` — contrato del paquete exportado

> `validation/validate_stage.py`. 7 checks + CLI `--stage-dir / --country --all`.

```pseudocodigo
PROCEDIMIENTO validate_stage_package(stage_dir):
    1. manifest.json: contract_version==1, start_pose completo
    2. VISUAL GLB: existe, SHA256==manifest, nodos==exported_nodes,
       contiene Track_Road_And_Terrain, samplers wrapS==wrapT (Godot 4)
    3. COLLISION GLB: SHA256 OK, nodos OK, contiene Collision_Road +
       Collision_Barriers con ≥1500 caras (barreras + cards de bosque)
    4. CONTENCIÓN: colisión contenida en visual en X/Z ±1 m
       (el visual puede ser mayor: agua 7×6 km, vegetación cutout)
    5. TIMING GATES: exactamente *_timing_gates.json con 10 gates monótonos,
       visual_marker_audit.minimum_plane_gap_m <= 4.0 m por gate
    6. COMPETICIÓN: *_competition.json con 10 sector_checkpoint_indices + 10 sector_lengths_km
    7. PACENOTES: *_route.json + *_pacenotes.json existen;
       curvas >= max(5, longitud_km·2.5);
       advisory_gate_node únicos, crecientes y en rango;
       TODA palabra decodifica a slots válidos 0..58
    SI todo OK: "[ALL CHECKS PASSED]"
```

---

## 11. Tests v3 — regresión obligatoria russia_stage1

> `tests/test_russia_stage1_v3.py`. 6/6 para aceptar el stage.

```pseudocodigo
T1: giro ~90° izq en s∈[1290,1390]: existe curva left ángulo>=70° sev one/square/openhairpin,
    Y ninguna right>=70° en [1270,1410]            # corrige giro invertido de RU1
T2: recta s∈[2020,2110]: CERO curvas sev 5..8     # sin horquillas fantasma
T3: zona s∈[1060,1210]: existe par left→right con hueco <30 m   # secuencia enlazada
T4: zona s∈[4200,4370]: alguna palabra con hazard==4 (rocks) o no_cut==1
T5: TODA distance>0: hueco_previo cae en el bucket de su clase (±2 m);
    entre curvas pegadas (<22 m) la clase es SIEMPRE 2 ("into")
T6: CERO eventos priority>=70 con estado fuera de {emitted, absorbed, grouped_into}
    o sin emitted_call_ids reales
```

---

## 12. `import_stage_export` — del exporter al juego

> `tools/rally/import_stage_export.py` (320 líneas).

```pseudocodigo
PROCEDIMIENTO import_single_stage(stage_source_dir, backup_dir?):
    manifest = LEER manifest.json ; track_id = manifest.track_id (OBLIGATORIO)
    destinos = game/assets/rally/{track} + game/data/rally + game/data/competition/stages
             + game/data/rally/pacenotes + game/docs/rally/pacenotes + .../metadata
    # GLBs: verificar SHA256 manifest vs archivo; copiar visual+collision;
    #       reescribir blend a ruta absoluta; sellar import_source_manifest_sha256
    COPIAR route.json, timing_gates.json (→ competition/stages/), competition.json (→ {track}.json)
    # PACENOTES (tres casos):
    SI export trae pacenotes.json CON curves:
        docs/..._authoring.json = pace_data (tal cual)
        data/.../{track}.json   = convert_notes(pace_data, route, track)  # runtime
    ELIF ya existe runtime activo:
        adapt_notes(activo, exportado): CONSERVA geometría de gates calibrada,
            remapea call_index→gate, sustituye words, registra changes[]
            [{call_index, curve_id, previous_word, word, previous_gate, gate, evidence}]
    SINO: copiar tal cual
    COPIAR authoring/candidates/metadata/original si existen
    COPIAR texturas PNG de work_cache/{país}/textures_png → {track}_visual_*.png
    SI backup_dir: respaldar todo destino existente antes de escribir
    ESCRIBIR copias + JSONs ; FORZAR .import visual: meshes/force_disable_compression=true
    RETORNAR { track_id, files_copied, documents_written, textures_copied }
```

---

## 13. Runtime Godot (sin Python) — cómo se cantan

### 13.1 `pacenote_gate_tracker.gd` — cruce de puertas 3D

```pseudocodigo
CONFIG: TELEPORT_THRESHOLD=45 m, PLANE_EPSILON=0.01, WIDTH_MARGIN=0.5 m

PROCEDIMIENTO configure(definiciones):
    PARA cada puerta { left, right, forward_hint }:
        lateral = right-left (VALIDAR no degenerada) ; hint_dir normalizado
        road_normal = norm(lateral × hint) (hacia +Y)
        normal  = norm(road_normal × lateral) (hacia hint)
        up      = norm(normal × lateral)
        puerta += { center:(L+R)/2, lateral, up, normal,
                    half_width:|lateral|/2, height_tolerance_m }
    next_gate=0

FUNCION advance(prev_pos, curr_pos):   # llamada cada física con ambas posiciones
    SI salto > 45 m: teleport_to(curr) ; RETORNAR []     # rescate/glitch, sin ráfaga
    cruces=[]
    MIENTRAS next_gate < N:
        c = cruce_puerta(next_gate, prev, curr):
            before=(prev-center)·normal ; after=(curr-center)·normal
            EXIGIR before<eps Y after>0 (cruce negativo→positivo)
            fracción=-before/(after-before) en [0,1]
            punto=lerp(prev,curr,fracción); EXIGIR |lateral|<=half+0.5 Y |up|<=tol
        SI cruza: cruces+={index,fracción,punto,puerta,omitted:false} ; next_gate++
        SINO: BUSCAR hasta +8 puertas adelante (recuperación de trazada/corte):
              SI alguna cruza: marcar [next..j-1] como saltadas (skipped_indices),
                               next_gate=j+1 ; CONTINUAR
              SINO: ROMPER
    RETORNAR cruces
```

### 13.2 `rally_pacenote_controller.gd` — orquestador

```pseudocodigo
PROCEDIMIENTO configure(stage_data_path):   # ej. res://data/rally/pacenotes/russia_stage1.json
    RESETEAR tracker + call_queue + speech_queue (+crear AudioStreamPlayer si falta)
    CARGAR sound_bank desde provenance.json (slot→WAV, bus "Copilot")
    CARGAR calls[] (palabras) ; tracker.configure(gates[])
    PRECALCULAR route_distances acumuladas desde {track}_route.json (para off_route/teleport)
    active=true

PROCEDIMIENTO advance(posición, dt):   # cada frame físico, tras actualizar el curso
    progreso = proyección a route_points (segmento más cercano; on_route si error²<=100)
    SI off_route o teleport (>45 m): LIMPIAR presentación; REANCLAR next_gate por delante;
                                     NO repasar llamadas vencidas ; RETORNAR
    cruces = tracker.advance(last_pos, posición)
    PARA cada cruce con call_index válido:
        call_queue.queue_call(word) ; EMITIR señal call_triggered(idx, word)
    PARA cada llamada nueva sin asignar (flag 0x200):
        speech_queue.assign_slot(*speech_slots(primary, mirror))
        SI secondary: speech_queue.assign_slot(*speech_slots(secondary, mirror))
    RELOJ compatibilidad 25 Hz: tick_accum+=dt;
        has_upcoming = alguna de las 6 próximas puertas tiene call
        MIENTRAS tick>=1/25: call_queue.step_tick(has_upcoming)
    speech_queue.update(player, bank, dt)   # reproduce UNA muestra cada vez, secuencial
    hud.update(active_record, mirror)
EVENTOS: on_start_countdown(3/2/1/0→slots 56/57/58/13), on_rescue/teleport,
         on_retry(reset 0), on_retire(stop), on_pause(stream_paused)
```

### 13.3 Contratos Godot que blindan el importado

```pseudocodigo
# pacenote_import_traversal_contract.gd (stages 2..10): recorre la ruta interpolada a 2 m
#   y EXIGE: cero skipped_indices, len(vistas)==len(calls), orden 0..N-1 exacto.
# pacenote_recovery_contract.gd: teleport/rescate/recuperación sin llamadas fantasma.
# rally_pacenote_controller_test.gd / pacenote_full_stage_probe.gd: integración voz+HUD.
# Comandos: godot --headless --path game -s tests/rally/<test>.gd
```

---

## 14. Tabla de decisiones (resumen de una línea por etapa)

| Etapa | Pregunta que responde | Si falla… |
|---|---|---|
| mesh_extractor | ¿Qué es calzada / cruce / barrera en el BMF? | No hay corredor: revisar taxonomía de materiales del país |
| cross_sections | ¿Dónde están los bordes L/R cada 2 m? | Huecos `has_corridor=false`, confidence baja |
| corridor_solver | ¿El muro recorta el borde? ¿Qué rama es la buena? | Anchos falsos en cruces → junctions fantasma |
| centerline | ¿Eje suave + trazada mínima curvatura? | Kappa ruidosa → curvas fragmentadas |
| geometry_analyzer | ¿kappa/grade/camber/mu por estación? | Severidades y velocidades wrong |
| validator | ¿La reconstrucción es sana? | Clamps/gaps/sharp jumps altos |
| detect_curves | ¿Dónde empieza, dónde apica, dónde acaba cada curva? | Falsas curvas en rectas / curvas partidas |
| effective_severity | ¿La física (bajada, peralte, frenada) sube la nota? | Notas demasiado optimistas en bajadas |
| obstacles | ¿Qué peligros tocan el borde real? | Ruido de bosque / postes lejanos cantados |
| verticals | ¿Rasante o salto, y solo uno por loma? | Dobles "crest-crest" o saltos inventados |
| plan_and_emit | ¿Cabe la frase a esta velocidad sin pisar la anterior? | Solapes de voz → degradar/agrupar/dropear |
| cooldowns | ¿No repetimos "caution"/"rocks" cada 50 m? | Copiloto pesado y redundante |
| validate_stage | ¿El paquete cumple el contrato runtime? | Rechazo del stage antes de importar |
| v3 tests 6/6 | ¿Regresión RU1 verde? | No se acepta el stage |
| import | ¿Qué llegó al juego y qué cambió? | Revisar `changes[]` y `*_export_import.json` |
| traversal contract | ¿Godot cruza las N puertas en orden? | Revisar geometría de gates (12 m, tol 3.5 m) |

---

## 15. Límites conocidos y supuestos explícitos

1. `STEP_M = 2.0 m` en todo v3; `guide_node` es trazabilidad, no resolución de aviso (el aviso lo fija `advisory_gate_node` del scheduler).
2. Severidades 1..8 por radios propios calibrados (160/110/75/50/32/20/12 m) — documentado como umbrales propios, no universales CMR2.
3. `distance` hablada es campo editorial (clase 0..9 por hueco previo), no medida recalculada en runtime; si el hueco no encaja en 30/50/70/100/120/150/200 se deja sin voz engañosa.
4. Tres escenarios de velocidad (44/50/56 m/s cap, grips 0.85/1.00/1.15); el scheduler usa el nominal para `t(s)`.
5. Cooldowns: caution 85 m/4.5 s, hazards repetidos 65 m; NMS vertical 45 m; lookahead obstáculos 30–50 m.
6. Puertas runtime: 12 m de ancho, tolerancia vertical 3.5 m, recuperación 8 puertas, teleport 45 m.
7. v1/v2 (~22 llamadas) vs v3 (51 en RU1): v3 canta peligros sueltos y verticales como entradas propias; la densidad objetivo es ~1/95–98 m como el CMR2 original.
