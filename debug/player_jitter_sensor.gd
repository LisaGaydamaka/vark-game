class_name PlayerJitterSensor
extends RefCounted


const HISTORY_CAPACITY: int = 12
const REPORT_HISTORY_FRAMES: int = 5
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

	var contact_flip: bool = _contact_manifold_flipped(previous, current)
	if contact_flip:
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
		contact_flip,
		current
	)
	print(_format_report(current, diagnosis, reasons, score, blocked_ratio))


func _count_recent_support_flips(current: Dictionary) -> int:
	var snapshots: Array[Dictionary] = []
	var start_index: int = maxi(0, history.size() - SUPPORT_WINDOW_FRAMES + 1)
	for history_index: int in range(start_index, history.size()):
		var snapshot: Dictionary = history[history_index]
		if not _snapshot_matches_context(snapshot, current):
			continue
		snapshots.append(snapshot)
	snapshots.append(current)

	if snapshots.size() < 2:
		return 0

	var previous_support: bool = bool(snapshots[0]["support"])
	var previous_walkable: bool = bool(snapshots[0]["walkable"])
	var flips: int = 0
	for snapshot_index: int in range(1, snapshots.size()):
		var snapshot: Dictionary = snapshots[snapshot_index]
		var next_support: bool = bool(snapshot["support"])
		var next_walkable: bool = bool(snapshot["walkable"])
		if next_support != previous_support or next_walkable != previous_walkable:
			flips += 1
		previous_support = next_support
		previous_walkable = next_walkable
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
	return _snapshot_matches_context(previous, current)


func _snapshot_matches_context(snapshot: Dictionary, current: Dictionary) -> bool:
	if str(snapshot["state"]) != str(current["state"]):
		return false
	if bool(snapshot["step"]) != bool(current["step"]):
		return false
	return (
		str(snapshot["expected"]).is_empty()
		and str(current["expected"]).is_empty()
	)


func _diagnose(
	support_flips: int,
	displacement_reversal: bool,
	vertical_flip: bool,
	collision_blocked: bool,
	contact_flip: bool,
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
		return "support classification oscillated while vertical velocity changed sign"
	if support_flips >= 2 and collision_blocked:
		return "collision blocking and support classification alternated across frames"
	if support_flips >= 2 and contact_flip:
		return "support and collision contact normals were unstable across frames"
	if displacement_reversal and collision_blocked:
		return "collision response reversed actual movement while input stayed stable"
	if support_flips >= 2:
		return "support classification was unstable alongside another motion anomaly"
	if displacement_reversal:
		return "actual displacement reversed without a matching input reversal"
	if contact_flip:
		return "collision contact normal changed abruptly between adjacent frames"
	return "abrupt motion-state change exceeded jitter thresholds"


func _format_report(
	current: Dictionary,
	diagnosis: String,
	reasons: PackedStringArray,
	score: int,
	blocked_ratio: float
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("")
	lines.append("==================== [JITTER DETECTED] ====================")
	lines.append("diagnosis: %s" % diagnosis)
	lines.append("reasons: %s" % ", ".join(reasons))
	lines.append("score: %d" % score)
	lines.append("frame: %d  state: %s  step: %s" % [
		int(current["frame"]),
		str(current["state"]),
		str(current["step"]),
	])
	lines.append("position: %s" % str(current["position"]))
	lines.append("displacement: %s" % str(current["displacement"]))
	lines.append("velocity: %s -> %s" % [
		str(current["velocity_before"]),
		str(current["velocity"]),
	])
	lines.append("intent: %s" % str(current["intent"]))
	lines.append("support: %s  walkable: %s" % [
		str(current["support"]),
		str(current["walkable"]),
	])
	lines.append("support_normal: %s  support_point: %s" % [
		str(current["support_normal"]),
		str(current["support_point"]),
	])
	if blocked_ratio >= 0.0:
		lines.append("horizontal_motion_ratio: %.3f" % blocked_ratio)
	lines.append("collisions: %d" % int(current["collisions"]))
	lines.append("collision_normals: %s" % str(current["collision_normals"]))
	lines.append("collision_points: %s" % str(current["collision_points"]))
	lines.append("recent frames (oldest -> newest):")

	var start_index: int = maxi(0, history.size() - REPORT_HISTORY_FRAMES + 1)
	for history_index: int in range(start_index, history.size()):
		lines.append("  %s" % _format_snapshot_line(history[history_index]))
	lines.append("  %s" % _format_snapshot_line(current))
	lines.append("===========================================================")
	return "\n".join(lines)


func _format_snapshot_line(snapshot: Dictionary) -> String:
	return (
		"F:%d state=%s pos=%s move=%s vel=%s intent=%s "
		+ "support=%s walkable=%s support_n=%s collisions=%d normals=%s expected=%s"
	) % [
		int(snapshot["frame"]),
		str(snapshot["state"]),
		str(snapshot["position"]),
		str(snapshot["displacement"]),
		str(snapshot["velocity"]),
		str(snapshot["intent"]),
		str(snapshot["support"]),
		str(snapshot["walkable"]),
		str(snapshot["support_normal"]),
		int(snapshot["collisions"]),
		str(snapshot["collision_normals"]),
		str(snapshot["expected"]),
	]
