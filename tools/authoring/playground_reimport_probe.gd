extends SceneTree


const WorldSession = preload("res://application/world_session.gd")
const MissionDefinitionResource = preload("res://missions/mission_definition.gd")
const PersistentIdSource = preload("res://tools/authoring/persistent_id_source.gd")
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const PLAYGROUND_DEFINITION_PATH: String = "res://missions/playground/mission.tres"
const EXPECTED_CONTENT_IDS: Array[String] = [
	"default",
	"marker.playground_reference",
	"exit.default",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result: Dictionary = verify_map(get_root(), PLAYGROUND_SOURCE_PATH)
	if not bool(result.get("ok", false)):
		push_error(str(result.get("error", "Playground reimport verification failed.")))
		quit(1)
		return

	print("Playground reimport verification passed with no persistent-ID repair:")
	print("  source SHA-256: ", str(result["source_hash"]))
	var points: Dictionary = result["points"]
	for content_id: String in EXPECTED_CONTENT_IDS:
		var point: Dictionary = points[content_id]
		var point_transform: Transform3D = point["global_transform"]
		print(
			"  %-28s persistent_id=%s origin=%s"
			% [
				content_id,
				str(point["persistent_id"]),
				str(point_transform.origin),
			]
		)
	print("The real Playground wrapper reached PLAYING from the current authored .map source.")
	quit(0)


static func verify_map(root: Node, map_path: String) -> Dictionary:
	var source_result: Dictionary = PersistentIdSource.read_source(map_path)
	if not bool(source_result.get("ok", false)):
		return _failure(str(source_result.get("error", "Could not read map source.")))
	var source: String = str(source_result["text"])
	var source_hash: String = PersistentIdSource.source_sha256(source)

	var inspection: Dictionary = PersistentIdSource.inspect_source(source)
	if not bool(inspection.get("ok", false)):
		return _failure(str(inspection.get("error", "Could not inspect map identity.")))
	if not bool(inspection.get("valid", false)):
		return _failure(
			"Playground source needs persistent-ID repair before rebuild "
			+ "(missing=%d, duplicate=%d)."
			% [
				(inspection.get("missing", []) as Array).size(),
				(inspection.get("duplicates", []) as Array).size(),
			]
		)

	var dry_repair: Dictionary = PersistentIdSource.repair_source(
		source,
		func() -> String: return "vark_unexpected_reimport_repair"
	)
	if (
		not bool(dry_repair.get("ok", false))
		or bool(dry_repair.get("changed", false))
		or str(dry_repair.get("source", "")) != source
		or str(dry_repair.get("source_hash", "")) != source_hash
	):
		return _failure("Ordinary reimport verification would require or rewrite persistent-ID source repair.")

	var base_definition: Resource = load(PLAYGROUND_DEFINITION_PATH)
	if base_definition == null:
		return _failure("Could not load the Playground MissionDefinition.")
	var world_scene: PackedScene = base_definition.get("world_scene") as PackedScene
	if world_scene == null:
		return _failure("Playground MissionDefinition has no world_scene.")

	var mission_definition: Resource = base_definition
	if map_path != str(base_definition.get("map_source_path")):
		mission_definition = MissionDefinitionResource.new()
		mission_definition.set("mission_id", &"playground_reimport_probe")
		mission_definition.set("world_scene", world_scene)
		mission_definition.set("map_source_path", map_path)
		mission_definition.set(
			"player_start_selector",
			base_definition.get("player_start_selector")
		)
		mission_definition.set(
			"mission_content_revision",
			base_definition.get("mission_content_revision")
		)

	var session: Node = WorldSession.new()
	session.name = "PlaygroundReimportProbeSession"
	root.add_child(session)
	if not bool(session.call("build", 2808, world_scene, mission_definition)):
		_cleanup_session(session)
		return _failure("WorldSession could not rebuild the Playground from %s." % map_path)
	if int(session.get("state")) != WorldSession.State.READY:
		_cleanup_session(session)
		return _failure("Rebuilt Playground did not reach WorldSession READY.")

	var points: Dictionary = {}
	for content_id: String in EXPECTED_CONTENT_IDS:
		var lookup: Dictionary = session.call("lookup_content_entity", content_id)
		if not bool(lookup.get("ok", false)):
			var lookup_error: String = str(lookup.get("error", "lookup failed"))
			_cleanup_session(session)
			return _failure(
				"Rebuilt Playground could not resolve content_id '%s': %s"
				% [content_id, lookup_error]
			)
		var node := lookup.get("node") as Node3D
		if (
			node == null
			or not node.has_method("get_persistent_id")
			or not node.has_method("get_content_id")
		):
			_cleanup_session(session)
			return _failure("Resolved content_id '%s' is not a Vark persistent point." % content_id)
		var persistent_id: String = str(node.call("get_persistent_id")).strip_edges()
		if persistent_id.is_empty() or str(node.call("get_content_id")) != content_id:
			_cleanup_session(session)
			return _failure("Resolved point '%s' lost its authored identity/content address." % content_id)
		points[content_id] = {
			"persistent_id": persistent_id,
			"content_id": content_id,
			"global_transform": node.global_transform,
		}

	var session_world := session.get("world") as Node
	var session_player := session.get("player") as Node3D
	var selected_start: Node3D = null
	if session_world != null:
		selected_start = session_world.get("selected_player_start") as Node3D
	var default_point: Dictionary = points["default"]
	var default_transform: Transform3D = default_point["global_transform"]
	if (
		selected_start == null
		or session_player == null
		or not session_player.global_transform.is_equal_approx(selected_start.global_transform)
		or not selected_start.global_transform.is_equal_approx(default_transform)
	):
		_cleanup_session(session)
		return _failure("Rebuilt Playground did not apply the authored default player-start transform to the real Player.")

	if not bool(session.call("begin_play")) or int(session.get("state")) != WorldSession.State.PLAYING:
		_cleanup_session(session)
		return _failure("Rebuilt Playground could not enter WorldSession PLAYING.")

	_cleanup_session(session)
	return {
		"ok": true,
		"error": "",
		"source_hash": source_hash,
		"points": points,
	}


static func _cleanup_session(session: Node) -> void:
	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")
	session.free()


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"source_hash": "",
		"points": {},
	}
