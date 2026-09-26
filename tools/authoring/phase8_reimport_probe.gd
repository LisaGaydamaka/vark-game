extends SceneTree


const WorldSession = preload("res://application/world_session.gd")
const MissionDefinitionResource = preload("res://missions/mission_definition.gd")
const PersistentIdSource = preload("res://tools/authoring/persistent_id_source.gd")

const WORKSPACE_PATH: String = "res://tests/authoring/workspace/mission.map"
const BASELINE_PATH: String = (
	"res://tests/authoring/workspace/phase8_reimport_baseline.bin"
)
const PLAYGROUND_DEFINITION_PATH: String = "res://missions/playground/mission.tres"
const PROOF_DOOR_ID: String = "phase8.workflow.door"
const PROOF_PROP_ID: String = "phase8.workflow.prop"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_print_usage()
		quit(2)
		return

	match args[0].to_lower():
		"snapshot":
			if FileAccess.file_exists(BASELINE_PATH):
				push_error(
					"Phase 8.2 baseline already exists. Use -- clear before intentionally replacing it."
				)
				quit(1)
				return
			var result: Dictionary = await capture_baseline(
				get_root(),
				WORKSPACE_PATH,
				BASELINE_PATH
			)
			if not bool(result.get("ok", false)):
				push_error(str(result.get("error", "Phase 8.2 snapshot failed.")))
				quit(1)
				return
			print("Phase 8.2 reimport baseline captured.")
			print("  source SHA-256: ", str(result.get("source_hash", "")))
			print("  geometry SHA-256: ", str(result.get("geometry_hash", "")))
			print(
				"  opening persistent_id: ",
				str(result.get("door_persistent_id", ""))
			)
			print(
				"  prop persistent_id:    ",
				str(result.get("prop_persistent_id", ""))
			)
			print("Now make the documented TrenchBroom geometry/entity edits and save.")
			quit(0)
		"verify":
			var result: Dictionary = await verify_against_baseline(
				get_root(),
				WORKSPACE_PATH,
				BASELINE_PATH
			)
			if not bool(result.get("ok", false)):
				push_error(str(result.get("error", "Phase 8.2 verification failed.")))
				quit(1)
				return
			print("Phase 8.2 reimport proof passed.")
			print(
				"  persistent IDs preserved: opening=%s prop=%s"
				% [
					str(result.get("door_persistent_id", "")),
					str(result.get("prop_persistent_id", "")),
				]
			)
			print("  world geometry changed and rebuilt successfully.")
			print("  both proof entity transforms changed without identity churn.")
			print("  fresh save capture retained both persistent owners.")
			print("  the pre-edit semantic save restored into the reimported world.")
			print("  verifier left the mapper .map source byte-for-byte unchanged.")
			quit(0)
		"clear":
			quit(0 if _clear_baseline(BASELINE_PATH) else 1)
		_:
			push_error("Unknown Phase 8.2 reimport probe command: %s" % args[0])
			_print_usage()
			quit(2)


