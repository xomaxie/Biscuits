# res://data/upgrades/upgrade_db.gd
extends Node

signal db_ready

@export var upgrades_folder: String = "res://data/upgrades"  # optional scan folder

# Explicit preloads force the exporter (incl. HTML5) to pack these resources.
const REG := {
	"damage":      preload("res://data/upgrades/damage.tres"),
	"firerate":    preload("res://data/upgrades/firerate.tres"),
	"range":       preload("res://data/upgrades/range.tres"),
	"pickup":      preload("res://data/upgrades/pickup.tres"),
	"projectiles": preload("res://data/upgrades/projectiles.tres"),
	"movespeed":   preload("res://data/upgrades/movespeed.tres"),
}

var _defs_by_key: Dictionary = {}         # key: String -> Resource
var _keys_sorted: Array[String] = []
var _is_ready: bool = false

func _ready() -> void:
	_load_all()

func is_ready() -> bool:
	return _is_ready

func _load_all() -> void:
	_defs_by_key.clear()
	_keys_sorted.clear()

	# 1) Register preloaded resources first (works on HTML5)
	for k in REG.keys():
		var r: Resource = REG[k]
		if r != null:
			_defs_by_key[k] = r

	# 2) OPTIONAL: scan folder to include any additional .tres
	#    (on HTML5 this only works if those files are packed in the export)
	var dir := DirAccess.open(upgrades_folder)
	if dir != null:
		dir.list_dir_begin()
		while true:
			var f := dir.get_next()
			if f == "":
				break
			if dir.current_is_dir():
				continue
			if not f.ends_with(".tres"):
				continue

			var path := upgrades_folder.path_join(f)
			var res: Resource = ResourceLoader.load(path)
			if res == null:
				push_warning("UpgradeDB: failed to load %s" % path)
				continue

			# Expect each .tres to have an exported 'key' property
			var k2_val: Variant = res.get("key")   # explicit type avoids Variant inference warning
			if typeof(k2_val) == TYPE_NIL or String(k2_val).is_empty():
				push_warning("UpgradeDB: resource missing/empty 'key' at %s" % path)
				continue

			var k2: String = String(k2_val)
			_defs_by_key[k2] = res
		dir.list_dir_end()
	else:
		# Not fatal on HTML5, we still have preloads
		if OS.has_feature("web"):
			print("UpgradeDB: (web) DirAccess scan unavailable; using preloads only")

	# 3) Build sorted key list (by 'order' then name)
	var pairs: Array[Dictionary] = []
	for kk in _defs_by_key.keys():
		var d: Resource = _defs_by_key[kk]
		var ord_i: int = 0
		var ord_val: Variant = d.get("order")
		if typeof(ord_val) != TYPE_NIL:
			ord_i = int(ord_val)
		pairs.append({ "key": String(kk), "order": ord_i })

	pairs.sort_custom(func(a, b):
		var ao: int = int(a["order"])
		var bo: int = int(b["order"])
		return String(a["key"]) < String(b["key"]) if ao == bo else ao < bo
	)

	for p in pairs:
		_keys_sorted.append(String(p["key"]))

	_is_ready = true
	emit_signal("db_ready")

func has(key: String) -> bool:
	return _defs_by_key.has(key)

func get_def(key: String) -> Resource:
	return _defs_by_key.get(key, null)

func keys_sorted() -> Array[String]:
	return _keys_sorted.duplicate()

func compute_cost_next_level(key: String, current_level: int) -> int:
	var def: Resource = get_def(key)
	if def == null:
		return 9999
	var cost_base: Variant = def.get("cost_base")
	if typeof(cost_base) == TYPE_NIL:
		return 9999
	var next_level := current_level + 1
	var cost := float(cost_base) * (1.0 + 0.2 * float(next_level - 1))
	return int(ceil(cost))
