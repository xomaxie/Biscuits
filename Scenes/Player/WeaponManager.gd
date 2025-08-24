extends Node2D

@export var starting_ranged_weapon: PackedScene
@export var starting_melee_weapon: PackedScene
@export var starting_ranged_count: int = 1
@export var starting_melee_count: int = 0
@export var orbit_radius: float = 24.0
@export var orbit_speed: float = 1.5        # radians/sec

var _weapons: Array[Node2D] = []
var _angle_offset: float = 0.0

func _ready() -> void:
	_spawn_weapons(starting_ranged_weapon, starting_ranged_count)
	_spawn_weapons(starting_melee_weapon, starting_melee_count)

func _physics_process(delta: float) -> void:
	if _weapons.is_empty():
		return
	_angle_offset += orbit_speed * delta
	var step := TAU / float(_weapons.size())
	for i in _weapons.size():
		var angle := _angle_offset + step * float(i)
		var pos := Vector2(cos(angle), sin(angle)) * orbit_radius
		_weapons[i].position = pos
		_weapons[i].rotation = angle

func _spawn_weapons(scene: PackedScene, count: int) -> void:
	if scene == null or count <= 0:
		return
	for i in count:
		var w := scene.instantiate() as Node2D
		add_child(w)
		_weapons.append(w)
