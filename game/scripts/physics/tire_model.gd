class_name TireModel
extends RefCounted

const CONTACT_PATCH_LOAD_GAIN := 0.12
const CONTACT_PATCH_DEFLECTION_GAIN := 0.20
const FRONT_CAMBER_THRUST_GAIN := 0.13
const REAR_CAMBER_THRUST_GAIN := 0.18
# Low-speed anchored contact: full static hold at/below FULL, fully dynamic
# at/above FREE, smooth blend between. Transport-based so wheelspin and
# locked-wheel slides stay on the dynamic branch.
const STATIC_BLEND_FULL_M_S := 0.25
const STATIC_BLEND_FREE_M_S := 1.25
const STATIC_DAMPING_RATIO := 0.5
# Radio efectivo: acoplado a deflexión (0.92 = aplastamiento tread vs
# flanco). Coherente en velocidad de llanta y par. §4.5.
const EFFECTIVE_RADIUS_COMPRESSION_GAIN := 0.92
const EFFECTIVE_RADIUS_RIM_MARGIN_M := 0.01
# Envolvente tandem-cam simplificada: la carga normal se filtra con
# tau = patch / max(planar,1). Suaviza bordes (curbs) a longitud de huella.
const ENVELOPE_PATCH_TAU_MIN_S := 0.002
# Rampa de aterrizaje: el contact_blend sube con tau rápido al re-contactar
# para no patinar con patch cero + blend<1. Despegue usa tau del perfil.
const CONTACT_LANDING_TAU_S := 0.02

var axle_profiles: Array[Dictionary] = []
var surfaces: Dictionary = { }
var axle_surfaces: Array[Dictionary] = []
var surface_transition_tau_s: float = 0.0
var axle_surface_tau_s: Array[float] = []
var base_contact_patch_m: Array[float] = []
var base_relaxation_length_m: Array[float] = []
var static_deflection_ratio: Array[float] = []
var static_wheel_load_n: Array[float] = []
var maximum_tire_deflection_m: Array[float] = []
var reference_hot_pressure_kpa: Array[float] = []
var load_sensitivity_per_newton: float = 1.5e-5
var axle_load_sensitivity: Array[float] = []
var axle_load_mult: Array[float] = []
var rolling_resistance_coefficient: float = 0.015
var axle_rolling_coefficient: Array[float] = []
var pneumatic_trail_m: float = 0.035
var axle_pneumatic_trail: Array[float] = []
var axle_camber_gain: Array[float] = []
var axle_relaxation_scale: Array[float] = []
var axle_contact_load_gain: Array[float] = []
var axle_contact_deflection_gain: Array[float] = []
var pressure_relaxation_sensitivity: float = 0.0
var pressure_rolling_resistance_sensitivity: float = 0.0
var axle_pressure_relaxation: Array[float] = []
var axle_pressure_rolling: Array[float] = []
var optimal_carcass_temperature_c: float = 60.0
var axle_optimal_carcass_c: Array[float] = []
var radial_tires: Dictionary = { }
var states: Array[Dictionary] = []
var active_compound_id: String = "gravel_normal"
var active_compound: Dictionary = {}
var wheel_compounds: Array[Dictionary] = []
var compound_catalog: Dictionary = {}
var missing_surface_warnings: Dictionary = {}


func _ensure_four_compounds(cat: Dictionary, requested_id: String) -> Array[Dictionary]:
	# §closure-3: validar antes de mutar; al recuperar un catálogo vacío,
	# inicializar las ruedas faltantes con el compuesto activo y su ID; si
	# todavía no hay compuesto activo, usar como base el primer compuesto
	# válido solicitado; copiar por rueda y conservar selecciones existentes.
	var definitions: Dictionary = cat.get("compounds", {})
	var out: Array[Dictionary] = []
	var base_id := ""
	var base_def: Dictionary = {}
	if not active_compound.is_empty() and definitions.has(active_compound_id):
		base_id = active_compound_id
		base_def = (definitions[active_compound_id] as Dictionary).duplicate(true)
		base_def["id"] = base_id
	elif definitions.has(requested_id):
		base_id = requested_id
		base_def = (definitions[requested_id] as Dictionary).duplicate(true)
		base_def["id"] = base_id
	for i in 4:
		if i < wheel_compounds.size():
			var cur: Variant = wheel_compounds[i]
			if cur is Dictionary and not (cur as Dictionary).is_empty():
				var cur_id := str((cur as Dictionary).get("id", ""))
				if definitions.has(cur_id):
					var kept := (definitions[cur_id] as Dictionary).duplicate(true)
					kept["id"] = cur_id
					out.append(kept)
					continue
		out.append(base_def.duplicate(true))
	return out


func set_compound(compound_id: String, catalog: Dictionary = {}) -> bool:
	var cat: Dictionary = catalog if not catalog.is_empty() else compound_catalog
	if cat.is_empty():
		cat = RallyTireCompound.load_catalog()
	var definitions: Dictionary = cat.get("compounds", {})
	if not definitions.has(compound_id):
		push_warning("Unknown tire compound: " + compound_id)
		return false
	active_compound_id = compound_id
	compound_catalog = cat
	active_compound = (definitions[compound_id] as Dictionary).duplicate(true)
	wheel_compounds.clear()
	for i in 4:
		var selected := active_compound.duplicate(true)
		selected["id"] = compound_id
		wheel_compounds.append(selected)
	return true


func set_wheel_compound(index: int, compound_id: String) -> bool:
	if index < 0 or index >= 4:
		push_warning("Invalid wheel index: " + str(index))
		return false
	# Contrato catálogo vacío §4.6: mismo fallback que set_compound.
	var cat: Dictionary = compound_catalog if not compound_catalog.is_empty() else RallyTireCompound.load_catalog()
	var definitions: Dictionary = cat.get("compounds", {})
	if not definitions.has(compound_id):
		push_warning("Unknown wheel compound: " + compound_id)
		return false
	compound_catalog = cat
	wheel_compounds = _ensure_four_compounds(cat, compound_id)
	# Conservar selecciones existentes salvo la rueda solicitada.
	var selected: Dictionary = (definitions[compound_id] as Dictionary).duplicate(true)
	selected["id"] = compound_id
	wheel_compounds[index] = selected
	# Si no había compuesto activo (arranque sin catálogo), el solicitado
	# se convierte en base activa sin pisar las otras tres ruedas.
	if active_compound.is_empty() or not definitions.has(active_compound_id):
		active_compound_id = compound_id
		active_compound = (definitions[compound_id] as Dictionary).duplicate(true)
	return true


# Inversión de respaldo compartida §closure-2: misma rutina para la
# referencia estática y el fallback. Bisección monótona con presión y
# óptima resueltas, seating y tope. Satura en el límite admitido.
static func fallback_deflection_m(
	tires: Dictionary, axle: String, pressure_kpa: float, carcass_c: float,
	load_n: float, optimum_c: float, sidewall_m: float, max_gain: float = 1.5,
) -> float:
	var coeffs := TireRadialModel.prepare_coefficients(tires, axle, pressure_kpa, carcass_c, optimum_c)
	return TireRadialModel.invert_deflection_m(coeffs, load_n, maxf(sidewall_m, 0.03) * max_gain)


func compound_water_snow_ground_factor(water_mm: float, snow_mm: float, ground_c: float, index: int = -1, planar_speed_m_s: float = 0.0) -> Dictionary:
	var compound := wheel_compounds[index] if index >= 0 and index < wheel_compounds.size() else active_compound
	if compound.is_empty():
		return {"water": 1.0, "snow": 1.0, "ground": 1.0, "combined": 1.0}
	var w := clampf(water_mm, 0.0, 12.0)
	var s := clampf(snow_mm, 0.0, 8.0)
	var wf_static := maxf(1.0 - w * float(compound.get("water_grip_loss_per_mm", 0.12)), float(compound.get("water_grip_floor", 0.6)))
	var sf := maxf(1.0 - s * float(compound.get("snow_grip_loss_per_mm", 0.09)), float(compound.get("snow_grip_floor", 0.6)))
	# Película fina dependiente de velocidad §4.5: a baja velocidad el dibujo
	# evacua; a velocidad de referencia el 100% de la pérdida estática aplica.
	# Evita que parado en mojado pierda lo mismo que a 30 m/s (aquaplaning).
	var evac := maxf(float(compound.get("water_evacuation_reference_speed_m_s", 16.0)), 1.0)
	var speed_ratio := clampf(planar_speed_m_s / evac, 0.0, 1.0)
	var speed_gain := 0.35 + 0.65 * speed_ratio * speed_ratio
	var wf := 1.0 - (1.0 - wf_static) * speed_gain if w > 1.0e-9 else 1.0
	var gf := 1.0
	if ground_c < 5.0:
		gf = lerpf(0.92, 1.0, clampf((ground_c + 5.0) / 10.0, 0.0, 1.0))
	elif ground_c > 32.0:
		gf = lerpf(1.0, 0.96, clampf((ground_c - 32.0) / 12.0, 0.0, 1.0))
	return {"water": wf, "snow": sf, "ground": gf, "combined": clampf(wf * sf * gf, 0.35, 1.0)}


