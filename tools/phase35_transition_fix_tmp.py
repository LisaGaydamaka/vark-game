from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    start_index = text.find(start)
    if start_index < 0:
        raise SystemExit(f"{label}: start marker not found")
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise SystemExit(f"{label}: end marker not found")
    return text[:start_index] + replacement + text[end_index:]


# ordinary_prop.gd: release collision ownership and real contact-manifold settling.
path = Path("gameplay/props/ordinary_prop.gd")
text = path.read_text(encoding="utf-8")
text = replace_once(
    text,
    "var _ordinary_collision_layer: int = 1\nvar _ordinary_collision_mask: int = 1\n",
    """var _ordinary_collision_layer: int = 1
var _ordinary_collision_mask: int = 1
var _dynamic_contact_count: int = 0
var _dynamic_support_valid: bool = false
var _dynamic_support_point: Vector3 = Vector3.ZERO
var _dynamic_support_normal: Vector3 = Vector3.UP
var _temporary_player_collision_exception: PhysicsBody3D = null
""",
    "ordinary prop dynamic fields",
)

new_physics = """func _physics_process(_delta: float) -> void:
\tmatch _phase:
\t\tPHASE_SETTLED:
\t\t\tlinear_velocity = Vector3.ZERO
\t\t\tangular_velocity = Vector3.ZERO
\t\t\t_last_contact_count = 0
\t\t\t_clear_dynamic_contact_state()
\t\t\tif _has_support():
\t\t\t\t_unsupported_frames = 0
\t\t\telse:
\t\t\t\t_unsupported_frames += 1
\t\t\t\tif _unsupported_frames >= 2:
\t\t\t\t\t_begin_motion(MOTION_UNSUPPORTED, Vector3.ZERO)
\t\tPHASE_CARRIED_JUNK:
\t\t\tlinear_velocity = Vector3.ZERO
\t\t\tangular_velocity = Vector3.ZERO
\t\t\t_unsupported_frames = 0
\t\t\t_settle_contact_frames = 0
\t\t\t_last_contact_count = 0
\t\t\t_clear_dynamic_contact_state()
\t\tPHASE_MOVING, PHASE_SETTLING:
\t\t\t_unsupported_frames = 0
\t\t\tangular_velocity = Vector3.ZERO
\t\t\t_update_dynamic_settling()
\t_update_temporary_player_collision_exception()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
\tif _phase != PHASE_MOVING and _phase != PHASE_SETTLING:
\t\treturn
\t_dynamic_contact_count = state.get_contact_count()
\t_dynamic_support_valid = false
\t_dynamic_support_point = Vector3.ZERO
\t_dynamic_support_normal = Vector3.UP
\tvar body_origin: Vector3 = state.transform.origin
\tfor contact_index: int in range(_dynamic_contact_count):
\t\tvar local_point: Vector3 = state.get_contact_local_position(contact_index)
\t\tif local_point.y > body_origin.y + 0.05:
\t\t\tcontinue
\t\tvar normal: Vector3 = state.get_contact_local_normal(contact_index)
\t\tif normal.length_squared() <= 0.000001:
\t\t\tcontinue
\t\tnormal = normal.normalized()
\t\tif normal.y < 0.0:
\t\t\tnormal = -normal
\t\tif normal.y < minimum_support_normal_y:
\t\t\tcontinue
\t\tvar support_point: Vector3 = state.get_contact_collider_position(contact_index)
\t\tif not _dynamic_support_valid or support_point.y > _dynamic_support_point.y:
\t\t\t_dynamic_support_valid = true
\t\t\t_dynamic_support_point = support_point
\t\t\t_dynamic_support_normal = normal


"""
text = replace_between(
    text,
    "func _physics_process(_delta: float) -> void:\n",
    "func can_interact(interactor: Node) -> bool:\n",
    new_physics,
    "ordinary prop physics process",
)

release_helpers = """func is_release_transform_world_clear(
\trelease_transform: Transform3D,
\tignored_body: PhysicsBody3D = null
) -> bool:
\tif prop_collision == null or prop_collision.shape == null or not is_inside_tree():
\t\treturn false
\tvar query := PhysicsShapeQueryParameters3D.new()
\tquery.shape = prop_collision.shape
\tquery.transform = release_transform * prop_collision.transform
\tquery.collision_mask = _ordinary_collision_mask
\tquery.collide_with_areas = false
\tquery.collide_with_bodies = true
\tquery.margin = 0.001
\tvar excluded: Array[RID] = [get_rid()]
\tif ignored_body != null and is_instance_valid(ignored_body):
\t\texcluded.append(ignored_body.get_rid())
\tquery.exclude = excluded
\treturn get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func has_temporary_player_collision_exception() -> bool:
\treturn (
\t\t_temporary_player_collision_exception != null
\t\tand is_instance_valid(_temporary_player_collision_exception)
\t)


"""
text = replace_once(
    text,
    "\n\nfunc begin_carried_junk(holder: Node) -> bool:\n",
    "\n\n" + release_helpers + "func begin_carried_junk(holder: Node) -> bool:\n",
    "ordinary prop release helpers",
)

new_begin = """func begin_carried_junk(holder: Node) -> bool:
\tif holder == null or _phase == PHASE_CARRIED_JUNK:
\t\treturn false
\t_clear_temporary_player_collision_exception()
\t_clear_dynamic_contact_state()
\t_holder = holder
\t_phase = PHASE_CARRIED_JUNK
\t_motion_kind = MOTION_NONE
\t_settle_contact_frames = 0
\t_unsupported_frames = 0
\t_last_contact_count = 0
\tlinear_velocity = Vector3.ZERO
\tangular_velocity = Vector3.ZERO
\tfreeze = true
\tsleeping = true
\tset_interaction_highlighted(false)
\t_set_world_presentation_enabled(false)
\treturn true


"""
text = replace_between(
    text,
    "func begin_carried_junk(holder: Node) -> bool:\n",
    "func release_from_carry(\n",
    new_begin,
    "ordinary prop carried transition",
)

