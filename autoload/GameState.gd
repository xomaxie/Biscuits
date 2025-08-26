extends Node
# class_name GameState   # optional if you want typed access elsewhere

signal biscuits_changed(new_total:int, delta:int)
signal phase_changed(new_phase:int)
signal wave_changed(new_wave:int)
signal run_started()
signal run_ended(victory:bool)
signal upgrades_changed()                       # fired when owned item counts change
signal weapon_purchased(key:String, data:Dictionary)  # fired when a weapon is bought

enum Phase { PREP, WAVE, GAME_OVER }

@export var starting_biscuits:int = 0

var biscuits:int = 0
var wave:int = 1
var phase:int = Phase.PREP

# Items are stackable (count). Weapons are a list (non-stacking by default).
var _owned_items:Dictionary = {}     # key:String -> count:int
var _owned_weapons:Array[String] = []

# --- Engine-facing/internal stat names used everywhere in gameplay math ---
const STAT_BASE := {
	"move_speed": 230.0,      # absolute px/s
	"damage_mult": 1.0,       # multiplier (>=1.0)
	"fire_rate_mult": 1.0,    # multiplier (>=1.0); >1 = faster
	"range_add": 0.0,         # +px
	"pickup_radius_add": 0.0, # +px
	"projectiles_add": 0.0,   # +count
	"spread_deg_add": 0.0,    # +deg

	# Extended core & meta stats (default bases)
	"max_hp": 0.0,
	"hp_regen": 0.0,
	"lifesteal_pct": 0.0,
	"armor": 0.0,
	"dodge_pct": 0.0,
	"luck": 0.0,
	"harvesting": 0.0,
	"crate_bonus_biscuits": 0.0,

	# Multipliers stored separately but cached here after recompute (as products)
	"shop_price_mult": 1.0,       # derived from shop_price_pct
	"enemy_hp_mult": 1.0,         # derived from enemy_hp_pct
	"explosion_damage_mult": 1.0, # derived from explosion_damage_pct

	# Weapon-feel adders
	"pierce_add": 0.0,
	"knockback_add": 0.0,

	# Time-based ramp config accumulator (read by EffectsManager, etc.)
	"ramp_damage_pct_per_5s": 0.0
}

# Map user-facing keys (Shop/UI) to internal stat names
const FRIENDLY_TO_INTERNAL := {
	"damage":      "damage_mult",         # multiplier
	"firerate":    "fire_rate_mult",      # multiplier
	"range":       "range_add",           # +px
	"pickup":      "pickup_radius_add",   # +px
	"projectiles": "projectiles_add",     # +count
	"movespeed":   "move_speed",          # absolute px/s
	"spread":      "spread_deg_add"       # +deg
}

# Cached computed stats after applying items
var _cached_stats:Dictionary = {}

# Autoload instance (JSON DB)
@onready var DB: Node = get_node("/root/UpgradeDB")

func _ready() -> void:
	reset_to_defaults()
	if DB.is_ready():
		_recompute_cache()
		emit_signal("upgrades_changed")
	else:
		DB.db_ready.connect(_on_db_ready)

func _on_db_ready() -> void:
	_recompute_cache()
	emit_signal("upgrades_changed")

# -----------------------------------------------------------------------------
# Run lifecycle
# -----------------------------------------------------------------------------
func reset_to_defaults() -> void:
	biscuits = starting_biscuits
	wave = 1
	phase = Phase.PREP
	_owned_items.clear()
	_owned_weapons.clear()
	_recompute_cache()
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

# -----------------------------------------------------------------------------
# Currency
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Shop / Ownership
# -----------------------------------------------------------------------------
func get_item_count(key:String) -> int:
	return int(_owned_items.get(key, 0))

func has_weapon(key:String) -> bool:
	return _owned_weapons.has(key)

func get_owned_weapons() -> Array[String]:
	return _owned_weapons.duplicate()

# Compatibility with older ShopUI code:
func get_upgrade(name:String, default_level:int=0) -> int:
	return int(_owned_items.get(name, default_level))

func set_upgrade(name:String, level:int) -> void:
	var clamped: int = max(0, level)
	var prev: int = int(_owned_items.get(name, 0))
	_owned_items[name] = clamped
	if clamped != prev:
		_recompute_cache()
		emit_signal("upgrades_changed")

