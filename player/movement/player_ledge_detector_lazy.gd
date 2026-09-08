class_name PlayerLedgeDetectorLazy
extends PlayerLedgeDetector


const DISCOVERY_DIRECTION_EPSILON_SQUARED: float = 0.000001
const DISCOVERY_PROBE_SAFE_MARGIN: float = 0.001


var discovery_player: CharacterBody3D = null
var discovery_support: PlayerSupport = null
var discovery_wall_hit = null
var alternates_expanded: bool = false


func update(
	player: CharacterBody3D,
	support: PlayerSupport,
	detection_allowed: bool,
	intent_direction: Vector3,
	view_forward: Vector3
) -> void:
	current_candidates.clear()
	current_candidate = null
	_clear_lazy_discovery()

	if not detection_allowed:
		return
	if player.velocity.y < -get_max_catch_fall_speed():
		return

	var approach_direction: Vector3 = _get_discovery_approach_direction(
		player,
		intent_direction,
		view_forward
	)
	if approach_direction.length_squared() <= DISCOVERY_DIRECTION_EPSILON_SQUARED:
		return

	var wall_hit = find_wall(player, approach_direction)
	if wall_hit == null:
		return
	if not has_catch_intent(wall_hit.normal, intent_direction, view_forward):
		return

	# Cache the proven wall/contact context. The expensive height-band scan is
	# deferred until the controller rejects the broad first-ranked opportunity.
	discovery_player = player
	discovery_support = support
	discovery_wall_hit = wall_hit

	var broad_top = find_top(player, support, wall_hit)
	if broad_top != null:
		_add_unique_discovery_candidate(
			current_candidates,
			build_reachable_candidate(player, support, wall_hit, broad_top)
		)

	_refresh_current_candidate()


func expand_current_candidates() -> bool:
	if alternates_expanded:
		return false
	alternates_expanded = true

	if (
		discovery_player == null
		or discovery_support == null
		or discovery_wall_hit == null
	):
		return false

	var previous_count: int = current_candidates.size()
	_append_alternate_height_candidates(
		current_candidates,
		discovery_player,
		discovery_support,
		discovery_wall_hit
	)
	_sort_discovery_candidates(current_candidates)
	_refresh_current_candidate()
	return current_candidates.size() > previous_count


func clear_candidate() -> void:
	current_candidate = null
	current_candidates.clear()
	_clear_lazy_discovery()


func _clear_lazy_discovery() -> void:
	discovery_player = null
	discovery_support = null
	discovery_wall_hit = null
	alternates_expanded = false


func _refresh_current_candidate() -> void:
	current_candidate = null
	if not current_candidates.is_empty():
		current_candidate = current_candidates[0]


func _get_discovery_approach_direction(
	player: CharacterBody3D,
	intent_direction: Vector3,
	view_forward: Vector3
) -> Vector3:
	var horizontal_intent := Vector3(
		intent_direction.x,
		0.0,
		intent_direction.z
	)
	if horizontal_intent.length_squared() > DISCOVERY_DIRECTION_EPSILON_SQUARED:
		return horizontal_intent.normalized()

	var horizontal_velocity := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	if horizontal_velocity.length_squared() > DISCOVERY_DIRECTION_EPSILON_SQUARED:
		return horizontal_velocity.normalized()

	var horizontal_view := Vector3(
		view_forward.x,
		0.0,
		view_forward.z
	)
	if horizontal_view.length_squared() <= DISCOVERY_DIRECTION_EPSILON_SQUARED:
		return Vector3.ZERO
	return horizontal_view.normalized()


func _append_alternate_height_candidates(
	results: Array[PlayerLedgeDetector.LedgeCandidate],
	player: CharacterBody3D,
	support: PlayerSupport,
	wall_hit
) -> void:
	var minimum_edge_y: float = player.global_position.y + get_min_edge_height()
	var maximum_edge_y: float = player.global_position.y + get_max_catch_height()
	var height_range: float = maximum_edge_y - minimum_edge_y
	if height_range <= DISCOVERY_PROBE_SAFE_MARGIN:
		return

	var sample_step: float = height_range / float(DISCOVERY_HEIGHT_SAMPLE_COUNT)
	var band_half_height: float = maxf(
		DISCOVERY_PROBE_SAFE_MARGIN * 4.0,
		sample_step * DISCOVERY_LOCAL_BAND_OVERLAP
	)
	for sample_index: int in range(DISCOVERY_HEIGHT_SAMPLE_COUNT + 1):
		var expected_edge_y: float = (
			maximum_edge_y - sample_step * float(sample_index)
		)
		var wall_seed := Vector3(
			wall_hit.point.x,
			expected_edge_y,
			wall_hit.point.z
		)
		var local_wall = find_wall_at_height(
			player,
			wall_hit.normal,
			wall_seed
		)
		if local_wall == null:
			continue

		var local_top = find_top_in_height_band(
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
