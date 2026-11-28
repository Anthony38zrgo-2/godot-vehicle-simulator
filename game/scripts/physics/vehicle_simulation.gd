class_name FordRallyVehicleSimulation
extends RefCounted

const PROFILE_PATH := "res://data/vehicles/ford-escort-rs2000/vehicle.json"
# preload directo: no depende de la caché global de clases del editor.
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
var dirt := preload("res://scripts/physics/dirt_model.gd").new()
var dirt_radiator_enabled := true
var dirt_accumulating := false
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
# Paso 2.1 Jolt fix: márgenes explícitos fijos para eliminar el sesgo por
# defecto de 0.04 m que inflaba la deflexión radial δ.
const SHAPECAST_CYLINDER_MARGIN := 0.005
const SHAPECAST_MARGIN := 0.002
# Paso 2.3: impactos laterales de barrera excluidos temporalmente para buscar
# el asfalto debajo. Se guardan en este array local durante el paso y se
# entregan a _collect_wheel_cast_impacts() en vez de releer el ShapeCast ya
# modificado al final del frame.
var last_barrier_hits: Array = [[], [], [], []]
# Paso 3.1: discriminación Flanco (sidewall) vs Banda (tread) con el eje de
# giro de la rueda. axial = |n · spin_axis|.
const SIDEWALL_AXIAL_MIN := 0.70
const TREAD_AXIAL_MAX := 0.45
const TREAD_UP_MIN := 0.25
# Paso 3.3: sensibilidad de carga en lugar de tope duro de agarre.
# La ley mu_eff = mu0*(fz/fz_nom)^(-k) vive en TireModel.load_adjusted_mu()
# (k 0.10-0.20). Aquí solo queda el tope de recuperación de baja confianza.
const RECOVERY_FZ_CAP_MULT := 2.4
# Paso 0.1 Jolt fix: firma de solapamiento. Se arma al crear los casts para
# que se imprima UNA vez en el primer tick (igual que la estabilidad) y se
# puede volver a pedir con request_overlap_signature_diagnostic().
const OVERLAP_DIAGNOSTIC_BURY_M := 0.05
var debug_overlap_signature_requested := false
## Última firma capturada ({} hasta que se ejecuta el diagnóstico).
var last_overlap_signature: Dictionary = {}
# Auditoría §3: último contacto por rueda (hit, punto, normal, collider,
# distancia usada por la ley radial, fracción segura y apoyo seleccionado).
var last_contacts: Array[Dictionary] = [{}, {}, {}, {}]
var contact_frequency_samples: int = 0
var contact_frequency_elapsed_s: float = 0.0
var mass_state: Dictionary = { }
var maximum_substep_seconds: float = 0.002
var configured_substeps_per_tick: int = 0
var configured_substep_hz: int = 120
var configured_powertrain_hz: int = 240
var configured_tangential_tire_hz: int = 120
var _powertrain_step_samples: int = 0
var _powertrain_tire_acc: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _powertrain_brake_acc: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _powertrain_spin_damp_acc: Array[float] = [0.0, 0.0, 0.0, 0.0]
# Caché de subpaso para desacoplar evaluación tangencial de neumáticos / charcos / jacking
# cuando la suspensión corre a mayor frecuencia que configured_tangential_tire_hz.
var _substep_cached_valid: Array[bool] = [false, false, false, false]
var _substep_cached_fz_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_cached_tire_force: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _substep_cached_sat_torque: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _substep_cached_mz_nm: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_cached_raw_tire_torque: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_cached_spin_damp: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_cached_tire_power: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_cached_lat_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_cached_lon_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_cached_load_scale: Array[float] = [1.0, 1.0, 1.0, 1.0]
# Buffers preasignados para el bucle de subpasos (cero asignaciones por subpaso).
var _substep_tire_reactions: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_spin_damping: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_j_tang_hub: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_lat_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_lon_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _substep_cg_h: Array[float] = [0.5, 0.5, 0.5, 0.5]
var _tire_thermal_elapsed := 0.0
# Friction, brake and radial damping work, in joules per wheel.
var _wheel_thermal_work: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _engine_thermal_elapsed := 0.0
var _engine_thermal_inputs := Vector4.ZERO
var _engine_thermal_peak_rpm := 0.0
var _fuel_elapsed := 0.0
var _fuel_work_j := 0.0
var last_step_seconds: float = 0.0
var published_state: Dictionary = { }
var publication_sequence: int = 0
var simulation_time_s: float = 0.0
var session_generation: int = 0
var setup_design_values: Dictionary = {}
var setup_values: Dictionary = {}
var setup_design_suspension: Dictionary = {}
var setup_design_powertrain: Dictionary = {}
var wheelbase_m: float = 2.41
var ackermann: float = 0.18
var maximum_steering_angle_rad: float = 0.5585053606381855
var steering_exponent: float = 1.1
var front_steering_ratio: float = 1.0
var rear_steering_ratio: float = 0.0
# 1DOF cremallera/columna de dirección (inercia + muelle asistencia + amortiguación vs Mz + steering_pull).
var steering_rack_enabled: bool = true
var steering_rack_angle_rad: float = 0.0
var steering_rack_vel_rad_s: float = 0.0
var steering_ffb_torque_nm: float = 0.0
var steering_rack_inertia_kg_m2: float = 0.18
var steering_rack_stiffness_nm_per_rad: float = 900.0
var steering_rack_damping_nms_per_rad: float = 36.0
var steering_rack_torque_scale: float = 0.25
var _last_front_road_torque_nm: float = 0.0
# 1DOF torsión de carcasa del neumático (wind-up entre llanta y banda de rodadura).
var carcass_windup_enabled: bool = true
var tire_windup_rad: Array[float] = [0.0, 0.0, 0.0, 0.0]
var tire_belt_spins: Array[float] = [0.0, 0.0, 0.0, 0.0]
var carcass_torsional_stiffness_nm_per_rad: float = 35000.0
var carcass_torsional_damping_ratio: float = 0.55
var carcass_belt_inertia_fraction: float = 0.25
# Acoplamiento dinámico de masa de combustible (slosh) al chasis.
var fuel_slosh_enabled: bool = true
var _prev_chassis_vel_world: Vector3 = Vector3.ZERO
var _has_prev_chassis_vel: bool = false
# Cinemática de centros instantáneos: Roll Centers, Anti-Dive, Anti-Squat/Anti-Lift y Jacking Forces.
var instant_center_kinematics_enabled: bool = true
var last_kinematic_jacking_forces_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_geometric_load_transfer_n: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_roll_center_heights_m: Array[float] = [0.0, 0.0, 0.0, 0.0]
# Elastocinemática filtrada de silentblocks y brazos (compliance steer y compliance camber bajo Fy/Fx).
var elastokinematics_enabled: bool = true
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
var tire_sources: Dictionary = {}
var last_local_conditions: Array = [{}, {}, {}, {}]
var _ambient_irradiance_w_m2: float = 0.0
var last_puddle_depths_mm: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_snow_patch_depths_mm: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _water_wheel_positions: PackedVector3Array = PackedVector3Array()
# §closure-6: prototipo de envolvente espacial tandem-cam (comparación).
# Dos apoyos geométricos longitudinales separados por la longitud de huella.
# Mantener separados: distancia de detección, radio geométrico y radio
# efectivo de rodadura. Flag off por defecto hasta completar comparaciones
# de contacto, manejo y coste. Con geometría activa se revisa cuánto
# filtrado temporal sigue haciendo falta para evitar retraso duplicado.
var tandem_cam_enabled := false
var tandem_cam_patch_scale := 1.0
var active_profile_id: String = ""


func configure(asset_document: Dictionary, manifest_path: String = PROFILE_PATH) -> Dictionary:
	asset_manifest = asset_document
	var loaded := VehicleProfileLoader.load_profile(manifest_path)
	if not bool(loaded.get("ok", false)):
		return loaded
	profile = loaded["manifest"]
	domains = loaded["domains"]
	tire_sources = loaded["tire_sources"]
	var mass_result := mass_model.configure(domains, asset_manifest)
	if not bool(mass_result.get("ok", false)):
		return mass_result
	mass_state = mass_model.resolve(mass_model.fuel_initial_kg)
	if mass_state.has("inertia_tensor") and mass_state["inertia_tensor"] is Basis:
		unsprung_rig.set_local_inertia_tensor(mass_state["inertia_tensor"])
	unsprung_rig.configure_chassis_torsion(
		domains.get("chassis", { }).get("chassis", { }),
		float((mass_state.get("inertia", Vector3(500.0, 800.0, 1200.0)) as Vector3).z),
	)
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
	steering_rack_inertia_kg_m2 = maxf(float(steering.get("rack_inertia_kg_m2", 0.18)), 0.005)
	steering_rack_stiffness_nm_per_rad = maxf(float(steering.get("rack_stiffness_nm_per_rad", 900.0)), 1.0)
	steering_rack_damping_nms_per_rad = maxf(float(steering.get("rack_damping_nms_per_rad", 36.0)), 0.1)
	steering_rack_torque_scale = clampf(float(steering.get("rack_torque_scale", 0.25)), 0.0, 4.0)
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
	configured_powertrain_hz = maxi(
		1,
		int(coupled.get("powertrain_frequency_hz", 240)),
	)
	configured_tangential_tire_hz = maxi(
		1,
		int(coupled_suspension.get(
			"tangential_tire_frequency_hz",
			coupled.get("tangential_tire_frequency_hz", 120),
		)),
	)

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
	setup_design_suspension = domains.get("suspension", {}).get("suspension", {}).duplicate(true)
	setup_design_powertrain = domains.get("powertrain", {}).get("powertrain", {}).duplicate(true)
	for axle_index in 2:
		var axle := "front" if axle_index == 0 else "rear"
		setup_design_suspension[axle]["ride_frequency_hz"] = suspension_model.axle_parameters[axle_index * 2].ride_frequency_hz
	setup_design_values = RallySetupCatalog.defaults(domains)
	setup_design_values["powertrain.max_rpm"] = powertrain_model.maximum_rpm
	setup_design_values["brakes.front_brake_bias"] = brake_model.front_brake_bias
	setup_design_values["fuel.initial_kg"] = mass_model.fuel_initial_kg
	setup_values = setup_design_values.duplicate()
	set_compound(active_compound_id)
	_apply_setup_pressures(setup_values)
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


## Reloads tire catalog values (default_tire_profile + compounds) from disk in real time
## while keeping vehicle geometry, session cold pressures, wheel compounds and thermal/wear state intact.
func reload_tire_catalog_runtime() -> bool:
	RallyTireCompound.invalidate_cache()
	var cat := RallyTireCompound.load_catalog()
	if not supports_tire_calibration_catalog(cat):
		return false
	var tire_domains := resolve_tire_calibration_domains(cat)
	domains["tires"] = tire_domains["tires"]
	domains["tire_filters"] = tire_domains["tire_filters"]
	TireRadialModel._model_cache.clear()
	var prev_states := tire_model.states.duplicate(true)
	_configure_tire_calibration_model(tire_model, tire_domains, cat)
	if prev_states.size() == tire_model.states.size():
		tire_model.states.assign(prev_states)
	thermal_model.reload_tire_metadata(domains, cat)
	compound_catalog = cat
	return true


func resolve_tire_calibration_domains(catalog: Dictionary) -> Dictionary:
	var tires := RallyTireCompound.merged_tire_domain(tire_sources.get("tires", {}), catalog)
	var current_pressure: Dictionary = domains.get("tires", {}).get("tires", {}).get("pressure", {})
	if current_pressure.has("cold_kpa_gauge"):
		var pressure: Dictionary = tires["tires"].get("pressure", {})
		pressure["cold_kpa_gauge"] = current_pressure["cold_kpa_gauge"].duplicate(true)
		tires["tires"]["pressure"] = pressure
	return {
		"tires": tires,
		"tire_filters": RallyTireCompound.merged_tire_filter_domain(tire_sources.get("tire_filters", {}), catalog),
	}


func make_tire_calibration_model(catalog: Dictionary) -> TireModel:
	var model := TireModel.new()
	_configure_tire_calibration_model(model, resolve_tire_calibration_domains(catalog), catalog)
	return model


func supports_tire_calibration_catalog(catalog: Dictionary) -> bool:
	var definitions: Variant = catalog.get("compounds", {})
	if not definitions is Dictionary or not definitions.get(active_compound_id) is Dictionary:
		return false
	for wheel in tire_model.wheel_compounds:
		if not definitions.get(wheel.get("id", active_compound_id)) is Dictionary:
			return false
	return true


