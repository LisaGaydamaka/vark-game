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
	await _assert_application_patrol_and_door()
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
		and guard_class.class_properties.has("guard_id")
		and guard_class.class_properties.has("patrol_a_id")
		and guard_class.class_properties.has("patrol_b_id")
		and guard_class.class_properties.has("door_id")
		and patrol_class.class_properties.has("patrol_id")
		and exported_fgd.contains("vark_guard")
		and exported_fgd.contains("vark_patrol_point"),
		"TrenchBroom exports the real primitive guard and patrol-point authoring entities"
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
		and nav_errors.is_empty(),
		"Guard/Nav Lab launches through the production mission/session path and bakes navigation from imported FuncGodot geometry"
	)
	if not ready or guard == null or door == null:
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

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

	var completed_cycle: bool = await _wait_for_guard_cycle(guard, 720)
	var final_guard_summary: Dictionary = guard.get_debug_summary()
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
