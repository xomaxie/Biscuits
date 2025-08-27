extends CharacterBody2D

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

# -----------------------------------------------------------------------------
# Node refs & runtime state
# -----------------------------------------------------------------------------
@onready var _visual: CanvasItem = _find_visual()
@onready var contact: Area2D = get_node_or_null("Contact") as Area2D

var _target: Node2D = null
var _nexus: Node2D = null
var _player: Node2D = null

var _touching_nexus: bool = false
var _touching_player: bool = false

var _contact_accum: float = 0.0
var _retarget_accum: float = 0.0

var _pending_damage: int = 0
var _took_damage_this_frame: bool = false
var _flashing: bool = false
var _gs: Node = null

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

	if _nexus == null:
		var nlist: Array = get_tree().get_nodes_in_group("nexus")
		if nlist.size() > 0:
			_nexus = nlist[0] as Node2D
	if _target == null and _nexus != null:
		_target = _nexus

	if _player == null:
		var plist: Array = get_tree().get_nodes_in_group("player")
		if plist.size() > 0:
			_player = plist[0] as Node2D

	if contact != null:
		contact.monitoring = true
		contact.monitorable = true
		if not contact.body_entered.is_connected(_on_contact_body_entered):
			contact.body_entered.connect(_on_contact_body_entered)
		if not contact.body_exited.is_connected(_on_contact_body_exited):
			contact.body_exited.connect(_on_contact_body_exited)

	var mult: float = 1.0
	if _gs and _gs.has_method("get_enemy_hp_mult"):
		mult = max(0.1, _gs.get_enemy_hp_mult())
	hp = max(1, int(round(float(hp) * mult)))

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if debug_draw:
		queue_redraw()

	_retarget_accum += delta
	if _retarget_accum >= retarget_interval:
		_retarget_accum = 0.0
		_reselect_target()

	if _target != null:
		var dist: float = _target.global_position.distance_to(
			global_position
		)
		var dir: Vector2 = Vector2.ZERO
		if dist > stop_distance:
			dir = global_position.direction_to(_target.global_position)
		velocity = dir * speed
		move_and_slide()

	if _pending_damage > 0:
		var applied: int = min(_pending_damage, hp)
		hp -= applied
		_pending_damage = 0
		_took_damage_this_frame = true
		_flash_hit()
		if applied > 0:
			_notify_player_damage_dealt(applied)
		if hp <= 0:
			queue_free()
			return

	_contact_accum += delta
	if _contact_accum >= contact_interval:
		_contact_accum = 0.0
		_apply_contact_damage()

	_took_damage_this_frame = false

# -----------------------------------------------------------------------------
# Retargeting
# -----------------------------------------------------------------------------
func _reselect_target() -> void:
	var best: Node2D = _nexus
	var best_score: float = -1e9

	if is_instance_valid(_nexus):
		var s_n: float = _score_target(_nexus)
		best = _nexus
		best_score = s_n

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
	var d: float = max(1.0, global_position.distance_to(t.global_position))
	var invd: float = 1.0 / d
	var score: float = invd * distance_weight

	if t == _player:
		if d <= prefer_player_within:
			score += player_proximity_bonus
		var hp_ratio: float = 1.0
		if "hp" in _player and "max_hp" in _player:
			var ph: int = int(_player.hp)
			var pm: int = max(1, int(_player.max_hp))
			hp_ratio = float(ph) / float(pm)
		score += (1.0 - clamp(hp_ratio, 0.0, 1.0)) * player_hp_weight

	if t == _target:
		score += current_target_stickiness

	return score

# -----------------------------------------------------------------------------
# Damage
# -----------------------------------------------------------------------------
func take_hit(dmg: int) -> void:
	if dmg < 0:
		dmg = 0
	_pending_damage += dmg

# -----------------------------------------------------------------------------
# Contact damage application
# -----------------------------------------------------------------------------
func _apply_contact_damage() -> void:
	var player_overlap: bool = false
	var nexus_overlap: bool = false

	if _player != null and is_instance_valid(_player):
		var dp: float = global_position.distance_to(_player.global_position)
		if _touching_player or dp <= manual_attack_radius:
			player_overlap = true

	if _nexus != null and is_instance_valid(_nexus):
		var dn: float = global_position.distance_to(_nexus.global_position)
		if _touching_nexus or dn <= manual_attack_radius:
			nexus_overlap = true

	if player_overlap and nexus_overlap:
		var sp: float = _score_target(_player)
		var sn: float = _score_target(_nexus)
		if sp >= sn:
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
		if debug_attack_logs:
			print(
				"[Enemy#", str(get_instance_id()),
				"] attack tick -> Player for ", str(touch_damage)
			)

func _damage_nexus() -> void:
	if not is_instance_valid(_nexus):
		return
	if _nexus.has_method("apply_damage"):
		_nexus.apply_damage(touch_damage)
		if debug_attack_logs:
			print(
				"[Enemy#", str(get_instance_id()),
				"] attack tick -> Nexus for ", str(touch_damage)
			)

# -----------------------------------------------------------------------------
# Lifesteal notify
# -----------------------------------------------------------------------------
func _notify_player_damage_dealt(applied:int) -> void:
	if applied <= 0:
		return
	var p: Node = _player
	if p == null or not is_instance_valid(p):
		var plist: Array = get_tree().get_nodes_in_group("player")
		if plist.size() > 0:
			p = plist[0]
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
		_visual.modulate = Color(1, 1, 1)
		_visual.self_modulate = Color(1, 1, 1)
	_flashing = true
	_visual.modulate = Color(1, 0, 0)
	_visual.self_modulate = Color(1, 0, 0)
	await get_tree().create_timer(hit_flash_time, true).timeout
	if not is_instance_valid(self) or not is_instance_valid(_visual):
		return
	_visual.modulate = Color(1, 1, 1)
	_visual.self_modulate = Color(1, 1, 1)
	_flashing = false

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
			print(
				"[Enemy#", str(get_instance_id()),
				"] begin attack on Nexus"
			)
	elif body.is_in_group("player"):
		_touching_player = true
		_player = body as Node2D
		_contact_accum = contact_interval
		if debug_attack_logs:
			print(
				"[Enemy#", str(get_instance_id()),
				"] begin attack on Player"
			)

func _on_contact_body_exited(body: Node) -> void:
	if body == null:
		return
	if body == _nexus:
		_touching_nexus = false
		if debug_attack_logs:
			print(
				"[Enemy#", str(get_instance_id()),
				"] end attack on Nexus"
			)
	if body == _player:
		_touching_player = false
		if debug_attack_logs:
			print(
				"[Enemy#", str(get_instance_id()),
				"] end attack on Player"
			)

# -----------------------------------------------------------------------------
# Debug draw
# -----------------------------------------------------------------------------
func _draw() -> void:
	if not debug_draw or _target == null:
		return
	draw_line(
		Vector2.ZERO,
		to_local(_target.global_position),
		Color(1, 0, 0),
		2.0
	)
