extends Node3D


signal navigation_rebuilt(serial: int)


const PLAYER_START_GROUP: StringName = &"vark_player_start"
const PATROL_POINT_GROUP: StringName = &"vark_patrol_point"
const GUARD_GROUP: StringName = &"vark_guard"

@onready var player: Node3D = $Player
@onready var func_map: FuncGodotMap = $FuncGodotMap
@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var ordinary_door: VarkOrdinaryDoor = $OrdinaryDoor

var mission_definition: Resource = null
var selected_player_start: Node3D = null
var navigation_ready: bool = false
var navigation_rebuild_serial: int = 0
var navigation_errors := PackedStringArray()
var _navigation_mesh: NavigationMesh = null


func configure_mission_definition(definition: Resource) -> bool:
	if is_inside_tree() or definition == null:
		return false
	mission_definition = definition
	return true


func _ready() -> void:
	assert(
		mission_definition != null,
		"The Guard/Nav Lab must be instantiated through its MissionDefinition."
	)
	func_map.local_map_file = str(mission_definition.get("map_source_path"))
	func_map.build()
	_apply_authored_player_start()
	call_deferred("_rebuild_navigation_from_imported_geometry")


func get_navigation_debug_summary() -> Dictionary:
	return {
		"ready": navigation_ready,
		"rebuild_serial": navigation_rebuild_serial,
		"errors": navigation_errors.duplicate(),
		"vertex_count": _navigation_mesh.get_vertices().size() if _navigation_mesh != null else 0,
		"polygon_count": _navigation_mesh.get_polygon_count() if _navigation_mesh != null else 0,
		"map_source_path": func_map.local_map_file,
	}


func _rebuild_navigation_from_imported_geometry() -> void:
	navigation_ready = false
	navigation_errors.clear()

	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_radius = 0.30
	navigation_mesh.agent_height = 1.75
	navigation_mesh.agent_max_climb = 0.30
	navigation_mesh.agent_max_slope = 45.0
	navigation_mesh.sample_partition_type = NavigationMesh.SAMPLE_PARTITION_MONOTONE
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	navigation_mesh.geometry_collision_mask = 1

	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, source_geometry, func_map)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source_geometry)

	if navigation_mesh.get_polygon_count() <= 0:
		navigation_errors.append(
			"Navigation bake produced no polygons from imported FuncGodot static geometry."
		)
		push_error(navigation_errors[navigation_errors.size() - 1])
		return

	_navigation_mesh = navigation_mesh
	navigation_region.navigation_mesh = navigation_mesh

	# NavigationServer changes synchronize on physics frames. Bind the first
	# consumer only after the new region is visible on the default World3D map.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var patrol_points: Dictionary = {}
	var guards: Array[VarkGuard] = []
	for node: Node in func_map.find_children("*", "", true, false):
		if node.is_in_group(PATROL_POINT_GROUP):
			var patrol_point := node as VarkPatrolPoint
			if patrol_point == null or patrol_point.patrol_id.strip_edges().is_empty():
				navigation_errors.append("Guard/Nav Lab contains an invalid authored patrol point.")
				continue
			if patrol_points.has(patrol_point.patrol_id):
				navigation_errors.append(
					"Duplicate patrol_id '%s' in Guard/Nav Lab." % patrol_point.patrol_id
				)
				continue
			patrol_points[patrol_point.patrol_id] = patrol_point
		elif node.is_in_group(GUARD_GROUP):
			var guard := node as VarkGuard
			if guard != null:
				guards.append(guard)

	if guards.size() != 1:
		navigation_errors.append(
			"Guard/Nav Lab expected exactly one authored guard, found %d." % guards.size()
		)
	else:
		var guard: VarkGuard = guards[0]
		if guard.door_id != str(ordinary_door.door_id):
			navigation_errors.append(
				"Guard door_id '%s' does not match ordinary door '%s'."
				% [guard.door_id, ordinary_door.door_id]
			)
		elif not guard.configure_patrol(patrol_points, ordinary_door):
			navigation_errors.append(str(guard.get_debug_summary().get("last_error", "")))

	if not navigation_errors.is_empty():
		for error_message: String in navigation_errors:
			push_error(error_message)
		return

	navigation_rebuild_serial += 1
	navigation_ready = true
	navigation_rebuilt.emit(navigation_rebuild_serial)


func _apply_authored_player_start() -> void:
	var selector: String = str(mission_definition.get("player_start_selector")).strip_edges()
	var matching_starts: Array[Node] = []
	for node: Node in func_map.find_children("*", "", true, false):
		if not node.is_in_group(PLAYER_START_GROUP):
			continue
		if not node.has_method("get_content_id"):
			continue
		if str(node.call("get_content_id")).strip_edges() != selector:
			continue
		matching_starts.append(node)

	if matching_starts.size() != 1:
		push_error(
			"Guard/Nav Lab player_start_selector '%s' resolved to %d starts; expected exactly one."
			% [selector, matching_starts.size()]
		)
		return

	var start := matching_starts[0] as Node3D
	if start == null:
		push_error("Guard/Nav Lab selected player start is not Node3D.")
		return

	selected_player_start = start
	player.global_transform = start.global_transform
