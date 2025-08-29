extends Node2D

# -----------------------------------------------------------------------------
# Exports (base values)
# -----------------------------------------------------------------------------
@export var bullet_scene: PackedScene
@export var lifetime_sec: float = 12.0
@export var base_fire_rate: float = 2.0
@export var base_range: float = 520.0
@export var base_bullet_speed: float = 700.0
@export var base_damage: int = 1
@export var bullet_scale: Vector2 = Vector2.ONE
@export var sprite_forward_offset: float = 0.0

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var _gs: Node = null
var _cooldown: float = 0.0
var _attack_mult: float = 1.0
var _proj_speed_mult: float = 1.0
var _bullet_tex_path: String = ""
var _bullet_scale_override: Vector2 = Vector2.ZERO
@onready var _muzzle: Marker2D = get_node_or_null("Muzzle") as Marker2D
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_gs = get_node_or_null("/root/GameState")

# -----------------------------------------------------------------------------
# Setup from dropper JSON
# -----------------------------------------------------------------------------
func setup_from_dict(turret_def: Dictionary, parent_weapon: Dictionary) \
-> void:
	base_fire_rate = float(turret_def.get(
		"fire_rate", base_fire_rate))
	base_range = float(turret_def.get(
		"range", base_range))
	base_bullet_speed = float(turret_def.get(
		"bullet_speed", base_bullet_speed))
	base_damage = int(turret_def.get(
		"damage", base_damage))

	_bullet_tex_path = String(parent_weapon.get("bullet_sprite_tex", ""))
	var bx: float = float(parent_weapon.get(
		"bullet_scale_x", bullet_scale.x))
	var by: float = float(parent_weapon.get(
		"bullet_scale_y", bullet_scale.y))
	_bullet_scale_override = Vector2(bx, by)

	var tex_path: String = String(parent_weapon.get("sprite_tex", ""))
	if tex_path != "" and _sprite:
		var res: Resource = load(tex_path)
		if res is Texture2D:
			_sprite.texture = res
	if _sprite:
		var sx: float = float(parent_weapon.get(
			"sprite_scale_x", _sprite.scale.x))
		var sy: float = float(parent_weapon.get(
			"sprite_scale_y", _sprite.scale.y))
		_sprite.scale = Vector2(sx, sy)

# -----------------------------------------------------------------------------
# Attack-speed hooks
# -----------------------------------------------------------------------------
func set_attack_speed_bonus_pct(v: float) -> void:
	_attack_mult = 1.0 + float(clamp(v, -95.0, 5000.0)) / 100.0

func set_projectile_speed_from_attack_mult(m: float) -> void:
	_proj_speed_mult = max(0.05, float(m))

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	lifetime_sec -= delta
	if lifetime_sec <= 0.0:
		queue_free()
		return

	_cooldown -= delta
	if _cooldown > 0.0:
		return

	var t: Node2D = _nearest_enemy()
	if t == null:
		return

	_snap_aim(t.global_position)
	_fire_once(t.global_position)
	var live_rate: float = max(0.01, _effective_fire_rate() * _attack_mult)
	_cooldown = 1.0 / live_rate

# -----------------------------------------------------------------------------
# Targeting
# -----------------------------------------------------------------------------
func _nearest_enemy() -> Node2D:
	var origin: Vector2 = global_position
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
func _fire_once(target_pos: Vector2) -> void:
	if bullet_scene == null:
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return

	var dir: Vector2 = (target_pos - global_position).normalized()
	var spd: float = base_bullet_speed * _proj_speed_mult
	var rng: float = _effective_range()
	var dmg: int = _effective_damage()

	var lifetime_sec: float = 0.01
	if spd > 0.0:
		lifetime_sec = rng / spd

	var spawn_pos: Vector2 = _spawn_position(dir)

	var b: Node = bullet_scene.instantiate()
	if b == null:
		return
	world.add_child(b)

	_apply_bullet_visuals(b)

	var b2d: Node2D = b as Node2D
	if b2d:
		b2d.global_position = spawn_pos
		if _bullet_scale_override != Vector2.ZERO:
			b2d.scale = _bullet_scale_override
		else:
			b2d.scale = bullet_scale

	if b.has_method("init"):
		b.call("init", dir, spd, dmg, lifetime_sec, spawn_pos, rng, 0, 0.0, 0.0)

# -----------------------------------------------------------------------------
# Bullet visuals
# -----------------------------------------------------------------------------
func _apply_bullet_visuals(b: Node) -> void:
	if _bullet_tex_path == "":
		return
	var spr: Sprite2D = null
	if b is Sprite2D:
		spr = b as Sprite2D
	else:
		spr = b.get_node_or_null("Sprite2D") as Sprite2D
		if spr == null:
			for c in b.get_children():
				if c is Sprite2D:
					spr = c as Sprite2D
					break
	if spr == null:
		return
	var res: Resource = load(_bullet_tex_path)
	if res is Texture2D:
		spr.texture = res

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _spawn_position(dir: Vector2) -> Vector2:
	if _muzzle:
		return _muzzle.global_position
	return global_position

func _effective_range() -> float:
	if _gs and _gs.has_method("get_effective_weapon_values"):
		var eff: Dictionary = _gs.get_effective_weapon_values(
			base_fire_rate, base_range, base_damage, 1, 0.0)
		return float(eff.get("range", base_range))
	return base_range

func _effective_fire_rate() -> float:
	if _gs and _gs.has_method("get_effective_weapon_values"):
		var eff: Dictionary = _gs.get_effective_weapon_values(
			base_fire_rate, base_range, base_damage, 1, 0.0)
		return float(eff.get("fire_rate", base_fire_rate))
	return base_fire_rate

func _effective_damage() -> int:
	if _gs and _gs.has_method("get_effective_weapon_values"):
		var eff: Dictionary = _gs.get_effective_weapon_values(
			base_fire_rate, base_range, base_damage, 1, 0.0)
		return int(eff.get("damage", base_damage))
	return base_damage
