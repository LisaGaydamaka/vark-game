extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const AWARENESS_SCRIPT_PATH: String = "res://gameplay/npc/guard_awareness.gd"
const STATE_UNAWARE: StringName = &"unaware"
const STATE_SUSPICIOUS: StringName = &"suspicious"
const STATE_INVESTIGATING: StringName = &"investigating"
const STATE_SEARCHING: StringName = &"searching"
const STATE_ALERTED: StringName = &"alerted"
const STATE_RECOVERING: StringName = &"recovering"
const NAV_INVESTIGATE: StringName = &"investigate"
const NAV_SEARCH: StringName = &"search"
const NAV_PURSUIT: StringName = &"pursuit"
const PURSUIT_VISIBLE: StringName = &"visible"
const PURSUIT_CONTACT_GRACE: StringName = &"contact_grace"
const PURSUIT_CHECKING_LAST_KNOWN: StringName = &"checking_last_known"
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"
const TEST_SAVE_DIRECTORY: String = "user://vark_tests/phase55"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_cleanup_test_storage()
	if not _assert_awareness_script_compiles():
		_print_summary()
		quit(1)
		return
	await _assert_guard_awareness_state_machine()
	await _assert_advanced_local_search_behavior()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_awareness_script_compiles() -> bool:
	var source: String = FileAccess.get_file_as_string(AWARENESS_SCRIPT_PATH)
	var script := GDScript.new()
	script.source_code = source
	var error: Error = script.reload()
	_assert_true(
		error == OK,
		"Phase 5.4 reusable guard-awareness source compiles independently"
	)
	return error == OK


