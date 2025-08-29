extends Node2D

# -----------------------------------------------------------------------------
# Exports (base values)
# -----------------------------------------------------------------------------
@export var bullet_scene: PackedScene
@export var base_fire_rate: float = 2.5
@export var base_range: float = 520.0
@export var base_bullet_speed: float = 620.0
@export var base_damage: int = 1
@export var base_projectiles: int = 1
@export var base_spread_deg: float = 0.0
@export var muzzle_forward: float = 0.0
@export var bullet_scale: Vector2 = Vector2.ONE
@export var sprite_forward_offset: float = 0.0
@export var debug_attack_speed: bool = false

# -----------------------------------------------------------------------------
# Runtime (after upgrades)
# -----------------------------------------------------------------------------
var current_fire_rate: float = 2.5
var current_range: float = 520.0
var current_damage: int = 1
var current_projectiles: int = 1
var current_spread_total_deg: float = 0.0

var _cooldown: float = 0.0
var _json_key: String = ""
var _json_weapon: Dictionary = {}
var _gs: Node = null
var _muzzle: Marker2D = null
var _attack_speed_mult: float = 1.0

var _sprite: Sprite2D = null
var _sprite_apply_deferred_once: bool = false

var _bullet_tex_path: String = ""
var _bullet_scale_override: Vector2 = Vector2.ZERO

var _proj_speed_mult_from_atk: float = 1.0

# Split params (for archetypes like "explosive_split")
var _split_count: int = 0
var _split_damage: int = 0
var _split_spread_deg: float = 360.0
var _split_lifetime_sec: float = 0.6
var _split_speed_mult: float = 1.0

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_gs = get_node_or_null("/root/GameState")
	_muzzle = get_node_or_null("Muzzle") as Marker2D
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	_apply_all_upgrades()
	_apply_sprite_overrides()
	if _gs:
		_gs.upgrades_changed.connect(_on_upgrades_changed)

# -----------------------------------------------------------------------------
# External control from WeaponManager
# -----------------------------------------------------------------------------
func set_attack_speed_bonus_pct(v: float) -> void:
	_attack_speed_mult = 1.0 + float(clamp(v, -95.0, 5000.0)) / 100.0
	if debug_attack_speed:
		print("[W:", name, "] bonus_pct=", v, " mult=", _attack_speed_mult)

func set_projectile_speed_from_attack_mult(m: float) -> void:
	_proj_speed_mult_from_atk = max(0.05, m)

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
	base_bullet_speed = float(_json_weapon.get("bullet_speed", base_bullet_speed))
	base_damage = int(_json_weapon.get("damage", base_damage))
	base_projectiles = int(_json_weapon.get("projectiles", base_projectiles))
	base_spread_deg = float(_json_weapon.get("spread_total_deg", base_spread_deg))
	muzzle_forward = float(_json_weapon.get("muzzle_forward", muzzle_forward))

	_bullet_tex_path = String(_json_weapon.get("bullet_sprite_tex", ""))
	var bx: float = float(_json_weapon.get("bullet_scale_x", bullet_scale.x))
	var by: float = float(_json_weapon.get("bullet_scale_y", bullet_scale.y))
	_bullet_scale_override = Vector2(bx, by)

	# Split-related (optional) — used by glitter_bomb
	_split_count = int(_json_weapon.get("split_count", 0))
	_split_damage = int(_json_weapon.get("split_damage", 0))
	_split_spread_deg = float(_json_weapon.get("split_spread_deg", 360.0))
	_split_lifetime_sec = float(_json_weapon.get("split_lifetime_sec", 0.6))
	_split_speed_mult = float(_json_weapon.get("split_speed_mult", 1.0))

	_apply_sprite_overrides()
	_apply_all_upgrades()

# -----------------------------------------------------------------------------
# Sprite overrides
# -----------------------------------------------------------------------------
func _apply_sprite_overrides() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null or not is_inside_tree():
		if not _sprite_apply_deferred_once:
			_sprite_apply_deferred_once = true
			call_deferred("_apply_sprite_overrides")
		return

	var tex_path: String = String(_json_weapon.get("sprite_tex", ""))
	if tex_path != "":
		var res: Resource = load(tex_path)
		if res is Texture2D:
			_sprite.texture = res

	var sx: float = float(_json_weapon.get("sprite_scale_x", _sprite.scale.x))
	var sy: float = float(_json_weapon.get("sprite_scale_y", _sprite.scale.y))
	_sprite.scale = Vector2(sx, sy)

	var ox: float = float(_json_weapon.get("sprite_offset_x", _sprite.position.x))
	var oy: float = float(_json_weapon.get("sprite_offset_y", _sprite.position.y))
	_sprite.position = Vector2(ox, oy)

	var flip_h: bool = bool(_json_weapon.get("sprite_flip_h", _sprite.flip_h))
	var flip_v: bool = bool(_json_weapon.get("sprite_flip_v", _sprite.flip_v))
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
	if _cooldown <= 0.0:
		var target: Node2D = _get_nearest_enemy()
		if target != null:
			_snap_aim(target.global_position)
			_shoot_spread(target.global_position)
			var live_rate: float = max(0.01, current_fire_rate * _attack_speed_mult)
			if debug_attack_speed:
				print("[W:", name, "] fire_rate base=", current_fire_rate, " mult=", _attack_speed_mult, " live=", live_rate)
			_cooldown = 1.0 / live_rate

