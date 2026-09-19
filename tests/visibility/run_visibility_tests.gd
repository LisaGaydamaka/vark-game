extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const ExposureOwner = preload("res://gameplay/visibility/gameplay_exposure.gd")
const GameplayLight = preload("res://gameplay/visibility/gameplay_light.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _assert_exposure_lab()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_exposure_lab() -> void:
	var default_application: Node = ApplicationScene.instantiate()
	var default_labels: PackedStringArray = default_application.get(
		"development_launch_labels"
	)
	var default_paths: PackedStringArray = default_application.get(
		"development_launch_resource_paths"
	)
	_assert_true(
		default_labels.has("Exposure Lab")
		and default_paths.has("res://scenes/ExposureLab.tscn"),
		"Application Development Launch exposes the 3.8 Exposure Lab"
	)
	default_application.free()

	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Exposure Lab"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray(["res://scenes/ExposureLab.tscn"])
	)
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var owner := (
		world.get_node_or_null("GameplayExposure") as VarkGameplayExposure
		if world != null
		else null
	)
	_assert_true(
		launched
		and world != null
		and world.name == &"ExposureLab"
		and player != null
		and owner != null
		and owner.get_script() == ExposureOwner,
		"Exposure Lab launches through the production application/session/player path with one world-owned exposure owner"
	)
	if world == null or player == null or owner == null:
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var key_light := world.get_node_or_null("KeyGameplayLight") as VarkGameplayLight
	var fill_light := world.get_node_or_null("FillGameplayLight") as VarkGameplayLight
	var readout := world.get_node_or_null(
		"ExposureHUD/Panel/VBox/Readout"
	) as Label
	var bar := world.get_node_or_null(
		"ExposureHUD/Panel/VBox/ExposureBar"
	) as ProgressBar
	_assert_true(
		key_light != null
		and fill_light != null
		and key_light.get_script() == GameplayLight
		and fill_light.get_script() == GameplayLight
		and key_light is OmniLight3D
		and fill_light is OmniLight3D
		and key_light.shadow_enabled
		and fill_light.shadow_enabled
		and readout != null
		and bar != null,
		"Exposure proof uses real shadow-casting OmniLight3D sources and an in-world development light-gem/debug readout"
	)

	var dark: Dictionary = await _sample_marker(world, player, owner, "DarknessMarker")
	var edge: Dictionary = await _sample_marker(world, player, owner, "EdgeMarker")
	var partial: Dictionary = await _sample_marker(world, player, owner, "PartialMarker")
	var full: Dictionary = await _sample_marker(world, player, owner, "FullMarker")
	var occluded: Dictionary = await _sample_marker(world, player, owner, "OccludedMarker")
	var multi: Dictionary = await _sample_marker(world, player, owner, "MultiMarker")

	var dark_value: float = float(dark.get("exposure", -1.0))
	var edge_value: float = float(edge.get("exposure", -1.0))
	var partial_value: float = float(partial.get("exposure", -1.0))
	var full_value: float = float(full.get("exposure", -1.0))
	var occluded_value: float = float(occluded.get("exposure", -1.0))
	var multi_value: float = float(multi.get("exposure", -1.0))
	_assert_true(
		dark_value >= 0.0
		and dark_value <= 0.02
		and edge_value > 0.05
		and edge_value < partial_value
		and partial_value > 0.20
		and partial_value < 0.55
		and full_value > 0.75
		and full_value <= 1.0,
		"One gameplay-light falloff produces deterministic darkness, edge, partial, and full exposure relationships"
	)

	var occluded_key: Dictionary = _light_summary(occluded, &"key")
	_assert_true(
		occluded_value <= 0.02
		and int(occluded_key.get("sample_count", 0)) == 3
		and int(occluded_key.get("visible_samples", -1)) == 0
		and float(occluded_key.get("contribution", -1.0)) <= 0.001,
		"Opaque world geometry occludes all three real-player body samples in the representative shadow position"
	)

	var key_multi: Dictionary = _light_summary(multi, &"key")
	var fill_multi: Dictionary = _light_summary(multi, &"fill")
	var key_contribution: float = float(key_multi.get("contribution", 0.0))
	var fill_contribution: float = float(fill_multi.get("contribution", 0.0))
	_assert_true(
		int(multi.get("sample_count", 0)) == 3
		and int(multi.get("active_light_count", 0)) == 2
		and key_contribution > 0.0
		and fill_contribution > 0.0
		and multi_value > key_contribution
		and multi_value > fill_contribution
		and multi_value < 1.0,
		"Multiple gameplay lights contribute additively before the exposure result clamps to the 0-1 light-gem range"
	)

	var live_summary: Dictionary = owner.get_exposure_summary()
	_assert_true(
		is_equal_approx(float(live_summary.get("exposure", -1.0)), multi_value)
		and readout.text.contains("EXPOSURE")
		and readout.text.contains("key")
		and readout.text.contains("fill")
		and absf(float(bar.value) - multi_value) <= float(bar.step) + 0.000001,
		"World-owned exposure continuously drives the stepped development light-gem/debug HUD with source diagnostics"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _sample_marker(
	world: Node3D,
	player: CharacterBody3D,
	owner: VarkGameplayExposure,
	marker_name: String
) -> Dictionary:
	var marker := world.get_node(marker_name) as Node3D
	player.global_position = Vector3(
		marker.global_position.x,
		0.0,
		marker.global_position.z
	)
	player.velocity = Vector3.ZERO
	for _frame_index: int in 3:
		await physics_frame
		await process_frame
	return owner.sample_now()


func _light_summary(summary: Dictionary, light_id: StringName) -> Dictionary:
	for light_summary: Dictionary in summary.get("lights", []):
		if light_summary.get("light_id", &"") == light_id:
			return light_summary
	return {}


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
		print("ALL VISIBILITY TESTS PASSED")
		return
	print("%d VISIBILITY TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