static func effective_radius_m(nominal_m: float, deflection_m: float, sidewall_m: float) -> float:
	var rim := maxf(nominal_m - maxf(sidewall_m, 0.03), 0.05)
	return maxf(nominal_m - maxf(deflection_m, 0.0) * EFFECTIVE_RADIUS_COMPRESSION_GAIN, rim + EFFECTIVE_RADIUS_RIM_MARGIN_M)


func configure(
	domains: Dictionary,
	resolved_filters: Dictionary,
	static_wheel_loads: Array,
) -> void:
	var tires: Dictionary = domains.get("tires", { }).get("tires", { })
	radial_tires = tires
	surfaces = (tires.get("surfaces", { }) as Dictionary).duplicate(true)
	surface_transition_tau_s = float(resolved_filters.get("surface_transition_tau_s", tires.get("surface_transition_tau_s", 0.0)))
	var front_tire: Dictionary = _axle_dict(tires, "front")
	var rear_tire: Dictionary = _axle_dict(tires, "rear")
	var axle_tires: Array[Dictionary] = [front_tire, front_tire, rear_tire, rear_tire]
	var tire_thermal: Dictionary = tires.get("thermal", { })
	var tire_pressure: Dictionary = tires.get("pressure", { })
	var hot_pressures: Dictionary = tire_pressure.get("reference_hot_kpa_gauge", { })
	var wheel_keys := ["FL", "FR", "RL", "RR"]
	# Per-axle scalar defaults: filter axle > tires axle > tires global > builtin.
	var front_filter_scalars: Dictionary = _filter_scalars(resolved_filters, "front")
	var rear_filter_scalars: Dictionary = _filter_scalars(resolved_filters, "rear")
	var axle_scalar_dicts: Array[Dictionary] = [
		front_tire, front_tire, rear_tire, rear_tire,
	]
	var filter_scalar_dicts: Array[Dictionary] = [
		front_filter_scalars, front_filter_scalars, rear_filter_scalars, rear_filter_scalars,
	]
	axle_surfaces.clear()
	axle_surface_tau_s.clear()
	axle_load_sensitivity.clear()
	axle_load_mult.clear()
	axle_rolling_coefficient.clear()
	axle_pneumatic_trail.clear()
	axle_camber_gain.clear()
	axle_relaxation_scale.clear()
	axle_contact_load_gain.clear()
	axle_contact_deflection_gain.clear()
	axle_pressure_relaxation.clear()
	axle_pressure_rolling.clear()
	axle_optimal_carcass_c.clear()
	var global_pressure_mechanics: Dictionary = tires.get("pressure_mechanics", {}) if tires.get("pressure_mechanics", {}) is Dictionary else {}
	for i in 4:
		var is_front := i < 2
		var axle_tire: Dictionary = axle_scalar_dicts[i]
		var filter_scalars: Dictionary = filter_scalar_dicts[i]
		var default_tau := surface_transition_tau_s
		var axle_tau := _resolve_scalar(
			axle_tire, tires, filter_scalars, "surface_transition_tau_s", default_tau, 0.0, 2.0
		)
		axle_surface_tau_s.append(axle_tau)
		var global_surfaces: Dictionary = surfaces
		var axle_override_raw: Variant = axle_tire.get("surfaces", {})
		var axle_override: Dictionary = (axle_override_raw as Dictionary) if axle_override_raw is Dictionary else {}
		var filter_override_raw: Variant = resolved_filters.get("front_surfaces" if is_front else "rear_surfaces", {})
		var filter_override: Dictionary = (filter_override_raw as Dictionary) if filter_override_raw is Dictionary else {}
		axle_surfaces.append(_resolve_axle_surfaces(global_surfaces, axle_override, filter_override, is_front))
		axle_load_sensitivity.append(_resolve_scalar(
			axle_tire, tires, filter_scalars, "load_sensitivity_per_newton", 1.5e-5, 0.0, 1.0e-3
		))
		axle_load_mult.append(_resolve_scalar(
			axle_tire, tires, filter_scalars, "load_sensitivity_axle_mult",
			2.85 if is_front else 2.15, 0.1, 8.0
		))
		axle_rolling_coefficient.append(_resolve_scalar(
			axle_tire, tires, filter_scalars, "rolling_resistance_coefficient", 0.015, 0.0, 0.2
		))
		axle_pneumatic_trail.append(_resolve_scalar(
			axle_tire, tires, filter_scalars, "pneumatic_trail_m", 0.035, 0.0, 0.2
		))
		axle_camber_gain.append(_resolve_scalar(
			axle_tire, tires, filter_scalars, "camber_thrust_gain",
			FRONT_CAMBER_THRUST_GAIN if is_front else REAR_CAMBER_THRUST_GAIN, 0.0, 1.0
		))
		axle_relaxation_scale.append(_resolve_scalar(
			axle_tire, tires, filter_scalars, "relaxation_length_scale",
			1.85 if is_front else 1.55, 0.2, 5.0
		))
		axle_contact_load_gain.append(_resolve_scalar(
			axle_tire, tires, filter_scalars, "contact_patch_load_gain",
			CONTACT_PATCH_LOAD_GAIN, 0.0, 1.0
		))
		axle_contact_deflection_gain.append(_resolve_scalar(
			axle_tire, tires, filter_scalars, "contact_patch_deflection_gain",
			CONTACT_PATCH_DEFLECTION_GAIN, 0.0, 1.0
		))
		var axle_pm_raw: Variant = axle_tire.get("pressure_mechanics", {})
		var axle_pm: Dictionary = (axle_pm_raw as Dictionary) if axle_pm_raw is Dictionary else {}
		var filter_pm_raw: Variant = resolved_filters.get("front_pressure_mechanics" if is_front else "rear_pressure_mechanics", {})
		var filter_pm: Dictionary = (filter_pm_raw as Dictionary) if filter_pm_raw is Dictionary else {}
		axle_pressure_relaxation.append(clampf(_resolve_pm_scalar(
			axle_pm, global_pressure_mechanics, filter_pm, "response_sensitivity", 0.0
		), -3.0, 3.0))
		axle_pressure_rolling.append(clampf(_resolve_pm_scalar(
			axle_pm, global_pressure_mechanics, filter_pm, "rolling_resistance_sensitivity", 0.0
		), -3.0, 3.0))
		var axle_thermal_raw: Variant = axle_tire.get("thermal", {})
		var axle_thermal: Dictionary = (axle_thermal_raw as Dictionary) if axle_thermal_raw is Dictionary else {}
		var filter_thermal_raw: Variant = resolved_filters.get("front_thermal" if is_front else "rear_thermal", {})
		var filter_thermal: Dictionary = (filter_thermal_raw as Dictionary) if filter_thermal_raw is Dictionary else {}
		var global_opt := float(tire_thermal.get("optimal_carcass_temperature_c", 60.0))
		var axle_opt := float(axle_thermal.get("optimal_carcass_temperature_c", global_opt))
		if filter_thermal.has("optimal_carcass_temperature_c"):
			axle_opt = float(filter_thermal.get("optimal_carcass_temperature_c", axle_opt))
		axle_optimal_carcass_c.append(axle_opt)
	# Keep legacy globals in sync with the front axle for debug/HUD readers.
	load_sensitivity_per_newton = float(axle_load_sensitivity[0]) if axle_load_sensitivity.size() == 4 else 1.5e-5
	rolling_resistance_coefficient = float(axle_rolling_coefficient[0]) if axle_rolling_coefficient.size() == 4 else 0.015
	pneumatic_trail_m = float(axle_pneumatic_trail[0]) if axle_pneumatic_trail.size() == 4 else 0.035
	pressure_relaxation_sensitivity = float(axle_pressure_relaxation[0]) if axle_pressure_relaxation.size() == 4 else 0.0
	pressure_rolling_resistance_sensitivity = float(axle_pressure_rolling[0]) if axle_pressure_rolling.size() == 4 else 0.0
	optimal_carcass_temperature_c = float(axle_optimal_carcass_c[0]) if axle_optimal_carcass_c.size() == 4 else 60.0
	base_contact_patch_m.clear()
	base_relaxation_length_m.clear()
	static_wheel_load_n.clear()
	static_deflection_ratio.clear()
	missing_surface_warnings.clear()
	maximum_tire_deflection_m.clear()
	reference_hot_pressure_kpa.clear()
	for i in 4:
		var axle_tire: Dictionary = axle_tires[i]
		var contact_patch := maxf(
			float(axle_tire.get("contact_patch", tires.get("contact_patch", 0.2))),
			0.03,
		)
		base_contact_patch_m.append(contact_patch)
		base_relaxation_length_m.append(contact_patch * float(axle_relaxation_scale[i]))
		static_wheel_load_n.append(
			maxf(float(static_wheel_loads[i]) if i < static_wheel_loads.size() else 0.0, 100.0)
		)
		maximum_tire_deflection_m.append(float(TireRadialModel.geometry(axle_tire).sidewall_m))
		reference_hot_pressure_kpa.append(
			maxf(float(hot_pressures.get(wheel_keys[i], 225.0)), 20.0)
		)
		var sidewall := maximum_tire_deflection_m[i]
		# §closure-2: misma rutina compartida que el fallback (bisección
		# monótona con presión caliente ref y óptima resuelta). Coeffs una
		# vez por solución, sin reevaluar diccionarios en el bucle.
		var ref_ratio := fallback_deflection_m(
			radial_tires, "front" if i < 2 else "rear",
			reference_hot_pressure_kpa[i], axle_optimal_carcass_c[i],
			static_wheel_load_n[i], axle_optimal_carcass_c[i], sidewall, 1.5,
		) / sidewall
		static_deflection_ratio.append(ref_ratio)

	axle_profiles = [
		resolved_filters.get("front", { }).duplicate(true),
		resolved_filters.get("front", { }).duplicate(true),
		resolved_filters.get("rear", { }).duplicate(true),
		resolved_filters.get("rear", { }).duplicate(true),
	]
	states.clear()
	for i in 4:
		states.append(
			{
				"patch_pos": Vector2.ZERO,
				"patch_forward": Vector3.ZERO,
				"patch_right": Vector3.ZERO,
				"patch_energy_j": 0.0,
				"brush_demand_n": 0.0,
				"effective_slip_angle": 0.0,
				"effective_slip_ratio": 0.0,
				"post_peak_decay_lat": 0.0,
				"post_peak_decay_lon": 0.0,
				"contact_blend": 0.0,
				"surface_initialized": false,
				"surface_friction": 0.0,
				"surface_stiffness": 0.0,
				"surface_rolling": 0.0,
				"slip_angle": 0.0,
				"slip_ratio": 0.0,
				"dynamic_contact_patch_m": base_contact_patch_m[i],
				"relaxation_length_m": base_relaxation_length_m[i],
				"estimated_carcass_deflection_m": 0.0,
				"enveloped_load_n": static_wheel_load_n[i],
				"envelope_valid": false,
				"effective_radius_m": 0.28,
				"energy_residue_w": 0.0,
				"combined_utilization": 0.0,
				"instant_combined_utilization": 0.0,
				"contact_power_w": 0.0,
				"rolling_power_w": 0.0,
				"elastic_before_j": 0.0,
				"plastic_loss_j": 0.0,
				"blend_loss_j": 0.0,
				"stiffness_loss_j": 0.0,
				"liftoff_discard_j": 0.0,
				"contact_work_j": 0.0,
				"heat_work_j": 0.0,
				"longitudinal_force": 0.0,
				"lateral_force": 0.0,
				"aligning_torque": 0.0,
				"friction_power": 0.0,
				"surface": "Unknown",
			}
		)


