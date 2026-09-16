extends SceneTree


const WorldSession = preload("res://application/world_session.gd")
const PersistentIdSource = preload("res://tools/authoring/persistent_id_source.gd")
const PersistentIdentityProbe = preload("res://tools/authoring/persistent_identity_probe.gd")
const PersistentEntity = preload("res://missions/persistence/persistent_entity.gd")
const PersistentIdentityValidator = preload(
	"res://missions/persistence/persistent_identity_validator.gd"
)
const SessionIdentityRegressions = preload(
	"res://tests/authoring/persistent_identity_runtime_regressions.gd"
)
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const PLAYGROUND_DEFINITION_PATH: String = "res://missions/playground/mission.tres"
const MAP_SETTINGS_PATH: String = "res://authoring/vark_map_settings.tres"
const VARK_TRENCHBROOM_CONFIG_PATH: String = "res://VarkTrenchBroom.tres"
const VARK_PROOF_MATERIAL_PATH: String = "res://textures/zebra/zebra16x16.png"
const TEMP_MAP_PATH: String = "user://vark_persistent_identity_feasibility.map"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_assert_true(
		PersistentIdentityProbe != null,
		"Mapper-facing persistent-identity probe script parses under pinned Godot"
	)
	_assert_vark_trenchbroom_identity_property()
	_assert_vark_trenchbroom_material_config()
	_assert_vark_runtime_identity_wiring()
	_assert_vark_point_entity_foundation()
	_assert_runtime_identity_validator_diagnostics()
	var session_identity_regressions: RefCounted = SessionIdentityRegressions.new()
	session_identity_regressions.run(Callable(self, "_assert_true"))

	var playground_read: Dictionary = PersistentIdSource.read_source(
		PLAYGROUND_SOURCE_PATH
	)
	_assert_true(
		bool(playground_read["ok"])
		and str(playground_read["text"]).contains("// Phase 2 playground: authoritative spatial source."),
		"Persistent-identity proof derives from the real Playground authored map"
	)
	if not bool(playground_read["ok"]):
		_print_summary()
		quit(1)
		return

	var base_source: String = str(playground_read["text"]).trim_suffix("\n")
	_remove_temp_map()

	var created_source: String = _compose_source(base_source, [
		_probe_entity("alpha", 160),
		_probe_entity("beta", 192),
	])
	_assert_true(
		_write_source(TEMP_MAP_PATH, created_source),
		"Identity proof creates mapper-style entities in a copy of the Playground source"
	)
	var missing_runtime: Dictionary = _build_runtime_identity_result(TEMP_MAP_PATH)
	_assert_true(
		int(missing_runtime["identity_count"]) == 2
		and not bool((missing_runtime["validation"] as Dictionary)["ok"])
		and _errors_contain(
			missing_runtime["validation"] as Dictionary,
			"Missing persistent_id"
		),
		"Runtime FuncGodot build exposes missing authored persistent IDs to fail-closed validation"
	)

	var first_repair: Dictionary = _repair_with_ids(
		TEMP_MAP_PATH,
		["pid-alpha", "pid-beta"]
	)
	var first_ids: Dictionary = _parse_probe_ids(TEMP_MAP_PATH)
	_assert_true(
		bool(first_repair["ok"])
		and bool(first_repair["changed"])
		and (first_repair["repairs"] as Array).size() == 2
		and first_ids == {
			"alpha": "pid-alpha",
			"beta": "pid-beta",
		},
		"Missing authored IDs are repaired into authoritative map source and survive FuncGodot parsing"
	)
	var repaired_runtime: Dictionary = _build_runtime_identity_result(TEMP_MAP_PATH)
	var repaired_runtime_ids: Array[String] = repaired_runtime["ids"]
	repaired_runtime_ids.sort()
	_assert_true(
		bool((repaired_runtime["validation"] as Dictionary)["ok"])
		and int(repaired_runtime["identity_count"]) == 2
		and int(repaired_runtime["static_body_count"]) == 2
		and repaired_runtime_ids == ["pid-alpha", "pid-beta"],
		"Vark FuncGodot runtime nodes receive authored persistent_id values without changing func_detail StaticBody3D behavior"
	)

	var moved_source: String = _compose_source(base_source, [
		_probe_entity("alpha", 224, "pid-alpha"),
		_probe_entity("beta", 192, "pid-beta"),
	])
	_write_source(TEMP_MAP_PATH, moved_source)
	var moved_before: String = _read_text(TEMP_MAP_PATH)
	var moved_repair: Dictionary = _repair_with_ids(TEMP_MAP_PATH, [])
	var moved_after: String = _read_text(TEMP_MAP_PATH)
	var moved_ids: Dictionary = _parse_probe_ids(TEMP_MAP_PATH)
	_assert_true(
		bool(moved_repair["ok"])
		and not bool(moved_repair["changed"])
		and moved_before == moved_after
		and moved_ids == {
			"alpha": "pid-alpha",
			"beta": "pid-beta",
		},
		"Moving an authored entity preserves identity and valid source is not rewritten"
	)

	var reordered_source: String = _compose_source(base_source, [
		_probe_entity("beta", 192, "pid-beta"),
		_probe_entity("alpha", 224, "pid-alpha"),
	])
	_write_source(TEMP_MAP_PATH, reordered_source)
	var reordered_before_hash: String = PersistentIdSource.source_sha256(
		_read_text(TEMP_MAP_PATH)
	)
	var reordered_repair: Dictionary = _repair_with_ids(TEMP_MAP_PATH, [])
	var reordered_after_hash: String = PersistentIdSource.source_sha256(
		_read_text(TEMP_MAP_PATH)
	)
	var reordered_ids: Dictionary = _parse_probe_ids(TEMP_MAP_PATH)
	_assert_true(
		bool(reordered_repair["ok"])
		and not bool(reordered_repair["changed"])
		and reordered_before_hash == reordered_after_hash
		and reordered_ids == {
			"alpha": "pid-alpha",
			"beta": "pid-beta",
		},
		"Reordering unrelated authored entities does not reassign persistent identity"
	)

	var duplicated_source: String = _compose_source(base_source, [
		_probe_entity("beta", 192, "pid-beta"),
		_probe_entity("alpha", 224, "pid-alpha"),
		_probe_entity("alpha_copy", 256, "pid-alpha"),
	])
	_write_source(TEMP_MAP_PATH, duplicated_source)
	var duplicate_runtime: Dictionary = _build_runtime_identity_result(TEMP_MAP_PATH)
	_assert_true(
		int(duplicate_runtime["identity_count"]) == 3
		and not bool((duplicate_runtime["validation"] as Dictionary)["ok"])
		and _errors_contain(
			duplicate_runtime["validation"] as Dictionary,
			"Duplicate persistent_id 'pid-alpha'"
		),
		"Runtime FuncGodot build exposes duplicate authored persistent IDs to fail-closed validation"
	)
	var duplicate_repair: Dictionary = _repair_with_ids(
		TEMP_MAP_PATH,
		["pid-alpha-copy"]
	)
	var duplicate_ids: Dictionary = _parse_probe_ids(TEMP_MAP_PATH)
	var duplicate_repairs: Array = duplicate_repair["repairs"]
	_assert_true(
		bool(duplicate_repair["ok"])
		and bool(duplicate_repair["changed"])
		and duplicate_repairs.size() == 1
		and str((duplicate_repairs[0] as Dictionary)["reason"]) == "duplicate"
		and duplicate_ids == {
			"alpha": "pid-alpha",
			"alpha_copy": "pid-alpha-copy",
			"beta": "pid-beta",
		},
		"Duplicating an authored entity keeps the original ID and repairs the duplicate to a distinct ID"
	)

	var recreated_source: String = _compose_source(base_source, [
		_probe_entity("alpha", 224, "pid-alpha"),
		_probe_entity("alpha_copy", 256, "pid-alpha-copy"),
		_probe_entity("delta", 288),
	])
	_write_source(TEMP_MAP_PATH, recreated_source)
	var recreate_repair: Dictionary = _repair_with_ids(
		TEMP_MAP_PATH,
		["pid-delta"]
	)
	var recreated_ids: Dictionary = _parse_probe_ids(TEMP_MAP_PATH)
	_assert_true(
		bool(recreate_repair["ok"])
		and bool(recreate_repair["changed"])
		and not recreated_ids.has("beta")
		and recreated_ids == {
			"alpha": "pid-alpha",
			"alpha_copy": "pid-alpha-copy",
			"delta": "pid-delta",
		},
		"Deleting and recreating another authored entity gives the replacement a fresh identity"
	)

	var stable_source: String = _read_text(TEMP_MAP_PATH)
	var stable_hash: String = PersistentIdSource.source_sha256(stable_source)
	var stable_repair: Dictionary = _repair_with_ids(TEMP_MAP_PATH, [])
	var stable_after: String = _read_text(TEMP_MAP_PATH)
	var stable_ids: Dictionary = _parse_probe_ids(TEMP_MAP_PATH)
	_assert_true(
		bool(stable_repair["ok"])
		and not bool(stable_repair["changed"])
		and stable_source == stable_after
		and stable_hash == PersistentIdSource.source_sha256(stable_after)
		and stable_ids == recreated_ids,
		"Repeated validation/import is idempotent and does not create ID churn or rewrite loops"
	)

	var stale_expected_hash: String = PersistentIdSource.source_sha256(stable_after)
	var newer_mapper_source: String = stable_after + "// mapper newer edit\n"
	_write_source(TEMP_MAP_PATH, newer_mapper_source)
	var stale_attempt: Dictionary = PersistentIdSource.repair_file(
		TEMP_MAP_PATH,
		stale_expected_hash,
		func() -> String: return "pid-should-not-write"
	)
	_assert_true(
		not bool(stale_attempt["ok"])
		and bool(stale_attempt["stale"])
		and _read_text(TEMP_MAP_PATH) == newer_mapper_source,
		"Stale generated repair work refuses to overwrite newer authored map edits"
	)

	_remove_temp_map()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_vark_trenchbroom_identity_property() -> void:
	var config := load(VARK_TRENCHBROOM_CONFIG_PATH) as TrenchBroomGameConfig
	var fgd_file: FuncGodotFGDFile = config.fgd_file if config != null else null
	var definitions: Dictionary[String, FuncGodotFGDEntityClass] = {}
	if fgd_file != null:
		definitions = fgd_file.get_entity_definitions()
	var func_detail: FuncGodotFGDEntityClass = definitions.get("func_detail")
	var exported_fgd: String = ""
	if fgd_file != null:
		exported_fgd = fgd_file.build_class_text(
			FuncGodotFGDFile.FuncGodotTargetMapEditors.TRENCHBROOM
		)
	_assert_true(
		config != null
		and fgd_file != null
		and fgd_file.fgd_name == "Vark"
		and func_detail != null
		and func_detail.class_properties.has("persistent_id")
		and str(func_detail.class_properties["persistent_id"]).is_empty()
		and exported_fgd.contains("VarkPersistentIdentity")
		and exported_fgd.contains("persistent_id"),
		"Vark TrenchBroom FGD declares persistent_id on func_detail so mapper saves preserve repaired IDs"
	)


