extends CharacterBody2D

# -----------------------------------------------------------------------------
# Enums
# -----------------------------------------------------------------------------
enum KnockMode { PROJECTILE_DIR, BACK_ONLY, BACK_CLAMP }

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var speed: float = 80.0
@export var hp: int = 6
@export var touch_damage: int = 5
@export var contact_interval: float = 0.4
@export var stop_distance: float = 14.0
@export var target_path: NodePath = NodePath("")
@export var debug_attack_logs: bool = true
@export var debug_draw: bool = false
@export var hit_flash_time: float = 0.06
@export var retarget_interval: float = 0.35
@export var prefer_player_within: float = 240.0
@export var player_proximity_bonus: float = 1.2
@export var distance_weight: float = 1.0
@export var player_hp_weight: float = 0.6
@export var current_target_stickiness: float = 0.4
@export var manual_attack_radius: float = 16.0
@export var archetype_key: String = ""
@export var debug_archetype_logs: bool = false
@export var debug_spawn_logs: bool = true
@export var biscuit_pickup_scene: PackedScene
@export var knockback_friction: float = 700
@export var knockback_resistance: float = 0.0
@export var knockback_mode: KnockMode = KnockMode.BACK_CLAMP




# -----------------------------------------------------------------------------
# Node refs & runtime state
# -----------------------------------------------------------------------------
@onready var contact: Area2D = get_node_or_null("Contact") as Area2D
@onready var _visual: CanvasItem = _find_visual()
var _target: Node2D = null
var _nexus: Node2D = null
var _player: Node2D = null
var _gs: Node = null
var _touching_nexus: bool = false
var _touching_player: bool = false
var _contact_accum: float = 0.0
var _retarget_accum: float = 0.0
var _pending_damage: int = 0
var _flashing: bool = false
var _flash_color: Color = Color(1, 0, 0, 1)
var _base_flash_time: float = 0.06
var _drop_mult: float = 1.0
var _dead: bool = false
var _anim_gen: int = 0
var _kb_vel: Vector2 = Vector2.ZERO
var _base_move_dir: Vector2 = Vector2.ZERO

# -----------------------------------------------------------------------------
# Sprite/animation helpers
# -----------------------------------------------------------------------------
var _sprite: AnimatedSprite2D = null
var _anim_map: Dictionary = {
	"idle": "Run",
	"move": "Run",
	"attack": "Attack",
	"hit": "Hit",
	"die": "Die"
}
var _faces_right: bool = true
var _anim_speed_base: float = 1.0
var _oneshot_playing: bool = false

# -----------------------------------------------------------------------------
# Target
# -----------------------------------------------------------------------------
func set_target(t: Node2D) -> void:
	_target = t
	if is_instance_valid(t):
		target_path = t.get_path()

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("enemies")
	_gs = get_node_or_null("/root/GameState")
	if _target == null and target_path != NodePath(""):
		_target = get_node_or_null(target_path) as Node2D
	_nexus = _first_in_group("nexus")
	if _target == null and _nexus != null:
		_target = _nexus
	_player = _first_in_group("player")
	if contact != null:
		contact.monitoring = true
		contact.monitorable = true
		if not contact.body_entered.is_connected(_on_contact_body_entered):
			contact.body_entered.connect(_on_contact_body_entered)
		if not contact.body_exited.is_connected(_on_contact_body_exited):
			contact.body_exited.connect(_on_contact_body_exited)
	_base_flash_time = hit_flash_time
	_apply_global_scalers()
	_apply_archetype_json()

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if debug_draw:
		queue_redraw()
	if _dead:
		return

	_retarget_accum += delta
	if _reached(_retarget_accum, retarget_interval):
		_retarget_accum = 0.0
		_reselect_target()

	var dir: Vector2 = Vector2.ZERO
	if _target != null:
		var dist: float = _dist_to(_target)
		if dist > stop_distance:
			dir = global_position.direction_to(_target.global_position)

	if dir.length_squared() > 1e-6:
		_base_move_dir = dir.normalized()

	var base_vel: Vector2 = dir * speed
	var total_vel: Vector2 = base_vel + _kb_vel
	velocity = total_vel
	move_and_slide()

	if _kb_vel.length_squared() > 1e-6:
		var dec: float = knockback_friction * delta
		var len: float = _kb_vel.length()
		var new_len: float = max(0.0, len - dec)
		_kb_vel = _kb_vel.normalized() * new_len if new_len > 0.0 else Vector2.ZERO

	_update_visual_orientation(dir)
	_update_move_idle(dir)
	if _pending_damage > 0:
		var applied: int = min(_pending_damage, hp)
		hp -= applied
		_pending_damage = 0
		_flash_hit()
		if _has_anim("hit"):
			_play_once("hit")
		if applied > 0:
			_notify_player_damage_dealt(applied)
		if hp <= 0:
			_die()
			return
	_contact_accum += delta
	if _reached(_contact_accum, contact_interval):
		_contact_accum = 0.0
		_apply_contact_damage()