## Convenio de camber (explícito §4.3):
## `camber_rad` es AXLE-FRAME (VehicleSuspensionModel.dynamic_camber, mismo
## valor para FL/FR). Signo interno rueda: signed = +camber en izquierda
## [0,2], -camber en derecha [1,3], idéntico a dynamic_wheel_camber.
## Axle positivo = parte alta hacia fuera en ambas ruedas (espejo FL/FR).
## Se acota tan() a ±0.5 rad tras aplicar camber_thrust_gain por eje.
func evaluate(
	index: int,
	normal_load_n: float,
	surface_name: String,
	longitudinal_speed_m_s: float,
	lateral_speed_m_s: float,
	wheel_speed_rad_s: float,
	rolling_radius_m: float,
	camber_rad: float,
	thermal_grip_factor: float,
	pressure_kpa_gauge: float,
	delta: float,
	carcass_temperature_c: float,
	water_mm: float = 0.0,
	snow_mm: float = 0.0,
	ground_temperature_c: float = 30.0,
	winter_layer_id: String = "",
) -> Dictionary:
	var state: Dictionary = states[index]
	var axle_surface_set: Dictionary = axle_surfaces[index] if index >= 0 and index < axle_surfaces.size() else surfaces
	if axle_surface_set.is_empty():
		axle_surface_set = surfaces
	# Virtual deep-snow profile: Dirt friction as the starting point, soft carcass
	# response and heavy rolling drag. No vehicle JSON carries SnowDeep; the
	# builder assigns the contact identity from winter materials.
	var target_surface: Dictionary = {}
	if surface_name == "SnowDeep":
		var dirt_base: Dictionary = (axle_surface_set.get("Dirt", surfaces.get("Dirt", { })) as Dictionary).duplicate(true)
		if dirt_base.is_empty():
			dirt_base = {
				"friction": 1.05,
				"stiffness": 0.9,
				"rolling_resistance": 2.0,
				"longitudinal_grip_ratio": 1.0,
				"lateral_grip_assist": 0.0,
			}
		dirt_base["stiffness"] = 0.5
		dirt_base["rolling_resistance"] = 5.5
		target_surface = dirt_base
	else:
		if not axle_surface_set.has(surface_name):
			# "Unknown"/vacío es el centinela de contacto sin superficie mapeada
			# (colisionador sin grupo/meta): fallback silencioso a grava/carretera.
			# Solo los nombres reales no registrados merecen aviso de contenido.
			if surface_name != "Unknown" and not surface_name.is_empty() and not missing_surface_warnings.has(surface_name):
				missing_surface_warnings[surface_name] = true
				push_warning("Tire contact has no surface profile for '%s'; using the original gravel/road fallback." % surface_name)
		target_surface = axle_surface_set.get(
			surface_name,
			axle_surface_set.get("Gravel", axle_surface_set.get("Road", surfaces.get("Gravel", surfaces.get("Road", { })))),
		)
		if target_surface.is_empty():
			target_surface = {
				"friction": 1.0,
				"stiffness": 1.0,
				"rolling_resistance": 1.0,
				"longitudinal_grip_ratio": 1.0,
				"lateral_grip_assist": 0.0,
			}
	var tau_surface := maxf(float(axle_surface_tau_s[index]) if index >= 0 and index < axle_surface_tau_s.size() else surface_transition_tau_s, 0.0)
	if not bool(state.surface_initialized):
		state.surface_friction = float(target_surface.get("friction", 1.0))
		state.surface_stiffness = float(target_surface.get("stiffness", 1.0))
		state.surface_rolling = float(target_surface.get("rolling_resistance", 1.0))
		state.surface_initialized = true
	else:
		var surface_alpha := (
			1.0
			if tau_surface <= 1e-9
			else 1.0 - exp(-maxf(delta, 0.0) / tau_surface)
		)
		state.surface_friction += (
			float(target_surface.get("friction", 1.0)) - float(state.surface_friction)
		) * surface_alpha
		state.surface_stiffness += (
			float(target_surface.get("stiffness", 1.0)) - float(state.surface_stiffness)
		) * surface_alpha
		state.surface_rolling += (
			float(target_surface.get("rolling_resistance", 1.0)) - float(state.surface_rolling)
		) * surface_alpha
	state.surface = surface_name
	var profile: Dictionary = axle_profiles[index]
	var contact_target := normal_load_n > 1e-4
	var contact_tau := clampf(float(profile.get("contact_ramp_tau_s", 0.0)), 0.0, 1.0)
	# Rampa §4.6: al re-contactar (blend<1, con carga) subida rápida 20 ms para
	# no patinar con patch cero; al descargar se respeta el tau del perfil.
	var effective_contact_tau := contact_tau
	if contact_target and float(state.contact_blend) < 1.0:
		effective_contact_tau = minf(contact_tau, CONTACT_LANDING_TAU_S)
	if effective_contact_tau <= 1e-9:
		state.contact_blend = 1.0 if contact_target else 0.0
	else:
		var contact_alpha := 1.0 - exp(-maxf(delta, 0.0) / effective_contact_tau)
		state.contact_blend = clampf(
			float(state.contact_blend)
			+ ((1.0 if contact_target else 0.0) - float(state.contact_blend)) * contact_alpha,
			0.0,
			1.0,
		)
	if not contact_target:
		_advance_unloaded(index, delta)
		return _output(state)

	# Envolvente §closure-1 + tandem temporal §4.5: la carga que alimenta
	# mu/capacidad se filtra con tau = huella / planar (mín 2 ms). A carga
	# constante converge a Fz. Al despegar se invalida; al volver se siembra
	# con la primera carga válida (sin memoria residual entre aterrizajes).
	var planar_early := Vector2(longitudinal_speed_m_s, lateral_speed_m_s).length()
	var envelope_tau := maxf(float(state.get("dynamic_contact_patch_m", base_contact_patch_m[index])) / maxf(planar_early, 1.0), ENVELOPE_PATCH_TAU_MIN_S)
	if not bool(state.get("envelope_valid", false)):
		state.enveloped_load_n = maxf(normal_load_n, 0.0)
		state.envelope_valid = true
	else:
		var env_alpha := 1.0 - exp(-maxf(delta, 0.0) / maxf(envelope_tau, 1.0e-4))
		state.enveloped_load_n = lerpf(float(state.enveloped_load_n), maxf(normal_load_n, 0.0), env_alpha)
	var enveloped_load := maxf(float(state.enveloped_load_n), 0.0)

	# §closure-2: deflexión ya resuelta ANTES del slip. Prioridad al rig;
	# fallback por inversión compartida (bisección monótona, satura en tope).
	# Coeffs una vez por solución.
	var nominal_radius := maxf(rolling_radius_m, 0.05)
	var sidewall_max := maximum_tire_deflection_m[index]
	var estimated_deflection := 0.0
	var rig_has := state.has("radial_deflection_m") and float(state.get("radial_deflection_m", 0.0)) > 0.0
	if rig_has:
		estimated_deflection = clampf(float(state.radial_deflection_m), 0.0, sidewall_max * 1.5)
	else:
		estimated_deflection = fallback_deflection_m(
			radial_tires, "front" if index < 2 else "rear",
			pressure_kpa_gauge, carcass_temperature_c,
			maxf(normal_load_n, 0.0), float(axle_optimal_carcass_c[index]),
			sidewall_max, 1.5,
		)
	# Radio efectivo del mismo subpaso con la deflexión ya resuelta.
	var radius := effective_radius_m(nominal_radius, estimated_deflection, sidewall_max)
	state.effective_radius_m = radius
	var rim_speed := wheel_speed_rad_s * radius
	var speed_reference := maxf(maxf(absf(longitudinal_speed_m_s), absf(rim_speed)), 1.0)
	var target_ratio := clampf((rim_speed - longitudinal_speed_m_s) / speed_reference, -3.0, 3.0)
	var target_angle := clampf(
		atan2(-lateral_speed_m_s, maxf(absf(longitudinal_speed_m_s), 0.5)),
		-0.75,
		0.75,
	)
	state.slip_ratio = target_ratio
	state.slip_angle = target_angle
	var planar_speed := Vector2(longitudinal_speed_m_s, lateral_speed_m_s).length()
	var reference_load := maxf(static_wheel_load_n[index], 100.0)
	var load_ratio := maxf(maxf(normal_load_n, 0.0) / reference_load, 0.05)
	var pressure_ratio := maxf(pressure_kpa_gauge / reference_hot_pressure_kpa[index], 0.001)
	var deflection_ratio := clampf(
		estimated_deflection / maximum_tire_deflection_m[index],
		0.0,
		1.5,
	)
	var patch_scale := clampf(
		1.0 + float(axle_contact_load_gain[index]) * (load_ratio - 1.0)
		+ float(axle_contact_deflection_gain[index]) * (deflection_ratio - static_deflection_ratio[index]),
		0.70,
		1.45,
	)
	var dynamic_contact_patch := base_contact_patch_m[index] * patch_scale
	var patch_ratio := clampf(dynamic_contact_patch / base_contact_patch_m[index], 0.70, 1.50)
	var pressure_relaxation_scale := clampf(
		pow(pressure_ratio, clampf(float(axle_pressure_relaxation[index]), -3.0, 3.0)),
		0.80,
		1.30,
	)
	var relaxation_length := base_relaxation_length_m[index] * sqrt(patch_ratio) * pressure_relaxation_scale
	state.dynamic_contact_patch_m = dynamic_contact_patch
	state.relaxation_length_m = relaxation_length
	state.estimated_carcass_deflection_m = estimated_deflection
	var min_relaxation_tau := clampf(float(profile.get("min_relaxation_tau_s", 0.0)), 0.0, 0.5)
	var relaxation_tau := maxf(
		relaxation_length / maxf(planar_speed, 4.0),
		min_relaxation_tau,
	)
	var recovery_scale := clampf(float(profile.get("relaxation_recovery_scale", 1.0)), 0.1, 5.0)
	var lat_recovering := absf(float(state.effective_slip_angle)) > absf(target_angle)
	var lon_recovering := absf(float(state.effective_slip_ratio)) > absf(target_ratio)
	var lat_tau := relaxation_tau * (recovery_scale if lat_recovering else 1.0)
	var lon_tau := relaxation_tau * (recovery_scale if lon_recovering else 1.0)
	var lat_alpha := 1.0 - exp(-maxf(delta, 0.0) / maxf(lat_tau, 1e-4))
	var lon_alpha := 1.0 - exp(-maxf(delta, 0.0) / maxf(lon_tau, 1e-4))
	state.effective_slip_angle += (target_angle - float(state.effective_slip_angle)) * lat_alpha
	state.effective_slip_ratio += (target_ratio - float(state.effective_slip_ratio)) * lon_alpha

	# Carga para mu/capacidad: envolvente (suaviza curbs), no el pico instantáneo.
	# A carga constante converge a Fz. §4.5.
	var fz := enveloped_load
	var fz_static := maxf(normal_load_n, 0.0)
	var pressure_rr := clampf(
		pow(pressure_ratio, clampf(float(axle_pressure_rolling[index]), -3.0, 3.0)),
		0.75,
		1.50,
	)
	var axle_mult := float(axle_load_mult[index])
	var load_sensitivity_exp := clampf(
		float(axle_load_sensitivity[index]) * reference_load * axle_mult,
		0.08,
		0.25,
	)
	var load_scale := clampf(pow(load_ratio, -load_sensitivity_exp), 0.60, 1.20)
	# Respuesta de compuesto/agua/nieve/suelo combinada una sola vez con la
	# curva base y el factor térmico (sin duplicar la reducción mojada).
	# Película fina con velocidad §4.5; hielo mojado combina y clampea §4.5.
	var compound_mult := 1.0
	var compound_detail := {"water": 1.0, "snow": 1.0, "ground": 1.0, "combined": 1.0}
	var compound: Dictionary = wheel_compounds[index] if index >= 0 and index < wheel_compounds.size() else active_compound

	if not compound.is_empty():
		if winter_layer_id in ["snow_packed", "snow_loose", "snow_deep", "ice"]:
			var snow_base := 1.0
			match winter_layer_id:
				"snow_packed":
					snow_base = float(compound.get("snow_packed_grip_scale", 1.0))
				"snow_loose", "snow_deep":
					snow_base = float(compound.get("snow_loose_grip_scale", 1.0))
				"ice":
					snow_base = float(compound.get("ice_grip_scale", 1.0))
			# Hielo/nieve mojada: la película fina también muerde (antes se
			# ignoraba el agua). Clamp combinado para no salirse del rango.
			var wet_detail := compound_water_snow_ground_factor(
				water_mm, snow_mm, ground_temperature_c, index, planar_speed
			)
			var wet_mult := float(wet_detail.get("combined", 1.0))
			compound_detail = {"water": float(wet_detail.get("water", 1.0)), "snow": snow_base, "ground": float(wet_detail.get("ground", 1.0)), "combined": 1.0}
			compound_mult = clampf(snow_base * wet_mult, 0.05, 1.0)
			compound_detail["combined"] = compound_mult
			if str(compound.get("id", "")) == "snow_studded" and winter_layer_id != "ice":
				compound_mult = clampf(compound_mult * float(compound.get("uncovered_grip_scale", 1.0)), 0.05, 1.0)
		else:
			compound_detail = compound_water_snow_ground_factor(
				water_mm, snow_mm, ground_temperature_c, index, planar_speed
			)
			compound_mult = float(compound_detail.get("combined", 1.0))
			if str(compound.get("id", "")) == "snow_studded":
				compound_mult *= float(compound.get("uncovered_grip_scale", 1.0))

	state["winter_layer_id"] = winter_layer_id
	state["compound_water_factor"] = float(compound_detail.get("water", 1.0))
	state["compound_snow_factor"] = float(compound_detail.get("snow", 1.0))
	state["compound_ground_factor"] = float(compound_detail.get("ground", 1.0))
	# Additional compound/surface compatibility.
	# Do not apply over physical snow or ice overlays.
	if winter_layer_id.is_empty():
		if surface_name == "Road":
			compound_mult *= float(
				compound.get("road_grip_scale", 1.0)
			)
		elif surface_name in ["Gravel", "Dirt", "Sand"]:
			compound_mult *= float(
				compound.get("loose_grip_scale", 1.0)
			)
	state["compound_mult"] = compound_mult
	state["local_water_mm"] = water_mm
	state["local_snow_mm"] = snow_mm
	state["local_ground_c"] = ground_temperature_c
	var mu := maxf(float(state.surface_friction), 0.0) * load_scale * clampf(
		thermal_grip_factor,
		0.05,
		1.0,
	) * compound_mult
	var longitudinal_ratio := clampf(
		float(target_surface.get("longitudinal_grip_ratio", 1.0)),
		0.10,
		1.50,
	)
	var lateral_assist := clampf(float(target_surface.get("lateral_grip_assist", 0.0)), -0.5, 1.0)
	var lateral_bonus := 1.0 + lateral_assist
	var fx_capacity := maxf(mu * longitudinal_ratio * fz, 1e-6)
	var fy_capacity := maxf(mu * lateral_bonus * fz, 1e-6)
	var stiffness_scale := sqrt(clampf(maxf(float(state.surface_stiffness), 0.0) / 5.0, 0.15, 2.5))
	var rise_gamma := clampf(2.0 * stiffness_scale, 1.2, 4.0)
	# Pico dependiente de carga + térmico/desgaste §4.5.
	# peak_load_sensitivity (default 0 = neutro): picos crecen con la carga
	# como pow(load_ratio, exp). Ventana térmica/desgaste vía thermal_grip:
	# frío/gastado adelanta el pico (0.85-1.0). Sin claves nuevas el
	# comportamiento es bit-idéntico al anterior.
	var peak_load_exp := clampf(float(profile.get("peak_load_sensitivity", 0.0)), -0.5, 0.5)
	var peak_load_scale := pow(load_ratio, peak_load_exp) if absf(peak_load_exp) > 1.0e-9 else 1.0
	var peak_thermal_scale := clampf(0.85 + 0.15 * clampf(thermal_grip_factor, 0.0, 1.0), 0.85, 1.0)
	var base_peak_lat := maxf(float(profile.get("lateral_peak_slip_angle_rad", 0.18)) * peak_load_scale * peak_thermal_scale, 1e-6)
	var base_peak_lon := maxf(float(profile.get("longitudinal_peak_slip_ratio", 0.2)) * peak_load_scale * peak_thermal_scale, 1e-6)
	# Rigidez de carcasa por temperatura §4.5: misma ley que el radial
	# (1 - 0.0015*(T-opt), 0.88-1.12). Frío = más rígido, caliente = blando.
	var carcass_stiff_scale := clampf(1.0 - 0.0015 * (carcass_temperature_c - float(axle_optimal_carcass_c[index])), 0.88, 1.12)
	var slide_lat := clampf(
		float(
			profile.get("lateral_slide_mu_ratio", profile.get("longitudinal_slide_mu_ratio", 0.94))
		),
		0.0,
		1.0,
	)
	var slide_lon := clampf(float(profile.get("longitudinal_slide_mu_ratio", 0.95)), 0.0, 1.0)
	var signed_camber := camber_rad * (1.0 if index in [0, 2] else -1.0)
	var camber_gain := float(axle_camber_gain[index])
	var blend := float(state.contact_blend)

	var patch_before: Vector2 = state.patch_pos
	# Transport sets the steady deflection. The time constants govern only
	# how quickly each component approaches it.
	var transport_speed := maxf(planar_speed, absf(rim_speed))
	var transport_rate := transport_speed / maxf(relaxation_length, 0.001)
	var patch_velocity := Vector2(rim_speed - longitudinal_speed_m_s, -lateral_speed_m_s)
	patch_velocity.y += absf(longitudinal_speed_m_s) * tan(clampf(signed_camber * camber_gain, -0.5, 0.5))
	var patch_dt := maxf(delta, 0.0)
	var patch_pos := patch_before + patch_velocity * patch_dt
	if transport_rate > 1.0e-6:
		var transport_tau := 1.0 / transport_rate
		var lon_patch_tau := maxf(min_relaxation_tau, transport_tau * (recovery_scale if lon_recovering else 1.0))
		var lat_patch_tau := maxf(min_relaxation_tau, transport_tau * (recovery_scale if lat_recovering else 1.0))
		var target_patch := patch_velocity / transport_rate
		patch_pos.x = lerpf(patch_before.x, target_patch.x, 1.0 - exp(-patch_dt / lon_patch_tau))
		patch_pos.y = lerpf(patch_before.y, target_patch.y, 1.0 - exp(-patch_dt / lat_patch_tau))
	# Bidirectional combined-slip reference migration.
	# Preserve the legacy behavior unless explicitly enabled.

	var length_m := maxf(relaxation_length, 0.001)

	# Original brush stiffness and trial demand (con escala térmica carcasa).
	var stiffness_x := fx_capacity * 3.0 * carcass_stiff_scale / (
		base_peak_lon * length_m
	)
	var stiffness_y := fy_capacity * rise_gamma * carcass_stiff_scale / (
		base_peak_lat * length_m
	)

	var trial := Vector2(
		stiffness_x * patch_pos.x,
		stiffness_y * patch_pos.y
	)

	var migration_v2_enabled := bool(
		profile.get("combined_migration_v2_enabled", false)
	)

	if migration_v2_enabled:
		# Compute utilization BEFORE migration.
		# Do not calculate these values recursively.
		var ux := clampf(
			absf(trial.x) / maxf(3.0 * fx_capacity, 1e-6),
			0.0,
			1.0
		)
		var uy := clampf(
			absf(trial.y) / maxf(rise_gamma * fy_capacity, 1e-6),
			0.0,
			1.0
		)

		var m_lat := clampf(
			float(profile.get("combined_lateral_peak_migration", 0.0)),
			0.0,
			0.30
		)
		var m_lon := clampf(
			float(profile.get("combined_longitudinal_peak_migration", 0.0)),
			0.0,
			0.30
		)

		# Longitudinal demand migrates lateral reference.
		var peak_lat_eff := base_peak_lat * (
			1.0 + m_lat * ux
		)

		# Lateral demand migrates longitudinal reference.
		var peak_lon_eff := base_peak_lon * (
			1.0 + m_lon * uy
		)

		# Recompute stiffness without modifying force limits.
		stiffness_x = fx_capacity * 3.0 * carcass_stiff_scale / (
			peak_lon_eff * length_m
		)
		stiffness_y = fy_capacity * rise_gamma * carcass_stiff_scale / (
			peak_lat_eff * length_m
		)

		trial = Vector2(
			stiffness_x * patch_pos.x,
			stiffness_y * patch_pos.y
		)

	# Post-peak demand must use the actual migrated trial.
	var norm_demand_x := absf(trial.x) / fx_capacity
	var norm_demand_y := absf(trial.y) / fy_capacity

	# Legacy longitudinal relief (old anti-oversteer hack, now opt-in).
	# Previously: abrupt step at patch_pos.x = 0, rear axle only, default 0.3,
	# keyed off the overloaded combined_lateral_peak_migration.
	# Now: smooth blend centered at 0 with configurable width, per-axle opt-in
	# via legacy_longitudinal_relief (default 0 = off). No hardcoded axle bias:
	# each axle's profile decides. Drive side (patch_pos.x > 0) gets relief,
	# braking side keeps full demand, with a continuous transition.
	if not migration_v2_enabled:
		var legacy_relief := clampf(
			float(profile.get("legacy_longitudinal_relief", 0.0)),
			0.0,
			0.65
		)
		if legacy_relief > 1.0e-9:
			var legacy_blend_m := clampf(
				float(profile.get("legacy_relief_blend_m", 0.01)),
				0.001,
				0.10
			)
			var relief_s := smoothstep(-legacy_blend_m, legacy_blend_m, patch_pos.x)
			norm_demand_x *= (1.0 - legacy_relief * relief_s)

	var combined_theta := Vector2(
		norm_demand_x,
		norm_demand_y
	).length() / 3.0
	var sharpness := clampf(float(profile.get("falloff_sharpness", 1.2)), 0.2, 8.0)
	var over_peak := clampf((combined_theta - 0.68) / 0.32 * sharpness, 0.0, 1.0)
	var target_decay := over_peak * over_peak * (3.0 - 2.0 * over_peak)
	var lat_weight := norm_demand_y / maxf(norm_demand_x + norm_demand_y, 1.0e-6)
	var lon_weight := 1.0 - lat_weight
	state.post_peak_decay_lat = _advance_memory(
		float(state.post_peak_decay_lat),
		target_decay * lat_weight,
		profile,
		delta,
	)
	state.post_peak_decay_lon = _advance_memory(
		float(state.post_peak_decay_lon),
		target_decay * lon_weight,
		profile,
		delta,
	)

	var mu_fz := maxf(mu * fz, 0.0)
	var sliding_fraction := clampf(
		float(state.post_peak_decay_lon) + float(state.post_peak_decay_lat),
		0.0,
		1.0,
	)
	var directional_slide_mu := lerpf(slide_lon, slide_lat, lat_weight)
	var slide_scale := lerpf(1.0, directional_slide_mu, sliding_fraction)
	var limit_x := fx_capacity * slide_scale
	var limit_y := fy_capacity * slide_scale
	var grip_limit := mu_fz * slide_scale

	if limit_x <= 1.0e-6 or limit_y <= 1.0e-6:
		patch_pos = Vector2.ZERO
		trial = Vector2.ZERO
	else:
		var norm_trial := Vector2(trial.x / limit_x, trial.y / limit_y)
		var norm_length := norm_trial.length()
		var unloading := patch_pos.dot(patch_velocity) < 0.0
		var current_theta := norm_length / 3.0
		if unloading and current_theta > 0.5:
			var recovery_boost := exp(-clampf((current_theta - 0.5) * 12.0, 0.0, 15.0) * patch_dt)
			patch_pos *= recovery_boost
			trial *= recovery_boost
			norm_length *= recovery_boost
		var max_elastic_norm := 2.65
		var plastic_scale_applied := 1.0
		if norm_length > max_elastic_norm:
			plastic_scale_applied = max_elastic_norm / norm_length
			patch_pos *= plastic_scale_applied
			trial *= plastic_scale_applied
		# §closure-4: pérdida plástica desde el cambio de estado (>= 0).
		# E_pre (sin proyectar) vs E_post: E_post = E_pre * s^2.
		var e_pre_plastic := 0.5 * (trial / maxf(plastic_scale_applied, 1.0e-9)).dot(patch_pos / maxf(plastic_scale_applied, 1.0e-9)) * blend if plastic_scale_applied < 1.0 else 0.0
		var e_post_plastic := 0.5 * trial.dot(patch_pos) * blend if plastic_scale_applied < 1.0 else 0.0
		state.set("plastic_loss_j", maxf(e_pre_plastic - e_post_plastic, 0.0))

	var brush := _brush_force_elliptical(trial, limit_x, limit_y) * blend
	var fx := brush.x
	var fy := brush.y
	# Low-speed anchored contact: at tread transports below ~1 m/s the brush
	# memory is an undamped integrator (renewal -> 0) and the rolling deadzone
	# lets a parked car chatter instead of holding. Blend toward a
	# ground-anchored Coulomb spring-damper built from the same patch state:
	# Kelvin-Voigt force (stiffness * patch + damping * slip velocity, same
	# sign convention as the brush) hard-capped to the slide-aware friction
	# ellipse so post-peak memory (incl. legacy relief) still flows through.
	# Damping is weighted by static_w twice so launches in the blend band do
	# not bog down; at rest it settles parking rock critically-ish.
	var static_w := 1.0 - smoothstep(STATIC_BLEND_FULL_M_S, STATIC_BLEND_FREE_M_S, transport_speed)
	if static_w > 1.0e-6:
		var anchor_mass := maxf(fz, 100.0) / 9.81
		var damp_scale := static_w * STATIC_DAMPING_RATIO
		var static_damp_x := 2.0 * damp_scale * sqrt(maxf(stiffness_x * anchor_mass, 1.0))
		var static_damp_y := 2.0 * damp_scale * sqrt(maxf(stiffness_y * anchor_mass, 1.0))
		var f_static := Vector2(
			stiffness_x * patch_pos.x + static_damp_x * patch_velocity.x,
			stiffness_y * patch_pos.y + static_damp_y * patch_velocity.y
		) * blend
		var cap_norm := Vector2(
			f_static.x / maxf(limit_x, 1.0e-6),
			f_static.y / maxf(limit_y, 1.0e-6)
		).length()
		if cap_norm > 1.0:
			f_static /= cap_norm
		fx = lerpf(fx, f_static.x, static_w)
		fy = lerpf(fy, f_static.y, static_w)
	var patch_energy := 0.5 * trial.dot(patch_pos) * blend
	var previous_patch_energy := float(state.patch_energy_j)
	var blend_loss_j := maxf(0.5 * trial.dot(patch_pos) * (1.0 - blend), 0.0)
	state.patch_pos = patch_pos
	state.patch_energy_j = patch_energy
	var rolling_spin := clampf(absf(rim_speed) / 0.5, 0.0, 1.0)
	# Rodadura con carga estática para reacción (no envolvente): el par de
	# histéresis sostiene el peso real, no el filtrado. §4.5 coherente.
	var rolling_base := fz_static * float(axle_rolling_coefficient[index]) * float(state.surface_rolling) * pressure_rr
	var rolling_force := rolling_base * tanh(longitudinal_speed_m_s / 0.3) * rolling_spin * blend
	fx -= rolling_force

	var bound_x := maxf(limit_x * blend, 1.0e-6)
	var bound_y := maxf(limit_y * blend, 1.0e-6)
	var budget_norm := Vector2(fx / bound_x, fy / bound_y).length()
	if budget_norm > 1.0:
		fx /= budget_norm
		fy /= budget_norm
		rolling_force /= budget_norm
	# §closure-1: segunda elipse con carga normal INSTANTÁNEA + mismas
	# capacidades direccionales, caída post-pico y rampa de contacto. Mismo
	# factor sobre Fx neta, Fy y rodadura (reconstrucción de par y calor).
	var limit_x_inst := mu * longitudinal_ratio * fz_static * slide_scale
	var limit_y_inst := mu * lateral_bonus * fz_static * slide_scale
	var bound_x_inst := maxf(limit_x_inst * blend, 1.0e-6)
	var bound_y_inst := maxf(limit_y_inst * blend, 1.0e-6)
	var budget_inst := Vector2(fx / bound_x_inst, fy / bound_y_inst).length()
	if budget_inst > 1.0 and (contact_target):
		fx /= budget_inst
		fy /= budget_inst
		rolling_force /= budget_inst
	# Include the rolling moment in the wheel reaction, separate from net Fx.
	state.rolling_force = rolling_force

	var brush_theta := clampf(
		Vector2(trial.x / maxf(limit_x, 1.0e-6), trial.y / maxf(limit_y, 1.0e-6)).length() / 3.0,
		0.0,
		1.0,
	)
	var lon_theta := clampf(absf(trial.x) / maxf(3.0 * limit_x, 1.0e-6), 0.0, 1.0)
	var trail := float(axle_pneumatic_trail[index]) * patch_ratio * pow(1.0 - brush_theta, 1.35) * (1.0 - 0.75 * lon_theta)
	var aligning_torque := -fy * trail
	var slip_longitudinal_speed := rim_speed - longitudinal_speed_m_s
	# §closure-4: trabajo de contacto con Fx reconstruida (neta + rodadura),
	# slip de llanta con radio efectivo y lateral con signo del marco.
	var fx_contact := fx + rolling_force
	var contact_power := fx_contact * slip_longitudinal_speed - fy * lateral_speed_m_s
	var rolling_power := rolling_force * longitudinal_speed_m_s
	# Balance energético §4.2: energía elástica con demanda trial (no fuerza
	# saturada). El residuo con signo se publica para medirlo antes de decidir
	# si se sustituye el clamp; la proyección plástica y la rigidez variable
	# aparecen como disipación positiva en el residuo.
	var energy_residue := contact_power - (patch_energy - previous_patch_energy) / maxf(patch_dt, 1.0e-6)
	state.energy_residue_w = energy_residue
	var friction_power := maxf(energy_residue, 0.0)
	friction_power += absf(rolling_force * longitudinal_speed_m_s)
	# §closure-4: calor slide independiente (déficit demanda vs brush por
	# velocidad de deslizamiento), sin cerrar por construcción. Término
	# separado del momento autoalineante (velocidad angular conjugada no
	# disponible a nivel de neumático: se publica en 0 y el vehículo lo
	# integra como Mz*omega_z si lo necesita).
	var brush_unblended := _brush_force_elliptical(trial, limit_x, limit_y)
	var slide_heat_w := maxf((trial - brush_unblended).dot(patch_velocity), 0.0) * blend
	state.longitudinal_force = fx
	state.lateral_force = fy
	state.aligning_torque = aligning_torque
	state.friction_power = friction_power
	state.combined_utilization = Vector2(
		fx / maxf(fx_capacity, 1.0e-6),
		fy / maxf(fy_capacity, 1.0e-6),
	).length()
	state.instant_combined_utilization = Vector2(
		fx / bound_x_inst,
		fy / bound_y_inst,
	).length()
	state.brush_demand_n = trial.length()
	# Auditoría acumulada §closure-4 (julios; descarte al despegar separado).
	state.contact_power_w = contact_power
	state.rolling_power_w = rolling_power
	state.elastic_before_j = previous_patch_energy
	state.blend_loss_j = blend_loss_j
	state.stiffness_loss_j = 0.0
	state.aligning_power_w = 0.0
	var h_step := maxf(patch_dt, 0.0)
	state.contact_work_j = float(state.get("contact_work_j", 0.0)) + contact_power * h_step
	state.heat_work_j = float(state.get("heat_work_j", 0.0)) + friction_power * h_step
	state.slide_heat_w = slide_heat_w
	return _output(state)


