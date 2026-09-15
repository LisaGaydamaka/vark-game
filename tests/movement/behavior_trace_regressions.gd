extends RefCounted


const FlatFixture = preload(
	"res://tests/movement/fixtures/sprint_jump.tscn"
)
const StepFixture = preload(
	"res://tests/movement/fixtures/normal_step.tscn"
)
const LedgeFixture = preload(
	"res://tests/movement/fixtures/ledge_traversal.tscn"
)

const SETTLE_PHYSICS_FRAMES: int = 3
const WALK_START_FRAMES: int = 10
const WALK_CRUISE_ADDITIONAL_FRAMES: int = 20
const WALK_BRAKE_FRAMES: int = 6
const WALK_STOP_ADDITIONAL_FRAMES: int = 6
const CROUCH_TRANSITION_FRAMES: int = 10
const CROUCH_MOVE_FRAMES: int = 20
const JUMP_TRACE_ADDITIONAL_FRAMES: int = 10
const SPRINT_TRACE_FRAMES: int = 30
const STEP_APPROACH_FRAMES: int = 20
const STEP_TOP_ADDITIONAL_FRAMES: int = 22
const ENTER_HANG_MAX_FRAMES: int = 90
const SHIMMY_FRAMES: int = 10
const CORNER_APPROACH_FRAMES: int = 60
const CORNER_TRANSITION_MAX_FRAMES: int = 60
const MANTLE_MAX_FRAMES: int = 90

const WALK_POSITION_TOLERANCE: float = 0.08
const WALK_VELOCITY_TOLERANCE: float = 0.14
const JUMP_POSITION_TOLERANCE: float = 0.035
const JUMP_VELOCITY_TOLERANCE: float = 0.1
const STEP_POSITION_TOLERANCE: float = 0.16
const STEP_VELOCITY_TOLERANCE: float = 0.2
const HANG_POSITION_TOLERANCE: float = 0.06
const SHIMMY_POSITION_TOLERANCE: float = 0.09
const CORNER_POSITION_TOLERANCE: float = 0.35
const MANTLE_POSITION_TOLERANCE: float = 0.1
const ZERO_VELOCITY_TOLERANCE: float = 0.06

const WALK_START_POSITION := Vector3(0.0, 0.0, 1.733)
const WALK_START_VELOCITY := Vector3(0.0, 0.0, -2.342)
const WALK_CRUISE_POSITION := Vector3(0.0, 0.0, 0.822)
const WALK_CRUISE_VELOCITY := Vector3(0.0, 0.0, -2.853)
const WALK_BRAKE_POSITION := Vector3(0.0, 0.0, 0.625)
const WALK_BRAKE_VELOCITY := Vector3(0.0, 0.0, -1.353)
const WALK_STOP_POSITION := Vector3(0.0, 0.0, 0.574)
const CROUCH_MOVE_POSITION := Vector3(0.0, 0.0, 1.466)
const CROUCH_MOVE_VELOCITY := Vector3(0.0, 0.0, -1.905)
const CROUCH_STAND_POSITION := Vector3(0.0, 0.0, 1.361)
const JUMP_TAKEOFF_POSITION := Vector3(0.0, 0.071, 2.0)
const JUMP_TAKEOFF_VELOCITY := Vector3(0.0, 4.243, 0.0)
const JUMP_RISE_POSITION := Vector3(0.0, 0.594, 2.0)
const JUMP_RISE_VELOCITY := Vector3(0.0, 2.243, 0.0)
const SPRINT_POSITION := Vector3(0.0, 0.0, 0.444)
const SPRINT_VELOCITY := Vector3(0.0, 0.0, -4.146)
const SPRINT_JUMP_POSITION := Vector3(0.0, 0.071, 0.374)
const SPRINT_JUMP_VELOCITY := Vector3(0.0, 4.243, -4.163)
const STEP_APPROACH_POSITION := Vector3(0.0, 0.0, 0.294)
const STEP_APPROACH_VELOCITY := Vector3(0.0, 0.0, -2.774)
const STEP_TOP_POSITION := Vector3(0.0, 0.25, -0.75)
const STEP_TOP_VELOCITY := Vector3(0.0, 0.0, -2.869)
const HANG_POSITION := Vector3(0.0, 0.24, -0.759)
const SHIMMY_POSITION := Vector3(0.251, 0.24, -0.759)
const HANG_RELEASE_POSITION := Vector3(0.251, 0.237, -0.759)
const HANG_RELEASE_VELOCITY := Vector3(0.0, -0.2, 0.0)
const CORNER_POSITION := Vector3(1.441, 0.24, -1.24)
const MANTLE_POSITION := Vector3(0.0, 1.603, -1.0)


