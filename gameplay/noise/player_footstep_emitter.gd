class_name VarkPlayerFootstepEmitter
extends Node


signal gameplay_noise_emitted(summary: Dictionary)


const SURFACE_PROFILE_PATHS: Dictionary = {
	"stone": "res://gameplay/noise/profiles/stone.tres",
	"carpet": "res://gameplay/noise/profiles/carpet.tres",
	"tile": "res://gameplay/noise/profiles/tile.tres",
}
const SURFACE_TEXTURE_PREFIX: String = "vark_surfaces/"
const SURFACE_PROBE_RADIUS: float = 0.10
const SURFACE_PROBE_CENTER_HEIGHT: float = 0.04


@export var player_path: NodePath = NodePath("../Player")
@export_range(0.2, 4.0, 0.05) var step_distance: float = 1.25
@export_range(0.0, 5.0, 0.05) var minimum_move_speed: float = 0.35
@export_range(0.05, 1.0, 0.05) var crouched_strength_scale: float = 0.45
@export_range(1.0, 2.0, 0.05) var sprint_strength_scale: float = 1.35
@export var emission_enabled: bool = true

var _player: CharacterBody3D = null
var _world_session: Node = null
var _last_position: Vector3 = Vector3.ZERO
var _distance_since_step: float = 0.0
var _queued_count: int = 0
var _last_surface_id: StringName = &""
var _last_loudness_id: StringName = &""
var _last_sound_kind: StringName = &""
var _last_base_strength: float = 0.0
var _last_strength: float = 0.0
var _last_stance: String = "standing"
var _last_gait: String = "walking"
var _last_resolution_source: StringName = &""
var _last_surface_texture: StringName = &""
var _surface_profile_cache: Dictionary = {}
var _landing_armed: bool = false
var _mantle_contact_pending: bool = false


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_world_session = _find_world_session()
	if _player != null:
		_last_position = _player.global_position
	_landing_armed = false
	_mantle_contact_pending = false


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var current: Vector3 = _player.global_position
	var horizontal_delta := Vector3(
		current.x - _last_position.x,
		0.0,
		current.z - _last_position.z
	)
	_last_position = current
	if not emission_enabled:
		_distance_since_step = 0.0
		_landing_armed = false
		_mantle_contact_pending = false
		return

	var movement_state: Dictionary = _get_player_movement_state()
	if not _advance_landing_transition(movement_state):
		return

	var horizontal_speed := Vector3(
		_player.velocity.x,
		0.0,
		_player.velocity.z
	).length()
	if horizontal_speed < minimum_move_speed:
		# Standing still pauses cadence progress instead of forgiving it. This
		# prevents repeated sub-step movement bursts from resetting footstep
		# distance and becoming indefinitely silent.
		return

	_distance_since_step += horizontal_delta.length()
	while _distance_since_step >= step_distance:
		if not emit_step_now():
			break
		_distance_since_step -= step_distance


func _advance_landing_transition(movement_state: Dictionary) -> bool:
	var grounded: bool = str(
		movement_state.get("support", "airborne")
	) == "grounded"
	var traversal: String = str(
		movement_state.get("traversal", "normal")
	)

	if traversal == "mantling":
		# Mantle motion is traversal-owned, not a run/fall. Suppress cadence and
		# remember that a successful grounded handoff owes exactly one ordinary
		# stance-scaled contact step.
		_mantle_contact_pending = true
		_landing_armed = false
		_distance_since_step = 0.0
		return false

	if not grounded:
		# Leaving mantle ownership while still airborne means the mantle was
		# cancelled/released. From here onward the eventual impact is an ordinary
		# jump/fall landing and therefore keeps the running-strength rule.
		if _mantle_contact_pending:
			_mantle_contact_pending = false
		if traversal == "normal":
			_landing_armed = true
		_distance_since_step = 0.0
		return false

	if traversal != "normal":
		# Catching/hanging/cornering never generate distance cadence or a delayed
		# landing by themselves.
		_distance_since_step = 0.0
		return false

	if _mantle_contact_pending:
		_mantle_contact_pending = false
		_landing_armed = false
		_distance_since_step = 0.0
		emit_mantle_step_now(movement_state)
		return false

	if _landing_armed:
		# Landing replaces a same-frame cadence footstep so one contact produces
		# one semantic movement sound.
		_landing_armed = false
		_distance_since_step = 0.0
		emit_landing_now()
		return false
	return true


