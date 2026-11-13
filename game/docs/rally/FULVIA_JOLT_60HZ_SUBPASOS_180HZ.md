# Estabilidad del Fulvia con Jolt a 60 Hz

## Resumen

El Lancia Fulvia diverge con el integrador radial explícito y Jolt a 60 Hz, incluso al arrancar sobre piso plano. El balance de impulsos muestra que el contacto radial inicia el rebote del buje y el amortiguador de suspensión amplifica la oscilación. Un paso radial implícito con limitador del amortiguador estabilizó el aterrizaje, pero el Fulvia trompeó en la curva de ensayo. Se propone integrar suspensión, bujes y neumáticos en tres subpasos de 5.56 ms por tick de Jolt y comparar con seis subpasos de 2.78 ms. Este documento describe el experimento pendiente.

## Modelo y mecanismo de inestabilidad

El chasis y los cuatro bujes son cuerpos de Jolt. Cada buje del Fulvia tiene 19 kg y se mueve respecto al chasis por una guía. ShapeCast3D determina el apoyo geométrico. La fuerza radial positiva indica contacto cargado. El barrido puede detectar el terreno antes de que exista compresión. En el esquema base, el cálculo de la suspensión y la carga normal ocurre cada 16.67 ms. El neumático tangencial se evalúa en seis subpasos con esa carga retenida.

Sea q la compresión de la suspensión, δ la deformación radial positiva al comprimir y cᵣ el coeficiente viscoso radial efectivo. En terreno plano, con eje vertical positivo hacia arriba, δ̇ = v_terreno − v_buje mientras existe contacto. El modelo se puede representar como:

$$
F_z=\max\bigl(0, F_{\mathrm{el}}(\delta)+c_r\dot\delta+F_{\mathrm{tope}}(\delta)\bigr),
\qquad
m_u\dot v_u= F_z-F_s-m_u g+R
$$

F_s es la fuerza de suspensión con el signo aplicado al chasis y R recoge la reacción de la guía sobre el buje. El modelo real incluye rampas, límites de velocidad y rigidez dependiente del estado. Para el muelle y amortiguador de suspensión, las relaciones de referencia son:

$$
k_s=m_{\rm ref}(2\pi f_s)^2,
\qquad c_s=2\zeta\sqrt{k_s m_{\rm ref}},
\qquad F_s\simeq k_s q+c_s\dot q
$$

La última expresión es una linealización. El amortiguador real tiene curvas distintas en compresión y rebote y la suspensión añade estabilizadora y topes. Los valores de fábrica son 1.75/1.85 Hz y ζ = 0.55/0.55, delantero/trasero. Para el modo rápido del buje, una escala aproximada es ωᵤ ≈ √(kᵣ/mᵤ). Con una rigidez nominal ilustrativa de 180 kN/m y 19 kg se obtiene ωᵤ ≈ 97 rad/s, equivalente a unos 15.5 Hz. El producto adimensional ωᵤh vale aproximadamente 1.62 a 60 Hz, 0.54 a 180 Hz y 0.27 a 360 Hz. Estos valores estiman cuánto cambia el estado dentro de un paso. La tangente efectiva, los topes, la amortiguación y las guías alteran el límite real de estabilidad.

Para cada intervalo se compara el impulso de las fuerzas conocidas con el cambio de momento del buje sobre un eje fijo durante la medición:

$$
R_J=m_u(v_{n+1}-v_n)-\sum_k J_k,
\qquad
J_k=\int_{t_n}^{t_{n+1}}F_k(t)\,dt
$$

En el solve 2 de FL, el impulso radial fue +110.7 N·s, el de suspensión +78.8 N·s y el de gravedad −3.1 N·s. El buje pasó de −2.71 a +7.10 m/s. El balance cierra en los ticks 1–5. Desde el tick 6, con grandes recorridos y topes, el residual crece. El residual mide la contribución sin explicar por las fuerzas registradas e incluye posibles efectos de juntas y del solver.

## Hipótesis y experimentos realizados

