extends Node2D

# ---- Base (inspector) values ----
@export var fire_rate: float = 2.5            # shots per second (base)
@export var range: float = 520.0              # base range used for target selection
@export var bullet_speed: float = 620.0
@export var damage: int = 1
@export var bullet_scene: PackedScene
@export var sprite_forward_offset: float = 0.0   # e.g., -PI/2 if sprite faces up

# Multi-shot + spread (base)
@export var projectiles: int = 1                # bullets per shot (base)
@export var spread_total_deg: float = 0.0       # total arc across all bullets (e.g., 30 = ±15°) (base)
@export var muzzle_forward: float = 0.0         # push spawn forward (px) to avoid clipping

# Bullet scale (visual only)
@export var bullet_scale: Vector2 = Vector2.ONE

# ---- Runtime (after upgrades) ----
var current_fire_rate: float = 2.5
var current_range: float = 520.0
var current_damage: int = 1
var current_projectiles: int = 1
var current_spread_total_deg: float = 0.0

var _cooldown: float = 0.0
var _gs: Node = null   # /root/GameState

func _ready() -> void:
	_gs = get_node_or_null("/root/GameState")

	# Initialize from base values
	current_fire_rate = fire_rate
	current_range = range
	current_damage = damage
	current_projectiles = projectiles
	current_spread_total_deg = spread_total_deg

	# Apply upgrades now and subscribe for future changes
	_apply_all_upgrades()
	if _gs:
		_gs.upgrades_changed.connect(_on_upgrade_changed)

func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		# Safety net: refresh just before we shoot in case a purchase happened while paused.
		_apply_all_upgrades()

		var target: Node2D = _get_nearest_enemy()
		if target != null:
			_snap_aim(target.global_position)
			_shoot_spread(target.global_position)
			var rate: float = current_fire_rate
			if rate < 0.01:
				rate = 0.01
			_cooldown = 1.0 / rate

func _snap_aim(target_pos: Vector2) -> void:
	rotation = (target_pos - global_position).angle() + sprite_forward_offset

func _get_nearest_enemy() -> Node2D:
	var origin: Vector2
	if get_parent() is Node2D:
		origin = (get_parent() as Node2D).global_position
	else:
		origin = global_position

	var best: Node2D = null
	var max_d2: float = current_range * current_range
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e is Node2D and is_instance_valid(e):
			var pos: Vector2 = (e as Node2D).global_position
			var d2: float = origin.distance_squared_to(pos)
			if d2 < max_d2:
				max_d2 = d2
				best = e
	return best

func _shoot_spread(target_pos: Vector2) -> void:
	if bullet_scene == null:
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return

	var center_dir: Vector2 = (target_pos - global_position).normalized()
	var center_ang: float = center_dir.angle()

	var count: int = current_projectiles
	if count < 1:
		count = 1

	var total_deg: float = current_spread_total_deg
	# Tiny visual safeguard so multiple bullets don't perfectly stack when spread is 0
	if count > 1 and total_deg <= 0.0:
		total_deg = 6.0

	var start_rad: float = 0.0
	var step_rad: float = 0.0
	if count > 1:
		start_rad = -deg_to_rad(total_deg) * 0.5
		step_rad = deg_to_rad(total_deg) / float(count - 1)

	# Precompute lifetime from range so bullets respect range
	var lifetime_sec: float = 0.01
	if bullet_speed > 0.0:
		lifetime_sec = current_range / bullet_speed
	var max_distance: float = current_range

	for i in range(count):
		var ang: float = center_ang + start_rad + step_rad * float(i)
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var spawn_pos: Vector2 = global_position + dir * muzzle_forward

		var b: Node = bullet_scene.instantiate()
		if b == null:
			continue
		world.add_child(b)

		if b is Node2D:
			var b2d: Node2D = b as Node2D
			b2d.global_position = spawn_pos
			b2d.scale = bullet_scale

		if b.has_method("init"):
			# bullet.init(dir, speed, dmg, lifetime, start_pos, max_distance)
			b.call("init", dir, bullet_speed, current_damage, lifetime_sec, spawn_pos, max_distance)

# ---------- Upgrades ----------
func _on_upgrade_changed() -> void:
	# Signal carries no args in your GameState; just recompute everything.
	_apply_all_upgrades()

func _apply_all_upgrades() -> void:
	# Start from base exports
	var base_fire: float = fire_rate
	var base_range: float = range
	var base_dmg: int = damage
	var base_proj: int = projectiles
	var base_spread: float = spread_total_deg

	if _gs and _gs.has_method("get_effective_weapon_values"):
		var eff: Dictionary = _gs.get_effective_weapon_values(
			base_fire, base_range, base_dmg, base_proj, base_spread
		)
		if eff.has("fire_rate"):
			current_fire_rate = float(eff["fire_rate"])
		if eff.has("range"):
			current_range = float(eff["range"])
		if eff.has("damage"):
			current_damage = int(eff["damage"])
		if eff.has("projectiles"):
			current_projectiles = int(eff["projectiles"])
		if eff.has("spread"):
			current_spread_total_deg = float(eff["spread"])
	else:
		# Fallback: keep bases if GameState missing
		current_fire_rate = base_fire
		current_range = base_range
		current_damage = base_dmg
		current_projectiles = base_proj
		current_spread_total_deg = base_spread

	# Safety clamps
	if current_projectiles < 1:
		current_projectiles = 1
	if current_fire_rate < 0.01:
		current_fire_rate = 0.01
	if current_range < 0.0:
		current_range = 0.0
