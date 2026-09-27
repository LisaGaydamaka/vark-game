extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const WorldSession = preload("res://application/world_session.gd")
const Definition: Resource = preload(
	"res://missions/representative_stealth_ledge_city/mission.tres"
)

const ORIGINAL_LABEL := "Representative Stealth"
const ORIGINAL_PATH := "res://missions/representative_stealth/mission.tres"
const LEDGE_LABEL := "Representative Stealth — Ledge City"
const LEDGE_PATH := "res://missions/representative_stealth_ledge_city/mission.tres"
const MAP_PATH := "res://missions/representative_stealth_ledge_city/mission.map"
const HANGING_LANTERN_PATH := "res://assets/light_assets/HangingLantern.tscn"
const STREET_LAMP_PATH := "res://assets/light_assets/StreetLamp.tscn"
const ALLOWED_SURFACE_TEXTURES := [
	"vark_surfaces/stone",
	"vark_surfaces/tile",
	"vark_surfaces/carpet",
]


func run(tree: SceneTree, assert_true: Callable) -> void:
	var application: Node = ApplicationScene.instantiate()
	var labels: PackedStringArray = application.get("development_launch_labels")
	var paths: PackedStringArray = application.get("development_launch_resource_paths")
	var original_index: int = labels.find(ORIGINAL_LABEL)
	var ledge_index: int = labels.find(LEDGE_LABEL)
	assert_true.call(
		original_index >= 0
		and original_index < paths.size()
		and paths[original_index] == ORIGINAL_PATH
		and ledge_index >= 0
		and ledge_index < paths.size()
		and paths[ledge_index] == LEDGE_PATH,
		"8.4 keeps baseline Representative Stealth separate and exposes rebuilt Ledge City"
	)
	application.free()

	var load_errors: PackedStringArray = Definition.call("get_load_errors")
	assert_true.call(
		load_errors.is_empty()
		and Definition.get("mission_id")
			== &"phase8_representative_stealth_ledge_city"
		and str(Definition.get("map_source_path")) == MAP_PATH
		and int(Definition.get("mission_content_revision")) == 5,
		"8.4 Ledge City revision 5 owns a distinct save identity after the spatial rebuild"
	)

	var source: String = FileAccess.get_file_as_string(MAP_PATH)
	var face_audit: Dictionary = _audit_source_face_materials(source)
	var brush_bounds: Array[AABB] = _worldspawn_brush_bounds(source)
	var source_clearances_valid: bool = not _any_positive_overlap(
		brush_bounds,
		AABB(Vector3(-28, -438, 2), Vector3(56, 876, 70))
	)
	for aperture: AABB in [
		AABB(Vector3(-120, 278, 2), Vector3(12, 44, 64)),
		AABB(Vector3(108, 278, 2), Vector3(12, 44, 64)),
		AABB(Vector3(-120, 28, 2), Vector3(12, 44, 64)),
		AABB(Vector3(108, 28, 2), Vector3(12, 44, 64)),
		AABB(Vector3(108, -292, 2), Vector3(12, 44, 64)),
		AABB(Vector3(-120, -292, 2), Vector3(12, 44, 64)),
		AABB(Vector3(-120, -292, 186), Vector3(12, 44, 56)),
	]:
		if _any_positive_overlap(brush_bounds, aperture):
			source_clearances_valid = false
			break
	assert_true.call(
		bool(face_audit.get("valid", false))
		and int(face_audit.get("face_count", 0)) >= 1800
		and source_clearances_valid
		and source.count("// building_floor:") == 6
		and source.count("// interior_stair:") == 77
		and source.count("// sloped_roof:") == 12
		and source.count("// timber_tie:") == 2
		and source.count("// balcony:") >= 35
		and not source.contains("zebra/zebra16x16")
		and not source.contains("WallLamp.tscn")
		and not source.contains("// platform:")
		and not source.contains("// west_route:")
		and not source.contains("// east_route:"),
		"8.4 source uses only solid stone/tile/carpet faces, real interiors/architecture, and audited street/opening clearances"
	)

	var session: Node = WorldSession.new()
	session.name = "Phase8LedgeCityWorldSession"
	tree.get_root().add_child(session)
	var built: bool = bool(session.call(
		"build",
		84201,
		Definition.get("world_scene"),
		Definition
	))
	var world := session.get("world") as Node
	assert_true.call(
		built
		and world != null
		and world.has_method("get_representative_debug_summary"),
		"8.4 rebuilt Ledge City builds through the production mission path"
	)
	if not built or world == null:
		session.call("teardown")
		session.queue_free()
		await tree.process_frame
		return

	var nodes: Array[Node] = [world]
	nodes.append_array(world.find_children("*", "", true, false))
	var openings: Array[Node] = []
	var pickups: Array[Node] = []
	var containers: Array[Node] = []
	var guards: Array[Node] = []
	var patrol_points: Array[Node] = []
	var props: Array[Node] = []
	var lights: Array[Node] = []
	var switches: Array[Node] = []
	var starts: Array[Node] = []
	var exits: Array[Node] = []
	var markers: Array[Node] = []
	var surfaces: Array[Node] = []
	for node: Node in nodes:
		if node.has_method("get_access_summary") and node.has_method(
			"configure_navigation_traversal"
		):
			openings.append(node)
		if node.has_method("get_collection_payload"):
			pickups.append(node)
		if node.is_in_group(&"vark_container"):
			containers.append(node)
		if node.is_in_group(&"vark_guard"):
			guards.append(node)
		if node.is_in_group(&"vark_patrol_point"):
			patrol_points.append(node)
		if node is VarkOrdinaryProp:
			props.append(node)
		if node.is_in_group(&"vark_gameplay_light"):
			lights.append(node)
		if node.is_in_group(&"vark_light_switch"):
			switches.append(node)
		if node.is_in_group(&"vark_player_start"):
			starts.append(node)
		if node.is_in_group(&"vark_mission_exit"):
			exits.append(node)
		if node.is_in_group(&"vark_semantic_marker"):
			markers.append(node)
		if node.is_in_group(&"vark_footstep_surface"):
			surfaces.append(node)

	var worldspawn := world.get_node_or_null(
		"FuncGodotMap/entity_0_worldspawn"
	) as StaticBody3D
	assert_true.call(
		starts.size() == 1
		and exits.size() == 1
		and guards.size() == 1
		and patrol_points.size() == 2
		and containers.size() == 1
		and props.size() == 5
		and lights.size() == 23
		and switches.size() == 1
		and openings.size() == 7
		and pickups.size() == 4
		and markers.size() >= 33
		and surfaces.size() == 22
		and _count_direct_collision_shapes(worldspawn) >= 280,
		"8.4 compact city keeps representative gameplay roles and adds enterable multi-floor architecture"
	)

	var surface_variants: Dictionary = {}
	for surface: Node in surfaces:
		var variant: String = str(surface.get("surface_variant"))
		surface_variants[variant] = int(surface_variants.get(variant, 0)) + 1
	assert_true.call(
		int(surface_variants.get("stone", 0)) > 0
		and int(surface_variants.get("tile", 0)) > 0
		and int(surface_variants.get("carpet", 0)) > 0,
		"8.4 floor regions retain stone/tile/carpet footstep semantics matching visible materials"
	)

	var expected_openings: Dictionary = {
		"door.mercer.front": Vector3(-112, 300, 0),
		"door.watchmaker.front": Vector3(112, 300, 0),
		"door.office.front": Vector3(-112, 50, 0),
		"door.tenement.front": Vector3(112, 50, 0),
		"door.foundry.front": Vector3(112, -270, 0),
		"door.east_locked": Vector3(-112, -270, 0),
		"opening.window_west": Vector3(-112, -270, 184),
	}
	var opening_positions_valid: bool = true
	for door_id: String in expected_openings:
		var opening := _find_by_property(openings, "door_id", door_id) as Node3D
		if (
			opening == null
			or opening.global_position.distance_to(
				_map_origin_to_world(expected_openings[door_id] as Vector3)
			) > 0.02
		):
			opening_positions_valid = false
			break
	var window: Node = _find_by_property(
		openings,
		"door_id",
		"opening.window_west"
	)
	var locked_door: Node = _find_by_property(
		openings,
		"door_id",
		"door.east_locked"
	)
	var access: Dictionary = (
		locked_door.call("get_access_summary")
		if locked_door != null else {}
	)
	assert_true.call(
		opening_positions_valid
		and window != null
		and str(window.get("opening_variant")) == "window"
		and locked_door != null
		and bool(access.get("locked", false))
		and str(access.get("required_key_id", "")) == "key.service",
		"8.4 every authored door/window is seated on its rebuilt opening and the Archive keeps keyed plus high-window routes"
	)

	var pickup_roles: Dictionary = {}
	for pickup: Node in pickups:
		var payload: Dictionary = pickup.call("get_collection_payload")
		pickup_roles[str(payload.get("content_id", ""))] = payload.get(
			"kind",
			&""
		)
	assert_true.call(
		pickup_roles.get("key.service", &"") == &"key"
		and pickup_roles.get("loot.rep.silver", &"") == &"loot"
		and pickup_roles.get("loot.rep.gold", &"") == &"loot"
		and pickup_roles.get("mission.dev_stealth.ledger", &"")
			== &"mission_item",
		"8.4 rebuilt interiors retain key/loot/objective content"
	)

	var key_cache := containers[0] as Node3D if containers.size() == 1 else null
	var key_pickup := _find_by_property(pickups, "content_id", "key.service") as Node3D
	var silver_pickup := _find_by_property(
		pickups,
		"content_id",
		"loot.rep.silver"
	) as Node3D
	var gold_pickup := _find_by_property(
		pickups,
		"content_id",
		"loot.rep.gold"
	) as Node3D
	var ledger_pickup := _find_by_property(
		pickups,
		"content_id",
		"mission.dev_stealth.ledger"
	) as Node3D
	assert_true.call(
		key_cache != null
		and key_cache.global_position.distance_to(
			_map_origin_to_world(Vector3(260, 310, 96))
		) <= 0.02
		and key_pickup != null
		and key_pickup.global_position.distance_to(
			_map_origin_to_world(Vector3(268, 310, 106))
		) <= 0.02
		and silver_pickup != null
		and silver_pickup.global_position.distance_to(
			_map_origin_to_world(Vector3(292, 310, 106))
		) <= 0.02
		and gold_pickup != null
		and gold_pickup.global_position.distance_to(
			_map_origin_to_world(Vector3(-265, -312, 184))
		) <= 0.02
		and ledger_pickup != null
		and ledger_pickup.global_position.distance_to(
			_map_origin_to_world(Vector3(-250, -225, 184.2))
		) <= 0.02,
		"8.4 chest and free pickups are seated on or inside their intended rebuilt floor/container geometry"
	)

	var required_light_ids := PackedStringArray([
		"light.rep.south",
		"light.rep.market",
		"light.rep.cross",
		"light.rep.mid",
		"light.rep.archive",
		"light.rep.north",
		"light.rep.watch_inside",
		"light.rep.archive_inside",
		"light.rep.mercer_inside",
		"light.rep.office_inside",
		"light.rep.tenement_inside",
		"light.rep.foundry_inside",
		"light.rep.watch_key_room",
		"light.rep.archive_upper",
		"light.rep.rear_w_south",
		"light.rep.rear_w_north",
		"light.rep.rear_e_south",
		"light.rep.rear_e_north",
		"light.rep.mercer.upper",
		"light.rep.office.upper",
		"light.rep.tenement.upper",
		"light.rep.foundry.upper",
		"light.rep.archive.mid",
	])
	var expected_hanging_origins: Dictionary = {
		"light.rep.mercer_inside": Vector3(-210, 285, 88),
		"light.rep.watch_inside": Vector3(210, 285, 88),
		"light.rep.office_inside": Vector3(-210, 70, 88),
		"light.rep.tenement_inside": Vector3(210, 70, 88),
		"light.rep.archive_inside": Vector3(-210, -285, 88),
		"light.rep.foundry_inside": Vector3(210, -285, 88),
		"light.rep.watch_key_room": Vector3(250, 300, 176),
		"light.rep.archive_upper": Vector3(-245, -235, 264),
		"light.rep.mercer.upper": Vector3(-250, 230, 176),
		"light.rep.office.upper": Vector3(-250, 80, 176),
		"light.rep.tenement.upper": Vector3(250, 80, 176),
		"light.rep.foundry.upper": Vector3(250, -235, 176),
		"light.rep.archive.mid": Vector3(-250, -310, 176),
	}
	var hanging_count: int = 0
	var street_count: int = 0
	var light_ids_valid: bool = true
	for required_id: String in required_light_ids:
		var light: Node = _find_by_property(
			lights,
			"gameplay_light_id",
			required_id
		)
		if light == null:
			light_ids_valid = false
			break
		var fixture_path: String = str(light.get("fixture_asset_path"))
		if fixture_path == HANGING_LANTERN_PATH:
			hanging_count += 1
			var expected_origin: Vector3 = expected_hanging_origins.get(
				required_id,
				Vector3(INF, INF, INF)
			)
			var light_node := light as Node3D
			if (
				light_node == null
				or light_node.global_position.distance_to(
					_map_origin_to_world(expected_origin)
				) > 0.02
			):
				light_ids_valid = false
				break
		elif fixture_path == STREET_LAMP_PATH:
			street_count += 1
		else:
			light_ids_valid = false
			break
	var interior_light := _find_by_property(
		lights,
		"gameplay_light_id",
		"light.rep.mercer_inside"
	) as VarkGameplayLight
	var lantern_asset := (
		interior_light.get_node_or_null(
			"FixtureAnchor/HangingLanternAsset"
		) as VarkLightFixtureAsset
		if interior_light != null else null
	)
	var lantern_summary: Dictionary = (
		lantern_asset.get_contract_summary()
		if lantern_asset != null else {}
	)
	var emitter_local: Vector3 = lantern_summary.get(
		"emitter_local_position",
		Vector3.ZERO
	)
	assert_true.call(
		light_ids_valid
		and hanging_count == 13
		and street_count == 10
		and lantern_asset != null
		and lantern_asset.validate_contract()
		and str(lantern_summary.get("asset_id", "")) == "hanging_lantern"
		and absf(emitter_local.x) <= 0.001
		and absf(emitter_local.z) <= 0.001
		and emitter_local.y < -0.30
		and emitter_local.y > -0.60
		and int(lantern_summary.get("collision_shape_count", 0)) >= 4
		and int(lantern_summary.get("exposure_occluder_shape_count", 0)) == 1
		and interior_light.get_emitter() is OmniLight3D
		and is_equal_approx(float(interior_light.get("omni_range")), 3.4),
		"8.4 rooms use short ceiling-hung omni lanterns while streets keep freestanding omni lamps"
	)

	var nav_ready: bool = await _wait_for_navigation(world, tree)
	var authored_patrol_path: bool = (
		_has_navigation_path_between_patrol_points(
			world,
			patrol_points
		)
		if nav_ready else false
	)
	assert_true.call(
		nav_ready
		and authored_patrol_path
		and (world.get("navigation_errors") as PackedStringArray).is_empty(),
		"8.4 rebuilt boulevard stays navigation-ready between both patrol endpoints"
	)

	var guard := guards[0] as VarkGuard if guards.size() == 1 else null
	var awareness: Node = (
		guard.get_node_or_null("Awareness")
		if guard != null else null
	)
	if awareness != null:
		awareness.call("reset_reaction")
		awareness.set_physics_process(false)
	if guard != null:
		guard.call("clear_awareness_navigation_target")
	var patrol_lookup: Dictionary = {}
	for patrol: Node in patrol_points:
		patrol.set("wait_seconds", 0.05)
		patrol_lookup[patrol.get("patrol_id")] = patrol
	if guard != null:
		guard.movement_speed = 6.0
	var patrol_reconfigured: bool = (
		guard.configure_patrol(patrol_lookup, locked_door)
		if guard != null and locked_door != null else false
	)
	var began_playing: bool = bool(session.call("begin_play"))
	var live_patrol_leg: bool = (
		await _wait_for_guard_patrol_leg(guard, tree, 600)
		if began_playing and patrol_reconfigured else false
	)
	var guard_summary: Dictionary = (
		guard.get_debug_summary()
		if guard != null else {}
	)
	if not live_patrol_leg and guard != null:
		print(
			"8.4 compact-city patrol diagnostics: ",
			{
				"guard_position": guard.global_position,
				"summary": guard_summary,
				"patrol_points": patrol_lookup.keys(),
			}
		)
	assert_true.call(
		began_playing
		and live_patrol_leg
		and str(guard_summary.get("last_error", "")).is_empty(),
		(
			"8.4 live guard traverses the audited boulevard without a hidden brush obstruction; summary=%s"
			% str(guard_summary)
		)
	)

	var summary: Dictionary = session.call("get_mission_run_summary")
	assert_true.call(
		int(summary.get("loot_available_count", -1)) == 2
		and int(summary.get("loot_available_value", -1)) == 125,
		"8.4 rebuilt mission keeps authored mission-start loot availability"
	)

	session.call("teardown")
	session.queue_free()
	await tree.process_frame

	await _test_application_quickload_returns_ledge_city_to_live_play(
		tree,
		assert_true
	)


