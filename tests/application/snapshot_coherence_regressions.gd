extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")
const WorldSession = preload("res://application/world_session.gd")
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"
const FLOAT_TOLERANCE: float = 0.0001


func run(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	await _prove_stable_boundary_coherence_and_restore_suppression(
		tree,
		assert_true
	)
	await _prove_source_binding_and_operation_exclusion(
		tree,
		assert_true
	)
	await _prove_restore_failure_safety(tree, assert_true)


func _prove_stable_boundary_coherence_and_restore_suppression(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_slice(tree)
	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var session := application.get("current_session") as Node
	var coordinator: Node = application.get_node("SaveCoordinator")
	var boundary: Node = application.get_node("InputBoundary")
	var guard := world.get_node("Guard") as VarkGuard
	var door := world.get_node("OrdinaryDoor") as VarkOrdinaryDoor
	var light := world.get_node("NorthGameplayLight") as VarkGameplayLight
	var exposure := world.get_node("GameplayExposure") as VarkGameplayExposure
	var objective := world.get_node(
		"ObjectiveState"
	) as VarkSimpleObjectiveState
	var objective_trigger := world.get_node(
		"ObjectiveTrigger"
	) as VarkSemanticRouteTrigger
	var exit_trigger := world.get_node(
		"ExitTrigger"
	) as VarkSemanticRouteTrigger
	var reaction: Node = world.get_node("Guard/Reaction")

	guard.movement_speed = 0.0
	guard.velocity = Vector3.ZERO
	light.gameplay_enabled = false
	light.visible = false
	exposure.sample_now()
	player.velocity = Vector3.ZERO

	var pose_before_look: Dictionary = application.call(
		"get_current_view_pose"
	)
	var look_motion := InputEventMouseMotion.new()
	look_motion.relative = Vector2(17.0, -7.0)
	boundary.call("route_input_event", look_motion)
	var pose_at_request: Dictionary = application.call(
		"get_current_view_pose"
	)
	var player_transform_at_request: Transform3D = player.global_transform
	var player_yaw_at_request: float = player.rotation.y
	var serial_before: int = int(
		session.call("get_stable_gameplay_boundary_serial")
	)

	# Queue multiple consequences before the requested boundary. Exit is first,
	# so it must record one blocked attempt before the objective completion in
	# the same controlled consequence pass. Sound perception joins that pass.
	var exit_queued: bool = exit_trigger.queue_for_body(player)
	var objective_queued: bool = objective_trigger.queue_for_body(player)
	var sound_queued: bool = bool(session.call(
		"queue_semantic_gameplay_event",
		int(session.get("session_id")),
		&"gameplay.sound",
		{
			"kind": &"footstep.stone",
			"origin": guard.global_position,
			"strength": 4.0,
		}
	))
	door.request_open(player)

	var generation: int = int(
		application.call("request_quicksave")
	)
	var committed: bool = await _wait_for_save_status(
		tree,
		coordinator,
		generation,
		&"committed",
		30
	)
	var snapshot: Dictionary = coordinator.call(
		"get_request_snapshot",
		generation
	)
	var envelope: Dictionary = snapshot.get("session", {})
	var world_state: Dictionary = envelope.get("world_state", {})
	var persistent: Dictionary = world_state.get(
		"persistent_entities",
		{}
	)
	var semantic: Dictionary = world_state.get(
		"semantic_owners",
		{}
	)
	var saved_player: Dictionary = world_state.get("player", {})
	var saved_door: Dictionary = persistent.get("slice.door", {})
	var objective_id: String = str(
		objective.get_semantic_save_id()
	)
	var trigger_id: String = str(
		objective_trigger.get_semantic_save_id()
	)
	var reaction_id: String = str(
		reaction.call("get_semantic_save_id")
	)
	var saved_objective: Dictionary = semantic.get(
		objective_id,
		{}
	)
	var saved_trigger: Dictionary = semantic.get(
		trigger_id,
		{}
	)
	var saved_reaction: Dictionary = semantic.get(
		reaction_id,
		{}
	)
	var captured_pose: Dictionary = snapshot.get(
		"player_view_pose",
		{}
	)
	var saved_player_transform: Transform3D = saved_player.get(
		"transform",
		Transform3D.IDENTITY
	)

	assert_true.call(
		not is_equal_approx(
			float(pose_before_look.get("body_yaw", 0.0)),
			float(pose_at_request.get("body_yaw", 0.0))
		)
		and is_equal_approx(
			player_yaw_at_request,
			float(pose_at_request.get("body_yaw", 0.0))
		),
		"Phase 4.5 input-owned look mutates the live player/view pose immediately before any save physics boundary"
	)
	assert_true.call(
		exit_queued
		and objective_queued
		and sound_queued
		and generation > 0
		and committed
		and int(envelope.get("stable_boundary_serial", 0))
			== serial_before + 1
		and bool(saved_objective.get(
			"objective_complete",
			false
		))
		and int(saved_objective.get(
			"blocked_exit_count",
			0
		)) == 1
		and not bool(saved_objective.get(
			"mission_complete",
			true
		))
		and not bool(saved_trigger.get("armed", true))
		and saved_reaction.get("state", &"") == &"investigating"
		and int(saved_reaction.get("heard_count", 0)) >= 1
		and saved_door.get("phase", &"")
			== VarkOrdinaryDoor.PHASE_OPENING
		and float(saved_door.get("open_fraction", 0.0)) > 0.0,
		"Phase 4.5 one save request captures several ordered systems only after one completed stable semantic boundary"
	)
	assert_true.call(
		is_equal_approx(
			float(captured_pose.get("body_yaw", 0.0)),
			float(pose_at_request.get("body_yaw", 0.0))
		)
		and is_equal_approx(
			float(captured_pose.get("head_pitch", 0.0)),
			float(pose_at_request.get("head_pitch", 0.0))
		)
		and _basis_close(
			saved_player_transform.basis,
			player_transform_at_request.basis
		),
		"Phase 4.5 captured view pose and player world orientation describe the same coherent request-side pose"
	)

	# Move every representative owner away from the captured truth before load.
	door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_CLOSED,
		"open_fraction": 0.0,
		"motion_blocked": false,
	})
	var second_sound_queued: bool = bool(session.call(
		"queue_semantic_gameplay_event",
		int(session.get("session_id")),
		&"gameplay.sound",
		{
			"kind": &"footstep.stone",
			"origin": guard.global_position,
			"strength": 4.0,
		}
	))
	await _completed_physics_frame(tree)
	var mutated_reaction: Dictionary = reaction.call(
		"get_debug_summary"
	)
	var old_session: Node = session
	var restored: bool = bool(
		application.call("restore_snapshot", snapshot)
	)

	world = application.get("current_world") as Node3D
	session = application.get("current_session") as Node
	objective = world.get_node(
		"ObjectiveState"
	) as VarkSimpleObjectiveState
	objective_trigger = world.get_node(
		"ObjectiveTrigger"
	) as VarkSemanticRouteTrigger
	reaction = world.get_node("Guard/Reaction")
	door = world.get_node("OrdinaryDoor") as VarkOrdinaryDoor
	var restored_objective: Dictionary = objective.capture_semantic_state()
	var restored_trigger: Dictionary = objective_trigger.capture_semantic_state()
	var restored_reaction: Dictionary = reaction.call(
		"capture_semantic_state"
	)
	var restored_pose: Dictionary = application.call(
		"get_current_view_pose"
	)

	assert_true.call(
		second_sound_queued
		and int(mutated_reaction.get("heard_count", 0))
			> int(saved_reaction.get("heard_count", 0))
		and restored
		and not is_instance_valid(old_session)
		and application.get_node("WorldHost").get_child_count() == 1
		and restored_objective == saved_objective
		and restored_trigger == saved_trigger
		and restored_reaction == saved_reaction
		and int(session.call(
			"get_pending_semantic_event_count"
		)) == 0
		and door.get_semantic_phase()
			== VarkOrdinaryDoor.PHASE_OPENING
		and absf(
			door.get_open_fraction()
			- float(saved_door.get("open_fraction", 0.0))
		) <= FLOAT_TOLERANCE
		and is_equal_approx(
			float(restored_pose.get("body_yaw", 0.0)),
			float(captured_pose.get("body_yaw", 0.0))
		),
		"Phase 4.5 restore/after_restore reconstructs the captured boundary without replaying one-shot objectives, stats, awareness consequences, or queued gameplay events"
	)

	await _cleanup_application(tree, application)


