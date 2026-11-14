class_name FordRallyVehicleSimulation
extends RefCounted

const PROFILE_PATH := "res://data/vehicles/ford-escort-rs2000/vehicle.json"
# preload directo: no depende de la caché global de clases del editor.
const RallyDifferentialCatalog = preload("res://scripts/rally/rally_differential_catalog.gd")
const TIRE_THERMAL_PERIOD := 1.0 / 30.0
const ENGINE_THERMAL_PERIOD := 1.0 / 20.0
const FUEL_PERIOD := 1.0 / 10.0

const WHEEL_KEYS := ["front_left", "front_right", "rear_left", "rear_right"]

var profile: Dictionary = { }
var domains: Dictionary = { }
var asset_manifest: Dictionary = { }
var mass_model := VehicleMassModel.new()
var suspension_model := VehicleSuspensionModel.new()
var unsprung_rig := UnsprungSuspensionRig.new()
var tire_model := TireModel.new()
var powertrain_model := VehiclePowertrainModel.new()
var brake_model := VehicleBrakeModel.new()
var aero_model := VehicleAerodynamicModel.new()
var thermal_model := VehicleThermalModel.new()
var alignment_collision_damage: Array[float] = [0.0, 0.0, 0.0, 0.0]
var brake_collision_loss: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_positions_local: Array[Vector3] = []
var wheel_radii: Array[float] = []
var wheel_widths: Array[float] = []
var wheel_spins: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_slips: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var wheel_contact_points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var wheel_contact_normals: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
var wheel_surfaces: Array[String] = ["Unknown", "Unknown", "Unknown", "Unknown"]
var wheel_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_visual_pivots: Array[Node3D] = []
var wheel_visuals: Array[Node3D] = []
var wheel_rotation_angles: Array[float] = [0.0, 0.0, 0.0, 0.0]
var contact_query_count: int = 0
var wheel_contact_casts: Array[ShapeCast3D] = []
# Auditoría §3: último contacto por rueda (hit, punto, normal, collider,
# distancia usada por la ley radial, fracción segura y apoyo seleccionado).
var last_contacts: Array[Dictionary] = [{}, {}, {}, {}]
var contact_frequency_samples: int = 0
var contact_frequency_elapsed_s: float = 0.0
var mass_state: Dictionary = { }
var maximum_substep_seconds: float = 0.002
var configured_substeps_per_tick: int = 0
var configured_substep_hz: int = 120
var _tire_thermal_elapsed := 0.0
# Friction, brake and radial damping work, in joules per wheel.
var _wheel_thermal_work: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _engine_thermal_elapsed := 0.0
var _engine_thermal_inputs := Vector4.ZERO
var _fuel_elapsed := 0.0
var _fuel_work_j := 0.0
var last_step_seconds: float = 0.0
var published_state: Dictionary = { }
var publication_sequence: int = 0
var simulation_time_s: float = 0.0
var session_generation: int = 0
var setup_design_axles: Array[Dictionary] = []
var setup_design_values: Dictionary = { }
var wheelbase_m: float = 2.41
var ackermann: float = 0.18
var maximum_steering_angle_rad: float = 0.5585053606381855
var steering_exponent: float = 1.1
var front_steering_ratio: float = 1.0
var rear_steering_ratio: float = 0.0
var traction_control_enabled: bool = false
var stability_enabled: bool = false
var abs_enabled: bool = false
var assistance_available: Dictionary = { }
var underfloor_document: Dictionary = { }
var weather_controller = null
var puddle_system = null
var river_system = null
const PuddleModel = preload("res://scripts/rally/rally_puddles.gd")
var active_compound_id: String = "gravel_normal"
var compound_catalog: Dictionary = {}
var last_local_conditions: Array = [{}, {}, {}, {}]
var _ambient_irradiance_w_m2: float = 0.0
var last_puddle_depths_mm: Array[float] = [0.0, 0.0, 0.0, 0.0]
# §closure-6: prototipo de envolvente espacial tandem-cam (comparación).
# Dos apoyos geométricos longitudinales separados por la longitud de huella.
# Mantener separados: distancia de detección, radio geométrico y radio
# efectivo de rodadura. Flag off por defecto hasta completar comparaciones
# de contacto, manejo y coste. Con geometría activa se revisa cuánto
# filtrado temporal sigue haciendo falta para evitar retraso duplicado.
var tandem_cam_enabled := false
var tandem_cam_patch_scale := 1.0
# v1 presets de diferencial: perfil activo y preset aplicado.
# El perfil activo nunca se toma de un payload: solo de configure().
const DIFFERENTIAL_PRESET_PATH := "powertrain.differential.preset_id"
const LEGACY_DIFFERENTIAL_PATHS: Array[String] = [
	"powertrain.differential.preload_nm",
	"powertrain.differential.power_ramp_angle_deg",
	"powertrain.differential.coast_ramp_angle_deg",
	"powertrain.differential.clutches",
]
var active_profile_id: String = ""
var active_differential_preset_id: String = ""


func configure(asset_document: Dictionary, manifest_path: String = PROFILE_PATH) -> Dictionary:
	asset_manifest = asset_document
	var loaded := VehicleProfileLoader.load_profile(manifest_path)
	if not bool(loaded.get("ok", false)):
		return loaded
	profile = loaded["manifest"]
	domains = loaded["domains"]
	var mass_result := mass_model.configure(domains, asset_manifest)
	if not bool(mass_result.get("ok", false)):
		return mass_result
	mass_state = mass_model.resolve(mass_model.fuel_initial_kg)
	var suspension_result := suspension_model.configure(
		domains,
		asset_manifest.get("geometry", { }),
		mass_state,
	)
	if not bool(suspension_result.get("ok", false)):
		return suspension_result
	tire_model.configure(
		domains,
		loaded["resolved_tire_filters"],
		suspension_model.static_corner_loads_n,
	)
	var powertrain_result := powertrain_model.configure(domains)
	if not bool(powertrain_result.get("ok", false)):
		return powertrain_result
	brake_model.configure(domains)
	aero_model.configure(domains)
	var thermal_result := thermal_model.configure(domains)
	if not bool(thermal_result.get("ok", false)):
		return thermal_result
	underfloor_document = domains \
			.get("underfloor_contact", { }) \
			.get("underfloor_contact", { }) \
			.duplicate(true)
	var steering: Dictionary = domains.get("steering", { }).get("steering", { })
	maximum_steering_angle_rad = float(
		steering.get("max_steering_angle", maximum_steering_angle_rad)
	)
	steering_exponent = float(steering.get("steering_exponent", 1.0))
	front_steering_ratio = float(steering.get("front_steering_ratio", 1.0))
	rear_steering_ratio = float(steering.get("rear_steering_ratio", 0.0))
	ackermann = float(steering.get("ackermann", 0.0))
	var coupled: Dictionary = domains.get("coupled_world", { }).get("coupled_world", { })
	var coupled_suspension: Dictionary = coupled.get("suspension", { })

	# 1. Prioridad a enteros directos (subpasos por tick o frecuencia en Hz)
	configured_substeps_per_tick = int(coupled_suspension.get(
		"substeps_per_tick",
		coupled.get("substeps_per_tick", 0)
	))
	configured_substep_hz = int(coupled_suspension.get(
		"substep_frequency_hz",
		coupled.get("physical_frequency_hertz", 0)
	))

	# 2. Respaldo legado solo si el JSON viejo no define enteros
	if configured_substeps_per_tick <= 0 and configured_substep_hz <= 0:
		maximum_substep_seconds = maxf(float(coupled.get("maximum_substep_seconds", 0.002)), 0.0005)
		maximum_substep_seconds = maxf(
			float(coupled_suspension.get("maximum_substep_seconds", maximum_substep_seconds)),
			0.0005,
		)
	var pivot_doc: Dictionary = asset_manifest.get("wheel_pivots", { })
	wheel_positions_local.clear()
	wheel_radii.clear()
	wheel_widths.clear()
	for key in WHEEL_KEYS:
		var wheel_doc: Dictionary = pivot_doc.get(key, { })
		wheel_positions_local.append(
			_vector_from_document(wheel_doc.get("center_metres", { }), Vector3.ZERO)
		)
		wheel_radii.append(float(wheel_doc.get("radius_metres", 0.28)))
		wheel_widths.append(float(wheel_doc.get("width_metres", 0.2)))
	if wheel_positions_local.size() != 4 or wheel_radii.size() != 4:
		return {
			"ok": false,
			"error": "Ford asset manifest must define four wheel pivots and radii.",
		}
	wheelbase_m = absf(wheel_positions_local[2].z - wheel_positions_local[0].z)
	var aids: Dictionary = domains.get("driving_assistance", { }).get("aids", { })
	assistance_available = {
		"traction_control": bool(aids.get("traction_control_available", false)),
		"stability": bool(aids.get("stability_available", false)),
		"anti_lock_brakes": bool(aids.get("abs_available", false)),
		"automatic_transmission": bool(powertrain_model.automatic_transmission),
	}
	active_profile_id = str(loaded.get("profile_id", ""))
	_apply_default_differential_preset()
	setup_design_values = filter_garage_values(RallySetupCatalog.defaults(domains))
	_capture_setup_design()
	set_compound(active_compound_id)
	return {
		"ok": true,
		"profile_id": str(loaded.get("profile_id", "")),
	}


func set_compound(compound_id: String, catalog: Dictionary = {}) -> bool:
	var cat: Dictionary = catalog if not catalog.is_empty() else compound_catalog
	if cat.is_empty():
		cat = RallyTireCompound.load_catalog()
	var definitions: Dictionary = cat.get("compounds", {})
	if not definitions.has(compound_id):
		push_warning("Unknown tire compound: " + compound_id)
		return false
	# Both physics models receive exactly the same resolved catalog.
	if not thermal_model.set_compound(compound_id, cat):
		return false
	if not tire_model.set_compound(compound_id, cat):
		return false
	compound_catalog = cat
	active_compound_id = compound_id
	return true


func get_compound_catalog() -> Dictionary:
	return RallyTireCompound.load_catalog()

func set_weather_controller(controller) -> void:
	weather_controller = controller


# Entorno térmico de Single Stage/práctica: sin calendario no hay proveedor
# climático, así que la sesión fija aire/suelo/irradiancia/agua/nieve desde
# el perfil regional (misma fuente que el scheduler de eventos).
var practice_thermal_override := false
var practice_air_c := 25.0
var practice_ground_c := 30.0
var practice_water_mm := 0.0
var practice_snow_mm := 0.0
var practice_irradiance_w_m2 := 0.0


