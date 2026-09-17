class_name PlayerPropCarry
extends RefCounted


var player: CharacterBody3D
var camera: Camera3D
var held_prop: Node = null
var hud_container: Control
var hud_mesh: MeshInstance3D
var hud_material: StandardMaterial3D

var release_distance: float = 1.15
var release_clearance: float = 0.34
var release_speed: float = 0.55


func _init(
	owner: CharacterBody3D,
	view_camera: Camera3D,
	carried_hud_container: Control,
	carried_hud_mesh: MeshInstance3D,
	carried_hud_material: StandardMaterial3D
) -> void:
	player = owner
	camera = view_camera
	hud_container = carried_hud_container
	hud_mesh = carried_hud_mesh
	hud_material = carried_hud_material
	_refresh_hud(null)


func has_held_prop() -> bool:
	return held_prop != null and is_instance_valid(held_prop)


func get_held_prop() -> Node:
	return held_prop if has_held_prop() else null


func try_pick_up(prop: Node) -> bool:
	if has_held_prop() or prop == null or not (prop is Node3D):
		return false
	if not prop.has_method("begin_carried_junk") or not prop.has_method("release_from_carry"):
		return false
	if not bool(prop.call("begin_carried_junk", player)):
		return false
	held_prop = prop
	_refresh_hud(prop)
	return true


func adopt_restored_held_prop(prop: Node) -> bool:
	if has_held_prop() or prop == null or not (prop is Node3D):
		return false
	if not prop.has_method("get_semantic_phase") or prop.call("get_semantic_phase") != &"carried_junk":
		return false
	held_prop = prop
	_refresh_hud(prop)
	return true


func release_held_gently() -> bool:
	if not has_held_prop():
		return false
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var initial_velocity: Vector3 = forward * release_speed + player.velocity * 0.15
	return _release(&"released", initial_velocity)


func throw_held() -> bool:
	if not has_held_prop():
		return false
	var speed: float = maxf(float(held_prop.get("throw_speed")), 0.0)
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var initial_velocity: Vector3 = forward * speed + player.velocity
	return _release(&"thrown", initial_velocity)


func clear_reference() -> void:
	held_prop = null
	_refresh_hud(null)


func _release(motion_kind: StringName, initial_velocity: Vector3) -> bool:
	var prop: Node = held_prop
	var released: bool = bool(prop.call(
		"release_from_carry",
		motion_kind,
		_compute_release_transform(),
		initial_velocity
	))
	if released:
		held_prop = null
		_refresh_hud(null)
	return released


func _compute_release_transform() -> Transform3D:
	var view_basis: Basis = camera.global_transform.basis.orthonormalized()
	var forward: Vector3 = -view_basis.z.normalized()
	var origin: Vector3 = camera.global_position
	var desired: Vector3 = origin + forward * release_distance
	var query := PhysicsRayQueryParameters3D.create(origin, desired)
	query.exclude = [player.get_rid()]
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		desired = hit.get("position", desired) - forward * release_clearance
	var release_basis: Basis = (
		view_basis * Basis(Vector3.BACK, PI * 0.5)
	).orthonormalized()
	return Transform3D(release_basis, desired)


func _refresh_hud(prop: Node) -> void:
	if hud_container == null or hud_mesh == null:
		return
	var active: bool = prop != null and is_instance_valid(prop)
	hud_container.visible = active
	if not active:
		hud_mesh.mesh = null
		return
	if prop.has_method("get_visual_model"):
		hud_mesh.mesh = prop.call("get_visual_model") as Mesh
	if hud_material != null:
		hud_material.albedo_color = prop.get("base_color") as Color
