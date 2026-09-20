extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const WorldSession = preload("res://application/world_session.gd")
const MissionDefinitionResource = preload("res://missions/mission_definition.gd")
const GuardNavWorld = preload("res://missions/guard_nav_lab/world.tscn")
const GuardScript = preload("res://gameplay/npc/vark_guard.gd")
const PatrolPointScript = preload("res://gameplay/npc/vark_patrol_point.gd")

const GUARD_NAV_DEFINITION_PATH: String = "res://missions/guard_nav_lab/mission.tres"
const GUARD_NAV_SOURCE_PATH: String = "res://missions/guard_nav_lab/mission.map"
const VARK_TRENCHBROOM_CONFIG_PATH: String = "res://VarkTrenchBroom.tres"
const TEMP_REIMPORT_MAP_PATH: String = "user://vark_guard_nav_reimport.map"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_assert_authoring_schema()
	_assert_guard_nav_doorway_fit()
	await _assert_application_patrol_and_door()
	await _assert_guard_obstructs_player_close()
	await _assert_guard_reopens_player_closed_route()
	await _assert_open_leaf_nearby_route_ignored()
	await _assert_open_leaf_side_block_recovery()
	await _assert_guard_uses_passable_partial_door()
	await _assert_blocked_door_recovery()
	await _assert_reimport_rebuild()
	_remove_temp_map()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_authoring_schema() -> void:
	var config := load(VARK_TRENCHBROOM_CONFIG_PATH) as TrenchBroomGameConfig
	var fgd_file: FuncGodotFGDFile = config.fgd_file if config != null else null
	var definitions: Dictionary[String, FuncGodotFGDEntityClass] = {}
	var exported_fgd: String = ""
	if fgd_file != null:
		definitions = fgd_file.get_entity_definitions()
		exported_fgd = fgd_file.build_class_text(
			FuncGodotFGDFile.FuncGodotTargetMapEditors.TRENCHBROOM
		)
	var guard_class := definitions.get("vark_guard") as FuncGodotFGDPointClass
	var patrol_class := definitions.get("vark_patrol_point") as FuncGodotFGDPointClass
	_assert_true(
		guard_class != null
		and patrol_class != null
		and guard_class.script_class == GuardScript
		and patrol_class.script_class == PatrolPointScript
		and guard_class.node_class == "CharacterBody3D"
		and patrol_class.node_class == "Node3D"
		and guard_class.class_properties.has("persistent_id")
		and guard_class.class_properties.has("content_id")
		and guard_class.class_properties.has("guard_id")
		and guard_class.class_properties.has("patrol_a_id")
		and guard_class.class_properties.has("patrol_b_id")
		and guard_class.class_properties.has("door_id")
		and is_equal_approx(float(guard_class.class_properties.get("door_use_distance", 0.0)), 2.0)
		and patrol_class.class_properties.has("patrol_id")
		and exported_fgd.contains("vark_guard")
		and exported_fgd.contains("vark_patrol_point"),
		"TrenchBroom exports the real primitive guard and patrol-point authoring entities"
	)


func _assert_guard_nav_doorway_fit() -> void:
	var source: String = FileAccess.get_file_as_string(GUARD_NAV_SOURCE_PATH)
	_assert_true(
		source.contains("( 6 43.2 84 )")
		and source.contains("( -6 84.8 0 )")
		and source.contains("( -6 43.2 68 )")
		and source.contains("( 6 84.8 84 )")
		and source.contains("\"door_use_distance\" \"2.0\"")
		and source.contains("\"persistent_id\" \"vark_guard_nav_guard\"")
		and source.contains("\"content_id\" \"guard.nav_probe\"")
		and not source.contains("( 6 40 84 )")
		and not source.contains("( -6 88 0 )"),
		"Guard/Nav Lab authored doorway is exactly 1.30 m wide so the closed ordinary leaf meets both jambs without side gaps"
	)


