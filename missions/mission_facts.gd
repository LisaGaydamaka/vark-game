class_name VarkMissionFacts
extends RefCounted


const TYPE_BOOL: StringName = &"bool"
const TYPE_INT: StringName = &"int"
const TYPE_FLOAT: StringName = &"float"
const TYPE_STRING: StringName = &"string"

const SCOPE_MISSION: StringName = &"mission"
const SCOPE_RUNTIME: StringName = &"runtime"

const FACT_SET_REQUESTED_EVENT_NAME: StringName = &"mission.fact_set_requested"
const FACT_CHANGED_EVENT_NAME: StringName = &"mission.fact_changed"


var _declarations: Dictionary = {}
var _values: Dictionary = {}
var _last_error: String = ""


static func validate_declarations(
	declarations: Array[Dictionary]
) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen: Dictionary[String, bool] = {}
	for index: int in declarations.size():
		var declaration: Dictionary = declarations[index]
		var prefix: String = "mission_fact_declarations[%d]" % index
		if (
			declaration.size() != 4
			or not declaration.has("key")
			or not declaration.has("type")
			or not declaration.has("default")
			or not declaration.has("scope")
		):
			errors.append(
				"%s must contain exactly key, type, default, and scope."
				% prefix
			)
			continue

		var key: String = str(declaration.get("key", "")).strip_edges()
		var fact_type := StringName(str(declaration.get("type", "")).strip_edges())
		var scope := StringName(str(declaration.get("scope", "")).strip_edges())
		var default_value: Variant = declaration.get("default")

		if key.is_empty():
			errors.append("%s key must not be empty." % prefix)
		elif seen.has(key):
			errors.append("%s duplicates fact key '%s'." % [prefix, key])
		else:
			seen[key] = true

		if not _is_supported_type(fact_type):
			errors.append(
				"%s type '%s' is unsupported; use bool, int, float, or string."
				% [prefix, fact_type]
			)
		elif not _value_matches_type(default_value, fact_type):
			errors.append(
				"%s default does not match declared type '%s'."
				% [prefix, fact_type]
			)

		if scope != SCOPE_MISSION and scope != SCOPE_RUNTIME:
			errors.append(
				"%s scope '%s' is unsupported; use mission or runtime."
				% [prefix, scope]
			)
	return errors


func configure(declarations: Array[Dictionary]) -> bool:
	_last_error = ""
	var errors: PackedStringArray = validate_declarations(declarations)
	if not errors.is_empty():
		_last_error = "
".join(errors)
		return false

	_declarations.clear()
	_values.clear()
	for declaration: Dictionary in declarations:
		var key := StringName(str(declaration.get("key", "")).strip_edges())
		var normalized: Dictionary = {
			"key": key,
			"type": StringName(str(declaration.get("type", "")).strip_edges()),
			"default": declaration.get("default"),
			"scope": StringName(str(declaration.get("scope", "")).strip_edges()),
		}
		_declarations[key] = normalized.duplicate(true)
		_values[key] = normalized["default"]
	return true


func get_last_error() -> String:
	return _last_error


func has_fact(key: StringName) -> bool:
	return _declarations.has(key)


func get_value(key: StringName, fallback: Variant = null) -> Variant:
	if not _values.has(key):
		return fallback
	return _values[key]


func get_type(key: StringName) -> StringName:
	if not _declarations.has(key):
		return &""
	return (_declarations[key] as Dictionary).get("type", &"")


func get_scope(key: StringName) -> StringName:
	if not _declarations.has(key):
		return &""
	return (_declarations[key] as Dictionary).get("scope", &"")


func get_declarations() -> Array[Dictionary]:
	var keys: Array = _declarations.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	var result: Array[Dictionary] = []
	for key_value: Variant in keys:
		var declaration: Dictionary = _declarations[key_value]
		result.append(declaration.duplicate(true))
	return result


func get_all_values() -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = _values.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for key_value: Variant in keys:
		result[str(key_value)] = _values[key_value]
	return result


func can_assign(key: StringName, value: Variant) -> bool:
	_last_error = ""
	if not _declarations.has(key):
		_last_error = "Unknown mission fact '%s'." % key
		return false
	var declaration: Dictionary = _declarations[key]
	var fact_type: StringName = declaration.get("type", &"")
	if not _value_matches_type(value, fact_type):
		_last_error = (
			"Mission fact '%s' requires type '%s'."
			% [key, fact_type]
		)
		return false
	return true


func set_value_controlled(key: StringName, value: Variant) -> Dictionary:
	if not can_assign(key, value):
		return {"ok": false, "changed": false}
	var changed: bool = _values[key] != value
	if changed:
		_values[key] = value
	return {"ok": true, "changed": changed}


func capture_semantic_state() -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = _declarations.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for key_value: Variant in keys:
		var key := StringName(str(key_value))
		var declaration: Dictionary = _declarations[key]
		if declaration.get("scope", &"") == SCOPE_MISSION:
			result[str(key)] = _values[key]
	return result


func get_default_semantic_state() -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = _declarations.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for key_value: Variant in keys:
		var key := StringName(str(key_value))
		var declaration: Dictionary = _declarations[key]
		if declaration.get("scope", &"") == SCOPE_MISSION:
			result[str(key)] = declaration.get("default")
	return result


func validate_semantic_state(snapshot: Dictionary) -> bool:
	_last_error = ""
	var expected: Dictionary = get_default_semantic_state()
	if snapshot.size() != expected.size():
		_last_error = "Mission fact snapshot has the wrong set of mission-scoped keys."
		return false
	for key_value: Variant in expected.keys():
		var key_text: String = str(key_value)
		if not snapshot.has(key_text):
			_last_error = "Mission fact snapshot is missing '%s'." % key_text
			return false
		var key := StringName(key_text)
		var declaration: Dictionary = _declarations[key]
		var fact_type: StringName = declaration.get("type", &"")
		if not _value_matches_type(snapshot[key_text], fact_type):
			_last_error = (
				"Mission fact snapshot value '%s' does not match type '%s'."
				% [key_text, fact_type]
			)
			return false
	return true


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if not validate_semantic_state(snapshot):
		return false

	for key_value: Variant in _declarations.keys():
		var key := StringName(str(key_value))
		var declaration: Dictionary = _declarations[key]
		_values[key] = declaration.get("default")

	for key_value: Variant in snapshot.keys():
		var key := StringName(str(key_value))
		_values[key] = snapshot[key_value]
	return true


static func _is_supported_type(fact_type: StringName) -> bool:
	return (
		fact_type == TYPE_BOOL
		or fact_type == TYPE_INT
		or fact_type == TYPE_FLOAT
		or fact_type == TYPE_STRING
	)


static func _value_matches_type(value: Variant, fact_type: StringName) -> bool:
	match fact_type:
		TYPE_BOOL:
			return typeof(value) == TYPE_BOOL
		TYPE_INT:
			return typeof(value) == TYPE_INT
		TYPE_FLOAT:
			return typeof(value) == TYPE_FLOAT
		TYPE_STRING:
			return typeof(value) == TYPE_STRING
	return false
