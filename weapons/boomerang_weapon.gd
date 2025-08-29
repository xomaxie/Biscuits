# -----------------------------------------------------------------------------
# BoomerangWeapon.gd
# -----------------------------------------------------------------------------
extends Node2D

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var boomerang_scene: PackedScene
@export var base_fire_rate: float = 1.6
@export var base_range: float = 520.0
@export var base_speed: float = 680.0
@export var base_damage: int = 2
@export var base_projectiles: int = 1
@export var base_spread_deg: float = 0.0
@export var return_after_sec: float = 0.5
@export var muzzle_forward: float = 0.0
@export var sprite_forward_offset: float = 0.0

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var _cooldown: float = 0.0
var _json_key: String = ""
var _json_weapon: Dictionary = {}
var _gs: Node = null
var _muzzle: Marker2D = null
var _in_flight_count: int = 0
var _proj_speed_mult: float = 1.0
var _attack_speed_mult: float = 1.0
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_gs = get_node_or_null("/root/GameState")
	_muzzle = get_node_or_null("Muzzle") as Marker2D
	if _gs:
		_gs.upgrades_changed.connect(_on_upgrades_changed)

# -----------------------------------------------------------------------------
# Attack-speed hooks
# -----------------------------------------------------------------------------
func set_attack_speed_bonus_pct(v: float) -> void:
	_attack_speed_mult = 1.0 + float(clamp(v, -95.0, 5000.0)) / 100.0

func set_projectile_speed_from_attack_mult(mult: float) -> void:
	_proj_speed_mult = max(0.05, float(mult))

# -----------------------------------------------------------------------------
# JSON setup
# -----------------------------------------------------------------------------
func setup_from_json(key: String, weapon_dict_v: Variant) -> void:
	_json_key = key
	if typeof(weapon_dict_v) == TYPE_DICTIONARY:
		_json_weapon = weapon_dict_v
	else:
		_json_weapon = {}

	base_fire_rate = float(_json_weapon.get("fire_rate", base_fire_rate))
	base_range = float(_json_weapon.get("range", base_range))
	base_speed = float(_json_weapon.get("bullet_speed", base_speed))
	base_damage = int(_json_weapon.get("damage", base_damage))
	base_projectiles = int(_json_weapon.get("projectiles",
		base_projectiles))
	base_spread_deg = float(_json_weapon.get("spread_total_deg",
		base_spread_deg))
	return_after_sec = float(_json_weapon.get("return_after_sec",
		return_after_sec))
	muzzle_forward = float(_json_weapon.get("muzzle_forward",
		muzzle_forward))

	_apply_sprite_overrides()

# -----------------------------------------------------------------------------
# Sprite overrides
# -----------------------------------------------------------------------------
func _apply_sprite_overrides() -> void:
	if _sprite == null:
		return

	var tex_path: String = String(_json_weapon.get("sprite_tex", ""))
	if tex_path != "":
		var res: Resource = load(tex_path)
		if res is Texture2D:
			_sprite.texture = res

	var sx: float = float(_json_weapon.get("sprite_scale_x",
		_sprite.scale.x))
	var sy: float = float(_json_weapon.get("sprite_scale_y",
		_sprite.scale.y))
	_sprite.scale = Vector2(sx, sy)

	var ox: float = float(_json_weapon.get("sprite_offset_x",
		_sprite.position.x))
	var oy: float = float(_json_weapon.get("sprite_offset_y",
		_sprite.position.y))
	_sprite.position = Vector2(ox, oy)

	var flip_h: bool = bool(_json_weapon.get("sprite_flip_h",
		_sprite.flip_h))
	var flip_v: bool = bool(_json_weapon.get("sprite_flip_v",
		_sprite.flip_v))
	_sprite.flip_h = flip_h
	_sprite.flip_v = flip_v

	var z: int = int(_json_weapon.get("sprite_z", _sprite.z_index))
	_sprite.z_index = z

	var mod_str: String = String(_json_weapon.get("sprite_modulate", ""))
	if mod_str != "":
		_sprite.modulate = Color(mod_str)

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return

	if _in_flight_count > 0:
		_cooldown = 0.05
		return

	var t: Node2D = _nearest_enemy()
	if t == null:
		return

	_snap_aim(t.global_position)
	_fire_spread(t.global_position)
	_cooldown = 1.0 / max(0.01, _effective_fire_rate())

