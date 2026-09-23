extends CharacterBody3D


@onready var head: Node3D = $Head
@onready var view_camera: Camera3D = $Head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var player_mesh: MeshInstance3D = $MeshInstance3D


@export_category("Settings")
@export var locomotion_settings: PlayerLocomotionSettings = PlayerLocomotionSettings.new()
@export var stance_settings: PlayerStanceSettings = PlayerStanceSettings.new()
@export var traversal_settings: PlayerTraversalSettings = PlayerTraversalSettings.new()


@export_category("Look")
@export var mouse_sensitivity: float = 0.007


@export_category("Interaction")
@export var interaction_range: float = 2.5
@export var crude_hostile_range: float = 2.0


var gameplay_input_boundary: Node = null
var player_input: PlayerInput
var player_look: PlayerLook
var support: PlayerSupport
var motor: PlayerMotor
var velocity_state: PlayerVelocityState
var motion_solver: PlayerMotionSolver
var step: PlayerStep
var crouch: PlayerCrouch
var ledge_detector: PlayerLedgeDetectorLazy
var ledge_catch: PlayerLedgeCatch
var ledge_hang: PlayerLedgeHang
var ledge_corner: PlayerLedgeCorner
var ledge_mantle: PlayerMantle
var ledge_controller: PlayerLedgeController
var locomotion_controller: PlayerLocomotionController
var player_interaction: PlayerInteraction
var player_hostile_interaction: PlayerHostileInteraction
var prop_carry: PlayerPropCarry
var semantic_possession: PlayerSemanticPossession
var junk_hud_container: Control
var junk_hud_mesh: MeshInstance3D
var junk_hud_material: StandardMaterial3D

var _requested_world_interaction_available: bool = true


func _ready() -> void:
	_create_components()


func _physics_process(delta: float) -> void:
	var command: PlayerCommand
	if gameplay_input_boundary != null and is_instance_valid(gameplay_input_boundary):
		command = gameplay_input_boundary.call("sample_locomotion_command") as PlayerCommand
	else:
		# Standalone Player.tscn/movement fixtures retain their direct sampler.
		# The production F5 path always binds the application-owned boundary before
		# the WorldSession enters PLAYING.
		command = player_input.sample()

	var interact_pressed: bool = false
	var release_prop_pressed: bool = false
	var attack_pressed: bool = false
	if gameplay_input_boundary != null and is_instance_valid(gameplay_input_boundary):
		interact_pressed = bool(gameplay_input_boundary.call("sample_interaction_pressed"))
		release_prop_pressed = bool(gameplay_input_boundary.call("sample_prop_release_pressed"))
		attack_pressed = bool(gameplay_input_boundary.call("sample_attack_pressed"))
	else:
		interact_pressed = Input.is_action_just_pressed("interact")
		release_prop_pressed = Input.is_action_just_pressed("release_prop")
		attack_pressed = Input.is_action_just_pressed("attack")

	player_input.current_command = command
	velocity_state.apply_to_body(self)

	if ledge_controller.is_active():
		step.cancel()
		ledge_controller.update(
			command.jump_pressed,
			command.crouch_pressed,
			delta
		)
		velocity_state.capture_body_as_controlled(self)
	else:
		locomotion_controller.update(command, delta)
		if ledge_controller.is_active():
			velocity_state.capture_body_as_controlled(self)

	if prop_carry != null and prop_carry.has_held_prop():
		if interact_pressed:
			prop_carry.throw_held()
			_refresh_world_interaction_availability()
		elif release_prop_pressed:
			prop_carry.release_held_gently()
			_refresh_world_interaction_availability()
		if player_interaction != null:
			# F/R belong to carry ownership while Junk is carried; neither may
			# immediately retrigger the object that was just restored to the world.
			player_interaction.update(false)
	elif player_interaction != null:
		player_interaction.update(interact_pressed)

	if (
		player_hostile_interaction != null
		and are_hand_actions_available()
	):
		player_hostile_interaction.update(attack_pressed)


func _unhandled_input(event: InputEvent) -> void:
	# Production input is routed by the application boundary. Standalone scenes
	# keep the old event path so focused player fixtures remain useful.
	if gameplay_input_boundary != null and is_instance_valid(gameplay_input_boundary):
		return
	player_look.handle_input(event)


func bind_gameplay_input_boundary(boundary: Node) -> void:
	gameplay_input_boundary = boundary


func set_interaction_input_enabled(enabled: bool) -> void:
	if player_interaction != null:
		player_interaction.set_input_enabled(enabled)


