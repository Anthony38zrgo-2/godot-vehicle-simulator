# Muelles y transmisiÃ³n acoplada

## Arquitectura del Ford

El perfil declara `macpherson_coil` delante y `live_axle_leaf` detrÃ¡s.
La ficha original de Ford describe muelles helicoidales/MacPherson delanteros
y eje rÃ­gido con ballestas semielÃ­pticas detrÃ¡s:
https://www.motomobil.com/fileadmin/_2020/prospekte/Prospekte_Escort/Ford_Escort_MK2_Originalprospekt_Rallye_Sport_1979_english_1979.pdf

Con desplazamiento de compresiÃ³n q, precarga F0 y rigidez efectiva k:

- Delante: F_el = max(F0 + k(q-q0), 0). El muelle sin asiento no tira.
- DetrÃ¡s: F_el = F0 + k(q-q0). La ballesta fijada conserva respuesta bilateral.
- Amortiguador: F_d = c(v)v, independiente del asiento del muelle.
- Topes y estabilizadora se suman despuÃ©s, sin limitar la fuerza total a cero.

Las frecuencias, rigideces y amortiguamientos anteriores se conservan.
Con las masas de referencia actuales, el asiento delantero se pierde cerca
de q=-0,089 m. Esto no implica anular la fuerza del amortiguador en extensiÃ³n.
La ley trasera es una aproximaciÃ³n lineal de la ballesta; no reconstruye
la cinemÃ¡tica de gemelas ni convierte los dos hubs en un eje rÃ­gido articulado.

## Grados de libertad rotacionales

Se mantienen seis velocidades: motor, primario de caja y cuatro ruedas.
La matriz de inercia es diagonal: Ie, Is e Iw[i]; cada inercia aparece una vez.
El par motor integra Ãºnicamente Ie y los pares de neumÃ¡tico Ãºnicamente Iw[i].

Para relaciÃ³n firmada g y pesos a=[s/2,s/2,(1-s)/2,(1-s)/2], la caja impone:

    ws - g sum(a[i] ww[i]) = 0
    inverse_effective_inertia = 1/Is + gÂ² sum(a[i]Â²/Iw[i])

Un impulso de engranaje J cambia ws en J/Is y cada ww[i] en
-g a[i] J/Iw[i]. Esta transferencia proviene del Jacobiano de la restricciÃ³n;
no se reparte una inercia de motor artificial entre ruedas. En punto muerto
no existe esta restricciÃ³n, aunque el embrague puede unir motor y primario.

El embrague resuelve la diferencia we-ws con:

    Jc_free = (we-ws)/(1/Ie + 1/Is)
    |Jc_accumulated| <= engagement * clutch_capacity * h

Aplica -Jc al motor y +Jc al primario. Si la capacidad permite sincronizar,
el embrague bloquea; si no, desliza. Con embrague abierto Jc=0: el motor no
aporta inercia a las ruedas. La inercia del primario permanece conectada a
las ruedas cuando hay una marcha engranada, como corresponde fÃ­sicamente.

Los frenos imponen impulsos acotados |Jb[i]|<=Tb[i] h buscando ww[i]=0.
El LSD trasero aplica impulsos opuestos, limitados por precarga y rampas.
Las restricciones de caja, embrague, LSD y frenos se iteran conjuntamente
48 veces por subpaso; es un solver numÃ©rico, no una soluciÃ³n analÃ­tica exacta.
El trabajo del freno se obtiene acumulando -dJb*(w_before+w_after)/2.
La disipaciÃ³n del embrague se publica separada de los frenos.

La inercia del primario es configurable mediante
`gearbox_input_inertia_kg_m2`; el valor por defecto de 0,02 kg mÂ² procede del
parÃ¡metro heredado, no de una mediciÃ³n del Ford. `gear_inertia` sigue siendo
el retardo de cambio heredado, expresado en segundos, y no una inercia fÃ­sica.

## IntegraciÃ³n y lÃ­mites

Los cuatro neumÃ¡ticos y toda la transmisiÃ³n comparten subpasos de hasta
0,002 s: normalmente cinco de 1/600 s por tick de 1/120 s. Las fuerzas sobre
Jolt se promedian por tick; cargas normales y velocidades de traslaciÃ³n de
los hubs permanecen constantes dentro de ese tick. La suspensiÃ³n Jolt no
pasa a ejecutarse a 600 Hz.

Se conserva la asistencia de ralentÃ­ y desembrague automÃ¡tico a bajas RPM.
Los engranajes y su sincronizaciÃ³n son ideales; no se modelan dientes,
holguras o flexibilidad torsional de los Ã¡rboles. La validaciÃ³n realizada
para este cambio es importaciÃ³n y compilaciÃ³n de GDScript, sin tests ni
validaciÃ³n de conducciÃ³n.

## Secuencia de cambio y accionamiento del embrague

La petición guarda `pending_gear` y conserva la relación anterior durante
`opening`. La capacidad del embrague baja como máximo a razón de 1/0,04 s.
Solo cuando llega a cero se desacopla la marcha anterior (`current_gear=0`).
Durante `synchronizing` la relación candidata no es una restricción rígida:
el impulso acumulado del sincronizador queda limitado a 25 Nm * h, referido
al primario. Su reacción llega al portadiferencial mediante el Jacobiano de
la relación candidata, conservando el acoplamiento de inercias. No se asigna
artificialmente una nueva velocidad al primario.

