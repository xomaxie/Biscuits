extends CharacterBody2D

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var move_speed: float = 230.0

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
@onready var weapon_manager: Node2D    = $WeaponManager
@onready var cam: Camera2D             = $Camera2D
@onready var sprite: AnimatedSprite2D  = $Sprite2D

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
var current_speed: float = 230.0
var _last_dir: Vector2 = Vector2.DOWN

var _gs: Node = null
var _last_movespeed_level: int = -999

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("player")

	_gs = get_node_or_null("/root/GameState")

	_apply_move_speed_upgrade()
	if _gs:
		_gs.upgrades_changed.connect(_on_upgrades_changed)

	if cam and not cam.is_current():
		cam.make_current()
	if cam:
		var was_smoothing: bool = cam.position_smoothing_enabled
		cam.position_smoothing_enabled = false
		await get_tree().process_frame
		cam.position_smoothing_enabled = was_smoothing

	_play_anim(_compose_name(false, _last_dir))

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(_dt: float) -> void:
	_try_refresh_speed_from_gamestate()

	var v: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = v.normalized() * current_speed
	move_and_slide()

	var moving: bool = v.length() > 0.001
	if moving:
		_last_dir = v
	var dir: Vector2 = _last_dir
	if moving:
		dir = v
	_play_anim(_compose_name(moving, dir))

# -----------------------------------------------------------------------------
# Upgrades
# -----------------------------------------------------------------------------
func _on_upgrades_changed() -> void:
	_apply_move_speed_upgrade()

func _apply_move_speed_upgrade() -> void:
	var lvl: int = 0
	if _gs and _gs.has_method("get_upgrade"):
		lvl = _gs.get_upgrade("movespeed", 0)
	_last_movespeed_level = lvl
	current_speed = move_speed + 40.0 * float(lvl)

func _try_refresh_speed_from_gamestate() -> void:
	if _gs and _gs.has_method("get_upgrade"):
		var lvl_now: int = _gs.get_upgrade("movespeed", 0)
		if lvl_now != _last_movespeed_level:
			_last_movespeed_level = lvl_now
			current_speed = move_speed + 40.0 * float(lvl_now)

# -----------------------------------------------------------------------------
# Animation selection
# -----------------------------------------------------------------------------
func _compose_name(moving: bool, dir: Vector2) -> String:
	var n: Vector2 = dir.normalized()

	var sx: int = 0
	if n.x > 0.35:
		sx = 1
	elif n.x < -0.35:
		sx = -1

	var sy: int = 0
	if n.y > 0.35:
		sy = 1
	elif n.y < -0.35:
		sy = -1

	var horiz: String = ""
	if sx == 1:
		horiz = "Right"
	elif sx == -1:
		horiz = "Left"

	var vert: String = ""
	if sy == 1:
		vert = "Backward"
	elif sy == -1:
		vert = "Forward"

	var base: String = "Run"
	if not moving:
		base = "Idle"

	var candidates: Array[String] = []
	if horiz != "" and vert != "":
		candidates.append(base + horiz + vert)
	if horiz != "":
		candidates.append(base + horiz)
	if vert != "":
		candidates.append(base + vert)
	candidates.append(base)

	return _first_existing_animation(candidates)

func _first_existing_animation(cands: Array[String]) -> String:
	if sprite == null or sprite.sprite_frames == null:
		return ""
	var names: PackedStringArray = sprite.sprite_frames.get_animation_names()
	for name in cands:
		if name in names:
			return name
	return ""

func _play_anim(name: String) -> void:
	if name == "" or sprite == null:
		return
	if sprite.animation != name:
		sprite.play(name)
