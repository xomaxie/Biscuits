extends Control



func _on_back_btn_button_down() -> void:
	print("DEBUG: Credits button pressed")
	get_tree().change_scene_to_file("res://MainMenu/Red.tscn")
