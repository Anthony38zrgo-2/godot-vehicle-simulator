class_name RallyRiverChannels
extends Node3D

## Controlador de cauces dinámicos de Kenia (alcance de etapa).
## Mantiene por sección un incremento `rise_m` y expone la cota resultante a
## malla (desplazamiento vertical uniforme que conserva la pendiente
## longitudinal original) y a consultas físicas. El cálculo de nivel es
## independiente del render: `advance()` integra el modelo de primer orden y
## `_update_render()` publica el mismo estado a malla y a física.
##
## Fuente de lluvia: en competición se consulta el clima EN EL PROGRESO FIJO
## DEL CAUCE (`provider.liquid_rain_at_distance(progress_m)`); la posición del
## coche no modifica el clima asignado a ningún río. En práctica se usa la
## selección de clima de la sesión en un único adaptador
## (`practice_rain_for_choice`). La nieve queda fuera de la escorrentía.

const DATA_PATH := "res://data/rally/kenya_rivers.json"
const SNAPSHOT_VERSION := 1
const RIVER_SHADER := preload("res://scripts/rally/rally_river.gdshader")
const BUCKET_CELL_M := 8.0
const MAX_BAKE_SAMPLES := 4096

var stage_id: String = ""
var valid: bool = false
var error: String = ""
var diagnostics: Array = []
var channels: Array = []
var provider = null
var tca_node: Node = null
var practice_choice: String = "random"
var practice_rain_override: float = -1.0
var initial_state: Dictionary = {}

# channel runtime: {
#  id, kind, active, pilot, surfaces, progress_m, max_rise_m, reference_rain_mm_h,
#  tau_rise_s, tau_drain_s, activation_threshold_mm_h, flow_dir, edge_feather_m,
#  drag_scale, rainy_start_fraction, settle_tolerance_m,
#  base_cx, base_cz, base_b0, base_gx, base_gz,
#  min_x, min_z, max_x, max_z, rise_m, target_m, last_rain_mm_h,
#  nodes: Array[MeshInstance3D], orig_y: Array[float],
#  override_info: Array (mesh, surface_idx, prev_material),
#  materials: Array[ShaderMaterial], tris: Array (a,b,c Vector2),
#  buckets: Dictionary, bed_tex: ImageTexture, bed_min_y, bed_max_y,
#  bed_res, bed_valid: PackedByteArray, bed_heights: PackedFloat32Array,
# }


static func practice_rain_for_choice(choice: String) -> float:
	## Adaptador único práctica -> mm/h de lluvia LÍQUIDA.
	## Cubre exactamente las opciones que expone la práctica
	## (soleado/nublado/lluvia/aleatorio + alias de single_stage).
	match choice.strip_edges().to_lower():
		"sunny", "soleado", "clear", "despejado":
			return 0.0
		"cloudy", "nublado", "overcast", "cubierto", "partly_cloudy", "random", "aleatorio":
			return 0.0
		"drizzle", "llovizna":
			return 0.95
		"light_precipitation", "light_rain", "lluvia", "rain", "light":
			return 2.5
		"medium_precipitation", "medium_rain":
			return 5.75
		"heavy_precipitation", "heavy_rain", "tormenta", "storm":
			return 15.0
		"mist_fog", "fog", "niebla":
			return 0.2
	return 0.0


static func is_finite_number(v: Variant) -> bool:
	if v is float or v is int:
		return is_finite(float(v))
	return false


func _log_channel(channel_id: String, message: String) -> void:
	diagnostics.append({"channel": channel_id, "message": message})
	push_warning("RallyRiverChannels[%s]: %s" % [channel_id, message])


func configure(for_stage_id: String, visual_root: Node, weather_provider, choice: String = "random", tca = null) -> bool:
	stage_id = for_stage_id
	provider = weather_provider
	practice_choice = choice
	tca_node = tca
	channels.clear()
	diagnostics.clear()
	error = ""
	if not FileAccess.file_exists(DATA_PATH):
		error = "Sin datos de cauces: " + DATA_PATH
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		error = "JSON inválido: " + DATA_PATH
		return false
	var doc: Dictionary = parsed
	if int(doc.get("format_version", 0)) != 1:
		error = "Versión de datos no soportada"
		return false
	var route_total := _route_total_m()
	for cfg in (doc.get("channels", []) as Array):
		if not cfg is Dictionary:
			continue
		if str((cfg as Dictionary).get("stage_id", "")) != for_stage_id:
			continue
		_register_channel((cfg as Dictionary).duplicate(true), visual_root, route_total)
	_resolve_instance_ownership()
	for ch in channels:
		if bool((ch as Dictionary).get("active", false)) and not ((ch as Dictionary).get("nodes", []) as Array).is_empty():
			_apply_materials((ch as Dictionary))
	valid = true
	return true