static func capture_baseline(
	root: Node,
	map_path: String,
	baseline_path: String
) -> Dictionary:
	if FileAccess.file_exists(baseline_path):
		return _failure(
			"Phase 8.2 baseline already exists: %s" % baseline_path
		)

	var source_result: Dictionary = PersistentIdSource.read_source(map_path)
	if not bool(source_result.get("ok", false)):
		return _failure(str(source_result.get("error", "Could not read mapper source.")))
	var source: String = str(source_result.get("text", ""))
	var identity_check: Dictionary = _validate_source_identity(source)
	if not bool(identity_check.get("ok", false)):
		return identity_check

	var built: Dictionary = _build_session(root, map_path, 8201)
	if not bool(built.get("ok", false)):
		return built
	var session := built.get("session") as Node
	var entities: Dictionary = _resolve_proof_entities(session)
	if not bool(entities.get("ok", false)):
		_cleanup_session(session)
		return entities

	var door := entities.get("door") as Node3D
	var prop := entities.get("prop") as Node3D
	var door_persistent_id: String = str(
		door.call("get_persistent_id")
	).strip_edges()
	var prop_persistent_id: String = str(
		prop.call("get_persistent_id")
	).strip_edges()
	var door_authored_transform: Transform3D = door.global_transform
	var prop_authored_transform: Transform3D = prop.global_transform

	if not bool(session.call("begin_play")):
		_cleanup_session(session)
		return _failure("Baseline WorldSession could not enter PLAYING.")
	await root.get_tree().physics_frame
	await root.get_tree().process_frame

	var envelope: Dictionary = session.call("capture_save_envelope")
	if envelope.is_empty():
		_cleanup_session(session)
		return _failure("Could not capture a stable semantic save envelope.")
	var persistent: Dictionary = (
		(envelope.get("world_state", {}) as Dictionary).get(
			"persistent_entities",
			{}
		) as Dictionary
	)
	if (
		not persistent.has(door_persistent_id)
		or not persistent.has(prop_persistent_id)
	):
		_cleanup_session(session)
		return _failure(
			"Baseline save envelope does not contain both proof persistent owners."
		)

	var baseline: Dictionary = {
		"format": 1,
		"map_path": map_path,
		"source_hash": PersistentIdSource.source_sha256(source),
		"geometry_hash": _world_geometry_hash(source),
		"door_persistent_id": door_persistent_id,
		"prop_persistent_id": prop_persistent_id,
		"door_authored_transform": door_authored_transform,
		"prop_authored_transform": prop_authored_transform,
		"save_envelope": envelope.duplicate(true),
	}
	_cleanup_session(session)

	var absolute_path: String = ProjectSettings.globalize_path(baseline_path)
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_path.get_base_dir()
	)
	if make_dir_error != OK:
		return _failure(
			"Could not create Phase 8.2 baseline directory: %s"
			% error_string(make_dir_error)
		)
	var file := FileAccess.open(baseline_path, FileAccess.WRITE)
	if file == null:
		return _failure("Could not create Phase 8.2 baseline: %s" % baseline_path)
	file.store_var(baseline)
	file.flush()
	file.close()

	return {
		"ok": true,
		"error": "",
		"source_hash": baseline["source_hash"],
		"geometry_hash": baseline["geometry_hash"],
		"door_persistent_id": door_persistent_id,
		"prop_persistent_id": prop_persistent_id,
	}


