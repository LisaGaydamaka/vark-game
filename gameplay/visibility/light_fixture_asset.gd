@tool
class_name VarkLightFixtureAsset
extends Node3D


# Reserved render layer used only by a fixture's local visual self-fill.
# Ordinary world geometry remains on layer 1, so this helper cannot brighten
# the room or become a second gameplay-light source.
const FIXTURE_SELF_FILL_RENDER_LAYER: int = 1 << 19
# Dedicated physics layer used only by gameplay-light visibility rays. The
# player-facing solid collision stays coarse, while this occluder is generated
# from the opaque fixture body mesh so semantic exposure follows rendered
# fixture shadowing without treating glass as opaque.
const EXPOSURE_OCCLUDER_PHYSICS_LAYER: int = 1 << 5


@export var asset_id: StringName = &""
@export var lit_surface_off_color: Color = Color(0.10, 0.09, 0.07, 1.0)
@export var lit_surface_on_color: Color = Color(1.0, 0.72, 0.28, 1.0)
@export_range(0.0, 16.0, 0.1) var lit_surface_emission_energy: float = 3.0
@export var lit_surface_visible_when_off: bool = true
@export_range(0.0, 2.0, 0.01) var self_fill_energy_scale: float = 0.45
@export_range(0.05, 4.0, 0.05) var self_fill_range: float = 0.85

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var lit_surface_mesh: MeshInstance3D = $LitSurfaceMesh
@onready var emitter_anchor: Marker3D = $EmitterAnchor
@onready var fixture_fill: OmniLight3D = $EmitterAnchor/FixtureFill
@onready var solid_body: StaticBody3D = $SolidBody
@onready var exposure_occluder: StaticBody3D = $ExposureOccluder

var _body_material: StandardMaterial3D = null
var _body_authored_shading_mode: BaseMaterial3D.ShadingMode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
var _body_authored_disable_receive_shadows: bool = false
var _lit_material: StandardMaterial3D = null
var _lit_enabled: bool = false
var _highlighted: bool = false
var _source_light_color: Color = Color.WHITE
var _source_light_energy: float = 0.0


func _ready() -> void:
	_configure_render_layers()
	_configure_exposure_occluder()
	_localize_body_material()
	_apply_lit_surface_material()
	_configure_fixture_fill()
	set_lit_enabled(_lit_enabled)


