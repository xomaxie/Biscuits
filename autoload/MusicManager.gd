extends Node

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var title_path: String = "res://Music/Title.ogg"
@export var game_tracks_dir: String = "res://Music/GameTracks/"
@export var track_min_index: int = 1
@export var track_max_index: int = 12
@export var music_bus: String = "Music"
@export var default_fade: float = 5.0
@export var duck_db: float = -16.0
@export var duck_fade_sec: float = 0.25
@export var unduck_fade_sec: float = 0.25
@export var advance_fade_sec: float = 0.35
@export var avoid_repeat: bool = true
@export var persist_min_db: float = -40.0
@export var persist_max_db: float = 0.0

# -----------------------------------------------------------------------------
# Node refs
# -----------------------------------------------------------------------------
@onready var _player_a: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var _player_b: AudioStreamPlayer = AudioStreamPlayer.new()

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
var _title_stream: AudioStream
var _tracks: Array[AudioStream] = []
var _last_slot: int = -1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _xfade_tween: Tween
var _vol_tween: Tween
var _advance_enabled: bool = true
var _use_a: bool = true
var _user_db: float = 0.0
var _duck_active: bool = false

# -----------------------------------------------------------------------------
# Persistence
# -----------------------------------------------------------------------------
const CONFIG_PATH: String = "user://settings.cfg"

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player_a)
	add_child(_player_b)
	for p in [_player_a, _player_b]:
		p.bus = music_bus
		p.autoplay = false
		p.volume_db = _effective_db()
		p.finished.connect(_on_any_finished)
	_rng.randomize()
	_build_track_list()
	load_saved_volume()

# -----------------------------------------------------------------------------
# Public API: playback
# -----------------------------------------------------------------------------
func preload_all() -> void:
	_load_title_stream()
	_build_track_list()
	await _warm_up_streams()

func is_playing_title() -> bool:
	var p := _current_player()
	return p.playing and _title_stream != null and p.stream == _title_stream

func play_title(fade: float = default_fade) -> void:
	if _title_stream == null:
		_load_title_stream()
	if _title_stream == null:
		return
	if is_playing_title():
		return
	_play_stream(_title_stream, fade)

func play_run_start(fade: float = default_fade) -> void:
	var p: AudioStreamPlayer = _current_player()
	if p.playing and p.stream in _tracks:
		return
	play_random_game_track(fade)

func play_random_game_track(fade: float = default_fade) -> void:
	if _tracks.is_empty():
		return
	var slot: int = _pick_slot()
	_play_slot(slot, fade)

func next_game_track(fade: float = default_fade) -> void:
	if _tracks.is_empty():
		return
	var slot: int = (_last_slot + 1) % _tracks.size()
	_play_slot(slot, fade)

func stop_music(fade: float = default_fade) -> void:
	var p: AudioStreamPlayer = _current_player()
	if fade > 0.0 and p.playing:
		var t: Tween = create_tween()
		t.tween_property(p, "volume_db", persist_min_db, fade)
		t.tween_callback(Callable(p, "stop"))
		t.tween_callback(func(): p.volume_db = _effective_db())
	else:
		p.stop()

# -----------------------------------------------------------------------------
# Public API: volume and ducking
# -----------------------------------------------------------------------------
func set_bus(name: String) -> void:
	music_bus = name
	_player_a.bus = name
	_player_b.bus = name

func set_volume_db(db: float, tween_sec: float = 0.15) -> void:
	_user_db = clamp(db, persist_min_db, persist_max_db)
	_apply_volume(_effective_db(), tween_sec)

func set_volume_unit(unit_0_1: float, tween_sec: float = 0.15) -> void:
	var u: float = clamp(unit_0_1, 0.0, 1.0)
	var db: float = lerp(persist_min_db, persist_max_db, u)
	set_volume_db(db, tween_sec)

func get_volume_unit() -> float:
	return inverse_lerp(
		persist_min_db, persist_max_db,
		clamp(_user_db, persist_min_db, persist_max_db)
	)

func duck_music(dur: float = -1.0) -> void:
	_duck_active = true
	var d: float = dur if dur >= 0.0 else duck_fade_sec
	_apply_volume(_effective_db(), d)

func unduck_music(dur: float = -1.0) -> void:
	_duck_active = false
	var d: float = dur if dur >= 0.0 else unduck_fade_sec
	_apply_volume(_effective_db(), d)

