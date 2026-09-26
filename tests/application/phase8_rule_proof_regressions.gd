extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const WorldSession = preload("res://application/world_session.gd")
const MissionFacts = preload("res://missions/mission_facts.gd")
const RULE_DEFINITION: Resource = preload(
	"res://missions/rule_proof/mission.tres"
)

const FACT_SECURITY_CUT: StringName = &"security_cut"
const OBJECTIVE_SECURITY_CUT: StringName = &"objective.security_cut"
const SWITCH_USED: StringName = &"switch.used"
const FACT_SET_REQUESTED: StringName = &"mission.fact_set_requested"
const FACT_CHANGED: StringName = &"mission.fact_changed"
const OBJECTIVE_ACTIVATE_REQUESTED: StringName = &"objective.activate_requested"
const OBJECTIVE_STATE_CHANGED: StringName = &"objective.state_changed"
const EXPECTED_FIRED_RULES: Array[String] = [
	"rule.security_cut.activate_objective",
	"rule.security_cut.latch",
]


func run(tree: SceneTree, assert_true: Callable) -> void:
	var application: Node = ApplicationScene.instantiate()
	var labels: PackedStringArray = application.get("development_launch_labels")
	var paths: PackedStringArray = application.get(
		"development_launch_resource_paths"
	)
	var target_index: int = labels.find("Rule Proof")
	assert_true.call(
		target_index >= 0
		and target_index < paths.size()
		and paths[target_index] == "res://missions/rule_proof/mission.tres",
		"8.3 Rule Proof is a curated Development Launch MissionDefinition target"
	)
	application.free()

	var load_errors: PackedStringArray = RULE_DEFINITION.call("get_load_errors")
	var fact_declarations: Array[Dictionary] = RULE_DEFINITION.get(
		"mission_fact_declarations"
	)
	var rule_declarations: Array[Dictionary] = RULE_DEFINITION.get(
		"mission_rule_declarations"
	)
	assert_true.call(
		load_errors.is_empty()
		and RULE_DEFINITION.get("mission_id") == &"phase8_rule_proof"
		and str(RULE_DEFINITION.get("map_source_path"))
			== "res://missions/rule_proof/mission.map"
		and fact_declarations.size() == 1
		and fact_declarations[0].get("key", &"") == FACT_SECURITY_CUT
		and fact_declarations[0].get("type", &"")
			== MissionFacts.VALUE_TYPE_BOOL
		and fact_declarations[0].get("scope", &"")
			== MissionFacts.SCOPE_MISSION
		and fact_declarations[0].get("default", null) == false
		and rule_declarations.size() == 2,
		"8.3 representative mission owns one latched mission fact plus two valid small-data rules"
	)

	var session: Node = WorldSession.new()
	session.name = "Phase8RuleProofWorldSession"
	tree.get_root().add_child(session)
	var built: bool = bool(session.call(
		"build",
		83001,
		RULE_DEFINITION.get("world_scene"),
		RULE_DEFINITION
	))
	var world := session.get("world") as Node
	var player := session.get("player") as Node
	var rules: RefCounted = (
		session.call("get_mission_rules") as RefCounted
		if built
		else null
	)
	var switch: Node = _find_first_in_group(world, &"vark_light_switch")
	var lights: Array[Node] = _find_in_group(world, &"vark_gameplay_light")
	var initial_objective: Dictionary = (
		session.call("query_mission_objective", OBJECTIVE_SECURITY_CUT)
		if built
		else {}
	)
	var wrapper_script: Script = (
		world.get_script() as Script
		if world != null
		else null
	)
	assert_true.call(
		built
		and world != null
		and player != null
		and rules != null
		and switch != null
		and lights.size() == 1
		and wrapper_script != null
		and wrapper_script.resource_path == "res://missions/playground/world.gd"
		and session.call("get_mission_fact", FACT_SECURITY_CUT, null) == false
		and bool(initial_objective.get("ok", false))
		and initial_objective.get("state", &"") == &"inactive"
		and bool(lights[0].call("is_enabled_state")),
		"8.3 real TrenchBroom switch/light mission starts with inactive objective and uses only the shared mission wrapper plus generic owners"
	)
	if (
		not built
		or world == null
		or player == null
		or rules == null
		or switch == null
		or lights.size() != 1
	):
		session.call("teardown")
		session.queue_free()
		await tree.process_frame
		return

	assert_true.call(
		bool(session.call("begin_play")),
		"8.3 rule proof enters PLAYING through the normal WorldSession lifecycle"
	)
	switch.call("interact", player)
	var immediate_objective: Dictionary = session.call(
		"query_mission_objective",
		OBJECTIVE_SECURITY_CUT
	)
	assert_true.call(
		not bool(lights[0].call("is_enabled_state"))
		and session.call("get_mission_fact", FACT_SECURITY_CUT, null) == false
		and immediate_objective.get("state", &"") == &"inactive"
		and int(session.call("get_pending_semantic_event_count")) > 0,
		"8.3 real switch interaction may change switch-owned light truth immediately but authored fact/objective consequences wait for the controlled semantic pass"
	)

	await _settle(tree)
	var active_objective: Dictionary = session.call(
		"query_mission_objective",
		OBJECTIVE_SECURITY_CUT
	)
	var rule_state: Dictionary = rules.call("capture_semantic_state")
	var objective_owner := world.get_node_or_null("ObjectiveState") as Node
	var objective_debug: Dictionary = (
		objective_owner.call("get_debug_summary")
		if objective_owner != null
		else {}
	)
	var trace: Array[Dictionary] = session.call(
		"get_recent_semantic_event_trace"
	)
	var switch_index: int = _trace_index(trace, SWITCH_USED)
	var fact_request_index: int = _trace_index(
		trace,
		FACT_SET_REQUESTED,
		switch_index + 1
	)
	var fact_changed_index: int = _trace_index(
		trace,
		FACT_CHANGED,
		fact_request_index + 1
	)
	var objective_request_index: int = _trace_index(
		trace,
		OBJECTIVE_ACTIVATE_REQUESTED,
		fact_changed_index + 1
	)
	var objective_changed_index: int = _trace_index(
		trace,
		OBJECTIVE_STATE_CHANGED,
		objective_request_index + 1
	)
	assert_true.call(
		session.call("get_mission_fact", FACT_SECURITY_CUT, null) == true
		and active_objective.get("state", &"") == &"active"
		and int(objective_debug.get("objective_activation_count", 0)) == 1
		and rule_state.get("fired_one_shot_rule_ids", []) == EXPECTED_FIRED_RULES
		and switch_index >= 0
		and fact_request_index > switch_index
		and fact_changed_index > fact_request_index
		and objective_request_index > fact_changed_index
		and objective_changed_index > objective_request_index,
		"8.3 common mission logic runs entirely through the small rule grammar and existing FIFO semantic owners"
	)

	switch.call("interact", player)
	await _settle(tree)
	switch.call("interact", player)
	await _settle(tree)
	objective_debug = objective_owner.call("get_debug_summary")
	assert_true.call(
		session.call("get_mission_fact", FACT_SECURITY_CUT, null) == true
		and session.call(
			"query_mission_objective",
			OBJECTIVE_SECURITY_CUT
		).get("state", &"") == &"active"
		and int(objective_debug.get("objective_activation_count", 0)) == 1
		and int(rules.call("get_debug_summary").get("match_count", 0)) == 2
		and rules.call("capture_semantic_state").get(
			"fired_one_shot_rule_ids",
			[]
		) == EXPECTED_FIRED_RULES,
		"8.3 repeated ordinary switch use does not replay one-shot authored mission consequences"
	)

	var envelope: Dictionary = session.call("capture_save_envelope")
	assert_true.call(
		not envelope.is_empty()
		and (envelope.get("world_state", {}) as Dictionary).get(
			"mission_facts",
			{}
		).get("security_cut", false) == true
		and (envelope.get("world_state", {}) as Dictionary).get(
			"mission_rules",
			{}
		).get("fired_one_shot_rule_ids", []) == EXPECTED_FIRED_RULES,
		"8.3 representative authored fact and one-shot rule execution are stable-boundary save truth"
	)

	session.call("teardown")
	var rebuilt: bool = bool(session.call(
		"build",
		83002,
		RULE_DEFINITION.get("world_scene"),
		RULE_DEFINITION
	))
	var restore_world_state: Dictionary = envelope.get("world_state", {})
	var restore_began: bool = (
		bool(session.call("begin_restore_from_envelope", envelope))
		if rebuilt
		else false
	)
	var restore_applied: bool = (
		bool(session.call("apply_restore_world_state", restore_world_state))
		if restore_began
		else false
	)
	var restore_completed: bool = (
		bool(session.call("complete_restore"))
		if restore_applied
		else false
	)
	var restored_world := session.get("world") as Node
	var restored_switch: Node = _find_first_in_group(
		restored_world,
		&"vark_light_switch"
	)
	var restored_lights: Array[Node] = _find_in_group(
		restored_world,
		&"vark_gameplay_light"
	)
	var restored_rules: RefCounted = (
		session.call("get_mission_rules") as RefCounted
		if rebuilt
		else null
	)
	var restored_objective_owner := (
		restored_world.get_node_or_null("ObjectiveState") as Node
		if restored_world != null
		else null
	)
	assert_true.call(
		rebuilt
		and restore_began
		and restore_applied
		and restore_completed
		and restored_switch != null
		and restored_lights.size() == 1
		and restored_rules != null
		and restored_objective_owner != null
		and session.call("get_mission_fact", FACT_SECURITY_CUT, null) == true
		and session.call(
			"query_mission_objective",
			OBJECTIVE_SECURITY_CUT
		).get("state", &"") == &"active"
		and not bool(restored_lights[0].call("is_enabled_state"))
		and restored_rules.call("capture_semantic_state").get(
			"fired_one_shot_rule_ids",
			[]
		) == EXPECTED_FIRED_RULES
		and int(
			restored_objective_owner.call(
				"get_debug_summary"
			).get("objective_activation_count", 0)
		) == 1,
		"8.3 save/restore preserves the authored latch, objective state, light truth, and fired one-shot rules without replaying consequences"
	)

	if (
		rebuilt
		and restore_completed
		and restored_switch != null
		and restored_lights.size() == 1
	):
		assert_true.call(
			bool(session.call("begin_play")),
			"8.3 restored representative mission resumes through normal lifecycle"
		)
		var restored_player := session.get("player") as Node
		restored_switch.call("interact", restored_player)
		await _settle(tree)
		restored_switch.call("interact", restored_player)
		await _settle(tree)
		var restored_debug: Dictionary = restored_objective_owner.call(
			"get_debug_summary"
		)
		assert_true.call(
			session.call("get_mission_fact", FACT_SECURITY_CUT, null) == true
			and session.call(
				"query_mission_objective",
				OBJECTIVE_SECURITY_CUT
			).get("state", &"") == &"active"
			and int(restored_debug.get("objective_activation_count", 0)) == 1
			and int(restored_rules.call("get_debug_summary").get(
				"match_count",
				0
			)) == 0,
			"8.3 restored one-shot rules stay suppressed while ordinary switch gameplay continues"
		)

	session.call("teardown")
	session.queue_free()
	await tree.process_frame


func _find_first_in_group(root: Node, group_name: StringName) -> Node:
	var nodes: Array[Node] = _find_in_group(root, group_name)
	return nodes[0] if not nodes.is_empty() else null


func _find_in_group(root: Node, group_name: StringName) -> Array[Node]:
	var result: Array[Node] = []
	if root == null:
		return result
	if root.is_in_group(group_name):
		result.append(root)
	for node: Node in root.find_children("*", "", true, false):
		if node.is_in_group(group_name):
			result.append(node)
	return result


func _trace_index(
	trace: Array[Dictionary],
	event_name: StringName,
	start_index: int = 0
) -> int:
	for index: int in range(maxi(start_index, 0), trace.size()):
		if trace[index].get("name", &"") == event_name:
			return index
	return -1


func _settle(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
