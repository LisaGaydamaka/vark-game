@tool
class_name VarkOrdinaryContainer
extends Node3D


const PHASE_CLOSED: StringName = &"closed"
const PHASE_OPENING: StringName = &"opening"
const PHASE_OPEN: StringName = &"open"
const PHASE_CLOSING: StringName = &"closing"

const OPENING_FRONT: StringName = &"front"
const OPENING_TOP: StringName = &"top"
const MODE_SLIDE: StringName = &"slide"
const MODE_HINGE: StringName = &"hinge"

const STATE_CHANGED_EVENT_NAME: StringName = &"container.state_changed"
const USE_SOUND_KIND: StringName = &"container.use"


@export var persistent_id: String = ""
@export var content_id: String = ""
@export var container_id: StringName = &""
@export var container_variant: String = "drawer"

@export var opening_face: StringName = OPENING_FRONT
@export var mechanism_mode: StringName = MODE_SLIDE
@export var outer_size: Vector3 = Vector3(1.6, 1.2, 0.9)
@export var wall_thickness: float = 0.10
@export var mechanism_thickness: float = 0.08
@export var transition_seconds: float = 0.45
@export var open_position_offset: Vector3 = Vector3(0.0, 0.0, 0.85)
@export var open_rotation_degrees: Vector3 = Vector3.ZERO
@export var contents_closed_position: Vector3 = Vector3(0.0, 0.15, 0.10)
@export var contents_follow_mechanism: bool = true
@export var starts_open: bool = false

@export var frame_visual_model: Mesh
@export var frame_visual_model_path: String = ""
@export var mechanism_visual_model: Mesh
@export var mechanism_visual_model_path: String = ""
@export var base_color: Color = Color(0.30, 0.22, 0.15, 1.0)
@export var mechanism_color: Color = Color(0.42, 0.29, 0.17, 1.0)
@export var gameplay_sound_strength: float = 0.45

@onready var frame_a: StaticBody3D = $FrameA
@onready var frame_b: StaticBody3D = $FrameB
@onready var frame_c: StaticBody3D = $FrameC
@onready var frame_d: StaticBody3D = $FrameD
@onready var frame_e: StaticBody3D = $FrameE
@onready var frame_model: MeshInstance3D = $FrameModel
@onready var mechanism: AnimatableBody3D = $Mechanism
@onready var mechanism_fallback: MeshInstance3D = $Mechanism/FallbackMesh
@onready var mechanism_model: MeshInstance3D = $Mechanism/Model
@onready var contents: Node3D = $Contents

var _phase: StringName = PHASE_CLOSED
var _open_fraction: float = 0.0
var _highlighted: bool = false
var _world_session: Node = null
var _closed_mechanism_transform: Transform3D = Transform3D.IDENTITY
var _open_mechanism_transform: Transform3D = Transform3D.IDENTITY
var _contents_closed_transform: Transform3D = Transform3D.IDENTITY
var _contents_relative_to_mechanism: Transform3D = Transform3D.IDENTITY
var _mechanism_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_world_session = _find_world_session()
	_prepare_unique_geometry_resources()
	_configure_geometry()
	_configure_visual_models()
	_mechanism_material = StandardMaterial3D.new()
	mechanism_fallback.material_override = _mechanism_material
	mechanism_model.material_override = _mechanism_material

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
	return true


func interact(interactor: Node) -> void:
	if _phase == PHASE_CLOSED or _phase == PHASE_CLOSING:
		request_open(interactor)
	else:
		request_close(interactor)


func request_open(_requester: Node = null) -> bool:
	if _phase == PHASE_OPEN:
		return true
	if _phase == PHASE_OPENING:
		return true
	_phase = PHASE_OPENING
	_queue_use_sound()
	return true


func request_close(_requester: Node = null) -> bool:
	if _phase == PHASE_CLOSED:
		return true
	if _phase == PHASE_CLOSING:
		return true
	_phase = PHASE_CLOSING
	_queue_use_sound()
	return true


func get_semantic_phase() -> StringName:
	return _phase


func get_open_fraction() -> float:
	return _open_fraction


func is_interaction_highlighted() -> bool:
	return _highlighted


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_refresh_visual()