# -----------------------------------------------------------------------------
# External forces
# -----------------------------------------------------------------------------
func apply_knockback(force: Vector2) -> void:
	if _dead:
		return
	var mult: float = max(0.0, 1.0 - knockback_resistance)

	match knockback_mode:
		KnockMode.PROJECTILE_DIR:
			_kb_vel += force * mult

		KnockMode.BACK_ONLY:
			var mag: float = force.length()
			var back_dir: Vector2 = _pick_back_dir()
			_kb_vel += back_dir * mag * mult

		KnockMode.BACK_CLAMP:
			var back_dir: Vector2 = _pick_back_dir()
			var comp: float = max(0.0, force.dot(back_dir))
			_kb_vel += back_dir * comp * mult

# -----------------------------------------------------------------------------
# Retargeting
# -----------------------------------------------------------------------------
func _reselect_target() -> void:
	var best: Node2D = _nexus
	var best_score: float = -1e9
	if is_instance_valid(_nexus):
		best = _nexus
		best_score = _score_target(_nexus)
	if is_instance_valid(_player):
		var s_p: float = _score_target(_player)
		if s_p > best_score:
			best = _player
			best_score = s_p
	if best != null and best != _target:
		_target = best

func _score_target(t: Node2D) -> float:
	if t == null:
		return -1e9
	var d: float = max(1.0, _dist_to(t))
	var score: float = (1.0 / d) * distance_weight
	if t == _player:
		if d <= prefer_player_within:
			score += player_proximity_bonus
		var hp_ratio: float = 1.0
		if "hp" in _player and "max_hp" in _player:
			var ph: int = int(_player.hp)
			var pm: int = max(1, int(_player.max_hp))
			hp_ratio = float(ph) / float(pm)
		hp_ratio = clamp(hp_ratio, 0.0, 1.0)
		score += (1.0 - hp_ratio) * player_hp_weight
	if t == _target:
		score += current_target_stickiness
	return score

# -----------------------------------------------------------------------------
# Damage
# -----------------------------------------------------------------------------
func take_hit(dmg: int) -> void:
	if dmg < 0 or _dead:
		return
	_pending_damage += dmg

# -----------------------------------------------------------------------------
# Contact damage
# -----------------------------------------------------------------------------
func _apply_contact_damage() -> void:
	var player_overlap: bool = false
	var nexus_overlap: bool = false
	if is_instance_valid(_player):
		var dp: float = _dist_to(_player)
		if _touching_player or dp <= manual_attack_radius:
			player_overlap = true
	if is_instance_valid(_nexus):
		var dn: float = _dist_to(_nexus)
		if _touching_nexus or dn <= manual_attack_radius:
			nexus_overlap = true
	if player_overlap and nexus_overlap:
		if _score_target(_player) >= _score_target(_nexus):
			_damage_player()
		else:
			_damage_nexus()
	elif player_overlap:
		_damage_player()
	elif nexus_overlap:
		_damage_nexus()

func _damage_player() -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("take_hit"):
		_player.take_hit(touch_damage, self)
		_after_attack("Player")

func _damage_nexus() -> void:
	if not is_instance_valid(_nexus):
		return
	if _nexus.has_method("apply_damage"):
		_nexus.apply_damage(touch_damage)
		_after_attack("Nexus")