Se engrana cuando ha transcurrido el tiempo mínimo heredado de cambio
(`shift_time + gear_inertia`, 0,125 s en este perfil) y el error de velocidad
primario/relación candidata es menor de 0,1 rad/s (aprox. 0,955 rpm).
Después se inicia `closing`: la capacidad del embrague sube como máximo
1/0,18 s hasta la demanda del conductor y de la asistencia de ralentí.
Los tiempos siguen vigentes aunque el cambio tarde más en sincronizar.
El embrague continúa resolviendo deslizamiento y bloqueo por fricción; no
se modifica directamente la velocidad del motor para hacer rev matching.

Los nuevos parámetros del perfil son `clutch_release_seconds`,
`clutch_reengage_seconds`, `synchronizer_capacity_nm` y
`synchronizer_tolerance_rad_s`. Son estimaciones de calibración editables,
no valores medidos del Ford. El estado publicado incluye fase de cambio,
marcha pendiente y acoplamiento efectivo del embrague. No se han añadido
elasticidad torsional ni cambios al modelo del LSD en esta corrección.

## Autoblip de reducción

`powertrain.downshift_rev_matching_enabled` activa el autoblip por coche;
por defecto es false si falta la clave y en el Ford está en false (desactivado por petición del usuario).
Solo se arma al pasar de una marcha positiva a otra positiva más corta.
No actúa en subidas de marcha, entrada desde neutral o marcha atrás.

La velocidad objetivo se recalcula cada subpaso a partir de las ruedas:

    carrier = s*(wFL+wFR)/2 + (1-s)*(wRL+wRR)/2
    rpm_target = ratio_pending * final_drive * carrier * 60/(2*pi)

Se limita entre ralentí y `downshift_maximum_target_revolutions_per_minute_fraction`
por RPM máximas (0,92 en el Ford). Este límite pertenece a la asistencia;
no constituye un bloqueo mecánico de reducciones que provocarían sobrerégimen.

Una vez casi abierto el embrague, el controlador solicita par según
`T_required = Ie * (w_target-w_engine) / max(response_seconds, h)`.
Invierte la curva par/acelerador, compensando el arrastre del motor, y limita
la demanda automática a `downshift_blip_torque_fraction` (0,8).
La demanda del conductor tiene prioridad si es mayor. No se asignan RPM:
el par pasa por la curva, limitación de subida de par, estado térmico e
integración normal de la inercia del motor.

`downshift_blip_response_seconds` (0,04 s) regula la aproximación al objetivo
 y `downshift_blip_tolerance_rpm` (25 rpm) corta el golpe de gas cuando el
error es pequeño o negativo. El estado se limpia al terminar/resetear el cambio.
La publicación incluye `autoblip_active`, `autoblip_target_rpm` y
`autoblip_throttle`. El objetivo usa giro de ruedas: con patinamiento no es
una estimación independiente de velocidad del suelo.

## Tramo equivalente elástico implementado

El Ford activa `powertrain.driveline_compliance.enabled`. El enlace rígido
primario/ruedas se sustituye por primario -> engranajes -> salida con inercia
propia -> muelle/amortiguador -> portadiferencial equivalente -> ruedas.
La salida y todos los parámetros elásticos están referidos al lado de las
ruedas, después de la reducción final. No son parámetros del árbol físico
antes del grupo cónico; deben transformarse si se usa otra referencia.

Parámetros iniciales, estimaciones de calibración:

- `output_inertia_kg_m2`: 0,2 kg m².
- `stiffness_nm_per_rad`: 8000 Nm/rad.
- `damping_nms_per_rad`: 120 Nm s/rad.

A 600 Nm estáticos, la torsión es 600/8000=0,075 rad (4,30 grados), con
22,5 J de energía elástica. El amortiguador disipa 120*(delta_omega)^2 W.
No hay un límite artificial de par ni se borra la torsión durante cambios,
neutral o apertura del embrague. Solo el reset completo reinicia el estado.

La integración es backward Euler dentro del solver conjunto de embrague,
engranajes, LSD y frenos. Para W=1/I_output+sum(a_i^2/I_wheel_i), el residuo
usado por el acoplamiento es:

    R = J + h*k*theta_old + h*(c+h*k)*v_current
    delta_J = -R / (1+h*(c+h*k)*W)

Se aplica delta_J a la salida y -a_i*delta_J a cada rueda. J es acumulado
para ese subpaso, no se reintegra theta en cada iteración. Tras resolver:

    theta_new = theta_old + h*(w_output-sum(a_i*w_i))

El LSD calcula su capacidad de rampas desde el par real -J/h que llega al
portadiferencial, también con el embrague abierto si queda energía elástica.
El sincronizador ajusta el primario a la salida de caja, no directamente a
las ruedas, y permanece limitado en par. `enabled=false` conserva el camino
rígido anterior para comparar; requiere recargar el perfil.

El estado publicado `driveline` contiene velocidad de salida, torsión, par,
energía y disipación del amortiguador. Esta disipación no se añade a los
frenos ni a los neumáticos. Backward Euler también introduce disipación
numérica, distinta de la disipación física publicada.

La simulación comparte subpasos de hasta 2 ms; Jolt sigue a 120 Hz.
La primera versión representa un único tramo equivalente; los semiejes
izquierdo/derecho siguen rígidos respecto del diferencial. No hay backlash.
La fórmula del muelle sigue la referencia de Chrono y la actualización
implícita se deriva para el solver actual; no se incorpora una dependencia
externa. El autoblip permanece desactivado.
