extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const IntegratedReaction = preload("res://missions/integrated_slice/guard_reaction.gd")
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"

const GUARD_COUNT: int = 12
const VISION_ROUNDS: int = 32
const SOUND_EVENT_COUNT: int = 48
const EXTRA_LIGHT_COUNT: int = 24
const EXPOSURE_SAMPLE_COUNT: int = 48
const DOOR_NAV_CYCLE_COUNT: int = 64

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("[PHASE5_STRESS_ENV] ", JSON.stringify(_environment_summary()))

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
	var navigation_ready: bool = await _wait_for_navigation_ready(world, 360)
	var original_guard := (
		world.get_node_or_null("Guard") as VarkGuard
		if world != null else null
	)
	var exposure := (
		world.get_node_or_null("GameplayExposure") as VarkGameplayExposure
		if world != null else null
	)
	var propagation := (
		world.get_node_or_null("AcousticPropagation") as VarkAcousticPropagation
		if world != null else null
	)
	var door := (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null else null
	)

	_assert_true(
		launched
		and navigation_ready
		and world != null
		and player != null
		and original_guard != null
		and exposure != null
		and propagation != null
		and door != null,
		"5.8 stress fixture launches the real Integrated Slice production owners"
	)
	if (
		not launched
		or not navigation_ready
		or world == null
		or player == null
		or original_guard == null
		or exposure == null
		or propagation == null
		or door == null
	):
		await _cleanup(application)
		_print_summary()
		quit(1)
		return

	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.0, 5.5)
	door.set_physics_process(false)
	exposure.set_physics_process(false)

	var guards: Array[VarkGuard] = _create_stress_guards(
		world,
		original_guard
	)
	await process_frame
	var reactions: Array[Node] = []
	for guard: VarkGuard in guards:
		guard.set_physics_process(false)
		guard.velocity = Vector3.ZERO
		guard.look_at(player.global_position, Vector3.UP, true)
		var reaction: Node = guard.get_node_or_null("Reaction")
		if reaction != null:
			reaction.set_physics_process(false)
			reaction.call("reset_reaction")
			reactions.append(reaction)

	_assert_true(
		guards.size() == GUARD_COUNT
		and reactions.size() == GUARD_COUNT,
		"5.8 creates twelve simultaneous real guard/awareness owners without replacing the production vision path"
	)

	exposure.sample_now()
	var vision_start_us: int = Time.get_ticks_usec()
	var vision_visible_count: int = 0
	for _round: int in VISION_ROUNDS:
		for reaction: Node in reactions:
			if bool(reaction.call("sample_vision_now", 0.0)):
				vision_visible_count += 1
	var vision_total_us: int = Time.get_ticks_usec() - vision_start_us
	var vision_checks: int = guards.size() * VISION_ROUNDS
	var vision_state_valid: bool = true
	for reaction: Node in reactions:
		var summary: Dictionary = reaction.call("get_debug_summary")
		vision_state_valid = (
			vision_state_valid
			and is_finite(float(summary.get("last_vision_distance", NAN)))
			and is_finite(float(summary.get("last_vision_exposure", NAN)))
	)
	_assert_true(
		vision_checks == GUARD_COUNT * VISION_ROUNDS
		and vision_state_valid
		and vision_total_us > 0,
		"5.8 executes the fixed multi-guard production vision workload and records finite observation time"
	)

	var acoustic_configuration: Dictionary = propagation.configure(world)
	var acoustic_summary: Dictionary = propagation.get_debug_summary()
	var listener_count: int = int(acoustic_summary.get("listener_count", 0))
	var sound_event: Dictionary = {
		"name": &"gameplay.sound",
		"payload": {
			"kind": &"stress.measurement",
			"origin": player.global_position + Vector3.UP,
			"strength": 1.0,
		},
	}
	var sound_start_us: int = Time.get_ticks_usec()
	var sounds_handled: int = 0
	for _index: int in SOUND_EVENT_COUNT:
		if propagation.handle_gameplay_sound(sound_event):
			sounds_handled += 1
	var sound_total_us: int = Time.get_ticks_usec() - sound_start_us
	var last_sound: Dictionary = propagation.get_last_sound_debug_snapshot()
	var last_listener_results: Array = last_sound.get("listeners", [])
	_assert_true(
		bool(acoustic_configuration.get("ok", false))
		and listener_count >= GUARD_COUNT
		and sounds_handled == SOUND_EVENT_COUNT
		and last_listener_results.size() == listener_count
		and sound_total_us > 0,
		"5.8 propagates forty-eight semantic sounds across the real acoustic graph with at least twelve hearing receivers"
	)

	var base_light_count: int = int(
		exposure.get_exposure_summary().get("source_count", 0)
	)
	_add_stress_lights(world, player)
	await process_frame
	exposure.refresh_sources()
	var light_summary: Dictionary = exposure.sample_now()
	var total_light_count: int = int(light_summary.get("source_count", 0))
	var exposure_start_us: int = Time.get_ticks_usec()
	for _index: int in EXPOSURE_SAMPLE_COUNT:
		light_summary = exposure.sample_now()
	var exposure_total_us: int = Time.get_ticks_usec() - exposure_start_us
	_assert_true(
		total_light_count == base_light_count + EXTRA_LIGHT_COUNT
		and int(light_summary.get("sample_count", 0)) > 0
		and is_finite(float(light_summary.get("exposure", NAN)))
		and is_finite(float(light_summary.get("raw_exposure", NAN)))
		and exposure_total_us > 0,
		"5.8 executes forty-eight production exposure samples with twenty-four additional real gameplay lights"
	)

	var navigation_map: RID = world.get_world_3d().navigation_map
	var patrol_a := world.get_node_or_null("PatrolA") as Node3D
	var patrol_b := world.get_node_or_null("PatrolB") as Node3D
	var nav_start_us: int = Time.get_ticks_usec()
	var successful_paths: int = 0
	var successful_door_changes: int = 0
	if patrol_a != null and patrol_b != null and navigation_map.is_valid():
		for cycle: int in DOOR_NAV_CYCLE_COUNT:
			var opening: bool = cycle % 2 == 0
			var applied: bool = door.apply_semantic_state({
				"phase": (
					VarkOrdinaryDoor.PHASE_OPEN
					if opening
					else VarkOrdinaryDoor.PHASE_CLOSED
				),
				"open_fraction": 1.0 if opening else 0.0,
				"motion_blocked": false,
			})
			if applied:
				successful_door_changes += 1
			var path: PackedVector3Array = NavigationServer3D.map_get_path(
				navigation_map,
				patrol_a.global_position,
				patrol_b.global_position,
				true
			)
			if not path.is_empty():
				successful_paths += 1
	var door_nav_total_us: int = Time.get_ticks_usec() - nav_start_us
	var restored_open: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_OPEN,
		"open_fraction": 1.0,
		"motion_blocked": false,
	})
	var link_summary: Dictionary = door.get_navigation_link_summary()
	_assert_true(
		patrol_a != null
		and patrol_b != null
		and navigation_map.is_valid()
		and successful_door_changes == DOOR_NAV_CYCLE_COUNT
		and successful_paths == DOOR_NAV_CYCLE_COUNT
		and restored_open
		and door.is_navigation_passage_open()
		and bool(link_summary.get("map_bound", false))
		and door_nav_total_us > 0,
		"5.8 resolves sixty-four paths across the real door-owned navigation link while alternating the same semantic door state"
	)

	var metrics: Dictionary = {
		"guard_count": guards.size(),
		"vision_rounds": VISION_ROUNDS,
		"vision_checks": vision_checks,
		"vision_visible_results": vision_visible_count,
		"vision_total_us": vision_total_us,
		"listener_count": listener_count,
		"sound_events": SOUND_EVENT_COUNT,
		"hearing_receiver_evaluations": listener_count * SOUND_EVENT_COUNT,
		"sound_total_us": sound_total_us,
		"base_gameplay_light_count": base_light_count,
		"extra_gameplay_light_count": EXTRA_LIGHT_COUNT,
		"total_gameplay_light_count": total_light_count,
		"exposure_samples": EXPOSURE_SAMPLE_COUNT,
		"exposure_total_us": exposure_total_us,
		"door_nav_cycles": DOOR_NAV_CYCLE_COUNT,
		"successful_nav_paths": successful_paths,
		"door_nav_total_us": door_nav_total_us,
	}
	print("[PHASE5_STRESS_METRICS] ", JSON.stringify(metrics))

	await _cleanup(application)
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _create_stress_guards(
	world: Node3D,
	original_guard: VarkGuard
) -> Array[VarkGuard]:
	var guards: Array[VarkGuard] = [original_guard]
	for index: int in range(1, GUARD_COUNT):
		var guard := VarkGuard.new()
		guard.name = "StressGuard%d" % index
		guard.persistent_id = "stress.guard.%d" % index
		guard.content_id = "guard.stress.%d" % index
		guard.guard_id = "guard.stress.%d" % index
		guard.patrol_a_id = "slice.patrol.a"
		guard.patrol_b_id = "slice.patrol.b"
		guard.door_id = "door.slice"
		guard.movement_speed = 1.2
		var column: int = index % 4
		var row: int = index / 4
		guard.position = Vector3(
			-3.0 + float(column) * 2.0,
			0.0,
			1.0 + float(row) * 1.4
		)

		var hearing := VarkAcousticListener.new()
		hearing.name = "Hearing"
		hearing.listener_id = StringName("listener.stress.%d" % index)
		hearing.hearing_threshold = 0.16
		guard.add_child(hearing)

		var reaction: Node = IntegratedReaction.new()
		reaction.name = "Reaction"
		guard.add_child(reaction)

		world.add_child(guard)
		guards.append(guard)

	original_guard.global_position = Vector3(-3.0, 0.0, 1.0)
	return guards


