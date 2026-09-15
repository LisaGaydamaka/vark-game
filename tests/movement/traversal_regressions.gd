extends RefCounted


const LedgeTraversalFixture = preload(
	"res://tests/movement/fixtures/ledge_traversal.tscn"
)

const PLAYER_START_POSITION := Vector3(0.0, 0.5, -0.3)
const ENTER_HANG_MAX_FRAMES: int = 90
const HANG_STABILITY_FRAMES: int = 6
const HANG_POSITION_TOLERANCE: float = 0.025
const SHIMMY_DIRECTION_FRAMES: int = 10
const SHIMMY_MINIMUM_PROGRESS: float = 0.08
const CORNER_APPROACH_FRAMES: int = 60
const CORNER_TRANSITION_MAX_FRAMES: int = 60
const CORNER_MINIMUM_SIDE_X: float = 1.25
const CORNER_MINIMUM_INWARD_Z: float = -1.0
const MANTLE_MAX_FRAMES: int = 90
const MANTLE_MINIMUM_TOP_Y: float = 1.58
const COMPLETION_VELOCITY_TOLERANCE: float = 0.05
const DROP_GUARD_CLEAR_Y: float = -0.6
const DROP_GUARD_MAX_FRAMES: int = 60


var tree: SceneTree


func _init(test_tree: SceneTree) -> void:
	tree = test_tree


func run(helpers: RefCounted) -> void:
	await _test_ledge_catch_hang_release(helpers)
	await _test_ledge_shimmy_supported_corner(helpers)
	await _test_ledge_mantle(helpers)
	await _test_drop_regrab_suppression(helpers)


func _test_ledge_catch_hang_release(helpers: RefCounted) -> void:
	_release_movement_actions()

	var fixture: Node3D = LedgeTraversalFixture.instantiate()
	tree.get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	var controller: PlayerLedgeController = player.get("ledge_controller")

	var transition: Dictionary = await _wait_for_hang(player, controller)
	var reached_hang: bool = bool(transition.get("reached_hang", false))
	var saw_catching: bool = bool(transition.get("saw_catching", false))
	helpers.assert_true(
		saw_catching,
		"Normal falling ledge approach enters the real catch transition"
	)
	helpers.assert_true(
		reached_hang,
		"Normal falling ledge approach settles into a hang"
	)

	if reached_hang:
		var stable_position: Vector3 = player.global_position
		for _frame: int in range(HANG_STABILITY_FRAMES):
			await _completed_physics_frame()
		helpers.assert_true(
			controller.state == PlayerLedgeController.State.HANGING
			and player.global_position.distance_to(stable_position)
			<= HANG_POSITION_TOLERANCE
			and not bool(player.call("is_grounded")),
			"Hang remains attached without support/step drift"
		)

		var hang_y: float = player.global_position.y
		Input.action_press("crouch")
		await _completed_physics_frame()
		Input.action_release("crouch")
		helpers.assert_true(
			controller.state == PlayerLedgeController.State.NONE
			and player.velocity.y < 0.0
			and player.global_position.y < hang_y,
			"Crouch releases the hang cleanly into falling motion"
		)

	await _cleanup_fixture(fixture)


func _test_ledge_shimmy_supported_corner(helpers: RefCounted) -> void:
	_release_movement_actions()

	var fixture: Node3D = LedgeTraversalFixture.instantiate()
	tree.get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	var controller: PlayerLedgeController = player.get("ledge_controller")

	var transition: Dictionary = await _wait_for_hang(player, controller)
	var reached_hang: bool = bool(transition.get("reached_hang", false))
	helpers.assert_true(reached_hang, "Shimmy fixture reaches its starting hang")
	if not reached_hang:
		await _cleanup_fixture(fixture)
		return

	var start_x: float = player.global_position.x
	Input.action_press("move_right")
	for _frame: int in range(SHIMMY_DIRECTION_FRAMES):
		await _completed_physics_frame()
	Input.action_release("move_right")
	var right_x: float = player.global_position.x
	helpers.assert_true(
		right_x >= start_x + SHIMMY_MINIMUM_PROGRESS,
		"Hang shimmies right along the real ledge"
	)

	Input.action_press("move_left")
	for _frame: int in range(SHIMMY_DIRECTION_FRAMES):
		await _completed_physics_frame()
	Input.action_release("move_left")
	var left_x: float = player.global_position.x
	helpers.assert_true(
		left_x <= right_x - SHIMMY_MINIMUM_PROGRESS,
		"Hang shimmies left along the real ledge"
	)

	# Hold toward the physical end of the front ledge. PlayerLedgeHang requires
	# the endpoint input to be released and deliberately re-pressed before it
	# asks the corner system to continue around a supported corner.
	Input.action_press("move_right")
	for _frame: int in range(CORNER_APPROACH_FRAMES):
		await _completed_physics_frame()
	Input.action_release("move_right")
	await _completed_physics_frame()
	await _completed_physics_frame()

	Input.action_press("move_right")
	var saw_cornering: bool = false
	var completed_corner: bool = false
	for _frame: int in range(CORNER_TRANSITION_MAX_FRAMES):
		await _completed_physics_frame()
		if controller.state == PlayerLedgeController.State.CORNERING:
			saw_cornering = true
		if (
			saw_cornering
			and controller.state == PlayerLedgeController.State.HANGING
		):
			completed_corner = true
			break
	Input.action_release("move_right")

	helpers.assert_true(
		saw_cornering and completed_corner,
		"Supported right-angle ledge corner transitions back into hanging"
	)
	if completed_corner:
		helpers.assert_true(
			player.global_position.x >= CORNER_MINIMUM_SIDE_X
			and player.global_position.z <= CORNER_MINIMUM_INWARD_Z,
			"Supported corner finishes attached to the adjoining ledge face"
		)

	await _cleanup_fixture(fixture)