new_release = """func release_from_carry(
\tmotion_kind: StringName,
\trelease_transform: Transform3D,
\tinitial_velocity: Vector3,
\treleasing_player: PhysicsBody3D = null
) -> bool:
\tif _phase != PHASE_CARRIED_JUNK:
\t\treturn false
\tif motion_kind != MOTION_RELEASED and motion_kind != MOTION_THROWN:
\t\treturn false
\tif not _is_finite_transform(release_transform) or not _is_finite_vector(initial_velocity):
\t\treturn false
\t_clear_temporary_player_collision_exception()
\t_holder = null
\tglobal_transform = release_transform
\tif (
\t\treleasing_player != null
\t\tand is_instance_valid(releasing_player)
\t\tand _shape_overlaps_body_at_transform(release_transform, releasing_player)
\t):
\t\tadd_collision_exception_with(releasing_player)
\t\t_temporary_player_collision_exception = releasing_player
\t_set_world_presentation_enabled(true)
\t_begin_motion(motion_kind, initial_velocity)
\treturn true


"""
text = replace_between(
    text,
    "func release_from_carry(\n",
    "func capture_semantic_state() -> Dictionary:\n",
    new_release,
    "ordinary prop release transaction",
)

text = replace_once(
    text,
    "\t_phase = phase\n\t_motion_kind = motion_kind\n",
    "\t_clear_temporary_player_collision_exception()\n\t_clear_dynamic_contact_state()\n\t_phase = phase\n\t_motion_kind = motion_kind\n",
    "ordinary prop restore transient reset",
)
text = replace_once(
    text,
    "\t_holder = null\n\t_set_world_presentation_enabled(true)\n\tif _phase == PHASE_SETTLED:\n",
    "\t_holder = null\n\t_clear_temporary_player_collision_exception()\n\t_set_world_presentation_enabled(true)\n\tif _phase == PHASE_SETTLED:\n",
    "ordinary prop reconcile transient reset",
)
text = replace_once(
    text,
    "\t_last_contact_count = 0\n\tlinear_velocity = initial_velocity\n",
    "\t_last_contact_count = 0\n\t_clear_dynamic_contact_state()\n\tlinear_velocity = initial_velocity\n",
    "ordinary prop begin motion contact reset",
)

dynamic_settle = """func _update_dynamic_settling() -> void:
\tvar contact_count: int = _dynamic_contact_count
\tif contact_count > 0 and _last_contact_count == 0:
\t\t_queue_impact_sound(linear_velocity.length())
\t_last_contact_count = contact_count
\tif _dynamic_support_valid and linear_velocity.length() <= maxf(settle_linear_speed, 0.01):
\t\t_settle_contact_frames += 1
\t\t_phase = PHASE_SETTLING
\t\tif _settle_contact_frames >= maxi(settle_contact_frames_required, 1):
\t\t\t_settle_now(_dynamic_support_point, _dynamic_support_normal)
\t\treturn
\t_settle_contact_frames = 0
\t_phase = PHASE_MOVING


func _settle_now(support_point: Vector3, support_normal: Vector3) -> void:
\tvar top_up_basis: Basis = _top_up_basis_for_yaw(_settle_yaw)
\tvar settled_origin: Vector3 = global_position
\tvar box: BoxShape3D = prop_collision.shape as BoxShape3D if prop_collision != null else null
\tvar normal: Vector3 = support_normal
\tif normal.length_squared() > 0.000001:
\t\tnormal = normal.normalized()
\tif box != null and normal.y >= minimum_support_normal_y:
\t\tvar support_extent: float = _support_extent_along_normal(top_up_basis, box.size * 0.5, normal)
\t\tvar horizontal_delta := Vector3(
\t\t\tsettled_origin.x - support_point.x,
\t\t\t0.0,
\t\t\tsettled_origin.z - support_point.z
\t\t)
\t\tsettled_origin.y = support_point.y + (
\t\t\tsupport_extent
\t\t\t- normal.x * horizontal_delta.x
\t\t\t- normal.z * horizontal_delta.z
\t\t) / normal.y
\tfreeze = true
\tlinear_velocity = Vector3.ZERO
\tangular_velocity = Vector3.ZERO
\tglobal_transform = Transform3D(top_up_basis, settled_origin)
\tsleeping = true
\t_phase = PHASE_SETTLED
\t_motion_kind = MOTION_NONE
\t_settle_contact_frames = 0
\t_unsupported_frames = 0
\t_last_contact_count = 0
\t_clear_dynamic_contact_state()


func _support_extent_along_normal(source_basis: Basis, half: Vector3, normal: Vector3) -> float:
\tvar basis: Basis = source_basis.orthonormalized()
\treturn (
\t\tabsf(basis.x.dot(normal)) * half.x
\t\t+ absf(basis.y.dot(normal)) * half.y
\t\t+ absf(basis.z.dot(normal)) * half.z
\t)


func _clear_dynamic_contact_state() -> void:
\t_dynamic_contact_count = 0
\t_dynamic_support_valid = false
\t_dynamic_support_point = Vector3.ZERO
\t_dynamic_support_normal = Vector3.UP


func _update_temporary_player_collision_exception() -> void:
\tif _temporary_player_collision_exception == null:
\t\treturn
\tif not is_instance_valid(_temporary_player_collision_exception):
\t\t_temporary_player_collision_exception = null
\t\treturn
\tif _shape_overlaps_body_at_transform(global_transform, _temporary_player_collision_exception):
\t\treturn
\t_clear_temporary_player_collision_exception()


func _clear_temporary_player_collision_exception() -> void:
\tif (
\t\t_temporary_player_collision_exception != null
\t\tand is_instance_valid(_temporary_player_collision_exception)
\t):
\t\tremove_collision_exception_with(_temporary_player_collision_exception)
\t_temporary_player_collision_exception = null


func _shape_overlaps_body_at_transform(body_transform: Transform3D, other_body: PhysicsBody3D) -> bool:
\tif (
\t\tother_body == null
\t\tor not is_instance_valid(other_body)
\t\tor prop_collision == null
\t\tor prop_collision.shape == null
\t\tor not is_inside_tree()
\t):
\t\treturn false
\tvar query := PhysicsShapeQueryParameters3D.new()
\tquery.shape = prop_collision.shape
\tquery.transform = body_transform * prop_collision.transform
\tquery.collision_mask = 0xFFFFFFFF
\tquery.collide_with_areas = false
\tquery.collide_with_bodies = true
\tquery.margin = 0.001
\tquery.exclude = [get_rid()]
\tvar other_rid: RID = other_body.get_rid()
\tfor hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
\t\tvar hit_rid: Variant = hit.get(\"rid\")
\t\tif hit_rid is RID and hit_rid == other_rid:
\t\t\treturn true
\treturn false


"""
text = replace_between(
    text,
    "func _update_dynamic_settling() -> void:\n",
    "func _has_support() -> bool:\n",
    dynamic_settle + "func _has_support() -> bool:\n",
    "ordinary prop dynamic settle",
)
path.write_text(text, encoding="utf-8")


