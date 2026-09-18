class_name VarkAcousticSpace
extends Area3D


const MAP_UNITS_PER_WORLD_METER: float = 32.0
const IMPORTED_BOUNDS_TOLERANCE: float = 0.001

@export var space_id: String = ""
@export var half_extent_x: float = 2.0
@export var half_extent_y: float = 2.0
@export var half_extent_z: float = 2.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	add_to_group(&"vark_acoustic_space")


func _func_godot_apply_properties(_properties: Dictionary) -> void:
	_apply_imported_brush_bounds()


func _apply_imported_brush_bounds() -> void:
	var imported_shapes: Array[CollisionShape3D] = []
	for child: Node in get_children():
		if child is CollisionShape3D:
			imported_shapes.append(child as CollisionShape3D)

	if imported_shapes.size() != 1:
		_invalidate_imported_bounds(
			"must be authored as exactly one axis-aligned rectangular TrenchBroom brush"
		)
		return

	var collision_shape: CollisionShape3D = imported_shapes[0]
	var convex_shape := collision_shape.shape as ConvexPolygonShape3D
	if convex_shape == null:
		_invalidate_imported_bounds("did not import one convex brush shape")
		return

	var local_points := PackedVector3Array()
	for point: Vector3 in convex_shape.points:
		local_points.append(collision_shape.transform * point)

	if not _points_form_axis_aligned_box(local_points):
		_invalidate_imported_bounds(
			"must remain an axis-aligned rectangular box; wedges/rotated/multi-brush spaces are unsupported in the Phase 3.6 prototype"
		)
		return

	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)
	for point: Vector3 in local_points:
		bounds_min = bounds_min.min(point)
		bounds_max = bounds_max.max(point)

	var local_center: Vector3 = (bounds_min + bounds_max) * 0.5
	if local_center.length() > IMPORTED_BOUNDS_TOLERANCE:
		_invalidate_imported_bounds(
			"did not import around its bounds center; check the FuncGodot solid-class origin contract"
		)
		return

	var half_extents: Vector3 = (bounds_max - bounds_min) * 0.5
	half_extent_x = half_extents.x
	half_extent_y = half_extents.y
	half_extent_z = half_extents.z
	if not has_valid_extents():
		_invalidate_imported_bounds("imported non-positive or non-finite brush bounds")


func _points_form_axis_aligned_box(points: PackedVector3Array) -> bool:
	if points.size() != 8:
		return false
	var x_values: Array[float] = []
	var y_values: Array[float] = []
	var z_values: Array[float] = []
	for point: Vector3 in points:
		_append_unique_approx(x_values, point.x)
		_append_unique_approx(y_values, point.y)
		_append_unique_approx(z_values, point.z)
	return x_values.size() == 2 and y_values.size() == 2 and z_values.size() == 2


func _append_unique_approx(values: Array[float], value: float) -> void:
	for existing: float in values:
		if is_equal_approx(existing, value):
			return
	values.append(value)


func _invalidate_imported_bounds(reason: String) -> void:
	half_extent_x = 0.0
	half_extent_y = 0.0
	half_extent_z = 0.0
	push_error("Acoustic space '%s' %s." % [space_id, reason])


func contains_world_point(world_point: Vector3) -> bool:
	if not has_valid_extents():
		return false
	var local_point: Vector3 = to_local(world_point)
	const TOLERANCE: float = 0.001
	return (
		absf(local_point.x) <= half_extent_x + TOLERANCE
		and absf(local_point.y) <= half_extent_y + TOLERANCE
		and absf(local_point.z) <= half_extent_z + TOLERANCE
	)


func has_valid_extents() -> bool:
	return (
		is_finite(half_extent_x)
		and is_finite(half_extent_y)
		and is_finite(half_extent_z)
		and half_extent_x > 0.0
		and half_extent_y > 0.0
		and half_extent_z > 0.0
	)


func get_world_volume() -> float:
	if not has_valid_extents():
		return INF
	return 8.0 * half_extent_x * half_extent_y * half_extent_z
