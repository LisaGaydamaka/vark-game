extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const OrdinaryPropScript = preload("res://gameplay/props/ordinary_prop.gd")
const GuardScript = preload("res://gameplay/npc/vark_guard.gd")

const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _assert_integrated_slice()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_integrated_slice() -> void:
	var default_application: Node = ApplicationScene.instantiate()
	var default_labels: PackedStringArray = default_application.get(
		"development_launch_labels"
	)
	var default_paths: PackedStringArray = default_application.get(
		"development_launch_resource_paths"
	)
	_assert_true(
		default_labels.has("Integrated Slice")
		and default_paths.has(SLICE_PATH),
		"Application Development Launch exposes the 3.12 Integrated Slice"
	)
	default_application.free()

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
	var player := application.get("current_player") as CharacterBody3D
	var session := application.get("current_session") as Node
	var ready: bool = await _wait_for_navigation_ready(world, 240)

	var guard := (
		world.get_node_or_null("Guard") as VarkGuard
		if world != null
		else null
	)
	var door := (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null
		else null
	)
	var propagation := (
		world.get_node_or_null("AcousticPropagation")
			as VarkAcousticPropagation
		if world != null
		else null
	)
	var exposure := (
		world.get_node_or_null("GameplayExposure")
			as VarkGameplayExposure
		if world != null
		else null
	)
	var light_gem := (
		world.get_node_or_null("ExposureHUD/Panel")
			as VarkLightGem
		if world != null
		else null
	)
	var objective := (
		world.get_node_or_null("ObjectiveState")
			as VarkSimpleObjectiveState
		if world != null
		else null
	)
	var objective_trigger := (
		world.get_node_or_null("ObjectiveTrigger")
			as VarkSemanticRouteTrigger
		if world != null
		else null
	)
	var exit_trigger := (
		world.get_node_or_null("ExitTrigger")
			as VarkSemanticRouteTrigger
		if world != null
		else null
	)
	var player_listener := (
		world.get_node_or_null("Player/SpeechListener")
			as VarkAcousticListener
		if world != null
		else null
	)
	var guard_listener := (
		world.get_node_or_null("Guard/Hearing")
			as VarkAcousticListener
		if world != null
		else null
	)
	var speech := (
		world.get_node_or_null("Guard/Speech")
			as VarkWorldSpeechSpeaker
		if world != null
		else null
	)
	var speech_label := (
		world.get_node_or_null("Guard/Speech/SpeechLabel") as Label3D
		if world != null
		else null
	)
	var reaction: Node = (
		world.get_node_or_null("Guard/Reaction")
		if world != null
		else null
	)
	var footsteps: Node = (
		world.get_node_or_null("FootstepEmitter")
		if world != null
		else null
	)
	var stone_surface: Area3D = (
		world.get_node_or_null("StoneSurface") as Area3D
		if world != null
		else null
	)
	var carpet_surface: Area3D = (
		world.get_node_or_null("CarpetSurface") as Area3D
		if world != null
		else null
	)
	var tile_surface: Area3D = (
		world.get_node_or_null("TileSurface") as Area3D
		if world != null
		else null
	)
	var crate_a := (
		world.get_node_or_null("CrateA") as VarkOrdinaryProp
		if world != null
		else null
	)
	var crate_b := (
		world.get_node_or_null("CrateB") as VarkOrdinaryProp
		if world != null
		else null
	)
	var gameplay_light := (
		world.get_node_or_null("NorthGameplayLight") as VarkGameplayLight
		if world != null
		else null
	)
	var crouch_cover := (
		world.get_node_or_null("Geometry/CrouchCover") as StaticBody3D
		if world != null
		else null
	)
	var rendered_lights: Array[Light3D] = _get_gameplay_world_rendered_lights(world)

	var propagation_summary: Dictionary = (
		propagation.get_debug_summary()
		if propagation != null
		else {}
	)
	var navigation_summary: Dictionary = (
		world.call("get_navigation_debug_summary")
		if world != null and world.has_method(
			"get_navigation_debug_summary"
		)
		else {}
	)
	var persistent_guard: Dictionary = (
		session.call("lookup_persistent_entity", "slice.guard")
		if session != null
		else {}
	)
	var semantic_guard: Dictionary = (
		session.call("lookup_content_entity", "guard.slice")
		if session != null
		else {}
	)
	_assert_true(
		launched
		and world != null
		and world.name == &"IntegratedSlice"
		and world.scene_file_path == SLICE_PATH
		and session != null
		and player != null,
		"Integrated Slice scene launches through the production Application → WorldSession path"
	)
	_assert_true(
		ready
		and player != null
		and session != null
		and guard != null
		and guard.get_script() == GuardScript
		and door != null
		and propagation != null
		and exposure != null
		and light_gem != null
		and objective != null
		and objective_trigger != null
		and exit_trigger != null
		and player_listener != null
		and guard_listener != null
		and speech != null
		and speech_label != null
		and reaction != null
		and footsteps != null
		and stone_surface != null
		and carpet_surface != null
		and tile_surface != null
		and crate_a != null
		and crate_b != null
		and gameplay_light != null
		and crouch_cover != null
		and rendered_lights.size() == 1
		and rendered_lights[0] == gameplay_light
		and gameplay_light.shadow_enabled
		and crate_a.get_script() == OrdinaryPropScript
		and crate_b.get_script() == OrdinaryPropScript
		and persistent_guard.get("node") == guard
		and semantic_guard.get("node") == guard,
		"One playable slice contains the real guard, door, props, acoustics, exposure/light-gem observer, typed speech, objective, exit, and stable actor identity; its only rendered shadow light is the gameplay light sampled by exposure"
	)
	if (
		not ready
		or player == null
		or session == null
		or guard == null
		or door == null
		or propagation == null
		or exposure == null
		or light_gem == null
		or objective == null
		or objective_trigger == null
		or exit_trigger == null
		or speech == null
		or reaction == null
		or footsteps == null
		or stone_surface == null
		or carpet_surface == null
		or tile_surface == null
		or crate_a == null
	):
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	_assert_true(
		int(navigation_summary.get("polygon_count", 0)) > 0
		and bool(navigation_summary.get("guard_configured", false))
		and int(propagation_summary.get("space_count", 0)) == 2
		and int(propagation_summary.get("portal_count", 0)) == 1
		and int(propagation_summary.get("listener_count", 0)) == 2
		and int(propagation_summary.get("door_count", 0)) == 1
		and stone_surface.has_method("get_surface_summary")
		and carpet_surface.has_method("get_surface_summary")
		and tile_surface.has_method("get_surface_summary")
		and is_equal_approx(
			float((
				stone_surface.call("get_surface_summary") as Dictionary
			).get("footstep_strength", 0.0)),
			0.45
		)
		and is_equal_approx(
			float((
				carpet_surface.call("get_surface_summary") as Dictionary
			).get("footstep_strength", 0.0)),
			0.09
		)
		and (carpet_surface.call("get_surface_summary") as Dictionary).get("loudness_id", &"") == &"quiet"
		and (stone_surface.call("get_surface_summary") as Dictionary).get("loudness_id", &"") == &"normal"
		and (tile_surface.call("get_surface_summary") as Dictionary).get("loudness_id", &"") == &"loud"
		and is_equal_approx(
			float((
				tile_surface.call("get_surface_summary") as Dictionary
			).get("footstep_strength", 0.0)),
			0.90
		),
		"The slice reuses one baked nav route, one door-controlled acoustic portal, two listeners, and explicit quiet-carpet / normal-stone / loud-tile footstep tiers"
	)

	var guard_start: Vector3 = guard.global_position
	var guard_advanced: bool = await _wait_for_guard_motion(guard, guard_start, 60)
	var guard_used_door: bool = await _wait_for_guard_door_use(guard, 300)
	_assert_true(
		guard_advanced
		and guard_used_door
		and int(guard.get_debug_summary().get("door_use_count", 0)) >= 1,
		"The same patrolling guard follows baked navigation and uses the same ordinary door inside the integrated route"
	)

	footsteps.call("set_emission_enabled", false)
	guard.movement_speed = 0.0
	guard.global_position = Vector3(0.0, 0.0, -2.5)
	guard.velocity = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.0, 2.5)
	player.velocity = Vector3.ZERO
	for _frame_index: int in 3:
		await physics_frame
		await process_frame

	var closed_applied: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_CLOSED,
		"open_fraction": 0.0,
		"motion_blocked": false,
	})
	var closed_route: Dictionary = propagation.evaluate(
		player.global_position,
		0.45,
		guard.global_position
	)
	door.request_open(player)
	var opened: bool = await _wait_for_door_phase(
		door,
		VarkOrdinaryDoor.PHASE_OPEN,
		120
	)
	var open_route: Dictionary = propagation.evaluate(
		player.global_position,
		0.45,
		guard.global_position
	)
	_assert_true(
		closed_applied
		and opened
		and bool(closed_route.get("route_found", false))
		and bool(open_route.get("route_found", false))
		and (closed_route.get("portal_route", []) as Array)
			== [&"portal.slice.door"]
		and (open_route.get("portal_route", []) as Array)
			== [&"portal.slice.door"]
		and float(open_route.get("propagated_strength", 0.0))
			> float(closed_route.get("propagated_strength", 0.0)) * 5.0,
		"Opening the same ordinary door materially increases the same acoustic route used by the guard and speech"
	)

	reaction.call("reset_reaction")
	player.global_position = Vector3(0.0, 0.0, 2.5)
	guard.global_position = Vector3(0.0, 0.0, -2.5)
	for _frame_index: int in 3:
		await physics_frame
		await process_frame
	var step_queued: bool = bool(footsteps.call("emit_step_now"))
	await _completed_physics_frame()
	var footstep_summary: Dictionary = footsteps.call("get_debug_summary")
	var reaction_summary: Dictionary = reaction.call("get_debug_summary")
	var speech_summary: Dictionary = speech.get_debug_summary()
	var player_perception: Dictionary = player_listener.get_last_perception()
	_assert_true(
		step_queued
		and int(footstep_summary.get("queued_count", 0)) == 1
		and reaction_summary.get("state", &"") == &"heard_noise"
		and int(reaction_summary.get("heard_count", 0)) == 1
		and reaction_summary.get("last_heard_kind", &"") == &"footstep.stone"
		and footstep_summary.get("last_stance", "") == "standing"
		and is_equal_approx(
			float(footstep_summary.get("last_base_strength", 0.0)),
			0.45
		)
		and is_equal_approx(
			float(footstep_summary.get("last_strength", 0.0)),
			0.45
		)
		and int(reaction_summary.get("speech_reaction_count", 0)) == 1
		and int(speech_summary.get("queued_count", 0)) == 1
		and bool(speech_summary.get("utterance_active", false))
		and bool(player_perception.get("heard", false))
		and player_perception.get("kind", &"")
			== &"speech.slice.heard_noise"
		and speech_label.visible
		and speech_label.text == "What was that?",
		"A real loud stone footstep crosses the acoustic graph, triggers the guard reaction, and produces one acoustically gated world-space spoken response"
	)

	guard_listener.clear_perception()
	reaction.call("reset_reaction")
	var crouched_for_sound: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.CROUCHED
	)
	var crouched_step_queued: bool = bool(footsteps.call("emit_step_now"))
	await _completed_physics_frame()
	var crouched_footstep_summary: Dictionary = footsteps.call(
		"get_debug_summary"
	)
	var crouched_guard_perception: Dictionary = guard_listener.get_last_perception()
	var crouched_reaction_summary: Dictionary = reaction.call(
		"get_debug_summary"
	)
	_assert_true(
		crouched_for_sound
		and crouched_step_queued
		and int(crouched_footstep_summary.get("queued_count", 0)) == 2
		and crouched_footstep_summary.get("last_stance", "") == "crouched"
		and is_equal_approx(
			float(crouched_footstep_summary.get("last_base_strength", 0.0)),
			0.45
		)
		and is_equal_approx(
			float(crouched_footstep_summary.get("last_strength", 0.0)),
			0.45 * 0.45
		)
		and not bool(crouched_guard_perception.get("heard", true))
		and crouched_reaction_summary.get("state", &"") == &"calm"
		and int(crouched_reaction_summary.get("speech_reaction_count", 0)) == 1,
		"Crouching preserves the stone surface identity but lowers each semantic footstep enough for the same cross-room guard-hearing case to become muted"
	)


	var standing_for_vision: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.STANDING
	)
	# Real patrol/door behavior has already been proven above. Freeze only guard
	# locomotion while comparing the same controlled LOS geometry across the
	# player's multi-frame stance transition.
	guard.set_physics_process(false)
	reaction.call("reset_reaction")
	player.global_position = Vector3(0.0, 0.0, -2.4)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -5.6)
	guard.velocity = Vector3.ZERO
	guard.look_at(player.global_position, Vector3.UP, true)
	for _frame_index: int in 2:
		await physics_frame
		await process_frame

	var standing_lit_summary: Dictionary = exposure.sample_now()
	var standing_saw_player: bool = bool(
		reaction.call("sample_vision_now")
	)
	var standing_vision_summary: Dictionary = reaction.call(
		"get_debug_summary"
	)
	var standing_target: Vector3 = standing_vision_summary.get(
		"last_vision_target",
		Vector3.ZERO
	)

	var crouched_for_vision: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.CROUCHED
	)
	var crouched_lit_summary: Dictionary = exposure.sample_now()
	var crouched_saw_player: bool = bool(
		reaction.call("sample_vision_now")
	)
	var crouched_vision_summary: Dictionary = reaction.call(
		"get_debug_summary"
	)
	var crouched_target: Vector3 = crouched_vision_summary.get(
		"last_vision_target",
		Vector3.ZERO
	)
	var vision_contract_passed: bool = (
		standing_for_vision
		and crouched_for_vision
		and float(standing_lit_summary.get("exposure", 0.0)) > 0.45
		and float(crouched_lit_summary.get("exposure", 0.0)) > 0.28
		and is_equal_approx(
			light_gem.get_gem_value(),
			float(crouched_lit_summary.get("exposure", -1.0))
		)
		and light_gem.get_debug_text().contains(
			"light.slice_north ON"
		)
		and standing_saw_player
		and float(standing_vision_summary.get("visual_suspicion", 0.0)) > 0.0
		and standing_vision_summary.get("awareness_state", &"") != &"alerted"
		and not bool(
			standing_vision_summary.get("last_vision_blocked", true)
		)
		and not crouched_saw_player
		# Suspicion is intentionally historical and may have accumulated while
		# the multi-frame crouch transition was still visibly standing. This
		# contract only compares the final LOS sample after the stance settles.
		and crouched_vision_summary.get("awareness_state", &"") != &"alerted"
		and bool(crouched_vision_summary.get("last_vision_blocked", false))
		and crouched_vision_summary.get("last_vision_blocker", "")
			== "CrouchCover"
		and standing_target.y > crouched_target.y + 0.40
	)
	if not vision_contract_passed:
		print(
			"3.12 crouch-cover diagnostics: ",
			{
				"standing_stance_ready": standing_for_vision,
				"crouched_stance_ready": crouched_for_vision,
				"standing_exposure": standing_lit_summary.get("exposure", 0.0),
				"crouched_exposure": crouched_lit_summary.get("exposure", 0.0),
				"standing_seen": standing_saw_player,
				"standing_state": standing_vision_summary.get("awareness_state", &""),
				"standing_suspicion": standing_vision_summary.get("visual_suspicion", 0.0),
				"standing_blocked": standing_vision_summary.get("last_vision_blocked", true),
				"standing_blocker": standing_vision_summary.get("last_vision_blocker", ""),
				"crouched_seen": crouched_saw_player,
				"crouched_state": crouched_vision_summary.get("awareness_state", &""),
				"crouched_suspicion": crouched_vision_summary.get("visual_suspicion", 0.0),
				"crouched_blocked": crouched_vision_summary.get("last_vision_blocked", false),
				"crouched_blocker": crouched_vision_summary.get("last_vision_blocker", ""),
				"standing_target": standing_target,
				"crouched_target": crouched_target,
				"target_drop": standing_target.y - crouched_target.y,
				"guard_position": guard.global_position,
				"player_position": player.global_position,
			}
		)
	_assert_true(
		vision_contract_passed,
		"Crouching lowers the real guard LOS target enough for low cover to block sight while the player remains gameplay-lit"
	)
	guard.set_physics_process(true)

	var prop_pickup: bool = bool(player.call("try_carry_prop", crate_a))
	var carry := player.get("prop_carry") as PlayerPropCarry
	var prop_thrown: bool = false
	if prop_pickup and carry != null:
		prop_thrown = carry.throw_held()
	_assert_true(
		prop_pickup
		and prop_thrown
		and not bool(player.call("is_carrying_prop"))
		and crate_a.get_semantic_phase() == VarkOrdinaryProp.PHASE_MOVING
		and crate_a.get_motion_kind() == VarkOrdinaryProp.MOTION_THROWN,
		"The accepted Junk carry/throw implementation remains live in the same world as guard hearing, door acoustics, and objectives"
	)

	var initial_exit: Dictionary = objective.query_exit(&"exit.slice")
	var blocked_queued: bool = exit_trigger.queue_for_body(player)
	await _completed_physics_frame()
	var blocked_exit: Dictionary = objective.query_exit(&"exit.slice")
	var objective_queued: bool = objective_trigger.queue_for_body(player)
	await _completed_physics_frame()
	var completed_objective: Dictionary = objective.query_objective(
		&"objective.slice"
	)
	var unlocked_exit: Dictionary = objective.query_exit(&"exit.slice")
	var finish_queued: bool = exit_trigger.queue_for_body(player)
	await _completed_physics_frame()
	var finished_exit: Dictionary = objective.query_exit(&"exit.slice")
	_assert_true(
		not bool(initial_exit.get("unlocked", true))
		and blocked_queued
		and int(blocked_exit.get("blocked_attempt_count", 0)) == 1
		and not bool(blocked_exit.get("mission_complete", true))
		and objective_queued
		and bool(completed_objective.get("complete", false))
		and bool(unlocked_exit.get("unlocked", false))
		and finish_queued
		and bool(finished_exit.get("mission_complete", false)),
		"The integrated route still has a real semantic beginning/end: early exit blocks, objective unlocks it, and the later exit completes the slice"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _get_gameplay_world_rendered_lights(world: Node) -> Array[Light3D]:
	var result: Array[Light3D] = []
	if not (world is Node3D):
		return result
	var gameplay_world: World3D = (world as Node3D).get_world_3d()
	var nodes: Array[Node] = [world]
	nodes.append_array(world.find_children("*", "", true, false))
	for node: Node in nodes:
		if not (node is Light3D):
			continue
		var light := node as Light3D
		if light.visible and light.get_world_3d() == gameplay_world:
			result.append(light)
	return result


func _request_player_stance(
	player: CharacterBody3D,
	stance: int
) -> bool:
	if player == null:
		return false
	var crouch := player.get("crouch") as PlayerCrouch
	if crouch == null:
		return false
	crouch.request_stance(stance)
	var expected: String = (
		"crouched"
		if stance == PlayerCrouch.Stance.CROUCHED
		else "standing"
	)
	for _frame_index: int in 45:
		await physics_frame
		await process_frame
		var movement_state: Dictionary = player.call(
			"get_movement_semantic_state"
		)
		if movement_state.get("stance", "") == expected:
			return true
	return false


func _wait_for_navigation_ready(world: Node, max_frames: int) -> bool:
	if world == null:
		return false
	for _frame_index: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await physics_frame
		await process_frame
	return bool(world.get("navigation_ready"))


func _wait_for_guard_motion(
	guard: VarkGuard,
	start_position: Vector3,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		if guard.global_position.distance_to(start_position) > 0.05:
			return true
		await physics_frame
		await process_frame
	return guard.global_position.distance_to(start_position) > 0.05


func _wait_for_guard_door_use(
	guard: VarkGuard,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		if int(guard.get_debug_summary().get("door_use_count", 0)) > 0:
			return true
		await physics_frame
		await process_frame
	return int(guard.get_debug_summary().get("door_use_count", 0)) > 0


func _wait_for_door_phase(
	door: VarkOrdinaryDoor,
	phase: StringName,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		if door.get_semantic_phase() == phase:
			return true
		await physics_frame
		await process_frame
	return door.get_semantic_phase() == phase


func _completed_physics_frame() -> void:
	await physics_frame
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
		print("ALL PHASE 3 INTEGRATION TESTS PASSED")
		return
	print("%d PHASE 3 INTEGRATION TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