# PlayerPropCarry: shape-aware release placement excluding only the player.
Path("player/interaction/player_prop_carry.gd").write_text("""class_name PlayerPropCarry
extends RefCounted


const RELEASE_POSE_SCAN_STEPS: int = 16
const RELEASE_POSE_REFINE_STEPS: int = 8


var player: CharacterBody3D
var camera: Camera3D
var held_prop: Node = null
var hud_container: Control
var hud_mesh: MeshInstance3D
var hud_material: StandardMaterial3D

var release_distance: float = 1.15
var release_surface_padding: float = 0.006
var release_speed: float = 0.55


func _init(
\towner: CharacterBody3D,
\tview_camera: Camera3D,
\tcarried_hud_container: Control,
\tcarried_hud_mesh: MeshInstance3D,
\tcarried_hud_material: StandardMaterial3D
) -> void:
\tplayer = owner
\tcamera = view_camera
\thud_container = carried_hud_container
\thud_mesh = carried_hud_mesh
\thud_material = carried_hud_material
\t_refresh_hud(null)


func has_held_prop() -> bool:
\treturn held_prop != null and is_instance_valid(held_prop)


func get_held_prop() -> Node:
\treturn held_prop if has_held_prop() else null


func try_pick_up(prop: Node) -> bool:
\tif has_held_prop() or prop == null or not (prop is Node3D):
\t\treturn false
\tif not prop.has_method(\"begin_carried_junk\") or not prop.has_method(\"release_from_carry\"):
\t\treturn false
\tif not bool(prop.call(\"begin_carried_junk\", player)):
\t\treturn false
\tif prop is CollisionObject3D and player.has_method(\"invalidate_world_collider_dependency\"):
\t\tplayer.call(\"invalidate_world_collider_dependency\", (prop as CollisionObject3D).get_rid())
\theld_prop = prop
\t_refresh_hud(prop)
\treturn true


func adopt_restored_held_prop(prop: Node) -> bool:
\tif has_held_prop() or prop == null or not (prop is Node3D):
\t\treturn false
\tif not prop.has_method(\"get_semantic_phase\") or prop.call(\"get_semantic_phase\") != &\"carried_junk\":
\t\treturn false
\theld_prop = prop
\t_refresh_hud(prop)
\treturn true


func release_held_gently() -> bool:
\tif not has_held_prop():
\t\treturn false
\tvar forward: Vector3 = -camera.global_transform.basis.z.normalized()
\tvar initial_velocity: Vector3 = forward * release_speed + player.velocity * 0.15
\treturn _release(&\"released\", initial_velocity)


func throw_held() -> bool:
\tif not has_held_prop():
\t\treturn false
\tvar speed: float = maxf(float(held_prop.get(\"throw_speed\")), 0.0)
\tvar forward: Vector3 = -camera.global_transform.basis.z.normalized()
\tvar initial_velocity: Vector3 = forward * speed + player.velocity
\treturn _release(&\"thrown\", initial_velocity)


func clear_reference() -> void:
\theld_prop = null
\t_refresh_hud(null)


func _release(motion_kind: StringName, initial_velocity: Vector3) -> bool:
\tvar release_result: Dictionary = _compute_release_transform()
\tvar transform_value: Variant = release_result.get(\"transform\")
\tif not (transform_value is Transform3D):
\t\treturn false
\tvar prop: Node = held_prop
\tvar released: bool = bool(prop.call(
\t\t\"release_from_carry\",
\t\tmotion_kind,
\t\ttransform_value,
\t\tinitial_velocity,
\t\tplayer
\t))
\tif released:
\t\theld_prop = null
\t\t_refresh_hud(null)
\treturn released


func _compute_release_transform() -> Dictionary:
\tvar view_basis: Basis = camera.global_transform.basis.orthonormalized()
\tvar forward: Vector3 = -view_basis.z.normalized()
\tvar release_basis: Basis = (view_basis * Basis(Vector3.BACK, PI * 0.5)).orthonormalized()
\tvar origin: Vector3 = camera.global_position
\tvar maximum_distance: float = maxf(release_distance, 0.0)
\tvar candidate := Transform3D(release_basis, origin + forward * maximum_distance)
\tif _is_release_pose_world_clear(candidate):
\t\treturn {\"transform\": candidate}
\tvar blocked_distance: float = maximum_distance
\tvar clear_distance: float = -1.0
\tfor scan_step: int in range(1, RELEASE_POSE_SCAN_STEPS + 1):
\t\tvar distance: float = maximum_distance * (1.0 - float(scan_step) / float(RELEASE_POSE_SCAN_STEPS))
\t\tcandidate.origin = origin + forward * distance
\t\tif _is_release_pose_world_clear(candidate):
\t\t\tclear_distance = distance
\t\t\tbreak
\t\tblocked_distance = distance
\tif clear_distance < 0.0:
\t\treturn {}
\tvar safe_distance: float = clear_distance
\tvar unsafe_distance: float = blocked_distance
\tfor _refine_step: int in range(RELEASE_POSE_REFINE_STEPS):
\t\tvar distance: float = (safe_distance + unsafe_distance) * 0.5
\t\tcandidate.origin = origin + forward * distance
\t\tif _is_release_pose_world_clear(candidate):
\t\t\tsafe_distance = distance
\t\telse:
\t\t\tunsafe_distance = distance
\tvar padded_distance: float = maxf(0.0, safe_distance - maxf(release_surface_padding, 0.0))
\tcandidate.origin = origin + forward * padded_distance
\tif not _is_release_pose_world_clear(candidate):
\t\tcandidate.origin = origin + forward * safe_distance
\treturn {\"transform\": candidate}


func _is_release_pose_world_clear(candidate: Transform3D) -> bool:
\tif held_prop == null or not is_instance_valid(held_prop):
\t\treturn false
\tif not held_prop.has_method(\"is_release_transform_world_clear\"):
\t\treturn false
\treturn bool(held_prop.call(\"is_release_transform_world_clear\", candidate, player))


func _refresh_hud(prop: Node) -> void:
\tif hud_container == null or hud_mesh == null:
\t\treturn
\tvar active: bool = prop != null and is_instance_valid(prop)
\thud_container.visible = active
\tif not active:
\t\thud_mesh.mesh = null
\t\treturn
\tif prop.has_method(\"get_visual_model\"):
\t\thud_mesh.mesh = prop.call(\"get_visual_model\") as Mesh
\tif hud_material != null:
\t\thud_material.albedo_color = prop.get(\"base_color\") as Color
""", encoding="utf-8")


