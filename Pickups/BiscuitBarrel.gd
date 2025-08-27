extends StaticBody2D
class_name BiscuitBarrel

# -----------------------------------------------------------------------------
# Exports (tuning)
# -----------------------------------------------------------------------------
@export var base_value: int = 1
@export var value_per_px: float = 0.01
@export var min_value: int = 1
@export var max_value: int = 12
@export var min_radius_for_bonus: float = 0.0

@export var max_hp: int = 6
@export var drip_interval: float = 2.4
@export var burst_count: int = 8
@export var drip_impulse: float = 220.0
@export var burst_impulse_min: float = 260.0
@export var burst_impulse_max: float = 420.0

@export var pickup_scene: PackedScene
@export var nexus_path: NodePath

@export var scatter_radius: float = 46.0

@export var target_budget_min: int = 12
@export var target_budget_max: int = 40

@export var enable_wave_scaling: bool = true
@export var wave_min: int = 1
@export var wave_max: int = 10

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var _hp: int
var _nexus: Node2D
var _gs: Node = null
var _remaining_budget: int = 0
var _wave_factor: float = 1.0

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("enemies")
	add_to_group("barrels")

	_hp = max_hp
	_resolve_nexus()
	_gs = get_node_or_null("/root/GameState")

	_compute_wave_scalars()
	_setup_budget()

	var t: Timer = $DripTimer if has_node("DripTimer") else null
	if t:
		t.wait_time = max(0.25, drip_interval / _wave_factor)
		t.autostart = true
		t.timeout.connect(_on_drip_timeout)

# -----------------------------------------------------------------------------
# Nexus resolution
# -----------------------------------------------------------------------------
func _resolve_nexus() -> void:
	if nexus_path != NodePath():
		_nexus = get_node_or_null(nexus_path) as Node2D
	if _nexus == null:
		var arr: Array = get_tree().get_nodes_in_group("nexus")
		if arr.size() > 0:
			_nexus = arr[0] as Node2D

# -----------------------------------------------------------------------------
# Wave scaling and budget
# -----------------------------------------------------------------------------
func _get_wave_index() -> int:
	if _gs and _gs.has_method("get_wave"):
		var w: int = int(_gs.get_wave())
		return max(1, w)
	return 1

func _normalized_wave() -> float:
	var w: int = clamp(_get_wave_index(), wave_min, wave_max)
	var span: int = max(1, wave_max - wave_min)
	return float(w - wave_min) / float(span)

func _compute_wave_scalars() -> void:
	if not enable_wave_scaling:
		_wave_factor = 1.0
		return
	var t: float = _normalized_wave()
	_wave_factor = lerpf(0.7, 1.6, t)

func _setup_budget() -> void:
	var t: float = _normalized_wave() if enable_wave_scaling else 0.5
	var per_barrel: int = int(round(lerpf(
		float(target_budget_min),
		float(target_budget_max),
		t
	)))
	per_barrel += _get_barrel_bonus_count()
	_remaining_budget = max(0, per_barrel)

# -----------------------------------------------------------------------------
# Damage
# -----------------------------------------------------------------------------
func take_hit(damage: int = 1) -> void:
	_hp -= damage
	_play_hit_anim()
	if _hp <= 0:
		_burst()
		_play_break_anim()
		queue_free()

# -----------------------------------------------------------------------------
# Drip timer
# -----------------------------------------------------------------------------
func _on_drip_timeout() -> void:
	_drip_one()

func _drip_one() -> void:
	if pickup_scene == null:
		return
	if _remaining_budget <= 0:
		return
	var value: int = _compute_pickup_value(global_position)
	value = min(value, _remaining_budget)
	_remaining_budget -= value
	_spawn_pickup(global_position, value, drip_impulse)

# -----------------------------------------------------------------------------
# Burst on destroy
# -----------------------------------------------------------------------------
func _burst() -> void:
	if pickup_scene == null:
		return

	var count: int = int(round(float(burst_count) * _wave_factor))
	count = max(1, count)

	for i in count:
		if _remaining_budget <= 0:
			break
		var angle: float = (
			float(i) / float(max(1, count))
		) * TAU + randf() * 0.35
		var dir: Vector2 = Vector2.RIGHT.rotated(angle)
		var pos: Vector2 = global_position + dir * (randf() * scatter_radius)
		var value: int = _compute_pickup_value(pos)
		value = min(value, _remaining_budget)
		_remaining_budget -= value
		var impulse: float = lerpf(
			burst_impulse_min, burst_impulse_max, randf()
		)
		_spawn_pickup(pos, value, impulse)

	while _remaining_budget > 0:
		var ang: float = randf() * TAU
		var dir2: Vector2 = Vector2.RIGHT.rotated(ang)
		var pos2: Vector2 = global_position + dir2 * (randf() * scatter_radius)
		var v: int = min(1, _remaining_budget)
		_remaining_budget -= v
		var imp: float = lerpf(burst_impulse_min, burst_impulse_max, randf())
		_spawn_pickup(pos2, v, imp)

# -----------------------------------------------------------------------------
# Extra pickups (bonus count)
# -----------------------------------------------------------------------------
func _get_barrel_bonus_count() -> int:
	if _gs and _gs.has_method("get_crate_bonus_biscuits"):
		var v: int = _gs.get_crate_bonus_biscuits()
		return max(0, v)
	return 0

# -----------------------------------------------------------------------------
# Spawn helper
# -----------------------------------------------------------------------------
func _spawn_pickup(pos: Vector2, value: int, impulse: float) -> void:
	var p := pickup_scene.instantiate()
	if p == null:
		return

	if p.has_method("init_with_value"):
		p.call("init_with_value", value)
	elif p.has_method("set_value"):
		p.call("set_value", value)

	p.global_position = pos
	get_tree().current_scene.add_child(p)

	var dir: Vector2 = (p.global_position - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	var vel: Vector2 = dir * impulse

	if p.has_method("set_initial_impulse"):
		p.call("set_initial_impulse", vel)
	elif p.has_method("set_velocity"):
		p.call("set_velocity", vel)
	else:
		p.global_position += dir * (impulse * get_physics_process_delta_time())

# -----------------------------------------------------------------------------
# Value computation
# -----------------------------------------------------------------------------
func _compute_pickup_value(world_pos: Vector2) -> int:
	if _nexus == null:
		_resolve_nexus()

	var dist: float = 0.0
	if _nexus:
		dist = _nexus.global_position.distance_to(world_pos)

	var bonus_dist: float = max(0.0, dist - min_radius_for_bonus)
	var scaled_f: float = float(base_value) + bonus_dist * value_per_px
	scaled_f *= _wave_factor

	var scaled: int = int(round(scaled_f))
	scaled = clamp(scaled, min_value, max_value)
	return scaled

# -----------------------------------------------------------------------------
# Visuals
# -----------------------------------------------------------------------------
func _play_hit_anim() -> void:
	var ap := get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("Hit"):
		ap.play("Hit")

func _play_break_anim() -> void:
	var ap := get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("Break"):
		ap.play("Break")