| Hipótesis | Experimento y resultado | Interpretación |
| --- | --- | --- |
| La calibración de muelles y amortiguadores causa la divergencia | A 60 Hz fallaron los barridos por eje de frecuencia natural ±5/10 % y ζ entre 0.45 y 0.65. El control a 120 Hz se mantuvo estable en arranque. | Los cambios moderados de calibración ensayados no resolvieron el problema. |
| El rebote se origina en la fuerza radial y se amplifica en la suspensión | La primera carga de FL fue 6.64 kN. El limitador mantuvo el primer impulso radial, redujo el rebote inicial y estabilizó reposo. En caída y bache todavía se observaron 142 y 127 kN. | La radial dispara el evento y la suspensión participa en su amplificación. |
| La viscosidad radial o la pose inicial explican el fallo | Suprimir la viscosidad conservó unos 81.8 N·s de impulso elástico y la divergencia persistió. Reiniciar desde la pose asentada a 120 Hz también divergió. | La viscosidad y la pose inicial influyen en el transitorio. En las condiciones probadas, ninguna explica por sí sola la inestabilidad. |
| Resolver el impulso radial con el estado al final del paso estabiliza el buje | El implícito redujo el primer impulso de 110.7 a 20.4 N·s. Solo la combinación con el limitador pasó reposo, caída y bache en las tres repeticiones de la matriz. | El radial implícito controla el primer impacto. La respuesta del amortiguador sigue siendo relevante. |
| El algoritmo cambia la respuesta lateral al descargar una rueda | En DIAG4, el combinado a 60 Hz trompeó 5/5 en curva. El explícito a 120 Hz fue estable 5/5. El implícito a 120 Hz también trompeó. | La asociación con el algoritmo está respaldada. La mediación por Fz promediada y el presupuesto de agarre combinado aún requiere una prueba específica. |

En DIAG4 se igualó la velocidad objetivo de impacto a 2.37 m/s. El candidato a 60 Hz se asentó 3/3 y el balance global cerró con residual de −0.8 %. El impulso integrado reportado difirió cerca de 0.8 % del control a 120 Hz. El pico en ventanas de 16.67 ms fue 30.35 frente a 31.95 kN, una diferencia de aproximadamente 5 %, superior a la dispersión de ±2 % indicada para el control. La frenada y la cresta quedaron dentro de 2 % en las métricas reportadas. En curva, la trasera interior cayó a 0 N alrededor de 2.3 s y la guiñada alcanzó 2.72–2.95 rad/s frente a 0.97 rad/s en el control.

Fuentes del banco. [Entrega inicial](SUSPENSION_RECALIBRATION_60HZ_FULVIA_DELIVERY.md) · [DIAG2](SUSPENSION_RECALIBRATION_60HZ_FULVIA_DIAG2.md) · [DIAG3](SUSPENSION_RECALIBRATION_60HZ_FULVIA_DIAG3.md) · [DIAG4](SUSPENSION_RECALIBRATION_60HZ_FULVIA_DIAG4.md).

## Hipótesis de integración acoplada a 180 Hz

Con Jolt a 60 Hz, tomar Δt = 1/60 s y h = Δt/N. Para N = 3, cada paso debe avanzar el estado mecánico predicho, recalcular recorrido, deformación y carga, y usar esa carga para el agarre y el giro de la rueda. Para N = 6 se usa el mismo método con un intervalo menor. El menor h permite que una fuerza radial elevada actúe durante menos tiempo antes de reevaluar la separación y que el amortiguador vea la velocidad relativa actualizada.

Un paso semiimplícito sirve como candidato inicial para el estado auxiliar. Para cada cuerpo se acumula también el momento de las fuerzas respecto a su centro de masa:

$$
v_{j+1}=v_j+hM^{-1}F_j,
\qquad x_{j+1}=x_j+h v_{j+1},
\qquad J=\sum_j h F_j,
\qquad L=\sum_j h\bigl(r_j\times F_j+\tau_j\bigr)
$$

La predicción angular usa la inercia del chasis y debe actualizar cabeceo y balanceo. Las fuerzas internas de suspensión se aplican con reacción opuesta. Las juntas de Jolt se resuelven a 60 Hz. Entre ticks, la predicción tiene que representar la guía de cada buje mediante coordenadas restringidas o una proyección coherente de pose y velocidad. Esa aproximación se valida comparando la predicción al final del tick con el estado observado de Jolt al siguiente. En piso plano puede reconstruirse la separación con la pose predicha y el plano de apoyo. Para terreno irregular hay que consultar o reconstruir de manera verificable el apoyo a lo largo del recorrido.