func set_auto_advance(enabled: bool) -> void:
	_advance_enabled = enabled

# -----------------------------------------------------------------------------
# Persistence API
# -----------------------------------------------------------------------------
func load_saved_volume() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK and \
		cfg.has_section_key("audio", "music_unit"):
		var u: float = float(cfg.get_value("audio", "music_unit"))
		set_volume_unit(u, 0.0)
	else:
		set_volume_db(_user_db, 0.0)

func save_volume(unit_0_1: float) -> void:
	var u: float = clamp(unit_0_1, 0.0, 1.0)
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("audio", "music_unit", u)
	cfg.set_value("audio", "music_db",
		lerp(persist_min_db, persist_max_db, u))
	cfg.save(CONFIG_PATH)

# -----------------------------------------------------------------------------
# Core playback
# -----------------------------------------------------------------------------
func _play_slot(slot: int, fade: float) -> void:
	if slot < 0 or slot >= _tracks.size():
		return
	_last_slot = slot
	_play_stream(_tracks[slot], fade)

func _play_stream(s: AudioStream, fade: float) -> void:
	var from: AudioStreamPlayer = _current_player()
	var to: AudioStreamPlayer = _next_player()
	if _xfade_tween and _xfade_tween.is_running():
		_xfade_tween.kill()
	to.stream = s
	to.volume_db = _effective_db()
	to.play()
	if fade > 0.0 and from.playing:
		_xfade_tween = create_tween()
		_xfade_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
		_xfade_tween.tween_property(from, "volume_db",
			persist_min_db, fade)
		_xfade_tween.parallel().tween_property(to, "volume_db",
			_effective_db(), fade)
		_xfade_tween.tween_callback(Callable(from, "stop"))
		_xfade_tween.tween_callback(
			func(): from.volume_db = _effective_db()
		)
	else:
		from.stop()
		to.volume_db = _effective_db()
	_use_a = not _use_a

# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------
func _load_title_stream() -> void:
	if _title_stream:
		return
	if ResourceLoader.exists(title_path):
		_title_stream = load(title_path)
		if _title_stream is AudioStreamOggVorbis:
			var ogg: AudioStreamOggVorbis = _title_stream
			ogg.loop = false

func _build_track_list() -> void:
	_tracks.clear()
	for i in range(track_min_index, track_max_index + 1):
		var path: String = "%sTrack%02d.ogg" % [game_tracks_dir, i]
		if ResourceLoader.exists(path):
			var st: AudioStream = load(path)
			if st:
				if st is AudioStreamOggVorbis:
					(st as AudioStreamOggVorbis).loop = false
				_tracks.append(st)
	if _tracks.is_empty():
		push_warning("No playable tracks were loaded.")

func _warm_up_streams() -> void:
	var all: Array[AudioStream] = []
	if _title_stream:
		all.append(_title_stream)
	for s in _tracks:
		all.append(s)
	for s in all:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(p)
		p.bus = music_bus
		p.volume_db = persist_min_db
		p.stream = s
		p.play()
		await get_tree().process_frame
		p.stop()
		p.queue_free()

func _on_any_finished() -> void:
	if not _advance_enabled:
		return
	next_game_track(advance_fade_sec)

func _pick_slot() -> int:
	if _tracks.size() == 1:
		return 0
	var slot: int = _rng.randi_range(0, _tracks.size() - 1)
	if avoid_repeat and slot == _last_slot:
		slot = (slot + 1 + _rng.randi_range(
			0, _tracks.size() - 2)) % _tracks.size()
	return slot

func _current_player() -> AudioStreamPlayer:
	return _player_a if _use_a else _player_b

func _next_player() -> AudioStreamPlayer:
	return _player_b if _use_a else _player_a

func _effective_db() -> float:
	return duck_db if _duck_active else _user_db

func _apply_volume(db: float, tween_sec: float) -> void:
	if _vol_tween and _vol_tween.is_running():
		_vol_tween.kill()
	if tween_sec <= 0.0:
		_player_a.volume_db = db
		_player_b.volume_db = db
		return
	_vol_tween = create_tween()
	_vol_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_vol_tween.tween_property(_player_a, "volume_db", db, tween_sec)
	_vol_tween.parallel().tween_property(_player_b, "volume_db",
		db, tween_sec)
