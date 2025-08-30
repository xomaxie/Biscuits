extends Node2D
class_name EnemySpawner

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var enemy_scene: PackedScene
@export var spawn_margin: float = 48.0
@export var max_enemies: int = 120

@export var bursts_per_cycle: int = 3
@export var intra_spawn_interval: float = 0.12
@export var cycle_downtime: float = 1.40

@export var inter_burst_min: float = 0.20
@export var downtime_min: float = 0.60

@export var burst_enemies_wave1: int = 4
@export var burst_enemies_wave20: int = 14
@export var inter_burst_wave1: float = 0.70
@export var inter_burst_wave20: float = 0.25

@export var allow_remaining_in_burst: int = 0
@export var burst_force_timeout: float = 7.0

enum ClusterMode { DISK, ALONG_EDGE }
@export var cluster_mode: ClusterMode = ClusterMode.DISK
@export var cluster_radius: float = 64.0
@export var cluster_tangent_span: float = 160.0
@export var cluster_perp_jitter: float = 32.0

@export var pick_from_db: bool = true
@export var default_archetype_key: String = ""
@export var debug_burst_logs: bool = true
@export var debug_weight_logs: bool = false

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
var _enabled: bool = false
var _nexus: Node2D = null
var _container: Node = null
var _gs: Node = null

enum State { IDLE, BURSTING, BETWEEN_BURSTS, DOWNTIME }
var _state: int = State.IDLE
var _timer: float = 0.0

var _enemies_left_in_burst: int = 0
var _bursts_left_in_cycle: int = 0

var _cur_enemies_base: int = 6
var _cur_inter: float = 0.55
var _cur_intra: float = 0.12
var _cur_down: float = 1.40

var _burst_alive_ids: Dictionary = {}
var _between_elapsed: float = 0.0
var _between_min_pause: float = 0.5
var _between_max_wait: float = 7.0

var _burst_anchor_side: int = 0
var _burst_anchor_pos: Vector2 = Vector2.ZERO

var _wave: int = 1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _burst_key: String = ""
var _burst_index: int = 0

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_rng.randomize()
	_gs = get_node_or_null("/root/GameState")
	if _gs:
		_gs.phase_changed.connect(_on_phase_changed)
		_gs.wave_changed.connect(_on_wave_changed)
		_on_wave_changed(int(_gs.wave))
		_on_phase_changed(int(_gs.phase))

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
func configure(nexus: Node2D, container: Node) -> void:
	_nexus = nexus
	_container = container

func set_enabled(flag: bool) -> void:
	_enabled = flag
	if _enabled:
		_start_new_cycle()
	else:
		_state = State.IDLE
		_timer = 0.0
		_burst_alive_ids.clear()

# -----------------------------------------------------------------------------
# Signals from GameState
# -----------------------------------------------------------------------------
func _on_phase_changed(new_phase: int) -> void:
	if _gs == null:
		return
	if new_phase == _gs.Phase.WAVE:
		set_enabled(true)
	else:
		set_enabled(false)

func _on_wave_changed(new_wave: int) -> void:
	_wave = clamp(new_wave, 1, 20)
	var t: float = float(_wave - 1) / 19.0
	_cur_enemies_base = max(
		1,
		int(round(lerp(
			float(burst_enemies_wave1),
			float(burst_enemies_wave20),
			t)))
	)
	_cur_inter = max(
		inter_burst_min,
		lerp(inter_burst_wave1, inter_burst_wave20, t)
	)
	_cur_intra = intra_spawn_interval
	_cur_down = max(downtime_min, cycle_downtime)
	_between_min_pause = _cur_inter
	_between_max_wait = burst_force_timeout