func _after_attack(label: String) -> void:
	if _has_anim("attack"):
		_play_once("attack")
	if debug_attack_logs:
		print("[Enemy#", str(get_instance_id()), "] attack tick -> ",
			label, " ", str(touch_damage))

# -----------------------------------------------------------------------------
# Lifesteal notify
# -----------------------------------------------------------------------------
func _notify_player_damage_dealt(applied: int) -> void:
	if applied <= 0:
		return
	var p: Node = _player
	if p == null or not is_instance_valid(p):
		p = _first_in_group("player")
	if p and p.has_method("report_damage_dealt"):
		p.report_damage_dealt(applied)

# -----------------------------------------------------------------------------
# Flash visuals
# -----------------------------------------------------------------------------
func _find_visual() -> CanvasItem:
	var q: Array[Node] = [self]
	while q.size() > 0:
		var n: Node = q.pop_front()
		if n is AnimatedSprite2D:
			return n as CanvasItem
		if n is Sprite2D:
			return n as CanvasItem
		for c in n.get_children():
			q.push_back(c as Node)
	var q2: Array[Node] = [self]
	while q2.size() > 0:
		var n2: Node = q2.pop_front()
		if n2 != self and n2 is CanvasItem:
			return n2 as CanvasItem
		for c2 in n2.get_children():
			q2.push_back(c2 as Node)
	return self

func _flash_hit() -> void:
	if not is_instance_valid(_visual):
		return
	if _flashing:
		_reset_visual_modulate()
	_flashing = true
	_visual.modulate = _flash_color
	_visual.self_modulate = _flash_color
	await get_tree().create_timer(hit_flash_time, true).timeout
	if not is_instance_valid(self) or not is_instance_valid(_visual):
		return
	_reset_visual_modulate()
	_flashing = false

func _reset_visual_modulate() -> void:
	_visual.modulate = Color(1, 1, 1)
	_visual.self_modulate = Color(1, 1, 1)

# -----------------------------------------------------------------------------
# Contact sensing
# -----------------------------------------------------------------------------
func _on_contact_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("nexus"):
		_touching_nexus = true
		_nexus = body as Node2D
		_contact_accum = contact_interval
		if debug_attack_logs:
			print("[Enemy#", str(get_instance_id()),
				"] begin attack on Nexus")
	elif body.is_in_group("player"):
		_touching_player = true
		_player = body as Node2D
		_contact_accum = contact_interval
		if debug_attack_logs:
			print("[Enemy#", str(get_instance_id()),
				"] begin attack on Player")

func _on_contact_body_exited(body: Node) -> void:
	if body == null:
		return
	if body == _nexus:
		_touching_nexus = false
		if debug_attack_logs:
			print("[Enemy#", str(get_instance_id()),
				"] end attack on Nexus")
	if body == _player:
		_touching_player = false
		if debug_attack_logs:
			print("[Enemy#", str(get_instance_id()),
				"] end attack on Player")

# -----------------------------------------------------------------------------
# Debug draw
# -----------------------------------------------------------------------------
func _draw() -> void:
	if not debug_draw or _target == null:
		return
	draw_line(Vector2.ZERO, to_local(_target.global_position),
		Color(1, 0, 0), 2.0)

# -----------------------------------------------------------------------------
# Global and JSON archetype application
# -----------------------------------------------------------------------------
func _apply_global_scalers() -> void:
	var hp_m: float = 1.0
	var dmg_m: float = 1.0
	var spd_m: float = 1.0
	if _gs:
		if _gs.has_method("get_enemy_hp_mult"):
			hp_m = max(0.1, float(_gs.get_enemy_hp_mult()))
		if _gs.has_method("get_enemy_damage_mult"):
			dmg_m = max(0.1, float(_gs.get_enemy_damage_mult()))
		if _gs.has_method("get_enemy_speed_mult"):
			spd_m = max(0.1, float(_gs.get_enemy_speed_mult()))
	hp = max(1, int(round(float(hp) * hp_m)))
	touch_damage = int(max(0, round(float(touch_damage) * dmg_m)))
	speed *= spd_m

func _db() -> Node:
	return get_node_or_null("/root/EnemyDB")

