extends Node2D

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var turret_scene: PackedScene
@export var deploy_interval: float = 8.0
@export var max_turrets: int = 3
@export var sprite_forward_offset: float = 0.0

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var _cooldown: float = 0.0
var _json_weapon: Dictionary = {}
var _turret_def: Dictionary = {}
var _gs: Node = null
var _muzzle: Marker2D = null
var _atk_mult: float = 1.0
var _proj_speed_mult: float = 1.0
var _turrets: Array[Node2D] = []
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("orbitless")
	_gs = get_node_or_null("/root/GameState")
	_muzzle = get_node_or_null("Muzzle") as Marker2D

# -----------------------------------------------------------------------------
# WeaponManager hooks
# -----------------------------------------------------------------------------
func set_attack_speed_bonus_pct(v: float) -> void:
	_atk_mult = 1.0 + float(clamp(v, -95.0, 5000.0)) / 100.0

func set_projectile_speed_from_attack_mult(m: float) -> void:
	_proj_speed_mult = max(0.05, float(m))

# -----------------------------------------------------------------------------
# JSON setup
# -----------------------------------------------------------------------------
func setup_from_json(key: String, weapon_dict_v: Variant) -> void:
	if typeof(weapon_dict_v) == TYPE_DICTIONARY:
		_json_weapon = weapon_dict_v
	else:
		_json_weapon = {}
	deploy_interval = float(_json_weapon.get(
		"deploy_interval", deploy_interval))
	if _json_weapon.has("turret") and \
		typeof(_json_weapon["turret"]) == TYPE_DICTIONARY:
		_turret_def = _json_weapon["turret"]
	else:
		_turret_def = {}

	var tex_path: String = String(_json_weapon.get("sprite_tex", ""))
	if tex_path != "" and _sprite:
		var res: Resource = load(tex_path)
		if res is Texture2D:
			_sprite.texture = res
	if _sprite:
		var sx: float = float(_json_weapon.get(
			"sprite_scale_x", _sprite.scale.x))
		var sy: float = float(_json_weapon.get(
			"sprite_scale_y", _sprite.scale.y))
		_sprite.scale = Vector2(sx, sy)

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		_deploy_turret()
		_cooldown = deploy_interval

# -----------------------------------------------------------------------------
# Deploy
# -----------------------------------------------------------------------------
func _deploy_turret() -> void:
	if turret_scene == null:
		return
	var world: Node = get_tree().current_scene
	if world == null:
		return
	if _turrets.size() >= max_turrets:
		var old: Node2D = _turrets.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	var t: Node2D = turret_scene.instantiate() as Node2D
	if t == null:
		return
	world.add_child(t)
	t.global_position = _spawn_position()

	if t.has_method("setup_from_dict"):
		t.call("setup_from_dict", _turret_def, _json_weapon)
	if t.has_method("set_attack_speed_bonus_pct"):
		t.call("set_attack_speed_bonus_pct", (_atk_mult - 1.0) * 100.0)
	if t.has_method("set_projectile_speed_from_attack_mult"):
		t.call("set_projectile_speed_from_attack_mult", _proj_speed_mult)

	_turrets.append(t)
	t.tree_exited.connect(_on_turret_exited.bind(t))

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _spawn_position() -> Vector2:
	if _muzzle:
		return _muzzle.global_position
	return global_position

func _on_turret_exited(t: Node) -> void:
	_turrets.erase(t)
