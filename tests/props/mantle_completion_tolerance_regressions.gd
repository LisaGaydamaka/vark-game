extends RefCounted


const LedgeTraversalFixture = preload(
	"res://tests/movement/fixtures/ledge_traversal.tscn"
)

const ENTER_HANG_MAX_FRAMES: int = 90
const FORWARD_PHASE_MAX_FRAMES: int = 90
const MICRO_TRAVERSAL_SPEED: float = 0.0001
const SUB_TOLERANCE_FRACTION: float = 0.5


func run(tree: SceneTree, assert_true: Callable) -> void:
	_release_movement_actions()

	var fixture: Node3D = LedgeTraversalFixture.instantiate()
	tree.get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player") as CharacterBody3D
	var controller: PlayerLedgeController = player.get("ledge_controller") as PlayerLedgeController
	var mantle: PlayerMantle = player.get("ledge_mantle") as PlayerMantle

	var reached_hang: bool = await _wait_for_hang(tree, player, controller)
	assert_true.call(
		reached_hang,
		"Mantle completion-tolerance fixture reaches the real hanging state"
	)
	if not reached_hang or mantle == null:
		await _cleanup_fixture(tree, fixture)
		return

	Input.action_press("jump")
	await _completed_physics_frame(tree)
	Input.action_release("jump")

	var reached_forward_phase: bool = false
	for _frame: int in range(FORWARD_PHASE_MAX_FRAMES):
		if (
			controller.state == PlayerLedgeController.State.MANTLING
			and mantle.phase == PlayerMantle.Phase.FORWARD
		):
			reached_forward_phase = true
			break
		if controller.state == PlayerLedgeController.State.NONE:
			break
		await _completed_physics_frame(tree)

	assert_true.call(
		reached_forward_phase,
		"Mantle completion-tolerance fixture reaches the production forward phase"
	)
	if not reached_forward_phase or mantle.active_candidate == null:
		await _cleanup_fixture(tree, fixture)
		return

	var route_tolerance: float = mantle.get_route_progress_tolerance()
	var current_outward: float = mantle.get_outward_distance(player.global_position)
	var desired_outward: float = route_tolerance * SUB_TOLERANCE_FRACTION
	var wall_normal: Vector3 = mantle.active_candidate.wall_normal
	player.global_position += wall_normal * (desired_outward - current_outward)

	var positioned_outward: float = mantle.get_outward_distance(player.global_position)
	assert_true.call(
		positioned_outward > 0.0
		and positioned_outward <= route_tolerance
		and mantle.has_reached_forward_limit(player.global_position),
		"A positive sub-tolerance forward remainder already counts as mantle completion"
	)

	# Keep any extra traversal motion microscopic. Before the fix, the forward
	# phase could remain owned forever when contact left this same positive
	# sub-tolerance remainder: it was too small to classify as blocked, but exact
	# zero was still required for completion.
	var previous_traversal_speed: float = mantle.traversal_speed
	mantle.traversal_speed = MICRO_TRAVERSAL_SPEED
	await _completed_physics_frame(tree)
	mantle.traversal_speed = previous_traversal_speed

	assert_true.call(
		controller.state == PlayerLedgeController.State.NONE
		and not mantle.is_active(),
		"Sub-tolerance forward completion releases traversal ownership on the next physics frame"
	)

	await _cleanup_fixture(tree, fixture)


func _wait_for_hang(
	tree: SceneTree,
	player: CharacterBody3D,
	controller: PlayerLedgeController
) -> bool:
	for _frame: int in range(ENTER_HANG_MAX_FRAMES):
		await _completed_physics_frame(tree)
		if controller.state == PlayerLedgeController.State.HANGING:
			return true
		if player.global_position.y < -2.0:
			break
	return false


func _completed_physics_frame(tree: SceneTree) -> void:
	await tree.physics_frame
	# physics_frame is emitted before node _physics_process callbacks. Waiting
	# for process_frame makes the observed state belong to the completed tick.
	await tree.process_frame


func _cleanup_fixture(tree: SceneTree, fixture: Node) -> void:
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
