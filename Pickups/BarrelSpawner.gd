extends Node2D

@export var barrel_scene:PackedScene
@export var nexus_path:NodePath
@export var spawn_interval:float = 8.0
@export var max_barrels:int = 5
@export var min_radius:float = 380.0
@export var max_radius:float = 820.0
@export var try_count:int = 10
@export var min_separation:float = 120.0
@export var per_wave_increment:int = 1
@export var clear_on_game_over:bool = true

var _nexus:Node2D
var _timer:Timer
var _barrels:={}
var _active:bool = false

func _ready() -> void:
	# Nexus
	if nexus_path != NodePath():
		_nexus = get_node(nexus_path) as Node2D

	# Timer (only runs during WAVE)
	_timer = Timer.new()
	_timer.wait_time = spawn_interval
	_timer.autostart = false
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)

	if has_node("/root/GameState"):
		GameState.phase_changed.connect(_on_phase_changed)
		GameState.run_started.connect(_on_run_started)
		GameState.run_ended.connect(_on_run_ended)
		_on_phase_changed(GameState.phase)
	else:
		_set_active(true)

func _on_run_started() -> void:
	_timer.stop()
	_clear_barrels()
	_on_phase_changed(GameState.phase)  # will set active based on PREP/WAVE

func _on_run_ended(_victory:bool) -> void:
	if clear_on_game_over:
		_clear_barrels()
	_set_active(false)

func _on_phase_changed(new_phase:int) -> void:
	# Only spawn during WAVE
	if new_phase == GameState.Phase.WAVE:
		_set_active(true)
	else:
		_set_active(false)

func _set_active(enable:bool) -> void:
	_active = enable
	if _active:
		if not _timer.is_stopped():
			_timer.stop()
		_timer.start()
	else:
		_timer.stop()

func _on_timeout() -> void:
	if not _active:
		return
	if barrel_scene == null or _nexus == null:
		return
	if _barrels.size() >= max_barrels:
		return

	var pos:Vector2 = _pick_spawn_position()
	var b := barrel_scene.instantiate() as Node2D
	if b == null:
		return
	b.global_position = pos
	get_tree().current_scene.add_child(b)
	_barrels[b.get_instance_id()] = b
	b.tree_exited.connect(func(): _barrels.erase(b.get_instance_id()))

func _pick_spawn_position() -> Vector2:
	var base := _nexus.global_position
	var i:int = 0
	while i < try_count:
		var angle := randf() * TAU
		var radius := randf_range(min_radius, max_radius)
		var candidate := base + Vector2.RIGHT.rotated(angle) * radius
		if _valid_position(candidate):
			return candidate
		i += 1
	# Fallback
	var fb_angle := randf() * TAU
	var fb_radius := randf_range(min_radius, max_radius)
	return base + Vector2.RIGHT.rotated(fb_angle) * fb_radius

func _valid_position(p:Vector2) -> bool:
	for id in _barrels:
		var b := _barrels[id] as Node2D
		if b:
			if b.global_position.distance_to(p) < min_separation:
				return false
	return true

func on_wave_started(w:int) -> void:
	if max_barrels + per_wave_increment < 1:
		max_barrels = 1
	else:
		max_barrels += per_wave_increment

func _clear_barrels() -> void:
	for id in _barrels:
		var b := _barrels[id] as Node
		if b and is_instance_valid(b):
			b.queue_free()
	_barrels.clear()
