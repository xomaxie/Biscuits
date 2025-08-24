extends Node2D

enum State { PREP, WAVE, GAME_OVER }

@export var prep_duration: float = 15.0
@export var wave_duration: float = 25.0

@onready var nexus: Node = $Nexus
@onready var spawner: Node = $EnemySpawner
@onready var enemies_container: Node = $Enemies
@onready var wave_label: Label = $UI/TopBar/WaveLabel
@onready var biscuit_label: Label = $UI/TopBar/BiscuitLabel
@onready var nexus_bar: Range = $UI/NexusBar
@onready var prep_timer: Timer = $PrepTimer
@onready var wave_timer: Timer = $WaveTimer

var state: State = State.PREP
var wave: int = 1
var biscuits: int = 0

func _ready() -> void:
	# Hook up timers
	prep_timer.one_shot = true
	wave_timer.one_shot = true
	prep_timer.timeout.connect(_on_prep_timeout)
	wave_timer.timeout.connect(_on_wave_timeout)

	# Nexus signals → UI + lose condition
	if nexus.has_signal("hp_changed"):
		nexus.hp_changed.connect(_on_nexus_hp_changed)
	if nexus.has_signal("nexus_destroyed"):
		nexus.nexus_destroyed.connect(_on_nexus_destroyed)

	# Init UI with Nexus HP if available
	if "max_hp" in nexus and "hp" in nexus:
		nexus_bar.max_value = nexus.max_hp
		nexus_bar.value = nexus.hp

	# Provide spawner with needed references
	if spawner.has_method("configure"):
		spawner.configure($Nexus, enemies_container)

	_start_prep()
	_refresh_timer_ui() # show initial countdown immediately

func _process(_delta: float) -> void:
	_refresh_timer_ui() # keep label live-updating every frame

func _start_prep() -> void:
	state = State.PREP
	_set_spawning(false)
	prep_timer.start(prep_duration)

func _start_wave() -> void:
	state = State.WAVE
	# Difficulty scaling: faster spawns over time
	var spawn_interval: float = clampf(1.2 - float(wave - 1) * 0.07, 0.35, 1.2)
	if spawner.has_method("set_spawn_interval"):
		spawner.set_spawn_interval(spawn_interval)
	_set_spawning(true)
	wave_timer.start(wave_duration)

func _on_prep_timeout() -> void:
	_start_wave()

func _on_wave_timeout() -> void:
	_set_spawning(false)
	wave += 1
	_start_prep()

func _set_spawning(enabled: bool) -> void:
	if spawner.has_method("set_enabled"):
		spawner.set_enabled(enabled)

func _refresh_timer_ui() -> void:
	match state:
		State.PREP:
			if prep_timer and prep_timer.time_left > 0.0:
				wave_label.text = "Prep… (Wave %d in %ds)" % [wave, int(ceil(prep_timer.time_left))]
			else:
				wave_label.text = "Prep… (Wave %d soon)" % wave
		State.WAVE:
			if wave_timer and wave_timer.time_left > 0.0:
				wave_label.text = "Wave %d — %ds left" % [wave, int(ceil(wave_timer.time_left))]
			else:
				wave_label.text = "Wave %d" % wave
		State.GAME_OVER:
			wave_label.text = "⚠ Nexus Destroyed — Game Over"

# --- Biscuits API ---
func add_biscuits(amount: int) -> void:
	biscuits += max(0, amount)
	biscuit_label.text = "Biscuits: %d" % biscuits

# --- Nexus events ---
func _on_nexus_hp_changed(current: int, maxv: int) -> void:
	if nexus_bar:
		nexus_bar.max_value = maxv
		nexus_bar.value = current

func _on_nexus_destroyed() -> void:
	state = State.GAME_OVER
	_set_spawning(false)
	for c in enemies_container.get_children():
		c.queue_free()
