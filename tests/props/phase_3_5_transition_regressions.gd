extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")
const OrdinaryProp = preload("res://gameplay/props/ordinary_prop.gd")
const OrdinaryPropScene = preload("res://gameplay/props/OrdinaryProp.tscn")


func run(tree: SceneTree, assert_true: Callable) -> void:
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
	assert_true.call(
		launched and world != null and player != null
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY,
		"Phase 3.5 transition regressions launch through the production application/player path"
	)
	if world == null or player == null:
		return
	assert_true.call(
		player.collision_layer == OrdinaryProp.COLLISION_LAYER_PLAYER
		and (player.collision_mask & OrdinaryProp.COLLISION_LAYER_WORLD) != 0
		and (player.collision_mask & OrdinaryProp.COLLISION_LAYER_ORDINARY_PROP) != 0
		and (player.collision_mask & OrdinaryProp.COLLISION_LAYER_PROP_IGNORING_PLAYER) == 0,
		"Player collision channels distinguish ordinary props from the transient overlap-only prop channel"
	)
	var pickup_prop: RigidBody3D = world.get_node("PickupProp") as RigidBody3D
	var edge_prop: RigidBody3D = world.get_node("EdgeProp") as RigidBody3D
	var stack_upper: RigidBody3D = world.get_node("StackUpper") as RigidBody3D
	if pickup_prop == null or edge_prop == null or stack_upper == null:
		assert_true.call(false, "Phase 3.5 transition fixture exposes required props")
		return
	await _prove_release_transaction(tree, world, player, pickup_prop, assert_true)
	await _prove_wakeable_world_physics(tree, world, player, assert_true)
	await _prove_ground_mantle_tracks_moving_prop(tree, world, player, assert_true)
	await _prove_support_invalidation(tree, player, edge_prop, assert_true)
	_prove_traversal_invalidation(player, stack_upper, assert_true)
	await _prove_upright_dynamic_rest(tree, world, assert_true)
	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _prove_release_transaction(
	tree: SceneTree,
	world: Node3D,
	player: CharacterBody3D,
	prop: RigidBody3D,
	assert_true: Callable
) -> void:
	player.global_position = Vector3(0.0, 0.0, 3.1)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	var head: Node3D = player.get_node("Head") as Node3D
	var camera: Camera3D = player.get_node("Head/Camera3D") as Camera3D
	head.rotation.x = 0.0
	await _settle_physics(tree)
	assert_true.call(bool(player.call("try_carry_prop", prop)), "Transition fixture can carry the representative prop")
	var carry: RefCounted = player.get("prop_carry") as RefCounted
	if carry == null:
		assert_true.call(false, "Player exposes the production prop-carry owner")
		return
	var blocker := StaticBody3D.new()
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(2.0, 3.0, 0.2)
	blocker_shape.shape = blocker_box
	blocker.add_child(blocker_shape)
	world.add_child(blocker)
	blocker.global_position = Vector3(0.0, 1.5, 2.15)
	await _settle_physics(tree)
	var full_release_distance: float = float(carry.get("release_distance"))
	var release_origin: Vector3 = camera.global_position
	var released: bool = bool(carry.call("release_held_gently"))
	assert_true.call(
		released
		and prop.global_position.distance_to(release_origin) < full_release_distance - 0.1
		and bool(prop.call("is_release_transform_world_clear", prop.global_transform, player)),
		"R release uses the real prop volume and backs away from a world blocker"
	)
	blocker.queue_free()
	await tree.process_frame
	await _settle_physics(tree, 2)
	assert_true.call(bool(player.call("try_carry_prop", prop)), "Released prop can re-enter carried Junk for overlap setup")
	carry.set("release_distance", 0.18)
	var thrown: bool = bool(carry.call("throw_held"))
	assert_true.call(
		thrown
		and prop.call("get_motion_kind") == OrdinaryProp.MOTION_THROWN
		and not prop.freeze
		and prop.collision_layer == OrdinaryProp.COLLISION_LAYER_PROP_IGNORING_PLAYER
		and (prop.collision_mask & OrdinaryProp.COLLISION_LAYER_WORLD) != 0
		and (prop.collision_mask & OrdinaryProp.COLLISION_LAYER_ORDINARY_PROP) != 0
		and (prop.collision_mask & OrdinaryProp.COLLISION_LAYER_PLAYER) == 0
		and bool(prop.call("is_temporarily_ignoring_player_collision"))
		and player.get_collision_exceptions().is_empty()
		and prop.get_collision_exceptions().is_empty(),
		"F throw activates a live world/prop-colliding body while the overlapping player channel alone is filtered"
	)
	var overlap_throw_start: Vector3 = prop.global_position
	var launched: bool = await _wait_for_solver_launch_motion(tree, prop, overlap_throw_start, 4)
	assert_true.call(
		launched
		and prop.linear_velocity.length() > 4.0
		and prop.global_position.distance_to(overlap_throw_start) > 0.05,
		"Initial player-overlap throw receives its full velocity through the synchronized rigid-body solver handoff"
	)
	var cleared: bool = await _wait_for_player_ignore_clear(tree, prop, player, 40)
	assert_true.call(
		cleared and not bool(prop.call("is_temporarily_ignoring_player_collision"))
		and prop.collision_layer == OrdinaryProp.COLLISION_LAYER_ORDINARY_PROP
		and prop.collision_mask == 15
		and not prop.freeze and prop.linear_velocity.length() > 2.0,
		"Temporary player-only collision filtering ends after geometric separation and restores ordinary prop collision"
	)
	carry.set("release_distance", full_release_distance)
	await _settle_until_phase(tree, prop, OrdinaryProp.PHASE_SETTLED, 240)


