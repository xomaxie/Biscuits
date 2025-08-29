extends Control

# -----------------------------------------------------------------------------
# Scene paths
# -----------------------------------------------------------------------------
const START_SCENE: String = "res://intro.tscn"
const TEST_SCENE: String = "res://scenes/Test.tscn"

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	var mm: Node = get_node_or_null("/root/MusicManager")
	if mm:
		if mm.has_method("preload_all"):
			mm.call("preload_all")
		mm.call("play_title")
	var idx := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(idx, -12.0)

# -----------------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_start_btn_button_down()

# -----------------------------------------------------------------------------
# Button callbacks
# -----------------------------------------------------------------------------
func _on_start_btn_button_down() -> void:
	get_tree().change_scene_to_file(START_SCENE)

func _on_test_level_btn_button_down() -> void:
	get_tree().change_scene_to_file(TEST_SCENE)

func _on_settings_btn_2_button_down() -> void:
	pass

func _on_credits_btn_button_down() -> void:
	get_tree().change_scene_to_file("res://MainMenu/Credits.tscn")

func _on_quit_btn_button_down() -> void:
	get_tree().quit()
