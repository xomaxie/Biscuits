extends Control

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export_file("*.tscn") var main_menu_scene: String = "res://MainMenu/Red.tscn"
@export var pause_action: StringName = &"pause"
@export var accept_resumes: bool = true

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
@onready var _ui_root: Control = $UI
@onready var _menu_root: Control = $UI/MainContainer
@onready var _settings_root: Control = $Settings
@onready var _resume_btn: Button = $UI/MainContainer/MenuButtons/ResumeBtn
@onready var _settings_btn: Button = $UI/MainContainer/MenuButtons/SettingsBtn2
@onready var _return_btn: Button = $UI/MainContainer/MenuButtons/ReturnBtn

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var _in_settings: bool = false

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _enter_tree() -> void:
	hide()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_buttons()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_instance_valid(_settings_root):
		_settings_root.visible = false

# -----------------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(pause_action):
		if visible and not _in_settings:
			close_menu()
		elif visible and _in_settings:
			_close_settings()
		else:
			open_menu()
	elif visible and _in_settings and event.is_action_pressed("ui_cancel"):
		_close_settings()
	elif accept_resumes and visible and not _in_settings and event.is_action_pressed("ui_accept"):
		close_menu()

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------
func open_menu() -> void:
	show()
	get_tree().paused = true
	_show_menu_view()
	_focus_resume()

func close_menu() -> void:
	_close_settings()
	hide()
	get_tree().paused = false

# -----------------------------------------------------------------------------
# Button callbacks
# -----------------------------------------------------------------------------
func _on_resume_pressed() -> void:
	close_menu()

func _on_settings_pressed() -> void:
	_open_settings()

func _on_return_pressed() -> void:
	get_tree().paused = false
	if main_menu_scene != "":
		get_tree().change_scene_to_file(main_menu_scene)

# -----------------------------------------------------------------------------
# View switching
# -----------------------------------------------------------------------------
func _show_menu_view() -> void:
	_in_settings = false
	if is_instance_valid(_settings_root):
		_settings_root.visible = false
	if is_instance_valid(_ui_root):
		_ui_root.visible = true

func _open_settings() -> void:
	if not is_instance_valid(_settings_root):
		return
	_in_settings = true
	_ui_root.visible = false
	_settings_root.visible = true
	var back_btn := _settings_root.find_child("BackBtn", true, false)
	if back_btn is Button and not back_btn.pressed.is_connected(_on_settings_back_pressed):
		back_btn.pressed.connect(_on_settings_back_pressed)

func _close_settings() -> void:
	if not _in_settings:
		return
	_show_menu_view()

func _on_settings_back_pressed() -> void:
	_close_settings()

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _bind_buttons() -> void:
	if is_instance_valid(_resume_btn):
		_resume_btn.pressed.connect(_on_resume_pressed)
	if is_instance_valid(_settings_btn):
		_settings_btn.pressed.connect(_on_settings_pressed)
	if is_instance_valid(_return_btn):
		_return_btn.pressed.connect(_on_return_pressed)

func _focus_resume() -> void:
	if is_instance_valid(_resume_btn):
		_resume_btn.grab_focus()
