class_name PlayerHostileInteraction
extends RefCounted


const HOSTILE_EFFECT_EVENT: StringName = &"combat.crude_hostile_effect"
const HOSTILE_EFFECT_KNOCKOUT: StringName = &"knockout"


var player: CollisionObject3D
var camera: Camera3D
var max_range: float


func _init(
	attacker: CollisionObject3D,
	view_camera: Camera3D,
	attack_range: float
) -> void:
	player = attacker
	camera = view_camera
	max_range = maxf(attack_range, 0.0)


func update(attack_pressed: bool) -> bool:
	if not attack_pressed:
		return false
	var target: VarkGuard = _select_guard_target()
	if target == null:
		return false
	if target.get_life_state() != VarkGuard.LIFE_CONSCIOUS:
		return false

	var session: Node = _find_world_session()
	if session == null or not is_instance_valid(session):
		return false
	var state: Dictionary = target.query_actor_state()
	var impact_origin: Vector3 = (
		target.global_position
		+ Vector3.UP * 0.9
	)
	return bool(session.call(
		"queue_semantic_gameplay_event",
		int(session.get("session_id")),
		HOSTILE_EFFECT_EVENT,
		{
			"target_persistent_id": target.get_persistent_id(),
			"target_actor_id": state.get("actor_id", ""),
			"effect": HOSTILE_EFFECT_KNOCKOUT,
			"impact_origin": impact_origin,
			"sound_strength": 0.85,
		}
	))


func _select_guard_target() -> VarkGuard:
	if (
		player == null
		or camera == null
		or not is_instance_valid(player)
		or not is_instance_valid(camera)
		or player.get_world_3d() == null
	):
		return null

	var origin: Vector3 = camera.global_position
	var direction: Vector3 = (
		-camera.global_transform.basis.z
	).normalized()
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * max_range
	)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(
		query
	)
	if hit.is_empty():
		return null

	var candidate := hit.get("collider") as Node
	while candidate != null:
		if candidate is VarkGuard:
			return candidate as VarkGuard
		candidate = candidate.get_parent()
	return null


func _find_world_session() -> Node:
	var cursor: Node = player
	while cursor != null:
		if cursor is WorldSession:
			return cursor
		cursor = cursor.get_parent()
	return null
