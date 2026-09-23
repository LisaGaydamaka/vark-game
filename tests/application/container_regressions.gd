extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const Container = preload("res://gameplay/containers/ordinary_container.gd")
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

	application.set(
		"development_launch_labels",
		PackedStringArray(["Container Lab"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([LAB_PATH])
	)
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
	var drawer_loot_lookup: Dictionary = (
		session.call("lookup_persistent_entity", "container_lab.drawer.loot25")
		if session != null else {}
	)
	var drawer_loot := drawer_loot_lookup.get("node") as VarkCollectible
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
		and drawer_key != null
		and drawer.get_semantic_phase() == Container.PHASE_CLOSED
		and chest.get_semantic_phase() == Container.PHASE_CLOSED
		and cabinet.get_semantic_phase() == Container.PHASE_CLOSED,
		"6.4 lab launches three real reusable container variants with authored physical contents"
	)

	var state_events: Array[Dictionary] = []
	var state_handler: Callable = func(event: Dictionary) -> bool:
		state_events.append((event.get("payload", {}) as Dictionary).duplicate(true))
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			Container.STATE_CHANGED_EVENT_NAME,
			state_handler
		)),
		"Container terminal state changes use the existing detached semantic event route"
	)

	# Closed drawer geometry must make the container the first target, not its contents.
	player.global_position = Vector3(-3.0, 0.0, 2.7)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	(player.get_node("Head") as Node3D).rotation.x = deg_to_rad(-8.0)
	await _settle(tree, 3)
	var closed_target: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		closed_target.get("target_name", "") == "Drawer",
		"Closed drawer physically occludes its contents and owns center-view interaction"
	)

	_press_interact()
	await _settle(tree, 2)
	_release_interact()
	await _settle(tree, 40)
	assert_true.call(
		drawer.get_semantic_phase() == Container.PHASE_OPEN
		and is_equal_approx(drawer.get_open_fraction(), 1.0)
		and state_events.size() >= 1
		and state_events[-1].get("container_id", &"") == &"container.drawer"
		and state_events[-1].get("state", &"") == Container.PHASE_OPEN,
		"Fresh F opens the sliding drawer physically and emits one terminal container state fact"
	)

	var contents := drawer.get_node("Contents") as Node3D
	assert_true.call(
		contents.global_position.z > drawer.global_position.z + 0.75
		and drawer_loot.global_position.z > drawer.global_position.z + 0.75
		and drawer_key.global_position.z > drawer.global_position.z + 0.75,
		"Drawer contents move into exposed world space with the physical drawer mechanism"
	)

	# Reposition above the open drawer and take only one physical loot object.
	player.global_position = Vector3(
		drawer_loot.global_position.x,
		0.0,
		drawer_loot.global_position.z + 1.25
	)
	player.velocity = Vector3.ZERO
	(player.get_node("Head") as Node3D).rotation.x = deg_to_rad(-18.0)
	await _settle(tree, 3)
	var open_target: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		open_target.get("target_name", "") == drawer_loot.name,
		"Once physically exposed, the ordinary child loot becomes the independent center-view interaction target"
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
		"Taking exposed container loot reuses 6.3 collection/tombstone/run-stat ownership without a container inventory"
	)

	# Prove the same archetype supports hinge variants.
	chest.request_open(player)
	cabinet.request_open(player)
	await _settle(tree, 40)
	assert_true.call(
		chest.get_semantic_phase() == Container.PHASE_OPEN
		and cabinet.get_semantic_phase() == Container.PHASE_OPEN
		and chest.get_node("Mechanism").rotation.x < deg_to_rad(-90.0)
		and cabinet.get_node("Mechanism").rotation.y < deg_to_rad(-90.0),
		"The same container archetype supports top-hinged chest and front-hinged cabinet mechanisms without separate gameplay code"
	)

	# Save with drawer open, 25 loot collected, key still present.
	await _settle(tree, 2)
	var generation: int = int(application.call("request_quicksave"))
	var snapshot: Dictionary = await _wait_for_quicksave(application, tree, 120)
	var saved_world: Dictionary = snapshot.get("session", {}).get("world_state", {})
	var saved_container: Dictionary = (
		saved_world.get("persistent_entities", {}) as Dictionary
	).get("container_lab.drawer", {})
	assert_true.call(
		generation > 0
		and not snapshot.is_empty()
		and saved_container.get("phase", &"") == Container.PHASE_OPEN
		and is_equal_approx(float(saved_container.get("open_fraction", -1.0)), 1.0)
		and (saved_world.get("object_existence", {}) as Dictionary).get(
			"authored_tombstones",
			[]
		).has("container_lab.drawer.loot25"),
		"Quicksave records physical container state and collected child-object tombstone through existing persistence owners"
	)

	# Deliberately diverge after capture: close drawer and collect the key directly.
	drawer.request_close(player)
	await _settle(tree, 40)
	assert_true.call(
		bool(player.call("collect_authored_pickup", drawer_key))
		and bool(player.call("has_semantic_possession", &"key.container.lab")),
		"Live container/possession state can diverge after the committed 6.4 snapshot"
	)

	var quickloaded: bool = bool(application.call("quickload_latest"))
	await tree.process_frame
	await _settle(tree, 4)
	var restored_world := application.get("current_world") as Node3D
	var restored_session := application.get("current_session") as Node
	var restored_player := application.get("current_player") as CharacterBody3D
	var restored_drawer := restored_world.get_node_or_null("Drawer") as VarkOrdinaryContainer
	var restored_key_lookup: Dictionary = restored_session.call(
		"lookup_persistent_entity",
		"container_lab.drawer.key"
	)
	assert_true.call(
		quickloaded
		and restored_drawer != null
		and restored_drawer.get_semantic_phase() == Container.PHASE_OPEN
		and is_equal_approx(restored_drawer.get_open_fraction(), 1.0)
		and restored_world.find_child("container_lab.drawer.loot25", true, false) == null
		and not bool((restored_session.call(
			"lookup_persistent_entity",
			"container_lab.drawer.loot25"
		) as Dictionary).get("ok", true))
		and bool(restored_key_lookup.get("ok", false))
		and not bool(restored_player.call(
			"has_semantic_possession",
			&"key.container.lab"
		))
		and (restored_session.call("get_mission_run_summary") as Dictionary) == {
			"loot_count": 1,
			"loot_value": 25,
		}
		and int(restored_session.call("get_pending_semantic_event_count")) == 0,
		"Quickload restores the open container, collected-loot absence, remaining physical key, and saved run state without replaying consequences"
	)

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
	max_frames: int
) -> Dictionary:
	for _index: int in max_frames:
		var snapshot: Dictionary = application.call("get_latest_quicksave_snapshot")
		if not snapshot.is_empty():
			return snapshot
		await tree.physics_frame
		await tree.process_frame
	return {}
