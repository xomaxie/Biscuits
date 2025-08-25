extends Node

signal biscuits_changed(new_total:int, delta:int)
signal phase_changed(new_phase:int)
signal wave_changed(new_wave:int)
signal run_started()
signal run_ended(victory:bool)

enum Phase { PREP, WAVE, GAME_OVER }

@export var starting_biscuits:int = 0

var biscuits:int = 0
var wave:int = 1
var phase:int = Phase.PREP
var upgrades:Dictionary = {}  # e.g. {"damage":1, "firerate":0}

func _ready() -> void:
	reset_to_defaults()

func reset_to_defaults() -> void:
	biscuits = starting_biscuits
	wave = 1
	phase = Phase.PREP
	upgrades.clear()

func start_run() -> void:
	reset_to_defaults()
	emit_signal("run_started")
	emit_signal("biscuits_changed", biscuits, 0)
	emit_signal("wave_changed", wave)
	emit_signal("phase_changed", phase)

func end_run(victory:bool) -> void:
	phase = Phase.GAME_OVER
	emit_signal("phase_changed", phase)
	emit_signal("run_ended", victory)

func set_phase(new_phase:int) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	emit_signal("phase_changed", phase)

func next_wave() -> void:
	wave += 1
	emit_signal("wave_changed", wave)

func add_biscuits(amount:int) -> void:
	if amount == 0:
		return
	biscuits += amount
	emit_signal("biscuits_changed", biscuits, amount)

func spend_biscuits(amount:int) -> bool:
	if biscuits < amount:
		return false
	biscuits -= amount
	emit_signal("biscuits_changed", biscuits, -amount)
	return true

func set_upgrade(name:String, level:int) -> void:
	upgrades[name] = level

func get_upgrade(name:String, default_level:int=0) -> int:
	return int(upgrades.get(name, default_level))
