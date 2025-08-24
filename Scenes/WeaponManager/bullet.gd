extends Area2D

@export var lifetime: float = 2.0
var velocity: Vector2 = Vector2.ZERO
var damage: int = 1

func init(dir: Vector2, speed: float, dmg: int) -> void:
	velocity = dir.normalized() * speed
	damage = dmg
	rotation = dir.angle()

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_Bullet_body_entered(body: Node) -> void:
	if body and body.has_method("take_hit"):
		body.take_hit(damage)
	queue_free()
