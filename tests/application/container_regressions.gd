extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const ContainerScript = preload("res://gameplay/containers/ordinary_container.gd")
const LAB_PATH: String = "res://scenes/ContainerLab.tscn"


func run(tree: SceneTree, assert_true: Callable) -> void:
	_release_interact()
	var application: Node = ApplicationScene.instantiate()
	var labels: PackedStringArray = application.get("development_launch_labels")
	var paths: PackedStringArray = application.get("development_launch_resource_paths")
	assert_true.call(
		labels.has("Container Lab") and paths.has(LAB_PATH),
		"Application Development Launch exposes the 6.4 Container Lab"
	)

	application.set("development_launch_labels", PackedStringArray(["Container Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray([LAB_PATH]))
	tree.get_root().add_child(application)
	await tree.process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	await _settle(tree, 3)

	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var session := application.get("current_session") as Node
	var drawer := world.get_node_or_null("Drawer") as VarkOrdinaryContainer if world != null else null
	var chest := world.get_node_or_null("Chest") as VarkOrdinaryContainer if world != null else null
	var cabinet := world.get_node_or_null("Cabinet") as VarkOrdinaryContainer if world != null else null
	var drawer_loot := (
		(session.call("lookup_persistent_entity", "container_lab.drawer.loot25") as Dictionary).get("node")
		as VarkCollectible
		if session != null else null
	)
	var drawer_key := (
		(session.call("lookup_persistent_entity", "container_lab.drawer.key") as Dictionary).get("node")
		as VarkCollectible
		if session != null else null
	)

	assert_true.call(
		launched
		and world != null
		and player != null
		and session != null
		and drawer != null
		and chest != null
		and cabinet != null
		and drawer_loot != null
		and drawer_key != null,
		"6.4 lab launches three reusable imported-model containers with real physical contents"
	)
	if (
		not launched or world == null or player == null or session == null
		or drawer == null or chest == null or cabinet == null
		or drawer_loot == null or drawer_key == null
	):
		_cleanup(application, tree)
		return

	var drawer_asset: Dictionary = drawer.get_asset_summary()
	var chest_asset: Dictionary = chest.get_asset_summary()
	var cabinet_asset: Dictionary = cabinet.get_asset_summary()
	var drawer_size: Vector3 = drawer_asset.get("closed_visual_size", Vector3.ZERO)
	var chest_size: Vector3 = chest_asset.get("closed_visual_size", Vector3.ZERO)
	var cabinet_size: Vector3 = cabinet_asset.get("closed_visual_size", Vector3.ZERO)
	assert_true.call(
		drawer_asset.get("asset_id", &"") == &"desk_drawer"
		and chest_asset.get("asset_id", &"") == &"wooden_chest"
		and cabinet_asset.get("asset_id", &"") == &"tall_cabinet"
		and int(drawer_asset.get("imported_model_count", 0)) >= 2
		and int(chest_asset.get("imported_model_count", 0)) >= 2
		and int(cabinet_asset.get("imported_model_count", 0)) >= 2,
		"Container variants are imported model asset scenes, not generated furniture geometry"
	)
	assert_true.call(
		drawer_size.x <= 1.0 and drawer_size.y <= 0.75 and drawer_size.z <= 0.70
		and chest_size.x <= 1.05 and chest_size.y <= 0.60 and chest_size.z <= 0.70
		and cabinet_size.x <= 0.90 and cabinet_size.y <= 1.50 and cabinet_size.z <= 0.60,
		"Container Lab imported furniture stays at human-scale dimensions relative to the 1.49 m player"
	)
	var drawer_loot_asset: Dictionary = drawer_loot.get_asset_summary()
	var drawer_key_asset: Dictionary = drawer_key.get_asset_summary()
	assert_true.call(
		drawer_loot_asset.get("asset_id", &"") == &"gold_cup"
		and drawer_key_asset.get("asset_id", &"") == &"brass_key"
		and str(drawer_loot_asset.get("model_path", "")).ends_with(".obj")
		and str(drawer_key_asset.get("model_path", "")).ends_with(".obj")
		and (drawer_loot_asset.get("visual_size", Vector3.ZERO) as Vector3).length() < 0.30
		and (drawer_key_asset.get("visual_size", Vector3.ZERO) as Vector3).length() < 0.18,
		"Container contents are realistically scaled imported collectible objects rather than universal generated blocks"
	)

	var state_events: Array[Dictionary] = []
	var state_handler: Callable = func(event: Dictionary) -> bool:
		state_events.append((event.get("payload", {}) as Dictionary).duplicate(true))
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			ContainerScript.STATE_CHANGED_EVENT_NAME,
			state_handler
		)),
		"Container terminal state changes use the existing detached semantic event route"
	)

	var drawer_loot_closed_position: Vector3 = drawer_loot.global_position
	_aim_player_at(player, Vector3(-1.45, 0.32, 0.27), 1.35)
	await _settle(tree, 3)
	var closed_target: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		closed_target.get("target_name", "") == "Drawer",
		"Closed imported drawer front physically occludes its contents and owns center-view interaction"
	)

	_press_interact()
	await _settle(tree, 2)
	_release_interact()
	await _settle(tree, 40)
	assert_true.call(
		drawer.get_semantic_phase() == ContainerScript.PHASE_OPEN
		and is_equal_approx(drawer.get_open_fraction(), 1.0)
		and state_events.size() >= 1
		and state_events[-1].get("container_id", &"") == &"container.drawer"
		and state_events[-1].get("state", &"") == ContainerScript.PHASE_OPEN,
		"Fresh F opens the imported sliding drawer assembly and emits one terminal state fact"
	)
	assert_true.call(
		drawer_loot.global_position.z > drawer_loot_closed_position.z + 0.30
		and drawer_key.global_position.z > drawer_loot_closed_position.z + 0.25,
		"Imported drawer tray and its authored contents anchor translate together into exposed world space"
	)

	_aim_player_at(
		player,
		drawer_loot.global_position
			+ (drawer_loot.get_node("CollisionShape3D") as CollisionShape3D).position,
		1.0
	)
	await _settle(tree, 3)
	var open_target: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		open_target.get("target_name", "") == drawer_loot.name,
		"Once exposed, the imported loot object becomes the independent center-view interaction target"
	)
	_press_interact()
	await _settle(tree, 2)
	_release_interact()
	await _settle(tree, 3)
	assert_true.call(
		(session.call("get_mission_run_summary") as Dictionary) == {
			"loot_count": 1,
			"loot_value": 25,
		}
		and not bool((session.call(
			"lookup_persistent_entity",
			"container_lab.drawer.loot25"
		) as Dictionary).get("ok", true))
		and bool((session.call(
			"lookup_persistent_entity",
			"container_lab.drawer.key"
		) as Dictionary).get("ok", false)),
		"Taking exposed imported loot reuses 6.3 collection ownership without a container inventory"
	)

	chest.request_open(player)
	cabinet.request_open(player)
	await _settle(tree, 40)
	var chest_mechanism: AnimatableBody3D = chest.get_mechanism()
	var cabinet_mechanism: AnimatableBody3D = cabinet.get_mechanism()
	assert_true.call(
		chest.get_semantic_phase() == ContainerScript.PHASE_OPEN
		and cabinet.get_semantic_phase() == ContainerScript.PHASE_OPEN
		and chest_mechanism != null
		and cabinet_mechanism != null
		and chest_mechanism.rotation.x < deg_to_rad(-90.0)
		and cabinet_mechanism.rotation.y < deg_to_rad(-90.0),
		"Authored rear-lid and side-door pivots produce real hinge opening instead of translated cavity-cover panels"
	)

	await _settle(tree, 2)
	var generation: int = int(application.call("request_quicksave"))
	var snapshot: Dictionary = await _wait_for_quicksave(
		application,
		tree,
		generation,
		120
	)
	var saved_world: Dictionary = snapshot.get("session", {}).get("world_state", {})
	var saved_container: Dictionary = (
		saved_world.get("persistent_entities", {}) as Dictionary
	).get("container_lab.drawer", {})
	assert_true.call(
		generation > 0
		and not snapshot.is_empty()
		and saved_container.get("phase", &"") == ContainerScript.PHASE_OPEN
		and is_equal_approx(float(saved_container.get("open_fraction", -1.0)), 1.0)
		and (saved_world.get("object_existence", {}) as Dictionary).get(
			"authored_tombstones",
			[]
		).has("container_lab.drawer.loot25"),
		"Quicksave records imported-container semantic state and collected child tombstone through existing owners"
	)

	drawer.request_close(player)
	await _settle(tree, 40)
	var diverged_key: bool = (
		drawer_key != null
		and is_instance_valid(drawer_key)
		and bool(player.call("collect_authored_pickup", drawer_key))
	)
	assert_true.call(
		diverged_key
		and bool(player.call("has_semantic_possession", &"key.container.lab")),
		"Live imported-container/possession state can diverge after the committed snapshot"
	)
	await _settle(tree, 2)

	var quickloaded: bool = bool(application.call("quickload_latest"))
	await tree.process_frame
	await _settle(tree, 4)
	var restored_world := application.get("current_world") as Node3D
	var restored_session := application.get("current_session") as Node
	var restored_player := application.get("current_player") as CharacterBody3D
	if (
		not quickloaded or restored_world == null
		or restored_session == null or restored_player == null
	):
		assert_true.call(false, "6.4 quickload rebuilds a replacement world before restore assertions")
		_cleanup(application, tree)
		return
	var restored_drawer := restored_world.get_node_or_null("Drawer") as VarkOrdinaryContainer
	var restored_key_lookup: Dictionary = restored_session.call(
		"lookup_persistent_entity",
		"container_lab.drawer.key"
	)
	assert_true.call(
		restored_drawer != null
		and restored_drawer.get_semantic_phase() == ContainerScript.PHASE_OPEN
		and is_equal_approx(restored_drawer.get_open_fraction(), 1.0)
		and not bool((restored_session.call(
			"lookup_persistent_entity",
			"container_lab.drawer.loot25"
		) as Dictionary).get("ok", true))
		and bool(restored_key_lookup.get("ok", false))
		and not bool(restored_player.call("has_semantic_possession", &"key.container.lab"))
		and (restored_session.call("get_mission_run_summary") as Dictionary) == {
			"loot_count": 1,
			"loot_value": 25,
		}
		and int(restored_session.call("get_pending_semantic_event_count")) == 0,
		"Quickload restores imported container pose, collected-loot absence, remaining key and saved run state without replay"
	)

	_cleanup(application, tree)


func _aim_player_at(
	player: CharacterBody3D,
	target: Vector3,
	distance: float
) -> void:
	player.global_position = Vector3(target.x, 0.0, target.z + distance)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	var head := player.get_node("Head") as Node3D
	head.rotation.x = atan2(target.y - 1.3, distance)


func _cleanup(application: Node, tree: SceneTree) -> void:
	_release_interact()
	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _press_interact() -> void:
	Input.action_press("interact")


func _release_interact() -> void:
	Input.action_release("interact")


func _settle(tree: SceneTree, frames: int = 1) -> void:
	for _index: int in frames:
		await tree.physics_frame
		await tree.process_frame


func _wait_for_quicksave(
	application: Node,
	tree: SceneTree,
	generation: int,
	max_frames: int
) -> Dictionary:
	var coordinator := application.get_node_or_null("SaveCoordinator") as Node
	if coordinator == null or generation <= 0:
		return {}
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
