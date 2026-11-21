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
const WATER_DETAIL_TEX := preload("res://assets/rally/water/water_detail.jpg")
const BUCKET_CELL_M := 8.0
const MAX_BAKE_SAMPLES := 4096
const MAX_FIT_SAMPLES := 16384
# Elevación de render de la capa de agua respecto a la lámina importada.
# Solo para ganar el test de profundidad; no cuenta en la profundidad.
const WATER_RENDER_BIAS_M := 0.05

var use_rust_backend: bool = true
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
# Mallas importadas por instance_id (para la partición por cauce).
var _mesh_registry: Dictionary = {}
var _rust_rivers: RefCounted = null
var _rust_rises: PackedFloat32Array = PackedFloat32Array()

# channel runtime: {
#  id, kind, active, pilot, surfaces, progress_m, max_rise_m, reference_rain_mm_h,
#  tau_rise_s, tau_drain_s, activation_threshold_mm_h, flow_dir, edge_feather_m,
#  drag_scale, rainy_start_fraction, settle_tolerance_m,
#  base_cx, base_cz, base_b0, base_gx, base_gz,
#  min_x, min_z, max_x, max_z, rise_m, target_m, last_rain_mm_h,
#  nodes: Array[MeshInstance3D], orig_y: Array[float],
#  claimed_surfaces: Dictionary (instance_id -> Array[int] de surface_idx),
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
	# 1) Geometría por cauce sobre la malla importada: plano base, índice de
	# triángulos (física) y lecho horneado (corte de la lámina).
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		if ((ch as Dictionary).get("nodes", []) as Array).is_empty():
			continue
		_prepare_channel_geometry((ch as Dictionary))
	# 2) Partir la geometría de agua por cauce: cada cauce recibe solo los
	# triángulos que moja y el resto conserva el material importado.
	_partition_water_surfaces()
	_resolve_instance_ownership()
	# 3) Material dinámico sobre las mallas propias de cada cauce.
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		if ((ch as Dictionary).get("nodes", []) as Array).is_empty():
			continue
		_apply_materials((ch as Dictionary))
	_sync_channels_to_rust()
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


func _partition_water_surfaces() -> void:
	## Prepara una CAPA de agua dinámica por cauce sobre la lámina importada.
	##
	## La lámina importada (la cinta de río que trae el GLB) se conserva tal
	## cual: es la superficie real del agua y con ella el cauce se ve river
	## en todo su recorrido. Encima, cada cauce dibuja su propia capa con el
	## shader de río, que solo pinta donde el lecho está por debajo de la
	## lámina (las hondonadas: vados y canales). Así el río seco conserva su
	## aspecto original y solo la parte con agua real se anima y reacciona a
	## la lluvia.
	##
	## Antes la capa sustituía al material importado de toda la superficie,
	## así que el shader (que descarta donde no hay agua) dejaba el río en
	## negro fuera de la huella del cauce: de ahí que se viera "seco de
	## golpe" en tramos enteros.
	##
	## Reparto de triángulos por huella (centroide, franja común de 4 m; a
	## igualdad, el cauce más cercano). Un cauce sin huella que lo contenga
	## no aporta capa, y sus triángulos quedan solo con la lámina importada.
	var groups := {}
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		var claimed: Dictionary = (ch as Dictionary).get("claimed_surfaces", {})
		for key in claimed.keys():
			for si in (claimed[key] as Array):
				var gkey := "%d:%d" % [int(key), int(si)]
				if not groups.has(gkey):
					groups[gkey] = {"instance_id": int(key), "surface": int(si), "owners": []}
				((groups[gkey] as Dictionary)["owners"] as Array).append(ch as Dictionary)
	for gkey in groups.keys():
		var g: Dictionary = groups[gkey]
		var owners: Array = g["owners"]
		var inst: MeshInstance3D = _mesh_registry.get(int(g["instance_id"]), null)
		if inst == null or not is_instance_valid(inst):
			continue
		_partition_surface(inst, int(g["surface"]), owners)


