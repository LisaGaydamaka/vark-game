class_name PlayerJitterSensor
extends RefCounted


const HISTORY_CAPACITY: int = 12
const SUPPORT_WINDOW_FRAMES: int = 5
const REPORT_COOLDOWN_FRAMES: int = 300
const MINIMUM_JITTER_DISPLACEMENT: float = 0.00075
const DISPLACEMENT_REVERSAL_DOT: float = -0.35
const MINIMUM_VERTICAL_FLIP_SPEED: float = 0.15
const UNEXPECTED_GROUND_VERTICAL_SPEED: float = 0.05
const VELOCITY_SNAP_ACCELERATION: float = 75.0
const BLOCKED_MOTION_RATIO: float = 0.25
const MINIMUM_REQUESTED_MOTION: float = 0.005
const STABLE_INTENT_DOT: float = 0.5


var enabled: bool = OS.is_debug_build()
var history: Array[Dictionary] = []
var frame_start_position: Vector3 = Vector3.ZERO
var frame_start_velocity: Vector3 = Vector3.ZERO
var frame_delta: float = 0.0
var frame_intent: Vector3 = Vector3.ZERO
var frame_collision_normals: Array[Vector3] = []
var frame_collision_points: Array[Vector3] = []
var expected_discontinuity: String = ""
var last_report_frame: int = -REPORT_COOLDOWN_FRAMES


func begin_frame(player: CharacterBody3D, delta: float) -> void:
	if not enabled:
		return
	frame_start_position = player.global_position
	frame_start_velocity = player.velocity
	frame_delta = maxf(delta, 0.000001)
	frame_intent = Vector3.ZERO
	frame_collision_normals.clear()
	frame_collision_points.clear()
	expected_discontinuity = ""


func set_intent(input_direction: Vector3) -> void:
	if not enabled:
		return
	frame_intent = Vector3(input_direction.x, 0.0, input_direction.z)


func mark_expected_discontinuity(reason: String) -> void:
	if not enabled:
		return
	expected_discontinuity = reason


func record_collisions(collisions: Array[KinematicCollision3D]) -> void:
	if not enabled:
		return
	for collision: KinematicCollision3D in collisions:
		if collision == null:
			continue
		for collision_index: int in range(collision.get_collision_count()):
			frame_collision_normals.append(collision.get_normal(collision_index))
			frame_collision_points.append(collision.get_position(collision_index))


func end_frame(
	player: CharacterBody3D,
	support: PlayerSupport,
	state_name: String,
	step_active: bool
) -> void:
	if not enabled:
		return

	var displacement: Vector3 = player.global_position - frame_start_position
	var snapshot: Dictionary = {
		"frame": Engine.get_physics_frames(),
		"position": player.global_position,
		"displacement": displacement,
		"velocity_before": frame_start_velocity,
		"velocity": player.velocity,
		"intent": frame_intent,
		"state": state_name,
		"step": step_active,
		"expected": expected_discontinuity,
		"collisions": frame_collision_normals.size(),
		"collision_normals": frame_collision_normals.duplicate(),
		"collision_points": frame_collision_points.duplicate(),
		"support": support.has_support,
		"walkable": support.walkable,
		"support_normal": support.support_normal,
		"support_point": support.support_point,
	}

	# This never reaches the console at the normal DEBUG threshold, but leaves a
	# short black-box timeline in GameLog's ring buffer before a jitter report.
	GameLog.trace("jitter", "frame", snapshot)
	_analyze(snapshot)

	history.append(snapshot)
	if history.size() > HISTORY_CAPACITY:
		history.pop_front()


