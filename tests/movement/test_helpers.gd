extends RefCounted


var failures: Array[String] = []


func assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return

	failures.append(message)
	push_error("FAIL: " + message)


func has_failures() -> bool:
	return not failures.is_empty()


func print_summary() -> void:
	print("")
	print("==============================")
	if failures.is_empty():
		print("ALL MOVEMENT TESTS PASSED")
		return

	print("%d MOVEMENT TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
