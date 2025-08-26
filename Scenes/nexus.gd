extends StaticBody2D

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------
signal hp_changed(current: int, maxv: int)
signal nexus_destroyed

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var max_hp: int = 100
@export var contact_damage_interval: float = 0.35

# -----------------------------------------------------------------------------
# Animation constants
# -----------------------------------------------------------------------------
const ANIM_IDLE: String = "Idle"
const ANIM_ON_HIT: String = "OnHit"
const ANIM_DESTROYED: String = "Destroyed"

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
var hp: int = 0
var _is_destroyed: bool = false
var _touch_timers: Dictionary = {}

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
@onready var damage_zone: Area2D = get_node_or_null("DamageZone") as Area2D
@onready var anim_sprite: AnimatedSprite2D = null
@onready var anim_player: AnimationPlayer = null

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("nexus")

	anim_sprite = get_node_or_null("Sprite2D") as AnimatedSprite2D
	if anim_sprite == null:
		anim_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer

	hp = max_hp
	hp_changed.emit(hp, max_hp)

	if damage_zone != null:
		if not damage_zone.body_entered.is_connected(_on_zone_enter):
			damage_zone.body_entered.connect(_on_zone_enter)
		if not damage_zone.body_exited.is_connected(_on_zone_exit):
			damage_zone.body_exited.connect(_on_zone_exit)

	if anim_sprite != null and not anim_sprite.animation_finished.is_connected(_on_anim_sprite_finished):
		anim_sprite.animation_finished.connect(_on_anim_sprite_finished)
	if anim_player != null and not anim_player.animation_finished.is_connected(_on_anim_player_finished):
		anim_player.animation_finished.connect(_on_anim_player_finished)

	_play_idle()

# -----------------------------------------------------------------------------
# Health & damage
# -----------------------------------------------------------------------------
func apply_damage(amount: int) -> void:
	if _is_destroyed:
		return
	var prev: int = hp
	hp = max(0, prev - max(0, amount))
	hp_changed.emit(hp, max_hp)

	if hp <= 0:
		_is_destroyed = true
		if damage_zone != null:
			damage_zone.monitoring = false
		_play_destroyed()
		nexus_destroyed.emit()
	else:
		_play_on_hit()

func on_enemy_touch(enemy: Node) -> void:
	var id: int = enemy.get_instance_id()
	_touch_timers[id] = 0.0

func on_enemy_leave(enemy: Node) -> void:
	var id: int = enemy.get_instance_id()
	_touch_timers.erase(id)

func _physics_process(delta: float) -> void:
	var keys: Array = _touch_timers.keys().duplicate()
	for k in keys:
		var id: int = int(k)
		if not _touch_timers.has(id):
			continue
		var obj: Object = instance_from_id(id)
		if obj == null:
			_touch_timers.erase(id)
			continue

		var t_val: Variant = _touch_timers.get(id, 0.0)
		var t: float = float(t_val) + delta
		if t >= contact_damage_interval:
			t -= contact_damage_interval
			apply_damage(1)

		if _touch_timers.has(id):
			_touch_timers[id] = t

# -----------------------------------------------------------------------------
# DamageZone handlers
# -----------------------------------------------------------------------------
func _on_zone_enter(body: Node) -> void:
	if body.is_in_group("enemies"):
		on_enemy_touch(body)

func _on_zone_exit(body: Node) -> void:
	if body.is_in_group("enemies"):
		on_enemy_leave(body)

# -----------------------------------------------------------------------------
# Animation helpers
# -----------------------------------------------------------------------------
func _play_idle() -> void:
	if _is_destroyed:
		return
	if anim_sprite != null and anim_sprite.sprite_frames != null:
		var name: String = ANIM_IDLE
		if not _has_sprite_anim(name):
			var names: PackedStringArray = anim_sprite.sprite_frames.get_animation_names()
			if names.size() > 0:
				name = names[0]
		if anim_sprite.animation != name:
			anim_sprite.play(name)
	elif anim_player != null and anim_player.has_animation(ANIM_IDLE):
		anim_player.play(ANIM_IDLE)

func _play_on_hit() -> void:
	if anim_sprite != null and _has_sprite_anim(ANIM_ON_HIT):
		anim_sprite.play(ANIM_ON_HIT)
	elif anim_player != null and anim_player.has_animation(ANIM_ON_HIT):
		anim_player.play(ANIM_ON_HIT)

func _play_destroyed() -> void:
	if anim_sprite != null and _has_sprite_anim(ANIM_DESTROYED):
		anim_sprite.play(ANIM_DESTROYED)
	elif anim_player != null and anim_player.has_animation(ANIM_DESTROYED):
		anim_player.play(ANIM_DESTROYED)

func _has_sprite_anim(name: String) -> bool:
	return anim_sprite != null \
		and anim_sprite.sprite_frames != null \
		and name in anim_sprite.sprite_frames.get_animation_names()

func _on_anim_sprite_finished() -> void:
	if _is_destroyed:
		return
	if anim_sprite.animation == ANIM_ON_HIT:
		_play_idle()

func _on_anim_player_finished(anim_name: StringName) -> void:
	if _is_destroyed:
		return
	if String(anim_name) == ANIM_ON_HIT:
		_play_idle()
