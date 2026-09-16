@tool
class_name VarkPersistentEntity
extends Node


@export var persistent_id: String = ""
@export var content_id: String = ""


func is_vark_persistent_entity() -> bool:
	return true


func get_persistent_id() -> String:
	return persistent_id


func get_content_id() -> String:
	return content_id
