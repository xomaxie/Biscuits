extends Node

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var title_path: String = "res://Music/Title.ogg"
@export var game_tracks_dir: String = "res://Music/GameTracks/"
@export var track_min_index: int = 1
@export var track_max_index: int = 12
@export var music_bus: String = "Music"
@export var default_fade: float = 5
@export var normal_volume_db: float = 0.0
@export var duck_db: float = -16.0
@export var duck_fade_sec: float = 0.25
@export var unduck_fade_sec: float = 0.25
@export var advance_fade_sec: float = 0.35
@export var avoid_repeat: bool = true

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
var _duck_tween: Tween
var _xfade_tween: Tween
var _advance_enabled: bool = true
var _use_a: bool = true

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
		p.volume_db = normal_volume_db
		p.finished.connect(_on_any_finished)
	_rng.randomize()
	_build_track_list()

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------
func preload_all() -> void:
	_load_title_stream()
	_build_track_list()
	await _warm_up_streams()

func play_title(fade: float = default_fade) -> void:
	if _title_stream == null:
		_load_title_stream()
	if _title_stream:
		_play_stream(_title_stream, fade)

func play_run_start(fade: float = default_fade) -> void:
	var p := _current_player()
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

func set_bus(name: String) -> void:
	music_bus = name
	_player_a.bus = name
	_player_b.bus = name

func set_volume_db(db: float) -> void:
	_player_a.volume_db = db
	_player_b.volume_db = db

func duck_music(dur: float = -1.0) -> void:
	var d: float = dur if dur >= 0.0 else duck_fade_sec
	_stop_duck_tween()
	_duck_tween = create_tween()
	_duck_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_duck_tween.tween_property(_current_player(), "volume_db", duck_db, d)

func unduck_music(dur: float = -1.0) -> void:
	var d: float = dur if dur >= 0.0 else unduck_fade_sec
	_stop_duck_tween()
	_duck_tween = create_tween()
	_duck_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_duck_tween.tween_property(_current_player(), "volume_db",
		normal_volume_db, d)

func set_auto_advance(enabled: bool) -> void:
	_advance_enabled = enabled

func stop_music(fade: float = default_fade) -> void:
	var p := _current_player()
	if fade > 0.0 and p.playing:
		var t: Tween = create_tween()
		t.tween_property(p, "volume_db", -40.0, fade)
		t.tween_callback(Callable(p, "stop"))
		t.tween_callback(func(): p.volume_db = normal_volume_db)
	else:
		p.stop()

# -----------------------------------------------------------------------------
# Core playback
# -----------------------------------------------------------------------------
func _play_slot(slot: int, fade: float) -> void:
	if slot < 0 or slot >= _tracks.size():
		return
	_last_slot = slot
	_play_stream(_tracks[slot], fade)

func _play_stream(s: AudioStream, fade: float) -> void:
	var from := _current_player()
	var to := _next_player()
	if _xfade_tween and _xfade_tween.is_running():
		_xfade_tween.kill()
	to.stream = s
	to.volume_db = from.volume_db
	to.play()
	if fade > 0.0 and from.playing:
		_xfade_tween = create_tween()
		_xfade_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
		_xfade_tween.tween_property(from, "volume_db", -40.0, fade)
		_xfade_tween.parallel().tween_property(
			to, "volume_db", normal_volume_db, fade)
		_xfade_tween.tween_callback(Callable(from, "stop"))
		_xfade_tween.tween_callback(
			func(): from.volume_db = normal_volume_db)
	else:
		from.stop()
		to.volume_db = normal_volume_db
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
			var ogg := _title_stream as AudioStreamOggVorbis
			ogg.loop = false

func _build_track_list() -> void:
	_tracks.clear()
	for i in range(track_min_index, track_max_index + 1):
		var path := "%sTrack%02d.ogg" % [game_tracks_dir, i]
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
		var p := AudioStreamPlayer.new()
		add_child(p)
		p.bus = music_bus
		p.volume_db = -80.0
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
		slot = (slot + 1 + _rng.randi_range(0, _tracks.size() - 2)) \
			% _tracks.size()
	return slot

func _current_player() -> AudioStreamPlayer:
	return _player_a if _use_a else _player_b

func _next_player() -> AudioStreamPlayer:
	return _player_b if _use_a else _player_a

func _stop_duck_tween() -> void:
	if _duck_tween and _duck_tween.is_running():
		_duck_tween.kill()