func _analyze(current: Dictionary) -> void:
	if history.is_empty():
		return

	var previous: Dictionary = history[history.size() - 1]
	if not _state_is_comparable(previous, current):
		return

	var reasons: PackedStringArray = PackedStringArray()
	var score: int = 0
	var support_flips: int = _count_recent_support_flips(current)
	if support_flips >= 2:
		score += 2
		reasons.append("support_oscillation:%d_flips" % support_flips)

	var displacement_reversal: bool = _has_displacement_reversal(previous, current)
	if displacement_reversal:
		score += 2
		reasons.append("displacement_reversal")

	var vertical_flip: bool = _has_unexpected_vertical_velocity_flip(previous, current)
	if vertical_flip:
		score += 1
		reasons.append("vertical_velocity_flip")

	var current_velocity: Vector3 = current["velocity"]
	if (
		bool(current["support"])
		and bool(current["walkable"])
		and current_velocity.y > UNEXPECTED_GROUND_VERTICAL_SPEED
		and str(current["expected"]).is_empty()
	):
		score += 3
		reasons.append("positive_persistent_y_on_walkable_ground")

	var velocity_snap: float = _get_velocity_snap_acceleration(previous, current)
	if velocity_snap >= VELOCITY_SNAP_ACCELERATION:
		score += 1
		reasons.append("velocity_snap:%.1f_mps2" % velocity_snap)

	var blocked_ratio: float = _get_horizontal_motion_ratio(current)
	var collision_blocked: bool = (
		int(current["collisions"]) > 0
		and blocked_ratio >= 0.0
		and blocked_ratio < BLOCKED_MOTION_RATIO
	)
	if collision_blocked and displacement_reversal:
		score += 1
		reasons.append("collision_blocked_reversal:%.2f" % blocked_ratio)

	if _contact_manifold_flipped(previous, current):
		score += 1
		reasons.append("contact_normal_flip")

	if score < 3:
		return

	var frame: int = int(current["frame"])
	if frame - last_report_frame < REPORT_COOLDOWN_FRAMES:
		return
	last_report_frame = frame

	var diagnosis: String = _diagnose(
		support_flips,
		displacement_reversal,
		vertical_flip,
		collision_blocked,
		current
	)
	GameLog.warn("jitter", "detected", {
		"diagnosis": diagnosis,
		"reasons": reasons,
		"score": score,
		"position": current["position"],
		"displacement": current["displacement"],
		"velocity_before": current["velocity_before"],
		"velocity": current["velocity"],
		"intent": current["intent"],
		"state": current["state"],
		"step": current["step"],
		"support": current["support"],
		"walkable": current["walkable"],
		"support_normal": current["support_normal"],
		"support_point": current["support_point"],
		"collisions": current["collisions"],
		"collision_normals": current["collision_normals"],
		"collision_points": current["collision_points"],
	})
	GameLog.dump_trace()


func _count_recent_support_flips(current: Dictionary) -> int:
	var start_index: int = maxi(0, history.size() - SUPPORT_WINDOW_FRAMES + 1)
	var previous_support: bool = bool(history[start_index]["support"])
	var previous_walkable: bool = bool(history[start_index]["walkable"])
	var flips: int = 0

	for history_index: int in range(start_index + 1, history.size()):
		var snapshot: Dictionary = history[history_index]
		var next_support: bool = bool(snapshot["support"])
		var next_walkable: bool = bool(snapshot["walkable"])
		if next_support != previous_support or next_walkable != previous_walkable:
			flips += 1
		previous_support = next_support
		previous_walkable = next_walkable

	var current_support: bool = bool(current["support"])
	var current_walkable: bool = bool(current["walkable"])
	if current_support != previous_support or current_walkable != previous_walkable:
		flips += 1
	return flips


func _has_displacement_reversal(previous: Dictionary, current: Dictionary) -> bool:
	var previous_displacement: Vector3 = previous["displacement"]
	var current_displacement: Vector3 = current["displacement"]
	if (
		previous_displacement.length() < MINIMUM_JITTER_DISPLACEMENT
		or current_displacement.length() < MINIMUM_JITTER_DISPLACEMENT
	):
		return false
	if not _intent_is_stable(previous, current):
		return false
	return (
		previous_displacement.normalized().dot(current_displacement.normalized())
		<= DISPLACEMENT_REVERSAL_DOT
	)


