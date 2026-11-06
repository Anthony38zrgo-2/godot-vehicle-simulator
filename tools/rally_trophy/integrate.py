from __future__ import annotations

import json
import os
import shutil
import tempfile
from pathlib import Path

from .common import REPO, within, read_json, write_json, safe_id


def registry_entry(recipe):
    identifier = safe_id(recipe["id"])
    return {"Id": identifier, "Assets": "rt/" + identifier, "Profile": "rt/" + identifier,
            "Scene": "rt/" + identifier, "Stage": "rt/" + identifier + "_stage",
            "Proving": "rt/" + identifier + "_proving", "Provenance": "HISTORICAL_PROVENANCE.json",
            "SoundBank": identifier, "ValidateSoundHashes": True, "DisplayName": recipe["display_name"]}


def write_scenes(recipe, payload, assets):
    identifier = safe_id(recipe["id"])
    scene_root = Path(payload) / "game/scenes/rally/rt"
    scene_root.mkdir(parents=True, exist_ok=True)
    asset = "res://assets/rally/rt/" + identifier + "/"
    ext = [("Script", "res://scripts/rally/rally_escort_vehicle.gd", "vehicle"),
           ("PackedScene", asset + "chassis.glb", "chassis"),
           ("Script", "res://scripts/rally/rally_vehicle_audio.gd", "audio"),
           ("Script", "res://scripts/rally/rally_cockpit_animation.gd", "cockpit"),
           ("Script", "res://scripts/rally/rally_vehicle_vfx.gd", "vfx"),
           ("Script", "res://scripts/rally/rally_escort_visual_damage.gd", "damage"),
           ("PackedScene", asset + "damage/damage.glb", "crash")]
    for key in ["front_left", "front_right", "rear_left", "rear_right"]:
        ext.append(("PackedScene", asset + "wheel_" + key + ".glb", key))
    for key in ["lights_damaged", "windows_damaged", "interior_windows_damaged"]:
        ext.append(("Texture2D", asset + "damage/" + key + ".png", key))
    damage_parts = ", ".join(json.dumps(part) for part in recipe.get("body_panels", ["body", "hood", "trunk"]) + ["interior"])
    scene = f'[gd_scene load_steps={len(ext) + 2} format=3]\n\n'
    scene += "\n".join(f'[ext_resource type="{kind}" path="{path}" id="{key}"]' for kind, path, key in ext)
    scene += f'''

[sub_resource type="PhysicsMaterial" id="surface"]
friction = 0.35
bounce = 0.0

[node name="Vehicle" type="RigidBody3D"]
collision_layer = 2
collision_mask = 1
physics_material_override = SubResource("surface")
can_sleep = false
continuous_cd = true
contact_monitor = true
max_contacts_reported = 8
script = ExtResource("vehicle")
rally_profile_path = "res://data/vehicles/rt/{identifier}/vehicle.json"
asset_manifest_path = "{asset}manifest.json"
rally_collision_path = "{asset}collision.json"
cockpit_camera_enabled = true

[node name="Chassis" parent="." instance=ExtResource("chassis")]

[node name="VisualDamage" type="Node3D" parent="."]
script = ExtResource("damage")
damage_meshes = ExtResource("crash")
damage_parts = PackedStringArray({damage_parts})
broken_light = ExtResource("lights_damaged")
broken_glass = ExtResource("windows_damaged")
broken_glass_inside = ExtResource("interior_windows_damaged")
'''
    front_z = assets["geometry"]["front_axle_z"] - 0.55
    track = assets["geometry"]["front_track"]
    for name, x in [("Left", -track * 0.43), ("Right", track * 0.43)]:
        scene += f'''
[node name="Headlight{name}" type="SpotLight3D" parent="VisualDamage"]
position = Vector3({x}, 0.45, {front_z})
visible = false
light_color = Color(1, 0.90, 0.73, 1)
light_energy = 6.0
spot_range = 95.0
spot_angle = 27.0
'''
    scene += '''
[node name="CockpitAnimation" type="Node" parent="."]
script = ExtResource("cockpit")
steering_wheel_axis = Vector3(0, 1, 0)

[node name="VehicleVFX" type="Node3D" parent="."]
script = ExtResource("vfx")
'''
    for key, name in zip(["front_left", "front_right", "rear_left", "rear_right"],
                         ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]):
        scene += f'''
[node name="{name}" type="Node3D" parent="."]

[node name="WheelVisual" type="Node3D" parent="{name}"]

[node name="WheelMesh" parent="{name}/WheelVisual" instance=ExtResource("{key}")]
'''
    scene += f'''
[node name="VehicleAudio" type="Node3D" parent="."]
script = ExtResource("audio")
vehicle_path = NodePath("..")
engine_bank_manifest_path = "res://sounds/banks/{identifier}/manifest.json"
'''
    (scene_root / (identifier + ".tscn")).write_text(scene, encoding="utf-8")
    # Compositional templates contain no per-car algorithms or physics constants.
    for template, suffix in [("stage_session.tscn", "_stage"), ("proving_session.tscn", "_proving")]:
        text = (Path(__file__).parent / "templates" / template).read_text(encoding="utf-8")
        text = text.replace("__VEHICLE_SCENE__", f"res://scenes/rally/rt/{identifier}.tscn")
        text = text.replace('team_id = "rally-trophy"', f'team_id = "{identifier}"')
        text = text.replace('team_name = "Rally Trophy"', 'team_name = ' + json.dumps(recipe["display_name"], ensure_ascii=False))
        (scene_root / (identifier + suffix + ".tscn")).write_text(text, encoding="utf-8")


