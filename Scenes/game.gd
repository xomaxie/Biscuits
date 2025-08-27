extends Node2D

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
@onready var nexus: Node = $Nexus
@onready var spawner: Node = $EnemySpawner
@onready var enemies_container: Node = $Enemies
@onready var wave_label: Label = $UI/WaveLabel
@onready var biscuit_label: Label = $UI/TopBar/BiscuitLabel
@onready var nexus_bar: Range = $UI/VBoxContainer/NexusBar
@onready var player_bar: Range = $UI/VBoxContainer/PlayerHealth
@onready var nexus_label: Label = $UI/VBoxContainer/NexusBar/Nexus
@onready var player_label: Label = $UI/VBoxContainer/PlayerHealth/Player
@onready var prep_timer: Timer = $PrepTimer
@onready var wave_timer: Timer = $WaveTimer
@onready var barrel_spawner: Node = $BarrelSpawner
@onready var shop_ui: ShopUI = $UI/Shop
@onready var player: Node = $Player
@onready var ui_root: CanvasLayer = $UI

# -----------------------------------------------------------------------------
# Tunables
# -----------------------------------------------------------------------------
@export var prep_duration: float = 5.0
@export var wave_duration: float = 25.0

# Heal nexus during wave: +X% max HP per biscuit gained
@export var nexus_heal_per_biscuit_pct: float = 1.0
@export var nexus_heal_enabled: bool = true
@export var nexus_heal_debug: bool = false

# Debug
@export var debug_start_with_biscuits: bool = false
@export var debug_biscuit_amount: int = 10000

# -----------------------------------------------------------------------------
# Style state
# -----------------------------------------------------------------------------
var _nexus_fill: StyleBoxFlat
var _player_fill: StyleBoxFlat

