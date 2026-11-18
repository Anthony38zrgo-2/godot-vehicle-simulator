"""Convert CDI's original sprites and both rock packs to stage props."""
import json
import re
import subprocess
import sys
from pathlib import Path

import bpy
from mathutils import Vector

BASE = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE))
from generar_vegetacion import cutout

SOURCE = BASE.parents[3] / "game/assets/rally/CDI"
TARGET = SOURCE.parent / "cdi_stage1/props"
INDEX = {"people": [], "animals": [], "rocks": []}
ANIMAL_HEIGHT = {"ani_cow": 1.35, "ani_shp1": 0.82, "ani_shp2": 0.82, "ani_shp3": 0.82,
                 "argentina-animal-1": 1.35, "argentina-caballo-2": 2.35, "argentina-caballo-3": 2.35}


def save(model, kind, name, **metadata):
    path = TARGET / (name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    model.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True)
    INDEX[kind].append(dict(file=path.name, **metadata))


def card(source, height):
    mat, image = cutout(source)
    width, pixels_high = image.size
    rgba = tuple(image.pixels)
    filled = [index for index in range(width * pixels_high) if rgba[index * 4 + 3] >= 0.5]
    left, right = min(i % width for i in filled), max(i % width for i in filled) + 1
    low, high = min(i // width for i in filled), max(i // width for i in filled) + 1
    half = 0.5 * height * (right - left) / (high - low)
    mesh = bpy.data.meshes.new(source.stem)
    mesh.from_pydata([(-half, 0, 0), (half, 0, 0), (half, 0, height), (-half, 0, height)],
                     [], [(0, 1, 2, 3)])
    mesh.materials.append(mat)
    uv = mesh.uv_layers.new()
    for index, (u, v) in enumerate([(left, low), (right, low), (right, high), (left, high)]):
        uv.data[index].uv = (u / width, v / pixels_high)
    model = bpy.data.objects.new(source.stem, mesh)
    bpy.context.collection.objects.link(model)
    return model


def rock_material(name, diffuse):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.95
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(diffuse), check_existing=True)
    material.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    return material


def rocks(fbx, diffuse, prefix):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(fbx))
    models = sorted((o for o in bpy.context.scene.objects if o.type == "MESH"), key=lambda o: o.name)
    assert models, f"No rock meshes in {fbx}"
    material = rock_material(prefix, diffuse)
    for model in models:
        points = [model.matrix_world @ vertex.co for vertex in model.data.vertices]
        low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
        high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
        center = Vector(((low.x+high.x)/2, (low.y+high.y)/2, low.z))
        size = max(high - low)
        model.parent = None
        model.matrix_world.identity()
        for vertex, point in zip(model.data.vertices, points):
            vertex.co = (point - center) / size
        model.data.materials.clear()
        model.data.materials.append(material)
        for face in model.data.polygons:
            face.material_index = 0
        name = prefix + "_" + re.sub(r"\W+", "_", model.name.lower())
        save(model, "rocks", name)


def main():
    TARGET.mkdir(parents=True, exist_ok=True)
    for folder, kind in (("personas", "people"), ("animales", "animals")):
        for source in sorted((SOURCE / folder).glob("*.png")):
            bpy.ops.wm.read_factory_settings(use_empty=True)
            human = kind == "people"
            use = "-espectador-" in source.stem if human else "caballo" not in source.stem
            height = 1.74 if human else ANIMAL_HEIGHT[source.stem]
            save(card(source, height), kind, source.stem, scatter=use)
    first = SOURCE / "stones/low-poly-rock-pack"
    second = SOURCE / "stones/low-poly-stones"
    archive = second / "source/Stones.rar"
    unpacked = BASE / "output/rocas_fuente"
    unpacked.mkdir(parents=True, exist_ok=True)
    subprocess.run(["tar", "-xf", str(archive), "-C", str(unpacked)], check=True)
    rocks(first / "source/rock_pack.fbx", first / "textures/rock_generic_diffuse.jpeg", "cascajo")
    rocks(unpacked / "Stones.FBX", second / "textures/Stones_albedo.jpeg", "piedra")
    (TARGET / "index.json").write_text(json.dumps(INDEX, indent=2) + "\n", encoding="utf8")
    print("CDI_PROPS", {name: len(items) for name, items in INDEX.items()})


if __name__ == "__main__":
    main()