# Exact player support invalidation.
path = Path("player/locomotion/player_support.gd")
text = path.read_text(encoding="utf-8")
support_invalidation = """func invalidate_collider(collider_rid: RID, origin: Vector3) -> bool:
\tif (
\t\tnot collider_rid.is_valid()
\t\tor not current_contact.valid
\t\tor current_contact.collider_rid != collider_rid
\t):
\t\treturn false
\tcurrent_contact.clear(origin)
\treturn true


"""
text = replace_once(
    text,
    "func _clear_support(player: CharacterBody3D) -> void:\n",
    support_invalidation + "func _clear_support(player: CharacterBody3D) -> void:\n",
    "player support collider invalidation",
)
path.write_text(text, encoding="utf-8")


# Ledge detector cached candidate invalidation.
path = Path("player/traversal/player_ledge_detector.gd")
text = path.read_text(encoding="utf-8")
detector_invalidation = """func invalidate_collider(collider_rid: RID) -> bool:
\tif not collider_rid.is_valid():
\t\treturn false
\tvar retained: Array[LedgeCandidate] = []
\tvar removed: bool = false
\tfor candidate: LedgeCandidate in current_candidates:
\t\tif _candidate_uses_collider(candidate, collider_rid):
\t\t\tremoved = true
\t\t\tcontinue
\t\tretained.append(candidate)
\tcurrent_candidates = retained
\tcurrent_candidate = current_candidates[0] if not current_candidates.is_empty() else null
\treturn removed


func _candidate_uses_collider(candidate: LedgeCandidate, collider_rid: RID) -> bool:
\tif candidate == null or not collider_rid.is_valid():
\t\treturn false
\treturn (
\t\t(candidate.wall_collider_rid.is_valid() and candidate.wall_collider_rid == collider_rid)
\t\tor (candidate.top_collider_rid.is_valid() and candidate.top_collider_rid == collider_rid)
\t)


"""
text = replace_once(
    text,
    "func find_candidate(\n",
    detector_invalidation + "func find_candidate(\n",
    "ledge detector collider invalidation",
)
path.write_text(text, encoding="utf-8")


