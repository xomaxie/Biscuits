extends Node2D

@export var fire_rate: float = 2.5            # shots per second
@export var range: float = 520.0
@export var bullet_speed: float = 620.0
@export var damage: int = 1
@export var bullet_scene: PackedScene
@export var sprite_forward_offset: float = 0.0   # e.g., -PI/2 if sprite faces up

# Multi-shot + spread
@export var projectiles: int = 1                # bullets per shot
@export var spread_total_deg: float = 0.0       # total arc across all bullets (e.g., 30 = ±15°)
@export var muzzle_forward: float = 0.0         # push spawn forward (px) to avoid clipping

# NEW: bullet scale
@export var bullet_scale: Vector2 = Vector2.ONE # uniform: Vector2(1,1), double size: Vector2(2,2)

var _cooldown: float = 0.0

func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		var target: Node2D = _get_nearest_enemy()
		if target != null:
			_snap_aim(target.global_position)
			_shoot_spread(target.global_position)
			_cooldown = 1.0 / max(fire_rate, 0.01)

func _snap_aim(target_pos: Vector2) -> void:
	rotation = (target_pos - global_position).angle() + sprite_forward_offset

func _get_nearest_enemy() -> Node2D:
	var origin: Vector2
	if get_parent() is Node2D:
		origin = (get_parent() as Node2D).global_position
	else:
		origin = global_position

	var best: Node2D = null
	var best_d2: float = range * range
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e is Node2D and is_instance_valid(e):
			var pos: Vector2 = (e as Node2D).global_position
			var d2: float = origin.distance_squared_to(pos)
			if d2 < best_d2:
				best_d2 = d2
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

	var count: int = max(projectiles, 1)
	var start_rad: float = 0.0
	var step_rad: float = 0.0
	if count > 1:
		start_rad = -deg_to_rad(spread_total_deg) * 0.5
		step_rad = deg_to_rad(spread_total_deg) / float(count - 1)

	for i: int in count:
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
			b.call("init", dir, bullet_speed, damage)