func _configure_tire_calibration_model(model: TireModel, tire_domains: Dictionary, catalog: Dictionary) -> void:
	var wheel_ids: Array[String] = []
	for wheel in tire_model.wheel_compounds:
		wheel_ids.append(str(wheel.get("id", active_compound_id)))
	var filters := VehicleProfileLoader.resolve_tire_filters(tire_domains["tires"], tire_domains["tire_filters"], catalog)
	model.configure(tire_domains, filters, suspension_model.static_corner_loads_n, catalog)
	var definitions: Dictionary = catalog.get("compounds", {})
	if not definitions.has(active_compound_id):
		return
	model.set_compound(active_compound_id, catalog)
	for i in wheel_ids.size():
		if wheel_ids[i] != active_compound_id and definitions.has(wheel_ids[i]):
			model.set_wheel_compound(i, wheel_ids[i])


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


func _local_conditions_base(surface_name: String, position: Vector3, loaded: bool) -> Dictionary:
	var local := {"air_c": thermal_model.ambient_temperature_c, "ground_c": 30.0,
		"water_mm": 0.0, "background_water_mm": 0.0, "snow_mm": 0.0, "ice_mm": 0.0, "snow_coverage": -1.0, "ice_coverage": -1.0,
		"loose_gravel_coverage": 0.0,
		"surface_name": surface_name, "puddle_depth_mm": 0.0, "puddle_drag": 0.0, "irradiance_w_m2": 0.0}
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
	local["background_water_mm"] = maxf(float(local.get("water_mm", 0.0)), 0.0)
	return local


func _apply_water_overlays_to_local(
	local: Dictionary,
	surface_name: String,
	has_puddle: bool,
	puddle_depth: float,
	puddle_drag: float,
	has_river: bool,
	river_depth: float,
	river_drag: float,
	river_channel_id: String,
) -> Dictionary:
	if not local.has("background_water_mm"):
		local["background_water_mm"] = maxf(float(local.get("water_mm", 0.0)), 0.0)
	if has_puddle:
		local["puddle_depth_mm"] = puddle_depth
		local["puddle_drag"] = puddle_drag
		local["water_mm"] = maxf(float(local.get("water_mm", 0.0)), puddle_depth)
	if has_river:
		if river_depth > float(local.get("puddle_depth_mm", 0.0)):
			local["puddle_depth_mm"] = river_depth
			local["puddle_drag"] = river_drag
		local["water_mm"] = maxf(float(local.get("water_mm", 0.0)), river_depth)
		local["river_depth_mm"] = river_depth
		local["river_channel_id"] = river_channel_id
	local["surface_name"] = surface_name
	return local


