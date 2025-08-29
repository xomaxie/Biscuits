extends CharacterBody2D

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------
signal hp_changed(current:int, maxv:int)
signal died()

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var move_speed: float = 230.0
@export var debug_desk_chair: bool = true
@export var debug_speed_log: bool = false
@export var max_hp: int = 6
@export var invuln_sec: float = 0.6
@export var regen_per_sec: float = 0.0
@export var knockback_on_hit: float = 80.0

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
@onready var weapon_manager: Node2D = $WeaponManager
@onready var cam: Camera2D = $Camera2D
@onready var sprite: AnimatedSprite2D = $Sprite2D

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
const MOVE_DEADZONE := 0.08
var current_speed: float = 230.0
var current_attack_speed_bonus_pct: float = 0.0
var _last_dir: Vector2 = Vector2.DOWN
var _last_still_state: bool = true
var _gs: Node = null
var _temp_boomerang_speed_pct: float = 0.0
var _boom_speed_sources: Dictionary = {}
var hp: int = 1
var _invuln: float = 0.0
var _alive: bool = true
var _regen_accum: float = 0.0
var _lifesteal_accum: float = 0.0
var _base_max_hp: int = 6

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("player")
	_acquire_gs()
	_base_max_hp = max_hp
	_refresh_max_hp_from_gs(true)
	if debug_desk_chair and _gs and _gs.has_method("get_stat"):
		var base0: float = float(_gs.get_stat("attack_speed_pct"))
		var still0: float = float(
			_gs.get_stat("attack_speed_while_still_pct"))
		print("[DeskChair] Startup base=", base0, " still=", still0)
	_refresh_speed_from_gs()
	_refresh_attack_speed_bonus(true)
	if _gs:
		_gs.upgrades_changed.connect(_on_upgrades_changed)
		_gs.weapon_purchased.connect(_on_weapon_purchased)
	if cam and not cam.is_current():
		cam.make_current()
	if cam:
		var was: bool = cam.position_smoothing_enabled
		cam.position_smoothing_enabled = false
		await get_tree().process_frame
		cam.position_smoothing_enabled = was
	_play_anim(_compose_name(false, _last_dir))

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(dt: float) -> void:
	if not _alive:
		return
	if _invuln > 0.0:
		_invuln -= dt
	_tick_regen(dt)
	_refresh_speed_from_gs()
	var v: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down")
	velocity = v.normalized() * current_speed
	move_and_slide()
	var moving: bool = v.length() > MOVE_DEADZONE
	if moving:
		_last_dir = v
	_refresh_attack_speed_bonus(not moving)
	var dir: Vector2 = v if moving else _last_dir
	_play_anim(_compose_name(moving, dir))

# -----------------------------------------------------------------------------
# Public health API
# -----------------------------------------------------------------------------
func take_hit(damage:int = 1, source:Node = null) -> void:
	if not _alive:
		return
	if _invuln > 0.0:
		return
	var dodge_pct: float = clampf(_get_statf("dodge_pct"), 0.0, 95.0)
	if dodge_pct > 0.0 and randf() < (dodge_pct / 100.0):
		_do_dodge_feedback(source)
		return
	var raw_amt: int = int(max(0, damage))
	if raw_amt <= 0:
		return
	var amt: int = _apply_armor(raw_amt)
	if amt <= 0:
		return
	hp -= amt
	emit_signal("hp_changed", hp, max_hp)
	_do_hit_feedback(source)
	_invuln = invuln_sec
	if hp <= 0:
		_die()

func heal(amount:int = 1) -> void:
	if not _alive:
		return
	var amt: int = int(max(0, amount))
	if amt <= 0:
		return
	var before: int = hp
	hp = int(min(max_hp, hp + amt))
	if hp != before:
		emit_signal("hp_changed", hp, max_hp)

func is_alive() -> bool:
	return _alive

# -----------------------------------------------------------------------------
# Armor
# -----------------------------------------------------------------------------
func _apply_armor(incoming:int) -> int:
	var flat_armor: float = _get_statf("armor")
	var pct_red: float = _get_statf("armor_pct")
	var after_flat: float = float(incoming) - max(0.0, flat_armor)
	var pct_mult: float = 1.0 - clamp(pct_red, -90.0, 90.0) / 100.0
	var reduced: float = after_flat * max(0.1, pct_mult)
	var final_amt: int = int(ceil(max(0.0, reduced)))
	if incoming > 0:
		final_amt = max(1, final_amt)
	return final_amt