func _audit_source_face_materials(source: String) -> Dictionary:
	var face_count: int = 0
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if not line.begins_with("("):
			continue
		face_count += 1
		var allowed: bool = false
		for texture: String in ALLOWED_SURFACE_TEXTURES:
			if line.contains(") " + texture + " ["):
				allowed = true
				break
		if not allowed:
			return {
				"valid": false,
				"face_count": face_count,
				"line": line,
			}
	return {
		"valid": face_count > 0,
		"face_count": face_count,
	}


func _worldspawn_brush_bounds(source: String) -> Array[AABB]:
	var result: Array[AABB] = []
	var world_start: int = source.find("\"classname\" \"worldspawn\"")
	var cutoff: int = source.find("\"classname\" \"vark_player_start\"")
	var world_source: String = source.substr(
		maxi(world_start, 0),
		(cutoff if cutoff >= 0 else source.length()) - maxi(world_start, 0)
	)
	var comment_pattern := RegEx.new()
	comment_pattern.compile("(?m)^// ([^\\n]+)\\n\\{")
	for comment_match: RegExMatch in comment_pattern.search_all(world_source):
		var comment: String = comment_match.get_string(1)
		var bounds: AABB = _brush_bounds_after_comment(world_source, comment)
		if bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0:
			result.append(bounds)
	return result


