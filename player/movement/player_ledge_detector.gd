class_name PlayerLedgeDetector
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const MIN_LEDGE_TOP_UP_DOT: float = 0.001
const PLANE_INTERSECTION_MIN_SINE_SQUARED: float = 0.00000001
const EDGE_TOP_SAMPLE_INSET_MARGIN_MULTIPLIER: float = 1.0

const FORWARD_REACH_RADIUS_MULTIPLIER: float = 2.0
const HAND_REACH_HEIGHT_RATIO: float = 0.25
const HANG_EDGE_ABOVE_EYE_RADIUS_RATIO: float = 0.25
const TOP_PROBE_INSET_RADIUS_RATIO: float = 0.32
const EDGE_EXPOSURE_HEIGHT_RADIUS_RATIO: float = 0.03
const MAX_CATCH_FALL_SPEED_JUMP_SPEED_MULTIPLIER: float = 2.0
const SHIMMY_MAX_WALL_TURN_DEGREES: float = 15.0
const SHIMMY_LEVEL_HEIGHT_RADIUS_RATIO: float = 0.05
const SHIMMY_ATTACHMENT_CORRECTION_RADIUS_RATIO: float = 0.1
const LEDGE_SPAN_HALF_WIDTH_RADIUS_RATIO: float = 0.75
const EXPECTED_HANG_WALL_MIN_ALIGNMENT: float = 0.9
const EXPECTED_HANG_WALL_PLANE_TOLERANCE_RADIUS_RATIO: float = 0.25
const DISCOVERY_HEIGHT_SAMPLE_COUNT: int = 12
const DISCOVERY_LOCAL_BAND_OVERLAP: float = 0.75


class LedgeGeometry:
	var edge_point: Vector3 = Vector3.ZERO
	var wall_normal: Vector3 = Vector3.ZERO
	var top_normal: Vector3 = Vector3.UP
	var ledge_direction: Vector3 = Vector3.ZERO


class LedgeCandidate:
	var wall_collider_rid: RID = RID()
	var wall_shape_index: int = -1
	var top_collider_rid: RID = RID()
	var top_shape_index: int = -1

	var edge_point: Vector3 = Vector3.ZERO
	var wall_normal: Vector3 = Vector3.ZERO
	# This is the inward top probe sample, not the physical wall/top edge.
	var top_point: Vector3 = Vector3.ZERO
	var top_normal: Vector3 = Vector3.UP
	var ledge_direction: Vector3 = Vector3.ZERO
	var hang_position: Vector3 = Vector3.ZERO
	var hangable: bool = false


class WallHit:
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.ZERO
	var collider_rid: RID = RID()
	var shape_index: int = -1


class TopHit:
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var collider_rid: RID = RID()
	var shape_index: int = -1


var jump_height: float
var gravity: float
var max_step_height: float
var eye_height: float
var max_wall_tilt_degrees: float
var max_ledge_line_tilt_degrees: float
var max_approach_angle_degrees: float
var debug_logging: bool
var collision_shape: CollisionShape3D

var capsule_shape: CapsuleShape3D
var capsule_radius: float
var capsule_height: float
var capsule_bottom_offset: float
var capsule_top_offset: float
var forward_probe_distance: float
var max_horizontal_reach: float
var min_edge_height: float
var max_catch_height: float
var hand_reach_height: float
var hang_anchor_height: float
var hang_wall_distance: float
var top_probe_inset: float
var edge_top_sample_inset: float
var max_top_sample_height_offset: float
var shimmy_level_tolerance: float
var shimmy_attachment_correction_limit: float
var ledge_span_half_width: float
var max_catch_fall_speed: float
var minimum_approach_alignment: float
var maximum_wall_normal_y: float
var minimum_ledge_line_horizontal_factor: float
var minimum_shimmy_wall_alignment: float

var ray_query: PhysicsRayQueryParameters3D = null
var ray_query_player_rid: RID = RID()

var current_candidate: LedgeCandidate = null
var current_candidates: Array[LedgeCandidate] = []


func _init(
	p_jump_height: float,
	p_gravity: float,
	p_max_step_height: float,
	p_eye_height: float,
	p_max_wall_tilt_degrees: float,
	p_max_ledge_line_tilt_degrees: float,
	p_max_approach_angle_degrees: float,
	p_debug_logging: bool,
	p_collision_shape: CollisionShape3D
) -> void:
	jump_height = p_jump_height
	gravity = p_gravity
	max_step_height = p_max_step_height
	eye_height = p_eye_height
	max_wall_tilt_degrees = p_max_wall_tilt_degrees
	max_ledge_line_tilt_degrees = p_max_ledge_line_tilt_degrees
	max_approach_angle_degrees = p_max_approach_angle_degrees
	debug_logging = p_debug_logging
	collision_shape = p_collision_shape

	assert(jump_height >= 0.0, "PlayerLedgeDetector requires jump_height to be non-negative.")
	assert(gravity > 0.0, "PlayerLedgeDetector requires gravity to be greater than zero.")
	assert(max_step_height >= 0.0, "PlayerLedgeDetector requires max_step_height to be non-negative.")
	assert(eye_height >= 0.0, "PlayerLedgeDetector requires eye_height to be non-negative.")
	assert(max_wall_tilt_degrees >= 0.0, "PlayerLedgeDetector requires max_wall_tilt_degrees to be non-negative.")
	assert(max_ledge_line_tilt_degrees >= 0.0, "PlayerLedgeDetector requires max_ledge_line_tilt_degrees to be non-negative.")
	assert(max_ledge_line_tilt_degrees < 90.0, "PlayerLedgeDetector requires max_ledge_line_tilt_degrees to be less than 90 degrees.")
	assert(max_approach_angle_degrees >= 0.0, "PlayerLedgeDetector requires max_approach_angle_degrees to be non-negative.")

	var shape: Shape3D = collision_shape.shape
	assert(shape is CapsuleShape3D, "PlayerLedgeDetector requires the player collision shape to be CapsuleShape3D.")
	capsule_shape = shape as CapsuleShape3D
	_cache_static_values()