static func verify_against_baseline(
	root: Node,
	map_path: String,
	baseline_path: String
) -> Dictionary:
	var baseline_result: Dictionary = _read_baseline(baseline_path)
	if not bool(baseline_result.get("ok", false)):
		return baseline_result
	var baseline: Dictionary = baseline_result.get("baseline", {})
	if (
		int(baseline.get("format", 0)) != 1
		or str(baseline.get("map_path", "")) != map_path
	):
		return _failure("Phase 8.2 baseline does not match this mapper workspace.")

	var source_result: Dictionary = PersistentIdSource.read_source(map_path)
	if not bool(source_result.get("ok", false)):
		return _failure(str(source_result.get("error", "Could not read edited source.")))
	var source: String = str(source_result.get("text", ""))
	var source_hash: String = PersistentIdSource.source_sha256(source)
	if source_hash == str(baseline.get("source_hash", "")):
		return _failure(
			"Mapper source is unchanged from the Phase 8.2 baseline; make the documented edits first."
		)
	var geometry_hash: String = _world_geometry_hash(source)
	if geometry_hash == str(baseline.get("geometry_hash", "")):
		return _failure(
			"World brush geometry did not change from the Phase 8.2 baseline."
		)
	var identity_check: Dictionary = _validate_source_identity(source)
	if not bool(identity_check.get("ok", false)):
		return identity_check

	var built: Dictionary = _build_session(root, map_path, 8202)
	if not bool(built.get("ok", false)):
		return built
	var session := built.get("session") as Node
	var entities: Dictionary = _resolve_proof_entities(session)
	if not bool(entities.get("ok", false)):
		_cleanup_session(session)
		return entities
	var door := entities.get("door") as Node3D
	var prop := entities.get("prop") as Node3D

	var expected_door_id: String = str(
		baseline.get("door_persistent_id", "")
	).strip_edges()
	var expected_prop_id: String = str(
		baseline.get("prop_persistent_id", "")
	).strip_edges()
	if (
		str(door.call("get_persistent_id")).strip_edges() != expected_door_id
		or str(prop.call("get_persistent_id")).strip_edges() != expected_prop_id
	):
		_cleanup_session(session)
		return _failure(
			"Reimport changed a proof object's persistent_id."
		)

	var baseline_door_transform: Transform3D = baseline.get(
		"door_authored_transform",
		Transform3D.IDENTITY
	)
	var baseline_prop_transform: Transform3D = baseline.get(
		"prop_authored_transform",
		Transform3D.IDENTITY
	)
	if door.global_transform.is_equal_approx(baseline_door_transform):
		_cleanup_session(session)
		return _failure("Proof opening transform did not change from the baseline.")
	if prop.global_transform.is_equal_approx(baseline_prop_transform):
		_cleanup_session(session)
		return _failure("Proof prop transform did not change from the baseline.")

	if not bool(session.call("begin_play")):
		_cleanup_session(session)
		return _failure("Edited WorldSession could not enter PLAYING.")
	await root.get_tree().physics_frame
	await root.get_tree().process_frame
	var edited_envelope: Dictionary = session.call("capture_save_envelope")
	if edited_envelope.is_empty():
		_cleanup_session(session)
		return _failure("Edited world could not capture a semantic save envelope.")
	var edited_persistent: Dictionary = (
		(edited_envelope.get("world_state", {}) as Dictionary).get(
			"persistent_entities",
			{}
		) as Dictionary
	)
	if (
		not edited_persistent.has(expected_door_id)
		or not edited_persistent.has(expected_prop_id)
	):
		_cleanup_session(session)
		return _failure(
			"Edited save capture lost one of the proof persistent owners."
		)
	_cleanup_session(session)

	var restore_build: Dictionary = _build_session(root, map_path, 8203)
	if not bool(restore_build.get("ok", false)):
		return restore_build
	var restore_session := restore_build.get("session") as Node
	var baseline_envelope: Dictionary = baseline.get("save_envelope", {})
	var baseline_world_state: Dictionary = baseline_envelope.get("world_state", {})
	var restore_ok: bool = (
		not baseline_envelope.is_empty()
		and bool(restore_session.call(
			"begin_restore_from_envelope",
			baseline_envelope
		))
		and bool(restore_session.call(
			"apply_restore_world_state",
			baseline_world_state
		))
		and bool(restore_session.call("complete_restore"))
	)
	if not restore_ok:
		var restore_error: String = str(
			restore_session.call("get_last_restore_error")
		)
		_cleanup_session(restore_session)
		return _failure(
			"Pre-edit semantic save did not restore after reimport: %s"
			% restore_error
		)

	var restored_entities: Dictionary = _resolve_proof_entities(restore_session)
	if not bool(restored_entities.get("ok", false)):
		_cleanup_session(restore_session)
		return restored_entities
	var restored_door := restored_entities.get("door") as Node
	var restored_prop := restored_entities.get("prop") as Node
	var baseline_persistent: Dictionary = (
		baseline_world_state.get("persistent_entities", {}) as Dictionary
	)
	if (
		restored_door.call("capture_semantic_state")
			!= baseline_persistent.get(expected_door_id, {})
		or restored_prop.call("capture_semantic_state")
			!= baseline_persistent.get(expected_prop_id, {})
	):
		_cleanup_session(restore_session)
		return _failure(
			"Restored proof owners do not match the pre-edit semantic snapshots."
		)
	_cleanup_session(restore_session)

	var source_after_result: Dictionary = PersistentIdSource.read_source(map_path)
	if (
		not bool(source_after_result.get("ok", false))
		or str(source_after_result.get("text", "")) != source
	):
		return _failure(
			"Phase 8.2 verifier changed the authoritative mapper source."
		)

	return {
		"ok": true,
		"error": "",
		"door_persistent_id": expected_door_id,
		"prop_persistent_id": expected_prop_id,
		"source_unchanged": true,
		"geometry_changed": true,
		"door_transform_changed": true,
		"prop_transform_changed": true,
		"fresh_save_contains_proof_owners": true,
		"baseline_save_restored": true,
	}


static func _build_session(
	root: Node,
	map_path: String,
	session_id: int
) -> Dictionary:
	var base_definition: Resource = load(PLAYGROUND_DEFINITION_PATH)
	if base_definition == null:
		return _failure("Could not load Playground MissionDefinition.")
	var world_scene := base_definition.get("world_scene") as PackedScene
	if world_scene == null:
		return _failure("Playground MissionDefinition has no world_scene.")

	var definition: Resource = MissionDefinitionResource.new()
	definition.set("mission_id", &"phase8_reimport_probe")
	definition.set("world_scene", world_scene)
	definition.set("map_source_path", map_path)
	definition.set(
		"player_start_selector",
		base_definition.get("player_start_selector")
	)
	definition.set(
		"mission_content_revision",
		base_definition.get("mission_content_revision")
	)

	var session: Node = WorldSession.new()
	session.name = "Phase8ReimportProbeSession"
	root.add_child(session)
	if not bool(session.call(
		"build",
		session_id,
		world_scene,
		definition
	)):
		_cleanup_session(session)
		return _failure("WorldSession could not build mapper source: %s" % map_path)
	return {
		"ok": true,
		"error": "",
		"session": session,
	}


