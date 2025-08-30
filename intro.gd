extends Control

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export_file("*.tscn") var next_scene: String = "res://Scenes/Game.tscn"
@export var auto_continue_after: float = 0.0

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
var _can_start := false
var _blink_t := 0.0

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
@onready var _title: RichTextLabel = $Center/VBox/Title
@onready var _objective: RichTextLabel = $Center/VBox/Objective
@onready var _tips: RichTextLabel = $Center/VBox/Tips
@onready var _anykey: Label = $Center/VBox/AnyKey

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
	assert($Fade is ColorRect)
	assert($Bg is ColorRect)
	assert(_title is RichTextLabel)
	assert(_objective is RichTextLabel)
	assert($Center/VBox/HSeparator is HSeparator)
	assert(_tips is RichTextLabel)
	assert(_anykey is Label)

	_apply_bbcode(_title, TITLE_BBCODE)
	_apply_bbcode(_objective, OBJECTIVE_BBCODE)
	_apply_bbcode(_tips, TIPS_BBCODE)
	if _anykey.text.strip_edges() == "":
		_anykey.text = "Press any key to start"
	_anykey.visible = auto_continue_after <= 0.0

	$Fade.color.a = 1.0
	var t := create_tween().set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
	t.tween_property($Fade, "color:a", 0.0, 0.6)
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
	var t := create_tween().set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN)
	t.tween_property($Fade, "color:a", 1.0, 0.35)
	await t.finished
	get_tree().change_scene_to_file(next_scene)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _apply_bbcode(rtl: RichTextLabel, txt: String) -> void:
	if rtl == null:
		return
	rtl.bbcode_enabled = true
	rtl.text = txt
