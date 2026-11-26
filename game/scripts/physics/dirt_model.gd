extends RefCounted

const CONFIG := preload("res://data/dirt/dirt_accumulation.json")
const ZONES := 7
const THRESHOLDS := [0.02, 0.25, 0.50, 0.85]
var deposits: Array[Vector2] = []

func _init() -> void:
	deposits.resize(ZONES)
	service_clean()


func step(dt: float, speed: float, surfaces: Array[String], conditions: Array, loads: Array[float], static_loads: Array[float], slips: Array[Vector2]) -> void:
	if dt <= 0.0 or speed < 0.15:
		return
	var cfg: Dictionary = CONFIG.data
	var exposure := dt * float(cfg.base_rate) * minf(speed / float(cfg.full_speed), 1.0)
	var doses: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	for i in 4:
		if loads[i] <= 0.0 or conditions[i].is_empty():
			continue
		var load := clampf(loads[i] / maxf(static_loads[i], 100.0), 0.0, float(cfg.max_load))
		var slip := 1.0 + float(cfg.slip_gain) * minf(absf(slips[i].x), 1.0)
		doses[i] = _rates(surfaces[i], conditions[i], cfg) * (exposure * load * slip)
		_deposit(i + 1, doses[i])
	_deposit(0, (doses[0] + doses[1]) * 0.5)
	_deposit(5, (doses[0] + doses[1] + doses[2] + doses[3]) * 0.25)
	_deposit(6, (doses[2] + doses[3]) * (0.5 + 0.12 * minf(speed / 25.0, 1.0)))


func _rates(surface: String, local: Dictionary, cfg: Dictionary) -> Vector2:
	var wet := smoothstep(0.0, 0.55, float(local.get("background_water_mm", 0.0)))
	var dry := 0.0
	var mud := 0.0
	var wet_rate := 1.0
	match surface:
		"Road", "Asphalt", "Tarmac":
			dry = lerpf(float(cfg.road_dry), float(cfg.road_wet), wet)
		"Sand":
			dry = float(cfg.sand)
		"Grass":
			dry = float(cfg.grass)
			mud = wet * 0.35
			wet_rate = 0.20
		"Gravel", "Dirt":
			dry = float(cfg.dirt) if surface == "Dirt" else lerpf(float(cfg.gravel_compact), float(cfg.gravel_loose), clampf(float(local.get("loose_gravel_coverage", 0.0)), 0.0, 1.0))
			mud = clampf(float(local.get("mud_factor", smoothstep(0.55, 0.90, float(local.get("saturation", 0.0))))), 0.0, 1.0)
	var cover := clampf(float(local.get("snow_coverage", 0.0)), 0.0, 1.0)
	var mud_cover := minf(smoothstep(0.0, 3.5, float(local.get("snow_patch_depth_mm", 0.0))) * 0.25, 0.25) if local.has("mud_factor") and surface in ["Gravel", "Dirt"] else cover
	return Vector2(dry * (1.0 - mud) * (1.0 - cover), wet_rate * mud * (1.0 - mud_cover))


func _deposit(zone: int, dose: Vector2) -> void:
	var old := deposits[zone]
	deposits[zone] = Vector2(1.0 - (1.0 - old.x) * exp(-dose.x), 1.0 - (1.0 - old.y) * exp(-dose.y))


func level(zone: int, dust_weight: float = 1.0) -> float:
	var value := deposits[zone]
	return 1.0 - (1.0 - dust_weight * value.x) * (1.0 - value.y)


func visual_state(zone: int) -> Vector2:
	var stage := 0
	for threshold: float in THRESHOLDS:
		stage += int(level(zone) >= threshold)
	var value := deposits[zone]
	var mud := value.y / maxf(value.x + value.y, 0.000001)
	return Vector2(stage, roundf(mud * 4.0) * 0.25)


func is_dirty() -> bool:
	return deposits.any(func(value: Vector2) -> bool: return value != Vector2.ZERO)


func service_clean() -> void:
	deposits.fill(Vector2.ZERO)


func snapshot() -> Dictionary:
	var zones: Array = []
	for value in deposits:
		zones.append([value.x, value.y])
	return {"version": 1, "zones": zones}


func restore(saved: Variant) -> void:
	service_clean()
	if not saved is Dictionary or saved.get("version", 0) != 1 or not saved.get("zones") is Array:
		return
	for i in mini(ZONES, saved.zones.size()):
		var pair: Variant = saved.zones[i]
		if pair is Array and pair.size() == 2:
			deposits[i] = Vector2(_read_level(pair[0]), _read_level(pair[1]))


func _read_level(value: Variant) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), 0.0, 1.0)
	return 0.0