func _local_conditions_at_contact(surface_name: String, position: Vector3, loaded: bool) -> Dictionary:
	var local := _local_conditions_base(surface_name, position, loaded)
	var has_puddle := false
	var p_depth := 0.0
	var p_drag := 0.0
	if loaded and is_instance_valid(puddle_system):
		var puddle: Dictionary = puddle_system.sample_contact(position)
		has_puddle = true
		p_depth = float(puddle.depth_mm)
		p_drag = float(puddle.drag)
	var has_river := false
	var r_depth := 0.0
	var r_drag := 1.25
	var r_channel := ""
	if loaded and is_instance_valid(river_system):
		# Agua de cauce y parche se combinan tomando el máximo; se propagan
		# los parámetros del origen elegido. Se conserva el máximo con el
		# agua climática para los consumidores actuales (neumáticos,
		# telemetría, VFX leen puddle_depth_mm/puddle_drag).
		var river: Dictionary = river_system.sample_contact(position)
		has_river = true
		r_depth = float(river.get("depth_mm", 0.0))
		r_drag = float(river.get("drag_scale", 1.25))
		r_channel = str(river.get("channel_id", ""))
	return _apply_water_overlays_to_local(local, surface_name, has_puddle, p_depth, p_drag, has_river, r_depth, r_drag, r_channel)


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
		var next_kpa := clampf(
			float(cold.get(key, 180.0)) + delta_kpa,
			RallySetupCatalog.PRESSURE_MIN,
			RallySetupCatalog.PRESSURE_MAX,
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


func current_setup_values() -> Dictionary:
	var values := setup_values.duplicate()
	var cold: Dictionary = domains.get("tires", {}).get("tires", {}).get("pressure", {}).get("cold_kpa_gauge", {})
	values["garage.front_pressure"] = RallySetupCatalog.axle_pressure(cold, "F")
	values["garage.rear_pressure"] = RallySetupCatalog.axle_pressure(cold, "R")
	return values


func apply_setup_values(values: Dictionary) -> Dictionary:
	var validation := RallySetupCatalog.validate(values, setup_design_values, setup_design_suspension)
	if not bool(validation.get("ok", false)):
		return validation
	var effective_values: Dictionary = validation.values
	effective_values["fuel.initial_kg"] = clampf(
		float(effective_values["fuel.initial_kg"]), 0.0, mass_model.fuel_capacity_kg
	)
	RallySetupCatalog.apply(domains, effective_values)
	setup_values = effective_values.duplicate()
	var fuel: Dictionary = domains.get("fuel", { }).get("fuel", { })
	var fuel_kg := clampf(
		float(fuel.get("initial_kg", mass_model.fuel_initial_kg)),
		0.0,
		mass_model.fuel_capacity_kg,
	)
	mass_model.fuel_initial_kg = fuel_kg
	mass_state = mass_model.resolve(fuel_kg)
	if mass_state.has("inertia_tensor") and mass_state["inertia_tensor"] is Basis:
		unsprung_rig.set_local_inertia_tensor(mass_state["inertia_tensor"])
	thermal_model.fuel_remaining_litres = fuel_kg / maxf(
		mass_model.fuel_density_kg_per_litre,
		0.000001,
	)
	var suspension: Dictionary = domains.get("suspension", { }).get("suspension", { })
	var stock_geometry: Dictionary = setup_design_suspension.get("geometry_physical", {})
	var suspension_index := int(effective_values["garage.suspension"]) - 1
	var spring_factor: float = RallySetupCatalog.SPRING_FACTORS[suspension_index]
	var damping_factor := lerpf(1.05, 0.95, suspension_index / 4.0)
	var stop_factor := lerpf(1.10, 0.90, suspension_index / 4.0)
	var height_delta := (suspension_index - 2) * 0.006
	for axle_index in 2:
		var axle := "front" if axle_index == 0 else "rear"
		var trim: Dictionary = suspension.get(axle, { })
		var stock: Dictionary = setup_design_suspension[axle]
		var stock_elements: Dictionary = stock_geometry.get(axle, {})
		var bump_stop_mult := float(stock_elements.get("bump_stop_mult", 1.0)) * stop_factor
		for wheel_index in ([0, 1] if axle_index == 0 else [2, 3]):
			var parameters: Dictionary = suspension_model.axle_parameters[wheel_index]
			parameters.camber = float(trim.get("camber", 0.0))
			parameters.toe = float(trim.get("toe", 0.0))
			# Positive travel compresses the spring and lowers the chassis.
			parameters.rest_compression_offset = clampf(
				-height_delta, -float(parameters.droop_m) * 0.25, float(parameters.bump_m) * 0.25
			)
			var reference_mass := float(parameters.frequency_reference_mass_kg)
			var frequency := float(stock.ride_frequency_hz) * sqrt(spring_factor)
			var rates := VehicleSuspensionModel.corner_rates(
				reference_mass,
				frequency,
				float(stock.get("damping_ratio", 0.65)),
				float(stock.get("bump_damp_multiplier", 1.0)) * damping_factor,
				float(stock.get("rebound_damp_multiplier", 1.0)),
				bump_stop_mult
			)
			parameters.ride_frequency_hz = frequency
			parameters.spring_rate = float(rates["spring_rate"])
			parameters.bump_damping = float(rates["bump_damping"])
			parameters.rebound_damping = float(rates["rebound_damping"])
			parameters.bump_stop_stiffness = float(rates["bump_stop_stiffness"])
			suspension_model.axle_parameters[wheel_index] = parameters
		var stock_bar: Dictionary = stock_geometry.get(axle + "_arb", {})
		var stock_ratio := float(stock_bar.get("ratio", 0.0))
		var arb_index := int(effective_values["garage." + axle + "_arb"]) - 1
		var target_ratio := stock_ratio * float(RallySetupCatalog.ARB_FACTORS[arb_index])
		if stock_ratio <= 0.0:
			target_ratio = maxf(2.0 - arb_index, 0.0) * 0.05
		var spring_rate := float(suspension_model.axle_parameters[axle_index * 2].spring_rate)
		var stiffness := VehicleSuspensionModel.arb_stiffness_n_per_m(spring_rate / spring_factor, target_ratio)
		if axle_index == 0:
			suspension_model.front_arb_stiffness_n_per_m = stiffness
		else:
			suspension_model.rear_arb_stiffness_n_per_m = stiffness
	suspension_model.sync_flat_parameters()
	var brakes: Dictionary = domains.get("brakes", { }).get("brakes", { })
	var thermal_brakes: Dictionary = brakes.get("thermal", {})
	for key in ["front_duct", "rear_duct"]:
		if thermal_brakes.has(key):
			thermal_model.brake_thermal_config[key] = (thermal_brakes[key] as Dictionary).duplicate()
	brake_model.front_brake_bias = clampf(float(brakes.get("front_brake_bias", 0.5)), 0.0, 1.0)
	brake_model.maximum_brake_torque_nm = float(
		brakes.get("max_brake_torque", brake_model.maximum_brake_torque_nm)
	)
	var powertrain: Dictionary = domains.get("powertrain", { }).get("powertrain", { })
	powertrain_model.maximum_rpm = float(effective_values["powertrain.max_rpm"])
	var stock_thermal: Dictionary = setup_design_powertrain.get("thermal", {})
	var duct: Dictionary = stock_thermal.get("water_cooling_duct", {})
	if not duct.is_empty():
		duct = duct.duplicate()
		var opening := int(effective_values["garage.cooling"])
		if opening < 0:
			duct["opening"] = RallySetupCatalog.MINIMUM_COOLING_OPENING
		elif opening > 0:
			duct["opening"] = opening * 0.25
		thermal_model.engine_config["water_cooling_duct"] = duct
	powertrain_model.final_drive_gravel = float(powertrain.get("final_drive_gravel", powertrain_model.final_drive_gravel))
	powertrain_model.final_drive_tarmac = float(powertrain.get("final_drive_tarmac", powertrain_model.final_drive_tarmac))
	var _preset := str(setup_design_powertrain.get("final_drive_preset", ""))
	if not is_equal_approx(float(effective_values["powertrain.final_drive"]), float(setup_design_values["powertrain.final_drive"])):
		_preset = ""
	powertrain_model.final_drive_preset = _preset
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
	powertrain_model.sync_setup_differentials(
		_setup_differential("differential", effective_values),
		_setup_differential("differential_front", effective_values),
		_setup_differential("differential_rear", effective_values)
	)
	powertrain_model.invalidate_rust_config()
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
	_apply_setup_pressures(effective_values)
	return {"ok": true, "values": effective_values}


func _apply_setup_pressures(values: Dictionary) -> void:
	RallySetupCatalog.apply_pressures(domains, values)
	var pressure: Dictionary = domains.get("tires", { }).get("tires", { }).get("pressure", { })
	var cold_pressures: Dictionary = pressure.get("cold_kpa_gauge", { })
	var temperature_reference := float(pressure.get("reference_temperature_c", 25.0))
	for wheel_index in 4:
		var wheel_key: String = ["FL", "FR", "RL", "RR"][wheel_index]
		var cold_bar := float(cold_pressures.get(wheel_key, 180.0)) / 100.0
		# Función común §1: actualiza la referencia en frío y refleja la
		# pérdida existente en la misma llamada; conserva gas y fuga.
		thermal_model.set_pressure_reference(wheel_index, cold_bar, temperature_reference)


func _setup_differential(block: String, values: Dictionary) -> Variant:
	if block != "differential" and not setup_design_powertrain.has(block):
		return null
	var stock: Dictionary = setup_design_powertrain.get(block, {})
	var differential := stock.duplicate()
	var prefix := RallySetupCatalog.DIFFERENTIAL_PREFIX
	var adjustable := bool(values["garage.lsd"])
	var stock_type := str(stock.get("type", "clutch_lsd"))
	var stock_open := stock_type == "open"
	differential["type"] = stock_type
	if not adjustable:
		differential["type"] = "open"
		if not stock_open:
			differential["preset_id"] = ""
		return differential
	if stock_open:
		differential["type"] = "clutch_lsd"
		differential["preload_nm"] = 15.0
		differential["clutch_friction_coefficient"] = 0.10
		differential["coast_friction_coefficient"] = 0.10
		differential["ramp_gain"] = 0.16
	for key in ["clutches", "power_ramp_angle_deg", "coast_ramp_angle_deg"]:
		var path: String = prefix + key
		if stock_open or not is_equal_approx(float(values[path]), float(setup_design_values[path])):
			differential[key] = values[path]
			differential["preset_id"] = ""
	return differential


func bind_wheel_visuals(pivots: Array[Node3D], visuals: Array[Node3D]) -> void:
	wheel_visual_pivots = pivots
	wheel_visuals = visuals


func create_wheel_contact_casts(body: RigidBody3D) -> void:
	unsprung_rig.create(body, wheel_positions_local, mass_model.unsprung_mass_kg, suspension_model, wheel_radii)
	for old_cast in wheel_contact_casts:
		old_cast.queue_free()
	wheel_contact_casts.clear()
	for i in 4:
		var cast := ShapeCast3D.new()
		cast.name = "WheelContact_" + WHEEL_KEYS[i]
		var cylinder := CylinderShape3D.new()
		cylinder.radius = wheel_radii[i]
		cylinder.height = wheel_widths[i]
		cylinder.margin = SHAPECAST_CYLINDER_MARGIN
		cast.shape = cylinder
		cast.enabled = false
		cast.margin = SHAPECAST_MARGIN
		cast.max_results = 16
		cast.collide_with_areas = false
		cast.collide_with_bodies = true
		body.add_child(cast)
		cast.add_exception_rid(body.get_rid())
		wheel_contact_casts.append(cast)
	# Paso 0.1/0.2 Jolt fix: diagnóstico rápido en consola. Firma de
	# solapamiento (qué devuelven cast_motion/intersect/get_rest_info con la
	# rueda enterrada 0.05 m) + chequeo ω*dt y c*dt/m_eff por esquina a
	# dt = 1/120 s. Si cualquiera supera 2.0 el integrador explícito diverge.
	_print_stability_diagnostic(body)
	# Paso 0.1: arma la firma de solapamiento; se ejecuta en el primer tick,
	# cuando ya existe un PhysicsDirectSpaceState3D (no disponible en setup).
	debug_overlap_signature_requested = true


## Paso 0.2: imprime ω*dt y c*dt/m_eff por esquina a dt=1/120.
## Si cualquiera supera 2.0, el integrador explícito explota por sí solo.
func _print_stability_diagnostic(body: RigidBody3D) -> void:
	var dt := 1.0 / 120.0
	var hub_masses: Array = mass_model.unsprung_mass_kg
	var total_sprung := maxf(float(mass_state.get("mass_kg", 1000.0)), 1.0)
	var corner_m := maxf(total_sprung * 0.25, 1.0)
	for i in 4:
		if i >= suspension_model.axle_parameters.size():
			continue
		var p: Dictionary = suspension_model.axle_parameters[i]
		var hm := float(hub_masses[i]) if i < hub_masses.size() else 15.0
		var m := VehicleSuspensionModel.stability_metrics(p, hm, corner_m, dt)
		print("RALLY_STABILITY_DIAG ", JSON.stringify({"wheel": i, "omega_dt": float(m["omega_dt"]), "c_dt_over_m": float(m["damper_dt_over_m"]), "m_eff_kg": float(m["m_eff_kg"]), "stable": bool(m["stable"]), "dt": dt}))


## Paso 2.2 Jolt fix: comprueba solapamiento inicial en el origen con
## intersect_shape. Si hay solapamiento, recupera punto y normal limpios con
## get_rest_info (normal del triángulo, sin fracción global contaminada).
## Devuelve {overlap, rest_position, rest_normal, rest_rid}.
static func check_initial_overlap(
	space_state: PhysicsDirectSpaceState3D,
	shape: Shape3D,
	origin: Transform3D,
	collision_margin: float,
	collision_mask: int,
	exclude: Array[RID],
) -> Dictionary:
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = shape
	qp.transform = origin
	qp.margin = collision_margin
	qp.collision_mask = collision_mask
	qp.exclude = exclude
	qp.collide_with_areas = false
	qp.collide_with_bodies = true
	var hits := space_state.intersect_shape(qp, 1)
	if hits.is_empty():
		return {"overlap": false}
	var rest := space_state.get_rest_info(qp)
	if rest.is_empty():
		return {"overlap": true}
	return {
		"overlap": true,
		"rest_position": rest.get("point", Vector3.ZERO),
		"rest_normal": (rest.get("normal", Vector3.UP) as Vector3).normalized(),
		"rest_rid": rest.get("rid", RID()),
		"rest_collider_id": rest.get("collider_id", 0),
	}


## Paso 3.1 Jolt fix: discriminación Flanco vs Banda con el eje de giro.
## axial = |n · spin_axis|. sidewall (axial>0.70) = golpe de flanco → daño,
## NO genera Fz. tread (axial<0.45 y n·up>0.25) = suelo válido para Fz.
## No subir el umbral global a 0.55: mataría el apoyo en peraltes/cunetas.
static func classify_tire_contact(contact_normal: Vector3, wheel_spin_axis: Vector3, chassis_up: Vector3) -> Dictionary:
	var n := (contact_normal as Vector3).normalized()
	var s := (wheel_spin_axis as Vector3).normalized()
	var u := (chassis_up as Vector3).normalized()
	var axial := absf(n.dot(s))
	var is_sidewall := axial > SIDEWALL_AXIAL_MIN
	var is_tread := axial < TREAD_AXIAL_MAX and n.dot(u) > TREAD_UP_MIN
	return {"axial": axial, "is_sidewall": is_sidewall, "is_tread": is_tread}


## Paso 3.3 Jolt fix: la ley de sensibilidad de carga (mu_eff = mu0 *
## (max(fz,1)/fz_nominal)^(-k_load)) tiene una única implementación en
## TireModel.load_adjusted_mu(), usada por el modelo de neumático. El tope
## duro 2.4× queda restringido a recuperación de baja confianza (ver step()).


## Paso 0.1 Jolt fix: firma de solapamiento en Jolt. Con la rueda enterrada
## 0.05 m, imprime qué devuelven space.cast_motion(q), space.intersect_shape(q)
## y space.get_rest_info(q). Si cast_motion reporta [0,0] o [1,1] naciendo
## solapado y get_rest_info entrega la normal limpia del triángulo, el
## diagnóstico confirma el solapamiento inicial antes de aplicar fuerzas.
static func debug_overlap_signature(
	space_state: PhysicsDirectSpaceState3D,
	shape: Shape3D,
	origin: Transform3D,
	target: Vector3,
	collision_margin: float,
	collision_mask: int,
	exclude: Array[RID],
) -> Dictionary:
	var qmotion := PhysicsShapeQueryParameters3D.new()
	qmotion.shape = shape
	qmotion.transform = origin
	qmotion.margin = collision_margin
	qmotion.collision_mask = collision_mask
	qmotion.exclude = exclude
	qmotion.collide_with_areas = false
	qmotion.collide_with_bodies = true
	qmotion.motion = target
	var cast_res := space_state.cast_motion(qmotion)
	var qshape := PhysicsShapeQueryParameters3D.new()
	qshape.shape = shape
	qshape.transform = origin
	qshape.margin = collision_margin
	qshape.collision_mask = collision_mask
	qshape.exclude = exclude
	qshape.collide_with_areas = false
	qshape.collide_with_bodies = true
	var hits := space_state.intersect_shape(qshape, 4)
	var rest := space_state.get_rest_info(qshape)
	var sig := {"cast_motion": cast_res, "intersect_count": hits.size(), "rest": rest}
	print("RALLY_OVERLAP_SIGNATURE ", JSON.stringify({"cast_motion": cast_res, "hits": hits.size(), "has_rest": not rest.is_empty(), "rest_normal": [float((rest.get("normal", Vector3.UP) as Vector3).x), float((rest.get("normal", Vector3.UP) as Vector3).y), float((rest.get("normal", Vector3.UP) as Vector3).z)] if not rest.is_empty() else []}))
	return sig


## Paso 0.1 Jolt fix: pide la firma de solapamiento en el próximo tick.
## Se arma automáticamente al crear los casts (primer tick) y está disponible
## para repetirla en cualquier momento desde consola/telemetría.
func request_overlap_signature_diagnostic() -> void:
	debug_overlap_signature_requested = true


## Paso 0.1 Jolt fix: ejecuta la consulta con la rueda 0 hundida 0.05 m.
## Usa el cilindro real, su margen y su máscara, y excluye chasis y bujes.
## Se llama desde step() porque necesita el space state del tick.
func _run_overlap_signature_diagnostic(
	body: RigidBody3D,
	state: PhysicsDirectBodyState3D,
	chassis_up: Vector3,
) -> void:
	var cast := wheel_contact_casts[0]
	var orientation := Basis(Vector3.UP, 0.0) * Basis(
		Vector3.BACK,
		suspension_model.dynamic_wheel_camber(0),
	) * Basis(Vector3.BACK, PI * 0.5)
	var buried_origin := state.transform * Transform3D(
		orientation,
		wheel_positions_local[0] - chassis_up * OVERLAP_DIAGNOSTIC_BURY_M,
	)
	var excluded: Array[RID] = [body.get_rid()]
	last_overlap_signature = debug_overlap_signature(
		state.get_space_state(),
		cast.shape,
		buried_origin,
		chassis_up * OVERLAP_DIAGNOSTIC_BURY_M,
		SHAPECAST_CYLINDER_MARGIN,
		body.collision_mask,
		excluded,
	)


## Selección del apoyo ShapeCast (§3): el apoyo con máxima alineación con +Y
## por encima de 0.25. Devuelve punto, normal, collider, índice y alineación,
## SIN fracción segura: Godot 4.7.1 no expone fracción por colisión (solo
## `get_closest_collision_safe_fraction()` global), así que la distancia
## coherente se obtiene aislando este apoyo en una consulta adicional
## (`_query_shapecast_contact()`). En pendiente no se proyecta el punto como
## si viniera de un rayo: la altura sale del barrido del cilindro.
## Devuelve {} sin apoyo válido.
static func _is_road_sign(collider: Variant) -> bool:
	return collider is CollisionObject3D and collider.get_meta("collision_role", "") in ["road_sign", "fallen_sign"]


static func select_shapecast_support(cast: ShapeCast3D, chassis_up: Vector3) -> Dictionary:
	var best := {}
	var best_alignment := 0.25
	for collision_index in cast.get_collision_count():
		if _is_road_sign(cast.get_collider(collision_index)):
			continue
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


static func _restore_shapecast_exceptions(cast: ShapeCast3D, permanent_exceptions: Array[RID]) -> void:
	cast.clear_exceptions()
	for prid in permanent_exceptions:
		cast.add_exception_rid(prid)


## Calcula la fracción segura proyectada geométricamente sobre el plano `(point, normal)`
## para el apoyo seleccionado. Evita heredar a ciegas `get_closest_collision_safe_fraction()`
## cuando un mismo `StaticBody3D` agrupa varias formas (p. ej. calzada + bordillo/talud)
## y `exclude` por RID no puede separarlas.
static func _shapecast_projected_safe_fraction(
	cast: ShapeCast3D,
	point: Vector3,
	normal: Vector3,
	travel_m: float,
) -> Dictionary:
	if travel_m <= 1.0e-6 or cast.target_position.length_squared() <= 1.0e-12:
		return {"ok": false}
	if not (cast.shape is CylinderShape3D):
		return {"ok": false}
	var origin := cast.global_transform.origin
	var sweep_dir := (cast.global_transform.basis * cast.target_position).normalized()
	var up_dir := -sweep_dir
	var unit_normal := normal.normalized()
	var denom := unit_normal.dot(up_dir)
	if denom <= 0.25:
		return {"ok": false}
	var cyl := cast.shape as CylinderShape3D
	var axis := cast.global_transform.basis.y.normalized()
	var n_dot_a := clampf(absf(unit_normal.dot(axis)), 0.0, 1.0)
	var n_perp := sqrt(maxf(1.0 - n_dot_a * n_dot_a, 0.0))
	var support := cyl.height * 0.5 * n_dot_a + cyl.radius * n_perp
	var sweep_m := ((origin - point).dot(unit_normal) - support) / denom
	return {
		"ok": true,
		"sweep_m": sweep_m,
		"safe_fraction": sweep_m / travel_m,
	}


static func _resolved_safe_for_same_rid(
	cast: ShapeCast3D,
	point: Vector3,
	normal: Vector3,
	global_safe: float,
	travel_m: float,
) -> Dictionary:
	var proj := _shapecast_projected_safe_fraction(cast, point, normal, travel_m)
	if not bool(proj.get("ok", false)):
		return {
			"safe": global_safe,
			"coherent": true,
			"same_rid_projected": false,
			"proj_safe": global_safe,
		}
	var proj_sweep_m := float(proj["sweep_m"])
	var proj_safe := float(proj["safe_fraction"])
	if absf(proj_sweep_m - global_safe * travel_m) > 0.015:
		var in_range := proj_safe >= -0.05 and proj_safe <= 1.05
		return {
			"safe": proj_safe if in_range else global_safe,
			"coherent": in_range,
			"same_rid_projected": in_range,
			"proj_safe": proj_safe,
		}
	return {
		"safe": global_safe,
		"coherent": true,
		"same_rid_projected": false,
		"proj_safe": proj_safe,
	}


## Barrido cilíndrico coherente (H2), núcleo estático: punto, normal, collider
## y distancia del MISMO apoyo. Tras seleccionar por alineación, si hay más
## de una colisión se aísla el apoyo seleccionado excluyendo los demás
## colliders y se repite el barrido; cuando todas las colisiones pertenecen al
## mismo `StaticBody3D` (`exclude_rids` vacío), valida o proyecta la distancia
## usando el punto y normal del apoyo elegido para evitar contaminar con otros
## sub-shapes. Si el barrido queda detenido únicamente contra un muro/barrera
## vertical (`alignment <= 0.25`), excluye temporalmente esos cuerpos una vez
## para alcanzar el suelo debajo. `permanent_exceptions` se restauran siempre.
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
		# Paso 2.3 Jolt fix: conservar los impactos de barrera para daño.
		# Se guardan en un array local de este paso (position/normal/collider
		# del MISMO candidato) en vez de releer el ShapeCast ya modificado.
		var barrier_hits: Array = []
		for ci in first_count:
			var bcol: Variant = cast.get_collider(ci)
			barrier_hits.append({
				"position": cast.get_collision_point(ci),
				"normal": (cast.get_collision_normal(ci) as Vector3).normalized(),
				"collider": bcol,
			})
		var barrier_rids: Array[RID] = []
		for ci in first_count:
			var other_b: Variant = cast.get_collider(ci)
			if other_b is CollisionObject3D:
				var brid := (other_b as CollisionObject3D).get_rid()
				if not barrier_rids.has(brid):
					barrier_rids.append(brid)
		if barrier_rids.is_empty():
			return {"sweeps": sweeps}
		for brid in barrier_rids:
			cast.add_exception_rid(brid)
		cast.force_shapecast_update()
		sweeps += 1
		first_count = cast.get_collision_count()
		if first_count == 0:
			_restore_shapecast_exceptions(cast, permanent_exceptions)
			# Sin suelo debajo: devolver solo barreras para daño, sin apoyo.
			return {"sweeps": sweeps, "barrier_hits": barrier_hits}
		global_safe = cast.get_closest_collision_safe_fraction()
		selected = select_shapecast_support(cast, chassis_up)
		if selected.is_empty():
			_restore_shapecast_exceptions(cast, permanent_exceptions)
			return {"sweeps": sweeps, "barrier_hits": barrier_hits}
		# Suelo encontrado bajo la barrera: el apoyo es el suelo; las
		# barreras viajan aparte para daño (Paso 2.3).
		# Se adjunta abajo tras resolver el apoyo coherente.
		selected["__barrier_hits"] = barrier_hits
	if first_count == 1:
		_restore_shapecast_exceptions(cast, permanent_exceptions)
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
			"barrier_hits": selected.get("__barrier_hits", []),
		}
	# Múltiples apoyos: aislar el seleccionado excluyendo los demás RIDs distintos.
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
		_restore_shapecast_exceptions(cast, permanent_exceptions)
		var same_rid_res := _resolved_safe_for_same_rid(
			cast,
			selected["position"] as Vector3,
			selected["normal"] as Vector3,
			global_safe,
			travel_m,
		)
		var safe := float(same_rid_res["safe"])
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
			"coherent": bool(same_rid_res["coherent"]),
			"sweeps": sweeps,
			"barrier_hits": selected.get("__barrier_hits", []),
			"verify": {
				"same_rid_multi_shape": true,
				"same_rid_projected": bool(same_rid_res["same_rid_projected"]),
				"proj_safe": float(same_rid_res["proj_safe"]),
			},
		}
	for rid in exclude_rids:
		cast.add_exception_rid(rid)
	cast.force_shapecast_update()
	sweeps += 1
	var isolated_safe := cast.get_closest_collision_safe_fraction()
	var isolated_count := cast.get_collision_count()
	var isolated_ok := isolated_count > 0
	var isolated_sel := select_shapecast_support(cast, chassis_up) if isolated_count > 1 else {}
	var isolated_idx := int(isolated_sel.get("collision_index", 0)) if not isolated_sel.is_empty() else 0
	var isolated_collider: Variant = cast.get_collider(isolated_idx) if isolated_ok else null
	var isolated_point: Vector3 = cast.get_collision_point(isolated_idx) if isolated_ok else selected["position"]
	var isolated_normal: Vector3 = (cast.get_collision_normal(isolated_idx) as Vector3).normalized() if isolated_ok else selected["normal"]
	_restore_shapecast_exceptions(cast, permanent_exceptions)
	if not isolated_ok:
		return {"sweeps": sweeps}
	var resolved_isolated_safe := isolated_safe
	var same_rid_projected := false
	if isolated_count > 1:
		var iso_same_rid := _resolved_safe_for_same_rid(
			cast,
			isolated_point,
			isolated_normal,
			isolated_safe,
			travel_m,
		)
		resolved_isolated_safe = float(iso_same_rid["safe"])
		same_rid_projected = bool(iso_same_rid["same_rid_projected"])
	var same_collider: bool = isolated_collider == selected_collider
	var point_gap := (isolated_point - (selected["position"] as Vector3)).length()
	var normal_gap := (isolated_normal - (selected["normal"] as Vector3)).length()
	var coherent: bool = same_collider and point_gap < 0.05 and normal_gap < 0.05
	return {
		"position": isolated_point,
		"normal": isolated_normal,
		"collider": isolated_collider,
		"distance": float(wheel_radius_m) + float(travel_m) * float(resolved_isolated_safe) - float(bump_m),
		"safe_fraction": float(resolved_isolated_safe),
		"global_safe_fraction": float(global_safe),
		"collision_index": int(selected["collision_index"]),
		"collision_count": first_count,
		"isolated_collision_count": isolated_count,
		"alignment": float(selected["alignment"]),
		"isolated": true,
		"coherent": coherent,
		"sweeps": sweeps,
		"barrier_hits": selected.get("__barrier_hits", []),
		"verify": {
			"same_collider": same_collider,
			"point_gap_m": point_gap,
			"normal_gap": normal_gap,
			"same_rid_projected": same_rid_projected,
		},
	}


