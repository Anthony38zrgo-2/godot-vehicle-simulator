# Rally Trophy — Motores históricos de competición

**Dossier técnico consolidado · 11 vehículos · referencia principal: 1964–1976**  
**Versión:** 1.0 · **Fecha de compilación:** 13-11-2026  
**Aplicación prevista:** documentación histórica y parametrización de motores en *Rally Maniac*.

> **Alcance.** Se documentan **únicamente variantes de competición** compatibles con los once coches de *Rally Trophy*. Las especificaciones de producción solo se mencionan cuando permiten distinguir una preparación histórica. No es una reproducción demostrada de las configuraciones internas del videojuego original.
>
> **Criterio de evidencia:** **[F]** dato explícito de ficha FIA u homologación; **[D]** documento de fabricante, preparador, archivo de época o publicación contemporánea; **[A]** aproximación respaldada por referencias históricas pero no cerrada para una unidad concreta; **[P]** propuesta de calibración/simulación, **no medida**. Una homologación determina componentes admisibles, **no** qué combinación se montó en todas las pruebas.

## Índice

1. [Cuadro comparativo](#1-cuadro-comparativo)
2. [Fichas técnicas por motor](#2-fichas-técnicas-por-motor)
3. [Masas homologadas e inercias](#3-masas-homologadas-e-inercias)
4. [Geometría y velocidad media de pistón](#4-geometría-y-velocidad-media-de-pistón)
5. [Implicaciones para una simulación física](#5-implicaciones-para-una-simulación-física)
6. [Vacíos documentales y prioridades](#6-vacíos-documentales-y-prioridades)
7. [Fuentes históricas](#7-fuentes-históricas)

## 1. Cuadro comparativo

| Vehículo | Preparación de referencia | Arquitectura y distribución | Cilindrada | Diámetro × carrera | Potencia de competición | Estado |
|---|---|---|---:|---:|---|---|
| Mini Cooper S 1275 Mk1 | BMC Works Rally, 1965–67 | L4, OHV, 8 válvulas | 1.275 cm³ | 70,63 × 81,33 mm | ~100–110 hp | [A] |
| Ford Lotus Cortina Mk1 | Lotus Twin Cam competición, 1963–66 | L4, DOHC, 8v | 1.558 cm³ | ~82,6 × 72,8 mm | 145 bhp a 7.500 rpm | [D] |
| Saab 96 V4 | Saab Sport & Rally Group 2, 1972 | V4 60°, OHV, 8v | 1.498 cm³ | 90 × 58,86 mm | 105–130 hp DIN | [D] |
| Volvo Amazon 122S | Volvo B18 de rally, años 60 | L4, OHV, 8v | 1.778 cm³ | 84,1 × 80 mm | ~115–135 hp | [P] |
| Fiat-Abarth 1000 TC | 1000 Berlina Corsa, 1966 | L4, OHV, 8v | 982 cm³ | 65 × 74 mm | 85 hp, régimen ~7.600 rpm | [D] |
| Opel Kadett B Rallye | 19S CIH Group 2, 1968–72 | L4, CIH, 8v | 1.897 cm³ | 93 × 69,8 mm | hasta ~160 hp a 7.000 rpm | [A] |
| Alfa Romeo Giulia GTA | Autodelta 1600 Corsa, 1965–67 | L4, DOHC, 8v, doble encendido | ~1.570 cm³ | 78 × 82 mm | 158 hp DIN (Tipo 532); hasta ~170 hp en otras preparaciones | [D] |
| Lancia Fulvia 1.6 HF | Squadra Corse Group 4, 1969–73 | V4 11°20′, DOHC, 8v | 1.584 cm³ | 82 × 75 mm | ~156–165 hp a 7.200 rpm | [A] |
| Ford Escort Mk1 RS2000 | Ford Boreham Group 2, 1974 | L4, SOHC Pinto, 8v | 1.993 cm³ | 90,82 × 76,95 mm | **165 bhp a 6.750 rpm** | [D] |
| Alpine A110 1600 | Renault-Mignotet Group 4, 1970–72 | L4, OHV, 8v | **1.596 cm³** | **77,8 × 84 mm** | ~155 hp DIN a 7.000 rpm | [D/A] |
| Lancia Stratos HF | Dino V6 Group 4, 1974–76 | V6 65°, DOHC, 12v | 2.418 cm³ | 92,5 × 60 mm | hasta ~280 bhp | [D/A] |

**Lectura de las cifras.** `hp`, `bhp`, `hp DIN` y `CV` no son automáticamente intercambiables: las publicaciones históricas mezclan normas y condiciones de ensayo. No se ha forzado una conversión ficticiamente exacta. **Las horquillas pertenecen a preparaciones diferentes**, no a una sola curva de potencia con tolerancia estadística.

## 2. Fichas técnicas por motor

### 2.1 Mini Cooper S 1275 Mk1 — BMC Works Rally (1965–1967)

| Campo | Característica |
|---|---|
| Configuración | Cuatro cilindros en línea, atmosférico, instalación transversal, tracción delantera |
| Construcción | Bloque y culata de hierro fundido; cigüeñal de **3 apoyos** |
| Cilindrada / geometría | 1.275 cm³; 70,63 × 81,33 mm; carrera larga |
| Distribución | OHV, un árbol en bloque, varillas, balancines, cadena dúplex; 2 válvulas/cilindro |
| Encendido | Orden 1-3-4-2 |
| Carburación | Dos SU de depresión variable; variantes homologadas HS2 y H4/HS4 según configuración |
| Compresión | Homologadas alternativas **9,75:1** y **12,0:1**; no atribuir una a todos los Works |
| Culata [F] | Admisión ~35,58/37,71 mm; escape ~30,84/30,96 mm; alzada registrada ~10,01 mm |
| Potencia | ~100–110 hp [A], sin curva Works única comprobada |

**Preparación:** mecanizado de conductos, distribución deportiva, pistones de elevada compresión, equilibrado, escape y refrigeración de aceite. La caja de cambios comparte aceite con el motor, elemento relevante para pérdidas y gestión térmica. **Nota:** las masas FIA de la sección 3 son de homologación, no prueba de volante aligerado en cada coche oficial. **Simulación:** buen par medio, caída por llenado a alto régimen y masa/inercia acoplada a transmisión. **Fuentes:** [S1].

### 2.2 Ford Lotus Cortina Mk1 — Lotus Twin Cam (1963–1966)

| Campo | Característica |
|---|---|
| Configuración | L4 atmosférico, delantero longitudinal |
| Construcción | Bloque Ford de hierro; culata Lotus de aluminio; cigüeñal de **5 apoyos** |
| Cilindrada / geometría | 1.558 cm³; ~82,6 × 72,8 mm |
| Distribución | **DOHC**, cadena, 8 válvulas |
| Carburación | Dos Weber **45 DCOE** horizontales |
| Compresión | ~11,0:1 en la preparación documentada |
| Rendimiento | **145 bhp a 7.500 rpm** [D] |
| Variantes | Conversión de competición a **1.598 cm³**, distinta del motor 1.558 |

**Preparación:** árboles deportivos, culata trabajada, refrigerador de aceite, bomba eléctrica de combustible y escape de ~2 pulgadas; algunas conversiones incluían aumento de cilindrada. **Simulación:** potencia específica alta, zona útil desplazada hacia altas RPM y admisión Weber sensible a la apertura del acelerador. No mezclar curva del 1.558 con la del 1.598. **Fuentes:** [S2].

### 2.3 Saab 96 V4 — Saab Sport & Rally Group 2 (1972)

| Campo | Característica |
|---|---|
| Configuración | **V4 a 60°**, delantero longitudinal, tracción delantera |
| Construcción | Ford Taunus V4; culatas/bloque de hierro; **eje equilibrador** |
| Cilindrada / geometría | 1.498 cm³; **90 × 58,86 mm** |
| Distribución | OHV, 8 válvulas, árbol en bloque y varillas |
| Potencia 1.5 | **105–130 hp DIN** según especificación de preparación [D] |
| Otra variante | 1.7 V4: **125–145 hp DIN**, **no** intercambiable con el 1.5 |
| Árbol preferente para rally | Perfil Saab **7.6**; más equilibrado que 8.3 de circuito |
| Alzada documentada | ~10,9–11,5 mm según balancines |
| Reglaje árbol 7.6 | Holguras ~0,50 mm admisión / ~0,60 mm escape |
| Válvulas deportivas | 42/37 mm; opción 44/38 mm |
| Carburación | Weber 40 DFI, o dos Solex 40–42 CCI, o dos Weber DCOE |
| Compresión | Hasta ~10,5:1 con junta convencional; hasta 11,5:1/11,0:1 con anillos especiales, según carburación |
| Aceite | Presión caliente objetivo documentada: ~6–6,5 bar |

**Preparación documentada:** taqués de **79 g** frente a **100 g** originales, engranajes reforzados de distribución/equilibrado, bomba de aceite modificada y componentes específicos de culata. El manual Saab-Scania de junio de 1972 permite identificar estas alternativas, pero no contiene una curva universal para todos los motores. **Simulación:** pulsos propios de V4 de 60°, efecto del equilibrador, limitación por llenado/culata y mayor área de par con árbol 7.6. **Fuente central:** [S3].

### 2.4 Volvo Amazon 122S — B18 de rally (años sesenta)

| Campo | Característica |
|---|---|
| Configuración | L4 delantero longitudinal, atmosférico |
| Construcción | Bloque/culata de hierro; cigüeñal de **5 apoyos** |
| Cilindrada / geometría | **1.778 cm³**, 84,1 × 80 mm |
| Distribución | OHV, 8 válvulas |
| Carburación deportiva | Dos SU HS6; otras opciones de competición según preparación |
| Potencia para calibrar | **~115–135 hp [P]**, no curva primaria validada de un B18 Works concreto |

**Preparación plausible de época:** trabajo de culata, mayor compresión, árbol deportivo, muelles reforzados, escape 4-1 o de cuatro ramas, equilibrado y carburación mejorada. **Advertencia documental:** el catálogo Volvo R-Sport de finales de los setenta registra árbol **R** (alzada **11,68 mm**, duración **287°**, mejor par ~4.500 rpm y potencia ~6.200 rpm) y árbol **S** (alzada **12,95 mm**, duración **300°**, hasta ~7.000 rpm), pero es posterior a los principales rallies del Amazon. Además, sus preparaciones de **145/165 hp DIN** exigen agrandar el B18 a dimensiones **B20**. **No atribuir esas cifras al B18 1.778 original.** **Simulación:** priorizar curva de par media y robustez; conservar incertidumbre en potencia exacta. **Fuente:** [S4].

### 2.5 Fiat-Abarth 1000 TC — 1000 Berlina Corsa (1966)

| Campo | Característica |
|---|---|
| Configuración | L4 atmosférico, motor trasero, refrigeración líquida |
| Construcción | Motor Abarth basado en Fiat; distribución OHV de 8 válvulas |
| Cilindrada / geometría | **982 cm³**, 65 × 74 mm |
| Compresión de competición | Hasta **13,0:1** en evolución de 1966 [D] |
| Rendimiento histórico | **85 hp**; régimen elevado a **~7.600 rpm** [D] |
| Alimentación | Carburación Weber de competición; modelo exacto no cerrado para todas las unidades |

**Preparación:** pistones de alta compresión, culata y conductos modificados, árbol deportivo, equilibrado, carburación y refrigeración reforzada. La carrera de 74 mm a 7.600 rpm produce una velocidad media de pistón de ~18,7 m/s. **No confundir** con el **1000 TCR** de culata radial y más de 100 hp ni con el **1000 Bialbero** DOHC. **Simulación:** escasa cilindrada, poca reserva de par, gran sensibilidad a RPM y altas pérdidas térmicas relativas. **Fuente:** [S5].

### 2.6 Opel Kadett B Rallye — 19S CIH Group 2 (1968–1972)

| Campo | Característica |
|---|---|
| Configuración | L4, delantero longitudinal, atmosférico |
| Construcción | Bloque/culata de hierro; cigüeñal de 5 apoyos |
| Cilindrada / geometría | **1.897 cm³**, **93 × 69,8 mm** |
| Distribución | **CIH** (*cam-in-head*): árbol dentro de culata, cadena, balancines; 8 válvulas |
| Válvulas de homologación | ~40 mm admisión / ~34 mm escape |
| Potencia máxima de preparaciones | Hasta **~160 hp a 7.000 rpm [A]**, no atribuible a todo Group 2 |
| Evoluciones | FIA registra preparaciones de culata, carburación, bielas y posterior **cárter seco** |

**Preparación:** conductos, carburadores de competición, distribución más agresiva, relación de compresión elevada y escape libre. Una configuración de cárter seco posterior no representa automáticamente a todos los Kadett tempranos. **Simulación:** mayor cilindrada, carrera corta, par relativamente abundante y banda de potencia que depende mucho del árbol/culata. **Fuente:** [S6].

### 2.7 Alfa Romeo Giulia GTA — Autodelta 1600 Corsa (1965–1967)

| Campo | Característica |
|---|---|
| Configuración | L4 atmosférico delantero longitudinal |
| Construcción | Bloque y culata de aluminio, camisas; cigüeñal de **5 apoyos** |
| Cilindrada / geometría | ~**1.570 cm³** nominales; **78 × 82 mm** |
| Distribución | **DOHC**, cadena, 8 válvulas |
| Encendido | **Dos bujías por cilindro** (Twin Spark), distribuidor para 8 bujías |
| Carburación | **2 Weber 45 DCOE** |
| Compresión | ~**10,5:1** en una preparación documentada |
| Rendimiento | Motor **Autodelta Tipo 532**: **157,79 hp DIN a 7.600 rpm** en curva de 1966; otras evoluciones ~170 hp a 7.800 rpm |

**Preparación:** cigüeñal especial de acero con ocho contrapesos según descripciones Autodelta, volante aligerado, equilibrado de pistones/bielas, conductos, levas, radiador de aceite, cárter y escape de competición. **No unir** la curva medida del Tipo 532 con el valor máximo de una evolución posterior. **Simulación:** doble encendido y avance propios; menor inercia si se confirma volante aligerado; eficiencia volumétrica máxima a RPM altas. **Fuentes:** [S7], [S8].

#### Curva original Autodelta Tipo 532 (noviembre de 1966)

| RPM | Potencia (hp DIN) | RPM | Potencia (hp DIN) |
|---:|---:|---:|---:|
| 2.700 | 50,97 | 6.000 | 137,67 |
| 3.000 | 56,32 | 6.500 | 148,47 |
| 3.500 | 65,70 | 6.800 | 151,06 |
| 4.000 | 75,51 | 7.000 | 154,05 |
| 4.500 | 93,87 | 7.200 | 156,19 |
| 5.000 | 113,68 | 7.400 | 156,67 |
| 5.500 | 121,61 | 7.500 | 157,23 |
| — | — | 7.600 | **157,79** |
| — | — | 7.800 | 155,30 |

**Diagrama de distribución del Tipo 532, según la publicación citada:**

| Parámetro | Admisión | Escape |
|---|---:|---:|
| Apertura | 52° antes de PMS | 64° antes de PMI |
| Cierre | 73° después de PMI | 43° después de PMS |
| Duración | 305° | 287° |
| Alzada | 10,2 mm | 10,2 mm |

Estas cifras son particularmente valiosas para ajustar la ley de potencia sin crear artificialmente una curva plana. Si se necesita par en Nm, convertir **cada punto** a partir de la potencia y RPM usando la convención de potencia elegida, evitando mezclar hp y CV.

### 2.8 Lancia Fulvia 1.6 HF — Squadra Corse Group 4 (1969–1973)

| Campo | Característica |
|---|---|
| Configuración | **V4 estrecho 11°20′**, motor inclinado ~45°, tracción delantera |
| Construcción | Bloque de hierro, **una culata de aluminio compartida**, cigüeñal de **3 apoyos** |
| Cilindrada / geometría | **1.584 cm³**, 82 × 75 mm |
| Distribución | **DOHC**, un árbol para admisión y otro para escape en culata común; 8 válvulas |
| Carburación | Dos Solex de doble cuerpo, familia **42 DDHF** en preparaciones HF |
| Válvulas | ~38 mm admisión / ~34 mm escape |
| Compresión | **10,5:1 [F]**; hasta ~**11,5:1 [A]** en preparación avanzada |
| Rendimiento | ~**156–165 hp a 7.200 rpm [A]**; par citado ~172 Nm a 6.000 rpm |

**Preparación:** culata y conductos deportivos, árboles de levas especiales, muelles, carburación y pistones de mayor compresión. El V4 estrecho **no es intercambiable** con el Saab de 60°: cigüeñal, culata, distribución y firma de pulsos son diferentes. **Simulación:** orden/intervalos reales de encendido, sensibilidad a carburación y elevada dependencia del régimen. **Fuente:** [S9].

### 2.9 Ford Escort Mk1 RS2000 — Ford Boreham Group 2 (1974)

| Campo | Característica |
|---|---|
| Configuración | L4 delantero longitudinal, motor **Ford Pinto** |
| Construcción | Bloque/culata de hierro, cigüeñal de 5 apoyos |
| Cilindrada / geometría | **1.993 cm³**, **90,82 × 76,95 mm** |
| Distribución | **SOHC**, correa dentada, 8 válvulas |
| Alimentación | **2 Weber 45 DCOE** |
| Compresión | **10,9:1** |
| Potencia | **165 bhp a 6.750 rpm** |
| Par máximo | **152 lb·ft a 4.000 rpm ≈ 206 Nm** |
| Culata y escape | Conductos preparados; válvulas de Capri V6; colector Janspeed según Boreham |

**Referencia documental:** Ford Escort RS2000 **AOO 674L**, preparado por Boreham. Es de los pocos motores de esta selección con potencia máxima, par máximo y RPM documentados en una **misma preparación**. También existieron RS2000 oficiales Group 1 con ~140–150 bhp y carburadores Solex de tiro descendente, una variante distinta. **No sustituir por Cosworth BDA/BDG** de otros Escort. **Simulación:** curva con par medio importante a 4.000 rpm y pérdida progresiva hacia el máximo de potencia a 6.750 rpm. **Fuente:** [S10].

### 2.10 Alpine A110 1600 — Renault-Mignotet Group 4 (1970–1972)

| Campo | Característica |
|---|---|
| Configuración | L4 longitudinal trasero, atmosférico, refrigerado por líquido |
| Construcción | Familia Renault Cléon-Alu: bloque y culata de aluminio, camisas de hierro, cigüeñal de 5 apoyos |
| Distribución | **OHV**, árbol lateral, 8 válvulas |
| Motor de partida | **1.565 cm³**, **77 × 84 mm** |
| Motor de competición elegido | **1.596 cm³**, **77,8 × 84 mm**; preparación Mignotet Group 4 |
| Carburación | **2 Weber 45 DCOE** |
| Compresión | ~**11,25:1 [A]** para preparación Group 4 citada |
| Rendimiento | ~**155 hp DIN a 7.000 rpm** |
| Lubricación | Cárter húmedo; radiador de aceite en preparaciones deportivas |

**Preparación:** pistones y cilindrada modificados, culata, distribución, carburación, equilibrado y refrigeración de aceite. La ficha FIA del motor base 1.565 cm³ registra ~4 L de aceite y ~10 L de refrigerante; son referencias de homologación, no cantidades demostradas para todos los Mignotet. **No aplicar** 155 hp / 1.596 cm³ a un 1.565 sin modificar; tampoco utilizar sin distinción el posterior 1.8 L. **Simulación:** tendencia a subir de RPM, respuesta de Weber y fuertes efectos dinámicos del montaje trasero en el vehículo (separar física del motor de distribución de masas del coche). **Fuente:** [S11].

### 2.11 Lancia Stratos HF — Ferrari Dino V6 Group 4 (1974–1976)

| Campo | Característica |
|---|---|
| Configuración | **V6 a 65°**, motor central-trasero transversal |
| Construcción | Bloque de hierro, culatas de aluminio, cigüeñal de **4 apoyos** |
| Cilindrada / geometría | **2.418 cm³**, **92,5 × 60 mm** |
| Distribución | **DOHC por bancada** (4 árboles), cadena, **12 válvulas** |
| Carburación | **3 Weber 40 IDF dobles**, preparados para competición |
| Diámetros de válvula [F] | Admisión ~42,5 mm; escape ~36,8 mm |
| Compresión de preparación [D] | ~**11,5:1** en prueba de 1975 |
| Potencia | Hasta **~280 bhp** en evolución rally Group 4; no toda unidad de 1974 |
| Régimen | Prueba de 1975: restringido a **7.500 rpm**, con capacidad descrita hasta **8.500 rpm** |

**Preparación:** pistones, levas, válvulas, carburación y escape de competición. FIA registra cárter húmedo y ~7 L de aceite en el conjunto homologado. Los motores de **24 válvulas** (~300–320 hp, según evolución) son una **configuración diferente** y quedan fuera de esta referencia de 12 válvulas. **Simulación:** gran capacidad de llenado, régimen alto, velocidad media de pistón relativamente contenida por la carrera de 60 mm, seis pulsos de combustión por ciclo y admisión/escape específicos del Dino V6. **Fuentes:** [S12], [S13].

## 3. Masas homologadas e inercias

**Masas de fichas FIA [F]** (no equivalentes a masas reales de piezas aligeradas instaladas en todas las pruebas):

| Motor | Cigüeñal | Volante | Biela (una) | Pistón y accesorios |
|---|---:|---:|---:|---|
| Mini Cooper S | 10,8 kg | 6,8 kg | 680 g | Pistón + segmentos ~290 g; bulón ~90 g |
| Opel CIH 1.9 | ~16,7 kg | ~10,1 kg | ~620 g | Conjunto ~777 g |
| Lancia Fulvia 1.6 | 12,0 kg | 6,0 kg | 705 g | Conjunto ~545 g |
| Alpine A110 1600 base | ~12,5 kg | ~8,0 kg | ~652 g | Conjunto ~478 g |
| Lancia Stratos V6 | 16,3 kg | 8,1 kg | 565 g | Conjunto ~534 g |

**Advertencias:** las convenciones de pesaje de pistones, segmentos y bulones varían entre homologaciones; no sumar ciegamente. La **masa** de cigüeñal o volante **no es su momento de inercia**; este requiere radios y distribución de masa. No se han recuperado momentos de inercia medidos de estos motores preparados.

## 4. Geometría y velocidad media de pistón

Fórmula empleada: `v_media [m/s] = (2 × carrera [m] × RPM) / 60`. Es una **magnitud calculada** y **no** un límite de seguridad ni medición de esfuerzo máximo.

| Motor | RPM usada | Velocidad media del pistón | Interpretación |
|---|---:|---:|---|
| Mini 1275 | 6.800 | 18,4 m/s | RPM de comparación, no límite Works acreditado |
| Lotus Twin Cam | 7.500 | 18,2 m/s | Régimen de potencia documentada |
| Saab 1.5 V4 | 6.500 | 12,8 m/s | RPM de comparación, no máximo certificado |
| Volvo B18 | 6.500 | 17,3 m/s | RPM de comparación, no máximo certificado |
| Abarth 1000 TC | 7.600 | 18,7 m/s | Régimen publicado de evolución 1966 |
| Opel 19S CIH | 7.000 | 16,3 m/s | Referencia de preparación avanzada |
| Alfa GTA | 7.800 | 21,3 m/s | Punto de curva de banco 1966 |
| Fulvia 1.6 HF | 7.200 | 18,0 m/s | Régimen de potencia aproximado |
| Escort RS2000 | 6.750 | 17,3 m/s | Régimen de potencia Boreham documentado |
| Alpine Group 4 | 7.000 | 19,6 m/s | Régimen de potencia de preparación 1.596 |
| Stratos V6 | 8.500 | 17,0 m/s | Régimen alto descrito en prueba de época |

## 5. Implicaciones para una simulación física

### 5.1 Diferenciar arquitecturas, no solo potencias

| Familia | Motores | Característica que conviene modelar |
|---|---|---|
| L4 OHV | Mini, Volvo, Abarth, Alpine | Régimen útil, fricción de varillas/balancines, admisión y distintas relaciones carrera/diámetro |
| L4 DOHC | Lotus Cortina, Alfa GTA | Culatas de mayor caudal, potencia específica alta y levas de competición |
| L4 CIH/SOHC | Opel, Escort Pinto | Cinemática de distribución y par medio; CIH **no** equivale a Pinto SOHC |
| V4 | Saab, Fulvia | Ángulos de bancadas muy diferentes (**60°** vs **11°20′**) y culatas/distribuciones distintas |
| V6 | Stratos | V6 65°, 12 válvulas, carburación triple y potencia a elevado régimen |

### 5.2 Variables mínimas para cada configuración

Para una reproducción utilizable: `engine_id`, `variant_year`, `displacement_cc`, `bore_mm`, `stroke_mm`, `cylinder_layout`, `bank_angle_deg`, `valvetrain`, `valves_per_cylinder`, `compression_ratio`, `induction_type`, `carburetors`, `firing_order`, `power_curve_rpm_hp`, `torque_curve_rpm_nm`, `idle_rpm`, `max_rpm`, `rotational_inertia_kg_m2`, `mechanical_friction_model`, `cooling_capacity`, `oil_system` y referencias de evidencia por campo.

**No crear datos históricos ficticios:** cuando no exista curva de banco, es legítimo generar una **curva simulada [P]**, etiquetarla expresamente y separarla del conjunto de datos históricos. Los campos de compresión, carburación y potencia deben quedar vinculados a **la misma variante/año**: mezclar la culata, la compresión y la potencia máxima de evoluciones diferentes crea un motor que quizá nunca existió.

### 5.3 Calibración de dinámica de motor

- **Par/potencia:** preferir curva medida; si solo existe potencia máxima y un punto de par, no inventar una curva «documentada». Priorizar **Alfa Tipo 532** y **Escort Boreham** para validar el modelo.
- **Inercia:** registrar `I_crank`, `I_flywheel`, `I_clutch`, `I_accessories` como estimaciones separadas y editables; la masa de volante no basta para convertirla a inercia.
- **Transitorios:** carburadores SU de depresión variable (Mini/Volvo) y Weber DCOE/IDF (otros) no deberían tener la misma respuesta de mezcla ante apertura rápida; diferenciar retardo de admisión y enriquecimiento.
- **Distribución:** respetar alzada, duración y cruces cuando existan datos (especialmente Alfa y preparaciones Saab/Volvo), evitando extrapolar valores de un motor a otro.
- **Sonido procedural:** usar frecuencia y secuencia de pulsos, orden de encendido, colectores de escape y resonancia de admisión propios. **Saab V4 ≠ Fulvia V4**; **Stratos V6 ≠ tres pares de L4**.
- **Fiabilidad/térmica:** vincular refrigeración y lubricación a la preparación; no asumir cárter seco en modelos cuyo año no lo incluye.

### 5.4 Orden recomendado de modelado según evidencia

1. **Saab 96 V4:** instrucciones originales de preparación excepcionalmente detalladas.
2. **Alfa GTA Tipo 532:** curva de banco y distribución histórica utilizables directamente.
3. **Escort RS2000 Boreham:** potencia, par y régimen de una misma preparación.
4. **Alpine A110 1600 Group 4 y Stratos Group 4:** variantes reconocibles pero aún faltan curvas completas.
5. **Mini, Lotus, Fulvia, Abarth y Opel:** reconstrucción gradual condicionada por variantes/años.
6. **Volvo B18:** cerrar primero preparación de rally auténticamente contemporánea; evitar mezclar el catálogo R-Sport posterior.

## 6. Vacíos documentales y prioridades

| Dato pendiente | Estado | Prioridad |
|---|---|---|
| Curva completa de par y potencia | Verificada para Alfa Tipo 532; parcial o desconocida en los demás | **P0** |
| Combinación exacta de compresión + levas + carburadores por temporada | Completa solo parcialmente; muchas variantes | **P0** |
| Inercia real de cigüeñal/volante preparados | Masas homologadas parciales, sin momentos de inercia | **P0** |
| Orden e intervalos efectivos de encendido, colectores | Verificación específica pendiente para sintetizador de sonido | **P0–P1** |
| Avance de encendido vs. RPM y carga | Datos incompletos | **P1** |
| Longitudes de biela, masas alternativas, geometría de pistones | Parcial | **P1** |
| Coeficientes de flujo de culata, tamaño de difusores | Incompleto | **P1** |
| Fricción, pérdidas de bombeo y consumo específico | Sin bancos comparables | **P1** |
| Volúmenes de aceite/refrigerante, presión de aceite, temperatura | Parcial (Saab, homologaciones FIA) | **P2** |
| Fiabilidad por sobre-régimen y temperaturas en etapa | Sin una serie homogénea | **P2** |

## 7. Fuentes históricas

Los enlaces conservan las referencias recopiladas durante la investigación anterior; **no se han vuelto a auditar individualmente al compilar este archivo**. Deben verificarse, junto con la página exacta y el año, antes de tratar cada cifra como una medición archivística definitiva.

| ID | Fuente | Uso principal |
|---|---|---|
| **[S1]** | [FIA, Mini Cooper S 1275, homologación n.º 1300](https://historicdb.fia.com/sites/default/files/car_attachment/1601034601/homologation_form_number_1300_group_t.pdf) | Bloque, compresión, masas y culata |
| **[S2]** | Documentación de preparaciones Lotus/Ford Twin Cam y conversiones de Lotus Cortina Mk1 | 1.558/1.598, potencia y Weber; buscar archivo original de conversión |
| **[S3]** | [Saab-Scania, *Directions for Competition Modification*, junio de 1972](https://abcdocz.com/doc/109923/directions-for-competition-modification-of-the) | Levas, carburadores, compresión, lubricación y rendimiento del V4 |
| **[S4]** | [Volvo, catálogo R-Sport](https://volvo1800pictures.com/amazon/documents/R_sport_eng/Volvo_R-Sport.pdf) | Levas R/S, culatas y distinción B18/B20; posterior a varios rallies Amazon |
| **[S5]** | Documentación histórica Abarth sobre el 1000 Berlina Corsa 1966 | Compresión 13:1, 85 hp y régimen 7.600 rpm; recuperar documento original exacto |
| **[S6]** | Homologaciones FIA Opel Kadett B 1900 / CIH y documentación de preparaciones 19S/19HL | Componentes, variantes Group 2 y cárter seco; identificar ficha concreta |
| **[S7]** | [*Alfacionada*, noviembre de 1966 — Autodelta Tipo 532](https://www.arosc.org/newsletters/1966/Nov1966.pdf) | **Curva de potencia y diagrama de distribución original** |
| **[S8]** | Alfa Romeo Heritage y documentación Autodelta Giulia GTA | Doble encendido y evolución posterior hasta ~170 hp |
| **[S9]** | [FIA, Lancia Fulvia 1.6 HF, homologación n.º 3006](https://historicdb.fia.com/sites/default/files/car_attachment/1649336401/homologation_form_number_3006_group_3.pdf) | Geometría, masas, válvulas y disposición V4 |
| **[S10]** | [Ford AVO Owners Club, Escort RS2000](https://www.avoclub.com/avo-marques/rs2000/escort-rs2000/) | AOO 674L Boreham 1974, 165 bhp y 152 lb·ft |
| **[S11]** | [FIA, Alpine A110, homologación n.º 624](https://historicdb.fia.com/sites/default/files/car_attachment/1759327201/homologation_form_number_624_group_4.pdf); documentación Renault/Alpine-Mignotet | Motor base 1.565 vs. competición 1.596, masas y especificación Group 4 |
| **[S12]** | [FIA, Lancia Stratos HF, homologación n.º 640](https://historicdb.fia.com/sites/default/files/car_attachment/1662976801/homologation_form_number_640_group_4.pdf) | Geometría Dino V6, masas, válvulas y lubricación |
| **[S13]** | *Motor Sport* (septiembre de 1975) y documentación histórica WRC/Lancia Stratos | 11,5:1, régimen de prueba y evoluciones de potencia |

---

### Conclusión técnica

Los **once motores deben mantenerse como once configuraciones físicas específicas**. El estado documental es más sólido para **Saab, Alfa y Escort**; en **Volvo**, y en algunas evoluciones de **Mini, Opel, Fulvia y Abarth**, siguen faltando especificaciones cerradas que permitan representar una sola unidad y temporada sin recurrir a estimaciones. Para la simulación, la prioridad no es agregar más decimales a potencia máxima, sino reconstruir **curvas completas, inercias, distribución y alimentación** sin mezclar versiones históricas.
