# Plan de Acción Ágil: Corrección de Físicas en Jolt (Rally Maniac)

**Objetivo:** Eliminar de raíz las explosiones de suspensión, el cálculo falso de $F_z$ en solapamiento y el "clavado" de ruedas en taludes manteniendo **Jolt Physics** a $120\text{ Hz}$, mediante cambios directos en GDScript listos para probar en el juego.

---

## Paso 0. Diagnóstico rápido en consola (10 min)

Antes de modificar las fuerzas, imprime en consola estos dos datos para confirmar los valores exactos en tu build de Godot 4.7:

1. **Firma de solapamiento en Jolt:** En el inicio de un tick con la rueda enterrada a propósito ($0.05\text{ m}$), imprime qué devuelven `space.cast_motion(q)`, `space.intersect_shape(q)` y `space.get_rest_info(q)`. Esto te confirma al instante si `cast_motion` reporta `[0.0, 0.0]` o `[1.0, 1.0]` cuando nace solapado y si `get_rest_info` entrega la normal limpia del triángulo.
2. **Chequeo de estabilidad numérica en `_ready()`:** Imprime por esquina:
   * $\omega \cdot \Delta t = \sqrt{k_{\text{stop\_max}} / m_u} \cdot \Delta t$
   * $c \cdot \Delta t / m_{\text{eff}} = c_{\text{damper}} \cdot \Delta t / m_{\text{eff}}$
   * Si cualquiera supera $2.0$, el integrador explícito está explotando por sí solo a $120\text{ Hz}$.

---

## Paso 1. Estabilizar el integrador y el amortiguador (Cura de la explosión)

**Archivos a modificar:** `unsprung_suspension_rig.gd`, `suspension_model.gd`, `tire_radial_model.gd`

En lugar de parchar con límites artificiales de velocidad o fuerza, estabiliza las ecuaciones para que los bujes ligeros ($12\text{--}20\text{ kg}$) no diverjan a $\Delta t = 1/120\text{ s}$.

### 1.1. Integración semi-implícita (Radial, Amortiguador y Bumpstop)
Activa la formulación implícita (`radial_implicit_enabled`) y aplícala también al tope progresivo (*bumpstop*), usando la masa reducida del par chasis-buje $m_{\text{eff}} = \frac{1}{1/m_u + 1/m_{s\_\text{corner}}}$:

```gdscript
# Masa reducida en la esquina
var m_eff: float = 1.0 / ((1.0 / hub_mass_kg) + (1.0 / corner_sprung_mass_kg))

# 1. Amortiguador semi-implícito (elimina oscilación por retardo de 1 tick)
var c_eff: float = c_damper / (1.0 + (c_damper * dt) / m_eff)
var f_damp: float = -c_eff * v_rel_axis

# 2. Bumpstop y muelle radial semi-implícitos
var k_eff: float = k_stop / (1.0 + (k_stop * dt * dt) / m_eff)
var f_stop: float = -k_eff * penetration_into_stop
```

### 1.2. Velocidad relativa limpia para el amortiguador
No leas `hub_state.linear_velocity` cruda después de que el solver actúe (viene contaminada por el impulso duro del límite de la junta en Jolt). Calcúlala proyectada únicamente sobre el eje de la suspensión respecto al punto de anclaje del chasis:

```gdscript
var v_mount: Vector3 = chassis_v_cm + chassis_omega.cross(mount_world - chassis_cm)
var v_rel_axis: float = (hub_v - v_mount).dot(susp_axis)
```

### 1.3. Simetría estricta Acción / Reacción
Calcula la fuerza interna total de la esquina **una sola vez** (incluyendo cualquier tope de seguridad) y aplica exactamente $+F$ al chasis y $-F$ al buje. Nunca recortes la fuerza del buje sin recortar exactamente igual la reacción sobre el chasis.

### 1.4. Ampliar ventana de la `Generic6DOFJoint3D`
Una vez que el *bumpstop* sea semi-implícito (punto 1.1), amplía los límites lineales Y de la junta de $\pm 0.03\text{ m}$ a $\pm 0.10\text{ m}$ (`[-droop - 0.10, bump + 0.10]`). Así tu modelo en GDScript frena la rueda progresivamente sin chocar contra el tope rígido del solver de Jolt.

---

## Paso 2. Corregir lectura del `ShapeCast3D` en solapamiento (Cura del $F_z$ falso)

**Archivos a modificar:** `vehicle_simulation.gd`, `rally_escort_vehicle.gd`

### 2.1. Fijar margen explícito en consultas
Asigna un margen pequeño y fijo en las consultas cilíndricas (ej. `margin = 0.005` o `0.0`) para eliminar el sesgo por defecto de $0.04\text{ m}$ que infla artificialmente la deflexión radial $\delta$.

### 2.2. Separar solapamiento inicial del barrido normal
No uses `safe_fraction` para adivinar si el cilindro nació enterrado:
1. Comprueba primero en el origen con `intersect_shape`.
2. Si hay solapamiento en el origen, haz el barrido desde una posición elevada (`origin + up * lift`) o recupera el punto y la normal directamente con `space.get_rest_info(q)`.
3. Garantiza que `position`, `normal`, `collider` y `distance_m` provengan **del mismo impacto candidato** (nunca combines la fracción global del primer impacto con la normal de otro obstáculo).