func _cache_static_values() -> void:
	capsule_radius = capsule_shape.radius
	capsule_height = capsule_shape.height
	capsule_bottom_offset = collision_shape.position.y - capsule_height * 0.5
	capsule_top_offset = collision_shape.position.y + capsule_height * 0.5
	forward_probe_distance = capsule_radius * FORWARD_REACH_RADIUS_MULTIPLIER
	max_horizontal_reach = capsule_radius + forward_probe_distance
	hand_reach_height = capsule_height * HAND_REACH_HEIGHT_RATIO
	min_edge_height = capsule_bottom_offset + max_step_height
	max_catch_height = capsule_top_offset + hand_reach_height
	hang_anchor_height = eye_height + capsule_radius * HANG_EDGE_ABOVE_EYE_RADIUS_RATIO
	hang_wall_distance = capsule_radius + PROBE_SAFE_MARGIN
	top_probe_inset = capsule_radius * TOP_PROBE_INSET_RADIUS_RATIO
	edge_top_sample_inset = PROBE_SAFE_MARGIN * EDGE_TOP_SAMPLE_INSET_MARGIN_MULTIPLIER
	var maximum_top_horizontal_ratio: float = sqrt(
		maxf(0.0, 1.0 - MIN_LEDGE_TOP_UP_DOT * MIN_LEDGE_TOP_UP_DOT)
	) / MIN_LEDGE_TOP_UP_DOT
	max_top_sample_height_offset = edge_top_sample_inset * maximum_top_horizontal_ratio
	shimmy_level_tolerance = maxf(PROBE_SAFE_MARGIN, capsule_radius * SHIMMY_LEVEL_HEIGHT_RADIUS_RATIO)
	shimmy_attachment_correction_limit = maxf(PROBE_SAFE_MARGIN, capsule_radius * SHIMMY_ATTACHMENT_CORRECTION_RADIUS_RATIO)
	ledge_span_half_width = capsule_radius * LEDGE_SPAN_HALF_WIDTH_RADIUS_RATIO

	var jump_speed: float = sqrt(2.0 * gravity * maxf(jump_height, 0.0))
	max_catch_fall_speed = jump_speed * MAX_CATCH_FALL_SPEED_JUMP_SPEED_MULTIPLIER
	minimum_approach_alignment = cos(deg_to_rad(max_approach_angle_degrees))
	maximum_wall_normal_y = sin(deg_to_rad(max_wall_tilt_degrees))
	minimum_ledge_line_horizontal_factor = cos(deg_to_rad(max_ledge_line_tilt_degrees))
	minimum_shimmy_wall_alignment = cos(deg_to_rad(SHIMMY_MAX_WALL_TURN_DEGREES))


func update(
	player: CharacterBody3D,
	support: PlayerSupport,
	detection_allowed: bool,
	intent_direction: Vector3,
	view_forward: Vector3
) -> void:
	var previously_had_candidate: bool = current_candidate != null
	var next_candidates: Array[LedgeCandidate] = []

	if detection_allowed and player.velocity.y >= -get_max_catch_fall_speed():
		next_candidates = find_candidates(
			player,
			support,
			intent_direction,
			view_forward
		)

	current_candidates = next_candidates
	current_candidate = null
	if not current_candidates.is_empty():
		current_candidate = current_candidates[0]
	update_debug_logging(previously_had_candidate)


func has_candidate() -> bool:
	return current_candidate != null


func get_candidate() -> LedgeCandidate:
	return current_candidate


func get_candidates() -> Array[LedgeCandidate]:
	return current_candidates


func clear_candidate() -> void:
	current_candidate = null
	current_candidates.clear()


func find_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	intent_direction: Vector3,
	view_forward: Vector3
) -> LedgeCandidate:
	var candidates: Array[LedgeCandidate] = find_candidates(
		player,
		support,
		intent_direction,
		view_forward
	)
	if candidates.is_empty():
		return null
	return candidates[0]


func find_candidates(
	player: CharacterBody3D,
	support: PlayerSupport,
	intent_direction: Vector3,
	view_forward: Vector3
) -> Array[LedgeCandidate]:
	var results: Array[LedgeCandidate] = []
	var horizontal_intent := Vector3(intent_direction.x, 0.0, intent_direction.z)
	var approach_direction := Vector3.ZERO

	if horizontal_intent.length_squared() > MOTION_EPSILON_SQUARED:
		approach_direction = horizontal_intent.normalized()
	else:
		var horizontal_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
		if horizontal_velocity.length_squared() > MOTION_EPSILON_SQUARED:
			approach_direction = horizontal_velocity.normalized()
		else:
			var horizontal_view := Vector3(view_forward.x, 0.0, view_forward.z)
			if horizontal_view.length_squared() <= MOTION_EPSILON_SQUARED:
				return results
			approach_direction = horizontal_view.normalized()

	var wall_hit: WallHit = find_wall(player, approach_direction)
	if wall_hit == null:
		return results
	if not has_catch_intent(wall_hit.normal, intent_direction, view_forward):
		return results

	# Preserve the existing broad discovery as the first-ranked opportunity.
	# Additional local height bands enumerate other exposed ledges on the same
	# reachable wall region so rejecting one candidate never hides another.
	var broad_top: TopHit = find_top(player, support, wall_hit)
	if broad_top != null:
		_add_unique_discovery_candidate(
			results,
			build_reachable_candidate(player, support, wall_hit, broad_top)
		)

	var minimum_edge_y: float = player.global_position.y + get_min_edge_height()
	var maximum_edge_y: float = player.global_position.y + get_max_catch_height()
	var height_range: float = maximum_edge_y - minimum_edge_y
	if height_range <= PROBE_SAFE_MARGIN:
		return results

	var sample_step: float = height_range / float(DISCOVERY_HEIGHT_SAMPLE_COUNT)
	var band_half_height: float = maxf(
		PROBE_SAFE_MARGIN * 4.0,
		sample_step * DISCOVERY_LOCAL_BAND_OVERLAP
	)
	for sample_index: int in range(DISCOVERY_HEIGHT_SAMPLE_COUNT + 1):
		var expected_edge_y: float = maximum_edge_y - sample_step * float(sample_index)
		var wall_seed := Vector3(
			wall_hit.point.x,
			expected_edge_y,
			wall_hit.point.z
		)
		var local_wall: WallHit = find_wall_at_height(
			player,
			wall_hit.normal,
			wall_seed
		)
		if local_wall == null:
			continue

		var local_top: TopHit = find_top_in_height_band(
			player,
			support,
			local_wall,
			expected_edge_y,
			band_half_height
		)
		if local_top == null:
			continue

		_add_unique_discovery_candidate(
			results,
			build_reachable_candidate(player, support, local_wall, local_top)
		)

	_sort_discovery_candidates(results)
	return results


