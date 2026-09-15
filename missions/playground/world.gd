extends Node3D


@onready var func_map: Node = $FuncGodotMap

var mission_definition: Resource = null


func configure_mission_definition(definition: Resource) -> bool:
	if is_inside_tree() or definition == null:
		return false
	mission_definition = definition
	return true


func _ready() -> void:
	assert(
		mission_definition != null,
		"The Playground must be instantiated through its MissionDefinition."
	)

	# MissionDefinition owns the package-local map source. The player-start
	# selector is metadata-only until Phase 2.7 introduces the real authored
	# TrenchBroom player-start entity; no transform is duplicated here.
	func_map.set("local_map_file", str(mission_definition.get("map_source_path")))
	func_map.call("build")
