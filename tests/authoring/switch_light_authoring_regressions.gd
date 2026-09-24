extends RefCounted


const GameplayLight = preload("res://gameplay/visibility/gameplay_light.gd")
const LightSwitch = preload("res://gameplay/visibility/light_switch.gd")
const MAP_SETTINGS_PATH: String = "res://authoring/vark_map_settings.tres"
const VARK_TRENCHBROOM_CONFIG_PATH: String = "res://VarkTrenchBroom.tres"
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const TEMP_MAP_PATH: String = "user://vark_switch_light_authoring.map"


func run(root: Node, assert_true: Callable) -> void:
	var config := load(VARK_TRENCHBROOM_CONFIG_PATH) as TrenchBroomGameConfig
	var fgd_file: FuncGodotFGDFile = config.fgd_file if config != null else null
	var definitions: Dictionary[String, FuncGodotFGDEntityClass] = {}
	var exported_fgd: String = ""
	if fgd_file != null:
		definitions = fgd_file.get_entity_definitions()
		exported_fgd = fgd_file.build_class_text(
			FuncGodotFGDFile.FuncGodotTargetMapEditors.TRENCHBROOM
		)

	var light_def := definitions.get("vark_gameplay_light") as FuncGodotFGDPointClass
	var switch_def := definitions.get("vark_switch") as FuncGodotFGDPointClass
	var light_props: Dictionary = light_def.class_properties if light_def != null else {}
	var switch_props: Dictionary = switch_def.class_properties if switch_def != null else {}
	assert_true.call(
		light_def != null
		and switch_def != null
		and light_def.scene_file != null
		and light_def.scene_file.resource_path
			== "res://gameplay/visibility/GameplayLight.tscn"
		and switch_def.scene_file != null
		and switch_def.scene_file.resource_path
			== "res://gameplay/visibility/LightSwitch.tscn"
		and light_props.has("persistent_id")
		and light_props.has("gameplay_light_id")
		and light_props.has("control_id")
		and light_props.has("starts_on")
		and light_props.has("gameplay_strength")
		and light_props.has("omni_range")
		and light_props.has("fixture_model_path")
		and light_props.has("direct_interaction")
		and switch_props.has("switch_id")
		and switch_props.has("control_id")
		and switch_props.has("base_model_path")
		and switch_props.has("lever_model_path")
		and exported_fgd.contains("vark_gameplay_light")
		and exported_fgd.contains("vark_switch")
		and exported_fgd.contains("control_id"),
		"Vark TrenchBroom FGD exposes mapper-facing gameplay-light and switch point entities linked only by control_id"
	)

	var source: String = FileAccess.get_file_as_string(PLAYGROUND_SOURCE_PATH)
	if source.is_empty():
		assert_true.call(false, "6.5 authoring fixture reads the tracked Playground map")
		return
	var file := FileAccess.open(TEMP_MAP_PATH, FileAccess.WRITE)
	if file == null:
		assert_true.call(false, "6.5 authoring fixture can create a temporary mapper source")
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

	var lights: Array[VarkGameplayLight] = []
	var switches: Array[VarkLightSwitch] = []
	for node: Node in func_map.find_children("*", "", true, false):
		if node.get_script() == GameplayLight:
			lights.append(node as VarkGameplayLight)
		elif node.get_script() == LightSwitch:
			switches.append(node as VarkLightSwitch)
	lights.sort_custom(
		func(a: VarkGameplayLight, b: VarkGameplayLight) -> bool:
			return str(a.gameplay_light_id) < str(b.gameplay_light_id)
	)

	var valid: bool = lights.size() == 2 and switches.size() == 1
	if valid:
		valid = (
			lights[0].gameplay_light_id == &"authoring.room.a"
			and lights[1].gameplay_light_id == &"authoring.room.b"
			and lights[0].control_id == &"authoring.room"
			and lights[1].control_id == &"authoring.room"
			and switches[0].control_id == &"authoring.room"
			and switches[0].switch_id == &"authoring.room.switch"
			and lights[0].persistent_id == "pid-light-a"
			and lights[1].persistent_id == "pid-light-b"
			and not lights[1].starts_on
			and str(lights[0].fixture_model_path)
				== "res://assets/models/lights/wall_lamp.obj"
			and str(switches[0].base_model_path)
				== "res://assets/models/switches/wall_switch_plate.obj"
		)
	assert_true.call(
		valid,
		"FuncGodot builds two real saved gameplay lights plus one real switch from mapper properties without Godot-side node-path wiring"
	)

	func_map.free()
	_remove_temp_map()


func _probe_entities() -> String:
	return "\n".join([
		"// Phase 6.5 gameplay-light probe A",
		"{",
		"\"classname\" \"vark_gameplay_light\"",
		"\"origin\" \"384 0 96\"",
		"\"persistent_id\" \"pid-light-a\"",
		"\"gameplay_light_id\" \"authoring.room.a\"",
		"\"control_id\" \"authoring.room\"",
		"\"starts_on\" \"1\"",
		"\"gameplay_strength\" \"1.25\"",
		"\"omni_range\" \"6.0\"",
		"\"fixture_model_path\" \"res://assets/models/lights/wall_lamp.obj\"",
		"}",
		"// Phase 6.5 gameplay-light probe B",
		"{",
		"\"classname\" \"vark_gameplay_light\"",
		"\"origin\" \"448 0 96\"",
		"\"persistent_id\" \"pid-light-b\"",
		"\"gameplay_light_id\" \"authoring.room.b\"",
		"\"control_id\" \"authoring.room\"",
		"\"starts_on\" \"0\"",
		"}",
		"// Phase 6.5 switch probe",
		"{",
		"\"classname\" \"vark_switch\"",
		"\"origin\" \"416 64 48\"",
		"\"angle\" \"180\"",
		"\"switch_id\" \"authoring.room.switch\"",
		"\"control_id\" \"authoring.room\"",
		"\"base_model_path\" \"res://assets/models/switches/wall_switch_plate.obj\"",
		"\"lever_model_path\" \"res://assets/models/switches/wall_switch_lever.obj\"",
		"}",
	])


func _remove_temp_map() -> void:
	if FileAccess.file_exists(TEMP_MAP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_MAP_PATH))