func set_emission_enabled(enabled: bool) -> void:
	emission_enabled = enabled
	_distance_since_step = 0.0
	_landing_armed = false
	_mantle_contact_pending = false
	if _player != null and is_instance_valid(_player):
		_last_position = _player.global_position


func emit_step_now() -> bool:
	var movement_state: Dictionary = _get_player_movement_state()
	var stance: String = str(movement_state.get("stance", "standing"))
	var sprinting: bool = bool(movement_state.get("sprinting", false))
	var gait: String = "walking"
	var movement_scale: float = 1.0
	if stance == "crouched":
		gait = "crouched"
		movement_scale = clampf(crouched_strength_scale, 0.05, 1.0)
	elif sprinting:
		gait = "sprinting"
		movement_scale = maxf(sprint_strength_scale, 1.0)
	return _emit_current_surface_noise(gait, movement_scale, stance)


func emit_landing_now() -> bool:
	var movement_state: Dictionary = _get_player_movement_state()
	var stance: String = str(movement_state.get("stance", "standing"))
	return _emit_current_surface_noise(
		"landing",
		maxf(sprint_strength_scale, 1.0),
		stance
	)


func emit_mantle_step_now(
	movement_state: Dictionary = {}
) -> bool:
	var resolved_state: Dictionary = movement_state
	if resolved_state.is_empty():
		resolved_state = _get_player_movement_state()
	var stance: String = str(resolved_state.get("stance", "standing"))
	if stance == "crouched":
		return _emit_current_surface_noise(
			"crouched",
			clampf(crouched_strength_scale, 0.05, 1.0),
			stance
		)
	return _emit_current_surface_noise(
		"walking",
		1.0,
		stance
	)


func _emit_current_surface_noise(
	gait: String,
	movement_scale: float,
	stance: String
) -> bool:
	if (
		_player == null
		or not is_instance_valid(_player)
		or _world_session == null
		or not is_instance_valid(_world_session)
	):
		return false
	var profile: VarkSurfaceProfile = _find_current_surface_profile()
	if profile == null or not profile.is_valid_profile():
		return false
	var base_strength: float = profile.get_footstep_strength()
	var kind: StringName = profile.get_footstep_sound_kind()
	if kind.is_empty() or base_strength <= 0.0:
		return false

	var strength: float = base_strength * maxf(movement_scale, 0.0)
	var queued: bool = bool(_world_session.call(
		"queue_gameplay_sound",
		int(_world_session.get("session_id")),
		kind,
		_player.global_position,
		strength
	))
	if not queued:
		return false
	_queued_count += 1
	_last_surface_id = profile.surface_id
	_last_loudness_id = profile.get_loudness_id()
	_last_sound_kind = kind
	_last_base_strength = base_strength
	_last_strength = strength
	_last_stance = stance
	_last_gait = gait
	gameplay_noise_emitted.emit(get_debug_summary())
	return true


func get_current_surface_debug() -> Dictionary:
	var profile: VarkSurfaceProfile = _find_current_surface_profile()
	return {
		"surface_id": profile.surface_id if profile != null else &"",
		"resolution_source": _last_resolution_source,
		"surface_texture": _last_surface_texture,
	}


func get_debug_summary() -> Dictionary:
	return {
		"enabled": emission_enabled,
		"queued_count": _queued_count,
		"last_surface_id": _last_surface_id,
		"last_loudness_id": _last_loudness_id,
		"last_sound_kind": _last_sound_kind,
		"last_base_strength": _last_base_strength,
		"last_strength": _last_strength,
		"last_stance": _last_stance,
		"last_gait": _last_gait,
		"last_resolution_source": _last_resolution_source,
		"last_surface_texture": _last_surface_texture,
		"landing_armed": _landing_armed,
		"mantle_contact_pending": _mantle_contact_pending,
		"crouched_strength_scale": crouched_strength_scale,
		"sprint_strength_scale": sprint_strength_scale,
		"step_distance": step_distance,
		"distance_since_step": _distance_since_step,
	}