# -----------------------------------------------------------------------------
# Targeting
# -----------------------------------------------------------------------------
func _nearest_enemy() -> Node2D:
	var host: Node2D = get_parent() as Node2D
	var origin: Vector2 = global_position
	if host != null:
		origin = host.global_position

	var best: Node2D = null
	var r: float = _effective_range()
	var best_d2: float = r * r

	var nodes: Array = get_tree().get_nodes_in_group("enemies")
	for e in nodes:
		var n: Node2D = e as Node2D
		if n == null:
			continue
		var d2: float = origin.distance_squared_to(n.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best

func _snap_aim(target_pos: Vector2) -> void:
	var ang: float = (target_pos - global_position).angle()
	rotation = ang + sprite_forward_offset

# -----------------------------------------------------------------------------
# Fire
# -----------------------------------------------------------------------------
func _fire_spread(target_pos: Vector2) -> void:
	if boomerang_scene == null:
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return

	var eff: Dictionary = _effective_values()
	var shots: int = int(eff["projectiles"])
	var spread: float = float(eff["spread"])
	var dmg: int = int(eff["damage"])
	var spd: float = float(eff["speed"])
	var rng: float = float(eff["range"])

	var pierce: int = GameState.get_pierce_add() + int(
		_json_weapon.get("pierce", 0)
	)
	var kb: float = GameState.get_knockback_add() + float(
		_json_weapon.get("knockback", 0.0)
	)

	var dir0: Vector2 = (target_pos - global_position).normalized()
	var base_ang: float = dir0.angle()

	var start: float = 0.0
	var step: float = 0.0
	if shots > 1 and spread > 0.0:
		start = -deg_to_rad(spread) * 0.5
		step = deg_to_rad(spread) / float(shots - 1)

	if _sprite != null:
		_sprite.visible = false

	for i in shots:
		var ang: float = base_ang + start + step * float(i)
		var dir: Vector2 = Vector2.RIGHT.rotated(ang)
		var spawn: Vector2 = _spawn_position(dir)

		var b: Node2D = boomerang_scene.instantiate() as Node2D
		if b == null:
			continue
		world.add_child(b)
		b.global_position = spawn

		_in_flight_count += 1

		if b.has_signal("returned"):
			b.connect("returned",
				Callable(self, "_on_boomerang_returned"))
		b.tree_exited.connect(_on_boomerang_exited)

		if b.has_method("init_boomerang"):
			b.call("init_boomerang", dir, spd, dmg, spawn, rng,
				return_after_sec, pierce, kb, self)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _spawn_position(dir: Vector2) -> Vector2:
	if _muzzle:
		return _muzzle.global_position
	return global_position + dir * muzzle_forward

func _effective_values() -> Dictionary:
	var fire: float = base_fire_rate
	var rng: float = base_range
	var dmg: int = base_damage
	var proj: int = base_projectiles
	var spr: float = base_spread_deg

	if _gs and _gs.has_method("get_effective_weapon_values"):
		var eff: Dictionary = _gs.get_effective_weapon_values(
			base_fire_rate, base_range, base_damage,
			base_projectiles, base_spread_deg
		)
		if eff.has("range"):
			rng = float(eff["range"])
		if eff.has("damage"):
			dmg = int(eff["damage"])
		if eff.has("projectiles"):
			proj = int(eff["projectiles"])
		if eff.has("spread"):
			spr = float(eff["spread"])

	if proj < 1:
		proj = 1
	if spr < 0.0:
		spr = 0.0

	var spd: float = base_speed * _proj_speed_mult

	return {
		"fire_rate": fire,
		"range": rng,
		"damage": dmg,
		"projectiles": proj,
		"spread": spr,
		"speed": spd
	}

func _effective_fire_rate() -> float:
	return base_fire_rate * _attack_speed_mult

func _effective_range() -> float:
	var eff: Dictionary = _effective_values()
	return float(eff["range"])

# -----------------------------------------------------------------------------
# Callbacks
# -----------------------------------------------------------------------------
func _on_boomerang_returned(_weapon: Node) -> void:
	_in_flight_count -= 1
	if _in_flight_count < 0:
		_in_flight_count = 0
	if _in_flight_count == 0 and _sprite != null:
		_sprite.visible = true

func _on_boomerang_exited() -> void:
	_in_flight_count -= 1
	if _in_flight_count < 0:
		_in_flight_count = 0
	if _in_flight_count == 0 and _sprite != null:
		_sprite.visible = true

func _on_upgrades_changed() -> void:
	pass
