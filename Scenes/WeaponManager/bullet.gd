# bullet.gd
extends Area2D

@export var lifetime: float = 2.0
@export var damage: int = 1
@export var speed: float = 620.0

var velocity: Vector2 = Vector2.ZERO
var _hit_once: bool = false

@onready var shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

func _ready() -> void:
	# Ensure we actually detect things
	monitoring = true
	monitorable = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if shape != null:
		shape.disabled = false

func init(dir: Vector2, speed_in: float, dmg: int) -> void:
	var d: Vector2 = dir.normalized()
	velocity = d * speed_in
	speed = speed_in
	damage = dmg
	rotation = d.angle()

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _apply_hit(target: Node) -> void:
	if _hit_once:
		return
	_hit_once = true
	if target != null and target.has_method("take_hit"):
		target.call("take_hit", damage)
	queue_free()

func _on_body_entered(body: Node) -> void:
	# Enemies are CharacterBody2D -> this fires
	_apply_hit(body)

func _on_area_entered(area: Area2D) -> void:
	var owner_node: Node = area.get_parent()
	if owner_node != null and owner_node.has_method("take_hit"):
		_apply_hit(owner_node)
