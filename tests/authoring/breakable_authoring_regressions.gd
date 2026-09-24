extends RefCounted


const ConfiguredBreakable = preload("res://gameplay/effects/configured_breakable.gd")
const MAP_SETTINGS_PATH: String = "res://authoring/vark_map_settings.tres"
const VARK_TRENCHBROOM_CONFIG_PATH: String = "res://VarkTrenchBroom.tres"
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const TEMP_MAP_PATH: String = "user://vark_breakable_authoring.map"


func run(_root: Node, assert_true: Callable) -> void:
	var config := load(VARK_TRENCHBROOM_CONFIG_PATH) as TrenchBroomGameConfig
	var fgd_file: FuncGodotFGDFile = config.fgd_file if config != null else null
	var definitions: Dictionary[String, FuncGodotFGDEntityClass] = {}
	var exported_fgd: String = ""
	if fgd_file != null:
		definitions = fgd_file.get_entity_definitions()
		exported_fgd = fgd_file.build_class_text(
			FuncGodotFGDFile.FuncGodotTargetMapEditors.TRENCHBROOM
		)

	var breakable_def := definitions.get("vark_breakable") as FuncGodotFGDPointClass
	var props: Dictionary = (
		breakable_def.class_properties
		if breakable_def != null
		else {}
	)
	assert_true.call(
		breakable_def != null
		and breakable_def.scene_file != null
		and breakable_def.scene_file.resource_path
			== "res://gameplay/effects/ConfiguredBreakable.tscn"
		and breakable_def.auto_apply_to_matching_node_properties
		and props.has("persistent_id")
		and props.has("content_id")
		and props.has("accepted_effect_id")
		and props.has("break_threshold")
		and props.has("visual_model_path")
		and props.has("collision_size")
		and props.has("base_color")
		and exported_fgd.contains("vark_breakable")
		and exported_fgd.contains("accepted_effect_id")
		and exported_fgd.contains("break_threshold"),
		"Vark TrenchBroom FGD exposes one explicit configured breakable/effect responder"
	)

	var source: String = FileAccess.get_file_as_string(PLAYGROUND_SOURCE_PATH)
	if source.is_empty():
		assert_true.call(false, "6.7 breakable authoring reads tracked Playground source")
		return
	var file := FileAccess.open(TEMP_MAP_PATH, FileAccess.WRITE)
	if file == null:
		assert_true.call(false, "6.7 breakable authoring creates temporary mapper source")
		return
	file.store_string(
		source.trim_suffix("\n")
		+ "\n"
		+ _probe_entity()
		+ "\n"
	)
	file.flush()
	file.close()

	var func_map := FuncGodotMap.new()
	func_map.map_settings = load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	func_map.local_map_file = TEMP_MAP_PATH
	func_map.build()

	var breakables: Array[VarkConfiguredBreakable] = []
	for node: Node in func_map.find_children("*", "", true, false):
		if node.get_script() == ConfiguredBreakable:
			breakables.append(node as VarkConfiguredBreakable)

	var valid: bool = breakables.size() == 1
	if valid:
		var target: VarkConfiguredBreakable = breakables[0]
		valid = (
			target.persistent_id == "pid-breakable-panel"
			and target.content_id == "breakable.authoring.panel"
			and target.accepted_effect_id == &"impact"
			and is_equal_approx(target.break_threshold, 2.25)
			and target.collision_size.is_equal_approx(Vector3(1.2, 1.4, 0.2))
		)
	assert_true.call(
		valid,
		"FuncGodot builds a real configured breakable from mapper identity/effect/threshold/collision properties"
	)

	func_map.free()
	_remove_temp_map()


func _probe_entity() -> String:
	return "\n".join([
		"// Phase 6.7 configured breakable probe",
		"{",
		"\"classname\" \"vark_breakable\"",
		"\"origin\" \"384 128 32\"",
		"\"persistent_id\" \"pid-breakable-panel\"",
		"\"content_id\" \"breakable.authoring.panel\"",
		"\"accepted_effect_id\" \"impact\"",
		"\"break_threshold\" \"2.25\"",
		"\"collision_size\" \"1.2 1.4 0.2\"",
		"}",
	])


func _remove_temp_map() -> void:
	if FileAccess.file_exists(TEMP_MAP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_MAP_PATH))