func _read_footprint(ch: Dictionary, cfg: Dictionary) -> void:
	## La huella máxima la delimitan las orillas verificadas (datos), no el
	## AABB de toda la malla: permite subdividir un río largo por geometría.
	var fp: Variant = cfg.get("footprint", null)
	if fp is Dictionary and (fp as Dictionary).has("min_x"):
		ch["min_x"] = float((fp as Dictionary)["min_x"])
		ch["min_z"] = float((fp as Dictionary)["min_z"])
		ch["max_x"] = float((fp as Dictionary)["max_x"])
		ch["max_z"] = float((fp as Dictionary)["max_z"])
		ch["has_footprint"] = true
	else:
		ch["has_footprint"] = false


func _inside_footprint(ch: Dictionary, x: float, z: float, margin: float) -> bool:
	if not bool(ch.get("has_footprint", false)):
		return true
	return x >= float(ch["min_x"]) - margin and x <= float(ch["max_x"]) + margin \
		and z >= float(ch["min_z"]) - margin and z <= float(ch["max_z"]) + margin


func _resolve_instance_ownership() -> void:
	## Varias secciones pueden compartir MeshInstances: cada instancia la
	## desplaza un solo cauce (el de la huella que contiene su centroide; si
	## no, el más cercano). La cobertura física ya va particionada por
	## huella, así que no hay doble desplazamiento ni escalones por ello.
	var owned := {}
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		var keep_nodes: Array = []
		var keep_orig: Array = []
		var nodes: Array = (ch as Dictionary).get("nodes", [])
		var orig: Array = (ch as Dictionary).get("orig_y", [])
		for i in mini(nodes.size(), orig.size()):
			var mi := nodes[i] as MeshInstance3D
			if mi == null or not is_instance_valid(mi):
				continue
			var key := mi.get_instance_id()
			var center: Vector3 = (mi as Node3D).global_transform.origin
			if owned.has(key):
				continue
			if _instance_claimed_by_other(ch, mi, center):
				continue
			owned[key] = str((ch as Dictionary).get("id", ""))
			keep_nodes.append(mi)
			keep_orig.append(orig[i])
		(ch as Dictionary)["nodes"] = keep_nodes
		(ch as Dictionary)["orig_y"] = keep_orig


func _instance_claimed_by_other(me: Dictionary, mi: MeshInstance3D, center: Vector3) -> bool:
	var best: Dictionary = me
	var best_d := INF
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		if not ((ch as Dictionary).get("nodes", []) as Array).has(mi):
			continue
		var d := INF
		if bool((ch as Dictionary).get("has_footprint", false)):
			var cx := (float((ch as Dictionary)["min_x"]) + float((ch as Dictionary)["max_x"])) * 0.5
			var cz := (float((ch as Dictionary)["min_z"]) + float((ch as Dictionary)["max_z"])) * 0.5
			if _inside_footprint((ch as Dictionary), center.x, center.z, 0.0):
				d = -1.0
			else:
				d = Vector2(center.x - cx, center.z - cz).length()
		else:
			d = 0.0
		if d < best_d:
			best_d = d
			best = (ch as Dictionary)
	return best != me


func _route_total_m() -> float:
	if provider != null and "route_total_m" in provider:
		return maxf(float(provider.route_total_m), 1.0)
	return 1.0


func _resolve_progress_m(cfg: Dictionary, route_total: float) -> float:
	var explicit: Variant = cfg.get("climate_progress_m", null)
	if is_finite_number(explicit):
		return maxf(float(explicit), 0.0)
	var frac: float = clampf(float(cfg.get("climate_progress_fraction", 0.0)), 0.0, 1.0)
	return frac * maxf(route_total, 1.0)


