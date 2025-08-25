extends CharacterBody2D

@export var move_speed: float = 230.0

@onready var weapon_manager: Node2D    = $WeaponManager
@onready var cam: Camera2D             = $Camera2D
@onready var sprite: AnimatedSprite2D  = $Sprite2D

var _last_dir: Vector2 = Vector2.DOWN  # default face "Backward" (toward camera, +Y)

func _ready() -> void:
	add_to_group("player")
	# Camera: make current & snap on first frame
	if cam and not cam.is_current():
		cam.make_current()
	if cam:
		var was_smoothing := cam.position_smoothing_enabled
		cam.position_smoothing_enabled = false
		await get_tree().process_frame
		cam.position_smoothing_enabled = was_smoothing

	# show initial idle
	_play_anim(_compose_name(false, _last_dir))

func _physics_process(_dt: float) -> void:
	var v: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = v.normalized() * move_speed
	move_and_slide()

	var moving := v.length() > 0.001
	if moving:
		_last_dir = v
	var dir := _last_dir
	if moving:
		dir = v
	_play_anim(_compose_name(moving, dir))

# ---------------- Animation selection ----------------

func _compose_name(moving: bool, dir: Vector2) -> String:
	var n := dir.normalized()

	var sx := 0
	if n.x > 0.35:
		sx = 1
	elif n.x < -0.35:
		sx = -1

	var sy := 0
	if n.y > 0.35:
		sy = 1           # +Y = Backward (facing camera)
	elif n.y < -0.35:
		sy = -1          # -Y = Forward (looking away)

	var horiz := ""
	if sx == 1:
		horiz = "Right"
	elif sx == -1:
		horiz = "Left"

	var vert := ""
	if sy == 1:
		vert = "Backward"
	elif sy == -1:
		vert = "Forward"

	var base := "Run"
	if not moving:
		base = "Idle"

	var candidates: Array[String] = []
	if horiz != "" and vert != "":
		candidates.append(base + horiz + vert)   # e.g. RunRightBackward
	if horiz != "":
		candidates.append(base + horiz)          # e.g. RunRight
	if vert != "":
		candidates.append(base + vert)           # e.g. RunBackward
	candidates.append(base)                      # e.g. Run / Idle

	return _first_existing_animation(candidates)

func _first_existing_animation(cands: Array[String]) -> String:
	if sprite == null or sprite.sprite_frames == null:
		return ""
	var names := sprite.sprite_frames.get_animation_names()
	for name in cands:
		if name in names:
			return name
	return ""

func _play_anim(name: String) -> void:
	if name == "" or sprite == null:
		return
	if sprite.animation != name:
		sprite.play(name)
