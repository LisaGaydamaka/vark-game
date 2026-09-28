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
const LEDGE_STATIC_SHADOW_RENDER_LAYER: int = 19
const LEDGE_STATIC_SHADOW_RENDER_MASK: int = 1 << (
	LEDGE_STATIC_SHADOW_RENDER_LAYER - 1
)
const LEDGE_SHADOW_ATLAS_SIZE: int = 2048
const LEDGE_SHADOW_ATLAS_SUBDIV: Viewport.PositionalShadowAtlasQuadrantSubdiv = (
	Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
)


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
		and int(Definition.get("mission_content_revision")) == 9,
		"8.4 Ledge City revision 9 owns a distinct save identity after rear-lane floor completion and inward sneak-window swing correction"
	)

	var source: String = FileAccess.get_file_as_string(MAP_PATH)
	var face_audit: Dictionary = _audit_source_face_materials(source)
	var brush_bounds: Array[AABB] = _worldspawn_brush_bounds(source)
	var source_clearances_valid: bool = not _any_positive_overlap(
		brush_bounds,
		AABB(Vector3(-28, -438, 2), Vector3(56, 876, 70))
	)
	for aperture: AABB in [
		# Six ground doors.
		AABB(Vector3(-117, 280, 2), Vector3(6, 40, 64)),
		AABB(Vector3(111, 280, 2), Vector3(6, 40, 64)),
		AABB(Vector3(-117, 30, 2), Vector3(6, 40, 64)),
		AABB(Vector3(111, 30, 2), Vector3(6, 40, 64)),
		AABB(Vector3(111, -290, 2), Vector3(6, 40, 64)),
		AABB(Vector3(-117, -290, 2), Vector3(6, 40, 64)),
		# Six upper crouch windows plus the Archive high window.
		AABB(Vector3(-117, 215, 98), Vector3(6, 40, 35.5)),
		AABB(Vector3(111, 215, 98), Vector3(6, 40, 35.5)),
		AABB(Vector3(-117, 88, 98), Vector3(6, 40, 35.5)),
		AABB(Vector3(111, 88, 98), Vector3(6, 40, 35.5)),
		AABB(Vector3(-117, -348, 98), Vector3(6, 40, 35.5)),
		AABB(Vector3(111, -348, 98), Vector3(6, 40, 35.5)),
		AABB(Vector3(-117, -290, 186), Vector3(6, 40, 35.5)),
	]:
		if _any_positive_overlap(brush_bounds, aperture):
			source_clearances_valid = false
			break
	assert_true.call(
		bool(face_audit.get("valid", false))
		and int(face_audit.get("face_count", 0)) >= 1800
		and source_clearances_valid
		and not _has_positive_pair_overlap(brush_bounds)
		and source.count("// building_floor:") == 6
		and source.count("// interior_stair:") == 83
		and source.count("// sloped_roof:") == 12
		and source.count("// timber_tie:") == 2
		and source.count("// supported_bay:") == 18
		and source.count("// supported_upper_bay:") == 3
		and source.count("// supported_terrace:") == 28
		and source.count("// overstreet:") == 10
		and source.count("// alley_bridge:") == 8
		and source.count("// back_valley_floor:") == 4
		and source.count("// room_wall:") == 14
		and source.count("// partition:") == 18
		and source.count("// balcony:") == 0
		and source.count("// window_sill:") == 0
		and _all_stair_landings_connect(source)
		and _all_upper_floor_coverage_complete(source)
		and _all_structural_extensions_connected(source)
		and _all_named_solid_brushes_face_connected(source)
		and _all_outdoor_ground_coverage_complete(source)
		and _all_opening_frames_seat_leaf(source)
		and _all_sneak_window_clearances_are_crouch_only(source)
		and not source.contains("zebra/zebra16x16")
		and not source.contains("WallLamp.tscn")
		and not source.contains("// platform:")
		and not source.contains("// west_route:")
		and not source.contains("// east_route:"),
		"8.4 all 329 solid map brushes are non-overlapping and face-connected; the full rear/end outdoor ground is tiled to the inner boundary, stairs/floors remain joined, and exact-fit opening frames stay aligned"
	)

	var root_viewport := tree.get_root() as Viewport
	var previous_shadow_atlas_size: int = root_viewport.positional_shadow_atlas_size
	var previous_shadow_atlas_16_bits: bool = (
		root_viewport.positional_shadow_atlas_16_bits
	)
	var previous_shadow_subdivisions: Array[int] = []
	for quadrant: int in 4:
		previous_shadow_subdivisions.append(
			int(root_viewport.get_positional_shadow_atlas_quadrant_subdiv(quadrant))
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
	var acoustic_spaces: Array[Node] = []
	var acoustic_portals: Array[Node] = []
	var door_frames: Array[Node] = []
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
		if node is VarkAcousticSpace:
			acoustic_spaces.append(node)
		if node is VarkAcousticPortal:
			acoustic_portals.append(node)
		if node.is_in_group(&"vark_door_frame"):
			door_frames.append(node)

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
		and openings.size() == 13
		and pickups.size() == 4
		and markers.size() >= 33
		and surfaces.size() == 33
		and acoustic_spaces.size() == 46
		and acoustic_portals.size() == 58
		and door_frames.size() == 1
		and _count_direct_collision_shapes(worldspawn) >= 280
		and _count_direct_collision_shapes(door_frames[0]) >= 1,
		"8.4 compact city keeps every representative gameplay role, four added rear/end floor surface regions, four explicit corner acoustic links, and the 39 exact-fit jamb/header brushes"
	)

	var shadow_budget_state: Dictionary = (
		world.call("get_shadow_budget_debug_state")
		if world.has_method("get_shadow_budget_debug_state")
		else {}
	)
	var atlas_layout_valid: bool = (
		bool(shadow_budget_state.get("active", false))
		and bool(shadow_budget_state.get("atlas_requested", false))
		and int(shadow_budget_state.get("desired_atlas_size", 0))
			== LEDGE_SHADOW_ATLAS_SIZE
		and int(shadow_budget_state.get("desired_atlas_subdiv", -1))
			== int(LEDGE_SHADOW_ATLAS_SUBDIV)
	)
	if bool(shadow_budget_state.get("atlas_applied", false)):
		atlas_layout_valid = (
			atlas_layout_valid
			and root_viewport.positional_shadow_atlas_size
				== LEDGE_SHADOW_ATLAS_SIZE
			and root_viewport.positional_shadow_atlas_16_bits
		)
		for quadrant: int in 4:
			atlas_layout_valid = (
				atlas_layout_valid
				and root_viewport.get_positional_shadow_atlas_quadrant_subdiv(
					quadrant
				) == LEDGE_SHADOW_ATLAS_SUBDIV
			)

	var world_shadow_meshes: Array[MeshInstance3D] = []
	if worldspawn != null:
		for node: Node in worldspawn.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh != null:
				world_shadow_meshes.append(mesh)
	var static_shadow_layers_valid: bool = not world_shadow_meshes.is_empty()
	for mesh: MeshInstance3D in world_shadow_meshes:
		static_shadow_layers_valid = (
			static_shadow_layers_valid
			and mesh.get_layer_mask_value(LEDGE_STATIC_SHADOW_RENDER_LAYER)
		)

	var opening_shadow_layers_valid: bool = true
	for opening: Node in openings:
		var door_mesh := opening.get_node_or_null("DoorMesh") as MeshInstance3D
		if (
			door_mesh == null
			or not door_mesh.get_layer_mask_value(
				LEDGE_STATIC_SHADOW_RENDER_LAYER
			)
		):
			opening_shadow_layers_valid = false
			break

	var frame_shadow_layers_valid: bool = door_frames.size() == 1
	if frame_shadow_layers_valid:
		var frame_meshes: Array[Node] = door_frames[0].find_children(
			"*",
			"MeshInstance3D",
			true,
			false
		)
		frame_shadow_layers_valid = not frame_meshes.is_empty()
		for frame_mesh_node: Node in frame_meshes:
			var frame_mesh := frame_mesh_node as MeshInstance3D
			if (
				frame_mesh == null
				or not frame_mesh.get_layer_mask_value(
					LEDGE_STATIC_SHADOW_RENDER_LAYER
				)
			):
				frame_shadow_layers_valid = false
				break

	var dynamic_shadow_layers_excluded: bool = true
	for prop: Node in props:
		var prop_mesh := prop.get_node_or_null("PropMesh") as MeshInstance3D
		if (
			prop_mesh == null
			or prop_mesh.get_layer_mask_value(
				LEDGE_STATIC_SHADOW_RENDER_LAYER
			)
		):
			dynamic_shadow_layers_excluded = false
			break
	var guard_shadow_mesh := (
		(guards[0] as Node).get_node_or_null("GuardMesh") as MeshInstance3D
		if guards.size() == 1 else null
	)
	dynamic_shadow_layers_excluded = (
		dynamic_shadow_layers_excluded
		and guard_shadow_mesh != null
		and not guard_shadow_mesh.get_layer_mask_value(
			LEDGE_STATIC_SHADOW_RENDER_LAYER
		)
	)

	var light_shadow_masks_valid: bool = true
	for light: Node in lights:
		var gameplay_light := light as VarkGameplayLight
		var emitter := (
			gameplay_light.get_emitter()
			if gameplay_light != null else null
		)
		if (
			gameplay_light == null
			or emitter == null
			or gameplay_light.get_visual_shadow_caster_mask()
				!= LEDGE_STATIC_SHADOW_RENDER_MASK
			or emitter.shadow_caster_mask != LEDGE_STATIC_SHADOW_RENDER_MASK
		):
			light_shadow_masks_valid = false
			break
	assert_true.call(
		atlas_layout_valid
		and static_shadow_layers_valid
		and opening_shadow_layers_valid
		and frame_shadow_layers_valid
		and dynamic_shadow_layers_excluded
		and light_shadow_masks_valid,
		"8.4 Ledge City bounds positional-shadow churn: rendered runtimes request a fixed 2048/16-slot atlas, static architecture/openings cast, and continuously moving guard/props do not invalidate 23 omni shadow caches"
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

	var world_material_metadata: Dictionary = _audit_func_godot_surface_metadata(
		worldspawn
	)
	var frame_material_metadata: Dictionary = _audit_func_godot_surface_metadata(
		door_frames[0] as CollisionObject3D
		if door_frames.size() == 1 else null
	)
	assert_true.call(
		bool(world_material_metadata.get("ok", false))
		and bool(frame_material_metadata.get("ok", false))
		and int(world_material_metadata.get("shape_count", 0)) >= 280,
		"8.4 every imported solid map collision shape carries face texture metadata so footsteps can resolve the rendered stone/tile/carpet plane directly; world=%s frame=%s"
		% [str(world_material_metadata), str(frame_material_metadata)]
	)

	var acoustic_propagation := world.get_node_or_null(
		"AcousticPropagation"
	) as VarkAcousticPropagation
	var acoustic_summary: Dictionary = (
		acoustic_propagation.get_debug_summary()
		if acoustic_propagation != null else {}
	)
	var acoustic_ids: Dictionary = {}
	for acoustic_space: Node in acoustic_spaces:
		acoustic_ids[str(acoustic_space.get("space_id"))] = true
	assert_true.call(
		acoustic_propagation != null
		and acoustic_propagation.is_configured()
		and acoustic_propagation.has_topology()
		and int(acoustic_summary.get("space_count", 0)) == 46
		and int(acoustic_summary.get("portal_count", 0)) == 58
		and int(acoustic_summary.get("door_count", 0)) == 13
		and not acoustic_ids.has("space.rep.main")
		and acoustic_ids.has("space.mercer.g.rear")
		and acoustic_ids.has("space.mercer.g.front")
		and acoustic_ids.has("space.mercer.stair")
		and acoustic_ids.has("space.archive.u.front")
		and acoustic_ids.has("space.ext.street_mercer")
		and (acoustic_summary.get("errors", PackedStringArray()) as PackedStringArray).is_empty(),
		"8.4 acoustics are room/stair/exterior authored topology rather than one city-sized acoustic box"
	)

	if acoustic_propagation != null:
		var room_route: Dictionary = acoustic_propagation.evaluate(
			_map_origin_to_world(Vector3(-300, 220, 20)),
			1.0,
			_map_origin_to_world(Vector3(-300, 320, 20))
		)
		var stair_route: Dictionary = acoustic_propagation.evaluate(
			_map_origin_to_world(Vector3(-300, 220, 20)),
			1.0,
			_map_origin_to_world(Vector3(-300, 220, 120))
		)
		var stair_identity: Dictionary = acoustic_propagation.evaluate(
			_map_origin_to_world(Vector3(-250, 218, 64)),
			1.0,
			_map_origin_to_world(Vector3(-250, 218, 72))
		)
		var office_front_identity: Dictionary = acoustic_propagation.evaluate(
			_map_origin_to_world(Vector3(-200, 108, 116)),
			1.0,
			_map_origin_to_world(Vector3(-190, 116, 116))
		)
		assert_true.call(
			bool(room_route.get("route_found", false))
			and (room_route.get("portal_route", []) as Array)
				== [&"portal.room.mercer.g"]
			and bool(stair_route.get("route_found", false))
			and (stair_route.get("portal_route", []) as Array)
				== [
					&"portal.stair.mercer.bottom",
					&"portal.stair.mercer.top",
				]
			and stair_identity.get("source_space_id", "")
				== "space.mercer.stair"
			and stair_identity.get("listener_space_id", "")
				== "space.mercer.stair"
			and office_front_identity.get("source_space_id", "")
				== "space.office.u.front"
			and office_front_identity.get("listener_space_id", "")
				== "space.office.u.front",
			"8.4 sound assigns ordinary room points to their room, stair-shaft points to the nested stair space, and crosses only authored room/stair portals"
		)

	var expected_openings: Dictionary = {
		"door.mercer.front": Vector3(-110, 320.8, 0),
		"door.watchmaker.front": Vector3(110, 279.2, 0),
		"door.office.front": Vector3(-110, 70.8, 0),
		"door.tenement.front": Vector3(110, 29.2, 0),
		"door.foundry.front": Vector3(110, -290.8, 0),
		"door.east_locked": Vector3(-110, -249.2, 0),
		"window.mercer.upper": Vector3(-110, 255.8, 96),
		"window.watchmaker.upper": Vector3(110, 214.2, 96),
		"window.office.upper": Vector3(-110, 128.8, 96),
		"window.tenement.upper": Vector3(110, 87.2, 96),
		"window.archive.level2": Vector3(-110, -307.2, 96),
		"window.foundry.upper": Vector3(110, -348.8, 96),
		"opening.window_west": Vector3(-110, -249.2, 184),
	}
	var expected_opening_yaws: Dictionary = {
		"door.mercer.front": 180.0,
		"door.watchmaker.front": 0.0,
		"door.office.front": 180.0,
		"door.tenement.front": 0.0,
		"door.foundry.front": 0.0,
		"door.east_locked": 180.0,
		"window.mercer.upper": 180.0,
		"window.watchmaker.upper": 0.0,
		"window.office.upper": 180.0,
		"window.tenement.upper": 0.0,
		"window.archive.level2": 180.0,
		"window.foundry.upper": 0.0,
		"opening.window_west": 180.0,
	}
	var opening_positions_valid: bool = true
	for door_id: String in expected_openings:
		var opening := _find_by_property(openings, "door_id", door_id) as Node3D
		if (
			opening == null
			or opening.global_position.distance_to(
				_map_origin_to_world(expected_openings[door_id] as Vector3)
			) > 0.02
			or absf(
				wrapf(opening.rotation_degrees.y, 0.0, 360.0)
				- float(expected_opening_yaws[door_id])
			) > 0.02
		):
			opening_positions_valid = false
			break
	var window: Node = _find_by_property(
		openings,
		"door_id",
		"opening.window_west"
	)
	var window_geometry_valid: bool = true
	var window_count: int = 0
	for opening_node: Node in openings:
		if str(opening_node.get("opening_variant")) != "sneak_window":
			continue
		window_count += 1
		var window_collision := opening_node.get_node_or_null(
			"CollisionShape3D"
		) as CollisionShape3D
		var window_box := (
			window_collision.shape as BoxShape3D
			if window_collision != null else null
		)
		var window_mesh := opening_node.get_node_or_null(
			"DoorMesh"
		) as MeshInstance3D
		var window_mesh_bounds: AABB = (
			window_mesh.mesh.get_aabb()
			if window_mesh != null and window_mesh.mesh != null
			else AABB()
		)
		var window_nav: Dictionary = opening_node.call(
			"get_navigation_link_summary"
		)
		if (
			window_box == null
			or not is_equal_approx(window_box.size.x, 1.30)
			or not is_equal_approx(window_box.size.y, 1.18)
			or not is_equal_approx(window_collision.position.y, 0.59)
			or not is_equal_approx(window_mesh_bounds.size.x, 1.30)
			or not is_equal_approx(window_mesh_bounds.size.y, 1.18)
			or not is_equal_approx(float(opening_node.get("open_angle_degrees")), -90.0)
			or bool(window_nav.get("configured", true))
			or bool(window_nav.get("map_bound", true))
		):
			window_geometry_valid = false
			break
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
		and window_count == 7
		and window_geometry_valid
		and window != null
		and str(window.get("opening_variant")) == "sneak_window"
		and locked_door != null
		and bool(access.get("locked", false))
		and str(access.get("required_key_id", "")) == "key.service",
		"8.4 all six ordinary doors plus seven crouch-height windows place their hinge root on the façade face, mirror east/west yaw correctly, and keep shared opening ownership"
	)

	var opening_sweeps_valid: bool = true
	var opening_sweep_failure: Dictionary = {}
	for opening_node: Node in openings:
		var sweep_opening := opening_node as VarkOrdinaryDoor
		if not _opening_completes_real_sweep(sweep_opening):
			opening_sweeps_valid = false
			opening_sweep_failure = {
				"door_id": str(opening_node.get("door_id")),
				"origin": (sweep_opening.global_position if sweep_opening != null else Vector3.ZERO),
				"phase": (sweep_opening.get_semantic_phase() if sweep_opening != null else &""),
				"fraction": (sweep_opening.get_open_fraction() if sweep_opening != null else -1.0),
				"blocked": (sweep_opening.is_motion_blocked() if sweep_opening != null else true),
			}
			break
	assert_true.call(
		opening_sweeps_valid,
		"8.4 every exact-fit door/window completes a real collision-authoritative 0→90 degree hinge sweep without widening the authored frame; failure=%s"
		% str(opening_sweep_failure)
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
			_map_origin_to_world(Vector3(260, 304.88, 100.48))
		) <= 0.02
		and silver_pickup != null
		and silver_pickup.global_position.distance_to(
			_map_origin_to_world(Vector3(260, 315.12, 99.84))
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

	var physical_positions_valid: bool = true
	var expected_prop_origins: Dictionary = {
		"prop.rep.route_crate": Vector3(-42, 348, 9.6),
		"prop.rep.climb_crate": Vector3(42, 285, 9.6),
		"prop.rep.distraction": Vector3(52, 20, 9.6),
		"prop.rep.hide_cover": Vector3(-275, 60, 9.6),
		"prop.rep.archive_cover": Vector3(-255, -245, 9.6),
	}
	for prop_id: String in expected_prop_origins:
		var prop := _find_by_property(props, "prop_id", prop_id) as Node3D
		if (
			prop == null
			or prop.global_position.distance_to(
				_map_origin_to_world(expected_prop_origins[prop_id] as Vector3)
			) > 0.02
		):
			physical_positions_valid = false
			break
	var switch_node := switches[0] as Node3D if switches.size() == 1 else null
	var guard_node := guards[0] as Node3D if guards.size() == 1 else null
	assert_true.call(
		physical_positions_valid
		and switch_node != null
		and switch_node.global_position.distance_to(
			_map_origin_to_world(Vector3(-122.2, 28, 42))
		) <= 0.02
		and guard_node != null
		and guard_node.global_position.distance_to(
			_map_origin_to_world(Vector3(0, 80, 0))
		) <= 0.02,
		"8.4 crates sit exactly on floors, the wall switch clears its facade, and the guard starts farther from the player"
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
	var expected_street_origins: Dictionary = {
		"light.rep.south": Vector3(-86, 405, 0),
		"light.rep.market": Vector3(60, 255, 0),
		"light.rep.cross": Vector3(-60, 125, 0),
		"light.rep.mid": Vector3(86, -65, 0),
		"light.rep.archive": Vector3(-86, -205, 0),
		"light.rep.north": Vector3(86, -405, 0),
		"light.rep.rear_w_south": Vector3(-372, 320, 0),
		"light.rep.rear_w_north": Vector3(-372, -275, 0),
		"light.rep.rear_e_south": Vector3(372, 275, 0),
		"light.rep.rear_e_north": Vector3(372, -330, 0),
	}
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
			var expected_street_origin: Vector3 = expected_street_origins.get(
				required_id,
				Vector3(INF, INF, INF)
			)
			var street_light_node := light as Node3D
			if (
				street_light_node == null
				or street_light_node.global_position.distance_to(
					_map_origin_to_world(expected_street_origin)
				) > 0.02
			):
				light_ids_valid = false
				break
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
		and is_equal_approx(emitter_local.y, -0.38)
		and int(lantern_summary.get("collision_shape_count", 0)) == 8
		and int(lantern_summary.get("exposure_occluder_shape_count", 0)) == 1
		and interior_light.get_emitter() is OmniLight3D
		and is_equal_approx(float(interior_light.get("omni_range")), 3.4),
		"8.4 rooms use short ceiling-hung omni lanterns with an open lower frame while streets keep freestanding omni lamps"
	)

	var guard := guards[0] as VarkGuard if guards.size() == 1 else null
	var awareness: Node = (
		guard.get_node_or_null("Awareness")
		if guard != null else null
	)
	# This is a patrol-geometry proof, not an awareness proof. Disable the two
	# player-driven perception producers before the world enters PLAYING so the
	# nearby spawn cannot inject an investigate/stare goal while nav settles.
	if awareness != null:
		awareness.set_physics_process(false)
	var footstep_emitter := world.get_node_or_null("FootstepEmitter")
	var player := world.get_node_or_null("Player") as CharacterBody3D
	var surface_sample_failures: Array[Dictionary] = []
	if footstep_emitter != null and player != null:
		var original_player_transform: Transform3D = player.global_transform
		for sample: Dictionary in [
			{
				"label": "Mercer carpet ground floor",
				"map_position": Vector3(-200.0, 300.0, 0.0),
				"expected": "carpet",
			},
			{
				"label": "Watchmaker tile ground floor",
				"map_position": Vector3(200.0, 300.0, 0.0),
				"expected": "tile",
			},
			{
				"label": "Mercer stone terrace (old carpet-volume mismatch)",
				"map_position": Vector3(-93.5, 234.5, 96.0),
				"expected": "stone",
			},
			{
				"label": "Archive upper carpet stair (old tile-volume mismatch)",
				"map_position": Vector3(-162.5, -219.5, 120.0),
				"expected": "carpet",
			},
			{
				"label": "Mercer over-street stone floor (previously unowned)",
				"map_position": Vector3(-91.5, 322.5, 96.0),
				"expected": "stone",
			},
			{
				"label": "West alley stone bridge (previously unowned)",
				"map_position": Vector3(-285.5, 160.5, 96.0),
				"expected": "stone",
			},
		]:
			player.global_position = _map_origin_to_world(
				sample.get("map_position", Vector3.ZERO) as Vector3
			)
			var resolved: Dictionary = footstep_emitter.call(
				"get_current_surface_debug"
			)
			if (
				str(resolved.get("surface_id", "")) != str(sample.get("expected", ""))
				or str(resolved.get("resolution_source", ""))
					!= "func_godot_material"
			):
				surface_sample_failures.append({
					"sample": sample,
					"resolved": resolved,
					"ray": _debug_surface_ray(player),
				})
		player.global_transform = original_player_transform
	assert_true.call(
		footstep_emitter != null
		and player != null
		and surface_sample_failures.is_empty(),
		"8.4 representative material probes resolve footstep sound from the exact rendered plane, including former terrace/stair mismatches and previously unowned elevated floors; failures=%s"
		% str(surface_sample_failures)
	)

	var debug_meters := world.get_node_or_null("StealthDebugMeters")
	var exposure_node := world.get_node_or_null(
		"GameplayExposure"
	) as VarkGameplayExposure
	if footstep_emitter != null and debug_meters != null:
		footstep_emitter.emit_signal(
			"gameplay_noise_emitted",
			{
				"last_strength": 0.62,
				"last_surface_id": &"stone",
				"last_gait": "walking",
				"last_sound_kind": &"footstep.stone",
			}
		)
	var meter_state: Dictionary = (
		debug_meters.call("get_debug_state")
		if debug_meters != null else {}
	)
	var light_meter := (
		debug_meters.find_child("LightMeter", true, false) as ProgressBar
		if debug_meters != null else null
	)
	var sound_meter := (
		debug_meters.find_child("SoundMeter", true, false) as ProgressBar
		if debug_meters != null else null
	)
	var meters_valid: bool = (
		debug_meters != null
		and exposure_node != null
		and bool(meter_state.get("exposure_connected", false))
		and bool(meter_state.get("sound_connected", false))
		and is_equal_approx(
			float(meter_state.get("light_exposure", -1.0)),
			exposure_node.get_current_exposure()
		)
		and is_equal_approx(
			float(meter_state.get("last_sound_strength", -1.0)),
			0.62
		)
		and is_equal_approx(
			float(meter_state.get("sound_display_strength", -1.0)),
			0.62
		)
		and str(meter_state.get("last_surface_id", "")) == "stone"
		and str(meter_state.get("last_gait", "")) == "walking"
		and bool(meter_state.get("ui_ready", false))
		and light_meter != null
		and sound_meter != null
	)
	if not meters_valid:
		print(
			"8.4 stealth debug meter diagnostics: ",
			{
				"meter_state": meter_state,
				"debug_meters": str(debug_meters),
				"exposure_node": str(exposure_node),
				"footstep_emitter": str(footstep_emitter),
				"light_meter": str(light_meter),
				"sound_meter": str(sound_meter),
			}
		)
	assert_true.call(
		meters_valid,
		"8.4 stealth debug HUD reads live gameplay exposure and reacts to the real player-noise signal"
	)
	if footstep_emitter != null:
		footstep_emitter.set_physics_process(false)

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

	var ordinary_links_valid: bool = nav_ready
	var ordinary_link_count: int = 0
	var ordinary_link_failure: Dictionary = {}
	for opening_node: Node in openings:
		if str(opening_node.get("opening_variant")) == "sneak_window":
			continue
		var ordinary := opening_node as VarkOrdinaryDoor
		if ordinary == null:
			continue
		ordinary_link_count += 1
		var link_summary: Dictionary = ordinary.get_navigation_link_summary()
		var cut_half_depth: float = float(
			link_summary.get("bake_cut_half_depth", 0.0)
		)
		var clearance: float = float(link_summary.get("clearance", 0.0))
		var start: Vector3 = link_summary.get("start", Vector3.ZERO)
		var end: Vector3 = link_summary.get("end", Vector3.ZERO)
		var frame: Dictionary = ordinary.get_navigation_doorway_frame()
		var center: Vector3 = frame.get("center", ordinary.global_position)
		var normal: Vector3 = frame.get("normal", Vector3.ZERO)
		var start_side: float = (start - center).dot(normal)
		var end_side: float = (end - center).dot(normal)
		if (
			not bool(link_summary.get("configured", false))
			or not bool(link_summary.get("map_bound", false))
			or clearance <= cut_half_depth
			or clearance - cut_half_depth < 0.30
			or start.distance_to(end) <= 0.10
			or start_side * end_side >= 0.0
		):
			ordinary_links_valid = false
			ordinary_link_failure = {
				"door_id": str(ordinary.door_id),
				"summary": link_summary,
				"start_side": start_side,
				"end_side": end_side,
			}
			break
	assert_true.call(
		ordinary_links_valid
		and ordinary_link_count == 6,
		"8.4 all six ordinary door smart links finalize on opposite baked sides with their approach endpoints outside the swept-leaf carve; failure=%s"
		% str(ordinary_link_failure)
	)

	var sneak_windows: Dictionary = {
		"window.mercer.upper": Vector3(-114, 235, 96),
		"window.watchmaker.upper": Vector3(114, 235, 96),
		"window.office.upper": Vector3(-114, 108, 96),
		"window.tenement.upper": Vector3(114, 108, 96),
		"window.archive.level2": Vector3(-114, -328, 96),
		"window.foundry.upper": Vector3(114, -328, 96),
		"opening.window_west": Vector3(-114, -270, 184),
	}
	var sneak_windows_valid: bool = true
	var sneak_window_failure: Dictionary = {}
	for window_id: String in sneak_windows:
		var sneak_window := _find_by_property(
			openings,
			"door_id",
			window_id
		) as VarkOrdinaryDoor
		var exterior_interaction_opens: bool = (
			await _sneak_window_opens_away_from_exterior_probe(
				world,
				tree,
				sneak_window,
				sneak_windows[window_id] as Vector3
			)
			if sneak_window != null else false
		)
		var opened: bool = (
			sneak_window != null
			and sneak_window.apply_semantic_state({
				"phase": VarkOrdinaryDoor.PHASE_OPEN,
				"open_fraction": 1.0,
				"motion_blocked": false,
				"locked": false,
				"barred": false,
			})
		)
		var crouched_traverses: bool = (
			_capsule_traverses_map_aperture(
				world,
				sneak_window,
				sneak_windows[window_id] as Vector3,
				0.95
			)
			if opened else false
		)
		if not exterior_interaction_opens or not opened or not crouched_traverses:
			sneak_windows_valid = false
			sneak_window_failure = {
				"window_id": window_id,
				"exterior_interaction_opens": exterior_interaction_opens,
				"opened": opened,
				"crouched_traverses": crouched_traverses,
				"origin": (
					sneak_window.global_position
					if sneak_window != null else Vector3.ZERO
				),
			}
			break
	assert_true.call(
		sneak_windows_valid,
		"8.4 every sneak window opens inward through ordinary interaction with a crouched exterior body clear of the swing, then physically admits the accepted 0.95 m crouched capsule; failure=%s"
		% str(sneak_window_failure)
	)

	if acoustic_propagation != null:
		var mercer_window := _find_by_property(
			openings,
			"door_id",
			"window.mercer.upper"
		) as VarkOrdinaryDoor
		var open_window_route: Dictionary = acoustic_propagation.evaluate(
			_map_origin_to_world(Vector3(-130, 235, 116)),
			1.0,
			_map_origin_to_world(Vector3(-90, 235, 116))
		)
		var open_window_strength: float = float(
			open_window_route.get("propagated_strength", 0.0)
		)
		var closed_window_strength: float = 0.0
		if mercer_window != null:
			mercer_window.apply_semantic_state({
				"phase": VarkOrdinaryDoor.PHASE_CLOSED,
				"open_fraction": 0.0,
				"motion_blocked": false,
				"locked": false,
				"barred": false,
			})
			var closed_window_route: Dictionary = acoustic_propagation.evaluate(
				_map_origin_to_world(Vector3(-130, 235, 116)),
				1.0,
				_map_origin_to_world(Vector3(-90, 235, 116))
			)
			closed_window_strength = float(
				closed_window_route.get("propagated_strength", 0.0)
			)
		assert_true.call(
			bool(open_window_route.get("route_found", false))
			and (open_window_route.get("portal_route", []) as Array)
				== [&"portal.window.mercer"]
			and closed_window_strength > 0.0
			and open_window_strength > closed_window_strength * 2.0,
			"8.4 the same ordinary window state that opens the sneak passage also opens its room-to-street acoustic portal"
		)

	var physical_roots: Array[Node] = []
	physical_roots.append_array(openings)
	physical_roots.append_array(pickups)
	physical_roots.append_array(containers)
	physical_roots.append_array(guards)
	physical_roots.append_array(props)
	physical_roots.append_array(lights)
	physical_roots.append_array(switches)
	var overlap_audit: Dictionary = _audit_runtime_physical_overlaps(
		world,
		physical_roots
	)
	assert_true.call(
		bool(overlap_audit.get("ok", false)),
		"8.4 all shrunken real physical point-entity colliders are clear of world brushes and each other; audit=%s"
		% str(overlap_audit)
	)

	var downward_sample: Dictionary = {}
	if interior_light != null:
		var emitter_position: Vector3 = interior_light.get_emitter_global_position()
		downward_sample = interior_light.sample_gameplay_exposure(
			emitter_position + Vector3.DOWN * 0.75,
			world.get_world_3d().direct_space_state
		)
	assert_true.call(
		not downward_sample.is_empty()
		and not bool(downward_sample.get("occluded", true))
		and float(downward_sample.get("contribution", 0.0)) > 0.0,
		"8.4 hanging lantern has a physically clear downward light path through its open bottom frame; sample=%s"
		% str(downward_sample)
	)

	var began_playing: bool = bool(session.call("begin_play"))
	if began_playing:
		# begin_play() enables the live producers again. Let that startup
		# boundary finish, then isolate this geometry-only patrol proof from
		# sight/footstep investigation before configuring the route.
		await tree.physics_frame
		await tree.process_frame
	if awareness != null:
		awareness.set_physics_process(false)
		awareness.process_mode = Node.PROCESS_MODE_DISABLED
		awareness.call("reset_reaction")
	if footstep_emitter != null:
		footstep_emitter.set_physics_process(false)
		footstep_emitter.process_mode = Node.PROCESS_MODE_DISABLED
	if guard != null:
		guard.call("set_awareness_observation_paused", false)
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

	var restored_shadow_budget: bool = (
		root_viewport.positional_shadow_atlas_size == previous_shadow_atlas_size
		and root_viewport.positional_shadow_atlas_16_bits
			== previous_shadow_atlas_16_bits
	)
	for quadrant: int in 4:
		restored_shadow_budget = (
			restored_shadow_budget
			and int(root_viewport.get_positional_shadow_atlas_quadrant_subdiv(quadrant))
				== previous_shadow_subdivisions[quadrant]
		)
	assert_true.call(
		restored_shadow_budget,
		"8.4 Ledge City renderer budget is mission-scoped and restores the host viewport shadow-atlas configuration on teardown"
	)

	await _test_application_quickload_returns_ledge_city_to_live_play(
		tree,
		assert_true
	)


func _debug_surface_ray(player: CharacterBody3D) -> Dictionary:
	if player == null or not player.is_inside_tree():
		return {"error": "player unavailable"}
	var query := PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3.UP * 0.20,
		player.global_position + Vector3.DOWN * 0.55
	)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(
		query
	)
	if hit.is_empty():
		return {
			"error": "no hit",
			"player_position": player.global_position,
			"from": query.from,
			"to": query.to,
		}
	var collider := hit.get("collider") as CollisionObject3D
	return {
		"player_position": player.global_position,
		"position": hit.get("position", Vector3.ZERO),
		"normal": hit.get("normal", Vector3.ZERO),
		"shape": int(hit.get("shape", -1)),
		"collider": str(collider),
		"collider_path": (
			str(collider.get_path())
			if collider != null and collider.is_inside_tree()
			else ""
		),
		"has_mesh_metadata": (
			collider != null and collider.has_meta("func_godot_mesh_data")
		),
	}


