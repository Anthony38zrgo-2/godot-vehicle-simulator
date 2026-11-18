# Migración de la suspensión de rally a 1 DOF por rueda

Cada buje conserva su masa y se mueve sobre un eje fijo en el espacio local del chasis. Jolt integra la carrocería y sus colisiones. El rig guarda cuatro recorridos y cuatro velocidades relativas. El neumático conserva su giro y su elasticidad radial. Se mantienen los perfiles, las masas, el alcance de los casts y la configuración de frecuencia existentes. La validación de conducción queda a cargo del usuario.

## 1. Definir el estado y la inercia acoplada

En el rig, usar el recorrido físico como coordenada canónica q, en metros, y u = dq/dt, en m/s. Un q positivo comprime la suspensión. El tramo nominal [−droop, bump] se usa para evaluar la suspensión y los extremos efectivos [−droop − 0,10 m, bump + 0,10 m] se usan para los topes mecánicos. La deformación radial usa q físico. Las masas no suspendidas de los perfiles intervienen como masas puntuales. Jolt conserva la masa e inercia suspendidas del inventario.

Sea C el centro de masa del chasis, R su orientación, e = R·Y el eje de suspensión mundial, aᵢ la posición neutra local referida al centro de masa, y rᵢ = R·aᵢ + e·qᵢ el brazo hasta el buje. La derivada de Hᵢ = C + rᵢ incluye la rotación del chasis y del eje. Bᵢ transforma la velocidad generalizada w = [V, ω, u₀, …, u₃] en velocidad de buje. Su derivada aporta aceleración centrípeta y de Coriolis.

~~~text
H[i] = C + r[i]
B[i] * w = V + cross(omega, r[i]) + e * u[i]
b[i] = cross(omega, cross(omega, r[i])) + 2 * cross(omega, e * u[i])

M = block_diag(m_s * eye(3), I_mundo, zeros(4,4))
para cada rueda i:
    M += m[i] * transpose(B[i]) * B[i]
factor = cholesky(M)
~~~

