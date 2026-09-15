extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_assert_true(
		str(ProjectSettings.get_setting("application/run/main_scene", ""))
		== "res://application/Application.tscn",
		"F5 main scene is the Vark application root"
	)

	var application: Node = ApplicationScene.instantiate()
	get_root().add_child(application)
	await process_frame

	var world_host: Node = application.get_node("WorldHost")
	var ui_root: CanvasLayer = application.get_node("UIRoot")
	var current_world: Node = application.get("current_world")
	var current_player: Node = application.get("current_player")
	var current_ui: CanvasLayer = application.get("current_ui")
	var session_id: int = int(application.call("get_current_session_id"))

	_assert_true(
		current_world != null
		and current_world.get_parent() == world_host
		and current_world.name == &"VarkTest",
		"Application owns the current development world"
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

	application.queue_free()
	await process_frame

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