var tree: SceneTree


func _init(test_tree: SceneTree) -> void:
	tree = test_tree


func run(helpers: RefCounted) -> void:
	await _test_walk_start_stop_trace(helpers)
	await _test_crouch_trace(helpers)
	await _test_jump_traces(helpers)
	await _test_step_trace(helpers)
	await _test_traversal_trace(helpers)
	await _test_corner_trace(helpers)
	await _test_mantle_trace(helpers)


func _test_walk_start_stop_trace(helpers: RefCounted) -> void:
	var fixture: Node3D = await _spawn_fixture(FlatFixture)
	var player: CharacterBody3D = fixture.get_node("Player")

	_assert_checkpoint(
		helpers,
		player,
		Vector3(0.0, 0.0, 2.0),
		0.01,
		Vector3.ZERO,
		ZERO_VELOCITY_TOLERANCE,
		"grounded",
		"standing",
		"normal",
		"Walk trace initial state"
	)

	Input.action_press("move_forward")
	await _advance_frames(WALK_START_FRAMES)
	_assert_checkpoint(
		helpers,
		player,
		WALK_START_POSITION,
		WALK_POSITION_TOLERANCE,
		WALK_START_VELOCITY,
		WALK_VELOCITY_TOLERANCE,
		"grounded",
		"standing",
		"normal",
		"Walk trace preserves accepted startup response"
	)

	await _advance_frames(WALK_CRUISE_ADDITIONAL_FRAMES)
	_assert_checkpoint(
		helpers,
		player,
		WALK_CRUISE_POSITION,
		WALK_POSITION_TOLERANCE,
		WALK_CRUISE_VELOCITY,
		WALK_VELOCITY_TOLERANCE,
		"grounded",
		"standing",
		"normal",
		"Walk trace preserves accepted sustained response"
	)

	Input.action_release("move_forward")
	await _advance_frames(WALK_BRAKE_FRAMES)
	_assert_checkpoint(
		helpers,
		player,
		WALK_BRAKE_POSITION,
		WALK_POSITION_TOLERANCE,
		WALK_BRAKE_VELOCITY,
		WALK_VELOCITY_TOLERANCE,
		"grounded",
		"standing",
		"normal",
		"Walk trace preserves accepted stopping response"
	)

	await _advance_frames(WALK_STOP_ADDITIONAL_FRAMES)
	_assert_checkpoint(
		helpers,
		player,
		WALK_STOP_POSITION,
		WALK_POSITION_TOLERANCE,
		Vector3.ZERO,
		ZERO_VELOCITY_TOLERANCE,
		"grounded",
		"standing",
		"normal",
		"Walk trace settles to the accepted stopped state"
	)

	await _cleanup_fixture(fixture)


