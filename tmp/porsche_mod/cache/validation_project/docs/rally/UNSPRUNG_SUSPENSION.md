# Suspension con masas no suspendidas

## Modelo activo

El coche consta ahora de un cuerpo Jolt para la masa suspendida y cuatro RigidBody3D para las masas equivalentes de los conjuntos de rueda. Cada hub tiene posicion y velocidad propias integradas por Jolt, unidas al chasis mediante un Generic6DOFJoint3D que permite recorrido vertical local y restringe traslaciones laterales/longitudinales y rotaciones. Sus limites son los recorridos bump/droop del perfil. Los muelles, amortiguadores y barras calculan fuerzas internas iguales y opuestas entre chasis y hubs, incluso sin contacto con el suelo. Los topes progresivos de compresion se mantienen; los limites duros se resuelven con los joints.

El ShapeCast3D cilindrico sigue localizando el centro de rueda compatible con una cubierta sin deformar. Se compara esa coordenada con el centro real del hub para obtener la deformacion radial positiva. La fuerza normal es unilateral: Fn=max(kt*delta + ct*delta_dot,0), solo con delta>0. La velocidad normal incluye el movimiento del suelo si el collider es RigidBody3D. La fuerza normal y las fuerzas tangenciales del brush se aplican a los hubs; la fuerza de suspension se aplica al chasis, sin volver a aplicar Fn directamente al chasis. Los joints transmiten las reacciones transversales y de momento. El giro de rueda alrededor de su eje sigue integrado por el modelo angular existente, no por una rueda libre rotatoria en Jolt.

En el equivalente vertical: m_s*z_s''=Fs-m_s*g y m_u*z_u''=Fn-Fs-m_u*g. Jolt integra las masas y gravedad una sola vez. La rigidez radial y amortiguamiento base proceden de coupled_world.suspension: 180000 N/m y 1100 N*s/m por rueda. Presion y temperatura de carcasa modifican kt mediante los factores del neumatico. La deformacion radial calculada alimenta el contacto/relajacion del brush, sustituyendo la estimacion cuasiestatica. La disipacion radial del amortiguador se incorpora al calor de carcasa.

## Inventario de masa

| Parte | Masa |
|---|---:|
| Chasis suspendido con combustible inicial | 926.5 kg |
| Hub delantero izquierdo/derecho | 35.25 kg cada uno |
| Hub trasero izquierdo/derecho | 49.0 kg cada uno |
| Vehiculo completo con 25 kg de combustible | 1095.0 kg |

Cada hub recibe 20 kg del conjunto rueda y 2 kg del portamangueta. De los agregados del inventario se asignan ademas 8.75 kg de suspension delantera por lado, 22 kg de eje/ballestas traseras por lado y las masas declaradas de rotor (4.5 kg delante, 5 kg detras). Las asignaciones de los agregados son estimaciones de ingenieria: 50% del agregado de suspension/direccion delantera y 80% del de eje/ballestas traseras. El resto permanece suspendido. Las masas retiradas dejan de contribuir a masa, centro de masas e inercia del chasis. Los tensores propios de los agregados se escalan por su fraccion restante; los hubs usan una inercia concentrada aproximada, no una reconstruccion CAD.

El consumo modifica solo la masa suspendida. La separacion permite que ambas masas participen en la inercia del movimiento a traves de las restricciones, sin sumar ruedas dos veces en el chasis.

## Reglaje, visuales y ciclo de vida

La masa usada por k=m*(2*pi*f)^2 y c=2*zeta*sqrt(k*m) es ahora la suspendida por esquina: aproximadamente 253.167 kg delante y 210.083 kg detras. Se recalcularon f y zeta para conservar los componentes iniciales: k=28000/24000 N/m, c_bump=1800/3000 N*s/m y c_rebound=2400/5500 N*s/m. Las frecuencias de referencia pasan a 1.67377/1.70110 Hz. No son las dos frecuencias propias del sistema acoplado completo. El orden de magnitud del modo de rueda con kt base es 11.37 Hz delante y 9.65 Hz detras, antes de incluir muelle, amortiguamiento y variacion de kt.

Los visuales siguen la posicion vertical del hub. Al colocar el coche en la salida y al reiniciarlo se trasladan y restablecen los cuatro hubs junto al chasis para no estirar artificialmente los joints. La congelacion y pausa de sesion se propagan. Los hubs no colisionan directamente con el suelo (mascaras cero); sus formas sirven para una inercia finita, mientras el contacto compliant procede del barrido. Los snapshots publican masa no suspendida, deformacion radial, fuerza de suspension y carga normal.

## Limites

Hay cuatro grados de libertad verticales reales integrados por Jolt, pero el eje rigido trasero del Escort se aproxima mediante dos hubs independientes y barra. No se han reconstruido su cinematica solidaria, ballestas ni brazos McPherson tridimensionales. No se modela contacto de flancos o llanta con obstaculos. El escenario de shape-cast overlap inicial sigue limitado por el barrido configurado. La masa repartida y los coeficientes radiales son valores declarados/estimados, no mediciones de este coche.

## Comprobacion de carga

Scripts cargados con Godot 4.7.1 y arranques breves de Rusia y campo de pruebas completados. RALLY_UNSPRUNG_READY informa cuatro cuerpos y las masas anteriores; RALLY_CONTACT_FREQUENCY informa dt=0.00833333376795053 s (120 Hz). En el asentamiento, las muestras de RALLY_UNSPRUNG_STATE mostraron cuatro cargas positivas y deformaciones radiales de aproximadamente 14 a 18 mm. No es aceptacion de conduccion, saltos o estabilidad en todos los reglajes. El primer arranque detecto y permitio corregir un error de colocacion inicial de los hubs. Al cierre de algunas ejecuciones persiste la advertencia de 26 instancias ObjectDB pendientes.
