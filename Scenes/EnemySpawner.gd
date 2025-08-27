extends Node2D

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var enemy_scene: PackedScene
@export var spawn_margin: float = 48.0
@export var spawn_interval: float = 0.9
@export var max_enemies: int = 120

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
var _enabled: bool = false
var _timer: float = 0.0
var _nexus: Node2D = null
var _container: Node = null
var _gs: Node = null

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	randomize()
	_gs = get_node_or_null("/root/GameState")
	if _gs:
		_gs.phase_changed.connect(_on_phase_changed)
		_gs.wave_changed.connect(_on_wave_changed)
		_on_phase_changed(int(_gs.phase))

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
func configure(nexus: Node2D, container: Node) -> void:
	_nexus = nexus
	_container = container

func set_enabled(flag: bool) -> void:
	_enabled = flag
	_timer = 0.0

func set_spawn_interval(seconds: float) -> void:
	spawn_interval = max(0.05, seconds)

# -----------------------------------------------------------------------------
# Signals from GameState
# -----------------------------------------------------------------------------
func _on_phase_changed(new_phase: int) -> void:
	if _gs == null:
		return
	if new_phase == _gs.Phase.WAVE:
		set_enabled(true)
	else:
		set_enabled(false)

func _on_wave_changed(new_wave: int) -> void:
	var waves: int = max(0, new_wave - 1)
	var mult: float = pow(0.97, float(waves))
	var base: float = spawn_interval * mult
	if base < 0.2:
		base = 0.2
	set_spawn_interval(base)

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not _enabled:
		return
	if enemy_scene == null or _nexus == null or _container == null:
		return
	if _enemy_count_in_container() >= max_enemies:
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_one()

# -----------------------------------------------------------------------------
# Spawning
# -----------------------------------------------------------------------------
func _spawn_one() -> void:
	var rect: Rect2 = _get_world_visible_rect()
	if rect.size == Vector2.ZERO:
		return

	var side: int = randi() % 4
	var pos: Vector2 = Vector2.ZERO
	match side:
		0:
			pos = Vector2(
				randf_range(rect.position.x, rect.position.x + rect.size.x),
				rect.position.y - spawn_margin
			)
		1:
			pos = Vector2(
				rect.position.x + rect.size.x + spawn_margin,
				randf_range(rect.position.y, rect.position.y + rect.size.y)
			)
		2:
			pos = Vector2(
				randf_range(rect.position.x, rect.position.x + rect.size.x),
				rect.position.y + rect.size.y + spawn_margin
			)
		3:
			pos = Vector2(
				rect.position.x - spawn_margin,
				randf_range(rect.position.y, rect.position.y + rect.size.y)
			)

	var e: Node = enemy_scene.instantiate()
	if e == null:
		return

	if _nexus != null:
		var nexus_path: NodePath = _nexus.get_path()
		if _has_property(e, "target_path"):
			e.set("target_path", nexus_path)

	_container.add_child(e)

	if e is Node2D:
		(e as Node2D).global_position = pos

	if _nexus != null and e.has_method("set_target"):
		e.set_target(_nexus)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _enemy_count_in_container() -> int:
	if _container == null:
		return 0
	var n: int = 0
	for c in _container.get_children():
		if c is Node and (c as Node).is_in_group("enemies"):
			n += 1
	return n

func _get_world_visible_rect() -> Rect2:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		var center: Vector2 = cam.get_screen_center_position()
		var vp_size: Vector2 = get_viewport_rect().size
		var half: Vector2 = vp_size * 0.5 * cam.zoom
		var top_left: Vector2 = center - half
		return Rect2(top_left, vp_size * cam.zoom)
	return Rect2(get_viewport().get_visible_rect())

func _has_property(obj: Object, prop: String) -> bool:
	var plist: Array = obj.get_property_list()
	for p_v in plist:
		var p: Dictionary = p_v
		if p.has("name") and String(p["name"]) == prop:
			return true
	return false
