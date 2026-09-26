extends Node3D


signal navigation_rebuilt(serial: int)


const PLAYER_START_GROUP: StringName = &"vark_player_start"
const EXIT_GROUP: StringName = &"vark_mission_exit"
const PATROL_POINT_GROUP: StringName = &"vark_patrol_point"
const GUARD_GROUP: StringName = &"vark_guard"
const GuardAwarenessScript = preload("res://gameplay/npc/guard_awareness.gd")
const GuardCommunicationScript = preload("res://gameplay/npc/guard_communication.gd")
const AcousticPropagationScript = preload(
	"res://gameplay/acoustics/acoustic_propagation.gd"
)
const GuardSpeechLine = preload(
	"res://missions/representative_stealth/guard_heard_noise.tres"
)


@onready var player: CharacterBody3D = $Player
@onready var func_map: FuncGodotMap = $FuncGodotMap
@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var gameplay_exposure: VarkGameplayExposure = $GameplayExposure
@onready var exit_trigger: VarkSemanticRouteTrigger = $ExitTrigger

var mission_definition: Resource = null
var selected_player_start: Node3D = null
var navigation_ready: bool = false
var navigation_rebuild_serial: int = 0
var navigation_errors := PackedStringArray()
var acoustic_propagation: VarkAcousticPropagation = null
var _navigation_mesh: NavigationMesh = null
var _guard: VarkGuard = null


func configure_mission_definition(definition: Resource) -> bool:
	if is_inside_tree() or definition == null:
		return false
	mission_definition = definition
	return true


func _ready() -> void:
	assert(
		mission_definition != null,
		"Representative Stealth must be instantiated through its MissionDefinition."
	)
	func_map.local_map_file = str(mission_definition.get("map_source_path"))
	func_map.build()
	_apply_authored_player_start()
	_apply_authored_exit()
	acoustic_propagation = AcousticPropagationScript.new()
	acoustic_propagation.name = "AcousticPropagation"
	add_child(acoustic_propagation)
	_configure_guard_runtime()
	var acoustic_result: Dictionary = acoustic_propagation.configure(self)
	if not bool(acoustic_result.get("ok", false)):
		for message: String in acoustic_result.get(
			"errors",
			PackedStringArray()
		):
			push_error(message)
	gameplay_exposure.refresh_sources()
	gameplay_exposure.sample_now()
	call_deferred("_rebuild_navigation_from_imported_geometry")


func get_representative_debug_summary() -> Dictionary:
	var awareness: Node = (
		_guard.get_node_or_null("Awareness")
		if _guard != null
		else null
	)
	var communication: Node = (
		_guard.get_node_or_null("Communication")
		if _guard != null
		else null
	)
	return {
		"map_source_path": func_map.local_map_file,
		"player_start_selected": selected_player_start != null,
		"exit_trigger_position": exit_trigger.global_position,
		"navigation_ready": navigation_ready,
		"navigation_errors": navigation_errors.duplicate(),
		"guard": _guard.get_debug_summary() if _guard != null else {},
		"awareness": (
			awareness.call("get_debug_summary")
			if awareness != null
			else {}
		),
		"communication": (
			communication.call("get_debug_summary")
			if communication != null
			else {}
		),
		"acoustics": acoustic_propagation.get_debug_summary(),
	}


