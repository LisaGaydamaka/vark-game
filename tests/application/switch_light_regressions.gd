extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const GameplayLight = preload("res://gameplay/visibility/gameplay_light.gd")
const LightSwitch = preload("res://gameplay/visibility/light_switch.gd")
const LAB_PATH: String = "res://scenes/SwitchLightLab.tscn"
const TEST_SAVE_DIRECTORY: String = "user://vark_tests/phase65"


func run(tree: SceneTree, assert_true: Callable) -> void:
	_release_interact()
	_cleanup_test_storage()
	var application: Node = ApplicationScene.instantiate()
	var coordinator: Node = application.get_node("SaveCoordinator")
	coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)
	var labels: PackedStringArray = application.get("development_launch_labels")
	var paths: PackedStringArray = application.get("development_launch_resource_paths")
	assert_true.call(
		labels.has("Switch/Light Lab") and paths.has(LAB_PATH),
		"Application Development Launch exposes the 6.5 Switch/Light Lab"
	)

	application.set("development_launch_labels", PackedStringArray(["Switch/Light Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([LAB_PATH]))
	tree.get_root().add_child(application)
	await tree.process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	await _settle(tree, 4)

	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var session := application.get("current_session") as Node
	var exposure := world.get_node_or_null("GameplayExposure") as VarkGameplayExposure if world != null else null
	var switch := world.get_node_or_null("RoomSwitch") as VarkLightSwitch if world != null else null
	var light_a := world.get_node_or_null("RoomLightA") as VarkGameplayLight if world != null else null
	var light_b := world.get_node_or_null("RoomLightB") as VarkGameplayLight if world != null else null
	var extinguishable := world.get_node_or_null("ExtinguishableLamp") as VarkGameplayLight if world != null else null
	assert_true.call(
		launched and world != null and player != null and session != null
		and exposure != null and switch != null
		and light_a != null and light_b != null and extinguishable != null
		and light_a.get_script() == GameplayLight
		and switch.get_script() == LightSwitch,
		"6.5 lab launches production player, switch, gameplay lights, exposure owner, and persistent world session"
	)
	if (
		not launched or world == null or player == null or session == null
		or exposure == null or switch == null or light_a == null
		or light_b == null or extinguishable == null
	):
		_cleanup(application, tree)
		return

	assert_true.call(
		light_a.control_id == "lab.room"
		and light_b.control_id == "lab.room"
		and switch.control_id == "lab.room"
		and light_a.is_enabled_state()
		and light_b.is_enabled_state()
		and bool((switch.get_debug_summary() as Dictionary).get("group_on", false)),
		"Two saved gameplay lights and one unsaved presentation switch share one mapper-authored control_id"
	)
	var light_a_asset := light_a.get_node_or_null("FixtureAnchor/WallLampAsset") as VarkLightFixtureAsset
	var light_a_contract: Dictionary = (
		light_a_asset.get_contract_summary()
		if light_a_asset != null
		else {}
	)
	var expected_emitter_position: Vector3 = (
		light_a_asset.to_global(
			light_a_contract.get("emitter_local_position", Vector3.ZERO)
		)
		if light_a_asset != null
		else Vector3.ZERO
	)
	assert_true.call(
		light_a_asset != null
		and light_a_asset.validate_contract()
		and bool(light_a_contract.get("lit_enabled", false))
		and bool(light_a_contract.get("emitter_inside_lit_surface", false))
		and int(light_a_contract.get("collision_shape_count", 0)) >= 3
		and int(light_a_contract.get("collision_layer", 0)) == 1
		and light_a.get_emitter() != null
		and light_a.get_emitter().light_energy > 0.0
		and light_a.get_emitter_global_position().distance_to(
			expected_emitter_position
		) < 0.001
		and light_a.get_emitter_global_position().distance_to(
			light_a.global_position
		) > 0.15,
		"Fixture asset authors the real emitter inside its bright glass instead of emitting from the mapper origin, and owns solid world collision"
	)

	var player_collision := player.get_node("CollisionShape3D") as CollisionShape3D
	var overlap_query := PhysicsShapeQueryParameters3D.new()
	overlap_query.shape = player_collision.shape
	var probe_player_transform := Transform3D(
		Basis.IDENTITY,
		Vector3(3.2, 0.0, 0.95)
	)
	overlap_query.transform = probe_player_transform * player_collision.transform
	overlap_query.collision_mask = player.collision_mask
	overlap_query.collide_with_bodies = true
	overlap_query.collide_with_areas = false
	var overlap_hits: Array[Dictionary] = (
		world.get_world_3d().direct_space_state.intersect_shape(
			overlap_query,
			32
		)
	)
	var hits_lamp_fixture: bool = false
	for hit: Dictionary in overlap_hits:
		var collider := hit.get("collider") as Node
		if (
			collider != null
			and light_a_asset != null
			and light_a_asset.is_ancestor_of(collider)
		):
			hits_lamp_fixture = true
			break
	assert_true.call(
		hits_lamp_fixture,
		"The real player collision shape overlaps the lamp's authored solid body at contact distance, so lamps physically block the player"
	)

	var light_events: Array[Dictionary] = []
	var switch_events: Array[Dictionary] = []
	var light_handler: Callable = func(event: Dictionary) -> bool:
		light_events.append((event.get("payload", {}) as Dictionary).duplicate(true))
		return true
	var switch_handler: Callable = func(event: Dictionary) -> bool:
		switch_events.append((event.get("payload", {}) as Dictionary).duplicate(true))
		return true
	session.call(
		"register_semantic_event_handler",
		GameplayLight.STATE_CHANGED_EVENT_NAME,
		light_handler
	)
	session.call(
		"register_semantic_event_handler",
		LightSwitch.USED_EVENT_NAME,
		switch_handler
	)

	var baseline: float = float(exposure.sample_now().get("exposure", 0.0))
	assert_true.call(
		baseline > 0.10,
		"Room gameplay lights contribute real stealth exposure before the switch is used"
	)

	player.global_position = Vector3(0, 0, 3.0)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	(player.get_node("Head") as Node3D).rotation.x = 0.0
	await _settle(tree, 3)
	var switch_target: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		switch_target.get("target_name", "") == "RoomSwitch"
		and switch.is_interaction_highlighted(),
		"Mapper-style wall switch uses the ordinary center-view/F interaction path"
	)
	_press_interact()
	await _settle(tree, 2)
	_release_interact()
	await _settle(tree, 16)

	var switched_exposure: float = float(exposure.sample_now().get("exposure", 1.0))
	var switch_debug: Dictionary = switch.get_debug_summary()
	assert_true.call(
		not light_a.is_enabled_state()
		and not light_b.is_enabled_state()
		and not bool(switch_debug.get("group_on", true))
		and float(switch_debug.get("display_fraction", 1.0)) < 0.1
		and switched_exposure < baseline * 0.35
		and switch_events.size() == 1
		and int(switch_events[0].get("changed_light_count", 0)) == 2
		and light_events.size() == 2,
		"One F toggles every light sharing control_id, moves derived switch presentation, and changes actual gameplay exposure"
	)
	var off_asset_summary: Dictionary = light_a_asset.get_contract_summary()
	assert_true.call(
		light_a.visible
		and light_a_asset.visible
		and not bool(off_asset_summary.get("lit_enabled", true))
		and bool(off_asset_summary.get("lit_surface_visible", false))
		and not bool(off_asset_summary.get("lit_surface_emission_enabled", true))
		and is_zero_approx(light_a.light_energy)
		and light_a.get_emitter() != null
		and is_zero_approx(light_a.get_emitter().light_energy),
		"Turning a lamp off leaves its model/dark glass visible while removing emissive appearance and the actual light emitter"
	)

	player.global_position = Vector3(3.2, 0, 2.45)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	(player.get_node("Head") as Node3D).rotation.x = 0.0
	await _settle(tree, 3)
	var lamp_target: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		lamp_target.get("target_name", "") == "ExtinguishableLamp"
		and extinguishable.is_interaction_highlighted(),
		"Extinguishable mapper light exposes the same center-view interaction contract through its fixture proxy"
	)
	_press_interact()
	await _settle(tree, 2)
	_release_interact()
	await _settle(tree, 3)
	assert_true.call(
		not extinguishable.is_enabled_state()
		and light_events.size() == 3
		and str(light_events[-1].get("light_id", "")) == "lab.extinguishable"
		and str(light_events[-1].get("source_id", "")) == "direct",
		"Direct extinguish turns off the same persistent gameplay-light truth instead of a separate visual-only state"
	)

	var generation: int = int(application.call("request_quicksave"))
	var snapshot: Dictionary = await _wait_for_quicksave(
		coordinator,
		tree,
		generation,
		120
	)
	var saved_entities: Dictionary = (
		snapshot.get("session", {}).get("world_state", {}).get(
			"persistent_entities",
			{}
		)
	)
	assert_true.call(
		generation > 0
		and not snapshot.is_empty()
		and not bool((saved_entities.get(
			"switch_light_lab.room_a",
			{}
		) as Dictionary).get("gameplay_enabled", true))
		and not bool((saved_entities.get(
			"switch_light_lab.room_b",
			{}
		) as Dictionary).get("gameplay_enabled", true))
		and not bool((saved_entities.get(
			"switch_light_lab.extinguishable",
			{}
		) as Dictionary).get("gameplay_enabled", true))
		and not saved_entities.has("lab.room.switch"),
		"Quicksave persists light truth only; derived switch presentation has no duplicate saved state"
	)

	light_a.set_enabled_state(true, false)
	light_b.set_enabled_state(true, false)
	extinguishable.set_enabled_state(true, false)
	await _settle(tree, 4)
	assert_true.call(
		light_a.is_enabled_state()
		and light_b.is_enabled_state()
		and extinguishable.is_enabled_state(),
		"Live light truth can deliberately diverge after the committed 6.5 snapshot"
	)

	var quickloaded: bool = bool(application.call("quickload_latest"))
	await tree.process_frame
	await _settle(tree, 20)
	var restored_world := application.get("current_world") as Node3D
	var restored_session := application.get("current_session") as Node
	var restored_switch := restored_world.get_node_or_null("RoomSwitch") as VarkLightSwitch if restored_world != null else null
	var restored_a := restored_world.get_node_or_null("RoomLightA") as VarkGameplayLight if restored_world != null else null
	var restored_b := restored_world.get_node_or_null("RoomLightB") as VarkGameplayLight if restored_world != null else null
	var restored_ext := restored_world.get_node_or_null("ExtinguishableLamp") as VarkGameplayLight if restored_world != null else null
	assert_true.call(
		quickloaded and restored_switch != null
		and restored_a != null and restored_b != null and restored_ext != null
		and not restored_a.is_enabled_state()
		and not restored_b.is_enabled_state()
		and not restored_ext.is_enabled_state()
		and not bool((restored_switch.get_debug_summary() as Dictionary).get("group_on", true))
		and float((restored_switch.get_debug_summary() as Dictionary).get("display_fraction", 1.0)) < 0.1
		and int(restored_session.call("get_pending_semantic_event_count")) == 0,
		"Quickload restores saved light state and a fresh switch derives the correct pose without replaying switch/light consequences"
	)
	var restored_asset := restored_a.get_node_or_null("FixtureAnchor/WallLampAsset") as VarkLightFixtureAsset
	var restored_asset_summary: Dictionary = (
		restored_asset.get_contract_summary()
		if restored_asset != null
		else {}
	)
	assert_true.call(
		restored_a.visible
		and restored_asset != null
		and restored_asset.visible
		and not bool(restored_asset_summary.get("lit_enabled", true))
		and bool(restored_asset_summary.get("lit_surface_visible", false))
		and is_zero_approx(restored_a.light_energy)
		and restored_a.get_emitter() != null
		and is_zero_approx(restored_a.get_emitter().light_energy),
		"Quickload of an OFF lamp restores dark visible fixture presentation and zero emitter energy rather than hiding the object"
	)

	_cleanup(application, tree)
	_cleanup_test_storage()


func _press_interact() -> void:
	Input.action_press("interact")


func _release_interact() -> void:
	Input.action_release("interact")


func _settle(tree: SceneTree, frames: int = 1) -> void:
	for _index: int in frames:
		await tree.physics_frame
		await tree.process_frame


func _wait_for_quicksave(
	coordinator: Node,
	tree: SceneTree,
	generation: int,
	max_frames: int
) -> Dictionary:
	for _index: int in max_frames:
		var status: Dictionary = coordinator.call("get_request_status", generation)
		if status.get("status", &"") == &"committed":
			return coordinator.call("get_request_snapshot", generation)
		if (
			status.get("status", &"") == &"failed"
			or status.get("status", &"") == &"cancelled"
			or status.get("status", &"") == &"superseded"
		):
			return {}
		await tree.physics_frame
		await tree.process_frame
	return {}


func _cleanup(application: Node, tree: SceneTree) -> void:
	_release_interact()
	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _cleanup_test_storage() -> void:
	var final_path: String = TEST_SAVE_DIRECTORY + "/quicksave.varksave"
	for path: String in [
		final_path,
		final_path + ".new",
		final_path + ".bak",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_dir: String = ProjectSettings.globalize_path(TEST_SAVE_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_dir):
		DirAccess.remove_absolute(absolute_dir)
