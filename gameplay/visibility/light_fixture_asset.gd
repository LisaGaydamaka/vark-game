@tool
class_name VarkLightFixtureAsset
extends Node3D


@export var asset_id: StringName = &""
@export var body_color: Color = Color(0.22, 0.18, 0.12, 1.0)
@export var lit_surface_off_color: Color = Color(0.10, 0.09, 0.07, 1.0)
@export var lit_surface_on_color: Color = Color(1.0, 0.72, 0.28, 1.0)
@export_range(0.0, 16.0, 0.1) var lit_surface_emission_energy: float = 3.0
@export var lit_surface_visible_when_off: bool = true

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var lit_surface_mesh: MeshInstance3D = $LitSurfaceMesh
@onready var emitter_anchor: Marker3D = $EmitterAnchor
@onready var solid_body: StaticBody3D = $SolidBody

var _body_material: StandardMaterial3D = null
var _lit_material: StandardMaterial3D = null
var _lit_enabled: bool = false
var _highlighted: bool = false


func _ready() -> void:
	_apply_authored_materials()
	set_lit_enabled(_lit_enabled)


func validate_contract() -> bool:
	return (
		not asset_id.is_empty()
		and body_mesh != null
		and body_mesh.mesh != null
		and lit_surface_mesh != null
		and lit_surface_mesh.mesh != null
		and emitter_anchor != null
		and solid_body != null
		and _collision_shape_count() > 0
		and _is_imported_mesh(body_mesh.mesh)
		and _is_imported_mesh(lit_surface_mesh.mesh)
		and _emitter_is_inside_lit_surface()
	)


func get_emitter_transform() -> Transform3D:
	return (
		emitter_anchor.transform
		if emitter_anchor != null
		else Transform3D.IDENTITY
	)


func get_collision_rids() -> Array[RID]:
	var result: Array[RID] = []
	if solid_body != null and solid_body.get_rid().is_valid():
		result.append(solid_body.get_rid())
	return result


func set_lit_enabled(enabled: bool) -> void:
	_lit_enabled = enabled
	_refresh_visuals()


func is_lit_enabled() -> bool:
	return _lit_enabled


func set_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_refresh_visuals()


func get_contract_summary() -> Dictionary:
	return {
		"asset_id": asset_id,
		"body_model_path": (
			body_mesh.mesh.resource_path
			if body_mesh != null and body_mesh.mesh != null
			else ""
		),
		"lit_surface_model_path": (
			lit_surface_mesh.mesh.resource_path
			if lit_surface_mesh != null and lit_surface_mesh.mesh != null
			else ""
		),
		"emitter_local_position": (
			emitter_anchor.position
			if emitter_anchor != null
			else Vector3.ZERO
		),
		"emitter_inside_lit_surface": _emitter_is_inside_lit_surface(),
		"collision_shape_count": _collision_shape_count(),
		"collision_layer": (
			solid_body.collision_layer
			if solid_body != null
			else 0
		),
		"lit_enabled": _lit_enabled,
		"lit_surface_visible": (
			lit_surface_mesh.visible
			if lit_surface_mesh != null
			else false
		),
		"lit_surface_emission_enabled": (
			_lit_material.emission_enabled
			if _lit_material != null
			else false
		),
		"lit_surface_color": (
			_lit_material.albedo_color
			if _lit_material != null
			else Color()
		),
	}


func _collision_shape_count() -> int:
	if solid_body == null:
		return 0
	var count: int = 0
	for candidate: Node in solid_body.get_children():
		if candidate is CollisionShape3D:
			var collision := candidate as CollisionShape3D
			if collision.shape != null and not collision.disabled:
				count += 1
	return count


func _emitter_is_inside_lit_surface() -> bool:
	if (
		emitter_anchor == null
		or lit_surface_mesh == null
		or lit_surface_mesh.mesh == null
	):
		return false
	var lit_bounds: AABB = lit_surface_mesh.mesh.get_aabb()
	var point_in_mesh_space: Vector3 = (
		lit_surface_mesh.transform.affine_inverse()
		* emitter_anchor.position
	)
	return lit_bounds.has_point(point_in_mesh_space)


func _apply_authored_materials() -> void:
	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 0.78
	_body_material.albedo_color = body_color
	body_mesh.material_override = _body_material
	body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	_lit_material = StandardMaterial3D.new()
	_lit_material.roughness = 0.45
	lit_surface_mesh.material_override = _lit_material
	lit_surface_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_refresh_visuals()


func _refresh_visuals() -> void:
	if _body_material != null:
		_body_material.albedo_color = body_color
		_body_material.shading_mode = (
			BaseMaterial3D.SHADING_MODE_UNSHADED
			if _highlighted
			else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		)
		_body_material.disable_receive_shadows = _highlighted

	if _lit_material == null or lit_surface_mesh == null:
		return
	lit_surface_mesh.visible = _lit_enabled or lit_surface_visible_when_off
	_lit_material.albedo_color = (
		lit_surface_on_color
		if _lit_enabled
		else lit_surface_off_color
	)
	_lit_material.emission_enabled = _lit_enabled
	_lit_material.emission = lit_surface_on_color
	_lit_material.emission_energy_multiplier = (
		lit_surface_emission_energy
		if _lit_enabled
		else 0.0
	)
	_lit_material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
		if _highlighted
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	_lit_material.disable_receive_shadows = _highlighted


func _is_imported_mesh(mesh: Mesh) -> bool:
	if mesh == null:
		return false
	var path: String = mesh.resource_path
	return (
		path.ends_with(".obj")
		or path.ends_with(".glb")
		or path.ends_with(".gltf")
	)