static func _shapecast_is_initial_overlap(
	cast: ShapeCast3D,
	hit: Dictionary,
	travel_m: float,
) -> bool:
	if hit.is_empty():
		return true
	var safe := float(hit.get("safe_fraction", 0.0))
	if safe <= 0.001:
		return true
	# En Jolt Physics, ShapeCast3D/cast_motion devuelve safe_fraction == 1.0
	# cuando el cilindro arranca solapado con el suelo; contrastamos contra
	# la proyección geométrica del contacto reportado.
	if safe >= 0.999 and hit.has("position") and hit.has("normal"):
		var proj := _shapecast_projected_safe_fraction(
			cast,
			hit["position"] as Vector3,
			hit["normal"] as Vector3,
			travel_m,
		)
		if bool(proj.get("ok", false)) and float(proj["safe_fraction"]) <= 0.05:
			return true
		if not bool(hit.get("coherent", true)):
			return true
	return false


func _sweep_shapecast_with_elevation(
	cast: ShapeCast3D,
	body_transform: Transform3D,
	orientation: Basis,
	wheel_local_pos: Vector3,
	chassis_up: Vector3,
	wheel_radius_m: float,
	base_bump_m: float,
	base_travel_m: float,
	elevation_m: float,
	permanents: Array[RID],
) -> Dictionary:
	var eff_bump := base_bump_m + elevation_m
	var eff_travel := base_travel_m + elevation_m
	cast.global_transform = body_transform * Transform3D(
		orientation,
		wheel_local_pos + Vector3.UP * eff_bump,
	)
	cast.target_position = orientation.inverse() * (Vector3.DOWN * eff_travel)
	var hit := shapecast_coherent_result(cast, chassis_up, wheel_radius_m, eff_travel, eff_bump, permanents)
	if hit.has("position"):
		hit["query_bump_m"] = eff_bump
		hit["query_travel_m"] = eff_travel
		hit["elevated_m"] = elevation_m
	hit["_initial_overlap"] = _shapecast_is_initial_overlap(cast, hit, eff_travel)
	return hit


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
	# Wheel camber rotates around +Z (Vector3.BACK) in axle space to match WheelVisual tilt.
	var orientation := Basis(Vector3.UP, steer) * Basis(
		Vector3.BACK,
		suspension_model.dynamic_wheel_camber(index),
	) * Basis(Vector3.BACK, PI * 0.5)
	cast.collision_mask = body.collision_mask
	var permanents: Array[RID] = [body.get_rid()]
	# Paso 2.2 Jolt fix: separar solapamiento inicial del barrido normal.
	# 1) Comprobar primero en el origen con intersect_shape. 2) Si hay
	# solapamiento, el barrido se hace desde posición elevada (origin+up*lift)
	# o se recupera punto/normal con get_rest_info. 3) position, normal,
	# collider y distance provienen del MISMO candidato (nunca fracción
	# global + normal de otro obstáculo: lo garantiza shapecast_coherent_result).
	var _need_elevated := false
	# Nota: sin PhysicsDirectSpaceState aquí (llamado desde step con state),
	# la separación se hace por heurística safe_fraction + proyección (ver
	# _shapecast_is_initial_overlap) + barrido elevado con extremo inferior
	# invariante. La firma exacta cast_motion/intersect/get_rest_info se
	# diagnostica en _debug_overlap_signature() (Paso 0.1).
	var best := _sweep_shapecast_with_elevation(
		cast, body_transform, orientation, wheel_positions_local[index],
		chassis_up, wheel_radii[index], bump, travel, 0.0, permanents,
	)
	var total_sweeps := int(best.get("sweeps", 1))
	var best_has_support := best.has("position")
	var best_overlap := bool(best.get("_initial_overlap", not best_has_support))
	best.erase("sweeps")
	best.erase("_initial_overlap")
	if best_has_support and not best_overlap:
		contact_query_count += total_sweeps
		return best
	# Recuperación por barrido elevado (P0): si el cilindro comienza en o bajo
	# el terreno (safe_fraction <= 0.001, solapamiento Jolt con safe ≈ 1.0 o
	# vacío en malla ConcavePolygonShape3D), elevamos el origen manteniendo
	# invariante el extremo inferior del barrido.
	var phys_comp := (
		unsprung_rig.q[index]
		if index < unsprung_rig.q.size()
		else 0.0
	)
	var elev_1 := clampf(maxf(0.18, phys_comp - bump + 0.16), 0.18, 0.38)
	var elev_2 := clampf(maxf(elev_1 + 0.22, wheel_radii[index] + 0.14), elev_1 + 0.15, 0.55)
	var elevs: Array[float] = [elev_1, elev_2]
	var saw_overlap_hit := best.has("position") and best_overlap
	var preserved_barriers: Array = Array(best.get("barrier_hits", []))
	var step_idx := 0
	while step_idx < elevs.size():
		var cand := _sweep_shapecast_with_elevation(
			cast, body_transform, orientation, wheel_positions_local[index],
			chassis_up, wheel_radii[index], bump, travel, elevs[step_idx], permanents,
		)
		total_sweeps += int(cand.get("sweeps", 1))
		var cand_has_support := cand.has("position")
		var cand_overlap := bool(cand.get("_initial_overlap", not cand_has_support))
		cand.erase("sweeps")
		cand.erase("_initial_overlap")
		# Paso 2.3: acumular barreras de todos los barridos para daño.
		for bh in Array(cand.get("barrier_hits", [])):
			preserved_barriers.append(bh)
		cand["barrier_hits"] = preserved_barriers.duplicate()
		if cand_has_support:
			if not cand_overlap:
				best = cand
				break
			saw_overlap_hit = true
			if not best.has("position") or best_overlap or float(cand.get("distance", INF)) < float(best.get("distance", INF)):
				best = cand
				best_overlap = true
		elif cand.is_empty() and (saw_overlap_hit or not best.has("position")):
			# Sin apoyo en este barrido elevado: mantener barreras acumuladas.
			best["barrier_hits"] = preserved_barriers.duplicate()
		step_idx += 1
		if step_idx == 2 and (saw_overlap_hit or not best.has("position")):
			elevs.append(maxf(elev_2 + 0.35, 0.90))
	best["barrier_hits"] = preserved_barriers.duplicate()
	# Paso 2.2: marcar recuperación de solapamiento de baja confianza para que
	# el neumático aplique el tope duro Fz solo en ese caso (Paso 3.3).
	if best_overlap and best.has("position"):
		best["recovered_overlap"] = true
		best["low_confidence"] = true
	contact_query_count += total_sweeps
	return best


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
	var hits: Array[Dictionary] = []
	for offset in supports:
		var origin := center + forward * offset + up * bump
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin - up * (travel + wheel_radii[index]), body.collision_mask, excluded
		)
		var sample := state.get_space_state().intersect_ray(query)
		contact_query_count += 1
		if _is_road_sign(sample.get("collider")):
			query.exclude = [body.get_rid(), sample.rid]
			sample = state.get_space_state().intersect_ray(query)
			contact_query_count += 1
		if not sample.is_empty() and (_is_road_sign(sample.collider) or (sample.normal as Vector3).dot(up) <= 0.25):
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
	# Paso 0.1 Jolt fix: firma de solapamiento armada (una sola vez por petición).
	if debug_overlap_signature_requested:
		debug_overlap_signature_requested = false
		_run_overlap_signature_diagnostic(body, state, chassis_up)
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
		if hit.is_empty() or not hit.has("position"):
			# Rama sin impacto (§1 + Paso 2.3): sin apoyo de suelo (vacío o
			# solo barreras). Se conservan las barreras para daño.
			wheel_loads[i] = 0.0
			wheel_surfaces[i] = "Unknown"
			last_barrier_hits[i] = Array(hit.get("barrier_hits", []))
			contacts.append({"hit": false, "barrier_hits": last_barrier_hits[i]})
			continue
		wheel_contact_points[i] = hit["position"]
		wheel_contact_normals[i] = (hit["normal"] as Vector3).normalized()
		wheel_surfaces[i] = _surface_for_collider(hit.get("collider"))
		# Paso 3.1 Jolt fix: eje de giro de la rueda (spin axis) para distinguir
		# flanco vs banda. heading con steer+toe, forward proyectado, right =
		# eje de giro. No usar umbral global 0.55: mata peraltes/cunetas.
		var _steer_full: float = steer
		var _heading: Vector3 = (-state.transform.basis.z).rotated(chassis_up, _steer_full).normalized()
		var _fwd: Vector3 = (_heading - wheel_contact_normals[i] * _heading.dot(wheel_contact_normals[i])).normalized()
		if _fwd.length_squared() < 0.5:
			_fwd = (-state.transform.basis.z).normalized()
		var _spin_axis: Vector3 = _fwd.cross(wheel_contact_normals[i]).normalized()
		if _spin_axis.length_squared() < 0.5:
			_spin_axis = state.transform.basis.x.normalized()
		var _cls := classify_tire_contact(wheel_contact_normals[i], _spin_axis, chassis_up)
		var _is_sidewall := bool(_cls["is_sidewall"])
		var _is_tread := bool(_cls["is_tread"])
		# Paso 3.2: guardia de penetración profunda con recuperación. Si el
		# punto aparece por encima del centro del buje pero es banda (tread),
		# NO devolver NO_SUPPORT: es penetración profunda (tope llanta /
		# recuperación). Solo descartar si es flanco (sidewall).
		var _hub_center: Vector3 = state.transform * wheel_positions_local[i]
		var _is_deep := (wheel_contact_points[i] - _hub_center).dot(chassis_up) > 0.0
		var _deep_recovery := _is_deep and _is_tread
		if _is_sidewall and not _deep_recovery:
			# Golpe de flanco contra muro/talud: va a daño, NO genera Fz.
			# Se conserva el contacto geométrico para daño pero sin apoyo.
			last_barrier_hits[i] = Array(hit.get("barrier_hits", []))
			last_barrier_hits[i].append({"position": wheel_contact_points[i], "normal": wheel_contact_normals[i], "collider": hit.get("collider")})
			wheel_loads[i] = 0.0
			contacts.append({"hit": false, "sidewall": true, "axial": float(_cls["axial"]), "barrier_hits": last_barrier_hits[i]})
			continue
		# Conservar barreras para daño (Paso 2.3) en el array local del paso.
		last_barrier_hits[i] = Array(hit.get("barrier_hits", []))
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
				"tread_axis": _spin_axis,
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
				"query_bump_m": float(hit.get("query_bump_m", bump)),
				"query_travel_m": float(hit.get("query_travel_m", travel)),
				"elevated_m": float(hit.get("elevated_m", 0.0)),
				"axial": float(_cls["axial"]),
				"is_sidewall": _is_sidewall,
				"is_tread": _is_tread,
				"deep_recovery": _deep_recovery,
				"recovered_overlap": bool(hit.get("recovered_overlap", false)),
				"low_confidence": bool(hit.get("low_confidence", hit.get("recovered_overlap", false))),
				"barrier_hits": last_barrier_hits[i],
			}
		)

	last_contacts = contacts.duplicate(true)
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
	var target_count := 1
	if configured_substeps_per_tick > 0:
		target_count = configured_substeps_per_tick
	elif configured_substep_hz > 0:
		var base_hz := maxi(1, Engine.physics_ticks_per_second)
		target_count = maxi(1, roundi(float(configured_substep_hz) / float(base_hz)))
	else:
		target_count = maxi(1, ceili((dt - 1.0e-5) / maximum_substep_seconds))

	var count := target_count
	var h := dt / float(count)
	# Rig 1DOF: reconcilia u, ancla contactos y prepara coeficientes del tick.
	unsprung_rig.begin_tick(state, suspension_model, contacts, wheel_radii, domains, thermal_model)

	var tire_thermal_states: Array[Dictionary] = []
	var thermal_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_cambers: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_slip_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_surfaces: Array[String] = ["Gravel", "Gravel", "Gravel", "Gravel"]
	var thermal_vx: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_fy: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_water: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var background_water: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_snow: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_ice: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_snow_cov: Array[float] = [-1.0, -1.0, -1.0, -1.0]
	var thermal_ice_cov: Array[float] = [-1.0, -1.0, -1.0, -1.0]
	var thermal_loose_gravel_cov: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_mud_factor: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var thermal_ground: Array[float] = [30.0, 30.0, 30.0, 30.0]
	var thermal_air: Array[float] = [25.0, 25.0, 25.0, 25.0]
	var thermal_irradiance: Array[float] = [0.0, 0.0, 0.0, 0.0]

	var has_puddles: bool = is_instance_valid(puddle_system)
	var has_rivers: bool = is_instance_valid(river_system)
	var has_winter_patches: bool = has_puddles and bool(puddle_system.get("has_winter_patches"))
	var use_puddle_batch: bool = has_puddles and puddle_system.has_method(&"sample_4wheels")
	var use_river_batch: bool = has_rivers and river_system.has_method(&"sample_4wheels")
	var puddle_batch := PackedFloat32Array()
	var river_batch := PackedFloat32Array()
	if use_puddle_batch or use_river_batch:
		if _water_wheel_positions.size() != 4:
			_water_wheel_positions.resize(4)
		var loaded_mask: int = 0
		for wi in 4:
			var cw: Dictionary = contacts[wi]
			if bool(cw.get("hit", false)):
				loaded_mask |= (1 << wi)
				_water_wheel_positions[wi] = cw.get("position", wheel_contact_points[wi]) as Vector3
			else:
				_water_wheel_positions[wi] = wheel_contact_points[wi]
		if loaded_mask != 0:
			if use_puddle_batch:
				puddle_batch = puddle_system.sample_4wheels(_water_wheel_positions, loaded_mask)
			if use_river_batch:
				river_batch = river_system.sample_4wheels(_water_wheel_positions, loaded_mask)

	for i in 4:
		var contact: Dictionary = contacts[i]
		var loaded_contact := bool(contact.get("hit", false))
		var contact_pos: Vector3 = contact.get("position", wheel_contact_points[i])
		var surface_str := str(contact.get("surface", "Unknown"))
		var local: Dictionary
		if (not has_puddles or use_puddle_batch) and (not has_rivers or use_river_batch):
			local = _local_conditions_base(surface_str, contact_pos, loaded_contact)
			var batch_has_p := loaded_contact and puddle_batch.size() >= (i + 1) * 2
			var batch_p_depth := puddle_batch[i * 2] if batch_has_p else 0.0
			var batch_p_drag := puddle_batch[i * 2 + 1] if batch_has_p else 0.0
			var batch_has_r := loaded_contact and river_batch.size() >= (i + 1) * 4
			var batch_r_depth := river_batch[i * 4] if batch_has_r else 0.0
			var batch_r_drag := river_batch[i * 4 + 2] if batch_has_r else 1.25
			var batch_r_ch_idx := int(river_batch[i * 4 + 3]) if batch_has_r else -1
			var batch_r_ch: String = str(river_system.channel_id_at(batch_r_ch_idx)) if (batch_has_r and batch_r_ch_idx >= 0 and river_system.has_method(&"channel_id_at")) else ""
			local = _apply_water_overlays_to_local(local, surface_str, batch_has_p, batch_p_depth, batch_p_drag, batch_has_r, batch_r_depth, batch_r_drag, batch_r_ch)
		else:
			local = _local_conditions_at_contact(surface_str, contact_pos, loaded_contact)
		if has_winter_patches and loaded_contact:
			var snow_patch: Vector2 = puddle_system.sample_snow_patch(contact_pos) if puddle_system.has_method(&"sample_snow_patch") else Vector2(puddle_system.sample_winter_patch(contact_pos).x, 1.0)
			if snow_patch.x > 0.001:
				local["snow_patch_depth_mm"] = snow_patch.x
				local["snow_patch_drag"] = snow_patch.y
				local["snow_mm"] = maxf(float(local.get("snow_mm", 0.0)), snow_patch.x)
				# Cap tire-compound snow_coverage modestly so snow patches retain grip while snow_contact_response delivers plowing drag & impact.
				local["snow_coverage"] = maxf(float(local.get("snow_coverage", 0.0)), minf(smoothstep(0.0, 3.5, snow_patch.x) * 0.25, 0.25))
				# Snow patches replace underlying loose gravel and mud so snow_contact_response never double-stacks with mud plowing.
				var patch_snow_keep := 1.0 - smoothstep(0.05, 0.80, snow_patch.x)
				local["loose_gravel_coverage"] = float(local.get("loose_gravel_coverage", 0.0)) * patch_snow_keep
				local["mud_factor"] = float(local.get("mud_factor", 0.0)) * patch_snow_keep
		var current_puddle_depth := float(local.get("puddle_depth_mm", 0.0))
		var depth_rate := maxf(current_puddle_depth - last_puddle_depths_mm[i], 0.0) / maxf(dt, 0.001)
		last_puddle_depths_mm[i] = current_puddle_depth
		local["puddle_depth_rate"] = depth_rate
		var current_snow_patch_depth := float(local.get("snow_patch_depth_mm", 0.0))
		var snow_patch_rate := maxf(current_snow_patch_depth - last_snow_patch_depths_mm[i], 0.0) / maxf(dt, 0.001)
		last_snow_patch_depths_mm[i] = current_snow_patch_depth
		local["snow_patch_depth_rate"] = snow_patch_rate
		thermal_water[i] = float(local.get("water_mm", 0.0))
		background_water[i] = float(local.get("background_water_mm", thermal_water[i]))
		thermal_snow[i] = float(local.get("snow_mm", 0.0))
		thermal_ice[i] = float(local.get("ice_mm", 0.0))
		thermal_snow_cov[i] = float(local.get("snow_coverage", -1.0))
		thermal_ice_cov[i] = float(local.get("ice_coverage", -1.0))
		thermal_loose_gravel_cov[i] = float(local.get("loose_gravel_coverage", 0.0))
		thermal_mud_factor[i] = float(local.get("mud_factor", 0.0))
		thermal_ground[i] = float(local.get("ground_c", 30.0))
		thermal_air[i] = float(local.get("air_c", thermal_model.ambient_temperature_c))
		thermal_irradiance[i] = float(local.get("irradiance_w_m2", 0.0))
		if loaded_contact:
			last_local_conditions[i] = local.duplicate(true)
		else:
			last_local_conditions[i] = {}
		thermal_model.advance_tire_pressure(i, dt)
		tire_thermal_states.append(thermal_model.get_tire_thermal_state_snapshot(i))

	var current_fuel_kg := thermal_model.fuel_remaining_litres * mass_model.fuel_density_kg_per_litre
	if fuel_slosh_enabled:
		var world_accel := (state.linear_velocity - _prev_chassis_vel_world) / maxf(dt, 0.0001) if _has_prev_chassis_vel else Vector3.ZERO
		_prev_chassis_vel_world = state.linear_velocity
		_has_prev_chassis_vel = true
		var inv_basis := state.transform.basis.transposed()
		var local_accel := inv_basis * world_accel
		var specific_local := inv_basis * (world_accel - state.total_gravity)
		var slosh_accel_local := Vector3(specific_local.x, local_accel.y, specific_local.z)
		mass_model.step_fuel_slosh(dt, slosh_accel_local, current_fuel_kg)

	var effective_load_impulses := Vector4.ZERO
	var acc_kin_jacking_imp := Vector4.ZERO
	var acc_geo_transfer_imp := Vector4.ZERO
	var acc_rc_heights := Vector4.ZERO
	_tire_thermal_elapsed += dt
	var effective_substep_hz := 1.0 / maxf(h, 0.0001)
	var pt_substeps := maxi(1, roundi(float(configured_powertrain_hz) / effective_substep_hz))
	var pt_stride := maxi(1, roundi(effective_substep_hz / maxf(float(configured_powertrain_hz), 1.0))) if float(configured_powertrain_hz) < effective_substep_hz else 1
	var h_pt := (h / float(pt_substeps)) if pt_substeps > 1 else (h * float(pt_stride))
	var tire_stride := maxi(1, roundi(effective_substep_hz / maxf(float(configured_tangential_tire_hz), 1.0)))
	var dt_tire := h * float(tire_stride)
	for _substep_index in count:
		var run_tangential_step := (_substep_index % tire_stride) == 0
		var pred_V: Vector3 = unsprung_rig.V_pred
		var pred_R: Basis = unsprung_rig.R_pred
		var pred_C: Vector3 = unsprung_rig.C_pred
		var pred_up: Vector3 = (pred_R * Vector3.UP).normalized()
		var pred_right_chassis: Vector3 = pred_R.x.normalized()
		var pred_fwd_chassis: Vector3 = (-pred_R.z).normalized()
		var F_body := Vector3.ZERO
		var T_body := Vector3.ZERO
		if fuel_slosh_enabled:
			var slosh_reaction := mass_model.fuel_slosh_forces_world(
				pred_R,
				body.center_of_mass,
				state.total_gravity,
				current_fuel_kg,
			)
			F_body += slosh_reaction["force"] as Vector3
			T_body += slosh_reaction["torque"] as Vector3
		if powertrain_model.chassis_reaction_enabled and powertrain_model.chassis_reaction_torque_local_nm.length_squared() > 0.0:
			T_body += pred_R * powertrain_model.chassis_reaction_torque_local_nm
		if pred_V.length_squared() > 0.01:
			var spd := pred_V.length()
			var drag_mag := aero_model.drag_force(spd) + thermal_model.cooling_drag_force_n
			F_body += -pred_V.normalized() * drag_mag
			for wing_effect in aero_model.wing_forces(pred_V, pred_R):
				var Fw: Vector3 = wing_effect.force
				var local_pos: Vector3 = wing_effect.position
				var world_off: Vector3 = pred_R * local_pos
				var com_off: Vector3 = pred_R * body.center_of_mass
				F_body += Fw
				T_body += (world_off - com_off).cross(Fw)
		unsprung_rig.step_substep_normal(h, suspension_model, F_body, T_body)
		if steering_rack_enabled:
			_step_steering_rack_1dof(h, float(inputs.get("steering", 0.0)), _last_front_road_torque_nm)
		var tire_reactions := _substep_tire_reactions
		var spin_damping := _substep_spin_damping
		var J_tang_hub := _substep_j_tang_hub
		var substep_lat_n := _substep_lat_n
		var substep_lon_n := _substep_lon_n
		var substep_cg_h := _substep_cg_h
		tire_reactions.fill(0.0)
		spin_damping.fill(0.0)
		J_tang_hub.fill(0.0)
		substep_lat_n.fill(0.0)
		substep_lon_n.fill(0.0)
		substep_cg_h.fill(0.5)
		var front_road_torque_nm := 0.0
		var F_patch := Vector3.ZERO
		var T_patch := Vector3.ZERO
		for i in 4:
			var contact: Dictionary = contacts[i]
			tire_model.states[i].radial_deflection_m = unsprung_rig.s_defl[i]
			tire_model.states[i]["recovery_low_confidence"] = bool(contact.get("low_confidence", contact.get("recovered_overlap", false)))
			var normal_load := maxf(float(unsprung_rig.s_Fz[i]), 0.0)
			if bool(contact.get("low_confidence", contact.get("recovered_overlap", false))):
				var _ref := 3000.0
				if i < tire_model.static_wheel_load_n.size():
					_ref = maxf(float(tire_model.static_wheel_load_n[i]), 100.0)
				normal_load = minf(normal_load, _ref * RECOVERY_FZ_CAP_MULT)
			effective_load_impulses[i] += normal_load * h
			if not bool(contact.get("hit", false)) or normal_load <= 0.0:
				_substep_cached_valid[i] = false
				_substep_cached_fz_n[i] = 0.0
				_substep_cached_load_scale[i] = 0.0
				if carcass_windup_enabled:
					tire_reactions[i] = _step_carcass_windup_1dof(i, h, 0.0)
				else:
					tire_belt_spins[i] = wheel_spins[i]
				if run_tangential_step:
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
						dt_tire,
						float(free_thermal_state.get("carcass_c", 25.0)),
					)
					wheel_slips[i] = Vector2(
						float(free_result.get("slip_ratio", 0.0)),
						float(free_result.get("slip_angle_rad", 0.0)),
					)
				tire_powers[i] = 0.0
				thermal_speeds[i] = pred_V.length()
				thermal_slip_speeds[i] = 0.0
				thermal_surfaces[i] = "Gravel"
				thermal_vx[i] = 0.0
				thermal_fy[i] = 0.0
				continue
			var normal: Vector3 = contact["normal"]
			var point := unsprung_rig.contact_patch_position(i, contact["position"])
			var r_patch := point - pred_C
			var thermal_state := tire_thermal_states[i]
			var eval_wheel_full := run_tangential_step or (not _substep_cached_valid[i]) or _substep_cached_fz_n[i] <= 1.0
			if not eval_wheel_full:
				var load_scale := clampf(normal_load / _substep_cached_fz_n[i], 0.0, 2.0)
				_substep_cached_load_scale[i] = load_scale
				var tire_force := _substep_cached_tire_force[i] * load_scale
				var sat_torque := _substep_cached_sat_torque[i] * load_scale
				if i < 2:
					front_road_torque_nm += _substep_cached_mz_nm[i] * load_scale
				var spin := wheel_spins[i]
				var phase := wheel_rotation_angles[i] + spin * h * 0.5
				var vibration := float(thermal_state.rim_deformation) * minf(spin * spin * 0.025, normal_load * 0.12) * sin(phase)
				var vib := normal * vibration
				F_patch += tire_force + vib
				T_patch += r_patch.cross(tire_force + vib) + sat_torque
				J_tang_hub[i] = (tire_force + vib).dot(unsprung_rig.tick_e_wheel[i]) * h
				substep_lat_n[i] = _substep_cached_lat_n[i] * load_scale
				substep_lon_n[i] = _substep_cached_lon_n[i] * load_scale
				substep_cg_h[i] = clampf(-r_patch.dot(pred_up), 0.15, 1.5)
				tire_powers[i] = _substep_cached_tire_power[i] * load_scale
				spin_damping[i] = _substep_cached_spin_damp[i] * load_scale
				var raw_tire_torque := _substep_cached_raw_tire_torque[i] * load_scale
				if carcass_windup_enabled:
					tire_reactions[i] = _step_carcass_windup_1dof(i, h, raw_tire_torque)
				else:
					tire_reactions[i] = raw_tire_torque
					tire_belt_spins[i] = wheel_spins[i]
				continue
			var road_velocity := Vector3.ZERO
			var collider: Object = contact.get("collider")
			if collider is RigidBody3D:
				var road_body := collider as RigidBody3D
				road_velocity = road_body.linear_velocity + road_body.angular_velocity.cross(
					point - road_body.to_global(road_body.center_of_mass)
				)
			var point_velocity := unsprung_rig.V_pred + unsprung_rig.omega_pred.cross(r_patch) - road_velocity
			var steer_angle := _wheel_steer_angle(i, float(inputs.get("steering", 0.0)))
			var toe := _effective_toe(i)
			var camber := suspension_model.dynamic_camber(i)
			var wheel_camber := suspension_model.dynamic_wheel_camber(i)
			var heading := (-pred_R.z).rotated(pred_up, steer_angle + toe)
			var forward := (heading - normal * heading.dot(normal)).normalized()
			if forward.length_squared() < 0.5:
				forward = (-pred_R.z).normalized()
			var right := forward.cross(normal).normalized()
			var longitudinal_speed := point_velocity.dot(forward)
			var lateral_speed := point_velocity.dot(right)
			var local_water := background_water[i]
			var local_snow := thermal_snow[i]
			var local_ground := thermal_ground[i]
			var dt_eval := dt_tire if run_tangential_step else h
			tire_model.rotate_patch_frame(i, forward, right)
			var tire_result := _solve_contact_wheel(
				i,
				dt_eval,
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
				thermal_ice[i],
				thermal_snow_cov[i],
				thermal_ice_cov[i],
				thermal_loose_gravel_cov[i],
				thermal_mud_factor[i],
			)
			var fx := float(tire_result.get("longitudinal_force_n", 0.0))
			var fy := float(tire_result.get("lateral_force_n", 0.0))
			var mz := float(tire_result.get("aligning_torque_nm", 0.0))
			var flat_drag := -clampf(longitudinal_speed, -1.0, 1.0) * normal_load * 0.045 * float(thermal_state.pressure_loss_fraction)
			var puddle_depth_here: float = float(last_local_conditions[i].get("puddle_depth_mm", 0.0))
			var snow_patch_depth_here: float = float(last_local_conditions[i].get("snow_patch_depth_mm", 0.0))
			var mud_factor_here: float = thermal_mud_factor[i] if str(contact["surface"]) in ["Gravel", "Dirt"] else 0.0
			var mud_drag_n := 0.0
			var eff_sup_x: float = 1.0
			var eff_sup_y: float = 1.0
			var drag_n: float = 0.0
			var steering_pull_mag: float = 0.0
			var hydro_wheel_torque_mag: float = 0.0
			if puddle_depth_here > 0.001 or snow_patch_depth_here > 0.001 or mud_factor_here > 0.0:
				var point_surf_speed: float = point_velocity.slide(normal).length()
				if point_surf_speed > 0.001:
					if puddle_depth_here > 0.001:
						var pres: PackedFloat32Array = PuddleModel.contact_response_packed(
							puddle_depth_here,
							point_surf_speed,
							float(tire_model.wheel_compounds[i].get("water_evacuation_reference_speed_m_s", 16.0)),
							normal_load,
							wheel_widths[i],
							float(last_local_conditions[i].get("puddle_drag", 0.0)),
							float(last_local_conditions[i].get("puddle_depth_rate", 0.0)),
							wheel_radii[i]
						)
						var wf_bg := maxf(float(tire_model.states[i]["compound_water_factor"]), 0.05)
						eff_sup_x = minf(wf_bg, pres[1]) / wf_bg
						eff_sup_y = minf(wf_bg, pres[2]) / wf_bg
						drag_n = pres[3]
						hydro_wheel_torque_mag = pres[6]
						steering_pull_mag = pres[7]
					if snow_patch_depth_here > 0.001:
						var sres: PackedFloat32Array = PuddleModel.snow_contact_response_packed(
							snow_patch_depth_here,
							point_surf_speed,
							normal_load,
							wheel_widths[i],
							float(last_local_conditions[i].get("snow_patch_drag", 1.0)),
							float(last_local_conditions[i].get("snow_patch_depth_rate", 0.0)),
							wheel_radii[i]
						)
						eff_sup_x *= sres[1]
						eff_sup_y *= sres[2]
						drag_n += sres[3]
						hydro_wheel_torque_mag += sres[6]
						steering_pull_mag += sres[7]
					if mud_factor_here > 0.0:
						mud_drag_n = mud_plowing_force_n(mud_factor_here, normal_load, point_surf_speed)
						drag_n += mud_drag_n
						hydro_wheel_torque_mag += mud_drag_n * 0.82 * wheel_radii[i]
						steering_pull_mag += mud_drag_n * 0.055
			last_local_conditions[i]["puddle_support"] = minf(eff_sup_x, eff_sup_y)
			last_local_conditions[i]["puddle_drag_n"] = drag_n
			last_local_conditions[i]["mud_drag_n"] = mud_drag_n
			fx *= eff_sup_x
			fy *= eff_sup_y
			mz *= eff_sup_y
			if i < 2:
				var puddle_pull := 0.0
				if drag_n > 0.0:
					var steer_sign := -1.0 if i == 0 else 1.0
					puddle_pull = steering_pull_mag * steer_sign
					mz += puddle_pull
				front_road_torque_nm += mz
			var tire_force := forward * (fx + flat_drag) + right * fy
			tire_force -= point_velocity.slide(normal).normalized() * drag_n
			var sat_torque := normal * mz
			var vib := Vector3.ZERO
			if normal_load > 0.0:
				var spin := wheel_spins[i]
				var phase := wheel_rotation_angles[i] + spin * h * 0.5
				var vibration := float(thermal_state.rim_deformation) * minf(spin * spin * 0.025, normal_load * 0.12) * sin(phase)
				vib = normal * vibration
				F_patch += tire_force + vib
				T_patch += r_patch.cross(tire_force + vib) + sat_torque
				J_tang_hub[i] = (tire_force + vib).dot(unsprung_rig.tick_e_wheel[i]) * h
				substep_lat_n[i] = tire_force.dot(pred_right_chassis)
				substep_lon_n[i] = tire_force.dot(pred_fwd_chassis)
				substep_cg_h[i] = clampf(-r_patch.dot(pred_up), 0.15, 1.5)
			wheel_slips[i] = Vector2(
				float(tire_result.get("slip_ratio", 0.0)),
				float(tire_result.get("slip_angle_rad", 0.0)),
			)
			tire_powers[i] = float(tire_result.get("friction_power_w", 0.0)) * eff_sup_x
			var eff_radius: float = float(tire_result.get("effective_radius_m", wheel_radii[i]))
			var hydro_wheel_torque: float = hydro_wheel_torque_mag * signf(longitudinal_speed)
			var raw_tire_torque := (fx + float(tire_result.get("rolling_force_n", 0.0))) * eff_radius + hydro_wheel_torque
			# Amortiguamiento implícito de spin compatible con el estado brush (patch_pos.x):
			# dT/domega en un subpaso h es h * k_x * R_eff^2 * (1 - util)^2, sin falsear la inercia
			# del tren motriz ni ahogar el slip_ratio al acelerar.
			var util := clampf(float(tire_model.states[i].get("combined_utilization", 0.0)), 0.0, 1.0)
			var relax_m := maxf(float(tire_model.states[i].get("relaxation_length_m", 0.25)), 0.05)
			var k_patch_x := (normal_load / relax_m) * (1.0 - util) * (1.0 - util)
			var c_spin_i := h * k_patch_x * eff_radius * eff_radius
			spin_damping[i] = c_spin_i
			_substep_cached_valid[i] = true
			_substep_cached_fz_n[i] = normal_load
			_substep_cached_tire_force[i] = tire_force
			_substep_cached_sat_torque[i] = sat_torque
			_substep_cached_mz_nm[i] = mz
			_substep_cached_raw_tire_torque[i] = raw_tire_torque
			_substep_cached_spin_damp[i] = c_spin_i
			_substep_cached_tire_power[i] = tire_powers[i]
			_substep_cached_lat_n[i] = substep_lat_n[i]
			_substep_cached_lon_n[i] = substep_lon_n[i]
			_substep_cached_load_scale[i] = 1.0
			if carcass_windup_enabled:
				tire_reactions[i] = _step_carcass_windup_1dof(i, h, raw_tire_torque)
			else:
				tire_reactions[i] = raw_tire_torque
				tire_belt_spins[i] = wheel_spins[i]
			thermal_speeds[i] = point_velocity.length()
			thermal_cambers[i] = wheel_camber
			thermal_slip_speeds[i] = (tire_belt_spins[i] if carcass_windup_enabled else wheel_spins[i]) * eff_radius - longitudinal_speed
			thermal_surfaces[i] = str(contact["surface"])
			thermal_vx[i] = longitudinal_speed
			thermal_fy[i] = fy
		_last_front_road_torque_nm = front_road_torque_nm
		if instant_center_kinematics_enabled:
			if run_tangential_step:
				suspension_model.evaluate_instant_center_jacking(
					substep_lat_n,
					substep_lon_n,
					unsprung_rig.q,
					wheel_positions_local,
					substep_cg_h,
				)
			var ic_hub := suspension_model.ic_hub_forces_n
			var ic_geo := suspension_model.ic_geo_transfer_n
			var ic_rc := suspension_model.ic_rc_heights_m
			for i in 4:
				var ic_scale := 1.0 if run_tangential_step else _substep_cached_load_scale[i]
				var q_kin := ic_hub[i] * ic_scale
				J_tang_hub[i] += q_kin * h
				acc_kin_jacking_imp[i] += q_kin * h
				acc_geo_transfer_imp[i] += ic_geo[i] * ic_scale * h
				acc_rc_heights[i] += ic_rc[i] * h
		if elastokinematics_enabled:
			if run_tangential_step:
				suspension_model.step_elastokinematics(dt_tire, substep_lat_n, substep_lon_n)
		else:
			suspension_model.clear_compliance_state()
		unsprung_rig.step_substep_tangential_and_end(
			h,
			F_patch * h,
			T_patch * h,
			J_tang_hub[0],
			J_tang_hub[1],
			J_tang_hub[2],
			J_tang_hub[3],
		)
		var brake_work: Array = [0.0, 0.0, 0.0, 0.0]
		if pt_substeps > 1 or pt_stride <= 1:
			var inv_pt_sub := 1.0 / float(pt_substeps)
			var pt_spin_damping: Array[float] = [
				spin_damping[0] * inv_pt_sub,
				spin_damping[1] * inv_pt_sub,
				spin_damping[2] * inv_pt_sub,
				spin_damping[3] * inv_pt_sub,
			]
			var chassis_omega_local := unsprung_rig.R_pred.transposed() * unsprung_rig.omega_pred
			for _pt_i in pt_substeps:
				_prepare_powertrain(h_pt, inputs)
				var rotation := powertrain_model.solve_rotation(
					h_pt,
					wheel_spins,
					mass_model.wheel_spin_inertia,
					tire_reactions,
					brake_torques,
					pt_spin_damping,
					chassis_omega_local,
				)
				var engine_overrev_dmg := float(rotation.get("engine_overrev_damage", 0.0))
				if engine_overrev_dmg > 0.0:
					thermal_model.apply_damage(0.0, engine_overrev_dmg)
				_engine_thermal_peak_rpm = maxf(_engine_thermal_peak_rpm, powertrain_model.engine_rpm)
				var step_bw: Array = rotation.brake_work_j
				for i in 4:
					brake_work[i] = float(brake_work[i]) + float(step_bw[i])
		else:
			for i in 4:
				_powertrain_tire_acc[i] += tire_reactions[i]
				_powertrain_brake_acc[i] += brake_torques[i]
				_powertrain_spin_damp_acc[i] += spin_damping[i]
			_powertrain_step_samples += 1
			if _powertrain_step_samples >= pt_stride:
				var inv_pt_samples := 1.0 / float(_powertrain_step_samples)
				var pt_tire_reactions: Array[float] = [
					_powertrain_tire_acc[0] * inv_pt_samples,
					_powertrain_tire_acc[1] * inv_pt_samples,
					_powertrain_tire_acc[2] * inv_pt_samples,
					_powertrain_tire_acc[3] * inv_pt_samples,
				]
				var pt_brake_torques: Array[float] = [
					_powertrain_brake_acc[0] * inv_pt_samples,
					_powertrain_brake_acc[1] * inv_pt_samples,
					_powertrain_brake_acc[2] * inv_pt_samples,
					_powertrain_brake_acc[3] * inv_pt_samples,
				]
				var pt_spin_damping: Array[float] = [
					_powertrain_spin_damp_acc[0],
					_powertrain_spin_damp_acc[1],
					_powertrain_spin_damp_acc[2],
					_powertrain_spin_damp_acc[3],
				]
				_powertrain_tire_acc.fill(0.0)
				_powertrain_brake_acc.fill(0.0)
				_powertrain_spin_damp_acc.fill(0.0)
				_powertrain_step_samples = 0
				_prepare_powertrain(h_pt, inputs)
				var chassis_omega_local := unsprung_rig.R_pred.transposed() * unsprung_rig.omega_pred
				var rotation := powertrain_model.solve_rotation(
					h_pt,
					wheel_spins,
					mass_model.wheel_spin_inertia,
					pt_tire_reactions,
					pt_brake_torques,
					pt_spin_damping,
					chassis_omega_local,
				)
				var engine_overrev_dmg := float(rotation.get("engine_overrev_damage", 0.0))
				if engine_overrev_dmg > 0.0:
					thermal_model.apply_damage(0.0, engine_overrev_dmg)
				_engine_thermal_peak_rpm = maxf(_engine_thermal_peak_rpm, powertrain_model.engine_rpm)
				brake_work = rotation.brake_work_j
		for i in 4:
			wheel_rotation_angles[i] = fposmod(wheel_rotation_angles[i] + wheel_spins[i] * h, TAU)
			var radial_power := unsprung_rig.s_diss[i] if float(unsprung_rig.s_Fz[i]) > 0.0 else 0.0
			_wheel_thermal_work[i] += Vector3(tire_powers[i] * h, float(brake_work[i]), radial_power * h)
	var normal_loads := unsprung_rig.end_tick(state, dt, suspension_model)
	for i in 4:
		wheel_loads[i] = effective_load_impulses[i] / dt
		last_kinematic_jacking_forces_n[i] = acc_kin_jacking_imp[i] / dt
		last_geometric_load_transfer_n[i] = acc_geo_transfer_imp[i] / dt
		last_roll_center_heights_m[i] = acc_rc_heights[i] / dt
	if dirt_accumulating:
		var horizontal_speed := Vector2(state.linear_velocity.x, state.linear_velocity.z).length()
		dirt.step(dt, horizontal_speed, wheel_surfaces, last_local_conditions, wheel_loads, tire_model.static_wheel_load_n, wheel_slips)
		sync_dirt_factors()
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
	var rpm := powertrain_model.engine_rpm
	var torque := powertrain_model.engine_torque_nm
	_engine_thermal_elapsed += dt
	_engine_thermal_inputs += Vector4(rpm, torque, velocity.length(), aero_model.air_density_kg_m3) * dt
	if _engine_thermal_elapsed + 1.0e-6 >= ENGINE_THERMAL_PERIOD:
		var average := _engine_thermal_inputs / _engine_thermal_elapsed
		thermal_model.advance_engine(
			_engine_thermal_elapsed,
			average.x,
			average.y,
			average.z,
			average.w,
			_ambient_irradiance_w_m2,
			powertrain_model.torque_curve_reference_rpm,
			_engine_thermal_peak_rpm,
		)
		_engine_thermal_elapsed = 0.0
		_engine_thermal_inputs = Vector4.ZERO
		_engine_thermal_peak_rpm = 0.0

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
				"background_water_mm": float(last_local_conditions[index].get("background_water_mm", 0.0)),
				"puddle_support": float(last_local_conditions[index].get("puddle_support", 1.0)),
				"puddle_drag_n": float(last_local_conditions[index].get("puddle_drag_n", 0.0)),
				"loose_gravel_coverage": float(last_local_conditions[index].get("loose_gravel_coverage", 0.0)),
				"mud_factor": float(last_local_conditions[index].get("mud_factor", 0.0)),
				"mud_drag_n": float(last_local_conditions[index].get("mud_drag_n", 0.0)),
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
				"kinematic_jacking_n": last_kinematic_jacking_forces_n[index],
				"geometric_load_transfer_n": last_geometric_load_transfer_n[index],
				"roll_center_height_m": last_roll_center_heights_m[index],
				"compliance_toe_rad": suspension_model.compliance_toe_rad[index],
				"compliance_camber_rad": suspension_model.compliance_camber_rad[index],
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
		"rpm_design_max": powertrain_model.torque_curve_reference_rpm,
		"rpm_idle": powertrain_model.idle_rpm,
		"gear": powertrain_model.current_gear,
		"missgear": powertrain_model.missgear_active,
		"missgear_intensity": powertrain_model.missgear_intensity,
		"missgear_event": powertrain_model.consume_missgear_event(),
		"torque_nm": powertrain_model.engine_torque_nm,
		"manifold_fill": powertrain_model.manifold_fill,
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
		"clutch_bite": powertrain_model.clutch_bite,
		"clutch_slip_rad_s": powertrain_model.clutch_slip_rad_s,
		"clutch_torque_nm": powertrain_model.clutch_torque_nm,
		"clutch_slip_power_w": powertrain_model.clutch_slip_power_w,
		"clutch_damper_twist_deg": powertrain_model.clutch_damper_twist_deg,
		"clutch_damper_torque_nm": powertrain_model.clutch_damper_torque_nm,
		"clutch_damper_at_stop": powertrain_model.clutch_damper_at_stop,
		"input_shaft_rad_s": powertrain_model.input_shaft_omega_rad_s,
		"driveline": {
			"enabled": powertrain_model.driveline_compliance_enabled,
			"twist_rad": powertrain_model.driveline_twist_rad,
			"torque_nm": powertrain_model.driveline_torque_nm,
			"energy_j": powertrain_model.driveline_energy_j,
			"dissipation_w": powertrain_model.driveline_dissipation_w,
			"output_rad_s": powertrain_model.output_shaft_omega_rad_s,
			"backlash_rad": powertrain_model.driveline_backlash_rad,
			"in_backlash": powertrain_model.driveline_in_backlash,
			"backlash_flank": powertrain_model.driveline_backlash_flank,
			"backlash_impact_rad_s": powertrain_model.driveline_backlash_impact_rad_s,
			"chassis_reaction_enabled": powertrain_model.chassis_reaction_enabled,
			"chassis_reaction_torque_local_nm": powertrain_model.chassis_reaction_torque_local_nm,
			"engine_roll_deg": powertrain_model.engine_roll_deg,
			"engine_pitch_deg": powertrain_model.engine_pitch_deg,
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
			"dirt_cooler": thermal_model.dirt_cooler,
			"dirt_brakes": thermal_model.dirt_brakes.duplicate(),
			"engine": thermal_model.engine_damage,
			"transmission": powertrain_model.transmission_damage,
			"overheat_exposure_s": thermal_model.overheat_exposure_s,
			"high_rpm_exposure_s": thermal_model.high_rpm_exposure_s,
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
			"preset_id": powertrain_model.differential_preset_id,
			"profile_id": active_differential_profile(),
			"type": powertrain_model.differential_type,
			"diff_speed_rad_s": powertrain_model.last_diff_speed_rad_s,
			"lsd_capacity_nm": powertrain_model.last_lsd_capacity_nm,
			"lsd_torque_nm": powertrain_model.last_lsd_torque_nm,
			"lsd_saturation": powertrain_model.last_lsd_saturation,
			"lsd_filtered_torque_nm": powertrain_model.last_lsd_filtered_torque_nm,
			"lsd_blend": powertrain_model.last_lsd_blend,
			"lsd_lock_twist_rad": powertrain_model.last_lsd_lock_twist_rad,
			"front_type": powertrain_model.front_differential_type,
			"front_diff_speed_rad_s": powertrain_model.last_front_diff_speed_rad_s,
			"front_lsd_capacity_nm": powertrain_model.last_front_lsd_capacity_nm,
			"front_lsd_torque_nm": powertrain_model.last_front_lsd_torque_nm,
			"front_lsd_saturation": powertrain_model.last_front_lsd_saturation,
			"front_lsd_filtered_torque_nm": powertrain_model.last_front_lsd_filtered_torque_nm,
			"front_lsd_blend": powertrain_model.last_front_lsd_blend,
			"front_lsd_lock_twist_rad": powertrain_model.last_front_lsd_lock_twist_rad,
			"rear_type": powertrain_model.rear_differential_type,
			"rear_diff_speed_rad_s": powertrain_model.last_rear_diff_speed_rad_s,
			"rear_lsd_capacity_nm": powertrain_model.last_rear_lsd_capacity_nm,
			"rear_lsd_torque_nm": powertrain_model.last_rear_lsd_torque_nm,
			"rear_lsd_saturation": powertrain_model.last_rear_lsd_saturation,
			"rear_lsd_filtered_torque_nm": powertrain_model.last_rear_lsd_filtered_torque_nm,
			"rear_lsd_blend": powertrain_model.last_rear_lsd_blend,
			"rear_lsd_lock_twist_rad": powertrain_model.last_rear_lsd_lock_twist_rad,
		},
	}