func _assert_vark_trenchbroom_material_config() -> void:
	var config := load(VARK_TRENCHBROOM_CONFIG_PATH) as TrenchBroomGameConfig
	var exported_config: String = ""
	if config != null:
		exported_config = str(config.call("_build_class_text"))
	_assert_true(
		config != null
		and config.textures_root_folder == "textures"
		and config.palette_path.strip_edges().is_empty()
		and FileAccess.file_exists(VARK_PROOF_MATERIAL_PATH)
		and exported_config.contains("\"root\": \"textures\"")
		and exported_config.contains("\".png\"")
		and exported_config.contains("\"palette\": \"\""),
		"Vark TrenchBroom material config resolves PNG materials without a nonexistent palette dependency"
	)


func _assert_vark_runtime_identity_wiring() -> void:
	var map_settings := load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	var fgd_file: FuncGodotFGDFile = map_settings.entity_fgd if map_settings != null else null
	var definitions: Dictionary[String, FuncGodotFGDEntityClass] = {}
	if fgd_file != null:
		definitions = fgd_file.get_entity_definitions()
	var func_detail := definitions.get("func_detail") as FuncGodotFGDSolidClass
	_assert_true(
		str(ProjectSettings.get_setting("func_godot/default_map_settings", ""))
		== MAP_SETTINGS_PATH
		and map_settings != null
		and fgd_file != null
		and fgd_file.fgd_name == "Vark"
		and func_detail != null
		and func_detail.auto_apply_to_matching_node_properties
		and func_detail.script_class == PersistentEntity,
		"Runtime FuncGodot defaults and Playground use the project-owned Vark FGD persistent-identity wiring"
	)


