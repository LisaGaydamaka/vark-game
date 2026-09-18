extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const WorldSession = preload("res://application/world_session.gd")
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const MAP_SETTINGS_PATH: String = "res://authoring/vark_map_settings.tres"
const VARK_TRENCHBROOM_CONFIG_PATH: String = "res://VarkTrenchBroom.tres"
const TEMP_ACOUSTIC_MAP_PATH: String = "user://vark_acoustic_authoring_probe.map"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_assert_trenchbroom_authoring_seam()
	_assert_invalid_topology_fails_closed()
	await _assert_acoustic_lab_integration()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_trenchbroom_authoring_seam() -> void:
	var config := load(VARK_TRENCHBROOM_CONFIG_PATH) as TrenchBroomGameConfig
	var fgd_file: FuncGodotFGDFile = config.fgd_file if config != null else null
	var definitions: Dictionary[String, FuncGodotFGDEntityClass] = {}
	var exported_fgd: String = ""
	if fgd_file != null:
		definitions = fgd_file.get_entity_definitions()
		exported_fgd = fgd_file.build_class_text(
			FuncGodotFGDFile.FuncGodotTargetMapEditors.TRENCHBROOM
		)
	var space_class := definitions.get("vark_acoustic_space") as FuncGodotFGDPointClass
	var portal_class := definitions.get("vark_acoustic_portal") as FuncGodotFGDPointClass
	_assert_true(
		space_class != null
		and portal_class != null
		and space_class.script_class == VarkAcousticSpace
		and portal_class.script_class == VarkAcousticPortal
		and space_class.auto_apply_to_matching_node_properties
		and portal_class.auto_apply_to_matching_node_properties
		and exported_fgd.contains("vark_acoustic_space")
		and exported_fgd.contains("vark_acoustic_portal"),
		"Vark TrenchBroom exports mapper-facing acoustic-space and portal point entities"
	)

	var source_file := FileAccess.open(PLAYGROUND_SOURCE_PATH, FileAccess.READ)
	_assert_true(source_file != null, "Acoustic authoring proof can read the real Playground map source")
	if source_file == null:
		return
	var source: String = source_file.get_as_text().trim_suffix("\n")
	source_file.close()
	source += "\n" + _authored_acoustic_probe_source() + "\n"
	_remove_temp_acoustic_map()
	var temp_file := FileAccess.open(TEMP_ACOUSTIC_MAP_PATH, FileAccess.WRITE)
	_assert_true(temp_file != null, "Acoustic authoring proof creates a disposable mapper source copy")
	if temp_file == null:
		return
	temp_file.store_string(source)
	temp_file.flush()
	temp_file.close()

	var func_map := FuncGodotMap.new()
	func_map.map_settings = load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	_assert_true(
		func_map.map_settings != null
		and is_equal_approx(
			func_map.map_settings.inverse_scale_factor,
			VarkAcousticSpace.MAP_UNITS_PER_WORLD_METER
		),
		"Acoustic mapper-unit conversion stays aligned with the authoritative FuncGodot map scale"
	)
	func_map.local_map_file = TEMP_ACOUSTIC_MAP_PATH
	func_map.build()
	var built_spaces: Dictionary = {}
	var built_portals: Dictionary = {}
	var nodes: Array[Node] = [func_map]
	nodes.append_array(func_map.find_children("*", "", true, false))
	for node: Node in nodes:
		if node is VarkAcousticSpace:
			var space: VarkAcousticSpace = node as VarkAcousticSpace
			built_spaces[space.space_id] = {
				"mapper_half_extents": Vector3(
					space.mapper_half_extent_x,
					space.mapper_half_extent_y,
					space.mapper_half_extent_z
				),
				"world_half_extents": Vector3(
					space.half_extent_x,
					space.half_extent_y,
					space.half_extent_z
				),
			}
		elif node is VarkAcousticPortal:
			var portal: VarkAcousticPortal = node as VarkAcousticPortal
			built_portals[portal.portal_id] = {
				"space_a_id": portal.space_a_id,
				"space_b_id": portal.space_b_id,
				"door_id": portal.door_id,
				"closed_transmission": portal.closed_transmission,
				"open_transmission": portal.open_transmission,
			}
	var portal_state: Dictionary = built_portals.get("portal.authoring", {})
	_assert_true(
		built_spaces.size() == 2
		and (built_spaces.get("space.authoring_a", {}) as Dictionary)
			.get("mapper_half_extents", Vector3.ZERO)
			.is_equal_approx(Vector3(96.0, 64.0, 128.0))
		and (built_spaces.get("space.authoring_a", {}) as Dictionary)
			.get("world_half_extents", Vector3.ZERO)
			.is_equal_approx(Vector3(3.0, 2.0, 4.0))
		and (built_spaces.get("space.authoring_b", {}) as Dictionary)
			.get("mapper_half_extents", Vector3.ZERO)
			.is_equal_approx(Vector3(80.0, 64.0, 96.0))
		and (built_spaces.get("space.authoring_b", {}) as Dictionary)
			.get("world_half_extents", Vector3.ZERO)
			.is_equal_approx(Vector3(2.5, 2.0, 3.0))
		and built_portals.size() == 1
		and portal_state.get("space_a_id", "") == "space.authoring_a"
		and portal_state.get("space_b_id", "") == "space.authoring_b"
		and portal_state.get("door_id", "") == "door.authoring"
		and is_equal_approx(float(portal_state.get("closed_transmission", 0.0)), 0.12)
		and is_equal_approx(float(portal_state.get("open_transmission", 0.0)), 0.9),
		"FuncGodot reimport preserves topology and converts ordinary mapper-unit acoustic extents into Vark world meters"
	)
	func_map.free()
	_remove_temp_acoustic_map()


