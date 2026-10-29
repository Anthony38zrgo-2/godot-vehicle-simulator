class_name RallyStageVisualMaterialAdjuster
extends Node

const CUTOUT_MATERIAL_NAMES := [
	"grass",
	"russian_tree_plane",
	"forest_mixed_1",
	"forest_mixed_2",
	"forest_mixed_3",
	"forest_mixed_1_end_left",
	"forest_mixed_1_end_right",
	"bush_4",
	"audience_3",
	"audience_4",
	"fence_1_1",
	"fence_1_2",
	"fence_gate_1",
	"fence_metal",
	"string_red",
	"power_line_1",
	"power_line_cord",
	"polyn_1_wire",
	"terrain_field_1_",
]

@export var visual_root_path: NodePath
@export var alpha_scissor_threshold: float = 0.38

var adjusted_surface_count: int = 0


func _ready() -> void:
	var visual_root := get_node_or_null(visual_root_path)
	if visual_root == null:
		return
	adjust_node(visual_root)
	print("RALLY_STAGE_VISUAL_ADJUSTED surfaces=", adjusted_surface_count)


func adjust_node(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(surface_index)
			if material is BaseMaterial3D:
				adjust_material(material as BaseMaterial3D)
	for child in node.get_children():
		adjust_node(child)


func adjust_material(material: BaseMaterial3D) -> void:
	var material_name := material.resource_name.to_lower()
	if not CUTOUT_MATERIAL_NAMES.has(material_name):
		return
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = alpha_scissor_threshold
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	adjusted_surface_count += 1
