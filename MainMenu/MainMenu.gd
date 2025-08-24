extends Control

# Adjust these paths to match your project’s scene files
const START_SCENE := "res://scenes/dungeon.tscn"
const TEST_SCENE  := "res://scenes/Test.tscn"

func _on_start_btn_button_down() -> void:
	print("DEBUG: Start button pressed, loading ", START_SCENE)
	get_tree().change_scene_to_file(START_SCENE)

func _on_test_level_btn_button_down() -> void:
	print("DEBUG: Test Level button pressed, loading ", TEST_SCENE)
	get_tree().change_scene_to_file(TEST_SCENE)

func _on_settings_btn_2_button_down() -> void:
	print("DEBUG: Settings button pressed")
	# TODO: open settings scene / popup
	# get_tree().change_scene_to_file("res://scenes/settings.tscn")

func _on_credits_btn_button_down() -> void:
	print("DEBUG: Credits button pressed")
	# TODO: open credits scene
	# get_tree().change_scene_to_file("res://scenes/credits.tscn")

func _on_quit_btn_button_down() -> void:
	print("DEBUG: Quit button pressed")
	get_tree().quit()