# Active traversal invalidation.
path = Path("player/traversal/player_ledge_controller.gd")
text = path.read_text(encoding="utf-8")
controller_invalidation = """func invalidate_collider(collider_rid: RID) -> bool:
\tif not collider_rid.is_valid() or state == State.NONE:
\t\treturn false
\tvar depends_on_collider: bool = false
\tmatch state:
\t\tState.CATCHING:
\t\t\tdepends_on_collider = _candidate_uses_collider(active_catch_candidate, collider_rid)
\t\tState.HANGING:
\t\t\tdepends_on_collider = _candidate_uses_collider(ledge_hang.get_candidate(), collider_rid)
\t\tState.CORNERING:
\t\t\tfor candidate: PlayerLedgeDetector.LedgeCandidate in ledge_corner.get_release_candidates():
\t\t\t\tif _candidate_uses_collider(candidate, collider_rid):
\t\t\t\t\tdepends_on_collider = true
\t\t\t\t\tbreak
\t\tState.MANTLING:
\t\t\tdepends_on_collider = _candidate_uses_collider(ledge_mantle.get_release_candidate(), collider_rid)
\tif not depends_on_collider:
\t\treturn false
\tmatch state:
\t\tState.CATCHING:
\t\t\tledge_catch.cancel()
\t\t\tactive_catch_candidate = null
\t\tState.HANGING:
\t\t\tledge_hang.cancel()
\t\tState.CORNERING:
\t\t\tledge_corner.cancel()
\t\tState.MANTLING:
\t\t\tledge_mantle.cancel()
\tbody.velocity = Vector3.ZERO
\t_exit_traversal_state()
\treturn true


func _candidate_uses_collider(
\tcandidate: PlayerLedgeDetector.LedgeCandidate,
\tcollider_rid: RID
) -> bool:
\tif candidate == null or not collider_rid.is_valid():
\t\treturn false
\treturn (
\t\t(candidate.wall_collider_rid.is_valid() and candidate.wall_collider_rid == collider_rid)
\t\tor (candidate.top_collider_rid.is_valid() and candidate.top_collider_rid == collider_rid)
\t)


"""
text = replace_once(
    text,
    "func update(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:\n",
    controller_invalidation + "func update(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:\n",
    "ledge controller collider invalidation",
)
path.write_text(text, encoding="utf-8")


# Player owns the cross-system invalidation transaction.
path = Path("player/player.gd")
text = path.read_text(encoding="utf-8")
player_invalidation = """func invalidate_world_collider_dependency(collider_rid: RID) -> void:
\tif not collider_rid.is_valid():
\t\treturn
\tif ledge_controller != null:
\t\tledge_controller.invalidate_collider(collider_rid)
\tif ledge_detector != null:
\t\tledge_detector.invalidate_collider(collider_rid)
\tif support != null:
\t\tsupport.invalidate_collider(collider_rid, global_position)


"""
text = replace_once(
    text,
    "func reconcile_carried_junk_prop(prop: Node) -> bool:\n",
    player_invalidation + "func reconcile_carried_junk_prop(prop: Node) -> bool:\n",
    "player collider dependency invalidation",
)
path.write_text(text, encoding="utf-8")


