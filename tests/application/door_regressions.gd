extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")
const OrdinaryDoor = preload("res://gameplay/doors/ordinary_door.gd")
const DefaultDoorVisual: Mesh = preload("res://assets/models/doors/ordinary_door_leaf.obj")
const AlternateDoorVisual: Mesh = preload("res://assets/models/doors/ordinary_door_leaf_narrow.obj")


class SemanticPossessionProbe:
	extends Node

	var possession_ids: Dictionary = {}

	func has_semantic_possession(possession_id: StringName) -> bool:
		return possession_ids.has(str(possession_id))


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
	var locked_door: AnimatableBody3D = world.get_node("LockedDoor") as AnimatableBody3D
	var barred_door: AnimatableBody3D = world.get_node("BarredDoor") as AnimatableBody3D
	var vision_target: StaticBody3D = world.get_node("VisionTarget") as StaticBody3D
	var left_wall: StaticBody3D = world.get_node("LeftWall") as StaticBody3D
	var right_wall: StaticBody3D = world.get_node("RightWall") as StaticBody3D
	var door_mesh: MeshInstance3D = door.get_node("DoorMesh") as MeshInstance3D
	var door_collision: CollisionShape3D = door.get_node("CollisionShape3D") as CollisionShape3D
	var left_wall_collision: CollisionShape3D = left_wall.get_node("CollisionShape3D") as CollisionShape3D
	var right_wall_collision: CollisionShape3D = right_wall.get_node("CollisionShape3D") as CollisionShape3D
	var left_wall_shape: BoxShape3D = left_wall_collision.shape as BoxShape3D
	var right_wall_shape: BoxShape3D = right_wall_collision.shape as BoxShape3D
	var door_material: StandardMaterial3D = door_mesh.material_override as StandardMaterial3D
	var door_shape: BoxShape3D = door_collision.shape as BoxShape3D
	assert_true.call(
		door_shape != null
		and is_equal_approx(door_shape.size.x, 1.30)
		and is_equal_approx(door_collision.position.x, 0.65),
		"Ordinary door keeps its established full-width shared collision leaf"
	)

	var door_events: Array[StringName] = []
	var sound_events: Array[Dictionary] = []
	var restriction_events: Array[Dictionary] = []
	var access_denied_events: Array[Dictionary] = []
	var door_handler: Callable = func(event: Dictionary) -> bool:
		var payload: Dictionary = event.get("payload", {})
		door_events.append(payload.get("state", &""))
		return true
	var sound_handler: Callable = func(event: Dictionary) -> bool:
		sound_events.append(event)
		return true
	var restriction_handler: Callable = func(event: Dictionary) -> bool:
		restriction_events.append((event.get("payload", {}) as Dictionary).duplicate(true))
		return true
	var denied_handler: Callable = func(event: Dictionary) -> bool:
		access_denied_events.append((event.get("payload", {}) as Dictionary).duplicate(true))
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
		))
		and bool(session.call(
			"register_semantic_event_handler",
			OrdinaryDoor.RESTRICTION_CHANGED_EVENT_NAME,
			restriction_handler
		))
		and bool(session.call(
			"register_semantic_event_handler",
			OrdinaryDoor.ACCESS_DENIED_EVENT_NAME,
			denied_handler
		)),
		"Ordinary door registers motion, restriction, denial, and gameplay-sound consumers through the accepted semantic event route"
	)

	var initial_state: Dictionary = door.call("capture_semantic_state")
	var centered_state: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		initial_state == {
			"phase": OrdinaryDoor.PHASE_CLOSED,
			"open_fraction": 0.0,
			"motion_blocked": false,
			"locked": false,
			"barred": false,
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

	var locked_access: Dictionary = locked_door.call("get_access_summary")
	var barred_access: Dictionary = barred_door.call("get_access_summary")
	assert_true.call(
		bool(locked_access.get("locked", false))
		and not bool(locked_access.get("barred", true))
		and str(locked_access.get("required_key_id", "")) == "key.lab"
		and str(locked_access.get("opening_variant", "")) == "metal"
		and str(locked_access.get("visual_model_path", ""))
			== "res://assets/models/doors/ordinary_door_leaf_narrow.obj"
		and (locked_door.get_node("DoorMesh") as MeshInstance3D).mesh == AlternateDoorVisual
		and not bool(barred_access.get("locked", true))
		and bool(barred_access.get("barred", false))
		and str(barred_access.get("opening_variant", "")) == "window_like",
		"Door Lab exposes locked/keyed, barred, and compatible external-model variants through the same OrdinaryDoor archetype"
	)

	var configured_visual: Mesh = door.call("get_visual_model") as Mesh
	var state_before_model_swap: Dictionary = door.call("capture_semantic_state")
	var centered_before_model_swap: Dictionary = player.call("get_interaction_semantic_state")
	var collision_shape_before_model_swap: Shape3D = door_collision.shape
	var door_instance_id_before_model_swap: int = door.get_instance_id()
	assert_true.call(
		configured_visual == DefaultDoorVisual
		and door_mesh.mesh == DefaultDoorVisual
		and configured_visual.resource_path == "res://assets/models/doors/ordinary_door_leaf.obj",
		"Ordinary door instantiates its visible leaf from the configured external model resource"
	)

	var door_aabb: AABB = configured_visual.get_aabb()
	var left_frame_inner_x: float = left_wall.global_position.x + left_wall_shape.size.x * 0.5
	var right_frame_inner_x: float = right_wall.global_position.x - right_wall_shape.size.x * 0.5
	var door_left_x: float = door_mesh.global_position.x + door_aabb.position.x
	var door_right_x: float = door_left_x + door_aabb.size.x
	assert_true.call(
		is_equal_approx(door_left_x - left_frame_inner_x, 0.01)
		and is_equal_approx(right_frame_inner_x - door_right_x, 0.01),
		"Door Lab frame fits the ordinary 1.30 m leaf with only 1 cm side clearance"
	)

	var swapped_model: bool = bool(door.call("set_visual_model", AlternateDoorVisual))
	var replacement_visual: Mesh = door.call("get_visual_model") as Mesh
	var centered_after_model_swap: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		swapped_model
		and door.get_instance_id() == door_instance_id_before_model_swap
		and door.get_script() == OrdinaryDoor
		and replacement_visual == AlternateDoorVisual
		and door_mesh.mesh == AlternateDoorVisual
		and door_collision.shape == collision_shape_before_model_swap
		and door.call("capture_semantic_state") == state_before_model_swap
		and centered_before_model_swap.get("target_name", "") == "OrdinaryDoor"
		and centered_after_model_swap.get("target_name", "") == "OrdinaryDoor"
		and bool(door.call("is_interaction_highlighted"))
		and door_mesh.material_override == door_material
		and door.is_in_group(&"vark_interactable")
		and not bool(door.call("is_navigation_passage_open"))
		and is_zero_approx(float(door.call("get_acoustic_openness"))),
		"Compatible model replacement keeps the same semantic owner, interaction target, collider, highlight, and door-side state"
	)
	assert_true.call(
		_first_ray_collider(world, Vector3(0, 1.1, 1.5), Vector3(0, 1.1, -2.2)) == door
		and _door_overlaps_passage_probe(world, door),
		"Visual model replacement does not replace the closed-door collision or vision obstruction"
	)

	Input.action_press("interact")
	await _settle_player_physics(tree)
	Input.action_release("interact")
	await _settle_player_physics(tree, 3)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPENING
		and not bool(door.call("is_motion_blocked"))
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
		and float(mid_state.get("open_fraction", 1.0)) < 1.0
		and not bool(mid_state.get("motion_blocked", true)),
		"Door semantic capture preserves explicit in-progress opening state instead of a timer/coroutine"
	)

	await _settle_player_physics(tree, 45)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPEN
		and is_equal_approx(float(door.call("get_open_fraction")), 1.0)
		and not bool(door.call("is_motion_blocked"))
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

	var open_leaf_center: Vector3 = door_collision.global_position
	var open_leaf_normal := Vector3(
		door_collision.global_transform.basis.z.x,
		0.0,
		door_collision.global_transform.basis.z.z
	).normalized()
	assert_true.call(
		_first_ray_collider(
			world,
			open_leaf_center - open_leaf_normal * 0.55,
			open_leaf_center + open_leaf_normal * 0.55
		) == door,
		"Fully open ordinary door still blocks sight across the rotated physical leaf"
	)

	var open_state: Dictionary = door.call("capture_semantic_state")
	var event_count_before_apply: int = door_events.size()
	var sound_count_before_apply: int = sound_events.size()
	var mid_applied: bool = bool(door.call("apply_semantic_state", mid_state))
	var partial_leaf_center: Vector3 = door_collision.global_position
	var partial_leaf_normal := Vector3(
		door_collision.global_transform.basis.z.x,
		0.0,
		door_collision.global_transform.basis.z.z
	).normalized()
	var partial_leaf_blocks_ray: bool = (
		_first_ray_collider(
			world,
			partial_leaf_center - partial_leaf_normal * 0.55,
			partial_leaf_center + partial_leaf_normal * 0.55
		) == door
	)
	assert_true.call(
		mid_applied
		and partial_leaf_blocks_ray
		and door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPENING
		and is_equal_approx(
			float(door.call("get_open_fraction")),
			float(mid_state.get("open_fraction", -1.0))
		)
		and not bool(door.call("is_motion_blocked"))
		and door_events.size() == event_count_before_apply
		and sound_events.size() == sound_count_before_apply,
		"Applying captured door progress restores semantic/derived state, keeps the partial rotated leaf as a sight blocker, and replays no interaction consequences"
	)
	assert_true.call(
		not bool(door.call("apply_semantic_state", {
			"phase": OrdinaryDoor.PHASE_OPEN,
			"open_fraction": 0.5,
			"motion_blocked": false,
			"locked": false,
			"barred": false,
		})),
		"Ordinary door rejects internally inconsistent semantic restore state"
	)
	assert_true.call(
		not bool(door.call("apply_semantic_state", {
			"phase": OrdinaryDoor.PHASE_OPEN,
			"open_fraction": 1.0,
			"motion_blocked": true,
			"locked": false,
			"barred": false,
		})),
		"Ordinary door rejects impossible terminal state marked as motion-blocked"
	)
	assert_true.call(
		bool(door.call("apply_semantic_state", open_state))
		and door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPEN
		and not bool(door.call("is_motion_blocked"))
		and bool(door.call("is_navigation_passage_open")),
		"Applying a captured OPEN state restores the door-side consumer seams from semantic truth"
	)
	await _settle_player_physics(tree, 2)

	var original_player_transform: Transform3D = player.global_transform
	player.global_position = Vector3(0, 0, -0.7)
	player.set("velocity", Vector3.ZERO)
	await _settle_player_physics(tree, 2)

	door.call("interact", player)
	await _settle_player_physics(tree, 45)
	var blocked_fraction: float = float(door.call("get_open_fraction"))
	var blocked_state: Dictionary = door.call("capture_semantic_state")
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSING
		and bool(door.call("is_motion_blocked"))
		and blocked_fraction > 0.0
		and blocked_fraction < 1.0
		and bool(blocked_state.get("motion_blocked", false))
		and sound_events.size() == 2
		and door_events == [OrdinaryDoor.PHASE_OPEN],
		"Closing door stops before entering the real player body and publishes no false CLOSED state"
	)
	await _settle_player_physics(tree, 8)
	assert_true.call(
		is_equal_approx(float(door.call("get_open_fraction")), blocked_fraction)
		and bool(door.call("is_motion_blocked")),
		"Obstacle blockage latches instead of resuming automatically while the close command remains active"
	)
	assert_true.call(
		bool(door.call("apply_semantic_state", blocked_state)),
		"Blocked in-progress door state can be applied through the semantic restore seam"
	)
	door.call("reconcile_after_restore")
	assert_true.call(
		bool(door.call("is_motion_blocked"))
		and is_equal_approx(float(door.call("get_open_fraction")), blocked_fraction),
		"Restore reconciliation preserves a latched obstacle stop instead of restarting door motion"
	)

	door.call("interact", player)
	await _settle_player_physics(tree, 3)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPENING
		and not bool(door.call("is_motion_blocked"))
		and float(door.call("get_open_fraction")) > blocked_fraction
		and sound_events.size() == 3,
		"Using a blocked closing door again reverses it into opening without clipping through the obstacle"
	)
	player.global_transform = original_player_transform
	player.set("velocity", Vector3.ZERO)
	await _settle_player_physics(tree, 45)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPEN
		and is_equal_approx(float(door.call("get_open_fraction")), 1.0)
		and not bool(door.call("is_motion_blocked"))
		and door_events == [OrdinaryDoor.PHASE_OPEN, OrdinaryDoor.PHASE_OPEN],
		"Reversed blocked door completes opening and publishes the terminal OPEN state once"
	)

	door.call("interact", player)
	await _settle_player_physics(tree, 3)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSING
		and not bool(door.call("is_motion_blocked"))
		and sound_events.size() == 4,
		"The same ordinary interaction contract reverses an open door into a closing transition"
	)
	await _settle_player_physics(tree, 45)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSED
		and is_zero_approx(float(door.call("get_open_fraction")))
		and not bool(door.call("is_motion_blocked"))
		and not bool(door.call("is_navigation_passage_open"))
		and is_zero_approx(float(door.call("get_acoustic_openness")))
		and door_events == [
			OrdinaryDoor.PHASE_OPEN,
			OrdinaryDoor.PHASE_OPEN,
			OrdinaryDoor.PHASE_CLOSED,
		],
		"Completed closing republishes CLOSED and returns both door-side consumer seams to closed state"
	)
	assert_true.call(
		_first_ray_collider(world, Vector3(0, 1.1, 1.5), Vector3(0, 1.1, -2.2)) == door
		and _door_overlaps_passage_probe(world, door),
		"Closing restores the ordinary door's physical and vision obstruction"
	)

	player.global_position = Vector3(0, 0, -0.7)
	player.set("velocity", Vector3.ZERO)
	await _settle_player_physics(tree, 2)
	var sound_count_before_request_open: int = sound_events.size()
	door.call("request_open", player)
	await _settle_player_physics(tree, 45)
	var blocked_open_fraction: float = float(door.call("get_open_fraction"))
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPENING
		and bool(door.call("is_motion_blocked"))
		and blocked_open_fraction > 0.0
		and blocked_open_fraction < 1.0
		and sound_events.size() == sound_count_before_request_open + 1,
		"Idempotent open request stops safely when the real player blocks the opening sweep"
	)
	player.global_transform = original_player_transform
	player.set("velocity", Vector3.ZERO)
	# Let the physics server observe that the real player has left the sweep
	# before clearing the door's latched opening obstruction.
	await _settle_player_physics(tree, 2)
	door.call("request_open", player)
	await _settle_player_physics(tree, 45)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPEN
		and is_equal_approx(float(door.call("get_open_fraction")), 1.0)
		and not bool(door.call("is_motion_blocked"))
		and sound_events.size() == sound_count_before_request_open + 1,
		"Re-requesting OPEN after the obstruction clears resumes the same opening without toggle reversal or duplicate use sound"
	)

	var legacy_open_snapshot: Dictionary = {
		"phase": OrdinaryDoor.PHASE_OPEN,
		"open_fraction": 1.0,
		"motion_blocked": false,
	}
	assert_true.call(
		bool(door.call("apply_semantic_state", legacy_open_snapshot))
		and not bool((door.call("get_access_summary") as Dictionary).get("locked", true))
		and not bool((door.call("get_access_summary") as Dictionary).get("barred", true)),
		"Additive 6.2 restriction state keeps pre-6.2 three-field door snapshots safely loadable as unrestricted"
	)

	var denied_count_before: int = access_denied_events.size()
	locked_door.call("interact", player)
	await _settle_player_physics(tree, 2)
	assert_true.call(
		locked_door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSED
		and is_zero_approx(float(locked_door.call("get_open_fraction")))
		and access_denied_events.size() == denied_count_before + 1
		and str(access_denied_events[-1].get("door_id", "")) == "door.lab.locked"
		and access_denied_events[-1].get("reason", &"") == &"missing_key"
		and str(access_denied_events[-1].get("required_key_id", "")) == "key.lab",
		"A keyed locked door stays closed and emits one semantic access-denied fact when an ordinary requester lacks the key"
	)

	var key_holder := SemanticPossessionProbe.new()
	key_holder.name = "KeyHolder"
	key_holder.possession_ids["key.lab"] = true
	world.add_child(key_holder)
	var restriction_count_before_key: int = restriction_events.size()
	var keyed_open_accepted: bool = bool(locked_door.call("request_open", key_holder))
	await _settle_player_physics(tree, 2)
	var unlocked_access: Dictionary = locked_door.call("get_access_summary")
	assert_true.call(
		keyed_open_accepted
		and not bool(unlocked_access.get("locked", true))
		and restriction_events.size() == restriction_count_before_key + 1
		and restriction_events[-1].get("reason", &"") == &"key"
		and not bool(restriction_events[-1].get("locked", true)),
		"A requester that owns the authored semantic key unlocks the same door without the door owning or consuming possession"
	)
	await _settle_player_physics(tree, 45)
	assert_true.call(
		locked_door.call("get_semantic_phase") == OrdinaryDoor.PHASE_OPEN
		and not bool(locked_door.call("set_locked", true)),
		"Key-authorized opening reaches OPEN and a door cannot be re-locked while physically open"
	)

	var barred_open_accepted: bool = bool(barred_door.call("request_open", key_holder))
	assert_true.call(
		not barred_open_accepted
		and barred_door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSED
		and bool((barred_door.call("get_access_summary") as Dictionary).get("barred", false)),
		"Barred/external restriction blocks opening even for a requester that owns an unrelated valid key"
	)
	var restriction_count_before_unbar: int = restriction_events.size()
	assert_true.call(
		bool(barred_door.call("set_barred", false, &"test_unbar"))
		and bool(barred_door.call("request_open", key_holder)),
		"External world logic can unbar the same opening and ordinary open behavior resumes without a separate window/door subsystem"
	)
	await _settle_player_physics(tree, 2)
	assert_true.call(
		restriction_events.size() == restriction_count_before_unbar + 1
		and restriction_events[-1].get("reason", &"") == &"test_unbar"
		and not bool(restriction_events[-1].get("barred", true)),
		"Unbarring publishes one detached restriction-change semantic event"
	)

	door.call("request_close", player)
	await _settle_player_physics(tree, 45)
	assert_true.call(
		door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSED
		and bool(door.call("set_locked", true, &"save_probe"))
		and bool(door.call("set_barred", true, &"save_probe")),
		"Primary Door Lab opening can enter a stable closed+locked+barred semantic state for save proof"
	)
	await _settle_player_physics(tree, 2)
	var save_request_id: int = int(application.call("request_quicksave"))
	var saved_snapshot: Dictionary = await _wait_for_quicksave(application, tree)
	assert_true.call(
		save_request_id > 0
		and not saved_snapshot.is_empty(),
		"Door restriction save proof captures through the application-owned stable-boundary quicksave path"
	)

	assert_true.call(
		bool(door.call("set_barred", false, &"post_save_mutation"))
		and bool(door.call("set_locked", false, &"post_save_mutation")),
		"Live door restriction state can diverge after the detached save capture"
	)
	await _settle_player_physics(tree, 2)
	var quickloaded: bool = bool(application.call("quickload_latest"))
	await tree.process_frame
	var restored_world: Node3D = application.get("current_world") as Node3D
	var restored_session: Node = application.get("current_session") as Node
	var restored_door: AnimatableBody3D = (
		restored_world.get_node_or_null("OrdinaryDoor") as AnimatableBody3D
		if restored_world != null
		else null
	)
	var restored_access: Dictionary = (
		restored_door.call("get_access_summary")
		if restored_door != null
		else {}
	)
	assert_true.call(
		quickloaded
		and restored_door != null
		and restored_door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSED
		and is_zero_approx(float(restored_door.call("get_open_fraction")))
		and bool(restored_access.get("locked", false))
		and bool(restored_access.get("barred", false))
		and restored_session != null
		and int(restored_session.call("get_pending_semantic_event_count")) == 0,
		"Quickload reconstructs locked+barred door truth on the replacement persistent opening without replaying restriction events"
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


func _wait_for_quicksave(
	application: Node,
	tree: SceneTree,
	max_frames: int = 120
) -> Dictionary:
	for _frame_index: int in max_frames:
		var snapshot: Dictionary = application.call(
			"get_latest_quicksave_snapshot"
		)
		if not snapshot.is_empty():
			return snapshot
		await tree.physics_frame
		await tree.process_frame
	return {}


func _settle_player_physics(tree: SceneTree, frame_count: int = 1) -> void:
	for _frame_index: int in frame_count:
		await tree.physics_frame
		await tree.process_frame


func _release_interact() -> void:
	Input.action_release("interact")