func set_practice_thermal_environment(thermal: Dictionary) -> void:
	if thermal.is_empty():
		practice_thermal_override = false
		return
	practice_air_c = float(thermal.get("air_c", 25.0))
	practice_ground_c = float(thermal.get("ground_c", 30.0))
	practice_water_mm = maxf(float(thermal.get("water_mm", 0.0)), 0.0)
	practice_snow_mm = maxf(float(thermal.get("snow_mm", 0.0)), 0.0)
	practice_irradiance_w_m2 = maxf(float(thermal.get("irradiance_w_m2", 0.0)), 0.0)
	practice_thermal_override = true


func sync_ambient_conditions() -> void:
	# Sincroniza aire/irradiancia del clima sin esperar al primer paso de
	# física (necesario antes de precalentar neumáticos al salir a tramo).
	_sync_ambient_air_temperature()


func _sync_ambient_air_temperature() -> void:
	# El reloj climático publica el aire físico en current_blend; el visual es independiente.
	var fallback := float(thermal_model.tire_config.get("ambient_fallback_c", 25.0))
	var air_c := fallback
	var irradiance := 0.0
	if weather_controller != null and bool(weather_controller.get("calendar_active")):
		var weather: Dictionary = weather_controller.current_blend
		var candidate: Variant = weather.get("air_c", null)
		if (candidate is float or candidate is int) and is_finite(float(candidate)):
			air_c = clampf(float(candidate), -40.0, 60.0)
		irradiance = maxf(float((weather.get("climate", {}) as Dictionary).get("irradiance_w_m2", 0.0)), 0.0)
	elif practice_thermal_override:
		air_c = clampf(practice_air_c, -40.0, 60.0)
		irradiance = practice_irradiance_w_m2
	thermal_model.ambient_temperature_c = air_c
	_ambient_irradiance_w_m2 = irradiance


func local_conditions_for_wheel(index: int, surface_name: String) -> Dictionary:
	if index < 0 or index >= wheel_contact_points.size():
		return {}
	# Read-only query: step() owns the last completed wheel publication.
	return _local_conditions_at_contact(surface_name, wheel_contact_points[index], wheel_loads[index] > 0.0)


func _local_conditions_at_contact(surface_name: String, position: Vector3, loaded: bool) -> Dictionary:
	var local := {"air_c": thermal_model.ambient_temperature_c, "ground_c": 30.0,
		"water_mm": 0.0, "snow_mm": 0.0, "surface_name": surface_name,
		"puddle_depth_mm": 0.0, "puddle_drag": 0.0, "irradiance_w_m2": 0.0}
	if weather_controller != null and weather_controller.get("calendar_active"):
		var weather: Dictionary = weather_controller.call("local_conditions_for_contact", surface_name, position) if loaded else weather_controller.current_blend
		local.merge(weather, true)
		local["irradiance_w_m2"] = maxf(float((local.get("climate", {}) as Dictionary).get("irradiance_w_m2", 0.0)), 0.0)
	elif practice_thermal_override:
		local["air_c"] = practice_air_c
		local["ground_c"] = practice_ground_c
		local["water_mm"] = practice_water_mm
		local["snow_mm"] = practice_snow_mm
		local["irradiance_w_m2"] = practice_irradiance_w_m2
	if loaded and is_instance_valid(puddle_system):
		var puddle: Dictionary = puddle_system.sample_contact(position)
		local["puddle_depth_mm"] = float(puddle.depth_mm)
		local["puddle_drag"] = float(puddle.drag)
		local["water_mm"] = maxf(float(local.get("water_mm", 0.0)), float(puddle.depth_mm))
	if loaded and is_instance_valid(river_system):
		# Agua de cauce y parche se combinan tomando el máximo; se propagan
		# los parámetros del origen elegido. Se conserva el máximo con el
		# agua climática para los consumidores actuales (neumáticos,
		# telemetría, VFX leen puddle_depth_mm/puddle_drag).
		var river: Dictionary = river_system.sample_contact(position)
		var river_depth := float(river.get("depth_mm", 0.0))
		if river_depth > float(local.get("puddle_depth_mm", 0.0)):
			local["puddle_depth_mm"] = river_depth
			local["puddle_drag"] = float(river.get("drag_scale", 1.25))
		local["water_mm"] = maxf(float(local.get("water_mm", 0.0)), river_depth)
		local["river_depth_mm"] = river_depth
		local["river_channel_id"] = str(river.get("channel_id", ""))
	local["surface_name"] = surface_name
	return local


func surface_temperature_for_hud() -> Dictionary:
	if weather_controller != null and weather_controller.has_method("surface_temperature_at_vehicle"):
		return weather_controller.call("surface_temperature_at_vehicle")
	return {"ok": false, "text": "—"}


func adjust_live_tire_pressure(delta_kpa: float) -> void:
	var pressure: Dictionary = domains.get("tires", { }).get("tires", { }).get("pressure", { })
	var cold: Dictionary = pressure.get("cold_kpa_gauge", { })
	var reference_temp := float(pressure.get("reference_temperature_c", 25.0))
	for i in 4:
		var key: String = ["FL", "FR", "RL", "RR"][i]
		var field := RallySetupCatalog.field_for_path("tires.pressure.cold_kpa_gauge." + key)
		var next_kpa := clampf(
			float(cold.get(key, 180.0)) + delta_kpa,
			float(field.min),
			float(field.max),
		)
		cold[key] = next_kpa
		# Función común §1: conserva gas, pérdida y fuga; solo cambia la
		# referencia en frío.
		thermal_model.set_pressure_reference(i, next_kpa / 100.0, reference_temp)
	pressure["cold_kpa_gauge"] = cold


func active_differential_profile() -> String:
	if not active_profile_id.is_empty():
		return active_profile_id
	return str(profile.get("vehicle_identifier", ""))


## Modo dual de diferencial (v1):
## historic = presets de catálogo (solo si el perfil está cubierto);
## modern (defecto) = LSD autoblocante moderno totalmente configurable.
func is_historic_differential() -> bool:
	if RallyDifferentialCatalog.differential_mode() != RallyDifferentialCatalog.MODE_HISTORIC:
		return false
	return not RallyDifferentialCatalog.list_for_profile(active_differential_profile()).is_empty()


## Conjunto de valores apto para garaje/snapshots/fábrica según el modo:
## historic cubierto = preset + sin números libres; resto = números + sin preset.
func filter_garage_values(values: Dictionary) -> Dictionary:
	var out := values.duplicate(true)
	if is_historic_differential():
		for legacy_path in LEGACY_DIFFERENTIAL_PATHS:
			out.erase(legacy_path)
		out[DIFFERENTIAL_PRESET_PATH] = active_differential_preset_id
	else:
		out.erase(DIFFERENTIAL_PRESET_PATH)
	return out


func _base_differential_mu() -> Dictionary:
	return {
		"power": float(powertrain_model.base_differential_power_ratio),
		"coast": float(powertrain_model.base_differential_coast_ratio),
	}


func _sync_differential_to_domains(target_domains: Dictionary, resolved: Dictionary) -> void:
	var powertrain: Dictionary = (target_domains.get("powertrain", {}) as Dictionary).get("powertrain", {})
	var differential: Dictionary = powertrain.get("differential", {})
	differential["preset_id"] = str(resolved.get("preset_id", ""))
	differential["type"] = str(resolved.get("type", "clutch_lsd"))
	differential["preload_nm"] = float(resolved.get("preload_nm", 0.0))
	differential["power_ramp_angle_deg"] = float(resolved.get("power_ramp_deg", 45.0))
	differential["coast_ramp_angle_deg"] = float(resolved.get("coast_ramp_deg", 45.0))
	differential["clutches"] = float(resolved.get("active_friction_surfaces", 4))
	differential["clutch_friction_coefficient"] = float(resolved.get("friction_mu_power", 0.0))
	differential["coast_friction_coefficient"] = float(resolved.get("friction_mu_coast", 0.0))
	powertrain["differential"] = differential
	(target_domains.get("powertrain", {}) as Dictionary)["powertrain"] = powertrain


func _apply_default_differential_preset() -> void:
	if not is_historic_differential():
		return
	var pid := active_differential_profile()
	if pid.is_empty():
		return
	var powertrain: Dictionary = domains.get("powertrain", {}).get("powertrain", {})
	var differential: Dictionary = powertrain.get("differential", {})
	var configured_id := str(differential.get("preset_id", ""))
	var wanted := configured_id
	if wanted.is_empty() or not RallyDifferentialCatalog.is_allowed(pid, wanted):
		wanted = RallyDifferentialCatalog.default_for_profile(pid)
	if wanted.is_empty():
		return
	var resolved := RallyDifferentialCatalog.resolve(pid, wanted, _base_differential_mu())
	if not bool(resolved.get("ok", false)):
		push_warning("Diferencial por defecto no resoluble: " + str(resolved.get("error", "")))
		return
	_sync_differential_to_domains(domains, resolved)
	var runtime := powertrain_model.apply_differential_preset(resolved)
	if bool(runtime.get("ok", false)):
		active_differential_preset_id = wanted


