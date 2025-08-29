extends Area2D

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var lifetime: float = 2.0
@export var damage: int = 1
@export var speed: float = 620.0
@export var aoe_radius: float = 0.0
@export var tint_color: Color = Color(1, 1, 1, 0.7)

# -----------------------------------------------------------------------------
# Runtime State
# -----------------------------------------------------------------------------
var velocity: Vector2 = Vector2.ZERO
var pierce_left: int = 0
var knockback: float = 0.0
var _spawn_pos: Vector2 = Vector2.ZERO
var _max_distance: float = -1.0
var _alive: bool = false
var _crit_chance_pct: float = 0.0
var _crit_mult: float = 2.0
var _explosion_mult: float = 1.0
var _split_child_scene: PackedScene = null
var _split_count: int = 0
var _split_damage: int = 0
var _split_spread_deg: float = 360.0
var _split_lifetime_sec: float = 0.6
var _split_speed_mult: float = 1.0
var _split_tex_path: String = ""
var _split_scale_override: Vector2 = Vector2.ZERO
var _did_split: bool = false

# -----------------------------------------------------------------------------
# Node Refs
# -----------------------------------------------------------------------------
@onready var shape: CollisionShape2D = (
	get_node_or_null("CollisionShape2D") as CollisionShape2D
)
@onready var _visuals: Array[CanvasItem] = _find_visuals()

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	monitoring = true
	monitorable = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if shape != null:
		shape.disabled = false
	_spawn_pos = global_position
	_alive = true
	_apply_tint()

# -----------------------------------------------------------------------------
# Init (called by weapon)
# -----------------------------------------------------------------------------
func init(
	dir: Vector2,
	speed_in: float,
	dmg: int,
	lifetime_sec: float = -1.0,
	start_pos: Vector2 = Vector2.INF,
	max_distance: float = -1.0,
	pierce: int = 0,
	kb: float = 0.0,
	aoe: float = -1.0
) -> void:
	var d: Vector2 = dir.normalized()
	velocity = d * speed_in
	speed = speed_in
	damage = dmg
	rotation = d.angle()
	if start_pos != Vector2.INF:
		_spawn_pos = start_pos
		global_position = start_pos
	if lifetime_sec >= 0.0:
		lifetime = lifetime_sec
	_max_distance = max_distance
	pierce_left = max(0, pierce)
	knockback = kb
	if aoe >= 0.0:
		aoe_radius = aoe
	_apply_tint()

# -----------------------------------------------------------------------------
# Optional config
# -----------------------------------------------------------------------------
func set_crit(chance_pct: float, mult: float = 2.0) -> void:
	_crit_chance_pct = max(0.0, chance_pct)
	_crit_mult = max(1.0, mult)

func set_explosion_mult(m: float) -> void:
	_explosion_mult = max(0.0, m)

func set_split_options(opts: Dictionary) -> void:
	_split_child_scene = opts.get("child_scene", _split_child_scene)
	_split_count = int(opts.get("count", _split_count))
	_split_damage = int(opts.get("damage", _split_damage))
	_split_spread_deg = float(opts.get("spread_deg", _split_spread_deg))
	_split_lifetime_sec = float(opts.get("lifetime_sec", _split_lifetime_sec))
	_split_speed_mult = float(opts.get("speed_mult", _split_speed_mult))
	_split_tex_path = String(opts.get("tex_path", _split_tex_path))
	var s = opts.get("scale_override", _split_scale_override)
	if typeof(s) == TYPE_VECTOR2:
		_split_scale_override = s

func set_split_params(
	child_scene: PackedScene,
	count: int,
	dmg: int,
	tex_path: String = "",
	scale_override: Vector2 = Vector2.ZERO
) -> void:
	_split_child_scene = child_scene
	_split_count = count
	_split_damage = dmg
	_split_tex_path = tex_path
	_split_scale_override = scale_override
	_split_spread_deg = 360.0

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not _alive:
		return
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		_despawn()
		return
	if _max_distance >= 0.0:
		var traveled: float = _spawn_pos.distance_to(global_position)
		if traveled >= _max_distance:
			_despawn()
			return

# -----------------------------------------------------------------------------
# Hits
# -----------------------------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	_apply_hit(body)

func _on_area_entered(area: Area2D) -> void:
	var owner_node: Node = area.get_parent()
	if owner_node != null:
		_apply_hit(owner_node)