### 2.3. Conservar impactos de barrera para el sistema de daño
Cuando excluyas temporalmente una pared o guardarraíl del `ShapeCast3D` para buscar el asfalto debajo, guarda ese impacto lateral en un array local durante ese mismo paso y pásalo a `_collect_wheel_cast_impacts()`, en vez de releer el `ShapeCast3D` ya modificado al final del frame.

---

## Paso 3. Evitar que la rueda se "clave" en taludes y muros

**Archivos a modificar:** `vehicle_simulation.gd`, `tire_model.gd`

### 3.1. Discriminación geométrica Flanco (Sidewall) vs. Banda (Tread)
No subas el umbral de normal a $0.55$ de forma global porque perderás apoyo en peraltes y cunetas de rally ($>45^\circ$). Usa el eje de giro de la rueda (`wheel_spin_axis`) para distinguir si el impacto es de suelo o de costado contra un muro/talud:

```gdscript
var axial: float = absf(contact_normal.dot(wheel_spin_axis))

# Si la normal es paralela al eje de la rueda, es un golpe de flanco (va a daño, NO genera Fz)
var is_sidewall: bool = axial > 0.70

# Si la normal es perpendicular al eje y apunta hacia arriba, es suelo válido para Fz
var is_tread: bool = axial < 0.45 and contact_normal.dot(chassis_up) > 0.25
```

### 3.2. Guardia de penetración profunda con recuperación
Si el punto de impacto aparece por encima del centro del buje pero es banda de rodadura (`is_tread`), no devuelvas "sin apoyo" (`NO_SUPPORT`) porque el coche atravesará el suelo. Trátalo como penetración profunda (tope de llanta / recuperación). Solo descártalo si es flanco (`is_sidewall`).

### 3.3. Sensibilidad de carga en lugar de tope duro de agarre
En vez de cortar el agarre con un tope fijo de $2.4\times$ el peso estático (lo que te deja sin dirección al aterrizar de un salto), aplica decaimiento del coeficiente de fricción con la carga si aún no está activo:

```gdscript
# k_load típico entre 0.10 y 0.20
var mu_eff: float = mu0 * pow(maxf(fz, 1.0) / fz_nominal, -k_load)
```
Aplica un límite duro a $F_z$ **únicamente** cuando el contacto venga marcado como recuperación de solapamiento de baja confianza.

---

## Paso 4. Arreglar el Spawn, Reset y Teleport (Cura del salto en Tick 0)

**Archivos a modificar:** `unsprung_suspension_rig.gd`, `rally_escort_vehicle.gd`

### 4.1. Pre-asentar en el equilibrio estático
En `reset_at()` y `_reset_to_transform()`, no coloques los bujes en $q_i = 0$ (neutro) ni en $\delta_i = 0$ ($F_z = 0$):
* Calcula la compresión de equilibrio estático $q_{\text{eq}}$ donde el muelle soporta el peso suspendido de esa esquina ($F_s(q_{\text{eq}}) = W_{\text{sprung\_corner}}$) y el neumático tiene su deflexión estática sobre la distancia medida al suelo.
* Si el coche nace en el aire sin suelo debajo, inicializa en extensión máxima ($q_i = -\text{droop}$).

### 4.2. Limpiar memoria de filtros y sincronizar nodos
Al ejecutar el reset o rescate:
```gdscript
for i in range(4):
	var hub_target_xform: Transform3D = chassis_target * neutral_mount_local[i].translated_local(Vector3(0.0, q_eq[i], 0.0))
	
	# 1. Actualizar servidor físico Y nodo visual
	PhysicsServer3D.body_set_state(hub_rids[i], PhysicsServer3D.BODY_STATE_TRANSFORM, hub_target_xform)
	PhysicsServer3D.body_set_state(hub_rids[i], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(hub_rids[i], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	hub_nodes[i].global_transform = hub_target_xform
	
	# 2. Igualar historial para que la derivada del amortiguador sea 0.0 en el primer tick
	compression_physical_m[i] = q_eq[i]
	prev_compression_m[i] = q_eq[i]
	damper_velocity_filtered_mps[i] = 0.0
```
* Llama a `reset_physics_interpolation()` en el chasis y en los 4 bujes tras teletransportar.
* **No reconstruyas las juntas** después de pre-asentar; el origen local neutro de la junta debe seguir siendo $q = 0$.

### 4.3. Desactivar Sleep en chasis y bujes
Fija `can_sleep = false` tanto en el `RigidBody3D` del chasis como en los 4 `UnsprungHub_i` para evitar que un buje con `collision_mask = 0` quede dormido al arrancar o tras detenerse.

---

## Orden de ejecución recomendado (Impacto rápido)

1. **Iteración 1 (15–30 min):** Implementa el **Paso 1** (amortiguador y *bumpstop* semi-implícitos + velocidad relativa limpia + acción/reacción simétrica). Entra al juego y prueba baches fuertes y saltos.
2. **Iteración 2 (30–45 min):** Implementa el **Paso 2** y **Paso 3** (separar solapamiento inicial en `ShapeCast3D` + filtro axial `wheel_spin_axis`). Prueba el coche con la altura de carrocería al mínimo y choca en diagonal contra taludes y guardarraíles.
3. **Iteración 3 (15–20 min):** Implementa el **Paso 4** (`reset_at()` en equilibrio + `can_sleep = false`). Prueba el spawn inicial y el botón de rescate en pendiente y asfalto.