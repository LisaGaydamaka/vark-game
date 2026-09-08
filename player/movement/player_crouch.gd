class_name PlayerCrouch
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const HEIGHT_EPSILON: float = 0.0001


var collision_shape: CollisionShape3D
var head: Node3D
var visual_mesh: MeshInstance3D
var ledge_detector: PlayerLedgeDetector

var capsule_shape: CapsuleShape3D
var capsule_mesh: CapsuleMesh = null
var standing_height: float
var crouch_height: float
var capsule_bottom_offset: float
var standing_head_height: float
var head_top_clearance: float
var visual_bottom_offset: float = 0.0
var standing_requested: bool = true


func _init(
	p_collision_shape: CollisionShape3D,
	p_head: Node3D,
	p_visual_mesh: MeshInstance3D,
	p_crouch_height: float,
	p_ledge_detector: PlayerLedgeDetector
) -> void:
	collision_shape = p_collision_shape
	head = p_head
	visual_mesh = p_visual_mesh
	ledge_detector = p_ledge_detector

	assert(collision_shape != null, "PlayerCrouch requires a CollisionShape3D.")
	assert(head != null, "PlayerCrouch requires a head Node3D.")
	assert(ledge_detector != null, "PlayerCrouch requires a ledge detector.")

	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerCrouch requires the player collision shape to be CapsuleShape3D."
	)
	capsule_shape = shape as CapsuleShape3D
	standing_height = capsule_shape.height
	var minimum_height: float = capsule_shape.radius * 2.0
	crouch_height = clampf(p_crouch_height, minimum_height, standing_height)
	capsule_bottom_offset = collision_shape.position.y - standing_height * 0.5

	standing_head_height = head.position.y
	var standing_top: float = capsule_bottom_offset + standing_height
	head_top_clearance = standing_top - standing_head_height

	if visual_mesh != null and visual_mesh.mesh is CapsuleMesh:
		capsule_mesh = visual_mesh.mesh as CapsuleMesh
		visual_bottom_offset = visual_mesh.position.y - capsule_mesh.height * 0.5


func toggle() -> void:
	standing_requested = not standing_requested


func update(player: CharacterBody3D) -> bool:
	if not standing_requested:
		return _apply_height(crouch_height)

	var current_height: float = capsule_shape.height
	var missing_height: float = standing_height - current_height
	if missing_height <= HEIGHT_EPSILON:
		return _apply_height(standing_height)

	# Sweeping the current bottom-anchored capsule upward covers the same volume
	# that increasing its height would occupy. Collision travel therefore tells
	# us exactly how much of the requested stand-up is currently available.
	var collision := KinematicCollision3D.new()
	var blocked: bool = player.test_move(
		player.global_transform,
		Vector3.UP * missing_height,
		collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)
	var allowed_growth: float = missing_height
	if blocked:
		allowed_growth = maxf(
			0.0,
			collision.get_travel().y - PROBE_SAFE_MARGIN
		)
	if allowed_growth <= HEIGHT_EPSILON:
		return false

	return _apply_height(minf(standing_height, current_height + allowed_growth))


func get_movement_speed(standing_speed: float, crouched_speed: float) -> float:
	if standing_height <= crouch_height + HEIGHT_EPSILON:
		return standing_speed
	var stance_fraction: float = clampf(
		(capsule_shape.height - crouch_height) / (standing_height - crouch_height),
		0.0,
		1.0
	)
	return lerpf(crouched_speed, standing_speed, stance_fraction)


func is_fully_standing() -> bool:
	return (
		standing_requested
		and capsule_shape.height >= standing_height - HEIGHT_EPSILON
	)


func _apply_height(next_height: float) -> bool:
	next_height = clampf(next_height, crouch_height, standing_height)
	if absf(capsule_shape.height - next_height) <= HEIGHT_EPSILON:
		return false

	capsule_shape.height = next_height
	collision_shape.position.y = capsule_bottom_offset + next_height * 0.5

	var next_top: float = capsule_bottom_offset + next_height
	head.position.y = next_top - head_top_clearance

	if capsule_mesh != null and visual_mesh != null:
		capsule_mesh.height = next_height
		visual_mesh.position.y = visual_bottom_offset + next_height * 0.5

	# Ledge geometry caches capsule height/offsets and eye height. Refresh those
	# values immediately so traversal always uses the body's actual stance.
	ledge_detector.eye_height = head.position.y
	ledge_detector._cache_static_values()
	ledge_detector.clear_candidate()
	return true
