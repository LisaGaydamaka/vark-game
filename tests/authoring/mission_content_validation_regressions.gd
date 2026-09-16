extends RefCounted


const WorldSession = preload("res://application/world_session.gd")
const MissionDefinitionResource = preload("res://missions/mission_definition.gd")
const PLAYGROUND_DEFINITION_PATH: String = "res://missions/playground/mission.tres"
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const TEMP_MISSING_EXIT_MAP_PATH: String = "user://vark_missing_exit_validation.map"


func run(root: Node, assert_true: Callable) -> void:
	_remove_temp_map()
	_assert_valid_playground(root, assert_true)
	_assert_static_definition_validation(root, assert_true)
	_assert_player_start_reference_validation(root, assert_true)
	_assert_missing_exit_validation(root, assert_true)
	_assert_required_player_validation(root, assert_true)
	_remove_temp_map()


func _assert_valid_playground(root: Node, assert_true: Callable) -> void:
	var definition: Resource = load(PLAYGROUND_DEFINITION_PATH)
	var result: Dictionary = _build_session(root, 2900, definition)
	assert_true.call(
		bool(result.get("built", false))
		and int(result.get("state", WorldSession.State.EMPTY)) == WorldSession.State.READY,
		"2.9 content validation accepts the real Playground mission before WorldSession READY"
	)


func _assert_static_definition_validation(root: Node, assert_true: Callable) -> void:
	var definition: Resource = _make_definition(PLAYGROUND_SOURCE_PATH, "")
	assert_true.call(
		definition != null,
		"2.9 static-definition regression creates a valid test MissionDefinition resource"
	)
	if definition == null:
		return
	var result: Dictionary = _build_session(root, 2901, definition)
	assert_true.call(
		_failed_cleanly(result),
		"WorldSession rejects invalid MissionDefinition metadata before building mission content"
	)


func _assert_player_start_reference_validation(
	root: Node,
	assert_true: Callable
) -> void:
	var missing_definition: Resource = _make_definition(
		PLAYGROUND_SOURCE_PATH,
		"missing.player_start"
	)
	assert_true.call(
		missing_definition != null,
		"2.9 missing-reference regression creates a valid test MissionDefinition resource"
	)
	if missing_definition == null:
		return
	var missing_result: Dictionary = _build_session(
		root,
		2902,
		missing_definition
	)
	assert_true.call(
		_failed_cleanly(missing_result),
		"Mission content validation rejects a player_start_selector that does not resolve"
	)

	var wrong_type_definition: Resource = _make_definition(
		PLAYGROUND_SOURCE_PATH,
		"marker.playground_reference"
	)
	assert_true.call(
		wrong_type_definition != null,
		"2.9 wrong-role regression creates a valid test MissionDefinition resource"
	)
	if wrong_type_definition == null:
		return
	var wrong_type_result: Dictionary = _build_session(
		root,
		2903,
		wrong_type_definition
	)
	assert_true.call(
		_failed_cleanly(wrong_type_result),
		(
			"Mission content validation rejects a player_start_selector "
			+ "that resolves to the wrong authored role"
		)
	)


func _assert_missing_exit_validation(root: Node, assert_true: Callable) -> void:
	var source: String = FileAccess.get_file_as_string(PLAYGROUND_SOURCE_PATH)
	var missing_exit_source: String = _replace_single(
		source,
		"\"classname\" \"vark_exit\"",
		"\"classname\" \"vark_marker\""
	)
	assert_true.call(
		not missing_exit_source.is_empty()
		and _write_source(TEMP_MISSING_EXIT_MAP_PATH, missing_exit_source),
		"2.9 missing-exit regression derives a disposable real-Playground source copy"
	)
	if missing_exit_source.is_empty() or not FileAccess.file_exists(TEMP_MISSING_EXIT_MAP_PATH):
		return

	var definition: Resource = _make_definition(
		TEMP_MISSING_EXIT_MAP_PATH,
		"default"
	)
	assert_true.call(
		definition != null,
		"2.9 missing-exit regression creates a valid test MissionDefinition resource"
	)
	if definition == null:
		return
	var result: Dictionary = _build_session(root, 2904, definition)
	assert_true.call(
		_failed_cleanly(result),
		"Mission content validation rejects a built mission with no authored vark_exit endpoint"
	)


