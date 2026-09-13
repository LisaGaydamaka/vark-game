extends SceneTree


const TestHelpers = preload("res://tests/movement/test_helpers.gd")
const WalkOffEdgeFixture = preload(
	"res://tests/movement/fixtures/walk_off_edge.tscn"
)
const SprintJumpFixture = preload(
	"res://tests/movement/fixtures/sprint_jump.tscn"
)
const NormalStepFixture = preload(
	"res://tests/movement/fixtures/normal_step.tscn"
)
const FloatingStepFixture = preload(
	"res://tests/movement/fixtures/floating_step.tscn"
)
const WallSeamFallFixture = preload(
	"res://tests/movement/fixtures/wall_seam_fall.tscn"
)
const MultiContactFallFixture = preload(
	"res://tests/movement/fixtures/multi_contact_fall.tscn"
)

const INTENTIONAL_FAILURE_ARG: String = "--intentional-failure"
const SETTLE_PHYSICS_FRAMES: int = 3
const WALK_OFF_MAX_PHYSICS_FRAMES: int = 120
const EDGE_CLEARANCE_MARGIN: float = 0.01
const SPRINT_ACCELERATION_FRAMES: int = 30
const SPRINT_SPEED_TOLERANCE: float = 0.1
const SPRINT_MOMENTUM_TOLERANCE: float = 0.05
const STEP_MAX_PHYSICS_FRAMES: int = 100
const STEP_HEIGHT_TOLERANCE: float = 0.04
const STEP_PROGRESS_Z: float = -0.55
const WALL_SEAM_MAX_PHYSICS_FRAMES: int = 90
const WALL_SEAM_CONTINUATION_FRAMES: int = 8
const FALL_PROGRESS_TOLERANCE: float = 0.05
const MULTI_CONTACT_FRAMES: int = 30
const MULTI_CONTACT_MINIMUM_FALL: float = 0.2


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var helpers: RefCounted = TestHelpers.new()
	helpers.assert_true(1 + 1 == 2, "Test framework works")

	await _test_walk_off_edge(helpers)
	await _test_sprint_jump_momentum(helpers)
	await _test_normal_step(helpers)
	await _test_floating_step(helpers)
	await _test_wall_seam_fall(helpers)
	await _test_multi_contact_fall(helpers)

	if INTENTIONAL_FAILURE_ARG in OS.get_cmdline_user_args():
		helpers.assert_true(false, "Intentional failure path")

	helpers.print_summary()
	quit(1 if helpers.has_failures() else 0)


func _test_walk_off_edge(helpers: RefCounted) -> void:
	_release_movement_actions()

	var fixture: Node3D = WalkOffEdgeFixture.instantiate()
	get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	var platform_edge: Node3D = fixture.get_node("PlatformEdge")

	await _settle_physics()

	var started_grounded: bool = bool(player.call("is_grounded"))
	helpers.assert_true(
		started_grounded,
		"Walk-off fixture starts grounded"
	)
	if not started_grounded:
		await _cleanup_fixture(fixture)
		return

	var collision_shape: CollisionShape3D = player.get_node("CollisionShape3D")
	var capsule_shape := collision_shape.shape as CapsuleShape3D
	helpers.assert_true(
		capsule_shape != null,
		"Walk-off fixture uses the real player capsule"
	)
	if capsule_shape == null:
		await _cleanup_fixture(fixture)
		return

	# The platform ends at PlatformEdge. Once the capsule center is more than
	# one capsule radius beyond that edge, neither the footprint probes nor the
	# capsule itself can still be supported by the platform. The support snapshot
	# from that completed movement frame must therefore already be airborne.
	var unsupported_threshold_z: float = (
		platform_edge.global_position.z
		- capsule_shape.radius
		- EDGE_CLEARANCE_MARGIN
	)
	var reached_clear_air: bool = false
	var grounded_in_clear_air: bool = false

	Input.action_press("move_forward")
	for _frame: int in range(WALK_OFF_MAX_PHYSICS_FRAMES):
		await _completed_physics_frame()
		if player.global_position.z > unsupported_threshold_z:
			continue
		reached_clear_air = true
		grounded_in_clear_air = bool(player.call("is_grounded"))
		break

	helpers.assert_true(
		reached_clear_air,
		"Walk-off fixture reaches clear air beyond the platform edge"
	)
	if reached_clear_air:
		helpers.assert_true(
			not grounded_in_clear_air,
			"Walking off edge loses support on the final moved pose"
		)

	await _cleanup_fixture(fixture)


func _test_sprint_jump_momentum(helpers: RefCounted) -> void:
	_release_movement_actions()

	var fixture: Node3D = SprintJumpFixture.instantiate()
	get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	await _settle_physics()

	var started_grounded: bool = bool(player.call("is_grounded"))
	helpers.assert_true(started_grounded, "Sprint-jump fixture starts grounded")
	if not started_grounded:
		await _cleanup_fixture(fixture)
		return

	Input.action_press("move_forward")
	Input.action_press("sprint")
	for _frame: int in range(SPRINT_ACCELERATION_FRAMES):
		await _completed_physics_frame()

	var settings := player.get("locomotion_settings") as PlayerLocomotionSettings
	var normal_run_speed: float = (
		settings.max_speed if settings != null else 3.0
	)
	var before_jump_speed: float = _horizontal_speed(player.velocity)
	helpers.assert_true(
		before_jump_speed > normal_run_speed + SPRINT_SPEED_TOLERANCE,
		"Sprint-jump fixture exceeds normal running speed before takeoff"
	)

	Input.action_press("jump")
	await _completed_physics_frame()
	Input.action_release("jump")

	var after_jump_speed: float = _horizontal_speed(player.velocity)
	helpers.assert_true(
		not bool(player.call("is_grounded")) and player.velocity.y > 0.0,
		"Sprint-jump fixture actually takes off"
	)
	helpers.assert_true(
		after_jump_speed >= before_jump_speed - SPRINT_MOMENTUM_TOLERANCE,
		"Sprint jump preserves inherited horizontal momentum"
	)

	await _cleanup_fixture(fixture)


