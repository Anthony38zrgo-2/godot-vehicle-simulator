#!/usr/bin/env python3
"""
Blender 5.2 headless generator for the 20-house PSX Andean Modular Catalog.
Exports:
  - 20 individual .glb files in game/assets/rally/CDI/casas_andinas/glb/
  - catalog_manifest.json with metadata for Godot scene generation
  - A high-res overview render of all 20 houses in a 5x4 grid for visual review.
"""
import os
import sys
import json
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

BASE_DIR = r"d:\rust-godot-vehicle-simulator\game\assets\rally\CDI\casas_andinas"
TEX_DIR = os.path.join(BASE_DIR, "textures")
GLB_DIR = os.path.join(BASE_DIR, "glb")
SCRATCH_DIR = r"C:\Users\bill\.gemini\antigravity\brain\aec6b34e-ede5-418a-8c77-3a4d3d9a5402\scratch"
os.makedirs(GLB_DIR, exist_ok=True)
os.makedirs(SCRATCH_DIR, exist_ok=True)

# Curated Andean pastel palette (sRGB 0..1) — soft, chalky, sun-washed Andean limewash + Blanco Humo
PALETTE = {
    "blanco_humo":    (0.92, 0.91, 0.88),
    "crema":          (0.94, 0.89, 0.80),
    "celeste":        (0.80, 0.88, 0.93),
    "menta":          (0.81, 0.89, 0.82),
    "rosa_viejo":     (0.92, 0.81, 0.79),
    "amarillo_suave": (0.94, 0.89, 0.74),
    "lila":           (0.87, 0.83, 0.91),
    "durazno":        (0.93, 0.82, 0.74),
}

# Darker matching painted plinth (zócalo pintado) colors for non-stone-plinth houses
PLINTH_TINTS = {
    "blanco_humo":    (0.70, 0.69, 0.66),
    "crema":          (0.75, 0.66, 0.54),
    "celeste":        (0.56, 0.68, 0.75),
    "menta":          (0.57, 0.68, 0.60),
    "rosa_viejo":     (0.72, 0.57, 0.55),
    "amarillo_suave": (0.76, 0.68, 0.50),
    "lila":           (0.64, 0.59, 0.70),
    "durazno":        (0.74, 0.60, 0.51),
}