func _register_channel(cfg: Dictionary, visual_root: Node, route_total: float) -> void:
	var cid := str(cfg.get("id", ""))
	if cid.is_empty():
		_log_channel("?", "canal sin ID: se omite")
		return
	var required_numbers := ["max_rise_m", "reference_rain_mm_h", "tau_rise_s", "tau_drain_s"]
	for key in required_numbers:
		if not is_finite_number(cfg.get(key, null)) or float(cfg.get(key, 0.0)) <= 0.0:
			_log_channel(cid, "parámetro inválido '%s': se conserva material y se desactiva consulta dinámica" % key)
			return
	var max_rise := float(cfg["max_rise_m"])
	var ref_rain := float(cfg["reference_rain_mm_h"])
	var tau_rise := float(cfg["tau_rise_s"])
	var tau_drain := float(cfg["tau_drain_s"])
	if max_rise > 2.0:
		_log_channel(cid, "max_rise_m fuera de rango físico (<=2m): se desactiva")
		return
	var threshold: Variant = cfg.get("activation_threshold_mm_h", null)
	if threshold != null and (not is_finite_number(threshold) or float(threshold) < 0.0):
		_log_channel(cid, "umbral inválido: se desactiva")
		return
	var ch := {
		"id": cid,
		"kind": str(cfg.get("kind", "permanent")),
		"active": bool(cfg.get("active", false)),
		"pilot": bool(cfg.get("pilot", false)),
		"surfaces": (cfg.get("surfaces", []) as Array).duplicate(),
		"progress_m": _resolve_progress_m(cfg, route_total),
		"progress_fraction": clampf(float(cfg.get("climate_progress_fraction", 0.0)), 0.0, 1.0),
		"level_anchor": (cfg.get("level_anchor", {}) as Dictionary).duplicate(),
		"max_rise_m": max_rise,
		"reference_rain_mm_h": ref_rain,
		"tau_rise_s": tau_rise,
		"tau_drain_s": tau_drain,
		"activation_threshold_mm_h": threshold,
		"flow_dir": Vector2(0.3, 0.95),
		"edge_feather_m": maxf(float(cfg.get("edge_feather_m", 0.06)), 0.005),
		"drag_scale": maxf(float(cfg.get("drag_scale", 1.25)), 0.1),
		"rainy_start_fraction": clampf(float(cfg.get("rainy_start_fraction", 0.5)), 0.0, 1.0),
		"settle_tolerance_m": maxf(float(cfg.get("settle_tolerance_m", 0.001)), 0.0001),
		"base_cx": 0.0, "base_cz": 0.0, "base_b0": 0.0, "base_gx": 0.0, "base_gz": 0.0,
		"min_x": INF, "min_z": INF, "max_x": -INF, "max_z": -INF,
		"rise_m": 0.0, "target_m": 0.0, "last_rain_mm_h": 0.0,
		"nodes": [], "orig_y": [], "override_info": [], "materials": [],
		"tris": [], "buckets": {},
		"bed_tex": null, "bed_min_y": 0.0, "bed_max_y": 1.0,
		"bed_res": int(cfg.get("bed_bake_resolution", 32)),
		"bed_valid": PackedByteArray(), "bed_heights": PackedFloat32Array(),
		"slope": cfg.get("base_slope", {}),
	}
	var flow: Variant = cfg.get("flow_dir", [0.3, 0.95])
	if flow is Array and (flow as Array).size() >= 2:
		var fv := Vector2(float((flow as Array)[0]), float((flow as Array)[1]))
		if fv.length_squared() > 0.0001:
			ch["flow_dir"] = fv.normalized()
	if not bool(ch["active"]):
		# Registrado pero inactivo (pendiente de validación): sin consulta.
		ch["rise_m"] = 0.0
		channels.append(ch)
		return
	if visual_root == null:
		_log_channel(cid, "sin raíz visual: material intacto, consulta desactivada")
		ch["active"] = false
		channels.append(ch)
		return
	_discover_meshes(ch, visual_root)
	if (ch["nodes"] as Array).is_empty():
		_log_channel(cid, "superficies %s no encontradas en escena: material intacto, consulta desactivada" % str(ch["surfaces"]))
		ch["active"] = false
		channels.append(ch)
		return
	_read_footprint(ch, cfg)
	_fit_base_plane(ch)
	_build_triangle_index(ch)
	_bake_bed_field(ch)
	channels.append(ch)
	# Diagnóstico para el inventario del piloto: huella, cota base y clima.
	print("RALLY_RIVER_READY id=", cid, " progress_m=", snappedf(float(ch["progress_m"]), 0.1),
		" base_y=", snappedf(float(ch["base_b0"]), 0.001),
		" footprint_x=[", snappedf(float(ch["min_x"]), 0.1), ",", snappedf(float(ch["max_x"]), 0.1),
		"] z=[", snappedf(float(ch["min_z"]), 0.1), ",", snappedf(float(ch["max_z"]), 0.1),
		"] tris=", (ch["tris"] as Array).size())


func add_test_channel(cfg: Dictionary) -> Dictionary:
	## Canal sintético para contratos headless (sin GLB): huella rectangular
	## con plano de base plano o inclinado y 2 triángulos de cobertura.
	var ch := {
		"id": str(cfg.get("id", "test_channel")),
		"kind": str(cfg.get("kind", "permanent")),
		"active": true, "pilot": false,
		"surfaces": [], "progress_m": float(cfg.get("progress_m", 0.0)),
		"max_rise_m": float(cfg.get("max_rise_m", 0.45)),
		"reference_rain_mm_h": float(cfg.get("reference_rain_mm_h", 12.0)),
		"tau_rise_s": float(cfg.get("tau_rise_s", 45.0)),
		"tau_drain_s": float(cfg.get("tau_drain_s", 120.0)),
		"activation_threshold_mm_h": cfg.get("activation_threshold_mm_h", null),
		"flow_dir": Vector2(0.3, 0.95),
		"edge_feather_m": 0.06,
		"drag_scale": 1.25,
		"rainy_start_fraction": 0.5,
		"settle_tolerance_m": 0.001,
		"base_cx": 0.0, "base_cz": 0.0,
		"base_b0": float(cfg.get("base_y", 0.0)),
		"base_gx": 0.0, "base_gz": 0.0,
		"min_x": -5.0, "min_z": -5.0, "max_x": 5.0, "max_z": 5.0,
		"rise_m": 0.0, "target_m": 0.0, "last_rain_mm_h": 0.0,
		"nodes": [], "orig_y": [], "override_info": [], "materials": [],
		"tris": [], "buckets": {},
		"bed_tex": null, "bed_min_y": -1.0, "bed_max_y": 1.0,
		"bed_res": 8, "bed_valid": PackedByteArray(), "bed_heights": PackedFloat32Array(),
		"slope": {},
	}
	if cfg.has("min_x"):
		ch["min_x"] = float(cfg["min_x"])
		ch["min_z"] = float(cfg["min_z"])
		ch["max_x"] = float(cfg["max_x"])
		ch["max_z"] = float(cfg["max_z"])
	ch["base_cx"] = (float(ch["min_x"]) + float(ch["max_x"])) * 0.5
	ch["base_cz"] = (float(ch["min_z"]) + float(ch["max_z"])) * 0.5
	if cfg.has("grade_x"):
		ch["base_gx"] = float(cfg["grade_x"])
	if cfg.has("grade_z"):
		ch["base_gz"] = float(cfg["grade_z"])
	var a := Vector2(float(ch["min_x"]), float(ch["min_z"]))
	var b := Vector2(float(ch["max_x"]), float(ch["min_z"]))
	var c := Vector2(float(ch["max_x"]), float(ch["max_z"]))
	var d := Vector2(float(ch["min_x"]), float(ch["max_z"]))
	ch["tris"] = [[a, b, c], [a, c, d]]
	_build_buckets(ch)
	channels.append(ch)
	valid = true
	return ch