func build_reachable_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	wall_hit: WallHit,
	top_hit: TopHit
) -> LedgeCandidate:
	if wall_hit == null or top_hit == null:
		return null

	var provisional_geometry: LedgeGeometry = build_ledge_geometry(wall_hit, top_hit)
	if provisional_geometry == null:
		return null

	var near_edge_wall: WallHit = find_wall_near_edge(
		player,
		wall_hit.normal,
		provisional_geometry.edge_point
	)
	if (
		near_edge_wall == null
		or not is_wall_continuous(
			near_edge_wall,
			wall_hit.normal,
			provisional_geometry.edge_point
		)
	):
		return null

	var candidate: LedgeCandidate = build_ledge_candidate(
		player,
		near_edge_wall,
		top_hit
	)
	if candidate == null:
		return null

	var edge_offset: Vector3 = candidate.edge_point - player.global_position
	var horizontal_edge_offset := Vector3(edge_offset.x, 0.0, edge_offset.z)
	var horizontal_reach_limit: float = get_max_horizontal_reach() + PROBE_SAFE_MARGIN
	if horizontal_edge_offset.length_squared() > horizontal_reach_limit * horizontal_reach_limit:
		return null

	var relative_height: float = candidate.edge_point.y - player.global_position.y
	if relative_height < get_min_edge_height() - PROBE_SAFE_MARGIN:
		return null
	if relative_height > get_max_catch_height() + PROBE_SAFE_MARGIN:
		return null

	if has_usable_ledge_span(player, support, candidate):
		candidate.hangable = is_hang_pose_valid(
			player,
			candidate,
			candidate.hang_position
		)
	return candidate


func _add_unique_discovery_candidate(
	results: Array[LedgeCandidate],
	candidate: LedgeCandidate
) -> void:
	if candidate == null:
		return
	for existing: LedgeCandidate in results:
		if is_same_ledge_path(
			candidate,
			existing,
			get_capsule_radius()
		):
			return
	results.append(candidate)


func _sort_discovery_candidates(results: Array[LedgeCandidate]) -> void:
	# Preserve the old topmost-first behavior while allowing policy to skip a
	# rejected candidate and continue to lower opportunities.
	for candidate_index: int in range(1, results.size()):
		var candidate: LedgeCandidate = results[candidate_index]
		var insertion_index: int = candidate_index
		while (
			insertion_index > 0
			and results[insertion_index - 1].edge_point.y < candidate.edge_point.y
		):
			results[insertion_index] = results[insertion_index - 1]
			insertion_index -= 1
		results[insertion_index] = candidate


func find_attachment_candidate_at_position(
	player: CharacterBody3D,
	support: PlayerSupport,
	reference_candidate: LedgeCandidate,
	segment_wall_normal: Vector3,
	proposed_hang_position: Vector3
) -> LedgeCandidate:
	if reference_candidate == null:
		return null

	var fixed_wall_normal := Vector3(
		segment_wall_normal.x,
		0.0,
		segment_wall_normal.z
	)
	if fixed_wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	fixed_wall_normal = fixed_wall_normal.normalized()

	var expected_edge_point: Vector3 = (
		proposed_hang_position
		- fixed_wall_normal * get_hang_wall_distance()
	)
	expected_edge_point.y = proposed_hang_position.y + get_hang_anchor_height()

	var candidate: LedgeCandidate = find_tracked_candidate_at_edge(
		player,
		support,
		reference_candidate,
		fixed_wall_normal,
		expected_edge_point,
		get_capsule_radius()
	)
	if candidate == null:
		return null

	var attachment_correction: Vector3 = candidate.hang_position - proposed_hang_position
	var correction_limit: float = get_shimmy_attachment_correction_limit()
	if attachment_correction.length_squared() > correction_limit * correction_limit:
		return null

	candidate.hangable = is_hang_pose_valid(
		player,
		candidate,
		candidate.hang_position
	)
	if not candidate.hangable:
		return null
	return candidate


func find_tracked_candidate_at_edge(
	player: CharacterBody3D,
	support: PlayerSupport,
	reference_candidate: LedgeCandidate,
	expected_wall_normal: Vector3,
	expected_edge_point: Vector3,
	horizontal_limit: float
) -> LedgeCandidate:
	if reference_candidate == null or horizontal_limit < 0.0:
		return null

	var fixed_wall_normal := Vector3(
		expected_wall_normal.x,
		0.0,
		expected_wall_normal.z
	)
	if fixed_wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	fixed_wall_normal = fixed_wall_normal.normalized()

	var wall_hit: WallHit = find_wall_near_edge(
		player,
		fixed_wall_normal,
		expected_edge_point
	)
	if (
		wall_hit == null
		or not is_wall_continuous(
			wall_hit,
			fixed_wall_normal,
			expected_edge_point
		)
	):
		return null

	var top_hit: TopHit = find_tracked_top(
		player,
		support,
		reference_candidate,
		wall_hit,
		expected_edge_point
	)
	if top_hit == null:
		return null

	var candidate: LedgeCandidate = build_ledge_candidate(
		player,
		wall_hit,
		top_hit
	)
	if candidate == null:
		return null

	var correction_limit: float = (
		get_shimmy_attachment_correction_limit()
		+ PROBE_SAFE_MARGIN
	)
	if candidate.edge_point.distance_to(expected_edge_point) > correction_limit:
		return null
	if not is_same_ledge_path(
		candidate,
		reference_candidate,
		horizontal_limit
	):
		return null
	return candidate