func _audit_func_godot_surface_metadata(
	collider: CollisionObject3D
) -> Dictionary:
	if collider == null or not collider.has_meta("func_godot_mesh_data"):
		return {
			"ok": false,
			"error": "missing collider or func_godot_mesh_data",
		}
	var mesh_data_variant: Variant = collider.get_meta("func_godot_mesh_data")
	if not (mesh_data_variant is Dictionary):
		return {
			"ok": false,
			"error": "mesh metadata is not a Dictionary",
		}
	var mesh_data: Dictionary = mesh_data_variant as Dictionary
	var texture_names_variant: Variant = mesh_data.get("texture_names", [])
	var textures_variant: Variant = mesh_data.get("textures", PackedInt32Array())
	var normals_variant: Variant = mesh_data.get("normals", PackedVector3Array())
	var positions_variant: Variant = mesh_data.get("positions", PackedVector3Array())
	var shape_map_variant: Variant = mesh_data.get(
		"collision_shape_to_face_indices_map",
		{}
	)
	if (
		not (texture_names_variant is Array)
		or not (textures_variant is PackedInt32Array)
		or not (normals_variant is PackedVector3Array)
		or not (positions_variant is PackedVector3Array)
		or not (shape_map_variant is Dictionary)
	):
		return {
			"ok": false,
			"error": "required texture/face/shape metadata is missing",
		}
	var texture_names: Array = texture_names_variant as Array
	var textures: PackedInt32Array = textures_variant as PackedInt32Array
	var normals: PackedVector3Array = normals_variant as PackedVector3Array
	var positions: PackedVector3Array = positions_variant as PackedVector3Array
	var shape_map: Dictionary = shape_map_variant as Dictionary
	if (
		textures.is_empty()
		or textures.size() != normals.size()
		or textures.size() != positions.size()
	):
		return {
			"ok": false,
			"error": "parallel face metadata arrays are empty or differ in size",
			"texture_faces": textures.size(),
			"normal_faces": normals.size(),
			"position_faces": positions.size(),
		}

	var shape_count: int = 0
	var mapped_shape_count: int = 0
	var referenced_face_count: int = 0
	for child: Node in collider.get_children():
		if not (child is CollisionShape3D):
			continue
		shape_count += 1
		if not shape_map.has(child.name):
			continue
		var face_indices_variant: Variant = shape_map.get(
			child.name,
			PackedInt32Array()
		)
		if not (face_indices_variant is PackedInt32Array):
			continue
		var face_indices: PackedInt32Array = (
			face_indices_variant as PackedInt32Array
		)
		if face_indices.is_empty():
			continue
		var valid_shape: bool = true
		for face_index: int in face_indices:
			if face_index < 0 or face_index >= textures.size():
				valid_shape = false
				break
			var texture_index: int = textures[face_index]
			if texture_index < 0 or texture_index >= texture_names.size():
				valid_shape = false
				break
			if not ALLOWED_SURFACE_TEXTURES.has(str(texture_names[texture_index])):
				valid_shape = false
				break
		if valid_shape:
			mapped_shape_count += 1
			referenced_face_count += face_indices.size()
	return {
		"ok": (
			shape_count > 0
			and mapped_shape_count == shape_count
			and referenced_face_count > 0
		),
		"shape_count": shape_count,
		"mapped_shape_count": mapped_shape_count,
		"referenced_face_count": referenced_face_count,
		"texture_names": texture_names,
	}


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



