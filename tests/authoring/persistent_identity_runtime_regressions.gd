extends RefCounted


const WorldSession = preload("res://application/world_session.gd")
const PersistentEntity = preload("res://missions/persistence/persistent_entity.gd")
const PersistentIdentityValidator = preload(
	"res://missions/persistence/persistent_identity_validator.gd"
)
const MissingIdentityWorld = preload(
	"res://tests/authoring/fixtures/persistent_identity_missing_world.tscn"
)
const DuplicateIdentityWorld = preload(
	"res://tests/authoring/fixtures/persistent_identity_duplicate_world.tscn"
)
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const MAP_SETTINGS_PATH: String = "res://authoring/vark_map_settings.tres"
const VARK_TRENCHBROOM_CONFIG_PATH: String = "res://VarkTrenchBroom.tres"
const CONTENT_RUNTIME_MAP_PATH: String = "user://vark_content_id_runtime.map"


func run(assert_true: Callable) -> void:
	_assert_content_id_authoring_schema(assert_true)
	_assert_content_id_runtime_wiring(assert_true)
	_assert_content_id_validation(assert_true)

	var session: Node = WorldSession.new()

	var missing_built: bool = bool(session.call("build", 9001, MissingIdentityWorld))
	assert_true.call(
		not missing_built
		and int(session.get("state")) == WorldSession.State.EMPTY
		and session.get("world") == null
		and session.get("player") == null
		and int(session.get("session_id")) == 0,
		"WorldSession fails closed and tears down when an authored persistent ID is missing"
	)
	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")

	var duplicate_built: bool = bool(session.call(
		"build",
		9002,
		DuplicateIdentityWorld
	))
	assert_true.call(
		not duplicate_built
		and int(session.get("state")) == WorldSession.State.EMPTY
		and session.get("world") == null
		and session.get("player") == null
		and int(session.get("session_id")) == 0,
		"WorldSession fails closed and tears down when authored persistent IDs are duplicated"
	)
	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")

	var duplicate_content_scene: PackedScene = _make_duplicate_content_scene()
	var duplicate_content_built: bool = false
	if duplicate_content_scene != null:
		duplicate_content_built = bool(session.call(
			"build",
			9003,
			duplicate_content_scene
		))
	assert_true.call(
		duplicate_content_scene != null
		and not duplicate_content_built
		and int(session.get("state")) == WorldSession.State.EMPTY
		and session.get("world") == null
		and session.get("player") == null
		and int(session.get("session_id")) == 0,
		"WorldSession fails closed and tears down when optional semantic content IDs are duplicated"
	)
	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")

	session.free()
	_remove_content_probe_map()


func _assert_content_id_authoring_schema(assert_true: Callable) -> void:
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
	assert_true.call(
		config != null
		and fgd_file != null
		and func_detail != null
		and func_detail.class_properties.has("content_id")
		and str(func_detail.class_properties["content_id"]).is_empty()
		and exported_fgd.contains("VarkContentAddressable")
		and exported_fgd.contains("content_id"),
		"Vark TrenchBroom FGD exposes optional semantic content_id separately from persistent identity"
	)