func _get_player_movement_state() -> Dictionary:
	if (
		_player == null
		or not is_instance_valid(_player)
		or not _player.has_method("get_movement_semantic_state")
	):
		return {
			"stance": "standing",
			"sprinting": false,
		}
	return _player.call("get_movement_semantic_state")


func _find_current_surface_profile() -> VarkSurfaceProfile:
	var map_profile: VarkSurfaceProfile = _find_func_godot_surface_profile()
	if map_profile != null and map_profile.is_valid_profile():
		return map_profile

	var surface: VarkFootstepSurface = _find_current_surface()
	if surface == null or not surface.has_valid_surface_profile():
		_last_resolution_source = &""
		_last_surface_texture = &""
		return null
	_last_resolution_source = &"authored_volume"
	_last_surface_texture = &""
	return surface.get_surface_profile()


func _find_func_godot_surface_profile() -> VarkSurfaceProfile:
	if (
		_player == null
		or not is_instance_valid(_player)
		or not _player.is_inside_tree()
	):
		return null

	var world_3d: World3D = _player.get_world_3d()
	if world_3d == null:
		return null

	# Query the actual support contact just below the player's feet. FuncGodot
	# world geometry is built from convex brush shapes; a small overlap/rest
	# probe is reliable for those shapes in both READY and PLAYING worlds,
	# whereas a zero-width ray can miss a face that lies exactly on a convex
	# boundary. Keep this probe map-solid-only: non-map supports fall back to
	# the existing authored semantic surface volumes.
	var probe_shape := SphereShape3D.new()
	probe_shape.radius = SURFACE_PROBE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe_shape
	query.transform = Transform3D(
		Basis.IDENTITY,
		_player.global_position + Vector3.UP * SURFACE_PROBE_CENTER_HEIGHT
	)
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = world_3d.direct_space_state.get_rest_info(query)
	if hit.is_empty():
		return null

	var collider := hit.get("collider") as CollisionObject3D
	if collider == null or not collider.has_meta("func_godot_mesh_data"):
		return null
	var mesh_data_variant: Variant = collider.get_meta("func_godot_mesh_data")
	if not (mesh_data_variant is Dictionary):
		return null
	var mesh_data: Dictionary = mesh_data_variant as Dictionary
	var shape_to_faces_variant: Variant = mesh_data.get(
		"collision_shape_to_face_indices_map",
		{}
	)
	if not (shape_to_faces_variant is Dictionary):
		return null
	var shape_to_faces: Dictionary = shape_to_faces_variant as Dictionary

	var shape_index: int = int(hit.get("shape", -1))
	if shape_index < 0:
		return null
	var shape_owner_id: int = collider.shape_find_owner(shape_index)
	if shape_owner_id < 0:
		return null
	var shape_owner: Object = collider.shape_owner_get_owner(shape_owner_id)
	if not (shape_owner is CollisionShape3D):
		return null
	var collision_shape := shape_owner as CollisionShape3D
	var face_indices_variant: Variant = shape_to_faces.get(
		collision_shape.name,
		PackedInt32Array()
	)
	if not (face_indices_variant is PackedInt32Array):
		return null
	var face_indices: PackedInt32Array = face_indices_variant as PackedInt32Array
	if face_indices.is_empty():
		return null

	var texture_names_variant: Variant = mesh_data.get("texture_names", [])
	var textures_variant: Variant = mesh_data.get("textures", PackedInt32Array())
	var normals_variant: Variant = mesh_data.get("normals", PackedVector3Array())
	var positions_variant: Variant = mesh_data.get("positions", PackedVector3Array())
	if (
		not (texture_names_variant is Array)
		or not (textures_variant is PackedInt32Array)
		or not (normals_variant is PackedVector3Array)
		or not (positions_variant is PackedVector3Array)
	):
		return null
	var texture_names: Array = texture_names_variant as Array
	var textures: PackedInt32Array = textures_variant as PackedInt32Array
	var normals: PackedVector3Array = normals_variant as PackedVector3Array
	var positions: PackedVector3Array = positions_variant as PackedVector3Array
	if (
		textures.is_empty()
		or normals.is_empty()
		or positions.is_empty()
	):
		return null

	# Vark's authored solid-color brushes intentionally use one material on every
	# face. Resolve that common case directly from the collision shape mapping;
	# it avoids depending on face-normal winding conventions and guarantees the
	# gameplay surface stays identical to the brush's rendered material.
	var uniform_texture_index: int = -1
	var uniform_texture: bool = true
	for face_index: int in face_indices:
		if face_index < 0 or face_index >= textures.size():
			uniform_texture = false
			break
		var candidate_texture_index: int = textures[face_index]
		if uniform_texture_index < 0:
			uniform_texture_index = candidate_texture_index
		elif candidate_texture_index != uniform_texture_index:
			uniform_texture = false
			break
	if (
		uniform_texture
		and uniform_texture_index >= 0
		and uniform_texture_index < texture_names.size()
	):
		var uniform_texture_name: String = str(
			texture_names[uniform_texture_index]
		)
		var uniform_profile: VarkSurfaceProfile = (
			_get_profile_for_surface_texture(uniform_texture_name)
		)
		if uniform_profile != null:
			return uniform_profile

	var hit_normal: Vector3 = (hit.get("normal", Vector3.UP) as Vector3).normalized()
	var hit_position: Vector3 = hit.get("position", _player.global_position) as Vector3
	var best_face_index: int = -1
	var best_normal_score: float = -2.0
	var best_position_distance: float = INF
	for face_index: int in face_indices:
		if (
			face_index < 0
			or face_index >= textures.size()
			or face_index >= normals.size()
			or face_index >= positions.size()
		):
			continue
		var global_normal: Vector3 = (
			collider.global_transform.basis * normals[face_index]
		).normalized()
		# FuncGodot plane normals and physics hit normals may use opposite
		# winding conventions. Surface identity depends on the plane, not that
		# sign, so compare alignment magnitude and use face position to choose
		# between the two parallel planes of a convex brush.
		var normal_score: float = absf(global_normal.dot(hit_normal))
		var face_position: Vector3 = collider.to_global(positions[face_index])
		var position_distance: float = face_position.distance_squared_to(
			hit_position
		)
		if (
			normal_score > best_normal_score + 0.0001
			or (
				is_equal_approx(normal_score, best_normal_score)
				and position_distance < best_position_distance
			)
		):
			best_face_index = face_index
			best_normal_score = normal_score
			best_position_distance = position_distance

	if best_face_index < 0 or best_normal_score < 0.80:
		return null
	var texture_index: int = textures[best_face_index]
	if texture_index < 0 or texture_index >= texture_names.size():
		return null
	var texture_name: String = str(texture_names[texture_index])
	return _get_profile_for_surface_texture(texture_name)