# 20-house catalog specification
CATALOG = [
    # --- Row 1: 1-story rural, caserío, quincha ---
    {"id": "01", "name": "01_rural_blanco_humo_teja",     "floors": 1, "w": 6.0, "d": 4.6, "wall": "blanco_humo",    "plinth": "stone_warm",  "roof": "gable_teja",           "door": "andina",   "win": "reja",       "porch": False, "balcony": [],     "extra": None},
    {"id": "02", "name": "02_rural_celeste_corredor",     "floors": 1, "w": 7.2, "d": 4.6, "wall": "celeste",        "plinth": "stone_warm",  "roof": "gable_teja",           "door": "andina",   "win": "reja",       "porch": True,  "balcony": [],     "extra": None},
    {"id": "03", "name": "03_casita_crema_calamina",      "floors": 1, "w": 5.6, "d": 4.2, "wall": "crema",          "plinth": "painted",     "roof": "gable_calamina_galv",  "door": "mahogany", "win": "whitehouse", "porch": False, "balcony": [],     "extra": None},
    {"id": "04", "name": "04_quincha_calamina_un_agua",   "floors": 1, "w": 5.2, "d": 4.0, "wall": "quincha_barro",  "plinth": "stone_rustic","roof": "shed_calamina_oxido",  "door": "andina",   "win": "reja",       "porch": False, "balcony": [],     "extra": None},
    {"id": "05", "name": "05_quincha_larga_calamina",     "floors": 1, "w": 7.4, "d": 4.4, "wall": "quincha_claro",  "plinth": "stone_rustic","roof": "gable_calamina_oxido", "door": "andina",   "win": "reja",       "porch": True,  "balcony": [],     "extra": None},

    # --- Row 2: 1-story pastel village & L-shaped quincha ---
    {"id": "06", "name": "06_pueblo_rosa_teja",           "floors": 1, "w": 6.0, "d": 4.6, "wall": "rosa_viejo",     "plinth": "stone_warm",  "roof": "gable_teja",           "door": "mahogany", "win": "reja",       "porch": False, "balcony": [],     "extra": None},
    {"id": "07", "name": "07_pueblo_menta_calamina",      "floors": 1, "w": 6.4, "d": 4.4, "wall": "menta",          "plinth": "painted",     "roof": "gable_calamina_galv",  "door": "mahogany", "win": "whitehouse", "porch": False, "balcony": [],     "extra": None},
    {"id": "08", "name": "08_caserio_amarillo_un_agua",   "floors": 1, "w": 6.0, "d": 4.2, "wall": "amarillo_suave", "plinth": "stone_warm",  "roof": "shed_teja",            "door": "andina",   "win": "reja",       "porch": False, "balcony": [],     "extra": None},
    {"id": "09", "name": "09_quincha_doble_calamina",     "floors": 1, "w": 6.2, "d": 4.2, "wall": "quincha_barro",  "plinth": "stone_gray",  "roof": "shed_calamina_oxido",  "door": "andina",   "win": "reja",       "porch": False, "balcony": [],     "extra": "l_wing"},
    {"id": "10", "name": "10_estancia_blanco_humo_porche","floors": 1, "w": 7.6, "d": 4.8, "wall": "blanco_humo",    "plinth": "stone_warm",  "roof": "gable_teja",           "door": "andina",   "win": "reja",       "porch": True,  "balcony": [],     "extra": "side_fence"},

    # --- Row 3: 2-story Andean houses with wooden balconies ---
    {"id": "11", "name": "11_andina2p_blanco_humo_balcon","floors": 2, "w": 6.4, "d": 4.8, "wall": "blanco_humo",    "plinth": "stone_warm",  "roof": "gable_teja",           "door": "andina",   "win": "reja",       "porch": False, "balcony": [2],    "extra": "full_balcony"},
    {"id": "12", "name": "12_andina2p_celeste_balcon",    "floors": 2, "w": 6.8, "d": 4.8, "wall": "celeste",        "plinth": "stone_warm",  "roof": "gable_teja",           "door": "andina",   "win": "whitehouse", "porch": False, "balcony": [2],    "extra": "balcony_canopy"},
    {"id": "13", "name": "13_andina2p_durazno_calamina",  "floors": 2, "w": 6.0, "d": 4.6, "wall": "durazno",        "plinth": "painted",     "roof": "gable_calamina_galv",  "door": "mahogany", "win": "whitehouse", "porch": False, "balcony": [2],    "extra": None},
    {"id": "14", "name": "14_andina2p_lila_teja",         "floors": 2, "w": 6.2, "d": 4.8, "wall": "lila",           "plinth": "stone_warm",  "roof": "gable_teja",           "door": "andina",   "win": "reja",       "porch": False, "balcony": [],     "extra": None},
    {"id": "15", "name": "15_quincha2p_barro_calamina",   "floors": 2, "w": 6.2, "d": 4.6, "wall": "quincha_barro",  "plinth": "stone_rustic","roof": "gable_calamina_oxido", "door": "andina",   "win": "reja",       "porch": False, "balcony": [2],    "extra": "full_balcony"},

    # --- Row 4: Stepped 2-story + 3-story town houses ---
    {"id": "16", "name": "16_andina2p_menta_retranqueo",  "floors": 2, "w": 7.4, "d": 4.8, "wall": "menta",          "plinth": "stone_gray",  "roof": "shed_calamina_galv",   "door": "mahogany", "win": "whitehouse", "porch": False, "balcony": [],     "extra": "stepped_top"},
    {"id": "17", "name": "17_andina3p_blanco_humo_balcon","floors": 3, "w": 6.4, "d": 4.8, "wall": "blanco_humo",    "plinth": "stone_warm",  "roof": "gable_teja",           "door": "andina",   "win": "reja",       "porch": False, "balcony": [2],    "extra": "full_balcony"},
    {"id": "18", "name": "18_andina3p_crema_doble_balcon","floors": 3, "w": 7.0, "d": 4.8, "wall": "crema",          "plinth": "stone_warm",  "roof": "gable_teja",           "door": "andina",   "win": "whitehouse", "porch": False, "balcony": [2, 3], "extra": None},
    {"id": "19", "name": "19_andina3p_rosa_calamina",     "floors": 3, "w": 6.2, "d": 4.6, "wall": "rosa_viejo",     "plinth": "painted",     "roof": "gable_calamina_galv",  "door": "mahogany", "win": "whitehouse", "porch": False, "balcony": [2],    "extra": None},
    {"id": "20", "name": "20_andina3p_celeste_azotea",    "floors": 3, "w": 6.6, "d": 4.8, "wall": "celeste",        "plinth": "painted",     "roof": "flat_azotea",          "door": "mahogany", "win": "whitehouse", "porch": False, "balcony": [2],    "extra": "azotea_shed"},
]


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def ensure_tinted_textures():
    """Pre-bake 64x64 tinted stucco PNGs so GLB exports have 100% faithful pastel colors everywhere."""
    # Use Blender's own image API (no Pillow needed inside Blender's Python!)
    src_path = os.path.join(TEX_DIR, "stucco_clean.png")
    src = bpy.data.images.load(src_path, check_existing=True)
    w, h = src.size
    src_px = list(src.pixels)

    for cname, rgb in PALETTE.items():
        for prefix, col in [("stucco_", rgb), ("plinth_", PLINTH_TINTS[cname])]:
            out_path = os.path.join(TEX_DIR, f"{prefix}{cname}.png")
            im = bpy.data.images.new(f"{prefix}{cname}", width=w, height=h, alpha=False)
            out_px = [0.0] * len(src_px)
            for i in range(0, len(src_px), 4):
                # src_px is linear in Blender; multiply by linear tint
                out_px[i]     = min(1.0, src_px[i]     * srgb_to_linear(col[0]))
                out_px[i + 1] = min(1.0, src_px[i + 1] * srgb_to_linear(col[1]))
                out_px[i + 2] = min(1.0, src_px[i + 2] * srgb_to_linear(col[2]))
                out_px[i + 3] = 1.0
            im.pixels = out_px
            im.filepath_raw = out_path
            im.file_format = 'PNG'
            im.save()
            bpy.data.images.remove(im)


MAT_CACHE = {}


def get_mat(name: str, tex_file: str):
    if name in MAT_CACHE:
        return MAT_CACHE[name]
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.94
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.08

    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.interpolation = 'Closest'  # Nearest neighbor for crisp 64x64 PSX look!
    img_path = os.path.join(TEX_DIR, tex_file)
    img = bpy.data.images.load(img_path, check_existing=True)
    img.pack()  # Pack into memory for clean GLB export
    tex.image = img

    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    MAT_CACHE[name] = mat
    return mat


