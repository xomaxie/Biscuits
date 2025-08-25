extends Node2D

# --- Node refs ---
@onready var nexus: Node            = $Nexus
@onready var spawner: Node          = $EnemySpawner
@onready var enemies_container: Node = $Enemies
@onready var wave_label: Label      = $UI/TopBar/WaveLabel
@onready var biscuit_label: Label   = $UI/TopBar/BiscuitLabel
@onready var nexus_bar: Range       = $UI/NexusBar
@onready var prep_timer: Timer      = $PrepTimer
@onready var wave_timer: Timer      = $WaveTimer
@onready var barrel_spawner: Node   = $BarrelSpawner 

# --- Tunables ---
@export var prep_duration: float = 15.0
@export var wave_duration: float = 25.0

func _ready() -> void:
	# Timers
	prep_timer.one_shot = true
	wave_timer.one_shot = true
	prep_timer.timeout.connect(_on_prep_timeout)
	wave_timer.timeout.connect(_on_wave_timeout)

	# Nexus → UI + lose condition
	if nexus.has_signal("hp_changed"):
		nexus.hp_changed.connect(_on_nexus_hp_changed)
	if nexus.has_signal("nexus_destroyed"):
		nexus.nexus_destroyed.connect(_on_nexus_destroyed)

	# Init UI with Nexus HP if available
	if "max_hp" in nexus and "hp" in nexus:
		nexus_bar.max_value = nexus.max_hp
		nexus_bar.value = nexus.hp

	# Spawner wires
	if spawner.has_method("configure"):
		spawner.configure(nexus, enemies_container)

	# Subscribe to global GameState signals
	GameState.biscuits_changed.connect(_on_biscuits_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.run_started.connect(_on_run_started)
	GameState.run_ended.connect(_on_run_ended)

	# Start a new run and enter PREP
	GameState.start_run()
	_enter_prep()
	_refresh_timer_ui() 

func _process(_delta: float) -> void:
	_refresh_timer_ui()

# --- Phase control ---
func _enter_prep() -> void:
	GameState.set_phase(GameState.Phase.PREP)
	_set_spawning(false)
	prep_timer.start(prep_duration)

func _start_wave() -> void:
	GameState.set_phase(GameState.Phase.WAVE)
	# Difficulty scaling: faster spawns over time
	var spawn_interval: float = clampf(1.2 - float(GameState.wave - 1) * 0.07, 0.35, 1.2)
	if spawner.has_method("set_spawn_interval"):
		spawner.set_spawn_interval(spawn_interval)
	_set_spawning(true)
	if barrel_spawner and barrel_spawner.has_method("on_wave_started"):
		barrel_spawner.on_wave_started(GameState.wave)
	wave_timer.start(wave_duration)

func _on_prep_timeout() -> void:
	_start_wave()

func _on_wave_timeout() -> void:
	_set_spawning(false)
	GameState.next_wave()
	_enter_prep()

func _set_spawning(enabled: bool) -> void:
	if spawner.has_method("set_enabled"):
		spawner.set_enabled(enabled)

# --- UI updates ---
func _refresh_timer_ui() -> void:
	match GameState.phase:
		GameState.Phase.PREP:
			if prep_timer and prep_timer.time_left > 0.0:
				wave_label.text = "Prep… (Wave %d in %ds)" % [GameState.wave, int(ceil(prep_timer.time_left))]
			else:
				wave_label.text = "Prep… (Wave %d soon)" % GameState.wave
		GameState.Phase.WAVE:
			if wave_timer and wave_timer.time_left > 0.0:
				wave_label.text = "Wave %d — %ds left" % [GameState.wave, int(ceil(wave_timer.time_left))]
			else:
				wave_label.text = "Wave %d" % GameState.wave
		GameState.Phase.GAME_OVER:
			wave_label.text = "⚠ Nexus Destroyed — Game Over"

func _on_biscuits_changed(total:int, _delta:int) -> void:
	if biscuit_label:
		biscuit_label.text = "Biscuits: %d" % total

func _on_wave_changed(new_wave:int) -> void:
	pass

func _on_phase_changed(_p:int) -> void:
	_refresh_timer_ui()

func _on_run_started() -> void:
	_on_biscuits_changed(GameState.biscuits, 0)
	_on_phase_changed(GameState.phase)

func _on_run_ended(_victory:bool) -> void:
	pass

func add_biscuits(amount:int) -> void:
	GameState.add_biscuits(max(0, amount))

# --- Nexus events ---
func _on_nexus_hp_changed(current:int, maxv:int) -> void:
	if nexus_bar:
		nexus_bar.max_value = maxv
		nexus_bar.value = current

func _on_nexus_destroyed() -> void:
	GameState.end_run(false)
	_set_spawning(false)
	if wave_timer: wave_timer.stop()
	if prep_timer: prep_timer.stop()
	for c in enemies_container.get_children():
		c.queue_free()
