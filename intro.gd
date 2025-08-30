extends Control

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export_file("*.tscn") var next_scene: String = "res://Scenes/Game.tscn"
@export var auto_continue_after: float = 0.0
@export var base_design_size: Vector2 = Vector2(1280, 720)
@export var min_scale: float = 0.6
@export var max_scale: float = 2.0

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
var _can_start := false
var _blink_t := 0.0
var _scale := 1.0

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
@onready var _title: RichTextLabel = $Center/VBox/Title
@onready var _objective: RichTextLabel = $Center/VBox/Objective
@onready var _tips: RichTextLabel = $Center/VBox/Tips
@onready var _anykey: Label = $Center/VBox/AnyKey
@onready var _vbox: VBoxContainer = $Center/VBox
@onready var _center: CenterContainer = $Center
@onready var _fade: ColorRect = $Fade
@onready var _bg: ColorRect = $Bg

# -----------------------------------------------------------------------------
# Content
# -----------------------------------------------------------------------------
const TITLE_BBCODE := """
[center][b][color=#A6E3A1]Protect the Nexus[/color][/b][/center]
"""

const OBJECTIVE_BBCODE := """
[center][b]Objective — Protect the Nexus[/b][/center]

• Survive waves and keep the Nexus alive.
• Your HP refills between rounds; the Nexus does not.
• Picking up [b]biscuits[/b] instantly heals the Nexus by
  [b]1% per biscuit[/b].
• Spend biscuits between waves to upgrade Dodge, Lifesteal, and Regen.
"""

const TIPS_BBCODE := """
[b]Tips[/b]

• Weapons orbit and auto-fire; keep moving to herd enemies.
• Enemies swap to you if you’re close or low HP—kite them away from
  the Nexus when it’s threatened.
• Barrels drip and burst biscuits; farther from the Nexus can mean
  higher biscuit value.
• Lifesteal heals from damage dealt; partial amounts stack
  until they become 1 HP.
• Regen heals every second; Dodge can save you from big hits.
"""

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	assert(_fade is ColorRect)
	assert(_bg is ColorRect)
	assert(_title is RichTextLabel)
	assert(_objective is RichTextLabel)
	assert($Center/VBox/HSeparator is HSeparator)
	assert(_tips is RichTextLabel)
	assert(_anykey is Label)

	_title.bbcode_enabled = true
	_objective.bbcode_enabled = true
	_tips.bbcode_enabled = true
	_title.text = TITLE_BBCODE
	_objective.text = OBJECTIVE_BBCODE
	_tips.text = TIPS_BBCODE

	_title.fit_content = true
	_objective.fit_content = true
	_tips.fit_content = true
	_anykey.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_anykey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if _anykey.text.strip_edges() == "":
		_anykey.text = "Press any key to start"
	_anykey.visible = auto_continue_after <= 0.0

	resized.connect(_on_resized)
	_apply_scale_now()

	_fade.color.a = 1.0
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_fade, "color:a", 0.0, 0.6)
	await t.finished

	_can_start = true

	if auto_continue_after > 0.0:
		await get_tree().create_timer(auto_continue_after).timeout
		if _can_start:
			_start_game()

func _process(delta: float) -> void:
	_blink_t += delta
	if _anykey.visible:
		var a := 0.45 + 0.35 * sin(_blink_t * 4.0)
		_anykey.modulate.a = clamp(a, 0.1, 0.85)

# -----------------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not _can_start:
		return
	if (event is InputEventKey and event.pressed) \
	or (event is InputEventMouseButton and event.pressed) \
	or (event is InputEventJoypadButton and event.pressed):
		_start_game()

# -----------------------------------------------------------------------------
# Start transition
# -----------------------------------------------------------------------------
func _start_game() -> void:
	_can_start = false
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(_fade, "color:a", 1.0, 0.35)
	await t.finished
	get_tree().change_scene_to_file(next_scene)

# -----------------------------------------------------------------------------
# Resizing & scaling
# -----------------------------------------------------------------------------
func _on_resized() -> void:
	_apply_scale_now()

func _apply_scale_now() -> void:
	var vp := get_viewport_rect().size
	var s: float = min(vp.x / base_design_size.x, vp.y / base_design_size.y)
	_scale = clamp(s, min_scale, max_scale)

	_vbox.add_theme_constant_override("separation", int(16 * _scale))
	_center.add_theme_constant_override("hseparation", 0)
	_center.add_theme_constant_override("vseparation", 0)

	var pad := int(24 * _scale)
	_vbox.add_theme_constant_override("margin_left", pad)
	_vbox.add_theme_constant_override("margin_right", pad)
	_vbox.add_theme_constant_override("margin_top", pad)
	_vbox.add_theme_constant_override("margin_bottom", pad)

	_title.add_theme_font_size_override("normal_font_size", int(54 * _scale))
	_title.add_theme_font_size_override("bold_font_size", int(54 * _scale))

	_objective.add_theme_font_size_override("normal_font_size", int(22 * _scale))
	_objective.add_theme_font_size_override("bold_font_size", int(22 * _scale))

	_tips.add_theme_font_size_override("normal_font_size", int(20 * _scale))
	_tips.add_theme_font_size_override("bold_font_size", int(20 * _scale))

	_anykey.add_theme_font_size_override("font_size", int(22 * _scale))

	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anykey.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var max_w: int = clamp(int(960 * _scale), 480, int(vp.x * 0.94))
	_title.custom_minimum_size.x = max_w
	_objective.custom_minimum_size.x = max_w
	_tips.custom_minimum_size.x = max_w
	_anykey.custom_minimum_size.x = max_w

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _apply_bbcode(rtl: RichTextLabel, txt: String) -> void:
	if rtl == null:
		return
	rtl.bbcode_enabled = true
	rtl.text = txt
