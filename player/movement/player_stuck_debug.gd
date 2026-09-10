extends Node


@export var enabled: bool = true
@export var history_frames: int = 10
@export var dump_cooldown_frames: int = 30
@export var stall_frames_before_dump: int = 2

const FALL_SPEED_THRESHOLD: float = 0.05
const STALL_VERTICAL_PROGRESS: float = 0.0005
const INPUT_EPSILON_SQUARED: float = 0.000001

var body: CharacterBody3D
var initialized: bool = false
var frame_index: int = 0
var previous_position: Vector3 = Vector3.ZERO
var previous_velocity: Vector3 = Vector3.ZERO
var previous_step_active: bool = false
var previous_grounded: bool = false
var previous_ledge_state: int = PlayerLedgeController.State.NONE
var stall_frames: int = 0
var dump_cooldown: int = 0
var history: Array[String] = []


func _ready() -> void:
	body = get_parent() as CharacterBody3D


func _physics_process(delta: float) -> void:
	if not enabled or body == null:
		return

	var support: Variant = body.get("support")
	var step: Variant = body.get("step")
	var ledge_controller: Variant = body.get("ledge_controller")
	var ledge_detector: Variant = body.get("ledge_detector")
	var player_input: Variant = body.get("player_input")
	if (
		support == null
		or step == null
		or ledge_controller == null
		or ledge_detector == null
		or player_input == null
	):
		return

	frame_index += 1
	if dump_cooldown > 0:
		dump_cooldown -= 1

	var input_direction: Vector3 = player_input.get_movement_direction(
		body.global_transform
	)
	var position: Vector3 = body.global_position
	var velocity: Vector3 = body.velocity
	var grounded: bool = support.is_grounded()
	var has_support: bool = support.has_support
	var walkable: bool = support.walkable
	var step_active: bool = step.is_active()
	var ledge_state: int = ledge_controller.state

	var summary: String = _make_summary(
		delta,
		input_direction,
		position,
		velocity,
		support,
		step,
		ledge_state
	)
	history.append(summary)
	while history.size() > maxi(history_frames, 1):
		history.pop_front()

	if not initialized:
		initialized = true
		previous_position = position
		previous_velocity = velocity
		previous_step_active = step_active
		previous_grounded = grounded
		previous_ledge_state = ledge_state
		return

	var displacement: Vector3 = position - previous_position
	var was_falling: bool = previous_velocity.y < -FALL_SPEED_THRESHOLD
	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_active: bool = (
		horizontal_input.length_squared() > INPUT_EPSILON_SQUARED
	)

	var unsupported_stall: bool = (
		was_falling
		and input_active
		and not grounded
		and ledge_state == PlayerLedgeController.State.NONE
		and displacement.y > -STALL_VERTICAL_PROGRESS
	)
	if unsupported_stall:
		stall_frames += 1
	else:
		stall_frames = 0

	var reason: String = ""
	if (
		was_falling
		and not previous_step_active
		and step_active
		and not grounded
	):
		reason = "AIRBORNE_STEP_STARTED"
	elif (
		was_falling
		and step_active
		and not grounded
		and velocity.y >= -0.001
	):
		reason = "AIRBORNE_STEP_OWNS_ZERO_Y"
	elif (
		was_falling
		and previous_ledge_state == PlayerLedgeController.State.NONE
		and ledge_state != PlayerLedgeController.State.NONE
	):
		reason = "LEDGE_STATE_ENTERED_DURING_FALL"
	elif (
		was_falling
		and not previous_grounded
		and grounded
		and displacement.y > -0.01
	):
		reason = "SUPPORT_ACQUIRED_WITH_TINY_FALL_PROGRESS"
	elif (
		was_falling
		and not grounded
		and ledge_state == PlayerLedgeController.State.NONE
		and velocity.y >= -0.001
	):
		reason = "BALLISTIC_Y_CLEARED_WITHOUT_GROUND"
	elif stall_frames >= maxi(stall_frames_before_dump, 1):
		reason = "UNSUPPORTED_FALL_STALLED"

	if not reason.is_empty() and dump_cooldown <= 0:
		_dump(
			reason,
			delta,
			input_direction,
			displacement,
			support,
			step,
			ledge_controller,
			ledge_detector
		)
		dump_cooldown = maxi(dump_cooldown_frames, 1)

	previous_position = position
	previous_velocity = velocity
	previous_step_active = step_active
	previous_grounded = grounded
	previous_ledge_state = ledge_state


