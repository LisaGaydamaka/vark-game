extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")
const OrdinaryProp = preload("res://gameplay/props/ordinary_prop.gd")
const OrdinaryDoor = preload("res://gameplay/doors/ordinary_door.gd")
const DefaultPropVisual: Mesh = preload("res://assets/models/props/ordinary_crate.obj")
const AlternatePropVisual: Mesh = preload("res://assets/models/props/ordinary_crate_tall.obj")


func run(tree: SceneTree, assert_true: Callable) -> void:
	_release_actions()
	var release_bound_to_r: bool = false
	for event: InputEvent in InputMap.action_get_events("release_prop"):
		if event is InputEventKey and event.physical_keycode == KEY_R:
			release_bound_to_r = true
	assert_true.call(InputMap.has_action("release_prop") and release_bound_to_r, "Phase 3.5 binds gentle Junk release to R")
	assert_true.call(not InputMap.has_action("throw_prop"), "Ordinary prop throw continues to reuse F rather than a second throw action")
	assert_true.call(
		_obj_faces_point_outward("res://assets/models/props/ordinary_crate.obj")
		and _obj_faces_point_outward("res://assets/models/props/ordinary_crate_tall.obj"),
		"Representative prop OBJ face winding points outward"
	)
	assert_true.call(
		_obj_has_hard_face_normals("res://assets/models/props/ordinary_crate.obj")
		and _obj_has_hard_face_normals("res://assets/models/props/ordinary_crate_tall.obj"),
		"Representative box meshes use explicit per-face hard normals instead of shared smoothed corner shading"
	)

	var application: Node = ApplicationScene.instantiate()
	application.set("development_launch_labels", PackedStringArray(["Prop Lab"]))
	application.set("development_launch_resource_paths", PackedStringArray(["res://scenes/PropLab.tscn"]))
	tree.get_root().add_child(application)
	await tree.process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	await tree.process_frame
	await _settle_physics(tree, 3)
	var world: Node3D = application.get("current_world") as Node3D
	var player: CharacterBody3D = application.get("current_player") as CharacterBody3D
	var session: Node = application.get("current_session") as Node
	assert_true.call(launched and world != null and player != null and session != null and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY, "Prop Lab launches through the production application/session/input path")
	if world == null or player == null or session == null:
		return

	var pickup_prop: RigidBody3D = world.get_node("PickupProp") as RigidBody3D
	var edge_prop: RigidBody3D = world.get_node("EdgeProp") as RigidBody3D
	var stack_lower: RigidBody3D = world.get_node("StackLower") as RigidBody3D
	var stack_upper: RigidBody3D = world.get_node("StackUpper") as RigidBody3D
	var obstruction_door: AnimatableBody3D = world.get_node("ObstructionDoor") as AnimatableBody3D
	var door_blocker: RigidBody3D = world.get_node("DoorBlockerProp") as RigidBody3D
	assert_true.call(
		pickup_prop != null
		and edge_prop != null
		and stack_lower != null
		and stack_upper != null
		and obstruction_door != null
		and door_blocker != null,
		"6.6 Prop Lab uses real ordinary props plus the shared ordinary door for obstruction proof"
	)
	if (
		pickup_prop == null
		or edge_prop == null
		or stack_lower == null
		or stack_upper == null
		or obstruction_door == null
		or door_blocker == null
	):
		return

	var prop_mesh: MeshInstance3D = pickup_prop.get_node("PropMesh") as MeshInstance3D
	var prop_collision: CollisionShape3D = pickup_prop.get_node("CollisionShape3D") as CollisionShape3D
	var original_instance_id: int = pickup_prop.get_instance_id()
	var sound_events: Array[Dictionary] = []
	var sound_handler: Callable = func(event: Dictionary) -> bool:
		sound_events.append(event)
		return true
	assert_true.call(bool(session.call("register_semantic_event_handler", &"gameplay.sound", sound_handler)), "Ordinary prop impacts use the semantic gameplay-sound route")

	pickup_prop.call("set_interaction_highlighted", false)
	var normal_material: StandardMaterial3D = prop_mesh.material_override as StandardMaterial3D
	assert_true.call(
		normal_material != null
		and normal_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL
		and not normal_material.disable_receive_shadows
		and prop_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"Unselected prop presentation uses normal lit shading and ordinary cast/receive shadows"
	)
	assert_true.call(pickup_prop.freeze and pickup_prop.lock_rotation and pickup_prop.continuous_cd, "Settled props remain exactly stable until an explicit physical cause promotes them")
	var prop_physics_material: PhysicsMaterial = pickup_prop.physics_material_override
	assert_true.call(
		pickup_prop.mass <= 0.9
		and prop_physics_material != null
		and prop_physics_material.friction <= 0.6
		and float(pickup_prop.get("player_push_speed_scale")) >= 0.3,
		"Ordinary crates use the lighter, more responsive Phase 3.5 physical tuning"
	)
	assert_true.call(pickup_prop.call("get_visual_model") == DefaultPropVisual and bool(pickup_prop.call("set_visual_model", AlternatePropVisual)) and pickup_prop.get_instance_id() == original_instance_id and prop_collision.shape != null, "Compatible external prop model replacement preserves the gameplay instance and collider")
	var blocker_collision := door_blocker.get_node("CollisionShape3D") as CollisionShape3D
	var blocker_box := blocker_collision.shape as BoxShape3D if blocker_collision != null else null
	assert_true.call(
		str(door_blocker.call("get_visual_model_path"))
			== "res://assets/models/props/ordinary_crate_tall.obj"
		and str(door_blocker.get("prop_variant")) == "tall_crate"
		and door_blocker.call("get_visual_model") == AlternatePropVisual
		and blocker_box != null
		and blocker_box.size.is_equal_approx(Vector3(0.5, 0.7, 0.5)),
		"Imported tall-crate variant changes presentation and authored collision dimensions without changing the shared ordinary-prop gameplay class"
	)

	var edge_start: Transform3D = edge_prop.global_transform
	var lower_start: Transform3D = stack_lower.global_transform
	var upper_start: Transform3D = stack_upper.global_transform
	await _settle_physics(tree, 20)
	assert_true.call(edge_prop.global_transform.is_equal_approx(edge_start) and stack_lower.global_transform.is_equal_approx(lower_start) and stack_upper.global_transform.is_equal_approx(upper_start), "Supported edge placement and a simple stack remain exactly stationary while settled")

	var player_start_transform: Transform3D = player.global_transform
	player.global_position = stack_upper.global_position + Vector3.UP * 0.3
	player.velocity = Vector3.ZERO
	await _settle_physics(tree, 3)
	assert_true.call(
		bool(player.call("is_grounded")),
		"Settled stacked ordinary props provide real walkable support and remain usable as climbing aids"
	)
	player.global_transform = player_start_transform
	player.velocity = Vector3.ZERO
	await _settle_physics(tree, 3)

	assert_true.call(
		bool(obstruction_door.call("request_open", player)),
		"Shared ordinary door opens normally before the prop-obstruction proof"
	)
	await _settle_physics(tree, 45)
	var door_collision := obstruction_door.get_node("CollisionShape3D") as CollisionShape3D
	# The door root is already rotated to its current OPEN fraction. Rebuild the
	# candidate root exactly as the production sweep does, relative to that
	# current fraction, then place the blocker at the mid-sweep leaf center.
	var current_fraction: float = float(obstruction_door.call("get_open_fraction"))
	var target_fraction: float = 0.5
	var delta_angle: float = deg_to_rad(
		float(obstruction_door.get("open_angle_degrees"))
		* (target_fraction - current_fraction)
	)
	var candidate_root: Transform3D = obstruction_door.global_transform.rotated_local(
		Vector3.UP,
		delta_angle
	)
	var blocker_target: Vector3 = (
		candidate_root * door_collision.transform
	).origin
	blocker_target.y = blocker_box.size.y * 0.5
	door_blocker.global_position = blocker_target
	door_blocker.linear_velocity = Vector3.ZERO
	await _settle_physics(tree, 3)
	assert_true.call(
		bool(obstruction_door.call("request_close", player)),
		"Ordinary door begins closing toward a settled ordinary prop"
	)
	await _settle_physics(tree, 45)
	assert_true.call(
		obstruction_door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSING
		and bool(obstruction_door.call("is_motion_blocked"))
		and bool(obstruction_door.call("is_motion_blocked_by", door_blocker))
		and door_blocker.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and door_blocker.freeze,
		"A settled ordinary prop physically obstructs the shared door sweep without a prop-specific door rule or forced prop motion"
	)
	door_blocker.global_position += Vector3(0.0, 0.0, 1.4)
	await _settle_physics(tree, 2)
	obstruction_door.call("request_close", player)
	await _settle_physics(tree, 45)
	assert_true.call(
		obstruction_door.call("get_semantic_phase") == OrdinaryDoor.PHASE_CLOSED
		and not bool(obstruction_door.call("is_motion_blocked")),
		"Removing the prop obstruction lets the same ordinary door finish closing"
	)

	Input.action_press("interact")
	await _settle_physics(tree)
	Input.action_release("interact")
	await _settle_physics(tree, 2)
	var carried_state: Dictionary = pickup_prop.call("capture_semantic_state")
	var carry_state: Dictionary = player.call("get_prop_carry_semantic_state")
	var hud: Control = player.get("junk_hud_container") as Control
	var hud_mesh: MeshInstance3D = player.get("junk_hud_mesh") as MeshInstance3D
	assert_true.call(pickup_prop.call("get_semantic_phase") == OrdinaryProp.PHASE_CARRIED_JUNK and bool(carry_state.get("holding", false)) and player.call("get_held_prop") == pickup_prop, "F pickup transfers the same prop into the single carried_junk semantic slot")
	assert_true.call(pickup_prop.freeze and not prop_mesh.visible and pickup_prop.collision_layer == 0 and pickup_prop.collision_mask == 0 and not bool(pickup_prop.call("is_world_presentation_enabled")), "Carried Junk is frozen and removed from world rendering/collision rather than hovering in front of the camera")
	assert_true.call(hud != null and hud.visible and hud_mesh != null and hud_mesh.mesh == AlternatePropVisual, "Carried Junk is represented at the bottom-center HUD using the same configured prop model")
	var interaction_state: Dictionary = player.call("get_interaction_semantic_state")
	assert_true.call(not bool(interaction_state.get("available", true)) and not bool(player.call("are_hand_actions_available")), "Carried Junk centrally suppresses ordinary world and hand-occupying actions")
	assert_true.call(not _contains_live_object(carried_state), "Carried Junk semantic capture contains no live holder/Node references")

	var player_start_x: float = player.global_position.x
	Input.action_press("move_right")
	await _settle_physics(tree, 6)
	Input.action_release("move_right")
	assert_true.call(absf(player.global_position.x - player_start_x) > 0.01 and bool(player.call("is_carrying_prop")), "Walking remains available while Junk is carried")

	var input_boundary: Node = application.get_node("InputBoundary")
	input_boundary.call("set_gameplay_enabled", false)
	Input.action_press("interact")
	input_boundary.call("set_gameplay_enabled", true)
	await _settle_physics(tree, 2)
	assert_true.call(bool(player.call("is_carrying_prop")), "An F press begun outside gameplay ownership is not replayed as a throw")
	Input.action_release("interact")
	await _settle_physics(tree)
	input_boundary.call("set_gameplay_enabled", false)
	Input.action_press("release_prop")
	input_boundary.call("set_gameplay_enabled", true)
	await _settle_physics(tree, 2)
	assert_true.call(bool(player.call("is_carrying_prop")), "An R press begun outside gameplay ownership is not replayed as a release")
	Input.action_release("release_prop")
	await _settle_physics(tree)

	var head: Node3D = player.get_node("Head") as Node3D
	var camera: Camera3D = player.get_node("Head/Camera3D") as Camera3D
	player.rotation.y = 0.58
	head.rotation.x = -0.55
	await _settle_physics(tree)
	var release_origin: Vector3 = camera.global_position
	var release_forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var released_sound_start: int = sound_events.size()
	Input.action_press("release_prop")
	await _settle_physics(tree)
	Input.action_release("release_prop")
	var released_state: Dictionary = pickup_prop.call("capture_semantic_state")
	var released_velocity: Vector3 = released_state.get("linear_velocity", Vector3.ZERO)
	var release_direction: Vector3 = (pickup_prop.global_position - release_origin).normalized()
	var released_basis: Basis = pickup_prop.global_transform.basis.orthonormalized()
	var released_facing: Vector3 = _horizontal_forward_from_basis(released_basis)
	assert_true.call(not pickup_prop.freeze and released_state.get("motion_kind", &"") == OrdinaryProp.MOTION_RELEASED and released_velocity.length() < 2.0 and release_direction.dot(release_forward) > 0.72, "R gently restores the prop as a live rigid body at a view-derived release point")
	assert_true.call(released_basis.y.dot(Vector3.UP) > 0.999999, "R release enters world physics with the box top already up")
	await _settle_until_phase(tree, pickup_prop, OrdinaryProp.PHASE_SETTLED, 160)
	var released_strength: float = _max_impact_strength(sound_events, released_sound_start)
	var released_settled_basis: Basis = pickup_prop.global_transform.basis.orthonormalized()
	var released_settled_facing: Vector3 = _horizontal_forward_from_basis(released_settled_basis)
	assert_true.call(pickup_prop.freeze and released_settled_basis.y.dot(Vector3.UP) > 0.999999 and released_settled_facing.dot(released_facing) > 0.995 and released_settled_basis.is_equal_approx(released_basis), "Gentle release remains upright through dynamic motion and direct transition to stable rest")
	assert_true.call(absf(pickup_prop.global_position.y - 0.3) <= 0.015 and bool(pickup_prop.call("is_supported")), "A released crate comes to rest on its real support plane without a separate orientation-correction phase")

	assert_true.call(bool(pickup_prop.call("apply_semantic_state", carried_state)) and bool(pickup_prop.call("reconcile_after_restore", player)), "Restore reconciliation rebuilds the carried_junk relationship without serializing a live player reference")
	assert_true.call(hud.visible and not prop_mesh.visible and bool(player.call("is_carrying_prop")), "Restored carried Junk rebuilds HUD presentation and keeps world presentation inactive")

	player.global_position = Vector3(0.9, 0.0, 3.1)
	player.rotation.y = -0.47
	head.rotation.x = 0.0
	await _settle_physics(tree)
	var thrown_sound_start: int = sound_events.size()
	Input.action_press("interact")
	await _settle_physics(tree)
	Input.action_release("interact")
	var thrown_state: Dictionary = pickup_prop.call("capture_semantic_state")
	var thrown_basis: Basis = pickup_prop.global_transform.basis.orthonormalized()
	var thrown_facing: Vector3 = _horizontal_forward_from_basis(thrown_basis)
	var thrown_velocity: Vector3 = thrown_state.get("linear_velocity", Vector3.ZERO)
	assert_true.call(not pickup_prop.freeze and thrown_state.get("motion_kind", &"") == OrdinaryProp.MOTION_THROWN and thrown_velocity.length() > released_velocity.length() + 2.0 and pickup_prop.get_instance_id() == original_instance_id and thrown_basis.y.dot(Vector3.UP) > 0.999999, "F throws the same prop identity upright as an active rigid body with substantially stronger motion than R release")
	var observed_collision: bool = await _wait_for_contact(tree, pickup_prop, 120)
	assert_true.call(observed_collision, "Thrown rigid prop reaches a real physics contact")
	if observed_collision and pickup_prop.call("get_semantic_phase") != OrdinaryProp.PHASE_SETTLED:
		assert_true.call(pickup_prop.global_transform.basis.orthonormalized().is_equal_approx(thrown_basis), "Rigid-body collision changes translation without rotating the thrown box")
	await _settle_until_phase(tree, pickup_prop, OrdinaryProp.PHASE_SETTLED, 220)
	var thrown_strength: float = _max_impact_strength(sound_events, thrown_sound_start)
	var thrown_settled_basis: Basis = pickup_prop.global_transform.basis.orthonormalized()
	var thrown_settled_facing: Vector3 = _horizontal_forward_from_basis(thrown_settled_basis)
	assert_true.call(pickup_prop.freeze and thrown_settled_basis.y.dot(Vector3.UP) > 0.999999 and thrown_settled_facing.dot(thrown_facing) > 0.995 and thrown_settled_basis.is_equal_approx(thrown_basis) and pickup_prop.linear_velocity.is_zero_approx(), "Thrown box remains upright through collision and direct transition to stable rest")
	assert_true.call(thrown_strength > released_strength and released_strength > 0.0, "Gentle release emits lower semantic impact strength than a throw")

	var reset_lower_state := {
		"phase": OrdinaryProp.PHASE_SETTLED,
		"motion_kind": OrdinaryProp.MOTION_NONE,
		"transform": lower_start,
		"linear_velocity": Vector3.ZERO,
	}
	var reset_upper_state := {
		"phase": OrdinaryProp.PHASE_SETTLED,
		"motion_kind": OrdinaryProp.MOTION_NONE,
		"transform": upper_start,
		"linear_velocity": Vector3.ZERO,
	}
	assert_true.call(
		bool(stack_lower.call("apply_semantic_state", reset_lower_state))
		and bool(stack_upper.call("apply_semantic_state", reset_upper_state)),
		"Support-loss stack fixture is restored after unrelated earlier prop impacts"
	)
	await _settle_physics(tree, 2)
	var upper_facing: Vector3 = _horizontal_forward_from_basis(stack_upper.global_transform.basis)
	var upper_xz := Vector2(stack_upper.global_position.x, stack_upper.global_position.z)
	assert_true.call(bool(player.call("try_carry_prop", stack_lower)), "The lower stack support can be removed into the same carried Junk slot")
	await _settle_physics(tree, 3)
	assert_true.call(stack_upper.call("get_motion_kind") == OrdinaryProp.MOTION_UNSUPPORTED and not stack_upper.freeze, "Removing lower support activates the upper prop as a real unsupported rigid body")
	await _settle_until_phase(tree, stack_upper, OrdinaryProp.PHASE_SETTLED, 160)
	var upper_after := Vector2(stack_upper.global_position.x, stack_upper.global_position.z)
	var upper_settled_facing: Vector3 = _horizontal_forward_from_basis(stack_upper.global_transform.basis)
	assert_true.call(upper_settled_facing.dot(upper_facing) > 0.995 and upper_after.distance_to(upper_xz) <= 0.01 and absf(stack_upper.global_position.y - 0.3) <= 0.015, "Unsupported upper stack member falls through rigid-body physics, reaches stable floor support with no hover gap, and preserves yaw")

	_release_actions()
	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _settle_until_phase(tree: SceneTree, prop: Node, target_phase: StringName, max_frames: int) -> void:
	for _frame_index: int in max_frames:
		if prop.call("get_semantic_phase") == target_phase:
			return
		await tree.physics_frame
		await tree.process_frame