func _brush_bounds_after_comment(source: String, comment: String) -> AABB:
	var marker: String = "// " + comment
	var start: int = source.find(marker)
	if start < 0:
		return AABB()
	var brush_start: int = source.find("{", start + marker.length())
	var brush_end: int = source.find("\n}", brush_start)
	if brush_start < 0 or brush_end < 0:
		return AABB()
	var brush: String = source.substr(
		brush_start,
		brush_end - brush_start
	)
	var coordinate_pattern := RegEx.new()
	coordinate_pattern.compile(
		"\\(\\s*(-?[0-9.]+)\\s+(-?[0-9.]+)\\s+(-?[0-9.]+)\\s*\\)"
	)
	var found: bool = false
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for match_result: RegExMatch in coordinate_pattern.search_all(brush):
		var point := Vector3(
			float(match_result.get_string(1)),
			float(match_result.get_string(2)),
			float(match_result.get_string(3))
		)
		minimum = minimum.min(point)
		maximum = maximum.max(point)
		found = true
	if not found:
		return AABB()
	# The generated Valve-plane support points deliberately extend one map
	# unit past each positive axis plane so the three plane points are
	# non-collinear. They are not brush vertices. Remove that construction
	# unit before using the source-only AABB for clearance assertions.
	var corrected_maximum: Vector3 = maximum - Vector3.ONE
	return AABB(minimum, corrected_maximum - minimum)


