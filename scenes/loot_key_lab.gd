extends Node3D


@onready var status_label: Label3D = $Status


func _process(_delta: float) -> void:
	var session: Node = get_parent()
	var player := get_node_or_null("Player") as Node
	if session == null or player == null:
		return
	var run_summary: Dictionary = (
		session.call("get_mission_run_summary")
		if session.has_method("get_mission_run_summary")
		else {}
	)
	var has_key: bool = (
		bool(player.call("has_semantic_possession", &"key.lab"))
		if player.has_method("has_semantic_possession")
		else false
	)
	status_label.text = (
		"KEY key.lab: %s\nLOOT: %d items / %d value"
		% [
			"OWNED" if has_key else "not owned",
			int(run_summary.get("loot_count", 0)),
			int(run_summary.get("loot_value", 0)),
		]
	)
