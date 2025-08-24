extends Area2D
class_name InteractionArea

@export var action_name: String = "interact"

var interact: Callable = func():
	pass

func _on_body_entered(body: Node2D) -> void:
	#print("DEBUG: body_entered ->", body.name, " entered area:", self.name, " action:", action_name)
	InteractionManager.register_area(self)

func _on_body_exited(body: Node2D) -> void:
	#print("DEBUG: body_exited ->", body.name, " exited area:", self.name, " action:", action_name)
	InteractionManager.unregister_area(self)
