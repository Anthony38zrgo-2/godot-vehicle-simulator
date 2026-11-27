extends SceneTree

const Puddles := preload("res://scripts/rally/rally_puddles.gd")
const Channels := preload("res://scripts/rally/rally_river_channels.gd")
const Adjuster := preload("res://scripts/rally/rally_stage_visual_material_adjuster.gd")

const PUDDLE_SHADER := preload("res://shaders/water/water_puddle.gdshader")
const RIVER_SHADER := preload("res://shaders/water/water_river_ps2.gdshader")
const STATIC_WATER_SHADER := preload("res://shaders/water/water_static_lake.gdshader")

var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func _shader_has_uniform(shader: Shader, uniform_name: String) -> bool:
	if shader == null:
		return false
	for u in shader.get_shader_uniform_list():
		if str((u as Dictionary).get("name", "")) == uniform_name:
			return true
	return false


func _initialize() -> void:
	call_deferred("verify")


func verify() -> void:
	# 1. Verify all 3 shaders load and expose shared water detail uniforms.
	for entry in [
		["water_puddle.gdshader", PUDDLE_SHADER],
		["water_river_ps2.gdshader", RIVER_SHADER],
		["water_static_lake.gdshader", STATIC_WATER_SHADER],
	]:
		var sname: String = entry[0]
		var sh: Shader = entry[1]
		for uname in ["water_detail_tex", "detail_scale", "detail_strength", "detail_normal_strength", "detail_speed"]:
			check(_shader_has_uniform(sh, uname), "%s must expose uniform %s" % [sname, uname])

	# 2. Verify RallyPuddles binds water_detail_tex on generated patches.
	var world := Node3D.new()
	root.add_child(world)
	var road := StaticBody3D.new()
	road.name = "Collision_Road"
	road.set_meta("is_stage_road", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.2, 200)
	shape.shape = box
	road.add_child(shape)
	world.add_child(road)

	var moisture := Node.new()
	moisture.set_script(load("res://scripts/rally/rally_terrain_wetness.gd"))
	world.add_child(moisture)
	moisture.set_process(false)
	moisture.wetness = 1.0

	var puddles := Puddles.new()
	puddles.configure([Vector3(0, 0.1, -80), Vector3(0, 0.1, 80)], 731, null, moisture)
	world.add_child(puddles)
	await physics_frame
	await physics_frame
	check(not puddles.patches.is_empty(), "Puddles must generate test patches")
	if not puddles.patches.is_empty():
		var p_mat := puddles.patches[0].material as ShaderMaterial
		check(p_mat != null and p_mat.get_shader_parameter("water_detail_tex") != null, "Puddle material must bind water_detail_tex")

	# 3. Verify RallyRiverChannels binds water_detail_tex and dynamic marker on river surface.
	var river_mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	var river_base := StandardMaterial3D.new()
	river_base.resource_name = "river2_1"
	plane.surface_set_material(0, river_base)
	river_mesh_inst.mesh = plane
	world.add_child(river_mesh_inst)

	var rivers := Channels.new()
	root.add_child(rivers)
	var rch := rivers.add_test_channel({"id": "river_detail_test", "min_x": -5.0, "max_x": 5.0, "min_z": -5.0, "max_z": 5.0})
	rch["surfaces"] = ["river2_1"]
	rch["nodes"] = [river_mesh_inst]
	rivers._apply_materials(rch)
	var river_mat := river_mesh_inst.get_active_material(0) as ShaderMaterial
	check(river_mat != null and river_mat.shader == RIVER_SHADER, "River channel must override surface with RIVER_SHADER")
	if river_mat != null:
		check(river_mat.get_shader_parameter("water_detail_tex") != null, "River material must bind water_detail_tex")
		check(bool(river_mat.get_meta("rally_dynamic_water", false)), "River material must mark rally_dynamic_water")
		check(_shader_has_uniform(RIVER_SHADER, "rise_m"), "water_river_ps2.gdshader must expose uniform rise_m")
		rch["orig_y"] = [river_mesh_inst.position.y]
		rch["rise_m"] = 0.25
		rivers._update_render()
		check(absf(float(river_mat.get_shader_parameter("rise_m")) - 0.25) < 0.001, "River shader must receive rise_m uniform")
		check(absf(river_mesh_inst.position.y) < 0.0001, "River node position.y must remain unchanged so shared road meshes stay aligned")

	# 4. Verify RallyStageVisualMaterialAdjuster converts static lakes preserving color,
	# and leaves non-lake exclusions untouched.
	var lake_root := Node3D.new()
	world.add_child(lake_root)

	var lake_mi := MeshInstance3D.new()
	var lake_plane := PlaneMesh.new()
	var lake_mat := StandardMaterial3D.new()
	lake_mat.resource_name = "lake_test"
	lake_mat.albedo_color = Color(0.18, 0.24, 0.16, 0.77)
	lake_plane.surface_set_material(0, lake_mat)
	lake_mi.mesh = lake_plane
	lake_root.add_child(lake_mi)

	var excluded_instances: Array[MeshInstance3D] = []
	for ex_name in ["fin_lake_bank", "waterfall_1", "river1_1", "terrain_snow_river_1"]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var sm := StandardMaterial3D.new()
		sm.resource_name = ex_name
		pm.surface_set_material(0, sm)
		mi.mesh = pm
		lake_root.add_child(mi)
		excluded_instances.append(mi)

	var adjuster := Adjuster.new()
	adjuster.adjust_node(lake_root)
	adjuster.free()

	var converted := lake_mi.get_active_material(0) as ShaderMaterial
	check(converted != null and converted.shader == STATIC_WATER_SHADER, "lake_test must convert to STATIC_WATER_SHADER")
	if converted != null:
		check(converted.get_shader_parameter("water_detail_tex") != null, "Static lake material must bind water_detail_tex")
		var saved_col: Variant = converted.get_shader_parameter("base_color")
		check(saved_col is Color and (saved_col as Color).is_equal_approx(Color(0.18, 0.24, 0.16, 0.77)), "Static lake must preserve original albedo_color")
		var saved_alpha := float(converted.get_shader_parameter("base_alpha"))
		check(absf(saved_alpha - 0.77) < 0.005, "Static lake must preserve original alpha")

	for ex_mi in excluded_instances:
		var ex_mat := ex_mi.get_active_material(0)
		check(ex_mat is BaseMaterial3D, "Excluded surface %s must remain BaseMaterial3D" % ex_mi.mesh.surface_get_material(0).resource_name)

	check(Adjuster.is_static_water_candidate("water", "props_and_markers"), "Finland 'Water' material must match static water rule")

	# 5. Verify real Finland lake GLB material converts from alpha=0 cutout placeholder to static water shader.
	var finland_glb := "res://assets/rally/finland_stage2/finland_stage2_visual.glb"
	if ResourceLoader.exists(finland_glb):
		var packed := load(finland_glb) as PackedScene
		check(packed != null, "finland_stage2_visual.glb must load cleanly")
		if packed != null:
			var inst := packed.instantiate()
			world.add_child(inst)
			var fin_adjuster := Adjuster.new()
			fin_adjuster.adjust_node(inst)
			fin_adjuster.free()
			var found_water := false
			var water_converted := false
			var bank_kept_base := true
			var stack: Array[Node] = [inst]
			while not stack.is_empty():
				var cur: Node = stack.pop_back()
				if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
					var mi := cur as MeshInstance3D
					for si in mi.mesh.get_surface_count():
						var orig := mi.mesh.surface_get_material(si)
						if orig is BaseMaterial3D:
							var rname := (orig as BaseMaterial3D).resource_name.to_lower()
							if rname == "water":
								found_water = true
								var active := mi.get_active_material(si) as ShaderMaterial
								if active != null and active.shader == STATIC_WATER_SHADER and active.get_shader_parameter("water_detail_tex") != null:
									water_converted = true
							elif rname == "fin_lake_bank":
								if not (mi.get_active_material(si) is BaseMaterial3D):
									bank_kept_base = false
				for child in cur.get_children():
					stack.append(child)
			check(found_water and water_converted, "Finland Water surface must convert to STATIC_WATER_SHADER with water_detail_tex")
			check(bank_kept_base, "Finland fin_lake_bank must remain BaseMaterial3D")
			inst.queue_free()

	rivers.unbind()
	rivers.queue_free()
	print("WATER_DETAIL_CONTRACT ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