class MeshBuilder:
    """Low-poly box/prism/quad builder with clean world-scale box/planar UVs."""
    def __init__(self, obj_name: str):
        self.obj_name = obj_name
        self.bm = bmesh.new()
        self.uv_layer = self.bm.loops.layers.uv.new("UVMap")
        self.materials = []
        self.mat_idx = {}

    def mat_slot(self, mat_name: str, tex_file: str) -> int:
        if mat_name not in self.mat_idx:
            self.mat_idx[mat_name] = len(self.materials)
            self.materials.append(get_mat(mat_name, tex_file))
        return self.mat_idx[mat_name]

    def add_quad(self, p0, p1, p2, p3, mat_slot: int, uv_scale=(1.0, 1.0), uv_fit=False):
        """Add a quad (CCW facing outward) with either world-tiled UVs or 0..1 fit UVs."""
        v0 = self.bm.verts.new(p0)
        v1 = self.bm.verts.new(p1)
        v2 = self.bm.verts.new(p2)
        v3 = self.bm.verts.new(p3)
        f = self.bm.faces.new((v0, v1, v2, v3))
        f.material_index = mat_slot
        if uv_fit:
            uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        else:
            w = (Vector(p1) - Vector(p0)).length / uv_scale[0]
            h = (Vector(p3) - Vector(p0)).length / uv_scale[1]
            uvs = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)]
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv_layer].uv = uv
        return f

    def add_tri(self, p0, p1, p2, mat_slot: int, uv_scale=(1.0, 1.0)):
        v0 = self.bm.verts.new(p0)
        v1 = self.bm.verts.new(p1)
        v2 = self.bm.verts.new(p2)
        f = self.bm.faces.new((v0, v1, v2))
        f.material_index = mat_slot
        base = Vector(p1) - Vector(p0)
        bw = base.length
        bdir = base.normalized() if bw > 1e-5 else Vector((1, 0, 0))
        apex_vec = Vector(p2) - Vector(p0)
        u2 = apex_vec.dot(bdir) / uv_scale[0]
        v2_h = (apex_vec - bdir * apex_vec.dot(bdir)).length / uv_scale[1]
        uvs = [(0.0, 0.0), (bw / uv_scale[0], 0.0), (u2, v2_h)]
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv_layer].uv = uv
        return f

    def add_box(self, x0, y0, z0, x1, y1, z1, mat_slot: int, uv_scale=(2.0, 2.0), uv_fit=False, skip_bottom=False, skip_top=False):
        # Front (-Y)
        self.add_quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), mat_slot, uv_scale, uv_fit)
        # Back (+Y)
        self.add_quad((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1), mat_slot, uv_scale, uv_fit)
        # Left (-X)
        self.add_quad((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1), mat_slot, uv_scale, uv_fit)
        # Right (+X)
        self.add_quad((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1), mat_slot, uv_scale, uv_fit)
        # Top (+Z)
        if not skip_top:
            self.add_quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), mat_slot, uv_scale, uv_fit)
        # Bottom (-Z)
        if not skip_bottom:
            self.add_quad((x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0), mat_slot, uv_scale, uv_fit)

    def build_object(self):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(self.obj_name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.materials:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.obj_name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def add_framed_opening(mb: MeshBuilder, side: str, center_u: float, z0: float, width: float, height: float,
                       box_bounds, open_mat: int, wood_mat: int, is_door: bool = False):
    """Add a low-poly framed door or window slightly protruding from the wall face."""
    x0, y0, x1, y1 = box_bounds
    hw = width * 0.5
    depth = 0.05
    lintel_h = 0.11
    lintel_ext = 0.12
    lintel_d = 0.09

    if side == "front":  # -Y face
        u0, u1 = center_u - hw, center_u + hw
        mb.add_box(u0, y0 - depth, z0, u1, y0, z0 + height, open_mat, uv_fit=True, skip_bottom=is_door)
        # Wooden lintel above
        mb.add_box(u0 - lintel_ext, y0 - lintel_d, z0 + height, u1 + lintel_ext, y0, z0 + height + lintel_h, wood_mat, uv_scale=(1.2, 0.3))
        if not is_door:
            # Wooden sill below
            mb.add_box(u0 - 0.06, y0 - 0.08, z0 - 0.07, u1 + 0.06, y0, z0, wood_mat, uv_scale=(1.2, 0.3))
    elif side == "back":  # +Y face
        u0, u1 = center_u - hw, center_u + hw
        mb.add_box(u0, y1, z0, u1, y1 + depth, z0 + height, open_mat, uv_fit=True, skip_bottom=is_door)
        mb.add_box(u0 - lintel_ext, y1, z0 + height, u1 + lintel_ext, y1 + lintel_d, z0 + height + lintel_h, wood_mat, uv_scale=(1.2, 0.3))
        if not is_door:
            mb.add_box(u0 - 0.06, y1, z0 - 0.07, u1 + 0.06, y1 + 0.08, z0, wood_mat, uv_scale=(1.2, 0.3))
    elif side == "left":  # -X face
        u0, u1 = center_u - hw, center_u + hw
        mb.add_box(x0 - depth, u0, z0, x0, u1, z0 + height, open_mat, uv_fit=True, skip_bottom=is_door)
        mb.add_box(x0 - lintel_d, u0 - lintel_ext, z0 + height, x0, u1 + lintel_ext, z0 + height + lintel_h, wood_mat, uv_scale=(1.2, 0.3))
        if not is_door:
            mb.add_box(x0 - 0.08, u0 - 0.06, z0 - 0.07, x0, u1 + 0.06, z0, wood_mat, uv_scale=(1.2, 0.3))
    elif side == "right":  # +X face
        u0, u1 = center_u - hw, center_u + hw
        mb.add_box(x1, u0, z0, x1 + depth, u1, z0 + height, open_mat, uv_fit=True, skip_bottom=is_door)
        mb.add_box(x1, u0 - lintel_ext, z0 + height, x1 + lintel_d, u1 + lintel_ext, z0 + height + lintel_h, wood_mat, uv_scale=(1.2, 0.3))
        if not is_door:
            mb.add_box(x1, u0 - 0.06, z0 - 0.07, x1 + 0.08, u1 + 0.06, z0, wood_mat, uv_scale=(1.2, 0.3))


def add_wooden_balcony(mb: MeshBuilder, x0: float, x1: float, y_wall: float, z_floor: float,
                       wood_mat: int, fence_mat: int, roof_mat: int = None, with_canopy: bool = False):
    """Authentic Andean wooden balcony protruding along -Y."""
    depth = 1.05
    y_front = y_wall - depth
    slab_h = 0.14
    rail_h = 0.92

    # Floor slab
    mb.add_box(x0, y_front, z_floor - slab_h, x1, y_wall + 0.04, z_floor, wood_mat, uv_scale=(1.8, 1.0))

    # Supporting corbel beams under slab (vigas en voladizo)
    span = x1 - x0
    n_beams = max(3, int(span / 1.15) + 1)
    for i in range(n_beams):
        t = i / (n_beams - 1)
        bx = x0 + 0.14 + t * (span - 0.28)
        mb.add_box(bx - 0.06, y_front - 0.08, z_floor - slab_h - 0.14, bx + 0.06, y_wall, z_floor - slab_h, wood_mat, uv_scale=(1.0, 0.4))

    # Vertical posts (if canopy or tall posts)
    post_top = z_floor + (2.35 if with_canopy else rail_h + 0.06)
    n_posts = max(2, int(span / 1.8) + 1)
    for i in range(n_posts):
        t = i / (n_posts - 1)
        px = x0 + 0.08 + t * (span - 0.16)
        mb.add_box(px - 0.06, y_front, z_floor, px + 0.06, y_front + 0.12, post_top, wood_mat, uv_scale=(0.5, 1.5))

    # Side corner posts at wall
    for px in (x0 + 0.06, x1 - 0.06):
        mb.add_box(px - 0.05, y_wall - 0.10, z_floor, px + 0.05, y_wall, z_floor + rail_h, wood_mat, uv_scale=(0.5, 1.2))

    # Top handrail (front + sides)
    mb.add_box(x0, y_front - 0.02, z_floor + rail_h - 0.08, x1, y_front + 0.14, z_floor + rail_h, wood_mat, uv_scale=(2.0, 0.3))
    mb.add_box(x0, y_front, z_floor + rail_h - 0.08, x0 + 0.12, y_wall, z_floor + rail_h, wood_mat, uv_scale=(1.0, 0.3))
    mb.add_box(x1 - 0.12, y_front, z_floor + rail_h - 0.08, x1, y_wall, z_floor + rail_h, wood_mat, uv_scale=(1.0, 0.3))

    # Balustrade infill panels (front + sides using Nortimore wood fence texture)
    mb.add_box(x0 + 0.10, y_front + 0.03, z_floor + 0.06, x1 - 0.10, y_front + 0.09, z_floor + rail_h - 0.08, fence_mat, uv_scale=(1.1, 0.85))
    mb.add_box(x0 + 0.03, y_front + 0.10, z_floor + 0.06, x0 + 0.09, y_wall - 0.05, z_floor + rail_h - 0.08, fence_mat, uv_scale=(1.0, 0.85))
    mb.add_box(x1 - 0.09, y_front + 0.10, z_floor + 0.06, x1 - 0.03, y_wall - 0.05, z_floor + rail_h - 0.08, fence_mat, uv_scale=(1.0, 0.85))

    # Optional sloped balcony canopy
    if with_canopy and roof_mat is not None:
        z_hi = z_floor + 2.58
        z_lo = z_floor + 2.22
        ov = 0.22
        mb.add_quad((x0 - ov, y_front - ov, z_lo), (x1 + ov, y_front - ov, z_lo),
                    (x1 + ov, y_wall, z_hi), (x0 - ov, y_wall, z_hi), roof_mat, uv_scale=(1.6, 1.6))
        mb.add_quad((x0 - ov, y_wall, z_hi - 0.08), (x1 + ov, y_wall, z_hi - 0.08),
                    (x1 + ov, y_front - ov, z_lo - 0.08), (x0 - ov, y_front - ov, z_lo - 0.08), wood_mat, uv_scale=(1.6, 1.6))


def add_gable_roof(mb: MeshBuilder, x0, y0, x1, y1, z_base, wall_mat, roof_mat, wood_mat,
                   pitch_ratio=0.34, overhang_x=0.42, overhang_y=0.45, porch_extend_y=0.0):
    """Two-slope Andean gable roof with ridge along X, gable triangles on -X and +X."""
    ym = 0.5 * (y0 + y1)
    half_d = 0.5 * (y1 - y0)
    ridge_h = half_d * pitch_ratio * 2.0
    z_ridge = z_base + ridge_h

    # Gable triangles on left (-X) and right (+X)
    mb.add_tri((x0, y1, z_base), (x0, y0, z_base), (x0, ym, z_ridge), wall_mat, uv_scale=(2.4, 2.4))
    mb.add_tri((x1, y0, z_base), (x1, y1, z_base), (x1, ym, z_ridge), wall_mat, uv_scale=(2.4, 2.4))

    rx0, rx1 = x0 - overhang_x, x1 + overhang_x
    # Front slope extends further if porch_extend_y > 0
    front_ov = overhang_y + porch_extend_y
    slope = ridge_h / max(half_d, 0.1)
    y_front_eave = y0 - front_ov
    z_front_eave = z_base - front_ov * slope
    y_back_eave = y1 + overhang_y
    z_back_eave = z_base - overhang_y * slope
    thick = 0.11

    # Top roof slopes (front & back)
    mb.add_quad((rx0, y_front_eave, z_front_eave + thick), (rx1, y_front_eave, z_front_eave + thick),
                (rx1, ym, z_ridge + thick), (rx0, ym, z_ridge + thick), roof_mat, uv_scale=(1.9, 1.9))
    mb.add_quad((rx1, y_back_eave, z_back_eave + thick), (rx0, y_back_eave, z_back_eave + thick),
                (rx0, ym, z_ridge + thick), (rx1, ym, z_ridge + thick), roof_mat, uv_scale=(1.9, 1.9))

    # Underside soffit (dark wood)
    mb.add_quad((rx0, ym, z_ridge), (rx1, ym, z_ridge),
                (rx1, y_front_eave, z_front_eave), (rx0, y_front_eave, z_front_eave), wood_mat, uv_scale=(2.0, 2.0))
    mb.add_quad((rx1, ym, z_ridge), (rx0, ym, z_ridge),
                (rx0, y_back_eave, z_back_eave), (rx1, y_back_eave, z_back_eave), wood_mat, uv_scale=(2.0, 2.0))

    # Fascia strips (front, back, gable edges)
    mb.add_quad((rx0, y_front_eave, z_front_eave), (rx1, y_front_eave, z_front_eave),
                (rx1, y_front_eave, z_front_eave + thick), (rx0, y_front_eave, z_front_eave + thick), wood_mat, uv_scale=(2.0, 0.3))
    mb.add_quad((rx1, y_back_eave, z_back_eave), (rx0, y_back_eave, z_back_eave),
                (rx0, y_back_eave, z_back_eave + thick), (rx1, y_back_eave, z_back_eave + thick), wood_mat, uv_scale=(2.0, 0.3))
    # Left & right fascia along slopes
    for side_x, flip in ((rx0, False), (rx1, True)):
        if not flip:
            mb.add_quad((side_x, ym, z_ridge), (side_x, y_front_eave, z_front_eave),
                        (side_x, y_front_eave, z_front_eave + thick), (side_x, ym, z_ridge + thick), wood_mat, uv_scale=(2.0, 0.3))
            mb.add_quad((side_x, y_back_eave, z_back_eave), (side_x, ym, z_ridge),
                        (side_x, ym, z_ridge + thick), (side_x, y_back_eave, z_back_eave + thick), wood_mat, uv_scale=(2.0, 0.3))
        else:
            mb.add_quad((side_x, y_front_eave, z_front_eave), (side_x, ym, z_ridge),
                        (side_x, ym, z_ridge + thick), (side_x, y_front_eave, z_front_eave + thick), wood_mat, uv_scale=(2.0, 0.3))
            mb.add_quad((side_x, ym, z_ridge), (side_x, y_back_eave, z_back_eave),
                        (side_x, y_back_eave, z_back_eave + thick), (side_x, ym, z_ridge + thick), wood_mat, uv_scale=(2.0, 0.3))

    return z_front_eave


def add_shed_roof(mb: MeshBuilder, x0, y0, x1, y1, z_base, wall_mat, roof_mat, wood_mat, rise=0.85, overhang=0.38):
    """Single-slope (techo a un agua) roof sloping down toward -Y (front) or +Y."""
    z_front = z_base
    z_back = z_base + rise

    # Back wall extension + left/right slope triangles
    mb.add_quad((x1, y1, z_base), (x0, y1, z_base), (x0, y1, z_back), (x1, y1, z_back), wall_mat, uv_scale=(2.4, 2.4))
    mb.add_tri((x0, y1, z_base), (x0, y0, z_front), (x0, y1, z_back), wall_mat, uv_scale=(2.4, 2.4))
    mb.add_tri((x1, y0, z_front), (x1, y1, z_base), (x1, y1, z_back), wall_mat, uv_scale=(2.4, 2.4))

    slope = rise / max(y1 - y0, 0.1)
    rx0, rx1 = x0 - overhang, x1 + overhang
    yf, yb = y0 - overhang, y1 + overhang
    zf = z_front - overhang * slope
    zb = z_back + overhang * slope
    thick = 0.09

    # Top + underside + fascia
    mb.add_quad((rx0, yf, zf + thick), (rx1, yf, zf + thick), (rx1, yb, zb + thick), (rx0, yb, zb + thick), roof_mat, uv_scale=(1.9, 1.9))
    mb.add_quad((rx0, yb, zb), (rx1, yb, zb), (rx1, yf, zf), (rx0, yf, zf), wood_mat, uv_scale=(2.0, 2.0))
    mb.add_quad((rx0, yf, zf), (rx1, yf, zf), (rx1, yf, zf + thick), (rx0, yf, zf + thick), wood_mat, uv_scale=(2.0, 0.3))
    mb.add_quad((rx1, yb, zb), (rx0, yb, zb), (rx0, yb, zb + thick), (rx1, yb, zb + thick), wood_mat, uv_scale=(2.0, 0.3))
    mb.add_quad((rx0, yb, zb), (rx0, yf, zf), (rx0, yf, zf + thick), (rx0, yb, zb + thick), wood_mat, uv_scale=(2.0, 0.3))
    mb.add_quad((rx1, yf, zf), (rx1, yb, zb), (rx1, yb, zb + thick), (rx1, yf, zf + thick), wood_mat, uv_scale=(2.0, 0.3))


def build_house(spec: dict):
    mb = MeshBuilder(spec["name"])
    floors = spec["floors"]
    w = spec["w"]
    d = spec["d"]
    hw, hd = w * 0.5, d * 0.5
    x0, x1 = -hw, hw
    y0, y1 = -hd, hd

    # Resolve wall material
    wall_key = spec["wall"]
    if wall_key == "quincha_barro":
        wall_mat = mb.mat_slot("mat_quincha_barro", "wall_quincha_barro.png")
    elif wall_key == "quincha_claro":
        wall_mat = mb.mat_slot("mat_quincha_claro", "wall_quincha_claro.png")
    else:
        wall_mat = mb.mat_slot(f"mat_stucco_{wall_key}", f"stucco_{wall_key}.png")

    # Resolve plinth material (Floor 1 only)
    plinth_key = spec["plinth"]
    if plinth_key == "stone_warm":
        plinth_mat = mb.mat_slot("mat_stone_plinth_warm", "stone_plinth_warm.png")
    elif plinth_key == "stone_rustic":
        plinth_mat = mb.mat_slot("mat_stone_rustic", "stone_rustic.png")
    elif plinth_key == "stone_gray":
        plinth_mat = mb.mat_slot("mat_stone_gray", "stone_gray.png")
    else:
        plinth_mat = mb.mat_slot(f"mat_plinth_{wall_key}", f"plinth_{wall_key}.png")

    # Foundation skirt (for Andean mountain slopes, extends below y=0)
    skirt_mat = mb.mat_slot("mat_stone_gray", "stone_gray.png")
    wood_mat = mb.mat_slot("mat_wood_beam", "wood_beam.png")
    post_mat = mb.mat_slot("mat_wood_post", "wood_post.png")
    fence_mat = mb.mat_slot("mat_fence_wood", "fence_wood.png")
    floor_mat = mb.mat_slot("mat_floor_terracotta", "floor_terracotta.png")

    door_mat = mb.mat_slot("mat_door_andina", "door_andina.png") if spec["door"] == "andina" else mb.mat_slot("mat_door_mahogany", "door_mahogany.png")
    win_mat = mb.mat_slot("mat_win_reja", "window_reja.png") if spec["win"] == "reja" else mb.mat_slot("mat_win_whitehouse", "window_wood_whitehouse.png")

    roof_type = spec["roof"]
    if "teja" in roof_type:
        roof_mat = mb.mat_slot("mat_roof_teja", "roof_teja.png")
    elif "oxido" in roof_type:
        roof_mat = mb.mat_slot("mat_roof_calamina_oxido", "roof_calamina_oxido.png")
    else:
        roof_mat = mb.mat_slot("mat_roof_calamina_galv", "roof_calamina_galv.png")

    # 1. Foundation skirt (-2.4m to 0.0m)
    skirt_y0 = y0 - (1.65 if spec["porch"] else 0.0)
    mb.add_box(x0 - 0.03, skirt_y0 - 0.03, -2.4, x1 + 0.03, y1 + 0.03, 0.0, skirt_mat, uv_scale=(2.2, 2.2), skip_top=True)

    # 2. Floor 1 (z = 0.0 .. 2.85m): stone/painted plinth (0..0.78m) + upper wall (0.78..2.85m)
    f1_h = 2.85
    plinth_h = 0.78
    mb.add_box(x0, y0, 0.0, x1, y1, plinth_h, plinth_mat, uv_scale=(2.0, 1.5), skip_top=True, skip_bottom=True)
    mb.add_box(x0, y0, plinth_h, x1, y1, f1_h, wall_mat, uv_scale=(2.4, 2.4), skip_bottom=True)

    # Front door + ground-floor windows
    door_x = -hw * 0.36 if w >= 6.2 else 0.0
    add_framed_opening(mb, "front", door_x, 0.02, 1.05, 2.05, (x0, y0, x1, y1), door_mat, wood_mat, is_door=True)
    if w >= 6.2:
        add_framed_opening(mb, "front", hw * 0.32, 1.02, 1.05, 1.15, (x0, y0, x1, y1), win_mat, wood_mat)
        if w >= 7.1:
            add_framed_opening(mb, "front", 0.02, 1.02, 0.95, 1.12, (x0, y0, x1, y1), win_mat, wood_mat)
    else:
        add_framed_opening(mb, "front", hw * 0.56, 1.02, 0.95, 1.10, (x0, y0, x1, y1), win_mat, wood_mat)
        add_framed_opening(mb, "front", -hw * 0.56, 1.02, 0.95, 1.10, (x0, y0, x1, y1), win_mat, wood_mat)

    # Side & back windows on Floor 1
    add_framed_opening(mb, "left", 0.0, 1.05, 1.0, 1.10, (x0, y0, x1, y1), win_mat, wood_mat)
    add_framed_opening(mb, "right", 0.0, 1.05, 1.0, 1.10, (x0, y0, x1, y1), win_mat, wood_mat)
    add_framed_opening(mb, "back", -hw * 0.32, 1.05, 1.0, 1.10, (x0, y0, x1, y1), win_mat, wood_mat)
    add_framed_opening(mb, "back", hw * 0.32, 1.05, 1.0, 1.10, (x0, y0, x1, y1), win_mat, wood_mat)

    # Ground-floor porch / corredor (Nortimore style)
    porch_ext = 0.0
    if spec["porch"]:
        porch_d = 1.50
        porch_ext = porch_d
        # Compute exact eave height at porch post line so beam & posts tuck cleanly UNDER the sloped roof
        roof_pitch = 0.28 if "teja" in roof_type else 0.22
        slope = roof_pitch * 2.0
        post_y_offset = porch_d - 0.18
        eave_at_posts = f1_h - post_y_offset * slope
        beam_top = max(2.12, eave_at_posts - 0.04)
        beam_bot = beam_top - 0.16
        # Raised terracotta floor slab
        mb.add_box(x0, y0 - porch_d, 0.0, x1, y0, 0.16, floor_mat, uv_scale=(1.4, 1.4), skip_bottom=True)
        # Wooden posts with stone bases
        n_posts = 4 if w >= 7.0 else 3
        for i in range(n_posts):
            t = i / (n_posts - 1)
            px = x0 + 0.22 + t * (w - 0.44)
            mb.add_box(px - 0.13, y0 - porch_d + 0.06, 0.16, px + 0.13, y0 - porch_d + 0.32, 0.60, plinth_mat, uv_scale=(1.0, 1.0))
            mb.add_box(px - 0.09, y0 - porch_d + 0.10, 0.60, px + 0.09, y0 - porch_d + 0.28, beam_bot, post_mat, uv_scale=(0.6, 1.8))
        # Porch header beam
        mb.add_box(x0, y0 - porch_d + 0.08, beam_bot, x1, y0 - porch_d + 0.30, beam_top, wood_mat, uv_scale=(2.2, 0.4))

    # Optional side fence (House 10)
    if spec["extra"] == "side_fence":
        mb.add_box(x1, y0 - 1.35, 0.0, x1 + 2.1, y0 - 1.22, 1.05, fence_mat, uv_scale=(1.05, 1.05))
        mb.add_box(x1 + 2.02, y0 - 1.40, 0.0, x1 + 2.18, y0 - 1.18, 1.15, wood_mat, uv_scale=(0.5, 1.0))

    # Optional L-wing (House 09 - Quincha doble)
    if spec["extra"] == "l_wing":
        wx0, wx1 = x1 - 0.05, x1 + 2.8
        wy0, wy1 = y0 - 2.6, y0 + 1.4
        mb.add_box(wx0, wy0, -2.4, wx1, wy1, 0.0, skirt_mat, uv_scale=(2.2, 2.2), skip_top=True)
        mb.add_box(wx0, wy0, 0.0, wx1, wy1, 0.70, plinth_mat, uv_scale=(2.0, 1.5), skip_top=True)
        mb.add_box(wx0, wy0, 0.70, wx1, wy1, 2.55, wall_mat, uv_scale=(2.4, 2.4))
        add_framed_opening(mb, "front", 0.5 * (wx0 + wx1), 0.95, 0.95, 1.05, (wx0, wy0, wx1, wy1), win_mat, wood_mat)
        add_shed_roof(mb, wx0, wy0, wx1, wy1, 2.55, wall_mat, roof_mat, wood_mat, rise=0.65, overhang=0.30)

    # 3. Upper Floors (Floor 2 & Floor 3) — NO stone plinth!
    z_top = f1_h
    top_x0, top_x1 = x0, x1
    for fl in range(2, floors + 1):
        fl_h = 2.65
        z0 = z_top
        z1 = z_top + fl_h

        # Stepped upper floor (House 16)
        fx0, fx1 = x0, x1
        if spec["extra"] == "stepped_top" and fl == 2:
            fx0 = x0 + 2.2
            # Wooden railing around side terrace
            mb.add_box(x0 + 0.06, y0 + 0.06, z0, fx0, y0 + 0.14, z0 + 0.92, fence_mat, uv_scale=(1.1, 0.9))
            mb.add_box(x0 + 0.06, y0 + 0.06, z0, x0 + 0.14, y1 - 0.06, z0 + 0.92, fence_mat, uv_scale=(1.1, 0.9))
            mb.add_box(x0, y0, z0 - 0.02, fx0, y1, z0 + 0.06, floor_mat, uv_scale=(1.4, 1.4))

        top_x0, top_x1 = fx0, fx1
        # Subtle wooden floor band
        mb.add_box(fx0 - 0.04, y0 - 0.04, z0 - 0.07, fx1 + 0.04, y1 + 0.04, z0 + 0.07, wood_mat, uv_scale=(2.0, 0.3))
        # Upper wall (pure stucco or quincha)
        mb.add_box(fx0, y0, z0, fx1, y1, z1, wall_mat, uv_scale=(2.4, 2.4), skip_bottom=True)

        # Windows / balcony doors on front
        fw = fx1 - fx0
        fcx = 0.5 * (fx0 + fx1)
        has_balc = fl in spec["balcony"]
        if has_balc:
            # Balcony door in center + flanking windows if wide
            add_framed_opening(mb, "front", fcx, z0 + 0.02, 1.05, 2.02, (fx0, y0, fx1, y1), door_mat, wood_mat, is_door=True)
            if fw >= 6.0:
                add_framed_opening(mb, "front", fx0 + fw * 0.20, z0 + 0.92, 0.95, 1.12, (fx0, y0, fx1, y1), win_mat, wood_mat)
                add_framed_opening(mb, "front", fx1 - fw * 0.20, z0 + 0.92, 0.95, 1.12, (fx0, y0, fx1, y1), win_mat, wood_mat)
            # Balcony span
            if spec["extra"] == "full_balcony":
                bx0, bx1 = fx0 + 0.15, fx1 - 0.15
            else:
                bx0, bx1 = fcx - min(2.1, fw * 0.38), fcx + min(2.1, fw * 0.38)
            with_canopy = (spec["extra"] == "balcony_canopy" and fl == 2)
            add_wooden_balcony(mb, bx0, bx1, y0, z0, wood_mat, fence_mat, roof_mat=roof_mat, with_canopy=with_canopy)
        else:
            if fw >= 5.6:
                add_framed_opening(mb, "front", fcx - fw * 0.24, z0 + 0.92, 1.0, 1.15, (fx0, y0, fx1, y1), win_mat, wood_mat)
                add_framed_opening(mb, "front", fcx + fw * 0.24, z0 + 0.92, 1.0, 1.15, (fx0, y0, fx1, y1), win_mat, wood_mat)
            else:
                add_framed_opening(mb, "front", fcx, z0 + 0.92, 1.05, 1.15, (fx0, y0, fx1, y1), win_mat, wood_mat)

        # Side & back windows on upper floors
        add_framed_opening(mb, "left", 0.0, z0 + 0.92, 0.95, 1.10, (fx0, y0, fx1, y1), win_mat, wood_mat)
        add_framed_opening(mb, "right", 0.0, z0 + 0.92, 0.95, 1.10, (fx0, y0, fx1, y1), win_mat, wood_mat)
        add_framed_opening(mb, "back", fcx - fw * 0.22, z0 + 0.92, 0.95, 1.10, (fx0, y0, fx1, y1), win_mat, wood_mat)
        add_framed_opening(mb, "back", fcx + fw * 0.22, z0 + 0.92, 0.95, 1.10, (fx0, y0, fx1, y1), win_mat, wood_mat)

        z_top = z1

    # 4. Roof
    if roof_type.startswith("gable_"):
        if spec["porch"]:
            pitch = 0.28 if "teja" in roof_type else 0.22
        else:
            pitch = 0.36 if "teja" in roof_type else 0.24
        add_gable_roof(mb, top_x0, y0, top_x1, y1, z_top, wall_mat, roof_mat, wood_mat,
                       pitch_ratio=pitch, overhang_x=0.42, overhang_y=0.44, porch_extend_y=porch_ext)
    elif roof_type.startswith("shed_"):
        rise = 0.95 if "teja" in roof_type else 0.72
        add_shed_roof(mb, top_x0, y0, top_x1, y1, z_top, wall_mat, roof_mat, wood_mat, rise=rise, overhang=0.40)
    elif roof_type == "flat_azotea":
        # Flat roof terrace with parapet walls + small corrugated metal shelter
        ph = 0.85
        pt = 0.22
        mb.add_box(top_x0, y0, z_top - 0.05, top_x1, y1, z_top + 0.05, floor_mat, uv_scale=(1.5, 1.5))
        mb.add_box(top_x0, y0, z_top, top_x1, y0 + pt, z_top + ph, wall_mat, uv_scale=(2.4, 2.4))
        mb.add_box(top_x0, y1 - pt, z_top, top_x1, y1, z_top + ph, wall_mat, uv_scale=(2.4, 2.4))
        mb.add_box(top_x0, y0 + pt, z_top, top_x0 + pt, y1 - pt, z_top + ph, wall_mat, uv_scale=(2.4, 2.4))
        mb.add_box(top_x1 - pt, y0 + pt, z_top, top_x1, y1 - pt, z_top + ph, wall_mat, uv_scale=(2.4, 2.4))
        if spec["extra"] == "azotea_shed":
            sx0, sx1 = top_x0 + 0.3, top_x0 + 3.0
            sy0, sy1 = y0 + 1.4, y1 - 0.3
            mb.add_box(sx0, sy0, z_top, sx1, sy1, z_top + 2.0, wall_mat, uv_scale=(2.4, 2.4))
            add_shed_roof(mb, sx0, sy0, sx1, sy1, z_top + 2.0, wall_mat, roof_mat, wood_mat, rise=0.45, overhang=0.28)

    return mb.build_object()


def export_single_glb(obj, glb_path: str):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    orig_loc = obj.location.copy()
    obj.location = (0.0, 0.0, 0.0)
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
    )
    obj.location = orig_loc


