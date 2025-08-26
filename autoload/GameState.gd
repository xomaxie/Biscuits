extends Node
# class_name GameState   # optional if you want typed access elsewhere

signal biscuits_changed(new_total:int, delta:int)
signal phase_changed(new_phase:int)
signal wave_changed(new_wave:int)
signal run_started()
signal run_ended(victory:bool)
signal upgrades_changed()

enum Phase { PREP, WAVE, GAME_OVER }

@export var starting_biscuits:int = 0

var biscuits:int = 0
var wave:int = 1
var phase:int = Phase.PREP
var upgrades:Dictionary = {}  # e.g. {"damage":1, "firerate":0}

# --- Engine-facing/internal stat names used everywhere in gameplay math ---
const STAT_BASE := {
	"move_speed": 230.0,
	"damage_mult": 1.0,
	"fire_rate_mult": 1.0,   # >1 = faster
	"range_add": 0.0,
	"pickup_radius_add": 0.0,
	"projectiles_add": 0.0,
	"spread_deg_add": 0.0,
}

# Map user-facing keys (Shop/UI) to internal stat names
const FRIENDLY_TO_INTERNAL := {
	"damage":      "damage_mult",         # multiplier (>=1.0)
	"firerate":    "fire_rate_mult",      # multiplier (>=1.0)
	"range":       "range_add",           # +pixels
	"pickup":      "pickup_radius_add",   # +pixels
	"projectiles": "projectiles_add",     # +count
	"movespeed":   "move_speed",          # absolute px/s
	"spread":      "spread_deg_add"       # +deg
}

func _ready() -> void:
	reset_to_defaults()

func reset_to_defaults() -> void:
	biscuits = starting_biscuits
	wave = 1
	phase = Phase.PREP
	upgrades.clear()
	emit_signal("upgrades_changed")

func start_run() -> void:
	reset_to_defaults()
	emit_signal("run_started")
	emit_signal("biscuits_changed", biscuits, 0)
	emit_signal("wave_changed", wave)
	emit_signal("phase_changed", phase)

func end_run(victory:bool) -> void:
	phase = Phase.GAME_OVER
	emit_signal("phase_changed", phase)
	emit_signal("run_ended", victory)

func set_phase(new_phase:int) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	emit_signal("phase_changed", phase)

func next_wave() -> void:
	wave += 1
	emit_signal("wave_changed", wave)

func add_biscuits(amount:int) -> void:
	if amount == 0:
		return
	biscuits += amount
	emit_signal("biscuits_changed", biscuits, amount)

func spend_biscuits(amount:int) -> bool:
	if biscuits < amount:
		return false
	biscuits -= amount
	emit_signal("biscuits_changed", biscuits, -amount)
	return true

func set_upgrade(name:String, level:int) -> void:
	upgrades[name] = level
	emit_signal("upgrades_changed")

func get_upgrade(name:String, default_level:int=0) -> int:
	return int(upgrades.get(name, default_level))

# ---------- Stats helpers (read-only during play) ----------

