extends SceneTree

const Tracker = preload("res://scripts/rally/pacenote_gate_tracker.gd")

func _initialize() -> void:
	test_basic_and_direction()
	test_slope_and_camber()
	test_teleport_handling()
	test_missed_gate_recovery()
	test_hairpin_neighbor_gates()
	test_plane_contact_and_invalid_config()
	print("Pacenote gates (all tests): OK")
	quit()

func test_basic_and_direction() -> void:
	var tracker = Tracker.new()
	assert(tracker.configure([
		{"left": [-2, 0, 0], "right": [2, 0, 0], "forward_hint": [0, 0, 1]},
		{"left": [-2, 0, 2], "right": [2, 0, 2], "forward_hint": [0, 0, 1]},
	]))
	# Reverse move must not cross
	assert(tracker.advance(Vector3(0, 0, 3), Vector3(0, 0, -1)).is_empty())
	# Out of lateral width must not cross
	assert(tracker.advance(Vector3(5, 0, -1), Vector3(5, 0, 3)).is_empty())
	# Out of height tolerance must not cross
	assert(tracker.advance(Vector3(0, 5, -1), Vector3(0, 5, 3)).is_empty())
	# Clean forward crossing through both gates in one step
	var crossed: Array = tracker.advance(Vector3(0, 0, -1), Vector3(0, 0, 3))
	assert(crossed.size() == 2)
	assert(crossed[0].fraction < crossed[1].fraction)
	assert(tracker.next_gate == 2)
	# Repeated move without resetting should produce no new crossings
	assert(tracker.advance(Vector3(0, 0, -1), Vector3(0, 0, 3)).is_empty())

func test_slope_and_camber() -> void:
	var tracker = Tracker.new()
	# Gate on an uphill road (slope: Y increases with Z)
	# left: [-3, 10, 0], right: [3, 10, 0], hint: [0, 1, 1]
	assert(tracker.configure([
		{"left": [-3, 10, 0], "right": [3, 10, 0], "forward_hint": [0, 1, 1], "height_tolerance_m": 2.0}
	]))
	# Car moves along the slope
	var crossed: Array = tracker.advance(Vector3(0, 9, -1), Vector3(0, 11, 1))
	assert(crossed.size() == 1)
	assert(absf(crossed[0].point.y - 10.0) < 0.1)

	# Gate on a cambered road (left higher than right)
	var camber_tracker = Tracker.new()
	assert(camber_tracker.configure([
		{"left": [-3, 2, 0], "right": [3, 0, 0], "forward_hint": [0, 0, 1]}
	]))
	var camber_crossed: Array = camber_tracker.advance(Vector3(0, 1, -1), Vector3(0, 1, 1))
	assert(camber_crossed.size() == 1)

func test_teleport_handling() -> void:
	var tracker = Tracker.new()
	assert(tracker.configure([
		{"left": [-2, 0, 0], "right": [2, 0, 0], "forward_hint": [0, 0, 1]},
		{"left": [-2, 0, 100], "right": [2, 0, 100], "forward_hint": [0, 0, 1]},
	]))
	# Car teleports from 0 to 120 (jump > 45m): must NOT trigger swept crossing
	var crossed: Array = tracker.advance(Vector3(0, 0, -5), Vector3(0, 0, 120))
	assert(crossed.is_empty())
	# Cursor should have snapped to nearest gate (index 1)
	assert(tracker.next_gate == 1)

func test_missed_gate_recovery() -> void:
	var tracker = Tracker.new()
	assert(tracker.configure([
		{"left": [-2, 0, 10], "right": [2, 0, 10], "forward_hint": [0, 0, 1]}, # gate 0
		{"left": [-2, 0, 20], "right": [2, 0, 20], "forward_hint": [0, 0, 1]}, # gate 1 (missed)
		{"left": [-2, 0, 30], "right": [2, 0, 30], "forward_hint": [0, 0, 1]}, # gate 2
	]))
	# Car crosses gate 0 normally
	var c0: Array = tracker.advance(Vector3(0, 0, 5), Vector3(0, 0, 15))
	assert(c0.size() == 1 and c0[0].index == 0)
	assert(tracker.next_gate == 1)

	# Car cuts corner: bypasses gate 1 via X=20, then cuts back and crosses gate 2!
	var c2: Array = tracker.advance(Vector3(0, 0, 25), Vector3(0, 0, 35))
	assert(c2.size() == 1)
	assert(c2[0].index == 2)
	assert(c2[0].has("skipped_indices") and c2[0].skipped_indices == [1])
	assert(tracker.next_gate == 3)

func test_hairpin_neighbor_gates() -> void:
	var tracker = Tracker.new()
	# Two gates physically close (e.g. 10m apart across grass in a hairpin),
	# but gate 0 faces +Z and gate 1 faces -Z
	assert(tracker.configure([
		{"left": [-4, 0, 0], "right": [4, 0, 0], "forward_hint": [0, 0, 1]},
		{"left": [4, 0, 10], "right": [-4, 0, 10], "forward_hint": [0, 0, -1]},
	]))
	# Car approaches gate 0 heading +Z
	var c0 = tracker.advance(Vector3(0, 0, -1), Vector3(0, 0, 2))
	assert(c0.size() == 1 and c0[0].index == 0)
	# Car is in turn, heading towards gate 1 heading -Z
	var c1 = tracker.advance(Vector3(0, 0, 12), Vector3(0, 0, 8))
	assert(c1.size() == 1 and c1[0].index == 1)

func test_plane_contact_and_invalid_config() -> void:
	var tracker = Tracker.new()
	# Invalid configs
	assert(not tracker.configure([]))
	assert(not tracker.configure([{"left": [0, 0]}])) # bad vector
	assert(not tracker.configure([{"left": [0, 0, 0], "right": [0, 0, 0], "forward_hint": [0, 0, 1]}])) # zero length

	# Exact plane contact
	assert(tracker.configure([
		{"left": [-2, 0, 0], "right": [2, 0, 0], "forward_hint": [0, 0, 1]}
	]))
	# Car starting on plane (Z=0) moving forward
	var c = tracker.advance(Vector3(0, 0, 0), Vector3(0, 0, 2))
	assert(c.size() == 1)
