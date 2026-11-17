"""Render the original and PSX Mustang GLBs with identical Blender settings."""

import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def aim(obj, point):
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render(asset_dir, manifest, output):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(asset_dir / manifest["chassis"]["path"]))
    for corner, wheel in manifest["wheels"].items():
        existing = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(asset_dir / wheel["path"]))
        pivot = manifest["wheel_pivots"][corner]["center_metres"]
        for obj in set(bpy.context.scene.objects) - existing:
            if obj.parent is None:
                obj.location += Vector((pivot["x"], -pivot["z"], pivot["y"]))

    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.015))
    floor = bpy.data.materials.new("Studio floor")
    floor.diffuse_color = (0.16, 0.18, 0.21, 1)
    bpy.context.object.data.materials.append(floor)

    scene = bpy.context.scene
    scene.world = bpy.data.worlds.new("Studio")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.34, 0.38, 0.46, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    for position, power, size in [((2, 4, 6), 950, 5), ((-4, 1, 3), 550, 4), ((0, -5, 5), 1000, 4)]:
        bpy.ops.object.light_add(type="AREA", location=position)
        light = bpy.context.object
        light.data.energy = power
        light.data.size = size
        aim(light, (0, 0, 0.7))

    bpy.ops.object.camera_add(location=(5.9, 7.5, 3.2))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 5.8
    aim(camera, (0, 0, 0.75))
    scene.camera = camera
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 780
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


arguments = sys.argv[sys.argv.index("--") + 1:]
source, output = (Path(arg).resolve() for arg in arguments[:2])
manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
variants = arguments[2:] or ["original", "psx", "psx_dither"]
for name in variants:
    asset_dir = source if name == "original" else output / name
    render(asset_dir, manifest, output / f"{name}.png")
