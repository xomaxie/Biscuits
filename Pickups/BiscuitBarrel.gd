extends StaticBody2D
class_name BiscuitBarrel

@export var base_value:int = 1
@export var value_per_px:float = 0.01
@export var min_value:int = 1
@export var max_value:int = 12
@export var min_radius_for_bonus:float = 0.0

@export var max_hp:int = 6
@export var drip_interval:float = 2.4
@export var burst_count:int = 8
@export var drip_impulse:float = 140.0
@export var burst_impulse_min:float = 180.0
@export var burst_impulse_max:float = 320.0

@export var pickup_scene:PackedScene
@export var nexus_path:NodePath

@export var scatter_radius:float = 10.0

var _hp:int
var _nexus:Node2D

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("barrels")

	_hp = max_hp
	_resolve_nexus()

	var t:Timer = $DripTimer if has_node("DripTimer") else null
	if t:
		t.wait_time = drip_interval
		t.autostart = true
		t.timeout.connect(_on_drip_timeout)

func _resolve_nexus() -> void:
	if nexus_path != NodePath():
		_nexus = get_node_or_null(nexus_path) as Node2D
	if _nexus == null:
		var arr := get_tree().get_nodes_in_group("nexus")
		if arr.size() > 0:
			_nexus = arr[0] as Node2D

func take_hit(damage:int=1) -> void:
	_hp -= damage
	_play_hit_anim()
	if _hp <= 0:
		_burst()
		_play_break_anim()
		queue_free()

func _on_drip_timeout() -> void:
	_drip_one()

func _drip_one() -> void:
	if pickup_scene == null:
		return
	var value := _compute_pickup_value(global_position)
	_spawn_pickup(global_position, value, drip_impulse)

func _burst() -> void:
	if pickup_scene == null:
		return
	for i in burst_count:
		var angle := (float(i) / float(max(1, burst_count))) * TAU + randf() * 0.25
		var dir := Vector2.RIGHT.rotated(angle)
		var pos := global_position + dir * (randf() * scatter_radius)
		var value := _compute_pickup_value(pos)
		var impulse := lerpf(burst_impulse_min, burst_impulse_max, randf())
		_spawn_pickup(pos, value, impulse)

func _spawn_pickup(pos:Vector2, value:int, impulse:float) -> void:
	var p := pickup_scene.instantiate() as BarrelPickup
	if p == null:
		return
	p.global_position = pos
	p.init_with_value(value)
	get_tree().current_scene.add_child(p)

	var dir := (p.global_position - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	p.global_position += dir * (impulse * get_physics_process_delta_time())

func _compute_pickup_value(world_pos:Vector2) -> int:
	if _nexus == null:
		_resolve_nexus()
	var dist := 0.0
	if _nexus:
		dist = _nexus.global_position.distance_to(world_pos)

	var bonus_dist := dist - min_radius_for_bonus
	if bonus_dist < 0.0:
		bonus_dist = 0.0

	var scaled := base_value + int(round(bonus_dist * value_per_px))
	if scaled < min_value:
		scaled = min_value
	if scaled > max_value:
		scaled = max_value
	return scaled

func _play_hit_anim() -> void:
	var ap := get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("Hit"):
		ap.play("Hit")

func _play_break_anim() -> void:
	var ap := get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("Break"):
		ap.play("Break")
