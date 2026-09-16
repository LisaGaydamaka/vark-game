extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")


func run(tree: SceneTree, assert_true: Callable) -> void:
	_release_interact()
	var application: Node = ApplicationScene.instantiate()
	var default_labels: PackedStringArray = application.get("development_launch_labels")
	var default_paths: PackedStringArray = application.get("development_launch_resource_paths")
	assert_true.call(
		default_labels.has("Interaction Lab")
		and default_paths.has("res://scenes/InteractionLab.tscn"),
		"Application Development Launch exposes the 3.1 Interaction Lab"
	)

	application.set(
		"development_launch_labels",
		PackedStringArray(["Interaction Lab"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray(["res://scenes/InteractionLab.tscn"])
	)
	tree.get_root().add_child(application)
	await tree.process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	await tree.process_frame
	await _settle_player_physics(tree)
	var world: Node = application.get("current_world") as Node
	var player: Node3D = application.get("current_player") as Node3D
	assert_true.call(
		launched
		and world != null
		and world.name == &"InteractionLab"
		and player != null
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY,
		"Interaction Lab launches through the production application/session/input path"
	)
	if world == null or player == null:
		_release_interact()
		application.queue_free()
		await tree.process_frame
		return

	var door: Node3D = world.get_node("DoorProbe") as Node3D
	var prop: Node3D = world.get_node("PropProbe") as Node3D
	var divider: Node3D = world.get_node("Divider") as Node3D
	var door_position: Vector3 = door.position
	var prop_position: Vector3 = prop.position
	var divider_position: Vector3 = divider.position

	# The lab starts with the door exactly on the player's normal forward camera axis.
	# Keeping the camera under its real PlayerLook owner makes this proof exercise the
	# production center-view direction rather than mutating a child camera in tests.
	await _settle_player_physics(tree)
	var centered_state: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		bool(door.call("is_interaction_highlighted"))
		and bool(centered_state.get("has_target", false))
		and centered_state.get("target_name", "") == "DoorProbe",
		"Center-view interaction targeting highlights the first eligible in-range hit"
	)

	player.global_position = Vector3(0, 0, 5)
	player.set("velocity", Vector3.ZERO)
	await _settle_player_physics(tree)
	assert_true.call(
		not bool(door.call("is_interaction_highlighted"))
		and not bool((player.call("get_interaction_semantic_state") as Dictionary).get("has_target", false)),
		"Interaction targeting rejects an otherwise valid target outside the configured range"
	)

	player.global_position = Vector3(0, 0, 2)
	player.set("velocity", Vector3.ZERO)
	# Put the prop unambiguously inside range and raise its small box through the
	# player's normal horizontal camera ray. The divider sits between camera and
	# prop, while the door moves aside so first-hit semantics are unambiguous.
	door.position = Vector3(-3.0, door_position.y, door_position.z)
	prop.position = Vector3(0, 1.3, 0)
	divider.position = Vector3(0, 0.9, 1.0)
	await _settle_player_physics(tree, 2)
	assert_true.call(
		not bool(prop.call("is_interaction_highlighted"))
		and not bool((player.call("get_interaction_semantic_state") as Dictionary).get("has_target", false)),
		"Interaction targeting treats the first blocking physics hit as occlusion"
	)

	divider.position = Vector3(-3, divider_position.y, divider_position.z)
	await _settle_player_physics(tree, 2)
	assert_true.call(
		bool(prop.call("is_interaction_highlighted"))
		and (player.call("get_interaction_semantic_state") as Dictionary).get("target_name", "") == "PropProbe",
		"An eligible in-range target highlights once the center-view line is unobstructed"
	)

	prop.call("set_interaction_enabled", false)
	await _settle_player_physics(tree)
	assert_true.call(
		not bool(prop.call("is_interaction_highlighted"))
		and not bool((player.call("get_interaction_semantic_state") as Dictionary).get("has_target", false)),
		"Target-owned current-state eligibility can reject interaction without changing the selector"
	)
	prop.call("set_interaction_enabled", true)

	# Restore the authored lab layout before exercising primary interaction so the
	# door is again the real center-view target and the manual fixture stays legible.
	door.position = door_position
	prop.position = prop_position
	divider.position = divider_position
	await _settle_player_physics(tree, 2)
	assert_true.call(
		bool(door.call("is_interaction_highlighted"))
		and (player.call("get_interaction_semantic_state") as Dictionary).get("target_name", "") == "DoorProbe",
		"Door probe is reacquired on the normal center-view axis before primary interaction"
	)

	var door_count_before: int = int(door.call("get_interaction_count"))
	Input.action_press("interact")
	await _settle_player_physics(tree)
	var first_count: int = int(door.call("get_interaction_count"))
	await _settle_player_physics(tree)
	var held_count: int = int(door.call("get_interaction_count"))
	Input.action_release("interact")
	await _settle_player_physics(tree)
	Input.action_press("interact")
	await _settle_player_physics(tree)
	var second_count: int = int(door.call("get_interaction_count"))
	Input.action_release("interact")
	await _settle_player_physics(tree)
	assert_true.call(
		first_count == door_count_before + 1
		and held_count == first_count
		and second_count == first_count + 1,
		"Primary interaction consumes one fresh application-owned edge instead of repeating while held"
	)

	player.call("set_world_interaction_available", false)
	var unavailable_state: Dictionary = player.call("get_interaction_semantic_state")
	var unavailable_count_before: int = int(door.call("get_interaction_count"))
	Input.action_press("interact")
	await _settle_player_physics(tree)
	Input.action_release("interact")
	await _settle_player_physics(tree)
	assert_true.call(
		not bool(unavailable_state.get("available", true))
		and not bool(door.call("is_interaction_highlighted"))
		and int(door.call("get_interaction_count")) == unavailable_count_before,
		"Player interaction ownership can centrally suppress ordinary world interaction"
	)

	player.call("set_world_interaction_available", true)
	await _settle_player_physics(tree)
	assert_true.call(
		bool(door.call("is_interaction_highlighted"))
		and bool((player.call("get_interaction_semantic_state") as Dictionary).get("available", false)),
		"Central interaction availability can resume without teaching the interactable private owner state"
	)

	_release_interact()
	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _settle_player_physics(tree: SceneTree, frame_count: int = 1) -> void:
	for _frame_index: int in frame_count:
		# SceneTree.physics_frame is emitted before node _physics_process callbacks.
		# Waiting for process_frame afterward observes the completed physics update.
		await tree.physics_frame
		await tree.process_frame


func _release_interact() -> void:
	Input.action_release("interact")