func _prove_wakeable_world_physics(
	tree: SceneTree,
	world: Node3D,
	player: CharacterBody3D,
	assert_true: Callable
) -> void:
	var target: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
	var striker: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
	world.add_child(target)
	world.add_child(striker)
	await tree.process_frame
	target.global_position = Vector3(3.0, 0.3, 3.0)
	striker.global_position = Vector3(3.0, 0.3, 4.2)
	await _settle_physics(tree, 3)
	var target_start: Vector3 = target.global_position
	assert_true.call(
		target.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and target.freeze,
		"Settled ordinary props remain exactly stable until an explicit physical cause promotes them"
	)
	assert_true.call(
		bool(striker.call("begin_carried_junk", world))
		and bool(striker.call(
			"release_from_carry",
			OrdinaryProp.MOTION_THROWN,
			striker.global_transform,
			Vector3(0.0, 0.0, -5.0),
			null
		)),
		"Prop-impact fixture launches through the production carry-to-rigid handoff"
	)
	var target_moved: bool = await _wait_for_displacement(tree, target, target_start, 0.08, 90)
	assert_true.call(
		target_moved
		and target.call("get_motion_kind") == OrdinaryProp.MOTION_DISTURBED
		and target.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999,
		"A moving prop transfers solver contact impulse into a settled prop without free tumbling"
	)
	target.queue_free()
	striker.queue_free()
	await tree.process_frame
	await _settle_physics(tree, 2)

	var push_prop: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
	world.add_child(push_prop)
	await tree.process_frame
	push_prop.global_position = Vector3(-3.0, 0.3, 3.0)
	player.global_position = Vector3(-3.0, 0.0, 3.9)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	await _settle_physics(tree, 3)
	var push_start: Vector3 = push_prop.global_position
	Input.action_press("move_forward")
	await _settle_physics(tree, 24)
	Input.action_release("move_forward")
	await _settle_physics(tree, 2)
	assert_true.call(
		push_prop.global_position.distance_to(push_start) > 0.025
		and push_prop.call("get_motion_kind") == OrdinaryProp.MOTION_DISTURBED,
		"Production player locomotion gives a contacted ordinary prop a bounded physical shove"
	)
	push_prop.queue_free()
	await tree.process_frame