static func _resolve_proof_entities(session: Node) -> Dictionary:
	var door_lookup: Dictionary = session.call(
		"lookup_content_entity",
		PROOF_DOOR_ID
	)
	var prop_lookup: Dictionary = session.call(
		"lookup_content_entity",
		PROOF_PROP_ID
	)
	var door := door_lookup.get("node") as Node3D
	var prop := prop_lookup.get("node") as Node3D
	if (
		not bool(door_lookup.get("ok", false))
		or not bool(prop_lookup.get("ok", false))
		or door == null
		or prop == null
		or not door.has_method("get_persistent_id")
		or not prop.has_method("get_persistent_id")
		or not door.has_method("capture_semantic_state")
		or not prop.has_method("capture_semantic_state")
	):
		return _failure(
			"Phase 8.2 source must contain the accepted proof opening and prop from 8.1."
		)
	return {
		"ok": true,
		"error": "",
		"door": door,
		"prop": prop,
	}


static func _validate_source_identity(source: String) -> Dictionary:
	var inspection: Dictionary = PersistentIdSource.inspect_source(source)
	if not bool(inspection.get("ok", false)):
		return _failure(
			str(inspection.get("error", "Could not inspect mapper identity."))
		)
	if not bool(inspection.get("valid", false)):
		return _failure(
			"Mapper source needs persistent-ID repair before the Phase 8.2 proof."
		)
	var dry_repair: Dictionary = PersistentIdSource.repair_source(
		source,
		func() -> String: return "vark_unexpected_phase8_reimport_repair"
	)
	if (
		not bool(dry_repair.get("ok", false))
		or bool(dry_repair.get("changed", false))
		or str(dry_repair.get("source", "")) != source
	):
		return _failure(
			"Valid mapper source would still be rewritten by persistent-ID repair."
		)
	return {"ok": true, "error": ""}


static func _world_geometry_hash(source: String) -> String:
	var geometry_lines: Array[String] = []
	var depth: int = 0
	var in_worldspawn: bool = false
	for line: String in source.split("\n", true):
		var stripped: String = line.strip_edges()
		if stripped == "{":
			depth += 1
			continue
		if stripped == "}":
			depth -= 1
			if in_worldspawn and depth == 0:
				break
			continue
		if depth == 1 and stripped == "\"classname\" \"worldspawn\"":
			in_worldspawn = true
			continue
		if in_worldspawn and depth >= 2 and stripped.begins_with("("):
			geometry_lines.append(stripped)
	return PersistentIdSource.source_sha256("\n".join(geometry_lines))


static func _read_baseline(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure(
			"Phase 8.2 baseline is missing. Run the snapshot command before editing."
		)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Could not read Phase 8.2 baseline: %s" % path)
	var value: Variant = file.get_var()
	file.close()
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("Phase 8.2 baseline is malformed.")
	return {
		"ok": true,
		"error": "",
		"baseline": value,
	}


static func _cleanup_session(session: Node) -> void:
	if session == null:
		return
	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")
	if session.get_parent() != null:
		session.get_parent().remove_child(session)
	session.free()


static func _clear_baseline(path: String) -> bool:
	if not FileAccess.file_exists(path):
		print("No Phase 8.2 baseline exists; nothing to clear.")
		return true
	var error: Error = DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)
	if error != OK:
		push_error(
			"Could not remove Phase 8.2 baseline: %s"
			% error_string(error)
		)
		return false
	print("Cleared Phase 8.2 reimport baseline.")
	return true


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}


func _print_usage() -> void:
	print("Phase 8.2 reimport/saveability probe")
	print("  -- snapshot  Capture ignored-workspace identities + a real semantic save before mapper edits.")
	print("  -- verify    Rebuild edited source, compare identities/transforms/geometry, capture a fresh save, and restore the pre-edit save.")
	print("  -- clear     Remove only the ignored Phase 8.2 baseline sidecar.")
