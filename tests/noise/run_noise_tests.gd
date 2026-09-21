extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"
const STONE_PROFILE_PATH: String = "res://gameplay/noise/profiles/stone.tres"
const CARPET_PROFILE_PATH: String = "res://gameplay/noise/profiles/carpet.tres"
const TILE_PROFILE_PATH: String = "res://gameplay/noise/profiles/tile.tres"
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
	var tile := load(TILE_PROFILE_PATH) as VarkSurfaceProfile
	var missing_id := VarkSurfaceProfile.new()
	missing_id.surface_id = &""
	var invalid_level := VarkSurfaceProfile.new()
	invalid_level.surface_id = &"invalid"
	invalid_level.loudness_level = 99

	_assert_true(
		stone != null
		and carpet != null
		and tile != null
		and stone.is_valid_profile()
		and carpet.is_valid_profile()
		and tile.is_valid_profile()
		and carpet.surface_id == &"carpet"
		and stone.surface_id == &"stone"
		and tile.surface_id == &"tile"
		and carpet.get_loudness_id() == &"quiet"
		and stone.get_loudness_id() == &"normal"
		and tile.get_loudness_id() == &"loud"
		and carpet.get_footstep_sound_kind() == &"footstep.carpet"
		and stone.get_footstep_sound_kind() == &"footstep.stone"
		and tile.get_footstep_sound_kind() == &"footstep.tile"
		and is_equal_approx(carpet.get_footstep_strength(), 0.09)
		and is_equal_approx(stone.get_footstep_strength(), 0.45)
		and is_equal_approx(tile.get_footstep_strength(), 0.90)
		and carpet.get_footstep_strength() < stone.get_footstep_strength()
		and stone.get_footstep_strength() < tile.get_footstep_strength(),
		"Phase 5.1 SurfaceProfiles enforce exactly quiet/normal/loud footstep tiers with canonical strengths"
	)
	_assert_true(
		not missing_id.is_valid_profile()
		and missing_id.get_footstep_sound_kind().is_empty()
		and not invalid_level.is_valid_profile()
		and invalid_level.get_loudness_id().is_empty()
		and is_zero_approx(invalid_level.get_footstep_strength()),
		"Phase 5.1 invalid surface IDs or loudness tiers fail closed instead of manufacturing gameplay-noise truth"
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
	var tile_surface := (
		world.get_node_or_null("TileSurface") as VarkFootstepSurface
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
		and is_equal_approx(guard_listener.hearing_threshold, 0.16)
		and reaction != null
		and footsteps != null
		and stone_surface != null
		and carpet_surface != null
		and tile_surface != null
		and noise_meter != null
		and noise_meter.get_script() == NoiseMeter
		and noise_bar != null
		and stone_surface.get_surface_profile().resource_path
			== STONE_PROFILE_PATH
		and carpet_surface.get_surface_profile().resource_path
			== CARPET_PROFILE_PATH
		and tile_surface.get_surface_profile().resource_path
			== TILE_PROFILE_PATH,
		"Phase 5.1 the real Integrated Slice consumes reusable gameplay/noise surfaces, emitter, authored profiles, and the tuned 0.16 guard hearing floor"
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
		or tile_surface == null
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
		and stone_summary.get("last_loudness_id", &"") == &"normal"
		and stone_summary.get("last_sound_kind", &"") == &"footstep.stone"
		and is_equal_approx(
			float(stone_summary.get("last_base_strength", 0.0)),
			0.45
		)
		and is_equal_approx(
			float(stone_summary.get("last_strength", 0.0)),
			0.45
		)
		and int(stone_reaction.get("heard_count", 0)) == 1
		and stone_reaction.get("last_heard_kind", &"")
			== &"footstep.stone",
		"Phase 5.1 standing stone footsteps derive identity/strength from SurfaceProfile and resolve through the existing gameplay.sound acoustic reaction path"
	)

	var stone_meter_summary: Dictionary = noise_meter.get_last_summary()
	_assert_true(
		is_equal_approx(noise_meter.get_current_loudness(), 0.45)
		and is_equal_approx(float(noise_bar.value), 0.45)
		and stone_meter_summary.get("last_sound_kind", &"")
			== &"footstep.stone"
		and is_equal_approx(
			float(stone_meter_summary.get("last_strength", 0.0)),
			0.45
		)
		and noise_meter.get_debug_text().contains("footstep.stone"),
		"Integrated Slice development loudness meter observes the actual semantic footstep source strength beside the exposure meter"
	)

	player.global_position = Vector3(0.0, 0.0, 6.85)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, 6.10)
	guard.velocity = Vector3.ZERO
	await _settle_overlap_frames(3)
	guard_listener.clear_perception()

	var tile_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var tile_summary: Dictionary = footsteps.get_debug_summary()
	var tile_perception: Dictionary = guard_listener.get_last_perception()
	var tile_meter_summary: Dictionary = noise_meter.get_last_summary()
	_assert_true(
		tile_queued
		and tile_summary.get("last_surface_id", &"") == &"tile"
		and tile_summary.get("last_loudness_id", &"") == &"loud"
		and tile_summary.get("last_sound_kind", &"") == &"footstep.tile"
		and is_equal_approx(
			float(tile_summary.get("last_base_strength", 0.0)),
			0.90
		)
		and bool(tile_perception.get("heard", false))
		and tile_perception.get("kind", &"") == &"footstep.tile"
		and is_equal_approx(noise_meter.get_current_loudness(), 0.90)
		and tile_meter_summary.get("last_loudness_id", &"") == &"loud"
		and noise_meter.get_debug_text().contains("loud"),
		"Phase 5.1 tile is the loud surface tier and uses the same semantic sound, acoustic listener, and debug-meter path"
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
		and carpet_summary.get("last_loudness_id", &"") == &"quiet"
		and carpet_summary.get("last_sound_kind", &"") == &"footstep.carpet"
		and is_equal_approx(
			float(carpet_summary.get("last_base_strength", 0.0)),
			0.09
		)
		and is_equal_approx(
			float(carpet_summary.get("last_strength", 0.0)),
			0.09
		)
		and not bool(carpet_perception.get("heard", true))
		and carpet_perception.get("kind", &"") == &"footstep.carpet"
		and float(carpet_perception.get("propagated_strength", 1.0))
			< float(carpet_perception.get("hearing_threshold", 0.0)),
		"Phase 5.1 normal walking on quiet carpet is emitted semantically but is already below the guard hearing floor at roughly one meter"
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
	var sprint_perception: Dictionary = guard_listener.get_last_perception()
	var sprint_meter_summary: Dictionary = noise_meter.get_last_summary()
	_assert_true(
		sprint_state_ready
		and bool(sprint_movement.get("sprinting", false))
		and sprint_queued
		and sprint_summary.get("last_gait", "") == "sprinting"
		and is_equal_approx(
			float(sprint_summary.get("last_strength", 0.0)),
			0.09 * 1.35
		)
		and float(sprint_summary.get("last_strength", 0.0))
			> float(carpet_summary.get("last_strength", 0.0))
		and float(sprint_summary.get("last_strength", 0.0))
			< guard_listener.hearing_threshold
		and not bool(sprint_perception.get("heard", true))
		and sprint_perception.get("kind", &"") == &"footstep.carpet"
		and float(sprint_perception.get("propagated_strength", 1.0))
			< float(sprint_perception.get("hearing_threshold", 0.0))
		and is_equal_approx(
			noise_meter.get_current_loudness(),
			0.09 * 1.35
		)
		and sprint_meter_summary.get("last_gait", "") == "sprinting"
		and noise_meter.get_debug_text().contains("sprinting"),
		"Sprinting makes near-silent carpet louder than walking but remains below the real slice guard hearing floor at ordinary test distance"
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
			0.09
		)
		and is_equal_approx(
			float(crouched_summary.get("last_strength", 0.0)),
			0.09 * 0.45
		)
		and float(crouched_summary.get("last_strength", 0.0))
			< guard_listener.hearing_threshold,
		"Phase 5.1 stance modifies emitted strength without changing the authored surface identity or semantic sound kind"
	)

	_assert_true(
		is_equal_approx(
			noise_meter.get_current_loudness(),
			0.09 * 0.45
		)
		and is_equal_approx(
			float(crouched_meter_summary.get("last_strength", 0.0)),
			0.09 * 0.45
		)
		and crouched_meter_summary.get("last_stance", "")
			== "crouched"
		and crouched_meter_summary.get("last_gait", "")
			== "crouched"
		and noise_meter.get_debug_text().contains("footstep.carpet")
		and noise_meter.get_debug_text().contains("crouched"),
		"Development loudness meter tracks the crouched carpet source value without creating independent stealth-noise truth"
	)

	# Hearing-only behavior matrix. Freeze awareness physics so vision cannot
	# promote these deliberately out-of-sight footstep reactions.
	reaction.set_physics_process(false)
	var investigate_source_floor: float = float(
		reaction.get_debug_summary().get(
			"hearing_footstep_investigate_source_floor",
			0.0
		)
	)

	# Stone sneak: clearly heard at close range, but source intensity is capped
	# below investigation even if propagated strength is high enough.
	var stone_sneak_ready: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.CROUCHED
	)
	if player_input != null:
		player_input.current_command = PlayerCommand.new()
	player.global_position = Vector3(0.0, 0.0, 4.0)
	guard.global_position = Vector3(0.0, 0.0, 3.85)
	await _settle_overlap_frames(3)
	guard_listener.clear_perception()
	reaction.call("reset_reaction")
	var stone_sneak_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var stone_sneak_step: Dictionary = footsteps.get_debug_summary()
	var stone_sneak_perception: Dictionary = guard_listener.get_last_perception()
	var stone_sneak_reaction: Dictionary = reaction.call("get_debug_summary")
	var stone_sneak_repeat_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var stone_sneak_repeat_reaction: Dictionary = reaction.call(
		"get_debug_summary"
	)
	_assert_true(
		stone_sneak_ready
		and stone_sneak_queued
		and stone_sneak_repeat_queued
		and is_equal_approx(
			float(stone_sneak_step.get("last_strength", 0.0)),
			0.45 * 0.45
		)
		and float(stone_sneak_step.get("last_strength", 0.0))
			< investigate_source_floor
		and bool(stone_sneak_perception.get("heard", false))
		and stone_sneak_reaction.get("awareness_state", &"") == &"suspicious"
		and stone_sneak_repeat_reaction.get("awareness_state", &"")
			== &"suspicious",
		"Stone sneak can be noticed at very close range but repeated sneak steps are source-capped at suspicion and never promote to investigation"
	)

	# Stone walk/run: both are strong enough sources to investigate.
	var stone_walk_ready: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.STANDING
	)
	if player_input != null:
		player_input.current_command = PlayerCommand.new()
	guard_listener.clear_perception()
	reaction.call("reset_reaction")
	var stone_walk_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var stone_walk_reaction: Dictionary = reaction.call("get_debug_summary")
	_assert_true(
		stone_walk_ready
		and stone_walk_queued
		and stone_walk_reaction.get("awareness_state", &"")
			== &"investigating",
		"Stone walk is strong enough to trigger investigation when heard at close range"
	)

	var stone_run_command := PlayerCommand.new()
	stone_run_command.movement_vector = Vector2(0.0, -1.0)
	stone_run_command.sprint_held = true
	if player_input != null:
		player_input.current_command = stone_run_command
	guard_listener.clear_perception()
	reaction.call("reset_reaction")
	var stone_run_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var stone_run_reaction: Dictionary = reaction.call("get_debug_summary")
	var stone_run_strength: float = float(
		footsteps.get_debug_summary().get("last_strength", 0.0)
	)
	_assert_true(
		player_input != null
		and stone_run_queued
		and stone_run_reaction.get("awareness_state", &"")
			== &"investigating",
		"Stone run is strong enough to trigger investigation when heard at close range"
	)

	guard_listener.clear_perception()
	reaction.call("reset_reaction")
	var stone_landing_queued: bool = footsteps.emit_landing_now()
	await _completed_physics_frame()
	var stone_landing_summary: Dictionary = footsteps.get_debug_summary()
	var stone_landing_reaction: Dictionary = reaction.call("get_debug_summary")
	_assert_true(
		stone_landing_queued
		and stone_landing_summary.get("last_surface_id", &"") == &"stone"
		and stone_landing_summary.get("last_gait", "") == "landing"
		and is_equal_approx(
			float(stone_landing_summary.get("last_strength", 0.0)),
			stone_run_strength
		)
		and stone_landing_reaction.get("awareness_state", &"") == &"investigating",
		"Landing after airborne movement uses exactly the running loudness multiplier for the corresponding surface"
	)

	# Tile is deliberately loud: even sneak clears the fixed source floor, so
	# walk and run (which are stronger) remain investigation-capable too.
	var tile_sneak_ready: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.CROUCHED
	)
	if player_input != null:
		player_input.current_command = PlayerCommand.new()
	player.global_position = Vector3(0.0, 0.0, 6.85)
	guard.global_position = Vector3(0.0, 0.0, 6.70)
	await _settle_overlap_frames(3)
	guard_listener.clear_perception()
	reaction.call("reset_reaction")
	var tile_sneak_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var tile_sneak_step: Dictionary = footsteps.get_debug_summary()
	var tile_sneak_reaction: Dictionary = reaction.call("get_debug_summary")
	_assert_true(
		tile_sneak_ready
		and tile_sneak_queued
		and is_equal_approx(
			float(tile_sneak_step.get("last_strength", 0.0)),
			0.90 * 0.45
		)
		and float(tile_sneak_step.get("last_strength", 0.0))
			>= investigate_source_floor
		and tile_sneak_reaction.get("awareness_state", &"")
			== &"investigating",
		"Tile sneak is deliberately loud enough to trigger investigation"
	)

	var tile_walk_ready: bool = await _request_player_stance(
		player,
		PlayerCrouch.Stance.STANDING
	)
	if player_input != null:
		player_input.current_command = PlayerCommand.new()
	guard_listener.clear_perception()
	reaction.call("reset_reaction")
	var tile_walk_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var tile_walk_reaction: Dictionary = reaction.call("get_debug_summary")
	_assert_true(
		tile_walk_ready
		and tile_walk_queued
		and tile_walk_reaction.get("awareness_state", &"")
			== &"investigating",
		"Tile walk triggers investigation"
	)

	var tile_run_command := PlayerCommand.new()
	tile_run_command.movement_vector = Vector2(0.0, -1.0)
	tile_run_command.sprint_held = true
	if player_input != null:
		player_input.current_command = tile_run_command
	guard_listener.clear_perception()
	reaction.call("reset_reaction")
	var tile_run_queued: bool = footsteps.emit_step_now()
	await _completed_physics_frame()
	var tile_run_reaction: Dictionary = reaction.call("get_debug_summary")
	_assert_true(
		player_input != null
		and tile_run_queued
		and tile_run_reaction.get("awareness_state", &"")
			== &"investigating",
		"Tile run triggers investigation"
	)

	reaction.set_physics_process(true)
	if player_input != null:
		player_input.current_command = PlayerCommand.new()

	# Exercise the same transition helper called by the emitter's real physics
	# process, but drive the semantic support states deterministically so this
	# regression does not depend on mutating PlayerSupport internals.
	var landing_transition_start_count: int = int(
		footsteps.get_debug_summary().get("queued_count", 0)
	)
	footsteps.set_physics_process(false)
	footsteps.set_emission_enabled(true)
	player.global_position = Vector3(0.0, 0.0, 4.0)
	await _settle_overlap_frames(2)
	var airborne_allows_cadence: bool = bool(
		footsteps._advance_landing_transition({
			"support": "airborne",
			"traversal": "normal",
		})
	)
	var armed_airborne: bool = bool(
		footsteps.get_debug_summary().get("landing_armed", false)
	)
	var landing_allows_cadence: bool = bool(
		footsteps._advance_landing_transition({
			"support": "grounded",
			"traversal": "normal",
		})
	)
	await _completed_physics_frame()
	var automatic_landing_summary: Dictionary = footsteps.get_debug_summary()
	_assert_true(
		not airborne_allows_cadence
		and armed_airborne
		and not landing_allows_cadence
		and int(automatic_landing_summary.get("queued_count", 0))
			== landing_transition_start_count + 1
		and automatic_landing_summary.get("last_gait", "") == "landing"
		and float(automatic_landing_summary.get("last_base_strength", 0.0)) > 0.0
		and is_equal_approx(
			float(automatic_landing_summary.get("last_strength", 0.0)),
			float(automatic_landing_summary.get("last_base_strength", 0.0))
				* footsteps.sprint_strength_scale
		),
		(
			"Phase 5.1 the production airborne-to-grounded transition logic emits exactly one running-strength landing sound on the current surface "
			+ "(summary=%s)" % str(automatic_landing_summary)
		)
	)

	var mantle_walk_start_count: int = int(
		automatic_landing_summary.get("queued_count", 0)
	)
	var mantle_walk_active_allows: bool = bool(
		footsteps._advance_landing_transition({
			"support": "grounded",
			"traversal": "mantling",
			"stance": "standing",
		})
	)
	var mantle_walk_pending: bool = bool(
		footsteps.get_debug_summary().get("mantle_contact_pending", false)
	)
	var mantle_walk_complete_allows: bool = bool(
		footsteps._advance_landing_transition({
			"support": "grounded",
			"traversal": "normal",
			"stance": "standing",
		})
	)
	await _completed_physics_frame()
	var mantle_walk_summary: Dictionary = footsteps.get_debug_summary()
	_assert_true(
		not mantle_walk_active_allows
		and mantle_walk_pending
		and not mantle_walk_complete_allows
		and int(mantle_walk_summary.get("queued_count", 0))
			== mantle_walk_start_count + 1
		and mantle_walk_summary.get("last_gait", "") == "walking"
		and is_equal_approx(
			float(mantle_walk_summary.get("last_strength", 0.0)),
			float(mantle_walk_summary.get("last_base_strength", 0.0))
		),
		(
			"Phase 5.1 standing mantle completion emits one walking-strength step instead of a running-strength landing "
			+ "(summary=%s)" % str(mantle_walk_summary)
		)
	)

	var mantle_crouch_start_count: int = int(
		mantle_walk_summary.get("queued_count", 0)
	)
	footsteps._advance_landing_transition({
		"support": "grounded",
		"traversal": "mantling",
		"stance": "crouched",
	})
	var mantle_crouch_complete_allows: bool = bool(
		footsteps._advance_landing_transition({
			"support": "grounded",
			"traversal": "normal",
			"stance": "crouched",
		})
	)
	await _completed_physics_frame()
	var mantle_crouch_summary: Dictionary = footsteps.get_debug_summary()
	_assert_true(
		not mantle_crouch_complete_allows
		and int(mantle_crouch_summary.get("queued_count", 0))
			== mantle_crouch_start_count + 1
		and mantle_crouch_summary.get("last_gait", "") == "crouched"
		and is_equal_approx(
			float(mantle_crouch_summary.get("last_strength", 0.0)),
			float(mantle_crouch_summary.get("last_base_strength", 0.0))
				* footsteps.crouched_strength_scale
		),
		(
			"Phase 5.1 crouched mantle completion emits one crouched/sneaking-strength step "
			+ "(summary=%s)" % str(mantle_crouch_summary)
		)
	)

	var cancelled_mantle_start_count: int = int(
		mantle_crouch_summary.get("queued_count", 0)
	)
	footsteps._advance_landing_transition({
		"support": "grounded",
		"traversal": "mantling",
		"stance": "standing",
	})
	var cancelled_to_air_allows: bool = bool(
		footsteps._advance_landing_transition({
			"support": "airborne",
			"traversal": "normal",
			"stance": "standing",
		})
	)
	var cancelled_air_summary: Dictionary = footsteps.get_debug_summary()
	var cancelled_landing_allows: bool = bool(
		footsteps._advance_landing_transition({
			"support": "grounded",
			"traversal": "normal",
			"stance": "standing",
		})
	)
	await _completed_physics_frame()
	var cancelled_landing_summary: Dictionary = footsteps.get_debug_summary()
	_assert_true(
		not cancelled_to_air_allows
		and not bool(cancelled_air_summary.get("mantle_contact_pending", true))
		and bool(cancelled_air_summary.get("landing_armed", false))
		and not cancelled_landing_allows
		and int(cancelled_landing_summary.get("queued_count", 0))
			== cancelled_mantle_start_count + 1
		and cancelled_landing_summary.get("last_gait", "") == "landing"
		and is_equal_approx(
			float(cancelled_landing_summary.get("last_strength", 0.0)),
			float(cancelled_landing_summary.get("last_base_strength", 0.0))
				* footsteps.sprint_strength_scale
		),
		"Phase 5.1 a cancelled mantle that releases to air keeps the ordinary hard fall-landing rule"
	)

	footsteps.set_emission_enabled(false)
	footsteps.set_physics_process(true)
	await _settle_overlap_frames(2)

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
