class_name PlayerPropCarry
extends RefCounted


var player: CharacterBody3D
var camera: Camera3D
var held_prop: Node = null

var held_distance: float = 0.85
var held_horizontal_offset: float = 0.28
var held_vertical_offset: float = -0.18

var _held_basis_offset: Basis = Basis.IDENTITY


func _init(owner: CharacterBody3D, view_camera: Camera3D) -> void:
	player = owner
	camera = view_camera


func has_held_prop() -> bool:
	return held_prop != null and is_instance_valid(held_prop)


func get_held_prop() -> Node:
	return held_prop if has_held_prop() else null


func try_pick_up(prop: Node) -> bool:
	if has_held_prop() or prop == null or not (prop is Node3D):
		return false
	if (
		not prop.has_method("begin_held")
		or not prop.has_method("set_held_pose")
		or not prop.has_method("release_from_hold")
	):
		return false
	if not bool(prop.call("begin_held", player)):
		return false

	_adopt(prop)
	return true


func adopt_restored_held_prop(prop: Node) -> bool:
	if has_held_prop() or prop == null or not (prop is Node3D):
		return false
	if (
		not prop.has_method("get_semantic_phase")
		or prop.call("get_semantic_phase") != &"held"
		or not prop.has_method("set_held_pose")
	):
		return false

	_adopt(prop)
	return true


func update_held_pose() -> void:
	if not has_held_prop() or camera == null or not is_instance_valid(camera):
		return

	var camera_basis: Basis = camera.global_transform.basis.orthonormalized()
	var offset: Vector3 = (
		camera_basis.x * held_horizontal_offset
		+ camera_basis.y * held_vertical_offset
		- camera_basis.z * held_distance
	)
	var pose := Transform3D(
		(camera_basis * _held_basis_offset).orthonormalized(),
		camera.global_position + offset
	)
	held_prop.call("set_held_pose", pose)


func drop_held() -> bool:
	if not has_held_prop():
		return false
	var prop: Node = held_prop
	var released: bool = bool(
		prop.call("release_from_hold", &"dropped", Vector3.ZERO)
	)
	if released:
		held_prop = null
	return released


func throw_held() -> bool:
	if not has_held_prop():
		return false
	var prop: Node = held_prop
	var speed: float = maxf(float(prop.get("throw_speed")), 0.0)
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var initial_velocity: Vector3 = forward * speed + player.velocity
	var released: bool = bool(
		prop.call("release_from_hold", &"thrown", initial_velocity)
	)
	if released:
		held_prop = null
	return released


func clear_reference() -> void:
	held_prop = null


func _adopt(prop: Node) -> void:
	held_prop = prop
	var camera_basis: Basis = camera.global_transform.basis.orthonormalized()
	var prop_basis: Basis = (prop as Node3D).global_transform.basis.orthonormalized()
	_held_basis_offset = camera_basis.inverse() * prop_basis
	update_held_pose()
