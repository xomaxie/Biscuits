# -----------------------------------------------------------------------------
# BoomerangProjectile.gd
# -----------------------------------------------------------------------------
extends Area2D

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------
signal returned(weapon: Node)

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var lifetime: float = 8.0
@export var return_after_sec: float = 0.5
@export var speed: float = 680.0
@export var damage: int = 2
@export var max_out_distance: float = 520.0
@export var return_snap_distance: float = 18.0
@export var spin_speed_deg: float = 540.0
@export var return_turn_rate_deg: float = 300
@export var return_speed_mult: float = 1.0
@export var debug_boomerang_speed: bool = false

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var velocity: Vector2 = Vector2.ZERO
var pierce_pass_through: int = 0
var knockback: float = 0.0
var owner_weapon: Node = null
var _t: float = 0.0
var _spawn_pos: Vector2 = Vector2.ZERO
var _state_outward: bool = true
var _hit_ids_out: Dictionary = {}
var _hit_ids_back: Dictionary = {}

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
	_spawn_pos = global_position

# -----------------------------------------------------------------------------
# Init
# -----------------------------------------------------------------------------
func init_boomerang(
	dir: Vector2,
	spd: float,
	dmg: int,
	start_pos: Vector2,
	out_dist: float,
	ret_after: float,
	pierce: int,
	kb: float,
	weapon_node: Node
) -> void:
	var d: Vector2 = dir.normalized()
	velocity = d * spd
	speed = spd
	damage = dmg
	_spawn_pos = start_pos
	global_position = start_pos
	max_out_distance = out_dist
	return_after_sec = ret_after
	pierce_pass_through = max(0, pierce)
	knockback = kb
	owner_weapon = weapon_node
	if debug_boomerang_speed:
		print("[Boomerang] spawn speed=", speed)

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_t += delta
	lifetime -= delta
	if lifetime <= 0.0:
		emit_signal("returned", owner_weapon)
		queue_free()
		return
	rotation += deg_to_rad(spin_speed_deg) * delta
	if _state_outward:
		_do_outward(delta)
	else:
		_do_return(delta)

# -----------------------------------------------------------------------------
# Outward / Return
# -----------------------------------------------------------------------------
func _do_outward(delta: float) -> void:
	global_position += velocity * delta
	var dist: float = _spawn_pos.distance_to(global_position)
	var timed_out: bool = _t >= return_after_sec
	var too_far: bool = dist >= max_out_distance
	if timed_out:
		_state_outward = false
	if not _state_outward and not timed_out and too_far:
		_state_outward = false

func _do_return(delta: float) -> void:
	var target_pos: Vector2 = _spawn_pos
	if owner_weapon and is_instance_valid(owner_weapon) and owner_weapon is Node2D:
		target_pos = (owner_weapon as Node2D).global_position
	var want_dir: Vector2 = global_position.direction_to(target_pos)
	var cur_dir: Vector2 = velocity.normalized()
	var max_step: float = deg_to_rad(return_turn_rate_deg) * delta
	var ang: float = cur_dir.angle_to(want_dir)
	var step: float = min(abs(ang), max_step) * (-1.0 if ang < 0.0 else 1.0)
	var new_dir: Vector2 = cur_dir.rotated(step)
	var speed_now: float = speed * max(0.01, return_speed_mult)
	velocity = new_dir * speed_now
	global_position += velocity * delta
	if global_position.distance_to(target_pos) <= return_snap_distance:
		emit_signal("returned", owner_weapon)
		queue_free()

# -----------------------------------------------------------------------------
# Hit handling
# -----------------------------------------------------------------------------
func _try_hit(node: Node) -> void:
	if node == null:
		return
	if not node.has_method("take_hit"):
		return
	var id: int = node.get_instance_id()
	var bag: Dictionary = _hit_ids_out if _state_outward else _hit_ids_back
	if bag.has(id):
		return
	node.call("take_hit", damage)
	if knockback > 0.0 and node is CharacterBody2D:
		var body: CharacterBody2D = node as CharacterBody2D
		var dir: Vector2 = (body.global_position - global_position).normalized()
		body.velocity += dir * knockback
	bag[id] = true

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _on_area_entered(area: Area2D) -> void:
	var owner_node: Node = area.get_parent()
	if owner_node != null and owner_node.has_method("take_hit"):
		_try_hit(owner_node)
