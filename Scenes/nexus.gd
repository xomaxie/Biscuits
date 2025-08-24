extends StaticBody2D

signal hp_changed(current: int, maxv: int)
signal nexus_destroyed

@export var max_hp: int = 100
@export var contact_damage_interval: float = 0.35   # how often enemies can chip the nexus

var hp: int
var _damage_cooldowns := {}

func _ready() -> void:
	add_to_group("nexus")
	hp = max_hp
	hp_changed.emit(hp, max_hp)

func apply_damage(amount: int) -> void:
	hp = max(0, hp - max(0, amount))
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		nexus_destroyed.emit()

func on_enemy_touch(enemy: Node) -> void:
	_damage_cooldowns[enemy] = 0.0

func on_enemy_leave(enemy: Node) -> void:
	_damage_cooldowns.erase(enemy)

func _physics_process(delta: float) -> void:
	for e in _damage_cooldowns.keys():
		_damage_cooldowns[e] += delta
		if _damage_cooldowns[e] >= contact_damage_interval:
			_damage_cooldowns[e] = 0.0
			apply_damage(1) 
