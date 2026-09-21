class_name VarkPatrolPoint
extends Node3D


@export var patrol_id: String = ""
@export_range(0.0, 30.0, 0.25) var wait_seconds: float = 0.0


func _ready() -> void:
	add_to_group(&"vark_patrol_point")
