class_name RallyWeatherController
extends RefCounted
## Controlador climático del evento: lee el cronograma ya generado y el modelo
## de superficie por zona. La posición proyectada sobre la ruta identifica la
## zona (no el tiempo deportivo ni las puertas de pacenotes). Mezcla por
## distancia con smoothstep. El cielo y TCA son adaptadores; no generan una
## segunda secuencia. Un único proveedor físico alimenta materiales,
## precipitación, termodinámica y fricción.

const SchedulerScript := preload("res://scripts/rally/rally_weather_scheduler.gd")
const SurfaceScript := preload("res://scripts/rally/rally_surface_model.gd")

var error: String = ""
var stage_id: String = ""
var schedule_entry: Dictionary = {}
var catalog: Dictionary = {}
var route_points: Array[Vector3] = []
var route_distances := PackedFloat64Array()
var route_total_m: float = 1.0
var route_segment: int = 0
var route_progress_m: float = 0.0
var surface := SurfaceScript.new()
var current_zone: int = 0
var current_blend: Dictionary = {}
var visual_smoothing_s: float = 0.0
var visual_state: Dictionary = {}
var last_vehicle_pos: Vector3 = Vector3.ZERO
var has_position: bool = false
var calendar_active: bool = false


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		error = "No existe " + path
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		error = "JSON inválido: " + path
		return {}
	return parsed


func configure(for_stage_id: String, entry: Dictionary, route_path: String) -> bool:
	error = ""
	stage_id = for_stage_id
	schedule_entry = (entry as Dictionary).duplicate(true)
	catalog = _read_json(SchedulerScript.PRESET_CATALOG_PATH)
	if catalog.is_empty():
		return false
	if schedule_entry.is_empty():
		error = "Sin cronograma para " + for_stage_id
		return false
	if not surface.configure_from_schedule(schedule_entry, catalog):
		error = "Modelo de superficie incompatible para " + for_stage_id
		return false
	route_points.clear()
	if FileAccess.file_exists(route_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(route_path))
		if parsed is Dictionary:
			for p in (parsed as Dictionary).get("points", []):
				if p is Array and (p as Array).size() >= 3:
					route_points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	if route_points.size() < 2:
		error = "Ruta sin puntos para proyección: " + route_path
		return false
	route_distances = PackedFloat64Array([0.0])
	for i in range(1, route_points.size()):
		route_distances.append(route_distances[-1] + route_points[i - 1].distance_to(route_points[i]))
	route_total_m = route_distances[-1]
	route_segment = 0
	route_progress_m = 0.0
	current_zone = 0
	current_blend = surface.blended_state_at_distance(0.0)
	visual_state = current_blend.duplicate(true)
	visual_smoothing_s = 0.0
	has_position = false
	calendar_active = true
	return true


func reset_projection() -> void:
	route_segment = 0
	route_progress_m = 0.0
	current_zone = 0
	has_position = false
	visual_smoothing_s = 0.0
	if surface.valid:
		current_blend = surface.blended_state_at_distance(0.0)
		visual_state = current_blend.duplicate(true)


