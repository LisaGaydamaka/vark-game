extends SceneTree


const PersistentIdSource = preload("res://tools/authoring/persistent_id_source.gd")
const AUTHORED_SOURCE_PATH: String = "res://missions/playground/mission.map"
const WORKSPACE_PATH: String = "res://tests/authoring/workspace/mission.map"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_print_usage()
		quit(2)
		return

	match args[0].to_lower():
		"prepare":
			quit(0 if _prepare_workspace() else 1)
		"inspect":
			quit(0 if _inspect_workspace() else 1)
		"repair":
			quit(0 if _repair_workspace() else 1)
		_:
			push_error("Unknown persistent-identity probe command: %s" % args[0])
			_print_usage()
			quit(2)


func _prepare_workspace() -> bool:
	if FileAccess.file_exists(WORKSPACE_PATH):
		push_error(
			"Identity-proof workspace already exists; refusing to overwrite mapper work: %s"
			% WORKSPACE_PATH
		)
		return false

	var source_result: Dictionary = PersistentIdSource.read_source(AUTHORED_SOURCE_PATH)
	if not bool(source_result["ok"]):
		push_error(str(source_result["error"]))
		return false

	var workspace_absolute: String = ProjectSettings.globalize_path(WORKSPACE_PATH)
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(
		workspace_absolute.get_base_dir()
	)
	if make_dir_error != OK:
		push_error(
			"Could not create identity-proof workspace directory: %s"
			% error_string(make_dir_error)
		)
		return false

	var file := FileAccess.open(WORKSPACE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not create identity-proof workspace map: %s" % WORKSPACE_PATH)
		return false
	file.store_string(str(source_result["text"]))
	file.flush()
	file.close()

	print("Prepared mapper identity workspace from the real Playground source:")
	print("  source:    ", AUTHORED_SOURCE_PATH)
	print("  workspace: ", WORKSPACE_PATH)
	print("The workspace is ignored by Git and will not overwrite the authored mission.")
	return true


func _inspect_workspace() -> bool:
	var result: Dictionary = PersistentIdSource.inspect_file(WORKSPACE_PATH)
	if not bool(result["ok"]):
		push_error(str(result["error"]))
		return false
	_print_inspection(result)
	if not bool(result["valid"]):
		push_error(
			"Workspace identity source is not valid yet; run the repair command after saving mapper edits."
		)
		return false
	return true


func _repair_workspace() -> bool:
	var before: Dictionary = PersistentIdSource.read_source(WORKSPACE_PATH)
	if not bool(before["ok"]):
		push_error(str(before["error"]))
		return false
	var expected_hash: String = PersistentIdSource.source_sha256(str(before["text"]))
	var result: Dictionary = PersistentIdSource.repair_file(
		WORKSPACE_PATH,
		expected_hash
	)
	if not bool(result["ok"]):
		push_error(str(result["error"]))
		return false

	if bool(result["changed"]):
		print("Wrote persistent-ID repairs to the mapper workspace source:")
		for repair_variant: Variant in result["repairs"]:
			var repair: Dictionary = repair_variant
			print(
				"  entity %d %s: %s -> %s (%s)"
				% [
					int(repair["entity_index"]),
					str(repair["classname"]),
					str(repair["old_id"]),
					str(repair["new_id"]),
					str(repair["reason"]),
				]
			)
	else:
		print("No persistent-ID repair needed; valid source was left byte-for-byte unchanged.")

	var inspection: Dictionary = PersistentIdSource.inspect_file(WORKSPACE_PATH)
	if not bool(inspection["ok"]):
		push_error(str(inspection["error"]))
		return false
	_print_inspection(inspection)
	return bool(inspection["valid"])


func _print_inspection(result: Dictionary) -> void:
	print("Source SHA-256: ", str(result["source_hash"]))
	var candidates: Array = result["candidates"]
	if candidates.is_empty():
		print("No authored identity candidates are present yet.")
	else:
		print("Authored identity candidates:")
		for summary_variant: Variant in candidates:
			var summary: Dictionary = summary_variant
			var persistent_id: String = str(summary["persistent_id"])
			if persistent_id.is_empty():
				persistent_id = "<missing>"
			print(
				"  entity %d %-18s %s"
				% [
					int(summary["entity_index"]),
					str(summary["classname"]),
					persistent_id,
				]
			)
	print(
		"Identity status: %s (missing=%d, duplicate=%d)"
		% [
			"valid" if bool(result["valid"]) else "needs repair",
			(result["missing"] as Array).size(),
			(result["duplicates"] as Array).size(),
		]
	)


func _print_usage() -> void:
	print("Persistent identity authoring probe")
	print("  -- prepare  Copy the real Playground map into an ignored mapper workspace.")
	print("  -- inspect  Report authored persistent IDs in that workspace.")
	print("  -- repair   Repair missing/duplicate IDs in the workspace source.")