func apply_setup_values(values: Dictionary) -> Dictionary:
	# Modo dual v1: historic = presets de catálogo (validación estricta);
	# modern (defecto) = LSD autoblocante moderno libre (números directos).
	# El perfil activo nunca sale del payload.
	var historic := is_historic_differential()
	var pid := active_differential_profile()
	if historic:
		for legacy_path in LEGACY_DIFFERENTIAL_PATHS:
			if values.has(legacy_path):
				return {
					"ok": false,
					"error": "Reglaje de diferencial antiguo incompatible: use el preset " + DIFFERENTIAL_PRESET_PATH + " o restaure fábrica.",
				}
	var incoming := values.duplicate(true)
	var requested_preset: Variant = null
	if historic and incoming.has(DIFFERENTIAL_PRESET_PATH):
		var requested: Variant = incoming[DIFFERENTIAL_PRESET_PATH]
		if not requested is String or (requested as String).is_empty():
			return {
				"ok": false,
				"error": "preset_id inválido.",
			}
		requested_preset = incoming[DIFFERENTIAL_PRESET_PATH]
	incoming.erase(DIFFERENTIAL_PRESET_PATH)
	var validation := RallySetupCatalog.validate(incoming)
	if not bool(validation.get("ok", false)):
		return validation
	var effective_values: Dictionary = (validation as Dictionary).get("values", {}).duplicate(true)
	effective_values["fuel.initial_kg"] = minf(
		float(effective_values.get("fuel.initial_kg", 0.0)),
		mass_model.fuel_capacity_kg,
	)
	# Resolver preset (solicitado > activo > defecto) sin mutar estado.
	var resolved_preset: Dictionary = {}
	if historic:
		var wanted := ""
		if requested_preset is String and not (requested_preset as String).is_empty():
			wanted = str(requested_preset)
		elif not active_differential_preset_id.is_empty():
			wanted = active_differential_preset_id
		else:
			wanted = RallyDifferentialCatalog.default_for_profile(pid)
		if wanted.is_empty():
			return {"ok": false, "error": "Sin preset de diferencial por defecto para: " + pid}
		if requested_preset is String and not (requested_preset as String).is_empty():
			if not RallyDifferentialCatalog.is_allowed(pid, wanted):
				return {"ok": false, "error": "Preset no permitido para este vehículo: " + wanted}
			if not RallyDifferentialCatalog.is_enabled(pid, wanted):
				return {"ok": false, "error": "Preset deshabilitado pendiente de calibración: " + wanted}
		resolved_preset = RallyDifferentialCatalog.resolve(pid, wanted, _base_differential_mu())
		if not bool(resolved_preset.get("ok", false)):
			return resolved_preset
	# Staging atómico (§4): aplicar numérico + diferencial sobre copia y
	# validar el runtime ANTES de publicar domains. apply_differential_preset
	# valida antes de mutar, así que un rechazo deja domains, preset activo
	# y solver intactos. Solo tras superar los pasos que devuelven error se
	# publican domains, ID activo y valores aceptados.
	var staging := domains.duplicate(true)
	var applied := RallySetupCatalog.apply(staging, effective_values)
	if not bool(applied.get("ok", false)):
		return applied
	if historic:
		_sync_differential_to_domains(staging, resolved_preset)
		var runtime := powertrain_model.apply_differential_preset(resolved_preset)
		if not bool(runtime.get("ok", false)):
			return runtime
	# Commit: a partir de aquí el runtime se sincroniza desde staging.
	domains = staging
	if historic:
		active_differential_preset_id = str(resolved_preset.get("preset_id", ""))
		effective_values[DIFFERENTIAL_PRESET_PATH] = active_differential_preset_id
	else:
		# Modern: sin preset activo; el solver usa los números libres.
		active_differential_preset_id = ""
	var fuel: Dictionary = domains.get("fuel", { }).get("fuel", { })
	var fuel_kg := clampf(
		float(fuel.get("initial_kg", mass_model.fuel_initial_kg)),
		0.0,
		mass_model.fuel_capacity_kg,
	)
	mass_model.fuel_initial_kg = fuel_kg
	mass_state = mass_model.resolve(fuel_kg)
	thermal_model.fuel_remaining_litres = fuel_kg / maxf(
		mass_model.fuel_density_kg_per_litre,
		0.000001,
	)
	var suspension: Dictionary = domains.get("suspension", { }).get("suspension", { })
	var physical: Dictionary = suspension.get("geometry_physical", { })
	for axle_index in 2:
		var axle := "front" if axle_index == 0 else "rear"
		var trim: Dictionary = suspension.get(axle, { })
		var design: Dictionary = setup_design_axles[axle_index]
		var stop_base := maxf(float(design.get("stop_multiplier", 1.0)), 0.000001)
		var stop_multiplier := float(trim.get("bump_stop_multiplier", stop_base)) / stop_base
		var bump_stop_mult := float(design.get("physical_bump_stop_multiplier", 1.0)) * stop_multiplier
		for wheel_index in ([0, 1] if axle_index == 0 else [2, 3]):
			var parameters: Dictionary = suspension_model.axle_parameters[wheel_index]
			parameters.camber = float(trim.get("camber", 0.0))
			parameters.toe = float(trim.get("toe", 0.0))
			# Precarga (§3): el offset desplaza el neutro sin cambiar la masa
			# de referencia ni la frecuencia vigente; conserva equilibrio
			# total y longitudinal. Registrar la decisión antes de cambiar
			# perfiles o fuerzas y comprobar frecuencias dentro de tolerancia.
			var current_rest := float(trim.get("spring_length", 0.3)) * float(
				trim.get("resting_ratio", 0.35)
			)
			parameters.rest_compression_offset = current_rest - float(
				design.get("rest_compression", current_rest)
			)
			# Cálculo compartido §6: misma precedencia de frecuencia
			# declarada y misma masa de referencia ya calibrada que en
			# configure(). Geometría y joints quedan fuera.
			var reference_mass := float(parameters.frequency_reference_mass_kg)
			var frequency := float(trim.get("ride_frequency_hz", parameters.ride_frequency_hz))
			var rates := VehicleSuspensionModel.corner_rates(
				reference_mass,
				frequency,
				float(trim.get("damping_ratio", 0.65)),
				float(trim.get("bump_damp_multiplier", 1.0)),
				float(trim.get("rebound_damp_multiplier", 1.0)),
				bump_stop_mult
			)
			parameters.ride_frequency_hz = frequency
			parameters.spring_rate = float(rates["spring_rate"])
			parameters.bump_damping = float(rates["bump_damping"])
			parameters.rebound_damping = float(rates["rebound_damping"])
			parameters.bump_stop_stiffness = float(rates["bump_stop_stiffness"])
			suspension_model.axle_parameters[wheel_index] = parameters
		var arb: Dictionary = physical.get(axle + "_arb", { })
		var spring_rate := float(suspension_model.axle_parameters[axle_index * 2].spring_rate)
		if axle_index == 0:
			suspension_model.front_arb_stiffness_n_per_m = VehicleSuspensionModel.arb_stiffness_n_per_m(
				spring_rate, float(arb.get("ratio", 0.0))
			)
		else:
			suspension_model.rear_arb_stiffness_n_per_m = VehicleSuspensionModel.arb_stiffness_n_per_m(
				spring_rate, float(arb.get("ratio", 0.0))
			)
	var brakes: Dictionary = domains.get("brakes", { }).get("brakes", { })
	brake_model.front_brake_bias = clampf(float(brakes.get("front_brake_bias", 0.5)), 0.0, 1.0)
	brake_model.maximum_brake_torque_nm = float(
		brakes.get("max_brake_torque", brake_model.maximum_brake_torque_nm)
	)
	var powertrain: Dictionary = domains.get("powertrain", { }).get("powertrain", { })
	var differential: Dictionary = powertrain.get("differential", { })
	powertrain_model.maximum_rpm = float(powertrain.get("max_rpm", powertrain_model.maximum_rpm))
	powertrain_model.final_drive_gravel = float(powertrain.get("final_drive_gravel", powertrain_model.final_drive_gravel))
	powertrain_model.final_drive_tarmac = float(powertrain.get("final_drive_tarmac", powertrain_model.final_drive_tarmac))
	var _preset := str(powertrain.get("final_drive_preset", ""))
	if _preset == "gravel" and powertrain_model.final_drive_gravel > 0.0:
		powertrain_model.final_drive_ratio = powertrain_model.final_drive_gravel
	elif _preset == "tarmac" and powertrain_model.final_drive_tarmac > 0.0:
		powertrain_model.final_drive_ratio = powertrain_model.final_drive_tarmac
	else:
		powertrain_model.final_drive_ratio = float(
			powertrain.get("final_drive", powertrain_model.final_drive_ratio)
		)
	var _fw: Dictionary = powertrain.get("freewheel", {})
	if not _fw.is_empty():
		powertrain_model.freewheel_enabled = bool(_fw.get("enabled", powertrain_model.freewheel_enabled))
		powertrain_model.freewheel_idle_rpm = maxf(float(_fw.get("idle_rpm", powertrain_model.freewheel_idle_rpm)), 400.0)
	if powertrain.has("gear_ratios") and powertrain["gear_ratios"] is Array:
		var gr: Array = powertrain["gear_ratios"]
		powertrain_model.gear_ratios.clear()
		for r in gr:
			powertrain_model.gear_ratios.append(float(r))
		powertrain_model.maximum_forward_gear = powertrain_model.gear_ratios.size()
	if powertrain.has("reverse_ratio"):
		powertrain_model.reverse_ratio = -absf(float(powertrain.get("reverse_ratio", powertrain_model.reverse_ratio)))
	# Sincronía de diferenciales (hallazgo 3): en AWD cada eje se alimenta
	# de su bloque (differential_front/rear); en FWD/RWD el bloque histórico
	# alimenta el espejo y el eje motriz. Los bloques llegan validados del
	# perfil o acotados del garaje; uno inválido conserva los valores en curso.
	powertrain_model.sync_setup_differentials(
		differential,
		powertrain.get("differential_front", null),
		powertrain.get("differential_rear", null)
	)
	powertrain_model.engine_rpm = minf(
		powertrain_model.engine_rpm,
		powertrain_model.maximum_rpm + 200.0,
	)
	var steering: Dictionary = domains.get("steering", { }).get("steering", { })
	maximum_steering_angle_rad = float(
		steering.get("max_steering_angle", maximum_steering_angle_rad)
	)
	var aero: Dictionary = domains.get("aerodynamics", { }).get("aero", { })
	aero_model.aero_model = aero.get("model", { }).duplicate(true)
	var pressure: Dictionary = domains.get("tires", { }).get("tires", { }).get("pressure", { })
	var cold_pressures: Dictionary = pressure.get("cold_kpa_gauge", { })
	var temperature_reference := float(pressure.get("reference_temperature_c", 25.0))
	for wheel_index in 4:
		var wheel_key: String = ["FL", "FR", "RL", "RR"][wheel_index]
		var cold_bar := float(cold_pressures.get(wheel_key, 180.0)) / 100.0
		# Función común §1: actualiza la referencia en frío y refleja la
		# pérdida existente en la misma llamada; conserva gas y fuga.
		thermal_model.set_pressure_reference(wheel_index, cold_bar, temperature_reference)
	return { "ok": true, "values": effective_values }


func _capture_setup_design() -> void:
	setup_design_axles.clear()
	var suspension: Dictionary = domains.get("suspension", { }).get("suspension", { })
	var physical: Dictionary = suspension.get("geometry_physical", { })
	for axle in ["front", "rear"]:
		var elements: Dictionary = physical.get(axle, { })
		var trim: Dictionary = suspension.get(axle, { })
		setup_design_axles.append(
			{
				"bump_damping": float(elements.get("damper_bump_Ns_per_m", 0.0)),
				"rebound_damping": float(elements.get("damper_rebound_Ns_per_m", 0.0)),
				"physical_bump_stop_multiplier": float(elements.get("bump_stop_mult", 1.0)),
				"damping_ratio": float(trim.get("damping_ratio", 1.0)),
				"bump_multiplier": float(trim.get("bump_damp_multiplier", 1.0)),
				"rebound_multiplier": float(trim.get("rebound_damp_multiplier", 1.0)),
				"stop_multiplier": float(trim.get("bump_stop_multiplier", 1.0)),
				"rest_compression": float(trim.get("spring_length", 0.3))
				* float(trim.get("resting_ratio", 0.35)),
			}
		)


