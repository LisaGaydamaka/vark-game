extends SceneTree

const MAP_PATH: String = "res://missions/representative_stealth_ledge_city/mission.map"
const MAP_SETTINGS_PATH: String = "res://authoring/vark_map_settings.tres"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var func_map := FuncGodotMap.new()
	func_map.name = "AnimatedLightmapLayoutReport"
	func_map.map_settings = load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	func_map.local_map_file = MAP_PATH
	func_map.build_flags = 0
	get_root().add_child(func_map)
	func_map.build()
	await process_frame

	var descriptors: Dictionary = {}
	for candidate: Node in func_map.find_children("*", "", true, false):
		var light := candidate as VarkGameplayLight
		if light == null:
			continue
		var light_id: String = str(light.gameplay_light_id).strip_edges()
		if light_id.is_empty() or descriptors.has(light_id):
			continue
		descriptors[light_id] = VarkAnimatedLightmapBaker.descriptor_from_gameplay_light(
			light
		)

	var analysis_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var analysis: VarkAnimatedLightmapLayout = analysis_builder.build_from_root(
		func_map,
		descriptors,
		{"max_light_slots": 64}
	)
	if analysis == null:
		push_error(
			"8.4.1A Ledge City layout analysis failed: %s"
			% str(analysis_builder.get_errors())
		)
		quit(1)
		return
	var report: Dictionary = analysis.get_scale_report()
	print("[ANIMATED_LIGHTMAP_LAYOUT_LEDGE] ", JSON.stringify(report))

	var max_candidates: int = int(report.get("max_candidate_lights_per_tile", 0))
	if max_candidates > VarkAnimatedLightmapLayout.DEFAULT_MAX_LIGHT_SLOTS_PER_TILE:
		push_error(
			"8.4.1A Ledge City needs %d per-tile light slots; production ABI allows %d."
			% [
				max_candidates,
				VarkAnimatedLightmapLayout.DEFAULT_MAX_LIGHT_SLOTS_PER_TILE,
			]
		)
		quit(1)
		return

	var production_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var production: VarkAnimatedLightmapLayout = production_builder.build_from_root(
		func_map, descriptors
	)
	if production == null:
		push_error(
			"8.4.1A production Ledge City layout failed: %s"
			% str(production_builder.get_errors())
		)
		quit(1)
		return
	print(
		"8.4.1A production layout fingerprint: ",
		production.representation_fingerprint
	)
	func_map.queue_free()
	await process_frame
	quit(0)