func _configure_guard_runtime() -> void:
	var guards: Array[VarkGuard] = []
	for node: Node in func_map.find_children("*", "", true, false):
		if node.is_in_group(GUARD_GROUP):
			var guard := node as VarkGuard
			if guard != null:
				guards.append(guard)
	if guards.size() != 1:
		push_error(
			"Representative Stealth expected one authored guard, found %d."
			% guards.size()
		)
		return
	_guard = guards[0]

	var hearing := VarkAcousticListener.new()
	hearing.name = "Hearing"
	hearing.position = Vector3(0.0, 1.25, 0.0)
	hearing.listener_id = &"listener.dev_stealth.guard"
	hearing.hearing_threshold = 0.16
	_guard.add_child(hearing)

	var speech := VarkWorldSpeechSpeaker.new()
	speech.name = "Speech"
	speech.speech_line = GuardSpeechLine
	speech.propagation_path = NodePath(str(acoustic_propagation.get_path()))
	speech.listener_path = NodePath(str($Player/SpeechListener.get_path()))
	speech.label_path = NodePath("SpeechLabel")
	speech.auto_repeat_seconds = 0.0
	var speech_label := Label3D.new()
	speech_label.name = "SpeechLabel"
	speech_label.position = Vector3(0.0, 2.2, 0.0)
	speech_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	speech_label.font_size = 30
	speech_label.outline_size = 8
	speech_label.no_depth_test = true
	speech.add_child(speech_label)
	_guard.add_child(speech)

	var reaction_label := Label3D.new()
	reaction_label.name = "ReactionLabel"
	reaction_label.position = Vector3(0.0, 2.85, 0.0)
	reaction_label.text = "CALM"
	reaction_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reaction_label.font_size = 19
	reaction_label.outline_size = 7
	reaction_label.no_depth_test = true
	_guard.add_child(reaction_label)

	var awareness: Node = GuardAwarenessScript.new()
	awareness.name = "Awareness"
	awareness.set("player_path", NodePath(str(player.get_path())))
	awareness.set("listener_path", NodePath("../Hearing"))
	awareness.set("speech_path", NodePath("../Speech"))
	awareness.set(
		"exposure_path",
		NodePath(str(gameplay_exposure.get_path()))
	)
	awareness.set("status_label_path", NodePath("../ReactionLabel"))
	_guard.add_child(awareness)

	var communication: Node = GuardCommunicationScript.new()
	communication.name = "Communication"
	communication.set("guard_path", NodePath(".."))
	communication.set("awareness_path", NodePath("../Awareness"))
	communication.set("listener_path", NodePath("../Hearing"))
	communication.set(
		"acoustic_propagation_path",
		NodePath(str(acoustic_propagation.get_path()))
	)
	communication.set("faction_id", &"guards")
	communication.set(
		"alarm_channels",
		PackedStringArray(["alarm.dev_stealth"])
	)
	_guard.add_child(communication)


