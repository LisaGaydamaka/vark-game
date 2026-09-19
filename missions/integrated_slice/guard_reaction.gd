extends Node


@export var player_path: NodePath = NodePath("../../Player")
@export var listener_path: NodePath = NodePath("../Hearing")
@export var speech_path: NodePath = NodePath("../Speech")
@export var exposure_path: NodePath = NodePath("../../GameplayExposure")
@export var status_label_path: NodePath = NodePath("../ReactionLabel")
@export var vision_distance: float = 6.0
@export var vision_facing_dot: float = 0.30
@export var vision_exposure_threshold: float = 0.28

var _guard: VarkGuard = null
var _player: CharacterBody3D = null
var _listener: VarkAcousticListener = null
var _speech: VarkWorldSpeechSpeaker = null
var _exposure: VarkGameplayExposure = null
var _status_label: Label3D = null

var _reaction_state: StringName = &"calm"
var _heard_count: int = 0
var _seen_count: int = 0
var _speech_reaction_count: int = 0
var _last_heard_kind: StringName = &""
var _last_heard_origin: Vector3 = Vector3.ZERO
var _last_heard_strength: float = 0.0


func _ready() -> void:
	_guard = get_parent() as VarkGuard
	_player = get_node_or_null(player_path) as CharacterBody3D
	_listener = get_node_or_null(listener_path) as VarkAcousticListener
	_speech = get_node_or_null(speech_path) as VarkWorldSpeechSpeaker
	_exposure = get_node_or_null(exposure_path) as VarkGameplayExposure
	_status_label = get_node_or_null(status_label_path) as Label3D
	if _listener != null:
		_listener.gameplay_sound_heard.connect(_on_gameplay_sound_heard)
	_refresh_label()


func _exit_tree() -> void:
	if (
		_listener != null
		and is_instance_valid(_listener)
		and _listener.gameplay_sound_heard.is_connected(
			_on_gameplay_sound_heard
		)
	):
		_listener.gameplay_sound_heard.disconnect(
			_on_gameplay_sound_heard
		)


func _physics_process(_delta: float) -> void:
	sample_vision_now()


func sample_vision_now() -> bool:
	if (
		_guard == null
		or _player == null
		or _exposure == null
		or not is_instance_valid(_guard)
		or not is_instance_valid(_player)
		or not is_instance_valid(_exposure)
	):
		return false
	if _guard.get_life_state() != VarkGuard.LIFE_CONSCIOUS:
		_reaction_state = &"inactive"
		_refresh_label()
		return false

	var exposure: float = _exposure.get_current_exposure()
	if exposure < vision_exposure_threshold:
		return false

	var eye: Vector3 = _guard.global_position + Vector3.UP * 1.35
	var target: Vector3 = _player.global_position + Vector3.UP * 0.75
	var to_player: Vector3 = target - eye
	var distance: float = to_player.length()
	if distance <= 0.001 or distance > vision_distance:
		return false
	var direction: Vector3 = to_player / distance
	var facing: Vector3 = _guard.global_transform.basis.z.normalized()
	if facing.dot(direction) < vision_facing_dot:
		return false

	var query := PhysicsRayQueryParameters3D.create(eye, target)
	query.collision_mask = 1 | 4
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [_guard.get_rid()]
	var hit: Dictionary = _guard.get_world_3d().direct_space_state.intersect_ray(
		query
	)
	if not hit.is_empty():
		return false

	if _reaction_state != &"saw_player":
		_seen_count += 1
	_reaction_state = &"saw_player"
	_refresh_label()
	return true


func reset_reaction() -> void:
	_reaction_state = &"calm"
	_last_heard_kind = &""
	_last_heard_origin = Vector3.ZERO
	_last_heard_strength = 0.0
	_refresh_label()


func get_debug_summary() -> Dictionary:
	return {
		"state": _reaction_state,
		"heard_count": _heard_count,
		"seen_count": _seen_count,
		"speech_reaction_count": _speech_reaction_count,
		"last_heard_kind": _last_heard_kind,
		"last_heard_origin": _last_heard_origin,
		"last_heard_strength": _last_heard_strength,
		"vision_distance": vision_distance,
		"vision_facing_dot": vision_facing_dot,
		"vision_exposure_threshold": vision_exposure_threshold,
	}


func _on_gameplay_sound_heard(perception: Dictionary) -> void:
	if _guard == null or _guard.get_life_state() != VarkGuard.LIFE_CONSCIOUS:
		return
	var kind: StringName = perception.get("kind", &"")
	var kind_text: String = str(kind)
	if kind != &"prop.impact" and not kind_text.begins_with("footstep."):
		return

	_heard_count += 1
	_last_heard_kind = kind
	_last_heard_origin = perception.get("origin", Vector3.ZERO)
	_last_heard_strength = float(
		perception.get("propagated_strength", 0.0)
	)
	if _reaction_state != &"saw_player":
		_reaction_state = &"heard_noise"

	var flat_origin := Vector3(
		_last_heard_origin.x,
		_guard.global_position.y,
		_last_heard_origin.z
	)
	if flat_origin.distance_squared_to(_guard.global_position) > 0.001:
		_guard.look_at(flat_origin, Vector3.UP, true)

	if _speech_reaction_count == 0 and _speech != null:
		if _speech.speak_line():
			_speech_reaction_count += 1
	_refresh_label()


func _refresh_label() -> void:
	if _status_label == null:
		return
	if _reaction_state == &"heard_noise":
		_status_label.text = "HEARD NOISE\n%s" % str(_last_heard_kind)
		return
	if _reaction_state == &"saw_player":
		var exposure: float = (
			_exposure.get_current_exposure()
			if _exposure != null
			else 0.0
		)
		_status_label.text = "PLAYER SEEN\nexposure %.2f" % exposure
		return
	if _reaction_state == &"inactive":
		_status_label.text = "ACTOR INACTIVE"
		return
	_status_label.text = "CALM"
