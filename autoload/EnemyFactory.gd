extends Node
class_name EnemyFactory

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var enemy_scene: PackedScene

# -----------------------------------------------------------------------------
# API
# -----------------------------------------------------------------------------
func spawn(key:String, pos:Vector2, target:Node2D) -> CharacterBody2D:
	if enemy_scene == null:
		return null
	var e: CharacterBody2D = enemy_scene.instantiate() as CharacterBody2D
	if e == null:
		return null
	e.set("archetype_key", key)
	e.global_position = pos
	if target != null and e.has_method("set_target"):
		e.set_target(target)
	return e