# -----------------------------------------------------------------------------
# Regen and lifesteal
# -----------------------------------------------------------------------------
func _tick_regen(dt: float) -> void:
	if hp >= max_hp:
		_regen_accum = 0.0
		return
	var regen_ps: float = max(0.0, regen_per_sec + _get_statf("hp_regen"))
	if regen_ps <= 0.0:
		return
	_regen_accum += regen_ps * dt
	if _regen_accum >= 1.0:
		var heal_amt: int = int(_regen_accum)
		_regen_accum -= float(heal_amt)
		heal(heal_amt)

func report_damage_dealt(dmg:int) -> void:
	if dmg <= 0 or not _alive:
		return
	var ls_pct: float = max(0.0, _get_statf("lifesteal_pct"))
	if ls_pct <= 0.0:
		return
	_lifesteal_accum += float(dmg) * (ls_pct / 100.0)
	var whole: int = int(_lifesteal_accum)
	if whole > 0:
		_lifesteal_accum -= float(whole)
		heal(whole)

# -----------------------------------------------------------------------------
# Hit feedback
# -----------------------------------------------------------------------------
func _do_hit_feedback(source:Node) -> void:
	if knockback_on_hit > 0.0:
		var dir: Vector2 = Vector2.ZERO
		if source and source is Node2D:
			dir = global_position - (source as Node2D).global_position
		if dir == Vector2.ZERO:
			dir = -_last_dir
		velocity += dir.normalized() * knockback_on_hit
	var ap: AnimationPlayer = get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("Hurt"):
		ap.play("Hurt")

func _do_dodge_feedback(_source:Node) -> void:
	var ap: AnimationPlayer = get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("Dodge"):
		ap.play("Dodge")

# -----------------------------------------------------------------------------
# Death
# -----------------------------------------------------------------------------
func _die() -> void:
	_alive = false
	emit_signal("died")
	velocity = Vector2.ZERO
	var death_name: String = _compose_death_name(_last_dir)
	if sprite:
		if death_name != "":
			sprite.play(death_name)
		else:
			sprite.stop()
	set_physics_process(false)

# -----------------------------------------------------------------------------
# GameState handling
# -----------------------------------------------------------------------------
func _acquire_gs() -> void:
	if _gs != null and is_instance_valid(_gs):
		return
	_gs = get_node_or_null("/root/GameState")
	if _gs and not _gs.is_connected(
		"upgrades_changed", Callable(self, "_on_upgrades_changed")):
		_gs.upgrades_changed.connect(_on_upgrades_changed)
	if _gs and not _gs.is_connected(
		"weapon_purchased", Callable(self, "_on_weapon_purchased")):
		_gs.weapon_purchased.connect(_on_weapon_purchased)

# -----------------------------------------------------------------------------
# Upgrades
# -----------------------------------------------------------------------------
func _on_upgrades_changed() -> void:
	_refresh_max_hp_from_gs(false)
	_refresh_speed_from_gs()
	_refresh_attack_speed_bonus(true)
	if debug_desk_chair and _gs and _gs.has_method("get_stat"):
		var base_now: float = float(_gs.get_stat("attack_speed_pct"))
		var still_now: float = float(
			_gs.get_stat("attack_speed_while_still_pct"))
		print("[DeskChair] Upgrades base=", base_now, " still=", still_now)

func _refresh_speed_from_gs() -> void:
	_acquire_gs()
	if _gs and _gs.has_method("get_stat"):
		var ms: float = _gs.get_stat("movespeed")
		if ms <= 0.0:
			ms = move_speed
		var mult: float = 1.0 + (_temp_boomerang_speed_pct / 100.0)
		current_speed = ms * max(0.05, mult)
	else:
		current_speed = move_speed
	if debug_speed_log:
		print("[Speed] eff_ms=", current_speed)

func _refresh_attack_speed_bonus(still_state: bool) -> void:
	var base_bonus: float = _get_statf("attack_speed_pct")
	var still_bonus_raw: float = _get_statf("attack_speed_while_still_pct")
	var still_bonus: float = 0.0
	if still_state:
		still_bonus = still_bonus_raw
	var new_bonus: float = base_bonus + still_bonus
	if debug_desk_chair:
		if still_state != _last_still_state:
			if still_state:
				print("[DeskChair] Now still apply=", still_bonus_raw,
					" total=", new_bonus)
			else:
				print("[DeskChair] Moving remove still bonus total=",
					new_bonus)
		elif abs(new_bonus - current_attack_speed_bonus_pct) > 0.001:
			print("[DeskChair] Bonus total=", new_bonus, " base=",
				base_bonus, " still=", still_bonus)
	current_attack_speed_bonus_pct = new_bonus
	_last_still_state = still_state
	if weapon_manager and weapon_manager.has_method(
		"set_attack_speed_bonus_pct"):
		weapon_manager.set_attack_speed_bonus_pct(
			current_attack_speed_bonus_pct)

