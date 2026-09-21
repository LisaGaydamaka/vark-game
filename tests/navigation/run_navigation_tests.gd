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
const VERTICAL_STEALTH_LAB_PATH: String = "res://missions/vertical_stealth_lab/world.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_assert_authoring_schema()
	_assert_guard_nav_doorway_fit()
	await _assert_explicit_link_patrol()
	await _assert_patrol_point_wait()
	await _assert_vertical_stealth_lab()
	await _assert_open_door_crossing_is_passive()
	await _assert_same_side_goal_ignores_open_door()
	await _assert_player_close_during_crossing()
	await _assert_blocked_opening_recovers()
	await _assert_local_traversal_failure_is_nonfatal()
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
		and patrol_class.class_properties.has("patrol_id")
		and patrol_class.class_properties.has("wait_seconds")
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
		and source.contains("\"persistent_id\" \"vark_guard_nav_guard\"")
		and source.contains("\"content_id\" \"guard.nav_probe\""),
		"Guard/Nav Lab keeps the authored exact-fit doorway and stable guard identity"
	)


func _assert_explicit_link_patrol() -> void:
	var fixture: Dictionary = await _launch_guard_nav()
	var application: Node = fixture.get("application")
	var world: Node3D = fixture.get("world")
	var guard: VarkGuard = fixture.get("guard")
	var door: VarkOrdinaryDoor = fixture.get("door")
	var ready: bool = bool(fixture.get("ready", false))
	var navigation_summary: Dictionary = (
		world.call("get_navigation_debug_summary")
		if world != null
		else {}
	)
	var link_summary: Dictionary = navigation_summary.get("door_link", {})
	var nav_errors: PackedStringArray = navigation_summary.get(
		"errors",
		PackedStringArray()
	)
	_assert_true(
		bool(fixture.get("launched", false))
		and ready
		and guard != null
		and door != null
		and int(navigation_summary.get("polygon_count", 0)) > 0
		and bool(link_summary.get("configured", false))
		and bool(link_summary.get("map_bound", false))
		and int(link_summary.get("iteration_id", 0)) > 0
		and (
			link_summary.get("server_start", Vector3.ZERO) as Vector3
		).distance_to(
			link_summary.get("server_end", Vector3.ZERO) as Vector3
		) > 2.0
		and nav_errors.is_empty(),
		"Guard/Nav Lab builds a carved navigation graph bridged by one synchronized ordinary-door link"
	)
	if not ready or guard == null or door == null:
		_cleanup_application(application)
		return

	var entered_link: bool = await _wait_for_door_use(guard, 360)
	var link_wait_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		entered_link
		and int(link_wait_summary.get("door_use_count", 0)) >= 1
		and int(link_wait_summary.get("door_open_request_count", 0)) >= 1
		and bool(link_wait_summary.get("door_use_active", false))
		and str(link_wait_summary.get("last_door_error", "")).is_empty(),
		"A closed required doorway is discovered through link metadata and opens inside the local traversal task"
	)

	var completed_cycle: bool = await _wait_for_guard_cycle(guard, 900)
	var final_summary: Dictionary = guard.get_debug_summary()
	if not completed_cycle:
		_print_guard_timeout_diagnostics("explicit-link patrol cycle", guard, door)
	_assert_true(
		completed_cycle
		and int(final_summary.get("patrol_leg_count", 0)) >= 2
		and int(final_summary.get("patrol_cycle_count", 0)) >= 1
		and int(final_summary.get("door_use_count", 0)) >= 2
		and int(final_summary.get("door_traversal_failure_count", 0)) == 0
		and str(final_summary.get("last_error", "")).is_empty()
		and str(final_summary.get("last_door_error", "")).is_empty(),
		"The guard completes both patrol directions through explicit door traversals and resumes its semantic patrol goal"
	)
	_cleanup_application(application)