# Focused cross-system regressions.
Path("tests/props/phase_3_5_transition_regressions.gd").write_text("""extends RefCounted


const ApplicationScene = preload(\"res://application/Application.tscn\")
const ApplicationRoot = preload(\"res://application/application_root.gd\")
const OrdinaryProp = preload(\"res://gameplay/props/ordinary_prop.gd\")
const OrdinaryPropScene = preload(\"res://gameplay/props/OrdinaryProp.tscn\")


func run(tree: SceneTree, assert_true: Callable) -> void:
\tvar application: Node = ApplicationScene.instantiate()
\tapplication.set(\"development_launch_labels\", PackedStringArray([\"Prop Lab\"]))
\tapplication.set(\"development_launch_resource_paths\", PackedStringArray([\"res://scenes/PropLab.tscn\"]))
\ttree.get_root().add_child(application)
\tawait tree.process_frame
\tvar launched: bool = bool(application.call(\"launch_development_target\", 0))
\tawait tree.process_frame
\tawait _settle_physics(tree, 3)
\tvar world: Node3D = application.get(\"current_world\") as Node3D
\tvar player: CharacterBody3D = application.get(\"current_player\") as CharacterBody3D
\tassert_true.call(
\t\tlaunched and world != null and player != null
\t\tand int(application.call(\"get_control_mode\")) == ApplicationRoot.ControlMode.GAMEPLAY,
\t\t\"Phase 3.5 transition regressions launch through the production application/player path\"
\t)
\tif world == null or player == null:
\t\treturn
\tvar pickup_prop: RigidBody3D = world.get_node(\"PickupProp\") as RigidBody3D
\tvar edge_prop: RigidBody3D = world.get_node(\"EdgeProp\") as RigidBody3D
\tvar stack_upper: RigidBody3D = world.get_node(\"StackUpper\") as RigidBody3D
\tif pickup_prop == null or edge_prop == null or stack_upper == null:
\t\tassert_true.call(false, \"Phase 3.5 transition fixture exposes required props\")
\t\treturn
\tawait _prove_release_transaction(tree, world, player, pickup_prop, assert_true)
\tawait _prove_support_invalidation(tree, player, edge_prop, assert_true)
\t_prove_traversal_invalidation(player, stack_upper, assert_true)
\tawait _prove_contact_manifold_settle(tree, world, assert_true)
\tapplication.call(\"exit_current_world\")
\tapplication.queue_free()
\tawait tree.process_frame


func _prove_release_transaction(
\ttree: SceneTree,
\tworld: Node3D,
\tplayer: CharacterBody3D,
\tprop: RigidBody3D,
\tassert_true: Callable
) -> void:
\tplayer.global_position = Vector3(0.0, 0.0, 3.1)
\tplayer.rotation.y = 0.0
\tplayer.velocity = Vector3.ZERO
\tvar head: Node3D = player.get_node(\"Head\") as Node3D
\tvar camera: Camera3D = player.get_node(\"Head/Camera3D\") as Camera3D
\thead.rotation.x = 0.0
\tawait _settle_physics(tree)
\tassert_true.call(bool(player.call(\"try_carry_prop\", prop)), \"Transition fixture can carry the representative prop\")
\tvar carry: RefCounted = player.get(\"prop_carry\") as RefCounted
\tif carry == null:
\t\tassert_true.call(false, \"Player exposes the production prop-carry owner\")
\t\treturn
\tvar blocker := StaticBody3D.new()
\tvar blocker_shape := CollisionShape3D.new()
\tvar blocker_box := BoxShape3D.new()
\tblocker_box.size = Vector3(2.0, 3.0, 0.2)
\tblocker_shape.shape = blocker_box
\tblocker.add_child(blocker_shape)
\tworld.add_child(blocker)
\tblocker.global_position = Vector3(0.0, 1.5, 2.15)
\tawait _settle_physics(tree)
\tvar full_release_distance: float = float(carry.get(\"release_distance\"))
\tvar release_origin: Vector3 = camera.global_position
\tvar released: bool = bool(carry.call(\"release_held_gently\"))
\tassert_true.call(
\t\treleased
\t\tand prop.global_position.distance_to(release_origin) < full_release_distance - 0.1
\t\tand bool(prop.call(\"is_release_transform_world_clear\", prop.global_transform, player)),
\t\t\"R release uses the real prop volume and backs away from a world blocker\"
\t)
\tblocker.queue_free()
\tawait tree.process_frame
\tassert_true.call(bool(player.call(\"try_carry_prop\", prop)), \"Released prop can re-enter carried Junk for overlap setup\")
\tcarry.set(\"release_distance\", 0.18)
\tvar thrown: bool = bool(carry.call(\"throw_held\"))
\tassert_true.call(
\t\tthrown
\t\tand prop.call(\"get_motion_kind\") == OrdinaryProp.MOTION_THROWN
\t\tand prop.linear_velocity.length() > 4.0
\t\tand bool(prop.call(\"has_temporary_player_collision_exception\"))
\t\tand player in prop.get_collision_exceptions(),
\t\t\"F throw keeps its impulse through an initial player overlap\"
\t)
\tawait _settle_physics(tree)
\tassert_true.call(prop.linear_velocity.length() > 2.0, \"Initial player overlap does not cancel throw velocity\")
\tvar cleared: bool = await _wait_for_player_exception_clear(tree, prop, player, 40)
\tassert_true.call(
\t\tcleared and not bool(prop.call(\"has_temporary_player_collision_exception\"))
\t\tand not (player in prop.get_collision_exceptions()),
\t\t\"Temporary prop-player collision exclusion ends after geometric separation\"
\t)
\tcarry.set(\"release_distance\", full_release_distance)
\tawait _settle_until_phase(tree, prop, OrdinaryProp.PHASE_SETTLED, 240)


func _prove_support_invalidation(
\ttree: SceneTree,
\tplayer: CharacterBody3D,
\tprop: RigidBody3D,
\tassert_true: Callable
) -> void:
\tplayer.global_position = Vector3(-1.68, 1.2, 0.0)
\tplayer.velocity = Vector3.ZERO
\tawait _settle_physics(tree)
\tvar support: RefCounted = player.get(\"support\") as RefCounted
\tsupport.call(\"update\", player)
\tvar contact: PlayerSupportContact = support.call(\"get_contact\") as PlayerSupportContact
\tassert_true.call(
\t\tcontact != null and contact.valid and contact.collider_rid == prop.get_rid()
\t\tand bool(player.call(\"is_grounded\")),
\t\t\"Player support records the exact ordinary-prop collider RID\"
\t)
\tvar start_y: float = player.global_position.y
\tassert_true.call(bool(player.call(\"try_carry_prop\", prop)), \"Standing support prop can be picked up\")
\tassert_true.call(not bool(player.call(\"is_grounded\")), \"Picking up the exact support invalidates grounding immediately\")
\tawait _settle_physics(tree, 4)
\tassert_true.call(player.global_position.y < start_y - 0.001, \"Player falls after supporting prop leaves world participation\")
\tvar carry: RefCounted = player.get(\"prop_carry\") as RefCounted
\tif carry != null and bool(carry.call(\"has_held_prop\")):
\t\tcarry.call(\"release_held_gently\")
\tawait _settle_physics(tree, 2)


func _prove_traversal_invalidation(
\tplayer: CharacterBody3D,
\tprop: RigidBody3D,
\tassert_true: Callable
) -> void:
\tvar controller: RefCounted = player.get(\"ledge_controller\") as RefCounted
\tvar hang: RefCounted = player.get(\"ledge_hang\") as RefCounted
\tvar corner: RefCounted = player.get(\"ledge_corner\") as RefCounted
\tvar mantle: RefCounted = player.get(\"ledge_mantle\") as RefCounted
\tif controller == null or hang == null or corner == null or mantle == null:
\t\tassert_true.call(false, \"Traversal components exist for collider invalidation\")
\t\treturn
\tvar candidate := PlayerLedgeDetector.LedgeCandidate.new()
\tcandidate.wall_collider_rid = prop.get_rid()
\tcandidate.top_collider_rid = prop.get_rid()
\tcandidate.wall_normal = Vector3.FORWARD
\tcandidate.top_normal = Vector3.UP
\tcandidate.ledge_direction = Vector3.RIGHT
\tcandidate.hangable = true
\tcontroller.set(\"active_catch_candidate\", candidate)
\tcontroller.set(\"state\", PlayerLedgeController.State.CATCHING)
\tassert_true.call(bool(controller.call(\"invalidate_collider\", prop.get_rid())) and int(controller.get(\"state\")) == PlayerLedgeController.State.NONE, \"Catch state invalidates with its prop collider\")
\thang.call(\"start\", candidate)
\tcontroller.set(\"state\", PlayerLedgeController.State.HANGING)
\tassert_true.call(not bool(controller.call(\"invalidate_collider\", RID())) and int(controller.get(\"state\")) == PlayerLedgeController.State.HANGING, \"Unrelated collider invalidation leaves hang active\")
\tassert_true.call(bool(controller.call(\"invalidate_collider\", prop.get_rid())) and int(controller.get(\"state\")) == PlayerLedgeController.State.NONE, \"Hang state invalidates with its prop collider\")
\tvar corner_candidate := PlayerLedgeCorner.CornerCandidate.new()
\tcorner_candidate.source_candidate = candidate
\tcorner_candidate.target_candidate = candidate
\tcorner.set(\"active_corner\", corner_candidate)
\tcontroller.set(\"state\", PlayerLedgeController.State.CORNERING)
\tassert_true.call(bool(controller.call(\"invalidate_collider\", prop.get_rid())) and int(controller.get(\"state\")) == PlayerLedgeController.State.NONE, \"Corner state invalidates with its prop collider\")
\tvar mantle_candidate := PlayerMantle.MantleCandidate.new()
\tmantle_candidate.source_candidate = candidate
\tmantle_candidate.valid = true
\tmantle.set(\"active_candidate\", mantle_candidate)
\tmantle.set(\"phase\", PlayerMantle.Phase.LIFT)
\tcontroller.set(\"state\", PlayerLedgeController.State.MANTLING)
\tassert_true.call(bool(controller.call(\"invalidate_collider\", prop.get_rid())) and int(controller.get(\"state\")) == PlayerLedgeController.State.NONE, \"Mantle state invalidates with its prop collider\")


func _prove_contact_manifold_settle(tree: SceneTree, world: Node3D, assert_true: Callable) -> void:
\tvar support_body := StaticBody3D.new()
\tvar support_shape := CollisionShape3D.new()
\tvar support_box := BoxShape3D.new()
\tsupport_box.size = Vector3(0.12, 0.8, 0.12)
\tsupport_shape.shape = support_box
\tsupport_body.add_child(support_shape)
\tworld.add_child(support_body)
\tsupport_body.global_position = Vector3(3.0, 0.4, 2.5)
\tvar prop: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
\tworld.add_child(prop)
\tawait tree.process_frame
\tvar tilted_basis := Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(30.0))
\tvar moving_state := {
\t\t\"phase\": OrdinaryProp.PHASE_MOVING,
\t\t\"motion_kind\": OrdinaryProp.MOTION_UNSUPPORTED,
\t\t\"transform\": Transform3D(tilted_basis, Vector3(3.0, 1.25, 2.5)),
\t\t\"linear_velocity\": Vector3.ZERO,
\t\t\"settle_yaw\": 0.0,
\t}
\tassert_true.call(bool(prop.call(\"apply_semantic_state\", moving_state)), \"Narrow-support fixture enters moving rigid-body state\")
\tawait _settle_until_phase(tree, prop, OrdinaryProp.PHASE_SETTLED, 220)
\tassert_true.call(
\t\tprop.call(\"get_semantic_phase\") == OrdinaryProp.PHASE_SETTLED
\t\tand prop.freeze
\t\tand prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999
\t\tand absf(prop.global_position.y - 1.1) <= 0.025
\t\tand bool(prop.call(\"is_supported\")),
\t\t\"Tilted box settles from real contact state on a narrow support the retired corner-ray authority misses\"
\t)
\tprop.queue_free()
\tsupport_body.queue_free()
\tawait tree.process_frame


func _wait_for_player_exception_clear(tree: SceneTree, prop: RigidBody3D, player: CharacterBody3D, max_frames: int) -> bool:
\tfor _frame_index: int in max_frames:
\t\tif not bool(prop.call(\"has_temporary_player_collision_exception\")) and not (player in prop.get_collision_exceptions()):
\t\t\treturn true
\t\tawait tree.physics_frame
\t\tawait tree.process_frame
\treturn false


func _settle_until_phase(tree: SceneTree, prop: Node, target_phase: StringName, max_frames: int) -> void:
\tfor _frame_index: int in max_frames:
\t\tif prop.call(\"get_semantic_phase\") == target_phase:
\t\t\treturn
\t\tawait tree.physics_frame
\t\tawait tree.process_frame


func _settle_physics(tree: SceneTree, frame_count: int = 1) -> void:
\tfor _frame_index: int in frame_count:
\t\tawait tree.physics_frame
\t\tawait tree.process_frame
""", encoding="utf-8")


