extends Node


const FreezeTrace = preload("res://player/debug/player_post_mantle_freeze_trace.gd")
const TRACE_PATH: String = "user://post_mantle_freeze_trace.json"


var player: CharacterBody3D = null
var trace: RefCounted = null
var previous_position: Vector3 = Vector3.ZERO
var previous_traversal: String = "normal"
var initialized: bool = false


func _ready() -> void:
	# This node is diagnostic-only. A release export keeps no per-frame tracing
	# overhead, while editor/debug builds automatically watch the real Player path.
	if not OS.is_debug_build():
		set_physics_process(false)
		return
	process_physics_priority = 1000
	player = get_parent() as CharacterBody3D
	trace = FreezeTrace.new()
	if player == null:
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if player == null or trace == null:
		return

	var traversal_after: String = _get_traversal_name()
	if not initialized:
		previous_position = player.global_position
		previous_traversal = traversal_after
		initialized = true
		return

	var player_input: PlayerInput = player.get("player_input") as PlayerInput
	var command: PlayerCommand = null
	if player_input != null:
		command = player_input.current_command
	var command_vector: Vector2 = Vector2.ZERO
	var jump_pressed: bool = false
	var jump_held: bool = false
	var crouch_pressed: bool = false
	var sprint_held: bool = false
	if command != null:
		command_vector = command.movement_vector
		jump_pressed = command.jump_pressed
		jump_held = command.jump_held
		crouch_pressed = command.crouch_pressed
		sprint_held = command.sprint_held

	var raw_input: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var frame_displacement: Vector3 = player.global_position - previous_position
	var horizontal_displacement: float = Vector2(
		frame_displacement.x,
		frame_displacement.z
	).length()

	var support: PlayerSupport = player.get("support") as PlayerSupport
	var support_contact: PlayerSupportContact = null
	if support != null:
		support_contact = support.get_contact()

	var velocity_state: PlayerVelocityState = (
		player.get("velocity_state") as PlayerVelocityState
	)
	var step: PlayerStep = player.get("step") as PlayerStep
	var locomotion_controller: PlayerLocomotionController = (
		player.get("locomotion_controller") as PlayerLocomotionController
	)
	var contact_solver_snapshot: Dictionary = {}
	if (
		locomotion_controller != null
		and locomotion_controller.contact_motion_solver != null
	):
		contact_solver_snapshot = (
			locomotion_controller.contact_motion_solver.get_last_debug_snapshot()
		)

	var physics_frame: int = Engine.get_physics_frames()
	var support_rid: String = ""
	if support_contact != null and support_contact.collider_rid.is_valid():
		support_rid = str(support_contact.collider_rid)
	var support_normal: Vector3 = Vector3.ZERO
	if support != null and support.has_support:
		support_normal = support.support_normal

	var snapshot := {
		"physics_frame": physics_frame,
		"traversal_before": previous_traversal,
		"traversal_after": traversal_after,
		"uses_application_boundary": (
			player.get("gameplay_input_boundary") != null
		),
		"raw_input": _vector2_to_array(raw_input),
		"raw_input_strength": raw_input.length(),
		"command_input": _vector2_to_array(command_vector),
		"command_strength": command_vector.length(),
		"jump_pressed": jump_pressed,
		"jump_held": jump_held,
		"crouch_pressed": crouch_pressed,
		"sprint_held": sprint_held,
		"grounded": support != null and support.is_grounded(),
		"support_valid": support != null and support.has_support,
		"support_walkable": support != null and support.walkable,
		"support_normal": _vector3_to_array(support_normal),
		"support_collider_rid": support_rid,
		"step_active": step != null and step.is_active(),
		"position": _vector3_to_array(player.global_position),
		"frame_displacement": _vector3_to_array(frame_displacement),
		"horizontal_displacement": horizontal_displacement,
		"body_velocity": _vector3_to_array(player.velocity),
		"controlled_velocity": _vector3_to_array(
			velocity_state.controlled_velocity if velocity_state != null else Vector3.ZERO
		),
		"support_velocity": _vector3_to_array(
			velocity_state.support_velocity if velocity_state != null else Vector3.ZERO
		),
		"external_velocity": _vector3_to_array(
			velocity_state.external_velocity if velocity_state != null else Vector3.ZERO
		),
		"contact_solver_current_frame": (
			int(contact_solver_snapshot.get("physics_frame", -1)) == physics_frame
		),
		"contact_solver": contact_solver_snapshot,
	}
	var capture: Dictionary = trace.call("record_frame", snapshot)
	if not capture.is_empty():
		_write_capture(capture)

	previous_position = player.global_position
	previous_traversal = traversal_after


func get_debug_state() -> Dictionary:
	if trace == null:
		return {}
	return trace.call("get_debug_state") as Dictionary


func _get_traversal_name() -> String:
	var controller: PlayerLedgeController = (
		player.get("ledge_controller") as PlayerLedgeController
	)
	if controller == null:
		return "normal"
	match controller.state:
		PlayerLedgeController.State.CATCHING:
			return "catching"
		PlayerLedgeController.State.HANGING:
			return "hanging"
		PlayerLedgeController.State.CORNERING:
			return "cornering"
		PlayerLedgeController.State.MANTLING:
			return "mantling"
	return "normal"


func _write_capture(capture: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning(
			"Post-mantle freeze detected but trace file could not be opened: %s"
			% TRACE_PATH
		)
		return
	file.store_string(JSON.stringify(capture, "\t"))
	file.close()
	var absolute_path: String = ProjectSettings.globalize_path(TRACE_PATH)
	if bool(capture.get("complete", false)):
		print("[POST_MANTLE_FREEZE] finalized trace: ", absolute_path)
	else:
		print("[POST_MANTLE_FREEZE] detected; preliminary trace: ", absolute_path)


func _vector2_to_array(value: Vector2) -> Array:
	return [value.x, value.y]


func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
