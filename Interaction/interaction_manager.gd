extends Node2D

@onready var player = get_tree().get_first_node_in_group("player")
@onready var label = $Label

const base_text := "[E] to "

var active_areas: Array = []
var can_interact := true


func register_area(area: InteractionArea) -> void:
	active_areas.push_back(area)

func unregister_area(area: InteractionArea) -> void:
	var index := active_areas.find(area)
	if index != -1:
		active_areas.remove_at(index)

func _process(delta: float) -> void:
	# prune any null/out-of-tree entries (caused by frees/scene changes)
	for i in range(active_areas.size() - 1, -1, -1):
		var a = active_areas[i]
		if not is_instance_valid(a) or not a.is_inside_tree():
			active_areas.remove_at(i)

	if active_areas.size() > 0 and can_interact:
		# sort by distance, but be safe if something became invalid mid-frame
		active_areas.sort_custom(Callable(self, "_sort_by_distance_to_player"))

		var top = active_areas[0]
		if not is_instance_valid(top):
			label.hide()
			return

		label.text = base_text + top.action_name
		label.global_position = top.global_position
		label.global_position.y -= 36
		label.global_position.x -= label.size.x / 2
		label.show()
	else:
		label.hide()

func _sort_by_distance_to_player(area1, area2) -> bool:
	# handle any surprise invalids during sort
	if not is_instance_valid(player):
		return false
	if not is_instance_valid(area1):
		return false
	if not is_instance_valid(area2):
		return true
	var d1 = player.global_position.distance_to(area1.global_position)
	var d2 = player.global_position.distance_to(area2.global_position)
	return d1 < d2

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and can_interact:
		if active_areas.size() > 0:
			can_interact = false
			label.hide()

			# call as before—your interact can await internally if needed
			await active_areas[0].interact.call()

			can_interact = true
