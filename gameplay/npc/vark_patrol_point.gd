class_name VarkPatrolPoint
extends Node3D


@export var patrol_id: String = ""


func _ready() -> void:
	add_to_group(&"vark_patrol_point")
