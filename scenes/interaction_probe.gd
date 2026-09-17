extends StaticBody3D


@export var interaction_label: String = "Interaction Probe"
@export var interaction_enabled: bool = true
@export var disable_after_interact: bool = false
@export var base_color: Color = Color(0.25, 0.45, 0.75, 1.0)

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var status_label: Label3D = $StatusLabel

var _highlighted: bool = false
var _interaction_count: int = 0
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_material = StandardMaterial3D.new()
	mesh.material_override = _material
	_refresh_visual()


func can_interact(_interactor: Node) -> bool:
	return interaction_enabled


func interact(_interactor: Node) -> void:
	if not interaction_enabled:
		return
	_interaction_count += 1
	if disable_after_interact:
		interaction_enabled = false
		_highlighted = false
	_refresh_visual()


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted and interaction_enabled
	_refresh_visual()


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	if not interaction_enabled:
		_highlighted = false
	_refresh_visual()


func is_interaction_highlighted() -> bool:
	return _highlighted


func get_interaction_count() -> int:
	return _interaction_count


func _refresh_visual() -> void:
	if _material != null:
		# Thief-style selection keeps the authored/base color and the object's
		# ordinary cast shadow, but removes all lighting/shadow response from the
		# selected object's own visible surface.
		_material.albedo_color = base_color
		_material.emission_enabled = false
		_material.disable_receive_shadows = _highlighted
		_material.shading_mode = (
			BaseMaterial3D.SHADING_MODE_UNSHADED
			if _highlighted
			else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		)
	if status_label != null:
		var state_text: String = "READY" if interaction_enabled else "INACTIVE"
		status_label.text = "%s\n%s · uses: %d" % [
			interaction_label,
			state_text,
			_interaction_count,
		]