func _apply_archetype_json() -> void:
	if archetype_key == "":
		_flash_color = Color(1, 0, 0, 1)
		_drop_mult = 1.0
		if debug_archetype_logs:
			print("[Enemy#", str(get_instance_id()),
				"] no archetype; speed=", str(speed),
				" hp=", str(hp), " dmg=", str(touch_damage))
		if debug_spawn_logs:
			_log_spawn_stats()
		_ensure_sprite_node()
		_start_default_anim()
		return
	var db: Node = _db()
	if db == null:
		if debug_archetype_logs:
			print("[Enemy#", str(get_instance_id()),
				"] EnemyDB missing; key=", archetype_key)
		_use_def({})
		if debug_spawn_logs:
			_log_spawn_stats()
		_ensure_sprite_node()
		_start_default_anim()
		return
	var def: Dictionary = db.get_def(archetype_key)
	_use_def(def)
	_apply_sprite_from_def(def)
	if debug_archetype_logs:
		print("[Enemy#", str(get_instance_id()), "] applied key=",
			archetype_key, " speed=", str(speed), " hp=",
			str(hp), " dmg=", str(touch_damage), " contact=",
			str(contact_interval))
	if debug_spawn_logs:
		_log_spawn_stats()

func _use_def(def: Dictionary) -> void:
	var speed_mult: float = float(def.get("speed_mult", 1.0))
	var hp_mult: float = float(def.get("hp_mult", 1.0))
	var dmg_mult: float = float(def.get("touch_damage_mult", 1.0))
	var retarget_add: float = float(def.get("retarget_interval_add", 0.0))
	var prefer_override: float = float(
		def.get("prefer_player_within_override", -1.0))
	var prox_add: float = float(def.get("player_proximity_bonus_add", 0.0))
	var dist_w_add: float = float(def.get("distance_weight_add", 0.0))
	var php_w_add: float = float(def.get("player_hp_weight_add", 0.0))
	var stick_add: float = float(
		def.get("current_target_stickiness_add", 0.0))
	var atk_radius_add: float = float(
		def.get("manual_attack_radius_add", 0.0))
	var stop_add: float = float(def.get("stop_distance_add", 0.0))
	var contact_mult: float = float(def.get("contact_interval_mult", 1.0))
	var drop_mult: float = float(def.get("biscuit_drop_mult", 1.0))
	var flash_mult: float = float(def.get("hit_flash_time_mult", 1.0))
	var tint_s: String = String(def.get("tint", ""))
	var flash_s: String = String(def.get("hit_flash_tint", ""))
	speed *= speed_mult
	hp = max(1, int(round(float(hp) * hp_mult)))
	touch_damage = int(round(float(touch_damage) * dmg_mult))
	retarget_interval = max(0.05, retarget_interval + retarget_add)
	if prefer_override >= 0.0:
		prefer_player_within = prefer_override
	player_proximity_bonus += prox_add
	distance_weight += dist_w_add
	player_hp_weight += php_w_add
	current_target_stickiness += stick_add
	manual_attack_radius = max(0.0, manual_attack_radius + atk_radius_add)
	stop_distance = max(0.0, stop_distance + stop_add)
	contact_interval = max(0.05, contact_interval * contact_mult)
	_drop_mult = max(0.1, drop_mult)
	hit_flash_time = max(0.01, _base_flash_time * flash_mult)
	if flash_s != "":
		_flash_color = Color(flash_s)
	else:
		_flash_color = Color(1, 0, 0, 1)
	if is_instance_valid(_visual) and tint_s != "":
		_visual.self_modulate = Color(tint_s)