# Preferred new API used by JSON system:
# Returns true on success (biscuits spent + granted).
func buy_entry(key:String, current_level:int=0) -> bool:
	if not DB.is_ready():
		return false
	if not DB.has(key):
		return false

	var price:int = DB.compute_cost_next_level(key, current_level)
	# NOTE: If you implement shop price discounts globally, you can multiply here:
	# price = int(round(price * get_shop_price_mult()))
	if not spend_biscuits(price):
		return false

	var e:Dictionary = DB.get_entry(key)
	var typ:String = String(e.get("type", "item"))

	if typ == "weapon":
		_owned_weapons.append(key)
		emit_signal("weapon_purchased", key, e)
	else:
		var prev:int = int(_owned_items.get(key, 0))
		_owned_items[key] = prev + 1
		_recompute_cache()
		emit_signal("upgrades_changed")

	return true

# -----------------------------------------------------------------------------
# Stat Computation
# -----------------------------------------------------------------------------
func _apply_effect(effect:Dictionary, add_accum:Dictionary, mul_accum:Dictionary) -> void:
	var stat:String = String(effect.get("stat", ""))

	if stat == "attack_speed_pct":
		mul_accum["fire_rate_mult"] = float(mul_accum.get("fire_rate_mult", 1.0)) * (1.0 + float(effect.get("add", 0.0)) / 100.0)
	elif stat == "damage_pct":
		mul_accum["damage_mult"] = float(mul_accum.get("damage_mult", 1.0)) * (1.0 + float(effect.get("add", 0.0)) / 100.0)
	elif stat == "speed_pct":
		mul_accum["move_speed"] = float(mul_accum.get("move_speed", 1.0)) * (1.0 + float(effect.get("add", 0.0)) / 100.0)
	elif stat == "shop_price_pct":
		mul_accum["shop_price_mult"] = float(mul_accum.get("shop_price_mult", 1.0)) * (1.0 + float(effect.get("add", 0.0)) / 100.0)
	elif stat == "enemy_hp_pct":
		mul_accum["enemy_hp_mult"] = float(mul_accum.get("enemy_hp_mult", 1.0)) * (1.0 + float(effect.get("add", 0.0)) / 100.0)
	elif stat == "explosion_damage_pct":
		mul_accum["explosion_damage_mult"] = float(mul_accum.get("explosion_damage_mult", 1.0)) * (1.0 + float(effect.get("add", 0.0)) / 100.0)

	elif stat == "range":
		add_accum["range_add"] = float(add_accum.get("range_add", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "pickup_radius_add":
		add_accum["pickup_radius_add"] = float(add_accum.get("pickup_radius_add", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "projectiles_add":
		add_accum["projectiles_add"] = float(add_accum.get("projectiles_add", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "spread_deg_add":
		add_accum["spread_deg_add"] = float(add_accum.get("spread_deg_add", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "max_hp":
		add_accum["max_hp"] = float(add_accum.get("max_hp", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "hp_regen":
		add_accum["hp_regen"] = float(add_accum.get("hp_regen", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "lifesteal_pct":
		add_accum["lifesteal_pct"] = float(add_accum.get("lifesteal_pct", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "armor":
		add_accum["armor"] = float(add_accum.get("armor", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "dodge_pct":
		add_accum["dodge_pct"] = float(add_accum.get("dodge_pct", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "luck":
		add_accum["luck"] = float(add_accum.get("luck", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "harvesting":
		add_accum["harvesting"] = float(add_accum.get("harvesting", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "crate_bonus_biscuits":
		add_accum["crate_bonus_biscuits"] = float(add_accum.get("crate_bonus_biscuits", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "projectile_pierce":
		add_accum["pierce_add"] = float(add_accum.get("pierce_add", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "knockback":
		add_accum["knockback_add"] = float(add_accum.get("knockback_add", 0.0)) + float(effect.get("add", 0.0))
	elif stat == "ramp_damage_pct_per_5s":
		add_accum["ramp_damage_pct_per_5s"] = float(add_accum.get("ramp_damage_pct_per_5s", 0.0)) + float(effect.get("add", 0.0))

	# Stats present in JSON but not part of core math are no-ops here; other systems can read them.
	else:
		pass

# Recompute cached engine-facing stats from base + all owned items
func _recompute_cache() -> void:
	_cached_stats.clear()

	# Start with base
	for k in STAT_BASE.keys():
		_cached_stats[k] = STAT_BASE[k]

	# Accumulate item effects:
	var add_accum:Dictionary = {}
	var mul_accum:Dictionary = {}

	for key in _owned_items.keys():
		var count:int = int(_owned_items[key])
		if count <= 0:
			continue
		if not DB.has(key):
			continue

		var e:Dictionary = DB.get_entry(key)
		var effects:Array = e.get("effects", [])
		if typeof(effects) != TYPE_ARRAY:
			continue

		for i in count:
			for fx_v in effects:
				if typeof(fx_v) != TYPE_DICTIONARY:
					continue
				_apply_effect(fx_v, add_accum, mul_accum)

	# Apply additives
	for a_key in add_accum.keys():
		var base_val:float = float(_cached_stats.get(a_key, 0.0))
		_cached_stats[a_key] = base_val + float(add_accum[a_key])

	# Apply multiplicatives
	for m_key in mul_accum.keys():
		var base2:float = float(_cached_stats.get(m_key, 1.0))
		_cached_stats[m_key] = base2 * float(mul_accum[m_key])

# -----------------------------------------------------------------------------
# Public Stat API (read-only during play)
# -----------------------------------------------------------------------------
func _compute_internal_stat(stat_name:String) -> float:
	if _cached_stats.has(stat_name):
		return float(_cached_stats[stat_name])
	return 0.0

func get_stat(stat_name:String) -> float:
	if STAT_BASE.has(stat_name):
		return _compute_internal_stat(stat_name)

	if FRIENDLY_TO_INTERNAL.has(stat_name):
		var internal_name: String = FRIENDLY_TO_INTERNAL[stat_name]
		var v: float = _compute_internal_stat(internal_name)
		if stat_name == "projectiles":
			return float(round(v))
		return v

	return 0.0

func get_all_stats() -> Dictionary:
	return {
		"movespeed":   get_stat("movespeed"),                    # px/s
		"damage":      get_stat("damage"),                       # multiplier
		"firerate":    get_stat("firerate"),                     # multiplier
		"range":       get_stat("range"),                        # +px
		"pickup":      get_stat("pickup"),                       # +px
		"projectiles": int(round(get_stat("projectiles"))),      # count
		"spread":      get_stat("spread"),                       # +deg
		"max_hp":      _compute_internal_stat("max_hp"),
		"hp_regen":    _compute_internal_stat("hp_regen"),
		"lifesteal":   _compute_internal_stat("lifesteal_pct"),
		"armor":       _compute_internal_stat("armor"),
		"dodge":       _compute_internal_stat("dodge_pct"),
		"luck":        _compute_internal_stat("luck")
	}

# Handy getters for other systems (optional but convenient)
func get_shop_price_mult() -> float:        return _compute_internal_stat("shop_price_mult")
func get_enemy_hp_mult() -> float:          return _compute_internal_stat("enemy_hp_mult")
func get_explosion_damage_mult() -> float:  return _compute_internal_stat("explosion_damage_mult")
func get_pierce_add() -> int:               return int(round(_compute_internal_stat("pierce_add")))
func get_knockback_add() -> float:          return _compute_internal_stat("knockback_add")
func get_ramp_damage_pct_per_5s() -> float: return _compute_internal_stat("ramp_damage_pct_per_5s")
func get_crate_bonus_biscuits() -> int:     return int(round(_compute_internal_stat("crate_bonus_biscuits")))
func get_lifesteal_pct() -> float:          return _compute_internal_stat("lifesteal_pct")

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

# -----------------------------------------------------------------------------
# Pricing helpers (delegates to UpgradeDB JSON)
# -----------------------------------------------------------------------------
func get_upgrade_cost(upgrade_key:String) -> int:
	var lvl:int = int(_owned_items.get(upgrade_key, 0))
	return DB.compute_cost_next_level(upgrade_key, lvl)

func can_level(upgrade_key:String) -> bool:
	return DB.has(upgrade_key)
