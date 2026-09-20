class_name VarkPlayerFootstepEmitter
extends Node


signal gameplay_noise_emitted(summary: Dictionary)


@export var player_path: NodePath = NodePath("../Player")
@export_range(0.2, 4.0, 0.05) var step_distance: float = 1.25
@export_range(0.0, 5.0, 0.05) var minimum_move_speed: float = 0.35
@export_range(0.05, 1.0, 0.05) var crouched_strength_scale: float = 0.45
@export var emission_enabled: bool = true

var _player: CharacterBody3D = null
var _world_session: Node = null
var _last_position: Vector3 = Vector3.ZERO
var _distance_since_step: float = 0.0
var _queued_count: int = 0
var _last_surface_id: StringName = &""
var _last_sound_kind: StringName = &""
var _last_base_strength: float = 0.0
var _last_strength: float = 0.0
var _last_stance: String = "standing"


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_world_session = _find_world_session()
	if _player != null:
		_last_position = _player.global_position


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
		return
	if (
		not _player.has_method("is_grounded")
		or not bool(_player.call("is_grounded"))
	):
		_distance_since_step = 0.0
		return
	var horizontal_speed := Vector3(
		_player.velocity.x,
		0.0,
		_player.velocity.z
	).length()
	if horizontal_speed < minimum_move_speed:
		_distance_since_step = 0.0
		return

	_distance_since_step += horizontal_delta.length()
	while _distance_since_step >= step_distance:
		if not emit_step_now():
			break
		_distance_since_step -= step_distance


func set_emission_enabled(enabled: bool) -> void:
	emission_enabled = enabled
	_distance_since_step = 0.0
	if _player != null and is_instance_valid(_player):
		_last_position = _player.global_position


func emit_step_now() -> bool:
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
	var base_strength: float = profile.footstep_strength
	var kind: StringName = profile.get_footstep_sound_kind()
	if kind.is_empty() or base_strength <= 0.0:
		return false

	var stance: String = _get_player_stance()
	var stance_scale: float = (
		clampf(crouched_strength_scale, 0.05, 1.0)
		if stance == "crouched"
		else 1.0
	)
	var strength: float = base_strength * stance_scale
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
	_last_sound_kind = kind
	_last_base_strength = base_strength
	_last_strength = strength
	_last_stance = stance
	gameplay_noise_emitted.emit(get_debug_summary())
	return true


func get_debug_summary() -> Dictionary:
	return {
		"enabled": emission_enabled,
		"queued_count": _queued_count,
		"last_surface_id": _last_surface_id,
		"last_sound_kind": _last_sound_kind,
		"last_base_strength": _last_base_strength,
		"last_strength": _last_strength,
		"last_stance": _last_stance,
		"crouched_strength_scale": crouched_strength_scale,
		"step_distance": step_distance,
	}


func _get_player_stance() -> String:
	if (
		_player == null
		or not is_instance_valid(_player)
		or not _player.has_method("get_movement_semantic_state")
	):
		return "standing"
	var movement_state: Dictionary = _player.call(
		"get_movement_semantic_state"
	)
	return str(movement_state.get("stance", "standing"))


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