# -----------------------------------------------------------------------------
# Targeting and aim
# -----------------------------------------------------------------------------
func _snap_aim(target_pos: Vector2) -> void:
	rotation = (target_pos - global_position).angle() + sprite_forward_offset

func _get_nearest_enemy() -> Node2D:
	var host: Node2D = get_parent() as Node2D
	var origin: Vector2 = host.global_position if host else global_position
	var best: Node2D = null
	var best_d2: float = current_range * current_range
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

# -----------------------------------------------------------------------------
# Firing
# -----------------------------------------------------------------------------
func _shoot_spread(target_pos: Vector2) -> void:
	if bullet_scene == null:
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return

	var center_dir: Vector2 = (target_pos - global_position).normalized()
	var center_ang: float = center_dir.angle()

	var count: int = max(1, current_projectiles)
	var total_deg: float = current_spread_total_deg
	if count > 1 and total_deg <= 0.0:
		total_deg = 6.0

	var start_rad: float = 0.0
	var step_rad: float = 0.0
	if count > 1:
		start_rad = -deg_to_rad(total_deg) * 0.5
		step_rad = deg_to_rad(total_deg) / float(count - 1)

	var current_speed: float = max(1.0, base_bullet_speed * _proj_speed_mult_from_atk)
	var lifetime_sec: float = current_range / current_speed
	var max_distance: float = current_range

	var pierce_base: int = int(_json_weapon.get("pierce", 0))
	var kb_base: float = float(_json_weapon.get("knockback", 0.0))
	var aoe: float = float(_json_weapon.get("aoe_radius", 0.0))
	var pierce: int = GameState.get_pierce_add() + pierce_base
	var kb: float = GameState.get_knockback_add() + kb_base

	# Optional crit
	var crit_chance: float = float(_json_weapon.get("crit_chance_pct", 0.0))
	var crit_mult: float = float(_json_weapon.get("crit_multiplier", 2.0))

	# Optional explosion damage mult (applies only if aoe > 0)
	var explosion_mult: float = 1.0
	if aoe > 0.0 and GameState and GameState.has_method("get_explosion_damage_mult"):
		explosion_mult = max(0.0, float(GameState.get_explosion_damage_mult()))

	for i in count:
		var ang: float = center_ang + start_rad + step_rad * float(i)
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var spawn_pos: Vector2 = _spawn_position(dir)

		var b: Node = bullet_scene.instantiate()
		if b == null:
			continue
		world.add_child(b)

		_apply_bullet_visuals(b)

		var b2d: Node2D = b as Node2D
		if b2d:
			b2d.global_position = spawn_pos
			if _bullet_scale_override != Vector2.ZERO:
				b2d.scale = _bullet_scale_override
			else:
				b2d.scale = bullet_scale

		# Init bullet core stats
		if b.has_method("init"):
			b.call(
				"init",
				dir,
				current_speed,
				current_damage,
				lifetime_sec,
				spawn_pos,
				max_distance,
				pierce,
				kb,
				aoe
			)

		# Optional extensions, if the bullet supports them
		if b.has_method("set_crit"):
			b.call("set_crit", crit_chance, crit_mult)
		if b.has_method("set_explosion_mult"):
			b.call("set_explosion_mult", explosion_mult)

		# Split behavior (e.g., Glitter Bomb). Bullet must implement one of these.
		if _split_count > 0:
			# Prefer an options dictionary API if available
			if b.has_method("set_split_options"):
				var opts: Dictionary = {
					"child_scene": bullet_scene,
					"count": _split_count,
					"damage": _split_damage,
					"spread_deg": _split_spread_deg,
					"lifetime_sec": _split_lifetime_sec,
					"speed_mult": _split_speed_mult,
					"tex_path": _bullet_tex_path,
					"scale_override": _bullet_scale_override,
				}
				b.call("set_split_options", opts)
			elif b.has_method("set_split_params"):
				# Back-compat minimal API
				b.call("set_split_params",
					bullet_scene,
					_split_count,
					_split_damage,
					_bullet_tex_path,
					_bullet_scale_override
				)

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
# Spawn helpers
# -----------------------------------------------------------------------------
func _spawn_position(dir: Vector2) -> Vector2:
	if _muzzle:
		return _muzzle.global_position
	return global_position + dir * muzzle_forward

# -----------------------------------------------------------------------------
# Upgrades
# -----------------------------------------------------------------------------
func _on_upgrades_changed() -> void:
	_apply_all_upgrades()

func _apply_all_upgrades() -> void:
	var eff: Dictionary
	if _gs and _gs.has_method("get_effective_weapon_values"):
		eff = _gs.get_effective_weapon_values(
			base_fire_rate, base_range, base_damage, base_projectiles, base_spread_deg
		)
	else:
		eff = {
			"fire_rate": base_fire_rate,
			"range": base_range,
			"damage": base_damage,
			"projectiles": base_projectiles,
			"spread": base_spread_deg
		}

	current_fire_rate = float(eff.get("fire_rate", base_fire_rate))
	current_range = float(eff.get("range", base_range))
	current_damage = int(eff.get("damage", base_damage))
	current_projectiles = int(eff.get("projectiles", base_projectiles))
	current_spread_total_deg = float(eff.get("spread", base_spread_deg))

	if current_projectiles < 1:
		current_projectiles = 1
	if current_fire_rate < 0.01:
		current_fire_rate = 0.01
	if current_range < 0.0:
		current_range = 0.0