func _test_crouch_trace(helpers: RefCounted) -> void:
	var fixture: Node3D = await _spawn_fixture(FlatFixture)
	var player: CharacterBody3D = fixture.get_node("Player")

	Input.action_press("crouch")
	await _completed_physics_frame()
	Input.action_release("crouch")
	await _advance_frames(CROUCH_TRANSITION_FRAMES - 1)
	_assert_checkpoint(
		helpers,
		player,
		Vector3(0.0, 0.0, 2.0),
		0.02,
		Vector3.ZERO,
		ZERO_VELOCITY_TOLERANCE,
		"grounded",
		"crouched",
		"normal",
		"Crouch trace reaches the accepted crouched stance"
	)

	Input.action_press("move_forward")
	await _advance_frames(CROUCH_MOVE_FRAMES)
	Input.action_release("move_forward")
	_assert_checkpoint(
		helpers,
		player,
		CROUCH_MOVE_POSITION,
		WALK_POSITION_TOLERANCE,
		CROUCH_MOVE_VELOCITY,
		WALK_VELOCITY_TOLERANCE,
		"grounded",
		"crouched",
		"normal",
		"Crouch trace preserves accepted crouched movement"
	)

	Input.action_press("crouch")
	await _completed_physics_frame()
	Input.action_release("crouch")
	await _advance_frames(CROUCH_TRANSITION_FRAMES - 1)
	_assert_checkpoint(
		helpers,
		player,
		CROUCH_STAND_POSITION,
		WALK_POSITION_TOLERANCE,
		Vector3.ZERO,
		ZERO_VELOCITY_TOLERANCE,
		"grounded",
		"standing",
		"normal",
		"Crouch trace returns to the accepted standing state"
	)

	await _cleanup_fixture(fixture)


func _test_jump_traces(helpers: RefCounted) -> void:
	var fixture: Node3D = await _spawn_fixture(FlatFixture)
	var player: CharacterBody3D = fixture.get_node("Player")

	Input.action_press("jump")
	await _completed_physics_frame()
	Input.action_release("jump")
	_assert_checkpoint(
		helpers,
		player,
		JUMP_TAKEOFF_POSITION,
		JUMP_POSITION_TOLERANCE,
		JUMP_TAKEOFF_VELOCITY,
		JUMP_VELOCITY_TOLERANCE,
		"airborne",
		"standing",
		"normal",
		"Ordinary jump trace preserves accepted takeoff"
	)

	await _advance_frames(JUMP_TRACE_ADDITIONAL_FRAMES)
	_assert_checkpoint(
		helpers,
		player,
		JUMP_RISE_POSITION,
		0.06,
		JUMP_RISE_VELOCITY,
		JUMP_VELOCITY_TOLERANCE,
		"airborne",
		"standing",
		"normal",
		"Ordinary jump trace preserves accepted rising arc"
	)
	await _cleanup_fixture(fixture)

	fixture = await _spawn_fixture(FlatFixture)
	player = fixture.get_node("Player")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _advance_frames(SPRINT_TRACE_FRAMES)
	_assert_checkpoint(
		helpers,
		player,
		SPRINT_POSITION,
		WALK_POSITION_TOLERANCE,
		SPRINT_VELOCITY,
		0.16,
		"grounded",
		"standing",
		"normal",
		"Sprint-jump trace preserves accepted pre-jump momentum"
	)

	Input.action_press("jump")
	await _completed_physics_frame()
	Input.action_release("jump")
	_assert_checkpoint(
		helpers,
		player,
		SPRINT_JUMP_POSITION,
		0.09,
		SPRINT_JUMP_VELOCITY,
		0.18,
		"airborne",
		"standing",
		"normal",
		"Sprint-jump trace preserves inherited momentum at takeoff"
	)
	await _cleanup_fixture(fixture)


func _test_step_trace(helpers: RefCounted) -> void:
	var fixture: Node3D = await _spawn_fixture(StepFixture)
	var player: CharacterBody3D = fixture.get_node("Player")

	Input.action_press("move_forward")
	await _advance_frames(STEP_APPROACH_FRAMES)
	_assert_checkpoint(
		helpers,
		player,
		STEP_APPROACH_POSITION,
		WALK_POSITION_TOLERANCE,
		STEP_APPROACH_VELOCITY,
		WALK_VELOCITY_TOLERANCE,
		"grounded",
		"standing",
		"normal",
		"Step trace preserves the pre-contact locomotion state"
	)

	await _advance_frames(STEP_TOP_ADDITIONAL_FRAMES)
	Input.action_release("move_forward")
	_assert_checkpoint(
		helpers,
		player,
		STEP_TOP_POSITION,
		STEP_POSITION_TOLERANCE,
		STEP_TOP_VELOCITY,
		STEP_VELOCITY_TOLERANCE,
		"grounded",
		"standing",
		"normal",
		"Step trace preserves accepted support-to-support crossing"
	)
	await _cleanup_fixture(fixture)


