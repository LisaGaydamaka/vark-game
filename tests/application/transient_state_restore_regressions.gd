extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"
const FLOAT_TOLERANCE: float = 0.0001
const POSITION_TOLERANCE: float = 0.015
const VELOCITY_TOLERANCE: float = 0.02


func run(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	await _prove_moving_door_restore(tree, assert_true)
	await _prove_falling_thrown_prop_restore(tree, assert_true)
	await _prove_guard_awareness_and_body_restore(tree, assert_true)


func _prove_moving_door_restore(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_slice(tree)
	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var session := application.get("current_session") as Node
	var door := world.get_node("OrdinaryDoor") as VarkOrdinaryDoor

	door.request_open(player)
	var moving: bool = await _wait_for_door_fraction(
		tree,
		door,
		0.08,
		0.80,
		90
	)
	var snapshot: Dictionary = _capture_snapshot(application, 4401)
	var saved_session: Dictionary = snapshot.get("session", {})
	var saved_world: Dictionary = saved_session.get("world_state", {})
	var saved_door: Dictionary = (
		saved_world.get("persistent_entities", {}) as Dictionary
	).get("slice.door", {})
	var saved_fraction: float = float(
		saved_door.get("open_fraction", -1.0)
	)
	var saved_gameplay_time: float = float(
		saved_session.get("gameplay_time_seconds", -1.0)
	)
	var request_generation: int = int(
		application.call("request_quicksave")
	)

	var stopped: bool = bool(application.call("stop_current_world"))
	var stopped_fraction: float = door.get_open_fraction()
	for _frame: int in 5:
		await tree.process_frame
	var fraction_after_application_frames: float = door.get_open_fraction()

	var restored: bool = bool(
		application.call("restore_snapshot", snapshot)
	)
	var restored_session := application.get("current_session") as Node
	var restored_world := application.get("current_world") as Node3D
	var restored_door := restored_world.get_node(
		"OrdinaryDoor"
	) as VarkOrdinaryDoor
	var restored_fraction: float = restored_door.get_open_fraction()
	var restored_time: float = float(
		restored_session.call("get_gameplay_time_seconds")
	)

	assert_true.call(
		moving
		and saved_door.get("phase", &"")
			== VarkOrdinaryDoor.PHASE_OPENING
		and saved_fraction > 0.0
		and saved_fraction < 1.0
		and request_generation > 0,
		"Phase 4.4 accepts save during moving-door progress and captures semantic phase/fraction"
	)
	assert_true.call(
		stopped
		and is_equal_approx(
			stopped_fraction,
			fraction_after_application_frames
		)
		and restored
		and restored_door.get_semantic_phase()
			== VarkOrdinaryDoor.PHASE_OPENING
		and absf(restored_fraction - saved_fraction)
			<= FLOAT_TOLERANCE
		and absf(restored_time - saved_gameplay_time)
			<= FLOAT_TOLERANCE,
		"Phase 4.4 restores door progress from saved simulation truth without wall-clock/application-frame advancement"
	)

	await _advance_frames(tree, 3)
	var advanced_fraction: float = restored_door.get_open_fraction()
	var advanced_time: float = float(
		restored_session.call("get_gameplay_time_seconds")
	)
	assert_true.call(
		advanced_fraction > restored_fraction
		and advanced_time > restored_time,
		"Phase 4.4 moving-door duration resumes only as world simulation time advances"
	)

	await _cleanup_application(tree, application)


func _prove_falling_thrown_prop_restore(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_slice(tree)
	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var prop := world.get_node("CrateA") as VarkOrdinaryProp

	var carried: bool = prop.begin_carried_junk(player)
	var release_transform: Transform3D = prop.global_transform
	release_transform.origin = Vector3(
		prop.global_position.x,
		2.2,
		prop.global_position.z
	)
	var thrown: bool = prop.release_from_carry(
		VarkOrdinaryProp.MOTION_THROWN,
		release_transform,
		Vector3(1.1, 0.0, -0.35),
		null
	)
	var descending: bool = await _wait_for_descending_thrown_prop(
		tree,
		prop,
		40
	)
	var snapshot: Dictionary = _capture_snapshot(application, 4402)
	var saved_world: Dictionary = snapshot.get(
		"session",
		{}
	).get("world_state", {})
	var saved_prop: Dictionary = (
		saved_world.get("persistent_entities", {}) as Dictionary
	).get("slice.prop.a", {})
	var saved_transform: Transform3D = saved_prop.get(
		"transform",
		Transform3D.IDENTITY
	)
	var saved_velocity: Vector3 = saved_prop.get(
		"linear_velocity",
		Vector3.ZERO
	)
	var request_generation: int = int(
		application.call("request_quicksave")
	)

	var restored: bool = bool(
		application.call("restore_snapshot", snapshot)
	)
	var restored_world := application.get("current_world") as Node3D
	var restored_prop := restored_world.get_node(
		"CrateA"
	) as VarkOrdinaryProp

	assert_true.call(
		carried
		and thrown
		and descending
		and request_generation > 0
		and saved_prop.get("phase", &"")
			== VarkOrdinaryProp.PHASE_MOVING
		and saved_prop.get("motion_kind", &"")
			== VarkOrdinaryProp.MOTION_THROWN
		and saved_velocity.y < 0.0,
		"Phase 4.4 accepts save while a thrown prop is physically falling and captures semantic motion/pose/velocity"
	)
	assert_true.call(
		restored
		and restored_prop.get_semantic_phase()
			== VarkOrdinaryProp.PHASE_MOVING
		and restored_prop.get_motion_kind()
			== VarkOrdinaryProp.MOTION_THROWN
		and _transforms_close(
			restored_prop.global_transform,
			saved_transform,
			POSITION_TOLERANCE
		)
		and _vectors_close(
			restored_prop.linear_velocity,
			saved_velocity,
			VELOCITY_TOLERANCE
		)
		and not restored_prop.freeze
		and not restored_prop.sleeping,
		"Phase 4.4 reconstructs falling/thrown prop physics from semantic motion state instead of solver/contact callbacks"
	)

	var restored_position: Vector3 = restored_prop.global_position
	var restored_velocity_before_sim: Vector3 = restored_prop.linear_velocity
	await _advance_frames(tree, 2)
	var phase_after_sim: StringName = restored_prop.get_semantic_phase()
	var motion_after_sim: StringName = restored_prop.get_motion_kind()
	var simulation_progressed: bool = (
		restored_prop.global_position.distance_to(
			restored_position
		) > 0.001
		or not _vectors_close(
			restored_prop.linear_velocity,
			restored_velocity_before_sim,
			VELOCITY_TOLERANCE
		)
		or phase_after_sim == VarkOrdinaryProp.PHASE_SETTLED
	)
	assert_true.call(
		simulation_progressed
		and (
			(
				phase_after_sim == VarkOrdinaryProp.PHASE_MOVING
				and motion_after_sim
					== VarkOrdinaryProp.MOTION_THROWN
			)
			or (
				phase_after_sim == VarkOrdinaryProp.PHASE_SETTLED
				and motion_after_sim
					== VarkOrdinaryProp.MOTION_NONE
			)
		),
		"Phase 4.4 restored thrown prop resumes ordinary simulation from saved velocity or legitimately settles after contact"
	)

	await _cleanup_application(tree, application)


func _prove_guard_awareness_and_body_restore(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_slice(tree)
	var refs: Dictionary = _slice_refs(application)
	var player := refs["player"] as CharacterBody3D
	var session := refs["session"] as Node
	var guard := refs["guard"] as VarkGuard
	var reaction := refs["reaction"] as Node
	var light := refs["light"] as VarkGameplayLight
	var exposure := refs["exposure"] as VarkGameplayExposure

	guard.movement_speed = 0.0
	guard.velocity = Vector3.ZERO
	light.gameplay_enabled = false
	light.visible = false
	exposure.sample_now()

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
	await _completed_physics_frame(tree)
	var heard_summary: Dictionary = reaction.call(
		"get_debug_summary"
	)
	var heard_snapshot: Dictionary = _capture_snapshot(
		application,
		4403
	)
	var heard_request: int = int(
		application.call("request_quicksave")
	)
	var heard_restored: bool = bool(
		application.call("restore_snapshot", heard_snapshot)
	)

	refs = _slice_refs(application)
	player = refs["player"] as CharacterBody3D
	session = refs["session"] as Node
	guard = refs["guard"] as VarkGuard
	reaction = refs["reaction"] as Node
	light = refs["light"] as VarkGameplayLight
	exposure = refs["exposure"] as VarkGameplayExposure
	var restored_heard: Dictionary = reaction.call(
		"get_debug_summary"
	)

	assert_true.call(
		sound_queued
		and heard_request > 0
		and heard_summary.get("state", &"") == &"heard_noise"
		and int(heard_summary.get("heard_count", 0)) >= 1
		and heard_restored
		and restored_heard.get("state", &"") == &"heard_noise"
		and int(restored_heard.get("heard_count", -1))
			== int(heard_summary.get("heard_count", -2)),
		"Phase 4.4 directly restores guard investigation/heard-noise semantic awareness without replaying the source sound"
	)

	# Confirmed visual alert is a separate representative transient. Start from
	# a fresh slice so the investigation scenario's intentionally disabled
	# gameplay light and restored exposure cache cannot influence this proof.
	await _cleanup_application(tree, application)
	application = await _launch_slice(tree)
	refs = _slice_refs(application)
	player = refs["player"] as CharacterBody3D
	session = refs["session"] as Node
	guard = refs["guard"] as VarkGuard
	reaction = refs["reaction"] as Node
	light = refs["light"] as VarkGameplayLight
	exposure = refs["exposure"] as VarkGameplayExposure

	guard.movement_speed = 0.0
	guard.velocity = Vector3.ZERO
	# This fixture owns the exact facing used by the visual sample. Disable only
	# the guard root's patrol physics so its normal navigation tick cannot rotate
	# the guard away during the two frames needed to refresh exposure geometry.
	guard.set_physics_process(false)
	light.gameplay_enabled = true
	light.visible = true
	player.global_position = Vector3(0.0, 0.0, -2.4)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -5.6)
	guard.velocity = Vector3.ZERO
	guard.look_at(player.global_position, Vector3.UP, true)
	await _advance_frames(tree, 2)
	exposure.sample_now()
	var alert_summary: Dictionary = reaction.call("get_debug_summary")
	var saw_player: bool = false
	for _sample: int in 20:
		reaction.call("sample_vision_now", 0.10)
		alert_summary = reaction.call("get_debug_summary")
		if alert_summary.get("awareness_state", &"") == &"alerted":
			saw_player = true
			break
	var alert_snapshot: Dictionary = _capture_snapshot(
		application,
		4404
	)
	var alert_request: int = int(
		application.call("request_quicksave")
	)
	var alert_restored: bool = bool(
		application.call("restore_snapshot", alert_snapshot)
	)

	refs = _slice_refs(application)
	guard = refs["guard"] as VarkGuard
	reaction = refs["reaction"] as Node
	var restored_alert: Dictionary = reaction.call(
		"get_debug_summary"
	)
	assert_true.call(
		saw_player
		and alert_request > 0
		and alert_summary.get("state", &"") == &"saw_player"
		and alert_restored
		and restored_alert.get("state", &"") == &"saw_player"
		and int(restored_alert.get("seen_count", -1))
			== int(alert_summary.get("seen_count", -2)),
		"Phase 4.4 directly restores confirmed-alert awareness and its already-resolved evidence counters"
	)

	var unconscious_requested: bool = guard.request_life_state(
		VarkGuard.LIFE_UNCONSCIOUS
	)
	await _completed_physics_frame(tree)
	await _completed_physics_frame(tree)
	var unconscious_position: Vector3 = (
		guard.global_position + Vector3(0.35, 0.0, 0.0)
	)
	guard.global_position = unconscious_position
	guard.velocity = Vector3.ZERO
	var unconscious_snapshot: Dictionary = _capture_snapshot(
		application,
		4405
	)
	var unconscious_request: int = int(
		application.call("request_quicksave")
	)
	var unconscious_restored: bool = bool(
		application.call("restore_snapshot", unconscious_snapshot)
	)

	refs = _slice_refs(application)
	guard = refs["guard"] as VarkGuard
	reaction = refs["reaction"] as Node
	var unconscious_state: Dictionary = guard.query_actor_state()
	var restored_unconscious_reaction: Dictionary = reaction.call(
		"get_debug_summary"
	)
	assert_true.call(
		unconscious_requested
		and unconscious_request > 0
		and unconscious_restored
		and unconscious_state.get("life_state", &"")
			== VarkGuard.LIFE_UNCONSCIOUS
		and bool(unconscious_state.get("body_state", false))
		and not bool(
			unconscious_state.get("navigation_active", true)
		)
		and guard.global_position.distance_to(
			unconscious_position
		) <= POSITION_TOLERANCE
		and restored_unconscious_reaction.get("state", &"")
			== &"inactive",
		"Phase 4.4 restores an unconscious actor as the same persistent movable body with awareness/navigation inactive"
	)

	var dead_requested: bool = guard.request_life_state(
		VarkGuard.LIFE_DEAD
	)
	await _completed_physics_frame(tree)
	await _completed_physics_frame(tree)
	var dead_position: Vector3 = (
		guard.global_position + Vector3(-0.20, 0.0, 0.25)
	)
	guard.global_position = dead_position
	guard.velocity = Vector3.ZERO
	var dead_snapshot: Dictionary = _capture_snapshot(
		application,
		4406
	)
	var dead_request: int = int(
		application.call("request_quicksave")
	)
	var dead_restored: bool = bool(
		application.call("restore_snapshot", dead_snapshot)
	)

	refs = _slice_refs(application)
	guard = refs["guard"] as VarkGuard
	var dead_state: Dictionary = guard.query_actor_state()
	assert_true.call(
		dead_requested
		and dead_request > 0
		and dead_restored
		and dead_state.get("life_state", &"")
			== VarkGuard.LIFE_DEAD
		and bool(dead_state.get("body_state", false))
		and not bool(dead_state.get("navigation_active", true))
		and guard.global_position.distance_to(
			dead_position
		) <= POSITION_TOLERANCE,
		"Phase 4.4 restores dead/body state on the same persistent actor identity without resurrecting navigation or awareness"
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
		"Phase 4.4 regression must launch the real Integrated Slice."
	)
	var world := application.get("current_world") as Node
	var navigation_ready: bool = await _wait_for_navigation_ready(
		tree,
		world,
		240
	)
	assert(
		navigation_ready,
		"Phase 4.4 regression requires the slice navigation rebuild."
	)
	return application


func _slice_refs(application: Node) -> Dictionary:
	var world := application.get("current_world") as Node3D
	return {
		"world": world,
		"player": application.get("current_player"),
		"session": application.get("current_session"),
		"guard": world.get_node("Guard"),
		"reaction": world.get_node("Guard/Reaction"),
		"light": world.get_node("NorthGameplayLight"),
		"exposure": world.get_node("GameplayExposure"),
	}


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
		"slot": &"phase44",
		"session": envelope.duplicate(true),
		"player_view_pose": view_pose.duplicate(true),
	}


func _wait_for_door_fraction(
	tree: SceneTree,
	door: VarkOrdinaryDoor,
	minimum: float,
	maximum: float,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		await _completed_physics_frame(tree)
		var fraction: float = door.get_open_fraction()
		if (
			door.get_semantic_phase()
				== VarkOrdinaryDoor.PHASE_OPENING
			and fraction >= minimum
			and fraction <= maximum
		):
			return true
	return false


func _wait_for_descending_thrown_prop(
	tree: SceneTree,
	prop: VarkOrdinaryProp,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		await _completed_physics_frame(tree)
		if (
			prop.get_semantic_phase()
				== VarkOrdinaryProp.PHASE_MOVING
			and prop.get_motion_kind()
				== VarkOrdinaryProp.MOTION_THROWN
			and prop.linear_velocity.y < -0.05
		):
			return true
	return false


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


func _advance_frames(
	tree: SceneTree,
	frame_count: int
) -> void:
	for _frame: int in frame_count:
		await _completed_physics_frame(tree)


func _completed_physics_frame(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame


func _cleanup_application(
	tree: SceneTree,
	application: Node
) -> void:
	if application != null and is_instance_valid(application):
		application.call("exit_current_world")
		application.queue_free()
	await tree.process_frame


func _vectors_close(
	a: Vector3,
	b: Vector3,
	tolerance: float
) -> bool:
	return a.distance_to(b) <= tolerance


func _transforms_close(
	a: Transform3D,
	b: Transform3D,
	position_tolerance: float
) -> bool:
	return (
		a.origin.distance_to(b.origin) <= position_tolerance
		and a.basis.x.distance_to(b.basis.x) <= 0.001
		and a.basis.y.distance_to(b.basis.y) <= 0.001
		and a.basis.z.distance_to(b.basis.z) <= 0.001
	)
