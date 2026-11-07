from pathlib import Path
import json

recipe_path = Path("tools/rally_trophy/recipes/rt-porsche-356b-2000gs.json")
data = json.loads(recipe_path.read_text(encoding="utf-8"))
data["interior"]["synthesize_roof"] = False
recipe_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("Updated recipe successfully")

be_path = Path("tools/rally_trophy/blender_export.py")
code = be_path.read_text(encoding="utf-8")

old_roof = """    # Derive an inward-facing lining from real roof faces, avoiding duplicate glass.
    lo, hi = world_bounds(body)
    roof_faces = [f.index for f in body.data.polygons
                  if all((body.matrix_world @ body.data.vertices[v].co).z >= hi[2] - 0.09 for v in f.vertices)
                  and (body.matrix_world.to_3x3() @ f.normal).z > 0.3]
    if roof_faces:"""

new_roof = """    # Derive an inward-facing lining from real roof faces, avoiding duplicate glass.
    lo, hi = world_bounds(body)
    roof_faces = [f.index for f in body.data.polygons
                  if all((body.matrix_world @ body.data.vertices[v].co).z >= hi[2] - 0.09 for v in f.vertices)
                  and (body.matrix_world.to_3x3() @ f.normal).z > 0.3]
    if roof_faces and rules.get("synthesize_roof", True):"""

assert old_roof in code, "old_roof not found in blender_export.py"
code = code.replace(old_roof, new_roof, 1)

old_cull = 'material.use_backface_culling = False if alpha or material.name == "interior_lo" else True'
new_cull = """is_interior_mat = material.name.lower() in ["windows", "interior_windows", "windshield_interior", "interior_hi", "cockpit", "meters", "rally trophy roof lining"]
        if is_interior_mat:
            material.use_backface_culling = True
        else:
            material.use_backface_culling = False if alpha or material.name == "interior_lo" else True"""

assert old_cull in code, "old_cull not found in blender_export.py"
code = code.replace(old_cull, new_cull, 1)

be_path.write_text(code, encoding="utf-8")
print("Updated blender_export.py successfully")