static func mud_plowing_force_n(mud: float, load_n: float, speed_m_s: float) -> float:
	# Lateral mud berms exert strong plastic sinkage/suction resistance from low speeds
	# plus speed-dependent clay displacement so stepping into the mud noticeably brakes the car.
	var abs_speed := absf(speed_m_s)
	if mud <= 0.0 or load_n <= 0.0 or abs_speed <= 0.001:
		return 0.0
	var low_speed := smoothstep(0.0, 2.2, abs_speed)
	var speed_ratio := clampf(abs_speed / 16.0, 0.0, 1.35)
	var coeff := minf(0.26 * low_speed + 0.16 * speed_ratio + 0.24 * speed_ratio * speed_ratio, 0.74)
	return clampf(mud, 0.0, 1.0) * load_n * coeff


func sync_dirt_factors() -> void:
	thermal_model.dirt_cooler = dirt.level(0, 0.60) if dirt_radiator_enabled else 0.0
	for i in 4:
		thermal_model.dirt_brakes[i] = dirt.level(i + 1, 0.50)


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
		# Muestra escalar 1DOF: recorrido físico q (sin nodos).
		var hub_travel := suspension_model.compression[i]
		if i < unsprung_rig.q.size():
			hub_travel = unsprung_rig.q[i]
		pivot.position = wheel_positions_local[i] + Vector3.UP * hub_travel
		pivot.rotation.y = steer_angle + toe
		if i < wheel_visuals.size():
			# Spin first around local +X before tilting camber around +Z; YXZ Euler would precess the spindle.
			wheel_visuals[i].quaternion = Quaternion(Vector3.BACK, wheel_camber) * Quaternion(
				Vector3.RIGHT,
				wheel_rotation_angles[i],
			)