func _has_positive_pair_overlap(bounds: Array[AABB]) -> bool:
	for first_index: int in bounds.size():
		for second_index: int in range(first_index + 1, bounds.size()):
			if _aabb_positive_overlap(bounds[first_index], bounds[second_index]):
				return true
	return false


func _aabb_positive_overlap(first: AABB, second: AABB) -> bool:
	var first_end: Vector3 = first.position + first.size
	var second_end: Vector3 = second.position + second.size
	return (
		minf(first_end.x, second_end.x)
			- maxf(first.position.x, second.position.x) > 0.001
		and minf(first_end.y, second_end.y)
			- maxf(first.position.y, second.position.y) > 0.001
		and minf(first_end.z, second_end.z)
			- maxf(first.position.z, second.position.z) > 0.001
	)


func _audit_runtime_physical_overlaps(
	world: Node,
	roots: Array[Node]
) -> Dictionary:
	if world == null:
		return {"ok": false, "error": "missing world"}
	var space_state: PhysicsDirectSpaceState3D = (
		world.get_world_3d().direct_space_state
	)
	for root: Node in roots:
		if root == null or not is_instance_valid(root):
			continue
		var bodies: Array[PhysicsBody3D] = []
		if root is PhysicsBody3D:
			bodies.append(root as PhysicsBody3D)
		for candidate: Node in root.find_children("*", "", true, false):
			if candidate is PhysicsBody3D:
				var body := candidate as PhysicsBody3D
				if (
					body.collision_layer != 0
					and body.collision_layer
						!= VarkLightFixtureAsset.EXPOSURE_OCCLUDER_PHYSICS_LAYER
				):
					bodies.append(body)
		var excluded: Array[RID] = []
		for body: PhysicsBody3D in bodies:
			if body.get_rid().is_valid():
				excluded.append(body.get_rid())
		for body: PhysicsBody3D in bodies:
			for candidate: Node in body.find_children("*", "CollisionShape3D", true, false):
				var collision := candidate as CollisionShape3D
				if (
					collision == null
					or collision.disabled
					or collision.shape == null
					or _nearest_physics_body(collision) != body
				):
					continue
				var audit_shape: Shape3D = _shrink_audit_shape(collision.shape)
				if audit_shape == null:
					continue
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = audit_shape
				query.transform = collision.global_transform
				query.collision_mask = 0x7fffffff
				query.collide_with_bodies = true
				query.collide_with_areas = false
				query.exclude = excluded
				var hits: Array[Dictionary] = space_state.intersect_shape(query, 16)
				if not hits.is_empty():
					var collider: Object = hits[0].get("collider", null)
					return {
						"ok": false,
						"root": str(root.get_path()),
						"body": str(body.get_path()),
						"shape": str(collision.get_path()),
						"collider": str(collider),
					}
	return {"ok": true}


