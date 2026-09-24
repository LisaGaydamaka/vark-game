extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const Collectible = preload("res://gameplay/pickups/collectible.gd")
const OrdinaryDoor = preload("res://gameplay/doors/ordinary_door.gd")
const LAB_PATH: String = "res://scenes/LootKeyLab.tscn"
const TEST_SAVE_DIRECTORY: String = "user://vark_tests/phase63"


func run(tree: SceneTree, assert_true: Callable) -> void:
	_release_interact()
	_cleanup_test_storage()
	var application: Node = ApplicationScene.instantiate()
	var coordinator: Node = application.get_node("SaveCoordinator")
	coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)
	var labels: PackedStringArray = application.get("development_launch_labels")
	var paths: PackedStringArray = application.get("development_launch_resource_paths")
	assert_true.call(
		labels.has("Loot/Key Lab") and paths.has(LAB_PATH),
		"Application Development Launch exposes the 6.3 Loot/Key Lab"
	)

	application.set("development_launch_labels", PackedStringArray(["Loot/Key Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([LAB_PATH]))
	tree.get_root().add_child(application)
	await tree.process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	await _settle(tree, 2)

	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var session := application.get("current_session") as Node
	var key := world.get_node_or_null("Key") as VarkCollectible if world != null else null
	var loot25 := world.get_node_or_null("Loot25") as VarkCollectible if world != null else null
	var loot75 := world.get_node_or_null("Loot75") as VarkCollectible if world != null else null
	var door := world.get_node_or_null("LockedDoor") as VarkOrdinaryDoor if world != null else null

	var left_wall := world.get_node_or_null("LeftWall") as StaticBody3D if world != null else null
	var right_wall := world.get_node_or_null("RightWall") as StaticBody3D if world != null else null
	var header := world.get_node_or_null("Header") as StaticBody3D if world != null else null
	var floor := world.get_node_or_null("Floor") as StaticBody3D if world != null else null
	var door_mesh := door.get_node_or_null("DoorMesh") as MeshInstance3D if door != null else null
	var frame_flush: bool = false
	if (
		left_wall != null
		and right_wall != null
		and header != null
		and floor != null
		and door_mesh != null
		and door_mesh.mesh != null
	):
		var door_aabb: AABB = door_mesh.mesh.get_aabb()
		var door_local_min: Vector3 = door_mesh.position + door_aabb.position
		var door_local_max: Vector3 = door_local_min + door_aabb.size
		var door_world_min: Vector3 = door.global_position + door_local_min
		var door_world_max: Vector3 = door.global_position + door_local_max
		var left_shape := left_wall.get_node("CollisionShape3D").shape as BoxShape3D
		var right_shape := right_wall.get_node("CollisionShape3D").shape as BoxShape3D
		var header_shape := header.get_node("CollisionShape3D").shape as BoxShape3D
		var floor_shape := floor.get_node("CollisionShape3D").shape as BoxShape3D
		var left_inner_x: float = left_wall.global_position.x + left_shape.size.x * 0.5
		var right_inner_x: float = right_wall.global_position.x - right_shape.size.x * 0.5
		var header_bottom_y: float = header.global_position.y - header_shape.size.y * 0.5
		var floor_top_y: float = floor.global_position.y + floor_shape.size.y * 0.5
		frame_flush = (
			is_equal_approx(left_inner_x, door_world_min.x)
			and is_equal_approx(right_inner_x, door_world_max.x)
			and is_equal_approx(header_bottom_y, door_world_max.y)
			and is_equal_approx(floor_top_y, door_world_min.y)
		)

	assert_true.call(
		frame_flush,
		"Loot/Key Lab closed door leaf seats flush against both frame sides, header, and floor with no authored slit"
	)

	var key_asset: Dictionary = key.get_asset_summary() if key != null else {}
	var loot25_asset: Dictionary = loot25.get_asset_summary() if loot25 != null else {}
	var loot75_asset: Dictionary = loot75.get_asset_summary() if loot75 != null else {}
	assert_true.call(
		key_asset.get("asset_id", &"") == &"brass_key"
		and loot25_asset.get("asset_id", &"") == &"gold_cup"
		and loot75_asset.get("asset_id", &"") == &"silver_candlestick"
		and str(key_asset.get("model_path", "")).ends_with(".obj")
		and str(loot25_asset.get("model_path", "")).ends_with(".obj")
		and str(loot75_asset.get("model_path", "")).ends_with(".obj")
		and (key_asset.get("visual_size", Vector3.ZERO) as Vector3).length() < 0.18
		and (loot25_asset.get("visual_size", Vector3.ZERO) as Vector3).length() < 0.30
		and (loot75_asset.get("visual_size", Vector3.ZERO) as Vector3).length() < 0.30,
		"6.3 key and loot presentation uses realistically scaled imported item models"
	)
	var key_collision_size: Vector3 = key_asset.get("collision_size", Vector3.ZERO)
	var key_interaction_size: Vector3 = key_asset.get("interaction_size", Vector3.ZERO)
	var loot_interaction_size: Vector3 = loot25_asset.get("interaction_size", Vector3.ZERO)
	assert_true.call(
		key_interaction_size.x >= key_collision_size.x * 1.8
		and key_interaction_size.y >= key_collision_size.y * 2.5
		and loot_interaction_size.x >= 0.28
		and loot_interaction_size.y >= 0.26,
		"Tiny imported collectibles keep their real size but expose a materially larger interaction-only aim proxy"
	)

	assert_true.call(
		launched
		and world != null
		and player != null
		and session != null
		and key != null
		and loot25 != null
		and loot75 != null
		and door != null
		and not bool(player.call("has_semantic_possession", &"key.lab"))
		and (session.call("get_mission_run_summary") as Dictionary) == {
			"loot_count": 0,
			"loot_value": 0,
		},
		"6.3 lab begins with authored pickups present, empty semantic possession, zero run loot, and the real locked door"
	)

	var collected_events: Array[Dictionary] = []
	var collected_handler: Callable = func(event: Dictionary) -> bool:
		collected_events.append((event.get("payload", {}) as Dictionary).duplicate(true))
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			&"pickup.collected",
			collected_handler
		)),
		"6.3 pickup consequences use the existing detached semantic event route"
	)

	# Deliberately aim 11 cm beside the key center. This misses the real 14 cm
	# physical key box (7 cm half-width) but remains inside its invisible proxy.
	player.global_position = Vector3(0.11, 0.0, 4.0)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	(player.get_node("Head") as Node3D).rotation.x = 0.0
	await _settle(tree, 2)
	var key_target: Dictionary = player.call("get_interaction_semantic_state")
	var key_target_debug: Dictionary = player.call("get_interaction_debug_summary")
	assert_true.call(
		bool(key.call("is_interaction_highlighted"))
		and key_target.get("target_name", "") == "Key"
		and key_target_debug.get("hit_class", "") == "Area3D",
		"Off-center aim that misses the tiny key's solid collision still selects it through the non-solid interaction proxy"
	)
	_press_interact()
	await _settle(tree, 2)
	_release_interact()
	await _settle(tree, 2)
	assert_true.call(
		bool(player.call("has_semantic_possession", &"key.lab"))
		and not bool((session.call("lookup_persistent_entity", "loot_key_lab.key") as Dictionary).get("ok", true))
		and collected_events.size() == 1
		and collected_events[0].get("kind", &"") == Collectible.KIND_KEY
		and collected_events[0].get("content_id", "") == "key.lab",
		"Fresh F collection converts the authored key into abstract player semantic possession and tombstones its world identity once"
	)

	player.global_position = Vector3(0, 0, 1.2)
	player.velocity = Vector3.ZERO
	await _settle(tree, 2)
	_press_interact()
	await _settle(tree, 2)
	_release_interact()
	await _settle(tree, 3)
	var door_access: Dictionary = door.get_access_summary()
	assert_true.call(
		not bool(door_access.get("locked", true))
		and door.get_semantic_phase() == OrdinaryDoor.PHASE_OPENING,
		"The real 6.2 locked door queries the real player's 6.3 semantic key possession and unlocks without inventory UI"
	)
	await _settle(tree, 45)
	assert_true.call(
		door.get_semantic_phase() == OrdinaryDoor.PHASE_OPEN
		and is_equal_approx(door.get_open_fraction(), 1.0)
		and not door.is_motion_blocked(),
		"The flush Loot/Key Lab frame remains solid/sealed but never blocks the authored door from completing its full opening sweep"
	)

	await _collect_at(tree, player, Vector3(-2.0, 0.0, 3.35))
	await _collect_at(tree, player, Vector3(2.0, 0.0, 3.35))
	var run_summary: Dictionary = session.call("get_mission_run_summary")
	var tombstones: Array = session.call("get_authored_tombstones")
	assert_true.call(
		run_summary == {
			"loot_count": 2,
			"loot_value": 100,
		}
		and tombstones == [
			"loot_key_lab.key",
			"loot_key_lab.loot25",
			"loot_key_lab.loot75",
		]
		and not bool((session.call("lookup_persistent_entity", "loot_key_lab.loot25") as Dictionary).get("ok", true))
		and not bool((session.call("lookup_persistent_entity", "loot_key_lab.loot75") as Dictionary).get("ok", true))
		and collected_events.size() == 3,
		"Collected loot becomes abstract count/value on one MissionRunState owner and every removed authored pickup becomes a stable tombstone"
	)

	await _settle(tree, 2)
	var generation: int = int(application.call("request_quicksave"))
	var snapshot: Dictionary = await _wait_for_quicksave(
		coordinator,
		tree,
		generation,
		120
	)
	var saved_world: Dictionary = snapshot.get("session", {}).get("world_state", {})
	var saved_existence: Dictionary = saved_world.get("object_existence", {})
	var saved_player: Dictionary = saved_world.get("player", {})
	assert_true.call(
		generation > 0
		and not snapshot.is_empty()
		and saved_existence.get("authored_tombstones", []) == tombstones
		and (saved_world.get("mission_run_state", {}) as Dictionary) == run_summary
		and (saved_player.get("semantic_possession", {}) as Dictionary).get("ids", []) == ["key.lab"],
		"Quicksave captures tombstones, one mission-run loot owner, and detached player possession through the existing save envelope"
	)

	var live_run_state := session.get("mission_run_state") as RefCounted
	assert_true.call(
		bool(player.call("grant_semantic_possession", &"item.transient"))
		and live_run_state != null
		and bool(live_run_state.call("record_loot", 999)),
		"6.3 regression deliberately diverges possession and the real MissionRunState after the committed snapshot"
	)
	var quickloaded: bool = bool(application.call("quickload_latest"))
	await tree.process_frame
	await _settle(tree, 2)

	var restored_world := application.get("current_world") as Node3D
	var restored_player := application.get("current_player") as CharacterBody3D
	var restored_session := application.get("current_session") as Node
	var restored_door := restored_world.get_node_or_null("LockedDoor") as VarkOrdinaryDoor
	var restored_run: Dictionary = restored_session.call("get_mission_run_summary")
	var restored_possession: Dictionary = restored_player.call("get_semantic_possession_summary")
	assert_true.call(
		quickloaded
		and restored_world.get_node_or_null("Key") == null
		and restored_world.get_node_or_null("Loot25") == null
		and restored_world.get_node_or_null("Loot75") == null
		and restored_run == run_summary
		and restored_possession.get("ids", []) == ["key.lab"]
		and not bool(restored_player.call("has_semantic_possession", &"item.transient"))
		and restored_session.call("get_authored_tombstones") == tombstones
		and int(restored_session.call("get_pending_semantic_event_count")) == 0
		and restored_door != null
		and not bool((restored_door.get_access_summary() as Dictionary).get("locked", true)),
		"Quickload removes tombstoned authored pickups before state application, restores possession/run stats, and replays no collection consequences"
	)

	_release_interact()
	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame
	_cleanup_test_storage()


func _collect_at(
	tree: SceneTree,
	player: CharacterBody3D,
	position: Vector3
) -> void:
	player.global_position = position
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	await _settle(tree, 2)
	_press_interact()
	await _settle(tree, 2)
	_release_interact()
	await _settle(tree, 2)


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
		var status: Dictionary = coordinator.call(
			"get_request_status",
			generation
		)
		if status.get("status", &"") == &"committed":
			return coordinator.call(
				"get_request_snapshot",
				generation
			)
		if (
			status.get("status", &"") == &"failed"
			or status.get("status", &"") == &"cancelled"
		):
			return {}
		await tree.physics_frame
		await tree.process_frame
	return {}


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