func _wait_for_contact(tree: SceneTree, body: RigidBody3D, max_frames: int) -> bool:
	for _frame_index: int in max_frames:
		await tree.physics_frame
		await tree.process_frame
		if not body.get_colliding_bodies().is_empty():
			return true
	return false


func _settle_physics(tree: SceneTree, frame_count: int = 1) -> void:
	for _frame_index: int in frame_count:
		await tree.physics_frame
		await tree.process_frame


func _horizontal_forward_from_basis(source_basis: Basis) -> Vector3:
	var forward: Vector3 = -source_basis.orthonormalized().z
	forward.y = 0.0
	if forward.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return forward.normalized()


func _max_impact_strength(events: Array[Dictionary], start_index: int) -> float:
	var result: float = 0.0
	for index: int in range(start_index, events.size()):
		var payload: Dictionary = events[index].get("payload", {})
		if payload.get("kind", &"") == OrdinaryProp.IMPACT_SOUND_KIND:
			result = maxf(result, float(payload.get("strength", 0.0)))
	return result


func _contains_live_object(value: Variant) -> bool:
	if value is Object:
		return true
	if value is Array:
		for child: Variant in value:
			if _contains_live_object(child):
				return true
	if value is Dictionary:
		for key: Variant in value.keys():
			if _contains_live_object(key) or _contains_live_object(value[key]):
				return true
	return false