func _assert_required_player_validation(root: Node, assert_true: Callable) -> void:
	for player_count: int in [0, 2]:
		var scene: PackedScene = _make_player_count_scene(player_count)
		assert_true.call(
			scene != null,
			"2.9 required-player regression packs the %d-player fixture" % player_count
		)
		if scene == null:
			continue
		var result: Dictionary = _build_raw_session(
			root,
			2910 + player_count,
			scene
		)
		assert_true.call(
			_failed_cleanly(result),
			"WorldSession rejects a world with %d vark_player nodes before READY"
			% player_count
		)


func _build_session(
	root: Node,
	session_id: int,
	definition: Resource
) -> Dictionary:
	var world_scene: PackedScene = null
	if definition != null:
		world_scene = definition.get("world_scene") as PackedScene

	var session: Node = WorldSession.new()
	session.name = "MissionContentValidationSession_%d" % session_id
	root.add_child(session)
	var built: bool = bool(session.call(
		"build",
		session_id,
		world_scene,
		definition
	))
	var result := {
		"built": built,
		"state": int(session.get("state")),
		"world": session.get("world"),
		"registry": session.get("entity_registry"),
	}

	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")
	session.free()
	return result


func _build_raw_session(
	root: Node,
	session_id: int,
	world_scene: PackedScene
) -> Dictionary:
	var session: Node = WorldSession.new()
	session.name = "RequiredPlayerValidationSession_%d" % session_id
	root.add_child(session)
	var built: bool = bool(session.call("build", session_id, world_scene))
	var result := {
		"built": built,
		"state": int(session.get("state")),
		"world": session.get("world"),
		"registry": session.get("entity_registry"),
	}

	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")
	session.free()
	return result


func _make_player_count_scene(player_count: int) -> PackedScene:
	var root := Node3D.new()
	root.name = "PlayerCountWorld"
	for player_index: int in player_count:
		var player := Node.new()
		player.name = "Player_%d" % player_index
		player.add_to_group(&"vark_player", true)
		root.add_child(player)
		player.owner = root

	var packed := PackedScene.new()
	var pack_error: Error = packed.pack(root)
	root.free()
	if pack_error != OK:
		return null
	return packed


func _failed_cleanly(result: Dictionary) -> bool:
	return (
		not bool(result.get("built", false))
		and int(result.get("state", -1)) == WorldSession.State.EMPTY
		and result.get("world") == null
		and result.get("registry") == null
	)


func _make_definition(map_path: String, player_start_selector: String) -> Resource:
	var base_definition: Resource = load(PLAYGROUND_DEFINITION_PATH)
	if base_definition == null:
		return null
	var world_scene: PackedScene = base_definition.get("world_scene") as PackedScene
	if world_scene == null:
		return null

	var definition: Resource = MissionDefinitionResource.new()
	definition.set("mission_id", &"playground_content_validation")
	definition.set("world_scene", world_scene)
	definition.set("map_source_path", map_path)
	definition.set("player_start_selector", StringName(player_start_selector))
	definition.set(
		"mission_content_revision",
		base_definition.get("mission_content_revision")
	)
	return definition


func _replace_single(source: String, needle: String, replacement: String) -> String:
	var first_index: int = source.find(needle)
	if first_index < 0:
		return ""
	var second_index: int = source.find(needle, first_index + needle.length())
	if second_index >= 0:
		return ""
	return (
		source.substr(0, first_index)
		+ replacement
		+ source.substr(first_index + needle.length())
	)


func _write_source(path: String, source: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(source)
	file.flush()
	file.close()
	return true


func _remove_temp_map() -> void:
	if FileAccess.file_exists(TEMP_MISSING_EXIT_MAP_PATH):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(TEMP_MISSING_EXIT_MAP_PATH)
		)
