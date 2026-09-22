extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const WorldSession = preload("res://application/world_session.gd")
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _assert_same_door_integration()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_same_door_integration() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Integrated Slice"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([SLICE_PATH])
	)
	get_root().add_child(application)
	await process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var session := application.get("current_session") as Node
	var player := application.get("current_player") as CharacterBody3D
	var ready: bool = await _wait_for_navigation_ready(world, 360)

	var guard := (
		world.get_node_or_null("Guard") as VarkGuard
		if world != null else null
	)
	var door := (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null else null
	)
	var propagation := (
		world.get_node_or_null("AcousticPropagation") as VarkAcousticPropagation
		if world != null else null
	)
	var north_space := (
		world.get_node_or_null("NorthSpace") as VarkAcousticSpace
		if world != null else null
	)
	var reaction: Node = (
		world.get_node_or_null("Guard/Reaction")
		if world != null else null
	)

	_assert_true(
		launched
		and ready
		and world != null
		and session != null
		and player != null
		and guard != null
		and door != null
		and propagation != null
		and north_space != null
		and reaction != null,
		"5.7 real Integrated Slice launches the one ordinary door with guard navigation, perception, acoustics, and save ownership"
	)
	if (
		not ready
		or world == null
		or session == null
		or player == null
		or guard == null
		or door == null
		or propagation == null
		or north_space == null
		or reaction == null
	):
		await _cleanup(application)
		return

	# Keep the first proof about authored patrol/navigation rather than incidental
	# player perception while the guard approaches the carved door link.
	reaction.call("reset_reaction")
	reaction.set_physics_process(false)
	var used_before: int = int(
		guard.get_debug_summary().get("door_use_count", 0)
	)
	var npc_used_door: bool = (
		used_before > 0
		or await _wait_for_guard_door_use(guard, 420)
	)
	var door_opened_for_guard: bool = await _wait_for_door_phase(
		door,
		VarkOrdinaryDoor.PHASE_OPEN,
		180
	)
	var post_use: Dictionary = world.call(
		"get_door_integration_debug_summary"
	)
	var link_summary: Dictionary = post_use.get("navigation_link", {})
	var portal_after_use: Dictionary = post_use.get("acoustic_portal", {})
	_assert_true(
		npc_used_door
		and door_opened_for_guard
		and post_use.get("persistent_id", "") == "slice.door"
		and post_use.get("door_id", &"") == &"door.slice"
		and post_use.get("guard_door_id", "") == "door.slice"
		and int(post_use.get("guard_door_use_count", 0)) >= 1
		and bool(link_summary.get("configured", false))
		and bool(link_summary.get("map_bound", false))
		and bool(portal_after_use.get("uses_door", false))
		and portal_after_use.get("door_id", &"") == &"door.slice",
		"5.7 the same persistent door owns the explicit nav link used by the guard and the acoustic portal consumed by perception"
	)

	guard.set_physics_process(false)
	player.set_physics_process(false)
	door.set_physics_process(false)
	guard.velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -2.5)
	player.global_position = Vector3(0.0, 0.0, 2.5)
	guard.look_at(player.global_position, Vector3.UP, true)
	await _completed_physics_frame()

	var closed_applied: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_CLOSED,
		"open_fraction": 0.0,
		"motion_blocked": false,
	})
	await _settle_physics_frames(2)
	reaction.call("reset_reaction")
	guard.look_at(player.global_position, Vector3.UP, true)
	reaction.call("sample_vision_now")
	var closed_route: Dictionary = propagation.evaluate(
		player.global_position,
		1.0,
		guard.global_position
	)
	var closed_summary: Dictionary = world.call(
		"get_door_integration_debug_summary"
	)
	var closed_portal: Dictionary = closed_summary.get(
		"acoustic_portal",
		{}
	)

	var open_applied: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_OPEN,
		"open_fraction": 1.0,
		"motion_blocked": false,
	})
	await _settle_physics_frames(2)
	reaction.call("reset_reaction")
	guard.look_at(player.global_position, Vector3.UP, true)
	reaction.call("sample_vision_now")
	var open_route: Dictionary = propagation.evaluate(
		player.global_position,
		1.0,
		guard.global_position
	)
	var open_summary: Dictionary = world.call(
		"get_door_integration_debug_summary"
	)
	var open_portal: Dictionary = open_summary.get(
		"acoustic_portal",
		{}
	)

	_assert_true(
		closed_applied
		and open_applied
		and closed_summary.get("phase", &"")
			== VarkOrdinaryDoor.PHASE_CLOSED
		and not bool(closed_summary.get("navigation_passage_open", true))
		and is_zero_approx(float(closed_summary.get("acoustic_openness", -1.0)))
		and bool(closed_summary.get("vision_blocked", false))
		and closed_summary.get("vision_blocker", "") == "OrdinaryDoor"
		and is_equal_approx(
			float(closed_portal.get("door_openness", -1.0)),
			0.0
		)
		and open_summary.get("phase", &"")
			== VarkOrdinaryDoor.PHASE_OPEN
		and bool(open_summary.get("navigation_passage_open", false))
		and is_equal_approx(
			float(open_summary.get("acoustic_openness", -1.0)),
			1.0
		)
		and not bool(open_summary.get("vision_blocked", true))
		and is_equal_approx(
			float(open_portal.get("door_openness", -1.0)),
			1.0
		)
		and bool(closed_route.get("route_found", false))
		and bool(open_route.get("route_found", false))
		and (closed_route.get("portal_route", []) as Array)
			== [&"portal.slice.door"]
		and (open_route.get("portal_route", []) as Array)
			== [&"portal.slice.door"]
		and float(open_route.get("propagated_strength", 0.0))
			> float(closed_route.get("propagated_strength", 0.0)) * 2.0,
		"5.7 one CLOSED/OPEN semantic door state coherently closes/opens nav passage, blocks/clears real guard LOS, and muffles/opens the same acoustic portal"
	)

	var door_collision := door.get_node("CollisionShape3D") as CollisionShape3D
	var open_leaf_positions: Dictionary = _positions_across_leaf(
		door,
		door_collision,
		0.55
	)
	guard.global_position = open_leaf_positions.get("guard", Vector3.ZERO)
	player.global_position = open_leaf_positions.get("player", Vector3.ZERO)
	guard.look_at(player.global_position, Vector3.UP, true)
	reaction.call("reset_reaction")
	reaction.call("sample_vision_now")
	var open_leaf_summary: Dictionary = reaction.call("get_debug_summary")
	var open_leaf_passed: bool = (
		north_space.contains_world_point(guard.global_position)
		and north_space.contains_world_point(player.global_position)
		and bool(open_leaf_summary.get("last_vision_blocked", false))
		and open_leaf_summary.get("last_vision_blocker", "") == "OrdinaryDoor"
	)
	if not open_leaf_passed:
		print(
			"5.7 open-leaf LOS diagnostics: ",
			{
				"guard_position": guard.global_position,
				"player_position": player.global_position,
				"door_collision_transform": (
					door.global_transform * door_collision.transform
				),
				"guard_in_north": north_space.contains_world_point(
					guard.global_position
				),
				"player_in_north": north_space.contains_world_point(
					player.global_position
				),
				"vision": open_leaf_summary,
			}
		)
	_assert_true(
		open_leaf_passed,
		"5.7 fully OPEN clears the doorway opening but the rotated leaf still blocks guard LOS when the player hides behind it in the same room"
	)

	var partial_applied: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_OPENING,
		"open_fraction": 0.5,
		"motion_blocked": false,
	})
	await _settle_physics_frames(2)
	var partial_leaf_positions: Dictionary = _positions_across_leaf(
		door,
		door_collision,
		0.45
	)
	guard.global_position = partial_leaf_positions.get("guard", Vector3.ZERO)
	player.global_position = partial_leaf_positions.get("player", Vector3.ZERO)
	guard.look_at(player.global_position, Vector3.UP, true)
	reaction.call("reset_reaction")
	reaction.call("sample_vision_now")
	var partial_leaf_summary: Dictionary = reaction.call("get_debug_summary")
	var partial_leaf_passed: bool = (
		partial_applied
		and bool(partial_leaf_summary.get("last_vision_blocked", false))
		and partial_leaf_summary.get("last_vision_blocker", "") == "OrdinaryDoor"
	)
	if not partial_leaf_passed:
		print(
			"5.7 partial-leaf LOS diagnostics: ",
			{
				"partial_applied": partial_applied,
				"guard_position": guard.global_position,
				"player_position": player.global_position,
				"door_collision_transform": (
					door.global_transform * door_collision.transform
				),
				"vision": partial_leaf_summary,
			}
		)
	_assert_true(
		partial_leaf_passed,
		"5.7 a partially open rotated leaf remains a real production guard LOS occluder"
	)

	var reopened_for_save: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_OPEN,
		"open_fraction": 1.0,
		"motion_blocked": false,
	})
	await _settle_physics_frames(2)
	_assert_true(
		reopened_for_save,
		"5.7 returns the same door to OPEN before save/restore verification"
	)

	# Save OPEN truth, mutate the source world CLOSED, then quickload. The fresh
	# world must reconstruct all derived consumers from the saved semantic door
	# state without replaying a door interaction/state consequence.
	var coordinator: Node = application.get_node("SaveCoordinator")
	var generation: int = int(application.call("request_quicksave"))
	var committed: bool = await _wait_for_save_status(
		coordinator,
		generation,
		&"committed",
		90
	)
	var source_mutated_closed: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_CLOSED,
		"open_fraction": 0.0,
		"motion_blocked": false,
	})
	var old_world_instance_id: int = world.get_instance_id()
	var loaded: bool = bool(application.call("quickload_latest"))
	var replacement_ready: bool = await _wait_for_replacement_world(
		application,
		old_world_instance_id,
		300
	)

	var restored_world := application.get("current_world") as Node3D
	var restored_session := application.get("current_session") as Node
	var restored_player := application.get(
		"current_player"
	) as CharacterBody3D
	var restored_guard := (
		restored_world.get_node_or_null("Guard") as VarkGuard
		if restored_world != null else null
	)
	var restored_door := (
		restored_world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if restored_world != null else null
	)
	var restored_propagation := (
		restored_world.get_node_or_null(
			"AcousticPropagation"
		) as VarkAcousticPropagation
		if restored_world != null else null
	)
	var restored_reaction: Node = (
		restored_world.get_node_or_null("Guard/Reaction")
		if restored_world != null else null
	)
	if (
		restored_player != null
		and restored_guard != null
		and restored_reaction != null
	):
		restored_player.set_physics_process(false)
		restored_guard.set_physics_process(false)
		restored_reaction.set_physics_process(false)
		restored_player.global_position = Vector3(0.0, 0.0, 2.5)
		restored_guard.global_position = Vector3(0.0, 0.0, -2.5)
		restored_player.velocity = Vector3.ZERO
		restored_guard.velocity = Vector3.ZERO
		restored_guard.look_at(
			restored_player.global_position,
			Vector3.UP,
			true
		)
		restored_reaction.call("reset_reaction")
		restored_reaction.call("sample_vision_now")
	var restored_route: Dictionary = (
		restored_propagation.evaluate(
			restored_player.global_position,
			1.0,
			restored_guard.global_position
		)
		if (
			restored_propagation != null
			and restored_player != null
			and restored_guard != null
		)
		else {}
	)
	var restored_summary: Dictionary = (
		restored_world.call("get_door_integration_debug_summary")
		if restored_world != null
		else {}
	)
	var restored_link: Dictionary = restored_summary.get(
		"navigation_link",
		{}
	)
	var restored_portal: Dictionary = restored_summary.get(
		"acoustic_portal",
		{}
	)

	_assert_true(
		committed
		and source_mutated_closed
		and loaded
		and replacement_ready
		and restored_world != null
		and restored_world.get_instance_id() != old_world_instance_id
		and restored_session != null
		and restored_player != null
		and restored_guard != null
		and restored_door != null
		and restored_propagation != null
		and restored_reaction != null
		and restored_summary.get("persistent_id", "") == "slice.door"
		and restored_summary.get("door_id", &"") == &"door.slice"
		and restored_summary.get("phase", &"")
			== VarkOrdinaryDoor.PHASE_OPEN
		and is_equal_approx(
			float(restored_summary.get("open_fraction", 0.0)),
			1.0
		)
		and bool(restored_summary.get("navigation_passage_open", false))
		and bool(restored_link.get("configured", false))
		and bool(restored_link.get("map_bound", false))
		and is_equal_approx(
			float(restored_summary.get("acoustic_openness", 0.0)),
			1.0
		)
		and bool(restored_portal.get("uses_door", false))
		and restored_portal.get("door_id", &"") == &"door.slice"
		and is_equal_approx(
			float(restored_portal.get("door_openness", 0.0)),
			1.0
		)
		and not bool(restored_summary.get("vision_blocked", true))
		and bool(restored_route.get("route_found", false))
		and (restored_route.get("portal_route", []) as Array)
			== [&"portal.slice.door"]
		and int(restored_session.call(
			"get_pending_semantic_event_count"
		)) == 0,
		"5.7 quickload restores the same OPEN door semantic owner and rebuilds nav, LOS, and acoustic consumer truth in the fresh world without replayed consequences"
	)

	await _cleanup(application)


