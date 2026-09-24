class_name VarkGameplayLight
extends OmniLight3D


const STATE_CHANGED_EVENT_NAME: StringName = &"light.state_changed"
const EXTINGUISH_SOUND_KIND: StringName = &"light.extinguish"
const DIRECT_NONE: StringName = &"none"
const DIRECT_EXTINGUISH: StringName = &"extinguish"
const INTERACTION_PROXY_LAYER: int = 1 << 4


@export var persistent_id: String = ""
@export var gameplay_light_id: StringName = &"light"
@export var control_id: StringName = &""
@export_range(0.0, 4.0, 0.01) var gameplay_strength: float = 1.0
@export var gameplay_enabled: bool = true
@export var starts_on: bool = true
@export_flags_3d_physics var occlusion_mask: int = 1
@export var fixture_model: Mesh
@export var fixture_model_path: String = ""
@export var fixture_color: Color = Color(0.32, 0.27, 0.18, 1.0)
@export var direct_interaction: StringName = DIRECT_NONE
@export var interaction_size: Vector3 = Vector3(0.42, 0.42, 0.42)
@export var interaction_offset: Vector3 = Vector3.ZERO
@export var gameplay_sound_strength: float = 0.30

var _world_session: Node = null
var _fixture_mesh: MeshInstance3D = null
var _interaction_proxy: Area3D = null
var _interaction_collision: CollisionShape3D = null
var _highlighted: bool = false
var _fixture_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group(&"vark_gameplay_light")
	_world_session = _find_world_session()
	_fixture_mesh = get_node_or_null("FixtureMesh") as MeshInstance3D
	_interaction_proxy = get_node_or_null("InteractionProxy") as Area3D
	_interaction_collision = get_node_or_null(
		"InteractionProxy/CollisionShape3D"
	) as CollisionShape3D
	_configure_fixture()
	_configure_interaction_proxy()
	set_enabled_state(starts_on, false)


func is_vark_persistent_entity() -> bool:
	return not persistent_id.strip_edges().is_empty()


func get_persistent_id() -> String:
	return persistent_id


func get_content_id() -> String:
	return str(gameplay_light_id)


func get_control_id() -> StringName:
	return control_id


func is_enabled_state() -> bool:
	return gameplay_enabled and visible


func set_enabled_state(
	enabled: bool,
	emit_event: bool = true,
	source_id: StringName = &""
) -> bool:
	var changed: bool = gameplay_enabled != enabled or visible != enabled
	gameplay_enabled = enabled
	visible = enabled
	_refresh_interaction_proxy()
	if emit_event and changed:
		_queue_state_changed(source_id)
	return changed


func can_interact(_interactor: Node) -> bool:
	return direct_interaction == DIRECT_EXTINGUISH and is_enabled_state()


func interact(_interactor: Node) -> void:
	if not can_interact(_interactor):
		return
	if set_enabled_state(false, true, &"direct"):
		_queue_extinguish_sound()


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted and can_interact(null)
	_refresh_fixture_visual()


func is_interaction_highlighted() -> bool:
	return _highlighted