# -----------------------------------------------------------------------------
# Physics
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not _enabled:
		return
	if enemy_scene == null or _nexus == null or _container == null:
		return
	_timer -= delta
	match _state:
		State.BURSTING:
			if _timer <= 0.0:
				if _enemies_left_in_burst > 0 \
				and _enemy_count_in_container() < max_enemies:
					_spawn_one()
					_enemies_left_in_burst -= 1
					_timer = _cur_intra
				else:
					_begin_between_bursts()
		State.BETWEEN_BURSTS:
			_between_elapsed += delta
			var alive_now: int = _burst_alive_ids.size()
			var min_ok: bool = _between_elapsed >= _between_min_pause
			var cleared_ok: bool = alive_now <= allow_remaining_in_burst
			var timeout_ok: bool = _between_elapsed >= _between_max_wait
			if min_ok and (cleared_ok or timeout_ok):
				_bursts_left_in_cycle -= 1
				if _bursts_left_in_cycle > 0:
					_start_new_burst()
				else:
					_state = State.DOWNTIME
					_timer = _cur_down
		State.DOWNTIME:
			if _timer <= 0.0:
				_start_new_cycle()
		State.IDLE:
			pass

# -----------------------------------------------------------------------------
# Spawning
# -----------------------------------------------------------------------------
func _start_new_cycle() -> void:
	_bursts_left_in_cycle = max(1, bursts_per_cycle)
	_start_new_burst()

func _start_new_burst() -> void:
	var fuzz: int = randi_range(0, 5)
	_enemies_left_in_burst = _cur_enemies_base + fuzz
	_burst_alive_ids.clear()
	_choose_burst_anchor()
	_burst_key = _pick_archetype_key(_wave)
	if _burst_key == "" and default_archetype_key != "":
		_burst_key = default_archetype_key
	_burst_index += 1

	if debug_burst_logs:
		var disp: String = _get_archetype_display_name(_burst_key)
		var approx: int = _enemies_left_in_burst
		var stats: Dictionary = _predict_stats_for_key(_burst_key)
		var hp_i: int = int(stats.get("hp", 0))
		var dmg_i: int = int(stats.get("dmg", 0))
		var spd_f: float = float(stats.get("speed", 0.0))
		var ct_f: float = float(stats.get("contact_interval", 0.0))
		var tr_f: float = float(stats.get("tick_rate", 0.0))
		print(
			"[Spawner] Burst ", str(_burst_index),
			" wave=", str(_wave),
			" archetype=",
			(_burst_key if _burst_key != "" else "(default)"),
			" (", disp, ") count≈", str(approx),
			" | hp=", str(hp_i),
			" dmg=", str(dmg_i),
			" spd=", str(roundf(spd_f)),
			" contact=", str(ct_f),
			" tick/s=", str(tr_f)
		)

	_state = State.BURSTING
	_timer = 0.0

func _begin_between_bursts() -> void:
	_state = State.BETWEEN_BURSTS
	_between_elapsed = 0.0

func _choose_burst_anchor() -> void:
	var rect: Rect2 = _get_world_visible_rect()
	_burst_anchor_side = randi() % 4
	match _burst_anchor_side:
		0:
			_burst_anchor_pos = Vector2(
				randf_range(rect.position.x, rect.position.x + rect.size.x),
				rect.position.y - spawn_margin
			)
		1:
			_burst_anchor_pos = Vector2(
				rect.position.x + rect.size.x + spawn_margin,
				randf_range(rect.position.y, rect.position.y + rect.size.y)
			)
		2:
			_burst_anchor_pos = Vector2(
				randf_range(rect.position.x, rect.position.x + rect.size.x),
				rect.position.y + rect.size.y + spawn_margin
			)
		3:
			_burst_anchor_pos = Vector2(
				rect.position.x - spawn_margin,
				randf_range(rect.position.y, rect.position.y + rect.size.y)
			)

func _spawn_one() -> void:
	var pos: Vector2 = _burst_anchor_pos + _burst_offset()
	pos = _ensure_offscreen(pos)
	var e: Node = enemy_scene.instantiate()
	if e == null:
		return
	if _burst_key != "" and _has_property(e, "archetype_key"):
		e.set("archetype_key", _burst_key)
	if _nexus != null:
		var nexus_path: NodePath = _nexus.get_path()
		if _has_property(e, "target_path"):
			e.set("target_path", nexus_path)
	_container.add_child(e)
	if e is Node2D:
		(e as Node2D).global_position = pos
	if _nexus != null and e.has_method("set_target"):
		e.set_target(_nexus)
	var id: int = e.get_instance_id()
	_burst_alive_ids[id] = true
	e.tree_exited.connect(_on_enemy_tree_exited.bind(id))