func _brush_force_elliptical(demand: Vector2, limit_x: float, limit_y: float) -> Vector2:
	if limit_x <= 1.0e-6 or limit_y <= 1.0e-6:
		return Vector2.ZERO
	var norm_demand := Vector2(demand.x / limit_x, demand.y / limit_y)
	var magnitude := norm_demand.length()
	if magnitude <= 1.0e-9:
		return Vector2.ZERO
	var theta := clampf(magnitude / 3.0, 0.0, 1.0)
	var factor := 3.0 * theta - 3.0 * theta * theta + theta * theta * theta
	var unit_force := norm_demand * (factor / magnitude)
	return Vector2(unit_force.x * limit_x, unit_force.y * limit_y)


func state_for(index: int) -> Dictionary:
	return states[index].duplicate(true) if index >= 0 and index < states.size() else { }


func reset_patch(index: int) -> void:
	# Reset completo §4.6 + §closure-1: sin restos (slips, decays, fuerzas,
	# blend, energía). Invalida carga filtrada y geometría derivada; el
	# filtro se siembra con la primera carga válida al volver a contacto.
	# Preserva convenio de rampa y radio nominal sin contacto.
	var st: Dictionary = states[index]
	st.patch_pos = Vector2.ZERO
	st.patch_forward = Vector3.ZERO
	st.patch_right = Vector3.ZERO
	st.patch_energy_j = 0.0
	st.effective_slip_angle = 0.0
	st.effective_slip_ratio = 0.0
	st.slip_angle = 0.0
	st.slip_ratio = 0.0
	st.post_peak_decay_lat = 0.0
	st.post_peak_decay_lon = 0.0
	st.contact_blend = 0.0
	st.enveloped_load_n = 0.0
	st.envelope_valid = false
	st.dynamic_contact_patch_m = base_contact_patch_m[index] if index >= 0 and index < base_contact_patch_m.size() else 0.2
	st.relaxation_length_m = base_relaxation_length_m[index] if index >= 0 and index < base_relaxation_length_m.size() else 0.3
	st.estimated_carcass_deflection_m = 0.0
	st.longitudinal_force = 0.0
	st.rolling_force = 0.0
	st.lateral_force = 0.0
	st.aligning_torque = 0.0
	st.friction_power = 0.0
	st.energy_residue_w = 0.0
	st.combined_utilization = 0.0
	st.instant_combined_utilization = 0.0
	st.brush_demand_n = 0.0
	st.contact_power_w = 0.0
	st.rolling_power_w = 0.0
	st.elastic_before_j = 0.0
	st.set("plastic_loss_j", 0.0)
	st.blend_loss_j = 0.0
	st.stiffness_loss_j = 0.0
	st.liftoff_discard_j = 0.0
	st.slide_heat_w = 0.0
	st.aligning_power_w = 0.0