func _assert_vark_point_entity_foundation() -> void:
	var config := load(VARK_TRENCHBROOM_CONFIG_PATH) as TrenchBroomGameConfig
	var fgd_file: FuncGodotFGDFile = config.fgd_file if config != null else null
	var definitions: Dictionary[String, FuncGodotFGDEntityClass] = {}
	var exported_fgd: String = ""
	if fgd_file != null:
		definitions = fgd_file.get_entity_definitions()
		exported_fgd = fgd_file.build_class_text(
			FuncGodotFGDFile.FuncGodotTargetMapEditors.TRENCHBROOM
		)

	var point_specs: Dictionary[String, String] = {
		"vark_player_start": "vark_player_start",
		"vark_marker": "vark_semantic_marker",
		"vark_exit": "vark_mission_exit",
	}
	var schema_valid: bool = fgd_file != null
	for classname: String in point_specs:
		var point := definitions.get(classname) as FuncGodotFGDPointClass
		if point == null:
			schema_valid = false
			continue
		var properties: Dictionary = point.retrieve_all_class_properties()
		schema_valid = (
			schema_valid
			and point.node_class == "Node3D"
			and point.script_class == PersistentEntity
			and point.auto_apply_to_matching_node_properties
			and point.node_groups.has(point_specs[classname])
			and properties.has("persistent_id")
			and properties.has("content_id")
			and properties.has("angle")
		)
	_assert_true(
		schema_valid
		and exported_fgd.contains("vark_player_start")
		and exported_fgd.contains("vark_marker")
		and exported_fgd.contains("vark_exit"),
		"Vark TrenchBroom FGD exposes the minimal player-start, semantic-marker, and exit point vocabulary"
	)

	var func_map := FuncGodotMap.new()
	func_map.map_settings = load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	func_map.local_map_file = PLAYGROUND_SOURCE_PATH
	func_map.build()

	var player_starts: Array[Node] = []
	var markers: Array[Node] = []
	var exits: Array[Node] = []
	for node: Node in func_map.find_children("*", "", true, false):
		if node.is_in_group(&"vark_player_start"):
			player_starts.append(node)
		if node.is_in_group(&"vark_semantic_marker"):
			markers.append(node)
		if node.is_in_group(&"vark_mission_exit"):
			exits.append(node)

	var start: Node3D = null
	var marker: Node3D = null
	var exit_point: Node3D = null
	if player_starts.size() == 1:
		start = player_starts[0] as Node3D
	if markers.size() == 1:
		marker = markers[0] as Node3D
	if exits.size() == 1:
		exit_point = exits[0] as Node3D
	var validation: Dictionary = PersistentIdentityValidator.validate_subtree(func_map)
	var point_ids: Dictionary = {}
	for point: Node3D in [start, marker, exit_point]:
		if point != null and point.has_method("get_persistent_id"):
			point_ids[str(point.call("get_persistent_id"))] = true

	_assert_true(
		start != null
		and marker != null
		and exit_point != null
		and str(start.call("get_content_id")) == "default"
		and str(marker.call("get_content_id")) == "marker.playground_reference"
		and str(exit_point.call("get_content_id")) == "exit.default"
		and point_ids.size() == 3
		and not point_ids.has("")
		and bool(validation.get("ok", false))
		and int(validation.get("identity_count", 0)) == 3
		and int(validation.get("content_id_count", 0)) == 3
		and start.position.is_equal_approx(Vector3(0.0, 1.15, 0.0))
		and is_zero_approx(fposmod(start.rotation_degrees.y, 360.0)),
		"Tracked Playground source builds one valid persistent/content-addressed Node3D for each Vark point role"
	)
	func_map.free()

	var mission_definition: Resource = load(PLAYGROUND_DEFINITION_PATH)
	var world_scene: PackedScene = null
	if mission_definition != null:
		world_scene = mission_definition.get("world_scene") as PackedScene
	var session: Node = WorldSession.new()
	session.name = "PointFoundationWorldSession"
	get_root().add_child(session)
	var built: bool = false
	if world_scene != null:
		built = bool(session.call("build", 2701, world_scene, mission_definition))
	var session_world: Node = session.get("world") as Node
	var session_player: Node3D = session.get("player") as Node3D
	var selected_start: Node3D = null
	if session_world != null:
		selected_start = session_world.get("selected_player_start") as Node3D
	var start_lookup: Dictionary = session.call("lookup_content_entity", "default")
	var marker_lookup: Dictionary = session.call(
		"lookup_content_entity",
		"marker.playground_reference"
	)
	var exit_lookup: Dictionary = session.call("lookup_content_entity", "exit.default")
	_assert_true(
		built
		and int(session.get("state")) == WorldSession.State.READY
		and selected_start != null
		and bool(start_lookup.get("ok", false))
		and start_lookup.get("node") == selected_start
		and bool(marker_lookup.get("ok", false))
		and bool(exit_lookup.get("ok", false))
		and session_player != null
		and session_player.global_transform.is_equal_approx(selected_start.global_transform),
		"Playground resolves MissionDefinition player_start_selector to the map-authored Vark start before play and registers all three semantic points"
	)
	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")
	session.free()