func _discover_meshes(ch: Dictionary, visual_root: Node) -> void:
	var wanted := {}
	for s in (ch["surfaces"] as Array):
		wanted[str(s).to_lower()] = true
	var stack: Array = [visual_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			var mesh := mi.mesh
			for si in mesh.get_surface_count():
				# El material activo puede ser ya un ShaderMaterial de otro
				# cauce hermano: cotejar también el material base de la malla.
				var base := mesh.surface_get_material(si)
				var found := false
				if base is BaseMaterial3D and wanted.has(str((base as BaseMaterial3D).resource_name).to_lower()):
					found = true
				else:
					var mat := mi.get_active_material(si)
					if mat is BaseMaterial3D and wanted.has(str((mat as BaseMaterial3D).resource_name).to_lower()):
						found = true
				if found:
					if not (ch["nodes"] as Array).has(mi):
						(ch["nodes"] as Array).append(mi)
						(ch["orig_y"] as Array).append(mi.position.y)
		for child in node.get_children():
			stack.append(child)


func _collect_water_vertices(ch: Dictionary) -> Array:
	var pts: Array = []
	var wanted := {}
	for s in (ch["surfaces"] as Array):
		wanted[str(s).to_lower()] = true
	for mi in (ch["nodes"] as Array):
		var inst := mi as MeshInstance3D
		if inst == null or inst.mesh == null:
			continue
		var mesh := inst.mesh
		var gt := inst.global_transform
		for si in mesh.get_surface_count():
			var base := mesh.surface_get_material(si)
			var hit_name := ""
			if base is BaseMaterial3D:
				hit_name = str((base as BaseMaterial3D).resource_name).to_lower()
			else:
				var mat := inst.get_active_material(si)
				if mat is BaseMaterial3D:
					hit_name = str((mat as BaseMaterial3D).resource_name).to_lower()
			if not wanted.has(hit_name):
				continue
			var arrays := mesh.surface_get_arrays(si)
			if arrays == null or arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 512)
			var i := 0
			while i < verts.size() and pts.size() < MAX_BAKE_SAMPLES:
				pts.append(gt * verts[i])
				i += step
	return pts


func _fit_base_plane(ch: Dictionary) -> void:
	## Altura base interpolada: plano y = b0 + gx*(x-cx) + gz*(z-cz) por
	## mínimos cuadrados sobre vértices de agua. Conserva la pendiente
	## longitudinal de la malla original; el incremento del cauce se suma.
	var pts := _collect_water_vertices(ch)
	if bool(ch.get("has_footprint", false)):
		var inside: Array = []
		for p in pts:
			if _inside_footprint(ch, (p as Vector3).x, (p as Vector3).z, 4.0):
				inside.append(p)
		pts = inside
	if pts.is_empty():
		return
	var cx := 0.0
	var cz := 0.0
	var cy := 0.0
	for p in pts:
		cx += (p as Vector3).x
		cz += (p as Vector3).z
		cy += (p as Vector3).y
	cx /= pts.size()
	cz /= pts.size()
	cy /= pts.size()
	var sxx := 0.0
	var sxz := 0.0
	var szz := 0.0
	var sxy := 0.0
	var szy := 0.0
	for p in pts:
		var dx := (p as Vector3).x - cx
		var dz := (p as Vector3).z - cz
		var dy := (p as Vector3).y - cy
		sxx += dx * dx
		sxz += dx * dz
		szz += dz * dz
		sxy += dx * dy
		szy += dz * dy
	var det := sxx * szz - sxz * sxz
	var gx := 0.0
	var gz := 0.0
	if absf(det) > 0.000001:
		gx = (sxy * szz - szy * sxz) / det
		gz = (sxx * szy - sxz * sxy) / det
	ch["base_cx"] = cx
	ch["base_cz"] = cz
	ch["base_b0"] = cy
	ch["base_gx"] = clampf(gx, -0.25, 0.25)
	ch["base_gz"] = clampf(gz, -0.25, 0.25)
	if ch.has("level_anchor"):
		# Anclar el plano al nivel medido en el vado: exacto donde pisan las
		# ruedas; la pendiente de la malla se conserva alrededor.
		var an: Dictionary = ch["level_anchor"]
		var px := float(an.get("x", cx))
		var pz := float(an.get("z", cz))
		var py := float(an.get("y", cy))
		var plane_at := cy + float(ch["base_gx"]) * (px - cx) + float(ch["base_gz"]) * (pz - cz)
		ch["base_b0"] = cy + (py - plane_at)
	if bool(ch.get("has_footprint", false)):
		return
	ch["min_x"] = INF
	ch["min_z"] = INF
	ch["max_x"] = -INF
	ch["max_z"] = -INF
	for p in pts:
		ch["min_x"] = minf(float(ch["min_x"]), (p as Vector3).x)
		ch["min_z"] = minf(float(ch["min_z"]), (p as Vector3).z)
		ch["max_x"] = maxf(float(ch["max_x"]), (p as Vector3).x)
		ch["max_z"] = maxf(float(ch["max_z"]), (p as Vector3).z)


