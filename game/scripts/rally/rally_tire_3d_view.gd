class_name RallyTire3DView
extends RefCounted
## Utilidades compartidas para renderizar vistas 3D nativas de coche y neumáticos
## en SubViewports transparentes sin duplicar nodos pesados ni físicas.

const WHEELS := ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]
const HeldPreviewScript := preload("res://scripts/rally/rally_held_part_preview.gd")


static func create_viewport_container(
	dimensions: Vector2,
	ortho_size: float,
	camera_pos: Vector3,
	up_vector: Vector3,
	update_mode: SubViewport.UpdateMode = SubViewport.UPDATE_ONCE
) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.size = dimensions
	container.custom_minimum_size = dimensions
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.stretch = true

	var viewport := SubViewport.new()
	viewport.size = Vector2i(maxi(1, int(dimensions.x)), maxi(1, int(dimensions.y)))
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = update_mode
	container.add_child(viewport)

	var world := Node3D.new()
	world.name = "World"
	viewport.add_child(world)

	var camera := Camera3D.new()
	camera.name = "Camera"
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ortho_size
	camera.position = camera_pos
	camera.look_at_from_position(camera.position, Vector3.ZERO, up_vector)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-72.0, 24.0, 0.0)
	key_light.light_energy = 1.95
	world.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-35.0, -140.0, 0.0)
	fill_light.light_energy = 0.75
	world.add_child(fill_light)

	return container


static func create_vehicle_top_view(
	vehicle: Node3D,
	dimensions: Vector2,
	exclude_wheels: bool = false,
	copies_out: Array[MeshInstance3D] = [],
	update_mode: SubViewport.UpdateMode = SubViewport.UPDATE_ONCE
) -> SubViewportContainer:
	var container := create_viewport_container(
		dimensions,
		5.2,
		Vector3(0.0, 8.0, 0.0),
		Vector3.FORWARD,
		update_mode
	)
	var world := get_world(container)
	if is_instance_valid(vehicle) and world != null:
		copy_vehicle_body(vehicle, vehicle, world, exclude_wheels, copies_out)
	return container


static func create_wheel_view(
	vehicle: Node3D,
	wheel_index: int,
	tire_data: Dictionary,
	dimensions: Vector2,
	base_rotation: Vector3 = Vector3.ZERO,
	show_pedestal: bool = false,
	update_mode: SubViewport.UpdateMode = SubViewport.UPDATE_ONCE
) -> SubViewportContainer:
	var container := create_viewport_container(
		dimensions,
		0.74 if show_pedestal else 0.65,
		Vector3(0.0, 3.0, 0.0),
		Vector3.BACK,
		update_mode
	)
	var world := get_world(container)
	var pivot := Node3D.new()
	pivot.name = "ModelPivot"
	pivot.rotation = base_rotation
	world.add_child(pivot)
	populate_wheel_pivot(pivot, vehicle, wheel_index, tire_data, show_pedestal)
	return container


static func get_viewport(container: SubViewportContainer) -> SubViewport:
	if container == null or container.get_child_count() == 0:
		return null
	return container.get_child(0) as SubViewport


static func get_world(container: SubViewportContainer) -> Node3D:
	var vp := get_viewport(container)
	if vp == null or vp.get_child_count() == 0:
		return null
	return vp.get_child(0) as Node3D


static func get_pivot(container: SubViewportContainer) -> Node3D:
	var world := get_world(container)
	if world == null:
		return null
	return world.get_node_or_null("ModelPivot") as Node3D


static func refresh_viewport(container: SubViewportContainer) -> void:
	var vp := get_viewport(container)
	if vp != null and vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE


static func populate_wheel_pivot(
	pivot: Node3D,
	vehicle: Node3D,
	wheel_index: int,
	tire_data: Dictionary,
	show_pedestal: bool = false
) -> void:
	if pivot == null:
		return
	for child in pivot.get_children():
		pivot.remove_child(child)
		child.queue_free()
	if not is_instance_valid(vehicle):
		return
	var safe_idx := wheel_index if (wheel_index >= 0 and wheel_index < WHEELS.size()) else 0
	var wheel_node := vehicle.get_node_or_null(NodePath(WHEELS[safe_idx])) as Node3D
	if wheel_node == null:
		wheel_node = vehicle.get_node_or_null(NodePath(WHEELS[0])) as Node3D
	if wheel_node == null:
		return
	var state: Dictionary = (tire_data.get("state", {}) as Dictionary) if tire_data is Dictionary else {}
	var compound_id := str(tire_data.get("compound_id", RallyTireCompound.DEFAULT_ID)) if tire_data is Dictionary else RallyTireCompound.DEFAULT_ID
	var severity := maxf(float(state.get("wear_fraction", 0.0)), float(state.get("pressure_loss_fraction", 0.0)))
	var destroyed := float(state.get("carcass_failure", 0.0)) >= 0.99
	copy_wheel_meshes(wheel_node, wheel_node, pivot, severity, destroyed)
	if show_pedestal and not tire_data.is_empty():
		var ring_color := compound_ring_color(compound_id, destroyed)
		_add_compound_pedestal(pivot, ring_color)