La matriz de 10 × 10 resulta de sumar la energía cinética del chasis y de las cuatro masas puntuales. Es definida positiva con masas e inercia válidas. Resolver sistemas con una factorización por subpaso y reutilizarla para las respuestas direccionales. La inercia lateral y longitudinal llega al chasis mediante los términos acoplados de M. La formulación en coordenadas reducidas elimina las restricciones transversales de la junta por construcción. [Ecuaciones de movimiento y jacobianos, MuJoCo](https://mujoco.readthedocs.io/en/3.3.3/computation/#general-framework)

## 2. Calcular suspensión y contacto

**Suspensión.** Reusar las leyes calibradas de muelle, amortiguador digresivo, barra, tope progresivo y resistencia al droop. Calcular los recorridos de las cuatro ruedas antes de evaluar la barra. Para el tratamiento semiimplícito usar la masa efectiva del modo definido por sᵢ, el selector de uᵢ. Se obtiene como 1 / (sᵢᵀ M⁻¹ sᵢ). Pasarla directamente a la ley actual en lugar de deducirla de una masa de esquina independiente. El convenio de la ley existente toma F_s positiva hacia arriba sobre el chasis. Como el par de fuerzas de suspensión es interno y axial, su contribución generalizada es −sᵢ F_s y su potencia es −F_s uᵢ. Así, la parte del amortiguador que tiene el signo de uᵢ absorbe energía. [Modelo de suspensión del simulador](../../scripts/physics/suspension_model.gd)

~~~text
al inicio del tick, por rueda:
    contacto = cast_existente(i)
    si hay apoyo radial:
        H0 = centro_del_buje(i)
        n = normal_unitaria_del_apoyo
        delta0 = (radio - contacto.distance - q[i]) * dot(n, e)
        guardar contacto, H0, n y delta0 con su signo

cada subpaso, para las cuatro ruedas:
    q_nom[i] = clamp(q[i], -droop[i], bump[i])
    s[i] = selector_de_u(i)
    m_rel[i] = 1 / dot(s[i], solve(factor, s[i]))
    Fs = suspension_existente(q_nom, u, m_rel, h, apoyo_previo)
    Q_susp = -suma(s[i] * Fs[i])
~~~

**Radial.** Usar la distancia axial del cast para anclar la deformación inicial y después aproximar el apoyo con su plano tangente durante el tick. Conservar la selección de apoyos del cast. El ángulo entra con la proyección real de la normal sobre el eje. Una vez anclada la geometría, la distancia y la velocidad se expresan en la misma dirección normal. Para suelo móvil, evaluar la velocidad del punto de apoyo como traslación más rotación alrededor del centro de masa del colisionador y extrapolar el punto durante el tick con esa velocidad.

La elasticidad radial empuja en el sentido de la normal n. Aplicar la normal por el centro del buje en el modelo radial. El jacobiano normal G = nᵀB convierte w en velocidad normal. Su traspuesta convierte un impulso de contacto en impulso generalizado. La respuesta Kₙ = G M⁻¹ Gᵀ tiene unidades de 1/kg. Reutilizar la bisección de solve_radial_impulse() y la ley preparada de TireRadialModel, con variables expresadas en la normal.

~~~text
si no hay apoyo radial:
    J_rad, J_llanta, Fz, deflexion, disipacion = 0
si hay apoyo radial:
    delta = delta0 - dot(n, (H - H0) - desplazamiento_del_suelo)
    G = transpose(n) * B[i]
    respuesta = solve(factor, transpose(G))
    K_n = G * respuesta
    v_libre = G * w_libre - dot(n, velocidad_del_suelo)

    para un impulso candidato J >= 0:
        v_fin(J) = v_libre + K_n * J
        delta_fin(J) = max(0, delta - h * v_fin(J))
        F_rad(J) = ley_radial_preparada(delta_fin(J), -v_fin(J))

    J_rad = 0 si delta_fin(0) == 0
    si delta_fin(0) > 0:
        J_max_rad = (delta / h - v_libre) / K_n
        J_rad = biseccion(J - h * max(0, F_rad(J)), 0, J_max_rad)

    deflexion = delta_fin(J_rad)
    disipacion = disipacion_radial(deflexion, -v_fin(J_rad))
~~~

Preparar los coeficientes radiales una vez por rueda y tick. La cota superior del impulso corresponde a la apertura de la cubierta, donde la ley sin penetración devuelve cero. Evaluar las cuatro raíces a partir de la misma w_libre y sumar sus impulsos antes de actualizar w. Esta aproximación trata implícitamente la respuesta normal de cada neumático y separa su interacción con los otros contactos dentro del subpaso. [Rig](../../scripts/physics/unsprung_suspension_rig.gd) · [Inercia en el espacio de restricciones, MuJoCo](https://mujoco.readthedocs.io/en/3.3.3/computation/#constraint-solver)

**Llanta.** Adaptar compute_unilateral_rim_constraint() para trabajar en metros y m/s sobre la normal. Conservar su holgura de goma, recuperación acotada y límite de impulso. Evaluar el exceso sobre la deflexión máxima con la velocidad resultante de todos los impulsos radiales. La respuesta acoplada M⁻¹ distribuye el impulso al chasis y al buje, por lo que se retira el reparto heurístico ligado a la cercanía al bump. Calcular las correcciones de las cuatro ruedas sobre la misma velocidad posterior al radial.

~~~text
w_rad = w_libre + solve(factor, suma(transpose(G[i]) * J_rad[i]))
para cada apoyo i:
    hueco = deflexion_maxima_de_llanta - delta
    si hueco >= 0:
        v_objetivo = -hueco / h
    si hueco < 0:
        v_objetivo = min(2 m/s, -0,18 * hueco / h)
    v_normal = G[i] * w_rad - dot(n, velocidad_del_suelo)
    F_max = 8 * max(m_s, 100 kg) * norma(g)
    J_llanta[i] = clamp((v_objetivo - v_normal) / K_n, 0, F_max * h)
    Fz[i] = (J_rad[i] + J_llanta[i]) / h
w_normal = w_rad + solve(factor, suma(transpose(G[i]) * J_llanta[i]))
~~~

Fz es la carga que consume el modelo tangencial. La disipación térmica radial se deriva de la ley de la carcasa evaluada en el estado de su raíz implícita. El impulso de llanta entra una vez en el balance normal y carece de un término térmico propio en esta migración.

## 3. Resolver los topes duros y avanzar el tick

Los topes de suspensión limitan la coordenada interna q. Para que Euler semiimplícito mantenga q + h·u⁺ dentro del recorrido, acotar la velocidad de cada rueda a [(q_min − q)/h, (q_max − q)/h]. Al alcanzar un extremo, la cota correspondiente queda en cero durante el siguiente subpaso. La rueda puede volver inmediatamente hacia el interior. Este esquema aproxima el instante de impacto con la resolución temporal del subpaso y evita introducir un coeficiente de rebote.

~~~text
w = velocidad después de la normal y del impulso tangencial
lambda[4] = 0
para cada rueda i:
    d[i] = solve(factor, s[i])
    K[i] = dot(s[i], d[i])
    lo[i] = (q_min[i] - q[i]) / h
    hi[i] = (q_max[i] - q[i]) / h

repetir barridos hasta convergencia numérica, con máximo acotado:
    para cada rueda i:
        u_sin_su_impulso = dot(s[i], w) - K[i] * lambda[i]
        u_limited = clamp(u_sin_su_impulso, lo[i], hi[i])
        lambda_nuevo = (u_limited - u_sin_su_impulso) / K[i]
        w += d[i] * (lambda_nuevo - lambda[i])
        lambda[i] = lambda_nuevo

q += h * w.u
redondear q al intervalo únicamente para corregir error numérico
C_pred += h * w.V
R_pred = exp_rotacion(h * w.omega) * R_pred
~~~

Cada corrección cambia la velocidad compartida del chasis y puede modificar la respuesta de las demás ruedas. Proyectar impulsos acumulados permite que un tope libere su reacción si otro deja a esa rueda dentro del recorrido. El signo negativo de λ frena compresión y el positivo frena extensión. [Restricciones unilaterales e impulsos, David Baraff](https://www.cs.cmu.edu/afs/cs/user/baraff/www/sigcourse/notesd2.pdf)

**Orden de integración y transferencia a Jolt.** El bucle exterior vive en vehicle_simulation.gd. Usar el conteo de subpasos que ya calcula el vehículo para que el neumático consuma la carga y deformación del mismo intervalo. La lógica de suspensión vive en el rig. La normal se resuelve primero y el neumático tangencial aporta su impulso al mismo intervalo antes de resolver los topes. Conservar los puntos y pares tangenciales existentes. F_parche incluye la fuerza tangencial y la vibración ya calculada por el neumático. Su impulso se aplica al chasis con el brazo del parche, como en el vehículo actual. Jolt es el único propietario de la pose real de la carrocería.

~~~text
leer C, R, V, omega, masa, tensor y gravedad efectivos de Jolt
reconciliar u con la velocidad observada, según se describe abajo
leer contactos y preparar coeficientes del tick
h = dt / cantidad_de_subpasos_existente
J_envio = 0
L_envio = 0

para cada subpaso:
    construir M, B y b desde una sola pose predicha de las cuatro ruedas
    calcular Q_susp
    Q = [m_s * g, -cross(omega, I_mundo * omega), 0, 0, 0, 0]
    Q += Q_susp + suma(transpose(B[i]) * m[i] * (g - b[i]))
    Q += fuerzas_y_pares_de_carroceria_trasladados_al_predictor
    w_libre = w + h * solve(factor, Q)

    resolver radial y llanta a partir de w_libre
    evaluar neumático, freno y transmisión una vez para este intervalo
    J_tangencial_del_intervalo = h * suma_por_rueda(
        [F_parche, cross(P_parche - C_pred, F_parche) + par_autoalineante, 0, 0, 0, 0]
    )
    w_candidato = w_normal + solve(factor, J_tangencial_del_intervalo)
    resolver topes con w_candidato
    avanzar q y pose predicha una vez con las velocidades resultantes

    J_envio += m_s * (V_nueva - V_anterior) - h * m_s * g
    L_envio += I_mundo_nueva * omega_nueva - I_mundo_anterior * omega_anterior
    actualizar apoyo_previo[i] = Fz[i] > 0 para el siguiente subpaso
    acumular Fz, deflexión y disipación con su intervalo h

aplicar a Jolt fuerza central J_envio / dt y par L_envio / dt una vez
guardar V y omega predichas para el siguiente tick
publicar q, u y salidas del neumático
~~~

El término −ω × Iω convierte la ecuación de momento angular en aceleración angular en coordenadas mundo. Al enviar a Jolt el **cambio de momento angular** se transfiere el par físico equivalente alrededor del centro de masa. La gravedad del chasis se resta porque la integra Jolt. La contribución de las ruedas ya está en el acoplamiento de M. Mover la aplicación de la fuerza tangencial, la vibración y el par autoalineante de las ruedas al acumulador. Para cada fuerza de carrocería incluida en Q, trasladar también su aplicación al acumulador. Las fuerzas de otros propietarios y las colisiones que solo resuelve Jolt quedan fuera de Q.

Al siguiente tick, calcular ΔV = V_Jolt − V_pred y Δω = ω_Jolt − ω_pred. Antes de evaluar la suspensión, corregir uᵢ restando e_actual · (ΔV + Δω × rᵢ_actual). Así se conserva la componente axial de la velocidad absoluta del buje ante una corrección instantánea del chasis. La respuesta de una colisión de carrocería sigue siendo particionada, porque Jolt resuelve ese impacto con su masa suspendida. El rig reanuda el acoplamiento desde el estado observado. Invalidar la predicción al reiniciar o teletransportar el coche. [Integración semiimplícita, MuJoCo](https://mujoco.readthedocs.io/en/3.3.3/computation/#numerical-integration) · [Estado físico directo de Godot](https://docs.godotengine.org/en/stable/classes/class_physicsdirectbodystate3d.html)

## 4. Migrar los consumidores y retirar los nodos

~~~text
create():
    asociar chasis, centros neutros, radios y masas no suspendidas
    inicializar los escalares y llamar al reset de estado

reset_at(pose):
    para cada rueda:
        q = equilibrio_del_perfil si la sonda tiene suelo alcanzable
        q = -droop si la rueda queda en el aire
        u = 0
    limpiar carga, deformación, disipación e historial transitorio
    invalidar predicción y sincronizar la primera muestra visual y sonora

muestra_de_rueda(i, estado_del_chasis):
    devolver recorrido y reconstruir H y vH desde q y u

salida_del_intervalo(i):
    entregar Fz, deformación y disipación al neumático y al modelo térmico

fin_del_tick():
    publicar la carga media temporal y el recorrido físico
    reconstruir las muestras visuales y sonoras con la pose real del chasis
~~~

- **Rig.** Reemplazar la lectura de estados físicos de buje, y consolidar solve() y solve_coupled() en la misma secuencia. Retirar RigidBody3D, Generic6DOFJoint3D, formas auxiliares y sincronización de congelación de los bujes. [Rig](../../scripts/physics/unsprung_suspension_rig.gd)
- **Vehículo.** Retirar las exclusiones de RIDs de buje de los casts y cambiar la condición visual basada en el número de nodos a la disponibilidad de la muestra escalar. Reusar reset_at() durante arranque, rescate y teletransporte. [Simulación](../../scripts/physics/vehicle_simulation.gd) · [Vehículo de rally](../../scripts/rally/rally_escort_vehicle.gd)
- **Audio.** Sustituir las lecturas de transform y linear_velocity de los nodos por H y vH de una misma muestra. Reiniciar el historial de velocidad al cambiar de pose. [Audio del vehículo](../../scripts/rally/rally_vehicle_audio.gd)