func _obj_faces_point_outward(path: String) -> bool:
	var source: String = FileAccess.get_file_as_string(path)
	var vertices: Array[Vector3] = []
	var faces: Array[PackedInt32Array] = []
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("v "):
			var p: PackedStringArray = line.split(" ", false)
			vertices.append(Vector3(float(p[1]), float(p[2]), float(p[3])))
		elif line.begins_with("f "):
			var parts: PackedStringArray = line.split(" ", false)
			var face := PackedInt32Array()
			for i: int in range(1, parts.size()):
				face.append(int(parts[i].split("/")[0]) - 1)
			faces.append(face)
	if vertices.is_empty() or faces.is_empty():
		return false
	var center := Vector3.ZERO
	for vertex: Vector3 in vertices:
		center += vertex
	center /= float(vertices.size())
	for face: PackedInt32Array in faces:
		if face.size() < 3:
			return false
		var a: Vector3 = vertices[face[0]]
		var b: Vector3 = vertices[face[1]]
		var c: Vector3 = vertices[face[2]]
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		var face_center := Vector3.ZERO
		for index: int in face:
			face_center += vertices[index]
		face_center /= float(face.size())
		if normal.dot(face_center - center) <= 0.0:
			return false
	return true


func _obj_has_hard_face_normals(path: String) -> bool:
	var source: String = FileAccess.get_file_as_string(path)
	var normal_count: int = 0
	var face_count: int = 0
	var hard_smoothing: bool = false
	for raw_line: String in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if line == "s off":
			hard_smoothing = true
		elif line.begins_with("vn "):
			normal_count += 1
		elif line.begins_with("f "):
			face_count += 1
			for part: String in line.split(" ", false).slice(1):
				if not "//" in part:
					return false
	return hard_smoothing and normal_count == 6 and face_count == 6


func _release_actions() -> void:
	Input.action_release("interact")
	Input.action_release("release_prop")
	Input.action_release("move_right")