func find_tracked_top(
	player: CharacterBody3D,
	support: PlayerSupport,
	reference_candidate: LedgeCandidate,
	wall_hit: WallHit,
	expected_edge_point: Vector3
) -> TopHit:
	if reference_candidate == null or wall_hit == null:
		return null

	var top_normal: Vector3 = reference_candidate.top_normal
	if top_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	top_normal = top_normal.normalized()
	if not is_ledge_top_surface(top_normal):
		return null

	var inward_direction: Vector3 = get_top_inward_direction(
		wall_hit.normal,
		top_normal
	)
	if inward_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var local_probe_distance: float = maxf(
		PROBE_SAFE_MARGIN * 4.0,
		get_shimmy_attachment_correction_limit()
	)
	var expected_top_sample: Vector3 = (
		expected_edge_point
		+ inward_direction * local_probe_distance
	)
	return raycast_top(
		player,
		support,
		expected_top_sample + top_normal * local_probe_distance,
		expected_top_sample - top_normal * local_probe_distance
	)


func find_hang_candidate_at_position(
	player: CharacterBody3D,
	support: PlayerSupport,
	reference_candidate: LedgeCandidate,
	segment_wall_normal: Vector3,
	proposed_hang_position: Vector3
) -> LedgeCandidate:
	var candidate: LedgeCandidate = find_attachment_candidate_at_position(
		player,
		support,
		reference_candidate,
		segment_wall_normal,
		proposed_hang_position
	)
	if candidate == null:
		return null
	if not has_usable_ledge_span(player, support, candidate):
		return null
	return candidate


func find_local_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	expected_wall_normal: Vector3,
	edge_hint: Vector3,
	height_window: float,
	require_span: bool,
	require_hang_pose: bool
) -> LedgeCandidate:
	if height_window <= 0.0:
		return null

	var expected_normal := Vector3(
		expected_wall_normal.x,
		0.0,
		expected_wall_normal.z
	)
	if expected_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	expected_normal = expected_normal.normalized()

	# This is discovery, not tracking: target height is unknown, so a broad
	# ledge-top search is intentional here.
	var top_probe_center: Vector3 = (
		edge_hint
		- expected_normal * get_edge_top_sample_inset()
	)
	top_probe_center.y = edge_hint.y
	var top_search_half_height: float = (
		height_window + get_max_top_sample_height_offset()
	)
	var top_hit: TopHit = raycast_top(
		player,
		support,
		top_probe_center + Vector3.UP * top_search_half_height,
		top_probe_center - Vector3.UP * top_search_half_height
	)
	if top_hit == null:
		return null

	var expected_wall := WallHit.new()
	expected_wall.point = edge_hint
	expected_wall.normal = expected_normal
	var provisional_geometry: LedgeGeometry = build_ledge_geometry(
		expected_wall,
		top_hit
	)
	if provisional_geometry == null:
		return null

	var wall_hit: WallHit = find_wall_near_edge(
		player,
		expected_normal,
		provisional_geometry.edge_point
	)
	if wall_hit == null:
		return null
	if wall_hit.normal.dot(expected_normal) < minimum_shimmy_wall_alignment:
		return null

	var candidate: LedgeCandidate = build_ledge_candidate(
		player,
		wall_hit,
		top_hit
	)
	if candidate == null:
		return null

	if require_span and not has_usable_ledge_span(
		player,
		support,
		candidate
	):
		return null

	if require_hang_pose:
		candidate.hangable = is_hang_pose_valid(
			player,
			candidate,
			candidate.hang_position
		)
		if not candidate.hangable:
			return null
	return candidate


func is_same_attachment_region(candidate: LedgeCandidate, reference_candidate: LedgeCandidate) -> bool:
	return is_same_ledge_path(candidate, reference_candidate, get_capsule_radius())


func is_same_ledge_path(
	candidate: LedgeCandidate,
	reference_candidate: LedgeCandidate,
	horizontal_limit: float
) -> bool:
	if candidate == null or reference_candidate == null or horizontal_limit < 0.0:
		return false

	var candidate_normal := Vector3(candidate.wall_normal.x, 0.0, candidate.wall_normal.z)
	var reference_normal := Vector3(reference_candidate.wall_normal.x, 0.0, reference_candidate.wall_normal.z)
	if (
		candidate_normal.length_squared() <= MOTION_EPSILON_SQUARED
		or reference_normal.length_squared() <= MOTION_EPSILON_SQUARED
	):
		return false
	candidate_normal = candidate_normal.normalized()
	reference_normal = reference_normal.normalized()
	if candidate_normal.dot(reference_normal) < minimum_shimmy_wall_alignment:
		return false

	var candidate_direction: Vector3 = candidate.ledge_direction
	var reference_direction: Vector3 = reference_candidate.ledge_direction
	if candidate_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		candidate_direction = get_ledge_direction(candidate.wall_normal, candidate.top_normal)
	if reference_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		reference_direction = get_ledge_direction(reference_candidate.wall_normal, reference_candidate.top_normal)
	if (
		candidate_direction.length_squared() <= MOTION_EPSILON_SQUARED
		or reference_direction.length_squared() <= MOTION_EPSILON_SQUARED
	):
		return false
	candidate_direction = candidate_direction.normalized()
	reference_direction = reference_direction.normalized()
	if candidate_direction.dot(reference_direction) < minimum_shimmy_wall_alignment:
		return false

	var edge_delta: Vector3 = candidate.edge_point - reference_candidate.edge_point
	var plane_distance: float = absf(edge_delta.dot(reference_normal))
	if plane_distance > get_expected_local_wall_plane_tolerance():
		return false

	var horizontal_direction := Vector3(reference_direction.x, 0.0, reference_direction.z)
	var horizontal_factor: float = horizontal_direction.length()
	if horizontal_factor <= 0.000001:
		return false
	horizontal_direction /= horizontal_factor

	var horizontal_delta := Vector3(edge_delta.x, 0.0, edge_delta.z)
	var along_distance: float = horizontal_delta.dot(horizontal_direction)
	if absf(along_distance) > horizontal_limit:
		return false

	var cross_track: Vector3 = horizontal_delta - horizontal_direction * along_distance
	if cross_track.length() > get_expected_local_wall_plane_tolerance():
		return false

	var expected_vertical_delta: float = (
		reference_direction.y
		/ horizontal_factor
		* along_distance
	)
	return absf(edge_delta.y - expected_vertical_delta) <= get_shimmy_level_tolerance()


