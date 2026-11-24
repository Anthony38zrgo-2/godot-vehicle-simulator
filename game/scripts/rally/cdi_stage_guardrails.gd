extends Node3D
## Builds roadside metallic guardrails (same arm_1a/arm_1b/arm_1a_reverse visual &
## collision style as SS03/SS04) along abyss-facing switchback zones of SS01 and SS02.

const TEX_DIR := "res://assets/rally/CDI/asfalto_estepa/"
const HEIGHT_SCALE := 0.70
const RAIL_TOP_Y := 1.18 * HEIGHT_SCALE
const COLL_BOT_Y := 0.34 * HEIGHT_SCALE
const COLL_TOP_Y := 1.04 * HEIGHT_SCALE
const PANEL_LEN_M := 4.0
const SAMPLE_STEP_M := 2.0
const ROAD_EDGE_OFFSET_M := 3.35

# Switchback / serpentin zones per stage where cliff-facing edges get guardrails.
const SERPENTIN_ZONES := {
	"cdi_stage1": [
		[1320.0, 2060.0],
		[2320.0, 3160.0],
		[4020.0, 4660.0],
	],
	"cdi_stage2": [
		[380.0, 1520.0],
		[1880.0, 3260.0],
	],
}

var _materials := {}
var _runs: Array[Dictionary] = []


func build(stage_id: String, course: RallyStageProgress, mask: int, stream: RallyVisualSectorStream) -> void:
	var zones: Array = SERPENTIN_ZONES.get(stage_id, [])
	if zones.is_empty() or stream == null:
		return
	_ensure_materials()
	var space := get_world_3d().direct_space_state
	var dists := course.route_distances
	var pts := course.points
	var total := float(dists[-1])
	_runs.clear()
	var total_length := 0.0

	for zone in zones:
		var z0 := clampf(float(zone[0]), 12.0, total - 12.0)
		var z1 := clampf(float(zone[1]), 12.0, total - 12.0)
		for side: float in [-1.0, 1.0]:
			var sname := "left" if side < 0.0 else "right"
			var samples: Array[Dictionary] = []
			var pk := z0
			while pk <= z1:
				var sample := _probe_shoulder(pts, dists, pk, side, space, mask)
				samples.append(sample)
				pk += SAMPLE_STEP_M

			# Bridge small gaps (<= 24m) between exposed cliff runs for clean continuous rails
			var exposed: Array[bool] = []
			exposed.resize(samples.size())
			for idx in samples.size():
				exposed[idx] = bool(samples[idx]["exposed"])
			var max_gap_steps := int(round(24.0 / SAMPLE_STEP_M))
			var i := 0
			while i < exposed.size():
				if exposed[i]:
					var j := i + 1
					while j < exposed.size() and not exposed[j]:
						j += 1
					if j < exposed.size() and (j - i - 1) > 0 and (j - i - 1) <= max_gap_steps:
						var can_bridge := true
						for k in range(i + 1, j):
							if not bool(samples[k]["has_ground"]):
								can_bridge = false
								break
						if can_bridge:
							for k in range(i + 1, j):
								exposed[k] = true
					i = j
				else:
					i += 1

			# Extract contiguous runs >= 14m
			var first := 0
			while first < exposed.size():
				if not exposed[first]:
					first += 1
					continue
				var last := first
				while last + 1 < exposed.size() and exposed[last + 1]:
					last += 1
				var run_len := float(samples[last]["pk"]) - float(samples[first]["pk"])
				if run_len >= 14.0:
					# Extend up to 8m (4 steps) at each end so rails wrap smoothly into switchback rims
					var ext_first := first
					for _e in range(4):
						if ext_first > 0 and bool(samples[ext_first - 1]["has_ground"]):
							ext_first -= 1
						else:
							break
					var ext_last := last
					for _e in range(4):
						if ext_last + 1 < samples.size() and bool(samples[ext_last + 1]["has_ground"]):
							ext_last += 1
						else:
							break
					run_len = float(samples[ext_last]["pk"]) - float(samples[ext_first]["pk"])
					var run_pts: Array[Vector3] = []
					var run_pks: Array[float] = []
					for k in range(ext_first, ext_last + 1):
						run_pts.append(samples[k]["pos"] as Vector3)
						run_pks.append(float(samples[k]["pk"]))
					_smooth_heights(run_pts)
					_emit_guardrail_run(run_pts, run_pks, side, mask, stream)
					var mid_pt := run_pts[run_pts.size() / 2]
					_runs.append({
						"side": sname,
						"start_m": float(samples[ext_first]["pk"]),
						"end_m": float(samples[ext_last]["pk"]),
						"length_m": run_len,
						"mid_point": mid_pt,
					})
					total_length += run_len
				first = last + 1

	set_meta("runs", _runs)
	set_meta("total_length_m", total_length)
	print("CDI_GUARDRAILS_READY stage=", stage_id, " runs=", _runs.size(), " total_m=", "%.1f" % total_length)


