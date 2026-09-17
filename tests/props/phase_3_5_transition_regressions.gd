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
	var pickup_prop: RigidBody3D = world.get_node("PickupProp") as RigidBody3D
	var edge_prop: RigidBody3D = world.get_node("EdgeProp") as RigidBody3D
	var stack_upper: RigidBody3D = world.get_node("StackUpper") as RigidBody3D
	if pickup_prop == null or edge_prop == null or stack_upper == null:
		assert_true.call(false, "Phase 3.5 transition fixture exposes required props")
		return
	await _prove_release_transaction(tree, world, player, pickup_prop, assert_true)
	await _prove_support_invalidation(tree, player, edge_prop, assert_true)
	_prove_traversal_invalidation(player, stack_upper, assert_true)
	await _prove_contact_manifold_settle(tree, world, assert_true)
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
		and prop.linear_velocity.length() > 4.0
		and bool(prop.call("has_temporary_player_collision_exception"))
		and player in prop.get_collision_exceptions()
		and prop in player.get_collision_exceptions(),
		"F throw keeps its impulse through an initial player overlap"
	)
	var overlap_throw_start: Vector3 = prop.global_position
	await _settle_physics(tree)
	assert_true.call(
		prop.global_position.distance_to(overlap_throw_start) > 0.05,
		"Initial player overlap escapes along the throw vector instead of canceling the throw"
	)
	var cleared: bool = await _wait_for_player_exception_clear(tree, prop, player, 40)
	assert_true.call(
		cleared and not bool(prop.call("has_temporary_player_collision_exception"))
		and not (player in prop.get_collision_exceptions())
		and not (prop in player.get_collision_exceptions())
		and prop.collision_layer == 1 and prop.collision_mask == 1
		and not prop.freeze and prop.linear_velocity.length() > 2.0,
		"Temporary prop-player collision exclusion ends after geometric separation"
	)
	carry.set("release_distance", full_release_distance)
	await _settle_until_phase(tree, prop, OrdinaryProp.PHASE_SETTLED, 240)


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
	if controller == null or hang == null or corner == null or mantle == null:
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


func _prove_contact_manifold_settle(tree: SceneTree, world: Node3D, assert_true: Callable) -> void:
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
		"settle_yaw": 0.0,
	}
	assert_true.call(bool(prop.call("apply_semantic_state", moving_state)), "Narrow-support fixture enters moving rigid-body state")
	await _settle_until_phase(tree, prop, OrdinaryProp.PHASE_SETTLED, 220)
	assert_true.call(
		prop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
		and prop.freeze
		and prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999
		and absf(prop.global_position.y - 1.1) <= 0.025
		and bool(prop.call("is_supported")),
		"Tilted box settles from real contact state on a narrow support the retired corner-ray authority misses"
	)
	prop.queue_free()
	support_body.queue_free()
	await tree.process_frame


func _wait_for_player_exception_clear(tree: SceneTree, prop: RigidBody3D, player: CharacterBody3D, max_frames: int) -> bool:
	for _frame_index: int in max_frames:
		if (
			not bool(prop.call("has_temporary_player_collision_exception"))
			and not (player in prop.get_collision_exceptions())
			and not (prop in player.get_collision_exceptions())
			and prop.collision_layer == 1
			and prop.collision_mask == 1
			and not prop.freeze
		):
			return true
		await tree.physics_frame
		await tree.process_frame
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