func base_level_at(ch: Dictionary, x: float, z: float) -> float:
	return float(ch["base_b0"]) + float(ch["base_gx"]) * (x - float(ch["base_cx"])) + float(ch["base_gz"]) * (z - float(ch["base_cz"]))


func surface_level_at(ch: Dictionary, x: float, z: float) -> float:
	return base_level_at(ch, x, z) + float(ch["rise_m"])


func _build_triangle_index(ch: Dictionary) -> void:
	var wanted := {}
	for s in (ch["surfaces"] as Array):
		wanted[str(s).to_lower()] = true
	var tris: Array = []
	for mi in (ch["nodes"] as Array):
		var inst := mi as MeshInstance3D
		if inst == null or inst.mesh == null:
			continue
		var mesh := inst.mesh
		var gt := inst.global_transform
		for si in mesh.get_surface_count():
			var base := mesh.surface_get_material(si)
			var hit_name := ""
			if base is BaseMaterial3D:
				hit_name = str((base as BaseMaterial3D).resource_name).to_lower()
			else:
				var mat := inst.get_active_material(si)
				if mat is BaseMaterial3D:
					hit_name = str((mat as BaseMaterial3D).resource_name).to_lower()
			if not wanted.has(hit_name):
				continue
			var arrays := mesh.surface_get_arrays(si)
			if arrays == null or arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var to_global := func(vi: int) -> Vector3: return gt * verts[vi]
			var push_tri := func(pa: Vector3, pb: Vector3, pc: Vector3) -> void:
				# Cobertura particionada por huella: cada triángulo lo cubre
				# el cauce de su centroide (franja común de 4 m en el borde).
				var cx := (pa.x + pb.x + pc.x) / 3.0
				var cz := (pa.z + pb.z + pc.z) / 3.0
				if not _inside_footprint(ch, cx, cz, 4.0):
					return
				tris.append([Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), Vector2(pc.x, pc.z)])
			if idx.is_empty():
				var t := 0
				while t + 2 < verts.size() and tris.size() < 22000:
					push_tri.call(to_global.call(t), to_global.call(t + 1), to_global.call(t + 2))
					t += 3
			else:
				var t := 0
				while t + 2 < idx.size() and tris.size() < 22000:
					push_tri.call(to_global.call(idx[t]), to_global.call(idx[t + 1]), to_global.call(idx[t + 2]))
					t += 3
	ch["tris"] = tris
	if tris.is_empty():
		_log_channel(str(ch.get("id", "?")), "huella sin cobertura de triángulos: material intacto, consulta desactivada")
		ch["active"] = false
		ch["nodes"] = []
		return
	_build_buckets(ch)


func _build_buckets(ch: Dictionary) -> void:
	var buckets := {}
	for ti in (ch["tris"] as Array).size():
		var tri: Array = (ch["tris"] as Array)[ti]
		var minx := minf(minf((tri[0] as Vector2).x, (tri[1] as Vector2).x), (tri[2] as Vector2).x)
		var maxx := maxf(maxf((tri[0] as Vector2).x, (tri[1] as Vector2).x), (tri[2] as Vector2).x)
		var minz := minf(minf((tri[0] as Vector2).y, (tri[1] as Vector2).y), (tri[2] as Vector2).y)
		var maxz := maxf(maxf((tri[0] as Vector2).y, (tri[1] as Vector2).y), (tri[2] as Vector2).y)
		for cx in range(floori(minx / BUCKET_CELL_M), floori(maxx / BUCKET_CELL_M) + 1):
			for cz in range(floori(minz / BUCKET_CELL_M), floori(maxz / BUCKET_CELL_M) + 1):
				var key := Vector2i(cx, cz)
				if not buckets.has(key):
					buckets[key] = []
				(buckets[key] as Array).append(ti)
	ch["buckets"] = buckets


static func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 0.0000001:
		return false
	var l1 := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / d
	var l2 := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / d
	var l3 := 1.0 - l1 - l2
	return l1 >= -0.001 and l2 >= -0.001 and l3 >= -0.001