func bind_wheel_visuals(pivots: Array[Node3D], visuals: Array[Node3D]) -> void:
	wheel_visual_pivots = pivots
	wheel_visuals = visuals


func create_wheel_contact_casts(body: RigidBody3D) -> void:
	unsprung_rig.create(body, wheel_positions_local, mass_model.unsprung_mass_kg, suspension_model)
	for old_cast in wheel_contact_casts:
		old_cast.queue_free()
	wheel_contact_casts.clear()
	for i in 4:
		var cast := ShapeCast3D.new()
		cast.name = "WheelContact_" + WHEEL_KEYS[i]
		var cylinder := CylinderShape3D.new()
		cylinder.radius = wheel_radii[i]
		cylinder.height = wheel_widths[i]
		cast.shape = cylinder
		cast.enabled = false
		cast.margin = 0.002
		cast.max_results = 8
		cast.collide_with_areas = false
		cast.collide_with_bodies = true
		body.add_child(cast)
		cast.add_exception_rid(body.get_rid())
		for hub in unsprung_rig.hubs:
			cast.add_exception_rid(hub.get_rid())
		wheel_contact_casts.append(cast)


## Selección del apoyo ShapeCast (§3): el apoyo con máxima alineación con +Y
## por encima de 0.25. Devuelve punto, normal, collider, índice y alineación,
## SIN fracción segura: Godot 4.7.1 no expone fracción por colisión (solo
## `get_closest_collision_safe_fraction()` global), así que la distancia
## coherente se obtiene aislando este apoyo en una consulta adicional
## (`_query_shapecast_contact()`). En pendiente no se proyecta el punto como
## si viniera de un rayo: la altura sale del barrido del cilindro.
## Devuelve {} sin apoyo válido.
static func select_shapecast_support(cast: ShapeCast3D, chassis_up: Vector3) -> Dictionary:
	var best := {}
	var best_alignment := 0.25
	for collision_index in cast.get_collision_count():
		var normal := (cast.get_collision_normal(collision_index) as Vector3).normalized()
		var alignment := normal.dot(chassis_up)
		if alignment > best_alignment:
			best_alignment = alignment
			best = {
				"position": cast.get_collision_point(collision_index),
				"normal": normal,
				"collider": cast.get_collider(collision_index),
				"collision_index": collision_index,
				"alignment": alignment,
				"collision_count": cast.get_collision_count(),
			}
	return best


## Barrido cilíndrico coherente (H2), núcleo estático: punto, normal, collider
## y distancia del MISMO apoyo. Tras seleccionar por alineación, si hay más
## de una colisión se aísla el apoyo seleccionado excluyendo los demás
## colliders y se repite el barrido: la fracción leída entonces pertenece
## por construcción al apoyo seleccionado (se verifica collider, punto y
## normal). Con una sola colisión no hace falta consulta adicional.
## `permanent_exceptions` se restauran antes de salir. `sweeps` cuenta los
## barridos (1 o 2). La coherencia se demuestra por correspondencia, no por
## el rango [0,1]. Sin llamada a get_collision_safe_fraction(i): no existe
## en Godot 4.7.1.
static func shapecast_coherent_result(
	cast: ShapeCast3D,
	chassis_up: Vector3,
	wheel_radius_m: float,
	travel_m: float,
	bump_m: float,
	permanent_exceptions: Array[RID],
) -> Dictionary:
	cast.force_shapecast_update()
	var sweeps := 1
	var first_count := cast.get_collision_count()
	if first_count == 0:
		return {"sweeps": sweeps}
	var global_safe := cast.get_closest_collision_safe_fraction()
	var selected := select_shapecast_support(cast, chassis_up)
	if selected.is_empty():
		return {"sweeps": sweeps}
	if first_count == 1:
		var safe := global_safe
		return {
			"position": selected["position"],
			"normal": selected["normal"],
			"collider": selected["collider"],
			"distance": float(wheel_radius_m) + float(travel_m) * float(safe) - float(bump_m),
			"safe_fraction": float(safe),
			"global_safe_fraction": float(safe),
			"collision_index": int(selected["collision_index"]),
			"collision_count": first_count,
			"alignment": float(selected["alignment"]),
			"isolated": false,
			"coherent": true,
			"sweeps": sweeps,
		}
	# Múltiples apoyos: aislar el seleccionado excluyendo los demás.
	var selected_collider: Variant = selected.get("collider")
	var selected_rid := RID()
	if selected_collider is CollisionObject3D:
		selected_rid = (selected_collider as CollisionObject3D).get_rid()
	var exclude_rids: Array[RID] = []
	for ci in first_count:
		if ci == int(selected["collision_index"]):
			continue
		var other: Variant = cast.get_collider(ci)
		if other is CollisionObject3D:
			var orid := (other as CollisionObject3D).get_rid()
			if orid != selected_rid and not exclude_rids.has(orid):
				exclude_rids.append(orid)
	if exclude_rids.is_empty():
		var safe := global_safe
		return {
			"position": selected["position"],
			"normal": selected["normal"],
			"collider": selected["collider"],
			"distance": float(wheel_radius_m) + float(travel_m) * float(safe) - float(bump_m),
			"safe_fraction": float(safe),
			"global_safe_fraction": float(global_safe),
			"collision_index": int(selected["collision_index"]),
			"collision_count": first_count,
			"alignment": float(selected["alignment"]),
			"isolated": false,
			"coherent": true,
			"sweeps": sweeps,
		}
	for rid in exclude_rids:
		cast.add_exception_rid(rid)
	cast.force_shapecast_update()
	sweeps = 2
	var isolated_safe := cast.get_closest_collision_safe_fraction()
	var isolated_count := cast.get_collision_count()
	var isolated_ok := isolated_count > 0
	var isolated_collider: Variant = cast.get_collider(0) if isolated_ok else null
	var isolated_point: Vector3 = cast.get_collision_point(0) if isolated_ok else selected["position"]
	var isolated_normal: Vector3 = (cast.get_collision_normal(0) as Vector3).normalized() if isolated_ok else selected["normal"]
	# Restaurar exclusiones permanentes antes de salir.
	cast.clear_exceptions()
	for prid in permanent_exceptions:
		cast.add_exception_rid(prid)
	if not isolated_ok:
		return {"sweeps": sweeps}
	var same_collider: bool = isolated_collider == selected_collider
	var point_gap := (isolated_point - (selected["position"] as Vector3)).length()
	var normal_gap := (isolated_normal - (selected["normal"] as Vector3)).length()
	var coherent: bool = same_collider and point_gap < 0.05 and normal_gap < 0.05
	return {
		"position": isolated_point,
		"normal": isolated_normal,
		"collider": isolated_collider,
		"distance": float(wheel_radius_m) + float(travel_m) * float(isolated_safe) - float(bump_m),
		"safe_fraction": float(isolated_safe),
		"global_safe_fraction": float(global_safe),
		"collision_index": int(selected["collision_index"]),
		"collision_count": first_count,
		"isolated_collision_count": isolated_count,
		"alignment": float(selected["alignment"]),
		"isolated": true,
		"coherent": coherent,
		"sweeps": sweeps,
		"verify": {
			"same_collider": same_collider,
			"point_gap_m": point_gap,
			"normal_gap": normal_gap,
		},
	}


func _query_shapecast_contact(
	body: RigidBody3D,
	index: int,
	body_transform: Transform3D,
	chassis_up: Vector3,
	bump: float,
	travel: float,
	steer: float,
) -> Dictionary:
	var cast := wheel_contact_casts[index]
	var orientation := Basis(Vector3.UP, steer) * Basis(
		Vector3.FORWARD,
		suspension_model.dynamic_wheel_camber(index),
	) * Basis(Vector3.BACK, PI * 0.5)
	cast.global_transform = body_transform * Transform3D(
		orientation,
		wheel_positions_local[index] + Vector3.UP * bump,
	)
	cast.target_position = orientation.inverse() * (Vector3.DOWN * travel)
	cast.collision_mask = body.collision_mask
	var permanents: Array[RID] = [body.get_rid()]
	for hub in unsprung_rig.hubs:
		permanents.append(hub.get_rid())
	var hit := shapecast_coherent_result(cast, chassis_up, wheel_radii[index], travel, bump, permanents)
	contact_query_count += int(hit.get("sweeps", 1))
	hit.erase("sweeps")
	return hit


func _query_tandem_contact(
	body: RigidBody3D, state: PhysicsDirectBodyState3D, index: int, steer: float,
	bump: float, travel: float,
) -> Dictionary:
	var up := state.transform.basis.y.normalized()
	var forward := (state.transform.basis * Vector3.FORWARD.rotated(Vector3.UP, steer)).normalized()
	var center := state.transform * wheel_positions_local[index]
	var patch := float(tire_model.states[index].get("dynamic_contact_patch_m", tire_model.base_contact_patch_m[index]))
	var supports := tandem_cam_supports(patch, tandem_cam_patch_scale)
	var excluded: Array[RID] = [body.get_rid()]
	for hub in unsprung_rig.hubs:
		excluded.append(hub.get_rid())
	var hits: Array[Dictionary] = []
	for offset in supports:
		var origin := center + forward * offset + up * bump
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin - up * (travel + wheel_radii[index]), body.collision_mask, excluded
		)
		var sample := state.get_space_state().intersect_ray(query)
		contact_query_count += 1
		if not sample.is_empty() and (sample.normal as Vector3).dot(up) <= 0.25:
			sample = {}
		hits.append(sample)
	var rear := hits[0]
	var front := hits[1]
	var front_height := ((front.position as Vector3) - center).dot(up) if not front.is_empty() else 0.0
	var rear_height := ((rear.position as Vector3) - center).dot(up) if not rear.is_empty() else 0.0
	var envelope := tandem_cam_effective_height(front_height, not front.is_empty(), rear_height, not rear.is_empty())
	if not bool(envelope.contact):
		return {}
	var dominant := front if rear.is_empty() or (not front.is_empty() and front_height >= rear_height) else rear
	var normal: Vector3 = dominant.normal
	var position: Vector3 = dominant.position
	if bool(envelope.both_contact):
		normal = ((front.normal as Vector3) + (rear.normal as Vector3)).normalized()
		position = ((front.position as Vector3) + (rear.position as Vector3)) * 0.5
	return {"position": position, "normal": normal, "collider": dominant.collider, "distance": -float(envelope.height)}