func set_world_interaction_available(available: bool) -> void:
	_requested_world_interaction_available = available
	_refresh_world_interaction_availability()


func get_interaction_semantic_state() -> Dictionary:
	if player_interaction == null:
		return {
			"available": false,
			"has_target": false,
			"target_name": "",
		}
	return player_interaction.get_semantic_state()


func get_interaction_debug_summary() -> Dictionary:
	if player_interaction == null:
		return {
			"available": false,
			"has_target": false,
			"target_name": "",
			"selection_status": &"unavailable",
		}
	return player_interaction.get_debug_summary()


func has_semantic_possession(possession_id: StringName) -> bool:
	return (
		semantic_possession != null
		and semantic_possession.has(possession_id)
	)


func grant_semantic_possession(possession_id: StringName) -> bool:
	if semantic_possession == null:
		return false
	return semantic_possession.grant(possession_id)


func get_semantic_possession_summary() -> Dictionary:
	if semantic_possession == null:
		return {
			"count": 0,
			"ids": [],
		}
	return semantic_possession.get_debug_summary()


func collect_authored_pickup(pickup: Node) -> bool:
	var session: Node = _find_world_session()
	if (
		session == null
		or not session.has_method("collect_authored_pickup")
	):
		return false
	return bool(session.call("collect_authored_pickup", self, pickup))


func try_carry_prop(prop: Node) -> bool:
	if prop_carry == null:
		return false
	var picked_up: bool = prop_carry.try_pick_up(prop)
	if picked_up:
		_refresh_world_interaction_availability()
	return picked_up


func invalidate_world_collider_dependency(collider_rid: RID) -> void:
	if not collider_rid.is_valid():
		return
	if ledge_controller != null:
		ledge_controller.invalidate_collider(collider_rid)
	if ledge_detector != null:
		ledge_detector.invalidate_collider(collider_rid)
	if support != null:
		support.invalidate_collider(collider_rid, global_position)


func reconcile_carried_junk_prop(prop: Node) -> bool:
	if prop_carry == null:
		return false
	var reconciled: bool = prop_carry.adopt_restored_held_prop(prop)
	if reconciled:
		_refresh_world_interaction_availability()
	return reconciled


func is_carrying_prop() -> bool:
	return prop_carry != null and prop_carry.has_held_prop()


func get_held_prop() -> Node:
	if prop_carry == null:
		return null
	return prop_carry.get_held_prop()


func get_prop_carry_semantic_state() -> Dictionary:
	var held: Node = get_held_prop()
	return {
		"holding": held != null,
		"held_name": str(held.name) if held != null else "",
		"phase": &"carried_junk" if held != null else &"none",
		"hud_visible": junk_hud_container != null and junk_hud_container.visible,
		"hand_actions_available": are_hand_actions_available(),
	}


func are_hand_actions_available() -> bool:
	return prop_carry == null or not prop_carry.has_held_prop()


func handle_look_input(event: InputEvent) -> void:
	player_look.handle_input(event)


func capture_look_mouse() -> void:
	player_look.capture_mouse()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = value
	if player_look != null:
		player_look.mouse_sensitivity = value


func cancel_gameplay_input_gestures() -> void:
	player_input.current_command = PlayerCommand.new()
	if locomotion_controller != null:
		locomotion_controller.air_mantle_intent_active = false


func get_input_view_pose() -> Dictionary:
	return {
		"view_transform": head.global_transform,
		"body_yaw": rotation.y,
		"head_pitch": head.rotation.x,
		"head_yaw": head.rotation.y,
	}


