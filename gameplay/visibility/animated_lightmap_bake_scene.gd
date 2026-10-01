class_name VarkAnimatedLightmapBakeScene
extends RefCounted

const SURFACE_EPSILON: float = 0.001
const RAY_EPSILON: float = 0.000001
const LEAF_TRIANGLE_LIMIT: int = 4

var _triangles: Array[Dictionary] = []
var _nodes: Array[Dictionary] = []
var _root_index: int = -1
var _fingerprint: String = ""
var _errors := PackedStringArray()


func configure(layout: VarkAnimatedLightmapLayout) -> bool:
	_triangles.clear()
	_nodes.clear()
	_root_index = -1
	_fingerprint = ""
	_errors = PackedStringArray()
	if layout == null or layout.faces.is_empty():
		_errors.append("static light bake scene requires a non-empty surface layout")
		return false

	for face: Dictionary in layout.faces:
		var face_id: String = str(face.get("face_id", ""))
		var triangles_uv: PackedVector2Array = face.get(
			"triangles_uv", PackedVector2Array()
		)
		if face_id.is_empty() or triangles_uv.size() % 3 != 0:
			_errors.append(
				"face '%s' has invalid triangle data for static bake scene" % face_id
			)
			continue
		for index: int in range(0, triangles_uv.size(), 3):
			var a: Vector3 = _face_local_to_world(face, triangles_uv[index])
			var b: Vector3 = _face_local_to_world(face, triangles_uv[index + 1])
			var c: Vector3 = _face_local_to_world(face, triangles_uv[index + 2])
			var normal: Vector3 = (b - a).cross(c - a)
			if normal.length_squared() <= RAY_EPSILON * RAY_EPSILON:
				_errors.append(
					"face '%s' contains a degenerate static bake triangle" % face_id
				)
				continue
			normal = normal.normalized()
			var triangle_id: String = _triangle_id(face_id, a, b, c)
			var minimum: Vector3 = a.min(b).min(c)
			var maximum: Vector3 = a.max(b).max(c)
			_triangles.append({
				"triangle_id": triangle_id,
				"face_id": face_id,
				"a": a,
				"b": b,
				"c": c,
				"normal": normal,
				"minimum": minimum,
				"maximum": maximum,
				"centroid": (a + b + c) / 3.0,
			})
	if not _errors.is_empty() or _triangles.is_empty():
		if _triangles.is_empty() and _errors.is_empty():
			_errors.append("static light bake scene contains no triangles")
		return false

	_triangles.sort_custom(_sort_triangles)
	var indices: Array[int] = []
	for index: int in _triangles.size():
		indices.append(index)
	_root_index = _build_node(indices)
	_fingerprint = _hash_text(to_canonical_text())
	return _root_index >= 0 and not _fingerprint.is_empty()


func get_errors() -> PackedStringArray:
	return _errors.duplicate()


func get_triangle_count() -> int:
	return _triangles.size()


func get_node_count() -> int:
	return _nodes.size()


func get_fingerprint() -> String:
	return _fingerprint


func to_canonical_text() -> String:
	var lines := PackedStringArray()
	for triangle: Dictionary in _triangles:
		lines.append(
			"triangle|%s|face=%s|a=%s|b=%s|c=%s"
			% [
				str(triangle.get("triangle_id", "")),
				str(triangle.get("face_id", "")),
				_vector3_text(triangle.get("a", Vector3.ZERO)),
				_vector3_text(triangle.get("b", Vector3.ZERO)),
				_vector3_text(triangle.get("c", Vector3.ZERO)),
			]
		)
	for index: int in _nodes.size():
		var node: Dictionary = _nodes[index]
		var leaf_indices: Array = node.get("triangle_indices", [])
		var leaf_parts := PackedStringArray()
		for triangle_index: int in leaf_indices:
			leaf_parts.append(
				str(_triangles[triangle_index].get("triangle_id", ""))
			)
		lines.append(
			"node|%d|min=%s|max=%s|left=%d|right=%d|triangles=%s"
			% [
				index,
				_vector3_text(node.get("minimum", Vector3.ZERO)),
				_vector3_text(node.get("maximum", Vector3.ZERO)),
				int(node.get("left", -1)),
				int(node.get("right", -1)),
				",".join(leaf_parts),
			]
		)
	return "\n".join(lines) + "\n"


