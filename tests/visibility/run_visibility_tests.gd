extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const ExposureOwner = preload("res://gameplay/visibility/gameplay_exposure.gd")
const GameplayLight = preload("res://gameplay/visibility/gameplay_light.gd")
const LightGem = preload("res://gameplay/visibility/light_gem.gd")

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
	var decorative_light := world.get_node_or_null(
		"DecorativeOnlyLight"
	) as OmniLight3D
	var light_gem := world.get_node_or_null(
		"ExposureHUD/Panel"
	) as VarkLightGem
	var readout := world.get_node_or_null(
		"ExposureHUD/Panel/VBox/Readout"
	) as Label
	var bar := world.get_node_or_null(
		"ExposureHUD/Panel/VBox/ExposureBar"
	) as ProgressBar
	_assert_true(
		key_light != null
		and fill_light != null
		and decorative_light != null
		and light_gem != null
		and light_gem.get_script() == LightGem
		and key_light.get_script() == GameplayLight
		and fill_light.get_script() == GameplayLight
		and key_light is OmniLight3D
		and fill_light is OmniLight3D
		and key_light.shadow_enabled
		and fill_light.shadow_enabled
		and not (decorative_light is VarkGameplayLight)
		and decorative_light.light_energy > key_light.light_energy
		and readout != null
		and bar != null,
		"Phase 5.3 exposure proof separates explicit gameplay lights from a brighter decorative OmniLight3D and uses the reusable light-gem observer"
	)

	var dark: Dictionary = await _sample_marker(world, player, owner, "DarknessMarker")
	var edge: Dictionary = await _sample_marker(world, player, owner, "EdgeMarker")
	var partial: Dictionary = await _sample_marker(world, player, owner, "PartialMarker")
	var full: Dictionary = await _sample_marker(world, player, owner, "FullMarker")
	var decorative: Dictionary = await _sample_marker(
		world,
		player,
		owner,
		"DecorativeMarker"
	)
	var occluded: Dictionary = await _sample_marker(world, player, owner, "OccludedMarker")
	var multi: Dictionary = await _sample_marker(world, player, owner, "MultiMarker")

	var dark_value: float = float(dark.get("exposure", -1.0))
	var edge_value: float = float(edge.get("exposure", -1.0))
	var partial_value: float = float(partial.get("exposure", -1.0))
	var full_value: float = float(full.get("exposure", -1.0))
	var decorative_value: float = float(
		decorative.get("exposure", -1.0)
	)
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

	_assert_true(
		decorative_value >= 0.0
		and decorative_value <= 0.02
		and int(decorative.get("source_count", 0)) == 2
		and int(decorative.get("active_light_count", 0)) == 2
		and _light_summary(
			decorative,
			&"key"
		).get("light_id", &"") == &"key"
		and _light_summary(
			decorative,
			&"fill"
		).get("light_id", &"") == &"fill",
		"Phase 5.3 a bright decorative-only visual light does not become gameplay exposure truth or a gameplay-light source"
	)

	var baseline_full: Dictionary = await _sample_marker(
		world,
		player,
		owner,
		"FullMarker"
	)
	key_light.gameplay_enabled = false
	var disabled_full: Dictionary = await _sample_marker(
		world,
		player,
		owner,
		"FullMarker"
	)
	var disabled_key: Dictionary = _light_summary(
		disabled_full,
		&"key"
	)
	key_light.gameplay_enabled = true
	var reenabled_full: Dictionary = await _sample_marker(
		world,
		player,
		owner,
		"FullMarker"
	)
	key_light.visible = false
	var hidden_full: Dictionary = await _sample_marker(
		world,
		player,
		owner,
		"FullMarker"
	)
	var hidden_key: Dictionary = _light_summary(
		hidden_full,
		&"key"
	)
	key_light.visible = true
	var restored_full: Dictionary = await _sample_marker(
		world,
		player,
		owner,
		"FullMarker"
	)
	_assert_true(
		float(baseline_full.get("exposure", 0.0)) > 0.75
		and float(disabled_full.get("exposure", 1.0)) <= 0.02
		and int(disabled_full.get(
			"active_light_count",
			-1
		)) == 1
		and not bool(disabled_key.get(
			"gameplay_enabled",
			true
		))
		and not bool(disabled_key.get("active", true))
		and is_zero_approx(float(disabled_key.get(
			"contribution",
			-1.0
		)))
		and is_equal_approx(
			float(reenabled_full.get("exposure", 0.0)),
			float(baseline_full.get("exposure", -1.0))
		)
		and float(hidden_full.get("exposure", 1.0)) <= 0.02
		and not bool(hidden_key.get("visible", true))
		and not bool(hidden_key.get("active", true))
		and is_zero_approx(float(hidden_key.get(
			"contribution",
			-1.0
		)))
		and is_equal_approx(
			float(restored_full.get("exposure", 0.0)),
			float(baseline_full.get("exposure", -1.0))
		),
		"Phase 5.3 gameplay-light enable/visibility state immediately controls semantic exposure while restoration returns the same accepted exposure value"
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

	var live_multi: Dictionary = await _sample_marker(
		world,
		player,
		owner,
		"MultiMarker"
	)
	var live_multi_value: float = float(
		live_multi.get("exposure", -1.0)
	)
	var live_summary: Dictionary = owner.get_exposure_summary()
	var gem_text: String = light_gem.refresh_now()
	_assert_true(
		is_equal_approx(
			float(live_summary.get("exposure", -1.0)),
			live_multi_value
		)
		and int(live_summary.get("source_count", 0)) == 2
		and int(live_summary.get("active_light_count", 0)) == 2
		and is_equal_approx(
			light_gem.get_gem_value(),
			live_multi_value
		)
		and light_gem.get_filled_segments()
			== clampi(
				roundi(live_multi_value * 10.0),
				0,
				10
			)
		and readout.text == gem_text
		and gem_text.contains("EXPOSURE")
		and gem_text.contains("sources 2 active 2")
		and gem_text.contains("key ON")
		and gem_text.contains("fill ON")
		and gem_text.contains("vis")
		and absf(float(bar.value) - live_multi_value)
			<= float(bar.step) + 0.000001,
		"Phase 5.3 reusable light gem observes semantic exposure without owning it and reports numeric value plus per-source state/visibility diagnostics"
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
