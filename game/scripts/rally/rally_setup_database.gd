class_name RallySetupDatabase
extends RefCounted

const DATABASE_PATH := "user://open_formula.db"
const DATABASE_VERSION := 2
const PHYSICS_BACKEND := "gdscript_jolt"

var _database: Variant
var _extension: Resource
var _last_error: String = ""


func open_database() -> Dictionary:
	if _database != null:
		return {"ok": true}
	if not ClassDB.class_exists("SQLite"):
		_extension = load("res://addons/godot-sqlite/gdsqlite.gdextension")
	if not ClassDB.class_exists("SQLite"):
		_last_error = "La extension SQLite no se cargo."
		return {"ok": false, "error": _last_error}
	_database = ClassDB.instantiate("SQLite")
	_database.path = DATABASE_PATH
	_database.foreign_keys = true
	_database.verbosity_level = 0
	if not bool(_database.open_db()):
		_last_error = str(_database.error_message)
		_database = null
		return {"ok": false, "error": _last_error}
	if not _exec("PRAGMA foreign_keys=ON") or not _exec("PRAGMA synchronous=FULL"):
		return _fail_open()
	var version_query := _query("PRAGMA user_version")
	if not bool(version_query.get("ok", false)):
		return _fail_open()
	var version_rows: Array = version_query.get("rows", [])
	var version := int(version_rows[0].get("user_version", 0)) if not version_rows.is_empty() else 0
	if version > DATABASE_VERSION:
		_last_error = "La base de datos pertenece a una version mas reciente del simulador."
		return _fail_open()
	if version == 1:
		if not _migrate_v1_to_v2():
			return _fail_open()
	elif version == 0:
		if not _create_schema():
			return _fail_open()
	if not _exec("INSERT OR IGNORE INTO circuit(id,name,country,length_m) VALUES('rally-proving-ground','Campo de pruebas','N/A',200.0)"):
		return _fail_open()
	if not _exec("INSERT OR IGNORE INTO circuit(id,name,country,length_m) VALUES('russia-stage-1','Rusia Stage 1','Russia',5500.0)"):
		return _fail_open()
	if not _exec("INSERT OR IGNORE INTO team(id,name) VALUES('ford-rally-works','Ford Rally Works')"):
		return _fail_open()
	return {"ok": true, "path": DATABASE_PATH, "version": DATABASE_VERSION}


func list_setups(context: Dictionary) -> Dictionary:
	var result := _query(
		"SELECT id,name,team_id,created_at,modified_at FROM car_setup WHERE circuit_id=? AND car_id=? AND physics_backend=? AND base_profile_sha256=? AND mode=? ORDER BY modified_at DESC,id DESC",
		[context.circuit_id, context.car_id, context.physics_backend, context.base_profile_sha256, context.mode]
	)
	return result


func create_setup(context: Dictionary, name: String, values: Dictionary) -> Dictionary:
	var result := _query(
		"INSERT INTO car_setup(name,circuit_id,team_id,car_id,physics_backend,base_profile_sha256,mode,values_json) VALUES(?,?,?,?,?,?,?,?)",
		[name.strip_edges(), context.circuit_id, context.team_id, context.car_id, context.physics_backend, context.base_profile_sha256, context.mode, JSON.stringify(values)]
	)
	if not bool(result.get("ok", false)):
		return result
	return {"ok": true, "id": int(_database.last_insert_rowid)}


func update_setup(context: Dictionary, setup_id: int, name: String, values: Dictionary) -> Dictionary:
	var result := _query(
		"UPDATE car_setup SET name=?,values_json=?,modified_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=? AND circuit_id=? AND car_id=? AND physics_backend=? AND base_profile_sha256=? AND mode=? AND schema_version=1",
		[name.strip_edges(), JSON.stringify(values), setup_id, context.circuit_id, context.car_id, context.physics_backend, context.base_profile_sha256, context.mode]
	)
	if not bool(result.get("ok", false)):
		return result
	var changes := _query("SELECT changes() AS affected")
	if not bool(changes.get("ok", false)) or changes.rows.is_empty() or int(changes.rows[0].get("affected", 0)) != 1:
		return {"ok": false, "error": "El reglaje ya no existe o no corresponde al perfil activo."}
	return {"ok": true}


func load_setup(context: Dictionary, setup_id: int) -> Dictionary:
	var result := _query(
		"SELECT name,values_json,car_id,physics_backend,base_profile_sha256,schema_version,mode FROM car_setup WHERE id=? AND circuit_id=?",
		[setup_id, context.circuit_id]
	)
	if not bool(result.get("ok", false)):
		return result
	var rows: Array = result.get("rows", [])
	if rows.is_empty():
		return {"ok": false, "error": "El reglaje ya no existe en este circuito."}
	var row: Dictionary = rows[0]
	if str(row.get("car_id", "")) != str(context.car_id) \
		or str(row.get("physics_backend", "")) != str(context.physics_backend) \
		or str(row.get("base_profile_sha256", "")) != str(context.base_profile_sha256) \
		or int(row.get("schema_version", 0)) != 1 \
		or str(row.get("mode", "")) != str(context.mode):
		return {"ok": false, "error": "El reglaje no coincide con el coche, modo o perfil actual."}
	var parser := JSON.new()
	if parser.parse(str(row.get("values_json", ""))) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "El contenido guardado del reglaje no es valido."}
	return {"ok": true, "name": str(row.get("name", "")), "values": parser.data}


