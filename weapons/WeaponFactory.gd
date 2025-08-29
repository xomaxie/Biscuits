# -----------------------------------------------------------------------------
# WeaponFactory.gd  (autoload singleton, no scene)
# -----------------------------------------------------------------------------
extends Node

# -----------------------------------------------------------------------------
# TEMP: Remap all archetypes to ProjectileWeapon
# -----------------------------------------------------------------------------
const PATHS: Dictionary = {
	"projectile":               "res://weapons/ProjectileWeapon.tscn",
	"projectile_spread":        "res://weapons/ProjectileWeapon.tscn",
	"projectile_heavy":         "res://weapons/ProjectileWeapon.tscn",
	"projectile_arc_explosive": "res://weapons/ProjectileWeapon.tscn",
	"boomerang": "res://weapons/BoomerangWeapon.tscn",
	"explosive_split":          "res://weapons/ProjectileWeapon.tscn",
	"turret_dropper":           "res://weapons/TurretDropperWeapon.tscn",
	"radial_burst":             "res://weapons/ProjectileWeapon.tscn"
}


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------
func create_from_key(key: String) -> Node2D:
	if not UpgradeDB.is_ready():
		return null
	if not UpgradeDB.has(key):
		return null
	var entry: Dictionary = UpgradeDB.get_entry(key)
	return create_from_entry(key, entry)

func create_from_entry(key: String, entry: Dictionary) -> Node2D:
	if entry.is_empty():
		return null
	var weapon_def_v: Variant = entry.get("weapon", {})
	if typeof(weapon_def_v) != TYPE_DICTIONARY:
		return null
	var weapon_def: Dictionary = weapon_def_v
	var arche: String = String(weapon_def.get("archetype", "projectile"))
	var scene_path: String = String(PATHS.get(arche, PATHS["projectile"]))
	return _spawn_and_setup(scene_path, key, weapon_def)

# -----------------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------------
func _spawn_and_setup(scene_path: String, key: String, weapon_def: Dictionary) -> Node2D:
	var ps := load(scene_path)
	if ps == null:
		push_error("WeaponFactory: Missing scene at " + scene_path)
		return null
	var inst := ps.instantiate() as Node2D
	if inst == null:
		return null
	if inst.has_method("setup_from_json"):
		inst.call("setup_from_json", key, weapon_def)
	return inst
