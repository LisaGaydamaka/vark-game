extends SceneTree

const LabScene = preload(
	"res://scenes/animated_lightmap_lab/AnimatedLightmapLab.tscn"
)
const OUTPUT_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_lightmap_data.tres"
)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var lab := LabScene.instantiate() as VarkAnimatedLightmapLab
	lab.auto_apply_committed_bake = false
	get_root().add_child(lab)
	await process_frame
	await physics_frame
	var context: Dictionary = lab.get_bake_context()
	var data := VarkAnimatedLightmapBaker.bake_data(
		str(context.get("source_map_path", "")),
		context.get("mesh", null) as MeshInstance3D,
		context.get("light_descriptors", {}) as Dictionary,
		context.get("space_state", null) as PhysicsDirectSpaceState3D,
		context.get("texture_size", Vector2i.ZERO) as Vector2i
	)
	if data == null:
		push_error("8.4.1 animated-lightmap bake failed.")
		quit(1)
		return
	var resource_text: String = data.to_resource_text()
	if OS.get_cmdline_user_args().has("--write"):
		var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write animated-lightmap bake to %s" % OUTPUT_PATH)
			quit(1)
			return
		file.store_string(resource_text)
		print("Wrote ", OUTPUT_PATH)
	else:
		print("ANIMATED_LIGHTMAP_RESOURCE_BEGIN")
		print(resource_text)
		print("ANIMATED_LIGHTMAP_RESOURCE_END")
	lab.queue_free()
	await process_frame
	quit(0)
