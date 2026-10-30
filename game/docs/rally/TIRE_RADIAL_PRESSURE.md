# Neumático radial, aro y presión en vivo

## Geometría y calibración

Se conserva radio exterior 0,280 m y ancho 0,200 m. Se declara aro nominal
13 pulgadas: radio del asiento del talón 0,1651 m; flanco geométrico
0,280-0,1651=0,1149 m. El radio del aro representa el asiento del talón,
no el borde exterior exacto de la pestaña ni la cavidad interior del aire.

Ford documenta ruedas de 13 pulgadas en su ficha RS2000:
https://www.motomobil.com/fileadmin/_2020/prospekte/Prospekte_Escort/Ford_Escort_MK2_Originalprospekt_Rallye_Sport_1979_english_1979.pdf
Esto fundamenta el diámetro nominal elegido, no demuestra que el activo
3D de rally tenga esa misma llanta. No se cambia ni deforma la malla visual.

La ley es una aproximación parametrizada, no una carcasa de elementos finitos:

    h = R_outer - R_bead
    geometry_scale = width/reference_width * reference_sidewall/h
    k = geometry_scale * (k_carcass * thermal_scale + pressure_slope * P_gauge)
    F_elastic = k*deflection + F_rim_stop
    c = 2*zeta*sqrt(k_tangent * m_unsprung) * contact_fade
    F_normal = max(F_elastic+c*compression_speed, 0)

k_carcass=30000 N/m, pressure_slope=666,667 N/m/kPa, zeta=0,12.
Los coeficientes son estimaciones de calibración, no ensayos del neumático.
La corrección térmica afecta la carcasa; el gas actúa a través de su presión
actual. El factor de geometría es una aproximación dimensional local.

Antes del tope y a 60 C de carcasa:

| Presión manométrica | Rigidez | Compresión a 3000 N |
| --- | --- | --- |
| 225 kPa | 180000 N/m | 16,7 mm |
| 180 kPa | 150000 N/m | 20,0 mm |
| 120 kPa | 110000 N/m | 27,3 mm |
| 100 kPa | 96667 N/m | 31,0 mm |
| 80 kPa | 83333 N/m | 36,0 mm |

Se elimina el piso de relación de presión 0,45 y el amortiguamiento fijo
1100 Ns/m. A 80 kPa, c es aproximadamente 411 Ns/m delante (35,25 kg)
y 485 Ns/m detrás (49 kg), con contacto plenamente desarrollado.
La rampa smoothstep de 5 mm evita un salto de amortiguamiento al tocar suelo.

El tope progresivo empieza al consumir el 75% del flanco (86,175 mm).
Su fuerza crece cuadráticamente durante el cuarto restante y luego linealmente,
con rigidez tangente adicional limitada a 300000 N/m. No hay recorte de
la deformación física que elimine energía; el tope aporta fuerza y rigidez.
No representa una colisión rígida exacta con la pestaña del aro.

La clase compartida TireRadialModel calcula la ley para hubs y estimación
del brush, evitando dos leyes de rigidez radial contradictorias. Los arrays
radiales de coupled_world.json y compliance_sensitivity heredados ya no
controlan la fuerza radial. ShapeCast continúa usando la envolvente rígida
exterior; no hay envolvimiento local de piedras ni deformación visual.

## Prueba manual sin reiniciar

Ejecutar scripts/run_rally.ps1. Fuera del garaje:

- Ctrl+RePág: aumenta 5 kPa la presión fría de referencia de las cuatro ruedas.
- Ctrl+AvPág: reduce 5 kPa la presión fría de referencia de las cuatro ruedas.
- Se mantienen límites del reglaje: 80-220 kPa en frío.

El HUD muestra la presión real, corregida por temperatura del gas: un paso
frío de 5 kPa puede producir un incremento caliente ligeramente mayor.
Los atajos no reinician combustible, velocidades, temperaturas ni suspensión.
Es una herramienta de calibración en vivo, no un sistema físico de inflado
a bordo. En el garaje se conserva el ajuste independiente por rueda.

El garaje pausa el mundo; al regresar, la fuerza radial usa la nueva presión
en el siguiente callback físico. En pista los atajos actualizan la inflación
y el modelo la lee en cada callback a 120 Hz. El estado publicado por rueda
incluye presión, deformación y un diccionario radial con rigidez, amortiguamiento,
radio de aro, altura de flanco y fuerza de tope.

Compilación y arranque verificados; no se añadieron tests ni se validó la
absorción de baches conduciendo. Los coeficientes requieren esa calibración.
