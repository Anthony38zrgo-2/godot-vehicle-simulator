# Investigación: elasticidad torsional amortiguada

Estado: primer tramo equivalente implementado; semiejes separados pendientes. Autoblip del Ford desactivado.
Consulta de fuentes: 2026-10-29. No se añadieron tests.

## Fuentes verificadas

1. Project Chrono, ChShaftsTorsionSpring.cpp:
https://github.com/projectchrono/chrono/blob/main/src/chrono/physics/ChShaftsTorsionSpring.cpp
Implementa T=-(k*relative_angle+c*relative_speed).
Su base ChShaftsTorque aplica pares opuestos a ambos grados de libertad:
https://github.com/projectchrono/chrono/blob/main/src/chrono/physics/ChShaftsTorque.cpp
El ejemplo demo_CH_powertrain.cpp combina inercias 1D, engranajes y embragues:
https://github.com/projectchrono/chrono/blob/main/src/demos/core/demo_CH_powertrain.cpp
Tomar esta arquitectura y ley constitutiva como referencia; no requiere
instalar Chrono ni reemplazar Jolt.

2. Aalto-Arotor/openTorsion, shaft_element.py:
https://github.com/Aalto-Arotor/openTorsion/blob/main/opentorsion/elements/shaft_element.py
Calcula rigidez desde módulo de cortadura y geometría; ensambla matrices
simétricas de rigidez y amortiguamiento. assembly.py transforma matrices
con engranajes y proporciona análisis modal:
https://github.com/Aalto-Arotor/openTorsion/blob/main/opentorsion/assembly.py
Útil para cálculos fuera del runtime y selección de parámetros.

3. oxiphysics-vehicle 0.1.2, DriveshaftCompliance:
https://docs.rs/oxiphysics-vehicle/0.1.2/src/oxiphysics_vehicle/drivetrain/types.rs.html
Expone stiffness, damping, deflection y deflection_rate y usa Euler para
integrar deflection. Su valor typical_steel (8000,80) es una referencia
numérica genérica, no un dato de nuestro Ford. No trasladar directamente
velocidades motor/rueda sin referirlas al mismo eje; tampoco copiar resets
arbitrarios de torsión, ya que eliminan energía elástica.

## Propuesta para el modelo actual

Conservar motor, embrague y fases de cambio. Separar la salida de caja
del portadiferencial mediante un acoplamiento torsional. Después añadir
semiejes elásticos izquierdo/derecho con velocidades propias a la salida
del diferencial y ruedas independientes. El LSD conecta esas salidas,
no debe forzar directamente velocidades de ruedas separadas por semiejes.

La restricción rígida actual primario/ruedas puentea cualquier muelle
colocado en paralelo: debe sustituirse por la nueva cadena de grados de
libertad. Cada inercia se contabiliza una sola vez. Mantener engranajes
ideales como restricciones entre ejes locales; el tramo flexible está
entre nodos del mismo lado de una reducción o usa el Jacobiano correcto.

Para dos extremos referidos al mismo eje:
    v = wa-wb; theta_dot = v
    Ta = -k*theta-c*v; Tb = -Ta
    E = 0.5*k*theta^2; P_diss = c*v^2

La torsión es estado persistente y no se borra al cambiar marcha o abrir
el embrague. Una desconexión cambia la topología, no destruye la energía.

## Base física de parámetros

Para eje circular:
    polar_area = pi*(Do^4-Di^4)/32
    k = G*polar_area/L

Ejemplo geométrico, NO medición del Ford: acero G=80 GPa, eje macizo
Do=30 mm, L=0.6 m => k aproximadamente 10603 Nm/rad. A 600 Nm de par
estático corresponde theta aproximadamente 0.0566 rad = 3.24 grados.
Un acoplamiento de embrague con muelles o juntas modifica la rigidez
equivalente; para elementos en serie 1/k_eq=sum(1/k_i).

Con inercias locales Ia e Ib, Ieq=Ia*Ib/(Ia+Ib):
    f = sqrt(k/Ieq)/(2*pi)
    c = 2*zeta*sqrt(k*Ieq)

La fórmula de dos inercias solo caracteriza ese modo aislado. Una cadena
con diferencial, embrague y neumáticos requiere modos del sistema completo.
La rigidez es una propiedad mecánica: no recalcularla cada marcha para
conservar artificialmente la misma frecuencia. La frecuencia sí cambia
con la inercia reflejada y el estado de bloqueo del embrague.

## Integración propuesta

Incluir los acoplamientos dentro del mismo solver de impulsos que embrague,
LSD y frenos. Usar integración implícita de los muelles; no Euler explícito
con rigideces elevadas. Para un acoplamiento lineal aislado, h constante,
v_free y W=1/Ia+1/Ib, Euler implícito da:

    J = -h*(k*theta + (c+h*k)*v_free)/(1+h*(c+h*k)*W)
    v_new = v_free + W*J
    theta_new = theta + h*v_new

Para el solver iterativo deben incluirse los impulsos acumulados y sus
interacciones; no aplicar esa actualización completa en cada iteración.
Registrar torsión, par elástico, par amortiguador, energía, disipación y
residuo del solver. Mantener subpasos de hasta 0.002 s y Jolt a 120 Hz;
la estabilidad de un elemento aislado no prueba precisión del sistema.

Primera integración: un tramo equivalente amortiguado caja/diferencial.
Segunda integración: semiejes separados para capturar transitorios del LSD.
Añadir holgura/backlash después: puede producir golpes y complicar la
calibración; no es la primera herramienta para suavizar la transmisión.
