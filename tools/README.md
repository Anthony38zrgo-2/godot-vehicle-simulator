# 3D Geometry & Modeling Tools

Este directorio (`tools/`) contiene las herramientas de auditoría, reparación geométrica y automatización con Blender para el simulador y sus modelos 3D.

---

## 1. MCP for Blender (`tools/mcp-for-blender`)

Permite a los asistentes de IA interactuar directamente con una instancia activa de Blender para ejecutar Python, manipular objetos, consultar la escena y capturar imágenes desde distintos ángulos.

- **Repositorio local:** `tools/mcp-for-blender`
- **Add-on instalado en:** `C:\Users\bill\AppData\Roaming\Blender Foundation\Blender\5.2\scripts\addons\blender_mcp.py`
- **Configuración MCP:** Agregado automáticamente a Antigravity (`~/.gemini/config/mcp_config.json`) y OpenCode (`~/.config/opencode/opencode.json`).

### Cómo usarlo con Blender:
1. Abre Blender 5.2.
2. Si es la primera vez, comprueba en **Edit → Preferences → Add-ons** que **Interface: MCP for Blender** esté activado.
3. En la vista 3D, presiona `N` para abrir la barra lateral y ve a la pestaña **MCP for Blender** (o el servidor iniciará en segundo plano).
4. El agente podrá invocar herramientas como:
   - `get_scene_info`: Estructura de la escena y objetos.
   - `execute_blender_code`: Ejecutar scripts Python en tiempo real.
   - `look`: Renders y capturas de cámara para verificar mallas visualmente.

---

## 2. PyMeshLab (`tools/PyMeshLab` & `mesh_audit.py`)

Herramienta especializada en auditoría e inspección matemática de geometría 3D (detección de problemas topológicos y de normales).

- **Repositorio local:** `tools/PyMeshLab`
- **Librería Python:** `pymeshlab` (instalada en el entorno Python global).
- **Herramienta CLI:** `tools/mesh_audit.py`

### Diagnósticos que realiza:
- Caras y vértices no-manifold (*non-manifold edges & vertices*).
- Caras autointersectadas (*self-intersections*).
- Caras plegadas (*folded faces*) y triángulos excesivamente alargados (*sliver triangles*).
- Bordes abiertos y orificios no deseados (*open boundary edges*).
- Caras duplicadas y vértices aislados / no referenciados.

### Uso:
```bash
# Auditoría rápida en consola
python tools/mesh_audit.py ruta/a/modelo.obj

# Salida en formato JSON para procesamiento por scripts o agentes
python tools/mesh_audit.py ruta/a/modelo.obj --json

# Limpiar automáticamente caras duplicadas y vértices huérfanos
python tools/mesh_audit.py ruta/a/modelo.obj --clean-output ruta/a/limpio.obj
```

---

## 3. MeshLib (`tools/MeshLib` & `mesh_repair.py`)

Librería de alta fidelidad geométrica (desarrollada por MeshInspector) orientada a la reparación profunda de mallas, cierre de orificios (*hole filling*) y reconstrucción de superficies watertight.

- **Repositorio local:** `tools/MeshLib`
- **Librería Python:** `meshlib` y `meshlib-core` (instaladas en el entorno Python global).
- **Herramienta CLI:** `tools/mesh_repair.py`

### Capacidades principales:
- **Cierre de orificios (`fillHoles`):** Detecta bordes perimetrales abiertos y genera parches continuos.
- **Autointersecciones conservadoras (`--fix-intersections`):** Resuelve autointersecciones a nivel de componentes conservando la geometría original.
- **Reconstrucción de superficie (`--reconstruct-surface`):** Voxeliza la malla y genera una superficie hermética (*watertight*) libre de anomalías topológicas.
- **Simplificación / Decimación (`--decimate-error`):** Reduce la carga poligonal controlando el error métrico máximo.

### Uso:
```bash
# Reparación básica (cierre de orificios)
python tools/mesh_repair.py ruta/a/modelo.obj -o ruta/a/modelo_reparado.obj

# Reparación con resolución de autointersecciones locales
python tools/mesh_repair.py entrada.obj -o salida.obj --fix-intersections

# Reconstrucción de superficie hermética (watertight)
python tools/mesh_repair.py entrada.obj -o salida.obj --reconstruct-surface --voxel-res 200

# Reparación con simplificación geométrica
python tools/mesh_repair.py entrada.obj -o salida.obj --decimate-error 0.005
```
