extends RefCounted


const WorldSession = preload("res://application/world_session.gd")


func run(
	tree: SceneTree,
	application: Node,
	assert_true: Callable
) -> void:
	var coordinator: Node = application.get_node("SaveCoordinator")
	var boundary: Node = application.get_node("InputBoundary")
	var initial_session: Node = application.get("current_session") as Node
	var initial_session_id: int = int(
		application.call("get_current_session_id")
	)

	assert_true.call(
		coordinator != null
		and coordinator.get("application") == application,
		"Phase 4.1 application owns one persistent save coordinator"
	)

	var cancelled_generation: int = int(
		application.call("request_quicksave")
	)
	var cancelled_status_before: Dictionary = coordinator.call(
		"get_request_status",
		cancelled_generation
	)
	var cancelled_by_restart: bool = bool(
		application.call("restart_current_world")
	)
	var cancelled_status_after: Dictionary = coordinator.call(
		"get_request_status",
		cancelled_generation
	)
	assert_true.call(
		cancelled_generation > 0
		and cancelled_status_before.get("status", &"") == &"pending"
		and cancelled_by_restart
		and cancelled_status_after.get("status", &"") == &"cancelled"
		and int(cancelled_status_after.get("source_session_id", 0))
			== initial_session_id
		and not is_instance_valid(initial_session),
		"A save request is bound to its source WorldSession and cancels instead of retargeting across restart"
	)

	var source_session: Node = application.get("current_session") as Node
	var source_session_id: int = int(
		application.call("get_current_session_id")
	)
	var source_serial_before: int = int(
		source_session.call("get_stable_gameplay_boundary_serial")
	)
	var motion_a := InputEventMouseMotion.new()
	motion_a.relative = Vector2(13.0, -6.0)
	boundary.call("route_input_event", motion_a)
	var pose_at_request: Dictionary = application.call(
		"get_current_view_pose"
	)
	var captured_generation: int = int(
		application.call("request_quicksave")
	)
	await _advance_to_capture_before_writer(tree)
	var captured_status: Dictionary = coordinator.call(
		"get_request_status",
		captured_generation
	)
	var captured_snapshot: Dictionary = coordinator.call(
		"get_request_snapshot",
		captured_generation
	)
	var captured_session: Dictionary = captured_snapshot.get(
		"session",
		{}
	)
	var captured_pose: Dictionary = captured_snapshot.get(
		"player_view_pose",
		{}
	)
	assert_true.call(
		captured_status.get("status", &"") == &"captured"
		and int(captured_session.get("source_session_id", 0))
			== source_session_id
		and int(captured_session.get("stable_boundary_serial", 0))
			== source_serial_before + 1
		and is_equal_approx(
			float(captured_pose.get("body_yaw", 0.0)),
			float(pose_at_request.get("body_yaw", 0.0))
		)
		and is_equal_approx(
			float(captured_pose.get("head_pitch", 0.0)),
			float(pose_at_request.get("head_pitch", 0.0))
		),
		"Save capture occurs synchronously at the source session's next stable gameplay boundary and includes the current input-owned view pose"
	)

	var live_motion_after_capture := InputEventMouseMotion.new()
	live_motion_after_capture.relative = Vector2(-21.0, 9.0)
	boundary.call("route_input_event", live_motion_after_capture)
	var mutated_copy: Dictionary = captured_snapshot.duplicate(true)
	var mutated_session_copy: Dictionary = mutated_copy.get("session", {})
	mutated_session_copy["gameplay_time_seconds"] = 99999.0
	mutated_copy["session"] = mutated_session_copy
	var recaptured_snapshot: Dictionary = coordinator.call(
		"get_request_snapshot",
		captured_generation
	)
	assert_true.call(
		not is_equal_approx(
			float(
				recaptured_snapshot.get("session", {}).get(
					"gameplay_time_seconds",
					99999.0
				)
			),
			99999.0
		)
		and is_equal_approx(
			float(
				recaptured_snapshot.get("player_view_pose", {}).get(
					"body_yaw",
					0.0
				)
			),
			float(captured_pose.get("body_yaw", 0.0))
		),
		"Captured snapshot is detached from later live view changes and caller-owned mutable containers"
	)

	var source_torn_down: bool = bool(
		application.call("restart_current_world")
	)
	assert_true.call(
		source_torn_down and not is_instance_valid(source_session),
		"Captured save data no longer depends on the source world remaining alive"
	)
	await tree.process_frame
	var committed_status: Dictionary = coordinator.call(
		"get_request_status",
		captured_generation
	)
	assert_true.call(
		committed_status.get("status", &"") == &"committed"
		and int(
			coordinator.call("get_latest_committed_generation")
		) == captured_generation,
		"A detached captured snapshot can finish its logical slot commit after the source WorldSession is torn down"
	)

	var ordering_session: Node = application.get("current_session") as Node
	var motion_b := InputEventMouseMotion.new()
	motion_b.relative = Vector2(8.0, 3.0)
	boundary.call("route_input_event", motion_b)
	var older_generation: int = int(
		application.call("request_quicksave")
	)
	await _advance_to_capture_before_writer(tree)
	var older_captured: Dictionary = coordinator.call(
		"get_request_status",
		older_generation
	)
	var newer_generation: int = int(
		application.call("request_quicksave")
	)
	await tree.process_frame
	var older_after_newer_request: Dictionary = coordinator.call(
		"get_request_status",
		older_generation
	)
	assert_true.call(
		older_captured.get("status", &"") == &"captured"
		and newer_generation > older_generation
		and older_after_newer_request.get("status", &"")
			== &"superseded",
		"An older captured save cannot commit after a newer request for the same logical slot"
	)

	await _advance_to_capture_before_writer(tree)
	var newer_captured_snapshot: Dictionary = coordinator.call(
		"get_request_snapshot",
		newer_generation
	)
	await tree.process_frame
	var newer_committed: Dictionary = coordinator.call(
		"get_request_status",
		newer_generation
	)
	assert_true.call(
		newer_committed.get("status", &"") == &"committed"
		and int(
			coordinator.call("get_latest_committed_generation")
		) == newer_generation,
		"The newest save request becomes the latest fully committed logical quicksave"
	)

	var committed_copy: Dictionary = coordinator.call(
		"get_latest_committed_snapshot"
	)
	var committed_copy_pose: Dictionary = committed_copy.get(
		"player_view_pose",
		{}
	)
	committed_copy_pose["body_yaw"] = 123.0
	committed_copy["player_view_pose"] = committed_copy_pose
	var committed_again: Dictionary = coordinator.call(
		"get_latest_committed_snapshot"
	)
	assert_true.call(
		absf(
			float(
				committed_again.get("player_view_pose", {}).get(
					"body_yaw",
					0.0
				)
			) - 123.0
		) > 1.0,
		"Committed slot reads return detached copies rather than mutable coordinator-owned state"
	)

	var expected_restore_snapshot: Dictionary = newer_captured_snapshot
	var expected_restore_pose: Dictionary = expected_restore_snapshot.get(
		"player_view_pose",
		{}
	)
	var expected_restore_time: float = float(
		expected_restore_snapshot.get("session", {}).get(
			"gameplay_time_seconds",
			0.0
		)
	)

	var motion_c := InputEventMouseMotion.new()
	motion_c.relative = Vector2(25.0, -10.0)
	boundary.call("route_input_event", motion_c)
	var pending_newest_generation: int = int(
		application.call("request_quicksave")
	)
	var pre_load_session: Node = application.get(
		"current_session"
	) as Node
	var pre_load_session_id: int = int(
		application.call("get_current_session_id")
	)
	var loaded: bool = bool(application.call("quickload_latest"))
	var restored_session: Node = application.get("current_session") as Node
	var restored_pose: Dictionary = application.call(
		"get_current_view_pose"
	)
	var pending_after_load: Dictionary = coordinator.call(
		"get_request_status",
		pending_newest_generation
	)
	assert_true.call(
		loaded
		and not is_instance_valid(pre_load_session)
		and restored_session != null
		and int(application.call("get_current_session_id"))
			> pre_load_session_id
		and int(application.call("get_current_session_state"))
			== WorldSession.State.PLAYING
		and pending_after_load.get("status", &"") == &"cancelled"
		and is_equal_approx(
			float(restored_pose.get("body_yaw", 0.0)),
			float(expected_restore_pose.get("body_yaw", 0.0))
		)
		and is_equal_approx(
			float(restored_pose.get("head_pitch", 0.0)),
			float(expected_restore_pose.get("head_pitch", 0.0))
		)
		and is_equal_approx(
			float(application.call("get_gameplay_time_seconds")),
			expected_restore_time
		),
		"Quickload reads only the latest fully committed snapshot, cancels an in-progress newer capture, and restores through a fresh non-playing replacement before gameplay resumes"
	)

	assert_true.call(
		bool(application.get_node("InputBoundary").get("gameplay_enabled"))
		and bool(application.get_node("InputBoundary").get("look_enabled"))
		and not bool(application.call("has_active_top_level_operation"))
		and application.get("current_session") != ordering_session,
		"Transactional restore returns application ownership and input to one authoritative PLAYING replacement"
	)


func _advance_to_capture_before_writer(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