## Proyección sobre la ruta con continuidad de segmento (tolera salida de
## carretera, rescate y reincorporación; distingue curvas cercanas y puentes
## incluyendo altura). Al retroceder se consulta la posición real.
func project_position(world_pos: Vector3) -> Dictionary:
	if route_points.is_empty():
		return {"progress_m": 0.0, "segment": 0, "lateral_m2": 0.0}
	var best_d := INF
	var best_prog := route_progress_m
	var best_seg := route_segment
	var lo := maxi(0, route_segment - 8)
	var hi := mini(route_points.size() - 1, route_segment + 24)
	# Primera fijación: búsqueda amplia.
	if not has_position or world_pos.distance_to(last_vehicle_pos) > 45.0:
		lo = 0
		hi = route_points.size() - 1
	for i in range(lo, hi):
		var a: Vector3 = route_points[i]
		var b: Vector3 = route_points[i + 1]
		var ab := b - a
		var denom := maxf(Vector2(ab.x, ab.z).length_squared(), 0.000001)
		var frac := clampf(Vector2(world_pos.x - a.x, world_pos.z - a.z).dot(Vector2(ab.x, ab.z)) / denom, 0.0, 1.0)
		var projected: Vector3 = a.lerp(b, frac)
		# Puentes y curvas cercanas: exige coherencia en altura.
		if absf(world_pos.y - projected.y) > 12.0:
			continue
		var candidate := lerpf(route_distances[i], route_distances[i + 1], frac)
		# No saltar hacia adelante más de lo físicamente plausible en un paso;
		# hacia atrás siempre se permite (retroceso consulta la posición real).
		if has_position and hi != route_points.size() - 1 and candidate > route_progress_m + 60.0:
			continue
		var lateral := Vector2(world_pos.x, world_pos.z).distance_squared_to(Vector2(a.x, a.z).lerp(Vector2(b.x, b.z), frac))
		if lateral < best_d:
			best_d = lateral
			best_prog = candidate
			best_seg = i
	if best_d <= 35.0 * 35.0:
		# Avance monótono salvo retroceso real: si el coche vuelve atrás, el
		# progreso también vuelve (sin re-sortear ni rebobinar agua/nieve).
		route_progress_m = best_prog
		route_segment = best_seg
		last_vehicle_pos = world_pos
		has_position = true
		return {"progress_m": route_progress_m, "segment": route_segment, "lateral_m2": best_d}
	# Fuera de carretera: mantener la referencia proyectada (no oscila).
	return {"progress_m": route_progress_m, "segment": route_segment, "lateral_m2": best_d}


func zone_index_for_progress(progress_m: float) -> int:
	return surface.zone_index_at_distance(progress_m)


## Actualiza la proyección y devuelve el estado mezclado objetivo (físico,
## inmediato). Lo visual puede ir suavizado tras teletransportes.
func update_vehicle_position(world_pos: Vector3) -> Dictionary:
	var proj := project_position(world_pos)
	current_zone = surface.zone_index_at_distance(float(proj.get("progress_m", 0.0)))
	current_blend = surface.blended_state_at_distance(float(proj.get("progress_m", 0.0)))
	current_blend["route_progress_m"] = float(proj.get("progress_m", 0.0))
	current_blend["zone_index"] = current_zone
	if visual_state.is_empty():
		# Inicializar en el primer fix; después tick_visual aplica la inercia desacoplada.
		visual_state = current_blend.duplicate(true)
	return current_blend.duplicate(true)