func get_debug_summary() -> Dictionary:
	return {
		"container_id": container_id,
		"variant": container_variant,
		"phase": _phase,
		"open_fraction": _open_fraction,
		"opening_face": opening_face,
		"mechanism_mode": mechanism_mode,
		"contents_follow_mechanism": contents_follow_mechanism,
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
		or typeof(snapshot.get("open_fraction", null)) != TYPE_FLOAT
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


func set_frame_visual_model_from_path(path: String) -> bool:
	var model: Mesh = _load_mesh(path)
	if model == null:
		return false
	frame_visual_model_path = path.strip_edges()
	frame_visual_model = model
	_configure_visual_models()
	return true


func set_mechanism_visual_model_from_path(path: String) -> bool:
	var model: Mesh = _load_mesh(path)
	if model == null:
		return false
	mechanism_visual_model_path = path.strip_edges()
	mechanism_visual_model = model
	_configure_visual_models()
	return true


func _prepare_unique_geometry_resources() -> void:
	for body: StaticBody3D in [frame_a, frame_b, frame_c, frame_d, frame_e]:
		var collision := body.get_node("CollisionShape3D") as CollisionShape3D
		var mesh_instance := body.get_node("MeshInstance3D") as MeshInstance3D
		collision.shape = collision.shape.duplicate()
		mesh_instance.mesh = mesh_instance.mesh.duplicate()
	var mechanism_collision := mechanism.get_node("CollisionShape3D") as CollisionShape3D
	mechanism_collision.shape = mechanism_collision.shape.duplicate()
	mechanism_fallback.mesh = mechanism_fallback.mesh.duplicate()


func _configure_geometry() -> void:
	var wall: float = clampf(
		wall_thickness,
		0.02,
		maxf(0.02, minf(outer_size.x, outer_size.y, outer_size.z) * 0.45)
	)
	var panel: float = clampf(mechanism_thickness, 0.02, maxf(wall, 0.02))
	var inner_x: float = maxf(outer_size.x - wall * 2.0, 0.10)
	var inner_y: float = maxf(outer_size.y - wall * 2.0, 0.10)
	var inner_z: float = maxf(outer_size.z - wall * 2.0, 0.10)

	if opening_face == OPENING_TOP:
		_set_frame_piece(
			frame_a,
			Vector3(wall, outer_size.y, outer_size.z),
			Vector3(-outer_size.x * 0.5 + wall * 0.5, 0.0, 0.0)
		)
		_set_frame_piece(
			frame_b,
			Vector3(wall, outer_size.y, outer_size.z),
			Vector3(outer_size.x * 0.5 - wall * 0.5, 0.0, 0.0)
		)
		_set_frame_piece(
			frame_c,
			Vector3(inner_x, outer_size.y, wall),
			Vector3(0.0, 0.0, outer_size.z * 0.5 - wall * 0.5)
		)
		_set_frame_piece(
			frame_d,
			Vector3(inner_x, outer_size.y, wall),
			Vector3(0.0, 0.0, -outer_size.z * 0.5 + wall * 0.5)
		)
		_set_frame_piece(
			frame_e,
			Vector3(inner_x, wall, inner_z),
			Vector3(0.0, -outer_size.y * 0.5 + wall * 0.5, 0.0)
		)
		_configure_top_mechanism(inner_x, inner_z, panel)
	else:
		_set_frame_piece(
			frame_a,
			Vector3(wall, outer_size.y, outer_size.z),
			Vector3(-outer_size.x * 0.5 + wall * 0.5, 0.0, 0.0)
		)
		_set_frame_piece(
			frame_b,
			Vector3(wall, outer_size.y, outer_size.z),
			Vector3(outer_size.x * 0.5 - wall * 0.5, 0.0, 0.0)
		)
		_set_frame_piece(
			frame_c,
			Vector3(inner_x, wall, outer_size.z),
			Vector3(0.0, outer_size.y * 0.5 - wall * 0.5, 0.0)
		)
		_set_frame_piece(
			frame_d,
			Vector3(inner_x, wall, outer_size.z),
			Vector3(0.0, -outer_size.y * 0.5 + wall * 0.5, 0.0)
		)
		_set_frame_piece(
			frame_e,
			Vector3(inner_x, inner_y, wall),
			Vector3(0.0, 0.0, -outer_size.z * 0.5 + wall * 0.5)
		)
		_configure_front_mechanism(inner_x, inner_y, panel)

	_contents_closed_transform = Transform3D(
		Basis.IDENTITY,
		contents_closed_position
	)
	contents.transform = _contents_closed_transform
	_contents_relative_to_mechanism = (
		_closed_mechanism_transform.affine_inverse()
		* _contents_closed_transform
	)


func _configure_front_mechanism(
	inner_x: float,
	inner_y: float,
	panel: float
) -> void:
	var front_z: float = outer_size.z * 0.5 - panel * 0.5
	var size := Vector3(inner_x, inner_y, panel)
	if mechanism_mode == MODE_HINGE:
		_closed_mechanism_transform = Transform3D(
			Basis.IDENTITY,
			Vector3(-inner_x * 0.5, 0.0, front_z)
		)
		_set_mechanism_geometry(size, Vector3(inner_x * 0.5, 0.0, 0.0))
	else:
		_closed_mechanism_transform = Transform3D(
			Basis.IDENTITY,
			Vector3(0.0, 0.0, front_z)
		)
		_set_mechanism_geometry(size, Vector3.ZERO)
	_open_mechanism_transform = _make_open_transform(
		_closed_mechanism_transform
	)


func _configure_top_mechanism(
	inner_x: float,
	inner_z: float,
	panel: float
) -> void:
	var top_y: float = outer_size.y * 0.5 - panel * 0.5
	var size := Vector3(inner_x, panel, inner_z)
	if mechanism_mode == MODE_HINGE:
		_closed_mechanism_transform = Transform3D(
			Basis.IDENTITY,
			Vector3(0.0, top_y, -inner_z * 0.5)
		)
		_set_mechanism_geometry(size, Vector3(0.0, 0.0, inner_z * 0.5))
	else:
		_closed_mechanism_transform = Transform3D(
			Basis.IDENTITY,
			Vector3(0.0, top_y, 0.0)
		)
		_set_mechanism_geometry(size, Vector3.ZERO)
	_open_mechanism_transform = _make_open_transform(
		_closed_mechanism_transform
	)


func _make_open_transform(closed: Transform3D) -> Transform3D:
	var radians := Vector3(
		deg_to_rad(open_rotation_degrees.x),
		deg_to_rad(open_rotation_degrees.y),
		deg_to_rad(open_rotation_degrees.z)
	)
	return Transform3D(
		Basis.from_euler(radians),
		closed.origin + open_position_offset
	)


func _set_frame_piece(
	body: StaticBody3D,
	size: Vector3,
	position: Vector3
) -> void:
	body.position = position
	var collision := body.get_node("CollisionShape3D") as CollisionShape3D
	var mesh_instance := body.get_node("MeshInstance3D") as MeshInstance3D
	(collision.shape as BoxShape3D).size = size
	(mesh_instance.mesh as BoxMesh).size = size


func _set_mechanism_geometry(size: Vector3, local_offset: Vector3) -> void:
	var collision := mechanism.get_node("CollisionShape3D") as CollisionShape3D
	(collision.shape as BoxShape3D).size = size
	collision.position = local_offset
	(mechanism_fallback.mesh as BoxMesh).size = size
	mechanism_fallback.position = local_offset


func _configure_visual_models() -> void:
	var resolved_frame: Mesh = frame_visual_model
	if not frame_visual_model_path.strip_edges().is_empty():
		var loaded_frame: Mesh = _load_mesh(frame_visual_model_path)
		if loaded_frame != null:
			resolved_frame = loaded_frame
			frame_visual_model = loaded_frame
	if resolved_frame != null:
		frame_model.mesh = resolved_frame
		frame_model.visible = true
		for body: StaticBody3D in [frame_a, frame_b, frame_c, frame_d, frame_e]:
			(body.get_node("MeshInstance3D") as MeshInstance3D).visible = false
	else:
		frame_model.visible = false
		for body: StaticBody3D in [frame_a, frame_b, frame_c, frame_d, frame_e]:
			var mesh_instance := body.get_node("MeshInstance3D") as MeshInstance3D
			mesh_instance.visible = true
			var material := StandardMaterial3D.new()
			material.albedo_color = base_color
			mesh_instance.material_override = material

	var resolved_mechanism: Mesh = mechanism_visual_model
	if not mechanism_visual_model_path.strip_edges().is_empty():
		var loaded_mechanism: Mesh = _load_mesh(mechanism_visual_model_path)
		if loaded_mechanism != null:
			resolved_mechanism = loaded_mechanism
			mechanism_visual_model = loaded_mechanism
	mechanism_model.mesh = resolved_mechanism
	mechanism_model.visible = resolved_mechanism != null
	mechanism_fallback.visible = resolved_mechanism == null


func _load_mesh(path: String) -> Mesh:
	var normalized: String = path.strip_edges()
	if normalized.is_empty() or not ResourceLoader.exists(normalized):
		return null
	var loaded: Resource = ResourceLoader.load(normalized)
	if loaded is Mesh:
		return loaded as Mesh
	return null


func _sync_mechanism() -> void:
	if mechanism == null:
		return
	var fraction: float = clampf(_open_fraction, 0.0, 1.0)
	var closed_quaternion := Quaternion(_closed_mechanism_transform.basis)
	var open_quaternion := Quaternion(_open_mechanism_transform.basis)
	var interpolated_quaternion := closed_quaternion.slerp(
		open_quaternion,
		fraction
	)
	mechanism.transform = Transform3D(
		Basis(interpolated_quaternion),
		_closed_mechanism_transform.origin.lerp(
			_open_mechanism_transform.origin,
			fraction
		)
	)
	if contents_follow_mechanism:
		contents.transform = (
			mechanism.transform
			* _contents_relative_to_mechanism
		)
	else:
		contents.transform = _contents_closed_transform


func _refresh_visual() -> void:
	if _mechanism_material == null:
		return
	_mechanism_material.albedo_color = mechanism_color
	_mechanism_material.emission_enabled = false
	if _highlighted:
		_mechanism_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mechanism_material.disable_receive_shadows = true
	else:
		_mechanism_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_mechanism_material.disable_receive_shadows = false
	mechanism_fallback.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mechanism_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _queue_use_sound() -> void:
	if _world_session == null:
		return
	_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		&"gameplay.sound",
		{
			"kind": USE_SOUND_KIND,
			"origin": global_position,
			"strength": maxf(gameplay_sound_strength, 0.0),
			"container_id": container_id,
		}
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
	var cursor: Node = self
	while cursor != null:
		if (
			cursor.has_method("queue_semantic_gameplay_event")
			and cursor.has_method("get_mission_run_summary")
		):
			return cursor
		cursor = cursor.get_parent()
	return null