func _positions_across_leaf(
	door: VarkOrdinaryDoor,
	door_collision: CollisionShape3D,
	offset: float
) -> Dictionary:
	var leaf_transform: Transform3D = (
		door.global_transform * door_collision.transform
	)
	var normal := Vector3(
		leaf_transform.basis.z.x,
		0.0,
		leaf_transform.basis.z.z
	).normalized()
	var center := Vector3(
		leaf_transform.origin.x,
		0.0,
		leaf_transform.origin.z
	)
	return {
		"guard": center - normal * offset,
		"player": center + normal * offset,
	}


func _wait_for_navigation_ready(world: Node3D, max_frames: int) -> bool:
	if world == null:
		return false
	for _index: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await physics_frame
		await process_frame
	return bool(world.get("navigation_ready"))


func _wait_for_guard_door_use(
	guard: VarkGuard,
	max_frames: int
) -> bool:
	for _index: int in max_frames:
		if int(guard.get_debug_summary().get("door_use_count", 0)) > 0:
			return true
		if not str(guard.get_debug_summary().get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return int(guard.get_debug_summary().get("door_use_count", 0)) > 0


func _wait_for_door_phase(
	door: VarkOrdinaryDoor,
	phase: StringName,
	max_frames: int
) -> bool:
	for _index: int in max_frames:
		if door.get_semantic_phase() == phase:
			return true
		await physics_frame
		await process_frame
	return door.get_semantic_phase() == phase


func _wait_for_save_status(
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
		if status.get("status", &"") in [
			&"cancelled",
			&"failed",
			&"superseded",
		]:
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_replacement_world(
	application: Node,
	old_world_instance_id: int,
	max_frames: int
) -> bool:
	for _index: int in max_frames:
		var world: Node = application.get("current_world")
		var session: Node = application.get("current_session")
		if (
			world != null
			and world.get_instance_id() != old_world_instance_id
			and session != null
			and int(session.get("state")) == WorldSession.State.PLAYING
			and bool(world.get("navigation_ready"))
		):
			return true
		await physics_frame
		await process_frame
	return false


func _settle_physics_frames(count: int) -> void:
	for _index: int in maxi(count, 1):
		await physics_frame
		await process_frame


func _completed_physics_frame() -> void:
	await physics_frame
	await process_frame


func _cleanup(application: Node) -> void:
	if application == null or not is_instance_valid(application):
		return
	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	failures.append(message)
	push_error("FAIL: " + message)


func _print_summary() -> void:
	print("")
	print("==============================")
	if failures.is_empty():
		print("ALL DOOR INTEGRATION TESTS PASSED")
		return
	print("%d DOOR INTEGRATION TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