func _assert_patrol_point_wait() -> void:
	var fixture: Dictionary = await _launch_guard_nav()
	var application: Node = fixture.get("application")
	var world: Node3D = fixture.get("world")
	var guard: VarkGuard = fixture.get("guard")
	var door: VarkOrdinaryDoor = fixture.get("door")
	var patrol_a: VarkPatrolPoint = _find_patrol_point(world, "patrol.a")
	var patrol_b: VarkPatrolPoint = _find_patrol_point(world, "patrol.b")
	if (
		not bool(fixture.get("ready", false))
		or guard == null
		or door == null
		or patrol_a == null
		or patrol_b == null
	):
		_assert_true(false, "Patrol-wait fixture launches the real authored guard route")
		await _cleanup_application(application)
		return

	patrol_b.wait_seconds = 0.20
	var reconfigured: bool = guard.configure_patrol(
		{patrol_a.patrol_id: patrol_a, patrol_b.patrol_id: patrol_b},
		door
	)
	guard.global_position = patrol_b.global_position
	guard.velocity = Vector3.ZERO
	await physics_frame
	await process_frame
	var waiting: Dictionary = guard.get_debug_summary()
	var wait_snapshot: Dictionary = guard.capture_semantic_state()
	var held_position: Vector3 = guard.global_position
	guard.call("_advance_patrol_wait", 0.05)
	var still_waiting: Dictionary = guard.get_debug_summary()
	guard.call("_advance_patrol_wait", 0.25)
	var resumed: Dictionary = guard.get_debug_summary()
	_assert_true(
		reconfigured
		and bool(waiting.get("patrol_wait_active", false))
		and float(waiting.get("patrol_wait_remaining_seconds", 0.0)) > 0.0
		and bool(wait_snapshot.get("patrol_wait_active", false))
		and float(wait_snapshot.get("patrol_wait_remaining_seconds", 0.0)) > 0.0
		and bool(still_waiting.get("patrol_wait_active", false))
		and guard.global_position.distance_to(held_position) <= 0.001
		and not bool(resumed.get("patrol_wait_active", true))
		and int(resumed.get("target_index", -1)) == 0,
		"Authored patrol-point dwell stops the real guard, persists remaining wait as semantic state, then advances to the next route endpoint"
	)
	await _cleanup_application(application)


