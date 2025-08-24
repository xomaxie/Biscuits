extends CharacterBody2D

@export var move_speed: float = 230.0

@onready var weapon_manager: Node2D = $WeaponManager
@onready var cam: Camera2D = $Camera2D

func _physics_process(_delta: float) -> void:
	var input_vec := Input.get_vector("move_left", "move_right", "move_up", "move_down").normalized()
	velocity = input_vec * move_speed
	move_and_slide()

func _ready() -> void:
	# Make it the active camera and snap on the first frame
	if not cam.is_current():
		cam.make_current()
	var was_smoothing := cam.position_smoothing_enabled
	cam.position_smoothing_enabled = false
	await get_tree().process_frame
	cam.position_smoothing_enabled = was_smoothing
