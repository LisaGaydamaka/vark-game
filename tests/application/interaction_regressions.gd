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
	await tree.physics_frame
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

	var camera: Camera3D = player.get_node("Head/Camera3D") as Camera3D
	var door: Node3D = world.get_node("DoorProbe") as Node3D
	var prop: Node3D = world.get_node("PropProbe") as Node3D
	var divider: Node3D = world.get_node("Divider") as Node3D

	_aim(camera, door)
	await tree.physics_frame
	var centered_state: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		bool(door.call("is_interaction_highlighted"))
		and bool(centered_state.get("has_target", false))
		and centered_state.get("target_name", "") == "DoorProbe",
		"Center-view interaction targeting highlights the first eligible in-range hit"
	)

	player.global_position = Vector3(0, 0, 5)
	player.set("velocity", Vector3.ZERO)
	_aim(camera, door)
	await tree.physics_frame
	assert_true.call(
		not bool(door.call("is_interaction_highlighted"))
		and not bool((player.call("get_interaction_semantic_state") as Dictionary).get("has_target", false)),
		"Interaction targeting rejects an otherwise valid target outside the configured range"
	)

	player.global_position = Vector3(0, 0, 2)
	player.set("velocity", Vector3.ZERO)
	_aim(camera, prop)
	await tree.physics_frame
	assert_true.call(
		not bool(prop.call("is_interaction_highlighted")),
		"Interaction targeting treats the first blocking physics hit as occlusion"
	)

	var divider_position: Vector3 = divider.position
	divider.position = Vector3(-3, divider_position.y, divider_position.z)
	_aim(camera, prop)
	await tree.physics_frame
	assert_true.call(
		bool(prop.call("is_interaction_highlighted")),
		"An eligible target highlights once the center-view line is unobstructed"
	)

	prop.call("set_interaction_enabled", false)
	await tree.physics_frame
	assert_true.call(
		not bool(prop.call("is_interaction_highlighted"))
		and not bool((player.call("get_interaction_semantic_state") as Dictionary).get("has_target", false)),
		"Target-owned current-state eligibility can reject interaction without changing the selector"
	)
	prop.call("set_interaction_enabled", true)

	_aim(camera, door)
	await tree.physics_frame
	var door_count_before: int = int(door.call("get_interaction_count"))
	Input.action_press("interact")
	await tree.physics_frame
	var first_count: int = int(door.call("get_interaction_count"))
	await tree.physics_frame
	var held_count: int = int(door.call("get_interaction_count"))
	Input.action_release("interact")
	await tree.physics_frame
	Input.action_press("interact")
	await tree.physics_frame
	var second_count: int = int(door.call("get_interaction_count"))
	Input.action_release("interact")
	await tree.physics_frame
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
	await tree.physics_frame
	Input.action_release("interact")
	await tree.physics_frame
	assert_true.call(
		not bool(unavailable_state.get("available", true))
		and not bool(door.call("is_interaction_highlighted"))
		and int(door.call("get_interaction_count")) == unavailable_count_before,
		"Player interaction ownership can centrally suppress ordinary world interaction"
	)

	player.call("set_world_interaction_available", true)
	_aim(camera, door)
	await tree.physics_frame
	assert_true.call(
		bool(door.call("is_interaction_highlighted"))
		and bool((player.call("get_interaction_semantic_state") as Dictionary).get("available", false)),
		"Central interaction availability can resume without teaching the interactable private owner state"
	)

	_release_interact()
	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _aim(camera: Camera3D, target: Node3D) -> void:
	camera.look_at(target.global_position, Vector3.UP)


func _release_interact() -> void:
	Input.action_release("interact")