func _intent_is_stable(previous: Dictionary, current: Dictionary) -> bool:
	var previous_intent: Vector3 = previous["intent"]
	var current_intent: Vector3 = current["intent"]
	if previous_intent.length_squared() <= 0.000001:
		return current_intent.length_squared() <= 0.000001
	if current_intent.length_squared() <= 0.000001:
		return false
	return (
		previous_intent.normalized().dot(current_intent.normalized())
		>= STABLE_INTENT_DOT
	)


func _has_unexpected_vertical_velocity_flip(
	previous: Dictionary,
	current: Dictionary
) -> bool:
	if not str(current["expected"]).is_empty():
		return false
	if not str(previous["expected"]).is_empty():
		return false
	var previous_velocity: Vector3 = previous["velocity"]
	var current_velocity: Vector3 = current["velocity"]
	if (
		absf(previous_velocity.y) < MINIMUM_VERTICAL_FLIP_SPEED
		or absf(current_velocity.y) < MINIMUM_VERTICAL_FLIP_SPEED
	):
		return false
	return previous_velocity.y * current_velocity.y < 0.0


func _get_velocity_snap_acceleration(
	previous: Dictionary,
	current: Dictionary
) -> float:
	if not str(current["expected"]).is_empty():
		return 0.0
	var previous_velocity: Vector3 = previous["velocity"]
	var current_velocity: Vector3 = current["velocity"]
	return (current_velocity - previous_velocity).length() / frame_delta


func _get_horizontal_motion_ratio(current: Dictionary) -> float:
	var velocity: Vector3 = current["velocity"]
	var requested := Vector3(velocity.x, 0.0, velocity.z) * frame_delta
	var requested_distance: float = requested.length()
	if requested_distance < MINIMUM_REQUESTED_MOTION:
		return -1.0
	var displacement: Vector3 = current["displacement"]
	var actual_horizontal := Vector3(displacement.x, 0.0, displacement.z)
	return actual_horizontal.length() / requested_distance


func _contact_manifold_flipped(previous: Dictionary, current: Dictionary) -> bool:
	var previous_normals: Array = previous["collision_normals"]
	var current_normals: Array = current["collision_normals"]
	if previous_normals.is_empty() or current_normals.is_empty():
		return false
	var previous_normal: Vector3 = previous_normals[0]
	var current_normal: Vector3 = current_normals[0]
	return previous_normal.dot(current_normal) < -0.25


func _state_is_comparable(previous: Dictionary, current: Dictionary) -> bool:
	if str(previous["state"]) != str(current["state"]):
		return false
	if bool(previous["step"]) != bool(current["step"]):
		return false
	return (
		str(previous["expected"]).is_empty()
		and str(current["expected"]).is_empty()
	)


func _diagnose(
	support_flips: int,
	displacement_reversal: bool,
	vertical_flip: bool,
	collision_blocked: bool,
	current: Dictionary
) -> String:
	var current_velocity: Vector3 = current["velocity"]
	if (
		bool(current["support"])
		and bool(current["walkable"])
		and current_velocity.y > UNEXPECTED_GROUND_VERTICAL_SPEED
	):
		return "walkable support created or preserved upward persistent velocity"
	if support_flips >= 2 and vertical_flip:
		return "support classification is oscillating while vertical velocity changes sign"
	if support_flips >= 2 and collision_blocked:
		return "collision blocking and support classification are alternating across frames"
	if displacement_reversal and collision_blocked:
		return "collision response reversed actual movement while player intent stayed stable"
	if support_flips >= 2:
		return "support classification is unstable alongside another motion anomaly"
	if displacement_reversal:
		return "actual player displacement reversed without a matching input reversal"
	return "abrupt motion-state change exceeded jitter thresholds"