func find_wall(player: CharacterBody3D, approach_direction: Vector3) -> WallHit:
	var collision := KinematicCollision3D.new()
	var blocked: bool = player.test_move(
		player.global_transform,
		approach_direction * get_forward_probe_distance(),
		collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)
	if not blocked:
		return null

	var best_push_strength: float = minimum_approach_alignment
	var best_collision_index: int = -1
	var collision_count: int = collision.get_collision_count()
	for collision_index: int in range(collision_count):
		var collision_normal: Vector3 = collision.get_normal(collision_index)
		if not is_wall_surface(collision_normal):
			continue
		var horizontal_normal := Vector3(collision_normal.x, 0.0, collision_normal.z)
		if horizontal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
			continue
		horizontal_normal = horizontal_normal.normalized()
		var push_strength: float = -approach_direction.dot(horizontal_normal)
		if push_strength < best_push_strength:
			continue
		best_push_strength = push_strength
		best_collision_index = collision_index

	if best_collision_index < 0:
		return null
	var best_normal: Vector3 = collision.get_normal(best_collision_index)
	best_normal.y = 0.0
	best_normal = best_normal.normalized()
	var best_hit := WallHit.new()
	best_hit.point = collision.get_position(best_collision_index)
	best_hit.normal = best_normal
	best_hit.collider_rid = collision.get_collider_rid(best_collision_index)
	best_hit.shape_index = collision.get_collider_shape_index(best_collision_index)
	return best_hit


func find_wall_at_height(
	player: CharacterBody3D,
	expected_wall_normal: Vector3,
	edge_seed: Vector3
) -> WallHit:
	var expected_normal := Vector3(
		expected_wall_normal.x,
		0.0,
		expected_wall_normal.z
	)
	if expected_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	expected_normal = expected_normal.normalized()

	var probe_y: float = edge_seed.y - get_capsule_radius() * 0.5
	var ray_from: Vector3 = (
		edge_seed
		+ expected_normal * (get_hang_wall_distance() + get_top_probe_inset())
	)
	ray_from.y = probe_y
	var ray_to: Vector3 = edge_seed - expected_normal * get_max_horizontal_reach()
	ray_to.y = probe_y
	var query := _prepare_ray_query(player, ray_from, ray_to)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var position_value: Variant = hit.get("position")
	var normal_value: Variant = hit.get("normal")
	var rid_value: Variant = hit.get("rid")
	var shape_value: Variant = hit.get("shape")
	if not (position_value is Vector3) or not (normal_value is Vector3):
		return null

	var collision_normal: Vector3 = normal_value
	if not is_wall_surface(collision_normal):
		return null
	var horizontal_normal := Vector3(
		collision_normal.x,
		0.0,
		collision_normal.z
	)
	if horizontal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	horizontal_normal = horizontal_normal.normalized()
	if horizontal_normal.dot(expected_normal) < minimum_shimmy_wall_alignment:
		return null

	var wall_hit := WallHit.new()
	wall_hit.point = position_value
	wall_hit.normal = horizontal_normal
	if rid_value is RID:
		wall_hit.collider_rid = rid_value
	if shape_value is int:
		wall_hit.shape_index = shape_value
	return wall_hit


func find_wall_near_edge(
	player: CharacterBody3D,
	expected_wall_normal: Vector3,
	expected_edge_point: Vector3
) -> WallHit:
	var ray_from: Vector3 = expected_edge_point + expected_wall_normal * (get_hang_wall_distance() + get_top_probe_inset())
	ray_from.y = expected_edge_point.y - get_capsule_radius() * 0.5
	var ray_to: Vector3 = expected_edge_point - expected_wall_normal * get_top_probe_inset()
	ray_to.y = ray_from.y
	var query := _prepare_ray_query(player, ray_from, ray_to)
	var space_state := player.get_world_3d().direct_space_state
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var position_value: Variant = hit.get("position")
	var normal_value: Variant = hit.get("normal")
	var rid_value: Variant = hit.get("rid")
	var shape_value: Variant = hit.get("shape")
	if not (position_value is Vector3) or not (normal_value is Vector3):
		return null

	var collision_normal: Vector3 = normal_value
	if not is_wall_surface(collision_normal):
		return null
	var horizontal_normal := Vector3(collision_normal.x, 0.0, collision_normal.z)
	if horizontal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	horizontal_normal = horizontal_normal.normalized()

	var wall_hit := WallHit.new()
	wall_hit.point = position_value
	wall_hit.normal = horizontal_normal
	if rid_value is RID:
		wall_hit.collider_rid = rid_value
	if shape_value is int:
		wall_hit.shape_index = shape_value
	return wall_hit


func find_top(player: CharacterBody3D, support: PlayerSupport, wall_hit: WallHit) -> TopHit:
	var ray_from: Vector3 = wall_hit.point - wall_hit.normal * get_edge_top_sample_inset()
	ray_from.y = (
		player.global_position.y
		+ get_max_catch_height()
		+ get_max_top_sample_height_offset()
		+ PROBE_SAFE_MARGIN
	)
	var ray_to: Vector3 = ray_from
	ray_to.y = (
		player.global_position.y
		+ get_min_edge_height()
		- get_max_top_sample_height_offset()
		- PROBE_SAFE_MARGIN
	)
	return raycast_top(player, support, ray_from, ray_to)