func _test_traversal_trace(helpers: RefCounted) -> void:
	var fixture: Node3D = await _spawn_fixture(LedgeFixture, false)
	var player: CharacterBody3D = fixture.get_node("Player")
	var hang_result: Dictionary = await _wait_for_hang(player)
	helpers.assert_true(
		bool(hang_result.get("saw_catching", false)),
		"Traversal trace observes the catch transition"
	)
	helpers.assert_true(
		bool(hang_result.get("reached_hang", false)),
		"Traversal trace reaches the hanging state"
	)
	if not bool(hang_result.get("reached_hang", false)):
		await _cleanup_fixture(fixture)
		return

	_assert_checkpoint(
		helpers,
		player,
		HANG_POSITION,
		HANG_POSITION_TOLERANCE,
		Vector3.ZERO,
		ZERO_VELOCITY_TOLERANCE,
		"airborne",
		"standing",
		"hanging",
		"Traversal trace preserves accepted hang attachment"
	)

	Input.action_press("move_right")
	await _advance_frames(SHIMMY_FRAMES)
	Input.action_release("move_right")
	_assert_checkpoint(
		helpers,
		player,
		SHIMMY_POSITION,
		SHIMMY_POSITION_TOLERANCE,
		Vector3.ZERO,
		ZERO_VELOCITY_TOLERANCE,
		"airborne",
		"standing",
		"hanging",
		"Traversal trace preserves accepted shimmy response"
	)

	Input.action_press("crouch")
	await _completed_physics_frame()
	Input.action_release("crouch")
	_assert_checkpoint(
		helpers,
		player,
		HANG_RELEASE_POSITION,
		0.08,
		HANG_RELEASE_VELOCITY,
		0.08,
		"airborne",
		"standing",
		"normal",
		"Traversal trace preserves accepted ledge release"
	)
	await _cleanup_fixture(fixture)


func _test_corner_trace(helpers: RefCounted) -> void:
	var fixture: Node3D = await _spawn_fixture(LedgeFixture, false)
	var player: CharacterBody3D = fixture.get_node("Player")
	var hang_result: Dictionary = await _wait_for_hang(player)
	if not bool(hang_result.get("reached_hang", false)):
		helpers.assert_true(false, "Corner trace reaches its starting hang")
		await _cleanup_fixture(fixture)
		return

	Input.action_press("move_right")
	await _advance_frames(CORNER_APPROACH_FRAMES)
	Input.action_release("move_right")
	await _advance_frames(2)

	Input.action_press("move_right")
	var saw_cornering: bool = false
	var completed_corner: bool = false
	for _frame: int in range(CORNER_TRANSITION_MAX_FRAMES):
		await _completed_physics_frame()
		var traversal_state: String = _traversal_state(player)
		if traversal_state == "cornering":
			saw_cornering = true
		if saw_cornering and traversal_state == "hanging":
			completed_corner = true
			break
	Input.action_release("move_right")

	helpers.assert_true(
		saw_cornering and completed_corner,
		"Corner trace preserves the supported corner transition"
	)
	if completed_corner:
		_assert_checkpoint(
			helpers,
			player,
			CORNER_POSITION,
			CORNER_POSITION_TOLERANCE,
			Vector3.ZERO,
			ZERO_VELOCITY_TOLERANCE,
			"airborne",
			"standing",
			"hanging",
			"Corner trace preserves the adjoining ledge attachment"
		)
	await _cleanup_fixture(fixture)