func _effective_toe(index: int) -> float:
	var config: Dictionary = domains.get("damage", {}).get("wheel_collision", {})
	var inward := -1.0 if index in [0, 2] else 1.0
	var damage_offset := deg_to_rad(float(config.get("maximum_toe_offset_deg", 0.0))) * alignment_collision_damage[index]
	return suspension_model.dynamic_toe(index) + inward * damage_offset


func _step_steering_rack_1dof(h: float, input_value: float, road_torque_nm: float) -> void:
	var dt_s := maxf(h, 0.00001)
	var shaped := signf(input_value) * pow(absf(input_value), maxf(steering_exponent, 0.1))
	var max_angle := maximum_steering_angle_rad * maxf(absf(front_steering_ratio), 0.01)
	var target_angle := shaped * maximum_steering_angle_rad * front_steering_ratio
	var k := maxf(steering_rack_stiffness_nm_per_rad, 1.0)
	var c := maxf(steering_rack_damping_nms_per_rad, 0.1)
	var inertia := maxf(steering_rack_inertia_kg_m2, 0.005)
	# Convención de signo: en Godot +steer_angle rota -Z hacia -X (izquierda, +Y),
	# donde fy < 0 y TireModel devuelve aligning_torque = -fy * trail > 0.
	# El par físico autoalineante alrededor de +Y es -road_torque_nm (empuja hacia 0
	# en giro y hacia el derrape en sobreviraje; charco en FL tira a +Y izquierda).
	var kingpin_torque_nm := -road_torque_nm
	var ext_torque := clampf(kingpin_torque_nm * steering_rack_torque_scale, -k * max_angle * 0.65, k * max_angle * 0.65)
	# Integración semi-implícita 1DOF: (I + h*c + h^2*k) * dv = h * (k*(target - q) - c*v + ext_torque)
	var denom := inertia + dt_s * c + dt_s * dt_s * k
	var accel := (k * (target_angle - steering_rack_angle_rad) - c * steering_rack_vel_rad_s + ext_torque) / denom
	steering_rack_vel_rad_s += accel * dt_s
	steering_rack_angle_rad += steering_rack_vel_rad_s * dt_s
	if steering_rack_angle_rad > max_angle:
		steering_rack_angle_rad = max_angle
		steering_rack_vel_rad_s = minf(steering_rack_vel_rad_s, 0.0)
	elif steering_rack_angle_rad < -max_angle:
		steering_rack_angle_rad = -max_angle
		steering_rack_vel_rad_s = maxf(steering_rack_vel_rad_s, 0.0)
	steering_ffb_torque_nm = kingpin_torque_nm


