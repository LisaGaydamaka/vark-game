extends SceneTree


const TestHelpers = preload("res://tests/movement/test_helpers.gd")
const WalkOffEdgeFixture = preload(
	"res://tests/movement/fixtures/walk_off_edge.tscn"
)
const INTENTIONAL_FAILURE_ARG: String = "--intentional-failure"
const WALK_OFF_MAX_PHYSICS_FRAMES: int = 120
const EDGE_CLEARANCE_MARGIN: float = 0.01


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var helpers: RefCounted = TestHelpers.new()
	helpers.assert_true(1 + 1 == 2, "Test framework works")
	await _test_walk_off_edge(helpers)

	if INTENTIONAL_FAILURE_ARG in OS.get_cmdline_user_args():
		helpers.assert_true(false, "Intentional failure path")

	helpers.print_summary()
	quit(1 if helpers.has_failures() else 0)


func _test_walk_off_edge(helpers: RefCounted) -> void:
	Input.action_release("move_forward")

	var fixture: Node3D = WalkOffEdgeFixture.instantiate()
	get_root().add_child(fixture)
	var player: CharacterBody3D = fixture.get_node("Player")
	var platform_edge: Node3D = fixture.get_node("PlatformEdge")

	# Let the real Player initialize and establish support on the platform.
	for _frame: int in range(3):
		await physics_frame
		await process_frame

	var started_grounded: bool = bool(player.call("is_grounded"))
	helpers.assert_true(
		started_grounded,
		"Walk-off fixture starts grounded"
	)
	if not started_grounded:
		fixture.queue_free()
		await process_frame
		return

	var collision_shape: CollisionShape3D = player.get_node("CollisionShape3D")
	var capsule_shape := collision_shape.shape as CapsuleShape3D
	helpers.assert_true(
		capsule_shape != null,
		"Walk-off fixture uses the real player capsule"
	)
	if capsule_shape == null:
		fixture.queue_free()
		await process_frame
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
		await physics_frame
		# physics_frame is emitted before node _physics_process callbacks. Waiting
		# for the process frame lets us inspect the completed physics-frame pose.
		await process_frame
		if player.global_position.z > unsupported_threshold_z:
			continue
		reached_clear_air = true
		grounded_in_clear_air = bool(player.call("is_grounded"))
		break
	Input.action_release("move_forward")

	helpers.assert_true(
		reached_clear_air,
		"Walk-off fixture reaches clear air beyond the platform edge"
	)
	if reached_clear_air:
		helpers.assert_true(
			not grounded_in_clear_air,
			"Walking off edge loses support on the final moved pose"
		)

	fixture.queue_free()
	await process_frame