func _get_statf(name: String) -> float:
	_acquire_gs()
	if _gs and _gs.has_method("get_stat"):
		return float(_gs.get_stat(name))
	return 0.0

# -----------------------------------------------------------------------------
# Max HP from GameState
# -----------------------------------------------------------------------------
func _refresh_max_hp_from_gs(init: bool) -> void:
	var bonus := int(round(_get_statf("max_hp")))
	var eff := int(max(1, _base_max_hp + bonus))
	if eff == max_hp:
		if init:
			hp = eff
			emit_signal("hp_changed", hp, max_hp)
		return
	var prev_max := max_hp
	var prev_hp := hp
	max_hp = eff
	if init:
		hp = eff
	else:
		if prev_max > 0:
			var ratio: float = clamp(
				float(prev_hp) / float(prev_max), 0.0, 1.0)
			hp = int(clamp(round(ratio * float(max_hp)), 1.0,
				float(max_hp)))
		else:
			hp = min(hp, max_hp)
	emit_signal("hp_changed", hp, max_hp)

# -----------------------------------------------------------------------------
# Boomerang temp speed API
# -----------------------------------------------------------------------------
func add_move_speed_pct_from_boomerang(source_id: int, pct: float) -> void:
	_boom_speed_sources[source_id] = pct
	_recalc_boomerang_speed()

func clear_move_speed_pct_from_boomerang(source_id: int) -> void:
	if _boom_speed_sources.has(source_id):
		_boom_speed_sources.erase(source_id)
	_recalc_boomerang_speed()

func _recalc_boomerang_speed() -> void:
	var total: float = 0.0
	for v in _boom_speed_sources.values():
		total += float(v)
	_temp_boomerang_speed_pct = total

# -----------------------------------------------------------------------------
# Weapons
# -----------------------------------------------------------------------------
func _on_weapon_purchased(key: String, def: Dictionary) -> void:
	var node: Node2D = WeaponFactory.create_from_entry(key, def)
	if node and weapon_manager:
		weapon_manager.register_weapon(node)
	if weapon_manager and weapon_manager.has_method(
		"set_attack_speed_bonus_pct"):
		weapon_manager.set_attack_speed_bonus_pct(
			current_attack_speed_bonus_pct)

# -----------------------------------------------------------------------------
# Animation selection
# -----------------------------------------------------------------------------
func _compose_name(moving: bool, dir: Vector2) -> String:
	var n: Vector2 = dir.normalized()
	var sx: int = 0
	if n.x > 0.35:
		sx = 1
	elif n.x < -0.35:
		sx = -1
	var sy: int = 0
	if n.y > 0.35:
		sy = 1
	elif n.y < -0.35:
		sy = -1
	var horiz: String = ""
	if sx == 1:
		horiz = "Right"
	elif sx == -1:
		horiz = "Left"
	var vert: String = ""
	if sy == 1:
		vert = "Backward"
	elif sy == -1:
		vert = "Forward"
	var base: String = "Run"
	if not moving:
		base = "Idle"
	var candidates: Array[String] = []
	if horiz != "" and vert != "":
		candidates.append(base + horiz + vert)
	if horiz != "":
		candidates.append(base + horiz)
	if vert != "":
		candidates.append(base + vert)
	candidates.append(base)
	return _first_existing_animation(candidates)

func _first_existing_animation(cands: Array[String]) -> String:
	if sprite == null or sprite.sprite_frames == null:
		return ""
	var names: PackedStringArray = sprite.sprite_frames.get_animation_names()
	for name in cands:
		if name in names:
			return name
	return ""

func _play_anim(name: String) -> void:
	if name == "" or sprite == null:
		return
	if sprite.animation != name:
		sprite.play(name)

# -----------------------------------------------------------------------------
# Death animation selection
# -----------------------------------------------------------------------------
func _compose_death_name(dir: Vector2) -> String:
	var n: Vector2 = dir.normalized()
	var sx: int = 0
	if n.x > 0.35:
		sx = 1
	elif n.x < -0.35:
		sx = -1
	var sy: int = 0
	if n.y > 0.35:
		sy = 1
	elif n.y < -0.35:
		sy = -1
	var horiz: String = ""
	if sx == 1:
		horiz = "Right"
	elif sx == -1:
		horiz = "Left"
	var vert: String = ""
	if sy == 1:
		vert = "Backward"
	elif sy == -1:
		vert = "Forward"
	var cands: Array[String] = []
	if horiz != "" and vert != "":
		cands.append("Death" + horiz + vert)
		if horiz == "Left" and vert == "Forward":
			cands.append("DeathLeftFoward")
	if horiz != "":
		cands.append("Death" + horiz)
	if vert != "":
		cands.append("Death" + vert)
	cands.append("Death")
	return _first_existing_animation(cands)