func tick_visual(delta_s: float) -> void:
	if current_blend.is_empty():
		return
	if visual_state.is_empty() or delta_s >= 2.0:
		visual_state = current_blend.duplicate(true)
		visual_smoothing_s = 0.0
		return

	if visual_smoothing_s > 0.0:
		visual_smoothing_s = maxf(visual_smoothing_s - delta_s, 0.0)
		var t := 1.0 - clampf(visual_smoothing_s / 2.0, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		visual_state = SurfaceScript._lerp_states(visual_state, current_blend, clampf(t * 0.3 + 0.1, 0.0, 1.0))
		if visual_smoothing_s <= 0.0:
			visual_state = current_blend.duplicate(true)
		return

	# Inercia visual desacoplada por componente atmosférico:
	# Cielo y nubes: adaptación lenta (~6.0s)
	# Niebla: adaptación media (~4.0s)
	# Precipitación y viento: adaptación rápida (~2.5s)
	var tgt_climate: Dictionary = current_blend.get("climate", {})
	var cur_climate: Dictionary = visual_state.get("climate", tgt_climate.duplicate(true))
	var new_climate := cur_climate.duplicate(true)

	var tau_sky := 6.0
	var alpha_sky := 1.0 - exp(-delta_s / tau_sky)
	for k in ["cumulus_coverage", "cirrus_coverage", "irradiance_w_m2", "air_temperature_c"]:
		if tgt_climate.has(k):
			new_climate[k] = lerpf(float(cur_climate.get(k, tgt_climate[k])), float(tgt_climate[k]), clampf(alpha_sky, 0.0, 1.0))

	var tau_fog := 4.0
	var alpha_fog := 1.0 - exp(-delta_s / tau_fog)
	if tgt_climate.has("fog_density"):
		new_climate["fog_density"] = lerpf(float(cur_climate.get("fog_density", tgt_climate["fog_density"])), float(tgt_climate["fog_density"]), clampf(alpha_fog, 0.0, 1.0))

	var tau_precip := 2.5
	var alpha_precip := 1.0 - exp(-delta_s / tau_precip)
	for k in ["precipitation_mm_h", "wind_m_s"]:
		if tgt_climate.has(k):
			new_climate[k] = lerpf(float(cur_climate.get(k, tgt_climate[k])), float(tgt_climate[k]), clampf(alpha_precip, 0.0, 1.0))

	if tgt_climate.has("wind_direction_deg"):
		var diff := fposmod(float(tgt_climate["wind_direction_deg"]) - float(cur_climate.get("wind_direction_deg", tgt_climate["wind_direction_deg"])) + 180.0, 360.0) - 180.0
		new_climate["wind_direction_deg"] = fposmod(float(cur_climate.get("wind_direction_deg", tgt_climate["wind_direction_deg"])) + diff * clampf(alpha_precip, 0.0, 1.0), 360.0)

	visual_state["climate"] = new_climate
	for k in ["air_c", "ground_c", "water_mm", "saturation", "snow_mm"]:
		visual_state[k] = current_blend.get(k, visual_state.get(k, 0.0))


## Rescate/teletransporte: suavizar visualmente para no provocar un salto
## brusco de cielo; los contactos consultan inmediatamente la zona correcta.
func on_rescue(world_pos: Vector3) -> void:
	has_position = false
	var proj := project_position(world_pos)
	# Forzar re-proyección amplia en el siguiente paso.
	route_progress_m = float(proj.get("progress_m", route_progress_m))
	current_zone = surface.zone_index_at_distance(route_progress_m)
	current_blend = surface.blended_state_at_distance(route_progress_m)
	visual_smoothing_s = 2.0


## Avance ambiental de todas las zonas (incluidas las no visitadas) con pasos
## acotados. No llamar en pausa/reglaje/carga.
func advance_ambient(delta_s: float, solar_factor: float) -> void:
	surface.advance_ambient(delta_s, solar_factor)


## Factor solar por hora: Soleado de noche no crea luz solar.
func solar_factor_for_hour(hour: float) -> float:
	# Amanece ~6h, pico 13h, anochece ~20h (verano nórdico).
	if hour < 5.0 or hour > 21.0:
		return 0.0
	var t := (hour - 6.0) / 14.0
	return clampf(sin(t * PI), 0.0, 1.0)


## Condiciones locales por contacto: material real + condiciones de zona.
## Se combina una sola vez aguas abajo (tire_model); aquí no se duplica la
## reducción mojada.
func local_conditions_for_contact(surface_name: String, vehicle_pos: Vector3) -> Dictionary:
	# Query contacts without changing the vehicle/HUD projection cursor.
	var distance := route_progress_m
	var best := INF
	for i in range(maxi(0, route_segment - 4), mini(route_points.size() - 1, route_segment + 5)):
		var a := route_points[i]
		var ab := route_points[i + 1] - a
		var t := clampf((vehicle_pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := vehicle_pos.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			distance = lerpf(route_distances[i], route_distances[i + 1], t)
	var st := surface.blended_state_at_distance(distance)
	st["surface_name"] = surface_name
	st["water_mm_effective"] = float(st.get("water_mm", 0.0))
	st["snow_mm_effective"] = float(st.get("snow_mm", 0.0))
	st["route_progress_m"] = distance
	st["zone_index"] = surface.zone_index_at_distance(distance)
	return st


## Temperatura de superficie del corredor de ruta (minimapa): misma
## interpolación espacial en límites; al salir de carretera mantiene la
## referencia proyectada.
func surface_temperature_at_vehicle() -> Dictionary:
	if current_blend.is_empty():
		return {"ok": false, "text": "—"}
	if not has_position and route_progress_m <= 0.01:
		# Sin dato válido: mostrar «—», nunca cero como temperatura real.
		pass
	return {"ok": true, "celsius": float(current_blend.get("ground_c", 15.0)), "zone_index": current_zone, "route_progress_m": route_progress_m}


## Aplica el clima a los adaptadores visuales/sonoros desde la fuente única.
## Con calendario activo se desactiva la selección aleatoria autónoma de TCA.
func apply_to_adapters(sky: Node, tca_controller: Node, wetness: Node, hour: float) -> void:
	if not calendar_active or current_blend.is_empty():
		return
	var climate: Dictionary = (visual_state.get("climate", current_blend.get("climate", {})) as Dictionary)
	var solar := solar_factor_for_hour(hour)
	var irr := float(climate.get("irradiance_w_m2", 200.0)) * solar
	var visual: Dictionary = catalog.get("visual_response", {})
	if sky != null and sky.has_method("apply_climate"):
		sky.call("apply_climate", climate, visual)
	if tca_controller != null and is_instance_valid(tca_controller):
		tca_controller.set_process(false)
		# Fuente unica: congelar el avance autonomo y la ruleta de climas.
		if tca_controller.get("time_speed_multiplier") != null and float(tca_controller.get("time_speed_multiplier")) != 0.0:
			tca_controller.set("time_speed_multiplier", 0.0)
		var precip := float(climate.get("precipitation_mm_h", 0.0))
		var raining := precip >= 0.4
		# Exponer intensidad a los adaptadores que la lean (sonido/particulas).
		tca_controller.set_meta("calendar_precip_mm_h", precip)
		tca_controller.set_meta("calendar_raining", raining)
		var kind := str(current_blend.get("precipitation_kind", "rain"))
		if current_blend.has("blend_to") and float(current_blend.get("blend_t", 0.0)) >= 0.5:
			kind = str(surface.zones[int(current_blend.blend_to)].get("precipitation_kind", kind))
		if kind == "mixed":
			kind = "snow"
		var adapter: Dictionary = catalog.get("precipitation_adapter", {})
		var particles := tca_controller.get("particle_system") as GPUParticles3D
		if precip > 0.01 and kind != "none" and str(tca_controller.get_meta("calendar_particle_kind", "")) != kind:
			if particles != null:
				particles.queue_free()
			particles = null
			var path := str(adapter.get(kind + "_scene", ""))
			if ResourceLoader.exists(path):
				var packed := load(path) as PackedScene
				particles = packed.instantiate() as GPUParticles3D
				if particles != null:
					if kind == "rain":
						particles.trail_lifetime = float(visual.get("rain_trail_seconds", 0.045))
						var mesh := particles.draw_pass_1.duplicate() as Mesh
						var material := ShaderMaterial.new()
						material.shader = load("res://scripts/rally/rally_rain.gdshader")
						material.set_shader_parameter("opacity", float(visual.get("rain_opacity", 0.65)))
						# Fade drops close to the camera; a ribbon crossing the
						# near plane otherwise expands into a screen-sized stripe.
						material.set_shader_parameter("near_start_m", float(visual.get("rain_near_fade_start_m", 0.8)))
						material.set_shader_parameter("near_end_m", float(visual.get("rain_near_fade_end_m", 3.2)))
						material.set_shader_parameter("far_start_m", float(visual.get("rain_far_fade_start_m", 22.0)))
						material.set_shader_parameter("far_end_m", float(visual.get("rain_far_fade_end_m", 38.0)))
						material.set_shader_parameter("ambient_luma", clampf(irr / 400.0, 0.40, 1.0))
						if mesh is RibbonTrailMesh:
							var rmesh := mesh as RibbonTrailMesh
							rmesh.size = float(visual.get("rain_width_m", 0.025))
							# Anular la curva que reducia el grosor real de la cinta al 4.6%
							rmesh.curve = null
						mesh.surface_set_material(0, material)
						particles.draw_pass_1 = mesh
					elif kind == "snow":
						var mesh := particles.draw_pass_1.duplicate() as Mesh
						if mesh is QuadMesh:
							var snow_s: float = float(visual.get("snow_size_m", 0.26))
							(mesh as QuadMesh).size = Vector2(snow_s, snow_s)
						var mat := mesh.surface_get_material(0)
						if mat is StandardMaterial3D:
							var smat := mat.duplicate() as StandardMaterial3D
							smat.albedo_color = Color(1.0, 1.0, 1.0, float(visual.get("snow_opacity", 0.85)))
							smat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
							smat.distance_fade_min_distance = float(visual.get("rain_near_fade_start_m", 0.8))
							smat.distance_fade_max_distance = float(visual.get("rain_near_fade_end_m", 3.2))
							mesh.surface_set_material(0, smat)
							particles.draw_pass_1 = mesh
					tca_controller.add_child(particles)
			tca_controller.set("particle_system", particles)
			tca_controller.set_meta("calendar_particle_kind", kind)
		if particles != null:
			particles.emitting = precip > 0.005 and kind != "none"
			var full_int := maxf(float(adapter.get("full_intensity_mm_h", 12.0)), 0.01)
			var base_ratio := clampf(precip / full_int, 0.0, 1.0)
			# Rampa suave continua sin salto brusco a 0.18:
			var entry_ramp := smoothstep(0.005, 0.40, precip)
			particles.amount_ratio = clampf(base_ratio * entry_ramp, 0.0, 1.0) if precip > 0.005 else 0.0
			particles.global_position = last_vehicle_pos + Vector3.UP * 10.0
			# Orientacion de lluvia/nieve segun el viento local
			var pm := particles.process_material as ParticleProcessMaterial
			if pm != null:
				var wind_speed := float(climate.get("wind_m_s", 0.0))
				var wind_deg := float(climate.get("wind_direction_deg", 0.0))
				var wind_rad := deg_to_rad(wind_deg)
				var wind_drift := clampf(wind_speed / 14.0, 0.0, 0.75)
				pm.direction = Vector3(cos(wind_rad) * wind_drift, -1.0, sin(wind_rad) * wind_drift).normalized()
			if kind == "rain" and particles.draw_pass_1 != null:
				var pmesh := particles.draw_pass_1 as Mesh
				if pmesh != null:
					var pmat := pmesh.surface_get_material(0) as ShaderMaterial
					if pmat != null:
						pmat.set_shader_parameter("ambient_luma", clampf(irr / 400.0, 0.40, 1.0))
	if wetness != null and is_instance_valid(wetness):
		var w := clampf(float(current_blend.get("water_mm", 0.0)) / 4.0, 0.0, 1.0)
		if wetness.has_method("set_rain_intensity"):
			var precip2 := float(climate.get("precipitation_mm_h", 0.0))
			wetness.call("set_rain_intensity", clampf(precip2 / 6.0, 0.0, 1.0))
		if wetness.has_method("set_zone_wetness"):
			wetness.call("set_zone_wetness", w, current_zone)


func snapshot() -> Dictionary:
	return {
		"stage_id": stage_id,
		"route_progress_m": route_progress_m,
		"route_segment": route_segment,
		"current_zone": current_zone,
		"surface": surface.snapshot(),
		"has_position": has_position,
	}


func restore_snapshot(data: Dictionary) -> void:
	route_progress_m = float(data.get("route_progress_m", 0.0))
	route_segment = int(data.get("route_segment", 0))
	current_zone = int(data.get("current_zone", 0))
	has_position = bool(data.get("has_position", false))
	surface.restore_snapshot(data.get("surface", []))
	current_blend = surface.blended_state_at_distance(route_progress_m)
	visual_state = current_blend.duplicate(true)
	visual_smoothing_s = 0.0
