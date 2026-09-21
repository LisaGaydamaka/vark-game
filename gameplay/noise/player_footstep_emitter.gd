class_name VarkPlayerFootstepEmitter
extends Node


signal gameplay_noise_emitted(summary: Dictionary)


@export var player_path: NodePath = NodePath("../Player")
@export_range(0.2, 4.0, 0.05) var step_distance: float = 1.25
@export_range(0.0, 5.0, 0.05) var minimum_move_speed: float = 0.35
@export_range(0.05, 1.0, 0.05) var crouched_strength_scale: float = 0.45
@export_range(1.0, 2.0, 0.05) var sprint_strength_scale: float = 1.35
@export var emission_enabled: bool = true

var _player: CharacterBody3D = null
var _world_session: Node = null
var _last_position: Vector3 = Vector3.ZERO
var _distance_since_step: float = 0.0
var _queued_count: int = 0
var _last_surface_id: StringName = &""
var _last_loudness_id: StringName = &""
var _last_sound_kind: StringName = &""
var _last_base_strength: float = 0.0
var _last_strength: float = 0.0
var _last_stance: String = "standing"
var _last_gait: String = "walking"
var _landing_armed: bool = false


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_world_session = _find_world_session()
	if _player != null:
		_last_position = _player.global_position
	_landing_armed = false


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var current: Vector3 = _player.global_position
	var horizontal_delta := Vector3(
		current.x - _last_position.x,
		0.0,
		current.z - _last_position.z
	)
	_last_position = current
	if not emission_enabled:
		_distance_since_step = 0.0
		_landing_armed = false
		return

	var movement_state: Dictionary = _get_player_movement_state()
	var grounded: bool = str(
		movement_state.get("support", "airborne")
	) == "grounded"
	if not grounded:
		# Normal airborne locomotion covers both a jump and an unsupported fall.
		# Traversal-owned hanging/mantling does not arm a delayed landing sound.
		if str(movement_state.get("traversal", "normal")) == "normal":
			_landing_armed = true
		_distance_since_step = 0.0
		return

	if _landing_armed:
		# Landing replaces a same-frame cadence footstep so one contact produces
		# one semantic movement sound.
		_landing_armed = false
		_distance_since_step = 0.0
		emit_landing_now()
		return

	var horizontal_speed := Vector3(
		_player.velocity.x,
		0.0,
		_player.velocity.z
	).length()
	if horizontal_speed < minimum_move_speed:
		# Standing still pauses cadence progress instead of forgiving it. This
		# prevents repeated sub-step movement bursts from resetting footstep
		# distance and becoming indefinitely silent.
		return

	_distance_since_step += horizontal_delta.length()
	while _distance_since_step >= step_distance:
		if not emit_step_now():
			break
		_distance_since_step -= step_distance


func set_emission_enabled(enabled: bool) -> void:
	emission_enabled = enabled
	_distance_since_step = 0.0
	_landing_armed = false
	if _player != null and is_instance_valid(_player):
		_last_position = _player.global_position


func emit_step_now() -> bool:
	var movement_state: Dictionary = _get_player_movement_state()
	var stance: String = str(movement_state.get("stance", "standing"))
	var sprinting: bool = bool(movement_state.get("sprinting", false))
	var gait: String = "walking"
	var movement_scale: float = 1.0
	if stance == "crouched":
		gait = "crouched"
		movement_scale = clampf(crouched_strength_scale, 0.05, 1.0)
	elif sprinting:
		gait = "sprinting"
		movement_scale = maxf(sprint_strength_scale, 1.0)
	return _emit_current_surface_noise(gait, movement_scale, stance)


func emit_landing_now() -> bool:
	var movement_state: Dictionary = _get_player_movement_state()
	var stance: String = str(movement_state.get("stance", "standing"))
	return _emit_current_surface_noise(
		"landing",
		maxf(sprint_strength_scale, 1.0),
		stance
	)


func _emit_current_surface_noise(
	gait: String,
	movement_scale: float,
	stance: String
) -> bool:
	if (
		_player == null
		or not is_instance_valid(_player)
		or _world_session == null
		or not is_instance_valid(_world_session)
	):
		return false
	var surface: VarkFootstepSurface = _find_current_surface()
	if surface == null or not surface.has_valid_surface_profile():
		return false
	var profile: VarkSurfaceProfile = surface.get_surface_profile()
	var base_strength: float = profile.get_footstep_strength()
	var kind: StringName = profile.get_footstep_sound_kind()
	if kind.is_empty() or base_strength <= 0.0:
		return false

	var strength: float = base_strength * maxf(movement_scale, 0.0)
	var queued: bool = bool(_world_session.call(
		"queue_gameplay_sound",
		int(_world_session.get("session_id")),
		kind,
		_player.global_position,
		strength
	))
	if not queued:
		return false
	_queued_count += 1
	_last_surface_id = profile.surface_id
	_last_loudness_id = profile.get_loudness_id()
	_last_sound_kind = kind
	_last_base_strength = base_strength
	_last_strength = strength
	_last_stance = stance
	_last_gait = gait
	gameplay_noise_emitted.emit(get_debug_summary())
	return true


func get_debug_summary() -> Dictionary:
	return {
		"enabled": emission_enabled,
		"queued_count": _queued_count,
		"last_surface_id": _last_surface_id,
		"last_loudness_id": _last_loudness_id,
		"last_sound_kind": _last_sound_kind,
		"last_base_strength": _last_base_strength,
		"last_strength": _last_strength,
		"last_stance": _last_stance,
		"last_gait": _last_gait,
		"landing_armed": _landing_armed,
		"crouched_strength_scale": crouched_strength_scale,
		"sprint_strength_scale": sprint_strength_scale,
		"step_distance": step_distance,
		"distance_since_step": _distance_since_step,
	}


func _get_player_movement_state() -> Dictionary:
	if (
		_player == null
		or not is_instance_valid(_player)
		or not _player.has_method("get_movement_semantic_state")
	):
		return {
			"stance": "standing",
			"sprinting": false,
		}
	return _player.call("get_movement_semantic_state")


func _find_current_surface() -> VarkFootstepSurface:
	var world_root: Node = get_parent()
	for node: Node in get_tree().get_nodes_in_group(
		&"vark_footstep_surface"
	):
		if not (node is VarkFootstepSurface):
			continue
		if world_root != null and not world_root.is_ancestor_of(node):
			continue
		var surface := node as VarkFootstepSurface
		if surface.contains_body(_player):
			return surface
	return null


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_gameplay_sound"):
			return cursor
		cursor = cursor.get_parent()
	return null
