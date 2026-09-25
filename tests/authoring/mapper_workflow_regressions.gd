extends RefCounted


const MapperWorkflowProbe = preload(
	"res://tools/authoring/mapper_workflow_probe.gd"
)
const OrdinaryDoor = preload("res://gameplay/doors/ordinary_door.gd")
const OrdinaryProp = preload("res://gameplay/props/ordinary_prop.gd")

const VARK_TRENCHBROOM_CONFIG_PATH: String = "res://VarkTrenchBroom.tres"
const PLAYGROUND_SOURCE_PATH: String = "res://missions/playground/mission.map"
const TEMP_MAP_PATH: String = "user://vark_phase8_mapper_workflow.map"


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

	var opening := definitions.get("vark_opening") as FuncGodotFGDPointClass
	var prop := definitions.get("vark_prop") as FuncGodotFGDPointClass
	var opening_properties: Dictionary = (
		opening.class_properties if opening != null else {}
	)
	var prop_properties: Dictionary = (
		prop.class_properties if prop != null else {}
	)
	var opening_descriptions: Dictionary = (
		opening.class_property_descriptions if opening != null else {}
	)
	var prop_descriptions: Dictionary = (
		prop.class_property_descriptions if prop != null else {}
	)
	var opening_choices: Dictionary = (
		opening_properties.get("opening_variant", {}) as Dictionary
	)
	var prop_choices: Dictionary = (
		prop_properties.get("prop_variant", {}) as Dictionary
	)
	var opening_variant_description: Variant = opening_descriptions.get(
		"opening_variant"
	)
	var prop_variant_description: Variant = prop_descriptions.get(
		"prop_variant"
	)

	assert_true.call(
		opening != null
		and prop != null
		and opening.scene_file != null
		and opening.scene_file.resource_path
			== "res://gameplay/doors/OrdinaryDoor.tscn"
		and prop.scene_file != null
		and prop.scene_file.resource_path
			== "res://gameplay/props/OrdinaryProp.tscn"
		and opening_choices.has("Ordinary opening")
		and opening_choices.get("Ordinary opening")
			== OrdinaryDoor.OPENING_VARIANT_ORDINARY
		and opening_choices.has("Narrow opening")
		and opening_choices.get("Narrow opening")
			== OrdinaryDoor.OPENING_VARIANT_NARROW
		and typeof(opening_variant_description) == TYPE_ARRAY
		and (opening_variant_description as Array).size() >= 2
		and (opening_variant_description as Array)[1]
			== OrdinaryDoor.OPENING_VARIANT_ORDINARY
		and typeof(opening_properties.get("visual_model_path")) == TYPE_STRING
		and str(opening_properties.get("visual_model_path", "sentinel")).is_empty()
		and typeof(prop_properties.get("prop_id")) == TYPE_STRING
		and str(prop_properties.get("prop_id", "")) == "prop"
		and prop_choices.has("Standard crate")
		and prop_choices.get("Standard crate")
			== OrdinaryProp.PROP_VARIANT_ORDINARY_CRATE
		and prop_choices.has("Tall crate")
		and prop_choices.get("Tall crate")
			== OrdinaryProp.PROP_VARIANT_TALL_CRATE
		and typeof(prop_variant_description) == TYPE_ARRAY
		and (prop_variant_description as Array).size() >= 2
		and (prop_variant_description as Array)[1]
			== OrdinaryProp.PROP_VARIANT_ORDINARY_CRATE
		and typeof(prop_properties.get("visual_model_path")) == TYPE_STRING
		and str(prop_properties.get("visual_model_path", "sentinel")).is_empty()
		and exported_fgd.contains("opening_variant(choices)")
		and exported_fgd.contains("prop_variant(choices)")
		and exported_fgd.contains("prop_id(string)"),
		"8.1 Vark FGD gives mappers explicit proven opening/prop variant choices while retaining blank optional model-path overrides on the shared gameplay scenes"
	)

	var source: String = FileAccess.get_file_as_string(PLAYGROUND_SOURCE_PATH)
	if source.is_empty():
		assert_true.call(
			false,
			"8.1 mapper workflow regression reads the tracked Playground map"
		)
		return
	var proof_entities: String = _proof_entities()
	assert_true.call(
		not proof_entities.contains("visual_model_path")
		and not proof_entities.contains("collision_size")
		and not proof_entities.contains(".tscn"),
		"8.1 representative mapper source selects reusable variants without generated-scene references or manual model/collision override keys"
	)

	var file := FileAccess.open(TEMP_MAP_PATH, FileAccess.WRITE)
	if file == null:
		assert_true.call(
			false,
			"8.1 mapper workflow regression creates disposable source"
		)
		return
	file.store_string(
		source.trim_suffix("\n")
		+ "\n"
		+ proof_entities
		+ "\n"
	)
	file.flush()
	file.close()

	var result: Dictionary = await MapperWorkflowProbe.verify_map(
		root,
		TEMP_MAP_PATH
	)
	var door_summary: Dictionary = result.get("door", {})
	var prop_summary: Dictionary = result.get("prop", {})
	var resolved_collision: Vector3 = prop_summary.get(
		"collision_size",
		Vector3.ZERO
	)
	assert_true.call(
		bool(result.get("ok", false))
		and bool(result.get("identity_valid", false))
		and bool(result.get("source_unchanged", false))
		and int(result.get("door_count", 0)) >= 1
		and int(result.get("prop_count", 0)) >= 1
		and door_summary.get("opening_variant", "")
			== OrdinaryDoor.OPENING_VARIANT_NARROW
		and door_summary.get("visual_model_path", "")
			== OrdinaryDoor.OPENING_VARIANT_NARROW_MODEL_PATH
		and prop_summary.get("prop_variant", "")
			== OrdinaryProp.PROP_VARIANT_TALL_CRATE
		and prop_summary.get("visual_model_path", "")
			== OrdinaryProp.PROP_VARIANT_TALL_MODEL_PATH
		and resolved_collision.is_equal_approx(
			OrdinaryProp.PROP_VARIANT_TALL_COLLISION_SIZE
		),
		"8.1 real FuncGodot build resolves mapper-selected narrow/tall variants onto the existing OrdinaryDoor/OrdinaryProp owners with compatible model/collision defaults and no source rewrite"
	)

	_remove_temp_map()


func _proof_entities() -> String:
	return "\n".join([
		"// Phase 8.1 mapper workflow opening proof",
		"{",
		"\"classname\" \"vark_opening\"",
		"\"origin\" \"512 128 32\"",
		"\"persistent_id\" \"pid-phase8-workflow-door\"",
		"\"door_id\" \"phase8.workflow.door\"",
		"\"opening_variant\" \"narrow\"",
		"}",
		"// Phase 8.1 mapper workflow prop proof",
		"{",
		"\"classname\" \"vark_prop\"",
		"\"origin\" \"576 128 32\"",
		"\"persistent_id\" \"pid-phase8-workflow-prop\"",
		"\"prop_id\" \"phase8.workflow.prop\"",
		"\"prop_variant\" \"tall_crate\"",
		"}",
	])


func _remove_temp_map() -> void:
	if FileAccess.file_exists(TEMP_MAP_PATH):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(TEMP_MAP_PATH)
		)
