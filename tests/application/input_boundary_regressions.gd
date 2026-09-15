extends RefCounted


const InputBoundary = preload(
	"res://application/application_input_boundary.gd"
)


func run(
	tree: SceneTree,
	application: Node,
	assert_true: Callable
) -> void:
	var boundary: Node = application.get_node("InputBoundary")
	var player: Node = application.get("current_player") as Node

	assert_true.call(
		boundary.get("current_player") == player
		and bool(boundary.get("gameplay_enabled"))
		and bool(boundary.get("look_enabled"))
		and player.get("gameplay_input_boundary") == boundary,
		"Application owns the production gameplay/look input boundary"
	)

	# Keep the live application player neutral while the standalone boundary
	# probe manipulates global Input actions to verify frame semantics.
	assert_true.call(
		bool(application.call("set_gameplay_input_enabled", false)),
		"Application can suppress gameplay intent independently of look input"
	)
	await _test_gameplay_frame_lifetime(tree, assert_true)
	assert_true.call(
		bool(application.call("set_gameplay_input_enabled", true)),
		"Application can restore gameplay intent for the active PLAYING session"
	)

	await _test_domain_loss_cancels_gesture(application, player, assert_true)
	_test_event_cadence_look_and_view_pose(application, boundary, assert_true)


func _test_gameplay_frame_lifetime(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	_release_actions()
	var probe: Node = InputBoundary.new()
	probe.call("set_gameplay_enabled", true)

	Input.action_press("move_forward")
	Input.action_press("sprint")
	Input.action_press("jump")
	var first: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	assert_true.call(
		first.movement_vector.y < -0.9
		and first.sprint_held
		and first.jump_pressed
		and first.jump_held,
		"Gameplay intent frame samples held state and a fresh press together"
	)

	var same_frame: PlayerCommand = probe.call("sample_locomotion_command") as PlayerCommand
	assert_true.call(
		same_frame == first and same_frame.jump_pressed,
		"Gameplay input is sampled only once for one physics frame"
	)

	var held_next_frame: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	assert_true.call(
		held_next_frame.movement_vector.y < -0.9
		and held_next_frame.sprint_held
		and held_next_frame.jump_held
		and not held_next_frame.jump_pressed,
		"Held gameplay state persists while the pressed edge lasts one gameplay frame"
	)

	probe.call("set_gameplay_enabled", false)
	var disabled: PlayerCommand = probe.call("sample_locomotion_command") as PlayerCommand
	assert_true.call(
		disabled.movement_vector == Vector2.ZERO
		and not disabled.sprint_held
		and not disabled.jump_pressed
		and not disabled.jump_held,
		"Disabled gameplay domain produces a neutral intent frame"
	)

	probe.call("set_gameplay_enabled", true)
	var resumed_while_held: PlayerCommand = probe.call("sample_locomotion_command") as PlayerCommand
	assert_true.call(
		resumed_while_held.movement_vector.y < -0.9
		and resumed_while_held.sprint_held
		and not resumed_while_held.jump_pressed
		and not resumed_while_held.jump_held,
		"Domain resume restores continuous intent but does not replay an edge-dependent held gesture"
	)

	Input.action_release("jump")
	var released: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	assert_true.call(
		not released.jump_pressed and not released.jump_held,
		"Releasing after domain loss clears the blocked edge-dependent gesture"
	)

	Input.action_press("jump")
	var fresh_press: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	assert_true.call(
		fresh_press.jump_pressed and fresh_press.jump_held,
		"A fresh post-resume press creates a new gameplay edge"
	)

	var edge_expired: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	assert_true.call(
		not edge_expired.jump_pressed and edge_expired.jump_held,
		"Fresh gameplay press edge expires after one physics frame"
	)

	_release_actions()
	probe.free()


func _test_domain_loss_cancels_gesture(
	application: Node,
	player: Node,
	assert_true: Callable
) -> void:
	var locomotion_controller: RefCounted = player.get("locomotion_controller") as RefCounted
	locomotion_controller.set("air_mantle_intent_active", true)

	var disabled: bool = bool(application.call("set_gameplay_input_enabled", false))
	assert_true.call(
		disabled
		and not bool(locomotion_controller.get("air_mantle_intent_active")),
		"Application domain loss cancels incomplete edge-dependent locomotion gesture state"
	)

	assert_true.call(
		bool(application.call("set_gameplay_input_enabled", true)),
		"Application can restore gameplay input only for the active PLAYING session"
	)


func _test_event_cadence_look_and_view_pose(
	application: Node,
	boundary: Node,
	assert_true: Callable
) -> void:
	var before: Dictionary = application.call("get_current_view_pose")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(9.0, -4.0)
	boundary.call("route_input_event", motion)
	var after: Dictionary = application.call("get_current_view_pose")

	assert_true.call(
		absf(float(after.get("body_yaw", 0.0)) - float(before.get("body_yaw", 0.0))) > 0.0001
		and absf(float(after.get("head_pitch", 0.0)) - float(before.get("head_pitch", 0.0))) > 0.0001,
		"Look input updates the input-owned view pose immediately without waiting for a physics tick"
	)

	var detached: Dictionary = after
	detached["body_yaw"] = 123.0
	var resampled: Dictionary = application.call("get_current_view_pose")
	assert_true.call(
		absf(float(resampled.get("body_yaw", 0.0)) - 123.0) > 1.0,
		"Application view-pose sampling returns detached value-owned data"
	)

	var inverse_motion := InputEventMouseMotion.new()
	inverse_motion.relative = -motion.relative
	boundary.call("route_input_event", inverse_motion)

	assert_true.call(
		bool(application.call("set_look_input_enabled", false)),
		"Application can disable the look domain independently of gameplay"
	)
	var disabled_before: Dictionary = application.call("get_current_view_pose")
	boundary.call("route_input_event", motion)
	var disabled_after: Dictionary = application.call("get_current_view_pose")
	assert_true.call(
		is_equal_approx(
			float(disabled_before.get("body_yaw", 0.0)),
			float(disabled_after.get("body_yaw", 0.0))
		)
		and is_equal_approx(
			float(disabled_before.get("head_pitch", 0.0)),
			float(disabled_after.get("head_pitch", 0.0))
		),
		"Disabled look domain does not mutate the current view pose"
	)
	assert_true.call(
		bool(application.call("set_look_input_enabled", true)),
		"Application can restore event-cadence look for the active PLAYING session"
	)


func _sample_on_next_physics_frame(
	tree: SceneTree,
	boundary: Node
) -> PlayerCommand:
	await tree.physics_frame
	return boundary.call("sample_locomotion_command") as PlayerCommand


func _release_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("jump")
	Input.action_release("crouch")
	Input.action_release("sprint")