# -----------------------------------------------------------------------------
# Archetype selection
# -----------------------------------------------------------------------------
func _pick_archetype_key(wave: int) -> String:
	if not pick_from_db:
		return ""
	var db: Node = _db()
	if db == null:
		if debug_burst_logs:
			print("[Spawner] EnemyDB autoload missing; using default")
		return ""
	var keys: Array = db.keys()
	if keys.is_empty():
		if debug_burst_logs:
			print("[Spawner] EnemyDB has no keys; using default")
		return ""

	var weighted: Array = []
	var total_w: float = 0.0
	for k_v in keys:
		var k: String = String(k_v)
		var def: Dictionary = db.get_def(k)
		var unlock_wave: int = int(def.get("unlock_wave", 1))
		var max_wave: int = int(def.get("max_wave", 99999))
		if wave < unlock_wave or wave > max_wave:
			continue
		var base_w: float = float(def.get("spawn_weight", 1.0))
		var per_wave: float = float(def.get("weight_per_wave", 0.0))
		var wv: float = max(0.0, base_w + per_wave * float(wave - unlock_wave))
		if wv <= 0.0:
			continue
		weighted.append([k, wv])
		total_w += wv

	if weighted.is_empty():
		var fallback: String = String(keys[_rng.randi_range(0, keys.size()-1)])
		if debug_burst_logs:
			print("[Spawner] No eligible keys for wave ", str(wave),
				"; fallback=", fallback)
		return fallback

	if debug_weight_logs:
		var parts: Array[String] = []
		for row in weighted:
			parts.append(String(row[0]) + ":" + str(row[1]))
		print("[Spawner] Weights wave=", str(wave), " -> ", ", ".join(parts))

	var pick: float = _rng.randf() * total_w
	var run: float = 0.0
	for row in weighted:
		var key: String = String(row[0])
		var wv2: float = float(row[1])
		run += wv2
		if pick <= run:
			return key
	return String(weighted.back()[0])

func _get_archetype_display_name(key: String) -> String:
	if key == "":
		return "(default)"
	var db: Node = _db()
	if db == null:
		return key
	var def: Dictionary = db.get_def(key)
	var dn: String = String(def.get("display_name", ""))
	return dn if dn != "" else key

func _db() -> Node:
	return get_node_or_null("/root/EnemyDB")

# -----------------------------------------------------------------------------
# Prediction (per-burst stat preview)
# -----------------------------------------------------------------------------
func _predict_stats_for_key(key: String) -> Dictionary:
	var e: Node = enemy_scene.instantiate()
	var base_speed: float = 0.0
	var base_hp: int = 0
	var base_dmg: int = 0
	var base_contact: float = 0.0
	var base_stop: float = 0.0
	var base_atk: float = 0.0

	if _has_property(e, "speed"):
		base_speed = float(e.get("speed"))
	if _has_property(e, "hp"):
		base_hp = int(e.get("hp"))
	if _has_property(e, "touch_damage"):
		base_dmg = int(e.get("touch_damage"))
	if _has_property(e, "contact_interval"):
		base_contact = float(e.get("contact_interval"))
	if _has_property(e, "stop_distance"):
		base_stop = float(e.get("stop_distance"))
	if _has_property(e, "manual_attack_radius"):
		base_atk = float(e.get("manual_attack_radius"))

	var hp_mult_global: float = 1.0
	if _gs and _gs.has_method("get_enemy_hp_mult"):
		hp_mult_global = max(0.1, float(_gs.get_enemy_hp_mult()))

	var hp_final: int = max(1, int(round(float(base_hp) * hp_mult_global)))
	var speed_final: float = base_speed
	var dmg_final: int = base_dmg
	var contact_final: float = base_contact
	var stop_final: float = base_stop
	var atk_final: float = base_atk

	if key != "":
		var db: Node = _db()
		if db != null:
			var def: Dictionary = db.get_def(key)
			var sm: float = float(def.get("speed_mult", 1.0))
			var hm: float = float(def.get("hp_mult", 1.0))
			var dm: float = float(def.get("touch_damage_mult", 1.0))
			var cim: float = float(def.get("contact_interval_mult", 1.0))
			var stop_add: float = float(def.get("stop_distance_add", 0.0))
			var atk_add: float = float(
				def.get("manual_attack_radius_add", 0.0)
			)

			speed_final = base_speed * sm
			hp_final = max(1, int(round(float(hp_final) * hm)))
			dmg_final = int(round(float(base_dmg) * dm))
			contact_final = max(0.05, base_contact * cim)
			stop_final = max(0.0, base_stop + stop_add)
			atk_final = max(0.0, base_atk + atk_add)

	e.queue_free()
	var tick_rate: float = 0.0
	if contact_final > 0.0:
		tick_rate = 1.0 / contact_final

	return {
		"hp": hp_final,
		"dmg": dmg_final,
		"speed": speed_final,
		"contact_interval": contact_final,
		"tick_rate": tick_rate,
		"stop_distance": stop_final,
		"attack_radius": atk_final
	}

