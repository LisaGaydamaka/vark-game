class_name VarkGameplayExposure
extends Node3D


@export var player_path: NodePath = NodePath("../Player")
@export var debug_label_path: NodePath = NodePath("../ExposureHUD/Panel/VBox/Readout")
@export var debug_bar_path: NodePath = NodePath("../ExposureHUD/Panel/VBox/ExposureBar")

var _player: CharacterBody3D = null
var _lights: Array[VarkGameplayLight] = []
var _current_exposure: float = 0.0
var _last_summary: Dictionary = {}
var _debug_label: Label = null
var _debug_bar: ProgressBar = null


func _ready() -> void:
	add_to_group(&"vark_gameplay_exposure")
	_player = get_node_or_null(player_path) as CharacterBody3D
	_debug_label = get_node_or_null(debug_label_path) as Label
	_debug_bar = get_node_or_null(debug_bar_path) as ProgressBar
	refresh_sources()
	sample_now()


func _physics_process(_delta: float) -> void:
	sample_now()


func refresh_sources() -> void:
	_lights.clear()
	var root: Node = get_parent()
	if root == null:
		return
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	for node: Node in nodes:
		if node is VarkGameplayLight:
			_lights.append(node as VarkGameplayLight)
	_lights.sort_custom(
		func(a: VarkGameplayLight, b: VarkGameplayLight) -> bool:
			return str(a.gameplay_light_id) < str(b.gameplay_light_id)
	)


func get_current_exposure() -> float:
	return _current_exposure


func get_exposure_summary() -> Dictionary:
	return _last_summary.duplicate(true)


func sample_now() -> Dictionary:
	if _player == null or not is_instance_valid(_player) or not is_inside_tree():
		_current_exposure = 0.0
		_last_summary = {
			"exposure": 0.0,
			"sample_count": 0,
			"active_light_count": 0,
			"lights": [],
			"error": "Gameplay exposure has no valid player.",
		}
		_update_debug_readout()
		return get_exposure_summary()

	var samples: Array[Vector3] = _get_player_sample_points()
	var light_summaries: Array[Dictionary] = []
	var total_exposure: float = 0.0
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	for light: VarkGameplayLight in _lights:
		if light == null or not is_instance_valid(light):
			continue
		var light_total: float = 0.0
		var visible_samples: int = 0
		var sample_summaries: Array[Dictionary] = []
		for sample_position: Vector3 in samples:
			var sample_summary: Dictionary = light.sample_gameplay_exposure(
				sample_position,
				space_state
			)
			var contribution: float = float(
				sample_summary.get("contribution", 0.0)
			)
			light_total += contribution
			if contribution > 0.0 and not bool(sample_summary.get("occluded", false)):
				visible_samples += 1
			sample_summaries.append(sample_summary)

		var average_contribution: float = (
			light_total / float(samples.size())
			if not samples.is_empty()
			else 0.0
		)
		total_exposure += average_contribution
		light_summaries.append({
			"light_id": light.gameplay_light_id,
			"contribution": average_contribution,
			"visible_samples": visible_samples,
			"sample_count": samples.size(),
			"samples": sample_summaries,
		})

	_current_exposure = clampf(total_exposure, 0.0, 1.0)
	_last_summary = {
		"exposure": _current_exposure,
		"raw_exposure": total_exposure,
		"sample_count": samples.size(),
		"active_light_count": _lights.size(),
		"lights": light_summaries,
		"error": "",
	}
	_update_debug_readout()
	return get_exposure_summary()


func _get_player_sample_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var collision := _player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var capsule: CapsuleShape3D = (
		collision.shape as CapsuleShape3D
		if collision != null
		else null
	)
	if collision == null or capsule == null:
		points.append(_player.global_position + Vector3.UP * 0.75)
		return points

	# Three vertical samples intentionally keep this prototype legible:
	# lower body, torso, and upper body. The algorithm remains OPEN until the
	# visual playtest says these weights/positions feel right.
	var offset: float = capsule.height * 0.30
	points.append(collision.to_global(Vector3(0.0, -offset, 0.0)))
	points.append(collision.global_position)
	points.append(collision.to_global(Vector3(0.0, offset, 0.0)))
	return points


func _update_debug_readout() -> void:
	if _debug_bar != null:
		_debug_bar.value = _current_exposure
	if _debug_label == null:
		return

	var filled: int = clampi(roundi(_current_exposure * 10.0), 0, 10)
	var bar: String = ""
	for index: int in 10:
		bar += "#" if index < filled else "-"

	var source_parts: PackedStringArray = []
	for light_summary: Dictionary in _last_summary.get("lights", []):
		source_parts.append(
			"%s %.2f"
			% [
				str(light_summary.get("light_id", "")),
				float(light_summary.get("contribution", 0.0)),
			]
		)
	var source_text: String = ", ".join(source_parts)
	if source_text.is_empty():
		source_text = "no active gameplay lights"

	_debug_label.text = (
		"EXPOSURE %.2f  [%s]\n%s"
		% [_current_exposure, bar, source_text]
	)
