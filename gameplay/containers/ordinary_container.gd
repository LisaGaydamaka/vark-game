@tool
class_name VarkOrdinaryContainer
extends Node3D


const PHASE_CLOSED: StringName = &"closed"
const PHASE_OPENING: StringName = &"opening"
const PHASE_OPEN: StringName = &"open"
const PHASE_CLOSING: StringName = &"closing"

const STATE_CHANGED_EVENT_NAME: StringName = &"container.state_changed"
const USE_SOUND_KIND: StringName = &"container.use"

const VARIANT_ASSET_PATHS: Dictionary = {
	"wooden_chest": "res://assets/container_assets/WoodenChest.tscn",
	"desk_drawer": "res://assets/container_assets/DeskDrawer.tscn",
	"tall_cabinet": "res://assets/container_assets/TallCabinet.tscn",
}


@export var persistent_id: String = ""
@export var content_id: String = ""
@export var container_id: StringName = &""
@export var container_variant: String = "ordinary"
@export var asset_scene: PackedScene
@export var transition_seconds: float = 0.45
@export var gameplay_sound_strength: float = 0.45
@export var starts_open: bool = false

@onready var asset_root: Node3D = $AssetRoot

var _phase: StringName = PHASE_CLOSED
var _open_fraction: float = 0.0
var _highlighted: bool = false
var _world_session: Node = null
var _asset: VarkContainerAsset = null
var _mechanism: AnimatableBody3D = null
var _closed_mechanism_transform: Transform3D = Transform3D.IDENTITY
var _open_mechanism_transform: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_world_session = _find_world_session()
	_apply_authored_variant_defaults()
	if asset_scene == null:
		push_error("VarkOrdinaryContainer requires an authored container asset_scene.")
		return
	var instance: Node = asset_scene.instantiate()
	asset_root.add_child(instance)
	_asset = instance as VarkContainerAsset
	if _asset == null or not _asset.validate_contract():
		push_error(
			"VarkOrdinaryContainer asset_scene must instantiate a valid VarkContainerAsset."
		)
		return

	_mechanism = _asset.get_mechanism()
	_closed_mechanism_transform = _asset.get_closed_mechanism_transform()
	_open_mechanism_transform = _asset.get_open_mechanism_transform()
	_phase = PHASE_OPEN if starts_open else PHASE_CLOSED
	_open_fraction = 1.0 if starts_open else 0.0
	_sync_mechanism()
	_refresh_visual()


func _physics_process(delta: float) -> void:
	if _phase != PHASE_OPENING and _phase != PHASE_CLOSING:
		return
	var duration: float = maxf(transition_seconds, 0.001)
	var direction: float = 1.0 if _phase == PHASE_OPENING else -1.0
	_open_fraction = clampf(
		_open_fraction + direction * delta / duration,
		0.0,
		1.0
	)
	_sync_mechanism()
	if _phase == PHASE_OPENING and is_equal_approx(_open_fraction, 1.0):
		_open_fraction = 1.0
		_phase = PHASE_OPEN
		_queue_state_changed()
	elif _phase == PHASE_CLOSING and is_zero_approx(_open_fraction):
		_open_fraction = 0.0
		_phase = PHASE_CLOSED
		_queue_state_changed()


func is_vark_persistent_entity() -> bool:
	return not persistent_id.strip_edges().is_empty()


func get_persistent_id() -> String:
	return persistent_id


func get_content_id() -> String:
	return content_id


func can_interact(_interactor: Node) -> bool:
	return _asset != null and _mechanism != null


func interact(interactor: Node) -> void:
	if _phase == PHASE_CLOSED or _phase == PHASE_CLOSING:
		request_open(interactor)
	else:
		request_close(interactor)


func request_open(_requester: Node = null) -> bool:
	if not can_interact(_requester):
		return false
	if _phase == PHASE_OPEN or _phase == PHASE_OPENING:
		return true
	_phase = PHASE_OPENING
	_queue_use_sound()
	return true