func _assert_runtime_identity_validator_diagnostics() -> void:
	var missing_root := Node.new()
	var missing_entity: Node = PersistentEntity.new()
	missing_entity.name = "MissingIdentity"
	missing_root.add_child(missing_entity)
	var missing_result: Dictionary = PersistentIdentityValidator.validate_subtree(missing_root)
	_assert_true(
		not bool(missing_result["ok"])
		and int(missing_result["identity_count"]) == 1
		and _errors_contain(missing_result, "Missing persistent_id")
		and _errors_contain(missing_result, "MissingIdentity"),
		"Persistent identity validation reports the path of an authored entity with a missing ID"
	)
	missing_root.free()

	var duplicate_root := Node.new()
	for node_name: String in ["FirstOwner", "DuplicateOwner"]:
		var entity: Node = PersistentEntity.new()
		entity.name = node_name
		entity.set("persistent_id", "pid-duplicate")
		duplicate_root.add_child(entity)
	var duplicate_result: Dictionary = PersistentIdentityValidator.validate_subtree(duplicate_root)
	_assert_true(
		not bool(duplicate_result["ok"])
		and int(duplicate_result["identity_count"]) == 2
		and _errors_contain(duplicate_result, "Duplicate persistent_id 'pid-duplicate'")
		and _errors_contain(duplicate_result, "FirstOwner")
		and _errors_contain(duplicate_result, "DuplicateOwner"),
		"Persistent identity validation reports duplicate ID plus both authored owner paths"
	)
	duplicate_root.free()