func step(body: RigidBody3D, state: PhysicsDirectBodyState3D, inputs: Dictionary) -> void:
	var dt := state.step
	if dt <= 0.0 or wheel_positions_local.size() != 4 or wheel_contact_casts.size() != 4:
		return
	last_step_seconds = dt
	_sync_ambient_air_temperature()
	if contact_frequency_samples < 120:
		contact_frequency_samples += 1
		contact_frequency_elapsed_s += dt
		if contact_frequency_samples == 120:
			print(
				"RALLY_CONTACT_FREQUENCY ",
				JSON.stringify(
					{
						"query_type": "tandem_cam" if tandem_cam_enabled else "ShapeCast3D",
						"wheel_count": wheel_contact_casts.size(),
						"configured_hz": Engine.physics_ticks_per_second,
						"integration_hz": contact_frequency_samples / contact_frequency_elapsed_s,
						"dt_s": dt,
					}
				),
			)

	var chassis_up := state.transform.basis.y.normalized()
	var com_world := state.transform * body.center_of_mass
	var contacts: Array[Dictionary] = []
	contact_query_count = 0
	for i in 4:
		var cast := wheel_contact_casts[i]
		# Alcance §2: deriva del mismo límite efectivo que usa la junta
		# (droop + JOINT_LIMIT_MARGIN_M). Distancia referida al centro neutro.
		var query := UnsprungSuspensionRig.contact_query_travel_m(
			float(suspension_model.axle_parameters[i].get("bump_m", 0.22)),
			float(suspension_model.axle_parameters[i].get("droop_m", 0.18))
		)
		var bump: float = query["bump"]
		var travel: float = query["travel"]
		var steer := _wheel_steer_angle(i, float(inputs.get("steering", 0.0))) + _effective_toe(i)
		var hit: Dictionary = {}
		var ray_distance := 0.0
		if tandem_cam_enabled:
			hit = _query_tandem_contact(body, state, i, steer, bump, travel)
			ray_distance = float(hit.get("distance", 0.0))
		else:
			# Coherencia H2: barrido cilíndrico del MISMO apoyo (aislado si
			# hay varios). Sin llamada a get_collision_safe_fraction(i):
			# no existe en Godot 4.7.1.
			hit = _query_shapecast_contact(body, i, state.transform, chassis_up, bump, travel, steer)
			ray_distance = float(hit.get("distance", 0.0))
		if hit.is_empty():
			# Rama sin impacto (§1): el rig es el escritor único del estado
			# físico (recorrido/velocidad/contactos) y lo resolverá en
			# UnsprungSuspensionRig.solve() desde la medida hub-vs-chasis.
			# Aquí solo se registra la ausencia de contacto geométrico; no se
			# llama a set_airborne() (legado) porque sus escrituras quedaban
			# sobrescritas en el mismo tick. La distinción geométrico vs carga
			# positiva la resuelve el rig (`geometric_contact` vs
			# `contact_active = carga > 0`).
			wheel_loads[i] = 0.0
			wheel_surfaces[i] = "Unknown"
			contacts.append({ "hit": false })
			continue
		wheel_contact_points[i] = hit["position"]
		wheel_contact_normals[i] = (hit["normal"] as Vector3).normalized()
		wheel_surfaces[i] = _surface_for_collider(hit.get("collider"))
		var winter_layer_id := ""
		var audio_surface := wheel_surfaces[i]
		var contact_collider: Variant = hit.get("collider")
		if contact_collider is CollisionObject3D:
			winter_layer_id = str(contact_collider.get_meta("winter_layer_id", ""))
			audio_surface = str(contact_collider.get_meta("audio_surface", audio_surface))
		contacts.append(
			{
				"hit": true,
				"position": wheel_contact_points[i],
				"normal": wheel_contact_normals[i],
				"distance": ray_distance,
				"surface": wheel_surfaces[i],
				"collider": hit.get("collider"),
				"winter_layer_id": winter_layer_id,
				"audio_surface": audio_surface,
				"safe_fraction": float(hit.get("safe_fraction", 0.0)),
				"global_safe_fraction": float(hit.get("global_safe_fraction", hit.get("safe_fraction", 0.0))),
				"support_index": int(hit.get("collision_index", -1)),
				"support_alignment": float(hit.get("alignment", 0.0)),
				"collision_count": int(hit.get("collision_count", 1)),
				"isolated": bool(hit.get("isolated", false)),
				"coherent": bool(hit.get("coherent", true)),
				"verify": hit.get("verify", {}),
				"query_bump_m": bump,
				"query_travel_m": travel,
			}
		)

	last_contacts = contacts.duplicate(true)
	var normal_loads := unsprung_rig.solve(
		state,
		suspension_model,
		contacts,
		wheel_radii,
		domains,
		thermal_model,
	)
	var fade_factors: Array[float] = []
	for i in 4:
		fade_factors.append(thermal_model.brake_fade_factor(i))
	var brake_torques := brake_model.evaluate(
		float(inputs.get("brake", 0.0)),
		float(inputs.get("handbrake", 0.0)),
		fade_factors,
	)
	var brake_demand := brake_torques.duplicate()
	for i in 4:
		brake_torques[i] *= (1.0 - brake_collision_loss[i]) * thermal_model.brake_wear_factor(i)
	var tire_powers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var rig_n := int(unsprung_rig.coupled_substeps)
	var target_count := 1
	if configured_substeps_per_tick > 0:
		# Modo entero directo: p. ej. 2, 3 o 6 subpasos por tick
		target_count = configured_substeps_per_tick
	elif configured_substep_hz > 0:
		# Modo por frecuencia entera: p. ej. 360 Hz / 60 Hz = 6 subpasos exactos
		var base_hz := maxi(1, Engine.physics_ticks_per_second)
		target_count = maxi(1, roundi(float(configured_substep_hz) / float(base_hz)))
	else:
		# Fallback legado con margen epsilon (-1e-5) para evitar saltos por error de float en ceili()
		target_count = maxi(1, ceili((dt - 1.0e-5) / maximum_substep_seconds))

	var count := maxi(rig_n, target_count)
	var h := dt / float(count)
	var force_weight := 1.0 / float(count)

	var substep_linear_vel := state.linear_velocity
	var substep_angular_vel := state.angular_velocity
	var effective_chassis_mass := maxf(body.mass, 100.0)

	var tire_thermal_states: Array[Dictionary] = []
	var thermal_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_cambers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_slip_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_surfaces: Array[String] = ["Gravel", "Gravel", "Gravel", "Gravel"]
	var thermal_vx: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_fy: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_water: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_snow: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_ground: Array[float] = [30.0, 30.0, 30.0, 30.0]
	var thermal_air: Array[float] = [25.0, 25.0, 25.0, 25.0]
	var thermal_irradiance: Array[float] = [0.0, 0.0, 0.0, 0.0]

	for i in 4:
		var contact: Dictionary = contacts[i]
		var loaded_contact := bool(contact.get("hit", false)) and normal_loads[i] > 0.0
		var local := _local_conditions_at_contact(str(contact.get("surface", "Unknown")), contact.get("position", wheel_contact_points[i]), loaded_contact)
		var current_puddle_depth := float(local.get("puddle_depth_mm", 0.0))
		var depth_rate := maxf(current_puddle_depth - last_puddle_depths_mm[i], 0.0) / maxf(dt, 0.001)
		last_puddle_depths_mm[i] = current_puddle_depth
		local["puddle_depth_rate"] = depth_rate
		thermal_water[i] = float(local.get("water_mm", 0.0))
		thermal_snow[i] = float(local.get("snow_mm", 0.0))
		thermal_ground[i] = float(local.get("ground_c", 30.0))
		thermal_air[i] = float(local.get("air_c", thermal_model.ambient_temperature_c))
		thermal_irradiance[i] = float(local.get("irradiance_w_m2", 0.0))
		if loaded_contact:
			last_local_conditions[i] = local.duplicate(true)
		else:
			last_local_conditions[i] = {}
		thermal_model.advance_tire_pressure(i, dt)
		tire_thermal_states.append(thermal_model.get_tire_thermal_state_snapshot(i))

	_tire_thermal_elapsed += dt
	for _substep_index in count:
		_prepare_powertrain(h, inputs)
		var tire_reactions: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var substep_force_sum := Vector3.ZERO

		for i in 4:
			var contact: Dictionary = contacts[i]
			tire_model.states[i].radial_deflection_m = unsprung_rig.radial_deflection_m[i]
			wheel_loads[i] = normal_loads[i]
			# Subpasos acoplados Q5: alimentar el neumático con la Fz y la
			# deflexión de ESE subpaso (mapeo rig_N/tire_N). Sin subpasos se
			# conserva la Fz del tick (comportamiento de producción).
			var tire_rig_n := int(unsprung_rig.coupled_substeps)
			var normal_load := maxf(float(normal_loads[i]), 0.0)
			if tire_rig_n > 1:
				var rig_k: int = _substep_index * tire_rig_n / count
				normal_load = maxf(float(unsprung_rig.substep_load(i, rig_k)), 0.0)
				tire_model.states[i].radial_deflection_m = unsprung_rig.substep_defl(i, rig_k)
				wheel_loads[i] = normal_load
			if not bool(contact.get("hit", false)) or normal_load <= 0.0:
				var free_thermal_state := tire_thermal_states[i]
				var free_result := tire_model.evaluate(
					i,
					0.0,
					"Gravel",
					0.0,
					0.0,
					wheel_spins[i],
					wheel_radii[i],
					0.0,
					thermal_model.tire_grip_factor(i),
					float(free_thermal_state.get("pressure_kpa_gauge", 180.0)),
					h,
					float(free_thermal_state.get("carcass_c", 25.0)),
				)
				wheel_slips[i] = Vector2(
					float(free_result.get("slip_ratio", 0.0)),
					float(free_result.get("slip_angle_rad", 0.0)),
				)
				tire_powers[i] = 0.0
				thermal_speeds[i] = substep_linear_vel.length()
				thermal_slip_speeds[i] = 0.0
				thermal_surfaces[i] = "Gravel"
				thermal_vx[i] = 0.0
				thermal_fy[i] = 0.0
				continue

			var point: Vector3 = contact["position"]
			var normal: Vector3 = contact["normal"]
			var road_velocity := Vector3.ZERO
			var collider: Object = contact.get("collider")
			if collider is RigidBody3D:
				var road_body := collider as RigidBody3D
				road_velocity = road_body.linear_velocity + road_body.angular_velocity.cross(
					point - road_body.global_position
				)

			var r_com := point - com_world
			var point_velocity := substep_linear_vel + substep_angular_vel.cross(r_com) - road_velocity
			var steer_angle := _wheel_steer_angle(i, float(inputs.get("steering", 0.0)))
			var toe := _effective_toe(i)
			var camber := suspension_model.dynamic_camber(i)
			var wheel_camber := suspension_model.dynamic_wheel_camber(i)

			var heading := (-state.transform.basis.z).rotated(chassis_up, steer_angle + toe)
			var forward := (heading - normal * heading.dot(normal)).normalized()
			if forward.length_squared() < 0.5:
				forward = (-state.transform.basis.z).normalized()
			var right := forward.cross(normal).normalized()

			var longitudinal_speed := point_velocity.dot(forward)
			var lateral_speed := point_velocity.dot(right)
			# (Q5) normal_load ya trae la Fz del subpaso (o del tick sin subpasos).
			wheel_loads[i] = normal_load
			var thermal_state := tire_thermal_states[i]
			# Película fina vs charco §4.5: el agua total ya incluye el charco
			# (max(water, puddle)); el soporte del charco lo aplica
			# PuddleModel, así que al neumático solo va la película fina
			# (total - charco) para no aplicar dos veces la misma pérdida.
			var puddle_here := float(last_local_conditions[i].get("puddle_depth_mm", 0.0))
			var thin_water := maxf(thermal_water[i] - puddle_here, 0.0)
			var local_water := thin_water
			var local_snow := thermal_snow[i]
			var local_ground := thermal_ground[i]
			tire_model.rotate_patch_frame(i, forward, right)
			var tire_result := _solve_contact_wheel(
				i,
				h,
				normal_load,
				str(contact["surface"]),
				longitudinal_speed,
				lateral_speed,
				camber,
				float(thermal_state.get("pressure_kpa_gauge", 180.0)),
				float(thermal_state.get("carcass_c", 25.0)),
				local_water,
				local_snow,
				local_ground,
				str(contact.get("winter_layer_id", "")),
			)
			var fx := float(tire_result.get("longitudinal_force_n", 0.0))
			var fy := float(tire_result.get("lateral_force_n", 0.0))
			var mz := float(tire_result.get("aligning_torque_nm", 0.0))
			var flat_drag := -clampf(longitudinal_speed, -1.0, 1.0) * normal_load * 0.045 * float(thermal_state.pressure_loss_fraction)
			var puddle_response := PuddleModel.contact_response(
				float(last_local_conditions[i].get("puddle_depth_mm", 0.0)),
				point_velocity.slide(normal).length(),
				float(tire_model.wheel_compounds[i].get("water_evacuation_reference_speed_m_s", 16.0)),
				normal_load,
				wheel_widths[i],
				float(last_local_conditions[i].get("puddle_drag", 0.0)),
				float(last_local_conditions[i].get("puddle_depth_rate", 0.0)),
				wheel_radii[i]
			)
			var sup_x := float(puddle_response.get("support_longitudinal", puddle_response.support))
			var sup_y := float(puddle_response.get("support_lateral", puddle_response.support))
			var drag_n := float(puddle_response.drag_n)
			last_local_conditions[i]["puddle_support"] = sup_x
			last_local_conditions[i]["puddle_drag_n"] = drag_n
			fx *= sup_x
			fy *= sup_y
			mz *= sup_y

			# Asymmetrical front wheel steering pull moment
			if i < 2 and drag_n > 0.0:
				var steer_sign := -1.0 if i == 0 else 1.0
				mz += float(puddle_response.get("steering_pull_nm", 0.0)) * steer_sign

			var tire_force := forward * (fx + flat_drag) + right * fy
			tire_force -= point_velocity.slide(normal).normalized() * drag_n
			var sat_torque := normal * mz

			if normal_load > 0.0:
				var spin := wheel_spins[i]
				var phase := wheel_rotation_angles[i] + spin * h * 0.5
				var vibration := float(thermal_state.rim_deformation) * minf(spin * spin * 0.025, normal_load * 0.12) * sin(phase)
				state.apply_force((tire_force + normal * vibration) * force_weight, point - state.transform.origin)
				state.apply_torque(sat_torque * force_weight)
				substep_force_sum += tire_force

			wheel_slips[i] = Vector2(
				float(tire_result.get("slip_ratio", 0.0)),
				float(tire_result.get("slip_angle_rad", 0.0)),
			)
			tire_powers[i] = float(tire_result.get("friction_power_w", 0.0)) * sup_x
			# Radio efectivo coherente §4.5: la reacción usa el radio
			# acoplado a deflexión, no el nominal del manifest.
			var eff_radius: float = float(tire_result.get("effective_radius_m", wheel_radii[i]))
			var hydro_wheel_torque := float(puddle_response.get("wheel_torque_nm", drag_n * 0.75 * eff_radius)) * signf(longitudinal_speed)
			tire_reactions[i] = (fx + float(tire_result.get("rolling_force_n", 0.0))) * eff_radius + hydro_wheel_torque
			thermal_speeds[i] = point_velocity.length()
			thermal_cambers[i] = wheel_camber
			thermal_slip_speeds[i] = wheel_spins[i] * eff_radius - longitudinal_speed
			thermal_surfaces[i] = str(contact["surface"])
			thermal_vx[i] = longitudinal_speed
			thermal_fy[i] = fy

		var rotation := powertrain_model.solve_rotation(
			h,
			wheel_spins,
			mass_model.wheel_spin_inertia,
			tire_reactions,
			brake_torques,
		)
		var brake_work: Array = rotation.brake_work_j
		for i in 4:
			wheel_rotation_angles[i] = fposmod(wheel_rotation_angles[i] + wheel_spins[i] * h, TAU)
			var radial_power := unsprung_rig.radial_dissipation_w[i] if normal_loads[i] > 0.0 else 0.0
			_wheel_thermal_work[i] += Vector3(tire_powers[i] * h, float(brake_work[i]), radial_power * h)
		substep_linear_vel += (substep_force_sum / effective_chassis_mass) * h
		# The suspension and collision torques are solved by Jolt outside these
		# substeps, so keep angular velocity fixed rather than integrating only
		# the tire torques and creating an unbalanced prediction.

	if _tire_thermal_elapsed + 1.0e-6 >= TIRE_THERMAL_PERIOD:
		for i in 4:
			var average_power := _wheel_thermal_work[i] / _tire_thermal_elapsed
			thermal_model.advance_tire(
				i, average_power.x, average_power.y, thermal_speeds[i], _tire_thermal_elapsed,
				thermal_cambers[i], average_power.z, thermal_slip_speeds[i], thermal_surfaces[i],
				maxf(float(normal_loads[i]), 0.0), thermal_fy[i], wheel_spins[i], thermal_vx[i],
				float(tire_model.states[i].get("effective_radius_m", wheel_radii[i])) if normal_loads[i] > 0.0 else wheel_radii[i],
				thermal_water[i], thermal_snow[i], thermal_ground[i], thermal_air[i], false,
				thermal_irradiance[i],
			)
		_wheel_thermal_work.fill(Vector3.ZERO)
		_tire_thermal_elapsed = 0.0

	var velocity := state.linear_velocity
	if velocity.length_squared() > 0.01:
		var speed := velocity.length()
		var drag := aero_model.drag_force(speed) + thermal_model.cooling_drag_force_n
		state.apply_central_force(-velocity.normalized() * drag)
		for wing_effect in aero_model.wing_forces(velocity, state.transform.basis):
			var wing_position: Vector3 = state.transform.basis * (wing_effect.position as Vector3)
			state.apply_force(wing_effect.force, wing_position)
	var rpm := powertrain_model.engine_rpm
	var torque := powertrain_model.engine_torque_nm
	_engine_thermal_elapsed += dt
	_engine_thermal_inputs += Vector4(rpm, torque, velocity.length(), aero_model.air_density_kg_m3) * dt
	if _engine_thermal_elapsed + 1.0e-6 >= ENGINE_THERMAL_PERIOD:
		var average := _engine_thermal_inputs / _engine_thermal_elapsed
		thermal_model.advance_engine(_engine_thermal_elapsed, average.x, average.y, average.z, average.w, _ambient_irradiance_w_m2)
		_engine_thermal_elapsed = 0.0
		_engine_thermal_inputs = Vector4.ZERO

	_fuel_elapsed += dt
	_fuel_work_j += maxf(torque * rpm * TAU / 60.0, 0.0) * dt
	if _fuel_elapsed + 1.0e-6 >= FUEL_PERIOD:
		_flush_fuel_work()
	if bool(inputs.get("automatic_transmission", false)):
		_update_automatic_shift(float(inputs.get("throttle", 0.0)))
	publication_sequence += 1
	if publication_sequence == 240:
		print(
			"RALLY_UNSPRUNG_STATE ",
			JSON.stringify(
				{
					"radial_deflection_m": unsprung_rig.radial_deflection_m,
					"suspension_compression_m": suspension_model.compression,
					"normal_load_n": normal_loads,
					"spring_force_n": unsprung_rig.spring_forces_n,
					"sprung_mass_kg": body.mass,
					"vehicle_mass_kg": mass_model
					.resolve(thermal_model.fuel_remaining_litres
					* mass_model.fuel_density_kg_per_litre)
					.vehicle_total_mass_kg,
				}
			),
		)
	simulation_time_s += dt
	var wheels: Array[Dictionary] = []
	for index in 4:
		var wheel := thermal_model.get_tire_thermal_state_snapshot(index)
		wheel.merge(
			{
				"brake_collision_loss": brake_collision_loss[index],
				"brake_demand": clampf(brake_demand[index] / maxf(brake_model.maximum_brake_torque_nm * 0.25, 1.0), 0.0, 1.0),
				"alignment_collision_damage": alignment_collision_damage[index],
				"surface": wheel_surfaces[index],
				"audio_surface": contacts[index].get("audio_surface", wheel_surfaces[index]),
				"load_n": wheel_loads[index],
				"spin_rad_s": wheel_spins[index],
				"slip_ratio": wheel_slips[index].x,
				"slip_angle_rad": wheel_slips[index].y,
				"effective_slip_ratio": float(tire_model.states[index].get("effective_slip_ratio", 0.0)),
				"effective_slip_angle_rad": float(tire_model.states[index].get("effective_slip_angle", 0.0)),
				"puddle_depth_mm": float(last_local_conditions[index].get("puddle_depth_mm", 0.0)),
				"water_mm": float(last_local_conditions[index].get("water_mm", 0.0)),
				"puddle_support": float(last_local_conditions[index].get("puddle_support", 1.0)),
				"puddle_drag_n": float(last_local_conditions[index].get("puddle_drag_n", 0.0)),
				"patch_pos": tire_model.states[index].patch_pos,
				"patch_energy_j": tire_model.states[index].patch_energy_j,
				"energy_residue_w": float(tire_model.states[index].get("energy_residue_w", 0.0)),
				"instant_combined_utilization": float(tire_model.states[index].get("instant_combined_utilization", 0.0)),
				"contact_power_w": float(tire_model.states[index].get("contact_power_w", 0.0)),
				"slide_heat_w": float(tire_model.states[index].get("slide_heat_w", 0.0)),
				"liftoff_discard_j": float(tire_model.states[index].get("liftoff_discard_j", 0.0)),
				"effective_radius_m": float(tire_model.states[index].get("effective_radius_m", wheel_radii[index])),
				"enveloped_load_n": float(tire_model.states[index].get("enveloped_load_n", wheel_loads[index])),
				"unsprung_mass_kg": mass_model.unsprung_mass_kg[index],
				"radial_deflection_m": unsprung_rig.radial_deflection_m[index],
				"radial": unsprung_rig.radial_states[index].duplicate(),
				"suspension_force_n": unsprung_rig.spring_forces_n[index],
			}
		)
		wheels.append(wheel)
	published_state = {
		"sequence": publication_sequence,
		"generation": session_generation,
		"time_s": simulation_time_s,
		"dt_s": dt,
		"rpm": powertrain_model.engine_rpm,
		"rpm_max": powertrain_model.maximum_rpm,
		"rpm_idle": powertrain_model.idle_rpm,
		"gear": powertrain_model.current_gear,
		"torque_nm": powertrain_model.engine_torque_nm,
		"autoblip_active": powertrain_model.autoblip_active,
		"autoblip_target_rpm": powertrain_model.autoblip_target_rpm,
		"autoblip_throttle": powertrain_model.autoblip_throttle,
		"freewheel_active": powertrain_model.freewheel_active,
		"freewheel_enabled": powertrain_model.freewheel_enabled,
		"freewheel_throttle": powertrain_model.freewheel_throttle,
		"freewheel_delta_rad_s": powertrain_model.freewheel_delta_rad_s,
		"final_drive": powertrain_model.final_drive_ratio,
		"shift_phase": powertrain_model.shift_phase,
		"pending_gear": powertrain_model.pending_gear,
		"clutch_engagement": powertrain_model.clutch_engagement,
		"clutch_torque_nm": powertrain_model.clutch_torque_nm,
		"clutch_slip_power_w": powertrain_model.clutch_slip_power_w,
		"input_shaft_rad_s": powertrain_model.input_shaft_omega_rad_s,
		"driveline": {
			"enabled": powertrain_model.driveline_compliance_enabled,
			"twist_rad": powertrain_model.driveline_twist_rad,
			"torque_nm": powertrain_model.driveline_torque_nm,
			"energy_j": powertrain_model.driveline_energy_j,
			"dissipation_w": powertrain_model.driveline_dissipation_w,
			"output_rad_s": powertrain_model.output_shaft_omega_rad_s,
		},
		"load": clampf(
			absf(powertrain_model.engine_torque_nm) / maxf(powertrain_model.peak_torque_nm, 1.0),
			0.0,
			1.0,
		),
		"peak_torque_nm": powertrain_model.peak_torque_nm,
		"normalized_torque": clampf(
			powertrain_model.engine_torque_nm / maxf(powertrain_model.peak_torque_nm, 1.0),
			-1.0,
			1.0,
		),
		"speed_kph": state.linear_velocity.length() * 3.6,
		"throttle": float(inputs.get("throttle", 0.0)),
		"brake": float(inputs.get("brake", 0.0)),
		"steering": float(inputs.get("steering", 0.0)),
		"engine": thermal_model.get_engine_thermal_state_snapshot(),
		"damage": {
			"radiator": thermal_model.radiator_damage,
			"engine": thermal_model.engine_damage,
			"transmission": powertrain_model.transmission_damage,
			"overheat_exposure_s": thermal_model.overheat_exposure_s,
		},
		"fuel": thermal_model.get_fuel_state_snapshot(),
		"wheels": wheels,
		"contact_queries": contact_query_count,
		"aids": {
			"automatic_transmission": bool(inputs.get("automatic_transmission", false)),
			"traction_control": traction_control_enabled,
			"stability": stability_enabled,
			"anti_lock_brakes": abs_enabled,
		},
		"aids_available": assistance_available.duplicate(),
		"differential": {
			"preset_id": active_differential_preset_id,
			"profile_id": active_differential_profile(),
			"type": powertrain_model.differential_type,
			"diff_speed_rad_s": powertrain_model.last_diff_speed_rad_s,
			"lsd_capacity_nm": powertrain_model.last_lsd_capacity_nm,
			"lsd_torque_nm": powertrain_model.last_lsd_torque_nm,
			"lsd_saturation": powertrain_model.last_lsd_saturation,
			"front_type": powertrain_model.front_differential_type,
			"front_diff_speed_rad_s": powertrain_model.last_front_diff_speed_rad_s,
			"front_lsd_capacity_nm": powertrain_model.last_front_lsd_capacity_nm,
			"front_lsd_torque_nm": powertrain_model.last_front_lsd_torque_nm,
			"front_lsd_saturation": powertrain_model.last_front_lsd_saturation,
			"rear_type": powertrain_model.rear_differential_type,
			"rear_diff_speed_rad_s": powertrain_model.last_rear_diff_speed_rad_s,
			"rear_lsd_capacity_nm": powertrain_model.last_rear_lsd_capacity_nm,
			"rear_lsd_torque_nm": powertrain_model.last_rear_lsd_torque_nm,
			"rear_lsd_saturation": powertrain_model.last_rear_lsd_saturation,
		},
	}