func find_top_in_height_band(
	player: CharacterBody3D,
	support: PlayerSupport,
	wall_hit: WallHit,
	expected_edge_y: float,
	half_height: float
) -> TopHit:
	if wall_hit == null or half_height <= 0.0:
		return null
	var probe_center: Vector3 = (
		wall_hit.point
		- wall_hit.normal * get_edge_top_sample_inset()
	)
	probe_center.y = expected_edge_y
	return raycast_top(
		player,
		support,
		probe_center + Vector3.UP * half_height,
		probe_center - Vector3.UP * half_height
	)


func find_top_for_hang(
	player: CharacterBody3D,
	support: PlayerSupport,
	wall_hit: WallHit,
	expected_edge_height: float
) -> TopHit:
	var probe_center: Vector3 = wall_hit.point - wall_hit.normal * get_edge_top_sample_inset()
	probe_center.y = expected_edge_height
	var half_height: float = get_capsule_radius() + get_max_top_sample_height_offset()
	var ray_from: Vector3 = probe_center + Vector3.UP * half_height
	var ray_to: Vector3 = probe_center - Vector3.UP * half_height
	return raycast_top(player, support, ray_from, ray_to)


func find_top_near_wall(
	player: CharacterBody3D,
	support: PlayerSupport,
	wall_hit: WallHit,
	center_height: float,
	height_window: float
) -> TopHit:
	if wall_hit == null or height_window <= 0.0:
		return null
	var probe_center: Vector3 = wall_hit.point - wall_hit.normal * get_edge_top_sample_inset()
	probe_center.y = center_height
	var half_height: float = height_window + get_max_top_sample_height_offset()
	return raycast_top(
		player,
		support,
		probe_center + Vector3.UP * half_height,
		probe_center - Vector3.UP * half_height
	)


func raycast_top(
	player: CharacterBody3D,
	_support: PlayerSupport,
	ray_from: Vector3,
	ray_to: Vector3
) -> TopHit:
	var query := _prepare_ray_query(player, ray_from, ray_to)
	var space_state := player.get_world_3d().direct_space_state
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var position_value: Variant = hit.get("position")
	var normal_value: Variant = hit.get("normal")
	var rid_value: Variant = hit.get("rid")
	var shape_value: Variant = hit.get("shape")
	if not (position_value is Vector3) or not (normal_value is Vector3):
		return null

	var point: Vector3 = position_value
	var normal: Vector3 = normal_value
	if not is_ledge_top_surface(normal):
		return null
	normal = normal.normalized()

	var top_hit := TopHit.new()
	top_hit.point = point
	top_hit.normal = normal
	if rid_value is RID:
		top_hit.collider_rid = rid_value
	if shape_value is int:
		top_hit.shape_index = shape_value
	return top_hit


func build_ledge_geometry(
	wall_hit: WallHit,
	top_hit: TopHit
) -> LedgeGeometry:
	if wall_hit == null or top_hit == null:
		return null

	var wall_normal := Vector3(
		wall_hit.normal.x,
		0.0,
		wall_hit.normal.z
	)
	if wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	wall_normal = wall_normal.normalized()

	var top_normal: Vector3 = top_hit.normal
	if top_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	top_normal = top_normal.normalized()
	if not is_ledge_top_surface(top_normal):
		return null

	# Solve the local wall/top plane intersection without assuming the top has a
	# useful Y component. The correction stays in the span of the two normals,
	# so the reconstructed point remains on the sampled top plane while moving
	# onto the wall plane.
	var normal_dot: float = clampf(wall_normal.dot(top_normal), -1.0, 1.0)
	var intersection_sine_squared: float = 1.0 - normal_dot * normal_dot
	if intersection_sine_squared <= PLANE_INTERSECTION_MIN_SINE_SQUARED:
		return null
	var wall_plane_distance: float = (
		(top_hit.point - wall_hit.point).dot(wall_normal)
	)
	var edge_point: Vector3 = (
		top_hit.point
		- (wall_plane_distance / intersection_sine_squared)
		* (wall_normal - top_normal * normal_dot)
	)

	var ledge_direction: Vector3 = get_ledge_direction(
		wall_normal,
		top_normal
	)
	if ledge_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	if not is_ledge_line_tilt_allowed(ledge_direction):
		return null

	var geometry := LedgeGeometry.new()
	geometry.edge_point = edge_point
	geometry.wall_normal = wall_normal
	geometry.top_normal = top_normal
	geometry.ledge_direction = ledge_direction
	return geometry


func build_ledge_candidate(
	player: CharacterBody3D,
	wall_hit: WallHit,
	top_hit: TopHit,
	require_exposed: bool = true
) -> LedgeCandidate:
	var geometry: LedgeGeometry = build_ledge_geometry(wall_hit, top_hit)
	if geometry == null:
		return null
	if require_exposed and not is_edge_exposed(
		player,
		geometry.edge_point,
		geometry.wall_normal,
		geometry.top_normal
	):
		return null

	var candidate := LedgeCandidate.new()
	candidate.wall_collider_rid = wall_hit.collider_rid
	candidate.wall_shape_index = wall_hit.shape_index
	candidate.top_collider_rid = top_hit.collider_rid
	candidate.top_shape_index = top_hit.shape_index
	candidate.edge_point = geometry.edge_point
	candidate.wall_normal = geometry.wall_normal
	candidate.top_point = top_hit.point
	candidate.top_normal = geometry.top_normal
	candidate.ledge_direction = geometry.ledge_direction
	candidate.hang_position = get_hang_position(
		geometry.edge_point,
		geometry.wall_normal
	)
	return candidate