func _build_runtime_identity_result(path: String) -> Dictionary:
	var func_map := FuncGodotMap.new()
	func_map.map_settings = load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	func_map.local_map_file = path
	func_map.build()

	var ids: Array[String] = []
	var identity_count: int = 0
	var static_body_count: int = 0
	for node: Node in func_map.find_children("*", "", true, false):
		if not node.has_method("is_vark_persistent_entity"):
			continue
		if not (node is StaticBody3D):
			continue
		identity_count += 1
		ids.append(str(node.call("get_persistent_id")))
		static_body_count += 1
	var validation: Dictionary = PersistentIdentityValidator.validate_subtree(func_map)
	func_map.free()
	return {
		"ids": ids,
		"identity_count": identity_count,
		"static_body_count": static_body_count,
		"validation": validation,
	}


func _errors_contain(result: Dictionary, needle: String) -> bool:
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	for error_message: String in errors:
		if error_message.contains(needle):
			return true
	return false


func _repair_with_ids(path: String, generated_ids: Array[String]) -> Dictionary:
	var ids: Array[String] = generated_ids.duplicate()
	var source: String = _read_text(path)
	var expected_hash: String = PersistentIdSource.source_sha256(source)
	var factory := func() -> String:
		if ids.is_empty():
			return ""
		return ids.pop_front()
	return PersistentIdSource.repair_file(path, expected_hash, factory)