func _inside_coverage(ch: Dictionary, x: float, z: float) -> bool:
	# Huella máxima delimitada por orillas verificadas: admite superficies
	# cóncavas (triángulos, no rectángulo) y distingue áreas solapadas en
	# altura vía el plano de base por cauce.
	if x < float(ch["min_x"]) or x > float(ch["max_x"]) or z < float(ch["min_z"]) or z > float(ch["max_z"]):
		return false
	var buckets: Dictionary = ch["buckets"]
	if buckets.is_empty():
		return true
	var key := Vector2i(floori(x / BUCKET_CELL_M), floori(z / BUCKET_CELL_M))
	if not buckets.has(key):
		return false
	var p := Vector2(x, z)
	for ti in (buckets[key] as Array):
		var tri: Array = (ch["tris"] as Array)[int(ti)]
		if _point_in_tri(p, tri[0], tri[1], tri[2]):
			return true
	return false


func _bake_bed_field(ch: Dictionary) -> void:
	## Campo de altura del lecho sobre la huella: rejilla local con máscara de
	## validez y altura en metros. El tablero de puentes se excluye del
	## horneado (se conserva para la consulta de contacto del coche).
	var res := maxi(8, int(ch.get("bed_res", 32)))
	var space = _space()
	var minx := float(ch["min_x"])
	var minz := float(ch["min_z"])
	var maxx := float(ch["max_x"])
	var maxz := float(ch["max_z"])
	if not is_finite(minx) or maxx <= minx:
		return
	var heights := PackedFloat32Array()
	var mask := PackedByteArray()
	heights.resize(res * res)
	mask.resize(res * res)
	var bed_min := INF
	var bed_max := -INF
	var base := float(ch["base_b0"])
	for gz in res:
		for gx in res:
			var idx := gz * res + gx
			var x := lerpf(minx, maxx, (float(gx) + 0.5) / float(res))
			var z := lerpf(minz, maxz, (float(gz) + 0.5) / float(res))
			var h := base - 0.25
			var ok := true
			if space != null:
				var query := PhysicsRayQueryParameters3D.create(
					Vector3(x, base + 8.0, z), Vector3(x, base - 8.0, z), 1)
				var hit: Dictionary = space.intersect_ray(query)
				if hit.is_empty():
					ok = false
				else:
					var collider: Object = hit.get("collider")
					var cname := str((collider as Node).name) if collider is Node else ""
					var hy := float((hit.get("position", Vector3(x, h, z)) as Vector3).y)
					# Tablero de puente: la lámina pasa por debajo; no hornear.
					if cname.to_lower().contains("bridge") and hy > base - 0.15:
						ok = false
					else:
						h = hy
			heights[idx] = h
			mask[idx] = 1 if ok else 0
			if ok:
				bed_min = minf(bed_min, h)
				bed_max = maxf(bed_max, h)
	var valid_count := 0
	for i in mask.size():
		if mask[i] == 1:
			valid_count += 1
	if valid_count < int(float(res * res) * 0.05):
		# Sin horneado útil (p. ej. sin colisión bajo la huella): lecho
		# uniforme bajo la base para no romper la lámina.
		for i in heights.size():
			heights[i] = base - 0.25
			mask[i] = 1
		bed_min = base - 0.5
		bed_max = base + 0.1
	elif bed_min >= bed_max:
		bed_min = base - 0.5
		bed_max = base + 0.1
	ch["bed_min_y"] = bed_min
	ch["bed_max_y"] = bed_max
	ch["bed_heights"] = heights
	ch["bed_valid"] = mask
	var img := Image.create(res, res, false, Image.FORMAT_RG8)
	for gz in res:
		for gx in res:
			var idx := gz * res + gx
			var r := clampf((heights[idx] - bed_min) / maxf(bed_max - bed_min, 0.001), 0.0, 1.0)
			img.set_pixel(gx, gz, Color(r, 1.0 if mask[idx] == 1 else 0.0, 0.0, 1.0))
	ch["bed_tex"] = ImageTexture.create_from_image(img)


func _space() -> PhysicsDirectSpaceState3D:
	if not is_inside_tree():
		return null
	var world := get_world_3d()
	if world == null:
		return null
	return world.direct_space_state


func _apply_materials(ch: Dictionary) -> void:
	for mi in (ch["nodes"] as Array):
		var inst := mi as MeshInstance3D
		if inst == null or inst.mesh == null:
			continue
		var mesh := inst.mesh
		for si in mesh.get_surface_count():
			var mat := inst.get_active_material(si)
			if not (mat is BaseMaterial3D):
				continue
			var wanted := false
			for s in (ch["surfaces"] as Array):
				if str((mat as BaseMaterial3D).resource_name).to_lower() == str(s).to_lower():
					wanted = true
					break
			if not wanted:
				continue
			# Sustituir el material solo en superficies registradas: no dibujar
			# a la vez la lámina importada y la de cobertura.
			var sm := ShaderMaterial.new()
			sm.shader = RIVER_SHADER
			(ch["override_info"] as Array).append([inst, si, mat])
			inst.set_surface_override_material(si, sm)
			(ch["materials"] as Array).append(sm)
	_update_channel_material(ch)