func delete_setup(context: Dictionary, setup_id: int) -> Dictionary:
	var result := _query(
		"DELETE FROM car_setup WHERE id=? AND circuit_id=? AND car_id=? AND physics_backend=? AND base_profile_sha256=? AND mode=?",
		[setup_id, context.circuit_id, context.car_id, context.physics_backend, context.base_profile_sha256, context.mode]
	)
	if not bool(result.get("ok", false)):
		return result
	var changes := _query("SELECT changes() AS affected")
	if not bool(changes.get("ok", false)) or changes.rows.is_empty() or int(changes.rows[0].get("affected", 0)) != 1:
		return {"ok": false, "error": "El reglaje no existe o no corresponde al circuito actual."}
	return {"ok": true}


func close_database() -> void:
	if _database != null:
		_database.close_db()
		_database = null


func _create_schema() -> bool:
	var statements := [
		"BEGIN IMMEDIATE",
		"CREATE TABLE circuit(id TEXT PRIMARY KEY,name TEXT NOT NULL,country TEXT NOT NULL,length_m REAL NOT NULL CHECK(length_m>0))",
		"CREATE TABLE team(id TEXT PRIMARY KEY,name TEXT NOT NULL)",
		"CREATE TABLE car_setup(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),circuit_id TEXT NOT NULL REFERENCES circuit(id),team_id TEXT NOT NULL REFERENCES team(id),car_id TEXT NOT NULL,physics_backend TEXT NOT NULL,base_profile_sha256 TEXT NOT NULL,mode TEXT NOT NULL CHECK(mode IN ('rally','gp')),schema_version INTEGER NOT NULL DEFAULT 1 CHECK(schema_version=1),values_json TEXT NOT NULL CHECK(json_valid(values_json) AND json_type(values_json)='object' AND length(values_json)<=65536),created_at TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%fZ','now')),modified_at TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%fZ','now')),UNIQUE(circuit_id,car_id,mode,name COLLATE NOCASE))",
		"CREATE INDEX car_setup_circuit_date ON car_setup(circuit_id,mode,modified_at DESC,id DESC)",
		"PRAGMA user_version=2",
		"COMMIT",
	]
	for statement in statements:
		if not _exec(statement):
			_exec("ROLLBACK")
			return false
	return true


func _migrate_v1_to_v2() -> bool:
	var statements := [
		"BEGIN IMMEDIATE",
		"ALTER TABLE car_setup RENAME TO car_setup_v1",
		"CREATE TABLE car_setup(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),circuit_id TEXT NOT NULL REFERENCES circuit(id),team_id TEXT NOT NULL REFERENCES team(id),car_id TEXT NOT NULL,physics_backend TEXT NOT NULL,base_profile_sha256 TEXT NOT NULL,mode TEXT NOT NULL DEFAULT 'gp' CHECK(mode IN ('rally','gp')),schema_version INTEGER NOT NULL DEFAULT 1 CHECK(schema_version=1),values_json TEXT NOT NULL CHECK(json_valid(values_json) AND json_type(values_json)='object' AND length(values_json)<=65536),created_at TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%fZ','now')),modified_at TEXT NOT NULL DEFAULT(strftime('%Y-%m-%dT%H:%M:%fZ','now')),UNIQUE(circuit_id,car_id,mode,name COLLATE NOCASE))",
		"INSERT INTO car_setup(id,name,circuit_id,team_id,car_id,physics_backend,base_profile_sha256,schema_version,values_json,created_at,modified_at,mode) SELECT id,name,circuit_id,team_id,car_id,physics_backend,base_profile_sha256,schema_version,values_json,created_at,modified_at,'gp' FROM car_setup_v1",
		"DROP TABLE car_setup_v1",
		"DROP INDEX IF EXISTS car_setup_circuit_date",
		"CREATE INDEX car_setup_circuit_date ON car_setup(circuit_id,mode,modified_at DESC,id DESC)",
		"PRAGMA user_version=2",
		"COMMIT",
	]
	for statement in statements:
		if not _exec(statement):
			_exec("ROLLBACK")
			return false
	return true


func _exec(statement: String) -> bool:
	return bool(_query(statement).get("ok", false))


func _query(statement: String, bindings: Array = []) -> Dictionary:
	if _database == null:
		return {"ok": false, "error": "La base de datos no esta abierta."}
	var succeeded: bool = _database.query_with_bindings(statement, bindings) if not bindings.is_empty() else _database.query(statement)
	if not succeeded:
		_last_error = str(_database.error_message)
		return {"ok": false, "error": _last_error}
	var rows: Array = _database.query_result.duplicate(true)
	return {"ok": true, "rows": rows}


func _fail_open() -> Dictionary:
	var message := _last_error if not _last_error.is_empty() else str(_database.error_message)
	close_database()
	return {"ok": false, "error": message}
