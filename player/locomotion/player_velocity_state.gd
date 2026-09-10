class_name PlayerVelocityState
extends RefCounted


var controlled_velocity: Vector3 = Vector3.ZERO
var support_velocity: Vector3 = Vector3.ZERO
var external_velocity: Vector3 = Vector3.ZERO


func get_velocity() -> Vector3:
	return controlled_velocity + support_velocity + external_velocity


func apply_to_body(body: CharacterBody3D) -> void:
	body.velocity = get_velocity()


func apply_controlled_to_body(body: CharacterBody3D) -> void:
	body.velocity = controlled_velocity


func capture_controlled_from_body(body: CharacterBody3D) -> void:
	controlled_velocity = body.velocity


func capture_controlled_from_composed_body(body: CharacterBody3D) -> void:
	controlled_velocity = (
		body.velocity
		- support_velocity
		- external_velocity
	)


func capture_body_as_controlled(body: CharacterBody3D) -> void:
	controlled_velocity = body.velocity
	support_velocity = Vector3.ZERO
	external_velocity = Vector3.ZERO


func set_controlled_velocity(value: Vector3) -> void:
	controlled_velocity = value


func set_support_velocity(value: Vector3) -> void:
	support_velocity = value


func set_external_velocity(value: Vector3) -> void:
	external_velocity = value


func add_external_velocity(value: Vector3) -> void:
	external_velocity += value


func clear_dynamic_vertical() -> void:
	controlled_velocity.y = 0.0
	external_velocity.y = 0.0


func clear_all() -> void:
	controlled_velocity = Vector3.ZERO
	support_velocity = Vector3.ZERO
	external_velocity = Vector3.ZERO
