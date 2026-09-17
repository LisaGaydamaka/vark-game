extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")
const OrdinaryDoor = preload("res://gameplay/doors/ordinary_door.gd")


func run(tree: SceneTree, assert_true: Callable) -> void:
	_release_interact()
	var application: Node = ApplicationScene.instantiate()
	var default_labels: PackedStringArray = application.get("development_launch_labels")
	var default_paths: PackedStringArray = application.get("development_launch_resource_paths")
	assert_true.call(
		default_labels.has("Door Lab")
		and default_paths.has("res://scenes/DoorLab.tscn"),
		"Application Development Launch exposes the 3.4 Door Lab"
	)

	application.set("development_launch_labels", PackedStringArray(["Door Lab"]))
	application.set(
		"development_launch_resource_paths",
		PackedStringArray(["res://scenes/DoorLab.tscn"])
	)
	tree.get_root().add_child(application)
	await tree.process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	await tree.process_frame
	await _settle_player_physics(tree, 2)
	var world: Node3D = application.get("current_world") as Node3D
	var player: Node3D = application.get("current_player") as Node3D
	var session: Node = application.get("current_session") as Node
	assert_true.call(
		launched
		and world != null
		and world.name == &"DoorLab"
		and player != null
		and session != null
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY,
		"Door Lab launches through the production application/session/input path"
	)
	if world == null or player == null or session == null:
		_release_interact()
		application.queue_free()
		await tree.process_frame
		return

	var door: AnimatableBody3D = world.get_node("OrdinaryDoor") as AnimatableBody3D
	var vision_target: StaticBody3D = world.get_node("VisionTarget") as StaticBody3D
	var door_mesh: MeshInstance3D = door.get_node("DoorMesh") as MeshInstance3D
	var door_material: StandardMaterial3D = door_mesh.material_override as StandardMaterial3D

	var door_events: Array[StringName] = []
	var sound_events: Array[Dictionary] = []
	var door_handler: Callable = func(event: Dictionary) -> bool:
		var payload: Dictionary = event.get("payload", {})
		door_events.append(payload.get("state", &""))
		return true
	var sound_handler: Callable = func(event: Dictionary) -> bool:
		sound_events.append(event)
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			OrdinaryDoor.STATE_CHANGED_EVENT_NAME,
			door_handler
		))
		and bool(session.call(
			"register_semantic_event_handler",
			&"gameplay.sound",
			sound_handler
		)),
		"Ordinary door registers consumers through the accepted semantic event route"
	)

	var initial_state: Dictionary = door.call("capture_semantic_state")
	var centered_state: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		initial_state == {
			"phase": OrdinaryDoor.PHASE_CLOSED,
			"open_fraction": 0.0,
		}
		and not bool(door.call("is_navigation_passage_open"))
		and is_zero_approx(float(door.call("get_acoustic_openness"))),
		"Ordinary door begins as one authoritative CLOSED semantic state with closed nav/acoustic seams"
	)
	assert_true.call(
		bool(door.call("is_interaction_highlighted"))
		and bool(centered_state.get("has_target", false))
		and centered_state.get("target_name", "") == "OrdinaryDoor"
		and door_material != null
		and door_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		and door_material.disable_receive_shadows
		and door_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"Real ordinary door consumes the accepted center-view interaction and Thief-style selection contract"
	)
	assert_true.call(
		_first_ray_collider(world, Vector3(0, 1.1, 1.5), Vector3(0, 1.1, -2.2)) == door
		and _door_overlaps_passage_probe(world, door),
		"Closed ordinary door is the physical and vision obstruction across its doorway"
	)

	Input.action_press("interact")
	await _settle_player_physics(tree)
	Input.action_release("interact")
	await _settle_player_physics(tree, 3)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPENING
		and sound_events.size() == 1
		and door_events.is_empty(),
		"Fresh F interaction starts the real door transition and emits gameplay sound without prematurely publishing OPEN"
	)
	var first_sound_payload: Dictionary = {}
	if sound_events.size() == 1:
		first_sound_payload = sound_events[0].get("payload", {})
	assert_true.call(
		first_sound_payload.get("kind", &"") == OrdinaryDoor.USE_SOUND_KIND
		and first_sound_payload.get("origin", Vector3.ZERO) is Vector3
		and is_equal_approx(
			float(first_sound_payload.get("strength", 0.0)),
			float(door.get("gameplay_sound_strength"))
		)
		and not first_sound_payload.has("audio_stream")
		and not first_sound_payload.has("volume_db"),
		"Door use emits only the 3.3 semantic gameplay-sound source fact, not presentation audio"
	)

	var mid_state: Dictionary = door.call("capture_semantic_state")
	assert_true.call(
		mid_state.get("phase", &"") == OrdinaryDoor.PHASE_OPENING
		and float(mid_state.get("open_fraction", 0.0)) > 0.0
		and float(mid_state.get("open_fraction", 1.0)) < 1.0,
		"Door semantic capture preserves explicit in-progress opening state instead of a timer/coroutine"
	)

	await _settle_player_physics(tree, 45)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPEN
		and is_equal_approx(float(door.call("get_open_fraction")), 1.0)
		and bool(door.call("is_navigation_passage_open"))
		and is_equal_approx(float(door.call("get_acoustic_openness")), 1.0)
		and door_events == [OrdinaryDoor.PHASE_OPEN],
		"Completed opening publishes OPEN once and exposes the same open state through nav/acoustic door seams"
	)
	assert_true.call(
		_first_ray_collider(world, Vector3(0, 1.1, 1.5), Vector3(0, 1.1, -2.2)) == vision_target
		and not _door_overlaps_passage_probe(world, door),
		"Open ordinary door clears the same doorway for physical passage and straight-through vision"
	)

	var open_state: Dictionary = door.call("capture_semantic_state")
	var event_count_before_apply: int = door_events.size()
	var sound_count_before_apply: int = sound_events.size()
	assert_true.call(
		bool(door.call("apply_semantic_state", mid_state))
		and door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPENING
		and is_equal_approx(
			float(door.call("get_open_fraction")),
			float(mid_state.get("open_fraction", -1.0))
		)
		and door_events.size() == event_count_before_apply
		and sound_events.size() == sound_count_before_apply,
		"Applying captured door progress restores semantic/derived state without replaying interaction consequences"
	)
	assert_true.call(
		not bool(door.call("apply_semantic_state", {
			"phase": OrdinaryDoor.PHASE_OPEN,
			"open_fraction": 0.5,
		})),
		"Ordinary door rejects internally inconsistent semantic restore state"
	)
	assert_true.call(
		bool(door.call("apply_semantic_state", open_state))
		and door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPEN
		and bool(door.call("is_navigation_passage_open")),
		"Applying a captured OPEN state restores the door-side consumer seams from semantic truth"
	)
	await _settle_player_physics(tree, 2)

	door.call("interact", player)
	await _settle_player_physics(tree, 3)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSING
		and sound_events.size() == 2,
		"The same ordinary interaction contract reverses an open door into a closing transition"
	)
	await _settle_player_physics(tree, 45)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSED
		and is_zero_approx(float(door.call("get_open_fraction")))
		and not bool(door.call("is_navigation_passage_open"))
		and is_zero_approx(float(door.call("get_acoustic_openness")))
		and door_events == [OrdinaryDoor.PHASE_OPEN, OrdinaryDoor.PHASE_CLOSED],
		"Completed closing republishes CLOSED and returns both door-side consumer seams to closed state"
	)
	assert_true.call(
		_first_ray_collider(world, Vector3(0, 1.1, 1.5), Vector3(0, 1.1, -2.2)) == door
		and _door_overlaps_passage_probe(world, door),
		"Closing restores the ordinary door's physical and vision obstruction"
	)

	_release_interact()
	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _first_ray_collider(world: Node3D, from: Vector3, to: Vector3) -> Object:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider", null) as Object


func _door_overlaps_passage_probe(world: Node3D, door: CollisionObject3D) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 1.8, 0.35)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0))
	query.collision_mask = 1
	for result: Dictionary in world.get_world_3d().direct_space_state.intersect_shape(query, 32):
		if result.get("collider", null) == door:
			return true
	return false


func _settle_player_physics(tree: SceneTree, frame_count: int = 1) -> void:
	for _frame_index: int in frame_count:
		await tree.physics_frame
		await tree.process_frame


func _release_interact() -> void:
	Input.action_release("interact")
