extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")
const OrdinaryProp = preload("res://gameplay/props/ordinary_prop.gd")
const DefaultPropVisual: Mesh = preload("res://assets/models/props/ordinary_crate.obj")
const AlternatePropVisual: Mesh = preload("res://assets/models/props/ordinary_crate_tall.obj")


func run(tree: SceneTree, assert_true: Callable) -> void:
	_release_actions()

	var throw_events: Array[InputEvent] = InputMap.action_get_events("throw_prop")
	var has_g_binding: bool = false
	for event: InputEvent in throw_events:
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_G:
			has_g_binding = true
	assert_true.call(
		InputMap.has_action("throw_prop") and has_g_binding,
		"Phase 3.5 exposes G as the dedicated held-prop throw gameplay action"
	)

	var application: Node = ApplicationScene.instantiate()
	var default_labels: PackedStringArray = application.get("development_launch_labels")
	var default_paths: PackedStringArray = application.get("development_launch_resource_paths")
	assert_true.call(
		default_labels.has("Prop Lab")
		and default_paths.has("res://scenes/PropLab.tscn"),
		"Application Development Launch exposes the 3.5 Prop Lab"
	)

	application.set("development_launch_labels", PackedStringArray(["Prop Lab"]))
	application.set(
		"development_launch_resource_paths",
		PackedStringArray(["res://scenes/PropLab.tscn"])
	)
	tree.get_root().add_child(application)
	await tree.process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	await tree.process_frame
	await _settle_physics(tree, 3)

	var world: Node3D = application.get("current_world") as Node3D
	var player: CharacterBody3D = application.get("current_player") as CharacterBody3D
	var session: Node = application.get("current_session") as Node
	assert_true.call(
		launched
		and world != null
		and world.name == &"PropLab"
		and player != null
		and session != null
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY,
		"Prop Lab launches through the production application/session/input path"
	)
	if world == null or player == null or session == null:
		_release_actions()
		application.queue_free()
		await tree.process_frame
		return

	var pickup_prop: CharacterBody3D = world.get_node("PickupProp") as CharacterBody3D
	var edge_prop: CharacterBody3D = world.get_node("EdgeProp") as CharacterBody3D
	var stack_lower: CharacterBody3D = world.get_node("StackLower") as CharacterBody3D
	var stack_upper: CharacterBody3D = world.get_node("StackUpper") as CharacterBody3D
	var prop_mesh: MeshInstance3D = pickup_prop.get_node("PropMesh") as MeshInstance3D
	var prop_collision: CollisionShape3D = (
		pickup_prop.get_node("CollisionShape3D") as CollisionShape3D
	)
	var prop_material: StandardMaterial3D = (
		prop_mesh.material_override as StandardMaterial3D
	)

	var sound_events: Array[Dictionary] = []
	var sound_handler: Callable = func(event: Dictionary) -> bool:
		sound_events.append(event)
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			&"gameplay.sound",
			sound_handler
		)),
		"Ordinary prop impact sounds use the accepted semantic gameplay-sound route"
	)

	var initial_state: Dictionary = pickup_prop.call("capture_semantic_state")
	var initial_velocity: Vector3 = initial_state.get("linear_velocity", Vector3.ONE)
	var interaction_state: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		initial_state.get("phase", &"") == OrdinaryProp.PHASE_SETTLED
		and initial_state.get("motion_kind", &"") == OrdinaryProp.MOTION_NONE
		and initial_velocity.is_zero_approx()
		and bool(pickup_prop.call("is_supported")),
		"Ordinary prop begins as explicit supported SETTLED semantic state"
	)
	assert_true.call(
		bool(pickup_prop.call("is_interaction_highlighted"))
		and bool(interaction_state.get("has_target", false))
		and interaction_state.get("target_name", "") == "PickupProp"
		and prop_material != null
		and prop_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		and prop_material.disable_receive_shadows
		and prop_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"Real ordinary prop consumes the accepted center-view interaction and Thief-style selection presentation"
	)

	var configured_visual: Mesh = pickup_prop.call("get_visual_model") as Mesh
	var collision_shape_before_swap: Shape3D = prop_collision.shape
	var state_before_swap: Dictionary = pickup_prop.call("capture_semantic_state")
	var prop_instance_before_swap: int = pickup_prop.get_instance_id()
	assert_true.call(
		configured_visual == DefaultPropVisual
		and prop_mesh.mesh == DefaultPropVisual
		and configured_visual.resource_path
		== "res://assets/models/props/ordinary_crate.obj",
		"Ordinary prop loads its visible geometry from the configured external model"
	)
	assert_true.call(
		bool(pickup_prop.call("set_visual_model", AlternatePropVisual))
		and pickup_prop.get_instance_id() == prop_instance_before_swap
		and pickup_prop.get_script() == OrdinaryProp
		and pickup_prop.call("get_visual_model") == AlternatePropVisual
		and prop_mesh.mesh == AlternatePropVisual
		and prop_collision.shape == collision_shape_before_swap
		and pickup_prop.call("capture_semantic_state") == state_before_swap
		and pickup_prop.is_in_group(&"vark_interactable")
		and bool(pickup_prop.call("is_interaction_highlighted")),
		"Compatible prop model replacement preserves semantic owner, collider, state, and interaction presentation"
	)

	var edge_start: Transform3D = edge_prop.global_transform
	var lower_start: Transform3D = stack_lower.global_transform
	var upper_start: Transform3D = stack_upper.global_transform
	await _settle_physics(tree, 20)
	assert_true.call(
		edge_prop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and bool(edge_prop.call("is_supported"))
		and edge_prop.global_transform.is_equal_approx(edge_start),
		"An edge-supported ordinary box remains exactly placed instead of toppling or drifting"
	)
	assert_true.call(
		stack_lower.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and stack_upper.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and stack_lower.global_transform.is_equal_approx(lower_start)
		and stack_upper.global_transform.is_equal_approx(upper_start),
		"A simple supported prop stack remains stationary"
	)

	Input.action_press("interact")
	await _settle_physics(tree)
	Input.action_release("interact")
	await _settle_physics(tree, 2)

	var held_state: Dictionary = pickup_prop.call("capture_semantic_state")
	var carry_state: Dictionary = player.call("get_prop_carry_semantic_state")
	var held_interaction_state: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		pickup_prop.call("get_semantic_phase") == OrdinaryProp.PHASE_HELD
		and pickup_prop.call("get_motion_kind") == OrdinaryProp.MOTION_NONE
		and bool(carry_state.get("holding", false))
		and carry_state.get("held_name", "") == "PickupProp"
		and player.call("get_held_prop") == pickup_prop,
		"Fresh F interaction transfers the ordinary prop into player-owned HELD state"
	)
	assert_true.call(
		not bool(held_interaction_state.get("available", true))
		and not bool(held_interaction_state.get("has_target", true))
		and not bool(pickup_prop.call("is_interaction_highlighted")),
		"Carrying centrally suppresses ordinary world interaction and clears selection"
	)
	player.call("set_world_interaction_available", true)
	held_interaction_state = player.call("get_interaction_semantic_state")
	assert_true.call(
		not bool(held_interaction_state.get("available", true)),
		"External interaction availability cannot bypass the held-prop central suppression gate"
	)

	var camera: Camera3D = player.get_node("Head/Camera3D") as Camera3D
	var camera_basis_before: Basis = camera.global_transform.basis.orthonormalized()
	var held_basis_before: Basis = pickup_prop.global_transform.basis.orthonormalized()
	var held_relative_basis_before: Basis = camera_basis_before.inverse() * held_basis_before
	var held_offset_before: Vector3 = (
		camera_basis_before.inverse()
		* (pickup_prop.global_position - camera.global_position)
	)
	assert_true.call(
		is_equal_approx(held_offset_before.x, 0.28)
		and is_equal_approx(held_offset_before.y, -0.18)
		and is_equal_approx(held_offset_before.z, -0.85),
		"Held ordinary prop uses the fixed first-person presentation offset"
	)

	player.rotation.y += 0.45
	await _settle_physics(tree, 2)
	var camera_basis_after: Basis = camera.global_transform.basis.orthonormalized()
	var held_relative_basis_after: Basis = (
		camera_basis_after.inverse()
		* pickup_prop.global_transform.basis.orthonormalized()
	)
	assert_true.call(
		held_relative_basis_after.is_equal_approx(held_relative_basis_before),
		"Held prop orientation follows the view with a fixed relative basis and has no free-rotation state"
	)
	player.rotation.y -= 0.45
	await _settle_physics(tree)

	assert_true.call(
		not _contains_live_object(held_state),
		"Prop semantic capture is detached value data and contains no live Node/Object references"
	)

	Input.action_press("interact")
	await _settle_physics(tree)
	Input.action_release("interact")
	await _settle_physics(tree, 2)
	var dropped_state: Dictionary = pickup_prop.call("capture_semantic_state")
	var dropped_interaction_state: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		dropped_state.get("phase", &"") == OrdinaryProp.PHASE_MOVING
		and dropped_state.get("motion_kind", &"") == OrdinaryProp.MOTION_DROPPED
		and not bool(player.call("is_carrying_prop"))
		and bool(dropped_interaction_state.get("available", false)),
		"F while carrying is owned by carry/drop and restores ordinary world interaction without re-picking"
	)

	await _settle_until_phase(
		tree,
		pickup_prop,
		OrdinaryProp.PHASE_SETTLED,
		90
	)
	assert_true.call(
		pickup_prop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and pickup_prop.call("get_motion_kind") == OrdinaryProp.MOTION_NONE
		and pickup_prop.velocity.is_zero_approx()
		and bool(pickup_prop.call("is_supported")),
		"Dropped ordinary prop falls only until support, settles, then becomes stationary again"
	)

	assert_true.call(
		bool(pickup_prop.call("apply_semantic_state", held_state))
		and pickup_prop.call("get_semantic_phase") == OrdinaryProp.PHASE_HELD
		and not bool(player.call("is_carrying_prop")),
		"Applying HELD prop state restores semantic truth without serializing a live holder reference"
	)
	var held_reconciled: bool = bool(
		pickup_prop.call("reconcile_after_restore", player)
	)
	var restored_interaction_state: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(
		held_reconciled
		and bool(player.call("is_carrying_prop"))
		and player.call("get_held_prop") == pickup_prop
		and not bool(restored_interaction_state.get("available", true)),
		"Restore reconciliation rebuilds the transient player/held-prop relationship and central interaction suppression"
	)

	Input.action_press("interact")
	await _settle_physics(tree)
	Input.action_release("interact")
	await _settle_until_phase(
		tree,
		pickup_prop,
		OrdinaryProp.PHASE_SETTLED,
		90
	)

	assert_true.call(
		bool(player.call("try_carry_prop", pickup_prop)),
		"The same player-owned carry seam can reacquire a settled ordinary prop"
	)
	await _settle_physics(tree)

	var input_boundary: Node = application.get_node("InputBoundary")
	input_boundary.call("set_gameplay_enabled", false)
	Input.action_press("throw_prop")
	input_boundary.call("set_gameplay_enabled", true)
	await _settle_physics(tree, 2)
	assert_true.call(
		bool(player.call("is_carrying_prop")),
		"A throw press that began outside gameplay ownership is not replayed after the domain resumes"
	)
	Input.action_release("throw_prop")
	await _settle_physics(tree)
	Input.action_press("throw_prop")
	await _settle_physics(tree)
	Input.action_release("throw_prop")
	await _settle_physics(tree)

	var moving_state: Dictionary = pickup_prop.call("capture_semantic_state")
	var moving_velocity: Vector3 = moving_state.get("linear_velocity", Vector3.ZERO)
	assert_true.call(
		moving_state.get("phase", &"") == OrdinaryProp.PHASE_MOVING
		and moving_state.get("motion_kind", &"") == OrdinaryProp.MOTION_THROWN
		and moving_velocity.length() > 1.0
		and not bool(player.call("is_carrying_prop")),
		"G while carrying throws the prop through the application-owned gameplay edge"
	)
	assert_true.call(
		not _contains_live_object(moving_state),
		"Moving/thrown prop capture stores explicit transform/velocity progress without runtime references"
	)

	await _settle_until_phase(
		tree,
		pickup_prop,
		OrdinaryProp.PHASE_SETTLED,
		120
	)
	var settled_after_throw: Transform3D = pickup_prop.global_transform
	var settled_basis_after_throw: Basis = settled_after_throw.basis
	await _settle_physics(tree, 15)
	assert_true.call(
		pickup_prop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and pickup_prop.global_transform.is_equal_approx(settled_after_throw)
		and pickup_prop.global_transform.basis.is_equal_approx(settled_basis_after_throw)
		and pickup_prop.velocity.is_zero_approx(),
		"Thrown prop does not keep tumbling, rolling, spinning, or drifting after it settles"
	)

	var impact_payload_found: bool = false
	for event: Dictionary in sound_events:
		var payload: Dictionary = event.get("payload", {})
		if payload.get("kind", &"") == OrdinaryProp.IMPACT_SOUND_KIND:
			impact_payload_found = (
				payload.get("origin", Vector3.ZERO) is Vector3
				and float(payload.get("strength", 0.0)) > 0.0
				and not payload.has("audio_stream")
				and not payload.has("volume_db")
			)
			if impact_payload_found:
				break
	assert_true.call(
		impact_payload_found,
		"Thrown/dropped collision emits semantic prop.impact gameplay sound without presentation-audio data"
	)

	assert_true.call(
		bool(pickup_prop.call("apply_semantic_state", moving_state))
		and bool(pickup_prop.call("reconcile_after_restore"))
		and pickup_prop.call("get_semantic_phase") == OrdinaryProp.PHASE_MOVING
		and pickup_prop.call("get_motion_kind") == OrdinaryProp.MOTION_THROWN,
		"Moving prop semantic state can be applied/reconciled without a timer, coroutine, or rigid-body continuation"
	)
	await _settle_until_phase(
		tree,
		pickup_prop,
		OrdinaryProp.PHASE_SETTLED,
		120
	)
	assert_true.call(
		pickup_prop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and pickup_prop.velocity.is_zero_approx(),
		"Restored in-flight prop resumes the explicit motion state and settles normally"
	)

	var upper_basis_before_fall: Basis = stack_upper.global_transform.basis
	var upper_xz_before_fall := Vector2(
		stack_upper.global_position.x,
		stack_upper.global_position.z
	)
	assert_true.call(
		bool(player.call("try_carry_prop", stack_lower)),
		"Simple lower support can be explicitly removed by the same ordinary prop carry action"
	)
	await _settle_physics(tree, 3)
	assert_true.call(
		stack_upper.call("get_semantic_phase") == OrdinaryProp.PHASE_MOVING
		and stack_upper.call("get_motion_kind") == OrdinaryProp.MOTION_UNSUPPORTED,
		"Removing the lower support transitions the upper prop to explicit UNSUPPORTED motion"
	)

	await _settle_until_phase(
		tree,
		stack_upper,
		OrdinaryProp.PHASE_SETTLED,
		90
	)
	var upper_xz_after_fall := Vector2(
		stack_upper.global_position.x,
		stack_upper.global_position.z
	)
	assert_true.call(
		stack_upper.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and stack_upper.global_transform.basis.is_equal_approx(upper_basis_before_fall)
		and upper_xz_after_fall.is_equal_approx(upper_xz_before_fall)
		and is_equal_approx(stack_upper.global_position.y, 0.3),
		"Unsupported upper stack member falls vertically to support without explosion, scatter, or rotation"
	)

	Input.action_press("interact")
	await _settle_physics(tree)
	Input.action_release("interact")
	await _settle_until_phase(
		tree,
		stack_lower,
		OrdinaryProp.PHASE_SETTLED,
		90
	)

	_release_actions()
	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _settle_until_phase(
	tree: SceneTree,
	prop: Node,
	target_phase: StringName,
	max_frames: int
) -> void:
	for _frame_index: int in max_frames:
		if prop.call("get_semantic_phase") == target_phase:
			return
		await tree.physics_frame
		await tree.process_frame


func _settle_physics(tree: SceneTree, frame_count: int = 1) -> void:
	for _frame_index: int in frame_count:
		await tree.physics_frame
		await tree.process_frame


func _contains_live_object(value: Variant) -> bool:
	if value is Object:
		return true
	if value is Array:
		for child: Variant in value:
			if _contains_live_object(child):
				return true
		return false
	if value is Dictionary:
		for key: Variant in value.keys():
			if _contains_live_object(key) or _contains_live_object(value[key]):
				return true
		return false
	return false


func _release_actions() -> void:
	Input.action_release("interact")
	Input.action_release("throw_prop")
