extends RefCounted
## 0.5 s dark, three red clicks at 0.5/1.5/2.5 s, green/horn at 3.5 s.
const GO_AT := 3.5
var elapsed: float = 0.0
var origin: Vector3 = Vector3.ZERO
var previous_position: Vector3 = Vector3.ZERO
var false_start: bool = false
var active: bool = false

func reset(position: Vector3) -> void:
	elapsed = 0.0
	origin = position
	previous_position = position
	false_start = false
	active = true

func advance(dt: float, position: Vector3, _speed: float) -> Dictionary:
	var events: Array = []
	var old := elapsed
	var step := maxf(0.0, dt)
	if not active:
		return {"events": events, "racing_dt": 0.0}
	elapsed += step
	if old < GO_AT and not false_start:
		var before_go := previous_position.lerp(position, clampf((GO_AT - old) / maxf(step, 0.000001), 0.0, 1.0))
		var offset := Vector2(before_go.x - origin.x, before_go.z - origin.z)
		# Small tolerance rejects suspension settling; both forward and reverse count.
		if offset.length() > 0.75:
			false_start = true
			events.append("false_start")
	for boundary in [0.5, 1.5, 2.5]:
		if old < boundary and elapsed >= boundary:
			events.append("click")
	if old < GO_AT and elapsed >= GO_AT:
		events.append("go")
	previous_position = position
	return {"events": events, "racing_dt": maxf(0.0, elapsed - maxf(old, GO_AT))}

func readout() -> Dictionary:
	return {"visible": active and elapsed < 5.0, "phase": "off" if elapsed < 0.5 else ("ready" if elapsed < GO_AT else "go"), "false_start": false_start}
