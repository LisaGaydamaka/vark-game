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
	NavigationServer3D.map_set_cell_size(
		navigation_map,
		navigation_mesh.cell_size
	)
	navigation_region.navigation_mesh = navigation_mesh

	await get_tree().physics_frame
	await get_tree().physics_frame

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