func _partition_surface(inst: MeshInstance3D, si: int, owners: Array) -> void:
	## Capa de agua por cauce sobre la lámina importada.
	##
	## La lámina importada (la cinta de río que trae el GLB) se conserva tal
	## cual: es el aspecto original del cauce y cubre todo el río. Encima,
	## cada cauce dibuja su propia capa con el shader de río, que solo pinta
	## donde el lecho está por debajo de la lámina (las hondonadas: vados y
	## canales).
	##
	## Antes la capa sustituía al material importado de toda la superficie,
	## así que el shader (que descarta donde no hay agua) dejaba el río sin
	## textura dentro de la huella del cauce: de ahí que se viera "seco de
	## golpe" en tramos enteros.
	##
	## La geometría de la capa es una MALLA DE COBERTURA sobre la huella, no
	## la cinta importada: la cinta es un zigzag con huecos y el agua necesita
	## superficie continua para cubrir la hondonada.
	for owner in owners:
		var ch: Dictionary = owner
		var coverage := _build_coverage_mesh(ch, inst, si)
		if coverage == null:
			continue
		var part := MeshInstance3D.new()
		part.name = "%s_water_%s" % [inst.name, str(ch.get("id", ""))]
		part.transform = inst.transform
		part.layers = inst.layers
		part.visible = inst.visible
		part.cast_shadow = inst.cast_shadow
		part.mesh = coverage
		var parent := inst.get_parent()
		if parent == null:
			continue
		parent.add_child(part)
		var ch_nodes: Array = ch.get("nodes", [])
		var ch_orig: Array = ch.get("orig_y", [])
		var ch_claimed: Dictionary = ch.get("claimed_surfaces", {})
		# La malla importada sale de la lista: su material no se toca y solo
		# la capa de este cauce lleva el shader de río.
		var keep_nodes: Array = []
		var keep_orig: Array = []
		for i in ch_nodes.size():
			if ch_nodes[i] == inst:
				continue
			keep_nodes.append(ch_nodes[i])
			keep_orig.append(ch_orig[i] if i < ch_orig.size() else 0.0)
		ch_claimed.erase(inst.get_instance_id())
		keep_nodes.append(part)
		keep_orig.append(part.position.y)
		ch_claimed[part.get_instance_id()] = [0]
		ch["nodes"] = keep_nodes
		ch["orig_y"] = keep_orig
		ch["claimed_surfaces"] = ch_claimed