func capture_semantic_state() -> Dictionary:
	return {
		"gameplay_enabled": gameplay_enabled,
		"visible": visible,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if (
		snapshot.size() != 2
		or typeof(snapshot.get("gameplay_enabled", null)) != TYPE_BOOL
		or typeof(snapshot.get("visible", null)) != TYPE_BOOL
	):
		return false
	gameplay_enabled = bool(snapshot["gameplay_enabled"])
	visible = bool(snapshot["visible"])
	_refresh_interaction_proxy()
	return true


func reconcile_after_restore() -> bool:
	_world_session = _find_world_session()
	_refresh_interaction_proxy()
	_refresh_fixture_visual()
	return true


func get_gameplay_debug_state() -> Dictionary:
	return {
		"light_id": gameplay_light_id,
		"control_id": control_id,
		"persistent_id": persistent_id,
		"gameplay_enabled": gameplay_enabled,
		"visible": visible,
		"gameplay_strength": gameplay_strength,
		"range_meters": maxf(omni_range, 0.0),
		"active": (
			gameplay_enabled
			and visible
			and is_finite(gameplay_strength)
			and gameplay_strength > 0.0
		),
	}


func sample_gameplay_exposure(
	sample_position: Vector3,
	space_state: PhysicsDirectSpaceState3D
) -> Dictionary:
	var distance: float = global_position.distance_to(sample_position)
	var range_meters: float = maxf(omni_range, 0.001)
	if (
		not gameplay_enabled
		or not visible
		or gameplay_strength <= 0.0
		or distance >= range_meters
	):
		var inactive_state: Dictionary = get_gameplay_debug_state()
		inactive_state.merge({
			"distance": distance,
			"distance_weight": 0.0,
			"occluded": false,
			"contribution": 0.0,
		}, true)
		return inactive_state

	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		sample_position
	)
	query.collision_mask = occlusion_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit: Dictionary = space_state.intersect_ray(query)
	var occluded: bool = not hit.is_empty()
	var distance_weight: float = clampf(
		1.0 - distance / range_meters,
		0.0,
		1.0
	)
	var state: Dictionary = get_gameplay_debug_state()
	state.merge({
		"distance": distance,
		"distance_weight": distance_weight,
		"occluded": occluded,
		"contribution": (
			0.0
			if occluded
			else gameplay_strength * distance_weight
		),
	}, true)
	return state


func _configure_fixture() -> void:
	if _fixture_mesh == null:
		return
	var resolved: Mesh = fixture_model
	if not fixture_model_path.strip_edges().is_empty():
		var path: String = fixture_model_path.strip_edges()
		if ResourceLoader.exists(path):
			var loaded: Resource = ResourceLoader.load(path)
			if loaded is Mesh:
				resolved = loaded as Mesh
				fixture_model = resolved
	_fixture_mesh.mesh = resolved
	_fixture_material = StandardMaterial3D.new()
	_fixture_material.roughness = 0.75
	_fixture_mesh.material_override = _fixture_material
	_refresh_fixture_visual()


func _configure_interaction_proxy() -> void:
	if _interaction_collision != null:
		_interaction_collision.shape = _interaction_collision.shape.duplicate()
		var box := _interaction_collision.shape as BoxShape3D
		if box != null:
			box.size = Vector3(
				maxf(interaction_size.x, 0.05),
				maxf(interaction_size.y, 0.05),
				maxf(interaction_size.z, 0.05)
			)
		_interaction_collision.position = interaction_offset
	if direct_interaction == DIRECT_EXTINGUISH:
		add_to_group(&"vark_interactable")
	_refresh_interaction_proxy()


func _refresh_interaction_proxy() -> void:
	if _interaction_proxy == null:
		return
	var enabled: bool = direct_interaction == DIRECT_EXTINGUISH and is_enabled_state()
	_interaction_proxy.collision_layer = INTERACTION_PROXY_LAYER if enabled else 0
	_interaction_proxy.collision_mask = 0
	if not enabled and _highlighted:
		_highlighted = false
		_refresh_fixture_visual()


func _refresh_fixture_visual() -> void:
	if _fixture_material == null:
		return
	_fixture_material.albedo_color = fixture_color
	_fixture_material.emission_enabled = false
	_fixture_material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
		if _highlighted
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	_fixture_material.disable_receive_shadows = _highlighted


func _queue_state_changed(source_id: StringName) -> void:
	if _world_session == null:
		return
	_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		STATE_CHANGED_EVENT_NAME,
		{
			"light_id": gameplay_light_id,
			"control_id": control_id,
			"enabled": is_enabled_state(),
			"source_id": source_id,
		}
	)


func _queue_extinguish_sound() -> void:
	if _world_session == null:
		return
	_world_session.call(
		"queue_gameplay_sound",
		int(_world_session.get("session_id")),
		EXTINGUISH_SOUND_KIND,
		global_position,
		maxf(gameplay_sound_strength, 0.0)
	)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if (
			cursor.has_method("queue_semantic_gameplay_event")
			and cursor.has_method("queue_gameplay_sound")
		):
			return cursor
		cursor = cursor.get_parent()
	return null
