extends RefCounted


const PersistentIdSource = preload("res://tools/authoring/persistent_id_source.gd")
const PlaygroundReimportProbe = preload("res://tools/authoring/playground_reimport_probe.gd")
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const TEMP_REIMPORT_MAP_PATH: String = "user://vark_reimport_stability.map"
const EXPECTED_CONTENT_IDS: Array[String] = [
	"default",
	"marker.playground_reference",
	"exit.default",
]


func run(root: Node, assert_true: Callable) -> void:
	_remove_temp_map()
	var source_result: Dictionary = PersistentIdSource.read_source(PLAYGROUND_SOURCE_PATH)
	assert_true.call(
		bool(source_result.get("ok", false)),
		"2.8 reimport regression reads the real Playground authored map"
	)
	if not bool(source_result.get("ok", false)):
		return

	var baseline_source: String = str(source_result["text"])
	var edited_source: String = _move_player_start_x(baseline_source, 32.0)
	assert_true.call(
		not edited_source.is_empty() and edited_source != baseline_source,
		"2.8 reimport regression makes one representative player-start mapper edit in a temporary source copy"
	)
	if edited_source.is_empty() or edited_source == baseline_source:
		return

	assert_true.call(
		_write_source(TEMP_REIMPORT_MAP_PATH, edited_source),
		"2.8 reimport regression writes only the disposable edited map copy"
	)
	if not FileAccess.file_exists(TEMP_REIMPORT_MAP_PATH):
		return

	var before_verify: String = _read_text(TEMP_REIMPORT_MAP_PATH)
	var baseline_verification: Dictionary = PlaygroundReimportProbe.verify_map(
		root,
		PLAYGROUND_SOURCE_PATH
	)
	var edited_verification: Dictionary = PlaygroundReimportProbe.verify_map(
		root,
		TEMP_REIMPORT_MAP_PATH
	)
	var after_verify: String = _read_text(TEMP_REIMPORT_MAP_PATH)
	assert_true.call(
		bool(baseline_verification.get("ok", false))
		and bool(edited_verification.get("ok", false))
		and before_verify == edited_source
		and after_verify == edited_source
		and str(edited_verification.get("source_hash", ""))
		== PersistentIdSource.source_sha256(edited_source),
		"Edited Playground source needs no persistent-ID repair and rebuild verification leaves it byte-for-byte unchanged"
	)

	if (
		not bool(baseline_verification.get("ok", false))
		or not bool(edited_verification.get("ok", false))
	):
		_remove_temp_map()
		return

	var baseline_points: Dictionary = baseline_verification["points"]
	var edited_points: Dictionary = edited_verification["points"]
	var identities_stable: bool = true
	for content_id: String in EXPECTED_CONTENT_IDS:
		identities_stable = (
			identities_stable
			and baseline_points.has(content_id)
			and edited_points.has(content_id)
			and str((baseline_points[content_id] as Dictionary)["persistent_id"])
			== str((edited_points[content_id] as Dictionary)["persistent_id"])
		)
	assert_true.call(
		identities_stable,
		"Representative edit/rebuild preserves every tracked Playground persistent_id and semantic content_id"
	)

	var baseline_start: Transform3D = (baseline_points["default"] as Dictionary)["global_transform"]
	var edited_start: Transform3D = (edited_points["default"] as Dictionary)["global_transform"]
	var baseline_marker: Transform3D = (
		baseline_points["marker.playground_reference"] as Dictionary
	)["global_transform"]
	var edited_marker: Transform3D = (
		edited_points["marker.playground_reference"] as Dictionary
	)["global_transform"]
	var baseline_exit: Transform3D = (baseline_points["exit.default"] as Dictionary)["global_transform"]
	var edited_exit: Transform3D = (edited_points["exit.default"] as Dictionary)["global_transform"]
	assert_true.call(
		not edited_start.is_equal_approx(baseline_start)
		and edited_marker.is_equal_approx(baseline_marker)
		and edited_exit.is_equal_approx(baseline_exit),
		"Rebuild consumes the intended mapper start edit without unrelated semantic-point transform churn"
	)

	_remove_temp_map()


func _move_player_start_x(source: String, offset: float) -> String:
	var lines: Array[String] = []
	for line: String in source.split("\n", true):
		lines.append(line)

	var depth: int = 0
	var in_player_start: bool = false
	var changed: bool = false
	for line_index: int in lines.size():
		var line: String = lines[line_index]
		var stripped: String = line.strip_edges()
		if stripped == "{":
			depth += 1
			continue
		if stripped == "}":
			if depth == 1:
				in_player_start = false
			depth -= 1
			continue
		if depth != 1:
			continue
		if stripped == "\"classname\" \"vark_player_start\"":
			in_player_start = true
			continue
		if not in_player_start or not stripped.begins_with("\"origin\" \""):
			continue

		var value: String = stripped.trim_prefix("\"origin\" \"").trim_suffix("\"")
		var coordinates: PackedStringArray = value.split(" ", false)
		if coordinates.size() != 3:
			return ""
		var prefix_length: int = line.find("\"")
		var prefix: String = line.substr(0, prefix_length) if prefix_length > 0 else ""
		lines[line_index] = "%s\"origin\" \"%s %s %s\"" % [
			prefix,
			str(float(coordinates[0]) + offset),
			coordinates[1],
			coordinates[2],
		]
		changed = true
		break

	return "\n".join(lines) if changed else ""


func _write_source(path: String, source: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(source)
	file.flush()
	file.close()
	return true


func _read_text(path: String) -> String:
	var result: Dictionary = PersistentIdSource.read_source(path)
	return str(result.get("text", "")) if bool(result.get("ok", false)) else ""


func _remove_temp_map() -> void:
	if FileAccess.file_exists(TEMP_REIMPORT_MAP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_REIMPORT_MAP_PATH))
