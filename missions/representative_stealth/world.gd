extends Node3D


signal navigation_rebuilt(serial: int)


const PLAYER_START_GROUP: StringName = &"vark_player_start"
const EXIT_GROUP: StringName = &"vark_mission_exit"
const PATROL_POINT_GROUP: StringName = &"vark_patrol_point"
const GUARD_GROUP: StringName = &"vark_guard"
const DOOR_FRAME_GROUP: StringName = &"vark_door_frame"
const GuardAwarenessScript = preload("res://gameplay/npc/guard_awareness.gd")
const GuardCommunicationScript = preload("res://gameplay/npc/guard_communication.gd")
const AcousticPropagationScript = preload(
	"res://gameplay/acoustics/acoustic_propagation.gd"
)
const GuardSpeechLine = preload(
	"res://missions/representative_stealth/guard_heard_noise.tres"
)
const LEDGE_CITY_MISSION_ID: StringName = &"phase8_representative_stealth_ledge_city"
const LEDGE_CITY_STATIC_SHADOW_RENDER_LAYER: int = 19
const LEDGE_CITY_STATIC_SHADOW_RENDER_MASK: int = 1 << (
	LEDGE_CITY_STATIC_SHADOW_RENDER_LAYER - 1
)
const LEDGE_CITY_SHADOW_ATLAS_SIZE: int = 4096
const LEDGE_CITY_SHADOW_ATLAS_SUBDIV: Viewport.PositionalShadowAtlasQuadrantSubdiv = (
	Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
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
static var _shared_shadow_budget_refcount: int = 0
static var _shared_shadow_budget_viewport: Viewport = null
static var _shared_shadow_budget_previous_size: int = 0
static var _shared_shadow_budget_previous_16_bits: bool = true
static var _shared_shadow_budget_previous_subdivisions: Array[int] = []
static var _shared_shadow_budget_atlas_applied: bool = false

var _navigation_mesh: NavigationMesh = null
var _guard: VarkGuard = null
var _owns_shadow_budget_reference: bool = false


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
	_configure_ledge_city_shadow_budget()
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


func _exit_tree() -> void:
	_restore_ledge_city_shadow_budget()


func _configure_ledge_city_shadow_budget() -> void:
	if (
		mission_definition == null
		or StringName(mission_definition.get("mission_id")) != LEDGE_CITY_MISSION_ID
		or _owns_shadow_budget_reference
	):
		return

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return

	# F9 replacement can construct the next world before the old world exits.
	# Treat the renderer budget as shared mission-scoped state so the retiring
	# world cannot restore defaults underneath the replacement world.
	if _shared_shadow_budget_refcount == 0:
		_shared_shadow_budget_viewport = viewport
		_shared_shadow_budget_atlas_applied = _should_apply_shadow_atlas_budget()
		if _shared_shadow_budget_atlas_applied:
			_shared_shadow_budget_previous_size = (
				viewport.positional_shadow_atlas_size
			)
			_shared_shadow_budget_previous_16_bits = (
				viewport.positional_shadow_atlas_16_bits
			)
			_shared_shadow_budget_previous_subdivisions.clear()
			for quadrant: int in 4:
				_shared_shadow_budget_previous_subdivisions.append(
					int(
						viewport.get_positional_shadow_atlas_quadrant_subdiv(
							quadrant
						)
					)
				)
	elif _shared_shadow_budget_viewport != viewport:
		push_error(
			"Ledge City shadow budget cannot span multiple active Viewports."
		)
		return

	# Headless CI has no Forward+ frame pacing to optimize, and allocating/
	# repartitioning its positional shadow atlas can stall renderer teardown.
	# Keep the renderer-facing caster partition fully testable there, but only
	# mutate the real atlas in a rendered runtime.
	if _shared_shadow_budget_atlas_applied:
		viewport.positional_shadow_atlas_size = LEDGE_CITY_SHADOW_ATLAS_SIZE
		viewport.positional_shadow_atlas_16_bits = true
		for quadrant: int in 4:
			viewport.set_positional_shadow_atlas_quadrant_subdiv(
				quadrant,
				LEDGE_CITY_SHADOW_ATLAS_SUBDIV
			)

	_shared_shadow_budget_refcount += 1
	_owns_shadow_budget_reference = true
	_configure_ledge_city_shadow_casters()


func _should_apply_shadow_atlas_budget() -> bool:
	return DisplayServer.get_name().to_lower() != "headless"


func _configure_ledge_city_shadow_casters() -> void:
	var worldspawn := func_map.get_node_or_null("entity_0_worldspawn") as StaticBody3D
	if worldspawn != null:
		_set_shadow_render_layer_recursive(worldspawn, true, true)

	for node: Node in func_map.find_children("*", "", true, false):
		if node.is_in_group(DOOR_FRAME_GROUP):
			_set_shadow_render_layer_recursive(node, true, true)
		if node is VarkOrdinaryDoor:
			var door_mesh := node.get_node_or_null("DoorMesh") as MeshInstance3D
			if door_mesh != null:
				door_mesh.set_layer_mask_value(
					LEDGE_CITY_STATIC_SHADOW_RENDER_LAYER,
					true
				)
				door_mesh.cast_shadow = (
					GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
				)
		if node is VarkGameplayLight:
			var light := node as VarkGameplayLight
			light.set_visual_shadow_caster_mask(
				LEDGE_CITY_STATIC_SHADOW_RENDER_MASK
			)
			var body_mesh := light.find_child(
				"BodyMesh",
				true,
				false
			) as MeshInstance3D
			if body_mesh != null:
				body_mesh.set_layer_mask_value(
					LEDGE_CITY_STATIC_SHADOW_RENDER_LAYER,
					true
				)
		if node is VarkOrdinaryProp:
			var prop_mesh := node.get_node_or_null("PropMesh") as MeshInstance3D
			if prop_mesh != null:
				prop_mesh.set_layer_mask_value(
					LEDGE_CITY_STATIC_SHADOW_RENDER_LAYER,
					false
				)
		if node is VarkGuard:
			var guard_mesh := node.get_node_or_null("GuardMesh") as MeshInstance3D
			if guard_mesh != null:
				guard_mesh.set_layer_mask_value(
					LEDGE_CITY_STATIC_SHADOW_RENDER_LAYER,
					false
				)


func _restore_ledge_city_shadow_budget() -> void:
	if not _owns_shadow_budget_reference:
		return
	_owns_shadow_budget_reference = false
	_shared_shadow_budget_refcount = maxi(_shared_shadow_budget_refcount - 1, 0)
	if _shared_shadow_budget_refcount > 0:
		return

	var viewport: Viewport = _shared_shadow_budget_viewport
	if (
		_shared_shadow_budget_atlas_applied
		and viewport != null
		and is_instance_valid(viewport)
	):
		viewport.positional_shadow_atlas_size = _shared_shadow_budget_previous_size
		viewport.positional_shadow_atlas_16_bits = (
			_shared_shadow_budget_previous_16_bits
		)
		for quadrant: int in mini(
			4,
			_shared_shadow_budget_previous_subdivisions.size()
		):
			viewport.set_positional_shadow_atlas_quadrant_subdiv(
				quadrant,
				_shared_shadow_budget_previous_subdivisions[quadrant]
			)

	_shared_shadow_budget_viewport = null
	_shared_shadow_budget_previous_subdivisions.clear()
	_shared_shadow_budget_atlas_applied = false


func get_shadow_budget_debug_state() -> Dictionary:
	return {
		"active": _owns_shadow_budget_reference,
		"shared_refcount": _shared_shadow_budget_refcount,
		"atlas_requested": true,
		"atlas_applied": _shared_shadow_budget_atlas_applied,
		"desired_atlas_size": LEDGE_CITY_SHADOW_ATLAS_SIZE,
		"desired_atlas_subdiv": int(LEDGE_CITY_SHADOW_ATLAS_SUBDIV),
		"static_shadow_render_layer": LEDGE_CITY_STATIC_SHADOW_RENDER_LAYER,
		"static_shadow_render_mask": LEDGE_CITY_STATIC_SHADOW_RENDER_MASK,
	}


func _set_shadow_render_layer_recursive(
	root: Node,
	enabled: bool,
	double_sided: bool = false
) -> void:
	if root is MeshInstance3D:
		var mesh := root as MeshInstance3D
		mesh.set_layer_mask_value(
			LEDGE_CITY_STATIC_SHADOW_RENDER_LAYER,
			enabled
		)
		if enabled and double_sided:
			mesh.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			)
	for child: Node in root.get_children():
		_set_shadow_render_layer_recursive(child, enabled, double_sided)


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
	var navigation_openings: Array[VarkOrdinaryDoor] = []
	var patrol_points: Dictionary = {}
	for node: Node in func_map.find_children("*", "", true, false):
		var opening := node as VarkOrdinaryDoor
		if opening != null:
			openings.append(opening)
			# Sneak windows reuse the ordinary-opening semantic/persistence spine,
			# but the guard navigation agent is 1.75 m tall and cannot crouch.
			# Do not carve/register an NPC smart link through a player-only
			# 1.18 m aperture; the real map geometry remains authoritative.
			if str(opening.opening_variant) != "sneak_window":
				navigation_openings.append(opening)
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

	for opening: VarkOrdinaryDoor in navigation_openings:
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

	for opening: VarkOrdinaryDoor in navigation_openings:
		var link_iteration_before: int = NavigationServer3D.map_get_iteration_id(
			navigation_map
		)
		if not opening.finalize_navigation_traversal(navigation_map):
			navigation_errors.append(
				"Opening '%s' could not finalize its navigation link. nav=%s"
				% [
					opening.door_id,
					str(opening.get_navigation_link_summary()),
				]
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
		elif not _validate_guard_patrol_navigation(
			navigation_map,
			patrol_points
		):
			navigation_errors.append(
				"Representative mission guard patrol endpoints do not share a usable navigation path."
			)

	if not navigation_errors.is_empty():
		_report_navigation_errors()
		return

	navigation_rebuild_serial += 1
	navigation_ready = true
	navigation_rebuilt.emit(navigation_rebuild_serial)


func _validate_guard_patrol_navigation(
	navigation_map: RID,
	patrol_points: Dictionary
) -> bool:
	if _guard == null or not navigation_map.is_valid():
		return false
	var patrol_a := patrol_points.get(_guard.patrol_a_id) as Node3D
	var patrol_b := patrol_points.get(_guard.patrol_b_id) as Node3D
	if patrol_a == null or patrol_b == null:
		return false

	var start: Vector3 = NavigationServer3D.map_get_closest_point(
		navigation_map,
		patrol_a.global_position
	)
	var target: Vector3 = NavigationServer3D.map_get_closest_point(
		navigation_map,
		patrol_b.global_position
	)
	if (
		start.distance_to(patrol_a.global_position) > 1.0
		or target.distance_to(patrol_b.global_position) > 1.0
		or start.distance_to(target) < 1.0
	):
		return false

	var query := NavigationPathQueryParameters3D.new()
	query.map = navigation_map
	query.start_position = start
	query.target_position = target
	query.metadata_flags = (
		NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_ALL
	)
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	return (
		result.path.size() >= 2
		and result.path[0].distance_to(start) <= 0.5
		and result.path[result.path.size() - 1].distance_to(target) <= 0.5
	)


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
