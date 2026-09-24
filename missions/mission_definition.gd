class_name MissionDefinition
extends Resource


const MissionFacts = preload("res://missions/mission_facts.gd")
const MissionRules = preload("res://missions/mission_rules.gd")


@export var mission_id: StringName = &""
@export var world_scene: PackedScene
@export_file("*.map") var map_source_path: String = ""
@export var player_start_selector: StringName = &""
@export var mission_content_revision: int = 1
@export var mission_fact_declarations: Array[Dictionary] = []
@export var mission_rule_declarations: Array[Dictionary] = []


func get_load_errors() -> PackedStringArray:
	var errors := PackedStringArray()

	if str(mission_id).strip_edges().is_empty():
		errors.append("mission_id must not be empty.")
	if world_scene == null:
		errors.append("world_scene must reference a PackedScene.")
	if map_source_path.strip_edges().is_empty():
		errors.append("map_source_path must point at the authoritative mission .map source.")
	elif not FileAccess.file_exists(map_source_path):
		errors.append("map_source_path does not exist: %s" % map_source_path)
	if str(player_start_selector).strip_edges().is_empty():
		errors.append("player_start_selector must not be empty.")
	if mission_content_revision <= 0:
		errors.append("mission_content_revision must be greater than zero.")

	var fact_errors: PackedStringArray = MissionFacts.validate_declarations(
		mission_fact_declarations
	)
	for fact_error: String in fact_errors:
		errors.append(fact_error)

	var rule_errors: PackedStringArray = MissionRules.validate_declarations(
		mission_rule_declarations,
		mission_fact_declarations
	)
	for rule_error: String in rule_errors:
		errors.append(rule_error)

	return errors


func is_loadable() -> bool:
	return get_load_errors().is_empty()