func _assert_vertical_stealth_lab() -> void:
	var application: Node = ApplicationScene.instantiate()
	var default_labels: PackedStringArray = application.get("development_launch_labels")
	var default_paths: PackedStringArray = application.get("development_launch_resource_paths")
	var menu_wired: bool = (
		default_labels.has("Vertical Stealth Lab")
		and default_paths.has(VERTICAL_STEALTH_LAB_PATH)
	)
	application.set("development_launch_labels", PackedStringArray(["Vertical Stealth Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([VERTICAL_STEALTH_LAB_PATH]))
	get_root().add_child(application)
	await process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var ready: bool = await _wait_for_navigation_ready(world, 480)
	var guard: VarkGuard = _find_guard(world)
	var patrol_a: VarkPatrolPoint = _find_patrol_point(world, "slice.patrol.a")
	var patrol_b: VarkPatrolPoint = _find_patrol_point(world, "slice.patrol.b")
	var floor_shape: BoxShape3D = null
	var objective: Area3D = null
	if world != null:
		var floor_collision := world.get_node_or_null("Geometry/Floor/CollisionShape3D") as CollisionShape3D
		if floor_collision != null:
			floor_shape = floor_collision.shape as BoxShape3D
		objective = world.get_node_or_null("ObjectiveTrigger") as Area3D
	var surface_colors_distinct: bool = false
	if world != null:
		var stone_band := world.get_node_or_null(
			"Geometry/StoneFloorBand"
		) as MeshInstance3D
		var carpet_band := world.get_node_or_null(
			"Geometry/CarpetFloorBand"
		) as MeshInstance3D
		var tile_band := world.get_node_or_null(
			"Geometry/TileFloorBand"
		) as MeshInstance3D
		if stone_band != null and carpet_band != null and tile_band != null:
			var stone_material := stone_band.material_override as StandardMaterial3D
			var carpet_material := carpet_band.material_override as StandardMaterial3D
			var tile_material := tile_band.material_override as StandardMaterial3D
			surface_colors_distinct = (
				stone_material != null
				and carpet_material != null
				and tile_material != null
				and stone_material.albedo_color != carpet_material.albedo_color
				and stone_material.albedo_color != tile_material.albedo_color
				and carpet_material.albedo_color != tile_material.albedo_color
			)
	var climb_nodes_present: bool = (
		world != null
		and world.get_node_or_null("Geometry/ClimbStep1") != null
		and world.get_node_or_null("Geometry/ClimbStep2") != null
		and world.get_node_or_null("Geometry/ClimbStep3") != null
		and world.get_node_or_null("Geometry/ClimbStep4") != null
		and world.get_node_or_null("Geometry/UpperCatwalk") != null
		and world.get_node_or_null("Geometry/ObjectiveTower") != null
		and world.get_node_or_null("Geometry/EastLedge") != null
	)
	var guard_summary: Dictionary = guard.get_debug_summary() if guard != null else {}
	var authored_waits: Array = guard_summary.get("patrol_wait_seconds", [])
	var gameplay_light_count: int = 0
	if world != null:
		for node: Node in world.find_children("*", "", true, false):
			if node is VarkGameplayLight:
				gameplay_light_count += 1
	_assert_true(
		menu_wired
		and launched
		and ready
		and world != null
		and world.name == &"VerticalStealthLab"
		and floor_shape != null
		and floor_shape.size.x >= 24.0
		and floor_shape.size.z >= 28.0
		and climb_nodes_present
		and objective != null
		and objective.global_position.y >= 4.5
		and gameplay_light_count >= 6
		and surface_colors_distinct
		and guard != null
		and bool(guard_summary.get("configured", false))
		and patrol_a != null
		and patrol_b != null
		and is_equal_approx(patrol_a.wait_seconds, 2.5)
		and is_equal_approx(patrol_b.wait_seconds, 4.0)
		and patrol_a.global_position.distance_to(patrol_b.global_position) >= 20.0
		and authored_waits.size() == 2
		and is_equal_approx(float(authored_waits[0]), 2.5)
		and is_equal_approx(float(authored_waits[1]), 4.0),
		"Vertical Stealth Lab is a larger real stealth fixture with a 24x28 floor, distinct stone/carpet/tile floor colors, climbable multi-level route, elevated objective, six gameplay lights, long guard patrol, and authored endpoint waits"
	)
	await _cleanup_application(application)


func _assert_open_door_crossing_is_passive() -> void:
	var fixture: Dictionary = await _launch_guard_nav()
	var application: Node = fixture.get("application")
	var guard: VarkGuard = fixture.get("guard")
	var door: VarkOrdinaryDoor = fixture.get("door")
	if not bool(fixture.get("ready", false)) or guard == null or door == null:
		_assert_true(false, "Open-door traversal fixture launches the real explicit-link world")
		_cleanup_application(application)
		return

	var original_speed: float = guard.movement_speed
	guard.movement_speed = 0.0
	var opened: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_OPEN,
		"open_fraction": 1.0,
		"motion_blocked": false,
	})
	var before: Dictionary = guard.get_debug_summary()
	var initial_open_requests: int = int(before.get("door_open_request_count", 0))
	var initial_uses: int = int(before.get("door_use_count", 0))
	guard.movement_speed = original_speed

	var reached_leg: bool = await _wait_for_patrol_leg(guard, 600)
	var after: Dictionary = guard.get_debug_summary()
	if not reached_leg:
		_print_guard_timeout_diagnostics("already-open link crossing", guard, door)
	_assert_true(
		opened
		and reached_leg
		and int(after.get("door_use_count", 0)) == initial_uses + 1
		and int(after.get("door_open_request_count", 0)) == initial_open_requests
		and int(after.get("door_close_request_count", 0)) == 0
		and int(after.get("door_maneuver_count", 0)) == 0
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN
		and int(after.get("door_traversal_failure_count", 0)) == 0,
		"An already-open required doorway is crossed through the reserved link corridor without close/reopen or redundant OPEN behavior"
	)
	_cleanup_application(application)


func _assert_same_side_goal_ignores_open_door() -> void:
	var fixture: Dictionary = await _launch_guard_nav()
	var application: Node = fixture.get("application")
	var world: Node3D = fixture.get("world")
	var guard: VarkGuard = fixture.get("guard")
	var door: VarkOrdinaryDoor = fixture.get("door")
	if not bool(fixture.get("ready", false)) or world == null or guard == null or door == null:
		_assert_true(false, "Same-side door-indifference fixture launches the real explicit-link world")
		_cleanup_application(application)
		return

	var opened: bool = door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_OPEN,
		"open_fraction": 1.0,
		"motion_blocked": false,
	})
	var frame: Dictionary = door.get_navigation_doorway_frame()
	var center: Vector3 = frame.get("center", door.global_position)
	var normal: Vector3 = frame.get("normal", Vector3.ZERO)
	var tangent: Vector3 = frame.get("tangent", Vector3.ZERO)
	var clearance: float = door.get_navigation_link_clearance()
	var map: RID = world.get_world_3d().navigation_map
	var link_owner_id: int = door.get_navigation_link().get_instance_id()

	# Discover a nearby path from the real baked graph instead of assuming a
	# particular imported-map axis/layout. Both endpoints must remain on one
	# doorway side and the query metadata must contain no door-link owner.
	var start: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3.ZERO
	var found_same_side_path: bool = false
	var selected_path_size: int = 0
	for side: float in [1.0, -1.0]:
		if found_same_side_path:
			break
		for outward: float in [0.35, 0.65, 1.0]:
			if found_same_side_path:
				break
			for tangent_span: float in [0.45, 0.75, 1.05]:
				var candidate_start: Vector3 = NavigationServer3D.map_get_closest_point(
					map,
					center
					+ normal * side * (clearance + outward)
					- tangent * tangent_span
				)
				var candidate_target: Vector3 = NavigationServer3D.map_get_closest_point(
					map,
					center
					+ normal * side * (clearance + outward)
					+ tangent * tangent_span
				)
				var query := NavigationPathQueryParameters3D.new()
				query.map = map
				query.start_position = candidate_start
				query.target_position = candidate_target
				query.metadata_flags = (
					NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_ALL
				)
				var result := NavigationPathQueryResult3D.new()
				NavigationServer3D.query_path(query, result)
				if (
					result.path.size() >= 2
					and candidate_start.distance_to(candidate_target) >= 0.5
					and not result.path_owner_ids.has(link_owner_id)
				):
					start = candidate_start
					target = candidate_target
					selected_path_size = result.path.size()
					found_same_side_path = true
					break

	guard.global_position = start
	guard.velocity = Vector3.ZERO
	var before: Dictionary = guard.get_debug_summary()
	var initial_uses: int = int(before.get("door_use_count", 0))
	var initial_open_requests: int = int(before.get("door_open_request_count", 0))
	var target_set: bool = (
		guard.set_awareness_navigation_target(&"search", target)
		if found_same_side_path
		else false
	)
	for _frame_index: int in 90:
		await physics_frame
		await process_frame
	var after: Dictionary = guard.get_debug_summary()
	_assert_true(
		opened
		and found_same_side_path
		and selected_path_size >= 2
		and target_set
		and int(after.get("door_use_count", 0)) == initial_uses
		and int(after.get("door_open_request_count", 0)) == initial_open_requests
		and not bool(after.get("door_use_active", true))
		and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN,
		"A nearby same-side search path contains no ordinary-door link and cannot trigger door interaction"
	)
	_cleanup_application(application)

