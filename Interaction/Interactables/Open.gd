extends Node2D

# What the prompt should show: "[E] to <action_name>"
@export var action_name: String = "open"

# Optional: simple one-shot cooldown to avoid spam
@export var interact_cooldown: float = 0.25
var _can_use: bool = true
var is_open: bool = false   # start closed

@onready var interaction_area: InteractionArea = $InteractionArea
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
@onready var anim_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var door_collision: Node = get_node_or_null("StaticBody2D/doorcollision")

func _ready() -> void:
	if interaction_area == null:
		push_error("%s: No InteractionArea child found. Add an Area2D with the InteractionArea script." % name)
		return

	# Initial prompt text and hook
	interaction_area.action_name = _action_text()
	interaction_area.interact = Callable(self, "_on_interact")
	print("DEBUG: %s registered interact '%s'." % [name, action_name])

func _on_interact() -> void:
	if not _can_use:
		return
	_can_use = false
	print("DEBUG: Interacted with %s" % name)

	# Toggle state
	_set_open_state(not is_open)

	await get_tree().create_timer(interact_cooldown).timeout
	_can_use = true

func _set_open_state(open: bool) -> void:
	is_open = open

	# 1) Play the right animation
	var anim_name := "Open" if is_open else "Close"
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
	elif anim and anim.sprite_frames and anim.sprite_frames.has_animation(anim_name):
		anim.play(anim_name)

	# 2) Toggle the collider
	if is_instance_valid(door_collision):
		door_collision.disabled = is_open  # disable when open, enable when closed
		print("DEBUG: doorcollision %s" % ("DISABLED (open)" if is_open else "ENABLED (closed)"))

	# 3) Update prompt text for InteractionManager
	if is_instance_valid(interaction_area):
		interaction_area.action_name = _action_text()

func _action_text() -> String:
	return "Close" if is_open else "Open"
