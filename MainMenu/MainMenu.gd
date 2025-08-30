extends Control

# -----------------------------------------------------------------------------
# Scene paths
# -----------------------------------------------------------------------------
const START_SCENE: String = "res://intro.tscn"
const TEST_SCENE: String = "res://scenes/Test.tscn"

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
@onready var _menu_container: Node = get_node("UI/MainContainer/VBoxContainer/MenuButtons")
@onready var _overlay: CanvasLayer = get_node_or_null("LoadingOverlay")
@onready var _status: Label = get_node_or_null("LoadingOverlay/PanelContainer/VBox/Status")
@onready var _bar: ProgressBar = get_node_or_null("LoadingOverlay/PanelContainer/VBox/Bar")

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var _loading: bool = false
var _progress_supported: bool = false

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_style_menu_buttons()
	_start_music_preload()

# -----------------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not _loading:
		_on_start_btn_button_down()

# -----------------------------------------------------------------------------
# Button callbacks
# -----------------------------------------------------------------------------
func _on_start_btn_button_down() -> void:
	get_tree().change_scene_to_file(START_SCENE)

func _on_test_level_btn_button_down() -> void:
	if _loading:
		return
	get_tree().change_scene_to_file(TEST_SCENE)

func _on_settings_btn_2_button_down() -> void:
	if _loading:
		return
	get_tree().change_scene_to_file("res://MainMenu/Settings.tscn")

func _on_credits_btn_button_down() -> void:
	if _loading:
		return
	get_tree().change_scene_to_file("res://MainMenu/Credits.tscn")

func _on_quit_btn_button_down() -> void:
	if _loading:
		return
	get_tree().quit()

# -----------------------------------------------------------------------------
# Loading flow
# -----------------------------------------------------------------------------
func _start_music_preload() -> void:
	var idx: int = AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(idx, -12.0)

	var mm: Node = get_node_or_null("/root/MusicManager")
	if mm == null:
		return

	_set_loading(true, "Loading music...")

	var has_ready_sig: bool = mm.has_method("when_ready")
	var has_ready_bool: bool = mm.has_method("is_ready")
	var has_preload: bool = mm.has_method("preload_all")
	var has_progress: bool = mm.has_method("get_progress")
	_progress_supported = has_progress

	if _bar:
		if _progress_supported:
			_bar.show()
		else:
			_bar.hide()

	if has_ready_sig:
		var sig: Signal = mm.call("when_ready") as Signal
		if has_preload:
			mm.call("preload_all")
		_set_status("Loading music...")
		if _progress_supported:
			_update_progress_bar(mm)
		await sig
		_finish_loading(mm)
		return

	if has_ready_bool:
		if has_preload:
			mm.call("preload_all")
		_set_status("Loading music...")
		await _poll_until_ready(mm, 0.05, 10.0)
		_finish_loading(mm)
		return

	if has_preload:
		_set_status("Loading music...")
		mm.call("preload_all")
		await get_tree().process_frame
		_finish_loading(mm)
		return

	_finish_loading(mm)

func _poll_until_ready(mm: Node, dt: float, timeout: float) -> void:
	var elapsed: float = 0.0
	while elapsed < timeout:
		if _progress_supported:
			_update_progress_bar(mm)
		var ready: bool = false
		if mm.has_method("is_ready"):
			ready = bool(mm.call("is_ready"))
		if ready:
			return
		elapsed += dt
		await get_tree().create_timer(dt, true).timeout

func _update_progress_bar(mm: Node) -> void:
	if _bar == null:
		return
	var p: float = 0.0
	if mm.has_method("get_progress"):
		p = clamp(float(mm.call("get_progress")), 0.0, 1.0)
	_bar.value = p * 100.0

func _finish_loading(mm: Node) -> void:
	if mm.has_method("play_title"):
		mm.call("play_title")
	_set_loading(false, "")

# -----------------------------------------------------------------------------
# UI helpers
# -----------------------------------------------------------------------------
func _set_loading(enabled: bool, msg: String) -> void:
	_loading = enabled
	_toggle_menu_buttons(not enabled)
	if _overlay:
		_overlay.visible = enabled
	_set_status(msg)

func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg

func _toggle_menu_buttons(enable: bool) -> void:
	if _menu_container == null:
		return
	for child in _menu_container.get_children():
		if child is Button:
			child.disabled = not enable

func _style_menu_buttons() -> void:
	if _menu_container is VBoxContainer or _menu_container is HBoxContainer:
		_menu_container.add_theme_constant_override("separation", 12)
	for child in _menu_container.get_children():
		if child is Button:
			var normal := StyleBoxFlat.new()
			normal.bg_color = Color.html("#1e293b")
			normal.border_color = Color.html("#fbbf24")
			normal.set_border_width_all(1)
			normal.set_corner_radius_all(2)
			normal.set_content_margin(SIDE_LEFT, 12)
			normal.set_content_margin(SIDE_RIGHT, 12)
			normal.set_content_margin(SIDE_TOP, 8)
			normal.set_content_margin(SIDE_BOTTOM, 8)
			child.add_theme_stylebox_override("normal", normal)

			var hover := normal.duplicate() as StyleBoxFlat
			hover.bg_color = Color.html("#334155")
			child.add_theme_stylebox_override("hover", hover)

			var pressed := normal.duplicate() as StyleBoxFlat
			pressed.bg_color = Color.html("#0f172a")
			child.add_theme_stylebox_override("pressed", pressed)

			var disabled := normal.duplicate() as StyleBoxFlat
			disabled.bg_color = Color.html("#111827")
			disabled.border_color = Color(0.25, 0.25, 0.25)
			child.add_theme_stylebox_override("disabled", disabled)

			var focus := normal.duplicate() as StyleBoxFlat
			focus.border_color = Color.html("#fbbf24")
			focus.set_border_width_all(2)
			child.add_theme_stylebox_override("focus", focus)

			child.custom_minimum_size = Vector2(240, 48)
			child.add_theme_color_override("font_color", Color.html("#e2e8f0"))
			child.add_theme_color_override("font_hover_color", Color.html("#ffffff"))
			child.add_theme_color_override("font_pressed_color", Color.html("#facc15"))
