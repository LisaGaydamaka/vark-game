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
var _last_vision_target: Vector3 = Vector3.ZERO
var _last_vision_exposure: float = 0.0
var _last_vision_blocked: bool = false
var _last_vision_blocker: String = ""


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
	_last_vision_exposure = exposure
	_last_vision_target = _get_player_vision_target()
	_last_vision_blocked = false
	_last_vision_blocker = ""
	if exposure < vision_exposure_threshold:
		_clear_visual_reaction()
		return false

	var eye: Vector3 = _guard.global_position + Vector3.UP * 1.35
	var target: Vector3 = _last_vision_target
	var to_player: Vector3 = target - eye
	var distance: float = to_player.length()
	if distance <= 0.001 or distance > vision_distance:
		_clear_visual_reaction()
		return false
	var direction: Vector3 = to_player / distance
	var facing: Vector3 = _guard.global_transform.basis.z.normalized()
	if facing.dot(direction) < vision_facing_dot:
		_clear_visual_reaction()
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
		_last_vision_blocked = true
		var blocker: Object = hit.get("collider") as Object
		if blocker != null:
			_last_vision_blocker = str(blocker.get("name"))
		_clear_visual_reaction()
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
		"last_vision_target": _last_vision_target,
		"last_vision_exposure": _last_vision_exposure,
		"last_vision_blocked": _last_vision_blocked,
		"last_vision_blocker": _last_vision_blocker,
		"vision_distance": vision_distance,
		"vision_facing_dot": vision_facing_dot,
		"vision_exposure_threshold": vision_exposure_threshold,
	}


func get_semantic_save_id() -> String:
	if _guard == null or not is_instance_valid(_guard):
		return ""
	return "guard_awareness:%s" % _guard.get_persistent_id()


func capture_semantic_state() -> Dictionary:
	return {
		"guard_persistent_id": (
			_guard.get_persistent_id()
			if _guard != null and is_instance_valid(_guard)
			else ""
		),
		"state": _reaction_state,
		"heard_count": _heard_count,
		"seen_count": _seen_count,
		"speech_reaction_count": _speech_reaction_count,
		"last_heard_kind": _last_heard_kind,
		"last_heard_origin": _last_heard_origin,
		"last_heard_strength": _last_heard_strength,
		"last_vision_target": _last_vision_target,
		"last_vision_exposure": _last_vision_exposure,
		"last_vision_blocked": _last_vision_blocked,
		"last_vision_blocker": _last_vision_blocker,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	var session: Node = _find_world_session()
	if (
		session != null
		and is_instance_valid(session)
		and int(session.get("state")) == WorldSession.State.PLAYING
	):
		return false
	if snapshot.size() != 12:
		return false
	if _guard == null or not is_instance_valid(_guard):
		return false
	if (
		str(snapshot.get("guard_persistent_id", "")).strip_edges()
		!= _guard.get_persistent_id()
	):
		return false
	var restored_state: StringName = snapshot.get("state", &"")
	if (
		restored_state != &"calm"
		and restored_state != &"heard_noise"
		and restored_state != &"saw_player"
		and restored_state != &"inactive"
	):
		return false
	for key: String in ["heard_count", "seen_count", "speech_reaction_count"]:
		if typeof(snapshot.get(key, null)) != TYPE_INT or int(snapshot[key]) < 0:
			return false
	if (
		typeof(snapshot.get("last_heard_kind", null)) != TYPE_STRING_NAME
		or typeof(snapshot.get("last_heard_origin", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("last_vision_target", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("last_vision_blocked", null)) != TYPE_BOOL
		or typeof(snapshot.get("last_vision_blocker", null)) != TYPE_STRING
	):
		return false
	var heard_strength_value: Variant = snapshot.get("last_heard_strength", null)
	var vision_exposure_value: Variant = snapshot.get("last_vision_exposure", null)
	if (
		(typeof(heard_strength_value) != TYPE_FLOAT and typeof(heard_strength_value) != TYPE_INT)
		or (typeof(vision_exposure_value) != TYPE_FLOAT and typeof(vision_exposure_value) != TYPE_INT)
	):
		return false
	var heard_origin: Vector3 = snapshot["last_heard_origin"]
	var vision_target: Vector3 = snapshot["last_vision_target"]
	if (
		not _is_finite_vector(heard_origin)
		or not _is_finite_vector(vision_target)
		or not is_finite(float(heard_strength_value))
		or not is_finite(float(vision_exposure_value))
	):
		return false

	_reaction_state = restored_state
	_heard_count = int(snapshot["heard_count"])
	_seen_count = int(snapshot["seen_count"])
	_speech_reaction_count = int(snapshot["speech_reaction_count"])
	_last_heard_kind = snapshot["last_heard_kind"]
	_last_heard_origin = heard_origin
	_last_heard_strength = float(heard_strength_value)
	_last_vision_target = vision_target
	_last_vision_exposure = float(vision_exposure_value)
	_last_vision_blocked = bool(snapshot["last_vision_blocked"])
	_last_vision_blocker = str(snapshot["last_vision_blocker"])
	return true


func reconcile_after_restore() -> bool:
	_refresh_label()
	return true


func after_restore() -> bool:
	_refresh_label()
	return true


func _get_player_vision_target() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return Vector3.ZERO
	var head := _player.get_node_or_null("Head") as Node3D
	if head != null:
		return head.global_position

	var collision := _player.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	var capsule: CapsuleShape3D = (
		collision.shape as CapsuleShape3D
		if collision != null
		else null
	)
	if collision != null and capsule != null:
		return collision.to_global(
			Vector3(0.0, capsule.height * 0.30, 0.0)
		)
	return _player.global_position + Vector3.UP * 0.75


func _clear_visual_reaction() -> void:
	if _reaction_state != &"saw_player":
		return
	_reaction_state = &"calm"
	_refresh_label()


func _on_gameplay_sound_heard(perception: Dictionary) -> void:
	if _guard == null or _guard.get_life_state() != VarkGuard.LIFE_CONSCIOUS:
		return
	var kind: StringName = perception.get("kind", &"")
	var kind_text: String = str(kind)
	if (
		kind != &"prop.impact"
		and kind != VarkGuard.CRUDE_HOSTILE_IMPACT_SOUND_KIND
		and not kind_text.begins_with("footstep.")
	):
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


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_semantic_gameplay_event"):
			return cursor
		cursor = cursor.get_parent()
	return null


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


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
