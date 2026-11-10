"""
Visual Multi-Angle Inspection Renderer using Blender Headless
Renders 4 angles per vehicle with Backface Culling enabled:
1. Front 3/4 view (Exterior front-left)
2. Rear 3/4 view (Exterior rear-right)
3. Cockpit interior view (From CockpitEye forward through dashboard/windshield)
4. Damage variant view (Damage mesh exterior)
Combines them into a 2x2 contact sheet per vehicle using Pillow.
"""

import json
import math
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
INSPECT_DIR = REPO / "tmp" / "glb_audit" / "visual_inspection"
INSPECT_DIR.mkdir(parents=True, exist_ok=True)

VEHICLE_DEFS = [
    {
        "id": "ford_escort_rs2000_1971",
        "chassis": REPO / "game" / "assets" / "rally" / "ford_escort_rs2000_1971" / "ford_escort_rs2000_1971_chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "ford_escort_rs2000_1971" / "damage" / "escort_damage.glb",
    },
    {
        "id": "lancia_fulvia",
        "chassis": REPO / "game" / "assets" / "rally" / "lancia_fulvia" / "lancia_fulvia_chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "lancia_fulvia" / "damage" / "fulvia_damage.glb",
    },
    {
        "id": "rt-alfa-giulia-gta",
        "chassis": REPO / "game" / "assets" / "rally" / "rt" / "rt-alfa-giulia-gta" / "chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "rt" / "rt-alfa-giulia-gta" / "damage" / "damage.glb",
    },
    {
        "id": "rt-alpine-a110",
        "chassis": REPO / "game" / "assets" / "rally" / "rt" / "rt-alpine-a110" / "chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "rt" / "rt-alpine-a110" / "damage" / "damage.glb",
    },
    {
        "id": "rt-fiat-abarth-1000",
        "chassis": REPO / "game" / "assets" / "rally" / "rt" / "rt-fiat-abarth-1000" / "chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "rt" / "rt-fiat-abarth-1000" / "damage" / "damage.glb",
    },
    {
        "id": "rt-lancia-stratos",
        "chassis": REPO / "game" / "assets" / "rally" / "rt" / "rt-lancia-stratos" / "chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "rt" / "rt-lancia-stratos" / "damage" / "damage.glb",
    },
    {
        "id": "rt-lotus-cortina",
        "chassis": REPO / "game" / "assets" / "rally" / "rt" / "rt-lotus-cortina" / "chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "rt" / "rt-lotus-cortina" / "damage" / "damage.glb",
    },
    {
        "id": "rt-mini-cooper-s",
        "chassis": REPO / "game" / "assets" / "rally" / "rt" / "rt-mini-cooper-s" / "chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "rt" / "rt-mini-cooper-s" / "damage" / "damage.glb",
    },
    {
        "id": "rt-opel-kadett",
        "chassis": REPO / "game" / "assets" / "rally" / "rt" / "rt-opel-kadett" / "chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "rt" / "rt-opel-kadett" / "damage" / "damage.glb",
    },
    {
        "id": "rt-saab-96-v4",
        "chassis": REPO / "game" / "assets" / "rally" / "rt" / "rt-saab-96-v4" / "chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "rt" / "rt-saab-96-v4" / "damage" / "damage.glb",
    },
    {
        "id": "rt-volvo-amazon",
        "chassis": REPO / "game" / "assets" / "rally" / "rt" / "rt-volvo-amazon" / "chassis.glb",
        "damage": REPO / "game" / "assets" / "rally" / "rt" / "rt-volvo-amazon" / "damage" / "damage.glb",
    },
]

# Blender python worker script
BLENDER_WORKER_SCRIPT = """
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
"""


def create_contact_sheet(vehicle_id: str, v_dir: Path):
    img1 = Image.open(v_dir / "1_front_three_quarter.png")
    img2 = Image.open(v_dir / "2_rear_three_quarter.png")
    img3 = Image.open(v_dir / "3_cockpit_view.png")
    img4 = Image.open(v_dir / "4_damage_view.png")

    w, h = img1.size
    sheet = Image.new("RGB", (w * 2, h * 2 + 80), color=(24, 24, 28))

    # Paste quadrants
    sheet.paste(img1, (0, 40))
    sheet.paste(img2, (w, 40))
    sheet.paste(img3, (0, h + 40))
    sheet.paste(img4, (w, h + 40))

    draw = ImageDraw.Draw(sheet)
    # Header title
    title = f"Visual Inspection Sheet: {vehicle_id} (Backface Culling Active)"
    draw.text((30, 10), title, fill=(240, 240, 245))

    # Labels for quadrants
    draw.text((20, 50), "[1] Exterior 3/4 Front", fill=(255, 230, 80))
    draw.text((w + 20, 50), "[2] Exterior 3/4 Rear", fill=(255, 230, 80))
    draw.text((20, h + 50), "[3] Cockpit Eye Interior", fill=(255, 230, 80))
    draw.text((w + 20, h + 50), "[4] Visual Damage State", fill=(255, 230, 80))

    sheet.save(v_dir / "contact_sheet.png")


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    worker_script_path = INSPECT_DIR / "blender_render_worker.py"
    worker_script_path.write_text(BLENDER_WORKER_SCRIPT, encoding="utf-8")

    jobs = []
    for item in VEHICLE_DEFS:
        v_out = INSPECT_DIR / item["id"]
        v_out.mkdir(parents=True, exist_ok=True)
        jobs.append(
            {
                "id": item["id"],
                "chassis": str(item["chassis"]),
                "damage": str(item["damage"]),
                "out_dir": str(v_out),
            }
        )

    jobs_path = INSPECT_DIR / "render_jobs.json"
    jobs_path.write_text(json.dumps(jobs, indent=2), encoding="utf-8")

    print(f"Starting visual multi-angle inspection for {len(jobs)} vehicles in Blender...")
    cmd = [
        "blender",
        "-b",
        "--factory-startup",
        "--python",
        str(worker_script_path),
        "--",
        str(jobs_path),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode != 0:
        print("Blender rendering worker failed:", proc.stderr, file=sys.stderr)
        sys.exit(1)

    print("Compositing 2x2 contact sheets with Pillow...")
    for item in VEHICLE_DEFS:
        v_dir = INSPECT_DIR / item["id"]
        create_contact_sheet(item["id"], v_dir)
        print(f"  ✓ Created contact sheet: {v_dir / 'contact_sheet.png'}")

    print("\nVisual inspection multi-angle rendering complete!")


if __name__ == "__main__":
    main()