func _prove_ground_mantle_tracks_moving_prop(
	tree: SceneTree,
	world: Node3D,
	player: CharacterBody3D,
	assert_true: Callable
) -> void:
	var prop: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
	world.add_child(prop)
	await tree.process_frame
	prop.global_position = Vector3(-3.0, 0.3, -2.0)
	player.global_position = Vector3(-3.0, 0.0, -0.95)
	# Approach off-axis so ordinary forward contact gives the crate lateral
	# velocity through the production contact solver.
	player.rotation.y = deg_to_rad(-15.0)
	player.velocity = Vector3.ZERO
	var head: Node3D = player.get_node("Head") as Node3D
	head.rotation.x = 0.0
	var velocity_state: PlayerVelocityState = player.get("velocity_state") as PlayerVelocityState
	velocity_state.capture_body_as_controlled(player)
	await _settle_physics(tree, 2)

	# Reproduce the player-facing sequence through production ownership: push the
	# lightweight crate with ordinary locomotion, keep holding forward, then
	# request mantle. The prop can translate out of direct contact in that same
	# physics transaction, but the exact collider-backed candidate must remain the
	# same mantle opportunity instead of degrading to a ballistic jump.
	var prop_start: Vector3 = prop.global_position
	var production_shove_observed: bool = false
	Input.action_press("move_forward")
	for _frame_index: int in range(45):
		await _settle_physics(tree)
		if (
			prop.call("get_motion_kind") == OrdinaryProp.MOTION_DISTURBED
			and prop.global_position.distance_to(prop_start) > 0.005
		):
			production_shove_observed = true
			break
	assert_true.call(
		production_shove_observed and bool(player.call("is_grounded")),
		"Ground-mantle fixture reaches the moving-crate state through real grounded player contact"
	)

	Input.action_press("jump")
	await _settle_physics(tree)
	Input.action_release("jump")
	var controller: PlayerLedgeController = player.get("ledge_controller") as PlayerLedgeController
	var entered_mantle: bool = (
		production_shove_observed
		and controller != null
		and controller.state == PlayerLedgeController.State.MANTLING
	)
	assert_true.call(
		entered_mantle and absf(player.velocity.y) <= 0.05,
		"Grounded mantle while pushing a moving prop enters the ordinary PlayerMantle path instead of ballistic jump"
	)
	# Keep forward held through traversal completion; locomotion must resume
	# from the already-held command when traversal ownership ends.
	var moving_start: Vector3 = prop.global_position
	var attachment_local_start: Vector3 = prop.global_transform.affine_inverse() * player.global_position
	var saw_prop_motion_during_mantle: bool = false
	var saw_lateral_prop_motion_during_mantle: bool = false
	var max_attachment_lateral_error: float = 0.0
	var completed_mantle: bool = false
	for _frame_index: int in range(120):
		await _settle_physics(tree)
		if prop.global_position.distance_to(moving_start) > 0.01:
			saw_prop_motion_during_mantle = true
		if absf(prop.global_position.x - moving_start.x) > 0.005:
			saw_lateral_prop_motion_during_mantle = true
		if controller.state == PlayerLedgeController.State.MANTLING:
			var attachment_local_now: Vector3 = prop.global_transform.affine_inverse() * player.global_position
			max_attachment_lateral_error = maxf(max_attachment_lateral_error, absf(attachment_local_now.x - attachment_local_start.x))
		if (
			entered_mantle
			and controller.state == PlayerLedgeController.State.NONE
			and bool(player.call("is_grounded"))
		):
			completed_mantle = true
			break
	assert_true.call(
		completed_mantle,
		"Ground mantle completes through the ordinary PlayerMantle lift/forward path on the moving prop"
	)
	assert_true.call(
		saw_prop_motion_during_mantle
		or prop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED,
		"Prop-backed mantle remains coherent while the shoved source prop moves or comes to rest"
	)
	assert_true.call(
		saw_lateral_prop_motion_during_mantle and max_attachment_lateral_error <= 0.003,
		"Moving-prop mantle keeps the player attachment-relative during lateral crate translation"
	)

	var locomotion_start: Vector3 = player.global_position
	await _settle_physics(tree, 8)
	Input.action_release("move_forward")
	assert_true.call(
		completed_mantle
		and controller.state == PlayerLedgeController.State.NONE
		and player.global_position.distance_to(locomotion_start) > 0.025,
		"Completed moving-prop mantle accepts already-held forward locomotion instead of leaving the player stuck on top"
	)
	prop.queue_free()
	await tree.process_frame
	await _settle_physics(tree, 2)