func _prove_source_binding_and_operation_exclusion(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_slice(tree)
	var coordinator: Node = application.get_node("SaveCoordinator")
	var slice_scene := ResourceLoader.load(
		SLICE_PATH
	) as PackedScene

	var source_session: Node = application.get(
		"current_session"
	) as Node
	var source_session_id: int = int(
		application.call("get_current_session_id")
	)
	var transition_generation: int = int(
		application.call("request_quicksave")
	)
	var transitioned: bool = bool(
		application.call("transition_to_world", slice_scene)
	)
	var transition_status: Dictionary = coordinator.call(
		"get_request_status",
		transition_generation
	)
	assert_true.call(
		transition_generation > 0
		and transitioned
		and transition_status.get("status", &"")
			== &"cancelled"
		and int(transition_status.get(
			"source_session_id",
			0
		)) == source_session_id
		and not is_instance_valid(source_session)
		and int(application.call(
			"get_current_session_id"
		)) > source_session_id,
		"Phase 4.5 pending save remains bound to its source session and cancels across mission transition"
	)

	var exit_source_id: int = int(
		application.call("get_current_session_id")
	)
	var exit_generation: int = int(
		application.call("request_quicksave")
	)
	var exited: bool = bool(
		application.call("exit_current_world")
	)
	var exit_status: Dictionary = coordinator.call(
		"get_request_status",
		exit_generation
	)
	assert_true.call(
		exit_generation > 0
		and exited
		and exit_status.get("status", &"")
			== &"cancelled"
		and int(exit_status.get(
			"source_session_id",
			0
		)) == exit_source_id
		and application.get("current_session") == null
		and application.get("current_world") == null
		and application.get("current_player") == null,
		"Phase 4.5 pending save cancels on exit instead of migrating into a future world"
	)

	var relaunched: bool = bool(
		application.call("launch_development_target", 0)
	)
	await _wait_for_navigation_ready(
		tree,
		application.get("current_world") as Node,
		240
	)
	var locked_session: Node = application.get(
		"current_session"
	) as Node
	var snapshot: Dictionary = _capture_snapshot(
		application,
		4501
	)
	var began_lock: bool = bool(application.call(
		"try_begin_top_level_operation",
		ApplicationRoot.TopLevelOperation.RESTART
	))
	var blocked_load: bool = bool(
		application.call("restore_snapshot", snapshot)
	)
	var blocked_restart: bool = bool(
		application.call("restart_current_world")
	)
	var blocked_transition: bool = bool(
		application.call("transition_to_world", slice_scene)
	)
	var blocked_exit: bool = bool(
		application.call("exit_current_world")
	)
	var blocked_save: int = int(
		application.call("request_quicksave")
	)
	var finished_lock: bool = bool(application.call(
		"finish_top_level_operation",
		ApplicationRoot.TopLevelOperation.RESTART
	))
	assert_true.call(
		relaunched
		and began_lock
		and not blocked_load
		and not blocked_restart
		and not blocked_transition
		and not blocked_exit
		and blocked_save == 0
		and application.get("current_session") == locked_session
		and finished_lock
		and not bool(application.call(
			"has_active_top_level_operation"
		)),
		"Phase 4.5 load/restart/transition/exit and save requests cannot race an already-owned top-level world operation"
	)

	await _cleanup_application(tree, application)


func _prove_restore_failure_safety(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_slice(tree)
	var input_boundary: Node = application.get_node(
		"InputBoundary"
	)
	var source_session: Node = application.get(
		"current_session"
	) as Node
	var valid_snapshot: Dictionary = _capture_snapshot(
		application,
		4502
	)

	var malformed_snapshot: Dictionary = valid_snapshot.duplicate(true)
	var malformed_pose: Dictionary = malformed_snapshot.get(
		"player_view_pose",
		{}
	)
	malformed_pose["body_yaw"] = INF
	malformed_snapshot["player_view_pose"] = malformed_pose
	var malformed_rejected: bool = not bool(
		application.call(
			"restore_snapshot",
			malformed_snapshot
		)
	)
	assert_true.call(
		malformed_rejected
		and application.get("current_session") == source_session
		and int(application.call(
			"get_current_session_state"
		)) == WorldSession.State.PLAYING
		and bool(input_boundary.get("gameplay_enabled"))
		and bool(input_boundary.get("look_enabled"))
		and not bool(application.call(
			"has_active_top_level_operation"
		)),
		"Phase 4.5 structurally invalid snapshot fails closed before destructive replacement and leaves the source world authoritative"
	)

	var semantic_invalid: Dictionary = valid_snapshot.duplicate(true)
	var invalid_envelope: Dictionary = semantic_invalid.get(
		"session",
		{}
	)
	var invalid_world: Dictionary = invalid_envelope.get(
		"world_state",
		{}
	)
	var invalid_player: Dictionary = invalid_world.get(
		"player",
		{}
	)
	invalid_player["restore_policy"] = &"invalid_policy"
	invalid_world["player"] = invalid_player
	invalid_envelope["world_state"] = invalid_world
	semantic_invalid["session"] = invalid_envelope
	var coordinator: Node = application.get_node(
		"SaveCoordinator"
	)
	var structurally_valid: bool = bool(
		coordinator.call(
			"validate_snapshot",
			semantic_invalid
		)
	)
	var semantic_failed: bool = not bool(
		application.call(
			"restore_snapshot",
			semantic_invalid
		)
	)
	var world_host: Node = application.get_node(
		"WorldHost"
	)
	assert_true.call(
		structurally_valid
		and semantic_failed
		and not is_instance_valid(source_session)
		and application.get("current_session") == null
		and application.get("current_world") == null
		and application.get("current_player") == null
		and world_host.get_child_count() == 0
		and not bool(input_boundary.get("gameplay_enabled"))
		and not bool(input_boundary.get("look_enabled"))
		and int(application.call("get_control_mode"))
			== ApplicationRoot.ControlMode.MENU
		and not bool(application.call(
			"has_active_top_level_operation"
		)),
		"Phase 4.5 sole-world replacement failure discards the invalid candidate and leaves one coherent application-owned menu recovery state"
	)

	var recovered: bool = bool(
		application.call("launch_development_target", 0)
	)
	var recovered_ready: bool = await _wait_for_navigation_ready(
		tree,
		application.get("current_world") as Node,
		240
	)
	assert_true.call(
		recovered
		and recovered_ready
		and application.get("current_session") != null
		and int(application.call(
			"get_current_session_state"
		)) == WorldSession.State.PLAYING
		and bool(input_boundary.get("gameplay_enabled"))
		and bool(input_boundary.get("look_enabled")),
		"Phase 4.5 coherent recovery state can launch a fresh authoritative world after failed restore"
	)

	await _cleanup_application(tree, application)


func _launch_slice(tree: SceneTree) -> Node:
	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Integrated Slice"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([SLICE_PATH])
	)
	tree.get_root().add_child(application)
	await tree.process_frame
	var launched: bool = bool(
		application.call("launch_development_target", 0)
	)
	assert(
		launched,
		"Phase 4.5 regression must launch the real Integrated Slice."
	)
	var ready: bool = await _wait_for_navigation_ready(
		tree,
		application.get("current_world") as Node,
		240
	)
	assert(
		ready,
		"Phase 4.5 regression requires the slice navigation rebuild."
	)
	return application


func _capture_snapshot(
	application: Node,
	generation: int
) -> Dictionary:
	var session := application.get("current_session") as Node
	var envelope: Dictionary = session.call(
		"capture_save_envelope"
	)
	var view_pose: Dictionary = application.call(
		"get_current_view_pose"
	)
	return {
		"generation": generation,
		"slot": &"phase45",
		"session": envelope.duplicate(true),
		"player_view_pose": view_pose.duplicate(true),
	}


func _wait_for_save_status(
	tree: SceneTree,
	coordinator: Node,
	generation: int,
	expected: StringName,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		var status: Dictionary = coordinator.call(
			"get_request_status",
			generation
		)
		if status.get("status", &"") == expected:
			return true
		await _completed_physics_frame(tree)
	return (
		coordinator.call(
			"get_request_status",
			generation
		).get("status", &"") == expected
	)


func _wait_for_navigation_ready(
	tree: SceneTree,
	world: Node,
	max_frames: int
) -> bool:
	if world == null:
		return false
	for _frame: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await _completed_physics_frame(tree)
	return bool(world.get("navigation_ready"))


func _completed_physics_frame(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame


func _cleanup_application(
	tree: SceneTree,
	application: Node
) -> void:
	if application != null and is_instance_valid(application):
		if application.get("current_session") != null:
			application.call("exit_current_world")
		application.queue_free()
	await tree.process_frame


func _basis_close(a: Basis, b: Basis) -> bool:
	return (
		a.x.distance_to(b.x) <= 0.0001
		and a.y.distance_to(b.y) <= 0.0001
		and a.z.distance_to(b.z) <= 0.0001
	)