func _make_summary(
	delta: float,
	input_direction: Vector3,
	position: Vector3,
	velocity: Vector3,
	support: Variant,
	step: Variant,
	ledge_state: int
) -> String:
	var step_height: float = -1.0
	var step_edge: Vector3 = Vector3.ZERO
	if step.is_active() and step.active_candidate != null:
		step_height = step.active_candidate.step_height
		step_edge = step.active_candidate.edge_point

	return (
		"pf=%d dt=%.6f pos=%s vel=%s input=%s support=%s grounded=%s walkable=%s support_point=%s support_normal=%s step=%s step_height=%.6f step_edge=%s ledge=%s"
		% [
			frame_index,
			delta,
			str(position),
			str(velocity),
			str(input_direction),
			str(support.has_support),
			str(support.is_grounded()),
			str(support.walkable),
			str(support.support_point),
			str(support.support_normal),
			str(step.is_active()),
			step_height,
			str(step_edge),
			_ledge_state_name(ledge_state),
		]
	)


func _dump(
	reason: String,
	delta: float,
	input_direction: Vector3,
	displacement: Vector3,
	support: Variant,
	step: Variant,
	ledge_controller: Variant,
	ledge_detector: Variant
) -> void:
	print(
		"[STUCK_DEBUG_BEGIN] reason=%s pf=%d"
		% [reason, frame_index]
	)
	for line: String in history:
		print("[STUCK_HISTORY] ", line)

	print(
		"[STUCK_NOW] dpos=%s previous_velocity=%s current_velocity=%s input=%s"
		% [
			str(displacement),
			str(previous_velocity),
			str(body.velocity),
			str(input_direction),
		]
	)
	print(
		"[STUCK_BODY] safe_margin=%.6f motion_mode=%s up=%s floor_max_angle=%.6f is_on_floor=%s is_on_wall=%s"
		% [
			body.safe_margin,
			str(body.motion_mode),
			str(body.up_direction),
			body.floor_max_angle,
			str(body.is_on_floor()),
			str(body.is_on_wall()),
		]
	)
	print(
		"[STUCK_SUPPORT] has=%s grounded=%s walkable=%s point=%s normal=%s"
		% [
			str(support.has_support),
			str(support.is_grounded()),
			str(support.walkable),
			str(support.support_point),
			str(support.support_normal),
		]
	)

	_dump_step(step)
	_dump_ledge(ledge_controller, ledge_detector)
	_dump_capsule()
	_dump_motion_tests(delta, input_direction)

	print("[STUCK_DEBUG_END] pf=%d" % frame_index)


func _dump_step(step: Variant) -> void:
	if not step.is_active() or step.active_candidate == null:
		print("[STUCK_STEP] active=false")
		return

	var candidate: Variant = step.active_candidate
	print(
		"[STUCK_STEP] active=true edge=%s wall=%s height=%.6f align=%.6f assist=%.6f remaining=%.6f crossed=%s"
		% [
			str(candidate.edge_point),
			str(candidate.wall_normal),
			candidate.step_height,
			candidate.approach_alignment,
			step.current_assist_speed,
			step.get_remaining_height(body.global_position),
			str(step.has_crossed_edge(body.global_position)),
		]
	)


func _dump_ledge(
	ledge_controller: Variant,
	ledge_detector: Variant
) -> void:
	var candidates: Variant = ledge_detector.get_candidates()
	print(
		"[STUCK_LEDGE] state=%s active=%s candidates=%d"
		% [
			_ledge_state_name(ledge_controller.state),
			str(ledge_controller.is_active()),
			candidates.size(),
		]
	)
	for candidate_index: int in range(candidates.size()):
		var candidate: Variant = candidates[candidate_index]
		if candidate == null:
			continue
		print(
			"[STUCK_LEDGE_CANDIDATE] index=%d edge=%s wall=%s top_point=%s top_normal=%s hang=%s hangable=%s wall_rid=%s top_rid=%s"
			% [
				candidate_index,
				str(candidate.edge_point),
				str(candidate.wall_normal),
				str(candidate.top_point),
				str(candidate.top_normal),
				str(candidate.hang_position),
				str(candidate.hangable),
				str(candidate.wall_collider_rid),
				str(candidate.top_collider_rid),
			]
		)


