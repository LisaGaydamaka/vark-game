extends SceneTree


const TestHelpers = preload("res://tests/movement/test_helpers.gd")
const INTENTIONAL_FAILURE_ARG: String = "--intentional-failure"


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var helpers: RefCounted = TestHelpers.new()
	helpers.assert_true(1 + 1 == 2, "Test framework works")

	if INTENTIONAL_FAILURE_ARG in OS.get_cmdline_user_args():
		helpers.assert_true(false, "Intentional failure path")

	helpers.print_summary()
	quit(1 if helpers.has_failures() else 0)