func _step_carcass_windup_1dof(index: int, h: float, tire_torque_nm: float) -> float:
	var dt_s := maxf(h, 0.00001)
	var wheel_i := maxf(float(mass_model.wheel_spin_inertia[index]) if index < mass_model.wheel_spin_inertia.size() else 0.8, 0.05)
	var belt_i := maxf(wheel_i * clampf(carcass_belt_inertia_fraction, 0.1, 0.6), 0.02)
	var k_t := maxf(carcass_torsional_stiffness_nm_per_rad, 100.0)
	var c_t := 2.0 * sqrt(k_t * belt_i) * clampf(carcass_torsional_damping_ratio, 0.05, 1.5)
	var rim_spin := wheel_spins[index]
	var belt_spin := tire_belt_spins[index]
	var twist := tire_windup_rad[index]
	# Par de carcasa desde llanta hacia banda: T_carcass = k*(theta_rim - theta_belt) + c*(omega_rim - omega_belt)
	# Sin c_spin en el denominador para no frenar artificialmente la banda respecto al suelo.
	var rel_spin := rim_spin - belt_spin
	var denom := belt_i + dt_s * c_t + dt_s * dt_s * k_t
	var net_belt_torque := k_t * twist + c_t * rel_spin - tire_torque_nm
	var d_belt_spin := (dt_s * net_belt_torque) / maxf(denom, 1.0e-6)
	belt_spin += d_belt_spin
	twist = clampf(twist + (rim_spin - belt_spin) * dt_s, -0.08, 0.08)
	tire_belt_spins[index] = belt_spin
	tire_windup_rad[index] = twist
	return k_t * twist + c_t * (rim_spin - belt_spin)