func is_edge_exposed(
	player: CharacterBody3D,
	edge_point: Vector3,
	wall_normal: Vector3,
	top_normal: Vector3 = Vector3.UP
) -> bool:
	if wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	var outward_normal: Vector3 = wall_normal.normalized()
	var exposure_distance: float = maxf(
		PROBE_SAFE_MARGIN * 4.0,
		get_capsule_radius() * EDGE_EXPOSURE_HEIGHT_RADIUS_RATIO
	)
	var surface_normal: Vector3 = top_normal
	if surface_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		surface_normal = Vector3.UP
	else:
		surface_normal = surface_normal.normalized()
	var exposure_offset: Vector3 = surface_normal * exposure_distance
	var probe_from: Vector3 = (
		edge_point
		+ outward_normal * get_top_probe_inset()
		+ exposure_offset
	)
	var probe_to: Vector3 = (
		edge_point
		- outward_normal * (PROBE_SAFE_MARGIN * 2.0)
		+ exposure_offset
	)
	var query := _prepare_ray_query(player, probe_from, probe_to)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _prepare_ray_query(
	player: CharacterBody3D,
	ray_from: Vector3,
	ray_to: Vector3
) -> PhysicsRayQueryParameters3D:
	var player_rid: RID = player.get_rid()
	if ray_query == null or ray_query_player_rid != player_rid:
		ray_query_player_rid = player_rid
		ray_query = PhysicsRayQueryParameters3D.create(ray_from, ray_to, player.collision_mask, [player_rid])
		ray_query.collide_with_areas = false
		ray_query.collide_with_bodies = true
		ray_query.hit_back_faces = false
		ray_query.hit_from_inside = false
		return ray_query
	ray_query.from = ray_from
	ray_query.to = ray_to
	ray_query.collision_mask = player.collision_mask
	return ray_query


func has_catch_intent(
	wall_normal: Vector3,
	intent_direction: Vector3,
	view_forward: Vector3
) -> bool:
	var toward_wall: Vector3 = -wall_normal
	var horizontal_intent := Vector3(intent_direction.x, 0.0, intent_direction.z)
	if horizontal_intent.length_squared() > MOTION_EPSILON_SQUARED:
		horizontal_intent = horizontal_intent.normalized()
		if horizontal_intent.dot(toward_wall) >= minimum_approach_alignment:
			return true

	var horizontal_view := Vector3(view_forward.x, 0.0, view_forward.z)
	if horizontal_view.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	horizontal_view = horizontal_view.normalized()
	return horizontal_view.dot(toward_wall) >= minimum_approach_alignment


func get_ledge_direction(wall_normal: Vector3, top_normal: Vector3) -> Vector3:
	var wall := Vector3(wall_normal.x, 0.0, wall_normal.z)
	if wall.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	wall = wall.normalized()

	var top: Vector3 = top_normal
	if top.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	top = top.normalized()

	var direction: Vector3 = top.cross(wall)
	if direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	direction = direction.normalized()

	var horizontal_reference: Vector3 = Vector3.UP.cross(wall)
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z)
	if (
		horizontal_reference.length_squared() <= MOTION_EPSILON_SQUARED
		or horizontal_direction.length_squared() <= MOTION_EPSILON_SQUARED
	):
		return Vector3.ZERO
	horizontal_reference = horizontal_reference.normalized()
	horizontal_direction = horizontal_direction.normalized()
	if horizontal_direction.dot(horizontal_reference) < 0.0:
		direction = -direction
	return direction


func get_top_inward_direction(
	wall_normal: Vector3,
	top_normal: Vector3
) -> Vector3:
	var wall := Vector3(wall_normal.x, 0.0, wall_normal.z)
	if wall.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	wall = wall.normalized()

	var top: Vector3 = top_normal
	if top.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	top = top.normalized()

	var inward_direction: Vector3 = (-wall).slide(top)
	if inward_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	inward_direction = inward_direction.normalized()

	var horizontal_inward := Vector3(
		inward_direction.x,
		0.0,
		inward_direction.z
	)
	if (
		horizontal_inward.length_squared() > MOTION_EPSILON_SQUARED
		and horizontal_inward.dot(-wall) < 0.0
	):
		inward_direction = -inward_direction
	return inward_direction


func is_ledge_top_surface(normal: Vector3) -> bool:
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	return normal.normalized().dot(Vector3.UP) >= MIN_LEDGE_TOP_UP_DOT


func is_ledge_line_tilt_allowed(direction: Vector3) -> bool:
	if direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	var normalized_direction: Vector3 = direction.normalized()
	var horizontal_factor: float = Vector3(
		normalized_direction.x,
		0.0,
		normalized_direction.z
	).length()
	return (
		horizontal_factor
		>= minimum_ledge_line_horizontal_factor - 0.00001
	)