func _update_channel_material(ch: Dictionary) -> void:
	var min2 := Vector2(float(ch["min_x"]), float(ch["min_z"]))
	var size2 := Vector2(maxf(float(ch["max_x"]) - float(ch["min_x"]), 0.5), maxf(float(ch["max_z"]) - float(ch["min_z"]), 0.5))
	for sm in (ch["materials"] as Array):
		var m := sm as ShaderMaterial
		if m == null:
			continue
		m.set_shader_parameter("footprint_min", min2)
		m.set_shader_parameter("footprint_size", size2)
		m.set_shader_parameter("bed_tex", ch.get("bed_tex", null))
		m.set_shader_parameter("bed_min_y", float(ch.get("bed_min_y", 0.0)))
		m.set_shader_parameter("bed_max_y", float(ch.get("bed_max_y", 1.0)))
		m.set_shader_parameter("edge_feather_m", float(ch.get("edge_feather_m", 0.06)))
		m.set_shader_parameter("flow_dir", ch.get("flow_dir", Vector2(0.3, 0.95)))
		m.set_shader_parameter("rain", clampf(float(ch.get("last_rain_mm_h", 0.0)) / 10.0, 0.0, 1.0))


func liquid_rain_now(progress_m: float) -> float:
	if provider != null and bool(provider.get("calendar_active")):
		if provider.has_method("liquid_rain_at_distance"):
			return maxf(float(provider.call("liquid_rain_at_distance", progress_m)), 0.0)
		# Respaldo: reglas del controlador existente sobre el estado mezclado.
		var st: Dictionary = provider.surface.blended_state_at_distance(progress_m)
		return _liquid_from_state(st)
	if practice_rain_override >= 0.0:
		return practice_rain_override
	return practice_rain_for_choice(practice_choice)


static func _liquid_from_state(st: Dictionary) -> float:
	## La nieve queda fuera de la escorrentía de esta entrega. El mixto sin
	## fracción líquida se trata explícito: 60% líquido (igual que el modelo
	## de superficie: precip_in = precip*0.6 + nieve).
	var climate: Dictionary = st.get("climate", {})
	var precip := maxf(float(climate.get("precipitation_mm_h", 0.0)), 0.0)
	match str(st.get("precipitation_kind", "none")):
		"rain":
			return precip
		"mixed":
			return precip * 0.6
	return 0.0


func target_for(ch: Dictionary, rain_mm_h: float) -> float:
	var threshold: Variant = ch.get("activation_threshold_mm_h", null)
	if threshold != null and rain_mm_h < float(threshold):
		return 0.0
	return float(ch["max_rise_m"]) * clampf(rain_mm_h / float(ch["reference_rain_mm_h"]), 0.0, 1.0)


func refresh_render() -> void:
	_update_render()


func rebind_provider(new_provider, tca = null) -> void:
	## Tras reconfigurar el clima (nueva especial), re-resuelve el progreso
	## fijo de cada cauce sobre la ruta actual sin perder el nivel acumulado.
	provider = new_provider
	tca_node = tca
	var total := _route_total_m()
	for ch in channels:
		if (ch as Dictionary).has("progress_fraction"):
			(ch as Dictionary)["progress_m"] = clampf(float((ch as Dictionary)["progress_fraction"]), 0.0, 1.0) * maxf(total, 1.0)


func advance(dt_s: float) -> void:
	## Avanza todos los cauces activos según el tiempo SIMULADO.
	## Llamar solo cuando la sesión/carrera avanza (no en pausa, reglaje,
	## carga ni resultados). Aplica pasos acotados independientes del FPS.
	if dt_s <= 0.0:
		return
	var remaining := dt_s
	while remaining > 0.001:
		var h := minf(remaining, 5.0)
		_step(h)
		remaining -= h
	_update_render()


func _step(h: float) -> void:
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		var rain := liquid_rain_now(float((ch as Dictionary).get("progress_m", 0.0)))
		(ch as Dictionary)["last_rain_mm_h"] = rain
		var target := target_for((ch as Dictionary), rain)
		(ch as Dictionary)["target_m"] = target
		var rise := float((ch as Dictionary).get("rise_m", 0.0))
		var tau := float((ch as Dictionary).get("tau_rise_s", 45.0)) if target > rise else float((ch as Dictionary).get("tau_drain_s", 120.0))
		tau = maxf(tau, 0.5)
		rise = lerpf(rise, target, 1.0 - exp(-h / tau))
		# Redondear a la cota base dentro de una tolerancia pequeña para no
		# dejar residuos al cabo del drenaje.
		if target <= 0.0 and rise < float((ch as Dictionary).get("settle_tolerance_m", 0.001)):
			rise = 0.0
		(ch as Dictionary)["rise_m"] = clampf(rise, 0.0, float((ch as Dictionary).get("max_rise_m", 0.45)))


func _update_render() -> void:
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		var rise := float((ch as Dictionary).get("rise_m", 0.0))
		var nodes: Array = (ch as Dictionary).get("nodes", [])
		var orig: Array = (ch as Dictionary).get("orig_y", [])
		for i in mini(nodes.size(), orig.size()):
			var mi := nodes[i] as MeshInstance3D
			if is_instance_valid(mi):
				mi.position.y = float(orig[i]) + rise
		_update_channel_material((ch as Dictionary))


