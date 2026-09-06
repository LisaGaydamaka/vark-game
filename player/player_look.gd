class_name PlayerLook
extends RefCounted


const HANG_LOOK_YAW_LIMIT_DEGREES: float = 179.0
const LOOK_DIRECTION_EPSILON_SQUARED: float = 0.000001
const MAX_PITCH_DEGREES: float = 89.0


var body: CharacterBody3D
var head: Node3D
var mouse_sensitivity: float

var ledge_view_active: bool = false
var ledge_view_center_yaw: float = 0.0
var ledge_view_yaw_offset: float = 0.0


func _init(
	player_body: CharacterBody3D,
	player_head: Node3D,
	look_sensitivity: float
) -> void:
	body = player_body
	head = player_head
	mouse_sensitivity = look_sensitivity


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var yaw_motion: float = (
			-event.relative.x
			* mouse_sensitivity
		)

		if ledge_view_active:
			_apply_ledge_yaw_motion(yaw_motion)
		else:
			body.rotate_y(yaw_motion)

		head.rotate_x(
			-event.relative.y
			* mouse_sensitivity
		)
		head.rotation.x = clampf(
			head.rotation.x,
			deg_to_rad(-MAX_PITCH_DEGREES),
			deg_to_rad(MAX_PITCH_DEGREES)
		)
		return

	if event is InputEventKey:
		if (
			event.pressed
			and event.keycode == KEY_ESCAPE
		):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func enter_ledge_view(wall_normal: Vector3) -> void:
	ledge_view_active = true

	var view_forward: Vector3 = (
		-head.global_transform.basis.z
	)
	view_forward.y = 0.0

	if (
		view_forward.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
	):
		view_forward = -body.global_transform.basis.z
		view_forward.y = 0.0

	view_forward = view_forward.normalized()

	var toward_wall: Vector3 = -wall_normal
	toward_wall.y = 0.0

	if (
		toward_wall.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
	):
		ledge_view_center_yaw = body.rotation.y
		ledge_view_yaw_offset = 0.0
		head.rotation.y = 0.0
		return

	toward_wall = toward_wall.normalized()
	ledge_view_center_yaw = atan2(
		-toward_wall.x,
		-toward_wall.z
	)

	var view_yaw: float = atan2(
		-view_forward.x,
		-view_forward.z
	)
	var yaw_limit: float = deg_to_rad(
		HANG_LOOK_YAW_LIMIT_DEGREES
	)
	ledge_view_yaw_offset = clampf(
		wrapf(
			view_yaw - ledge_view_center_yaw,
			-PI,
			PI
		),
		-yaw_limit,
		yaw_limit
	)

	body.rotation.y = wrapf(
		ledge_view_center_yaw
		+ ledge_view_yaw_offset,
		-PI,
		PI
	)
	head.rotation.y = 0.0


func update_ledge_view_center(wall_normal: Vector3) -> void:
	if not ledge_view_active:
		return

	var toward_wall: Vector3 = -wall_normal
	toward_wall.y = 0.0

	if (
		toward_wall.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
	):
		return

	toward_wall = toward_wall.normalized()
	ledge_view_center_yaw = atan2(
		-toward_wall.x,
		-toward_wall.z
	)

	var yaw_limit: float = deg_to_rad(
		HANG_LOOK_YAW_LIMIT_DEGREES
	)
	ledge_view_yaw_offset = clampf(
		ledge_view_yaw_offset,
		-yaw_limit,
		yaw_limit
	)
	body.rotation.y = wrapf(
		ledge_view_center_yaw
		+ ledge_view_yaw_offset,
		-PI,
		PI
	)
	head.rotation.y = 0.0


func exit_ledge_view() -> void:
	ledge_view_active = false
	head.rotation.y = 0.0
	ledge_view_center_yaw = body.rotation.y
	ledge_view_yaw_offset = 0.0


func _apply_ledge_yaw_motion(yaw_motion: float) -> void:
	var yaw_limit: float = deg_to_rad(
		HANG_LOOK_YAW_LIMIT_DEGREES
	)
	ledge_view_yaw_offset = clampf(
		ledge_view_yaw_offset + yaw_motion,
		-yaw_limit,
		yaw_limit
	)
	body.rotation.y = wrapf(
		ledge_view_center_yaw
		+ ledge_view_yaw_offset,
		-PI,
		PI
	)
