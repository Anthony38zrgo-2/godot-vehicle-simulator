# Insumos para co-registro de Raura

La referencia fija es el GLO-30 local, con alturas EGM2008. El AW3D30 se convirtió de EGM96 a EGM2008 aplicando H08 = H96 + N96 − N08 con las dos grillas NGA del CDN de PROJ. La conversión conserva la cuadrícula horizontal de 30 m de GLO-30. El ajuste mediano fue −1,393 m y el intervalo espacial fue de −1,698 a −1,103 m. El AW3D30 original se conserva aparte.

Los GeoTIFF de máscara usan 1 para incluir y 0 para excluir. La máscara candidata retiene 15.528 píxeles clasificados como no vegetados por Sentinel-2 SCL, con margen de dos píxeles. Excluye vecindarios con NoData, cotas de 4.700 m o más, pendientes fuera de 5–40° y el entorno de 60 m de la red OSM. El corte altitudinal y SCL de una sola fecha son filtros conservadores. No comprueban estabilidad entre las épocas de ambos DSM ni sustituyen un inventario glaciar.

- mascara_ajuste.tif contiene 10.521 píxeles. Leer como booleano para inlier_mask de xDEM.
- mascara_validacion.tif contiene 3.184 píxeles en bloques reservados de 600 m, separados del ajuste por al menos 90 m.
- mascara_estable_candidata.tif conserva la selección previa a la separación espacial.
- preparacion_coreg.json registra fuentes, hashes y parámetros. Las grillas PROJ se pueden volver a descargar desde sus URL registradas.

Para regenerar desde la raíz del repositorio:

    .\tools\xdem\.venv\Scripts\python.exe .\tools\rally\stage_gis\raura_quichas_gis\preparar_coreg.py

Al ajustar xDEM, declarar ambos rásteres con vcrs="EGM08", usar solo la máscara de ajuste y medir mediana y NMAD antes y después en la máscara de validación. Reportar la cobertura efectiva después del desplazamiento. El ajuste Nuth–Kääb ya se ejecutó. Los resultados están abajo.

## Validación de Nuth–Kääb

Se ajustó AW3D30 contra GLO-30 en los 10.521 píxeles de ajuste y se evaluaron los mismos 3.184 píxeles reservados antes y después. El residuo es AW3D30 menos GLO-30. La traslación estimada fue +6,67 m Este, −0,10 m Norte y +0,72 m de altura.

| Variante | Mediana (m) | NMAD (m) | RMSE (m) |
|---|---:|---:|---:|
| Antes | −0,702 | 3,326 | 4,393 |
| Solo corrección vertical con la máscara de ajuste | −0,337 | 3,326 | 4,364 |
| Nuth–Kääb con remuestreo bilineal | −0,276 | 1,427 | 3,831 |

El sesgo absoluto y la dispersión robusta bajaron en validación. El remuestreo bilineal puede explicar parte de la reducción de dispersión. Las cifras miden acuerdo entre los dos DSM sobre la máscara candidata, no exactitud absoluta. El GeoTIFF alineado se conserva como candidato aparte.

Repetir desde la raíz:

    .\tools\xdem\.venv\Scripts\python.exe .\tools\rally\stage_gis\raura_quichas_gis\ejecutar_coreg.py

[Resultados por bloque](resultado_nuth_kaab.json) · [AW3D30 alineado](raura_aw3d30_nuth_kaab.tif)