func sample_direct_irradiance(
	point: Vector3,
	normal: Vector3,
	descriptor: Dictionary,
	owner_face_id: String = ""
) -> float:
	var light_position: Vector3 = descriptor.get("position", Vector3.ZERO)
	var to_light: Vector3 = light_position - point
	var distance: float = to_light.length()
	var light_range: float = maxf(float(descriptor.get("range", 0.0)), 0.0)
	if distance <= SURFACE_EPSILON or light_range <= 0.0 or distance >= light_range:
		return 0.0
	var unit_normal: Vector3 = normal.normalized()
	var direction: Vector3 = to_light / distance
	var ndotl: float = unit_normal.dot(direction)
	if ndotl <= 0.0:
		return 0.0
	if not is_visible(point, unit_normal, light_position, owner_face_id):
		return 0.0
	var attenuation: float = 1.0 - distance / light_range
	attenuation *= attenuation
	return (
		maxf(float(descriptor.get("energy", 0.0)), 0.0)
		* attenuation
		* ndotl
	)


func is_visible(
	point: Vector3,
	normal: Vector3,
	light_position: Vector3,
	owner_face_id: String = ""
) -> bool:
	if _root_index < 0:
		return false
	var origin: Vector3 = point + normal.normalized() * SURFACE_EPSILON
	var to_light: Vector3 = light_position - origin
	var max_distance: float = to_light.length()
	if max_distance <= SURFACE_EPSILON:
		return true
	var direction: Vector3 = to_light / max_distance
	var hit: Dictionary = ray_first_hit(
		origin,
		direction,
		max_distance - SURFACE_EPSILON,
		owner_face_id
	)
	return hit.is_empty()


func ray_first_hit(
	origin: Vector3,
	direction: Vector3,
	max_distance: float,
	owner_face_id: String = ""
) -> Dictionary:
	if _root_index < 0 or max_distance <= 0.0:
		return {}
	var nearest: float = max_distance
	var nearest_triangle: Dictionary = {}
	var stack: Array[int] = [_root_index]
	while not stack.is_empty():
		var node_index: int = stack.pop_back()
		if node_index < 0 or node_index >= _nodes.size():
			continue
		var node: Dictionary = _nodes[node_index]
		if not _ray_hits_aabb(
			origin,
			direction,
			node.get("minimum", Vector3.ZERO),
			node.get("maximum", Vector3.ZERO),
			nearest
		):
			continue
		var triangle_indices: Array = node.get("triangle_indices", [])
		if not triangle_indices.is_empty():
			for triangle_index: int in triangle_indices:
				var triangle: Dictionary = _triangles[triangle_index]
				var distance: float = _ray_triangle_distance(
					origin,
					direction,
					triangle.get("a", Vector3.ZERO),
					triangle.get("b", Vector3.ZERO),
					triangle.get("c", Vector3.ZERO)
				)
				if distance <= RAY_EPSILON or distance >= nearest:
					continue
				if (
					str(triangle.get("face_id", "")) == owner_face_id
					and distance <= SURFACE_EPSILON * 4.0
				):
					continue
				nearest = distance
				nearest_triangle = triangle
			continue
		var left: int = int(node.get("left", -1))
		var right: int = int(node.get("right", -1))
		if right >= 0:
			stack.append(right)
		if left >= 0:
			stack.append(left)
	if nearest_triangle.is_empty():
		return {}
	return {
		"distance": nearest,
		"triangle_id": nearest_triangle.get("triangle_id", ""),
		"face_id": nearest_triangle.get("face_id", ""),
	}


func _build_node(indices: Array[int]) -> int:
	if indices.is_empty():
		return -1
	var minimum: Vector3 = _triangles[indices[0]].get("minimum", Vector3.ZERO)
	var maximum: Vector3 = _triangles[indices[0]].get("maximum", Vector3.ZERO)
	var centroid_min: Vector3 = _triangles[indices[0]].get(
		"centroid", Vector3.ZERO
	)
	var centroid_max: Vector3 = centroid_min
	for index: int in indices:
		var triangle: Dictionary = _triangles[index]
		minimum = minimum.min(triangle.get("minimum", minimum))
		maximum = maximum.max(triangle.get("maximum", maximum))
		var centroid: Vector3 = triangle.get("centroid", Vector3.ZERO)
		centroid_min = centroid_min.min(centroid)
		centroid_max = centroid_max.max(centroid)

	var node_index: int = _nodes.size()
	_nodes.append({
		"minimum": minimum - Vector3.ONE * SURFACE_EPSILON,
		"maximum": maximum + Vector3.ONE * SURFACE_EPSILON,
		"left": -1,
		"right": -1,
		"triangle_indices": [],
	})
	if indices.size() <= LEAF_TRIANGLE_LIMIT:
		_nodes[node_index]["triangle_indices"] = indices.duplicate()
		return node_index

	var extent: Vector3 = centroid_max - centroid_min
	var axis: int = 0
	if extent.y > extent.x and extent.y >= extent.z:
		axis = 1
	elif extent.z > extent.x and extent.z > extent.y:
		axis = 2
	_sort_indices_by_axis(indices, axis)
	var middle: int = indices.size() / 2
	if middle <= 0 or middle >= indices.size():
		_nodes[node_index]["triangle_indices"] = indices.duplicate()
		return node_index
	var left_indices: Array[int] = indices.slice(0, middle)
	var right_indices: Array[int] = indices.slice(middle, indices.size())
	_nodes[node_index]["left"] = _build_node(left_indices)
	_nodes[node_index]["right"] = _build_node(right_indices)
	return node_index


