extends RefCounted


const ShortcutPolicy = preload(
	"res://tools/editor/vark_editor_shortcut_policy.gd"
)
const PLUGIN_PATH := "res://addons/vark_editor_shortcuts/plugin.cfg"


func run(
	_tree: SceneTree,
	assert_true: Callable
) -> void:
	var project_source: String = FileAccess.get_file_as_string(
		"res://project.godot"
	)
	assert_true.call(
		project_source.contains(PLUGIN_PATH),
		"F9/F10 editor-shortcut isolation plugin is enabled as project tooling"
	)

	var plain_f9 := InputEventKey.new()
	plain_f9.keycode = KEY_F9
	var custom := InputEventKey.new()
	custom.keycode = KEY_P
	custom.ctrl_pressed = true
	var remapped_pause: Array[InputEvent] = (
		ShortcutPolicy.remap_unmodified_function_key(
			[plain_f9, custom],
			KEY_F9
		)
	)
	assert_true.call(
		not ShortcutPolicy.contains_unmodified_key(remapped_pause, KEY_F9)
		and ShortcutPolicy.contains_shifted_key(remapped_pause, KEY_F9)
		and _contains_ctrl_p(remapped_pause),
		"Godot embedded Pause moves off plain F9 to Shift+F9 without discarding unrelated editor shortcut events"
	)

	var plain_f10 := InputEventKey.new()
	plain_f10.keycode = KEY_F10
	var remapped_frame: Array[InputEvent] = (
		ShortcutPolicy.remap_unmodified_function_key(
			[plain_f10],
			KEY_F10
		)
	)
	assert_true.call(
		not ShortcutPolicy.contains_unmodified_key(remapped_frame, KEY_F10)
		and ShortcutPolicy.contains_shifted_key(remapped_frame, KEY_F10),
		"Godot embedded Next Frame moves off plain F10 to Shift+F10 so Vark restart remains unambiguous"
	)


func _contains_ctrl_p(events: Array) -> bool:
	for value: Variant in events:
		var event := value as InputEventKey
		if (
			event != null
			and event.keycode == KEY_P
			and event.ctrl_pressed
			and not event.shift_pressed
			and not event.alt_pressed
			and not event.meta_pressed
		):
			return true
	return false