func _ensure_materials() -> void:
	if not _materials.is_empty():
		return
	for layer in ["arm_1a", "arm_1b", "arm_1a_reverse"]:
		var tex := load(TEX_DIR + layer + ".png") as Texture2D
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_fog = true
		mat.roughness = 0.64
		_materials[layer] = mat


func _ray(space: PhysicsDirectSpaceState3D, mask: int, p: Vector3, reach: float = 25.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(
		p + Vector3.UP * reach, p - Vector3.UP * (reach + 35.0), mask)
	return space.intersect_ray(q)


func _probe_shoulder(pts: PackedVector3Array, dists: PackedFloat64Array, pk: float,
		side: float, space: PhysicsDirectSpaceState3D, mask: int) -> Dictionary:
	var i := clampi(dists.bsearch(pk), 1, pts.size() - 2)
	var center := pts[i - 1].lerp(pts[i], inverse_lerp(dists[i - 1], dists[i], pk))
	var heading := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 2, 0)]
	var fwd := Vector3(heading.x, 0.0, heading.z).normalized()
	var outward := fwd.cross(Vector3.UP) * side

	var curb_pos := center + outward * ROAD_EDGE_OFFSET_M
	var h0 := _ray(space, mask, curb_pos, 8.0)
	if h0.is_empty():
		return {"pk": pk, "pos": curb_pos, "has_ground": false, "exposed": false}

	var pos := Vector3(curb_pos.x, float(h0.position.y) - 0.03, curb_pos.z)
	var h_near := _ray(space, mask, center + outward * 8.2, 12.0)
	var h_far := _ray(space, mask, center + outward * 15.2, 18.0)
	var exposed := false
	if not h_near.is_empty() and not h_far.is_empty():
		var zc := float(h0.position.y)
		var zn := float(h_near.position.y)
		var zf := float(h_far.position.y)
		exposed = (zc - zn >= 1.3 and zc - zf >= 4.5 and zn - zf >= 2.0)
	return {"pk": pk, "pos": pos, "has_ground": true, "exposed": exposed}


func _smooth_heights(pts: Array[Vector3]) -> void:
	if pts.size() < 3:
		return
	var ys: Array[float] = []
	ys.resize(pts.size())
	for i in pts.size():
		ys[i] = pts[i].y
	for _pass in range(2):
		for i in range(1, pts.size() - 1):
			ys[i] = (ys[i - 1] + ys[i] * 2.0 + ys[i + 1]) * 0.25
	for i in pts.size():
		pts[i].y = ys[i]