func _any_positive_overlap(bounds: Array[AABB], query: AABB) -> bool:
	var query_end: Vector3 = query.position + query.size
	for candidate: AABB in bounds:
		var candidate_end: Vector3 = candidate.position + candidate.size
		var overlap_size := Vector3(
			minf(candidate_end.x, query_end.x)
				- maxf(candidate.position.x, query.position.x),
			minf(candidate_end.y, query_end.y)
				- maxf(candidate.position.y, query.position.y),
			minf(candidate_end.z, query_end.z)
				- maxf(candidate.position.z, query.position.z)
		)
		if (
			overlap_size.x > 0.001
			and overlap_size.y > 0.001
			and overlap_size.z > 0.001
		):
			return true
	return false


func _test_application_quickload_returns_ledge_city_to_live_play(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	const TEST_SAVE_DIRECTORY := "user://vark_tests/phase8_ledge_city_quickload"
	_cleanup_quickload_storage(TEST_SAVE_DIRECTORY)

	var application: Node = ApplicationScene.instantiate()
	tree.get_root().add_child(application)
	await tree.process_frame

	var labels: PackedStringArray = application.get("development_launch_labels")
	var target_index: int = labels.find(LEDGE_LABEL)
	var launched: bool = (
		bool(application.call("launch_development_target", target_index))
		if target_index >= 0 else false
	)
	var world := application.get("current_world") as Node
	var nav_ready: bool = (
		await _wait_for_navigation(world, tree)
		if launched and world != null else false
	)
	assert_true.call(
		launched
		and nav_ready
		and int(application.call("get_current_session_state"))
			== WorldSession.State.PLAYING,
		"8.4 Ledge City application quickload regression starts from a real PLAYING development-launch session"
	)
	if not launched or not nav_ready:
		application.queue_free()
		await tree.process_frame
		_cleanup_quickload_storage(TEST_SAVE_DIRECTORY)
		return

	var save_coordinator := application.get_node("SaveCoordinator") as Node
	save_coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)
	var generation: int = int(application.call("request_quicksave"))
	var snapshot: Dictionary = await _wait_for_save_commit(
		tree,
		save_coordinator,
		generation,
		180
	)
	assert_true.call(
		not snapshot.is_empty(),
		"8.4 Ledge City commits a real quicksave before exercising F9"
	)
	if snapshot.is_empty():
		application.queue_free()
		await tree.process_frame
		_cleanup_quickload_storage(TEST_SAVE_DIRECTORY)
		return

	var saved_position: Vector3 = (
		application.get("current_player") as Node3D
	).global_position
	Input.action_press("move_right")
	await _wait_physics_frames(tree, 20)
	Input.action_release("move_right")
	var moved_position: Vector3 = (
		application.get("current_player") as Node3D
	).global_position
	assert_true.call(
		moved_position.distance_to(saved_position) > 0.10,
		"8.4 Ledge City player can move away from the saved pose before F9"
	)

	var old_session_id: int = int(application.call("get_current_session_id"))
	var boundary := application.get_node("InputBoundary") as Node
	var load_event := InputEventKey.new()
	load_event.pressed = true
	load_event.keycode = KEY_F9
	boundary.call("route_input_event", load_event)

	var replaced: bool = false
	for _index: int in 240:
		await tree.process_frame
		if int(application.call("get_current_session_id")) != old_session_id:
			replaced = true
			break

	var restored_session := application.get("current_session") as Node
	var restored_world := application.get("current_world") as Node
	var restored_player := application.get("current_player") as Node3D
	var restored_time_before: float = float(
		application.call("get_gameplay_time_seconds")
	)
	var restored_position_before: Vector3 = (
		restored_player.global_position
		if restored_player != null else Vector3.ZERO
	)

	Input.action_press("move_right")
	await _wait_physics_frames(tree, 20)
	Input.action_release("move_right")

	var restored_time_after: float = float(
		application.call("get_gameplay_time_seconds")
	)
	var restored_position_after: Vector3 = (
		restored_player.global_position
		if restored_player != null and is_instance_valid(restored_player)
		else restored_position_before
	)
	var live_after_load: bool = (
		replaced
		and restored_session != null
		and restored_world != null
		and restored_player != null
		and restored_world.can_process()
		and restored_player.can_process()
		and int(application.call("get_current_session_state"))
			== WorldSession.State.PLAYING
		and int(restored_session.process_mode) == Node.PROCESS_MODE_INHERIT
		and bool(boundary.get("gameplay_enabled"))
		and bool(boundary.get("look_enabled"))
		and boundary.get("current_player") == restored_player
		and restored_player.get("gameplay_input_boundary") == boundary
		and restored_time_after > restored_time_before
		and restored_position_after.distance_to(restored_position_before) > 0.10
	)
	if not live_after_load:
		print(
			"8.4 F9 freeze diagnostics: ",
			{
				"replaced": replaced,
				"session_state": application.call("get_current_session_state"),
				"session_process_mode": (
					restored_session.process_mode
					if restored_session != null else -1
				),
				"world_can_process": (
					restored_world.can_process()
					if restored_world != null else false
				),
				"player_can_process": (
					restored_player.can_process()
					if restored_player != null else false
				),
				"gameplay_enabled": boundary.get("gameplay_enabled"),
				"look_enabled": boundary.get("look_enabled"),
				"boundary_player_matches": (
					boundary.get("current_player") == restored_player
				),
				"player_boundary_matches": (
					restored_player != null
					and restored_player.get("gameplay_input_boundary") == boundary
				),
				"time_before": restored_time_before,
				"time_after": restored_time_after,
				"movement_distance": restored_position_after.distance_to(
					restored_position_before
				),
			}
		)
	assert_true.call(
		live_after_load,
		"8.4 F9 restores Ledge City into a genuinely live simulation: session/world/player processing, gameplay clock and fresh movement all resume"
	)

	application.queue_free()
	await tree.process_frame
	Input.action_release("move_left")
	Input.action_release("move_right")
	_cleanup_quickload_storage(TEST_SAVE_DIRECTORY)