func sample_contact(world_position: Vector3) -> Dictionary:
	## Consulta de solo lectura: busca por huella con índice espacial y
	## consulta la altura de la lámina en XZ. Usa ÚNICAMENTE el contacto ya
	## resuelto por la rueda en Jolt (`world_position` = punto de contacto).
	## Dentro de una zona válida y mojada devuelve
	## max(0, surface_y - contact_y) * 1000 en mm. El puente queda seco
	## mientras el contacto esté sobre la lámina (contacto por encima).
	var best := {"depth_mm": 0.0, "surface_y": -INF, "channel_id": "", "drag_scale": 0.0, "wet": false}
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		if float((ch as Dictionary).get("rise_m", 0.0)) <= 0.0005 and float((ch as Dictionary).get("target_m", 0.0)) <= 0.0:
			# Nivel base permanente: la lámina base también moja (ríos
			# permanentes conservan su nivel en seco).
			pass
		if not _inside_coverage((ch as Dictionary), world_position.x, world_position.z):
			continue
		var surface_y := surface_level_at((ch as Dictionary), world_position.x, world_position.z)
		var depth := maxf(0.0, surface_y - world_position.y) * 1000.0
		if depth > float(best.get("depth_mm", 0.0)):
			best = {"depth_mm": depth, "surface_y": surface_y, "channel_id": str((ch as Dictionary).get("id", "")), "drag_scale": float((ch as Dictionary).get("drag_scale", 1.25)), "wet": depth > 0.001}
	return best


func initialize_levels() -> void:
	## Condición inicial determinista: nivel base en seco y una fracción
	## calibrada del objetivo en un inicio lluvioso. Documentada por perfil
	## (`rainy_start_fraction`). El nivel acumulado se conserva al reanudar
	## vía snapshot.
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		var rain := liquid_rain_now(float((ch as Dictionary).get("progress_m", 0.0)))
		(ch as Dictionary)["last_rain_mm_h"] = rain
		var target := target_for((ch as Dictionary), rain)
		(ch as Dictionary)["target_m"] = target
		if rain < 0.4:
			(ch as Dictionary)["rise_m"] = 0.0
		else:
			(ch as Dictionary)["rise_m"] = target * float((ch as Dictionary).get("rainy_start_fraction", 0.5))
	initial_state = snapshot().get("channels", {})
	_update_render()


func snapshot() -> Dictionary:
	var per := {}
	for ch in channels:
		per[str((ch as Dictionary).get("id", ""))] = float((ch as Dictionary).get("rise_m", 0.0))
	return {"version": SNAPSHOT_VERSION, "stage_id": stage_id, "channels": per}


func restore_snapshot(data: Dictionary) -> void:
	## Partidas antiguas o IDs ausentes se inicializan como en el paso 4
	## (determinista). Versión validada; diagnósticos por cauce.
	if data.is_empty() or int(data.get("version", 0)) != SNAPSHOT_VERSION:
		initialize_levels()
		return
	var per: Dictionary = data.get("channels", {})
	for ch in channels:
		var cid := str((ch as Dictionary).get("id", ""))
		if per.has(cid) and is_finite_number(per[cid]):
			(ch as Dictionary)["rise_m"] = clampf(float(per[cid]), 0.0, float((ch as Dictionary).get("max_rise_m", 0.45)))
		else:
			var rain := liquid_rain_now(float((ch as Dictionary).get("progress_m", 0.0)))
			(ch as Dictionary)["rise_m"] = 0.0 if rain < 0.4 else target_for((ch as Dictionary), rain) * float((ch as Dictionary).get("rainy_start_fraction", 0.5))
	_update_render()


func store_initial() -> void:
	initial_state = snapshot().get("channels", {})


func restore_initial() -> void:
	restore_snapshot({"version": SNAPSHOT_VERSION, "stage_id": stage_id, "channels": initial_state})


func unbind() -> void:
	## Desconecta el proveedor del vehículo antes de liberar mallas y datos.
	for ch in channels:
		for entry in ((ch as Dictionary).get("override_info", []) as Array):
			var mi := (entry as Array)[0] as MeshInstance3D
			var si := int((entry as Array)[1])
			var prev: Material = (entry as Array)[2]
			if is_instance_valid(mi):
				mi.set_surface_override_material(si, prev)
		(ch as Dictionary)["override_info"] = []
		(ch as Dictionary)["materials"] = []
	provider = null
	tca_node = null


func active_channel_count() -> int:
	var n := 0
	for ch in channels:
		if bool((ch as Dictionary).get("active", false)):
			n += 1
	return n


func rise_of(channel_id: String) -> float:
	for ch in channels:
		if str((ch as Dictionary).get("id", "")) == channel_id:
			return float((ch as Dictionary).get("rise_m", 0.0))
	return 0.0


func level_of(channel_id: String, x: float, z: float) -> float:
	for ch in channels:
		if str((ch as Dictionary).get("id", "")) == channel_id:
			return surface_level_at((ch as Dictionary), x, z)
	return 0.0