func _apply_hit(target: Node) -> void:
	if not _alive:
		return
	if target != null and target.has_method("take_hit"):
		var final_damage: int = damage
		if _crit_chance_pct > 0.0 and randf() < (_crit_chance_pct / 100.0):
			final_damage = int(
				max(1.0, round(float(final_damage) * _crit_mult))
			)
		target.call("take_hit", final_damage)
	if knockback > 0.0 and target != null:
		var dir: Vector2 = (
			(target as Node2D).global_position - global_position
		).normalized()
		var force: Vector2 = dir * knockback * _knock_mult()
		if target.has_method("apply_knockback"):
			target.call("apply_knockback", force)
		elif target is CharacterBody2D:
			var body: CharacterBody2D = target as CharacterBody2D
			body.velocity += force
	if aoe_radius > 0.0 or _split_count > 0:
		_explode_and_split()
		return
	if pierce_left > 0:
		pierce_left -= 1
	else:
		_despawn()

# -----------------------------------------------------------------------------
# Explosion + Split
# -----------------------------------------------------------------------------
func _explode_and_split() -> void:
	if _did_split:
		_despawn()
		return
	_did_split = true
	if aoe_radius > 0.0:
		_apply_aoe_damage()
	if _split_child_scene != null and _split_count > 0 \
	and is_instance_valid(_split_child_scene):
		var world: Node = get_tree().current_scene
		if world != null:
			var base_ang: float = velocity.angle()
			var full_circle: bool = (_split_spread_deg >= 359.0)
			var step: float = 0.0
			var start: float = 0.0
			if _split_count > 1:
				if full_circle:
					step = TAU / float(_split_count)
					start = 0.0
				else:
					step = deg_to_rad(_split_spread_deg) \
						/ float(_split_count - 1)
					start = -deg_to_rad(_split_spread_deg) * 0.5
			for i in _split_count:
				var ang: float = (
					base_ang + (start + step * float(i))
				) if not full_circle else (start + step * float(i))
				var dir: Vector2 = Vector2.RIGHT.rotated(ang)
				var child: Node2D = _split_child_scene.instantiate() as Node2D
				if child == null:
					continue
				world.add_child(child)
				child.global_position = global_position
				_apply_child_visuals(
					child, _split_tex_path, _split_scale_override
				)
				if child.has_method("init"):
					var spd: float = speed * max(0.05, _split_speed_mult)
					child.call(
						"init",
						dir,
						spd,
						max(1, _split_damage),
						_split_lifetime_sec,
						global_position,
						-1.0,
						0,
						knockback,
						0.0
					)
	_despawn()

# -----------------------------------------------------------------------------
# AOE
# -----------------------------------------------------------------------------
func _apply_aoe_damage() -> void:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = aoe_radius
	var params: PhysicsShapeQueryParameters2D = \
		PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.transform = Transform2D(0.0, global_position)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hits: Array[Dictionary] = space.intersect_shape(params, 64)
	var aoe_dmg: int = int(
		max(1.0, round(float(damage) * max(0.0, _explosion_mult)))
	)
	for h in hits:
		var collider: Object = h.get("collider")
		var node: Node = collider as Node
		if node != null and node != self and node.has_method("take_hit"):
			node.call("take_hit", aoe_dmg)

# -----------------------------------------------------------------------------
# Visuals
# -----------------------------------------------------------------------------
func _find_visuals() -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	var stack: Array[Node] = [self]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			var cn: Node = c as Node
			if cn == null:
				continue
			if cn is AnimatedSprite2D or cn is Sprite2D \
			or cn is GPUParticles2D:
				out.append(cn as CanvasItem)
			stack.append(cn)
	return out

func _apply_tint() -> void:
	var a: float = clamp(tint_color.a, 0.0, 1.0)
	var base: Color = Color(tint_color.r, tint_color.g, tint_color.b, a)
	if _visuals.is_empty():
		_visuals = _find_visuals()
	for v in _visuals:
		if is_instance_valid(v):
			v.self_modulate = base

func _apply_child_visuals(node: Node, tex_path: String,
	scale_override: Vector2) -> void:
	if tex_path == "" and scale_override == Vector2.ZERO:
		return
	var spr: Sprite2D = null
	if node is Sprite2D:
		spr = node as Sprite2D
	else:
		spr = node.get_node_or_null("Sprite2D") as Sprite2D
		if spr == null:
			for c in node.get_children():
				if c is Sprite2D:
					spr = c as Sprite2D
					break
	if spr != null:
		if tex_path != "":
			var res: Resource = load(tex_path)
			if res is Texture2D:
				spr.texture = res
		if scale_override != Vector2.ZERO:
			spr.scale = scale_override

# -----------------------------------------------------------------------------
# Despawn
# -----------------------------------------------------------------------------
func _despawn() -> void:
	_alive = false
	queue_free()

# -----------------------------------------------------------------------------
# Knockback helper
# -----------------------------------------------------------------------------
func _knock_mult() -> float:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs and gs.has_method("get_knockback_out_mult"):
		return float(gs.get_knockback_out_mult())
	return 1.0