func _nearest_physics_body(node: Node) -> PhysicsBody3D:
	var cursor: Node = node.get_parent()
	while cursor != null:
		if cursor is PhysicsBody3D:
			return cursor as PhysicsBody3D
		cursor = cursor.get_parent()
	return null


func _shrink_audit_shape(source_shape: Shape3D) -> Shape3D:
	const SHRINK := 0.01
	if source_shape is BoxShape3D:
		var source_box := source_shape as BoxShape3D
		var box := source_box.duplicate() as BoxShape3D
		box.size = Vector3(
			maxf(source_box.size.x - SHRINK * 2.0, 0.001),
			maxf(source_box.size.y - SHRINK * 2.0, 0.001),
			maxf(source_box.size.z - SHRINK * 2.0, 0.001)
		)
		return box
	if source_shape is SphereShape3D:
		var source_sphere := source_shape as SphereShape3D
		var sphere := source_sphere.duplicate() as SphereShape3D
		sphere.radius = maxf(source_sphere.radius - SHRINK, 0.001)
		return sphere
	if source_shape is CapsuleShape3D:
		var source_capsule := source_shape as CapsuleShape3D
		var capsule := source_capsule.duplicate() as CapsuleShape3D
		capsule.radius = maxf(source_capsule.radius - SHRINK, 0.001)
		capsule.height = maxf(source_capsule.height - SHRINK * 2.0, capsule.radius * 2.0)
		return capsule
	if source_shape is CylinderShape3D:
		var source_cylinder := source_shape as CylinderShape3D
		var cylinder := source_cylinder.duplicate() as CylinderShape3D
		cylinder.radius = maxf(source_cylinder.radius - SHRINK, 0.001)
		cylinder.height = maxf(source_cylinder.height - SHRINK * 2.0, 0.001)
		return cylinder
	return null