func _test_normal_step(helpers: RefCounted) -> void:
	await _test_step_fixture(
		helpers,
		NormalStepFixture,
		0.25,
		"Normal step is acquired and crossed"
	)


func _test_floating_step(helpers: RefCounted) -> void:
	# This reproduces the old undercut case: a 0.125 m block whose bottom is
	# 0.0625 m above the source floor. It is a valid support-to-support step even
	# though no solid riser reaches all the way down to the source floor.
	await _test_step_fixture(
		helpers,
		FloatingStepFixture,
		0.1875,
		"Floating/undercut step is acquired and crossed"
	)


func _test_step_fixture(
	helpers: RefCounted,
	fixture_scene: PackedScene,
	expected_top_y: float,
	message: String
) -> void:
	_release_movement_actions()

	var fixture: Node3D = fixture_scene.instantiate()
	get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	await _settle_physics()

	var started_grounded: bool = bool(player.call("is_grounded"))
	if not started_grounded:
		helpers.assert_true(false, message + " (fixture did not start grounded)")
		await _cleanup_fixture(fixture)
		return

	var maximum_y: float = player.global_position.y
	var furthest_z: float = player.global_position.z
	Input.action_press("move_forward")
	for _frame: int in range(STEP_MAX_PHYSICS_FRAMES):
		await _completed_physics_frame()
		maximum_y = maxf(maximum_y, player.global_position.y)
		furthest_z = minf(furthest_z, player.global_position.z)
		if (
			maximum_y >= expected_top_y - STEP_HEIGHT_TOLERANCE
			and furthest_z <= STEP_PROGRESS_Z
		):
			break

	var climbed_step: bool = (
		maximum_y >= expected_top_y - STEP_HEIGHT_TOLERANCE
	)
	var crossed_step: bool = furthest_z <= STEP_PROGRESS_Z
	helpers.assert_true(climbed_step and crossed_step, message)

	await _cleanup_fixture(fixture)


func _test_wall_seam_fall(helpers: RefCounted) -> void:
	_release_movement_actions()

	var fixture: Node3D = WallSeamFallFixture.instantiate()
	get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	var seam_marker: Node3D = fixture.get_node("SeamMarker")
	await process_frame

	var reached_below_seam: bool = false
	var y_below_seam: float = player.global_position.y
	var continuation_frames: int = 0
	var final_y: float = player.global_position.y

	Input.action_press("move_forward")
	for _frame: int in range(WALL_SEAM_MAX_PHYSICS_FRAMES):
		await _completed_physics_frame()
		if not reached_below_seam:
			if player.global_position.y >= seam_marker.global_position.y - 0.05:
				continue
			reached_below_seam = true
			y_below_seam = player.global_position.y
			continue

		continuation_frames += 1
		final_y = player.global_position.y
		if continuation_frames >= WALL_SEAM_CONTINUATION_FRAMES:
			break

	helpers.assert_true(
		reached_below_seam,
		"Wall-seam fall reaches below the modular seam"
	)
	if reached_below_seam:
		helpers.assert_true(
			continuation_frames >= WALL_SEAM_CONTINUATION_FRAMES
			and final_y < y_below_seam - FALL_PROGRESS_TOLERANCE
			and player.velocity.y < 0.0
			and not bool(player.call("is_grounded")),
			"Wall seam does not cancel unsupported falling"
		)

	await _cleanup_fixture(fixture)


func _test_multi_contact_fall(helpers: RefCounted) -> void:
	_release_movement_actions()

	var fixture: Node3D = MultiContactFallFixture.instantiate()
	get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	await process_frame

	var start_y: float = player.global_position.y
	Input.action_press("move_left")
	Input.action_press("move_forward")
	for _frame: int in range(MULTI_CONTACT_FRAMES):
		await _completed_physics_frame()

	var fell_distance: float = start_y - player.global_position.y
	helpers.assert_true(
		fell_distance >= MULTI_CONTACT_MINIMUM_FALL
		and player.velocity.y < 0.0,
		"Multi-contact corner preserves unsupported downward motion"
	)
	helpers.assert_true(
		not bool(player.call("is_grounded")),
		"Multi-contact wall corner does not manufacture ground support"
	)

	await _cleanup_fixture(fixture)


func _settle_physics() -> void:
	for _frame: int in range(SETTLE_PHYSICS_FRAMES):
		await _completed_physics_frame()


func _completed_physics_frame() -> void:
	await physics_frame
	# physics_frame is emitted before node _physics_process callbacks. Waiting
	# for the process frame lets tests inspect the completed physics-frame pose.
	await process_frame


func _cleanup_fixture(fixture: Node) -> void:
	_release_movement_actions()
	fixture.queue_free()
	await process_frame


func _release_movement_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("jump")
	Input.action_release("crouch")
	Input.action_release("sprint")


func _horizontal_speed(velocity: Vector3) -> float:
	return Vector2(velocity.x, velocity.z).length()
