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
@export var layout: Layout = Layout.RING
@export var center_offset: Vector2 = Vector2(0, -16)

@export var ring_radius: float = 80.0
@export var ellipse_radius_x: float = 96.0
@export var ellipse_radius_y: float = 56.0
@export var arc_radius: float = 32.0
@export var arc_center_angle: float = -PI * 0.5
@export var arc_span: float = PI

@export var animate_orbit: bool = true
@export var orbit_speed: float = 1.2
@export var face_outward: bool = true
@export var rotation_offset_deg: float = 0.0
@export var y_depth_sort: bool = true

@export var z_index_boost: int = 0
@export var debug_attack_speed: bool = false

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
var _weapons: Array[Node2D] = []
var _angle_offset: float = 0.0
var _attack_speed_bonus_pct: float = 0.0
var _attack_speed_mult: float = 1.0
var _proj_speed_from_atk_mult: float = 1.0

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_spawn_weapons(starting_ranged_weapon, starting_ranged_count)
	_spawn_weapons(starting_melee_weapon, starting_melee_count)
	_sync_all_attack_speed()
	_layout_now()

func _physics_process(delta: float) -> void:
	var n: int = _layout_weapons().size()
	if n == 0:
		return
	if animate_orbit and (layout == Layout.RING or layout == Layout.ELLIPSE):
		_angle_offset += orbit_speed * delta
	_layout_now()

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------
func register_weapon(w: Node2D) -> void:
	if w == null:
		return
	add_child(w)

	# Hide and exclude from orbit if the weapon says it's orbitless
	if not _is_layout_participant(w):
		if w is CanvasItem:
			(w as CanvasItem).visible = false
	else:
		# Only apply orbit z-index tweak to visible, orbit-participating weapons
		if z_index_boost != 0:
			w.z_index += z_index_boost

	_weapons.append(w)
	_apply_attack_speed_to_weapon(w)
	_layout_now()

# -----------------------------------------------------------------------------
# Attack-speed propagation
# -----------------------------------------------------------------------------
func set_attack_speed_bonus_pct(v: float) -> void:
	_attack_speed_bonus_pct = v
	_attack_speed_mult = 1.0 + float(clamp(v, -95.0, 500.0)) / 100.0
	var pos_atk: float = 0.0
	if v > 0.0:
		pos_atk = v
	_proj_speed_from_atk_mult = 1.0 + (pos_atk * 0.5) / 100.0
	if debug_attack_speed:
		print("[WM] atk%=", _attack_speed_bonus_pct, " fire_mult=",
			_attack_speed_mult, " proj_speed_mult=",
			_proj_speed_from_atk_mult)
	_sync_all_attack_speed()

func get_attack_speed_bonus_pct() -> float:
	return _attack_speed_bonus_pct

func get_attack_speed_multiplier() -> float:
	return _attack_speed_mult

func get_projectile_speed_from_attack_mult() -> float:
	return _proj_speed_from_atk_mult

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------
func _sync_all_attack_speed() -> void:
	for w in _weapons:
		_apply_attack_speed_to_weapon(w)

func _apply_attack_speed_to_weapon(w: Node2D) -> void:
	if w == null:
		return
	if w.has_method("set_attack_speed_bonus_pct"):
		w.call("set_attack_speed_bonus_pct", _attack_speed_bonus_pct)
	if w.has_method("set_projectile_speed_from_attack_mult"):
		w.call("set_projectile_speed_from_attack_mult",
			_proj_speed_from_atk_mult)

# Orbit participation checks (turrets/backpacks can opt-out)
func _is_layout_participant(w: Node) -> bool:
	if w == null:
		return false
	if w.has_method("is_orbitless"):
		var res: Variant = w.call("is_orbitless")
		if typeof(res) == TYPE_BOOL and bool(res):
			return false
	if w.is_in_group("orbitless"):
		return false
	if w.has_meta("orbitless") and bool(w.get_meta("orbitless")):
		return false
	return true