def setup_showcase_and_render(objs):
    """Arrange all 20 houses in a 5x4 grid and render a crisp overview screenshot."""
    # Ground plane (Andean ochre/gravel ground)
    bpy.ops.mesh.primitive_plane_add(size=140.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    gmat = bpy.data.materials.new("GroundMat")
    gmat.use_nodes = True
    bsdf = gmat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.28, 0.25, 0.20, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.98
    ground.data.materials.append(gmat)

    # Place 20 houses in 4 rows x 5 columns (row 0 = front/bottom, row 3 = back/top)
    spacing_x = 11.4
    spacing_y = 11.4
    cols = 5
    rows = 4
    positions = {}
    for idx, (spec, obj) in enumerate(zip(CATALOG, objs)):
        r = idx // cols
        c = idx % cols
        # Row 0 (1-story) in front (-Y), Row 3 (3-story) in back (+Y) so tall houses don't block short ones!
        px = (c - (cols - 1) * 0.5) * spacing_x
        py = (r - (rows - 1) * 0.5) * spacing_y
        obj.location = (px, py, 0.0)
        positions[spec["id"]] = (px, py)

    # Andean daylight Sun + bright sky
    world = bpy.data.worlds.new("AndeanSky")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.52, 0.68, 0.88, 1.0)
    bg.inputs["Strength"].default_value = 0.85

    sun_data = bpy.data.lights.new("AndeanSun", type='SUN')
    sun_data.energy = 3.2
    sun_data.color = (1.0, 0.96, 0.88)
    sun_obj = bpy.data.objects.new("AndeanSun", sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(48), math.radians(15), math.radians(-32))

    # Camera: elevated 3/4 front overview capturing ALL 20 houses with generous margin
    cam_data = bpy.data.cameras.new("OverviewCam")
    cam_data.lens = 35.0
    cam_data.clip_end = 500.0
    cam_obj = bpy.data.objects.new("OverviewCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0.0, -68.0, 42.0)
    direction = Vector((0.0, -1.5, 2.2)) - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam_obj

    # Render settings (EEVEE Next / Workbench-fast EEVEE)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1180
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.exposure = -0.15

    render_path = os.path.join(SCRATCH_DIR, "catalogo_20_casas_raw.png")
    scene.render.filepath = render_path
    bpy.ops.render.render(write_still=True)

    # Save screen-space projections of each house label so Pillow can draw clean numbers!
    from bpy_extras.object_utils import world_to_camera_view
    label_coords = []
    for spec, obj in zip(CATALOG, objs):
        # Put label just in front of house base
        pt = Vector((obj.location.x, obj.location.y - spec["d"] * 0.5 - 1.35, 0.15))
        co = world_to_camera_view(scene, cam_obj, pt)
        label_coords.append({
            "id": spec["id"],
            "name": spec["name"],
            "u": float(co.x),
            "v": float(co.y),
        })
    with open(os.path.join(SCRATCH_DIR, "label_coords.json"), "w", encoding="utf-8") as f:
        json.dump(label_coords, f, indent=2)
    print("RENDERED:", render_path)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ensure_tinted_textures()

    objs = []
    manifest = []
    for spec in CATALOG:
        obj = build_house(spec)
        glb_path = os.path.join(GLB_DIR, f"{spec['name']}.glb")
        export_single_glb(obj, glb_path)
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        manifest.append({
            "id": spec["id"],
            "name": spec["name"],
            "glb": f"res://assets/rally/CDI/casas_andinas/glb/{spec['name']}.glb",
            "floors": spec["floors"],
            "width_m": spec["w"],
            "depth_m": spec["d"],
            "wall": spec["wall"],
            "roof": spec["roof"],
            "has_balcony": len(spec["balcony"]) > 0,
            "has_porch": spec["porch"],
            "triangles": tris,
        })
        objs.append(obj)
        print(f"EXPORTED {spec['name']}.glb ({tris} tris)")

    with open(os.path.join(BASE_DIR, "catalog_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    setup_showcase_and_render(objs)


if __name__ == "__main__":
    main()