func rotate_patch_frame(index: int, forward: Vector3, right: Vector3) -> void:
	# Punto 1 original descartado: el frame se asigna fuera del guard y el
	# caller ya pasa vectores ortonormales. Solo hardening defensivo.
	# Ortonormalización Gram-Schmidt opcional si el caller deriva.
	var state: Dictionary = states[index]
	var previous_forward: Vector3 = state.patch_forward
	if previous_forward.length_squared() > 0.5:
		var patch: Vector2 = state.patch_pos
		var world_patch := previous_forward * patch.x + (state.patch_right as Vector3) * patch.y
		state.patch_pos = Vector2(world_patch.dot(forward), world_patch.dot(right))
	state.patch_forward = forward
	state.patch_right = right


func _advance_unloaded(index: int, delta: float) -> void:
	var state: Dictionary = states[index]
	var profile: Dictionary = axle_profiles[index]
	var recovery_tau := float(profile.get("slip_recovery_tau_s", 0.0))
	var release := 0.0 if recovery_tau <= 1e-6 else exp(-maxf(delta, 0.0) / recovery_tau)
	state.effective_slip_angle = 0.0
	# Detached tread cannot keep its ground anchor for the next landing.
	# La energía elástica remanente se descarta (no se cuenta como calor):
	# el balance con pérdida de contacto se verifica solo en contacto continuo.
	# §closure-1/4: invalida envolvente y geometría; descarte separado del calor.
	var discarded := float(state.get("patch_energy_j", 0.0))
	state.liftoff_discard_j = float(state.get("liftoff_discard_j", 0.0)) + discarded
	state.patch_pos = Vector2.ZERO
	state.patch_forward = Vector3.ZERO
	state.patch_right = Vector3.ZERO
	state.patch_energy_j = 0.0
	state.enveloped_load_n = 0.0
	state.envelope_valid = false
	state.dynamic_contact_patch_m = base_contact_patch_m[index] if index >= 0 and index < base_contact_patch_m.size() else 0.2
	state.relaxation_length_m = base_relaxation_length_m[index] if index >= 0 and index < base_relaxation_length_m.size() else 0.3
	state.estimated_carcass_deflection_m = 0.0
	state.effective_slip_angle = 0.0
	state.effective_slip_ratio = 0.0
	state.slip_angle = 0.0
	state.slip_ratio = 0.0
	state.post_peak_decay_lat *= release
	state.post_peak_decay_lon *= release
	state.longitudinal_force = 0.0
	state.rolling_force = 0.0
	state.lateral_force = 0.0
	state.aligning_torque = 0.0
	state.friction_power = 0.0
	state.energy_residue_w = 0.0
	state.combined_utilization = 0.0
	state.instant_combined_utilization = 0.0
	state.brush_demand_n = 0.0
	state.contact_power_w = 0.0
	state.rolling_power_w = 0.0
	state.elastic_before_j = 0.0
	state.blend_loss_j = 0.0
	state.stiffness_loss_j = 0.0
	state.slide_heat_w = 0.0
	state.aligning_power_w = 0.0


