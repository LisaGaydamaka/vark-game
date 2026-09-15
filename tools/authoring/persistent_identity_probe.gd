extends SceneTree


const PersistentIdSource = preload("res://tools/authoring/persistent_id_source.gd")
const AUTHORED_SOURCE_PATH: String = "res://missions/playground/mission.map"
const WORKSPACE_PATH: String = "res://tests/authoring/workspace/mission.map"
const VARK_TRENCHBROOM_CONFIG_PATH: String = "res://VarkTrenchBroom.tres"
const VARK_MATERIAL_ROOT: String = "textures"
const VARK_PROOF_MATERIAL_PATH: String = "res://textures/zebra/zebra16x16.png"


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
		"reset":
			quit(0 if _reset_workspace() else 1)
		"sync-config":
			quit(0 if _sync_trenchbroom_config() else 1)
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


func _reset_workspace() -> bool:
	if FileAccess.file_exists(WORKSPACE_PATH):
		var remove_error: Error = DirAccess.remove_absolute(
			ProjectSettings.globalize_path(WORKSPACE_PATH)
		)
		if remove_error != OK:
			push_error(
				"Could not remove the ignored identity-proof workspace map: %s"
				% error_string(remove_error)
			)
			return false
	print("Resetting ignored mapper identity workspace from authored Playground source.")
	return _prepare_workspace()


func _sync_trenchbroom_config() -> bool:
	var config_folder: String = str(
		FuncGodotLocalConfig.get_setting(
			FuncGodotLocalConfig.PROPERTY.TRENCHBROOM_GAME_CONFIG_FOLDER
		)
	).strip_edges()
	if config_folder.is_empty():
		push_error(
			"FuncGodot has no TrenchBroom Game Config Folder configured on this machine. "
			+ "Set it in res://addons/func_godot/func_godot_local_config.tres, export the local FuncGodot settings, then rerun sync-config."
		)
		return false

	var config := load(VARK_TRENCHBROOM_CONFIG_PATH) as TrenchBroomGameConfig
	if config == null or config.fgd_file == null:
		push_error("Could not load the Vark TrenchBroom configuration/FGD resource.")
		return false

	config.export_file()
	var fgd_path: String = config_folder.path_join(config.fgd_file.fgd_name + ".fgd")
	var game_config_path: String = config_folder.path_join("GameConfig.cfg")
	if not FileAccess.file_exists(fgd_path) or not FileAccess.file_exists(game_config_path):
		push_error(
			"Vark TrenchBroom config export did not produce the expected GameConfig.cfg and %s.fgd in %s"
			% [config.fgd_file.fgd_name, config_folder]
		)
		return false

	var fgd_text: String = FileAccess.get_file_as_string(fgd_path)
	if not fgd_text.contains("persistent_id"):
		push_error(
			"Exported Vark FGD does not declare persistent_id; refusing to continue the mapper proof."
		)
		return false

	var game_config_text: String = FileAccess.get_file_as_string(game_config_path)
	if not _validate_trenchbroom_material_config(config, game_config_text):
		return false

	print("Refreshed the installed Vark TrenchBroom game configuration:")
	print("  folder: ", config_folder)
	print("  FGD:    ", fgd_path)
	print("The exported Vark FGD declares persistent_id for func_detail.")
	print("The exported Vark material config resolves PNGs under textures/ with no palette dependency.")
	print("Close/reopen TrenchBroom before continuing so it reloads the updated game configuration.")
	return true


func _validate_trenchbroom_material_config(
	config: TrenchBroomGameConfig,
	game_config_text: String
) -> bool:
	if config.textures_root_folder != VARK_MATERIAL_ROOT:
		push_error(
			"Vark TrenchBroom material root must be '%s', got '%s'."
			% [VARK_MATERIAL_ROOT, config.textures_root_folder]
		)
		return false
	if not config.palette_path.strip_edges().is_empty():
		push_error(
			"Vark uses ordinary PNG materials and must not export a Quake palette dependency; palette_path is '%s'."
			% config.palette_path
		)
		return false
	if not FileAccess.file_exists(VARK_PROOF_MATERIAL_PATH):
		push_error(
			"Vark material probe source is missing: %s"
			% VARK_PROOF_MATERIAL_PATH
		)
		return false
	if (
		not game_config_text.contains("\"root\": \"%s\"" % VARK_MATERIAL_ROOT)
		or not game_config_text.contains("\".png\"")
		or not game_config_text.contains("\"palette\": \"\"")
	):
		push_error(
			"Exported Vark GameConfig.cfg does not advertise the expected textures/ PNG material path with an empty palette."
		)
		return false
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
	print("  -- sync-config  Export and validate the current Vark GameConfig/FGD in this machine's configured TrenchBroom game folder.")
	print("  -- prepare      Copy the real Playground map into an ignored mapper workspace.")
	print("  -- reset        Replace only the ignored workspace map with a fresh Playground copy.")
	print("  -- inspect      Report authored persistent IDs in that workspace.")
	print("  -- repair       Repair missing/duplicate IDs in the workspace source.")