func _parse_probe_ids(path: String) -> Dictionary:
	var map_settings := load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	var parser := FuncGodotParser.new()
	var parse_data: FuncGodotData.ParseData = parser.parse_map_data(
		path,
		map_settings
	)
	var probe_ids: Dictionary = {}
	for entity: FuncGodotData.EntityData in parse_data.entities:
		var properties: Dictionary = entity.properties
		if not properties.has("probe_name"):
			continue
		probe_ids[str(properties["probe_name"])] = str(
			properties.get("persistent_id", "")
		)
	return probe_ids


func _compose_source(base_source: String, entities: Array[String]) -> String:
	var result: String = base_source + "\n"
	for entity: String in entities:
		result += entity + "\n"
	return result


func _probe_entity(
	probe_name: String,
	min_x: int,
	persistent_id: String = ""
) -> String:
	var max_x: int = min_x + 16
	var lines: Array[String] = [
		"// identity feasibility probe entity",
		"{",
		"\"classname\" \"func_detail\"",
		"\"probe_name\" \"%s\"" % probe_name,
	]
	if not persistent_id.is_empty():
		lines.append("\"persistent_id\" \"%s\"" % persistent_id)
	lines.append_array([
		"{",
		"( %d -8 0 ) ( %d -7 0 ) ( %d -8 1 ) zebra/zebra16x16 [ 0 -1 0 0 ] [ 0 0 -1 0 ] 0 1 1" % [min_x, min_x, min_x],
		"( %d -8 0 ) ( %d -8 1 ) ( %d -8 0 ) zebra/zebra16x16 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1" % [min_x, min_x, min_x + 1],
		"( %d -8 0 ) ( %d -8 0 ) ( %d -7 0 ) zebra/zebra16x16 [ -1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1" % [min_x, min_x + 1, min_x],
		"( %d 8 4 ) ( %d 9 4 ) ( %d 8 4 ) zebra/zebra16x16 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1" % [max_x, max_x, max_x + 1],
		"( %d 8 4 ) ( %d 8 4 ) ( %d 8 5 ) zebra/zebra16x16 [ -1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1" % [max_x, max_x + 1, max_x],
		"( %d 8 4 ) ( %d 8 5 ) ( %d 9 4 ) zebra/zebra16x16 [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1" % [max_x, max_x, max_x],
		"}",
		"}",
	])
	return "\n".join(lines)


func _write_source(path: String, source: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write identity feasibility fixture: %s" % path)
		return false
	file.store_string(source)
	file.flush()
	file.close()
	return true


func _read_text(path: String) -> String:
	var result: Dictionary = PersistentIdSource.read_source(path)
	if not bool(result["ok"]):
		return ""
	return str(result["text"])


func _remove_temp_map() -> void:
	if FileAccess.file_exists(TEMP_MAP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_MAP_PATH))


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
		print("ALL AUTHORING TESTS PASSED")
		return
	print("%d AUTHORING TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
