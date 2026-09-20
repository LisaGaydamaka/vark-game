class_name VarkAcousticDebugInspector
extends Node3D


@export var propagation_path: NodePath
@export var label_path: NodePath = NodePath("StatusLabel")
@export var refresh_each_physics_frame: bool = true

var _propagation: VarkAcousticPropagation = null
var _label: Label3D = null
var _debug_text: String = ""


func _ready() -> void:
	_propagation = get_node_or_null(
		propagation_path
	) as VarkAcousticPropagation
	_label = get_node_or_null(label_path) as Label3D
	refresh_now()


func _physics_process(_delta: float) -> void:
	if refresh_each_physics_frame:
		refresh_now()


func refresh_now() -> String:
	if (
		_propagation == null
		or not is_instance_valid(_propagation)
	):
		_debug_text = "ACOUSTIC\nUNAVAILABLE"
		_apply_label()
		return _debug_text

	var inspection: Dictionary = _propagation.get_debug_inspection()
	var summary: Dictionary = inspection.get("summary", {})
	var lines: PackedStringArray = PackedStringArray([
		"ACOUSTIC spaces=%d portals=%d listeners=%d"
		% [
			int(summary.get("space_count", 0)),
			int(summary.get("portal_count", 0)),
			int(summary.get("listener_count", 0)),
		],
	])

	for portal: Dictionary in inspection.get("portals", []):
		var route: String = "%s<->%s" % [
			str(portal.get("space_a_id", &"")),
			str(portal.get("space_b_id", &"")),
		]
		if bool(portal.get("uses_door", false)):
			lines.append(
				"%s %s door=%s open=%.2f tx=%.3f"
				% [
					str(portal.get("portal_id", &"")),
					route,
					str(portal.get("door_id", &"")),
					float(portal.get("door_openness", 0.0)),
					float(portal.get("current_transmission", 0.0)),
				]
			)
		else:
			lines.append(
				"%s %s opening tx=%.3f"
				% [
					str(portal.get("portal_id", &"")),
					route,
					float(portal.get("current_transmission", 0.0)),
				]
			)

	var last_sound: Dictionary = inspection.get("last_sound", {})
	if not last_sound.is_empty():
		lines.append(
			"last=%s src=%.3f"
			% [
				str(last_sound.get("kind", &"")),
				float(last_sound.get("source_strength", 0.0)),
			]
		)
		for perception: Dictionary in last_sound.get(
			"listeners",
			[]
		):
			var route_text: String = str(
				perception.get("portal_route", [])
			)
			if (perception.get("portal_route", []) as Array).is_empty():
				route_text = "direct"
			lines.append(
				"%s %s %.3f/%.3f route=%s"
				% [
					str(perception.get("listener_id", &"")),
					"HEARD"
					if bool(perception.get("heard", false))
					else "MUTED",
					float(perception.get(
						"propagated_strength",
						0.0
					)),
					float(perception.get(
						"hearing_threshold",
						0.0
					)),
					route_text,
				]
			)

	_debug_text = "\n".join(lines)
	_apply_label()
	return _debug_text


func get_debug_text() -> String:
	return _debug_text


func _apply_label() -> void:
	if _label != null and is_instance_valid(_label):
		_label.text = _debug_text