func _test_ledge_mantle(helpers: RefCounted) -> void:
	_release_movement_actions()

	var fixture: Node3D = LedgeTraversalFixture.instantiate()
	tree.get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	var controller: PlayerLedgeController = player.get("ledge_controller")

	var transition: Dictionary = await _wait_for_hang(player, controller)
	var reached_hang: bool = bool(transition.get("reached_hang", false))
	helpers.assert_true(reached_hang, "Mantle fixture reaches its starting hang")
	if not reached_hang:
		await _cleanup_fixture(fixture)
		return

	Input.action_press("jump")
	await _completed_physics_frame()
	Input.action_release("jump")

	var saw_mantling: bool = (
		controller.state == PlayerLedgeController.State.MANTLING
	)
	var completed_mantle: bool = false
	for _frame: int in range(MANTLE_MAX_FRAMES):
		await _completed_physics_frame()
		if controller.state == PlayerLedgeController.State.MANTLING:
			saw_mantling = true
		if (
			saw_mantling
			and controller.state == PlayerLedgeController.State.NONE
			and bool(player.call("is_grounded"))
		):
			completed_mantle = true
			break

	helpers.assert_true(
		saw_mantling and completed_mantle,
		"No-input jump from hang mantles onto the valid ledge top"
	)
	if completed_mantle:
		helpers.assert_true(
			player.global_position.y >= MANTLE_MINIMUM_TOP_Y
			and player.velocity.length() <= COMPLETION_VELOCITY_TOLERANCE,
			"Successful mantle ends supported on top without stale traversal velocity"
		)

	await _cleanup_fixture(fixture)


func _test_drop_regrab_suppression(helpers: RefCounted) -> void:
	_release_movement_actions()

	var fixture: Node3D = LedgeTraversalFixture.instantiate()
	tree.get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	var controller: PlayerLedgeController = player.get("ledge_controller")

	var transition: Dictionary = await _wait_for_hang(player, controller)
	var reached_hang: bool = bool(transition.get("reached_hang", false))
	helpers.assert_true(
		reached_hang,
		"Drop/regrab fixture reaches its starting hang"
	)
	if not reached_hang:
		await _cleanup_fixture(fixture)
		return

	Input.action_press("crouch")
	await _completed_physics_frame()
	Input.action_release("crouch")

	var illegitimate_regrab: bool = false
	var left_guard_region: bool = false
	for _frame: int in range(DROP_GUARD_MAX_FRAMES):
		await _completed_physics_frame()
		if player.global_position.y > DROP_GUARD_CLEAR_Y and controller.is_active():
			illegitimate_regrab = true
			break
		if player.global_position.y <= DROP_GUARD_CLEAR_Y:
			left_guard_region = true
			# The guard updates before movement. Give it one more completed frame
			# at the clearly separated pose so the old local ledge is re-armed.
			await _completed_physics_frame()
			break

	helpers.assert_true(
		not illegitimate_regrab and left_guard_region,
		"Dropping suppresses immediate regrab of the same local ledge"
	)

	var later_regrab: bool = false
	if not illegitimate_regrab and left_guard_region:
		player.global_position = PLAYER_START_POSITION
		player.velocity = Vector3.ZERO
		var velocity_state: PlayerVelocityState = player.get("velocity_state")
		velocity_state.capture_body_as_controlled(player)
		var regrab_transition: Dictionary = await _wait_for_hang(player, controller)
		later_regrab = bool(regrab_transition.get("reached_hang", false))

	helpers.assert_true(
		later_regrab,
		"After leaving the suppression region, a later legitimate regrab works"
	)

	await _cleanup_fixture(fixture)


func _wait_for_hang(
	player: CharacterBody3D,
	controller: PlayerLedgeController
) -> Dictionary:
	var saw_catching: bool = false
	for _frame: int in range(ENTER_HANG_MAX_FRAMES):
		await _completed_physics_frame()
		if controller.state == PlayerLedgeController.State.CATCHING:
			saw_catching = true
		if controller.state == PlayerLedgeController.State.HANGING:
			return {
				"reached_hang": true,
				"saw_catching": saw_catching,
			}
		# Once the player has fallen far below this small fixture, no later catch
		# is possible in the same attempt; keep failures fast and deterministic.
		if player.global_position.y < -2.0:
			break
	return {
		"reached_hang": false,
		"saw_catching": saw_catching,
	}


func _completed_physics_frame() -> void:
	await tree.physics_frame
	# physics_frame is emitted before node _physics_process callbacks. Waiting
	# for the process frame lets tests inspect the completed physics-frame pose.
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
