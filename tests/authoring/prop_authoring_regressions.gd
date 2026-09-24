extends RefCounted


const OrdinaryProp = preload("res://gameplay/props/ordinary_prop.gd")
const MAP_SETTINGS_PATH: String = "res://authoring/vark_map_settings.tres"
const VARK_TRENCHBROOM_CONFIG_PATH: String = "res://VarkTrenchBroom.tres"
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const TEMP_MAP_PATH: String = "user://vark_prop_authoring.map"


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

	var prop_def := definitions.get("vark_prop") as FuncGodotFGDPointClass
	var prop_properties: Dictionary = prop_def.class_properties if prop_def != null else {}
	assert_true.call(
		prop_def != null
		and prop_def.scene_file != null
		and prop_def.scene_file.resource_path == "res://gameplay/props/OrdinaryProp.tscn"
		and prop_def.auto_apply_to_matching_node_properties
		and prop_properties.has("persistent_id")
		and prop_properties.has("prop_id")
		and prop_properties.has("prop_variant")
		and prop_properties.has("visual_model_path")
		and prop_properties.has("collision_size")
		and prop_properties.has("base_color")
		and prop_properties.has("throw_speed")
		and prop_properties.has("impact_sound_strength")
		and prop_properties.has("gentle_release_sound_scale")
		and exported_fgd.contains("vark_prop")
		and exported_fgd.contains("visual_model_path")
		and exported_fgd.contains("collision_size"),
		"Vark TrenchBroom FGD exposes one mapper-facing ordinary physical-prop archetype with model/variant/collision configuration"
	)

	var source: String = FileAccess.get_file_as_string(PLAYGROUND_SOURCE_PATH)
	if source.is_empty():
		assert_true.call(false, "6.6 prop authoring fixture reads the tracked Playground map")
		return
	var file := FileAccess.open(TEMP_MAP_PATH, FileAccess.WRITE)
	if file == null:
		assert_true.call(false, "6.6 prop authoring fixture can create temporary mapper source")
		return
	file.store_string(
		source.trim_suffix("\n")
		+ "\n"
		+ _probe_entities()
		+ "\n"
	)
	file.flush()
	file.close()

	var func_map := FuncGodotMap.new()
	func_map.map_settings = load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	func_map.local_map_file = TEMP_MAP_PATH
	func_map.build()

	var props: Array[VarkOrdinaryProp] = []
	for node: Node in func_map.find_children("*", "", true, false):
		if node.get_script() == OrdinaryProp:
			props.append(node as VarkOrdinaryProp)
	props.sort_custom(
		func(a: VarkOrdinaryProp, b: VarkOrdinaryProp) -> bool:
			return str(a.prop_id) < str(b.prop_id)
	)

	var valid: bool = props.size() == 2
	if valid:
		valid = (
			props[0].persistent_id == "pid-prop-standard"
			and props[0].prop_id == &"authoring.prop.standard"
			and props[0].prop_variant == "ordinary_crate"
			and props[0].visual_model_path
				== "res://assets/models/props/ordinary_crate.obj"
			and props[0].collision_size.is_equal_approx(Vector3(0.6, 0.6, 0.6))
			and is_equal_approx(props[0].throw_speed, 5.5)
			and props[1].persistent_id == "pid-prop-tall"
			and props[1].prop_id == &"authoring.prop.tall"
			and props[1].prop_variant == "tall_crate"
			and props[1].visual_model_path
				== "res://assets/models/props/ordinary_crate_tall.obj"
			and props[1].collision_size.is_equal_approx(Vector3(0.5, 0.7, 0.5))
			and is_equal_approx(props[1].impact_sound_strength, 0.72)
		)
	assert_true.call(
		valid,
		"FuncGodot builds standard and tall real OrdinaryProp instances from mapper properties without variant-specific gameplay scenes"
	)

	func_map.free()
	_remove_temp_map()


func _probe_entities() -> String:
	return "\n".join([
		"// Phase 6.6 ordinary prop probe A",
		"{",
		"\"classname\" \"vark_prop\"",
		"\"origin\" \"384 128 32\"",
		"\"persistent_id\" \"pid-prop-standard\"",
		"\"prop_id\" \"authoring.prop.standard\"",
		"\"prop_variant\" \"ordinary_crate\"",
		"\"visual_model_path\" \"res://assets/models/props/ordinary_crate.obj\"",
		"\"collision_size\" \"0.6 0.6 0.6\"",
		"\"throw_speed\" \"5.5\"",
		"}",
		"// Phase 6.6 ordinary prop probe B",
		"{",
		"\"classname\" \"vark_prop\"",
		"\"origin\" \"448 128 32\"",
		"\"persistent_id\" \"pid-prop-tall\"",
		"\"prop_id\" \"authoring.prop.tall\"",
		"\"prop_variant\" \"tall_crate\"",
		"\"visual_model_path\" \"res://assets/models/props/ordinary_crate_tall.obj\"",
		"\"collision_size\" \"0.5 0.7 0.5\"",
		"\"impact_sound_strength\" \"0.72\"",
		"}",
	])


func _remove_temp_map() -> void:
	if FileAccess.file_exists(TEMP_MAP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_MAP_PATH))
