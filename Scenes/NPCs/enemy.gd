extends CharacterBody2D

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var speed: float = 80.0
@export var hp: int = 6
@export var touch_damage: int = 5
@export var contact_interval: float = 0.4
@export var stop_distance: float = 14.0
@export var target_path: NodePath = NodePath("")
@export var debug_attack_logs: bool = true
@export var debug_draw: bool = false
@export var hit_flash_time: float = 0.06

# -----------------------------------------------------------------------------
# Node refs & runtime state
# -----------------------------------------------------------------------------
@onready var _visual: CanvasItem = _find_visual()
@onready var contact: Area2D = get_node_or_null("Contact") as Area2D

var _target: Node2D = null
var _touching_nexus: bool = false
var _nexus: Node2D = null
var _contact_accum: float = 0.0

var _pending_damage: int = 0
var _took_damage_this_frame: bool = false
var _flashing: bool = false

# -----------------------------------------------------------------------------
# Target
# -----------------------------------------------------------------------------
func set_target(t: Node2D) -> void:
	_target = t
	if is_instance_valid(t):
		target_path = t.get_path()

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("enemies")

	if _target == null and target_path != NodePath(""):
		_target = get_node_or_null(target_path) as Node2D

	if _target == null:
		var arr: Array = get_tree().get_nodes_in_group("nexus")
		if arr.size() > 0:
			_target = arr[0] as Node2D

	if contact != null:
		if not contact.body_entered.is_connected(_on_contact_body_entered):
			contact.body_entered.connect(_on_contact_body_entered)
		if not contact.body_exited.is_connected(_on_contact_body_exited):
			contact.body_exited.connect(_on_contact_body_exited)

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if debug_draw:
		queue_redraw()

	if _target != null:
		var to_target: Vector2 = _target.global_position - global_position
		var dist: float = to_target.length()

		var dir: Vector2 = Vector2.ZERO
		if dist > stop_distance:
			dir = global_position.direction_to(_target.global_position)

		velocity = dir * speed
		move_and_slide()

	if _pending_damage > 0:
		hp -= _pending_damage
		_pending_damage = 0
		_took_damage_this_frame = true
		_flash_hit()

		if hp <= 0:
			queue_free()
			return

	if _touching_nexus and is_instance_valid(_nexus):
		_contact_accum += _delta
		if _contact_accum >= contact_interval:
			_contact_accum = 0.0
			if _nexus.has_method("apply_damage"):
				_nexus.apply_damage(touch_damage)
				if debug_attack_logs:
					print("[Enemy#", str(get_instance_id()), "] attack tick -> Nexus for ", str(touch_damage))

	_took_damage_this_frame = false

# -----------------------------------------------------------------------------
# Damage
# -----------------------------------------------------------------------------
func take_hit(dmg: int) -> void:
	if dmg < 0:
		dmg = 0
	_pending_damage += dmg
	print("HIT ", Engine.get_physics_frames())

# -----------------------------------------------------------------------------
# Flash visuals
# -----------------------------------------------------------------------------
func _find_visual() -> CanvasItem:
	var q: Array[Node] = [self]
	while q.size() > 0:
		var n: Node = q.pop_front()
		if n is AnimatedSprite2D:
			return n as CanvasItem
		if n is Sprite2D:
			return n as CanvasItem
		for c in n.get_children():
			q.push_back(c as Node)
	var q2: Array[Node] = [self]
	while q2.size() > 0:
		var n2: Node = q2.pop_front()
		if n2 != self and n2 is CanvasItem:
			return n2 as CanvasItem
		for c2 in n2.get_children():
			q2.push_back(c2 as Node)
	return self

func _flash_hit() -> void:
	if not is_instance_valid(_visual):
		return

	if _flashing:
		_visual.modulate = Color(1, 1, 1)
		_visual.self_modulate = Color(1, 1, 1)

	_flashing = true
	_visual.modulate = Color(1, 0, 0)
	_visual.self_modulate = Color(1, 0, 0)

	await get_tree().create_timer(hit_flash_time, true).timeout

	if not is_instance_valid(self) or not is_instance_valid(_visual):
		return

	_visual.modulate = Color(1, 1, 1)
	_visual.self_modulate = Color(1, 1, 1)
	_flashing = false

# -----------------------------------------------------------------------------
# Nexus contact
# -----------------------------------------------------------------------------
func _on_contact_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("nexus"):
		_touching_nexus = true
		_nexus = body as Node2D
		_contact_accum = contact_interval
		if debug_attack_logs:
			print("[Enemy#", str(get_instance_id()), "] begin attack (entered Nexus zone)")

func _on_contact_body_exited(body: Node) -> void:
	if body == _nexus:
		_touching_nexus = false
		_nexus = null
		_contact_accum = 0.0
		if debug_attack_logs:
			print("[Enemy#", str(get_instance_id()), "] end attack (left Nexus zone)")

# -----------------------------------------------------------------------------
# Debug draw
# -----------------------------------------------------------------------------
func _draw() -> void:
	if not debug_draw or _target == null:
		return
	draw_line(Vector2.ZERO, to_local(_target.global_position), Color(1,0,0), 2.0)
