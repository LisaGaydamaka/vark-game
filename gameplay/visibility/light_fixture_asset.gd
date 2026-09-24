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
		and _is_imported_mesh(body_mesh.mesh)
		and _is_imported_mesh(lit_surface_mesh.mesh)
	)


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
