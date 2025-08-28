extends Node

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export_file("*.json") var db_path: String = "res://data/enemies.json"

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var _defs: Dictionary = {}

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	load_db()

# -----------------------------------------------------------------------------
# API
# -----------------------------------------------------------------------------
func load_db() -> void:
	_defs.clear()
	if db_path == "":
		return
	if not FileAccess.file_exists(db_path):
		return
	var f: FileAccess = FileAccess.open(db_path, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if data is Dictionary:
		_defs = data as Dictionary

func reload() -> void:
	load_db()

func get_def(key: String) -> Dictionary:
	if _defs.has(key):
		return _defs[key] as Dictionary
	return {}

func has(key: String) -> bool:
	return _defs.has(key)

func keys() -> Array[String]:
	var out: Array[String] = []
	for k in _defs.keys():
		out.append(String(k))
	return out
