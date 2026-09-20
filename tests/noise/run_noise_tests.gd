extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"
const STONE_PROFILE_PATH: String = "res://gameplay/noise/profiles/stone.tres"
const CARPET_PROFILE_PATH: String = "res://gameplay/noise/profiles/carpet.tres"
const NoiseMeter = preload("res://gameplay/noise/noise_meter.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_assert_surface_profile_contract()
	await _assert_integrated_surface_noise()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_surface_profile_contract() -> void:
	var stone := load(STONE_PROFILE_PATH) as VarkSurfaceProfile
	var carpet := load(CARPET_PROFILE_PATH) as VarkSurfaceProfile
	var invalid := VarkSurfaceProfile.new()
	invalid.surface_id = &""
	invalid.footstep_strength = 0.40

	_assert_true(
		stone != null
		and carpet != null
		and stone.is_valid_profile()
		and carpet.is_valid_profile()
		and stone.surface_id == &"stone"
		and carpet.surface_id == &"carpet"
		and stone.get_footstep_sound_kind() == &"footstep.stone"
		and carpet.get_footstep_sound_kind() == &"footstep.carpet"
		and stone.footstep_strength > carpet.footstep_strength,
		"Phase 5.1 authored SurfaceProfiles own stable semantic surface IDs and base footstep strengths"
	)
	_assert_true(
		not invalid.is_valid_profile()
		and invalid.get_footstep_sound_kind().is_empty(),
		"Phase 5.1 invalid surface profiles fail closed instead of manufacturing gameplay-noise identity"
	)

	var reusable_surface := VarkFootstepSurface.new()
	reusable_surface.surface_profile = stone
	_assert_true(
		reusable_surface.has_valid_surface_profile()
		and reusable_surface.get_surface_summary()
			== stone.get_semantic_summary(),
		"Phase 5.1 reusable footstep surfaces reference SurfaceProfile data instead of duplicating mission-local noise fields"
	)
	reusable_surface.free()


func _assert_integrated_surface_noise() -> void:
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
	var world := application.get("current_world") as Node3D
	var ready: bool = await _wait_for_navigation_ready(
		world,
		240
	)
	var player := application.get("current_player") as CharacterBody3D
	var guard := (
		world.get_node_or_null("Guard") as VarkGuard
		if world != null
		else null
	)
	var guard_listener := (
		world.get_node_or_null("Guard/Hearing") as VarkAcousticListener
		if world != null
		else null
	)
	var reaction: Node = (
		world.get_node_or_null("Guard/Reaction")
		if world != null
		else null
	)
	var footsteps := (
		world.get_node_or_null("FootstepEmitter") as VarkPlayerFootstepEmitter
		if world != null
		else null
	)
	var stone_surface := (
		world.get_node_or_null("StoneSurface") as VarkFootstepSurface
		if world != null
		else null
	)
	var carpet_surface := (
		world.get_node_or_null("CarpetSurface") as VarkFootstepSurface
		if world != null
		else null
	)
	var noise_meter := (
		world.get_node_or_null("ExposureHUD/NoisePanel") as VarkNoiseMeter
		if world != null
		else null
	)
	var noise_bar := (
		world.get_node_or_null(
			"ExposureHUD/NoisePanel/VBox/LoudnessBar"
		) as ProgressBar
		if world != null
		else null
	)

	_assert_true(
		launched
		and ready
		and player != null
		and guard != null
		and guard_listener != null
		and reaction != null
		and footsteps != null
		and stone_surface != null
		and carpet_surface != null
		and noise_meter != null
		and noise_meter.get_script() == NoiseMeter
		and noise_bar != null
		and stone_surface.get_surface_profile().resource_path
			== STONE_PROFILE_PATH
		and carpet_surface.get_surface_profile().resource_path
			== CARPET_PROFILE_PATH,
		"Phase 5.1 the real Integrated Slice consumes reusable gameplay/noise surfaces, emitter, and authored profiles"
	)
	if (
		not launched
		or not ready
		or player == null
		or guard == null
		or guard_listener == null
		or reaction == null
		or footsteps == null
		or stone_surface == null
		or carpet_surface == null
		or noise_meter == null
		or noise_bar == null
	):
		_cleanup_application(application)
		return

	footsteps.set_emission_enabled(false)
	guard.movement_speed = 0.0
	guard.velocity = Vector3.ZERO

	var standing_ready: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.STANDING
	)
	player.global_position = Vector3(0.0, 0.0, 4.0)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, 3.0)
	guard.velocity = Vector3.ZERO
	await _settle_overlap_frames(3)
	guard_listener.clear_perception()
	reaction.call("reset_reaction")

	var stone_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var stone_summary: Dictionary = footsteps.get_debug_summary()
	var stone_reaction: Dictionary = reaction.call(
		"get_debug_summary"
	)

	_assert_true(
		standing_ready
		and stone_queued
		and stone_summary.get("last_surface_id", &"") == &"stone"
		and stone_summary.get("last_sound_kind", &"") == &"footstep.stone"
		and is_equal_approx(
			float(stone_summary.get("last_base_strength", 0.0)),
			0.52
		)
		and is_equal_approx(
			float(stone_summary.get("last_strength", 0.0)),
			0.52
		)
		and int(stone_reaction.get("heard_count", 0)) == 1
		and stone_reaction.get("last_heard_kind", &"")
			== &"footstep.stone",
		"Phase 5.1 standing stone footsteps derive identity/strength from SurfaceProfile and resolve through the existing gameplay.sound acoustic reaction path"
	)

	var stone_meter_summary: Dictionary = noise_meter.get_last_summary()
	_assert_true(
		is_equal_approx(noise_meter.get_current_loudness(), 0.52)
		and is_equal_approx(float(noise_bar.value), 0.52)
		and stone_meter_summary.get("last_sound_kind", &"")
			== &"footstep.stone"
		and is_equal_approx(
			float(stone_meter_summary.get("last_strength", 0.0)),
			0.52
		)
		and noise_meter.get_debug_text().contains("footstep.stone"),
		"Integrated Slice development loudness meter observes the actual semantic footstep source strength beside the exposure meter"
	)

	player.global_position = Vector3(0.0, 0.0, -4.0)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -3.0)
	guard.velocity = Vector3.ZERO
	await _settle_overlap_frames(3)
	guard_listener.clear_perception()

	var carpet_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var carpet_summary: Dictionary = footsteps.get_debug_summary()
	var carpet_perception: Dictionary = guard_listener.get_last_perception()

	_assert_true(
		carpet_queued
		and carpet_summary.get("last_surface_id", &"") == &"carpet"
		and carpet_summary.get("last_sound_kind", &"") == &"footstep.carpet"
		and is_equal_approx(
			float(carpet_summary.get("last_base_strength", 0.0)),
			0.20
		)
		and is_equal_approx(
			float(carpet_summary.get("last_strength", 0.0)),
			0.20
		)
		and bool(carpet_perception.get("heard", false))
		and carpet_perception.get("kind", &"") == &"footstep.carpet",
		"Phase 5.1 quiet carpet is a profile-driven semantic surface rather than a hard-coded footstep special case"
	)

	var sprint_command := PlayerCommand.new()
	sprint_command.movement_vector = Vector2(0.0, -1.0)
	sprint_command.sprint_held = true
	var player_input := player.get("player_input") as PlayerInput
	var sprint_state_ready: bool = player_input != null
	if player_input != null:
		player_input.current_command = sprint_command
	var sprint_movement: Dictionary = player.call(
		"get_movement_semantic_state"
	)
	guard_listener.clear_perception()
	var sprint_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var sprint_summary: Dictionary = footsteps.get_debug_summary()
	var sprint_meter_summary: Dictionary = noise_meter.get_last_summary()
	_assert_true(
		sprint_state_ready
		and bool(sprint_movement.get("sprinting", false))
		and sprint_queued
		and sprint_summary.get("last_gait", "") == "sprinting"
		and is_equal_approx(
			float(sprint_summary.get("last_strength", 0.0)),
			0.20 * 1.35
		)
		and float(sprint_summary.get("last_strength", 0.0))
			> float(carpet_summary.get("last_strength", 0.0))
		and is_equal_approx(
			noise_meter.get_current_loudness(),
			0.20 * 1.35
		)
		and sprint_meter_summary.get("last_gait", "") == "sprinting"
		and noise_meter.get_debug_text().contains("sprinting"),
		"Sprinting uses the locomotion sprint intent to make the same carpet footstep semantically louder than walking and the debug meter reports that truth"
	)

	if player_input != null:
		player_input.current_command = PlayerCommand.new()
	var crouched_ready: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.CROUCHED
	)
	guard_listener.clear_perception()
	var crouched_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var crouched_summary: Dictionary = footsteps.get_debug_summary()
	var crouched_meter_summary: Dictionary = noise_meter.get_last_summary()

	_assert_true(
		crouched_ready
		and crouched_queued
		and crouched_summary.get("last_surface_id", &"") == &"carpet"
		and crouched_summary.get("last_sound_kind", &"") == &"footstep.carpet"
		and is_equal_approx(
			float(crouched_summary.get("last_base_strength", 0.0)),
			0.20
		)
		and is_equal_approx(
			float(crouched_summary.get("last_strength", 0.0)),
			0.20 * 0.45
		),
		"Phase 5.1 stance modifies emitted strength without changing the authored surface identity or semantic sound kind"
	)

	_assert_true(
		is_equal_approx(
			noise_meter.get_current_loudness(),
			0.20 * 0.45
		)
		and is_equal_approx(
			float(crouched_meter_summary.get("last_strength", 0.0)),
			0.20 * 0.45
		)
		and crouched_meter_summary.get("last_stance", "")
			== "crouched"
		and crouched_meter_summary.get("last_gait", "")
			== "crouched"
		and noise_meter.get_debug_text().contains("footstep.carpet")
		and noise_meter.get_debug_text().contains("crouched"),
		"Development loudness meter tracks the crouched carpet source value without creating independent stealth-noise truth"
	)

	var cadence_standing_ready: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.STANDING
	)
	player.global_position = Vector3(0.0, 0.0, 4.0)
	player.velocity = Vector3.ZERO
	await _settle_overlap_frames(3)
	var cadence_grounded: bool = bool(player.call("is_grounded"))
	player.set_physics_process(false)
	footsteps.step_distance = 0.80
	footsteps.minimum_move_speed = 0.35
	footsteps.set_emission_enabled(true)
	var cadence_start_count: int = int(
		footsteps.get_debug_summary().get("queued_count", 0)
	)

	player.velocity = Vector3(1.0, 0.0, 0.0)
	player.global_position += Vector3(0.22, 0.0, 0.0)
	await _completed_physics_frame()
	var first_burst_progress: float = float(
		footsteps.get_debug_summary().get("distance_since_step", 0.0)
	)
	player.velocity = Vector3.ZERO
	await _completed_physics_frame()
	var paused_progress: float = float(
		footsteps.get_debug_summary().get("distance_since_step", 0.0)
	)

	for _burst: int in 3:
		player.velocity = Vector3(1.0, 0.0, 0.0)
		player.global_position += Vector3(0.22, 0.0, 0.0)
		await _completed_physics_frame()
		player.velocity = Vector3.ZERO
		await _completed_physics_frame()

	var cadence_summary: Dictionary = footsteps.get_debug_summary()
	_assert_true(
		cadence_standing_ready
		and cadence_grounded
		and first_burst_progress > 0.20
		and is_equal_approx(paused_progress, first_burst_progress)
		and int(cadence_summary.get("queued_count", 0))
			== cadence_start_count + 1
		and float(cadence_summary.get("distance_since_step", -1.0))
			> 0.0
		and float(cadence_summary.get("distance_since_step", 1.0))
			< footsteps.step_distance,
		"Phase 5.1 grounded sub-step movement bursts retain cadence progress across stationary pauses and eventually emit a footstep instead of exploiting stop-to-reset silence"
	)
	footsteps.set_emission_enabled(false)
	player.velocity = Vector3.ZERO

	_cleanup_application(application)


func _request_player_stance(
	player: CharacterBody3D,
	stance: int
) -> bool:
	var crouch := player.get("crouch") as PlayerCrouch
	if crouch == null:
		return false
	crouch.request_stance(stance)
	var expected: String = (
		"crouched"
		if stance == PlayerCrouch.Stance.CROUCHED
		else "standing"
	)
	for _frame: int in 45:
		await _completed_physics_frame()
		var movement: Dictionary = player.call(
			"get_movement_semantic_state"
		)
		if movement.get("stance", "") == expected:
			return true
	return false


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


func _settle_overlap_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await _completed_physics_frame()


func _completed_physics_frame() -> void:
	await physics_frame
	await process_frame


func _cleanup_application(application: Node) -> void:
	if application != null and is_instance_valid(application):
		if application.get("current_session") != null:
			application.call("exit_current_world")
		application.free()


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
		print("ALL GAMEPLAY NOISE TESTS PASSED")
		return
	print("%d GAMEPLAY NOISE TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
