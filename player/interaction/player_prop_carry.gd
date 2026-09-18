class_name PlayerPropCarry
extends RefCounted


const RELEASE_POSE_SCAN_STEPS: int = 16
const RELEASE_POSE_REFINE_STEPS: int = 8


var player: CharacterBody3D
var camera: Camera3D
var held_prop: Node = null
var hud_container: Control
var hud_mesh: MeshInstance3D
var hud_material: StandardMaterial3D

var release_distance: float = 1.15
var release_surface_padding: float = 0.006
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
	if prop is CollisionObject3D and player.has_method("invalidate_world_collider_dependency"):
		player.call("invalidate_world_collider_dependency", (prop as CollisionObject3D).get_rid())
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
	var release_result: Dictionary = _compute_release_transform()
	var transform_value: Variant = release_result.get("transform")
	if not (transform_value is Transform3D):
		return false
	var prop: Node = held_prop
	var released: bool = bool(prop.call(
		"release_from_carry",
		motion_kind,
		transform_value,
		initial_velocity,
		player
	))
	if released:
		held_prop = null
		_refresh_hud(null)
	return released


func _compute_release_transform() -> Dictionary:
	var view_basis: Basis = camera.global_transform.basis.orthonormalized()
	var forward: Vector3 = -view_basis.z.normalized()
	var release_basis: Basis = _upright_release_basis(view_basis)
	var origin: Vector3 = camera.global_position
	var maximum_distance: float = maxf(release_distance, 0.0)
	var candidate := Transform3D(release_basis, origin + forward * maximum_distance)
	if _is_release_pose_world_clear(candidate):
		return {"transform": candidate}
	var blocked_distance: float = maximum_distance
	var clear_distance: float = -1.0
	for scan_step: int in range(1, RELEASE_POSE_SCAN_STEPS + 1):
		var distance: float = maximum_distance * (1.0 - float(scan_step) / float(RELEASE_POSE_SCAN_STEPS))
		candidate.origin = origin + forward * distance
		if _is_release_pose_world_clear(candidate):
			clear_distance = distance
			break
		blocked_distance = distance
	if clear_distance < 0.0:
		return {}
	var safe_distance: float = clear_distance
	var unsafe_distance: float = blocked_distance
	for _refine_step: int in range(RELEASE_POSE_REFINE_STEPS):
		var distance: float = (safe_distance + unsafe_distance) * 0.5
		candidate.origin = origin + forward * distance
		if _is_release_pose_world_clear(candidate):
			safe_distance = distance
		else:
			unsafe_distance = distance
	var padded_distance: float = maxf(0.0, safe_distance - maxf(release_surface_padding, 0.0))
	candidate.origin = origin + forward * padded_distance
	if not _is_release_pose_world_clear(candidate):
		candidate.origin = origin + forward * safe_distance
	return {"transform": candidate}


func _upright_release_basis(view_basis: Basis) -> Basis:
	var horizontal_forward: Vector3 = -view_basis.z
	horizontal_forward.y = 0.0
	if horizontal_forward.length_squared() <= 0.000001 and player != null:
		horizontal_forward = -player.global_transform.basis.z
		horizontal_forward.y = 0.0
	if horizontal_forward.length_squared() <= 0.000001:
		return Basis.IDENTITY
	horizontal_forward = horizontal_forward.normalized()
	var yaw: float = atan2(-horizontal_forward.x, -horizontal_forward.z)
	return Basis(Vector3.UP, yaw).orthonormalized()


func _is_release_pose_world_clear(candidate: Transform3D) -> bool:
	if held_prop == null or not is_instance_valid(held_prop):
		return false
	if not held_prop.has_method("is_release_transform_world_clear"):
		return false
	return bool(held_prop.call("is_release_transform_world_clear", candidate, player))


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