func _assert_player_close_during_crossing() -> void:
	var fixture: Dictionary = await _launch_guard_nav()
	var application: Node = fixture.get("application")
	var player: Node3D = fixture.get("player")
	var guard: VarkGuard = fixture.get("guard")
	var door: VarkOrdinaryDoor = fixture.get("door")
	if (
		not bool(fixture.get("ready", false))
		or player == null
		or guard == null
		or door == null
	):
		_assert_true(false, "Crossing obstruction fixture launches the real guard, player, and explicit door link")
		_cleanup_application(application)
		return

	var crossing: bool = await _wait_for_guard_crossing(guard, door, 480)
	if not crossing:
		_print_guard_timeout_diagnostics("crossing obstruction arrival", guard, door)
		_assert_true(false, "Guard reaches explicit CROSSING before the player-close obstruction proof")
		_cleanup_application(application)
		return

	var original_speed: float = guard.movement_speed
	guard.movement_speed = 0.0
	var before: Dictionary = guard.get_debug_summary()
	var initial_uses: int = int(before.get("door_use_count", 0))
	var initial_open_requests: int = int(before.get("door_open_request_count", 0))
	door.interact(player)
	var contact_reopened: bool = await _wait_for_crossing_reopen(
		guard,
		door,
		initial_uses,
		initial_open_requests,
		180
	)
	var contact_summary: Dictionary = guard.get_debug_summary()
	_assert_true(
		contact_reopened
		and int(contact_summary.get("door_use_count", 0)) == initial_uses
		and int(contact_summary.get("crossing_block_open_count", 0)) >= 1,
		"Player CLOSE may physically contact the crossing guard, but the active link traversal reopens it without creating a second logical use"
	)

	guard.movement_speed = original_speed
	var finished: bool = await _wait_for_door_traversal_finish(
		guard,
		initial_uses,
		360
	)
	var after: Dictionary = guard.get_debug_summary()
	_assert_true(
		finished
		and int(after.get("door_use_count", 0)) == initial_uses
		and int(after.get("door_open_request_count", 0)) > initial_open_requests
		and int(after.get("crossing_block_open_count", 0)) >= 1
		and int(after.get("door_traversal_failure_count", 0)) == 0
		and bool(after.get("configured", false)),
		"A contacted crossing reopens only the active traversal, clears the frame, and leaves normal navigation configured"
	)
	_cleanup_application(application)