func _emit_guardrail_run(pts: Array[Vector3], pks: Array[float], side: float,
		mask: int, stream: RallyVisualSectorStream) -> void:
	var start_pk := pks[0]
	var total_len := pks[-1] - start_pk
	var panel_count := maxi(3, int(round(total_len / PANEL_LEN_M)))
	var flip := side > 0.0

	# Build per-sector visual meshes + one collision ribbon for the run
	var sector_buckets := {}
	var coll_faces := PackedVector3Array()

	for panel in range(panel_count):
		var a := start_pk + total_len * float(panel) / float(panel_count)
		var b := start_pk + total_len * float(panel + 1) / float(panel_count)
		var style := "arm_1a" if panel == 0 else ("arm_1a_reverse" if panel == panel_count - 1 else "arm_1b")
		var pa := _interp_point(pts, pks, a)
		var pb := _interp_point(pts, pks, b)
		var mid := (pa + pb) * 0.5
		var sec_path := stream.sector_for_point(mid)
		if not sector_buckets.has(sec_path):
			sector_buckets[sec_path] = {"arm_1a": [], "arm_1b": [], "arm_1a_reverse": []}

		# Subdivide panel at intermediate knots so guardrail hugs tight switchbacks
		var knots: Array[float] = [a]
		for pk in pks:
			if pk > a + 0.15 and pk < b - 0.15:
				knots.append(pk)
		knots.append(b)

		var segs: Array = sector_buckets[sec_path][style]
		for k in range(knots.size() - 1):
			var k0 := knots[k]
			var k1 := knots[k + 1]
			var p0 := _interp_point(pts, pks, k0)
			var p1 := _interp_point(pts, pks, k1)
			var u0 := (k0 - a) / maxf(b - a, 0.01)
			var u1 := (k1 - a) / maxf(b - a, 0.01)
			segs.append([p0, p1, u0, u1, flip])

			# Collision triangles
			var c0 := p0 + Vector3.UP * COLL_BOT_Y
			var c1 := p1 + Vector3.UP * COLL_BOT_Y
			var c2 := p1 + Vector3.UP * COLL_TOP_Y
			var c3 := p0 + Vector3.UP * COLL_TOP_Y
			coll_faces.append_array([c0, c1, c2, c0, c2, c3])
			coll_faces.append_array([c0, c2, c1, c0, c3, c2])

	# Add real StaticBody3D barrier collision to the guardrail manager node
	if not coll_faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "GuardrailCollision_%s_%.0f" % ["L" if side < 0.0 else "R", start_pk]
		body.collision_layer = mask
		body.collision_mask = 0
		body.set_meta("collision_role", "barrier")
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(coll_faces)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		add_child(body)

	# Register streamed visual meshes per sector
	for sec_path in sector_buckets.keys():
		var bucket: Dictionary = sector_buckets[sec_path]
		stream.register_content(sec_path, _spawn_sector_rails.bind(bucket, start_pk, side))


func _interp_point(pts: Array[Vector3], pks: Array[float], pk: float) -> Vector3:
	if pk <= pks[0]:
		return pts[0]
	if pk >= pks[-1]:
		return pts[-1]
	var lo := 0
	var hi := pks.size() - 1
	while lo + 1 < hi:
		var mid := (lo + hi) >> 1
		if pks[mid] <= pk:
			lo = mid
		else:
			hi = mid
	var t := inverse_lerp(pks[lo], pks[hi], pk)
	return pts[lo].lerp(pts[hi], t)


func _spawn_sector_rails(parent: Node3D, bucket: Dictionary, start_pk: float, side: float) -> void:
	var mesh := ArrayMesh.new()
	var mats: Array[Material] = []
	for style in ["arm_1a", "arm_1b", "arm_1a_reverse"]:
		var segs: Array = bucket[style]
		if segs.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for seg in segs:
			var p0: Vector3 = seg[0]
			var p1: Vector3 = seg[1]
			var u0: float = seg[2]
			var u1: float = seg[3]
			var flip: bool = seg[4]
			var t0 := p0 + Vector3.UP * RAIL_TOP_Y
			var t1 := p1 + Vector3.UP * RAIL_TOP_Y
			var edge_dir := (p1 - p0).normalized()
			var n := Vector3.UP.cross(edge_dir)
			if flip:
				n = -n
			# Quad: bottom-left (p0), bottom-right (p1), top-right (t1), top-left (t0)
			# Note: PNG V=1 is bottom, V=0 is top in Godot UV space
			st.set_normal(n)
			st.set_uv(Vector2(u0, 1.0)); st.add_vertex(p0)
			st.set_uv(Vector2(u1, 1.0)); st.add_vertex(p1)
			st.set_uv(Vector2(u1, 0.0)); st.add_vertex(t1)

			st.set_normal(n)
			st.set_uv(Vector2(u0, 1.0)); st.add_vertex(p0)
			st.set_uv(Vector2(u1, 0.0)); st.add_vertex(t1)
			st.set_uv(Vector2(u0, 0.0)); st.add_vertex(t0)
		st.commit(mesh)
		mats.append(_materials[style])

	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Guardarrail_%s_%.0f" % ["L" if side < 0.0 else "R", start_pk]
	mi.mesh = mesh
	for s in mats.size():
		mi.set_surface_override_material(s, mats[s])
	parent.add_child(mi)