func validate_contract() -> bool:
	return (
		not asset_id.is_empty()
		and body_mesh != null
		and body_mesh.mesh != null
		and lit_surface_mesh != null
		and lit_surface_mesh.mesh != null
		and emitter_anchor != null
		and fixture_fill != null
		and solid_body != null
		and exposure_occluder != null
		and _collision_shape_count(solid_body) > 0
		and _collision_shape_count(exposure_occluder) > 0
		and exposure_occluder.collision_layer == EXPOSURE_OCCLUDER_PHYSICS_LAYER
		and exposure_occluder.collision_mask == 0
		and _is_imported_mesh(body_mesh.mesh)
		and _is_imported_mesh(lit_surface_mesh.mesh)
		and _emitter_is_inside_lit_surface()
		and (
			body_mesh.layers & FIXTURE_SELF_FILL_RENDER_LAYER
		) != 0
		and (
			body_mesh.layers & 1
		) != 0
		and (
			lit_surface_mesh.layers & FIXTURE_SELF_FILL_RENDER_LAYER
		) == 0
		and fixture_fill.light_cull_mask == FIXTURE_SELF_FILL_RENDER_LAYER
		and not fixture_fill.shadow_enabled
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


func configure_source_lighting(
	source_color: Color,
	source_energy: float
) -> void:
	_source_light_color = source_color
	_source_light_energy = maxf(source_energy, 0.0)
	_configure_fixture_fill()


func set_lit_enabled(enabled: bool) -> void:
	_lit_enabled = enabled
	_refresh_visuals()


func is_lit_enabled() -> bool:
	return _lit_enabled


func set_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_refresh_visuals()


func get_contract_summary() -> Dictionary:
	var body_material: Material = (
		body_mesh.material_override
		if body_mesh != null
		else null
	)
	var body_standard := body_material as StandardMaterial3D
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
		"collision_shape_count": _collision_shape_count(solid_body),
		"exposure_occluder_shape_count": _collision_shape_count(exposure_occluder),
		"exposure_occluder_layer": exposure_occluder.collision_layer if exposure_occluder != null else 0,
		"exposure_occluder_mask": exposure_occluder.collision_mask if exposure_occluder != null else 0,
		"collision_layer": (
			solid_body.collision_layer
			if solid_body != null
			else 0
		),
		"body_layers": body_mesh.layers if body_mesh != null else 0,
		"lit_surface_layers": (
			lit_surface_mesh.layers
			if lit_surface_mesh != null
			else 0
		),
		"body_material_instance_id": (
			body_material.get_instance_id()
			if body_material != null
			else 0
		),
		"body_material_albedo": (
			body_standard.albedo_color
			if body_standard != null
			else Color()
		),
		"body_material_shading_mode": (
			body_standard.shading_mode
			if body_standard != null
			else -1
		),
		"body_material_disable_receive_shadows": (
			body_standard.disable_receive_shadows
			if body_standard != null
			else false
		),
		"body_material_emission_enabled": (
			body_standard.emission_enabled
			if body_standard != null
			else false
		),
		"body_cast_shadow": (
			body_mesh.cast_shadow
			if body_mesh != null
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		),
		"highlighted": _highlighted,
		"fixture_fill_energy": (
			fixture_fill.light_energy
			if fixture_fill != null
			else 0.0
		),
		"fixture_fill_range": (
			fixture_fill.omni_range
			if fixture_fill != null
			else 0.0
		),
		"fixture_fill_cull_mask": (
			fixture_fill.light_cull_mask
			if fixture_fill != null
			else 0
		),
		"fixture_fill_shadows": (
			fixture_fill.shadow_enabled
			if fixture_fill != null
			else true
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
		"lit_surface_shading_mode": (
			_lit_material.shading_mode
			if _lit_material != null
			else -1
		),
		"lit_surface_disable_receive_shadows": (
			_lit_material.disable_receive_shadows
			if _lit_material != null
			else false
		),
	}


func _collision_shape_count(body: StaticBody3D) -> int:
	if body == null:
		return 0
	var count: int = 0
	for candidate: Node in body.get_children():
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


func _configure_exposure_occluder() -> void:
	if exposure_occluder == null or body_mesh == null or body_mesh.mesh == null:
		return
	for child: Node in exposure_occluder.get_children():
		child.free()
	var collision := CollisionShape3D.new()
	collision.name = "OpaqueBodyExposureShape"
	var shape: ConcavePolygonShape3D = body_mesh.mesh.create_trimesh_shape()
	shape.backface_collision = true
	collision.shape = shape
	collision.transform = exposure_occluder.transform.affine_inverse() * body_mesh.transform
	exposure_occluder.collision_layer = EXPOSURE_OCCLUDER_PHYSICS_LAYER
	exposure_occluder.collision_mask = 0
	exposure_occluder.add_child(collision)


func _configure_render_layers() -> void:
	if body_mesh != null:
		# Keep the ordinary layer so every normal scene light can illuminate the
		# fixture. Add one private layer for the lamp's unshadowed local fill.
		body_mesh.layers |= 1
		body_mesh.layers |= FIXTURE_SELF_FILL_RENDER_LAYER
	if lit_surface_mesh != null:
		# Glass/flame owns its explicit state material and must not receive the
		# fixture-only body fill.
		lit_surface_mesh.layers |= 1
		lit_surface_mesh.layers &= ~FIXTURE_SELF_FILL_RENDER_LAYER


func _localize_body_material() -> void:
	if body_mesh == null:
		return
	var authored := body_mesh.material_override as StandardMaterial3D
	if authored == null:
		return
	# Highlight state is per runtime fixture instance. Duplicate the authored
	# body material so aiming at one lamp never changes another lamp and so
	# temporary fullbright feedback cannot mutate the source asset resource.
	_body_material = authored.duplicate() as StandardMaterial3D
	if _body_material == null:
		return
	_body_authored_shading_mode = _body_material.shading_mode
	_body_authored_disable_receive_shadows = (
		_body_material.disable_receive_shadows
	)
	body_mesh.material_override = _body_material


func _apply_lit_surface_material() -> void:
	# The fixture body deliberately keeps the materials authored/imported by
	# the asset. Runtime ON/OFF state never owns or rewrites body albedo.
	_lit_material = StandardMaterial3D.new()
	_lit_material.roughness = 0.45
	lit_surface_mesh.material_override = _lit_material
	lit_surface_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_refresh_visuals()


func _configure_fixture_fill() -> void:
	if fixture_fill == null:
		return
	fixture_fill.light_color = _source_light_color
	fixture_fill.omni_range = maxf(self_fill_range, 0.05)
	fixture_fill.light_cull_mask = FIXTURE_SELF_FILL_RENDER_LAYER
	fixture_fill.shadow_enabled = false
	fixture_fill.light_energy = (
		_source_light_energy * maxf(self_fill_energy_scale, 0.0)
		if _lit_enabled
		else 0.0
	)


func _refresh_visuals() -> void:
	# Interaction selection follows the same Thief-style contract as doors,
	# containers, and pickups: preserve authored color/emission and ordinary
	# cast-shadow behavior, but make every visible fixture surface fullbright
	# and immune to received scene shadows while targeted.
	if _body_material != null:
		_body_material.shading_mode = (
			BaseMaterial3D.SHADING_MODE_UNSHADED
			if _highlighted
			else _body_authored_shading_mode
		)
		_body_material.disable_receive_shadows = (
			true
			if _highlighted
			else _body_authored_disable_receive_shadows
		)

	if _lit_material == null or lit_surface_mesh == null:
		_configure_fixture_fill()
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
	_configure_fixture_fill()


func _is_imported_mesh(mesh: Mesh) -> bool:
	if mesh == null:
		return false
	var path: String = mesh.resource_path
	return (
		path.ends_with(".obj")
		or path.ends_with(".glb")
		or path.ends_with(".gltf")
	)
