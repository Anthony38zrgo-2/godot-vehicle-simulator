extends RefCounted

const ROOT := "res://assets/rally/raurastart_stage2/"
const SHADER := preload("res://assets/rally/raurastart_stage2/raura_mezcla.gdshader")
const SOURCES := {
	"road_tex": "grecia_calzada.png",
	"gravel_tex": "argentina-grava-12.png",
	"earth_tex": "argentina-tierra-10.png",
	"rock_tex": "argentina-roca-4.png",
	"cold_tex": "monte_carlo-roca-5.png",
	"snow_tex": "monte_carlo-nieve-30.png",
	"snow_mask": "nieve_sentinel.png",
}

func apply(root: Node) -> void:
	var textures := {}
	for key: String in SOURCES:
		textures[key] = load(ROOT + SOURCES[key])
		if textures[key] == null:
			push_error("Missing Raura pilot texture: " + SOURCES[key])
			return
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var mesh_name := str(child.name)
		var kind := 0 if mesh_name == "Road" else (1 if mesh_name.begins_with("Terrain_Dirt") else 2)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		for key: String in textures:
			mat.set_shader_parameter(key, textures[key])
		mat.set_shader_parameter("surface_kind", kind)
		if kind == 2:
			var source := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
			if source != null:
				mat.set_shader_parameter("satellite_tex", source.albedo_texture)
		mesh_instance.material_override = mat
