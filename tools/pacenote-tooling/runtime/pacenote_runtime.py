"""Convert route-calibrated curve authoring to Godot CMR2 runtime data."""
import bisect
import math


def convert_notes(authoring, route, track_id):
    points = route["points"]
    if len(points) < 2 or any(len(p) != 3 or not all(math.isfinite(v) for v in p) for p in points):
        raise ValueError("Invalid route points")
    distances = [0.0]
    for a, b in zip(points, points[1:]):
        length = math.dist(a, b)
        if length < 0.001:
            raise ValueError("Degenerate route segment")
        distances.append(distances[-1] + length)
    curves = sorted(authoring["curves"], key=lambda c: c["call_index"])
    if [c["call_index"] for c in curves] != list(range(len(curves))) or not curves:
        raise ValueError("Call indices must be unique and contiguous")
    gates, calls = [], []
    previous_distance = -1.0
    for curve in curves:
        word = int(curve["call_word_hex"], 16)
        if not 0 < word <= 0xffffffff:
            raise ValueError("Invalid CMR2 word")
        entry = float(curve["route_distance_m"])
        if "advisory_gate_node" in curve:
            node = int(curve["advisory_gate_node"])
            if not 0 <= node < len(points):
                raise ValueError("Advisory node outside route")
            distance = distances[node]
        else:
            distance = max(0.0, entry - float(curve.get("lead_distance_m", 50.0)))
        if not previous_distance < distance <= distances[-1] or distance > entry + 1.0:
            raise ValueError("Advisories must be ordered, unique and precede curve entry")
        segment = min(len(points) - 2, max(0, bisect.bisect_right(distances, distance) - 1))
        a, b = points[segment:segment + 2]
        direction = [(y - x) / math.dist(a, b) for x, y in zip(a, b)]
        horizontal = math.hypot(direction[0], direction[2])
        if horizontal < 0.001:
            raise ValueError("Vertical route segment")
        lateral = [-direction[2] / horizontal, 0.0, direction[0] / horizontal]
        fraction = (distance - distances[segment]) / (distances[segment + 1] - distances[segment])
        center = [x + fraction * (y - x) for x, y in zip(a, b)]
        index = len(calls)
        gates.append({"id": f"{track_id}_CALL_{index:03d}",
                      "left": [x - 6.0 * v for x, v in zip(center, lateral)],
                      "right": [x + 6.0 * v for x, v in zip(center, lateral)],
                      "forward_hint": direction, "height_tolerance_m": 3.5,
                      "route_segment": segment, "route_distance_m": distance,
                      "lead_distance_m": max(0.0, entry - distance),
                      "curve_id": curve["curve_id"], "call_index": index})
        calls.append(word)
        previous_distance = distance
    return {"stage_id": track_id, "route_point_count": len(points),
            "total_distance_m": distances[-1], "calls": calls, "gates": gates,
            "conversion": {"version": 1, "gate_width_m": 12.0, "height_tolerance_m": 3.5}}