func _assert_blocked_opening_recovers() -> void:
	var fixture: Dictionary = await _launch_guard_nav()
	var application: Node = fixture.get("application")
	var player: Node3D = fixture.get("player")
	var guard: VarkGuard = fixture.get("guard")
	var door: VarkOrdinaryDoor = fixture.get("door")
	if (
		not bool(fixture.get("ready", false))
		or player == null
		or guard == null
		or door == null
	):
		_assert_true(false, "Blocked-opening fixture launches the real guard, player, and explicit door link")
		_cleanup_application(application)
		return

	var original_player_transform: Transform3D = player.global_transform
	player.global_position = Vector3(2.25, 0.0, 0.55)
	player.set("velocity", Vector3.ZERO)
	var blocked: bool = await _wait_for_door_blocked(door, 420)
	var blocked_summary: Dictionary = guard.get_debug_summary()
	var logical_use_count: int = int(blocked_summary.get("door_use_count", 0))
	_assert_true(
		blocked
		and logical_use_count == 1
		and int(blocked_summary.get("patrol_leg_count", 0)) == 0
		and bool(blocked_summary.get("door_use_active", false)),
		"A player may physically block the link task's OPEN sweep without manufacturing patrol progress or a second traversal"
	)

	player.global_transform = original_player_transform
	player.set("velocity", Vector3.ZERO)
	var reached_leg: bool = await _wait_for_patrol_leg(guard, 600)
	var recovered: Dictionary = guard.get_debug_summary()
	if not reached_leg:
		_print_guard_timeout_diagnostics("blocked explicit-link recovery", guard, door)
	_assert_true(
		reached_leg
		and int(recovered.get("door_use_count", 0)) == logical_use_count
		and int(recovered.get("door_open_request_count", 0)) >= 2
		and int(recovered.get("door_traversal_failure_count", 0)) == 0
		and bool(recovered.get("configured", false))
		and str(recovered.get("last_error", "")).is_empty(),
		"After the blocker leaves, idempotent OPEN retry finishes the same link traversal and resumes patrol"
	)
	_cleanup_application(application)


func _assert_local_traversal_failure_is_nonfatal() -> void:
	var fixture: Dictionary = await _launch_guard_nav()
	var application: Node = fixture.get("application")
	var guard: VarkGuard = fixture.get("guard")
	var door: VarkOrdinaryDoor = fixture.get("door")
	if not bool(fixture.get("ready", false)) or guard == null or door == null:
		_assert_true(false, "Nonfatal door-failure fixture launches the real explicit-link world")
		_cleanup_application(application)
		return

	var original_speed: float = guard.movement_speed
	guard.movement_speed = 0.0
	var before: Dictionary = guard.get_debug_summary()
	var before_failures: int = int(before.get("door_traversal_failure_count", 0))
	var before_target_index: int = int(before.get("target_index", -1))
	guard.call("_on_navigation_link_reached", {
		"owner": door.get_navigation_link(),
	})
	await process_frame
	var after: Dictionary = guard.get_debug_summary()
	_assert_true(
		int(after.get("door_traversal_failure_count", 0)) == before_failures + 1
		and not str(after.get("last_door_error", "")).is_empty()
		and bool(after.get("configured", false))
		and bool(after.get("navigation_active", false))
		and int(after.get("target_index", -2)) == before_target_index
		and str(after.get("last_error", "")).is_empty(),
		"A malformed local door traversal records diagnostics but never disables the guard or discards its semantic destination"
	)
	guard.movement_speed = original_speed
	_cleanup_application(application)


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
	var ready: bool = await _wait_for_navigation_ready(world, 360)
	var guard: VarkGuard = _find_guard(world)
	var patrol_b: VarkPatrolPoint = _find_patrol_point(world, "patrol.b")
	var navigation_summary: Dictionary = (
		world.call("get_navigation_debug_summary")
		if world != null
		else {}
	)
	var link_summary: Dictionary = navigation_summary.get("door_link", {})
	_assert_true(
		built
		and began
		and ready
		and guard != null
		and patrol_b != null
		and is_equal_approx(patrol_b.global_position.z, -3.25)
		and int(navigation_summary.get("rebuild_serial", 0)) == 1
		and int(navigation_summary.get("polygon_count", 0)) > 0
		and bool(link_summary.get("configured", false))
		and bool(link_summary.get("map_bound", false))
		and str(navigation_summary.get("map_source_path", "")) == TEMP_REIMPORT_MAP_PATH,
		"Edited authored map rebuilds both the fresh navigation mesh and its ordinary-door link"
	)

	if ready and guard != null:
		var reached_edited_target: bool = await _wait_for_patrol_leg(guard, 600)
		var guard_summary: Dictionary = guard.get_debug_summary()
		_assert_true(
			reached_edited_target
			and int(guard_summary.get("patrol_leg_count", 0)) >= 1
			and int(guard_summary.get("door_use_count", 0)) == 1
			and int(guard_summary.get("door_traversal_failure_count", 0)) == 0
			and str(guard_summary.get("last_error", "")).is_empty(),
			"Guard patrol and explicit ordinary-door traversal survive normal map edit/reimport/navigation rebuild"
		)

	if int(session.state) != WorldSession.State.EMPTY:
		session.teardown()
	session.free()


