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

const UP_GAPS := [
	"ledge_city.w00",
	"ledge_city.w01",
	"ledge_city.w02",
	"ledge_city.w03",
	"ledge_city.w04",
	"ledge_city.w06",
	"ledge_city.w07",
	"ledge_city.w08",
	"ledge_city.w09",
	"ledge_city.w11",
	"ledge_city.w12",
	"ledge_city.e00",
	"ledge_city.e01",
	"ledge_city.e02",
	"ledge_city.e03",
]
const LATERAL_GAPS := [
	"ledge_city.w05",
	"ledge_city.w10",
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
		"8.4 keeps the accepted vertical-city target unchanged and exposes Ledge City as a separate Development Launch mission"
	)
	application.free()

	var load_errors: PackedStringArray = Definition.call("get_load_errors")
	assert_true.call(
		load_errors.is_empty()
		and Definition.get("mission_id")
			== &"phase8_representative_stealth_ledge_city"
		and str(Definition.get("map_source_path")) == LEDGE_PATH.replace(
			"mission.tres",
			"mission.map"
		)
		and int(Definition.get("mission_content_revision")) == 1,
		"8.4 Ledge City owns a distinct MissionDefinition/save identity and authoritative mapper source"
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
		"8.4 Ledge City builds through the same production MissionDefinition/WorldSession path"
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
		and lights.size() == 6
		and switches.size() == 1
		and openings.size() == 2
		and pickups.size() == 4
		and markers.size() >= 35
		and _count_direct_collision_shapes(worldspawn) >= 105,
		"8.4 Ledge City preserves representative gameplay roles while adding a dense independent traversal-stress city"
	)

	var ground_catch: Node = _find_by_property(
		markers,
		"content_id",
		"ledge_city.ground_catch"
	)
	var key_roof: Node = _find_by_property(
		markers,
		"content_id",
		"ledge_city.key_roof"
	)
	var archive_apex: Node = _find_by_property(
		markers,
		"content_id",
		"ledge_city.archive_apex"
	)
	assert_true.call(
		ground_catch != null
		and ground_catch.global_position.y >= 2.40
		and ground_catch.global_position.y <= 2.55
		and key_roof != null
		and key_roof.global_position.y >= 6.30
		and archive_apex != null
		and archive_apex.global_position.y >= 14.0,
		"8.4 Ledge City starts above ordinary standing reach and escalates through a high key roof to a fourteen-metre archive apex"
	)

	var upward_gaps_valid: bool = true
	for prefix: String in UP_GAPS:
		var from_marker: Node3D = _find_by_property(
			markers,
			"content_id",
			prefix + ".from"
		) as Node3D
		var to_marker: Node3D = _find_by_property(
			markers,
			"content_id",
			prefix + ".to"
		) as Node3D
		if from_marker == null or to_marker == null:
			upward_gaps_valid = false
			break
		var rise: float = to_marker.global_position.y - from_marker.global_position.y
		var horizontal_gap: float = _horizontal_distance(
			from_marker.global_position,
			to_marker.global_position
		)
		if (
			rise < 0.90
			or rise > 1.10
			or horizontal_gap < 0.80
			or horizontal_gap > 2.25
		):
			upward_gaps_valid = false
			break
	assert_true.call(
		upward_gaps_valid,
		"8.4 Ledge City upward roof gaps sit inside the proven hang-jump/catch envelope instead of the old small-step mantle envelope"
	)

	var lateral_gaps_valid: bool = true
	for prefix: String in LATERAL_GAPS:
		var from_marker: Node3D = _find_by_property(
			markers,
			"content_id",
			prefix + ".from"
		) as Node3D
		var to_marker: Node3D = _find_by_property(
			markers,
			"content_id",
			prefix + ".to"
		) as Node3D
		if from_marker == null or to_marker == null:
			lateral_gaps_valid = false
			break
		var rise: float = absf(
			to_marker.global_position.y - from_marker.global_position.y
		)
		var horizontal_gap: float = _horizontal_distance(
			from_marker.global_position,
			to_marker.global_position
		)
		if rise > 0.05 or horizontal_gap < 1.60 or horizontal_gap > 2.40:
			lateral_gaps_valid = false
			break
	assert_true.call(
		lateral_gaps_valid,
		"8.4 Ledge City includes real same-height ledge-to-ledge directional jumps rather than only touching platforms"
	)

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
		if locked_door != null
		else {}
	)
	assert_true.call(
		window != null
		and str(window.get("opening_variant")) == "window"
		and window.global_position.y >= 6.7
		and locked_door != null
		and bool(access.get("locked", false))
		and str(access.get("required_key_id", "")) == "key.service",
		"8.4 Ledge City keeps the high window bypass and distinct locked/key street gate"
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
		"8.4 Ledge City retains the representative key/loot/objective content contract"
	)

	var nav_ready: bool = await _wait_for_navigation(world, tree)
	assert_true.call(
		nav_ready
		and (world.get("navigation_errors") as PackedStringArray).is_empty(),
		"8.4 Ledge City dense rooftop geometry still produces valid street-level guard navigation and opening links"
	)
	assert_true.call(
		bool(session.call("begin_play")),
		"8.4 Ledge City reaches PLAYING through the normal lifecycle"
	)

	var summary: Dictionary = session.call("get_mission_run_summary")
	assert_true.call(
		int(summary.get("loot_available_count", -1)) == 2
		and int(summary.get("loot_available_value", -1)) == 125,
		"8.4 Ledge City establishes the same authored mission-start loot availability without sharing save identity with the baseline city"
	)

	session.call("teardown")
	session.queue_free()
	await tree.process_frame


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


func _wait_for_navigation(world: Node, tree: SceneTree) -> bool:
	for _frame_index: int in 240:
		if bool(world.get("navigation_ready")):
			return true
		if not (world.get("navigation_errors") as PackedStringArray).is_empty():
			return false
		await tree.physics_frame
		await tree.process_frame
	return bool(world.get("navigation_ready"))
