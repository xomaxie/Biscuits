extends Node2D

@export var enemy_scene: PackedScene
@export var spawn_margin: float = 48.0          # how far off-screen edges to spawn
@export var spawn_interval: float = 0.9
@export var max_enemies: int = 120

var _enabled := false
var _timer := 0.0
var _nexus: Node2D
var _container: Node

func configure(nexus: Node2D, container: Node) -> void:
	_nexus = nexus
	_container = container

func set_enabled(flag: bool) -> void:
	_enabled = flag
	_timer = 0.0

func set_spawn_interval(seconds: float) -> void:
	spawn_interval = max(0.05, seconds)

func _physics_process(delta: float) -> void:
	if not _enabled or enemy_scene == null or _nexus == null or _container == null:
		return
	if _container.get_child_count() >= max_enemies:
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_one()

func _spawn_one() -> void:
	# Spawn at a random point just off the screen edges.
	var vp := get_viewport()
	if vp == null: return
	var rect := vp.get_visible_rect()
	var side := randi() % 4  # 0 top, 1 right, 2 bottom, 3 left

	var pos := Vector2.ZERO
	match side:
		0: pos = Vector2(randf_range(rect.position.x, rect.end.x), rect.position.y - spawn_margin)
		1: pos = Vector2(rect.end.x + spawn_margin, randf_range(rect.position.y, rect.end.y))
		2: pos = Vector2(randf_range(rect.position.x, rect.end.x), rect.end.y + spawn_margin)
		3: pos = Vector2(rect.position.x - spawn_margin, randf_range(rect.position.y, rect.end.y))

	var e := enemy_scene.instantiate()
	_container.add_child(e)
	if e is Node2D:
		e.global_position = pos
	# Optional: tell the enemy where to go if it wants a direct reference
	if e.has_method("set_target"):
		e.set_target(_nexus)