func set_final_drive_preset(preset: String) -> bool:
	return powertrain_model.set_final_drive_preset(preset)


func _prepare_powertrain(delta: float, inputs: Dictionary) -> void:
	var clutch := clampf(float(inputs.get("clutch", 1.0)), 0.0, 1.0)
	var split := powertrain_model.front_torque_split
	var carrier := 0.5 * (
		split * (wheel_spins[0] + wheel_spins[1])
		+ (1.0 - split) * (wheel_spins[2] + wheel_spins[3])
	)
	powertrain_model.advance(
		delta,
		float(inputs.get("throttle", 0.0)),
		clutch,
		thermal_model.engine_torque_factor() if thermal_model.fuel_remaining_litres > 0.0 else 0.0,
		carrier,
	)


func update_wheel_visuals(steering_input: float) -> void:
	for i in mini(4, wheel_visual_pivots.size()):
		var steer_angle := _wheel_steer_angle(i, steering_input)
		var toe := _effective_toe(i)
		var wheel_camber := suspension_model.dynamic_wheel_camber(i)
		var pivot := wheel_visual_pivots[i]
		pivot.position = wheel_positions_local[i] + Vector3.UP * suspension_model.compression[i]
		pivot.rotation.y = steer_angle + toe
		if i < wheel_visuals.size():
			wheel_visuals[i].rotation = Vector3(wheel_rotation_angles[i], 0.0, wheel_camber)


