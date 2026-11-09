class_name RallyTireCompound
extends RefCounted
## Fuente única de IDs de neumático; catálogo extensible sin listas duplicadas.
## Por contacto: material real + zona → compuesto/agua/nieve/suelo → una sola
## combinación con la curva base y el factor térmico (sin duplicar lo mojado).

const CATALOG_PATH := "res://data/tires/rally_compounds.json"
const DEFAULT_ID := "gravel_normal"


static func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return parsed if parsed is Dictionary else {}


static func compound_ids(catalog: Dictionary) -> Array:
	return ((catalog.get("compounds", {}) as Dictionary).keys())


static func get_compound(catalog: Dictionary, compound_id: String) -> Dictionary:
	var c: Dictionary = ((catalog.get("compounds", {}) as Dictionary).get(compound_id, {}) as Dictionary)
	return (c as Dictionary).duplicate(true)


static func is_valid(compound_id: String) -> bool:
	return not compound_id.is_empty() and (load_catalog().get("compounds", {}) as Dictionary).has(compound_id)


static func validated_id(compound_id: String) -> String:
	return compound_id if is_valid(compound_id) else ""


## Respuesta de compuesto/agua/nieve/temperatura del suelo (multiplicador
## único). No impone «llueve = frío» ni «sol = caliente»: es balance.
static func grip_response(compound: Dictionary, water_mm: float, snow_mm: float, tread_c: float, ground_c: float) -> Dictionary:
	var w := clampf(water_mm, 0.0, 12.0)
	var s := clampf(snow_mm, 0.0, 8.0)
	var water_loss := float(compound.get("water_grip_loss_per_mm", 0.12))
	var water_floor := float(compound.get("water_grip_floor", 0.6))
	var snow_loss := float(compound.get("snow_grip_loss_per_mm", 0.09))
	var snow_floor := float(compound.get("snow_grip_floor", 0.6))
	var water_factor := maxf(1.0 - w * water_loss, water_floor)
	var snow_factor := maxf(1.0 - s * snow_loss, snow_floor)
	# Curva de fricción según temperatura de superficie: el suelo frío/warm
	# matiza la transferencia, sin sustituir la ventana térmica del neumático.
	var ground_factor := 1.0
	if ground_c < 5.0:
		ground_factor = lerpf(0.92, 1.0, clampf((ground_c + 5.0) / 10.0, 0.0, 1.0))
	elif ground_c > 32.0:
		ground_factor = lerpf(1.0, 0.96, clampf((ground_c - 32.0) / 12.0, 0.0, 1.0))
	# Ventana térmica del compuesto sobre el tread (banda): fuera de ventana
	# pierde grip; sobretemperatura degrada (más en lluvia por dibujo).
	var opt := float(compound.get("tread_optimum_c", 50.0))
	var win := float(compound.get("tread_window_c", 40.0))
	var over := float(compound.get("overheat_tread_c", 95.0))
	var half := win * 0.5
	var thermal := 1.0
	if tread_c < opt - half:
		thermal = clampf(0.82 + 0.18 * clampf((tread_c - (opt - half - 30.0)) / 30.0, 0.0, 1.0), 0.70, 1.0)
	elif tread_c > opt + half:
		var over_loss := float(compound.get("overheat_grip_loss", 0.3))
		thermal = clampf(1.0 - over_loss * clampf((tread_c - (opt + half)) / maxf(over - (opt + half), 1.0), 0.0, 1.0), 0.65, 1.0)
	var combined := clampf(water_factor * snow_factor * ground_factor * thermal, 0.35, 1.0)
	return {
		"water_factor": water_factor,
		"snow_factor": snow_factor,
		"ground_factor": ground_factor,
		"thermal_factor": thermal,
		"combined": combined,
		"is_wet": w >= 0.4,
		"is_snow": s >= 0.3,
	}


## Objetivos térmicos del compuesto (banda y carcasa) para el reinicio tras
## montar neumáticos al inicio de cada stage.
static func start_temperatures(compound: Dictionary) -> Dictionary:
	var tread := float(compound.get("tread_optimum_c", 50.0))
	var carcass := float(compound.get("carcass_optimum_c", 60.0))
	return {"tread_c": tread, "carcass_c": carcass, "gas_c": carcass, "surface_c": tread}
