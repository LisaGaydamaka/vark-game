extends SceneTree

const LabScene = preload(
	"res://scenes/animated_lightmap_lab/AnimatedLightmapLab.tscn"
)
const OUTPUT_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_surface_bake.tres"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LabScene.instantiate() as VarkAnimatedLightmapLab
	lab.auto_apply_committed_bake = false
	get_root().add_child(lab)
	await process_frame
	await physics_frame

	var layout: VarkAnimatedLightmapLayout = lab.get_surface_layout()
	if layout == null:
		push_error(
			"8.4.1C integrated lab layout build failed: %s"
			% str(lab.get_validation_errors())
		)
		quit(1)
		return
	var descriptors: Dictionary = lab.get_expected_light_descriptors()
	var baker := VarkAnimatedLightmapSurfaceBaker.new()
	var data: VarkAnimatedLightmapBakeData = baker.bake(
		VarkAnimatedLightmapLab.MAP_SOURCE_PATH,
		layout,
		descriptors,
		4,
		null
	)
	if data == null:
		push_error(
			"8.4.1C surface bake failed: %s"
			% JSON.stringify(baker.get_diagnostics())
		)
		quit(1)
		return

	var resource_text: String = data.to_resource_text()
	print(
		"[ANIMATED_SURFACE_BAKE_REPORT] ",
		JSON.stringify(baker.get_diagnostics())
	)
	if OS.get_cmdline_user_args().has("--write"):
		var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write surface-light bake to %s" % OUTPUT_PATH)
			quit(1)
			return
		file.store_string(resource_text)
		print("Wrote ", OUTPUT_PATH)
	else:
		print("ANIMATED_SURFACE_BAKE_RESOURCE_BEGIN")
		print(resource_text)
		print("ANIMATED_SURFACE_BAKE_RESOURCE_END")

	lab.queue_free()
	await process_frame
	quit(0)
