extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")
const WorldSession = preload("res://application/world_session.gd")
const MissionDefinition = preload("res://missions/mission_definition.gd")
const SessionWorkProbe = preload("res://tests/application/session_work_probe.gd")
const MenuShellRegressions = preload(
	"res://tests/application/menu_shell_regressions.gd"
)
const InputBoundaryRegressions = preload(
	"res://tests/application/input_boundary_regressions.gd"
)
const InteractionRegressions = preload(
	"res://tests/application/interaction_regressions.gd"
)
const SemanticEventRegressions = preload(
	"res://tests/application/semantic_event_regressions.gd"
)
const DoorRegressions = preload(
	"res://tests/application/door_regressions.gd"
)
const PauseArbitrationRegressions = preload(
	"res://tests/application/pause_arbitration_regressions.gd"
)
const SaveCoordinatorRegressions = preload(
	"res://tests/application/save_coordinator_regressions.gd"
)
const SemanticSnapshotRegressions = preload(
	"res://tests/application/semantic_snapshot_regressions.gd"
)
const PlayerRestorePolicyRegressions = preload(
	"res://tests/application/player_restore_policy_regressions.gd"
)
const TransientStateRestoreRegressions = preload(
	"res://tests/application/transient_state_restore_regressions.gd"
)
const SnapshotCoherenceRegressions = preload(
	"res://tests/application/snapshot_coherence_regressions.gd"
)
const SaveCompatibilityRegressions = preload(
	"res://tests/application/save_compatibility_regressions.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_assert_true(
		str(ProjectSettings.get_setting("application/run/main_scene", ""))
		== "res://application/Application.tscn",
		"F5 main scene is the Vark application root"
	)

	var playground_definition: Resource = load("res://missions/playground/mission.tres")
	var playground_load_errors := PackedStringArray()
	if playground_definition != null:
		playground_load_errors = playground_definition.call("get_load_errors")
	_assert_true(
		playground_definition != null
		and playground_definition.get_script() == MissionDefinition
		and playground_load_errors.is_empty()
		and playground_definition.get("mission_id") == &"playground"
		and (playground_definition.get("world_scene") as PackedScene).resource_path
		== "res://missions/playground/world.tscn"
		and str(playground_definition.get("map_source_path"))
		== "res://missions/playground/mission.map"
		and playground_definition.get("player_start_selector") == &"default"
		and int(playground_definition.get("mission_content_revision")) == 1,
		"Playground MissionDefinition owns the minimal load metadata"
	)
	var definition_properties: Array[String] = []
	if playground_definition != null:
		for property: Dictionary in playground_definition.get_property_list():
			definition_properties.append(str(property.get("name", "")))
	_assert_true(
		not definition_properties.has("player_start_transform")
		and not definition_properties.has("player_start_position")
		and not definition_properties.has("player_start_rotation"),
		"MissionDefinition selects a player start semantically without duplicating its transform"
	)
	var invalid_definition: Resource = MissionDefinition.new()
	invalid_definition.set("mission_content_revision", 0)
	var invalid_load_errors: PackedStringArray = invalid_definition.call("get_load_errors")
	_assert_true(
		invalid_load_errors.size() == 5,
		"MissionDefinition reports every currently required load field when invalid"
	)

	var interaction_regressions: RefCounted = InteractionRegressions.new()
	await interaction_regressions.run(
		self,
		Callable(self, "_assert_true")
	)

	var semantic_event_regressions: RefCounted = SemanticEventRegressions.new()
	await semantic_event_regressions.run(
		self,
		Callable(self, "_assert_true")
	)

	var door_regressions: RefCounted = DoorRegressions.new()
	await door_regressions.run(
		self,
		Callable(self, "_assert_true")
	)

	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["VarkTest", "Playground", "Alternate Fixture"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([
			"res://scenes/VarkTest.tscn",
			"res://missions/playground/mission.tres",
			"res://tests/application/fixtures/development_alternate_world.tscn",
		])
	)
	get_root().add_child(application)
	await process_frame

	var menu_regressions: RefCounted = MenuShellRegressions.new()
	await menu_regressions.run(
		self,
		application,
		Callable(self, "_assert_true")
	)

	var world_host: Node = application.get_node("WorldHost")
	var ui_root: CanvasLayer = application.get_node("UIRoot")
	var current_session: Node = application.get("current_session")
	var current_world: Node = application.get("current_world")
	var current_player: Node = application.get("current_player")
	var current_ui: CanvasLayer = application.get("current_ui")
	var session_id: int = int(application.call("get_current_session_id"))

	_assert_true(
		current_session != null
		and current_session.get_parent() == world_host
		and int(application.call("get_current_session_state")) == WorldSession.State.PLAYING,
		"Application owns one playing world session"
	)
	_assert_true(
		current_world != null
		and current_world.get_parent() == current_session
		and current_world.name == &"VarkTest",
		"Application owns the current development world through the session"
	)
	_assert_true(
		current_player != null
		and current_player.is_in_group(&"vark_player")
		and _is_descendant_of(current_player, current_world),
		"Application owns the current player through the semantic player marker"
	)
	_assert_true(
		current_ui == ui_root,
		"Application owns the persistent UI root"
	)
	_assert_true(
		session_id > 0 and bool(application.call("is_current_session", session_id)),
		"Application exposes the active world-session identity"
	)
	_assert_true(
		not bool(application.call("is_current_session", session_id + 1)),
		"Application rejects a stale/foreign world-session identity"
	)

	var began_restart: bool = bool(application.call(
		"try_begin_top_level_operation",
		ApplicationRoot.TopLevelOperation.RESTART
	))
	var overlapping_load: bool = bool(application.call(
		"try_begin_top_level_operation",
		ApplicationRoot.TopLevelOperation.LOAD
	))
	var wrong_finish: bool = bool(application.call(
		"finish_top_level_operation",
		ApplicationRoot.TopLevelOperation.LOAD
	))
	var correct_finish: bool = bool(application.call(
		"finish_top_level_operation",
		ApplicationRoot.TopLevelOperation.RESTART
	))
	_assert_true(
		began_restart
		and not overlapping_load
		and not wrong_finish
		and correct_finish
		and not bool(application.call("has_active_top_level_operation")),
		"Application serializes top-level world operations through one owner"
	)

	var input_regressions: RefCounted = InputBoundaryRegressions.new()
	await input_regressions.run(
		self,
		application,
		Callable(self, "_assert_true")
	)

	var pause_regressions: RefCounted = PauseArbitrationRegressions.new()
	await pause_regressions.run(
		self,
		application,
		Callable(self, "_assert_true")
	)

	var save_regressions: RefCounted = SaveCoordinatorRegressions.new()
	await save_regressions.run(
		self,
		application,
		Callable(self, "_assert_true")
	)

	var isolated_session: Node = WorldSession.new()
	isolated_session.name = "IsolatedWorldSession"
	get_root().add_child(isolated_session)
	var isolated_id: int = session_id + 1000
	var isolated_built: bool = bool(isolated_session.call(
		"build",
		isolated_id,
		application.get("default_world_scene") as PackedScene
	))
	var isolated_world: Node = isolated_session.get("world") as Node
	_assert_true(
		isolated_built
		and int(isolated_session.get("state")) == WorldSession.State.READY
		and isolated_world != null
		and not isolated_world.can_process()
		and isolated_session.get("mission_definition") == null
		and is_zero_approx(float(isolated_session.call("get_gameplay_time_seconds"))),
		"WorldSession builds a non-playing READY raw world with no invented mission metadata"
	)
	_assert_true(
		bool(isolated_session.call("begin_play"))
		and int(isolated_session.get("state")) == WorldSession.State.PLAYING
		and isolated_world.can_process(),
		"WorldSession enters PLAYING only through explicit lifecycle permission"
	)
	_assert_true(
		bool(isolated_session.call("pause_gameplay"))
		and int(isolated_session.get("state")) == WorldSession.State.PAUSED
		and not isolated_world.can_process(),
		"WorldSession pauses ordinary world processing through an explicit PAUSED state"
	)
	_assert_true(
		bool(isolated_session.call("resume_gameplay"))
		and int(isolated_session.get("state")) == WorldSession.State.PLAYING
		and isolated_world.can_process(),
		"WorldSession resumes PAUSED gameplay without rebuilding the world"
	)
	_assert_true(
		bool(isolated_session.call("stop_gameplay"))
		and int(isolated_session.get("state")) == WorldSession.State.STOPPED
		and not isolated_world.can_process(),
		"WorldSession coherently stops ordinary world processing"
	)
	isolated_session.call("teardown")
	_assert_true(
		int(isolated_session.get("state")) == WorldSession.State.EMPTY
		and isolated_session.get("world") == null
		and isolated_session.get("player") == null
		and isolated_session.get("mission_definition") == null
		and int(isolated_session.get("session_id")) == 0,
		"WorldSession teardown clears world-owned references and invalidates its identity"
	)
	isolated_session.queue_free()
	await process_frame

	current_session = application.get("current_session") as Node
	current_world = application.get("current_world") as Node
	var timer_hits: Array[String] = []
	var timer_probe: Node = SessionWorkProbe.new()
	current_session.add_child(timer_probe)
	timer_probe.call("arm_timer", func(): timer_hits.append("timer"))

	var stopped: bool = bool(application.call("stop_current_world"))
	await process_frame
	await physics_frame
	_assert_true(
		stopped
		and int(application.call("get_current_session_state")) == WorldSession.State.STOPPED
		and not current_world.can_process()
		and timer_hits.is_empty(),
		"Application stop freezes the world and session-owned gameplay timer work"
	)

	var resumed: bool = bool(application.call("start_current_world"))
	await process_frame
	await process_frame
	_assert_true(
		resumed
		and int(application.call("get_current_session_state")) == WorldSession.State.PLAYING
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY
		and current_world.can_process()
		and timer_hits == ["timer"],
		"Application resumes the stopped session without recreating it"
	)
	timer_probe.queue_free()
	await process_frame

	var old_session: Node = application.get("current_session") as Node
	var old_world: Node = application.get("current_world") as Node
	var old_session_id: int = int(application.call("get_current_session_id"))
	var old_world_instance_id: int = old_world.get_instance_id()
	var persistent_ui_instance_id: int = ui_root.get_instance_id()
	var shared_world_scene: PackedScene = application.get("default_world_scene") as PackedScene
	old_world.set_meta(&"session_runtime_probe", "old")

	var stale_hits: Array[String] = []
	var stale_probe: Node = SessionWorkProbe.new()
	old_session.add_child(stale_probe)
	stale_probe.call("arm_deferred", func(): stale_hits.append("deferred"))
	stale_probe.call("arm_timer", func(): stale_hits.append("timer"))

	var restarted: bool = bool(application.call("restart_current_world"))
	var replacement_session: Node = application.get("current_session") as Node
	var replacement_world: Node = application.get("current_world") as Node
	var replacement_session_id: int = int(application.call("get_current_session_id"))
	_assert_true(
		restarted
		and not is_instance_valid(old_session)
		and replacement_session != null
		and replacement_session_id > old_session_id
		and bool(application.call("is_current_session", replacement_session_id))
		and not bool(application.call("is_current_session", old_session_id)),
		"Restart tears down the old session before a fresh session becomes authoritative"
	)
	_assert_true(
		replacement_world != null
		and replacement_world.get_instance_id() != old_world_instance_id
		and replacement_world.name == &"VarkTest"
		and not replacement_world.has_meta(&"session_runtime_probe"),
		"Restart creates a fresh world instance without mission-local runtime state"
	)
	_assert_true(
		application.get("default_world_scene") == shared_world_scene
		and ui_root.get_instance_id() == persistent_ui_instance_id
		and application.get("current_ui") == ui_root,
		"Authored world configuration and persistent application UI stay separate from session runtime state"
	)

	await process_frame
	await physics_frame
	await process_frame
	_assert_true(
		stale_hits.is_empty(),
		"Deferred and timer work owned by a torn-down session cannot affect its replacement"
	)

	var current_hits: Array[String] = []
	var current_probe: Node = SessionWorkProbe.new()
	replacement_session.add_child(current_probe)
	current_probe.call("arm_deferred", func(): current_hits.append("deferred"))
	current_probe.call("arm_timer", func(): current_hits.append("timer"))
	await process_frame
	await physics_frame
	await process_frame
	current_hits.sort()
	_assert_true(
		current_hits == ["deferred", "timer"],
		"Representative session-owned deferred and timer work executes while its session is current"
	)
	current_probe.queue_free()
	await process_frame

	var before_transition_id: int = int(application.call("get_current_session_id"))
	var transitioned: bool = bool(application.call("transition_to_world", shared_world_scene))
	var after_transition_id: int = int(application.call("get_current_session_id"))
	_assert_true(
		transitioned
		and after_transition_id > before_transition_id
		and not bool(application.call("is_current_session", before_transition_id))
		and bool(application.call("is_current_session", after_transition_id)),
		"Mission transition uses the same stop-teardown-replacement ownership path"
	)

	var exiting_session: Node = application.get("current_session") as Node
	var exiting_session_id: int = int(application.call("get_current_session_id"))
	var exited: bool = bool(application.call("exit_current_world"))
	_assert_true(
		exited
		and not is_instance_valid(exiting_session)
		and application.get("current_session") == null
		and application.get("current_world") == null
		and application.get("current_player") == null
		and int(application.call("get_current_session_id")) == 0
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.MENU
		and not bool(application.call("is_current_session", exiting_session_id))
		and world_host.get_child_count() == 0
		and application.get("current_ui") == ui_root
		and (application.get_node("UIRoot/MainMenu") as Control).visible,
		"Exit tears down mission-world ownership and returns to the application menu"
	)

	application.queue_free()
	await process_frame

	var semantic_snapshot_regressions: RefCounted = (
		SemanticSnapshotRegressions.new()
	)
	await semantic_snapshot_regressions.run(
		self,
		Callable(self, "_assert_true")
	)

	var player_restore_regressions: RefCounted = (
		PlayerRestorePolicyRegressions.new()
	)
	await player_restore_regressions.run(
		self,
		Callable(self, "_assert_true")
	)

	var transient_state_regressions: RefCounted = (
		TransientStateRestoreRegressions.new()
	)
	await transient_state_regressions.run(
		self,
		Callable(self, "_assert_true")
	)

	var snapshot_coherence_regressions: RefCounted = (
		SnapshotCoherenceRegressions.new()
	)
	await snapshot_coherence_regressions.run(
		self,
		Callable(self, "_assert_true")
	)

	var save_compatibility_regressions: RefCounted = (
		SaveCompatibilityRegressions.new()
	)
	await save_compatibility_regressions.run(
		self,
		Callable(self, "_assert_true")
	)

	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	if node == null or ancestor == null:
		return false
	var cursor: Node = node
	while cursor != null:
		if cursor == ancestor:
			return true
		cursor = cursor.get_parent()
	return false


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return

	failures.append(message)
	push_error("FAIL: " + message)


func _print_summary() -> void:
	print("")
	print("==============================")
	if failures.is_empty():
		print("ALL APPLICATION TESTS PASSED")
		return

	print("%d APPLICATION TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