# -----------------------------------------------------------------------------
# Sprite config
# -----------------------------------------------------------------------------
func _apply_sprite_from_def(def: Dictionary) -> void:
	if not def.has("sprite"):
		_ensure_sprite_node()
		_start_default_anim()
		return
	var sdef: Dictionary = def["sprite"]
	_faces_right = bool(sdef.get("faces_right", true))
	_anim_speed_base = float(sdef.get("speed_scale", 1.0))
	var scale_mult: float = float(sdef.get("scale", 1.0))
	if sdef.has("anim_map") and typeof(sdef["anim_map"]) == TYPE_DICTIONARY:
		for k in sdef["anim_map"].keys():
			_anim_map[String(k)] = String(sdef["anim_map"][k])
	var default_anim: String = String(
		sdef.get("default_anim", _anim_map.get("move", "Run"))
	)
	_ensure_sprite_node()
	if sdef.has("frames"):
		var frames_path: String = String(sdef["frames"])
		var frames: SpriteFrames = ResourceLoader.load(frames_path) \
			as SpriteFrames
		if frames != null:
			_sprite.sprite_frames = frames
		else:
			push_warning("Enemy: could not load SpriteFrames at " + frames_path)
	if is_instance_valid(_visual) and _visual != self:
		_visual.scale = Vector2.ONE * scale_mult
	if _sprite != null and _sprite.sprite_frames != null:
		var anim_to_play: String = default_anim
		if not _sprite.sprite_frames.has_animation(anim_to_play):
			var move_nm: String = String(_anim_map.get("move", "Run"))
			var idle_nm: String = String(_anim_map.get("idle", "Run"))
			if _sprite.sprite_frames.has_animation(move_nm):
				anim_to_play = move_nm
			elif _sprite.sprite_frames.has_animation(idle_nm):
				anim_to_play = idle_nm
		if anim_to_play != "":
			_sprite.play(anim_to_play)
			_update_anim_speed()

func _start_default_anim() -> void:
	_ensure_sprite_node()
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var move_nm: String = String(_anim_map.get("move", "Run"))
	var idle_nm: String = String(_anim_map.get("idle", "Run"))
	var pick: String = ""
	if _sprite.sprite_frames.has_animation(move_nm):
		pick = move_nm
	elif _sprite.sprite_frames.has_animation(idle_nm):
		pick = idle_nm
	if pick != "":
		_sprite.play(pick)
		_update_anim_speed()

func _ensure_sprite_node() -> void:
	if _visual is AnimatedSprite2D:
		_sprite = _visual as AnimatedSprite2D
		return
	var found: Node = get_node_or_null("Sprite")
	if found != null and found is AnimatedSprite2D:
		_sprite = found as AnimatedSprite2D
		_visual = _sprite
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	add_child(_sprite)
	_visual = _sprite

func _update_visual_orientation(dir: Vector2) -> void:
	if dir.x == 0.0:
		return
	var want_right: bool = dir.x >= 0.0
	var flip_h: bool = false
	if _faces_right:
		flip_h = not want_right
	else:
		flip_h = want_right
	if _visual is Sprite2D:
		var spr: Sprite2D = _visual as Sprite2D
		spr.flip_h = flip_h
	elif _visual is AnimatedSprite2D:
		var aspr: AnimatedSprite2D = _visual as AnimatedSprite2D
		aspr.flip_h = flip_h
	else:
		var sx: float = abs(_visual.scale.x)
		_visual.scale.x = -sx if flip_h else sx

func _update_move_idle(dir: Vector2) -> void:
	if _oneshot_playing or _dead:
		return
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var moving: bool = dir.length_squared() > 1e-6
	var key: String = "move" if moving else "idle"
	var want: String = String(_anim_map.get(key, "Run"))
	if _sprite.animation != want and _sprite.sprite_frames.has_animation(want):
		_sprite.play(want)
	_update_anim_speed()

func _update_anim_speed() -> void:
	if _sprite == null:
		return
	_sprite.speed_scale = max(0.01, _anim_speed_base * (speed / 300.0))

func _has_anim(kind: String) -> bool:
	if _sprite == null or _sprite.sprite_frames == null:
		return false
	var nm: String = String(_anim_map.get(kind, ""))
	return nm != "" and _sprite.sprite_frames.has_animation(nm)

func _estimate_anim_time(kind: String, fallback: float = 0.35) -> float:
	if _sprite == null or _sprite.sprite_frames == null:
		return fallback
	var nm: String = String(_anim_map.get(kind, ""))
	if nm == "" or not _sprite.sprite_frames.has_animation(nm):
		return fallback
	var frames: int = _sprite.sprite_frames.get_frame_count(nm)
	var fps: float = 10.0
	if _sprite.sprite_frames.has_method("get_animation_speed"):
		fps = float(_sprite.sprite_frames.get_animation_speed(nm))
	if fps <= 0.0:
		fps = 10.0
	var scale: float = max(0.001, float(_sprite.speed_scale))
	return float(frames) / (fps * scale)

