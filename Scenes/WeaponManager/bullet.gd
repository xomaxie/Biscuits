extends Area2D

@export var lifetime: float = 2.0
@export var damage: int = 1
@export var speed: float = 620.0

var velocity: Vector2 = Vector2.ZERO
var _hit_once: bool = false

var _spawn_pos: Vector2 = Vector2.ZERO
var _max_distance: float = -1.0   

@onready var shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

func _ready() -> void:
	monitoring = true
	monitorable = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if shape != null:
		shape.disabled = false
	_spawn_pos = global_position

func init(dir: Vector2, speed_in: float, dmg: int, lifetime_sec: float = -1.0, start_pos: Vector2 = Vector2.INF, max_distance: float = -1.0) -> void:
	var d: Vector2 = dir.normalized()
	velocity = d * speed_in
	speed = speed_in
	damage = dmg
	rotation = d.angle()

	if start_pos != Vector2.INF:
		_spawn_pos = start_pos
		global_position = start_pos

	if lifetime_sec >= 0.0:
		lifetime = lifetime_sec

	_max_distance = max_distance

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return

	if _max_distance >= 0.0:
		var traveled: float = _spawn_pos.distance_to(global_position)
		if traveled >= _max_distance:
			queue_free()
			return

func _apply_hit(target: Node) -> void:
	if _hit_once:
		return
	_hit_once = true
	if target != null and target.has_method("take_hit"):
		target.call("take_hit", damage)
	queue_free()

func _on_body_entered(body: Node) -> void:
	_apply_hit(body)

func _on_area_entered(area: Area2D) -> void:
	var owner_node: Node = area.get_parent()
	if owner_node != null and owner_node.has_method("take_hit"):
		_apply_hit(owner_node)