# Internal: compute an engine-facing stat by name in STAT_BASE using UpgradeDB data
func _compute_internal_stat(stat_name:String) -> float:
	if not STAT_BASE.has(stat_name):
		return 0.0

	var val: float = float(STAT_BASE[stat_name])

	# --- Additive effects (including additive side-effects) ---
	for key in upgrades.keys():
		var lvl: int = int(upgrades[key])
		if lvl <= 0 or not UpgradeDB.has(key):
			continue
		var def: Resource = UpgradeDB.get_def(key)
		if def == null:
			continue

		var def_stat = def.get("stat")
		var def_type = def.get("type")
		var per_level = def.get("per_level")

		if String(def_stat) == stat_name and String(def_type) == "add":
			val += float(per_level) * float(lvl)

		var side_effects = def.get("side_effects")
		if typeof(side_effects) == TYPE_ARRAY:
			for se in side_effects:
				var se_type = se.get("type", "")
				var se_stat = se.get("stat", "")
				var se_val  = se.get("value", 0.0)
				if String(se_type) == "add" and String(se_stat) == stat_name:
					val += float(se_val) * float(lvl)

	# --- Multiplicative effects (including multiplicative side-effects) ---
	var mul: float = 1.0
	for key2 in upgrades.keys():
		var lvl2: int = int(upgrades[key2])
		if lvl2 <= 0 or not UpgradeDB.has(key2):
			continue
		var def2: Resource = UpgradeDB.get_def(key2)
		if def2 == null:
			continue

		var def2_stat = def2.get("stat")
		var def2_type = def2.get("type")
		var per2 = def2.get("per_level")

		if String(def2_stat) == stat_name and String(def2_type) == "mul":
			mul *= pow(1.0 + float(per2), float(lvl2))

		var side2 = def2.get("side_effects")
		if typeof(side2) == TYPE_ARRAY:
			for se2 in side2:
				var se2_type = se2.get("type", "")
				var se2_stat = se2.get("stat", "")
				var se2_val  = se2.get("value", 0.0)
				if String(se2_type) == "mul" and String(se2_stat) == stat_name:
					mul *= pow(1.0 + float(se2_val), float(lvl2))

	return val * mul

func get_stat(stat_name:String) -> float:
	if STAT_BASE.has(stat_name):
		return _compute_internal_stat(stat_name)

	if FRIENDLY_TO_INTERNAL.has(stat_name):
		var internal_name: String = FRIENDLY_TO_INTERNAL[stat_name]
		var v: float = _compute_internal_stat(internal_name)
		# Projectiles should be whole numbers for most uses
		if stat_name == "projectiles":
			return float(round(v))
		return v

	return 0.0

# Dump a dictionary of current, player-facing stats for UI (Shop stats card)
func get_all_stats() -> Dictionary:
	return {
		"movespeed":   get_stat("movespeed"),                    # px/s
		"damage":      get_stat("damage"),                       # multiplier
		"firerate":    get_stat("firerate"),                     # multiplier
		"range":       get_stat("range"),                        # +px
		"pickup":      get_stat("pickup"),                       # +px
		"projectiles": int(round(get_stat("projectiles"))),      # count
		"spread":      get_stat("spread")                        # +deg
	}

# Helper to compute effective weapon values from base exports (use in Weapon.gd)
func get_effective_weapon_values(base_fire_rate:float, base_range:float, base_damage:int, base_projectiles:int, base_spread:float) -> Dictionary:
	var fire_rate_mult:float   = get_stat("fire_rate_mult")
	var range_add:float        = get_stat("range_add")
	var damage_mult:float      = get_stat("damage_mult")
	var proj_add:int           = int(round(get_stat("projectiles_add")))
	var spread_add:float       = get_stat("spread_deg_add")

	return {
		"fire_rate": max(0.05, base_fire_rate * fire_rate_mult),
		"range": base_range + range_add,
		"damage": int(max(1, round(float(base_damage) * damage_mult))),
		"projectiles": max(1, base_projectiles + proj_add),
		"spread": max(0.0, base_spread + spread_add),
	}

# Price scaling for an upgrade's next level (delegates to UpgradeDB)
func get_upgrade_cost(upgrade_key:String) -> int:
	var lvl:int = get_upgrade(upgrade_key, 0)
	return UpgradeDB.compute_cost_next_level(upgrade_key, lvl)

func can_level(upgrade_key:String) -> bool:
	if not UpgradeDB.has(upgrade_key):
		return false
	var def: Resource = UpgradeDB.get_def(upgrade_key)
	if def == null:
		return false
	var max_level = def.get("max_level")
	if typeof(max_level) == TYPE_NIL:
		# if not specified, assume infinite—treat as true
		return true
	var lvl:int = get_upgrade(upgrade_key, 0)
	return lvl < int(max_level)