func _advance_memory(current: float, target: float, profile: Dictionary, delta: float) -> float:
	var tau := (
		float(profile.get("slip_loss_tau_s", 0.0))
		if target > current
		else float(profile.get("slip_recovery_tau_s", 0.0))
	)
	if tau <= 1e-6:
		return target
	var alpha := 1.0 - exp(-maxf(delta, 0.0) / tau)
	return clampf(current + (target - current) * alpha, 0.0, 1.0)


# _pure_curve: referencia estacionaria para validar la curva brush+memoria
# (§4.5 curva estacionaria vs memoria). No está en el path caliente; los
# contratos de barrido la comparan contra el estado estable del brush.
# _brush_force y _combined_budget_scale eliminados §4.6 (código muerto: el
# path usa _brush_force_elliptical + renormalización directa del budget).
func _pure_curve(
	slip: float,
	peak: float,
	slide: float,
	rise: float,
	sharpness: float,
) -> Dictionary:
	var normalized := maxf(slip, 0.0) / maxf(peak, 1e-6)
	if normalized <= 1.0:
		return {
			"coefficient": clampf(1.0 - pow(1.0 - normalized, maxf(rise, 1.2)), 0.0, 1.0),
			"decay": 0.0,
		}
	var distance := clampf(sharpness, 0.1, 16.0) * (normalized - 1.0)
	var decay := distance * distance / (1.0 + distance * distance)
	return {
		"coefficient": clampf(slide + (1.0 - slide) * (1.0 - decay), 0.0, 1.0),
		"decay": decay,
	}