# -----------------------------------------------------------------------------
# UI visibility
# -----------------------------------------------------------------------------
var _ui_prev_visible: Dictionary = {}

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	shop_ui.hide()
	shop_ui.continue_pressed.connect(_on_shop_continue)

	prep_timer.one_shot = true
	wave_timer.one_shot = true
	prep_timer.timeout.connect(_on_prep_timeout)
	wave_timer.timeout.connect(_on_wave_timeout)

	if nexus.has_signal("hp_changed"):
		nexus.hp_changed.connect(_on_nexus_hp_changed)
	if nexus.has_signal("nexus_destroyed"):
		nexus.nexus_destroyed.connect(_on_nexus_destroyed)

	if "max_hp" in nexus and "hp" in nexus and nexus_bar:
		nexus_bar.max_value = nexus.max_hp
		nexus_bar.value = nexus.hp
		var nr: float = float(nexus.hp) / float(max(1, nexus.max_hp))
		_update_bar_color(nexus_bar, nr, true)
		if nexus_label:
			_update_label_style(nexus_label, nr)

	if player and player.has_signal("hp_changed") and player_bar:
		player.hp_changed.connect(_on_player_hp_changed)
		if "max_hp" in player and "hp" in player:
			player_bar.max_value = player.max_hp
			player_bar.value = player.hp
			var pr: float = float(player.hp) / float(max(1, player.max_hp))
			_update_bar_color(player_bar, pr, false)
			if player_label:
				_update_label_style(player_label, pr)

	if spawner.has_method("configure"):
		spawner.configure(nexus, enemies_container)

	GameState.biscuits_changed.connect(_on_biscuits_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.run_started.connect(_on_run_started)
	GameState.run_ended.connect(_on_run_ended)

	GameState.start_run()
	_enter_prep()
	_refresh_timer_ui()

func _process(_delta: float) -> void:
	_refresh_timer_ui()

# -----------------------------------------------------------------------------
# Phase control
# -----------------------------------------------------------------------------
func _enter_prep() -> void:
	GameState.set_phase(GameState.Phase.PREP)
	_set_spawning(false)
	_set_shop_ui_state(false)
	_clear_field()
	_heal_player_to_full()
	prep_timer.start(prep_duration)

func _start_wave() -> void:
	GameState.set_phase(GameState.Phase.WAVE)
	var s: float = clampf(1.2 - float(GameState.wave - 1) * 0.07, 0.35, 1.2)
	if spawner.has_method("set_spawn_interval"):
		spawner.set_spawn_interval(s)
	_set_spawning(true)
	if barrel_spawner and barrel_spawner.has_method("on_wave_started"):
		barrel_spawner.on_wave_started(GameState.wave)
	wave_timer.start(wave_duration)

func _enter_shop() -> void:
	_set_spawning(false)
	_clear_field()
	_heal_player_to_full()
	_set_shop_ui_state(true)
	get_tree().paused = true
	if wave_label:
		wave_label.text = "Shop — Spend your biscuits"
	shop_ui.show()

func _on_prep_timeout() -> void:
	_start_wave()

func _on_wave_timeout() -> void:
	_enter_shop()

func _on_shop_continue() -> void:
	shop_ui.hide()
	get_tree().paused = false
	_set_shop_ui_state(false)
	GameState.next_wave()
	_enter_prep()

func _set_spawning(enabled: bool) -> void:
	if spawner.has_method("set_enabled"):
		spawner.set_enabled(enabled)

# -----------------------------------------------------------------------------
# Field clearing
# -----------------------------------------------------------------------------
func _clear_field() -> void:
	if enemies_container:
		for c in enemies_container.get_children():
			if is_instance_valid(c):
				c.queue_free()

	var barrels: Array = get_tree().get_nodes_in_group("barrels")
	for b in barrels:
		if is_instance_valid(b):
			b.queue_free()

	if barrel_spawner and barrel_spawner.has_method("clear_all"):
		barrel_spawner.clear_all()

# -----------------------------------------------------------------------------
# UI updates
# -----------------------------------------------------------------------------
func _refresh_timer_ui() -> void:
	if get_tree().paused and shop_ui.visible:
		if wave_label:
			wave_label.text = "Shop — Spend your biscuits"
		return

	match GameState.phase:
		GameState.Phase.PREP:
			if prep_timer and prep_timer.time_left > 0.0:
				wave_label.text = "Prep… (Wave %d in %ds)" % [
					GameState.wave, int(ceil(prep_timer.time_left))
				]
			else:
				wave_label.text = "Prep… (Wave %d soon)" % GameState.wave
		GameState.Phase.WAVE:
			if wave_timer and wave_timer.time_left > 0.0:
				wave_label.text = "Wave %d — %ds left" % [
					GameState.wave, int(ceil(wave_timer.time_left))
				]
			else:
				wave_label.text = "Wave %d" % GameState.wave
		GameState.Phase.GAME_OVER:
			wave_label.text = "⚠ Nexus Destroyed — Game Over"

func _on_biscuits_changed(total:int, delta:int) -> void:
	if biscuit_label:
		biscuit_label.text = "Biscuits: %d" % total
	# Heal nexus immediately during wave for each biscuit gained
	if nexus_heal_enabled and delta > 0 and GameState.phase == GameState.Phase.WAVE:
		_heal_nexus_by_biscuits(delta)

func _on_wave_changed(_new_wave:int) -> void:
	pass

func _on_phase_changed(_p:int) -> void:
	_refresh_timer_ui()

func _on_run_started() -> void:
	if debug_start_with_biscuits:
		GameState.add_biscuits(max(0, debug_biscuit_amount))
	_on_biscuits_changed(GameState.biscuits, 0)
	_on_phase_changed(GameState.phase)

func _on_run_ended(_victory:bool) -> void:
	if shop_ui:
		shop_ui.hide()
	get_tree().paused = false
	_set_shop_ui_state(false)

func add_biscuits(amount:int) -> void:
	GameState.add_biscuits(max(0, amount))

# -----------------------------------------------------------------------------
# Nexus events
# -----------------------------------------------------------------------------
func _on_nexus_hp_changed(current:int, maxv:int) -> void:
	if nexus_bar:
		nexus_bar.max_value = maxv
		nexus_bar.value = current
		var r: float = float(current) / float(max(1, maxv))
		_update_bar_color(nexus_bar, r, true)
		if nexus_label:
			_update_label_style(nexus_label, r)

func _on_nexus_destroyed() -> void:
	GameState.end_run(false)
	_set_spawning(false)
	if wave_timer:
		wave_timer.stop()
	if prep_timer:
		prep_timer.stop()
	_clear_field()
	_set_shop_ui_state(false)

# -----------------------------------------------------------------------------
# Player events
# -----------------------------------------------------------------------------
func _on_player_hp_changed(current:int, maxv:int) -> void:
	if player_bar:
		player_bar.max_value = maxv
		player_bar.value = current
		var r: float = float(current) / float(max(1, maxv))
		_update_bar_color(player_bar, r, false)
		if player_label:
			_update_label_style(player_label, r)

# -----------------------------------------------------------------------------
# Heal helpers
# -----------------------------------------------------------------------------
func _heal_player_to_full() -> void:
	if player == null:
		return
	var has_hp: bool = "hp" in player
	var has_mhp: bool = "max_hp" in player
	if not has_hp or not has_mhp:
		return
	var cur: int = int(player.hp)
	var maxv: int = int(player.max_hp)
	var need: int = max(0, maxv - cur)
	if need <= 0:
		return
	if player.has_method("heal"):
		player.heal(need)
	else:
		player.hp = maxv
		if player_bar:
			player_bar.max_value = maxv
			player_bar.value = maxv
			_update_bar_color(player_bar, 1.0, false)
			if player_label:
				_update_label_style(player_label, 1.0)

func _heal_nexus_by_biscuits(delta_biscuits:int) -> void:
	if nexus == null:
		return
	if not ("hp" in nexus and "max_hp" in nexus):
		return
	var maxv: int = int(nexus.max_hp)
	var pct_per: float = max(0.0, nexus_heal_per_biscuit_pct)
	var heal_points: int = int(round(float(maxv) * (pct_per / 100.0) * float(delta_biscuits)))
	if heal_points <= 0:
		heal_points = 1  # ensure at least 1 HP if we gained biscuits
	var before: int = int(nexus.hp)

	if nexus.has_method("heal"):
		nexus.heal(heal_points)
	elif nexus.has_method("apply_heal"):
		nexus.apply_heal(heal_points)
	else:
		var after_direct: int = clamp(before + heal_points, 0, maxv)
		if after_direct != before:
			nexus.hp = after_direct
			_on_nexus_hp_changed(after_direct, maxv)

	if nexus_heal_debug:
		var after_now: int = int(nexus.hp)
		print("[NexusHeal] +", delta_biscuits, " biscuits -> +",
			heal_points, " HP (", before, "→", after_now, "/", maxv, ")")

# -----------------------------------------------------------------------------
# Color helpers (bar fill)
# -----------------------------------------------------------------------------
func _update_bar_color(bar: Range, ratio: float, is_nexus: bool) -> void:
	var r: float = clamp(ratio, 0.01, 1.0)
	var hue: float = lerpf(0.0, 0.33, r)
	var sat: float = 0.85
	var val: float = lerpf(0.55, 0.95, r)
	var col: Color = Color.from_hsv(hue, sat, val, 1.0)
	var box: StyleBoxFlat = _get_fill_stylebox(is_nexus)
	box.bg_color = col
	var ctrl: Control = bar as Control
	if ctrl != null:
		ctrl.add_theme_stylebox_override("fill", box)

func _get_fill_stylebox(is_nexus: bool) -> StyleBoxFlat:
	if is_nexus:
		if _nexus_fill == null:
			_nexus_fill = StyleBoxFlat.new()
		return _nexus_fill
	else:
		if _player_fill == null:
			_player_fill = StyleBoxFlat.new()
		return _player_fill

# -----------------------------------------------------------------------------
# Color helpers (label text/shadow/outline)
# -----------------------------------------------------------------------------
func _update_label_style(label: Label, ratio: float) -> void:
	var r: float = clamp(ratio, 0.0, 1.0)
	var font_col: Color
	var shadow_col: Color = Color(0, 0, 0, 0.6)
	var outline_col: Color = Color(0.05, 0.05, 0.05, 1.0)

	if r < 0.2:
		font_col = Color(1.0, 0.302, 0.302, 1.0)
	elif r < 0.5:
		font_col = Color(1.0, 0.839, 0.2, 1.0)
	else:
		font_col = Color(1, 1, 1, 1)

	label.add_theme_color_override("font_color", font_col)
	label.add_theme_color_override("font_outline_color", outline_col)
	label.add_theme_color_override("font_shadow_color", shadow_col)
	label.add_theme_constant_override("outline_size", 2)

# -----------------------------------------------------------------------------
# UI visibility helpers
# -----------------------------------------------------------------------------
func _set_shop_ui_state(in_shop: bool) -> void:
	if ui_root == null:
		return
	if in_shop:
		_ui_prev_visible.clear()
		var children: Array = ui_root.get_children()
		for n in children:
			var c: CanvasItem = n as CanvasItem
			if c == null:
				continue
			if c == shop_ui or c == wave_label:
				continue
			_ui_prev_visible[c] = c.visible
			c.visible = false
	else:
		for k in _ui_prev_visible.keys():
			var c2: CanvasItem = k as CanvasItem
			if c2 != null:
				var was: bool = bool(_ui_prev_visible[k])
				c2.visible = was
		_ui_prev_visible.clear()