func _wheel_steer_angle(index: int, input_value: float) -> float:
	var shaped := signf(input_value) * pow(absf(input_value), maxf(steering_exponent, 0.1))
	var center_angle := steering_rack_angle_rad if (steering_rack_enabled and index < 2) else (shaped * maximum_steering_angle_rad * front_steering_ratio)
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
				"hub_travel_m": unsprung_rig.q[i] if i < unsprung_rig.q.size() else suspension_model.compression[i],
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
				"damper_clamped": false,
				"damper_clip_events": 0,
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
				"elevated_m": float(c.get("elevated_m", 0.0)),
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
				"roll_center_height_m": float(p.get("roll_center_height_m", 0.0)),
				"roll_center_height_gain": float(p.get("roll_center_height_gain", 0.0)),
				"anti_dive_ratio": float(p.get("anti_dive_ratio", 0.0)),
				"anti_squat_ratio": float(p.get("anti_squat_ratio", 0.0)),
				"anti_lift_ratio": float(p.get("anti_lift_ratio", 0.0)),
				"solid_axle": bool(p.get("solid_axle", false)),
				"compliance_steer_lat_rad_per_n": float(p.get("compliance_steer_lat_rad_per_n", 0.0)),
				"compliance_toe_lon_rad_per_n": float(p.get("compliance_toe_lon_rad_per_n", 0.0)),
				"compliance_camber_lat_rad_per_n": float(p.get("compliance_camber_lat_rad_per_n", 0.0)),
				"compliance_tau_s": float(p.get("compliance_tau_s", 0.022)),
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
	_powertrain_step_samples = 0
	_powertrain_tire_acc.fill(0.0)
	_powertrain_brake_acc.fill(0.0)
	_powertrain_spin_damp_acc.fill(0.0)
	_substep_cached_valid.fill(false)
	_substep_cached_fz_n.fill(0.0)
	_substep_cached_tire_force.fill(Vector3.ZERO)
	_substep_cached_sat_torque.fill(Vector3.ZERO)
	_substep_cached_mz_nm.fill(0.0)
	_substep_cached_raw_tire_torque.fill(0.0)
	_substep_cached_spin_damp.fill(0.0)
	_substep_cached_tire_power.fill(0.0)
	_substep_cached_lat_n.fill(0.0)
	_substep_cached_lon_n.fill(0.0)
	_substep_cached_load_scale.fill(1.0)
	if is_instance_valid(unsprung_rig.chassis):
		unsprung_rig.reset_at(unsprung_rig.chassis.global_transform, suspension_model)
	else:
		unsprung_rig.reset_at(Transform3D.IDENTITY, suspension_model)
	session_generation += 1
	simulation_time_s = 0.0
	published_state = { }
	wheel_spins.fill(0.0)
	tire_windup_rad.fill(0.0)
	tire_belt_spins.fill(0.0)
	steering_rack_angle_rad = 0.0
	steering_rack_vel_rad_s = 0.0
	steering_ffb_torque_nm = 0.0
	_last_front_road_torque_nm = 0.0
	_prev_chassis_vel_world = Vector3.ZERO
	_has_prev_chassis_vel = false
	mass_model.reset_fuel_slosh()
	wheel_slips.fill(Vector2.ZERO)
	wheel_loads.fill(0.0)
	last_kinematic_jacking_forces_n.fill(0.0)
	last_geometric_load_transfer_n.fill(0.0)
	last_roll_center_heights_m.fill(0.0)
	wheel_rotation_angles.fill(0.0)
	wheel_contact_points.fill(Vector3.ZERO)
	wheel_contact_normals.fill(Vector3.UP)
	wheel_surfaces.fill("Unknown")
	last_local_conditions = [{}, {}, {}, {}]
	last_puddle_depths_mm.fill(0.0)
	last_snow_patch_depths_mm.fill(0.0)
	last_contacts = [{}, {}, {}, {}]
	contact_query_count = 0
	brake_model.smoothed_service_input = 0.0
	brake_model.smoothed_handbrake_input = 0.0
	for i in 4:
		tire_model.reset_patch(i)
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
	ice_mm: float = 0.0,
	snow_coverage: float = -1.0,
	ice_coverage: float = -1.0,
	loose_gravel_coverage: float = 0.0,
	mud_factor: float = 0.0,
) -> Dictionary:
	return tire_model.evaluate(
		index,
		load_n,
		surface,
		vx,
		vy,
		tire_belt_spins[index] if carcass_windup_enabled else wheel_spins[index],
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
		ice_mm,
		snow_coverage,
		ice_coverage,
		loose_gravel_coverage,
		mud_factor,
	)