func _assert_guard_awareness_state_machine() -> void:
	var application: Node = await _launch_slice()
	if application == null:
		return

	var coordinator: Node = application.get_node("SaveCoordinator")
	coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)
	var world := application.get("current_world") as Node3D
	var session := application.get("current_session") as Node
	var player := application.get("current_player") as CharacterBody3D
	var guard := world.get_node("Guard") as VarkGuard
	var reaction := world.get_node("Guard/Reaction") as Node
	var light := world.get_node(
		"NorthGameplayLight"
	) as VarkGameplayLight
	var exposure := world.get_node(
		"GameplayExposure"
	) as VarkGameplayExposure

	var stance_settings: Resource = player.get("stance_settings") as Resource
	var player_sneak_speed: float = (
		float(stance_settings.get("crouch_speed"))
		if stance_settings != null
		else 0.0
	)
	var guard_walk_speed: float = guard.movement_speed
	var guard_investigate_speed: float = (
		guard.movement_speed * guard.investigate_speed_scale
	)
	var guard_run_speed: float = (
		guard.movement_speed * guard.pursuit_speed_scale
	)
	_assert_true(
		player_sneak_speed > 0.0
		and guard_walk_speed < player_sneak_speed
		and guard_investigate_speed < guard_walk_speed
		and guard_run_speed > guard_walk_speed
		and is_equal_approx(guard_walk_speed, 1.20)
		and is_equal_approx(guard_investigate_speed, 0.72)
		and is_equal_approx(guard_run_speed, 2.64),
		"Guard locomotion exposes exactly walking 1.20 < player sneak 2.00, investigating/search 0.72, and running/pursuit 2.64 semantic speeds"
	)
	_assert_true(
		is_equal_approx(reaction.vision_distance, 10.0)
		and is_equal_approx(reaction.vision_alert_retain_facing_dot, -0.42)
		and is_equal_approx(reaction.vision_confirm_exposure_threshold, 0.44)
		and is_equal_approx(reaction.vision_suspicion_rate_max, 2.00)
		and is_equal_approx(reaction.vision_suspicion_decay_per_second, 0.08)
		and is_equal_approx(reaction.vision_investigate_suspicion, 0.40)
		and is_equal_approx(reaction.investigation_stare_min, 1.50)
		and is_equal_approx(reaction.investigation_stare_max, 3.50)
		and is_equal_approx(reaction.engaged_hearing_investigate_threshold_scale, 1.00)
		and is_equal_approx(reaction.engaged_footstep_investigate_source_floor_scale, 1.00)
		and is_equal_approx(reaction.engaged_vision_exposure_threshold_scale, 0.90)
		and is_equal_approx(reaction.engaged_visual_suspicion_rate_scale, 1.25)
		and is_equal_approx(reaction.suspicion_seconds, 4.00)
		and is_equal_approx(reaction.investigation_seconds, 12.00)
		and is_equal_approx(reaction.search_seconds, 45.00)
		and is_equal_approx(reaction.pursuit_max_lost_seconds, 30.00)
		and is_equal_approx(reaction.recovery_seconds, 8.00)
		and reaction.observation_stare_repeat_limit == 2
		and is_equal_approx(reaction.observation_stare_reset_seconds, 12.00),
		"Production perception keeps Vark's continuous/stare architecture but uses the Thief-Gold-like range, persistence, alert-retention, and evidence tuning"
	)

	_configure_short_durations(reaction)
	# Freeze locomotion without erasing the authored base speed; semantic
	# awareness speed-profile assertions still need a meaningful baseline.
	guard.velocity = Vector3.ZERO
	guard.set_physics_process(false)
	light.gameplay_enabled = false
	light.visible = false
	exposure.sample_now()

	var weak_origin: Vector3 = (
		guard.global_position + Vector3(-0.15, 0.0, 0.05)
	)
	var weak_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"footstep.test",
		weak_origin,
		0.20
	))
	await _completed_physics_frame()
	var weak_summary: Dictionary = reaction.get_debug_summary()
	var weak_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		weak_queued
		and weak_summary.get("awareness_state", &"")
			== STATE_SUSPICIOUS
		and weak_summary.get("state", &"") == &"heard_noise"
		and int(weak_summary.get("heard_count", 0)) == 1
		and bool(weak_summary.get("investigation_stare_active", false))
		and _dict_vector(weak_summary, "investigation_stare_target").distance_to(
			weak_origin
		) <= 0.001
		and not bool(weak_nav.get("active", true))
		and bool(weak_nav.get("motion_paused", false))
		and bool(weak_nav.get("observation_paused", false)),
		(
			"Phase 5.4 weak local hearing evidence immediately stops/orients for a suspicious observation hold without manufacturing an investigation route "
			+ "(summary=%s nav=%s perception=%s)"
			% [
				str(weak_summary),
				str(weak_nav),
				str(
					(world.get_node("Guard/Hearing") as VarkAcousticListener)
					.get_last_perception()
				),
			]
		)
	)

	var weak_snapshot: Dictionary = reaction.call("capture_semantic_state")
	_assert_true(
		weak_snapshot.get("state", &"") == STATE_SUSPICIOUS
		and bool(weak_snapshot.get("investigation_stare_active", false))
		and float(weak_snapshot.get("investigation_stare_remaining_seconds", 0.0)) > 0.0,
		"Phase 5.4 a suspicious source-facing hold is semantic save truth and can outlive the frame that heard the cue"
	)

	var returned_unaware: bool = await _wait_for_awareness_state(
		reaction,
		STATE_UNAWARE,
		30
	)
	_assert_true(
		returned_unaware
		and not bool(
			guard.get_awareness_navigation_state().get(
				"active",
				true
			)
		),
		"Phase 5.4 suspicion decays by WorldSession gameplay time and returns to unaware patrol ownership"
	)
	# The weak-cue proof above intentionally consumed one observation slot.
	# Reset the fixture before the independent rapid-strong-cue chain so the
	# limiter assertion starts from a clean semantic episode.
	reaction.reset_reaction()

	var strong_origin: Vector3 = (
		guard.global_position + Vector3(0.35, 0.0, 0.15)
	)
	var strong_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"prop.impact",
		strong_origin,
		0.60
	))
	await _completed_physics_frame()
	var investigate_summary: Dictionary = reaction.get_debug_summary()
	var investigate_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		strong_queued
		and investigate_summary.get("awareness_state", &"")
			== STATE_INVESTIGATING
		and bool(investigate_summary.get("investigation_stare_active", false))
		and float(investigate_summary.get(
			"investigation_stare_remaining_seconds",
			0.0
		)) > 0.0
		and bool(investigate_nav.get("active", false))
		and investigate_nav.get("reason", &"") == NAV_INVESTIGATE
		and investigate_nav.get("movement_mode", &"") == &"investigating"
		and bool(investigate_nav.get("motion_paused", false))
		and is_equal_approx(
			float(investigate_nav.get("current_movement_speed", -1.0)),
			guard.movement_speed * guard.investigate_speed_scale
		)
		and _dict_vector(
			investigate_nav,
			"target_position"
		).distance_to(strong_origin) <= 0.001
		and _dict_vector(
			investigate_summary,
			"investigation_stare_target"
		).distance_to(strong_origin) <= 0.001,
		"Phase 5.4 investigation-worthy hearing makes an unaware guard stop, face the source, and hold a resolved stare before moving"
	)

	var stare_snapshot: Dictionary = reaction.call("capture_semantic_state")
	_assert_true(
		bool(stare_snapshot.get("investigation_stare_active", false))
		and float(stare_snapshot.get(
			"investigation_stare_duration_seconds",
			0.0
		)) >= reaction.investigation_stare_min
		and float(stare_snapshot.get(
			"investigation_stare_duration_seconds",
			0.0
		)) <= reaction.investigation_stare_max
		and float(stare_snapshot.get(
			"investigation_stare_remaining_seconds",
			0.0
		)) > 0.0
		and int(stare_snapshot.get("investigation_stare_serial", 0)) > 0,
		"Phase 5.4 the current randomized pre-investigation stare is resolved semantic save truth rather than an unsaved presentation timer"
	)

	var stare_finished: bool = await _wait_for_investigation_stare(
		reaction,
		false,
		30
	)
	var investigate_after_stare: Dictionary = reaction.get_debug_summary()
	var investigate_after_stare_nav: Dictionary = (
		guard.get_awareness_navigation_state()
	)
	_assert_true(
		stare_finished
		and investigate_after_stare.get("awareness_state", &"")
			== STATE_INVESTIGATING
		and not bool(investigate_after_stare_nav.get("motion_paused", true))
		and investigate_after_stare_nav.get("movement_mode", &"")
			== &"investigating",
		"Phase 5.4 investigation navigation begins only after the resolved stare completes"
	)

	var repeated_strong_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"prop.impact",
		strong_origin,
		0.60
	))
	await _completed_physics_frame()
	var repeated_stare: Dictionary = reaction.get_debug_summary()
	var repeated_stare_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		repeated_strong_queued
		and repeated_stare.get("awareness_state", &"") == STATE_INVESTIGATING
		and bool(repeated_stare.get("investigation_stare_active", false))
		and int(repeated_stare.get("investigation_stare_serial", 0))
			> int(stare_snapshot.get("investigation_stare_serial", 0))
		and bool(repeated_stare_nav.get("motion_paused", false))
		and _dict_vector(repeated_stare, "investigation_stare_target").distance_to(
			strong_origin
		) <= 0.001,
		"Phase 5.4 every new investigation-worthy heard cue while already investigating immediately restarts the stop-turn-stare gate"
	)
	var repeated_stare_finished: bool = await _wait_for_investigation_stare(
		reaction,
		false,
		30
	)
	_assert_true(
		repeated_stare_finished,
		"Phase 5.4 investigation movement resumes only after the restarted observation hold finishes"
	)

	var third_strong_origin: Vector3 = strong_origin + Vector3(-0.20, 0.0, 0.25)
	var third_strong_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"prop.impact",
		third_strong_origin,
		0.60
	))
	await _completed_physics_frame()
	var third_strong_summary: Dictionary = reaction.get_debug_summary()
	var third_strong_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		third_strong_queued
		and third_strong_summary.get("awareness_state", &"") == STATE_INVESTIGATING
		and not bool(third_strong_summary.get("investigation_stare_active", true))
		and int(third_strong_summary.get("observation_stare_chain_count", 0))
			== reaction.observation_stare_repeat_limit
		and float(third_strong_summary.get(
			"observation_stare_reset_remaining_seconds",
			0.0
		)) > 0.0
		and not bool(third_strong_nav.get("motion_paused", true))
		and _dict_vector(third_strong_nav, "target_position").distance_to(
			third_strong_origin
		) <= 0.001,
		"Phase 5.4 a third rapid investigation-worthy cue cannot restart an endless stare chain and instead commits immediately to investigating the newest local evidence"
	)

	await _settle_frames(40)
	var reset_strong_origin: Vector3 = strong_origin
	var reset_strong_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"prop.impact",
		reset_strong_origin,
		0.60
	))
	await _completed_physics_frame()
	var reset_stare_summary: Dictionary = reaction.get_debug_summary()
	_assert_true(
		reset_strong_queued
		and bool(reset_stare_summary.get("investigation_stare_active", false))
		and int(reset_stare_summary.get("observation_stare_chain_count", 0)) == 1,
		"Phase 5.4 the bounded stare allowance replenishes after a quiet gameplay-time interval"
	)
	await _wait_for_investigation_stare(reaction, false, 30)

	var reached_search: bool = await _wait_for_awareness_state(
		reaction,
		STATE_SEARCHING,
		30
	)
	var search_summary: Dictionary = reaction.get_debug_summary()
	var search_nav: Dictionary = guard.get_awareness_navigation_state()
	var resolved_search_target: Vector3 = search_summary.get(
		"investigation_target",
		Vector3.ZERO
	)
	var search_points: Array = search_summary.get("search_points", [])
	var search_index: int = int(search_summary.get("search_index", 0))
	var current_search_point: Vector3 = (
		search_points[search_index]
		if search_index >= 0 and search_index < search_points.size()
		else Vector3.ZERO
	)
	_assert_true(
		reached_search
		and bool(search_nav.get("active", false))
		and search_nav.get("reason", &"")
			== NAV_SEARCH
		and resolved_search_target.distance_to(
			strong_origin
		) <= 0.001
		and _dict_vector(search_summary, "search_anchor").distance_to(
			strong_origin
		) <= 0.001
		and search_points.size() >= 2
		and _dict_vector(
			search_nav,
			"target_position"
		).distance_to(current_search_point) <= 0.001,
		"Phase 5.5 investigation advances into a resolved multi-point local search rooted only at the evidence position"
	)

	var generation: int = int(
		application.call("request_quicksave")
	)
	var committed: bool = await _wait_for_save_status(
		coordinator,
		generation,
		&"committed",
		30
	)
	var saved_snapshot: Dictionary = coordinator.call(
		"get_request_snapshot",
		generation
	)
	var awareness_id: String = reaction.get_semantic_save_id()
	var saved_awareness: Dictionary = (
		saved_snapshot.get("session", {})
		.get("world_state", {})
		.get("semantic_owners", {})
		.get(awareness_id, {})
	)
	_assert_true(
		committed
		and saved_awareness.get("state", &"")
			== STATE_SEARCHING
		and bool(saved_awareness.get(
			"has_investigation_target",
			false
		))
		and _dict_vector(
			saved_awareness,
			"investigation_target"
		).distance_to(resolved_search_target) <= 0.001
		and float(saved_awareness.get(
			"state_remaining_seconds",
			0.0
		)) > 0.0
		and (saved_awareness.get("search_points", []) as Array).size() >= 2
		and int(saved_awareness.get("search_index", -1)) >= 0
		and int(saved_awareness.get("search_seed", 0)) > 0
		and float(saved_awareness.get("search_uncertainty_radius", 0.0)) > 0.0
		and float(saved_awareness.get("search_confidence", 0.0)) > 0.0
		and float(saved_awareness.get("search_confidence", 0.0)) <= 1.0,
		"Phase 5.5 search stage, resolved multi-point plan/progress, target, and remaining gameplay-time duration are detached save truth"
	)

	var mutated_to_unaware: bool = await _wait_for_awareness_state(
		reaction,
		STATE_UNAWARE,
		60
	)
	var loaded: bool = bool(
		application.call("quickload_latest")
	)
	world = application.get("current_world") as Node3D
	session = application.get("current_session") as Node
	player = application.get("current_player") as CharacterBody3D
	guard = world.get_node("Guard") as VarkGuard
	reaction = world.get_node("Guard/Reaction") as Node
	light = world.get_node(
		"NorthGameplayLight"
	) as VarkGameplayLight
	exposure = world.get_node(
		"GameplayExposure"
	) as VarkGameplayExposure
	_configure_short_durations(reaction)
	# Freeze locomotion without erasing the authored base speed; semantic
	# awareness speed-profile assertions still need a meaningful baseline.
	guard.velocity = Vector3.ZERO
	guard.set_physics_process(false)

	var restored_search: Dictionary = reaction.get_debug_summary()
	var restored_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		mutated_to_unaware
		and loaded
		and restored_search.get("awareness_state", &"")
			== STATE_SEARCHING
		and _dict_vector(
			restored_search,
			"investigation_target"
		).distance_to(resolved_search_target) <= 0.001
		and is_equal_approx(
			float(restored_search.get(
				"state_remaining_seconds",
				-1.0
			)),
			float(saved_awareness.get(
				"state_remaining_seconds",
				-2.0
			))
		)
		and bool(restored_nav.get("active", false))
		and restored_nav.get("reason", &"")
			== NAV_SEARCH
		and _vector_arrays_equal(
			restored_search.get("search_points", []),
			saved_awareness.get("search_points", [])
		)
		and int(restored_search.get("search_index", -1))
			== int(saved_awareness.get("search_index", -2))
		and is_equal_approx(
			float(restored_search.get(
				"search_scan_remaining_seconds",
				-1.0
			)),
			float(saved_awareness.get(
				"search_scan_remaining_seconds",
				-2.0
			))
		)
		and int(restored_search.get("search_seed", -1))
			== int(saved_awareness.get("search_seed", -2))
		and int(restored_search.get("search_stage", -1))
			== int(saved_awareness.get("search_stage", -2))
		and is_equal_approx(
			float(restored_search.get("search_uncertainty_radius", -1.0)),
			float(saved_awareness.get("search_uncertainty_radius", -2.0))
		)
		and is_equal_approx(
			float(restored_search.get("search_confidence", -1.0)),
			float(saved_awareness.get("search_confidence", -2.0))
		)
		and is_equal_approx(
			float(restored_search.get("search_age_seconds", -1.0)),
			float(saved_awareness.get("search_age_seconds", -2.0))
		)
		and restored_search.get("search_action", &"")
			== saved_awareness.get("search_action", &"")
		and is_equal_approx(
			float(restored_search.get("search_action_remaining_seconds", -1.0)),
			float(saved_awareness.get("search_action_remaining_seconds", -2.0))
		)
		and is_equal_approx(
			float(restored_search.get("search_move_speed_scale", -1.0)),
			float(saved_awareness.get("search_move_speed_scale", -2.0))
		)
		and _vector_arrays_equal(
			restored_search.get("search_visited_positions", []),
			saved_awareness.get("search_visited_positions", [])
		)
		and int(session.call(
			"get_pending_semantic_event_count"
		)) == 0,
		(
			"Phase 5.4 quickload restores the resolved search choice and remaining simulation-time stage without replaying hearing "
			+ "(mutated=%s loaded=%s state=%s remaining=%.6f/%.6f nav=%s pending=%d)"
			% [
				str(mutated_to_unaware),
				str(loaded),
				str(restored_search.get("awareness_state", &"")),
				float(restored_search.get("state_remaining_seconds", -1.0)),
				float(saved_awareness.get("state_remaining_seconds", -2.0)),
				str(restored_nav),
				int(session.call("get_pending_semantic_event_count")),
			]
		)
	)

	reaction.reset_reaction()
	reaction.set_physics_process(false)
	light.gameplay_enabled = false
	light.visible = false
	player.global_position = Vector3(0.0, 0.0, -4.2)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -5.2)
	guard.velocity = Vector3.ZERO
	guard.look_at(player.global_position, Vector3.UP, true)
	await _settle_frames(2)
	var dark_exposure_summary: Dictionary = exposure.sample_now()
	var dark_exposure: float = float(
		dark_exposure_summary.get("exposure", 1.0)
	)
	var dark_close_visible: bool = reaction.sample_vision_now(0.10)
	var dark_close_initial: Dictionary = reaction.get_debug_summary()
	var dark_rate: float = float(
		dark_close_initial.get("last_visual_suspicion_rate", 0.0)
	)
	_assert_true(
		dark_exposure <= 0.02
		and dark_close_visible
		and dark_close_initial.get("awareness_state", &"")
			== STATE_SUSPICIOUS
		and float(dark_close_initial.get("visual_suspicion", 0.0)) > 0.0
		and float(dark_close_initial.get("visual_suspicion", 1.0))
			< reaction.vision_investigate_suspicion
		and bool(dark_close_initial.get(
			"last_vision_darkness_override",
			false
		))
		and dark_rate > 0.0,
		"Phase 5.4 even point-blank darkness builds visual suspicion over time instead of instantly confirming the player"
	)

	var dark_eventually_alerted: bool = false
	for _sample: int in 30:
		reaction.sample_vision_now(0.10)
		if reaction.get_debug_summary().get("awareness_state", &"") == STATE_ALERTED:
			dark_eventually_alerted = true
			break
	_assert_true(
		dark_eventually_alerted,
		"Phase 5.4 sustained point-blank direct-facing sight can still accumulate enough suspicion to confirm through darkness"
	)

	reaction.reset_reaction()
	light.gameplay_enabled = true
	light.visible = true
	player.global_position = Vector3(0.0, 0.0, -2.4)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -5.6)
	guard.velocity = Vector3.ZERO
	guard.look_at(player.global_position, Vector3.UP, true)
	await _settle_frames(2)
	exposure.sample_now()
	var bright_visible: bool = reaction.sample_vision_now(0.10)
	var bright_initial: Dictionary = reaction.get_debug_summary()
	var bright_rate: float = float(
		bright_initial.get("last_visual_suspicion_rate", 0.0)
	)
	_assert_true(
		bright_visible
		and bright_initial.get("awareness_state", &"") != STATE_ALERTED
		and float(bright_initial.get("visual_suspicion", 0.0)) > 0.0
		and bright_rate > dark_rate,
		"Phase 5.4 visual suspicion accumulation is continuous and rises faster at higher gameplay exposure"
	)

	var visual_stare_seen: bool = bool(
		bright_initial.get("investigation_stare_active", false)
	)
	for _sample: int in 20:
		if visual_stare_seen:
			break
		reaction.sample_vision_now(0.05)
		visual_stare_seen = bool(
			reaction.get_debug_summary().get("investigation_stare_active", false)
		)
	var visual_stare_before_loss: Dictionary = reaction.get_debug_summary()
	var suspicion_before_loss: float = float(
		visual_stare_before_loss.get("visual_suspicion", 0.0)
	)
	light.gameplay_enabled = false
	light.visible = false
	exposure.sample_now()
	var lost_during_stare: bool = not reaction.sample_vision_now(0.15)
	var visual_stare_after_loss: Dictionary = reaction.get_debug_summary()
	_assert_true(
		visual_stare_seen
		and lost_during_stare
		and bool(visual_stare_after_loss.get("investigation_stare_active", false))
		and float(visual_stare_after_loss.get("visual_suspicion", 1.0))
			< suspicion_before_loss,
		"Phase 5.4 visual suspicion is allowed to decay while the guard remains inside its source-facing observation hold"
	)

	reaction.reset_reaction()
	light.gameplay_enabled = true
	light.visible = true
	exposure.sample_now()
	var confirmed: bool = false
	for _sample: int in 30:
		reaction.sample_vision_now(0.05)
		var current_visual: Dictionary = reaction.get_debug_summary()
		visual_stare_seen = (
			visual_stare_seen
			or bool(current_visual.get("investigation_stare_active", false))
		)
		if current_visual.get("awareness_state", &"") == STATE_ALERTED:
			confirmed = true
			break
	var alert_summary: Dictionary = reaction.get_debug_summary()
	var alert_nav: Dictionary = guard.get_awareness_navigation_state()
	var last_seen: Vector3 = alert_summary.get(
		"last_seen_position",
		Vector3.ZERO
	)
	_assert_true(
		confirmed
		and visual_stare_seen
		and alert_summary.get("awareness_state", &"") == STATE_ALERTED
		and alert_summary.get("state", &"") == &"saw_player"
		and int(alert_summary.get("seen_count", 0)) >= 1
		and bool(alert_nav.get("active", false))
		and alert_nav.get("reason", &"") == NAV_PURSUIT
		and alert_nav.get("movement_mode", &"") == &"running"
		and is_equal_approx(
			float(alert_nav.get("current_movement_speed", 0.0)),
			guard.movement_speed * guard.pursuit_speed_scale
		)
		and alert_summary.get("pursuit_mode", &"") == PURSUIT_VISIBLE
		and bool(alert_summary.get("has_pursuit_goal", false))
		and guard.is_navigation_position_reachable(
			_dict_vector(alert_summary, "pursuit_goal_position")
		)
		and _dict_vector(
			alert_nav,
			"target_position"
		).distance_to(_dict_vector(
			alert_summary,
			"pursuit_goal_position"
		)) <= 0.001,
		"Phase 5.4 exposed sight passes through suspicion/investigation observation before confirmed running pursuit"
	)
	reaction.set_physics_process(true)

	var pursuit_generation: int = int(application.call("request_quicksave"))
	var pursuit_committed: bool = await _wait_for_save_status(
		coordinator,
		pursuit_generation,
		&"committed",
		30
	)
	var pursuit_snapshot: Dictionary = coordinator.call(
		"get_request_snapshot",
		pursuit_generation
	)
	var pursuit_awareness: Dictionary = (
		pursuit_snapshot.get("session", {})
		.get("world_state", {})
		.get("semantic_owners", {})
		.get(reaction.get_semantic_save_id(), {})
	)
	var saved_pursuit_goal: Vector3 = _dict_vector(
		pursuit_awareness,
		"pursuit_goal_position"
	)
	var visible_distraction_origin: Vector3 = guard.global_position + Vector3(-0.65, 0.0, 0.45)
	var visible_distraction_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"prop.impact",
		visible_distraction_origin,
		0.90
	))
	await _completed_physics_frame()
	var after_visible_distraction: Dictionary = reaction.get_debug_summary()
	_assert_true(
		pursuit_committed
		and pursuit_awareness.get("state", &"") == STATE_ALERTED
		and pursuit_awareness.get("pursuit_mode", &"") == PURSUIT_VISIBLE
		and bool(pursuit_awareness.get("has_pursuit_goal", false))
		and saved_pursuit_goal.distance_to(
			_dict_vector(alert_summary, "pursuit_goal_position")
		) <= 0.001
		and visible_distraction_queued
		and after_visible_distraction.get("pursuit_mode", &"") == PURSUIT_VISIBLE
		and not bool(after_visible_distraction.get("investigation_stare_active", false))
		and _dict_vector(
			after_visible_distraction,
			"investigation_target"
		).distance_to(player.global_position) <= 0.001,
		"Phase 5.5 visible confirmed pursuit persists resolved chase truth and ignores unrelated distraction navigation"
	)

	reaction.reset_reaction()
	var pursuit_loaded: bool = bool(application.call("quickload_latest"))
	world = application.get("current_world") as Node3D
	session = application.get("current_session") as Node
	player = application.get("current_player") as CharacterBody3D
	guard = world.get_node("Guard") as VarkGuard
	reaction = world.get_node("Guard/Reaction") as Node
	light = world.get_node("NorthGameplayLight") as VarkGameplayLight
	exposure = world.get_node("GameplayExposure") as VarkGameplayExposure
	_configure_short_durations(reaction)
	guard.velocity = Vector3.ZERO
	guard.set_physics_process(false)
	var restored_pursuit: Dictionary = reaction.get_debug_summary()
	_assert_true(
		pursuit_loaded
		and restored_pursuit.get("awareness_state", &"") == STATE_ALERTED
		and restored_pursuit.get("pursuit_mode", &"") == PURSUIT_VISIBLE
		and _dict_vector(
			restored_pursuit,
			"pursuit_goal_position"
		).distance_to(saved_pursuit_goal) <= 0.001
		and _dict_vector(
			guard.get_awareness_navigation_state(),
			"target_position"
		).distance_to(saved_pursuit_goal) <= 0.001,
		"Phase 5.5 quickload restores the already-resolved pursuit mode/goal instead of recomputing from hidden player state"
	)

	light.gameplay_enabled = false
	light.visible = false
	exposure.sample_now()
	var lost_now: bool = not reaction.sample_vision_now()
	var loss_summary: Dictionary = reaction.get_debug_summary()
	_assert_true(
		lost_now
		and loss_summary.get("awareness_state", &"")
			== STATE_ALERTED
		and bool(loss_summary.get(
			"has_alert_loss_timer",
			false
		))
		and float(loss_summary.get(
			"alert_loss_remaining_seconds",
			0.0
		)) > 0.0
		and loss_summary.get("pursuit_mode", &"") == PURSUIT_CONTACT_GRACE
		and loss_summary.get("state", &"") != &"saw_player"
		and guard.get_awareness_navigation_state().get("reason", &"") == NAV_PURSUIT,
		"Phase 5.5 losing sight starts only a contact-grace substate while confirmed pursuit remains active"
	)

	var checking_last_known: bool = await _wait_for_pursuit_mode(
		reaction,
		PURSUIT_CHECKING_LAST_KNOWN,
		30
	)
	var checking_summary: Dictionary = reaction.get_debug_summary()
	var checking_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		checking_last_known
		and checking_summary.get("awareness_state", &"") == STATE_ALERTED
		and checking_summary.get("pursuit_mode", &"") == PURSUIT_CHECKING_LAST_KNOWN
		and float(checking_summary.get("pursuit_lost_seconds", 0.0)) > 0.0
		and checking_nav.get("reason", &"") == NAV_PURSUIT,
		"Phase 5.5 contact-grace expiry keeps the guard ALERTED while it checks the last useful reachable pursuit approach"
	)

	var lost_sound_origin: Vector3 = guard.global_position + Vector3(0.40, 0.0, 0.55)
	var old_pursuit_goal: Vector3 = _dict_vector(checking_summary, "pursuit_goal_position")
	var lost_sound_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"footstep.stone",
		lost_sound_origin,
		0.70
	))
	await _completed_physics_frame()
	var heard_during_lost: Dictionary = reaction.get_debug_summary()
	_assert_true(
		lost_sound_queued
		and heard_during_lost.get("awareness_state", &"") == STATE_ALERTED
		and heard_during_lost.get("pursuit_mode", &"") == PURSUIT_CHECKING_LAST_KNOWN
		and _dict_vector(heard_during_lost, "investigation_target").distance_to(
			lost_sound_origin
		) <= 0.001
		and _dict_vector(heard_during_lost, "pursuit_goal_position").distance_to(
			old_pursuit_goal
		) > 0.01,
		"Phase 5.5 strong local evidence can update a lost confirmed trail without dropping to search, while visible pursuit ignores distractions"
	)

	var lost_to_search: bool = await _wait_for_awareness_state(
		reaction,
		STATE_SEARCHING,
		30
	)
	var lost_search_summary: Dictionary = reaction.get_debug_summary()
	var lost_search_nav: Dictionary = guard.get_awareness_navigation_state()
	var lost_points: Array = lost_search_summary.get("search_points", [])
	var lost_index: int = int(lost_search_summary.get("search_index", 0))
	var lost_current: Vector3 = (
		lost_points[lost_index]
		if lost_index >= 0 and lost_index < lost_points.size()
		else Vector3.ZERO
	)
	_assert_true(
		lost_to_search
		and bool(lost_search_nav.get("active", false))
		and lost_search_nav.get("reason", &"")
			== NAV_SEARCH
		and _dict_vector(
			lost_search_summary,
			"search_anchor"
		).distance_to(lost_sound_origin) <= 0.001
		and lost_points.size() >= 2
		and _dict_vector(
			lost_search_nav,
			"target_position"
		).distance_to(lost_current) <= 0.001,
		"Phase 5.5 search begins only after failed alerted pursuit and uses the latest explicit local evidence rather than hidden player knowledge"
	)

	var recovering: bool = await _wait_for_awareness_state(
		reaction,
		STATE_RECOVERING,
		40
	)
	var recovery_nav: Dictionary = guard.get_awareness_navigation_state()
	var final_unaware: bool = await _wait_for_awareness_state(
		reaction,
		STATE_UNAWARE,
		40
	)
	_assert_true(
		recovering
		and not bool(recovery_nav.get("active", true))
		and final_unaware
		and not bool(
			guard.get_awareness_navigation_state().get(
				"active",
				true
			)
		),
		"Phase 5.4 search exhausts into recovery and finally returns navigation ownership to patrol using only simulation time"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame
	_cleanup_test_storage()


func _assert_advanced_local_search_behavior() -> void:
	var application: Node = await _launch_slice()
	if application == null:
		return
	var world := application.get("current_world") as Node3D
	var session := application.get("current_session") as Node
	var player := application.get("current_player") as CharacterBody3D
	var guard := world.get_node("Guard") as VarkGuard
	var guard_listener := world.get_node("Guard/Hearing") as VarkAcousticListener
	var reaction := world.get_node("Guard/Reaction") as Node
	var light := world.get_node("NorthGameplayLight") as VarkGameplayLight
	var exposure := world.get_node("GameplayExposure") as VarkGameplayExposure

	var production_search_radius: float = reaction.search_radius
	var production_search_max_radius: float = reaction.search_max_radius
	var production_search_separation: float = reaction.search_point_min_separation
	_assert_true(
		production_search_radius >= 2.75
		and production_search_max_radius >= 5.90
		and production_search_separation >= 1.35,
		"Phase 5.5 production search defaults cover a wider area with materially separated investigation stops"
	)

	reaction.hearing_investigate_strength = 0.20
	reaction.investigation_seconds = 0.06
	# This fixture compresses the new source-facing observation hold along with
	# its existing compressed investigation/search timings.
	reaction.investigation_stare_min = 0.01
	reaction.investigation_stare_max = 0.02
	reaction.search_seconds = 2.50
	reaction.search_point_count = 2
	reaction.search_radius = 1.40
	reaction.search_max_radius = 2.80
	reaction.search_radius_expansion = 0.70
	reaction.search_point_min_separation = 0.70
	reaction.search_confidence_decay_per_second = 0.20
	reaction.search_confidence_drop_per_expansion = 0.15
	reaction.search_min_confidence = 0.20
	reaction.search_arrival_distance = 0.30
	reaction.search_move_speed_scale_min = 0.50
	reaction.search_move_speed_scale_max = 0.65
	reaction.search_arrival_pause_min = 0.02
	reaction.search_arrival_pause_max = 0.04
	reaction.search_look_turn_min = 0.02
	reaction.search_look_turn_max = 0.04
	reaction.search_look_hold_min = 0.03
	reaction.search_scan_seconds = 0.06
	reaction.search_between_pause_min = 0.02
	reaction.search_between_pause_max = 0.04
	reaction.search_departure_pause_min = 0.02
	reaction.search_departure_pause_max = 0.04
	reaction.search_look_count_min = 1
	reaction.search_look_count_max = 2
	reaction.search_look_min_degrees = 20.0
	reaction.search_scan_degrees = 55.0
	reaction.recovery_seconds = 0.30
	reaction.recovery_hearing_threshold_scale = 0.60
	guard.movement_speed = 5.0
	guard.investigate_speed_scale = 0.45
	guard.search_speed_scale = 0.45
	guard.pursuit_speed_scale = 1.65
	light.gameplay_enabled = false
	light.visible = false
	player.global_position = Vector3(-4.0, 0.0, 6.0)
	player.velocity = Vector3.ZERO
	exposure.sample_now()
	reaction.reset_reaction()

	var first_origin: Vector3 = guard.global_position + Vector3(0.45, 0.0, 0.20)
	var first_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"prop.impact",
		first_origin,
		0.70
	))
	await _completed_physics_frame()
	var first_search: bool = await _wait_for_awareness_state(
		reaction,
		STATE_SEARCHING,
		45
	)
	var first_summary: Dictionary = reaction.get_debug_summary()
	var first_points: Array = first_summary.get("search_points", [])
	var all_reachable: bool = first_points.size() >= 2
	var minimum_spacing: float = _minimum_pairwise_horizontal_distance(first_points)
	for point_value: Variant in first_points:
		if (
			typeof(point_value) != TYPE_VECTOR3
			or not guard.is_navigation_position_reachable(point_value)
		):
			all_reachable = false
			break
	_assert_true(
		first_queued
		and first_search
		and first_points.size() >= 2
		and all_reachable
		and minimum_spacing >= reaction.search_point_min_separation - 0.01
		and _dict_vector(first_summary, "search_anchor").distance_to(
			first_origin
		) <= 0.001
		and int(first_summary.get("search_seed", 0)) > 0
		and int(first_summary.get("search_stage", -1)) == 0
		and is_equal_approx(
			float(first_summary.get("search_uncertainty_radius", 0.0)),
			1.40
		)
		and is_equal_approx(
			float(first_summary.get("search_confidence", 0.0)),
			1.0
		)
		and first_summary.get("search_action", &"") == &"moving"
		and guard.get_awareness_navigation_state().get("movement_mode", &"")
			== &"investigating"
		and is_equal_approx(
			float(guard.get_awareness_navigation_state().get(
				"current_movement_speed",
				-1.0
			)),
			guard.movement_speed * guard.investigate_speed_scale
		),
		"Phase 5.5 search uses the fixed investigating speed while resolving reachable evidence-driven candidates without player-position input"
	)

	var plan_before_hidden_move: Array = (
		first_summary.get("search_points", []) as Array
	).duplicate(true)
	player.global_position = Vector3(4.0, 0.0, 6.0)
	player.velocity = Vector3.ZERO
	await _settle_frames(3)
	var after_hidden_move: Dictionary = reaction.get_debug_summary()
	_assert_true(
		after_hidden_move.get("awareness_state", &"") == STATE_SEARCHING
		and _vector_arrays_equal(
			plan_before_hidden_move,
			after_hidden_move.get("search_points", [])
		)
		and float(after_hidden_move.get("search_age_seconds", 0.0)) > 0.0
		and float(after_hidden_move.get("search_confidence", 1.0)) < 1.0,
		"Phase 5.5 moving the hidden player cannot rewrite resolved search truth while confidence decays only with simulation-time uncertainty"
	)

	var visited_first: bool = await _wait_for_search_visited(
		reaction,
		1,
		120
	)
	var expanded: bool = await _wait_for_search_stage(
		reaction,
		1,
		120
	)
	var expanded_summary: Dictionary = reaction.get_debug_summary()
	_assert_true(
		visited_first
		and expanded
		and int(expanded_summary.get("search_stage", 0)) >= 1
		and float(expanded_summary.get(
			"search_uncertainty_radius",
			0.0
		)) > 1.40
		and float(expanded_summary.get("search_confidence", 1.0))
			< float(after_hidden_move.get("search_confidence", 1.0)),
		"Phase 5.5 exhausted local evidence expands the bounded uncertainty radius while confidence falls"
	)
	var second_origin: Vector3 = guard.global_position + Vector3(-0.05, 0.0, 0.05)
	var search_attention_before_reseed: Dictionary = reaction.get_debug_summary()
	var reseed_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"footstep.stone",
		second_origin,
		0.2025
	))
	await _completed_physics_frame()
	var reseed_summary: Dictionary = reaction.get_debug_summary()
	var reseed_nav: Dictionary = guard.get_awareness_navigation_state()
	var reseed_investigating: bool = (
		reseed_summary.get("awareness_state", &"") == STATE_INVESTIGATING
		and int(reseed_summary.get("search_reseed_count", 0)) >= 1
		and bool(reseed_summary.get("investigation_stare_active", false))
		and bool(reseed_nav.get("motion_paused", false))
		and reseed_nav.get("movement_mode", &"") == &"investigating"
	)
	var second_search: bool = await _wait_for_awareness_state(
		reaction,
		STATE_SEARCHING,
		45
	)
	var second_summary: Dictionary = reaction.get_debug_summary()
	_assert_true(
		visited_first
		and bool(search_attention_before_reseed.get("heightened_attention", false))
		and float(search_attention_before_reseed.get(
			"effective_hearing_investigate_strength",
			1.0
		)) < reaction.hearing_investigate_strength
		and float(search_attention_before_reseed.get(
			"effective_footstep_investigate_source_floor",
			1.0
		)) < 0.2025
		and reaction.hearing_footstep_investigate_source_floor > 0.2025
		and reseed_queued
		and reseed_investigating
		and second_search
		and _dict_vector(second_summary, "search_anchor").distance_to(
			second_origin
		) <= 0.001
		and int(second_summary.get("search_stage", -1)) == 0
		and is_equal_approx(
			float(second_summary.get("search_uncertainty_radius", 0.0)),
			1.40
		)
		and float(second_summary.get("search_confidence", 0.0)) >= 0.99
		and int(second_summary.get("search_seed", 0))
			!= int(first_summary.get("search_seed", 0))
		and not _vector_arrays_equal(
			plan_before_hidden_move,
			second_summary.get("search_points", [])
		),
		"Phase 5.5 heightened search attention promotes a very close stone-sneak-strength cue that calm guards cap at suspicion, then stops/turns/stares before reseeding without global player knowledge"
	)

	var human_stop_seen: bool = await _wait_for_stationary_search_action(
		reaction,
		180
	)
	var human_stop_summary: Dictionary = reaction.get_debug_summary()
	var human_stop_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		human_stop_seen
		and human_stop_summary.get("search_action", &"") != &"moving"
		and float(human_stop_summary.get(
			"search_action_duration_seconds",
			0.0
		)) > 0.0
		and bool(human_stop_nav.get("motion_paused", false))
		and int(human_stop_summary.get("search_action_serial", 0)) > 0,
		"Phase 5.5 search execution deliberately stops for deterministic varied pause/look actions instead of continuously running or sinusoidally spinning"
	)

	var visited_multiple: bool = await _wait_for_search_visited(
		reaction,
		2,
		180
	)
	var reached_recovery: bool = await _wait_for_awareness_state(
		reaction,
		STATE_RECOVERING,
		180
	)
	var recovery_start: Dictionary = reaction.get_debug_summary()
	var recovery_nav: Dictionary = guard.get_awareness_navigation_state()
	await _settle_frames(3)
	var recovery_later: Dictionary = reaction.get_debug_summary()
	var residual_decays: bool = (
		float(recovery_start.get("residual_alert_strength", 0.0)) > 0.0
		and float(recovery_later.get("residual_alert_strength", 1.0))
			< float(recovery_start.get("residual_alert_strength", 0.0))
	)
	# This fixture isolates residual-alert threshold scaling. Use a non-footstep
	# sound so the separate weak-footstep investigation ceiling cannot become
	# the behavior under test.
	var borderline_strength: float = reaction.hearing_investigate_strength * 0.90
	var residual_realert_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"prop.impact",
		guard_listener.global_position,
		borderline_strength
	))
	await _completed_physics_frame()
	var residual_realert: Dictionary = reaction.get_debug_summary()
	var residual_realerted: bool = (
		residual_realert.get("awareness_state", &"") == STATE_INVESTIGATING
	)
	var second_recovery: bool = await _wait_for_awareness_state(
		reaction,
		STATE_RECOVERING,
		180
	)
	var returned_unaware: bool = await _wait_for_awareness_state(
		reaction,
		STATE_UNAWARE,
		90
	)
	var unaware_summary: Dictionary = reaction.get_debug_summary()
	_assert_true(
		visited_multiple
		and reached_recovery
		and not bool(recovery_nav.get("active", true))
		and residual_decays
		and residual_realert_queued
		and residual_realerted
		and second_recovery
		and returned_unaware
		and is_zero_approx(float(
			unaware_summary.get("residual_alert_strength", -1.0)
		))
		and not bool(
			guard.get_awareness_navigation_state().get("active", true)
		),
		"Phase 5.5 bounded search returns patrol ownership with decaying residual alertness, temporarily lowers the local re-alert threshold, then fully calms"
	)


	reaction.reset_reaction()
	guard.set_physics_process(false)
	guard.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -5.60)
	# Keep every sampled body point genuinely above the calm vertical field;
	# multi-sample vision now includes center/lower body, so 2.20 m was no
	# longer an unambiguous overhead fixture.
	player.global_position = Vector3(0.0, 3.00, -5.15)
	guard.look_at(
		Vector3(
			player.global_position.x,
			guard.global_position.y,
			player.global_position.z
		),
		Vector3.UP,
		true
	)
	light.gameplay_enabled = false
	light.visible = false
	exposure.sample_now()
	reaction.vision_suspicion_exposure_threshold = 0.0
	reaction.vision_confirm_exposure_threshold = 0.0
	var unaware_elevated_confirmed: bool = reaction.sample_vision_now()
	var unaware_vertical_summary: Dictionary = reaction.get_debug_summary()
	var base_vertical_limit: float = float(
		unaware_vertical_summary.get("current_vision_vertical_limit_degrees", 0.0)
	)

	reaction.vision_suspicion_exposure_threshold = 1.0
	reaction.vision_confirm_exposure_threshold = 1.0
	var elevated_evidence: Vector3 = player.global_position
	var elevated_sound_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"footstep.stone",
		elevated_evidence,
		0.70
	))
	await _completed_physics_frame()
	var reached_elevated_search: bool = await _wait_for_awareness_state(
		reaction,
		STATE_SEARCHING,
		60
	)
	var elevated_search_summary: Dictionary = reaction.get_debug_summary()
	var elevated_search_points: Array = elevated_search_summary.get(
		"search_points",
		[]
	)
	var elevated_points_reachable: bool = not elevated_search_points.is_empty()
	for point_value: Variant in elevated_search_points:
		if (
			typeof(point_value) != TYPE_VECTOR3
			or not guard.is_navigation_position_reachable(point_value)
		):
			elevated_points_reachable = false
			break
	reaction.set_physics_process(false)
	reaction.vision_suspicion_exposure_threshold = 0.0
	reaction.vision_confirm_exposure_threshold = 0.0
	# This proof isolates engaged vertical geometry/reachability. Detection
	# timing is covered earlier, so accelerate both ends of the suspicion rate
	# instead of spending seconds of synthetic samples at zero exposure.
	reaction.vision_suspicion_rate_min = 5.0
	reaction.vision_suspicion_rate_max = 5.0
	var search_elevated_visible: bool = reaction.sample_vision_now(0.10)
	var search_elevated_confirmed: bool = false
	for _sample: int in 40:
		if reaction.get_debug_summary().get("awareness_state", &"") == STATE_ALERTED:
			search_elevated_confirmed = true
			break
		reaction.sample_vision_now(0.10)
	var elevated_alert_summary: Dictionary = reaction.get_debug_summary()
	var elevated_pursuit_goal: Vector3 = _dict_vector(
		elevated_alert_summary,
		"pursuit_goal_position"
	)
	player.global_position += Vector3(0.65, 0.0, 0.0)
	player.velocity = Vector3(1.5, 0.0, 0.0)
	var lateral_elevated_confirmed: bool = reaction.sample_vision_now()
	var lateral_alert_summary: Dictionary = reaction.get_debug_summary()
	var lateral_pursuit_goal: Vector3 = _dict_vector(
		lateral_alert_summary,
		"pursuit_goal_position"
	)
	_assert_true(
		not unaware_elevated_confirmed
		and float(unaware_vertical_summary.get(
			"last_vision_vertical_angle_degrees",
			0.0
		)) > base_vertical_limit
		and is_equal_approx(
			float(unaware_vertical_summary.get(
				"last_vision_vertical_limit_degrees",
				-1.0
			)),
			base_vertical_limit
		),
		(
			"Phase 5.5 calm vertical attention rejects a genuinely overhead player "
			+ "(summary=%s)" % str(unaware_vertical_summary)
		)
	)
	_assert_true(
		elevated_sound_queued
		and reached_elevated_search
		and elevated_points_reachable
		and _dict_vector(elevated_search_summary, "search_anchor").distance_to(
			elevated_evidence
		) <= 0.001
		and float(elevated_search_summary.get(
			"current_vision_vertical_limit_degrees",
			0.0
		)) > base_vertical_limit,
		(
			"Phase 5.5 elevated evidence keeps true height while search resolves only reachable navigation "
			+ "(summary=%s)" % str(elevated_search_summary)
		)
	)
	_assert_true(
		search_elevated_visible
		and search_elevated_confirmed
		and elevated_alert_summary.get("awareness_state", &"") == STATE_ALERTED
		and guard.is_navigation_position_reachable(elevated_pursuit_goal)
		and absf(elevated_pursuit_goal.y - player.global_position.y) > 0.50
		and lateral_elevated_confirmed
		and lateral_alert_summary.get("awareness_state", &"") == STATE_ALERTED
		and lateral_alert_summary.get("pursuit_mode", &"") == PURSUIT_VISIBLE
		and guard.is_navigation_position_reachable(lateral_pursuit_goal)
		and _dict_vector(
			lateral_alert_summary,
			"last_seen_position"
		).distance_to(player.global_position) <= 0.001
		and _dict_vector(
			lateral_alert_summary,
			"last_confirmed_velocity"
		).distance_to(player.velocity) <= 0.001
		and float(elevated_alert_summary.get(
			"last_vision_vertical_angle_degrees",
			0.0
		)) > base_vertical_limit
		and float(elevated_alert_summary.get(
			"last_vision_vertical_angle_degrees",
			90.0
		)) <= float(elevated_alert_summary.get(
			"last_vision_vertical_limit_degrees",
			0.0
		)),
		(
			"Phase 5.5 engaged vertical attention reacquires and retains visible lateral elevated pursuit "
			+ "(first=%s lateral=%s)"
			% [str(elevated_alert_summary), str(lateral_alert_summary)]
		)
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _wait_for_stationary_search_action(
	reaction: Node,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		var action: StringName = reaction.get_debug_summary().get(
			"search_action",
			&"moving"
		)
		if action != &"moving":
			return true
		await _completed_physics_frame()
	return reaction.get_debug_summary().get(
		"search_action",
		&"moving"
	) != &"moving"


func _wait_for_search_stage(
	reaction: Node,
	minimum_stage: int,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		if int(reaction.get_debug_summary().get(
			"search_stage",
			0
		)) >= minimum_stage:
			return true
		await _completed_physics_frame()
	return int(reaction.get_debug_summary().get(
		"search_stage",
		0
	)) >= minimum_stage


func _wait_for_search_visited(
	reaction: Node,
	minimum_visited: int,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		if int(reaction.get_debug_summary().get(
			"search_points_visited",
			0
		)) >= minimum_visited:
			return true
		await _completed_physics_frame()
	return int(reaction.get_debug_summary().get(
		"search_points_visited",
		0
	)) >= minimum_visited


func _minimum_pairwise_horizontal_distance(points: Array) -> float:
	if points.size() < 2:
		return INF
	var minimum_distance: float = INF
	for left_index: int in range(points.size() - 1):
		if typeof(points[left_index]) != TYPE_VECTOR3:
			return 0.0
		var left: Vector3 = points[left_index]
		for right_index: int in range(left_index + 1, points.size()):
			if typeof(points[right_index]) != TYPE_VECTOR3:
				return 0.0
			var right: Vector3 = points[right_index]
			minimum_distance = minf(
				minimum_distance,
				Vector3(left.x - right.x, 0.0, left.z - right.z).length()
			)
	return minimum_distance


func _vector_arrays_equal(left_value: Variant, right_value: Variant) -> bool:
	if typeof(left_value) != TYPE_ARRAY or typeof(right_value) != TYPE_ARRAY:
		return false
	var left: Array = left_value
	var right: Array = right_value
	if left.size() != right.size():
		return false
	for index: int in left.size():
		if (
			typeof(left[index]) != TYPE_VECTOR3
			or typeof(right[index]) != TYPE_VECTOR3
			or (left[index] as Vector3).distance_to(
				right[index] as Vector3
			) > 0.001
		):
			return false
	return true


func _dict_vector(
	source: Dictionary,
	key: String
) -> Vector3:
	var value: Variant = source.get(key, Vector3.ZERO)
	return value if typeof(value) == TYPE_VECTOR3 else Vector3.ZERO


func _configure_short_durations(
	reaction: Node
) -> void:
	reaction.hearing_investigate_strength = 0.20
	# Production defaults keep engaged hearing interpretation neutral. Exercise
	# the configurable heightened-hearing seam only inside this compressed fixture.
	reaction.engaged_hearing_investigate_threshold_scale = 0.80
	reaction.engaged_footstep_investigate_source_floor_scale = 0.80
	reaction.suspicion_seconds = 0.08
	reaction.investigation_seconds = 0.10
	reaction.investigation_stare_min = 0.20
	reaction.investigation_stare_max = 0.24
	reaction.observation_stare_repeat_limit = 2
	reaction.observation_stare_reset_seconds = 0.60
	reaction.vision_suspicion_rate_min = 0.30
	reaction.vision_suspicion_rate_max = 2.50
	reaction.vision_suspicion_decay_per_second = 0.80
	reaction.vision_investigate_suspicion = 0.35
	reaction.vision_alert_suspicion = 1.0
	reaction.search_seconds = 0.60
	reaction.search_point_count = 3
	reaction.search_radius = 0.60
	reaction.search_max_radius = 1.20
	# This fixture deliberately compresses spatial search to keep CI fast, so
	# its spacing must scale with that tiny radius instead of inheriting the
	# much wider 1.40 m production stop-separation target.
	reaction.search_point_min_separation = 0.25
	reaction.search_radius_expansion = 0.30
	reaction.search_confidence_decay_per_second = 0.12
	reaction.search_confidence_drop_per_expansion = 0.10
	reaction.search_min_confidence = 0.20
	reaction.search_arrival_distance = 0.30
	reaction.search_move_speed_scale_min = 0.50
	reaction.search_move_speed_scale_max = 0.65
	reaction.search_arrival_pause_min = 0.01
	reaction.search_arrival_pause_max = 0.02
	reaction.search_look_turn_min = 0.01
	reaction.search_look_turn_max = 0.02
	reaction.search_look_hold_min = 0.01
	reaction.search_scan_seconds = 0.02
	reaction.search_between_pause_min = 0.01
	reaction.search_between_pause_max = 0.02
	reaction.search_departure_pause_min = 0.01
	reaction.search_departure_pause_max = 0.02
	reaction.search_look_count_min = 1
	reaction.search_look_count_max = 2
	reaction.search_look_min_degrees = 15.0
	reaction.search_scan_degrees = 45.0
	reaction.alert_loss_seconds = 0.05
	reaction.pursuit_prediction_seconds = 0.10
	reaction.pursuit_check_seconds = 0.08
	reaction.pursuit_max_lost_seconds = 0.28
	reaction.pursuit_arrival_distance = 0.30
	reaction.recovery_seconds = 0.12
	reaction.recovery_hearing_threshold_scale = 0.65


func _launch_slice() -> Node:
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
	var launched: bool = bool(
		application.call("launch_development_target", 0)
	)
	var ready: bool = await _wait_for_navigation_ready(
		application.get("current_world") as Node,
		240
	)
	_assert_true(
		launched and ready,
		"Phase 5.4 awareness fixture launches the real Integrated Slice with navigation ready"
	)
	if not launched or not ready:
		application.queue_free()
		await process_frame
		return null
	return application


func _wait_for_pursuit_mode(
	reaction: Node,
	expected: StringName,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		if reaction.get_debug_summary().get("pursuit_mode", &"") == expected:
			return true
		await _completed_physics_frame()
	return reaction.get_debug_summary().get("pursuit_mode", &"") == expected


func _wait_for_investigation_stare(
	reaction: Node,
	expected_active: bool,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		if bool(reaction.get_debug_summary().get(
			"investigation_stare_active",
			false
		)) == expected_active:
			return true
		await _completed_physics_frame()
	return bool(reaction.get_debug_summary().get(
		"investigation_stare_active",
		false
	)) == expected_active


func _wait_for_awareness_state(
	reaction: Node,
	expected: StringName,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		if (
			reaction.get_debug_summary().get(
				"awareness_state",
				&""
			) == expected
		):
			return true
		await _completed_physics_frame()
	return (
		reaction.get_debug_summary().get(
			"awareness_state",
			&""
		) == expected
	)


func _wait_for_save_status(
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
		await _completed_physics_frame()
	return (
		coordinator.call(
			"get_request_status",
			generation
		).get("status", &"") == expected
	)


func _wait_for_navigation_ready(
	world: Node,
	max_frames: int
) -> bool:
	if world == null:
		return false
	for _frame: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await _completed_physics_frame()
	return bool(world.get("navigation_ready"))


func _settle_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await _completed_physics_frame()


func _completed_physics_frame() -> void:
	await physics_frame
	await process_frame


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
		print("ALL AWARENESS TESTS PASSED")
		return
	print("%d AWARENESS TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
