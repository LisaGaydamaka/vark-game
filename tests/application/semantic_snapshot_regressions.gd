extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const WorldSession = preload("res://application/world_session.gd")
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"


func run(
	tree: SceneTree,
	assert_true: Callable
) -> void:
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
	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var session := application.get("current_session") as Node
	var coordinator: Node = application.get_node("SaveCoordinator")
	var boundary: Node = application.get_node("InputBoundary")
	var nav_ready: bool = await _wait_for_navigation_ready(
		tree,
		world,
		240
	)

	var guard := world.get_node_or_null("Guard") as VarkGuard
	var door := world.get_node_or_null(
		"OrdinaryDoor"
	) as VarkOrdinaryDoor
	var crate_a := world.get_node_or_null(
		"CrateA"
	) as VarkOrdinaryProp
	var light := world.get_node_or_null(
		"NorthGameplayLight"
	) as VarkGameplayLight
	var exposure := world.get_node_or_null(
		"GameplayExposure"
	) as VarkGameplayExposure
	var objective := world.get_node_or_null(
		"ObjectiveState"
	) as VarkSimpleObjectiveState
	var objective_trigger := world.get_node_or_null(
		"ObjectiveTrigger"
	) as VarkSemanticRouteTrigger
	var exit_trigger := world.get_node_or_null(
		"ExitTrigger"
	) as VarkSemanticRouteTrigger
	var reaction: Node = world.get_node_or_null("Guard/Reaction")

	assert_true.call(
		launched
		and nav_ready
		and world != null
		and player != null
		and session != null
		and guard != null
		and door != null
		and crate_a != null
		and light != null
		and exposure != null
		and objective != null
		and objective_trigger != null
		and exit_trigger != null
		and reaction != null,
		"Phase 4.2 regression launches the real Integrated Slice semantic owners"
	)
	if (
		not launched
		or not nav_ready
		or world == null
		or player == null
		or session == null
		or guard == null
		or door == null
		or crate_a == null
		or light == null
		or exposure == null
		or objective == null
		or objective_trigger == null
		or exit_trigger == null
		or reaction == null
	):
		application.queue_free()
		await tree.process_frame
		return

	var goal_resolved: bool = await _wait_for_guard_goal(
		tree,
		guard,
		0,
		480
	)
	assert_true.call(
		goal_resolved
		and guard.get_debug_summary().get("target_index", -1) == 0,
		"Guard reaches a non-default resolved patrol goal before snapshot capture"
	)
	guard.movement_speed = 0.0
	guard.velocity = Vector3.ZERO

	var early_exit_queued: bool = exit_trigger.queue_for_body(player)
	await _completed_physics_frame(tree)
	var objective_queued: bool = objective_trigger.queue_for_body(player)
	await _completed_physics_frame(tree)
	var objective_before_save: Dictionary = objective.get_debug_summary()
	var objective_trigger_before_save: Dictionary = (
		objective_trigger.get_debug_summary()
	)
	assert_true.call(
		early_exit_queued
		and objective_queued
		and bool(
			objective_before_save.get("objective", {}).get(
				"complete",
				false
			)
		)
		and not bool(
			objective_before_save.get("exit", {}).get(
				"mission_complete",
				true
			)
		)
		and int(
			objective_before_save.get("exit", {}).get(
				"blocked_attempt_count",
				0
			)
		) == 1
		and not bool(
			objective_trigger_before_save.get("armed", true)
		),
		"Objective facts, one-shot arming, and mission-run counters are non-default before save"
	)

	player.global_position = Vector3(0.0, 0.0, -2.4)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -5.6)
	guard.velocity = Vector3.ZERO
	guard.look_at(player.global_position, Vector3.UP, true)
	for _index: int in 2:
		await tree.physics_frame
		await tree.process_frame
	exposure.sample_now()
	var reaction_seen: Dictionary = reaction.call("get_debug_summary")
	var saw_player: bool = false
	for _sample: int in 20:
		reaction.call("sample_vision_now", 0.10)
		reaction_seen = reaction.call("get_debug_summary")
		if int(reaction_seen.get("seen_count", 0)) >= 1:
			saw_player = true
			break
	assert_true.call(
		saw_player
		and reaction_seen.get("awareness_state", &"") == &"alerted"
		and int(reaction_seen.get("seen_count", 0)) >= 1,
		"Guard awareness history becomes non-default through the real vision path"
	)

	light.gameplay_enabled = false
	light.visible = false
	await _completed_physics_frame(tree)
	var reaction_before_save: Dictionary = reaction.call(
		"get_debug_summary"
	)

	var saved_prop_transform: Transform3D = crate_a.global_transform
	saved_prop_transform.origin = Vector3(-3.15, 0.3, 3.85)
	crate_a.global_transform = saved_prop_transform

	var partial_door_applied: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_OPENING,
		"open_fraction": 0.42,
		"motion_blocked": false,
	})
	door.set_physics_process(false)

	player.global_position = Vector3(1.15, 0.0, 1.85)
	player.velocity = Vector3.ZERO
	var look_motion := InputEventMouseMotion.new()
	look_motion.relative = Vector2(14.0, -6.0)
	boundary.call("route_input_event", look_motion)
	var requested_view_pose: Dictionary = application.call(
		"get_current_view_pose"
	)
	var requested_player_position: Vector3 = player.global_position

	var generation: int = int(application.call("request_quicksave"))
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
	var session_snapshot: Dictionary = snapshot.get("session", {})
	var world_state: Dictionary = session_snapshot.get(
		"world_state",
		{}
	)
	var existence: Dictionary = world_state.get(
		"object_existence",
		{}
	)
	var persistent: Dictionary = world_state.get(
		"persistent_entities",
		{}
	)
	var semantic: Dictionary = world_state.get(
		"semantic_owners",
		{}
	)
	var saved_player: Dictionary = world_state.get("player", {})
	var saved_guard: Dictionary = persistent.get("slice.guard", {})
	var saved_door: Dictionary = persistent.get("slice.door", {})
	var saved_prop: Dictionary = persistent.get("slice.prop.a", {})
	var saved_light: Dictionary = persistent.get(
		"slice.light.north",
		{}
	)
	var objective_save_id: String = str(
		objective.call("get_semantic_save_id")
	)
	var objective_trigger_save_id: String = str(
		objective_trigger.call("get_semantic_save_id")
	)
	var reaction_save_id: String = str(
		reaction.call("get_semantic_save_id")
	)
	var saved_objective: Dictionary = semantic.get(
		objective_save_id,
		{}
	)
	var saved_objective_trigger: Dictionary = semantic.get(
		objective_trigger_save_id,
		{}
	)
	var saved_reaction: Dictionary = semantic.get(
		reaction_save_id,
		{}
	)

	assert_true.call(
		partial_door_applied
		and generation > 0
		and committed
		and (existence.get("authored_tombstones", []) as Array).is_empty()
		and (existence.get("runtime_entities", []) as Array).is_empty()
		and (world_state.get(
			"mission_script_state",
			{}
		) as Dictionary).is_empty()
		and persistent.has("slice.guard")
		and persistent.has("slice.door")
		and persistent.has("slice.prop.a")
		and persistent.has("slice.prop.b")
		and persistent.has("slice.light.north")
		and saved_guard.get("goal_id", "") == "slice.patrol.a"
		and saved_door.get("phase", &"")
			== VarkOrdinaryDoor.PHASE_OPENING
		and is_equal_approx(
			float(saved_door.get("open_fraction", 0.0)),
			0.42
		)
		and saved_prop.get("transform", Transform3D.IDENTITY)
			== saved_prop_transform
		and not bool(saved_light.get("gameplay_enabled", true))
		and not bool(saved_light.get("visible", true))
		and saved_objective.get("objective_complete", false)
		and not saved_objective.get("mission_complete", true)
		and int(saved_objective.get("blocked_exit_count", 0)) == 1
		and not bool(saved_objective_trigger.get("armed", true))
		and int(saved_reaction.get("seen_count", 0))
			== int(reaction_before_save.get("seen_count", -1))
		and saved_player.get("transform", Transform3D.IDENTITY).origin
			== requested_player_position,
		"Stable-boundary snapshot contains detached semantic state for player, persistent entities, facts/stats, awareness, resolved goal, and explicit empty existence/script sections"
	)

	door.set_physics_process(true)
	door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_CLOSED,
		"open_fraction": 0.0,
		"motion_blocked": false,
	})
	crate_a.global_position = Vector3(3.25, 0.3, 3.25)
	light.gameplay_enabled = true
	light.visible = true
	player.global_position = Vector3(-3.0, 0.0, 5.0)
	var mutate_look := InputEventMouseMotion.new()
	mutate_look.relative = Vector2(-25.0, 11.0)
	boundary.call("route_input_event", mutate_look)
	var mission_finish_queued: bool = exit_trigger.queue_for_body(player)
	await _completed_physics_frame(tree)
	assert_true.call(
		mission_finish_queued
		and bool(
			objective.query_exit(&"exit.slice").get(
				"mission_complete",
				false
			)
		),
		"Live semantic owners can diverge after detached capture"
	)

	var old_world_instance_id: int = world.get_instance_id()
	var loaded: bool = bool(application.call("quickload_latest"))
	var restored_world := application.get("current_world") as Node3D
	var restored_player := application.get(
		"current_player"
	) as CharacterBody3D
	var restored_session := application.get("current_session") as Node
	var restored_door := restored_world.get_node_or_null(
		"OrdinaryDoor"
	) as VarkOrdinaryDoor
	var restored_crate := restored_world.get_node_or_null(
		"CrateA"
	) as VarkOrdinaryProp
	var restored_guard := restored_world.get_node_or_null(
		"Guard"
	) as VarkGuard
	var restored_light := restored_world.get_node_or_null(
		"NorthGameplayLight"
	) as VarkGameplayLight
	var restored_objective := restored_world.get_node_or_null(
		"ObjectiveState"
	) as VarkSimpleObjectiveState
	var restored_objective_trigger := restored_world.get_node_or_null(
		"ObjectiveTrigger"
	) as VarkSemanticRouteTrigger
	var restored_reaction: Node = restored_world.get_node_or_null(
		"Guard/Reaction"
	)
	var restored_view: Dictionary = application.call(
		"get_current_view_pose"
	)
	var restored_objective_summary: Dictionary = (
		restored_objective.get_debug_summary()
	)
	var restored_trigger_summary: Dictionary = (
		restored_objective_trigger.get_debug_summary()
	)
	var restored_reaction_summary: Dictionary = restored_reaction.call(
		"get_debug_summary"
	)
	var restored_guard_snapshot: Dictionary = (
		restored_guard.capture_semantic_state()
	)

	assert_true.call(
		loaded
		and restored_world != null
		and restored_world.get_instance_id() != old_world_instance_id
		and restored_session != null
		and int(restored_session.get("state"))
			== WorldSession.State.PLAYING
		and int(
			restored_session.call(
				"get_pending_semantic_event_count"
			)
		) == 0
		and restored_player.global_position
			== requested_player_position
		and is_equal_approx(
			float(restored_view.get("body_yaw", 0.0)),
			float(requested_view_pose.get("body_yaw", 0.0))
		)
		and is_equal_approx(
			float(restored_view.get("head_pitch", 0.0)),
			float(requested_view_pose.get("head_pitch", 0.0))
		)
		and restored_door.get_semantic_phase()
			== VarkOrdinaryDoor.PHASE_OPENING
		and is_equal_approx(
			restored_door.get_open_fraction(),
			0.42
		)
		and restored_crate.global_transform == saved_prop_transform
		and restored_guard_snapshot.get("goal_id", "")
			== "slice.patrol.a"
		and not restored_light.gameplay_enabled
		and not restored_light.visible
		and bool(
			restored_objective_summary.get("objective", {}).get(
				"complete",
				false
			)
		)
		and not bool(
			restored_objective_summary.get("exit", {}).get(
				"mission_complete",
				true
			)
		)
		and int(
			restored_objective_summary.get("exit", {}).get(
				"blocked_attempt_count",
				0
			)
		) == 1
		and not bool(restored_trigger_summary.get("armed", true))
		and int(restored_trigger_summary.get("queued_count", 0))
			== int(saved_objective_trigger.get("queued_count", -1))
		and int(restored_reaction_summary.get("seen_count", 0))
			== int(saved_reaction.get("seen_count", -1)),
		"Quickload reconstructs the captured semantic owners in a fresh world before ordinary gameplay resumes, without replaying restore-time events"
	)

	var restored_nav_ready: bool = await _wait_for_navigation_ready(
		tree,
		restored_world,
		240
	)
	var restored_guard_summary: Dictionary = (
		restored_guard.get_debug_summary()
	)
	var requeue_one_shot: bool = restored_objective_trigger.queue_for_body(
		restored_player
	)
	assert_true.call(
		restored_nav_ready
		and int(restored_guard_summary.get("target_index", -1)) == 0
		and not requeue_one_shot,
		"Deferred navigation reconstruction resumes the saved guard goal and restored one-shot facts stay consumed"
	)

	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _wait_for_navigation_ready(
	tree: SceneTree,
	world: Node,
	max_frames: int
) -> bool:
	if world == null:
		return false
	for _index: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await tree.physics_frame
		await tree.process_frame
	return bool(world.get("navigation_ready"))


func _wait_for_guard_goal(
	tree: SceneTree,
	guard: VarkGuard,
	target_index: int,
	max_frames: int
) -> bool:
	for _index: int in max_frames:
		if int(guard.get_debug_summary().get("target_index", -1)) == target_index:
			return true
		await tree.physics_frame
		await tree.process_frame
	return int(guard.get_debug_summary().get("target_index", -1)) == target_index


func _wait_for_save_status(
	tree: SceneTree,
	coordinator: Node,
	generation: int,
	target_status: StringName,
	max_frames: int
) -> bool:
	for _index: int in max_frames:
		var status: Dictionary = coordinator.call(
			"get_request_status",
			generation
		)
		if status.get("status", &"") == target_status:
			return true
		if (
			status.get("status", &"") == &"cancelled"
			or status.get("status", &"") == &"failed"
			or status.get("status", &"") == &"superseded"
		):
			return false
		await tree.physics_frame
		await tree.process_frame
	return (
		coordinator.call(
			"get_request_status",
			generation
		).get("status", &"") == target_status
	)


func _completed_physics_frame(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
