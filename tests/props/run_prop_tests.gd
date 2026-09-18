extends SceneTree


const PropRegressions = preload("res://tests/props/prop_regressions.gd")
const TransitionRegressions = preload("res://tests/props/phase_3_5_transition_regressions.gd")
const MantleCompletionRegressions = preload("res://tests/props/mantle_completion_tolerance_regressions.gd")


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var regressions: RefCounted = PropRegressions.new()
	await regressions.run(
		self,
		Callable(self, "_assert_true")
	)

	var transition_regressions: RefCounted = TransitionRegressions.new()
	await transition_regressions.run(self, Callable(self, "_assert_true"))

	var mantle_completion_regressions: RefCounted = MantleCompletionRegressions.new()
	await mantle_completion_regressions.run(self, Callable(self, "_assert_true"))

	_print_summary()
	quit(1 if not failures.is_empty() else 0)


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
		print("ALL PROP TESTS PASSED")
		return

	print("%d PROP TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
