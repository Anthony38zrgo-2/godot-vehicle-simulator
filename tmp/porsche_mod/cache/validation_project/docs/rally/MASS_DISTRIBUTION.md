# Reajuste de masas del Ford Escort

## Base y limites

El inventario conserva todas las masas individuales: 990 kg sin conjuntos de rueda, 80 kg en cuatro ruedas y 25 kg de combustible inicial, total 1095 kg. Se han reubicado sus centros en el sistema activo del coche: -Z hacia delante, +Y arriba y suelo nominal y=0. El manifiesto visual especifica expresamente que el origen del cuerpo esta en el plano nominal de contacto. Las posiciones son estimaciones de empaquetado mecanico, no medidas de un Escort real ni un reparto homologado de competicion.

La ficha original Ford confirma el motor Pinto delantero longitudinal y la arquitectura del Escort RS2000, pero no proporciona centros de masa de componentes ni altura del centro de gravedad. Su masa de carretera no se sustituye por la masa del coche de rally, que incluye tripulacion y equipamiento. Fuente primaria: https://www.motomobil.com/fileadmin/_2020/prospekte/Prospekte_Escort/Ford_Escort_MK1_Originalprospekt_RS_2000_englisch.pdf

## Posiciones adoptadas

| Componente | kg | x (m) | y (m) | z (m) |
|---|---:|---:|---:|---:|
| Carroceria y jaula | 420 | 0 | 0.55 | -0.10 |
| Motor y auxiliares | 155 | 0 | 0.48 | -0.95 |
| Caja y diferencial, agregado | 75 | 0 | 0.30 | 0.10 |
| Suspension delantera y direccion | 35 | 0 | 0.28 | -1.205 |
| Eje trasero y ballestas | 55 | 0 | 0.28 | 1.205 |
| Frenos e hidraulica, agregado | 25 | 0 | 0.28 | 0 |
| Radiador y fluidos | 20 | 0 | 0.50 | -1.50 |
| Electricidad y bateria | 15 | -0.20 | 0.40 | 0.95 |
| Deposito vacio | 10 | 0 | 0.45 | 1.45 |
| Piloto y copiloto, agregado | 150 | 0 | 0.65 | 0.20 |
| Proteccion y herramientas, agregado | 22 | 0 | 0.25 | 1.00 |
| Combustible inicial | 25 | 0 | 0.45 | 1.40 |

Los cuatro conjuntos de rueda (20 kg cada uno) y los cuatro portamanguetas (2 kg cada uno, incluidos en el presupuesto de 990 kg) se situan respecto a sus ruedas: x=+/-0.64, y=0.28, z=+/-1.205 m. Antes el cargador reconocia los portamanguetas como adjuntos no soportados y los dejaba en el origen. Ahora su posicion relativa se suma al centro de rueda. Siguen formando parte de la aproximacion de un solo cuerpo rigido, sin introducir una dinamica independiente de masas no suspendidas.

Se declara incertidumbre espacial de 0.15 m para los componentes reubicados. Los agregados caja/diferencial y proteccion/herramientas siguen siendo aproximaciones: mover su centro no reconstruye sus inercias internas. Se conservan sus tensores propios estimados; el modelo recalcula la contribucion por posicion con el teorema de ejes paralelos.

## Calculo

`M = sum(m_i)`, `CG = sum(m_i * position_i) / M`.

`front_fraction = (z_rear_axle - CG.z) / wheelbase`, con z_rear_axle=1.205 m y wheelbase=2.410 m. El resultado no se impone como un multiplicador de fuerzas: procede del inventario que consume VehicleMassModel y se entrega a la suspension y al cuerpo Jolt.

| Combustible | Masa total | Altura CG nominal | CG longitudinal | Delante | Detras |
|---|---:|---:|---:|---:|---:|
| 0 kg | 1070 kg | 0.4750 m | -0.0999 m | 54.15% | 45.85% |
| 25 kg | 1095 kg | 0.4744 m | -0.0657 m | 52.72% | 47.28% |
| 45 kg | 1115 kg | 0.4740 m | -0.0394 m | 51.63% | 48.37% |

Con 25 kg de combustible, las cargas estaticas equivalentes por eje son 577.33 kg delante y 517.67 kg detras. El desplazamiento lateral de CG es -2.74 mm, debido a la bateria. En el balance cuasiestatico plano, sin aerodinamica y a 0.8 g de desaceleracion, la fraccion de carga delantera seria aproximadamente 68.47%: `front_static + (a/g)*h/L`. Es una prediccion analitica, no un resultado medido en ejecucion. La altura instantanea sobre el suelo tambien depende de cabeceo, suspension y colisiones del chasis.

El reparto de frenada no se modifica en este reajuste. Los campos antiguos de chassis.front_weight_distribution y center_of_gravity_height_offset pertenecen al perfil heredado y no son consumidos por VehicleMassModel; los valores efectivos se calculan del inventario anterior. Los hashes locales de chassis.json y fuel.json se actualizan conservando los originales en reference_profile_json_sha256.

No se han creado ni ejecutado tests. Las cifras proceden de sumas de masas, momentos estaticos y equilibrio longitudinal.
