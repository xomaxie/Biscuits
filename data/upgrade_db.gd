extends Node

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------
signal db_ready

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export_file("*.json") var upgrades_json_path: String = "res://data/upgrades/upgrades.json"

# -----------------------------------------------------------------------------
# Public accessors
# -----------------------------------------------------------------------------
var is_loaded: bool = false
var version: int = 1

# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------
var _by_key: Dictionary = {}
var _keys_sorted: Array[String] = []
var _by_type: Dictionary = { "item": [], "weapon": [] }

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_reload()

func _reload() -> void:
	is_loaded = false
	_by_key.clear()
	_keys_sorted.clear()
	_by_type = { "item": [], "weapon": [] }

	var text := ""
	var ok := true
	if not FileAccess.file_exists(upgrades_json_path):
		push_error("[UpgradeDB] JSON not found at: %s" % upgrades_json_path)
		ok = false
	else:
		text = FileAccess.get_file_as_string(upgrades_json_path)

	if ok:
		var root_v: Variant = JSON.parse_string(text)
		if typeof(root_v) != TYPE_DICTIONARY:
			push_error("[UpgradeDB] JSON root must be a Dictionary.")
			ok = false
		else:
			var root: Dictionary = root_v
			version = int(root.get("version", 1))

			var entries: Array = []
			entries.append_array(root.get("items", []))
			entries.append_array(root.get("weapons", []))

			for e_v in entries:
				if typeof(e_v) != TYPE_DICTIONARY:
					continue
				var e: Dictionary = e_v
				var key_s := String(e.get("key", ""))
				if key_s.is_empty():
					push_warning("[UpgradeDB] Skipping entry with empty key.")
					continue
				e["name"] = String(e.get("name", key_s.capitalize()))
				e["type"] = String(e.get("type", "item"))
				e["rarity"] = String(e.get("rarity", "common"))
				e["order"] = int(e.get("order", 0))
				e["cost_base"] = int(e.get("cost_base", 20))
				e["tags"] = e.get("tags", [])
				e["desc"] = String(e.get("desc", ""))

				_by_key[key_s] = e
				if not _by_type.has(e["type"]):
					_by_type[e["type"]] = []
				_by_type[e["type"]].append(key_s)

			var pairs: Array[Dictionary] = []
			for k in _by_key.keys():
				var d: Dictionary = _by_key[k]
				pairs.append({
					"key": String(k),
					"order": int(d.get("order", 0)),
					"name": String(d.get("name", k))
				})
			pairs.sort_custom(func(a, b):
				var ao: int = int(a["order"])
				var bo: int = int(b["order"])
				if ao == bo:
					return String(a["name"]) < String(b["name"])
				return ao < bo
			)
			for p in pairs:
				_keys_sorted.append(String(p["key"]))

	is_loaded = ok
	if is_loaded:
		emit_signal("db_ready")

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------
func is_ready() -> bool:
	return is_loaded

func get_entry(key: String) -> Dictionary:
	return _by_key.get(key, {})

func has(key: String) -> bool:
	return _by_key.has(key)

func keys_sorted(of_type: String = "") -> Array[String]:
	if of_type == "" or not _by_type.has(of_type):
		return _keys_sorted.duplicate()
	return (_by_type[of_type] as Array).duplicate()

func compute_cost_next_level(key: String, current_level: int) -> int:
	var e: Dictionary = get_entry(key)
	if e.is_empty():
		return 9999
	var base_cost := float(e.get("cost_base", 20))
	var next_level := current_level + 1
	var cost := base_cost * (1.0 + 0.2 * float(next_level - 1))
	return int(ceil(cost))

func roll_offers(count: int, rng: RandomNumberGenerator, allowed_types: Array[String] = [], allowed_rarities: Array[String] = []) -> Array[String]:
	var pool: Array[String] = []
	if allowed_types.is_empty():
		pool = _keys_sorted.duplicate()
	else:
		for t in allowed_types:
			if _by_type.has(t):
				pool.append_array(_by_type[t])

	if not allowed_rarities.is_empty():
		var f: Array[String] = []
		for k in pool:
			var r: String = String(_by_key[k].get("rarity", "common"))
			if r in allowed_rarities:
				f.append(k)
		pool = f

	var offers: Array[String] = []
	var pool_copy := pool.duplicate()
	while offers.size() < count and pool_copy.size() > 0:
		var idx := rng.randi_range(0, pool_copy.size() - 1)
		offers.append(pool_copy[idx])
		pool_copy.remove_at(idx)
	return offers

func reload_from_disk() -> void:
	_reload()
