# Raura Stage 2 · Tooling de cunetas, peralte y desgaste

## Alcance

Usar el piloto OSQP de 698 m como control. Conservar el eje XY, la rasante longitudinal y los tiempos de referencia. El feedback al volante indica que los cortes ya tienen una forma aceptable, que la cuneta y el relleno requieren transiciones más suaves y que los baches de 2–4 cm apenas se perciben. El dibujo adjunto sirve como esquema funcional, sin medidas de campo. Las amplitudes siguientes son parámetros de prueba.

## 1. Secciones transversales editables

Crear un módulo de secciones anterior al mallado de Blender. Cada PK define ancho, bombeo, pendiente transversal de diseño y perfiles independientes a izquierda y derecha. Usar códigos de borde persistentes para calzada, arcén, labios y fondo de cuneta, pie de relleno y encuentro con la ladera. Tomar como referencia las secciones y el cosido por códigos de AQGIS-Sivil3D. El perfil de corte actual es la referencia visual.

- **Cuneta.** Representarla explícitamente como una sección en U ancha o trapecio redondeado. Usar tramos cúbicos Hermite con tangentes continuas en ambos labios y fondo. Preservar un punto bajo definido. Empezar con 0,12–0,25 m de profundidad y 0,8–1,5 m de ancho solo donde haya espacio. Mantener un arcén entre la calzada y la cuneta. En horquillas estrechas, reducir profundidad o recurrir a una cuneta somera y registrar el PK.
- **Peralte ligero.** Partir de un bombeo suave en rectas y pasar gradualmente a pendiente transversal hacia el interior de la curva. Probar 2–4 % de peralte y transiciones de 20–40 m, con límites de cambio por metro y neutralización gradual en curvas enlazadas. Usar curvatura horizontal suavizada y radio de la curva como entradas. Rotar alrededor del eje de la rasante para que no cambie su cota. El arcén hereda la tangente de la calzada en el borde y después transita a su propia inclinación. Verificar que el peralte no drene hacia un borde sin salida.
- **Relleno.** Redondear la coronación y el pie del terraplén por separado. Usar 0,5–1,5 m de transición cuando la huella lo permita. Mantener una sola superficie entre ramas próximas, con bordes obligatorios y sin invadir calzadas vecinas. Un tramo sin espacio suficiente debe aparecer en el informe como incidencia, no resolverse con un cambio abrupto de altura.
- **Mallado.** Resolver primero perfiles continuos y después discretizarlos de forma adaptativa. Usar los mismos puntos y aristas de unión para visual y colisión. Mantener sin ruido los labios y bordes de contacto. En Blender, mostrar cortes comparativos por PK y marcar cambios de tipo y tramos truncados.

## 2. Perfiles de baches en JSON

Separar el catálogo de desgaste, la asignación por PK y el inventario realizado. El generador lee los perfiles, resuelve los baches una vez y guarda su posición, tamaño, profundidad y semilla. Un editor puede después mover, borrar o fijar un bache sin cambiar el resto. Definir el PK por distancia horizontal del eje fijo y el lateral en metros con signo, positivo a la derecha en el sentido de carrera.

Ejemplo inicial de catálogo. Los rangos altos se ensayan primero en una zona controlada:

~~~json
{
  "schema_version": 1,
  "seed": 20261111,
  "profiles": {
    "compactado": {
      "density_per_100m": 1,
      "depth_m": [0.02, 0.04],
      "length_m": [0.7, 1.3],
      "width_m": [0.35, 0.65],
      "cluster_probability": 0.1
    },
    "desgastado": {
      "density_per_100m": 4,
      "depth_m": [0.04, 0.08],
      "length_m": [0.8, 1.7],
      "width_m": [0.4, 0.8],
      "cluster_probability": 0.35
    },
    "muy_desgastado": {
      "density_per_100m": 8,
      "depth_m": [0.06, 0.12],
      "length_m": [1.0, 2.2],
      "width_m": [0.45, 0.95],
      "cluster_probability": 0.55
    }
  },
  "default_profile": "desgastado",
  "zones": [],
  "manual_features": [],
  "exclusion_zones": []
}
~~~

- **Distribución.** Las zonas por PK pueden mezclar perfiles o declarar un perfil dominante. Variar probabilidades según frenadas, rodada, drenaje y desgaste anotado al volante. Tratar esos factores como ponderaciones editables. Usar densidad esperada por 100 m y probabilidades de agrupación, con semilla estable por zona y una distancia mínima entre baches. Evitar sesgos al colocar centros que hagan cruzar el bache al arcén. Registrar exclusiones, baches manuales y el motivo de cada zona.
- **Forma.** Variar planta elíptica, orientación y asimetría. Usar labios redondeados, entradas largas y depresiones compactas. Separar rodadas largas de baches puntuales y limitar la depresión combinada cuando se solapan. Usar parches de desgaste en la textura para acompañar la geometría.
- **Resolución física.** El paso de 40 cm del piloto es la resolución general. Refinar localmente para que cada bache tenga varias muestras en largo y ancho, incluidas las rampas y el fondo. Usar una malla de colisión común con la visual para estas deformaciones. Validar las huellas con el ShapeCast de rueda del Escort: un rayo puede detectar una depresión que el volumen de la rueda atraviesa sin hundirse de la misma forma.

## 3. Entrega y validación

1. **Sección transversal primero.** Implementar los controles por PK y exportar un piloto de cuneta, relleno y peralte, con el mismo desgaste que el control. Comparar las secciones en Blender y cruzar el arcén en Godot. Comprobar tangentes, profundidad, paso de ruedas, ausencia de huecos y ausencia de solapes en las horquillas.
2. **Banco de baches.** Preparar una recta corta con baches conocidos de 4, 6, 8 y 12 cm, variando también la longitud. Conducir a velocidades repetibles con el mismo Escort y reglaje. Medir velocidad real, aceleración vertical, compresión y velocidad de suspensión, y tiempo sin contacto. Elegir el rango que se note sin convertir cada bache en un salto o un golpe de chasis.
3. **Piloto combinado.** Activar los perfiles por PK y comparar tres variantes: OSQP base, laterales y peralte, y laterales más desgaste. Guardar el JSON resuelto, una tabla de secciones críticas, métricas de colisión y la telemetría por PK. Verificar bordes y costuras con rayos y después conducir ambas líneas de rueda. Ajustar primero frecuencia, ancho y forma de los baches y luego profundidad según la respuesta del coche.
4. **Escalar a la bajada completa.** Aplicar el catálogo únicamente cuando el piloto tenga una transición conducible al arcén y diferencias perceptibles entre zonas compactadas y muy desgastadas. Mantener el Stage 2 actual como comparación hasta completar una pasada de punta a punta.

[Base OSQP](PILOTO_OSQP.md) · [Generador de relieve actual](relieve_piloto.py) · [Plan GIS](MEJORA_GIS_STAGE2.md)
