extends Node2D

# -----------------------------------------------------------------------------
# Enums
# -----------------------------------------------------------------------------
enum Layout { RING, ELLIPSE, TOP_ARC }

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var starting_ranged_weapon: PackedScene
@export var starting_melee_weapon: PackedScene
@export var starting_ranged_count: int = 1
@export var starting_melee_count: int = 0

@export var layout: Layout = Layout.TOP_ARC
@export var center_offset: Vector2 = Vector2(0, -16)

# RING
@export var ring_radius: float = 28.0
@export var orbit_speed: float = 1.2
@export var animate_orbit: bool = false

# ELLIPSE
@export var ellipse_radius_x: float = 36.0
@export var ellipse_radius_y: float = 18.0

# TOP_ARC
@export var arc_radius: float = 32.0
@export var arc_center_angle: float = -PI * 0.5
@export var arc_span: float = PI

# Draw order
@export var z_index_boost: int = 0

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
var _weapons: Array[Node2D] = []
var _angle_offset: float = 0.0

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_spawn_weapons(starting_ranged_weapon, starting_ranged_count)
	_spawn_weapons(starting_melee_weapon, starting_melee_count)

func _physics_process(delta: float) -> void:
	var n: int = _weapons.size()
	if n == 0:
		return

	if animate_orbit and (layout == Layout.RING or layout == Layout.ELLIPSE):
		_angle_offset += orbit_speed * delta

	match layout:
		Layout.RING:
			_apply_ring_layout(n)
		Layout.ELLIPSE:
			_apply_ellipse_layout(n)
		Layout.TOP_ARC:
			_apply_top_arc_layout(n)

# -----------------------------------------------------------------------------
# Layouts
# -----------------------------------------------------------------------------
func _apply_ring_layout(n: int) -> void:
	var step: float = TAU / float(n)
	var base: float = _angle_offset
	for i in n:
		var angle: float = base + step * float(i)
		var local: Vector2 = Vector2(cos(angle), sin(angle)) * ring_radius
		_weapons[i].position = center_offset + local

func _apply_ellipse_layout(n: int) -> void:
	var step: float = TAU / float(n)
	var base: float = _angle_offset
	for i in n:
		var angle: float = base + step * float(i)
		var local: Vector2 = Vector2(cos(angle) * ellipse_radius_x, sin(angle) * ellipse_radius_y)
		_weapons[i].position = center_offset + local

func _apply_top_arc_layout(n: int) -> void:
	if n == 1:
		var ang_single: float = arc_center_angle
		var pos_single: Vector2 = Vector2(cos(ang_single), sin(ang_single)) * arc_radius
		_weapons[0].position = center_offset + pos_single
		return

	var start: float = arc_center_angle - arc_span * 0.5
	var step: float = 0.0
	if n > 1:
		step = arc_span / float(n - 1)

	for i in n:
		var angle: float = start + step * float(i)
		var local: Vector2 = Vector2(cos(angle), sin(angle)) * arc_radius
		_weapons[i].position = center_offset + local

# -----------------------------------------------------------------------------
# Spawning
# -----------------------------------------------------------------------------
func _spawn_weapons(scene: PackedScene, count: int) -> void:
	if scene == null or count <= 0:
		return
	for i in count:
		var w: Node2D = scene.instantiate() as Node2D
		add_child(w)
		if z_index_boost != 0:
			w.z_index += z_index_boost
		_weapons.append(w)
