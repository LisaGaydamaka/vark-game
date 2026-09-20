extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"
const TEST_SAVE_DIRECTORY: String = "user://vark_tests/phase47"


func run(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	_cleanup_test_storage()
	Input.action_release("attack")

	var application: Node = await _launch_slice(tree)
	var coordinator: Node = application.get_node("SaveCoordinator")
	coordinator.set(
		"durable_save_directory",
		TEST_SAVE_DIRECTORY
	)
	var world := application.get("current_world") as Node3D
	var session := application.get("current_session") as Node
	var player := application.get("current_player") as CharacterBody3D
	var guard := world.get_node("Guard") as VarkGuard
	var reaction: Node = world.get_node("Guard/Reaction")
	var light := world.get_node(
		"NorthGameplayLight"
	) as VarkGameplayLight
	var exposure := world.get_node(
		"GameplayExposure"
	) as VarkGameplayExposure

	# Keep this proof about the hostile path rather than patrol/vision timing.
	guard.movement_speed = 0.0
	guard.velocity = Vector3.ZERO
	guard.set_physics_process(false)
	light.gameplay_enabled = false
	light.visible = false
	exposure.sample_now()

	player.global_position = (
		guard.global_position
		+ Vector3(0.0, 0.0, 1.4)
	)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	var head := player.get_node("Head") as Node3D
	head.rotation = Vector3.ZERO

	# The application boundary suppresses a held edge until release. Establish a
	# neutral released gameplay frame, then drive the same attack intent sampled
	# by production Player._physics_process().
	Input.action_release("attack")
	await _completed_physics_frame(tree)
	Input.action_press("attack")
	await _completed_physics_frame(tree)

	var first_actor_state: Dictionary = guard.query_actor_state()
	var first_reaction: Dictionary = reaction.call(
		"get_debug_summary"
	)
	assert_true.call(
		first_actor_state.get("life_state", &"")
			== VarkGuard.LIFE_UNCONSCIOUS
		and bool(first_actor_state.get("body_state", false))
		and first_reaction.get("state", &"")
			== &"heard_noise"
		and int(first_reaction.get("heard_count", 0)) == 1
		and first_reaction.get("last_heard_kind", &"")
			== VarkGuard.CRUDE_HOSTILE_IMPACT_SOUND_KIND,
		"Phase 4.7 fresh player attack intent queues one hostile effect, acoustic impact reaction, and semantic knockout in FIFO consequence order"
	)

	# Keep the action held for another gameplay frame. The boundary edge must
	# expire; only normal reaction physics advances, making the knocked-out guard
	# inactive without generating a second hostile/acoustic consequence.
	await _completed_physics_frame(tree)
	Input.action_release("attack")
	var settled_reaction: Dictionary = reaction.call(
		"get_debug_summary"
	)
	assert_true.call(
		settled_reaction.get("state", &"") == &"inactive"
		and int(settled_reaction.get("heard_count", 0)) == 1
		and settled_reaction.get("last_heard_kind", &"")
			== VarkGuard.CRUDE_HOSTILE_IMPACT_SOUND_KIND,
		"Phase 4.7 held attack does not replay its gameplay edge and unconscious awareness normalizes to inactive while preserving resolved evidence"
	)

	var reaction_save_id: String = str(
		reaction.call("get_semantic_save_id")
	)
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
	var world_state: Dictionary = snapshot.get(
		"session",
		{}
	).get("world_state", {})
	var saved_guard: Dictionary = (
		world_state.get(
			"persistent_entities",
			{}
		) as Dictionary
	).get("slice.guard", {})
	var saved_reaction: Dictionary = (
		world_state.get(
			"semantic_owners",
			{}
		) as Dictionary
	).get(reaction_save_id, {})
	assert_true.call(
		committed
		and generation > 0
		and saved_guard.get("life_state", &"")
			== VarkGuard.LIFE_UNCONSCIOUS
		and saved_reaction.get("state", &"")
			== &"inactive"
		and int(saved_reaction.get("heard_count", 0)) == 1
		and saved_reaction.get("last_heard_kind", &"")
			== VarkGuard.CRUDE_HOSTILE_IMPACT_SOUND_KIND,
		"Phase 4.7 hostile actor/life-state and resolved awareness evidence are captured as ordinary detached semantic save truth"
	)

	var old_guard: VarkGuard = guard
	var dead_queued: bool = guard.request_life_state(
		VarkGuard.LIFE_DEAD
	)
	await _completed_physics_frame(tree)
	var mutated_dead: bool = (
		guard.get_life_state() == VarkGuard.LIFE_DEAD
	)
	var loaded: bool = bool(
		application.call("quickload_latest")
	)

	world = application.get("current_world") as Node3D
	session = application.get("current_session") as Node
	guard = world.get_node("Guard") as VarkGuard
	reaction = world.get_node("Guard/Reaction")
	var restored_actor: Dictionary = guard.query_actor_state()
	var restored_reaction: Dictionary = reaction.call(
		"get_debug_summary"
	)

	assert_true.call(
		dead_queued
		and mutated_dead
		and loaded
		and not is_instance_valid(old_guard)
		and restored_actor.get("life_state", &"")
			== VarkGuard.LIFE_UNCONSCIOUS
		and bool(restored_actor.get("body_state", false))
		and not bool(
			restored_actor.get("navigation_active", true)
		)
		and restored_reaction.get("state", &"")
			== &"inactive"
		and int(restored_reaction.get("heard_count", 0)) == 1
		and restored_reaction.get("last_heard_kind", &"")
			== VarkGuard.CRUDE_HOSTILE_IMPACT_SOUND_KIND
		and int(session.call(
			"get_pending_semantic_event_count"
		)) == 0,
		"Phase 4.7 quickload restores coherent hostile actor/awareness state without replaying the attack, impact sound, or life-state event"
	)

	await _completed_physics_frame(tree)
	await _completed_physics_frame(tree)
	var after_resume: Dictionary = reaction.call(
		"get_debug_summary"
	)
	assert_true.call(
		guard.get_life_state() == VarkGuard.LIFE_UNCONSCIOUS
		and after_resume.get("state", &"") == &"inactive"
		and int(after_resume.get("heard_count", 0)) == 1,
		"Phase 4.7 restored hostile outcome remains stable when ordinary simulation resumes"
	)

	if application.get("current_session") != null:
		application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame
	Input.action_release("attack")
	_cleanup_test_storage()


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
		"Phase 4.7 regression must launch the real Integrated Slice."
	)
	var ready: bool = await _wait_for_navigation_ready(
		tree,
		application.get("current_world") as Node,
		240
	)
	assert(
		ready,
		"Phase 4.7 regression requires the slice navigation rebuild."
	)
	return application


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


func _cleanup_test_storage() -> void:
	var final_path: String = (
		TEST_SAVE_DIRECTORY
		+ "/quicksave.varksave"
	)
	for path: String in [
		final_path,
		final_path + ".new",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path)
			)
	var absolute_dir: String = ProjectSettings.globalize_path(
		TEST_SAVE_DIRECTORY
	)
	if DirAccess.dir_exists_absolute(absolute_dir):
		DirAccess.remove_absolute(absolute_dir)
