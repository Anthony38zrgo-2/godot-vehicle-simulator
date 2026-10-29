# Ajuste de filtros de neumáticos y suspensión

## Neumáticos

Cada rueda calcula su longitud base de relajación desde su parche: contact_patch × 1.65 delante y contact_patch × 1.80 detrás. En cada paso aceptado, el parche dinámico responde a la carga normal y a la deflexión estimada de carcasa; la presión y la temperatura de carcasa modifican la rigidez radial estimada, y la presión también ajusta la longitud de relajación y la resistencia a la rodadura según las sensibilidades del perfil. Se mantienen los mínimos de relajación, recuperación y rampa de contacto del perfil.

La referencia Rust obtiene la deflexión radial del solucionador acoplado de masa no suspendida y carcasa. El modelo GDScript actual no tiene ese estado mecánico separado; aproxima la deflexión cuasiestática con carga de rueda, presión y temperatura, usando la rigidez de referencia de Rust (carga estática por 8 mm). La longitud de relajación y el parche sí se actualizan por rueda, pero esta aproximación no reproduce la respuesta transitoria del solucionador radial Rust.

## Suspensión

El perfil activa estos filtros, con el contrato de la referencia Rust:

- Altura del contacto: límite de 15 m/s y constante de 4 ms.
- Velocidad del amortiguador: constante de 1 ms por eje.
- Recorrido relativo de la barra estabilizadora: constante de 1 ms por eje.

El filtro de altura suaviza primero el objetivo y después aplica el límite de velocidad. Los filtros de amortiguador y ARB se mantienen por rueda. Las constantes de 1 ms respetan el máximo de 1 ms que Rust valida para señales que alimentan fuerzas.

## Camber, toe y geometría

El camber del perfil conserva una convención común por eje para el modelo de neumático; la pose visual y la base del contacto lo espejan por lado. El toe axial positivo se convierte en yaw negativo a la izquierda y positivo a la derecha, como en Rust. La comprobación de humo contrasta la simetría lateral de camber y toe, verifica que el camber no cree fuerza lateral neta con cargas iguales y confirma que el toe trasero actual es cero.

El modelo GDScript sigue siendo una suspensión simplificada: aplica las ganancias lineales por recorrido del perfil, pero no resuelve los hardpoints de los brazos de la suspensión para derivar las curvas de camber/toe de la geometría multibrazo.