func _assert_application_patrol_and_door() -> void:
	var application: Node = ApplicationScene.instantiate()
	var default_labels: PackedStringArray = application.get("development_launch_labels")
	var default_paths: PackedStringArray = application.get("development_launch_resource_paths")
	_assert_true(
		default_labels.has("Guard/Nav Lab") and default_paths.has(GUARD_NAV_DEFINITION_PATH),
		"Application Development Launch exposes the Phase 3.7 Guard/Nav Lab"
	)

	application.set("development_launch_labels", PackedStringArray(["Guard/Nav Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([GUARD_NAV_DEFINITION_PATH]))
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var session := application.get("current_session") as Node
	var ready: bool = await _wait_for_navigation_ready(world, 240)
	var guard: VarkGuard = _find_guard(world)
	var door: VarkOrdinaryDoor = world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
	var navigation_summary: Dictionary = world.call("get_navigation_debug_summary") if world != null else {}
	var nav_errors: PackedStringArray = navigation_summary.get("errors", PackedStringArray())
	_assert_true(
		launched
		and session != null
		and world != null
		and world.name == &"GuardNavLab"
		and ready
		and guard != null
		and door != null
		and int(navigation_summary.get("rebuild_serial", 0)) == 1
		and int(navigation_summary.get("vertex_count", 0)) > 0
		and int(navigation_summary.get("polygon_count", 0)) > 0
		and is_equal_approx(float(navigation_summary.get("cell_size", 0.0)), 0.10)
		and is_equal_approx(float(navigation_summary.get("map_cell_size", 0.0)), 0.10)
		and is_equal_approx(float(navigation_summary.get("agent_radius", 0.0)), 0.30)
		and is_equal_approx(float(navigation_summary.get("door_visual_width", 0.0)), 1.30)
		and is_equal_approx(float(navigation_summary.get("door_sweep_width", 0.0)), 1.22)
		and nav_errors.is_empty(),
		"Guard/Nav Lab launches through the production mission/session path and bakes navigation from imported FuncGodot geometry"
	)
	if not ready or guard == null or door == null:
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var guard_start_position: Vector3 = guard.global_position
	for _frame_index: int in 20:
		await physics_frame
		await process_frame
	var initial_guard_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		bool(initial_guard_summary.get("configured", false))
		and int(initial_guard_summary.get("max_observed_path_point_count", 0)) >= 3
		and float(initial_guard_summary.get("max_observed_path_x", -INF)) > 1.0,
		"Primitive guard requests a non-straight NavigationAgent3D route through the offset opening in imported geometry"
	)
	_assert_true(
		guard.global_position.distance_to(guard_start_position) > 0.05,
		"Grounded guard advances off its authored start instead of stalling on the first vertically quantized nav waypoint"
	)

	var requested_on_imminent_block: bool = await _wait_for_guard_door_request(guard, 300)
	var request_summary: Dictionary = guard.get_debug_summary()
	var request_clearance: float = float(request_summary.get("door_approach_clearance", 0.0))
	var request_distance: float = float(request_summary.get("door_distance", 0.0))
	_assert_true(
		requested_on_imminent_block
		and bool(request_summary.get("door_request_pending", false))
		and bool(request_summary.get("door_route_blocked", false))
		and bool(request_summary.get("door_obstruction_imminent", false))
		and str(request_summary.get("door_traversal_state", "")) == "waiting_open"
		and is_equal_approx(float(request_summary.get("door_use_distance", 0.0)), 2.0)
		and request_clearance > 1.50
		and request_clearance < 1.60
		and request_distance >= request_clearance
		and request_distance <= request_clearance + 0.08
		and int(request_summary.get("door_use_count", 0)) == 1,
		"Guard requests OPEN at the real leaf-swing-plus-body clearance boundary before entering the opening sweep"
	)

	var released_before_terminal_open: bool = await _wait_for_guard_release_while_door_opening(
		guard,
		door,
		180
	)
	var release_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		released_before_terminal_open
		and not bool(release_summary.get("door_route_blocked", true))
		and str(release_summary.get("door_traversal_state", "")) == "approaching"
		and not bool(release_summary.get("door_request_pending", true))
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
		and door.get_open_fraction() > 0.0
		and door.get_open_fraction() < 1.0,
		"Guard resumes movement as soon as the partially open leaf physically clears its route instead of waiting for terminal OPEN"
	)

	var completed_cycle: bool = await _wait_for_guard_cycle(guard, 720)
	var final_guard_summary: Dictionary = guard.get_debug_summary()
	if not completed_cycle:
		_print_guard_timeout_diagnostics(
			"production patrol cycle",
			guard,
			door
		)
	_assert_true(
		completed_cycle
		and int(final_guard_summary.get("patrol_leg_count", 0)) >= 2
		and int(final_guard_summary.get("patrol_cycle_count", 0)) >= 1
		and int(final_guard_summary.get("door_use_count", 0)) == 1
		and str(final_guard_summary.get("last_error", "")).is_empty()
		and door.is_navigation_passage_open()
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN,
		"The authored guard completes an A↔B patrol and opens the same ordinary door through its existing navigation seam"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _assert_guard_obstructs_player_close() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set("development_launch_labels", PackedStringArray(["Guard/Nav Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([GUARD_NAV_DEFINITION_PATH]))
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as Node3D
	var ready: bool = await _wait_for_navigation_ready(world, 240)
	var guard: VarkGuard = _find_guard(world)
	var door: VarkOrdinaryDoor = (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null
		else null
	)
	_assert_true(
		launched and ready and world != null and player != null and guard != null and door != null,
		"Guard-close obstruction fixture launches the real Guard/Nav Lab player, guard, door, and baked navigation"
	)
	if not launched or not ready or world == null or player == null or guard == null or door == null:
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var guard_in_doorway: bool = await _wait_for_guard_in_open_doorway(guard, door, 480)
	var crossing_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		guard_in_doorway
		and str(crossing_summary.get("door_traversal_state", "")) == "crossing",
		"Real guard enters explicit CROSSING state in the open ordinary-door frame before the player-close obstruction check"
	)
	if not guard_in_doorway:
		_print_guard_timeout_diagnostics("guard-close doorway arrival", guard, door)
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	# Hold the production guard body in the doorway until the player-commanded
	# close physically contacts it. The guard must not counter-request before
	# that contact, but the confirmed blocker relationship then authorizes OPEN.
	var original_speed: float = guard.movement_speed
	guard.movement_speed = 0.0
	await physics_frame
	await process_frame
	var pre_close_fraction: float = door.get_open_fraction()
	var pre_close_summary: Dictionary = guard.get_debug_summary()
	var pre_contact_open_count: int = int(
		pre_close_summary.get("crossing_block_open_count", 0)
	)
	var pre_contact_door_use_count: int = int(pre_close_summary.get("door_use_count", 0))
	door.interact(player)

	var contact_reopened: bool = await _wait_for_crossing_contact_reopen(
		guard,
		door,
		pre_contact_open_count,
		180
	)
	var reopen_fraction: float = door.get_open_fraction()
	var reopen_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		contact_reopened
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
		and reopen_fraction > 0.0
		and reopen_fraction < pre_close_fraction
		and str(reopen_summary.get("door_traversal_state", "")) == "crossing"
		and bool(reopen_summary.get("door_request_pending", false))
		and int(reopen_summary.get("crossing_block_open_count", 0)) == pre_contact_open_count + 1
		and int(reopen_summary.get("door_use_count", 0)) == pre_contact_door_use_count,
		"Player close reaches real guard contact before the CROSSING guard reverses the same ordinary door with an OPEN request"
	)

	guard.movement_speed = original_speed
	var cleared_while_opening: bool = await _wait_for_guard_clear_door_while_opening(
		guard,
		door,
		180
	)
	var clear_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		cleared_while_opening
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
		and door.get_open_fraction() > reopen_fraction
		and door.get_open_fraction() < 1.0
		and not door.is_body_in_navigation_passage(guard)
		and str(clear_summary.get("door_traversal_state", "")) == "clear"
		and not bool(clear_summary.get("door_request_pending", true)),
		"After contact-triggered OPEN, the guard keeps crossing and clears the doorway as soon as the physical gap fits, before terminal OPEN"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _assert_guard_reopens_player_closed_route() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set("development_launch_labels", PackedStringArray(["Guard/Nav Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([GUARD_NAV_DEFINITION_PATH]))
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as Node3D
	var door: VarkOrdinaryDoor = (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null
		else null
	)
	var fixture_opened: bool = false
	if door != null:
		fixture_opened = door.apply_semantic_state({
			"phase": VarkOrdinaryDoor.PHASE_OPEN,
			"open_fraction": 1.0,
			"motion_blocked": false,
		})
	var ready: bool = await _wait_for_navigation_ready(world, 240)
	var guard: VarkGuard = _find_guard(world)
	_assert_true(
		launched
		and fixture_opened
		and ready
		and world != null
		and player != null
		and guard != null
		and door != null,
		"Guard route-reopen fixture launches the real Guard/Nav Lab with an initially open ordinary door"
	)
	if (
		not launched
		or not fixture_opened
		or not ready
		or world == null
		or player == null
		or guard == null
		or door == null
	):
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var approach_window: bool = await _wait_for_guard_approach_window(
		guard,
		door,
		1.70,
		1.95,
		360
	)
	var original_speed: float = guard.movement_speed
	guard.movement_speed = 0.0
	for _frame_index: int in 2:
		await physics_frame
		await process_frame
	var before_close_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		approach_window
		and not door.is_body_in_navigation_passage(guard)
		and str(before_close_summary.get("door_traversal_state", "")) == "approaching"
		and int(before_close_summary.get("door_use_count", 0)) == 0
		and not bool(before_close_summary.get("door_request_pending", true)),
		"An approaching guard can be near the open doorway without owning an OPEN request"
	)

	door.interact(player)
	var closed_before_contact: bool = await _wait_for_door_phase(
		door,
		VarkOrdinaryDoor.PHASE_CLOSED,
		180
	)
	for _frame_index: int in 2:
		await physics_frame
		await process_frame
	var closed_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		closed_before_contact
		and int(closed_summary.get("door_use_count", 0)) == 0
		and str(closed_summary.get("door_traversal_state", "")) == "approaching"
		and not bool(closed_summary.get("door_request_pending", true)),
		"Player can close the ordinary door in front of an approaching guard without an immediate AI reopen"
	)

	guard.movement_speed = original_speed
	var requested_on_imminent_block: bool = await _wait_for_guard_door_request(guard, 180)
	var request_summary: Dictionary = guard.get_debug_summary()
	var request_clearance: float = float(request_summary.get("door_approach_clearance", 0.0))
	var request_distance: float = float(request_summary.get("door_distance", 0.0))
	_assert_true(
		requested_on_imminent_block
		and bool(request_summary.get("door_route_blocked", false))
		and bool(request_summary.get("door_obstruction_imminent", false))
		and str(request_summary.get("door_traversal_state", "")) == "waiting_open"
		and request_distance >= request_clearance
		and request_distance <= request_clearance + 0.08
		and int(request_summary.get("door_use_count", 0)) == 1
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
		and not door.is_motion_blocked(),
		"Guard requests OPEN only when its next step would enter the physical door-swing clearance, while still leaving room for the leaf to open"
	)

	var released_before_terminal_open: bool = await _wait_for_guard_release_while_door_opening(
		guard,
		door,
		180
	)
	var release_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		released_before_terminal_open
		and not bool(release_summary.get("door_route_blocked", true))
		and str(release_summary.get("door_traversal_state", "")) == "approaching"
		and not bool(release_summary.get("door_request_pending", true))
		and int(release_summary.get("door_use_count", 0)) == 1
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
		and door.get_open_fraction() > 0.0
		and door.get_open_fraction() < 1.0,
		"Physical route clearance releases the guard before terminal OPEN without inventing a second logical door use"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame

func _assert_open_leaf_nearby_route_ignored() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set("development_launch_labels", PackedStringArray(["Guard/Nav Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([GUARD_NAV_DEFINITION_PATH]))
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var door: VarkOrdinaryDoor = (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null
		else null
	)
	var fixture_opened: bool = false
	if door != null:
		fixture_opened = door.apply_semantic_state({
			"phase": VarkOrdinaryDoor.PHASE_OPEN,
			"open_fraction": 1.0,
			"motion_blocked": false,
		})
	var ready: bool = await _wait_for_navigation_ready(world, 240)
	var guard: VarkGuard = _find_guard(world)
	_assert_true(
		launched and fixture_opened and ready and world != null and guard != null and door != null,
		"Open-leaf intent fixture launches the real Guard/Nav Lab with a fully open ordinary door"
	)
	if not launched or not fixture_opened or not ready or world == null or guard == null or door == null:
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var frame: Dictionary = door.get_navigation_doorway_frame()
	var door_collision := door.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_assert_true(
		bool(frame.get("valid", false)) and door_collision != null,
		"Ordinary door exposes a fixed closed-doorway frame independent of current leaf angle"
	)
	if not bool(frame.get("valid", false)) or door_collision == null:
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var center: Vector3 = frame.get("center", door.global_position)
	var normal: Vector3 = frame.get("normal", Vector3.ZERO)
	var tangent: Vector3 = frame.get("tangent", Vector3.ZERO)
	var same_side_route := PackedVector3Array([
		center + normal * 1.0 - tangent * 0.9,
		center + normal * 1.0 + tangent * 0.9,
	])
	var crossing_route := PackedVector3Array([
		center + normal * 1.0,
		center - normal * 1.0,
	])
	_assert_true(
		not door.does_navigation_route_cross_passage(same_side_route, 0.28)
		and door.does_navigation_route_cross_passage(crossing_route, 0.28),
		"Doorway intent distinguishes a same-side nearby route from a real side-to-side passage crossing"
	)

	# Build a real NavigationAgent path across the fully-open leaf while both
	# endpoints stay on the leaf's current side of the fixed doorway. This was
	# the old false-positive trigger: capsule prediction touched the leaf, so
	# the guard closed/reopened a door it did not intend to traverse.
	var open_leaf_center: Vector3 = door_collision.global_position
	var navigation_map: RID = world.get_world_3d().navigation_map
	var original_speed: float = guard.movement_speed
	guard.movement_speed = 0.0
	guard.set_physics_process(false)
	var found_leaf_contact_without_crossing: bool = false
	var nearby_start: Vector3 = Vector3.ZERO
	var nearby_target: Vector3 = Vector3.ZERO
	for tangent_span: float in [0.8, 1.0, 1.2]:
		var candidate_start: Vector3 = NavigationServer3D.map_get_closest_point(
			navigation_map,
			open_leaf_center - tangent * tangent_span
		)
		var candidate_target: Vector3 = NavigationServer3D.map_get_closest_point(
			navigation_map,
			open_leaf_center + tangent * tangent_span
		)
		candidate_start.y = guard.global_position.y
		candidate_target.y = guard.global_position.y
		guard.global_position = candidate_start
		guard.velocity = Vector3.ZERO
		guard.set_awareness_navigation_target(&"investigate", candidate_target)
		await physics_frame
		await process_frame
		await physics_frame
		await process_frame
		if (
			bool(guard.call("_current_route_hits_door"))
			and not bool(guard.call("_current_route_requires_doorway"))
		):
			nearby_start = candidate_start
			nearby_target = candidate_target
			found_leaf_contact_without_crossing = true
			break

	_assert_true(
		found_leaf_contact_without_crossing,
		"Real same-side NavigationAgent route can pass near the open leaf without becoming doorway traversal intent"
	)
	if found_leaf_contact_without_crossing:
		guard.global_position = nearby_start
		guard.velocity = Vector3.ZERO
		guard.set_awareness_navigation_target(&"investigate", nearby_target)
		guard.set_physics_process(true)
		for _frame_index: int in 12:
			await physics_frame
			await process_frame
		var summary: Dictionary = guard.get_debug_summary()
		_assert_true(
			not bool(summary.get("doorway_traversal_required", true))
			and int(summary.get("door_maneuver_count", 0)) == 0
			and int(summary.get("door_use_count", 0)) == 0
			and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN,
			"Open leaf proximity/contact cannot trigger close-reposition-reopen when the route does not cross the doorway"
		)
	else:
		guard.set_physics_process(true)
	guard.movement_speed = original_speed

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _assert_open_leaf_side_block_recovery() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set("development_launch_labels", PackedStringArray(["Guard/Nav Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([GUARD_NAV_DEFINITION_PATH]))
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var door: VarkOrdinaryDoor = (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null
		else null
	)
	var fixture_opened: bool = false
	if door != null:
		fixture_opened = door.apply_semantic_state({
			"phase": VarkOrdinaryDoor.PHASE_OPEN,
			"open_fraction": 1.0,
			"motion_blocked": false,
		})
	var ready: bool = await _wait_for_navigation_ready(world, 240)
	var guard: VarkGuard = _find_guard(world)
	_assert_true(
		launched and fixture_opened and ready and world != null and guard != null and door != null,
		"Open-leaf maneuver fixture launches the real Guard/Nav Lab with a fully open ordinary door"
	)
	if not launched or not fixture_opened or not ready or world == null or guard == null or door == null:
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var door_collision := door.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var passage_center: Vector3 = door.get_navigation_passage_center()
	var hinge_to_center: Vector3 = passage_center - door.global_position
	hinge_to_center.y = 0.0
	var open_leaf_direction: Vector3 = (
		door_collision.global_position - door.global_position
		if door_collision != null
		else Vector3.ZERO
	)
	open_leaf_direction.y = 0.0
	_assert_true(
		door_collision != null
		and hinge_to_center.length_squared() > 0.000001
		and open_leaf_direction.length_squared() > 0.000001,
		"Open-leaf maneuver fixture resolves the real hinge, closed passage center, and current leaf direction"
	)
	if (
		door_collision == null
		or hinge_to_center.length_squared() <= 0.000001
		or open_leaf_direction.length_squared() <= 0.000001
	):
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var doorway_tangent: Vector3 = hinge_to_center.normalized()
	open_leaf_direction = open_leaf_direction.normalized()
	var side_reference: Vector3 = door.global_position + open_leaf_direction * 3.0
	var opposite_reference: Vector3 = door.global_position - open_leaf_direction * 3.0
	var side_operating: Vector3 = door.get_navigation_operating_point(
		side_reference,
		0.28,
		0.05
	)
	var opposite_operating: Vector3 = door.get_navigation_operating_point(
		opposite_reference,
		0.28,
		0.05
	)

	var original_speed: float = guard.movement_speed
	guard.movement_speed = 0.0
	# Freeze only the guard root while placing the deterministic swing-side
	# scenario. The production guard itself will decide whether the current
	# route is physically blocked once processing resumes.
	guard.set_physics_process(false)
	var hinge_offset: float = 0.34
	var blocked_start: Vector3 = (
		side_operating - doorway_tangent * hinge_offset
	)
	var blocked_target: Vector3 = (
		opposite_operating - doorway_tangent * hinge_offset
	)
	guard.global_position = blocked_start
	guard.velocity = Vector3.ZERO
	guard.set_awareness_navigation_target(&"investigate", blocked_target)
	await physics_frame
	await process_frame
	_assert_true(
		door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN
		and not door.is_body_in_navigation_passage(guard),
		"The swing-side fixture starts outside the doorway with the ordinary leaf fully open"
	)

	guard.movement_speed = original_speed
	guard.set_physics_process(true)
	var maneuver_started: bool = false
	for _frame_index: int in 60:
		var start_summary: Dictionary = guard.get_debug_summary()
		if (
			int(start_summary.get("door_maneuver_count", 0)) == 1
			and bool(start_summary.get("doorway_traversal_required", false))
		):
			maneuver_started = true
			break
		if not str(start_summary.get("last_error", "")).is_empty():
			break
		await physics_frame
		await process_frame
	_assert_true(
		maneuver_started,
		"A fully open leaf starts the recovery maneuver only after the remaining route is classified as a real doorway crossing"
	)
	if not maneuver_started:
		_print_guard_timeout_diagnostics("open-leaf maneuver start", guard, door)
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var observed_closing: bool = false
	var minimum_fraction: float = 1.0
	var crossed_after_maneuver: bool = false
	for _frame_index: int in 480:
		var phase: StringName = door.get_semantic_phase()
		observed_closing = observed_closing or phase == VarkOrdinaryDoor.PHASE_CLOSING
		minimum_fraction = minf(minimum_fraction, door.get_open_fraction())
		var summary: Dictionary = guard.get_debug_summary()
		if (
			door.is_body_in_navigation_passage(guard)
			and str(summary.get("door_traversal_state", "")) == "crossing"
			and int(summary.get("door_maneuver_count", 0)) == 1
			and int(summary.get("door_close_request_count", 0)) == 1
		):
			crossed_after_maneuver = true
			break
		if not str(summary.get("last_error", "")).is_empty():
			break
		await physics_frame
		await process_frame

	var final_summary: Dictionary = guard.get_debug_summary()
	if not crossed_after_maneuver:
		_print_guard_timeout_diagnostics("open-leaf close/reopen recovery", guard, door)
	_assert_true(
		crossed_after_maneuver
		and observed_closing
		and minimum_fraction <= 0.05
		and int(final_summary.get("door_maneuver_count", 0)) == 1
		and int(final_summary.get("door_close_request_count", 0)) == 1
		and int(final_summary.get("door_use_count", 0)) == 1
		and not bool(final_summary.get("door_close_request_pending", true))
		and str(final_summary.get("last_error", "")).is_empty(),
		"An already-open leaf that blocks the current side route makes the guard reposition outside the sweep, close it, reopen it, and cross instead of retrying OPEN forever"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _assert_guard_uses_passable_partial_door() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set("development_launch_labels", PackedStringArray(["Guard/Nav Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([GUARD_NAV_DEFINITION_PATH]))
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var door: VarkOrdinaryDoor = (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null
		else null
	)
	var fixture_opened: bool = false
	if door != null:
		fixture_opened = door.apply_semantic_state({
			"phase": VarkOrdinaryDoor.PHASE_OPEN,
			"open_fraction": 1.0,
			"motion_blocked": false,
		})
	var ready: bool = await _wait_for_navigation_ready(world, 240)
	var guard: VarkGuard = _find_guard(world)
	_assert_true(
		launched and fixture_opened and ready and world != null and guard != null and door != null,
		"Passable-partial-door fixture launches the real Guard/Nav Lab guard and ordinary door"
	)
	if not launched or not fixture_opened or not ready or world == null or guard == null or door == null:
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var approach_window: bool = await _wait_for_guard_approach_window(
		guard,
		door,
		1.70,
		1.95,
		360
	)
	var original_speed: float = guard.movement_speed
	guard.movement_speed = 0.0
	var partial_applied: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_CLOSING,
		"open_fraction": 0.85,
		"motion_blocked": true,
	})
	for _frame_index: int in 2:
		await physics_frame
		await process_frame
	var partial_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		approach_window
		and partial_applied
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_CLOSING
		and is_equal_approx(door.get_open_fraction(), 0.85)
		and not bool(partial_summary.get("door_route_blocked", true))
		and str(partial_summary.get("door_traversal_state", "")) == "approaching"
		and int(partial_summary.get("door_use_count", 0)) == 0
		and not bool(partial_summary.get("door_request_pending", true)),
		"A slightly closed ordinary door that physically clears the current guard route does not become an AI OPEN request"
	)

	guard.movement_speed = original_speed
	var crossed_partial: bool = await _wait_for_guard_crossing_without_door_use(
		guard,
		door,
		240
	)
	var crossing_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		crossed_partial
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_CLOSING
		and is_equal_approx(door.get_open_fraction(), 0.85)
		and int(crossing_summary.get("door_use_count", 0)) == 0
		and not bool(crossing_summary.get("door_request_pending", true)),
		"Guard walks through the physically passable partially closed door without waiting for terminal OPEN"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _assert_blocked_door_recovery() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set("development_launch_labels", PackedStringArray(["Guard/Nav Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([GUARD_NAV_DEFINITION_PATH]))
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as Node3D
	var ready: bool = await _wait_for_navigation_ready(world, 240)
	var guard: VarkGuard = _find_guard(world)
	var door: VarkOrdinaryDoor = (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null
		else null
	)
	_assert_true(
		launched and ready and world != null and player != null and guard != null and door != null,
		"Blocked-door recovery fixture launches the real Guard/Nav Lab player, guard, door, and baked navigation"
	)
	if not launched or not ready or world == null or player == null or guard == null or door == null:
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var original_player_transform: Transform3D = player.global_transform
	player.global_position = Vector3(2.25, 0.0, 0.55)
	player.set("velocity", Vector3.ZERO)
	await physics_frame
	await process_frame

	var blocked: bool = await _wait_for_door_blocked(guard, door, 360)
	var blocked_fraction: float = door.get_open_fraction()
	var blocked_guard_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		blocked
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
		and blocked_fraction > 0.0
		and blocked_fraction < 1.0
		and int(blocked_guard_summary.get("door_use_count", 0)) == 1
		and int(blocked_guard_summary.get("patrol_leg_count", 0)) == 0,
		"Real player can temporarily block the guard-requested ordinary-door opening without false passage or patrol progress"
	)

	player.global_transform = original_player_transform
	player.set("velocity", Vector3.ZERO)
	await physics_frame
	await process_frame
	var recovered_cycle: bool = await _wait_for_guard_cycle(guard, 720)
	var recovered_guard_summary: Dictionary = guard.get_debug_summary()
	if not recovered_cycle:
		_print_guard_timeout_diagnostics("blocked-door recovery", guard, door)
	_assert_true(
		recovered_cycle
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN
		and door.is_navigation_passage_open()
		and not door.is_motion_blocked()
		and int(recovered_guard_summary.get("door_use_count", 0)) == 1
		and str(recovered_guard_summary.get("last_error", "")).is_empty(),
		"Guard retries idempotent OPEN after the player leaves and resumes the same patrol without a second logical door use"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _assert_reimport_rebuild() -> void:
	_remove_temp_map()
	var source: String = FileAccess.get_file_as_string(GUARD_NAV_SOURCE_PATH)
	var edited_source: String = source.replace(
		"\"patrol_id\" \"patrol.b\"\n\"origin\" \"-88 -64 0\"",
		"\"patrol_id\" \"patrol.b\"\n\"origin\" \"-104 -64 0\""
	)
	_assert_true(
		not source.is_empty() and edited_source != source,
		"Navigation reimport fixture makes one representative authored patrol-point edit"
	)
	if source.is_empty() or edited_source == source:
		return

	var file := FileAccess.open(TEMP_REIMPORT_MAP_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(edited_source)
		file.flush()
		file.close()
	_assert_true(
		FileAccess.file_exists(TEMP_REIMPORT_MAP_PATH),
		"Navigation reimport fixture writes a disposable edited map source"
	)
	if not FileAccess.file_exists(TEMP_REIMPORT_MAP_PATH):
		return

	var definition := MissionDefinitionResource.new()
	definition.mission_id = &"guard_nav_reimport_probe"
	definition.world_scene = GuardNavWorld
	definition.map_source_path = TEMP_REIMPORT_MAP_PATH
	definition.player_start_selector = &"default"
	definition.mission_content_revision = 1

	var session := WorldSession.new()
	session.name = "GuardNavReimportSession"
	get_root().add_child(session)
	var built: bool = bool(session.build(3707, GuardNavWorld, definition))
	var began: bool = built and bool(session.begin_play())
	var world := session.world as Node3D
	var ready: bool = await _wait_for_navigation_ready(world, 240)
	var guard: VarkGuard = _find_guard(world)
	var door: VarkOrdinaryDoor = (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null
		else null
	)
	var patrol_b: VarkPatrolPoint = _find_patrol_point(world, "patrol.b")
	var navigation_summary: Dictionary = world.call("get_navigation_debug_summary") if world != null else {}
	_assert_true(
		built
		and began
		and ready
		and guard != null
		and patrol_b != null
		and is_equal_approx(patrol_b.global_position.z, -3.25)
		and int(navigation_summary.get("rebuild_serial", 0)) == 1
		and int(navigation_summary.get("polygon_count", 0)) > 0
		and str(navigation_summary.get("map_source_path", "")) == TEMP_REIMPORT_MAP_PATH,
		"Edited authored map rebuilds a fresh navigation mesh and carries the changed patrol point into the real guard world"
	)

	if ready and guard != null:
		var reached_edited_target: bool = await _wait_for_patrol_leg(guard, 480)
		var guard_summary: Dictionary = guard.get_debug_summary()
		if not reached_edited_target:
			_print_guard_timeout_diagnostics(
				"reimport patrol leg",
				guard,
				door
			)
		_assert_true(
			reached_edited_target
			and int(guard_summary.get("patrol_leg_count", 0)) >= 1
			and int(guard_summary.get("door_use_count", 0)) == 1
			and str(guard_summary.get("last_error", "")).is_empty(),
			"Guard patrol and ordinary-door use still work after normal map edit/reimport/navigation rebuild"
		)

	if int(session.state) != WorldSession.State.EMPTY:
		session.teardown()
	session.free()


func _wait_for_navigation_ready(world: Node3D, max_frames: int) -> bool:
	if world == null:
		return false
	for _frame_index: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await physics_frame
		await process_frame
	return bool(world.get("navigation_ready"))


func _wait_for_guard_door_request(guard: VarkGuard, max_frames: int) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if (
			int(summary.get("door_use_count", 0)) >= 1
			and bool(summary.get("door_request_pending", false))
		):
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_guard_approach_window(
	guard: VarkGuard,
	door: VarkOrdinaryDoor,
	min_distance: float,
	max_distance: float,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		var door_distance: float = float(summary.get("door_distance", INF))
		if (
			door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN
			and not door.is_body_in_navigation_passage(guard)
			and str(summary.get("door_traversal_state", "")) == "approaching"
			and door_distance >= min_distance
			and door_distance <= max_distance
		):
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_crossing_contact_reopen(
	guard: VarkGuard,
	door: VarkOrdinaryDoor,
	initial_open_count: int,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if (
			int(summary.get("crossing_block_open_count", 0)) > initial_open_count
			and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
			and door.get_open_fraction() > 0.0
			and door.get_open_fraction() < 1.0
		):
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_guard_clear_door_while_opening(
	guard: VarkGuard,
	door: VarkOrdinaryDoor,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if (
			door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
			and door.get_open_fraction() > 0.0
			and door.get_open_fraction() < 1.0
			and not door.is_body_in_navigation_passage(guard)
			and str(summary.get("door_traversal_state", "")) == "clear"
			and not bool(summary.get("door_request_pending", true))
		):
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_guard_release_while_door_opening(
	guard: VarkGuard,
	door: VarkOrdinaryDoor,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if (
			door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
			and door.get_open_fraction() > 0.0
			and door.get_open_fraction() < 1.0
			and not bool(summary.get("door_route_blocked", true))
			and str(summary.get("door_traversal_state", "")) == "approaching"
			and not bool(summary.get("door_request_pending", true))
		):
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_guard_crossing_without_door_use(
	guard: VarkGuard,
	door: VarkOrdinaryDoor,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if (
			door.is_body_in_navigation_passage(guard)
			and str(summary.get("door_traversal_state", "")) == "crossing"
			and int(summary.get("door_use_count", 0)) == 0
		):
			return true
		if bool(summary.get("door_request_pending", false)):
			return false
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_guard_in_open_doorway(
	guard: VarkGuard,
	door: VarkOrdinaryDoor,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if (
			door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN
			and door.is_body_in_navigation_passage(guard)
			and str(summary.get("door_traversal_state", "")) == "crossing"
		):
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


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


func _wait_for_door_blocked(
	guard: VarkGuard,
	door: VarkOrdinaryDoor,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		if door.is_motion_blocked():
			return true
		var summary: Dictionary = guard.get_debug_summary()
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return door.is_motion_blocked()


func _wait_for_guard_cycle(guard: VarkGuard, max_frames: int) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if int(summary.get("patrol_cycle_count", 0)) >= 1:
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return int(guard.get_debug_summary().get("patrol_cycle_count", 0)) >= 1


func _wait_for_patrol_leg(guard: VarkGuard, max_frames: int) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if int(summary.get("patrol_leg_count", 0)) >= 1:
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return int(guard.get_debug_summary().get("patrol_leg_count", 0)) >= 1


func _find_guard(world: Node3D) -> VarkGuard:
	if world == null:
		return null
	for node: Node in world.find_children("*", "", true, false):
		if node is VarkGuard:
			return node as VarkGuard
	return null


func _find_patrol_point(world: Node3D, patrol_id: String) -> VarkPatrolPoint:
	if world == null:
		return null
	for node: Node in world.find_children("*", "", true, false):
		if not (node is VarkPatrolPoint):
			continue
		var patrol_point := node as VarkPatrolPoint
		if patrol_point.patrol_id == patrol_id:
			return patrol_point
	return null


func _remove_temp_map() -> void:
	if FileAccess.file_exists(TEMP_REIMPORT_MAP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_REIMPORT_MAP_PATH))


func _print_guard_timeout_diagnostics(
	label: String,
	guard: VarkGuard,
	door: VarkOrdinaryDoor
) -> void:
	var guard_summary: Dictionary = guard.get_debug_summary() if guard != null else {}
	var door_summary: Dictionary = {}
	if door != null:
		door_summary = {
			"phase": door.get_semantic_phase(),
			"open_fraction": door.get_open_fraction(),
			"motion_blocked": door.is_motion_blocked(),
			"navigation_passage_open": door.is_navigation_passage_open(),
			"global_position": door.global_position,
			"rotation_y": door.rotation.y,
		}
	print(
		"[NAV TIMEOUT] %s guard=%s door=%s"
		% [label, str(guard_summary), str(door_summary)]
	)


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
		print("ALL NAVIGATION TESTS PASSED")
		return
	print("%d NAVIGATION TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