func _get_profile_for_surface_texture(texture_name: String) -> VarkSurfaceProfile:
	if not texture_name.begins_with(SURFACE_TEXTURE_PREFIX):
		return null
	var variant: String = texture_name.trim_prefix(SURFACE_TEXTURE_PREFIX)
	if variant.contains("."):
		variant = variant.get_basename()
	var profile: VarkSurfaceProfile = _get_surface_profile_for_variant(variant)
	if profile == null:
		return null
	_last_resolution_source = &"func_godot_material"
	_last_surface_texture = StringName(texture_name)
	return profile


func _get_surface_profile_for_variant(variant: String) -> VarkSurfaceProfile:
	var normalized: String = variant.strip_edges()
	if _surface_profile_cache.has(normalized):
		return _surface_profile_cache[normalized] as VarkSurfaceProfile
	var profile_path: String = str(SURFACE_PROFILE_PATHS.get(normalized, ""))
	if profile_path.is_empty() or not ResourceLoader.exists(profile_path):
		return null
	var loaded: Resource = ResourceLoader.load(profile_path)
	if not (loaded is VarkSurfaceProfile):
		return null
	var profile := loaded as VarkSurfaceProfile
	_surface_profile_cache[normalized] = profile
	return profile


func _find_current_surface() -> VarkFootstepSurface:
	var world_root: Node = get_parent()
	for node: Node in get_tree().get_nodes_in_group(
		&"vark_footstep_surface"
	):
		if not (node is VarkFootstepSurface):
			continue
		if world_root != null and not world_root.is_ancestor_of(node):
			continue
		var surface := node as VarkFootstepSurface
		if surface.contains_body(_player):
			return surface
	return null


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_gameplay_sound"):
			return cursor
		cursor = cursor.get_parent()
	return null