func _output(state: Dictionary) -> Dictionary:
	return {
		"longitudinal_force_n": float(state.longitudinal_force),
		"rolling_force_n": float(state.get("rolling_force", 0.0)),
		"lateral_force_n": float(state.lateral_force),
		"aligning_torque_nm": float(state.aligning_torque),
		"friction_power_w": float(state.friction_power),
		"energy_residue_w": float(state.get("energy_residue_w", 0.0)),
		"effective_radius_m": float(state.get("effective_radius_m", 0.28)),
		"enveloped_load_n": float(state.get("enveloped_load_n", 0.0)),
		"slip_ratio": float(state.slip_ratio),
		"slip_angle_rad": float(state.slip_angle),
		"effective_slip_ratio": float(state.get("effective_slip_ratio", 0.0)),
		"effective_slip_angle_rad": float(state.get("effective_slip_angle", 0.0)),
		"combined_utilization": float(state.combined_utilization),
		"instant_combined_utilization": float(state.get("instant_combined_utilization", 0.0)),
		"contact_power_w": float(state.get("contact_power_w", 0.0)),
		"rolling_power_w": float(state.get("rolling_power_w", 0.0)),
		"slide_heat_w": float(state.get("slide_heat_w", 0.0)),
		"plastic_loss_j": float(state.get("plastic_loss_j", 0.0)),
		"blend_loss_j": float(state.get("blend_loss_j", 0.0)),
		"liftoff_discard_j": float(state.get("liftoff_discard_j", 0.0)),
		"contact_work_j": float(state.get("contact_work_j", 0.0)),
		"heat_work_j": float(state.get("heat_work_j", 0.0)),
		"aligning_power_w": float(state.get("aligning_power_w", 0.0)),
		"surface": str(state.surface),
		"patch_pos": state.patch_pos,
		"patch_energy_j": state.patch_energy_j,
		"brush_demand_n": state.get("brush_demand_n", 0.0),
	}


