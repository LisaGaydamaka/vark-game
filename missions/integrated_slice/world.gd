extends Node3D


signal navigation_rebuilt(serial: int)


@onready var player: CharacterBody3D = $Player
@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var ordinary_door: VarkOrdinaryDoor = $OrdinaryDoor
@onready var guard: VarkGuard = $Guard
@onready var geometry_root: Node3D = $Geometry

var navigation_ready: bool = false
var navigation_rebuild_serial: int = 0
var navigation_errors := PackedStringArray()
var _navigation_mesh: NavigationMesh = null


func _ready() -> void:
	call_deferred("_rebuild_navigation")


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


func get_navigation_debug_summary() -> Dictionary:
	return {
		"ready": navigation_ready,
		"rebuild_serial": navigation_rebuild_serial,
		"errors": navigation_errors.duplicate(),
		"vertex_count": (
			_navigation_mesh.get_vertices().size()
			if _navigation_mesh != null
			else 0
		),
		"polygon_count": (
			_navigation_mesh.get_polygon_count()
			if _navigation_mesh != null
			else 0
		),
		"guard_configured": bool(
			guard.get_debug_summary().get("configured", false)
		) if guard != null else false,
		"door_link": (
			ordinary_door.get_navigation_link_summary()
			if ordinary_door != null
			else {}
		),
	}


func get_slice_debug_summary() -> Dictionary:
	var reaction: Node = guard.get_node_or_null("Reaction") if guard != null else null
	var footsteps: Node = get_node_or_null("FootstepEmitter")
	var exposure: VarkGameplayExposure = get_node_or_null(
		"GameplayExposure"
	) as VarkGameplayExposure
	var objective: VarkSimpleObjectiveState = get_node_or_null(
		"ObjectiveState"
	) as VarkSimpleObjectiveState
	return {
		"navigation": get_navigation_debug_summary(),
		"guard": guard.get_debug_summary() if guard != null else {},
		"reaction": (
			reaction.call("get_debug_summary")
			if reaction != null and reaction.has_method("get_debug_summary")
			else {}
		),
		"footsteps": (
			footsteps.call("get_debug_summary")
			if footsteps != null and footsteps.has_method("get_debug_summary")
			else {}
		),
		"exposure": (
			exposure.get_exposure_summary()
			if exposure != null
			else {}
		),
		"objective": (
			objective.get_debug_summary()
			if objective != null
			else {}
		),
		"door_integration": get_door_integration_debug_summary(),
	}


func get_door_integration_debug_summary() -> Dictionary:
	var propagation := get_node_or_null(
		"AcousticPropagation"
	) as VarkAcousticPropagation
	var reaction: Node = (
		guard.get_node_or_null("Reaction") if guard != null else null
	)
	var guard_summary: Dictionary = (
		guard.get_debug_summary() if guard != null else {}
	)
	var reaction_summary: Dictionary = (
		reaction.call("get_debug_summary")
		if reaction != null and reaction.has_method("get_debug_summary")
		else {}
	)
	var portal_summary: Dictionary = (
		propagation.get_portal_debug_state(&"portal.slice.door")
		if propagation != null
		else {}
	)
	if ordinary_door == null:
		return {
			"configured": false,
			"error": "Integrated Slice has no ordinary door.",
		}
	return {
		"configured": true,
		"persistent_id": ordinary_door.get_persistent_id(),
		"door_id": ordinary_door.door_id,
		"phase": ordinary_door.get_semantic_phase(),
		"open_fraction": ordinary_door.get_open_fraction(),
		"navigation_passage_open": (
			ordinary_door.is_navigation_passage_open()
		),
		"navigation_link": ordinary_door.get_navigation_link_summary(),
		"guard_door_id": guard_summary.get("door_id", ""),
		"guard_door_use_count": guard_summary.get("door_use_count", 0),
		"guard_door_traversal_state": guard_summary.get(
			"door_traversal_state",
			""
		),
		"acoustic_openness": ordinary_door.get_acoustic_openness(),
		"acoustic_portal": portal_summary,
		"vision_blocked": reaction_summary.get(
			"last_vision_blocked",
			false
		),
		"vision_blocker": reaction_summary.get(
			"last_vision_blocker",
			""
		),
		"vision_distance": reaction_summary.get(
			"last_vision_distance",
			0.0
		),
	}


func _rebuild_navigation() -> void:
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
		geometry_root
	)
	if not ordinary_door.configure_navigation_traversal(
		navigation_mesh.agent_radius,
		0.30
	):
		navigation_errors.append(
			"Integrated Slice ordinary door could not configure its navigation link."
		)
		return
	if not ordinary_door.contribute_navigation_bake_cut(source_geometry):
		navigation_errors.append(
			"Integrated Slice ordinary door could not contribute its navigation bake cut."
		)
		return
	NavigationServer3D.bake_from_source_geometry_data(
		navigation_mesh,
		source_geometry
	)
	if navigation_mesh.get_polygon_count() <= 0:
		navigation_errors.append(
			"Integrated Slice navigation bake produced no polygons."
		)
		push_error(navigation_errors[navigation_errors.size() - 1])
		return

	_navigation_mesh = navigation_mesh
	var navigation_map: RID = get_world_3d().navigation_map
	# The Integrated Slice is still the tiny runtime-baked proof world. Keep
	# navigation map/region iteration synchronous here so the explicit door link
	# is finalized against a deterministic carved graph.
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
			"Integrated Slice navigation map did not synchronize the carved region."
		)
		push_error(navigation_errors[navigation_errors.size() - 1])
		return
	var link_iteration_before: int = NavigationServer3D.map_get_iteration_id(
		navigation_map
	)
	if not ordinary_door.finalize_navigation_traversal(navigation_map):
		navigation_errors.append(
			"Integrated Slice ordinary door could not finalize its navigation link on the baked map."
		)
		push_error(navigation_errors[navigation_errors.size() - 1])
		return
	if not await _wait_for_navigation_map_iteration(
		navigation_map,
		link_iteration_before,
		120
	):
		navigation_errors.append(
			"Integrated Slice navigation map did not synchronize the finalized ordinary-door link."
		)
		push_error(navigation_errors[navigation_errors.size() - 1])
		return

	var patrol_points: Dictionary = {
		"slice.patrol.a": $PatrolA,
		"slice.patrol.b": $PatrolB,
	}
	if not guard.configure_patrol(patrol_points, ordinary_door):
		navigation_errors.append(
			str(guard.get_debug_summary().get("last_error", ""))
		)
		push_error(navigation_errors[navigation_errors.size() - 1])
		return

	navigation_rebuild_serial += 1
	navigation_ready = true
	navigation_rebuilt.emit(navigation_rebuild_serial)
