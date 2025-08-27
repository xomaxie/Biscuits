extends Area2D

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var lifetime: float = 2.0
@export var damage: int = 1
@export var speed: float = 620.0
@export var aoe_radius: float = 0.0
@export var tint_color: Color = Color(1, 1, 1, 0.7)

# -----------------------------------------------------------------------------
# Runtime State
# -----------------------------------------------------------------------------
var velocity: Vector2 = Vector2.ZERO
var pierce_left: int = 0
var knockback: float = 0.0
var _spawn_pos: Vector2 = Vector2.ZERO
var _max_distance: float = -1.0
var _alive: bool = false

# -----------------------------------------------------------------------------
# Node Refs
# -----------------------------------------------------------------------------
@onready var shape: CollisionShape2D = (
	get_node_or_null("CollisionShape2D") as CollisionShape2D
)
@onready var _visuals: Array[CanvasItem] = _find_visuals()

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
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
	_alive = true
	_apply_tint()

# -----------------------------------------------------------------------------
# Init
# -----------------------------------------------------------------------------
func init(
	dir: Vector2,
	speed_in: float,
	dmg: int,
	lifetime_sec: float = -1.0,
	start_pos: Vector2 = Vector2.INF,
	max_distance: float = -1.0,
	pierce: int = 0,
	kb: float = 0.0,
	aoe: float = -1.0
) -> void:
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
	pierce_left = max(0, pierce)
	knockback = kb
	if aoe >= 0.0:
		aoe_radius = aoe
	_apply_tint()

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not _alive:
		return
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		_despawn()
		return
	if _max_distance >= 0.0:
		var traveled: float = _spawn_pos.distance_to(global_position)
		if traveled >= _max_distance:
			_despawn()
			return

# -----------------------------------------------------------------------------
# Hits
# -----------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	_apply_hit(body)

func _on_area_entered(area: Area2D) -> void:
	var owner_node: Node = area.get_parent()
	if owner_node != null:
		_apply_hit(owner_node)

func _apply_hit(target: Node) -> void:
	if not _alive:
		return
	if target != null and target.has_method("take_hit"):
		target.call("take_hit", damage)
	if knockback > 0.0 and target is CharacterBody2D:
		var body: CharacterBody2D = target as CharacterBody2D
		var dir: Vector2 = (
			(body.global_position - global_position).normalized()
		)
		body.velocity += dir * knockback
	if aoe_radius > 0.0:
		_apply_aoe()
	if pierce_left > 0:
		pierce_left -= 1
	else:
		_despawn()

# -----------------------------------------------------------------------------
# AOE
# -----------------------------------------------------------------------------
func _apply_aoe() -> void:
	var space: PhysicsDirectSpaceState2D = (
		get_world_2d().direct_space_state
	)
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = aoe_radius
	var params: PhysicsShapeQueryParameters2D = (
		PhysicsShapeQueryParameters2D.new()
	)
	params.shape = circle
	params.transform = Transform2D(0.0, global_position)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hits: Array[Dictionary] = space.intersect_shape(params, 32)
	for h in hits:
		var collider: Object = h.get("collider")
		var node: Node = collider as Node
		if node != null and node != self and node.has_method("take_hit"):
			node.call("take_hit", damage)

# -----------------------------------------------------------------------------
# Visuals
# -----------------------------------------------------------------------------
func _find_visuals() -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	var stack: Array[Node] = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			var cn: Node = c as Node
			if cn == null:
				continue
			if cn is AnimatedSprite2D or cn is Sprite2D or cn is GPUParticles2D:
				out.append(cn as CanvasItem)
			stack.append(cn)
	return out

func _apply_tint() -> void:
	var a: float = clamp(tint_color.a, 0.0, 1.0)
	var base: Color = Color(tint_color.r, tint_color.g, tint_color.b, a)
	if _visuals.is_empty():
		_visuals = _find_visuals()
	for v in _visuals:
		if is_instance_valid(v):
			v.self_modulate = base

# -----------------------------------------------------------------------------
# Despawn
# -----------------------------------------------------------------------------
func _despawn() -> void:
	_alive = false
	queue_free()
