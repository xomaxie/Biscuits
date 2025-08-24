extends Node2D

@export var swing_rate: float = 1.6         # slashes per second
@export var damage: int = 2
@export var slash_radius: float = 28.0
@export var active_time: float = 0.09       # hitbox on-time

var _cooldown := 0.0
var _active := false
var _timer := 0.0
var _area: Area2D
var _shape: CollisionShape2D

func _ready() -> void:
	_area = Area2D.new()
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = slash_radius
	_shape.shape = circle
	_area.monitorable = true
	_area.monitoring = false
	add_child(_area)
	_area.add_child(_shape)
	_area.area_entered.connect(_on_area_entered)
	_area.body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if not _active and _cooldown <= 0.0:
		# brief hit window at the weapon's tip
		_active = true
		_timer = active_time
		_area.global_position = to_global(Vector2.RIGHT.rotated(rotation) * slash_radius)
		_area.monitoring = true
		_cooldown = 1.0 / max(swing_rate, 0.01)
	elif _active:
		_timer -= delta
		if _timer <= 0.0:
			_active = false
			_area.monitoring = false

func _hit(node: Node) -> void:
	if node and node.has_method("take_hit"):
		node.take_hit(damage)

func _on_area_entered(a: Area2D) -> void:
	# if enemies are Areas (optional)
	_hit(a.get_parent())

func _on_body_entered(b: Node) -> void:
	_hit(b)