func _effective_toe(index: int) -> float:
	var config: Dictionary = domains.get("damage", {}).get("wheel_collision", {})
	var inward := -1.0 if index in [0, 2] else 1.0
	var damage_offset := deg_to_rad(float(config.get("maximum_toe_offset_deg", 0.0))) * alignment_collision_damage[index]
	return suspension_model.dynamic_toe(index) + inward * damage_offset


func _wheel_steer_angle(index: int, input_value: float) -> float:
	var shaped := signf(input_value) * pow(absf(input_value), maxf(steering_exponent, 0.1))
	var center_angle := shaped * maximum_steering_angle_rad * front_steering_ratio
	if index >= 2:
		return shaped * maximum_steering_angle_rad * rear_steering_ratio
	if ackermann <= 0.0 or wheelbase_m <= 0.0:
		return center_angle
	var x := wheel_positions_local[index].x
	var correction := atan2(wheelbase_m * tan(center_angle), wheelbase_m + x * tan(center_angle))
	return lerp_angle(center_angle, correction, clampf(ackermann, 0.0, 1.0))


func _update_automatic_shift(throttle: float) -> void:
	if not powertrain_model.automatic_transmission or powertrain_model.shift_remaining_seconds > 0.0:
		return
	var normalized_rpm := powertrain_model.engine_rpm / maxf(powertrain_model.maximum_rpm, 1.0)
	if powertrain_model.current_gear == 0 and absf(wheel_spins[2]) * wheel_radii[2] > 1.0:
		powertrain_model.set_gear(1)
	elif (
		powertrain_model.current_gear < powertrain_model.maximum_forward_gear
		and normalized_rpm > (0.90 if throttle > 0.65 else 0.70)
	):
		powertrain_model.request_shift(1)
	elif powertrain_model.current_gear > 1 and normalized_rpm < 0.34:
		powertrain_model.request_shift(-1)


func _surface_for_collider(collider: Variant) -> String:
	if collider is Node:
		if collider.is_in_group("SnowDeep"):
			return "SnowDeep"
		for surface_name in tire_model.surfaces:
			if collider.is_in_group(str(surface_name)):
				return str(surface_name)
		var surface_meta: Variant = collider.get_meta("surface", "")
		if tire_model.surfaces.has(str(surface_meta)):
			return str(surface_meta)
	# Surface errors remain drivable via TireModel's logged safety fallback.
	return "Unknown"


func _flush_fuel_work() -> void:
	if _fuel_elapsed > 0.0:
		thermal_model.advance_fuel(_fuel_work_j / _fuel_elapsed, _fuel_elapsed)
	_fuel_elapsed = 0.0
	_fuel_work_j = 0.0


## §closure-6: envolvente tandem-cam de dos apoyos.
## h_front/h_rear: alturas de suelo bajo cada apoyo (marco de rodadura).
## front_contact/rear_contact: si cada apoyo toca suelo.
## Devuelve {height, contact, both_contact, surface}: altura efectiva continua
## (media cuando ambos tocan = puenteo de bache + subida anticipada a bordillo;
## apoyo único cuando solo uno toca; sin contacto cuando ninguno), flag de
## contacto y superficie (la del apoyo más alto al cruzar bordes entre
## superficies; "" si no hay contacto).
static func tandem_cam_effective_height(
	h_front: float, front_contact: bool,
	h_rear: float, rear_contact: bool,
	front_surface: String = "",
	rear_surface: String = "",
) -> Dictionary:
	if front_contact and rear_contact:
		var h := (h_front + h_rear) * 0.5
		var surf := front_surface
		if front_surface != rear_surface:
			surf = front_surface if h_front >= h_rear else rear_surface
		return {"height": h, "contact": true, "both_contact": true, "surface": surf}
	if front_contact:
		return {"height": h_front, "contact": true, "both_contact": false, "surface": front_surface}
	if rear_contact:
		return {"height": h_rear, "contact": true, "both_contact": false, "surface": rear_surface}
	return {"height": 0.0, "contact": false, "both_contact": false, "surface": ""}


