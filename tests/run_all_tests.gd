extends SceneTree


const SUITES = [
	{
		"name": "Authoring",
		"script": "res://tests/authoring/run_authoring_tests.gd",
	},
	{
		"name": "Application",
		"script": "res://tests/application/run_application_tests.gd",
	},
	{
		"name": "Props",
		"script": "res://tests/props/run_prop_tests.gd",
	},
	{
		"name": "Acoustics",
		"script": "res://tests/acoustics/run_acoustic_tests.gd",
	},
	{
		"name": "Visibility",
		"script": "res://tests/visibility/run_visibility_tests.gd",
	},
	{
		"name": "Speech",
		"script": "res://tests/speech/run_speech_tests.gd",
	},
	{
		"name": "Objectives",
		"script": "res://tests/objectives/run_objective_tests.gd",
	},
	{
		"name": "Actors",
		"script": "res://tests/actors/run_actor_tests.gd",
	},
	{
		"name": "Phase 3 Integration",
		"script": "res://tests/integration/run_phase3_slice_tests.gd",
	},
	{
		"name": "Navigation",
		"script": "res://tests/navigation/run_navigation_tests.gd",
	},
	{
		"name": "Movement",
		"script": "res://tests/movement/run_movement_tests.gd",
	},
]


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var executable_path: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	var failed_suites: Array[String] = []

	for suite: Dictionary in SUITES:
		var suite_name: String = str(suite["name"])
		var script_path: String = str(suite["script"])
		print("")
		print("=== Running %s suite ===" % suite_name)

		var output: Array = []
		var arguments := PackedStringArray([
			"--headless",
			"--path",
			project_path,
			"--script",
			script_path,
		])
		var exit_code: int = OS.execute(
			executable_path,
			arguments,
			output,
			true
		)
		for chunk: Variant in output:
			print(str(chunk).trim_suffix("\n"))

		if exit_code != 0:
			failed_suites.append(suite_name)
			push_error(
				"%s suite failed with exit code %d" % [suite_name, exit_code]
			)

	print("")
	print("==============================")
	if failed_suites.is_empty():
		print("ALL TEST SUITES PASSED")
		quit(0)
		return

	print("%d TEST SUITE(S) FAILED" % failed_suites.size())
	for suite_name: String in failed_suites:
		print(" - ", suite_name)
	quit(1)