func _rebuild_navigation_from_imported_geometry() -> void:
	navigation_ready = false
	navigation_errors.clear()

	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.cell_size = 0.10
	navigation_mesh.agent_radius = 0.30
	navigation_mesh.agent_height = 1.75
	navigation_mesh.agent_max_climb = 0.30
	navigation_mesh.agent_max_slope = 45.0
	navigation_mesh.sample_partition_type = (
		NavigationMesh.SAMPLE_PARTITION_MONOTONE
	)
	navigation_mesh.geometry_parsed_geometry_type = (
		NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	)
	navigation_mesh.geometry_source_geometry_mode = (
		NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	)
	navigation_mesh.geometry_collision_mask = 1

	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(
		navigation_mesh,
		source_geometry,
		func_map
	)

	var openings: Array[VarkOrdinaryDoor] = []
	var patrol_points: Dictionary = {}
	for node: Node in func_map.find_children("*", "", true, false):
		var opening := node as VarkOrdinaryDoor
		if opening != null:
			openings.append(opening)
			continue
		if node.is_in_group(PATROL_POINT_GROUP):
			var patrol := node as VarkPatrolPoint
			if patrol == null or patrol.patrol_id.strip_edges().is_empty():
				navigation_errors.append(
					"Representative mission has an invalid patrol point."
				)
			elif patrol_points.has(patrol.patrol_id):
				navigation_errors.append(
					"Duplicate patrol_id '%s'." % patrol.patrol_id
				)
			else:
				patrol_points[patrol.patrol_id] = patrol

	for opening: VarkOrdinaryDoor in openings:
		if not opening.configure_navigation_traversal(
			navigation_mesh.agent_radius,
			0.30
		):
			navigation_errors.append(
				"Opening '%s' could not configure navigation traversal."
				% opening.door_id
			)
			continue
		if not opening.contribute_navigation_bake_cut(source_geometry):
			navigation_errors.append(
				"Opening '%s' could not contribute its navigation cut."
				% opening.door_id
			)

	if not navigation_errors.is_empty():
		_report_navigation_errors()
		return

	NavigationServer3D.bake_from_source_geometry_data(
		navigation_mesh,
		source_geometry
	)
	if navigation_mesh.get_polygon_count() <= 0:
		navigation_errors.append(
			"Representative mission navigation bake produced no polygons."
		)
		_report_navigation_errors()
		return

	_navigation_mesh = navigation_mesh
	var navigation_map: RID = get_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(navigation_map, false)
	NavigationServer3D.region_set_use_async_iterations(
		navigation_region.get_rid(),
		false
	)
	NavigationServer3D.map_set_cell_size(
		navigation_map,
		navigation_mesh.cell_size
	)
	var region_iteration_before: int = NavigationServer3D.map_get_iteration_id(
		navigation_map
	)
	navigation_region.navigation_mesh = navigation_mesh
	if not await _wait_for_navigation_map_iteration(
		navigation_map,
		region_iteration_before,
		120
	):
		navigation_errors.append(
			"Representative mission navigation map did not synchronize."
		)
		_report_navigation_errors()
		return

	for opening: VarkOrdinaryDoor in openings:
		var link_iteration_before: int = NavigationServer3D.map_get_iteration_id(
			navigation_map
		)
		if not opening.finalize_navigation_traversal(navigation_map):
			navigation_errors.append(
				"Opening '%s' could not finalize its navigation link."
				% opening.door_id
			)
			continue
		if not await _wait_for_navigation_map_iteration(
			navigation_map,
			link_iteration_before,
			120
		):
			navigation_errors.append(
				"Opening '%s' navigation link did not synchronize."
				% opening.door_id
			)

	if _guard == null:
		navigation_errors.append("Representative mission guard runtime is missing.")
	else:
		var guard_door: VarkOrdinaryDoor = null
		for opening: VarkOrdinaryDoor in openings:
			if str(opening.door_id) == _guard.door_id:
				guard_door = opening
				break
		if guard_door == null:
			navigation_errors.append(
				"Guard door_id '%s' does not resolve to an authored opening."
				% _guard.door_id
			)
		elif not _guard.configure_patrol(patrol_points, guard_door):
			navigation_errors.append(
				str(_guard.get_debug_summary().get("last_error", ""))
			)

	if not navigation_errors.is_empty():
		_report_navigation_errors()
		return

	navigation_rebuild_serial += 1
	navigation_ready = true
	navigation_rebuilt.emit(navigation_rebuild_serial)


func _wait_for_navigation_map_iteration(
	navigation_map: RID,
	previous_iteration: int,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		var iteration: int = NavigationServer3D.map_get_iteration_id(
			navigation_map
		)
		if iteration != 0 and iteration != previous_iteration:
			return true
		await get_tree().physics_frame
		await get_tree().process_frame
	return (
		NavigationServer3D.map_get_iteration_id(navigation_map) != 0
		and NavigationServer3D.map_get_iteration_id(navigation_map)
			!= previous_iteration
	)


func _report_navigation_errors() -> void:
	for message: String in navigation_errors:
		push_error(message)


func _apply_authored_player_start() -> void:
	var selector: String = str(
		mission_definition.get("player_start_selector")
	).strip_edges()
	var matches: Array[Node] = []
	for node: Node in func_map.find_children("*", "", true, false):
		if (
			node.is_in_group(PLAYER_START_GROUP)
			and node.has_method("get_content_id")
			and str(node.call("get_content_id")).strip_edges() == selector
		):
			matches.append(node)
	if matches.size() != 1:
		push_error(
			"Representative mission player start '%s' resolved to %d nodes."
			% [selector, matches.size()]
		)
		return
	selected_player_start = matches[0] as Node3D
	if selected_player_start != null:
		player.global_transform = selected_player_start.global_transform


func _apply_authored_exit() -> void:
	var matches: Array[Node] = []
	for node: Node in func_map.find_children("*", "", true, false):
		if (
			node.is_in_group(EXIT_GROUP)
			and node.has_method("get_content_id")
			and str(node.call("get_content_id")) == "exit.dev_stealth"
		):
			matches.append(node)
	if matches.size() != 1:
		push_error(
			"Representative mission exit resolved to %d nodes; expected one."
			% matches.size()
		)
		return
	var authored_exit := matches[0] as Node3D
	if authored_exit != null:
		exit_trigger.global_transform = authored_exit.global_transform