func _wait_for_save_commit(
	tree: SceneTree,
	save_coordinator: Node,
	generation: int,
	max_frames: int
) -> Dictionary:
	if generation <= 0:
		return {}
	for _index: int in max_frames:
		var status: Dictionary = save_coordinator.call(
			"get_request_status",
			generation
		)
		if status.get("status", &"") == &"committed":
			return save_coordinator.call("get_request_snapshot", generation)
		if status.get("status", &"") in [
			&"failed",
			&"cancelled",
			&"superseded",
		]:
			return {}
		await tree.physics_frame
		await tree.process_frame
	return {}


func _wait_physics_frames(tree: SceneTree, count: int) -> void:
	for _index: int in count:
		await tree.physics_frame
		await tree.process_frame


func _cleanup_quickload_storage(directory: String) -> void:
	var final_path: String = directory + "/quicksave.varksave"
	for path: String in [
		final_path,
		final_path + ".new",
		final_path + ".bak",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_dir: String = ProjectSettings.globalize_path(directory)
	if DirAccess.dir_exists_absolute(absolute_dir):
		DirAccess.remove_absolute(absolute_dir)


func _has_navigation_path_between_patrol_points(
	world: Node3D,
	patrol_points: Array[Node]
) -> bool:
	if world == null or patrol_points.size() != 2:
		return false
	var point_by_id: Dictionary = {}
	for patrol: Node in patrol_points:
		point_by_id[str(patrol.get("patrol_id"))] = patrol
	var patrol_a := point_by_id.get("patrol.rep.a") as Node3D
	var patrol_b := point_by_id.get("patrol.rep.b") as Node3D
	if patrol_a == null or patrol_b == null:
		return false
	var map: RID = world.get_world_3d().navigation_map
	var start: Vector3 = NavigationServer3D.map_get_closest_point(
		map,
		patrol_a.global_position
	)
	var target: Vector3 = NavigationServer3D.map_get_closest_point(
		map,
		patrol_b.global_position
	)
	var query := NavigationPathQueryParameters3D.new()
	query.map = map
	query.start_position = start
	query.target_position = target
	query.metadata_flags = (
		NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_ALL
	)
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	return (
		result.path.size() >= 2
		and result.path[result.path.size() - 1].distance_to(target) <= 0.5
	)


func _wait_for_guard_patrol_leg(
	guard: VarkGuard,
	tree: SceneTree,
	max_frames: int
) -> bool:
	if guard == null:
		return false
	for _frame_index: int in max_frames:
		var summary: Dictionary = guard.get_debug_summary()
		if int(summary.get("patrol_leg_count", 0)) >= 1:
			return true
		if not str(summary.get("last_error", "")).is_empty():
			return false
		await tree.physics_frame
		await tree.process_frame
	return int(guard.get_debug_summary().get("patrol_leg_count", 0)) >= 1


func _count_direct_collision_shapes(node: Node) -> int:
	if node == null:
		return 0
	var count: int = 0
	for child: Node in node.get_children():
		if child is CollisionShape3D:
			count += 1
	return count


func _find_by_property(
	nodes: Array[Node],
	property_name: String,
	expected: Variant
) -> Node:
	for node: Node in nodes:
		if node.get(property_name) == expected:
			return node
	return null


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _map_origin_to_world(map_origin: Vector3) -> Vector3:
	return Vector3(map_origin.y, map_origin.z, map_origin.x) / 32.0


func _wait_for_navigation(world: Node, tree: SceneTree) -> bool:
	for _frame_index: int in 240:
		if bool(world.get("navigation_ready")):
			return true
		if not (world.get("navigation_errors") as PackedStringArray).is_empty():
			return false
		await tree.physics_frame
		await tree.process_frame
	return bool(world.get("navigation_ready"))