func _assert_content_id_runtime_wiring(assert_true: Callable) -> void:
	var source: String = FileAccess.get_file_as_string(PLAYGROUND_SOURCE_PATH)
	var wrote: bool = false
	if not source.is_empty():
		var file := FileAccess.open(CONTENT_RUNTIME_MAP_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(
				source.trim_suffix("\n")
				+ "\n"
				+ _content_probe_entity()
				+ "\n"
			)
			file.flush()
			file.close()
			wrote = true

	var found_entity: Node = null
	var validation: Dictionary = {}
	if wrote:
		var func_map := FuncGodotMap.new()
		func_map.map_settings = load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
		func_map.local_map_file = CONTENT_RUNTIME_MAP_PATH
		func_map.build()
		for node: Node in func_map.find_children("*", "", true, false):
			if not node.has_method("is_vark_persistent_entity"):
				continue
			if str(node.call("get_persistent_id")) != "pid-content-probe":
				continue
			found_entity = node
			break
		validation = PersistentIdentityValidator.validate_subtree(func_map)
		assert_true.call(
			found_entity != null
			and found_entity is StaticBody3D
			and found_entity.has_method("get_content_id")
			and str(found_entity.call("get_content_id")) == "door.vault"
			and bool(validation.get("ok", false))
			and int(validation.get("content_id_count", 0)) == 1,
			"FuncGodot carries authored content_id onto the runtime persistent entity without changing func_detail behavior"
		)
		func_map.free()
	else:
		assert_true.call(false, "FuncGodot content_id runtime fixture can be written from Playground source")

	_remove_content_probe_map()


func _assert_content_id_validation(assert_true: Callable) -> void:
	var root := Node.new()
	var first: Node = PersistentEntity.new()
	first.name = "VaultDoor"
	first.set("persistent_id", "pid-vault-door")
	first.set("content_id", "door.vault")
	root.add_child(first)

	var optional_blank: Node = PersistentEntity.new()
	optional_blank.name = "UnaddressedGeometry"
	optional_blank.set("persistent_id", "pid-unaddressed")
	root.add_child(optional_blank)

	var third: Node = PersistentEntity.new()
	third.name = "LibraryGuard"
	third.set("persistent_id", "pid-library-guard")
	third.set("content_id", "guard.library")
	root.add_child(third)

	var valid_result: Dictionary = PersistentIdentityValidator.validate_subtree(root)
	assert_true.call(
		bool(valid_result["ok"])
		and int(valid_result["identity_count"]) == 3
		and int(valid_result["content_id_count"]) == 2,
		"Optional semantic content IDs may be blank and unique non-empty IDs validate"
	)

	third.set("content_id", "door.vault")
	var duplicate_result: Dictionary = PersistentIdentityValidator.validate_subtree(root)
	assert_true.call(
		not bool(duplicate_result["ok"])
		and int(duplicate_result["content_id_count"]) == 2
		and _errors_contain(duplicate_result, "Duplicate content_id 'door.vault'")
		and _errors_contain(duplicate_result, "VaultDoor")
		and _errors_contain(duplicate_result, "LibraryGuard"),
		"Semantic content-ID validation rejects ambiguity and reports both authored owner paths"
	)
	root.free()


func _make_duplicate_content_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "DuplicateContentWorld"

	var player := Node.new()
	player.name = "PlayerMarker"
	player.add_to_group(&"vark_player", true)
	root.add_child(player)
	player.owner = root

	var first: Node = PersistentEntity.new()
	first.name = "FirstContentOwner"
	first.set("persistent_id", "pid-content-first")
	first.set("content_id", "door.vault")
	root.add_child(first)
	first.owner = root

	var duplicate: Node = PersistentEntity.new()
	duplicate.name = "DuplicateContentOwner"
	duplicate.set("persistent_id", "pid-content-second")
	duplicate.set("content_id", "door.vault")
	root.add_child(duplicate)
	duplicate.owner = root

	var packed := PackedScene.new()
	var pack_error: Error = packed.pack(root)
	root.free()
	if pack_error != OK:
		return null
	return packed


func _content_probe_entity() -> String:
	return "\n".join([
		"// semantic content-id runtime probe entity",
		"{",
		"\"classname\" \"func_detail\"",
		"\"persistent_id\" \"pid-content-probe\"",
		"\"content_id\" \"door.vault\"",
		"{",
		"( 320 -8 0 ) ( 320 -7 0 ) ( 320 -8 1 ) zebra/zebra16x16 [ 0 -1 0 0 ] [ 0 0 -1 0 ] 0 1 1",
		"( 320 -8 0 ) ( 320 -8 1 ) ( 321 -8 0 ) zebra/zebra16x16 [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1",
		"( 320 -8 0 ) ( 321 -8 0 ) ( 320 -7 0 ) zebra/zebra16x16 [ -1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1",
		"( 336 8 4 ) ( 336 9 4 ) ( 337 8 4 ) zebra/zebra16x16 [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1",
		"( 336 8 4 ) ( 337 8 4 ) ( 336 8 5 ) zebra/zebra16x16 [ -1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1",
		"( 336 8 4 ) ( 336 8 5 ) ( 336 9 4 ) zebra/zebra16x16 [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1",
		"}",
		"}",
	])


func _errors_contain(result: Dictionary, needle: String) -> bool:
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	for error_message: String in errors:
		if error_message.contains(needle):
			return true
	return false


func _remove_content_probe_map() -> void:
	if FileAccess.file_exists(CONTENT_RUNTIME_MAP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONTENT_RUNTIME_MAP_PATH))
