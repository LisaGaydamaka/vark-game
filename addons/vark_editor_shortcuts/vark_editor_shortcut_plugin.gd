@tool
extends EditorPlugin


const ShortcutPolicy = preload(
	"res://tools/editor/vark_editor_shortcut_policy.gd"
)

var _saved_events: Dictionary = {}


func _enter_tree() -> void:
	call_deferred("_apply_vark_shortcut_policy")


func _exit_tree() -> void:
	_restore_editor_shortcuts()


func _apply_vark_shortcut_policy() -> void:
	if not is_inside_tree():
		return
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if editor_settings == null:
		push_warning("Vark could not access EditorSettings for F9/F10 shortcut isolation.")
		return
	_remap_if_conflicting(
		editor_settings,
		ShortcutPolicy.EMBED_SUSPEND_SHORTCUT,
		KEY_F9
	)
	_remap_if_conflicting(
		editor_settings,
		ShortcutPolicy.EMBED_NEXT_FRAME_SHORTCUT,
		KEY_F10
	)


func _remap_if_conflicting(
	editor_settings: EditorSettings,
	shortcut_path: String,
	keycode: Key
) -> void:
	var shortcut: Shortcut = editor_settings.get_shortcut(shortcut_path)
	if shortcut == null:
		push_warning(
			"Vark expected Godot editor shortcut '%s' but it is unavailable."
			% shortcut_path
		)
		return
	if not ShortcutPolicy.contains_unmodified_key(shortcut.events, keycode):
		return

	_saved_events[shortcut_path] = shortcut.events.duplicate(true)
	shortcut.events = ShortcutPolicy.remap_unmodified_function_key(
		shortcut.events,
		keycode
	)
	print(
		"Vark editor shortcut isolation: '%s' moved off its plain Vark function key."
		% shortcut_path
	)


func _restore_editor_shortcuts() -> void:
	if _saved_events.is_empty():
		return
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if editor_settings == null:
		return
	for shortcut_path: Variant in _saved_events.keys():
		var shortcut: Shortcut = editor_settings.get_shortcut(str(shortcut_path))
		if shortcut != null:
			shortcut.events = (
				_saved_events[shortcut_path] as Array
			).duplicate(true)
	_saved_events.clear()
