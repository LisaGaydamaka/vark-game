extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const WorldSession = preload("res://application/world_session.gd")
const Definition: Resource = preload(
	"res://missions/representative_stealth/mission.tres"
)

const OBJECTIVE_ID: StringName = &"objective.dev_stealth.ledger"
const WINDOW_ID: String = "opening.window_west"
const LOCKED_DOOR_ID: String = "door.east_locked"


func run(tree: SceneTree, assert_true: Callable) -> void:
	var application: Node = ApplicationScene.instantiate()
	var labels: PackedStringArray = application.get("development_launch_labels")
	var paths: PackedStringArray = application.get(
		"development_launch_resource_paths"
	)
	var target_index: int = labels.find("Representative Stealth")
	assert_true.call(
		target_index >= 0
		and target_index < paths.size()
		and paths[target_index]
			== "res://missions/representative_stealth/mission.tres",
		"8.4 representative stealth mission is a curated Development Launch MissionDefinition target"
	)
	application.free()

	var load_errors: PackedStringArray = Definition.call("get_load_errors")
	var rules: Array[Dictionary] = Definition.get("mission_rule_declarations")
	assert_true.call(
		load_errors.is_empty()
		and Definition.get("mission_id") == &"phase8_representative_stealth"
		and str(Definition.get("map_source_path"))
			== "res://missions/representative_stealth/mission.map"
		and rules.size() == 2,
		"8.4 package owns valid map-backed load metadata and two small declarative reactions"
	)

	var session: Node = WorldSession.new()
	session.name = "Phase8RepresentativeWorldSession"
	tree.get_root().add_child(session)
	var built: bool = bool(session.call(
		"build",
		84001,
		Definition.get("world_scene"),
		Definition
	))
	var world := session.get("world") as Node
	var player := session.get("player") as Node
	assert_true.call(
		built
		and world != null
		and player != null
		and world.has_method("get_representative_debug_summary"),
		"8.4 real representative package builds through the production MissionDefinition/WorldSession path"
	)
	if not built or world == null or player == null:
		session.call("teardown")
		session.queue_free()
		await tree.process_frame
		return

	var nodes: Array[Node] = [world]
	nodes.append_array(world.find_children("*", "", true, false))
	var openings: Array[Node] = []
	var pickups: Array[Node] = []
	var containers: Array[Node] = []
	var surfaces: Array[Node] = []
	var guards: Array[Node] = []
	var patrol_points: Array[Node] = []
	var props: Array[Node] = []
	var lights: Array[Node] = []
	var switches: Array[Node] = []
	var starts: Array[Node] = []
	var exits: Array[Node] = []
	for node: Node in nodes:
		if node.has_method("get_access_summary") and node.has_method(
			"configure_navigation_traversal"
		):
			openings.append(node)
		if node.has_method("get_collection_payload"):
			pickups.append(node)
		if node.is_in_group(&"vark_container"):
			containers.append(node)
		if node.is_in_group(&"vark_footstep_surface"):
			surfaces.append(node)
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

	var window: Node = _find_by_property(openings, "door_id", WINDOW_ID)
	var locked_door: Node = _find_by_property(
		openings,
		"door_id",
		LOCKED_DOOR_ID
	)
	var access: Dictionary = (
		locked_door.call("get_access_summary")
		if locked_door != null
		else {}
	)
	var surface_variants: Array[String] = []
	for surface: Node in surfaces:
		surface_variants.append(str(surface.get("surface_variant")))
	surface_variants.sort()

	var pickup_roles: Dictionary = {}
	var loot_pickups: Array[Node] = []
	var ledger: Node = null
	for pickup: Node in pickups:
		var payload: Dictionary = pickup.call("get_collection_payload")
		var content_id: String = str(payload.get("content_id", ""))
		pickup_roles[content_id] = payload.get("kind", &"")
		if payload.get("kind", &"") == &"loot":
			loot_pickups.append(pickup)
		if content_id == "mission.dev_stealth.ledger":
			ledger = pickup

	assert_true.call(
		starts.size() == 1
		and exits.size() == 1
		and guards.size() == 1
		and patrol_points.size() == 2
		and containers.size() == 1
		and props.size() == 2
		and lights.size() == 3
		and switches.size() == 1,
		"8.4 authoritative map builds exact representative topology counts: start/exit/guard/patrol/container/props/lights/switch"
	)
	assert_true.call(
		openings.size() == 2,
		"8.4 representative map builds exactly two ordinary-opening instances"
	)
	assert_true.call(
		window != null
		and str(window.get("opening_variant")) == "window",
		"8.4 west route resolves the authored window presentation on OrdinaryDoor"
	)
	assert_true.call(
		window != null
		and str(window.get("visual_model_path"))
			== "res://assets/models/doors/ordinary_window_leaf.obj",
		"8.4 west window presentation resolves the compatible shared window leaf model"
	)
	assert_true.call(
		locked_door != null
		and bool(access.get("locked", false))
		and str(access.get("required_key_id", "")) == "key.service",
		"8.4 east route resolves the authored locked/key OrdinaryDoor restriction"
	)
	assert_true.call(
		pickups.size() == 4
		and loot_pickups.size() == 2
		and pickup_roles.get("key.service", &"") == &"key"
		and pickup_roles.get("mission.dev_stealth.ledger", &"")
			== &"mission_item",
		"8.4 authoritative map builds four typed pickups: two loot, one key, and one mission item"
	)
	assert_true.call(
		surface_variants == ["carpet", "stone", "tile"],
		"8.4 authoritative map builds quiet/normal/loud semantic surface variants as carpet/stone/tile"
	)

	var initial_summary: Dictionary = session.call("get_mission_run_summary")
	var objectives: Array = initial_summary.get("objectives", [])
	assert_true.call(
		int(initial_summary.get("loot_count", -1)) == 0
		and int(initial_summary.get("loot_value", -1)) == 0
		and int(initial_summary.get("loot_available_count", -1)) == 2
		and int(initial_summary.get("loot_available_value", -1)) == 125
		and typeof(initial_summary.get("gameplay_time_seconds", null))
			== TYPE_FLOAT
		and objectives.size() == 1
		and (objectives[0] as Dictionary).get("objective_id", &"")
			== OBJECTIVE_ID
		and (objectives[0] as Dictionary).get("state", &"") == &"active",
		"8.4 run summary establishes available loot from fresh authored mission-start content and aggregates gameplay time/objective truth from existing owners"
	)

	var nav_ready: bool = await _wait_for_navigation(world, tree)
	var nav_errors: PackedStringArray = world.get("navigation_errors")
	assert_true.call(
		nav_ready and nav_errors.is_empty(),
		"8.4 representative authored geometry produces a usable guard navigation bake with ordinary opening links"
	)

	assert_true.call(
		bool(session.call("begin_play")),
		"8.4 representative mission reaches PLAYING through the normal lifecycle"
	)

	var collected_loot: Node = loot_pickups[0] if not loot_pickups.is_empty() else null
	var loot_payload: Dictionary = (
		collected_loot.call("get_collection_payload")
		if collected_loot != null
		else {}
	)
	var first_loot_value: int = int(loot_payload.get("loot_value", 0))
	var loot_collected: bool = (
		bool(session.call("collect_authored_pickup", player, collected_loot))
		if collected_loot != null
		else false
	)
	await _settle(tree)
	var after_loot: Dictionary = session.call("get_mission_run_summary")
	assert_true.call(
		loot_collected
		and int(after_loot.get("loot_count", -1)) == 1
		and int(after_loot.get("loot_value", -1)) == first_loot_value
		and int(after_loot.get("loot_available_count", -1)) == 2
		and int(after_loot.get("loot_available_value", -1)) == 125,
		"8.4 collected loot changes run progress without recomputing or shrinking mission-start availability"
	)

	var ledger_collected: bool = (
		bool(session.call("collect_authored_pickup", player, ledger))
		if ledger != null
		else false
	)
	await _settle(tree)
	await _settle(tree)
	var objective: Dictionary = session.call(
		"query_mission_objective",
		OBJECTIVE_ID
	)
	var alarm := world.get_node_or_null("AlarmChannel") as Node
	var alarm_debug: Dictionary = (
		alarm.call("get_debug_summary")
		if alarm != null
		else {}
	)
	var awareness := guards[0].get_node_or_null("Awareness") as Node
	var awareness_debug: Dictionary = (
		awareness.call("get_debug_summary")
		if awareness != null
		else {}
	)
	var after_ledger: Dictionary = session.call("get_mission_run_summary")
	var after_objectives: Array = after_ledger.get("objectives", [])
	assert_true.call(
		ledger_collected
		and bool(objective.get("complete", false))
		and bool(alarm_debug.get("active", false))
		and int(alarm_debug.get("raise_serial", 0)) == 1
		and awareness_debug.get("awareness_state", &"") == &"searching"
		and after_objectives.size() == 1
		and bool((after_objectives[0] as Dictionary).get("complete", false)),
		"8.4 real mission-item pickup drives declarative objective completion and the existing alarm/guard search ownership chain"
	)

	var exit_state: Dictionary = session.call(
		"query_mission_exit",
		&"exit.dev_stealth"
	)
	var envelope: Dictionary = session.call("capture_save_envelope")
	var saved_run: Dictionary = (
		(envelope.get("world_state", {}) as Dictionary).get(
			"mission_run_state",
			{}
		) as Dictionary
	)
	assert_true.call(
		bool(exit_state.get("unlocked", false))
		and not envelope.is_empty()
		and int(saved_run.get("loot_available_count", -1)) == 2
		and int(saved_run.get("loot_available_value", -1)) == 125,
		"8.4 objective unlock and start-latched available-loot truth are saveable semantic state, not mission-end scene scraping"
	)

	session.call("teardown")
	session.queue_free()
	await tree.process_frame


func _find_by_property(
	nodes: Array[Node],
	property_name: String,
	expected: Variant
) -> Node:
	for node: Node in nodes:
		if node.get(property_name) == expected:
			return node
	return null


func _wait_for_navigation(world: Node, tree: SceneTree) -> bool:
	for _frame_index: int in 240:
		if bool(world.get("navigation_ready")):
			return true
		if not (world.get("navigation_errors") as PackedStringArray).is_empty():
			return false
		await tree.physics_frame
		await tree.process_frame
	return bool(world.get("navigation_ready"))


func _settle(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