func _test_mantle_trace(helpers: RefCounted) -> void:
	var fixture: Node3D = await _spawn_fixture(LedgeFixture, false)
	var player: CharacterBody3D = fixture.get_node("Player")
	var hang_result: Dictionary = await _wait_for_hang(player)
	if not bool(hang_result.get("reached_hang", false)):
		helpers.assert_true(false, "Mantle trace reaches its starting hang")
		await _cleanup_fixture(fixture)
		return

	Input.action_press("jump")
	await _completed_physics_frame()
	Input.action_release("jump")
	_assert_checkpoint(
		helpers,
		player,
		HANG_POSITION,
		HANG_POSITION_TOLERANCE,
		Vector3.ZERO,
		ZERO_VELOCITY_TOLERANCE,
		"airborne",
		"standing",
		"mantling",
		"Mantle trace preserves the hang-to-mantle transition"
	)

	var completed_mantle: bool = false
	for _frame: int in range(MANTLE_MAX_FRAMES):
		await _completed_physics_frame()
		var state: Dictionary = _snapshot(player)
		if (
			str(state.get("traversal", "")) == "normal"
			and str(state.get("support", "")) == "grounded"
		):
			completed_mantle = true
			break
	helpers.assert_true(
		completed_mantle,
		"Mantle trace reaches its supported completion state"
	)
	if completed_mantle:
		_assert_checkpoint(
			helpers,
			player,
			MANTLE_POSITION,
			MANTLE_POSITION_TOLERANCE,
			Vector3.ZERO,
			ZERO_VELOCITY_TOLERANCE,
			"grounded",
			"standing",
			"normal",
			"Mantle trace preserves accepted completion pose and velocity"
		)
	await _cleanup_fixture(fixture)


func _spawn_fixture(
	fixture_scene: PackedScene,
	settle: bool = true
) -> Node3D:
	_release_movement_actions()
	var fixture: Node3D = fixture_scene.instantiate()
	tree.get_root().add_child(fixture)
	if settle:
		await _advance_frames(SETTLE_PHYSICS_FRAMES)
	else:
		await tree.process_frame
	return fixture


func _wait_for_hang(player: CharacterBody3D) -> Dictionary:
	var saw_catching: bool = false
	for _frame: int in range(ENTER_HANG_MAX_FRAMES):
		await _completed_physics_frame()
		var traversal_state: String = _traversal_state(player)
		if traversal_state == "catching":
			saw_catching = true
		if traversal_state == "hanging":
			return {
				"reached_hang": true,
				"saw_catching": saw_catching,
			}
		if player.global_position.y < -2.0:
			break
	return {
		"reached_hang": false,
		"saw_catching": saw_catching,
	}


func _assert_checkpoint(
	helpers: RefCounted,
	player: CharacterBody3D,
	expected_position: Vector3,
	position_tolerance: float,
	expected_velocity: Vector3,
	velocity_tolerance: float,
	expected_support: String,
	expected_stance: String,
	expected_traversal: String,
	message: String
) -> void:
	var state: Dictionary = _snapshot(player)
	var position: Vector3 = state.get("position", Vector3.ZERO)
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var support_state: String = str(state.get("support", ""))
	var stance_state: String = str(state.get("stance", ""))
	var traversal_state: String = str(state.get("traversal", ""))
	var matches: bool = (
		position.distance_to(expected_position) <= position_tolerance
		and velocity.distance_to(expected_velocity) <= velocity_tolerance
		and support_state == expected_support
		and stance_state == expected_stance
		and traversal_state == expected_traversal
	)
	helpers.assert_true(
		matches,
		"%s; expected pos=%s±%.3f vel=%s±%.3f support=%s stance=%s traversal=%s; got %s"
		% [
			message,
			expected_position,
			position_tolerance,
			expected_velocity,
			velocity_tolerance,
			expected_support,
			expected_stance,
			expected_traversal,
			_format_state(state),
		]
	)


func _snapshot(player: CharacterBody3D) -> Dictionary:
	return player.call("get_movement_semantic_state")


func _traversal_state(player: CharacterBody3D) -> String:
	return str(_snapshot(player).get("traversal", ""))


func _format_state(state: Dictionary) -> String:
	return "pos=%s vel=%s support=%s stance=%s traversal=%s" % [
		state.get("position", Vector3.ZERO),
		state.get("velocity", Vector3.ZERO),
		state.get("support", ""),
		state.get("stance", ""),
		state.get("traversal", ""),
	]


func _advance_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await _completed_physics_frame()


func _completed_physics_frame() -> void:
	await tree.physics_frame
	await tree.process_frame


func _cleanup_fixture(fixture: Node) -> void:
	_release_movement_actions()
	fixture.queue_free()
	await tree.process_frame


func _release_movement_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("jump")
	Input.action_release("crouch")
	Input.action_release("sprint")