# -----------------------------------------------------------------------------
# Cluster helpers
# -----------------------------------------------------------------------------
func _burst_offset() -> Vector2:
	if cluster_mode == ClusterMode.DISK:
		return _rand_point_in_disk(cluster_radius)
	return _rand_point_along_edge(
		_burst_anchor_side,
		cluster_tangent_span,
		cluster_perp_jitter
	)

func _rand_point_in_disk(r: float) -> Vector2:
	var ang: float = randf() * TAU
	var rad: float = r * sqrt(randf())
	return Vector2(cos(ang), sin(ang)) * rad

func _rand_point_along_edge(
	side: int,
	span: float,
	jitter: float
) -> Vector2:
	var t: float = randf_range(-span * 0.5, span * 0.5)
	var p: float = randf_range(-jitter, jitter)
	match side:
		0: return Vector2(t, -abs(p))
		1: return Vector2(abs(p), t)
		2: return Vector2(t, abs(p))
		3: return Vector2(-abs(p), t)
	return Vector2.ZERO

func _ensure_offscreen(pos: Vector2) -> Vector2:
	var rect: Rect2 = _get_world_visible_rect()
	match _burst_anchor_side:
		0:
			pos.y = min(pos.y, rect.position.y - spawn_margin)
		1:
			pos.x = max(pos.x, rect.position.x + rect.size.x + spawn_margin)
		2:
			pos.y = max(pos.y, rect.position.y + rect.size.y + spawn_margin)
		3:
			pos.x = min(pos.x, rect.position.x - spawn_margin)
	return pos

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
func _on_enemy_tree_exited(id: int) -> void:
	if _burst_alive_ids.has(id):
		_burst_alive_ids.erase(id)

func _enemy_count_in_container() -> int:
	if _container == null:
		return 0
	var n: int = 0
	for c in _container.get_children():
		if c is Node and (c as Node).is_in_group("enemies"):
			n += 1
	return n

# -----------------------------------------------------------------------------
# View rect + offscreen clamp (fixed for Camera2D.zoom)
# -----------------------------------------------------------------------------
func _get_world_visible_rect() -> Rect2:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		var center: Vector2 = cam.get_screen_center_position()
		var vp_size: Vector2 = get_viewport_rect().size
		var world_size: Vector2 = Vector2(
			vp_size.x / max(0.0001, cam.zoom.x),
			vp_size.y / max(0.0001, cam.zoom.y)
		)
		var top_left: Vector2 = center - world_size * 0.5
		return Rect2(top_left, world_size)
	return Rect2(get_viewport().get_visible_rect())


func _has_property(obj: Object, prop: String) -> bool:
	var plist: Array = obj.get_property_list()
	for p_v in plist:
		var p: Dictionary = p_v
		if p.has("name") and String(p["name"]) == prop:
			return true
	return false