func _assert_invalid_topology_fails_closed() -> void:
	var root := Node3D.new()
	var first := VarkAcousticSpace.new()
	first.name = "First"
	first.space_id = "duplicate"
	root.add_child(first)
	var second := VarkAcousticSpace.new()
	second.name = "Second"
	second.space_id = "duplicate"
	root.add_child(second)
	var broken_portal := VarkAcousticPortal.new()
	broken_portal.name = "BrokenPortal"
	broken_portal.portal_id = "portal.broken"
	broken_portal.space_a_id = "duplicate"
	broken_portal.space_b_id = "missing"
	root.add_child(broken_portal)
	var propagation := VarkAcousticPropagation.new()
	var result: Dictionary = propagation.configure(root)
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	_assert_true(
		not bool(result.get("ok", true))
		and _errors_contain(errors, "Duplicate acoustic space_id")
		and _errors_contain(errors, "references missing space 'missing'"),
		"Malformed acoustic topology fails closed with useful duplicate/missing-link diagnostics"
	)
	propagation.free()
	root.free()


func _assert_acoustic_lab_integration() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set("development_launch_labels", PackedStringArray(["Acoustic Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray(["res://scenes/AcousticLab.tscn"]))
	get_root().add_child(application)
	await process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	await process_frame
	await _completed_physics_frame()

	var world: Node3D = application.get("current_world") as Node3D
	var session: Node = application.get("current_session") as Node
	var player: CharacterBody3D = application.get("current_player") as CharacterBody3D
	_assert_true(
		launched
		and world != null
		and session != null
		and player != null
		and int(session.get("state")) == WorldSession.State.PLAYING,
		"Acoustic Lab launches through the production application/world-session path"
	)
	if world == null or session == null:
		application.queue_free()
		await process_frame
		return

	var propagation := world.get_node("AcousticPropagation") as VarkAcousticPropagation
	var door := world.get_node("OrdinaryDoor") as VarkOrdinaryDoor
	var same_listener := world.get_node("SameRoomListener") as VarkAcousticListener
	var door_listener := world.get_node("DoorRoomListener") as VarkAcousticListener
	var isolated_listener := world.get_node("IsolatedRoomListener") as VarkAcousticListener
	var corner_listener := world.get_node("AroundCornerListener") as VarkAcousticListener
	var footstep_emitter := world.get_node("FootstepEmitter") as Node3D
	var speech_emitter := world.get_node("SpeechEmitter") as Node3D
	var impact_emitter := world.get_node("ImpactEmitter") as Node3D
	var summary: Dictionary = propagation.get_debug_summary() if propagation != null else {}
	_assert_true(
		propagation != null
		and propagation.is_configured()
		and propagation.has_topology()
		and bool(summary.get("handler_registered", false))
		and int(summary.get("space_count", 0)) == 5
		and int(summary.get("portal_count", 0)) == 3
		and int(summary.get("listener_count", 0)) == 4
		and int(summary.get("door_count", 0)) == 1,
		"Acoustic Lab builds one validated world-owned space/portal graph with the ordinary-door seam and four listener probes"
	)
	if (
		propagation == null
		or door == null
		or same_listener == null
		or door_listener == null
		or isolated_listener == null
		or corner_listener == null
		or footstep_emitter == null
		or speech_emitter == null
		or impact_emitter == null
	):
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var same_room: Dictionary = propagation.evaluate(
		impact_emitter.global_position,
		1.0,
		same_listener.global_position
	)
	var around_corner: Dictionary = propagation.evaluate(
		impact_emitter.global_position,
		1.0,
		corner_listener.global_position
	)
	var isolated: Dictionary = propagation.evaluate(
		impact_emitter.global_position,
		1.0,
		isolated_listener.global_position
	)
	var corner_route: Array = around_corner.get("portal_route", [])
	var straight_corner_distance: float = impact_emitter.global_position.distance_to(
		corner_listener.global_position
	)
	_assert_true(
		bool(same_room.get("route_found", false))
		and (same_room.get("portal_route", []) as Array).is_empty()
		and float(same_room.get("propagated_strength", 0.0)) > 0.5,
		"Same-space sound uses ordinary distance attenuation without a portal hop"
	)
	_assert_true(
		bool(around_corner.get("route_found", false))
		and corner_route.size() == 2
		and corner_route[0] == &"portal.east"
		and corner_route[1] == &"portal.corner"
		and float(around_corner.get("path_distance", 0.0)) > straight_corner_distance + 1.5,
		"L-shaped corridor audibility follows the authored opening/corner route instead of a straight source-listener ray"
	)
	_assert_true(
		not bool(isolated.get("route_found", true))
		and is_zero_approx(float(isolated.get("propagated_strength", 1.0))),
		"A nearby-but-disconnected authored room has no acoustic route regardless of simple radius"
	)

	_assert_true(
		bool(door.apply_semantic_state({
			"phase": VarkOrdinaryDoor.PHASE_CLOSED,
			"open_fraction": 0.0,
			"motion_blocked": false,
		})),
		"Acoustic door fixture can restore its closed semantic state"
	)
	var closed_door: Dictionary = propagation.evaluate(
		impact_emitter.global_position,
		1.0,
		door_listener.global_position
	)
	_assert_true(
		bool(door.apply_semantic_state({
			"phase": VarkOrdinaryDoor.PHASE_OPENING,
			"open_fraction": 0.5,
			"motion_blocked": false,
		})),
		"Acoustic door fixture can restore a half-open semantic state"
	)
	var half_open_door: Dictionary = propagation.evaluate(
		impact_emitter.global_position,
		1.0,
		door_listener.global_position
	)
	_assert_true(
		bool(door.apply_semantic_state({
			"phase": VarkOrdinaryDoor.PHASE_OPEN,
			"open_fraction": 1.0,
			"motion_blocked": false,
		})),
		"Acoustic door fixture can restore its open semantic state"
	)
	var open_door: Dictionary = propagation.evaluate(
		impact_emitter.global_position,
		1.0,
		door_listener.global_position
	)
	var closed_strength: float = float(closed_door.get("propagated_strength", 0.0))
	var half_strength: float = float(half_open_door.get("propagated_strength", 0.0))
	var open_strength: float = float(open_door.get("propagated_strength", 0.0))
	_assert_true(
		bool(closed_door.get("route_found", false))
		and (closed_door.get("portal_route", []) as Array) == [&"portal.door"]
		and closed_strength > 0.0
		and closed_strength < half_strength
		and half_strength < open_strength
		and open_strength > closed_strength * 5.0,
		"Ordinary-door acoustic openness continuously controls the same portal instead of switching to a second door-specific model"
	)

	door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_CLOSED,
		"open_fraction": 0.0,
		"motion_blocked": false,
	})
	for listener: VarkAcousticListener in [same_listener, door_listener, isolated_listener, corner_listener]:
		listener.clear_perception()
	var session_id: int = int(session.get("session_id"))
	var footstep_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		session_id,
		&"footstep.test",
		footstep_emitter.global_position,
		0.35
	))
	_assert_true(
		footstep_queued
		and same_listener.get_heard_count() == 0
		and corner_listener.get_heard_count() == 0,
		"Gameplay sound remains queued until the controlled WorldSession consequence pass"
	)
	await _completed_physics_frame()
	_assert_true(
		same_listener.get_heard_count() == 1
		and door_listener.get_heard_count() == 0
		and isolated_listener.get_heard_count() == 0
		and corner_listener.get_heard_count() == 0
		and bool(same_listener.get_last_perception().get("heard", false))
		and not bool(corner_listener.get_last_perception().get("heard", true)),
		"Representative footstep strength is heard nearby but falls below threshold around the L-corridor and across the closed door"
	)

	var speech_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		session_id,
		&"speech.test",
		speech_emitter.global_position,
		0.55
	))
	await _completed_physics_frame()
	_assert_true(
		speech_queued
		and corner_listener.get_heard_count() == 1
		and bool(corner_listener.get_last_perception().get("heard", false))
		and (corner_listener.get_last_perception().get("portal_route", []) as Array) == [&"portal.east", &"portal.corner"],
		"Representative speech strength can remain audible around connected architecture without direct line of sight"
	)

	var impact_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		session_id,
		&"impact.test",
		impact_emitter.global_position,
		1.0
	))
	await _completed_physics_frame()
	_assert_true(
		impact_queued
		and corner_listener.get_heard_count() == 2
		and door_listener.get_heard_count() == 0
		and isolated_listener.get_heard_count() == 0,
		"Strong impact propagates around the connected corridor while the closed-door and disconnected-room cases remain protected"
	)

	door.apply_semantic_state({
		"phase": VarkOrdinaryDoor.PHASE_OPEN,
		"open_fraction": 1.0,
		"motion_blocked": false,
	})
	var open_impact_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		session_id,
		&"impact.test",
		impact_emitter.global_position,
		1.0
	))
	await _completed_physics_frame()
	_assert_true(
		open_impact_queued
		and door_listener.get_heard_count() == 1
		and bool(door_listener.get_last_perception().get("heard", false))
		and (door_listener.get_last_perception().get("portal_route", []) as Array) == [&"portal.door"],
		"Opening the real ordinary door makes the separated-room listener hear the same semantic impact through the existing door openness seam"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _authored_acoustic_probe_source() -> String:
	return "\n".join([
		"// acoustic authoring probe space A",
		"{",
		"\"classname\" \"vark_acoustic_space\"",
		"\"origin\" \"64 0 64\"",
		"\"space_id\" \"space.authoring_a\"",
		"\"mapper_half_extent_x\" \"96\"",
		"\"mapper_half_extent_y\" \"64\"",
		"\"mapper_half_extent_z\" \"128\"",
		"}",
		"// acoustic authoring probe space B",
		"{",
		"\"classname\" \"vark_acoustic_space\"",
		"\"origin\" \"192 0 64\"",
		"\"space_id\" \"space.authoring_b\"",
		"\"mapper_half_extent_x\" \"80\"",
		"\"mapper_half_extent_y\" \"64\"",
		"\"mapper_half_extent_z\" \"96\"",
		"}",
		"// acoustic authoring probe portal",
		"{",
		"\"classname\" \"vark_acoustic_portal\"",
		"\"origin\" \"128 0 64\"",
		"\"portal_id\" \"portal.authoring\"",
		"\"space_a_id\" \"space.authoring_a\"",
		"\"space_b_id\" \"space.authoring_b\"",
		"\"door_id\" \"door.authoring\"",
		"\"closed_transmission\" \"0.12\"",
		"\"open_transmission\" \"0.9\"",
		"}",
	])


func _completed_physics_frame() -> void:
	await physics_frame
	await process_frame


func _errors_contain(errors: PackedStringArray, needle: String) -> bool:
	for error_message: String in errors:
		if error_message.contains(needle):
			return true
	return false


func _remove_temp_acoustic_map() -> void:
	if FileAccess.file_exists(TEMP_ACOUSTIC_MAP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_ACOUSTIC_MAP_PATH))


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
		print("ALL ACOUSTIC TESTS PASSED")
		return
	print("%d ACOUSTIC TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