static func _axle_dict(tires: Dictionary, axle: String) -> Dictionary:
	var d: Variant = tires.get(axle, { })
	return (d as Dictionary).duplicate(true) if d is Dictionary else { }


static func _filter_scalars(resolved_filters: Dictionary, axle: String) -> Dictionary:
	var d: Variant = resolved_filters.get(axle + "_tire_scalars", { })
	if d is Dictionary:
		return (d as Dictionary).duplicate(true)
	return { }


static func _resolve_scalar(
	axle_tire: Dictionary, tires_global: Dictionary, filter_scalars: Dictionary,
	key: String, default_value: float, min_value: float, max_value: float,
) -> float:
	if filter_scalars.has(key):
		return clampf(float(filter_scalars.get(key, default_value)), min_value, max_value)
	if axle_tire.has(key):
		return clampf(float(axle_tire.get(key, default_value)), min_value, max_value)
	if tires_global.has(key):
		return clampf(float(tires_global.get(key, default_value)), min_value, max_value)
	return clampf(default_value, min_value, max_value)


static func _resolve_pm_scalar(
	axle_pm: Dictionary, global_pm: Dictionary, filter_pm: Dictionary,
	key: String, default_value: float,
) -> float:
	if filter_pm.has(key):
		return float(filter_pm.get(key, default_value))
	if axle_pm is Dictionary and axle_pm.has(key):
		return float(axle_pm.get(key, default_value))
	if global_pm is Dictionary and global_pm.has(key):
		return float(global_pm.get(key, default_value))
	return default_value


static func _resolve_axle_surfaces(
	global_surfaces: Dictionary, axle_override: Variant, filter_override: Variant, is_front: bool,
) -> Dictionary:
	var axle_dict: Dictionary = (axle_override as Dictionary).duplicate(true) if axle_override is Dictionary else { }
	var filter_dict: Dictionary = (filter_override as Dictionary).duplicate(true) if filter_override is Dictionary else { }
	var names := { }
	for k in global_surfaces:
		names[k] = true
	for k in axle_dict:
		names[k] = true
	for k in filter_dict:
		names[k] = true
	var resolved := { }
	for surface_name in names:
		var base: Dictionary = ((global_surfaces.get(surface_name, { }) as Dictionary).duplicate(true) if global_surfaces.get(surface_name, { }) is Dictionary else { })
		if base.is_empty():
			base = {
				"friction": 1.0,
				"stiffness": 1.0,
				"rolling_resistance": 1.0,
				"longitudinal_grip_ratio": 1.0,
				"lateral_grip_assist": 0.0,
			}
		var ax: Dictionary = axle_dict.get(surface_name, { }) if axle_dict.get(surface_name, { }) is Dictionary else { }
		var flt: Dictionary = filter_dict.get(surface_name, { }) if filter_dict.get(surface_name, { }) is Dictionary else { }
		for k in ax:
			base[k] = ax[k]
		for k in flt:
			base[k] = flt[k]
		if is_front:
			# Compatibilidad: el delantero ignoraba lateral_grip_assist global.
			# Solo aplica assist delante si viene explícito en su override por eje.
			var front_explicit := (ax is Dictionary and ax.has("lateral_grip_assist")) or (flt is Dictionary and flt.has("lateral_grip_assist"))
			if not front_explicit:
				base["lateral_grip_assist"] = 0.0
		resolved[surface_name] = base
	return resolved