static func compound_ring_color(compound_id: String, destroyed: bool = false) -> Color:
	if destroyed:
		return Color("#ef4444")
	var cat := RallyTireCompound.load_catalog()
	var data := RallyTireCompound.get_compound(cat, compound_id)
	var hex := str(data.get("visual_tread_color", "#22c55e"))
	return Color.from_string(hex, Color("#22c55e"))


static func make_slot_style(
	bg_color: Color,
	border_color: Color,
	border_width: int = 1,
	corner_radius: int = RallyUITheme.CORNER_RADIUS
) -> StyleBoxFlat:
	return RallyUITheme.make_flat_panel(bg_color, border_color, border_width, corner_radius)


static func create_drag_preview(
	vehicle: Node3D,
	wheel_index: int,
	tire_data: Dictionary,
	dimensions: Vector2 = Vector2(118.0, 118.0)
) -> Control:
	var preview := HeldPreviewScript.new()
	if is_instance_valid(vehicle):
		var view := create_wheel_view(
			vehicle,
			wheel_index,
			tire_data,
			dimensions,
			Vector3(0.22, 0.32, -0.10),
			true,
			SubViewport.UPDATE_ALWAYS
		)
		preview.model_view = view
		preview.pivot = get_pivot(view)
		preview.add_child(view)
	else:
		var cid := str(tire_data.get("compound_id", RallyTireCompound.DEFAULT_ID))
		var destroyed := float((tire_data.get("state", {}) as Dictionary).get("carcass_failure", 0.0)) >= 0.99
		var badge := Panel.new()
		var badge_size := Vector2(minf(dimensions.x, 76.0), minf(dimensions.y, 76.0))
		badge.size = badge_size
		badge.position = -badge_size * 0.5
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", make_slot_style(Color("#151f2c", 0.94), compound_ring_color(cid, destroyed), 3, 38))
		preview.add_child(badge)
	return preview


static func play_settle_animation(
	owner: Node,
	container: SubViewportContainer,
	base_rotation: Vector3 = Vector3.ZERO
) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(container):
		return
	var vp := get_viewport(container)
	var pivot := get_pivot(container)
	if pivot == null:
		return
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pivot.rotation = base_rotation + Vector3(0.18, 0.0, -0.14)
	var tween_host: Node = container if container.is_inside_tree() else owner
	var tween := tween_host.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "rotation", base_rotation, 0.28)
	if vp != null:
		var vp_id: int = vp.get_instance_id()
		tween.finished.connect(func():
			var target := instance_from_id(vp_id) as SubViewport
			if is_instance_valid(target):
				target.render_target_update_mode = SubViewport.UPDATE_ONCE
		)


static func copy_vehicle_body(
	node: Node,
	vehicle: Node3D,
	world: Node3D,
	exclude_wheels: bool,
	copies_out: Array[MeshInstance3D] = []
) -> void:
	if exclude_wheels and WHEELS.has(node.name):
		return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.is_visible_in_tree():
			var copy := _duplicate_mesh_node(mesh_node)
			world.add_child(copy)
			copy.transform = vehicle.global_transform.affine_inverse() * mesh_node.global_transform
			copies_out.append(copy)
	for child in node.get_children():
		copy_vehicle_body(child, vehicle, world, exclude_wheels, copies_out)


static func copy_wheel_meshes(
	node: Node,
	wheel_root: Node3D,
	pivot: Node3D,
	severity: float,
	destroyed: bool = false
) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.is_visible_in_tree():
			var copy := _duplicate_mesh_node(mesh_node)
			pivot.add_child(copy)
			copy.transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO) * (
				wheel_root.global_transform.affine_inverse() * mesh_node.global_transform
			)
			if destroyed:
				var bad_mat := StandardMaterial3D.new()
				bad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				bad_mat.albedo_color = Color(0.95, 0.16, 0.16, 0.34)
				copy.material_overlay = bad_mat
			elif severity > 0.05:
				var dmg_mat := StandardMaterial3D.new()
				dmg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dmg_mat.albedo_color = Color(1.0, 1.0 - clampf(severity, 0.0, 1.0), 0.0, 0.22)
				copy.material_overlay = dmg_mat
	for child in node.get_children():
		copy_wheel_meshes(child, wheel_root, pivot, severity, destroyed)


static func _duplicate_mesh_node(source: MeshInstance3D) -> MeshInstance3D:
	var copy := MeshInstance3D.new()
	copy.mesh = source.mesh
	copy.material_override = source.material_override
	for surface in source.mesh.get_surface_count():
		copy.set_surface_override_material(surface, source.get_surface_override_material(surface))
	return copy


static func _add_compound_pedestal(pivot: Node3D, ring_color: Color) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.305
	torus.outer_radius = 0.335
	torus.rings = 24
	torus.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(ring_color, 0.88)
	ring.material_override = mat
	ring.position = Vector3(0.0, -0.15, 0.0)
	pivot.add_child(ring)