# Whether to rotate weapon with orbit (aiming weapons can opt-out to keep snap-aim)
func _should_rotate_with_orbit(w: Node) -> bool:
	# 1) Explicit API on the weapon wins
	if w.has_method("should_orbit_rotate"):
		var res: Variant = w.call("should_orbit_rotate")
		if typeof(res) == TYPE_BOOL:
			return bool(res)
	# 2) Metadata or groups can opt-in/out
	if w.has_meta("orbit_rotate"):
		return bool(w.get_meta("orbit_rotate"))
	if w.is_in_group("orbit_rotate_on"):
		return true
	if w.is_in_group("orbit_rotate_off"):
		return false
	# 3) Heuristic: if the weapon does its own snap aim, don't override its rotation
	if w.has_method("_snap_aim"):
		return false
	# Default: rotate with orbit
	return true

func _apply_rotation_and_depth(w: Node2D, local: Vector2, angle: float) -> void:
	# Always depth-sort
	if y_depth_sort:
		w.z_index = z_index_boost + int(center_offset.y + local.y)

	# Expose orbit geometry to weapons (optional read-only hints)
	w.set_meta("orbit_angle", angle)
	w.set_meta("orbit_local", local)

	# Only rotate if weapon opts in
	if _should_rotate_with_orbit(w):
		var rot: float = angle
		if not face_outward:
			rot += PI
		rot += deg_to_rad(rotation_offset_deg)
		w.rotation = rot

func _layout_weapons() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for w in _weapons:
		if _is_layout_participant(w):
			out.append(w)
	return out

# -----------------------------------------------------------------------------
# Layouts
# -----------------------------------------------------------------------------
func _layout_now() -> void:
	var list: Array[Node2D] = _layout_weapons()
	var n: int = list.size()
	if n == 0:
		return
	match layout:
		Layout.RING:
			_apply_ring_layout(list)
		Layout.ELLIPSE:
			_apply_ellipse_layout(list)
		Layout.TOP_ARC:
			_apply_top_arc_layout(list)

func _apply_ring_layout(list: Array[Node2D]) -> void:
	var n: int = list.size()
	var step: float = TAU / float(n)
	var base: float = _angle_offset
	for i in n:
		var angle: float = base + step * float(i)
		var local: Vector2 = Vector2(cos(angle), sin(angle)) * ring_radius
		list[i].position = center_offset + local
		_apply_rotation_and_depth(list[i], local, angle)

func _apply_ellipse_layout(list: Array[Node2D]) -> void:
	var n: int = list.size()
	var step: float = TAU / float(n)
	var base: float = _angle_offset
	for i in n:
		var angle: float = base + step * float(i)
		var local: Vector2 = Vector2(
			cos(angle) * ellipse_radius_x,
			sin(angle) * ellipse_radius_y
		)
		list[i].position = center_offset + local
		_apply_rotation_and_depth(list[i], local, angle)

func _apply_top_arc_layout(list: Array[Node2D]) -> void:
	var n: int = list.size()
	if n == 1:
		var ang_single: float = arc_center_angle
		var pos_single: Vector2 = Vector2(
			cos(ang_single), sin(ang_single)
		) * arc_radius
		list[0].position = center_offset + pos_single
		_apply_rotation_and_depth(list[0], pos_single, ang_single)
		return
	var start: float = arc_center_angle - arc_span * 0.5
	var step: float = 0.0
	if n > 1:
		step = arc_span / float(n - 1)
	for i in n:
		var angle: float = start + step * float(i)
		var local: Vector2 = Vector2(cos(angle), sin(angle)) * arc_radius
		list[i].position = center_offset + local
		_apply_rotation_and_depth(list[i], local, angle)

# -----------------------------------------------------------------------------
# Spawning
# -----------------------------------------------------------------------------
func _spawn_weapons(scene: PackedScene, count: int) -> void:
	if scene == null or count <= 0:
		return
	for i in count:
		var w: Node2D = scene.instantiate() as Node2D
		register_weapon(w)