func capture_semantic_state() -> Dictionary:
	var source_stance: StringName = _get_stance_semantic_name()
	var restore_stance: StringName = _get_requested_restore_stance_name()
	var source_traversal: StringName = _get_traversal_semantic_name()
	var restore_policy: StringName = (
		&"direct"
		if source_traversal == &"normal"
		else &"normalize_airborne"
	)
	var saved_velocity: Vector3 = (
		velocity
		if restore_policy == &"direct"
		else Vector3.ZERO
	)
	return {
		"transform": global_transform,
		"velocity": saved_velocity,
		"source_stance": source_stance,
		"restore_stance": restore_stance,
		"source_traversal": source_traversal,
		"restore_policy": restore_policy,
		"semantic_possession": (
			semantic_possession.capture_semantic_state()
			if semantic_possession != null
			else {"ids": []}
		),
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if (
		(snapshot.size() != 6 and snapshot.size() != 7)
		or typeof(snapshot.get("transform", null)) != TYPE_TRANSFORM3D
		or typeof(snapshot.get("velocity", null)) != TYPE_VECTOR3
	):
		return false
	var restored_transform: Transform3D = snapshot["transform"]
	var restored_velocity: Vector3 = snapshot["velocity"]
	var source_stance: StringName = snapshot.get("source_stance", &"")
	var restore_stance: StringName = snapshot.get("restore_stance", &"")
	var source_traversal: StringName = snapshot.get("source_traversal", &"")
	var restore_policy: StringName = snapshot.get("restore_policy", &"")
	if (
		not _is_finite_transform(restored_transform)
		or not _is_finite_vector(restored_velocity)
		or not _is_valid_stance_semantic_name(source_stance, true)
		or not _is_valid_stance_semantic_name(restore_stance, false)
		or not _is_valid_traversal_semantic_name(source_traversal)
		or (
			restore_policy != &"direct"
			and restore_policy != &"normalize_airborne"
		)
		or (
			restore_policy == &"direct"
			and source_traversal != &"normal"
		)
		or (
			restore_policy == &"normalize_airborne"
			and source_traversal == &"normal"
		)
	):
		return false
	if (
		restore_policy == &"normalize_airborne"
		and not restored_velocity.is_zero_approx()
	):
		return false

	if semantic_possession == null:
		return false
	var possession_snapshot: Dictionary = snapshot.get(
		"semantic_possession",
		{"ids": []}
	)
	if not semantic_possession.apply_semantic_state(possession_snapshot):
		return false

	global_transform = restored_transform
	if crouch == null:
		return false
	var restored_stance_value: int = (
		PlayerCrouch.Stance.CROUCHED
		if restore_stance == &"crouched"
		else PlayerCrouch.Stance.STANDING
	)
	if not crouch.restore_stance(restored_stance_value):
		return false

	if ledge_controller == null:
		return false
	if restore_policy == &"normalize_airborne":
		if not ledge_controller.normalize_after_restore_to_airborne():
			return false
		restored_velocity = Vector3.ZERO

	velocity = restored_velocity
	player_input.current_command = PlayerCommand.new()
	if locomotion_controller != null:
		locomotion_controller.air_mantle_intent_active = false
	if step != null:
		step.cancel()
	if velocity_state != null:
		velocity_state.capture_body_as_controlled(self)
	return true


func validate_restored_semantic_state(snapshot: Dictionary) -> bool:
	if snapshot.size() != 6 and snapshot.size() != 7:
		return false
	if (
		typeof(snapshot.get("transform", null)) != TYPE_TRANSFORM3D
		or typeof(snapshot.get("velocity", null)) != TYPE_VECTOR3
	):
		return false
	var expected_transform: Transform3D = snapshot["transform"]
	var expected_velocity: Vector3 = snapshot["velocity"]
	var restore_stance: StringName = snapshot.get("restore_stance", &"")
	var source_traversal: StringName = snapshot.get("source_traversal", &"")
	var restore_policy: StringName = snapshot.get("restore_policy", &"")
	if (
		not global_transform.is_equal_approx(expected_transform)
		or not velocity.is_equal_approx(expected_velocity)
		or not _is_valid_stance_semantic_name(restore_stance, false)
		or not _is_valid_traversal_semantic_name(source_traversal)
	):
		return false
	var expected_possession: Dictionary = snapshot.get(
		"semantic_possession",
		{"ids": []}
	)
	if (
		semantic_possession == null
		or semantic_possession.capture_semantic_state() != expected_possession
	):
		return false
	var current_stance: StringName = _get_stance_semantic_name()
	var current_traversal: StringName = _get_traversal_semantic_name()
	if current_stance != restore_stance or current_traversal != &"normal":
		return false
	if restore_policy == &"direct":
		return source_traversal == &"normal"
	if restore_policy == &"normalize_airborne":
		return (
			source_traversal != &"normal"
			and velocity.is_zero_approx()
			and ledge_controller != null
			and ledge_controller.is_restore_reentry_blocked()
		)
	return false


func reconcile_after_restore() -> bool:
	if velocity_state != null:
		velocity_state.capture_body_as_controlled(self)
	_refresh_world_interaction_availability()
	return true


func apply_input_view_pose(pose: Dictionary) -> bool:
	for key: String in ["body_yaw", "head_pitch", "head_yaw"]:
		var value: Variant = pose.get(key, null)
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return false
		if not is_finite(float(value)):
			return false

	# Phase 4.1 restores input-owned orientation on a fresh player. Traversal
	# state and traversal-specific look reconstruction remain owned by 4.3.
	rotation.y = wrapf(float(pose["body_yaw"]), -PI, PI)
	head.rotation.x = clampf(
		float(pose["head_pitch"]),
		deg_to_rad(-89.0),
		deg_to_rad(89.0)
	)
	head.rotation.y = wrapf(float(pose["head_yaw"]), -PI, PI)
	return true


func is_grounded() -> bool:
	return support != null and support.is_grounded()


## Read-only player-facing movement state used by regression traces.
##
## Tests intentionally consume this semantic boundary rather than reaching into
## the current controller/component graph, so later input/controller refactors
## can preserve behavior without preserving today's ownership structure.
func get_movement_semantic_state() -> Dictionary:
	var support_state: String = "airborne"
	if support != null and support.has_support:
		support_state = "grounded" if support.walkable else "steep"

	var stance_state: String = "uninitialized"
	if crouch != null:
		if crouch.is_fully_crouched():
			stance_state = "crouched"
		elif crouch.is_fully_standing():
			stance_state = "standing"
		else:
			stance_state = "transitioning"

	var traversal_state: String = "normal"
	if ledge_controller != null:
		match ledge_controller.state:
			PlayerLedgeController.State.CATCHING:
				traversal_state = "catching"
			PlayerLedgeController.State.HANGING:
				traversal_state = "hanging"
			PlayerLedgeController.State.CORNERING:
				traversal_state = "cornering"
			PlayerLedgeController.State.MANTLING:
				traversal_state = "mantling"

	var sprinting_state: bool = (
		player_input != null
		and player_input.current_command != null
		and player_input.current_command.sprint_held
		and not player_input.current_command.movement_vector.is_zero_approx()
		and support_state == "grounded"
		and stance_state == "standing"
		and traversal_state == "normal"
	)

	return {
		"position": global_position,
		"velocity": velocity,
		"support": support_state,
		"stance": stance_state,
		"traversal": traversal_state,
		"sprinting": sprinting_state,
	}


func _get_stance_semantic_name() -> StringName:
	if crouch == null:
		return &"uninitialized"
	if crouch.is_fully_crouched():
		return &"crouched"
	if crouch.is_fully_standing():
		return &"standing"
	return &"transitioning"


func _get_requested_restore_stance_name() -> StringName:
	if (
		crouch != null
		and crouch.get_requested_stance() == PlayerCrouch.Stance.CROUCHED
	):
		return &"crouched"
	return &"standing"


func _get_traversal_semantic_name() -> StringName:
	if ledge_controller == null:
		return &"normal"
	match ledge_controller.state:
		PlayerLedgeController.State.CATCHING:
			return &"catching"
		PlayerLedgeController.State.HANGING:
			return &"hanging"
		PlayerLedgeController.State.CORNERING:
			return &"cornering"
		PlayerLedgeController.State.MANTLING:
			return &"mantling"
	return &"normal"


func _is_valid_stance_semantic_name(
	value: StringName,
	allow_transitioning: bool
) -> bool:
	if value == &"standing" or value == &"crouched":
		return true
	return allow_transitioning and value == &"transitioning"


func _is_valid_traversal_semantic_name(value: StringName) -> bool:
	return value in [
		&"normal",
		&"catching",
		&"hanging",
		&"cornering",
		&"mantling",
	]


func _refresh_world_interaction_availability() -> void:
	if player_interaction == null:
		return
	var carry_allows_world_interaction: bool = (
		prop_carry == null or not prop_carry.has_held_prop()
	)
	player_interaction.set_world_interaction_available(
		_requested_world_interaction_available
		and carry_allows_world_interaction
	)



func _find_world_session() -> Node:
	var cursor: Node = self
	while cursor != null:
		if (
			cursor.has_method("collect_authored_pickup")
			and cursor.has_method("get_mission_run_summary")
		):
			return cursor
		cursor = cursor.get_parent()
	return null


func _create_components() -> void:
	player_input = PlayerInput.new()
	velocity_state = PlayerVelocityState.new()
	semantic_possession = PlayerSemanticPossession.new()
	player_look = PlayerLook.new(
		self,
		head,
		mouse_sensitivity
	)
	player_interaction = PlayerInteraction.new(
		self,
		view_camera,
		interaction_range
	)
	player_hostile_interaction = PlayerHostileInteraction.new(
		self,
		view_camera,
		crude_hostile_range
	)
	_create_junk_hud()
	prop_carry = PlayerPropCarry.new(
		self,
		view_camera,
		junk_hud_container,
		junk_hud_mesh,
		junk_hud_material
	)
	support = PlayerSupport.new(
		locomotion_settings.max_walkable_slope,
		locomotion_settings.support_check_distance,
		collision_shape
	)

	motor = PlayerMotor.new(
		locomotion_settings.acceleration,
		locomotion_settings.ground_deceleration,
		locomotion_settings.gravity,
		locomotion_settings.static_friction_coefficient,
		locomotion_settings.kinetic_friction_coefficient,
		locomotion_settings.air_max_speed,
		locomotion_settings.air_acceleration,
		locomotion_settings.air_deceleration
	)

	motion_solver = PlayerMotionSolver.new(
		locomotion_settings.max_collision_iterations
	)

	step = PlayerStep.new(
		locomotion_settings.step_max_height,
		locomotion_settings.step_up_acceleration,
		locomotion_settings.step_up_max_speed,
		collision_shape
	)

	ledge_detector = PlayerLedgeDetectorLazy.new(
		locomotion_settings.jump_height,
		locomotion_settings.gravity,
		head.position.y,
		traversal_settings.ledge_max_wall_tilt_degrees,
		traversal_settings.ledge_max_line_tilt_degrees,
		traversal_settings.ledge_max_approach_angle_degrees,
		collision_shape
	)

	crouch = PlayerCrouch.new(
		collision_shape,
		head,
		player_mesh,
		stance_settings.crouch_height,
		ledge_detector
	)

	ledge_catch = PlayerLedgeCatch.new(
		locomotion_settings.jump_height,
		locomotion_settings.gravity,
		ledge_detector,
		collision_shape
	)

	ledge_hang = PlayerLedgeHang.new(
		locomotion_settings.max_speed,
		locomotion_settings.acceleration,
		ledge_detector
	)

	ledge_corner = PlayerLedgeCorner.new(
		traversal_settings.ledge_corner_turn_speed_degrees,
		ledge_detector
	)

	ledge_mantle = PlayerMantle.new(
		traversal_settings.mantle_speed,
		ledge_detector,
		crouch
	)

	ledge_controller = PlayerLedgeController.new(
		self,
		head,
		player_input,
		support,
		motor,
		motion_solver,
		ledge_detector,
		ledge_catch,
		ledge_hang,
		ledge_corner,
		ledge_mantle,
		player_look,
		locomotion_settings.jump_height,
		locomotion_settings.max_speed,
		traversal_settings.ledge_jump_horizontal_speed,
		traversal_settings.ledge_sprint_jump_horizontal_speed,
		traversal_settings.ledge_max_approach_angle_degrees,
		locomotion_settings.gravity
	)

	locomotion_controller = PlayerLocomotionController.new(
		self,
		head,
		support,
		motor,
		velocity_state,
		motion_solver,
		step,
		crouch,
		ledge_detector,
		ledge_controller,
		locomotion_settings.max_speed,
		locomotion_settings.sprint_speed,
		stance_settings.crouch_speed,
		locomotion_settings.jump_height
	)


func _create_junk_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "JunkHudLayer"
	layer.layer = 20
	add_child(layer)
	var root := Control.new()
	root.name = "JunkHudRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	junk_hud_container = SubViewportContainer.new()
	junk_hud_container.name = "CarriedJunk"
	junk_hud_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(junk_hud_container)
	junk_hud_container.anchor_left = 0.5
	junk_hud_container.anchor_right = 0.5
	junk_hud_container.anchor_top = 1.0
	junk_hud_container.anchor_bottom = 1.0
	junk_hud_container.offset_left = -110.0
	junk_hud_container.offset_right = 110.0
	junk_hud_container.offset_top = -190.0
	junk_hud_container.offset_bottom = -10.0
	junk_hud_container.stretch = true
	junk_hud_container.visible = false
	var viewport := SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = Vector2i(220, 180)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	junk_hud_container.add_child(viewport)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 0.0, 2.2)
	camera.fov = 32.0
	camera.current = true
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	viewport.add_child(light)
	junk_hud_mesh = MeshInstance3D.new()
	junk_hud_mesh.name = "JunkMesh"
	junk_hud_mesh.rotation_degrees = Vector3(-12.0, 28.0, 0.0)
	viewport.add_child(junk_hud_mesh)
	junk_hud_material = StandardMaterial3D.new()
	junk_hud_material.cull_mode = BaseMaterial3D.CULL_BACK
	junk_hud_mesh.material_override = junk_hud_material


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _is_finite_transform(value: Transform3D) -> bool:
	return (
		_is_finite_vector(value.origin)
		and _is_finite_vector(value.basis.x)
		and _is_finite_vector(value.basis.y)
		and _is_finite_vector(value.basis.z)
	)