func _sort_indices_by_axis(indices: Array[int], axis: int) -> void:
	for outer: int in range(1, indices.size()):
		var value: int = indices[outer]
		var cursor: int = outer - 1
		while cursor >= 0 and _triangle_axis_less(value, indices[cursor], axis):
			indices[cursor + 1] = indices[cursor]
			cursor -= 1
		indices[cursor + 1] = value


func _triangle_axis_less(a_index: int, b_index: int, axis: int) -> bool:
	var a: Dictionary = _triangles[a_index]
	var b: Dictionary = _triangles[b_index]
	var a_centroid: Vector3 = a.get("centroid", Vector3.ZERO)
	var b_centroid: Vector3 = b.get("centroid", Vector3.ZERO)
	var a_value: float = a_centroid[axis]
	var b_value: float = b_centroid[axis]
	if not is_equal_approx(a_value, b_value):
		return a_value < b_value
	return str(a.get("triangle_id", "")) < str(b.get("triangle_id", ""))


static func _ray_hits_aabb(
	origin: Vector3,
	direction: Vector3,
	minimum: Vector3,
	maximum: Vector3,
	max_distance: float
) -> bool:
	var t_min: float = 0.0
	var t_max: float = max_distance
	for axis: int in 3:
		var origin_axis: float = origin[axis]
		var direction_axis: float = direction[axis]
		var min_axis: float = minimum[axis]
		var max_axis: float = maximum[axis]
		if absf(direction_axis) <= RAY_EPSILON:
			if origin_axis < min_axis or origin_axis > max_axis:
				return false
			continue
		var inverse: float = 1.0 / direction_axis
		var t1: float = (min_axis - origin_axis) * inverse
		var t2: float = (max_axis - origin_axis) * inverse
		if t1 > t2:
			var swap: float = t1
			t1 = t2
			t2 = swap
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_max < t_min:
			return false
	return t_max >= 0.0 and t_min <= max_distance


static func _ray_triangle_distance(
	origin: Vector3,
	direction: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> float:
	var edge1: Vector3 = b - a
	var edge2: Vector3 = c - a
	var p: Vector3 = direction.cross(edge2)
	var determinant: float = edge1.dot(p)
	if absf(determinant) <= RAY_EPSILON:
		return -1.0
	var inverse: float = 1.0 / determinant
	var t: Vector3 = origin - a
	var u: float = t.dot(p) * inverse
	if u < -RAY_EPSILON or u > 1.0 + RAY_EPSILON:
		return -1.0
	var q: Vector3 = t.cross(edge1)
	var v: float = direction.dot(q) * inverse
	if v < -RAY_EPSILON or u + v > 1.0 + RAY_EPSILON:
		return -1.0
	var distance: float = edge2.dot(q) * inverse
	return distance if distance > RAY_EPSILON else -1.0


static func _face_local_to_world(face: Dictionary, local: Vector2) -> Vector3:
	var origin: Vector3 = face.get("origin", Vector3.ZERO)
	var basis_u: Vector3 = face.get("basis_u", Vector3.RIGHT)
	var basis_v: Vector3 = face.get("basis_v", Vector3.UP)
	var projection_min: Vector2 = face.get("projection_min", Vector2.ZERO)
	return (
		origin
		+ basis_u * (projection_min.x + local.x)
		+ basis_v * (projection_min.y + local.y)
	)


static func _triangle_id(
	face_id: String,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> String:
	var vertices := PackedStringArray([
		_vector3_text(a),
		_vector3_text(b),
		_vector3_text(c),
	])
	vertices.sort()
	return _hash_text("%s|%s" % [face_id, ";".join(vertices)])


static func _sort_triangles(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("triangle_id", "")) < str(b.get("triangle_id", ""))


static func _vector3_text(value: Vector3) -> String:
	return "%.6f,%.6f,%.6f" % [value.x, value.y, value.z]


static func _hash_text(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()