func _all_sneak_window_clearances_are_crouch_only(source: String) -> bool:
	const CROUCHED_HEIGHT_MAP_UNITS := 0.95 * 32.0
	const STANDING_HEIGHT_MAP_UNITS := 1.49 * 32.0
	var checks: Array[Dictionary] = [
		{"header": "facade: mercer_96_header", "floor_z": 96.0},
		{"header": "facade: watchmaker_96_header", "floor_z": 96.0},
		{"header": "facade: office_96_header", "floor_z": 96.0},
		{"header": "facade: tenement_96_header", "floor_z": 96.0},
		{"header": "facade: archive_level2_96_header", "floor_z": 96.0},
		{"header": "facade: foundry_96_header", "floor_z": 96.0},
		{"header": "facade: archive_level3_184_header", "floor_z": 184.0},
	]
	for check: Dictionary in checks:
		var header: AABB = _brush_bounds_after_comment(
			source,
			str(check["header"])
		)
		if header.size == Vector3.ZERO:
			return false
		var clearance: float = header.position.z - float(check["floor_z"])
		if (
			clearance <= CROUCHED_HEIGHT_MAP_UNITS + 1.0
			or clearance >= STANDING_HEIGHT_MAP_UNITS
		):
			return false
	return true


func _all_outdoor_ground_coverage_complete(source: String) -> bool:
	var expected: Dictionary = {
		"street: carriageway": AABB(Vector3(-68, -454, -8), Vector3(136, 908, 8)),
		"street: west_sidewalk": AABB(Vector3(-110, -454, -8), Vector3(42, 908, 8)),
		"street: east_sidewalk": AABB(Vector3(68, -454, -8), Vector3(42, 908, 8)),
		"rear_alley: west": AABB(Vector3(-424, -454, -8), Vector3(94, 908, 8)),
		"rear_alley: east": AABB(Vector3(330, -454, -8), Vector3(94, 908, 8)),
		"back_valley_floor: west_south": AABB(Vector3(-330, 360, -8), Vector3(220, 94, 8)),
		"back_valley_floor: east_south": AABB(Vector3(110, 360, -8), Vector3(220, 94, 8)),
		"back_valley_floor: west_north": AABB(Vector3(-330, -454, -8), Vector3(220, 94, 8)),
		"back_valley_floor: east_north": AABB(Vector3(110, -454, -8), Vector3(220, 94, 8)),
	}
	for comment: String in expected:
		var actual: AABB = _brush_bounds_after_comment(source, comment)
		var wanted: AABB = expected[comment] as AABB
		if (
			actual.size == Vector3.ZERO
			or actual.position.distance_to(wanted.position) > 0.001
			or actual.size.distance_to(wanted.size) > 0.001
		):
			return false
	return true


