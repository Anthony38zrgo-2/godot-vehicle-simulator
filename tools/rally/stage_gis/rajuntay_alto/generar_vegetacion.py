"""Export CDI billboard cards for Godot; pass -- bushes to export only shrubs."""
import sys
from pathlib import Path

import bpy

BASE = Path(__file__).resolve().parents[4] / "game/assets/rally"
GRASS = BASE / "grass/CDI"
SCATTER = BASE / "cdi_stage1/vegetacion"
BUSH_SOURCES = Path(__file__).with_name("arbustos_png")
BUSH_CARDS = (
    ("arbusto_beige_01", 0.90),
    ("arbusto_beige_02", 1.05),
    ("arbusto_verde_01", 0.85),
    ("arbusto_verde_02", 0.95),
    ("arbusto_verde_03", 0.90),
    ("cactus_01", 1.25),
)
CARDS = (
    ("scn_p07_x000_y224_80x32_sprite.png", 0.24),
    ("scn_p07_x000_y000_96x64_sprite.png", 0.25),
    ("scn_p08_x192_y160_64x64_sprite.png", 0.50),
    ("scn_p11_x192_y128_64x64_sprite.png", 1.00),
)


def cutout(image_path):
    material = bpy.data.materials.new(image_path.stem)
    material.use_nodes = True
    material.use_backface_culling = False
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 1
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(image_path))
    material.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    material.node_tree.links.new(tex.outputs["Alpha"], shader.inputs["Alpha"])
    return material, tex.image


def billboard_card(name, source, height):
    material, image = cutout(source)
    width = height * image.size[0] / image.size[1]
    half = width * 0.5
    vertices = [(-half, 0, 0), (half, 0, 0), (half, 0, height), (-half, 0, height)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], [(0, 1, 2, 3)])
    mesh.materials.append(material)
    uv = mesh.uv_layers.new()
    corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
    for loop in mesh.loops:
        uv.data[loop.index].uv = corners[loop.index]
    model = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(model)
    return model


def export(model, name):
    bpy.ops.object.select_all(action="DESELECT")
    model.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(SCATTER / (name + ".glb")), export_format="GLB",
                              use_selection=True)


def main(bushes_only):
    SCATTER.mkdir(parents=True, exist_ok=True)
    if not bushes_only:
        for index, (filename, height) in enumerate(CARDS):
            bpy.ops.wm.read_factory_settings(use_empty=True)
            name = f"pasto_{index + 1:02d}"
            export(billboard_card(name, GRASS / filename, height), name)
    for name, height in BUSH_CARDS:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        export(billboard_card(name, BUSH_SOURCES / (name + ".png"), height), name)


if __name__ == "__main__":
    main(sys.argv[-2:] == ["--", "bushes"])
