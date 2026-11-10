import bpy
import math

def render_wheel(glb_path, out_png):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    # Add camera
    cam_data = bpy.data.cameras.new("Camera")
    cam_obj = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    
    # Place camera looking at wheel from outside: wheel center is (0,0,0)
    # Wheel outer face is in -X
    cam_obj.location = (-0.8, 0.0, 0.0)
    cam_obj.rotation_euler = (0, math.radians(-90), 0)
    
    # Add light
    light_data = bpy.data.lights.new(name="Light", type='SUN')
    light_data.energy = 3.0
    light_obj = bpy.data.objects.new(name="Light", object_data=light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.location = (-1, 0, 1)
    light_obj.rotation_euler = (0, math.radians(-45), 0)
    
    # Set render settings
    bpy.context.scene.render.resolution_x = 512
    bpy.context.scene.render.resolution_y = 512
    bpy.context.scene.render.filepath = out_png
    bpy.context.scene.render.image_settings.file_format = 'PNG'
    
    bpy.ops.render.render(write_still=True)
    print(f"Rendered {out_png}")

render_wheel('game/assets/rally/rt/rt-lotus-cortina/wheel_front_left.glb', 'd:/rust-godot-vehicle-simulator/tmp/render_cortina_wheel.png')