func _prove_support_invalidation(
	tree: SceneTree,
	player: CharacterBody3D,
	prop: RigidBody3D,
	assert_true: Callable
) -> void:
	player.global_position = Vector3(-1.68, 1.2, 0.0)
	player.velocity = Vector3.ZERO
	await _settle_physics(tree)
	var support: RefCounted = player.get("support") as RefCounted
	support.call("update", player)
	var contact: PlayerSupportContact = support.call("get_contact") as PlayerSupportContact
	assert_true.call(
		contact != null and contact.valid and contact.collider_rid == prop.get_rid()
		and bool(player.call("is_grounded")),
		"Player support records the exact ordinary-prop collider RID"
	)
	var start_y: float = player.global_position.y
	assert_true.call(bool(player.call("try_carry_prop", prop)), "Standing support prop can be picked up")
	assert_true.call(not bool(player.call("is_grounded")), "Picking up the exact support invalidates grounding immediately")
	await _settle_physics(tree, 4)
	assert_true.call(player.global_position.y < start_y - 0.001, "Player falls after supporting prop leaves world participation")
	var carry: RefCounted = player.get("prop_carry") as RefCounted
	if carry != null and bool(carry.call("has_held_prop")):
		carry.call("release_held_gently")
	await _settle_physics(tree, 2)


func _prove_traversal_invalidation(
	player: CharacterBody3D,
	prop: RigidBody3D,
	assert_true: Callable
) -> void:
	var controller: RefCounted = player.get("ledge_controller") as RefCounted
	var hang: RefCounted = player.get("ledge_hang") as RefCounted
	var corner: RefCounted = player.get("ledge_corner") as RefCounted
	var mantle: RefCounted = player.get("ledge_mantle") as RefCounted
	var detector: RefCounted = player.get("ledge_detector") as RefCounted
	if controller == null or hang == null or corner == null or mantle == null or detector == null:
		assert_true.call(false, "Traversal components exist for collider invalidation")
		return
	var candidate := PlayerLedgeDetector.LedgeCandidate.new()
	candidate.wall_collider_rid = prop.get_rid()
	candidate.top_collider_rid = prop.get_rid()
	candidate.wall_normal = Vector3.FORWARD
	candidate.top_normal = Vector3.UP
	candidate.ledge_direction = Vector3.RIGHT
	candidate.hangable = true
	controller.set("active_catch_candidate", candidate)
	controller.set("state", PlayerLedgeController.State.CATCHING)
	assert_true.call(bool(controller.call("invalidate_collider", prop.get_rid())) and int(controller.get("state")) == PlayerLedgeController.State.NONE, "Catch state invalidates with its prop collider")
	hang.call("start", candidate)
	controller.set("state", PlayerLedgeController.State.HANGING)
	assert_true.call(not bool(controller.call("invalidate_collider", RID())) and int(controller.get("state")) == PlayerLedgeController.State.HANGING, "Unrelated collider invalidation leaves hang active")
	assert_true.call(bool(controller.call("invalidate_collider", prop.get_rid())) and int(controller.get("state")) == PlayerLedgeController.State.NONE, "Hang state invalidates with its prop collider")
	var corner_candidate := PlayerLedgeCorner.CornerCandidate.new()
	corner_candidate.source_candidate = candidate
	corner_candidate.target_candidate = candidate
	corner.set("active_corner", corner_candidate)
	controller.set("state", PlayerLedgeController.State.CORNERING)
	assert_true.call(bool(controller.call("invalidate_collider", prop.get_rid())) and int(controller.get("state")) == PlayerLedgeController.State.NONE, "Corner state invalidates with its prop collider")
	var mantle_candidate := PlayerMantle.MantleCandidate.new()
	mantle_candidate.source_candidate = candidate
	mantle_candidate.valid = true
	mantle.set("active_candidate", mantle_candidate)
	mantle.set("phase", PlayerMantle.Phase.LIFT)
	controller.set("state", PlayerLedgeController.State.MANTLING)
	assert_true.call(bool(controller.call("invalidate_collider", prop.get_rid())) and int(controller.get("state")) == PlayerLedgeController.State.NONE, "Mantle state invalidates with its prop collider")

	var settled_snapshot: Dictionary = prop.call("capture_semantic_state")
	assert_true.call(bool(detector.call("is_candidate_attachment_stable", candidate)), "A settled prop is valid traversal attachment geometry")
	var moving_snapshot := {
		"phase": OrdinaryProp.PHASE_MOVING,
		"motion_kind": OrdinaryProp.MOTION_DISTURBED,
		"transform": prop.global_transform,
		"linear_velocity": Vector3.ZERO,
	}
	assert_true.call(
		bool(prop.call("apply_semantic_state", moving_snapshot))
		and not bool(detector.call("is_candidate_attachment_stable", candidate)),
		"Moving ordinary props remain ineligible for stationary catch/hang/corner attachment"
	)
	assert_true.call(
		bool(prop.call("apply_semantic_state", settled_snapshot))
		and bool(detector.call("is_candidate_attachment_stable", candidate)),
		"Stationary traversal attachment eligibility returns after the prop is semantically settled again"
	)


