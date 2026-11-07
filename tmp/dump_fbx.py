import bpy, json, sys
fbx = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx, global_scale=100.0, use_custom_normals=True)
bpy.context.view_layer.update()
names = sorted(o.name for o in bpy.data.objects)
print("RT_OBJECTS_START")
print(json.dumps(names, indent=1))
print("RT_OBJECTS_END")
