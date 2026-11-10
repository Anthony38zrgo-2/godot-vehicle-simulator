
import bpy, math, sys, json
from pathlib import Path
from mathutils import Vector, Euler

args = sys.argv[sys.argv.index('--') + 1:]
jobs_file = Path(args[0]).resolve()
jobs = json.loads(jobs_file.read_text(encoding='utf-8'))

for item in jobs:
    vid = item['id']
    chassis_path = str(Path(item['chassis']).resolve())
    damage_path = str(Path(item['damage']).resolve())
    out_dir = Path(item['out_dir']).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    # --- 1. RENDER HEALTHY CHASSIS (Front 3/4, Rear 3/4, Cockpit) ---
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=chassis_path)
    bpy.context.view_layer.update()

    # Enable backface culling on all materials
    for mat in bpy.data.materials:
        mat.use_backface_culling = True

    # Setup lights
    sun1 = bpy.data.lights.new('Sun1', 'SUN')
    sun1.energy = 4.0
    sun1_obj = bpy.data.objects.new('Sun1', sun1)
    bpy.context.collection.objects.link(sun1_obj)
    sun1_obj.rotation_euler = Euler((math.radians(50), math.radians(20), math.radians(45)))

    fill = bpy.data.lights.new('Fill', 'SUN')
    fill.energy = 1.8
    fill_obj = bpy.data.objects.new('Fill', fill)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = Euler((math.radians(-40), math.radians(-15), math.radians(-135)))

    # Setup camera
    cam_data = bpy.data.cameras.new('Cam')
    cam_obj = bpy.data.objects.new('Cam', cam_data)
    bpy.context.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj

    bpy.context.scene.render.resolution_x = 960
    bpy.context.scene.render.resolution_y = 540

    # 1. Front 3/4 View (Looking towards car center from front-left)
    cam_data.lens = 50.0
    cam_obj.location = Vector((-3.6, 4.4, 1.9))
    direction = Vector((0.0, 0.1, 0.55)) - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.render.filepath = str(out_dir / '1_front_three_quarter.png')
    bpy.ops.render.render(write_still=True)

    # 2. Rear 3/4 View (Looking from rear-right)
    cam_obj.location = Vector((3.6, -4.4, 1.9))
    direction = Vector((0.0, -0.1, 0.55)) - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.render.filepath = str(out_dir / '2_rear_three_quarter.png')
    bpy.ops.render.render(write_still=True)

    # 3. Cockpit View (From CockpitEye position looking forward)
    eye = bpy.data.objects.get('CockpitEye')
    if eye:
        cam_obj.location = eye.matrix_world.translation.copy()
    else:
        cam_obj.location = Vector((-0.3, -0.15, 1.15))
    cam_data.lens = 28.0
    look_target = cam_obj.location + Vector((0.05, 2.5, -0.25))
    direction = look_target - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.render.filepath = str(out_dir / '3_cockpit_view.png')
    bpy.ops.render.render(write_still=True)

    # --- 2. RENDER DAMAGE VARIANT (Damage 3/4 View) ---
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=damage_path)
    bpy.context.view_layer.update()

    for mat in bpy.data.materials:
        mat.use_backface_culling = True

    sun_dmg = bpy.data.lights.new('SunDmg', 'SUN')
    sun_dmg.energy = 4.0
    sun_dmg_obj = bpy.data.objects.new('SunDmg', sun_dmg)
    bpy.context.collection.objects.link(sun_dmg_obj)
    sun_dmg_obj.rotation_euler = Euler((math.radians(50), math.radians(20), math.radians(45)))

    fill_dmg = bpy.data.lights.new('FillDmg', 'SUN')
    fill_dmg.energy = 1.8
    fill_dmg_obj = bpy.data.objects.new('FillDmg', fill_dmg)
    bpy.context.collection.objects.link(fill_dmg_obj)
    fill_dmg_obj.rotation_euler = Euler((math.radians(-40), math.radians(-15), math.radians(-135)))

    cam_dmg_data = bpy.data.cameras.new('CamDmg')
    cam_dmg_obj = bpy.data.objects.new('CamDmg', cam_dmg_data)
    bpy.context.collection.objects.link(cam_dmg_obj)
    bpy.context.scene.camera = cam_dmg_obj
    cam_dmg_data.lens = 50.0
    cam_dmg_obj.location = Vector((-3.6, 4.4, 1.9))
    direction = Vector((0.0, 0.1, 0.55)) - cam_dmg_obj.location
    cam_dmg_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()

    bpy.context.scene.render.resolution_x = 960
    bpy.context.scene.render.resolution_y = 540
    bpy.context.scene.render.filepath = str(out_dir / '4_damage_view.png')
    bpy.ops.render.render(write_still=True)

    print(f'RENDERED_4_ANGLES: {vid}')
