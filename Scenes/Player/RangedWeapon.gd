extends Node2D

@export var fire_rate: float = 2.5          # shots per second
@export var range: float = 520.0
@export var bullet_speed: float = 620.0
@export var damage: int = 1
@export var bullet_scene: PackedScene

var _cooldown := 0.0

func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		var target := _get_nearest_enemy()
		if target:
			_shoot(target.global_position)
			_cooldown = 1.0 / max(fire_rate, 0.01)

func _get_nearest_enemy() -> Node2D:
	var owner2d := get_parent() as Node2D
	if owner2d == null:
		return null
	var best: Node2D = null
	var best_d2 := range * range
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D:
			var d2 := owner2d.global_position.distance_squared_to(e.global_position)
			if d2 < best_d2:
				best_d2 = d2
				best = e
	return best

func _shoot(target_pos: Vector2) -> void:
	if bullet_scene == null:
		return
	var b := bullet_scene.instantiate()
	get_tree().current_scene.add_child(b)
	if b.has_method("init"):
		var dir := (target_pos - global_position).normalized()
		b.global_position = global_position
		b.init(dir, bullet_speed, damage)