## Separación de apoyos del prototipo: longitud de huella efectiva.
static func tandem_cam_supports(patch_length_m: float, scale: float = 1.0) -> Array[float]:
	var half := maxf(patch_length_m, 0.03) * 0.5 * maxf(scale, 0.1)
	return [-half, half]


## Limpia el estado residual publicado sin tocar tren motriz ni combustible
## (§2): misma limpieza de suspensión/hubs/contactos que reset_dynamics() para
## la rama de rescate en _integrate_forces, donde solo se reubican los cuerpos
## Jolt y debe garantizarse que la primera fuerza de amortiguador corresponda
## a la velocidad relativa medida, no a muestras previas.
func clear_teleport_residual() -> void:
	unsprung_rig.reset()
	suspension_model.clear_transient()
	for i in 4:
		unsprung_rig.spring_forces_n[i] = 0.0
		wheel_loads[i] = 0.0
		wheel_slips[i] = Vector2.ZERO
		wheel_contact_points[i] = Vector3.ZERO
		wheel_contact_normals[i] = Vector3.UP
		wheel_surfaces[i] = "Unknown"
		last_local_conditions[i] = {}
		last_puddle_depths_mm[i] = 0.0
	last_contacts = [{}, {}, {}, {}]
	contact_query_count = 0


## Muestra de consumo del vehículo (§1): recorrido, velocidad, carga y fuerza
## de barra tal como los lee el vehículo tras el tick. Sirve para comparar
## trazas antes/después en reposo, descarga, vuelo y recontacto, con tándem y
## con ShapeCast.
## Activa/desactiva el recorte de diagnóstico del damper (F1). Producción: OFF.
func set_damper_impulse_limit(enabled: bool) -> void:
	unsprung_rig.set_damper_impulse_limit(enabled)


## Muestra de consumo del vehículo (§1/F3): recorrido, velocidad, carga y fuerza
## de barra tal como los lee el vehículo tras el tick, más traza comparable por
## tick Jolt (id, dt, damper solicitado/aplicado, impulso en N·s). Sirve para
## comparar trazas antes/después en reposo, descarga, vuelo y recontacto, con
## tándem y con ShapeCast, y el último tick previo al rescate con los primeros
## posteriores frente a un vehículo recién colocado en la misma pose.
func sample_suspension_trace() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 4:
		out.append(
			{
				"compression_m": suspension_model.compression[i],
				"hub_travel_m": unsprung_rig.compression_physical_m[i] if i < unsprung_rig.compression_physical_m.size() else suspension_model.compression[i],
				"compression_velocity_m_s": suspension_model.compression_velocity[i],
				"geometric_contact": suspension_model.geometric_contact[i],
				"loaded_contact": suspension_model.contact_active[i],
				"load_n": wheel_loads[i],
				"spring_force_n": unsprung_rig.spring_forces_n[i],
				"elastic_n": suspension_model.last_elastic_forces_n[i],
				"damper_n": unsprung_rig.last_damper_applied_n[i],
				"damper_requested_n": unsprung_rig.last_damper_requested_n[i],
				"damper_applied_n": unsprung_rig.last_damper_applied_n[i],
				"damper_impulse_ns": unsprung_rig.last_damper_impulse_ns[i],
				"damper_clamped": unsprung_rig.last_damper_clamped[i],
				"damper_clip_events": unsprung_rig.damper_clip_events[i],
				"tick_id": unsprung_rig.last_tick_trace[i].get("tick_id", 0),
				"tick_dt_s": unsprung_rig.last_tick_trace[i].get("dt_s", 0.0),
				"bar_travel_m": suspension_model.filtered_arb_travel[i],
			}
		)
	return out


## Traza cruda por tick Jolt del rig (F3): identificador, dt, poses y
## velocidades leídas por el solver, velocidad relativa en el anclaje, damper
## solicitado/aplicado e impulso en N·s, potencia en W y trabajo estimado en J.
func sample_tick_trace() -> Array[Dictionary]:
	return unsprung_rig.last_tick_trace.duplicate(true)


## Traza de contacto por rueda §3 (JSON-segura): impacto geométrico, punto,
## normal, collider (nombre), superficie, distancia usada por la ley radial,
## fracción segura y apoyo seleccionado, más alcance de consulta. Sirve para
## capturar plano, pendiente, bordillo y doble superficie y comparar
## deformación y saltos de carga al cruzar el borde en ambos sentidos.
func sample_contact_trace() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 4:
		var c: Dictionary = last_contacts[i] if i < last_contacts.size() else {}
		var pos: Vector3 = c.get("position", wheel_contact_points[i])
		var nrm: Vector3 = c.get("normal", wheel_contact_normals[i])
		var collider_name := ""
		var collider: Variant = c.get("collider", null)
		if collider is Node:
			collider_name = str((collider as Node).name)
		elif collider != null:
			collider_name = str(collider)
		out.append(
			{
				"hit": bool(c.get("hit", false)),
				"position": [pos.x, pos.y, pos.z],
				"normal": [nrm.x, nrm.y, nrm.z],
				"collider": collider_name,
				"surface": str(c.get("surface", wheel_surfaces[i])),
				"distance_m": float(c.get("distance", 0.0)),
				"safe_fraction": float(c.get("safe_fraction", 0.0)),
				"global_safe_fraction": float(c.get("global_safe_fraction", c.get("safe_fraction", 0.0))),
				"support_index": int(c.get("support_index", -1)),
				"support_alignment": float(c.get("support_alignment", 0.0)),
				"collision_count": int(c.get("collision_count", 1)),
				"isolated": bool(c.get("isolated", false)),
				"coherent": bool(c.get("coherent", true)),
				"verify": c.get("verify", {}),
				"query_bump_m": float(c.get("query_bump_m", 0.0)),
				"query_travel_m": float(c.get("query_travel_m", 0.0)),
				"radial_deflection_m": unsprung_rig.radial_deflection_m[i] if i < unsprung_rig.radial_deflection_m.size() else 0.0,
				"load_n": wheel_loads[i] if i < wheel_loads.size() else 0.0,
			}
		)
	return out


## Reporte de calibración por eje (§3): masa de referencia, frecuencia
## efectiva, wheel rate y amortiguamientos vigentes, más precarga estática y
## vías delantera/trasera para contrastar suma de cargas y momentos con peso
## y COM. La rigidez explícita del perfil figura como respaldo cuando no hay
## `ride_frequency_hz` declarada.
func suspension_calibration_report() -> Dictionary:
	var axles: Array[Dictionary] = []
	for axle in [0, 2]:
		var p: Dictionary = suspension_model.axle_parameters[axle]
		axles.append(
			{
				"axle": "front" if axle == 0 else "rear",
				"static_note": "nominal_profile_computed",
				"reference_mass_kg": float(p.get("frequency_reference_mass_kg", 0.0)),
				"frequency_hz": float(p.get("ride_frequency_hz", 0.0)),
				"wheel_rate_n_m": float(p.get("spring_rate", 0.0)),
				"bump_damping_ns_m": float(p.get("bump_damping", 0.0)),
				"rebound_damping_ns_m": float(p.get("rebound_damping", 0.0)),
				"static_load_n": float(p.get("static_load", 0.0)),
				"static_corner_load_n": suspension_model.static_corner_loads_n[axle],
			}
		)
	var front_track := 0.0
	var rear_track := 0.0
	if wheel_positions_local.size() == 4:
		front_track = absf(wheel_positions_local[0].x - wheel_positions_local[1].x)
		rear_track = absf(wheel_positions_local[2].x - wheel_positions_local[3].x)
	return {
		"axles": axles,
		"front_track_m": front_track,
		"rear_track_m": rear_track,
		"wheelbase_m": wheelbase_m,
	}


func reset_dynamics() -> void:
	_flush_fuel_work()
	_tire_thermal_elapsed = 0.0
	_wheel_thermal_work.fill(Vector3.ZERO)
	_engine_thermal_elapsed = 0.0
	_engine_thermal_inputs = Vector4.ZERO
	unsprung_rig.reset()
	suspension_model.clear_transient()
	session_generation += 1
	simulation_time_s = 0.0
	published_state = { }
	wheel_spins.fill(0.0)
	wheel_slips.fill(Vector2.ZERO)
	wheel_loads.fill(0.0)
	wheel_rotation_angles.fill(0.0)
	wheel_contact_points.fill(Vector3.ZERO)
	wheel_contact_normals.fill(Vector3.UP)
	wheel_surfaces.fill("Unknown")
	last_local_conditions = [{}, {}, {}, {}]
	last_puddle_depths_mm.fill(0.0)
	last_contacts = [{}, {}, {}, {}]
	contact_query_count = 0
	brake_model.smoothed_service_input = 0.0
	brake_model.smoothed_handbrake_input = 0.0
	for i in 4:
		tire_model.reset_patch(i)
		unsprung_rig.spring_forces_n[i] = 0.0
		if i < wheel_visuals.size():
			wheel_visuals[i].rotation = Vector3.ZERO
	powertrain_model.current_gear = 0
	powertrain_model.engine_rpm = powertrain_model.idle_rpm
	powertrain_model.reset_shift()
	powertrain_model.engine_torque_nm = 0.0
	powertrain_model.engine_requested_torque_nm = 0.0
	powertrain_model.engine_attack_limited_torque_nm = 0.0
	powertrain_model.clutch_engagement = 0.0
	powertrain_model.clutch_torque_nm = 0.0
	powertrain_model.input_shaft_omega_rad_s = 0.0
	powertrain_model.reset_compliance()
	powertrain_model.clutch_slip_power_w = 0.0


func _vector_from_document(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(
			float(value.get("x", fallback.x)),
			float(value.get("y", fallback.y)),
			float(value.get("z", fallback.z)),
		)
	return fallback


func _solve_contact_wheel(
	index: int,
	dt: float,
	load_n: float,
	surface: String,
	vx: float,
	vy: float,
	camber: float,
	pressure: float,
	carcass_temperature_c: float,
	water_mm: float = 0.0,
	snow_mm: float = 0.0,
	ground_c: float = 30.0,
	winter_layer_id: String = "",
) -> Dictionary:
	return tire_model.evaluate(
		index,
		load_n,
		surface,
		vx,
		vy,
		wheel_spins[index],
		wheel_radii[index],
		camber,
		thermal_model.tire_grip_factor(index),
		pressure,
		dt,
		carcass_temperature_c,
		water_mm,
		snow_mm,
		ground_c,
		winter_layer_id,
	)
