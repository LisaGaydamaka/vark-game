extends RefCounted


const PersistentIdSource = preload("res://tools/authoring/persistent_id_source.gd")
const Phase8ReimportProbe = preload(
	"res://tools/authoring/phase8_reimport_probe.gd"
)

const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const TEMP_MAP_PATH: String = "user://vark_phase8_reimport.map"
const TEMP_BASELINE_PATH: String = "user://vark_phase8_reimport_baseline.bin"


func run(root: Node, assert_true: Callable) -> void:
	_cleanup()

	var source_result: Dictionary = PersistentIdSource.read_source(
		PLAYGROUND_SOURCE_PATH
	)
	assert_true.call(
		bool(source_result.get("ok", false)),
		"8.2 reimport proof reads the tracked Playground source"
	)
	if not bool(source_result.get("ok", false)):
		return
	var playground_source: String = str(source_result.get("text", ""))

	var baseline_source: String = (
		playground_source.trim_suffix("\n")
		+ "\n"
		+ _proof_entities(
			"64 0 16",
			"96 0 12"
		)
		+ "\n"
	)
	assert_true.call(
		_write_source(TEMP_MAP_PATH, baseline_source),
		"8.2 reimport proof writes a disposable mapper-style baseline with the accepted 8.1 opening/prop"
	)
	if not FileAccess.file_exists(TEMP_MAP_PATH):
		_cleanup()
		return

	var baseline_result: Dictionary = await Phase8ReimportProbe.capture_baseline(
		root,
		TEMP_MAP_PATH,
		TEMP_BASELINE_PATH
	)
	assert_true.call(
		bool(baseline_result.get("ok", false))
		and not str(baseline_result.get("door_persistent_id", "")).is_empty()
		and not str(baseline_result.get("prop_persistent_id", "")).is_empty(),
		"8.2 baseline captures stable proof identities and a real semantic save envelope before reimport"
	)
	if not bool(baseline_result.get("ok", false)):
		_cleanup()
		return

	var shifted_playground: String = _shift_brush_one_x(
		playground_source,
		16.0
	)
	assert_true.call(
		not shifted_playground.is_empty()
		and shifted_playground != playground_source,
		"8.2 automated fixture makes one real world-brush geometry edit"
	)
	if shifted_playground.is_empty():
		_cleanup()
		return

	var edited_source: String = (
		shifted_playground.trim_suffix("\n")
		+ "\n"
		+ _proof_entities(
			"96 0 16",
			"128 0 12"
		)
		+ "\n"
	)
	assert_true.call(
		_write_source(TEMP_MAP_PATH, edited_source),
		"8.2 automated fixture moves both model-backed proof entities without changing their persistent IDs"
	)
	var before_verify: String = _read_text(TEMP_MAP_PATH)
	var verify_result: Dictionary = await Phase8ReimportProbe.verify_against_baseline(
		root,
		TEMP_MAP_PATH,
		TEMP_BASELINE_PATH
	)
	var after_verify: String = _read_text(TEMP_MAP_PATH)
	assert_true.call(
		bool(verify_result.get("ok", false))
		and bool(verify_result.get("geometry_changed", false))
		and bool(verify_result.get("door_transform_changed", false))
		and bool(verify_result.get("prop_transform_changed", false))
		and bool(verify_result.get(
			"fresh_save_contains_proof_owners",
			false
		))
		and bool(verify_result.get("baseline_save_restored", false))
		and bool(verify_result.get("source_unchanged", false))
		and before_verify == edited_source
		and after_verify == edited_source
		and verify_result.get("door_persistent_id", "")
			== baseline_result.get("door_persistent_id", "")
		and verify_result.get("prop_persistent_id", "")
			== baseline_result.get("prop_persistent_id", ""),
		"8.2 geometry/entity reimport preserves authored identity, keeps both owners saveable, restores the pre-edit semantic save, and never rewrites source"
	)

	_cleanup()


func _proof_entities(door_origin: String, prop_origin: String) -> String:
	return "\n".join([
		"// Phase 8.2 persistent opening proof",
		"{",
		"\"classname\" \"vark_opening\"",
		"\"origin\" \"%s\"" % door_origin,
		"\"persistent_id\" \"pid-phase8-reimport-door\"",
		"\"door_id\" \"phase8.workflow.door\"",
		"\"opening_variant\" \"narrow\"",
		"}",
		"// Phase 8.2 persistent prop proof",
		"{",
		"\"classname\" \"vark_prop\"",
		"\"origin\" \"%s\"" % prop_origin,
		"\"persistent_id\" \"pid-phase8-reimport-prop\"",
		"\"prop_id\" \"phase8.workflow.prop\"",
		"\"prop_variant\" \"tall_crate\"",
		"}",
	])


func _shift_brush_one_x(source: String, offset: float) -> String:
	var marker_index: int = source.find("// brush 1")
	if marker_index < 0:
		return ""
	var block_start: int = source.find("\n{", marker_index)
	if block_start < 0:
		return ""
	var block_end: int = source.find("\n}", block_start + 2)
	if block_end < 0:
		return ""

	var block: String = source.substr(
		block_start,
		block_end + 2 - block_start
	)
	var replacements: Dictionary = {
		"( 32 ": "( %s " % str(32.0 + offset),
		"( 33 ": "( %s " % str(33.0 + offset),
		"( 64 ": "( %s " % str(64.0 + offset),
		"( 65 ": "( %s " % str(65.0 + offset),
	}
	var shifted: String = block
	for old_value: String in replacements:
		shifted = shifted.replace(
			old_value,
			str(replacements[old_value])
		)
	if shifted == block:
		return ""
	return (
		source.substr(0, block_start)
		+ shifted
		+ source.substr(block_end + 2)
	)


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
	return (
		str(result.get("text", ""))
		if bool(result.get("ok", false))
		else ""
	)


func _cleanup() -> void:
	for path: String in [TEMP_MAP_PATH, TEMP_BASELINE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
