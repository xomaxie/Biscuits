# res://autoload/FontSetup.gd
extends Node

# -----------------------------------------------------------------------------
# Global default font with fallback
# -----------------------------------------------------------------------------
func _ready() -> void:
	var main := FontFile.new()
	main.load("res://fonts/superstarorig_memesbruh03.ttf")

	var fb := FontFile.new()
	fb.load("res://fonts/Roboto-Bold.ttf")

	main.fallbacks = [fb]

	var theme := Theme.new()
	theme.set_default_font(main)
	get_tree().root.theme = theme