func _add_stress_lights(
	world: Node3D,
	player: CharacterBody3D
) -> void:
	for index: int in EXTRA_LIGHT_COUNT:
		var light := VarkGameplayLight.new()
		light.name = "StressGameplayLight%d" % index
		light.persistent_id = "stress.light.%d" % index
		light.gameplay_light_id = StringName("light.stress.%d" % index)
		light.gameplay_strength = 0.08
		light.gameplay_enabled = true
		light.omni_range = 12.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		var angle: float = TAU * float(index) / float(EXTRA_LIGHT_COUNT)
		light.position = player.position + Vector3(
			cos(angle) * 3.5,
			1.5 + float(index % 3) * 0.35,
			sin(angle) * 3.5
		)
		world.add_child(light)


func _environment_summary() -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	return {
		"godot": str(version.get("string", "")),
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"processor_count": OS.get_processor_count(),
		"github_actions": OS.get_environment("GITHUB_ACTIONS"),
		"runner_os": OS.get_environment("RUNNER_OS"),
		"runner_arch": OS.get_environment("RUNNER_ARCH"),
	}


func _wait_for_navigation_ready(
	world: Node3D,
	max_frames: int
) -> bool:
	if world == null:
		return false
	for _index: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await physics_frame
		await process_frame
	return bool(world.get("navigation_ready"))


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
		print("ALL PHASE 5 EARLY STRESS TESTS PASSED")
		return
	print("%d PHASE 5 EARLY STRESS TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