func request_close(_requester: Node = null) -> bool:
	if not can_interact(_requester):
		return false
	if _phase == PHASE_CLOSED or _phase == PHASE_CLOSING:
		return true
	_phase = PHASE_CLOSING
	_queue_use_sound()
	return true


func get_semantic_phase() -> StringName:
	return _phase


func get_open_fraction() -> float:
	return _open_fraction


func get_mechanism() -> AnimatableBody3D:
	return _mechanism


func get_contents_anchor() -> Node3D:
	return _asset.get_contents_anchor() if _asset != null else null


func get_asset_summary() -> Dictionary:
	return (
		_asset.get_contract_summary().duplicate(true)
		if _asset != null
		else {}
	)


func is_interaction_highlighted() -> bool:
	return _highlighted


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted and can_interact(null)
	_refresh_visual()


func get_debug_summary() -> Dictionary:
	var asset_summary: Dictionary = get_asset_summary()
	return {
		"container_id": container_id,
		"variant": container_variant,
		"asset_id": asset_summary.get("asset_id", &""),
		"phase": _phase,
		"open_fraction": _open_fraction,
	}


func capture_semantic_state() -> Dictionary:
	return {
		"phase": _phase,
		"open_fraction": _open_fraction,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if (
		snapshot.size() != 2
		or typeof(snapshot.get("phase", null)) != TYPE_STRING_NAME
		or (
			typeof(snapshot.get("open_fraction", null)) != TYPE_FLOAT
			and typeof(snapshot.get("open_fraction", null)) != TYPE_INT
		)
	):
		return false
	var phase: StringName = snapshot.get("phase", &"")
	var fraction: float = float(snapshot.get("open_fraction", -1.0))
	if (
		phase != PHASE_CLOSED
		and phase != PHASE_OPENING
		and phase != PHASE_OPEN
		and phase != PHASE_CLOSING
	):
		return false
	if not is_finite(fraction) or fraction < 0.0 or fraction > 1.0:
		return false
	if phase == PHASE_CLOSED and not is_zero_approx(fraction):
		return false
	if phase == PHASE_OPEN and not is_equal_approx(fraction, 1.0):
		return false
	_phase = phase
	_open_fraction = fraction
	_sync_mechanism()
	return true


func reconcile_after_restore() -> bool:
	_world_session = _find_world_session()
	_sync_mechanism()
	_refresh_visual()
	return true


func _apply_authored_variant_defaults() -> void:
	if asset_scene != null:
		return
	var asset_path: String = str(
		VARIANT_ASSET_PATHS.get(container_variant.strip_edges(), "")
	)
	if asset_path.is_empty() or not ResourceLoader.exists(asset_path):
		return
	var loaded: Resource = ResourceLoader.load(asset_path)
	if loaded is PackedScene:
		asset_scene = loaded as PackedScene


func _sync_mechanism() -> void:
	if _mechanism == null:
		return
	var fraction: float = clampf(_open_fraction, 0.0, 1.0)
	var closed_quaternion := Quaternion(_closed_mechanism_transform.basis)
	var open_quaternion := Quaternion(_open_mechanism_transform.basis)
	var interpolated_quaternion := closed_quaternion.slerp(
		open_quaternion,
		fraction
	)
	_mechanism.transform = Transform3D(
		Basis(interpolated_quaternion),
		_closed_mechanism_transform.origin.lerp(
			_open_mechanism_transform.origin,
			fraction
		)
	)


func _refresh_visual() -> void:
	if _asset != null:
		_asset.set_mechanism_highlighted(_highlighted)


func _queue_use_sound() -> void:
	if _world_session == null:
		return
	_world_session.call(
		"queue_gameplay_sound",
		int(_world_session.get("session_id")),
		USE_SOUND_KIND,
		global_position,
		maxf(gameplay_sound_strength, 0.0)
	)


func _queue_state_changed() -> void:
	if _world_session == null:
		return
	_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		STATE_CHANGED_EVENT_NAME,
		{
			"container_id": container_id,
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