func _launch_guard_nav() -> Dictionary:
	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Guard/Nav Lab"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([GUARD_NAV_DEFINITION_PATH])
	)
	get_root().add_child(application)
	await process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var ready: bool = await _wait_for_navigation_ready(world, 360)
	return {
		"application": application,
		"launched": launched,
		"world": world,
		"player": application.get("current_player") as Node3D,
		"guard": _find_guard(world),
		"door": (
			world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
			if world != null
			else null
		),
		"ready": ready,
	}


func _cleanup_application(application: Node) -> void:
	if application == null:
		return
	if application.get("current_world") != null:
		application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _wait_for_navigation_ready(world: Node3D, max_frames: int) -> bool:
	if world == null:
		return false
	for _frame_index: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await physics_frame
		await process_frame
	return bool(world.get("navigation_ready"))


func _wait_for_door_use(guard: VarkGuard, max_frames: int) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if int(summary.get("door_use_count", 0)) >= 1:
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_guard_crossing(
	guard: VarkGuard,
	door: VarkOrdinaryDoor,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if (
			str(summary.get("door_traversal_state", "")) == "crossing"
			and bool(summary.get("door_use_active", false))
			and door.is_body_in_navigation_passage(guard)
		):
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_crossing_reopen(
	guard: VarkGuard,
	door: VarkOrdinaryDoor,
	expected_use_count: int,
	initial_open_requests: int,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if (
			int(summary.get("door_use_count", 0)) == expected_use_count
			and int(summary.get("door_open_request_count", 0)) > initial_open_requests
			and int(summary.get("crossing_block_open_count", 0)) >= 1
			and door.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPENING
		):
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_door_traversal_finish(
	guard: VarkGuard,
	expected_use_count: int,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if (
			int(summary.get("door_use_count", 0)) == expected_use_count
			and not bool(summary.get("door_use_active", true))
			and (
				str(summary.get("door_traversal_state", "")) == "clear"
				or str(summary.get("door_traversal_state", "")) == "idle"
			)
		):
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_door_blocked(
	door: VarkOrdinaryDoor,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		if door.is_motion_blocked():
			return true
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


func _wait_for_position(
	guard: VarkGuard,
	target: Vector3,
	tolerance: float,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var horizontal := Vector3(
			target.x - guard.global_position.x,
			0.0,
			target.z - guard.global_position.z
		)
		if horizontal.length() <= tolerance:
			return true
		var summary: Dictionary = guard.get_debug_summary()
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await physics_frame
		await process_frame
	return false


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
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(TEMP_REIMPORT_MAP_PATH)
		)


func _print_guard_timeout_diagnostics(
	label: String,
	guard: VarkGuard,
	door: VarkOrdinaryDoor
) -> void:
	var guard_summary: Dictionary = (
		guard.get_debug_summary()
		if guard != null
		else {}
	)
	var door_summary: Dictionary = {}
	if door != null:
		door_summary = {
			"phase": door.get_semantic_phase(),
			"open_fraction": door.get_open_fraction(),
			"motion_blocked": door.is_motion_blocked(),
			"link": door.get_navigation_link_summary(),
			"global_position": door.global_position,
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