Una forma esquemática de expresar el límite de agarre es:

$$
\left(\frac{F_x}{\mu_x F_z}\right)^2+
\left(\frac{F_y}{\mu_y F_z}\right)^2\le 1
\qquad (F_z>0)
$$

El neumático real añade memoria de huella, sensibilidad a carga y caída pospico. Por ello, calcular las fuerzas tangenciales con Fz promediada durante el tick puede producir un impulso lateral diferente al de resolver cada subpaso con su Fz local. Si la rueda se descarga, el momento de guiñada resultante depende también de cuándo y dónde desaparece Fy.

## Pseudocódigo del prototipo

~~~text
en cada tick de Jolt (dt = 1/60):
    h = dt / N                         # N = 3 o 6
    estado = copiar_estado_de_chasis_y_bujes()
    acumular = impulsos_cero_por_cuerpo()

    para j en 0 .. N-1:
        apoyo = evaluar_apoyo(estado.pose, geometria_terreno)
        recorrido, velocidad_relativa = medir_suspension(estado)
        fuerzas_susp = resolver_suspension(recorrido, velocidad_relativa)
        deformacion, velocidad_radial = medir_compresion(estado, apoyo)
        Fz = resolver_radial_unilateral(deformacion, velocidad_radial)
        fuerzas_neumatico, par_rueda = evaluar_huella(estado, apoyo, Fz, h)
        fuerzas = distribuir_fuerzas_y_reacciones(fuerzas_susp, Fz,
                                                   fuerzas_neumatico)
        acumular.impulso += h * fuerzas.lineales
        acumular.momento += h * momentos_sobre_centros_de_masa(fuerzas)
        avanzar_giro_y_transmision(estado, par_rueda, h)
        avanzar_pose_y_velocidad_restringidas(estado, fuerzas, gravedad, h)
        registrar_subpaso(estado, Fz, fuerzas, apoyo)

    entregar_impulsos_o_fuerzas_equivalentes_a_Jolt(acumular, dt)
    registrar_estado_predicho_para_comparar_en_el_siguiente_tick()
~~~

El estado auxiliar se descarta después de predecir. Jolt conserva la autoridad sobre las poses y velocidades reales. La gravedad incluida en la predicción se excluye de la entrega si Jolt ya la integra. Se contabilizan una sola vez las reacciones y el momento de cada fuerza. Los interruptores de radial y amortiguador se fijan por variante y se documentan.

## Protocolo y criterio de decisión

1. Usar el mismo Fulvia, ShapeCast3D, combustible, temperaturas, curva de amortiguación y estado inicial. Comparar 180 y 360 Hz internos con Jolt a 60 Hz. Conservar el explícito a 120 Hz como referencia diagnóstica.
2. Repetir tres aterrizajes con la misma pose y velocidad de contacto objetivo de 2.37 m/s. Repetir cinco curvas por variante a 12 m/s, gas 0.45 y dirección 0.35 durante 6 s. Indexar el mando por tiempo simulado.
3. Registrar CSV por subpaso y tick. Alinear aterrizajes por primer contacto cargado. Medir impulso vertical neto, pico Fz en ventanas comunes, recorrido, rebote, asentamiento y residual de juntas. En curva comparar Fz y Fy de la rueda trasera interior, tiempo descargado, guiñada y deriva. Identificar la primera divergencia temporal.
4. Fijar tolerancias por métrica antes de evaluar resultados, usando repetibilidad y relevancia física. La hipótesis queda respaldada si ambas variantes se asientan, completan la curva sin trompo y se mantienen cerca entre sí y del control. Si solo pasa 360 Hz, revisar el error del estado predicho y la reacción de las guías antes de atribuir la diferencia exclusivamente al paso. Si las dos trompean, rastrear la secuencia Fz → Fy → guiñada y aislar el tratamiento de la carga tangencial.

[Instrucciones operativas](SUSPENSION_RECALIBRATION_60HZ_RUNBOOK.md).
