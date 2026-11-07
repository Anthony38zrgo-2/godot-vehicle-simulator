# Frecuencia natural y amortiguamiento

Actualizacion: la separacion fisica de masas no suspendidas cambia la masa de referencia y los valores de frecuencia a 1.67377/1.70110 Hz, conservando k y c iniciales. El estado activo se describe en [UNSPRUNG_SUSPENSION.md](UNSPRUNG_SUSPENSION.md); la tabla siguiente documenta la conversion anterior del modelo de un solo cuerpo.

La autoridad del reglaje por eje es ahora suspension.front/rear.ride_frequency_hz, damping_ratio y los multiplicadores de compresion/extension. La configuracion inicial y los cambios de garaje usan:

    k = m_ref * (2*pi*f)^2
    c_crit = 2 * sqrt(k*m_ref)
    c_bump = zeta * c_crit * bump_damp_multiplier
    c_rebound = zeta * c_crit * rebound_damp_multiplier

Unidades: m_ref en kg, f en Hz, k en N/m, c en N*s/m; zeta y los multiplicadores son adimensionales. El factor rapido y la velocidad de transicion del amortiguador siguen actuando sobre esos coeficientes. Las barras y los topes dependientes de k se actualizan al cambiar f; sus relaciones se conservan.

m_ref es la carga estatica de referencia por esquina dividida entre g, calculada con el inventario y combustible de configuracion. En el rig actual todas las masas estan agrupadas en el cuerpo Jolt: esta es la masa efectiva de un modelo equivalente de una libertad por esquina, no una medicion independiente de masa suspendida. La parametrizacion no representa las frecuencias propias acopladas de cabeceo/balanceo ni el salto de una rueda con masa independiente.

Los valores de referencia son 288.667 kg por esquina delantera y 258.833 kg por esquina trasera. Se fijan al configurar el vehiculo. El consumo de combustible cambia la masa del cuerpo, pero no reajusta automaticamente k ni c para mantener f: los componentes mecanicos conservan su rigidez y amortiguacion.

| Eje | f (Hz) | zeta base | Multiplicador compresion | Multiplicador extension | k (N/m) | c compresion (N*s/m) | c extension (N*s/m) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Delantero | 1.5674748 | 0.3165665 | 1.0 | 1.3333333 | 28000 | 1800 | 2400 |
| Trasero | 1.5325545 | 0.6018328 | 1.0 | 1.8333333 | 24000 | 3000 | 5500 |

Se derivaron f y zeta de los k y c originales para conservar el reglaje inicial. Los valores dimensionales antiguos del JSON quedan como referencia y fallback para derivar frecuencia si falta; cuando existe ride_frequency_hz, la frecuencia y razon son la autoridad activa. El garaje expone frecuencia por eje entre 0.5 y 3.5 Hz con paso de 0.01 Hz; esa cuantizacion puede producir pequenas diferencias respecto a los valores iniciales completos. Los reglajes guardados anteriores que carecen de frecuencia reciben 1.57/1.53 Hz, pero sus razones antiguas no se reinterpretan automaticamente: conviene guardarlos de nuevo con la semantica fisica actual.

Compilacion/carga Godot 4.7.1 y arranque de Rusia completados. El registro RALLY_SUSPENSION_FREQUENCY confirma los coeficientes anteriores dentro del redondeo numerico; RALLY_CONTACT_FREQUENCY confirma 120 Hz con ShapeCast3D. Log: game/logs/rally/rally_godot_20261029_183116.log. Al cerrar hubo una advertencia de 26 instancias ObjectDB pendientes; no se ha certificado comportamiento en conduccion.
