extends Control

@export_file("*.tscn") var next_scene: String = "res://scenes/Game.tscn"
@export var auto_continue_after: float = 0.0 

var _can_start := false
var _blink_t := 0.0

func _ready() -> void:
	assert($Fade is ColorRect)
	assert($Bg is ColorRect)
	assert($Center/VBox/Title is Label)
	assert($Center/VBox/Objective is Label)
	assert($Center/VBox/HSeparator is HSeparator)
	assert($Center/VBox/Tips is RichTextLabel)
	assert($Center/VBox/AnyKey is Label)

	$Fade.color.a = 1.0
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property($Fade, "color:a", 0.0, 0.6)
	await t.finished

	_can_start = true

	if auto_continue_after > 0.0:
		await get_tree().create_timer(auto_continue_after).timeout
		if _can_start:
			_start_game()

func _process(delta: float) -> void:
	_blink_t += delta
	var a := 0.45 + 0.35 * sin(_blink_t * 4.0)
	$Center/VBox/AnyKey.modulate.a = clamp(a, 0.1, 0.85)

func _unhandled_input(event: InputEvent) -> void:
	if not _can_start:
		return
	if (event is InputEventKey and event.pressed) \
	or (event is InputEventMouseButton and event.pressed) \
	or (event is InputEventJoypadButton and event.pressed):
		_start_game()

func _start_game() -> void:
	_can_start = false
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property($Fade, "color:a", 1.0, 0.35)
	await t.finished
	get_tree().change_scene_to_file(next_scene)