func _dump_capsule() -> void:
	var collision_shape: CollisionShape3D = body.get_node(
		"CollisionShape3D"
	) as CollisionShape3D
	if collision_shape == null:
		return
	var shape: Shape3D = collision_shape.shape
	if not (shape is CapsuleShape3D):
		return

	var capsule := shape as CapsuleShape3D
	print(
		"[STUCK_CAPSULE] radius=%.6f height=%.6f local_position=%s bottom_y=%.6f top_y=%.6f"
		% [
			capsule.radius,
			capsule.height,
			str(collision_shape.position),
			body.global_position.y
				+ collision_shape.position.y
				- capsule.height * 0.5,
			body.global_position.y
				+ collision_shape.position.y
				+ capsule.height * 0.5,
		]
	)


func _dump_motion_tests(
	delta: float,
	input_direction: Vector3
) -> void:
	_test_motion("down_0.02", Vector3.DOWN * 0.02)
	_test_motion("down_0.10", Vector3.DOWN * 0.10)

	if previous_velocity.y < -FALL_SPEED_THRESHOLD:
		_test_motion(
			"previous_ballistic_y",
			Vector3.UP * previous_velocity.y * delta
		)
		_test_motion(
			"previous_full_velocity",
			previous_velocity * delta
		)

	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	if horizontal_input.length_squared() <= INPUT_EPSILON_SQUARED:
		return

	var inward_motion: Vector3 = horizontal_input.normalized() * 0.02
	_test_motion("input_0.02", inward_motion)
	_test_motion(
		"input_plus_down",
		inward_motion + Vector3.DOWN * 0.02
	)


func _test_motion(label: String, motion: Vector3) -> void:
	var collision := KinematicCollision3D.new()
	var max_iterations: int = int(body.get("max_collision_iterations"))
	var blocked: bool = body.test_move(
		body.global_transform,
		motion,
		collision,
		body.safe_margin,
		false,
		maxi(max_iterations, 1)
	)
	print(
		"[STUCK_TEST_MOVE] label=%s motion=%s blocked=%s travel=%s remainder=%s contacts=%d"
		% [
			label,
			str(motion),
			str(blocked),
			str(collision.get_travel()),
			str(collision.get_remainder()),
			collision.get_collision_count(),
		]
	)
	if not blocked:
		return

	var contact_count: int = collision.get_collision_count()
	if contact_count <= 0:
		print(
			"[STUCK_TEST_CONTACT] label=%s normal=%s position=%s"
			% [
				label,
				str(collision.get_normal()),
				str(collision.get_position()),
			]
		)
		return

	for contact_index: int in range(contact_count):
		print(
			"[STUCK_TEST_CONTACT] label=%s index=%d normal=%s position=%s depth=%.6f rid=%s collider=%s"
			% [
				label,
				contact_index,
				str(collision.get_normal(contact_index)),
				str(collision.get_position(contact_index)),
				collision.get_depth(),
				str(collision.get_collider_rid(contact_index)),
				_collider_label(collision.get_collider(contact_index)),
			]
		)


func _collider_label(collider: Object) -> String:
	if collider == null:
		return "null"
	if collider is Node:
		var node := collider as Node
		return "%s:%s" % [node.get_class(), str(node.get_path())]
	return "%s#%s" % [collider.get_class(), str(collider.get_instance_id())]


func _ledge_state_name(state_value: int) -> String:
	match state_value:
		PlayerLedgeController.State.NONE:
			return "NONE"
		PlayerLedgeController.State.CATCHING:
			return "CATCHING"
		PlayerLedgeController.State.HANGING:
			return "HANGING"
		PlayerLedgeController.State.CORNERING:
			return "CORNERING"
		PlayerLedgeController.State.MANTLING:
			return "MANTLING"
	return "UNKNOWN_%d" % state_value
