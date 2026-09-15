extends SceneTree


const PersistentIdSource = preload("res://tools/authoring/persistent_id_source.gd")
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const MAP_SETTINGS_PATH: String = "res://addons/func_godot/func_godot_default_map_settings.tres"
const TEMP_MAP_PATH: String = "user://vark_persistent_identity_feasibility.map"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
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
