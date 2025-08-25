extends Area2D
class_name BarrelPickup

signal collected(value:int)

@export var max_speed:float = 560.0
@export var accel:float = 1200.0
@export var magnet_radius:float = 160.0
@export var idle_drift_speed:float = 22.0
@export var lifetime:float = 12.0
@export var fade_time:float = 0.5
@export var auto_rotate:bool = true

var value:int = 1

@export var sfx_collect_path:NodePath
@export var sfx_spawn_path:NodePath
@export var anim_player_path:NodePath

var _vel:Vector2 = Vector2.ZERO
var _player:Node2D
var _age:float = 0.0
var _fading:bool = false
var _spawned:bool = false

@onready var _shape:CollisionShape2D = $CollisionShape2D if has_node("CollisionShape2D") else null
@onready var _sprite:CanvasItem = $Sprite2D if has_node("Sprite2D") else self
@onready var _ap:AnimationPlayer = get_node_or_null(anim_player_path) if anim_player_path != NodePath() else get_node_or_null("AnimationPlayer")
@onready var _sfx_collect:AudioStreamPlayer = get_node_or_null(sfx_collect_path) if sfx_collect_path != NodePath() else get_node_or_null("SFX_Collect")
@onready var _sfx_spawn:AudioStreamPlayer = get_node_or_null(sfx_spawn_path) if sfx_spawn_path != NodePath() else get_node_or_null("SFX_Spawn")

func init_with_value(v:int) -> BarrelPickup:
	if v < 1:
		value = 1
	else:
		value = v
	return self

func _ready() -> void:
	monitoring = true
	monitorable = true
	if not _spawned:
		_spawn_pop()

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node2D

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta:float) -> void:
	if _fading:
		return

	_age += delta
	if _age >= lifetime:
		_start_fade()
		return

	var should_magnet:bool = false
	var dir:Vector2 = Vector2.ZERO

	if _player:
		var to_p := _player.global_position - global_position
		var d := to_p.length()
		if d <= magnet_radius and d > 0.001:
			should_magnet = true
			dir = to_p / d

	if should_magnet:
		_vel = _vel.move_toward(dir * max_speed, accel * delta)
	else:
		var jitter := Vector2(randf() - 0.5, randf() - 0.5)
		if jitter.length() > 0.0:
			jitter = jitter.normalized()
		_vel = _vel.move_toward(jitter * idle_drift_speed, accel * 0.25 * delta)

	global_position += _vel * delta

	if auto_rotate and _vel.length() > 1.0:
		rotation = _vel.angle()

func _on_body_entered(b:Node) -> void:
	_try_collect(b)

func _on_area_entered(a:Area2D) -> void:
	_try_collect(a)

func _try_collect(other:Node) -> void:
	var is_player := false
	if other.is_in_group("player"):
		is_player = true
	elif other.get_parent() and other.get_parent().is_in_group("player"):
		is_player = true

	if is_player:
		_collect()

func _collect() -> void:
	if _fading:
		return
	emit_signal("collected", value)

	if Engine.has_singleton("GameState"):
		GameState.add_biscuits(value)
	else:
		var scene := get_tree().current_scene
		if scene and scene.has_method("add_biscuits"):
			scene.add_biscuits(value)

	if _sfx_collect:
		_sfx_collect.play()

	if _shape:
		_shape.disabled = true
	monitoring = false
	_start_fade(true)

func _start_fade(fast:bool=false) -> void:
	_fading = true
	var t:float = fade_time
	if fast:
		if fade_time * 0.5 > 0.12:
			t = fade_time * 0.5
		else:
			t = 0.12

	if _ap and _ap.has_animation("fade"):
		_ap.play("fade")
		await _ap.animation_finished
		queue_free()
		return

	var ci:CanvasItem = _sprite
	if ci == null:
		ci = self

	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(ci, "modulate:a", 0.0, t)
	if ci.has_method("set_scale"):
		tw.parallel().tween_property(ci, "scale", ci.scale * 1.15, t)
	await tw.finished
	queue_free()

func _spawn_pop() -> void:
	_spawned = true
	if _sfx_spawn:
		_sfx_spawn.play()

	var ci:CanvasItem = _sprite
	if ci == null:
		ci = self
	ci.scale = ci.scale * 0.6
	ci.modulate.a = 0.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(ci, "scale", ci.scale * (1.0 / 0.6), 0.18)
	tw.parallel().tween_property(ci, "modulate:a", 1.0, 0.12)