func _play_once(kind: String, max_time: float = -1.0) -> void:
	if _dead or _oneshot_playing or not _has_anim(kind) or _sprite == null:
		return
	var my_gen: int = _anim_gen
	_oneshot_playing = true
	var nm: String = String(_anim_map.get(kind))
	_sprite.play(nm)
	var dur: float = max_time
	if dur <= 0.0:
		dur = _estimate_anim_time(kind, 0.35)
	await get_tree().create_timer(dur, true).timeout
	if _dead or my_gen != _anim_gen:
		return
	_oneshot_playing = false
	_update_move_idle(velocity.normalized())

# -----------------------------------------------------------------------------
# Biscuit drop
# -----------------------------------------------------------------------------
func _try_drop_biscuit() -> void:
	var chance: float = clamp(0.25 * _drop_mult, 0.0, 1.0)
	if biscuit_pickup_scene == null:
		return
	if randf() <= chance:
		var root: Node = get_tree().current_scene
		var parent: Node = root.get_node_or_null("Pickups")
		if parent == null:
			parent = root
		var pickup: Node2D = biscuit_pickup_scene.instantiate() as Node2D
		parent.add_child(pickup)
		pickup.global_position = global_position
		if pickup.has_method("init_with_value"):
			pickup.init_with_value(1)

# -----------------------------------------------------------------------------
# Death
# -----------------------------------------------------------------------------
func _die() -> void:
	if _dead:
		return
	_dead = true
	_anim_gen += 1
	_oneshot_playing = false
	velocity = Vector2.ZERO
	_kb_vel = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	if contact:
		contact.monitoring = false
	_try_drop_biscuit()
	if _has_anim("die"):
		var nm: String = String(_anim_map.get("die"))
		if _sprite != null and _sprite.sprite_frames != null:
			if _sprite.sprite_frames.has_animation(nm):
				_sprite.play(nm)
		var dur: float = _estimate_anim_time("die", 0.5)
		var my_gen: int = _anim_gen
		await get_tree().create_timer(dur, true).timeout
		if my_gen != _anim_gen:
			return
	queue_free()

# -----------------------------------------------------------------------------
# Spawn log
# -----------------------------------------------------------------------------
func _log_spawn_stats() -> void:
	var wave_i: int = 0
	if _gs and "wave" in _gs:
		wave_i = int(_gs.wave)
	var disp: String = archetype_key
	var db: Node = _db()
	if archetype_key != "" and db != null:
		var def: Dictionary = db.get_def(archetype_key)
		var dn: String = String(def.get("display_name", ""))
		if dn != "":
			disp = dn
	var tick_rate: float = 0.0
	if contact_interval > 0.0:
		tick_rate = 1.0 / contact_interval
	print("[Enemy#", str(get_instance_id()), "] spawn wave=", str(wave_i),
		" archetype=", (archetype_key if archetype_key != "" else "(default)"),
		" (", disp, ")", " hp=", str(hp), " dmg=", str(touch_damage),
		" spd=", str(speed), " contact=", str(contact_interval),
		" tick/s=", str(tick_rate), " stop=", str(stop_distance),
		" atk=", str(manual_attack_radius), " retarget=",
		str(retarget_interval))

# -----------------------------------------------------------------------------
# Small utilities
# -----------------------------------------------------------------------------
func _first_in_group(group_name: String) -> Node2D:
	var list: Array = get_tree().get_nodes_in_group(group_name)
	if list.size() > 0:
		var n: Node = list[0]
		if n is Node2D:
			return n as Node2D
	return null

func _dist_to(n: Node2D) -> float:
	return global_position.distance_to(n.global_position)

func _reached(accum: float, period: float) -> bool:
	return period > 0.0 and accum >= period

func get_drop_multiplier() -> float:
	return _drop_mult

func _pick_back_dir() -> Vector2:
	if _base_move_dir.length_squared() > 1e-6:
		return -_base_move_dir
	return Vector2((randi() & 1) * 2 - 1, 0.0).normalized()
