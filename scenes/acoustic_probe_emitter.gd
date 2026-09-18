extends StaticBody3D


@export var sound_kind: StringName = &"acoustic.probe"
@export var sound_strength: float = 0.5
@export var base_color: Color = Color(0.65, 0.45, 0.18, 1.0)

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var status_label: Label3D = $StatusLabel

var _highlighted: bool = false
var _emit_count: int = 0
var _material: StandardMaterial3D = null
var _world_session: Node = null


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_world_session = _find_world_session()
	_material = StandardMaterial3D.new()
	mesh.material_override = _material
	_refresh_visual()


func can_interact(_interactor: Node) -> bool:
	return _world_session != null and is_finite(sound_strength) and sound_strength > 0.0


func interact(_interactor: Node) -> void:
	if not can_interact(_interactor):
		return
	var source_session_id: int = int(_world_session.get("session_id"))
	if bool(_world_session.call(
		"queue_gameplay_sound",
		source_session_id,
		sound_kind,
		global_position,
		sound_strength
	)):
		_emit_count += 1
		_refresh_visual()


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_refresh_visual()


func is_interaction_highlighted() -> bool:
	return _highlighted


func get_emit_count() -> int:
	return _emit_count


func _refresh_visual() -> void:
	if _material != null:
		_material.albedo_color = base_color
		_material.emission_enabled = false
		_material.disable_receive_shadows = _highlighted
		_material.shading_mode = (
			BaseMaterial3D.SHADING_MODE_UNSHADED
			if _highlighted
			else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		)
	if status_label != null:
		status_label.text = "%s\nstrength %.2f · F to emit · uses %d" % [
			str(sound_kind),
			sound_strength,
			_emit_count,
		]


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_gameplay_sound"):
			return cursor
		cursor = cursor.get_parent()
	return null
