class_name VarkOrdinaryDoor
extends AnimatableBody3D


const PHASE_CLOSED: StringName = &"closed"
const PHASE_OPENING: StringName = &"opening"
const PHASE_OPEN: StringName = &"open"
const PHASE_CLOSING: StringName = &"closing"
const STATE_CHANGED_EVENT_NAME: StringName = &"door.state_changed"
const USE_SOUND_KIND: StringName = &"door.use"


@export var door_id: StringName = &"door"
@export var transition_seconds: float = 0.55
@export var open_angle_degrees: float = 90.0
@export var gameplay_sound_strength: float = 0.65
@export var base_color: Color = Color(0.34, 0.20, 0.10, 1.0)
@export var visual_model: Mesh

@onready var door_mesh: MeshInstance3D = $DoorMesh

var _phase: StringName = PHASE_CLOSED
var _open_fraction: float = 0.0
var _closed_rotation_y: float = 0.0
var _highlighted: bool = false
var _material: StandardMaterial3D = null
var _world_session: Node = null


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_closed_rotation_y = rotation.y
	_world_session = _find_world_session()
	_material = StandardMaterial3D.new()
	door_mesh.material_override = _material
	if not set_visual_model(visual_model):
		push_error("VarkOrdinaryDoor requires a configured visual_model Mesh.")
	_sync_derived_state()


func _physics_process(delta: float) -> void:
	if _phase != PHASE_OPENING and _phase != PHASE_CLOSING:
		return

	var duration: float = maxf(transition_seconds, 0.001)
	var step: float = delta / duration
	if _phase == PHASE_OPENING:
		_open_fraction = minf(1.0, _open_fraction + step)
		if is_equal_approx(_open_fraction, 1.0):
			_open_fraction = 1.0
			_phase = PHASE_OPEN
			_sync_derived_state()
			_queue_state_changed()
			return
	else:
		_open_fraction = maxf(0.0, _open_fraction - step)
		if is_zero_approx(_open_fraction):
			_open_fraction = 0.0
			_phase = PHASE_CLOSED
			_sync_derived_state()
			_queue_state_changed()
			return

	_sync_derived_state()


func can_interact(_interactor: Node) -> bool:
	return true


func interact(_interactor: Node) -> void:
	if _phase == PHASE_CLOSED or _phase == PHASE_CLOSING:
		_phase = PHASE_OPENING
	else:
		_phase = PHASE_CLOSING
	_queue_use_sound()


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_refresh_visual()


func is_interaction_highlighted() -> bool:
	return _highlighted


func set_visual_model(model: Mesh) -> bool:
	if model == null:
		return false
	visual_model = model
	if door_mesh != null:
		door_mesh.mesh = model
	return true


func get_visual_model() -> Mesh:
	return visual_model


func get_semantic_phase() -> StringName:
	return _phase


func get_open_fraction() -> float:
	return _open_fraction


func get_acoustic_openness() -> float:
	# This is a door-side source-state seam only. Phase 3.6 still owns how
	# openness affects propagated audibility through actual architecture.
	return _open_fraction


func is_navigation_passage_open() -> bool:
	# The first guard/nav proof can consume this same seam without the door
	# knowing anything about a particular NPC or navigation implementation.
	return _phase == PHASE_OPEN


func capture_semantic_state() -> Dictionary:
	return {
		"phase": _phase,
		"open_fraction": _open_fraction,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if snapshot.size() != 2:
		return false
	if not snapshot.has("phase") or not snapshot.has("open_fraction"):
		return false
	if typeof(snapshot["phase"]) != TYPE_STRING_NAME:
		return false
	var phase: StringName = snapshot["phase"]
	if not _is_valid_phase(phase):
		return false
	var fraction_value: Variant = snapshot["open_fraction"]
	if typeof(fraction_value) != TYPE_FLOAT and typeof(fraction_value) != TYPE_INT:
		return false
	var fraction: float = float(fraction_value)
	if not is_finite(fraction) or fraction < 0.0 or fraction > 1.0:
		return false
	if phase == PHASE_CLOSED and not is_zero_approx(fraction):
		return false
	if phase == PHASE_OPEN and not is_equal_approx(fraction, 1.0):
		return false

	_phase = phase
	_open_fraction = fraction
	_sync_derived_state()
	return true


func reconcile_after_restore() -> void:
	# Transform, interaction presentation, and the consumer seams are derived
	# from semantic phase/progress rather than serialized engine machinery.
	_sync_derived_state()


func _sync_derived_state() -> void:
	rotation.y = (
		_closed_rotation_y
		+ deg_to_rad(open_angle_degrees) * _open_fraction
	)
	_refresh_visual()


func _refresh_visual() -> void:
	if _material == null:
		return
	_material.albedo_color = base_color
	_material.emission_enabled = false
	_material.disable_receive_shadows = _highlighted
	_material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
		if _highlighted
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)


func _queue_use_sound() -> void:
	if _world_session == null:
		return
	var source_session_id: int = int(_world_session.get("session_id"))
	_world_session.call(
		"queue_gameplay_sound",
		source_session_id,
		USE_SOUND_KIND,
		door_mesh.global_position,
		gameplay_sound_strength
	)


func _queue_state_changed() -> void:
	if _world_session == null:
		return
	var source_session_id: int = int(_world_session.get("session_id"))
	_world_session.call(
		"queue_semantic_gameplay_event",
		source_session_id,
		STATE_CHANGED_EVENT_NAME,
		{
			"door_id": door_id,
			"state": _phase,
		}
	)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if (
			cursor.has_method("queue_gameplay_sound")
			and cursor.has_method("queue_semantic_gameplay_event")
		):
			return cursor
		cursor = cursor.get_parent()
	return null


func _is_valid_phase(phase: StringName) -> bool:
	return (
		phase == PHASE_CLOSED
		or phase == PHASE_OPENING
		or phase == PHASE_OPEN
		or phase == PHASE_CLOSING
	)
