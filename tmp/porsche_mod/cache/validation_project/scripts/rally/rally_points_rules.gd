class_name RallyPointsRules
extends RefCounted
## Cálculo puro y versionado de puntos. Sin dependencias de presentación.
## Perfil de referencia: WRC 2026 (arts. 3.3 y 50), simplificado como juego.

const PROFILE_ID := "wrc_2026_v1"
const GENERAL_POINTS := [25, 17, 15, 12, 10, 8, 6, 4, 2, 1]
const SUNDAY_POINTS := [5, 4, 3, 2, 1]
const POWER_POINTS := [5, 4, 3, 2, 1]
const MAX_PER_EVENT := 35

static func general_points_for_position(position: int) -> int:
	if position < 1 or position > GENERAL_POINTS.size():
		return 0
	return GENERAL_POINTS[position - 1]

static func sunday_points_for_position(position: int) -> int:
	if position < 1 or position > SUNDAY_POINTS.size():
		return 0
	return SUNDAY_POINTS[position - 1]

static func power_points_for_position(position: int) -> int:
	if position < 1 or position > POWER_POINTS.size():
		return 0
	return POWER_POINTS[position - 1]

## Ordena clasificados por total general; desempata por Stage1, Stage2...
## Los empatados comparten puntos y se saltan las posiciones ocupadas.
static func rank(classified_rows: Array, stage_order: Array) -> Array:
	var rows := classified_rows.duplicate(true)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("grand_total_ms", 0)) != int(b.get("grand_total_ms", 0)):
			return int(a.get("grand_total_ms", 0)) < int(b.get("grand_total_ms", 0))
		for stage_id in stage_order:
			var ta: int = int((a.get("stage_totals", {}) as Dictionary).get(stage_id, 9223372036854775807))
			var tb: int = int((b.get("stage_totals", {}) as Dictionary).get(stage_id, 9223372036854775807))
			if ta != tb:
				return ta < tb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	var ranked: Array = []
	var position := 0
	var previous_key := ""
	var previous_position := 0
	for row in rows:
		position += 1
		var key := "%d" % int(row.get("grand_total_ms", 0))
		for stage_id in stage_order:
			key += "|%d" % int((row.get("stage_totals", {}) as Dictionary).get(stage_id, -1))
		if key == previous_key:
			row["position"] = previous_position
		else:
			row["position"] = position
			previous_position = position
			previous_key = key
		ranked.append(row)
	return ranked

static func award(points_table: Array, position: int) -> int:
	if position < 1 or position > points_table.size():
		return 0
	return int(points_table[position - 1])

static func ledger_key(event_id: String, participant_id: String, category: String) -> String:
	return "%s/%s/%s" % [event_id, participant_id, category]
