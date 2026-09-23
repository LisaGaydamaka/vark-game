@tool
class_name VarkContainerAsset
extends Node3D


@export var asset_id: StringName = &""
@export var body_color: Color = Color(0.30, 0.22, 0.15, 1.0)
@export var mechanism_color: Color = Color(0.42, 0.29, 0.17, 1.0)

@onready var mechanism: AnimatableBody3D = $Mechanism
@onready var open_pose: Marker3D = $OpenPose

var _contents_anchor: Node3D = null
var _mechanism_materials: Array[StandardMaterial3D] = []
var _closed_visual_size: Vector3 = Vector3.ZERO


func _ready() -> void:
	_contents_anchor = find_child("ContentsAnchor", true, false) as Node3D
	_apply_authored_materials()
	_closed_visual_size = _compute_visual_bounds().size


func validate_contract() -> bool:
	if asset_id.is_empty() or mechanism == null or open_pose == null:
		return false
	if _contents_anchor == null:
		_contents_anchor = find_child("ContentsAnchor", true, false) as Node3D
	if _contents_anchor == null:
		return false

	var mechanism_mesh_count: int = 0
	var mechanism_collision_count: int = 0
	for candidate: Node in mechanism.find_children("*", "", true, false):
		if candidate is MeshInstance3D:
			var mesh_instance := candidate as MeshInstance3D
			if mesh_instance.mesh != null:
				mechanism_mesh_count += 1
		elif candidate is CollisionShape3D:
			var collision := candidate as CollisionShape3D
			if collision.shape != null:
				mechanism_collision_count += 1

	var static_collision_count: int = 0
	for candidate: Node in find_children("*", "StaticBody3D", true, false):
		for child: Node in candidate.find_children("*", "CollisionShape3D", true, false):
			var collision := child as CollisionShape3D
			if collision != null and collision.shape != null:
				static_collision_count += 1

	return (
		mechanism_mesh_count > 0
		and mechanism_collision_count > 0
		and static_collision_count > 0
		and int(get_contract_summary().get("imported_model_count", 0)) >= 2
	)


func get_mechanism() -> AnimatableBody3D:
	return mechanism


func get_contents_anchor() -> Node3D:
	if _contents_anchor == null:
		_contents_anchor = find_child("ContentsAnchor", true, false) as Node3D
	return _contents_anchor


func get_closed_mechanism_transform() -> Transform3D:
	return mechanism.transform if mechanism != null else Transform3D.IDENTITY


func get_open_mechanism_transform() -> Transform3D:
	return open_pose.transform if open_pose != null else Transform3D.IDENTITY


func set_mechanism_highlighted(highlighted: bool) -> void:
	for material: StandardMaterial3D in _mechanism_materials:
		material.albedo_color = mechanism_color
		material.emission_enabled = false
		material.shading_mode = (
			BaseMaterial3D.SHADING_MODE_UNSHADED
			if highlighted
			else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		)
		material.disable_receive_shadows = highlighted


func get_contract_summary() -> Dictionary:
	var imported_model_count: int = 0
	var model_paths: Array[String] = []
	for candidate: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var path: String = mesh_instance.mesh.resource_path
		if (
			path.ends_with(".obj")
			or path.ends_with(".glb")
			or path.ends_with(".gltf")
		):
			imported_model_count += 1
			model_paths.append(path)
	model_paths.sort()
	return {
		"asset_id": asset_id,
		"imported_model_count": imported_model_count,
		"model_paths": model_paths,
		"closed_visual_size": _closed_visual_size,
		"closed_mechanism_transform": get_closed_mechanism_transform(),
		"open_mechanism_transform": get_open_mechanism_transform(),
		"contents_follow_mechanism": (
			_contents_anchor != null
			and mechanism != null
			and mechanism.is_ancestor_of(_contents_anchor)
		),
	}


func _apply_authored_materials() -> void:
	_mechanism_materials.clear()
	for candidate: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var material := StandardMaterial3D.new()
		material.roughness = 0.78
		material.albedo_color = (
			mechanism_color
			if mechanism != null and mechanism.is_ancestor_of(mesh_instance)
			else body_color
		)
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mechanism != null and mechanism.is_ancestor_of(mesh_instance):
			_mechanism_materials.append(material)


func _compute_visual_bounds() -> AABB:
	var has_bounds: bool = false
	var bounds := AABB()
	for candidate: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var relative_transform: Transform3D = (
			global_transform.affine_inverse()
			* mesh_instance.global_transform
		)
		var transformed: AABB = _transform_aabb(
			mesh_instance.mesh.get_aabb(),
			relative_transform
		)
		if not has_bounds:
			bounds = transformed
			has_bounds = true
		else:
			bounds = bounds.merge(transformed)
	return bounds if has_bounds else AABB()


func _transform_aabb(source: AABB, transform_value: Transform3D) -> AABB:
	var first: Vector3 = transform_value * source.position
	var result := AABB(first, Vector3.ZERO)
	for x: float in [source.position.x, source.end.x]:
		for y: float in [source.position.y, source.end.y]:
			for z: float in [source.position.z, source.end.z]:
				result = result.expand(
					transform_value * Vector3(x, y, z)
				)
	return result
