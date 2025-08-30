extends Control
class_name PauseSettingsUI

signal back_pressed()

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var bus_fallback: String = "Music"
@export var min_db: float = -40.0
@export var max_db: float = 0.0
@export_node_path("HSlider") var slider_path: NodePath
@export_node_path("Label") var label_path: NodePath
@export var close_on_esc: bool = true

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
var _slider: HSlider
var _label: Label

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var _bus_index: int = -1

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_bind_nodes()
	if _slider == null or _label == null:
		push_error("SettingsUI: bind failed. Set slider_path/label_path or "
			+ "ensure nodes are named 'MusicSlider' and 'Label'.")
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_bus_index()
	_init_slider()
	_sync_from_manager()
	_update_label()
	_apply_music_volume(_slider.value)

# -----------------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if close_on_esc and event.is_action_pressed("ui_cancel"):
		_on_back_button_up()

# -----------------------------------------------------------------------------
# Bind nodes
# -----------------------------------------------------------------------------
func _bind_nodes() -> void:
	if slider_path != NodePath(""):
		_slider = get_node_or_null(slider_path) as HSlider
	if label_path != NodePath(""):
		_label = get_node_or_null(label_path) as Label
	if _slider == null:
		_slider = find_child("MusicSlider", true, false) as HSlider
	if _label == null:
		_label = find_child("Label", true, false) as Label

# -----------------------------------------------------------------------------
# UI wiring
# -----------------------------------------------------------------------------
func _init_slider() -> void:
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	if not _slider.value_changed.is_connected(_on_slider_value_changed):
		_slider.value_changed.connect(_on_slider_value_changed)

func _update_label() -> void:
	var pct: int = int(round(_slider.value * 100.0))
	_label.text = "Music Volume: %d%%" % pct

func _on_slider_value_changed(v: float) -> void:
	_apply_music_volume(v)
	_update_label()

# -----------------------------------------------------------------------------
# Audio plumbing
# -----------------------------------------------------------------------------
func _init_bus_index() -> void:
	var mm: Node = get_node_or_null("/root/MusicManager")
	var bus_name: String = bus_fallback
	if mm != null:
		var from_mm: String = String(mm.get("music_bus"))
		if from_mm != "":
			bus_name = from_mm
	_bus_index = AudioServer.get_bus_index(bus_name)
	if _bus_index < 0:
		_bus_index = AudioServer.get_bus_index(bus_fallback)
	if _bus_index < 0:
		_bus_index = 0

func _apply_music_volume(unit_0_1: float) -> void:
	var u: float = clamp(unit_0_1, 0.0, 1.0)
	var db: float = _unit_to_db(u)
	AudioServer.set_bus_volume_db(_bus_index, db)
	var mm: Node = get_node_or_null("/root/MusicManager")
	if mm != null:
		if mm.has_method("set_volume_unit"):
			mm.call("set_volume_unit", u)
		elif mm.has_method("set_volume_db"):
			mm.call("set_volume_db", db)
		if mm.has_method("save_volume"):
			mm.call("save_volume", u)

func _sync_from_manager() -> void:
	var mm: Node = get_node_or_null("/root/MusicManager")
	if mm != null and mm.has_method("get_volume_unit"):
		var u: float = float(mm.call("get_volume_unit"))
		_slider.value = clamp(u, 0.0, 1.0)
	else:
		var db_now: float = AudioServer.get_bus_volume_db(_bus_index)
		_slider.value = _db_to_unit(db_now)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _unit_to_db(u: float) -> float:
	return lerp(min_db, max_db, u)

func _db_to_unit(db: float) -> float:
	return inverse_lerp(min_db, max_db, clamp(db, min_db, max_db))

# -----------------------------------------------------------------------------
# Navigation back to PauseMenu
# -----------------------------------------------------------------------------
func _on_back_button_up() -> void:
	back_pressed.emit()
	var n := get_parent()
	while n != null:
		if n.has_method("_close_settings"):
			n.call("_close_settings")
			return
		n = n.get_parent()
	hide()
