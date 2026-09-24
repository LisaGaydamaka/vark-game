extends SceneTree


const PersistentIdentityValidator = preload(
	"res://missions/persistence/persistent_identity_validator.gd"
)
const OrdinaryDoor = preload("res://gameplay/doors/ordinary_door.gd")
const OrdinaryProp = preload("res://gameplay/props/ordinary_prop.gd")

const MAP_SETTINGS_PATH: String = "res://authoring/vark_map_settings.tres"
const WORKSPACE_PATH: String = "res://tests/authoring/workspace/mission.map"
const PROOF_DOOR_ID: String = "phase8.workflow.door"
const PROOF_PROP_ID: StringName = &"phase8.workflow.prop"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var map_path: String = WORKSPACE_PATH
	if not args.is_empty():
		map_path = args[0]

	var result: Dictionary = await verify_map(get_root(), map_path)
	if not bool(result.get("ok", false)):
		var errors: PackedStringArray = result.get("errors", PackedStringArray())
		for error_message: String in errors:
			push_error(error_message)
		quit(1)
		return

	var door: Dictionary = result.get("door", {})
	var prop: Dictionary = result.get("prop", {})
	print("Phase 8.1 mapper workflow proof passed.")
	print("  source: ", map_path)
	print(
		"  opening: id=%s persistent_id=%s variant=%s model=%s"
		% [
			str(door.get("door_id", "")),
			str(door.get("persistent_id", "")),
			str(door.get("opening_variant", "")),
			str(door.get("visual_model_path", "")),
		]
	)
	print(
		"  prop:    id=%s persistent_id=%s variant=%s model=%s collision=%s"
		% [
			str(prop.get("prop_id", &"")),
			str(prop.get("persistent_id", "")),
			str(prop.get("prop_variant", "")),
			str(prop.get("visual_model_path", "")),
			str(prop.get("collision_size", Vector3.ZERO)),
		]
	)
	print("The verifier is read-only; the mapper .map source was unchanged.")
	quit(0)


static func verify_map(root: Node, map_path: String) -> Dictionary:
	var errors := PackedStringArray()
	if root == null or root.get_tree() == null:
		errors.append("Mapper workflow verification requires an active SceneTree root.")
		return {"ok": false, "errors": errors}
	if not FileAccess.file_exists(map_path):
		errors.append(
			"Mapper workflow source does not exist: %s. Prepare/reset the ignored workspace first."
			% map_path
		)
		return {"ok": false, "errors": errors}

	var source_before: String = FileAccess.get_file_as_string(map_path)
	var map_settings := load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	if map_settings == null:
		errors.append("Could not load Vark FuncGodot map settings.")
		return {"ok": false, "errors": errors}

	var func_map := FuncGodotMap.new()
	func_map.map_settings = map_settings
	func_map.local_map_file = map_path
	func_map.build()
	root.add_child(func_map)
	await root.get_tree().process_frame

	var proof_door: VarkOrdinaryDoor = null
	var proof_prop: VarkOrdinaryProp = null
	var door_count: int = 0
	var prop_count: int = 0
	for node: Node in func_map.find_children("*", "", true, false):
		if node.get_script() == OrdinaryDoor:
			door_count += 1
			var door := node as VarkOrdinaryDoor
			if door != null and door.door_id == PROOF_DOOR_ID:
				proof_door = door
		elif node.get_script() == OrdinaryProp:
			prop_count += 1
			var prop := node as VarkOrdinaryProp
			if prop != null and prop.prop_id == PROOF_PROP_ID:
				proof_prop = prop

	var identity_result: Dictionary = PersistentIdentityValidator.validate_subtree(
		func_map
	)
	if not bool(identity_result.get("ok", false)):
		var identity_errors: PackedStringArray = identity_result.get(
			"errors",
			PackedStringArray()
		)
		for error_message: String in identity_errors:
			errors.append(error_message)

	var door_summary: Dictionary = {}
	if proof_door == null:
		errors.append(
			"Add one vark_opening with door_id '%s' and choose the Narrow opening variant."
			% PROOF_DOOR_ID
		)
	else:
		door_summary = {
			"persistent_id": proof_door.persistent_id,
			"door_id": proof_door.door_id,
			"opening_variant": proof_door.opening_variant,
			"visual_model_path": proof_door.get_visual_model_path(),
		}
		if proof_door.persistent_id.strip_edges().is_empty():
			errors.append(
				"The Phase 8 proof opening has no persistent_id; run the existing repair command, then reload TrenchBroom."
			)
		if proof_door.opening_variant != OrdinaryDoor.OPENING_VARIANT_NARROW:
			errors.append(
				"The Phase 8 proof opening must use the Narrow opening choice."
			)
		if (
			proof_door.get_visual_model_path()
			!= OrdinaryDoor.OPENING_VARIANT_NARROW_MODEL_PATH
		):
			errors.append(
				"The Narrow opening choice did not resolve its compatible narrow external model while visual_model_path was blank."
			)

	var prop_summary: Dictionary = {}
	if proof_prop == null:
		errors.append(
			"Add one vark_prop with prop_id '%s' and choose the Tall crate variant."
			% str(PROOF_PROP_ID)
		)
	else:
		prop_summary = {
			"persistent_id": proof_prop.persistent_id,
			"prop_id": proof_prop.prop_id,
			"prop_variant": proof_prop.prop_variant,
			"visual_model_path": proof_prop.get_visual_model_path(),
			"collision_size": proof_prop.get_collision_size(),
		}
		if proof_prop.persistent_id.strip_edges().is_empty():
			errors.append(
				"The Phase 8 proof prop has no persistent_id; run the existing repair command, then reload TrenchBroom."
			)
		if proof_prop.prop_variant != OrdinaryProp.PROP_VARIANT_TALL_CRATE:
			errors.append(
				"The Phase 8 proof prop must use the Tall crate choice."
			)
		if (
			proof_prop.get_visual_model_path()
			!= OrdinaryProp.PROP_VARIANT_TALL_MODEL_PATH
		):
			errors.append(
				"The Tall crate choice did not resolve its compatible tall external model while visual_model_path was blank."
			)
		if not proof_prop.get_collision_size().is_equal_approx(
			OrdinaryProp.PROP_VARIANT_TALL_COLLISION_SIZE
		):
			errors.append(
				"The Tall crate choice did not resolve its compatible collision dimensions while the authored collision_size stayed at the shared default."
			)

	var source_after: String = FileAccess.get_file_as_string(map_path)
	if source_after != source_before:
		errors.append(
			"Mapper workflow verification changed the authoritative .map source; the verifier must remain read-only."
		)

	var result: Dictionary = {
		"ok": errors.is_empty(),
		"errors": errors,
		"source_unchanged": source_after == source_before,
		"identity_valid": bool(identity_result.get("ok", false)),
		"door_count": door_count,
		"prop_count": prop_count,
		"door": door_summary.duplicate(true),
		"prop": prop_summary.duplicate(true),
	}
	func_map.queue_free()
	await root.get_tree().process_frame
	return result