func has_usable_ledge_span(
	player: CharacterBody3D,
	support: PlayerSupport,
	candidate: LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	var direction: Vector3 = candidate.ledge_direction
	if direction.length_squared() <= MOTION_EPSILON_SQUARED:
		direction = get_ledge_direction(
			candidate.wall_normal,
			candidate.top_normal
		)
	if direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	direction = direction.normalized()

	var horizontal_factor: float = Vector3(
		direction.x,
		0.0,
		direction.z
	).length()
	if horizontal_factor <= 0.000001:
		return false

	var path_distance: float = get_ledge_span_half_width() / horizontal_factor
	for direction_sign: float in [-1.0, 1.0]:
		var expected_edge_point: Vector3 = (
			candidate.edge_point
			+ direction * path_distance * direction_sign
		)
		var sample_candidate: LedgeCandidate = find_tracked_candidate_at_edge(
			player,
			support,
			candidate,
			candidate.wall_normal,
			expected_edge_point,
			get_ledge_span_half_width() + get_shimmy_attachment_correction_limit()
		)
		if sample_candidate == null:
			return false
	return true


func is_wall_continuous(
	wall_hit: WallHit,
	expected_wall_normal: Vector3,
	expected_edge_point: Vector3
) -> bool:
	if wall_hit.normal.dot(expected_wall_normal) < minimum_shimmy_wall_alignment:
		return false
	var plane_distance: float = absf((wall_hit.point - expected_edge_point).dot(expected_wall_normal))
	return plane_distance <= get_top_probe_inset() + PROBE_SAFE_MARGIN


func is_wall_surface(normal: Vector3) -> bool:
	return absf(normal.y) <= maximum_wall_normal_y


func get_hang_position(edge_point: Vector3, wall_normal: Vector3) -> Vector3:
	var hang_position: Vector3 = edge_point + wall_normal * get_hang_wall_distance()
	hang_position.y = edge_point.y - get_hang_anchor_height()
	return hang_position


func is_hang_pose_valid(
	player: CharacterBody3D,
	candidate: LedgeCandidate,
	hang_position: Vector3
) -> bool:
	if candidate == null:
		return false
	var hang_transform: Transform3D = player.global_transform
	hang_transform.origin = hang_position
	var collision := KinematicCollision3D.new()
	var has_contact: bool = player.test_move(
		hang_transform,
		Vector3.ZERO,
		collision,
		PROBE_SAFE_MARGIN,
		true,
		PROBE_MAX_COLLISIONS
	)
	if not has_contact:
		return true
	var collision_count: int = collision.get_collision_count()
	if collision_count <= 0:
		return false
	for collision_index: int in range(collision_count):
		if not is_expected_hang_wall_contact(collision, collision_index, candidate):
			return false
	return true


func is_expected_hang_wall_contact(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: LedgeCandidate
) -> bool:
	return is_expected_local_wall_contact(collision, collision_index, candidate, EXPECTED_HANG_WALL_MIN_ALIGNMENT)


func is_expected_local_wall_contact(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: LedgeCandidate,
	minimum_alignment: float = EXPECTED_HANG_WALL_MIN_ALIGNMENT
) -> bool:
	if candidate == null:
		return false
	var collision_normal: Vector3 = collision.get_normal(collision_index)
	if collision_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	collision_normal = collision_normal.normalized()

	var expected_wall_normal: Vector3 = candidate.wall_normal
	if expected_wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	expected_wall_normal = expected_wall_normal.normalized()
	if collision_normal.dot(expected_wall_normal) < minimum_alignment:
		return false

	var collision_point: Vector3 = collision.get_position(collision_index)
	var plane_distance: float = absf((collision_point - candidate.edge_point).dot(expected_wall_normal))
	if plane_distance > get_expected_local_wall_plane_tolerance():
		return false

	var ledge_direction: Vector3 = candidate.ledge_direction
	if ledge_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		ledge_direction = get_ledge_direction(candidate.wall_normal, candidate.top_normal)
	if ledge_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return false

	var horizontal_ledge := Vector3(ledge_direction.x, 0.0, ledge_direction.z)
	if horizontal_ledge.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	horizontal_ledge = horizontal_ledge.normalized()
	var point_delta: Vector3 = collision_point - candidate.edge_point
	var horizontal_delta := Vector3(point_delta.x, 0.0, point_delta.z)
	var lateral_distance: float = absf(horizontal_delta.dot(horizontal_ledge))
	return lateral_distance <= get_expected_local_wall_lateral_tolerance()


func get_forward_probe_distance() -> float:
	return forward_probe_distance

func get_max_horizontal_reach() -> float:
	return max_horizontal_reach

func get_min_edge_height() -> float:
	return min_edge_height

func get_max_catch_height() -> float:
	return max_catch_height

func get_hand_reach_height() -> float:
	return hand_reach_height

func get_hang_anchor_height() -> float:
	return hang_anchor_height

func get_hang_wall_distance() -> float:
	return hang_wall_distance

func get_top_probe_inset() -> float:
	return top_probe_inset

func get_edge_top_sample_inset() -> float:
	return edge_top_sample_inset

func get_max_top_sample_height_offset() -> float:
	return max_top_sample_height_offset

func get_max_ledge_line_tilt_degrees() -> float:
	return max_ledge_line_tilt_degrees

func get_shimmy_level_tolerance() -> float:
	return shimmy_level_tolerance

func get_shimmy_attachment_correction_limit() -> float:
	return shimmy_attachment_correction_limit

func get_ledge_span_half_width() -> float:
	return ledge_span_half_width

func get_max_catch_fall_speed() -> float:
	return max_catch_fall_speed

func get_expected_local_wall_plane_tolerance() -> float:
	return maxf(PROBE_SAFE_MARGIN, get_capsule_radius() * EXPECTED_HANG_WALL_PLANE_TOLERANCE_RADIUS_RATIO)

func get_expected_local_wall_lateral_tolerance() -> float:
	return get_capsule_radius() + get_shimmy_attachment_correction_limit()

func get_expected_hang_wall_plane_tolerance() -> float:
	return get_expected_local_wall_plane_tolerance()

func get_capsule_bottom_offset() -> float:
	return capsule_bottom_offset

func get_capsule_top_offset() -> float:
	return capsule_top_offset

func get_capsule_radius() -> float:
	return capsule_radius

func get_capsule_height() -> float:
	return capsule_height

func get_capsule_shape() -> CapsuleShape3D:
	return capsule_shape


func update_debug_logging(previously_had_candidate: bool) -> void:
	if not debug_logging:
		return
	var has_candidate_now: bool = current_candidate != null
	if has_candidate_now and not previously_had_candidate:
		print(
			"Ledge candidate acquired: edge=",
			current_candidate.edge_point,
			" wall_normal=",
			current_candidate.wall_normal,
			" hangable=",
			current_candidate.hangable,
			" hang_position=",
			current_candidate.hang_position,
			" candidates=",
			current_candidates.size(),
			" min_edge_height=",
			get_min_edge_height(),
			" max_catch_height=",
			get_max_catch_height(),
			" hang_anchor_height=",
			get_hang_anchor_height()
		)
	elif previously_had_candidate and not has_candidate_now:
		print("Ledge candidate lost")
