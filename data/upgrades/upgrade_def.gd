@icon("res://icon.svg")
extends Resource
class_name UpgradeDef


@export var key: String                    
@export var display_name: String = ""   
@export var description: String = ""     
@export var type: String = "add"        
@export var stat: String = ""        
@export var per_level: float = 0.0
@export var max_level: int = 5
@export var cost_base: int = 5
@export var order: int = 0   

@export var side_effects: Array[Dictionary] = []