func _all_opening_frames_seat_leaf(source: String) -> bool:
	const LEAF_WIDTH_MAP_UNITS := 41.6
	const ORDINARY_LEAF_HEIGHT_MAP_UNITS := 67.2
	const SNEAK_LEAF_HEIGHT_MAP_UNITS := 37.76
	var checks: Array[Dictionary] = [
		{"left": "facade: mercer_0_left", "right": "facade: mercer_0_right", "header": "facade: mercer_0_header", "floor_z": 0.0, "leaf_height": ORDINARY_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: watchmaker_0_left", "right": "facade: watchmaker_0_right", "header": "facade: watchmaker_0_header", "floor_z": 0.0, "leaf_height": ORDINARY_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: office_0_left", "right": "facade: office_0_right", "header": "facade: office_0_header", "floor_z": 0.0, "leaf_height": ORDINARY_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: tenement_0_left", "right": "facade: tenement_0_right", "header": "facade: tenement_0_header", "floor_z": 0.0, "leaf_height": ORDINARY_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: archive_0_left", "right": "facade: archive_0_right", "header": "facade: archive_0_header", "floor_z": 0.0, "leaf_height": ORDINARY_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: foundry_0_left", "right": "facade: foundry_0_right", "header": "facade: foundry_0_header", "floor_z": 0.0, "leaf_height": ORDINARY_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: mercer_96_left", "right": "facade: mercer_96_right", "header": "facade: mercer_96_header", "floor_z": 96.0, "leaf_height": SNEAK_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: watchmaker_96_left", "right": "facade: watchmaker_96_right", "header": "facade: watchmaker_96_header", "floor_z": 96.0, "leaf_height": SNEAK_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: office_96_left", "right": "facade: office_96_right", "header": "facade: office_96_header", "floor_z": 96.0, "leaf_height": SNEAK_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: tenement_96_left", "right": "facade: tenement_96_right", "header": "facade: tenement_96_header", "floor_z": 96.0, "leaf_height": SNEAK_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: archive_level2_96_left", "right": "facade: archive_level2_96_right", "header": "facade: archive_level2_96_header", "floor_z": 96.0, "leaf_height": SNEAK_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: foundry_96_left", "right": "facade: foundry_96_right", "header": "facade: foundry_96_header", "floor_z": 96.0, "leaf_height": SNEAK_LEAF_HEIGHT_MAP_UNITS},
		{"left": "facade: archive_level3_184_left", "right": "facade: archive_level3_184_right", "header": "facade: archive_level3_184_header", "floor_z": 184.0, "leaf_height": SNEAK_LEAF_HEIGHT_MAP_UNITS},
	]
	for check: Dictionary in checks:
		var left: AABB = _brush_bounds_after_comment(source, str(check["left"]))
		var right: AABB = _brush_bounds_after_comment(source, str(check["right"]))
		var header: AABB = _brush_bounds_after_comment(source, str(check["header"]))
		if left.size == Vector3.ZERO or right.size == Vector3.ZERO or header.size == Vector3.ZERO:
			return false
		var left_end: Vector3 = left.position + left.size
		var header_end: Vector3 = header.position + header.size
		if (
			not is_equal_approx(right.position.y - left_end.y, LEAF_WIDTH_MAP_UNITS)
			or not is_equal_approx(header.position.y, left_end.y)
			or not is_equal_approx(header_end.y, right.position.y)
			or not is_equal_approx(
				header.position.z,
				float(check["floor_z"]) + float(check["leaf_height"])
			)
		):
			return false
	return true


func _all_named_solid_brushes_face_connected(source: String) -> bool:
	var world_start: int = source.find("\"classname\" \"worldspawn\"")
	var cutoff: int = source.find("\"classname\" \"vark_player_start\"")
	if world_start < 0 or cutoff <= world_start:
		return false
	var physical_source: String = source.substr(
		world_start,
		cutoff - world_start
	)
	var comment_pattern := RegEx.new()
	comment_pattern.compile("(?m)^// ([^\\n]+)\\n\\{")
	var named_bounds: Array[AABB] = []
	for result: RegExMatch in comment_pattern.search_all(physical_source):
		var bounds: AABB = _brush_bounds_after_comment(
			physical_source,
			result.get_string(1)
		)
		if bounds.size != Vector3.ZERO:
			named_bounds.append(bounds)
	if named_bounds.size() != 329:
		return false
	for first_index: int in named_bounds.size():
		var connected: bool = false
		for second_index: int in named_bounds.size():
			if first_index == second_index:
				continue
			if _aabbs_share_supporting_face(
				named_bounds[first_index],
				named_bounds[second_index]
			):
				connected = true
				break
		if not connected:
			return false
	return true


func _all_structural_extensions_connected(source: String) -> bool:
	var world_start: int = source.find("\"classname\" \"worldspawn\"")
	var cutoff: int = source.find("\"classname\" \"vark_player_start\"")
	var world_source: String = source.substr(
		maxi(world_start, 0),
		(cutoff if cutoff >= 0 else source.length()) - maxi(world_start, 0)
	)
	var comment_pattern := RegEx.new()
	comment_pattern.compile("(?m)^// ([^\\n]+)\\n\\{")
	var named_bounds: Array[Dictionary] = []
	for result: RegExMatch in comment_pattern.search_all(world_source):
		var comment: String = result.get_string(1)
		var bounds: AABB = _brush_bounds_after_comment(world_source, comment)
		if bounds.size != Vector3.ZERO:
			named_bounds.append({
				"name": comment,
				"bounds": bounds,
			})
	var structural_prefixes := PackedStringArray([
		"supported_bay:",
		"supported_upper_bay:",
		"supported_terrace:",
		"overstreet:",
		"alley_bridge:",
	])
	var structural_count: int = 0
	for entry: Dictionary in named_bounds:
		var name: String = str(entry["name"])
		var structural: bool = false
		for prefix: String in structural_prefixes:
			if name.begins_with(prefix):
				structural = true
				break
		if not structural:
			continue
		structural_count += 1
		var connected: bool = false
		for other: Dictionary in named_bounds:
			if other == entry:
				continue
			if _aabbs_share_supporting_face(
				entry["bounds"] as AABB,
				other["bounds"] as AABB
			):
				connected = true
				break
		if not connected:
			return false
	return structural_count == 67


func _aabbs_share_supporting_face(first: AABB, second: AABB) -> bool:
	var first_end: Vector3 = first.position + first.size
	var second_end: Vector3 = second.position + second.size
	for axis: int in 3:
		var face_touch: bool = (
			is_equal_approx(first_end[axis], second.position[axis])
			or is_equal_approx(second_end[axis], first.position[axis])
		)
		if not face_touch:
			continue
		var first_other: int = (axis + 1) % 3
		var second_other: int = (axis + 2) % 3
		if (
			minf(first_end[first_other], second_end[first_other])
				- maxf(first.position[first_other], second.position[first_other])
				> 0.001
			and minf(first_end[second_other], second_end[second_other])
				- maxf(first.position[second_other], second.position[second_other])
				> 0.001
		):
			return true
	return false


func _all_upper_floor_coverage_complete(source: String) -> bool:
	# Positive world-brush overlap is already forbidden above, so the sum of
	# these floor-plate areas is also their union area. Require each upper
	# storey to cover the complete interior rectangle except the exact stair
	# shaft; this catches the earlier 10-map-unit missing-floor strips.
	var checks: Array[Dictionary] = [
		{
			"footprint": Vector4(-322, 188, -118, 352),
			"hole": Vector4(-258, 196, -138, 240),
			"brushes": [
				"interior_floor: mercer_back_88",
				"interior_floor: mercer_front_88",
				"interior_floor: mercer_side_a_88",
				"interior_floor: mercer_side_b_88",
			],
		},
		{
			"footprint": Vector4(118, 188, 322, 352),
			"hole": Vector4(138, 196, 258, 240),
			"brushes": [
				"interior_floor: watchmaker_back_88",
				"interior_floor: watchmaker_front_88",
				"interior_floor: watchmaker_side_a_88",
				"interior_floor: watchmaker_side_b_88",
			],
		},
		{
			"footprint": Vector4(-322, -32, -118, 132),
			"hole": Vector4(-258, -24, -138, 20),
			"brushes": [
				"interior_floor: office_back_88",
				"interior_floor: office_front_88",
				"interior_floor: office_side_a_88",
				"interior_floor: office_side_b_88",
			],
		},
		{
			"footprint": Vector4(118, -32, 322, 132),
			"hole": Vector4(138, -24, 258, 20),
			"brushes": [
				"interior_floor: tenement_back_88",
				"interior_floor: tenement_front_88",
				"interior_floor: tenement_side_a_88",
				"interior_floor: tenement_side_b_88",
			],
		},
		{
			"footprint": Vector4(-322, -352, -118, -188),
			"hole": Vector4(-258, -352, -138, -308),
			"brushes": [
				"interior_floor: archive_level2_back_88",
				"interior_floor: archive_level2_front_88",
				"interior_floor: archive_level2_side_b_88",
			],
		},
		{
			"footprint": Vector4(-322, -352, -118, -188),
			"hole": Vector4(-248, -242, -138, -198),
			"brushes": [
				"interior_floor: archive_level3_back_176",
				"interior_floor: archive_level3_front_176",
				"interior_floor: archive_level3_side_a_176",
				"interior_floor: archive_level3_side_b_176",
			],
		},
		{
			"footprint": Vector4(118, -352, 322, -188),
			"hole": Vector4(138, -344, 258, -300),
			"brushes": [
				"interior_floor: foundry_back_88",
				"interior_floor: foundry_front_88",
				"interior_floor: foundry_side_a_88",
				"interior_floor: foundry_side_b_88",
			],
		},
	]
	for check: Dictionary in checks:
		var footprint: Vector4 = check["footprint"]
		var hole: Vector4 = check["hole"]
		var expected_area: float = (
			(footprint.z - footprint.x) * (footprint.w - footprint.y)
			- (hole.z - hole.x) * (hole.w - hole.y)
		)
		var authored_area: float = 0.0
		for brush_name: String in check["brushes"]:
			var floor: AABB = _brush_bounds_after_comment(source, brush_name)
			if floor.size == Vector3.ZERO:
				return false
			authored_area += floor.size.x * floor.size.y
		if not is_equal_approx(authored_area, expected_area):
			return false
	return true


func _all_stair_landings_connect(source: String) -> bool:
	var checks: Array[Dictionary] = [
		{"step": "interior_stair: mercer_0_12", "floor": "interior_floor: mercer_back_88", "side": &"west"},
		{"step": "interior_stair: office_0_12", "floor": "interior_floor: office_back_88", "side": &"west"},
		{"step": "interior_stair: archive_lower_0_12", "floor": "interior_floor: archive_level2_back_88", "side": &"west"},
		{"step": "interior_stair: archive_upper_96_11", "floor": "interior_floor: archive_level3_back_176", "side": &"west"},
		{"step": "interior_stair: watchmaker_0_12", "floor": "interior_floor: watchmaker_front_88", "side": &"east"},
		{"step": "interior_stair: tenement_0_12", "floor": "interior_floor: tenement_front_88", "side": &"east"},
		{"step": "interior_stair: foundry_0_12", "floor": "interior_floor: foundry_front_88", "side": &"east"},
	]
	for check: Dictionary in checks:
		var step: AABB = _brush_bounds_after_comment(source, str(check["step"]))
		var floor: AABB = _brush_bounds_after_comment(source, str(check["floor"]))
		if step.size == Vector3.ZERO or floor.size == Vector3.ZERO:
			return false
		var step_end: Vector3 = step.position + step.size
		var floor_end: Vector3 = floor.position + floor.size
		# Stairs must reach the actual upper walking surface, not merely touch
		# the underside of the floor slab.
		if not is_equal_approx(step_end.z, floor_end.z):
			return false
		if (
			check["side"] == &"west"
			and not is_equal_approx(step.position.x, floor_end.x)
		):
			return false
		if (
			check["side"] == &"east"
			and not is_equal_approx(step_end.x, floor.position.x)
		):
			return false
	return true


func _opening_completes_real_sweep(opening: VarkOrdinaryDoor) -> bool:
	if opening == null:
		return false
	var saved: Dictionary = opening.capture_semantic_state()
	if saved.is_empty():
		return false
	var probe: Dictionary = saved.duplicate(true)
	probe["phase"] = VarkOrdinaryDoor.PHASE_OPENING
	probe["open_fraction"] = 0.0
	probe["motion_blocked"] = false
	probe["locked"] = false
	probe["barred"] = false
	if not opening.apply_semantic_state(probe):
		return false
	for _step: int in 40:
		opening.call("_physics_process", 0.02)
		if opening.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN:
			break
	var completed: bool = (
		opening.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN
		and is_equal_approx(opening.get_open_fraction(), 1.0)
		and not opening.is_motion_blocked()
	)
	var restored: bool = opening.apply_semantic_state(saved)
	return completed and restored


func _sneak_window_opens_away_from_exterior_probe(
	world: Node,
	tree: SceneTree,
	opening: VarkOrdinaryDoor,
	map_floor_center: Vector3
) -> bool:
	if world == null or opening == null:
		return false
	var saved: Dictionary = opening.capture_semantic_state()
	var closed_state := {
		"phase": VarkOrdinaryDoor.PHASE_CLOSED,
		"open_fraction": 0.0,
		"motion_blocked": false,
		"locked": false,
		"barred": false,
	}
	if not opening.apply_semantic_state(closed_state):
		return false

	var probe := StaticBody3D.new()
	probe.name = "SneakWindowExteriorProbe"
	probe.collision_layer = 1
	probe.collision_mask = 0
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 0.95
	collision.shape = capsule
	probe.add_child(collision)
	world.add_child(probe)

	var exterior_map: Vector3 = map_floor_center
	exterior_map.x = -80.0 if map_floor_center.x < 0.0 else 80.0
	probe.global_position = (
		_map_origin_to_world(exterior_map)
		+ Vector3.UP * 0.475
	)
	await tree.physics_frame

	var was_processing: bool = opening.is_physics_processing()
	opening.set_physics_process(false)
	opening.interact(null)
	for _step: int in 40:
		opening.call("_physics_process", 0.02)
		if opening.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN:
			break
	var opened: bool = (
		opening.get_semantic_phase() == VarkOrdinaryDoor.PHASE_OPEN
		and is_equal_approx(opening.get_open_fraction(), 1.0)
		and not opening.is_motion_blocked()
	)

	probe.queue_free()
	await tree.physics_frame
	var restored: bool = opening.apply_semantic_state(saved)
	opening.set_physics_process(was_processing)
	return opened and restored


func _capsule_traverses_map_aperture(
	world: Node,
	opening: VarkOrdinaryDoor,
	map_floor_center: Vector3,
	height: float
) -> bool:
	if world == null or opening == null:
		return false
	# All Ledge City passable windows are authored in the east/west facade
	# planes: map X becomes world Z. Use that authoritative wall axis for this
	# map-specific passage sweep. The ordinary-door navigation frame is a
	# navigation ownership seam and is intentionally not required for the
	# player-only sneak-window variant.
	var normal := Vector3(
		0.0,
		0.0,
		1.0 if map_floor_center.x < 0.0 else -1.0
	)

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = height
	var floor_world: Vector3 = _map_origin_to_world(map_floor_center)
	# Sweep the actual crouch/standing capsule all the way through the open
	# wall aperture. This proves traversability, rather than asking whether a
	# stationary capsule centered inside the wall plane happens to overlap one
	# of the jamb/header support colliders.
	const SUPPORT_CLEARANCE: float = 0.03
	const APPROACH_DISTANCE: float = 0.55
	var center: Vector3 = floor_world + Vector3.UP * (
		height * 0.5 + SUPPORT_CLEARANCE
	)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(
		Basis.IDENTITY,
		center - normal * APPROACH_DISTANCE
	)
	query.motion = normal * (APPROACH_DISTANCE * 2.0)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [opening.get_rid()]
	var cast: PackedFloat32Array = (
		world.get_world_3d().direct_space_state.cast_motion(query)
	)
	if cast.size() < 2:
		return false
	return cast[0] >= 0.999


func _test_application_quickload_returns_ledge_city_to_live_play(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	const TEST_SAVE_DIRECTORY := "user://vark_tests/phase8_ledge_city_quickload"
	_cleanup_quickload_storage(TEST_SAVE_DIRECTORY)

	var root_viewport := tree.get_root() as Viewport
	var previous_shadow_atlas_size: int = root_viewport.positional_shadow_atlas_size
	var previous_shadow_atlas_16_bits: bool = (
		root_viewport.positional_shadow_atlas_16_bits
	)
	var previous_shadow_subdivisions: Array[int] = []
	for quadrant: int in 4:
		previous_shadow_subdivisions.append(
			int(root_viewport.get_positional_shadow_atlas_quadrant_subdiv(quadrant))
		)

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
	var initial_shadow_budget: Dictionary = (
		world.call("get_shadow_budget_debug_state")
		if world != null and world.has_method("get_shadow_budget_debug_state")
		else {}
	)
	assert_true.call(
		launched
		and nav_ready
		and int(application.call("get_current_session_state"))
			== WorldSession.State.PLAYING
		and bool(initial_shadow_budget.get("active", false))
		and bool(initial_shadow_budget.get("atlas_requested", false))
		and (
			not bool(initial_shadow_budget.get("atlas_applied", false))
			or _is_ledge_shadow_budget_active(root_viewport)
		)
		and int(initial_shadow_budget.get("shared_refcount", 0)) >= 1,
		"8.4 Ledge City application quickload regression starts PLAYING with the mission-scoped shadow budget owned"
	)
	if not launched or not nav_ready:
		application.queue_free()
		await tree.process_frame
		_cleanup_quickload_storage(TEST_SAVE_DIRECTORY)
		return

	var save_coordinator := application.get_node("SaveCoordinator") as Node
	save_coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)

	# Reproduce the player-reported failure on the exact persistent owner. A
	# moving east-side sneak window may be physically obstructed arbitrarily
	# close to fully open; that is valid semantic truth and must survive F9.
	var live_openings: Array[Node] = []
	for candidate: Node in world.find_children("*", "", true, false):
		if candidate is VarkOrdinaryDoor:
			live_openings.append(candidate)
	var watch_window := _find_by_property(
		live_openings,
		"door_id",
		"window.watchmaker.upper"
	) as VarkOrdinaryDoor
	var watch_blocked_state := {
		"phase": VarkOrdinaryDoor.PHASE_OPENING,
		"open_fraction": 0.999999,
		"motion_blocked": true,
		"locked": false,
		"barred": false,
	}
	var watch_state_prepared: bool = (
		watch_window != null
		and watch_window.apply_semantic_state(watch_blocked_state)
	)
	assert_true.call(
		watch_state_prepared
		and watch_window.capture_semantic_state() == watch_blocked_state,
		"8.4 watchmaker sneak window accepts valid near-endpoint blocked state before quicksave"
	)

	# Reproduce the later F9 failure while the authored guard is dwelling at a
	# patrol endpoint. This is the exact persistent state whose wait staging is
	# applied before the replacement world's deferred navigation configuration.
	var live_guard: VarkGuard = null
	for candidate: Node in world.find_children("*", "", true, false):
		if candidate is VarkGuard:
			live_guard = candidate as VarkGuard
			break
	if live_guard != null:
		live_guard.call("_complete_patrol_leg")
	var prepared_guard_wait: Dictionary = (
		live_guard.capture_semantic_state()
		if live_guard != null else {}
	)
	assert_true.call(
		live_guard != null
		and bool(prepared_guard_wait.get("patrol_wait_active", false))
		and float(prepared_guard_wait.get(
			"patrol_wait_remaining_seconds",
			0.0
		)) > 0.0,
		"8.4 Ledge guard enters a real authored patrol dwell before quicksave"
	)

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

	var saved_guard_state: Dictionary = (
		snapshot.get("session", {})
		.get("world_state", {})
		.get("persistent_entities", {})
		.get("vark_ledge_guard", {})
	)
	assert_true.call(
		bool(saved_guard_state.get("patrol_wait_active", false))
		and float(saved_guard_state.get(
			"patrol_wait_remaining_seconds",
			0.0
		)) > 0.0,
		"8.4 committed quicksave contains the active Ledge guard patrol dwell"
	)

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
	var restored_guard: VarkGuard = null
	if restored_world != null:
		for candidate: Node in restored_world.find_children("*", "", true, false):
			if candidate is VarkGuard:
				restored_guard = candidate as VarkGuard
				break
	var restored_guard_state: Dictionary = (
		restored_guard.capture_semantic_state()
		if restored_guard != null else {}
	)
	var restored_watch_window: VarkOrdinaryDoor = null
	if restored_world != null:
		var restored_openings: Array[Node] = []
		for candidate: Node in restored_world.find_children("*", "", true, false):
			if candidate is VarkOrdinaryDoor:
				restored_openings.append(candidate)
		restored_watch_window = _find_by_property(
			restored_openings,
			"door_id",
			"window.watchmaker.upper"
		) as VarkOrdinaryDoor
	var restored_watch_state: Dictionary = (
		restored_watch_window.capture_semantic_state()
		if restored_watch_window != null else {}
	)
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
	var restored_shadow_budget: Dictionary = (
		restored_world.call("get_shadow_budget_debug_state")
		if (
			restored_world != null
			and restored_world.has_method("get_shadow_budget_debug_state")
		)
		else {}
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
		and bool(restored_shadow_budget.get("active", false))
		and bool(restored_shadow_budget.get("atlas_requested", false))
		and (
			not bool(restored_shadow_budget.get("atlas_applied", false))
			or _is_ledge_shadow_budget_active(root_viewport)
		)
		and int(restored_shadow_budget.get("shared_refcount", 0)) >= 1
		and restored_watch_state == watch_blocked_state
		and restored_guard != null
		and restored_guard_state.get("goal_id", "") == saved_guard_state.get("goal_id", "")
		and bool(restored_guard_state.get("patrol_wait_active", false))
		and float(restored_guard_state.get(
			"patrol_wait_remaining_seconds",
			0.0
		)) > 0.0
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
				"shadow_budget": restored_shadow_budget,
				"saved_guard_state": saved_guard_state,
				"restored_guard_state": restored_guard_state,
				"viewport_shadow_budget_active": _is_ledge_shadow_budget_active(
					root_viewport
				),
			}
		)
	assert_true.call(
		live_after_load,
		"8.4 F9 restores Ledge City into a genuinely live simulation: session/world/player processing, gameplay clock and fresh movement all resume"
	)

	application.queue_free()
	await tree.process_frame
	var shadow_budget_restored: bool = (
		root_viewport.positional_shadow_atlas_size == previous_shadow_atlas_size
		and root_viewport.positional_shadow_atlas_16_bits
			== previous_shadow_atlas_16_bits
	)
	for quadrant: int in 4:
		shadow_budget_restored = (
			shadow_budget_restored
			and int(root_viewport.get_positional_shadow_atlas_quadrant_subdiv(quadrant))
				== previous_shadow_subdivisions[quadrant]
		)
	assert_true.call(
		shadow_budget_restored,
		"8.4 F9 replacement retains the shared Ledge shadow budget until the final world exits, then restores the host viewport"
	)
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


func _is_ledge_shadow_budget_active(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	if (
		viewport.positional_shadow_atlas_size != LEDGE_SHADOW_ATLAS_SIZE
		or not viewport.positional_shadow_atlas_16_bits
	):
		return false
	for quadrant: int in 4:
		if (
			viewport.get_positional_shadow_atlas_quadrant_subdiv(quadrant)
			!= LEDGE_SHADOW_ATLAS_SUBDIV
		):
			return false
	return true


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