# Wire the new focused regression into the existing authoritative props suite.
path = Path("tests/props/run_prop_tests.gd")
text = path.read_text(encoding="utf-8")
text = replace_once(
    text,
    'const PropRegressions = preload("res://tests/props/prop_regressions.gd")\n',
    'const PropRegressions = preload("res://tests/props/prop_regressions.gd")\nconst TransitionRegressions = preload("res://tests/props/phase_3_5_transition_regressions.gd")\n',
    "props runner preload",
)
text = replace_once(
    text,
    "\n\t_print_summary()\n",
    "\n\tvar transition_regressions: RefCounted = TransitionRegressions.new()\n\tawait transition_regressions.run(self, Callable(self, \"_assert_true\"))\n\n\t_print_summary()\n",
    "props runner invocation",
)
path.write_text(text, encoding="utf-8")


# GAME_VISION: explicit transition ownership.
path = Path("docs/GAME_VISION.md")
text = path.read_text(encoding="utf-8")
anchor = "Throw and release restore the same prop to ordinary world participation with collision enabled. Throw applies substantial forward velocity. Release is deliberately gentler and should normally create less impact/noise than throwing.\n"
insert = anchor + "\nRelease placement uses the prop's real collision volume. World geometry and other physical objects remain solid blockers. If the nearest valid release pose still overlaps the releasing player's capsule, only that prop↔player pair is temporarily non-colliding so the object can leave the player's volume without having its throw/release impulse destroyed. Normal prop↔player collision returns automatically as soon as the collision volumes are geometrically separated; this is derived transient physics state, never a timer, arbitrary travel-distance rule, global collision-layer change, or saved semantic state.\n\nA prop that leaves world participation also invalidates player state derived from that exact collider. Standing support and active catch/hang/corner/mantle attachment cannot outlive a prop that has been picked up as carried Junk.\n"
text = replace_once(text, anchor, insert, "GAME_VISION release ownership")
anchor = "Once motion resolves, the object becomes settled again. Supported/settled props then resume the ordinary stylized support rules above.\n"
insert = "Genuine dynamic rest is recognized from the rigid body's actual support/contact state rather than guessed proximity samples. This keeps edge/corner box-on-box contacts eligible to finish settling when the physics solver is already holding the object at rest.\n\n" + anchor
text = replace_once(text, anchor, insert, "GAME_VISION contact settling")
path.write_text(text, encoding="utf-8")