func _prove_upright_dynamic_rest(tree: SceneTree, world: Node3D, assert_true: Callable) -> void:
	var support_body := StaticBody3D.new()
	var support_shape := CollisionShape3D.new()
	var support_box := BoxShape3D.new()
	support_box.size = Vector3(0.12, 0.8, 0.12)
	support_shape.shape = support_box
	support_body.add_child(support_shape)
	world.add_child(support_body)
	support_body.global_position = Vector3(2.89, 0.4, 2.5)
	var prop: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
	world.add_child(prop)
	await tree.process_frame
	var tilted_basis := Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(30.0))
	var moving_state := {
		"phase": OrdinaryProp.PHASE_MOVING,
		"motion_kind": OrdinaryProp.MOTION_UNSUPPORTED,
		"transform": Transform3D(tilted_basis, Vector3(3.0, 1.25, 2.5)),
		"linear_velocity": Vector3.ZERO,
	}
	assert_true.call(
		bool(prop.call("apply_semantic_state", moving_state))
		and prop.call("get_semantic_phase") == OrdinaryProp.PHASE_MOVING
		and prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999999,
		"Moving semantic state is normalized top-up immediately instead of entering a correction phase"
	)

	var saw_unexpected_phase: bool = false
	for _frame_index: int in range(280):
		var phase: StringName = prop.call("get_semantic_phase")
		if phase != OrdinaryProp.PHASE_MOVING and phase != OrdinaryProp.PHASE_SETTLED:
			saw_unexpected_phase = true
			break
		if phase == OrdinaryProp.PHASE_SETTLED:
			break
		await tree.physics_frame
		await tree.process_frame

	assert_true.call(
		not saw_unexpected_phase
		and prop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and prop.freeze
		and prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999999
		and absf(prop.global_position.y - 1.1) <= 0.025
		and bool(prop.call("is_supported")),
		"Upright dynamic prop goes directly from moving to exact stable rest with no settling phase"
	)
	prop.queue_free()
	support_body.queue_free()
	await tree.process_frame


func _wait_for_solver_launch_motion(
	tree: SceneTree,
	prop: RigidBody3D,
	start_position: Vector3,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		await tree.physics_frame
		await tree.process_frame
		if (
			prop.linear_velocity.length() > 4.0
			and prop.global_position.distance_to(start_position) > 0.05
		):
			return true
	return false


func _wait_for_player_ignore_clear(tree: SceneTree, prop: RigidBody3D, player: CharacterBody3D, max_frames: int) -> bool:
	for _frame_index: int in max_frames:
		if (
			not bool(prop.call("is_temporarily_ignoring_player_collision"))
			and prop.collision_layer == OrdinaryProp.COLLISION_LAYER_ORDINARY_PROP
			and prop.collision_mask == 15
			and not prop.freeze
			and not bool(prop.call("_shape_overlaps_body_at_transform", prop.global_transform, player))
		):
			return true
		await tree.physics_frame
		await tree.process_frame
	return false


func _wait_for_displacement(
	tree: SceneTree,
	prop: RigidBody3D,
	start_position: Vector3,
	required_distance: float,
	max_frames: int
) -> bool:
	for _frame_index: int in max_frames:
		await tree.physics_frame
		await tree.process_frame
		if prop.global_position.distance_to(start_position) >= required_distance:
			return true
	return false


func _settle_until_phase(tree: SceneTree, prop: Node, target_phase: StringName, max_frames: int) -> void:
	for _frame_index: int in max_frames:
		if prop.call("get_semantic_phase") == target_phase:
			return
		await tree.physics_frame
		await tree.process_frame


func _settle_physics(tree: SceneTree, frame_count: int = 1) -> void:
	for _frame_index: int in frame_count:
		await tree.physics_frame
		await tree.process_frame
