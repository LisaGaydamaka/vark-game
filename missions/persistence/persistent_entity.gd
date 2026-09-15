@tool
class_name VarkPersistentEntity
extends Node


@export var persistent_id: String = ""


func is_vark_persistent_entity() -> bool:
	return true


func get_persistent_id() -> String:
	return persistent_id