# DEVELOPMENT_PLAN: keep Phase 3.5 in progress with the correction dependency order.
path = Path("docs/DEVELOPMENT_PLAN.md")
text = path.read_text(encoding="utf-8")
start_marker = "## 3.5 Thief-style prop micro-proof `[~]`"
end_marker = "## 3.6 Acoustic propagation micro-proof"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit("DEVELOPMENT_PLAN Phase 3.5 markers not found")
new_section = """## 3.5 Thief-style prop micro-proof `[~]`

The carried-Junk implementation is complete enough for focused correction and acceptance. Keep the dependency order explicit:

1. **Release/throw collision transaction.** Release placement uses the prop's real collision volume and keeps world/other-prop blockers authoritative. A release pose may temporarily ignore only the releasing player when the two volumes overlap; the exception ends from geometric separation, not a timer or distance guess.
2. **Player dependency invalidation.** Picking up a prop immediately invalidates standing support and active catch/hang/corner/mantle state derived from that exact collider RID. Unrelated support/traversal state remains untouched.
3. **Dynamic settling authority.** Moving/settling props use the real rigid-body contact manifold to identify support/rest candidates. The old lowest-corner proximity-ray heuristic is not settling authority. Final top-up normalization preserves yaw and re-seats the box on the detected support plane before freezing.
4. **Acceptance.** Keep the existing carried-Junk HUD, F throw, R gentle release, hard-edged rendering, real rigid translation, stable settled edge/stack behavior, semantic sound/capture/reconcile seams, and accepted player movement feel unchanged.

**Done when:** world/prop blockers remain solid during release placement; an initially player-overlapping throw retains its intended impulse and restores normal player collision after separation; picking up the exact supporting/traversal prop ends that dependency immediately; low-speed tilted box-on-box contact can reach supported top-up settle from real contact state; yaw/no-gap/no-drift behavior remains; and the authoritative all-tests barrier plus Windows x64 user acceptance pass.

**Automated:** required — the dedicated Props suite must exercise shape-aware world-blocked placement, overlapping-player throw impulse preservation, pairwise exception lifetime, exact support RID invalidation, catch/hang/corner/mantle collider invalidation, real-contact narrow-support settling, existing prop behavior, and the unchanged movement regression suite through `tests/run_all_tests.gd`.

**Manual:** pending — validator: **Windows x64 user/playtester**. Launch **Development Launch → Prop Lab**. Confirm F pickup/HUD, movement/look/crouch/jump, F throw, R release, edge support, stacking, lower-support fall, hard-edged rendering, yaw-preserving top-up, and no hover/drift. Also test cramped release/throw near the player: the box may leave an initial player overlap without losing the throw, must still respect walls/props, and must collide with the player normally after separation. Stand on a prop and pick it up: support must end and the player must fall. Exercise a prop-based hang/catch/corner/mantle where practical and confirm pickup immediately ends the attachment. Repeatedly release tilted boxes onto box edges/corners and confirm genuine rest reaches top-up supported settle.

"""
text = text[:start] + new_section + text[end:]
path.write_text(text, encoding="utf-8")


# TESTING: record the new production-boundary coverage.
path = Path("docs/TESTING.md")
text = path.read_text(encoding="utf-8")
start_marker = "Phase 3.5 has a dedicated Props suite wired through the authoritative all-tests barrier."
start = text.find(start_marker)
end = text.find("\n\nThe movement runner currently:", start)
if start < 0 or end < 0:
    raise SystemExit("TESTING Phase 3.5 coverage markers not found")
coverage = "Phase 3.5 has a dedicated Props suite wired through the authoritative all-tests barrier. It retains the production-path Prop Lab coverage for outward/hard OBJ normals, normal lit/shadowed presentation, external-model replacement, real `RigidBody3D` ownership, frozen settled state, single-slot `carried_junk`, bottom-center HUD presentation, normal locomotion while carrying, central interaction/hand suppression, stale F/R edge suppression, F throw versus R release, semantic sound, detached capture/reconcile, edge support, stable stacks, lower-support fall, yaw-preserving top-up, no support gap, and no post-settle drift/spin. A second focused Phase 3.5 transition regression exercises the cross-system failure boundaries directly: shape-volume-aware release backs away from a world blocker; a valid throw pose intentionally overlapping the player retains its throw impulse; only the prop↔player pair is temporarily excluded and the exception disappears after geometric separation; standing support stores and invalidates the exact prop collider RID; catch/hang/corner/mantle state is canceled only when its referenced collider is invalidated; and a tilted moving crate resting on a narrow support settles from the real rigid-body contact manifold in a geometry case the retired lowest-corner ray heuristic cannot see. The authoritative all-tests barrier continues to run the accepted movement suite alongside these corrections. Acoustic propagation remains Phase 3.6."
text = text[:start] + coverage + text[end:]
path.write_text(text, encoding="utf-8")
