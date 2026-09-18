class_name VarkAcousticListener
extends Node3D


signal gameplay_sound_heard(perception: Dictionary)


@export var listener_id: StringName = &"listener"
@export var hearing_threshold: float = 0.08
@export var print_debug_events: bool = false

var _heard_count: int = 0
var _last_perception: Dictionary = {}


func _ready() -> void:
	add_to_group(&"vark_acoustic_listener")
	_refresh_debug_label()


func receive_gameplay_sound(event: Dictionary, propagation: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	var propagated_strength: float = float(
		propagation.get("propagated_strength", 0.0)
	)
	var threshold: float = maxf(hearing_threshold, 0.000001)
	var heard: bool = (
		bool(propagation.get("route_found", false))
		and propagated_strength >= threshold
	)
	_last_perception = {
		"heard": heard,
		"listener_id": listener_id,
		"kind": payload.get("kind", &""),
		"origin": payload.get("origin", Vector3.ZERO),
		"source_strength": float(payload.get("strength", 0.0)),
		"propagated_strength": propagated_strength,
		"hearing_threshold": threshold,
		"source_space_id": propagation.get("source_space_id", &""),
		"listener_space_id": propagation.get("listener_space_id", &""),
		"portal_route": (propagation.get("portal_route", []) as Array).duplicate(true),
	}
	if heard:
		_heard_count += 1
		gameplay_sound_heard.emit(_last_perception.duplicate(true))
	if print_debug_events:
		print(
			"[ACOUSTIC] %s %s kind=%s propagated=%.3f threshold=%.3f route=%s"
			% [
				listener_id,
				"HEARD" if heard else "MUTED",
				str(_last_perception["kind"]),
				propagated_strength,
				threshold,
				str(_last_perception["portal_route"]),
			]
		)
	_refresh_debug_label()
	return true


func get_heard_count() -> int:
	return _heard_count


func get_last_perception() -> Dictionary:
	return _last_perception.duplicate(true)


func clear_perception() -> void:
	_heard_count = 0
	_last_perception.clear()
	_refresh_debug_label()


func _refresh_debug_label() -> void:
	var label: Label3D = get_node_or_null("StatusLabel") as Label3D
	if label == null:
		return
	if _last_perception.is_empty():
		label.text = "%s\nthreshold %.2f\nWAITING" % [listener_id, hearing_threshold]
		return
	label.text = "%s\n%s %s\n%.3f / %.3f\n%s" % [
		listener_id,
		"HEARD" if bool(_last_perception.get("heard", false)) else "MUTED",
		str(_last_perception.get("kind", &"")),
		float(_last_perception.get("propagated_strength", 0.0)),
		float(_last_perception.get("hearing_threshold", hearing_threshold)),
		str(_last_perception.get("portal_route", [])),
	]