def install(payload, recipe, repo=REPO, *, replace=False):
    """Publish after validation. Roll back every changed file if any step fails."""
    repo, payload = Path(repo).resolve(), Path(payload).resolve()
    identifier = safe_id(recipe["id"])
    source_game = payload / "game"
    prefixes = (f"assets/rally/rt/{identifier}/", f"data/vehicles/rt/{identifier}/",
                f"sounds/banks/{identifier}/")
    scenes = {f"scenes/rally/rt/{identifier}{suffix}.tscn" for suffix in ["", "_stage", "_proving"]}
    files = sorted(p for p in source_game.rglob("*") if p.is_file())
    if not files:
        raise ValueError("Empty payload")
    for path in files:
        relative = path.relative_to(source_game).as_posix()
        if relative not in scenes and not any(relative.startswith(prefix) for prefix in prefixes):
            raise ValueError(f"Unexpected payload destination: {relative}")
        target = within(repo / "game", relative)
        if target.exists() and not replace:
            raise FileExistsError(f"Existing car files require --replace: {target}")
    registry_path = repo / "game/data/vehicles/registry.json"
    registry = read_json(registry_path)
    if identifier in registry["vehicles"] and not replace:
        raise FileExistsError(f"Vehicle already registered: {identifier}")
    registry["vehicles"][identifier] = registry_entry(recipe)
    written = []
    (repo / "build").mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="rt-publish-", dir=repo / "build") as backup:
        try:
            for source in files:
                relative = source.relative_to(source_game)
                target = within(repo / "game", relative)
                saved = None
                if target.exists():
                    saved = within(backup, relative)
                    saved.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(target, saved)
                target.parent.mkdir(parents=True, exist_ok=True)
                temporary = target.with_name(target.name + ".rt-tmp")
                shutil.copy2(source, temporary)
                os.replace(temporary, target)
                written.append((target, saved))
            # Registry is the final commit point; default vehicle never changes.
            write_json(registry_path, registry)
        except Exception:
            for target, saved in reversed(written):
                if saved:
                    shutil.copy2(saved, target)
                else:
                    target.unlink(missing_ok=True)
            raise
    return registry_entry(recipe)