func _build_coverage_mesh(ch: Dictionary, inst: MeshInstance3D, si: int) -> Mesh:
	## Malla de cobertura del cauce: rejilla sobre la huella a la cota del
	## plano base. El shader recorta contra el lecho horneado, así que solo
	## queda pintada el agua real. La resolución sigue la del lecho (una
	## celda por celda del campo de alturas).
	var rx := int(ch.get("bed_res_x", 0))
	var rz := int(ch.get("bed_res_z", 0))
	if rx < 2 or rz < 2:
		return null
	var minx := float(ch["min_x"])
	var minz := float(ch["min_z"])
	var maxx := float(ch["max_x"])
	var maxz := float(ch["max_z"])
	if not is_finite(minx) or maxx <= minx:
		return null
	var to_local := inst.global_transform.affine_inverse()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for gz in rz + 1:
		for gx in rx + 1:
			var x := lerpf(minx, maxx, float(gx) / float(rx))
			var z := lerpf(minz, maxz, float(gz) / float(rz))
			verts.append(to_local * Vector3(x, base_level_at(ch, x, z), z))
			norms.append(Vector3.UP)
			uvs.append(Vector2(float(gx) / float(rx), float(gz) / float(rz)))
	for gz in rz:
		for gx in rx:
			var i0 := gz * (rx + 1) + gx
			var i1 := i0 + 1
			var i2 := i0 + rx + 1
			var i3 := i2 + 1
			idx.append(i0)
			idx.append(i2)
			idx.append(i1)
			idx.append(i1)
			idx.append(i2)
			idx.append(i3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Material provisional con el nombre de la superficie importada: el
	# cotejo por material lo sustituye por el shader de río.
	var src_mat := inst.mesh.surface_get_material(si)
	var placeholder := StandardMaterial3D.new()
	if src_mat is BaseMaterial3D:
		placeholder.resource_name = (src_mat as BaseMaterial3D).resource_name
		placeholder.albedo_color = Color(0, 0, 0, 0)
		placeholder.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	out.surface_set_material(0, placeholder)
	return out


func _resolve_instance_ownership() -> void:
	## Verificación de mallas: la cobertura por cauce deja a cada cauce con su
	## propia malla de agua, así que no puede haber dos cauces sobre la misma
	## malla. Se avisa si lo hubiera.
	var seen := {}
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		for mi in ((ch as Dictionary).get("nodes", []) as Array):
			var part := mi as MeshInstance3D
			if part == null or not is_instance_valid(part):
				continue
			var key := part.get_instance_id()
			if seen.has(key):
				_log_channel(str((ch as Dictionary).get("id", "")), "malla compartida con otro cauce: se conserva la primera")
				continue
			seen[key] = str((ch as Dictionary).get("id", ""))


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
		"flow_speed": clampf(float(cfg.get("flow_speed", 0.58)), 0.0, 5.0),
		"edge_feather_m": maxf(float(cfg.get("edge_feather_m", 0.06)), 0.005),
		"drag_scale": maxf(float(cfg.get("drag_scale", 1.25)), 0.1),
		"rainy_start_fraction": clampf(float(cfg.get("rainy_start_fraction", 0.5)), 0.0, 1.0),
		"settle_tolerance_m": maxf(float(cfg.get("settle_tolerance_m", 0.001)), 0.0001),
		"base_cx": 0.0, "base_cz": 0.0, "base_b0": 0.0, "base_gx": 0.0, "base_gz": 0.0,
		"visual_base_offset_m": 0.0,
		"min_x": INF, "min_z": INF, "max_x": -INF, "max_z": -INF,
		"rise_m": 0.0, "target_m": 0.0, "last_rain_mm_h": 0.0,
		"nodes": [], "orig_y": [], "override_info": [], "materials": [],
		"claimed_surfaces": {}, "surface_min_y": 0.0, "surface_max_y": 0.0,
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
	channels.append(ch)


func _prepare_channel_geometry(ch: Dictionary) -> void:
	## Geometría del cauce: plano base, índice de triángulos y lecho horneado.
	## Se calcula DESPUÉS de la partición, sobre la malla propia del cauce.
	_fit_base_plane(ch)
	_build_triangle_index(ch)
	_bake_bed_field(ch)
	# Diagnóstico para el inventario del piloto: huella, cota base y clima.
	print("RALLY_RIVER_READY id=", str(ch.get("id", "")), " progress_m=", snappedf(float(ch.get("progress_m", 0.0)), 0.1),
		" base_y=", snappedf(float(ch.get("base_b0", 0.0)), 0.001),
		" footprint_x=[", snappedf(float(ch.get("min_x", 0.0)), 0.1), ",", snappedf(float(ch.get("max_x", 0.0)), 0.1),
		"] z=[", snappedf(float(ch.get("min_z", 0.0)), 0.1), ",", snappedf(float(ch.get("max_z", 0.0)), 0.1),
		"] tris=", (ch.get("tris", []) as Array).size())


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
		"flow_speed": clampf(float(cfg.get("flow_speed", 0.58)), 0.0, 5.0),
		"edge_feather_m": 0.06,
		"drag_scale": 1.25,
		"rainy_start_fraction": 0.5,
		"settle_tolerance_m": 0.001,
		"base_cx": 0.0, "base_cz": 0.0,
		"base_b0": float(cfg.get("base_y", 0.0)),
		"base_gx": 0.0, "base_gz": 0.0,
		"visual_base_offset_m": 0.0,
		"min_x": -5.0, "min_z": -5.0, "max_x": 5.0, "max_z": 5.0,
		"rise_m": 0.0, "target_m": 0.0, "last_rain_mm_h": 0.0,
		"nodes": [], "orig_y": [], "override_info": [], "materials": [],
		"claimed_surfaces": {}, "surface_min_y": 0.0, "surface_max_y": 0.0,
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
	_sync_channels_to_rust()
	valid = true
	return ch


func _discover_meshes(ch: Dictionary, visual_root: Node) -> void:
	var wanted := {}
	for s in (ch["surfaces"] as Array):
		wanted[str(s).to_lower()] = true
	var claimed: Dictionary = ch.get("claimed_surfaces", {})
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
					_mesh_registry[mi.get_instance_id()] = mi
					# Reclamación por (malla, superficie): dos cauces con
					# superficies distintas pueden compartir la malla.
					var key := mi.get_instance_id()
					var sis: Array = claimed.get(key, [])
					if not sis.has(si):
						sis.append(si)
					claimed[key] = sis
		for child in node.get_children():
			stack.append(child)
	ch["claimed_surfaces"] = claimed


func _collect_water_vertices(ch: Dictionary) -> Array:
	## Vértices de agua del cauce.
	##
	## Dentro de la huella se conserva la densidad COMPLETA: el plano base se
	## ajusta ahí y una muestra dispersa de la malla larga daría una
	## pendiente falsa (o ninguna). Fuera de la huella se guarda una muestra
	## espaciada como respaldo si la huella no contiene vértices.
	var dense: Array = []
	var sparse: Array = []
	var wanted := {}
	for s in (ch["surfaces"] as Array):
		wanted[str(s).to_lower()] = true
	var has_fp := bool(ch.get("has_footprint", false))
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
			var step := 1
			if verts.size() > MAX_FIT_SAMPLES * 2:
				step = int(ceil(float(verts.size()) / float(MAX_FIT_SAMPLES * 2)))
			var i := 0
			var k := 0
			while i < verts.size():
				var w: Vector3 = gt * verts[i]
				if has_fp:
					if _inside_footprint(ch, w.x, w.z, 4.0):
						dense.append(w)
					elif k % 8 == 0:
						sparse.append(w)
				else:
					sparse.append(w)
				k += 1
				i += step
	if dense.size() >= 16:
		return dense
	if not sparse.is_empty():
		return sparse
	return dense


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
		_log_channel(str(ch.get("id", "?")), "sin vértices de agua en la huella: plano base sin ajustar")
		return
	var ymin := INF
	var ymax := -INF
	var cx := 0.0
	var cz := 0.0
	var cy := 0.0
	var gx := 0.0
	var gz := 0.0
	var used_rust_fit := false
	var helper := _ensure_rust_rivers()
	if helper != null:
		var pvec := PackedVector3Array()
		pvec.resize(pts.size())
		for pi in pts.size():
			pvec[pi] = pts[pi] as Vector3
		var fit: PackedFloat32Array = helper.call("fit_base_plane_pts", pvec)
		if fit.size() >= 11:
			cx = fit[0]
			cz = fit[1]
			cy = fit[2]
			gx = fit[3]
			gz = fit[4]
			ymin = fit[5]
			ymax = fit[6]
			ch["surface_min_y"] = ymin
			ch["surface_max_y"] = ymax
			ch["base_cx"] = cx
			ch["base_cz"] = cz
			ch["base_b0"] = cy
			ch["base_gx"] = gx
			ch["base_gz"] = gz
			if not bool(ch.get("has_footprint", false)):
				ch["min_x"] = fit[7]
				ch["min_z"] = fit[8]
				ch["max_x"] = fit[9]
				ch["max_z"] = fit[10]
			used_rust_fit = true
	if not used_rust_fit:
		# Rango vertical real de la lámina en la zona de ajuste: define la
		# ventana del horneado del lecho (cascadas y tramos con desnivel).
		for p in pts:
			ymin = minf(ymin, (p as Vector3).y)
			ymax = maxf(ymax, (p as Vector3).y)
		ch["surface_min_y"] = ymin
		ch["surface_max_y"] = ymax
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
		# ruedas; la pendiente de la malla se conserva alrededor y se guarda
		# el desplazamiento vertical para alinear también el shader.
		var an: Dictionary = ch["level_anchor"]
		var px := float(an.get("x", cx))
		var pz := float(an.get("z", cz))
		var py := float(an.get("y", cy))
		var plane_at := cy + float(ch["base_gx"]) * (px - cx) + float(ch["base_gz"]) * (pz - cz)
		var delta_y := py - plane_at
		ch["base_b0"] = cy + delta_y
		ch["visual_base_offset_m"] = delta_y
	if bool(ch.get("has_footprint", false)):
		return
	if used_rust_fit:
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
	## Campo de altura del lecho sobre la huella: rejilla proporcional con
	## celda fija (~1 m, acotada por MAX_BAKE_SAMPLES) para evitar bloques
	## alargados en ríos largos. El tablero de puentes se excluye del horneado.
	##
	## La ventana vertical del rayo sigue al plano base local (no a un único
	## nivel) y se abre hasta el rango real de la lámina: con una ventana
	## fija el lecho de los tramos con desnivel (cascadas, river1_1) quedaba
	## sin muestrear y la lámina se descartaba entera.
	var space = _space()
	var minx := float(ch["min_x"])
	var minz := float(ch["min_z"])
	var maxx := float(ch["max_x"])
	var maxz := float(ch["max_z"])
	if not is_finite(minx) or maxx <= minx:
		return
	var span_x := maxf(maxx - minx, 0.5)
	var span_z := maxf(maxz - minz, 0.5)
	var cell_m := maxf(1.0, sqrt((span_x * span_z) / float(MAX_BAKE_SAMPLES)))
	var res_x := clampi(int(round(span_x / cell_m)), 8, 256)
	var res_z := clampi(int(round(span_z / cell_m)), 8, 256)
	var total_samples := res_x * res_z
	var heights := PackedFloat32Array()
	var mask := PackedByteArray()
	heights.resize(total_samples)
	mask.resize(total_samples)
	var bed_min := INF
	var bed_max := -INF
	var base := float(ch["base_b0"])
	# Rango de la lámina en el mismo marco que el plano base (el mesh se
	# desplaza en el shader por visual_base_offset_m).
	var offset := float(ch.get("visual_base_offset_m", 0.0))
	var s_min := float(ch.get("surface_min_y", base)) + offset
	var s_max := float(ch.get("surface_max_y", base)) + offset
	for gz in res_z:
		for gx in res_x:
			var idx := gz * res_x + gx
			var x := lerpf(minx, maxx, (float(gx) + 0.5) / float(res_x))
			var z := lerpf(minz, maxz, (float(gz) + 0.5) / float(res_z))
			var plane_y := base_level_at(ch, x, z)
			var h := plane_y - 0.25
			var ok := true
			if space != null:
				var top := minf(maxf(plane_y + 8.0, s_max + 2.0), plane_y + 60.0)
				var bottom := maxf(minf(plane_y - 8.0, s_min - 2.0), plane_y - 60.0)
				var query := PhysicsRayQueryParameters3D.create(
					Vector3(x, top, z), Vector3(x, bottom, z), 1)
				var hit: Dictionary = space.intersect_ray(query)
				if hit.is_empty():
					ok = false
				else:
					var collider: Object = hit.get("collider")
					var cname := str((collider as Node).name) if collider is Node else ""
					var hy := float((hit.get("position", Vector3(x, h, z)) as Vector3).y)
					# Tablero de puente: la lámina pasa por debajo; no hornear.
					if cname.to_lower().contains("bridge") and hy > plane_y - 0.15:
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
	if valid_count < int(float(total_samples) * 0.05):
		# Sin horneado útil (p. ej. sin colisión bajo la huella): lecho
		# uniforme bajo el plano base local para no romper la lámina.
		for gz in res_z:
			for gx in res_x:
				var idx := gz * res_x + gx
				var x := lerpf(minx, maxx, (float(gx) + 0.5) / float(res_x))
				var z := lerpf(minz, maxz, (float(gz) + 0.5) / float(res_z))
				heights[idx] = base_level_at(ch, x, z) - 0.25
		mask.fill(1)
		bed_min = base - 0.5
		bed_max = base + 0.1
	elif bed_min >= bed_max:
		bed_min = base - 0.5
		bed_max = base + 0.1
	ch["bed_min_y"] = bed_min
	ch["bed_max_y"] = bed_max
	ch["bed_res_x"] = res_x
	ch["bed_res_z"] = res_z
	ch["bed_heights"] = heights
	ch["bed_valid"] = mask
	var img := Image.create(res_x, res_z, false, Image.FORMAT_RG8)
	for gz in res_z:
		for gx in res_x:
			var idx := gz * res_x + gx
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
	var claimed: Dictionary = ch.get("claimed_surfaces", {})
	for mi in (ch["nodes"] as Array):
		var inst := mi as MeshInstance3D
		if inst == null or inst.mesh == null:
			continue
		var mesh := inst.mesh
		# Superficies asignadas a este cauce. Sin registro (canal sintético
		# de los contratos) se barren todas por nombre de material.
		var surfaces: Array = (claimed.get(inst.get_instance_id(), []) as Array).duplicate()
		if surfaces.is_empty():
			for si in mesh.get_surface_count():
				surfaces.append(si)
		for si in surfaces:
			var idx := int(si)
			if idx < 0 or idx >= mesh.get_surface_count():
				continue
			var mat := inst.get_active_material(idx)
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
			sm.render_priority = -1
			sm.set_meta("rally_dynamic_water", true)
			(ch["override_info"] as Array).append([inst, idx, mat])
			inst.set_surface_override_material(idx, sm)
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
		# La capa se apoya en la lámina importada: solo sube con la crecida.
		# El desfase de la cota base vive en el plano de física, no en el
		# render, para que la lámina dinámica no se despegue del río.
		m.set_shader_parameter("rise_m", float(ch.get("rise_m", 0.0)))
		# La capa se dibuja unos centímetros por encima de la lámina
		# importada: la cinta es opaca y su superfície ondula alrededor del
		# plano base. La elevación no cuenta en el cálculo de profundidad, así
		# que el agua que ve el jugador y la que siente el coche coinciden.
		m.set_shader_parameter("depth_bias", WATER_RENDER_BIAS_M)
		m.set_shader_parameter("flow_dir", ch.get("flow_dir", Vector2(0.3, 0.95)))
		m.set_shader_parameter("flow_speed", float(ch.get("flow_speed", 0.58)))
		m.set_shader_parameter("rain", clampf(float(ch.get("last_rain_mm_h", 0.0)) / 10.0, 0.0, 1.0))
		m.set_shader_parameter("water_detail_tex", WATER_DETAIL_TEX)
		# El oleaje y el color los calcula el shader (paleta de PS2): el mapa
		# de bits solo queda como respaldo.
		m.set_shader_parameter("detail_procedural_mix", 1.0)


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
	## La crecida vertical se aplica en el shader de río (uniform rise_m) en lugar
	## de desplazar el nodo MeshInstance3D, porque en Kenia river1_1/river2_1
	## comparten Track_Road_And_Terrain con toda la carretera y el terreno.
	for ch in channels:
		if not bool((ch as Dictionary).get("active", false)):
			continue
		_update_channel_material((ch as Dictionary))
	_sync_rises_to_rust()


func _ensure_rust_rivers() -> RefCounted:
	if not use_rust_backend or not ClassDB.class_exists(&"RustRiverChannels"):
		return null
	if _rust_rivers == null:
		_rust_rivers = ClassDB.instantiate(&"RustRiverChannels") as RefCounted
	return _rust_rivers


func _sync_channels_to_rust() -> void:
	var helper := _ensure_rust_rivers()
	if helper == null:
		_rust_rivers = null
		_rust_rises.resize(0)
		return
	helper.call("clear")
	var count: int = channels.size()
	_rust_rises.resize(count)
	for i in count:
		var ch: Dictionary = channels[i] as Dictionary
		var tris: Array = ch.get("tris", []) as Array
		var tri_verts := PackedVector2Array()
		tri_verts.resize(tris.size() * 3)
		for ti in tris.size():
			var tri: Array = tris[ti] as Array
			tri_verts[ti * 3] = tri[0] as Vector2
			tri_verts[ti * 3 + 1] = tri[1] as Vector2
			tri_verts[ti * 3 + 2] = tri[2] as Vector2
		var rise: float = float(ch.get("rise_m", 0.0))
		_rust_rises[i] = rise
		helper.call(
			"add_channel",
			bool(ch.get("active", false)),
			float(ch.get("min_x", -5.0)),
			float(ch.get("min_z", -5.0)),
			float(ch.get("max_x", 5.0)),
			float(ch.get("max_z", 5.0)),
			float(ch.get("base_cx", 0.0)),
			float(ch.get("base_cz", 0.0)),
			float(ch.get("base_b0", 0.0)),
			float(ch.get("base_gx", 0.0)),
			float(ch.get("base_gz", 0.0)),
			float(ch.get("drag_scale", 1.25)),
			rise,
			tri_verts,
		)


func _sync_rises_to_rust() -> void:
	if not use_rust_backend or _rust_rivers == null:
		return
	var count: int = channels.size()
	if _rust_rises.size() != count:
		_sync_channels_to_rust()
		return
	for i in count:
		_rust_rises[i] = float((channels[i] as Dictionary).get("rise_m", 0.0))
	_rust_rivers.call("update_rises", _rust_rises)


func channel_id_at(ch_idx: int) -> String:
	if ch_idx < 0 or ch_idx >= channels.size():
		return ""
	return str((channels[ch_idx] as Dictionary).get("id", ""))


func sample_4wheels(positions: PackedVector3Array, loaded_mask: int) -> PackedFloat32Array:
	if use_rust_backend and _rust_rivers != null:
		return _rust_rivers.call("sample_4wheels", positions, loaded_mask) as PackedFloat32Array
	var out := PackedFloat32Array()
	out.resize(16)
	for wi in 4:
		out[wi * 4 + 1] = -INF
		out[wi * 4 + 3] = -1.0
	var count: int = mini(positions.size(), 4)
	for i in count:
		if (loaded_mask & (1 << i)) == 0:
			continue
		var r: Dictionary = sample_contact(positions[i])
		var base_i: int = i * 4
		out[base_i] = float(r.get("depth_mm", 0.0))
		out[base_i + 1] = float(r.get("surface_y", -INF))
		out[base_i + 2] = float(r.get("drag_scale", 0.0))
		var cid: String = str(r.get("channel_id", ""))
		var found_idx: float = -1.0
		if not cid.is_empty():
			for ci in channels.size():
				if str((channels[ci] as Dictionary).get("id", "")) == cid:
					found_idx = float(ci)
					break
		out[base_i + 3] = found_idx
	return out


func sample_contact(world_position: Vector3) -> Dictionary:
	## Consulta de solo lectura: busca por huella con índice espacial y
	## consulta la altura de la lámina en XZ. Usa ÚNICAMENTE el contacto ya
	## resuelto por la rueda en Jolt (`world_position` = punto de contacto).
	## Dentro de una zona válida y mojada devuelve
	## max(0, surface_y - contact_y) * 1000 en mm. El puente queda seco
	## mientras el contacto esté sobre la lámina (contacto por encima).
	if use_rust_backend and _rust_rivers != null:
		var packed: PackedFloat32Array = _rust_rivers.call("sample_contact_packed", world_position)
		var ch_idx: int = int(packed[3])
		if ch_idx < 0 or ch_idx >= channels.size():
			return {"depth_mm": 0.0, "surface_y": -INF, "channel_id": "", "drag_scale": 0.0, "wet": false}
		var depth_mm: float = packed[0]
		return {
			"depth_mm": depth_mm,
			"surface_y": packed[1],
			"channel_id": str((channels[ch_idx] as Dictionary).get("id", "")),
			"drag_scale": packed[2],
			"wet": depth_mm > 0.001,
		}
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
	# Superficies neutralizadas por la partición: restaurar el material
	# importado y retirar las mallas por cauce.
	for ch in channels:
		for mi in ((ch as Dictionary).get("nodes", []) as Array):
			var part := mi as MeshInstance3D
			if part != null and is_instance_valid(part):
				part.queue_free()
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
