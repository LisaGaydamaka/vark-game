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


func _build() -> bool:
	# Godot serializes the embedded-game shortcuts for every debugger session.
	# Reassert Vark's ownership immediately before that session is started instead
	# of relying on the one-time editor-plugin load order.
	return _apply_vark_shortcut_policy()


func _apply_vark_shortcut_policy() -> bool:
	if not is_inside_tree():
		push_error(
			"Vark cannot isolate F9/F10 editor shortcuts outside the editor tree."
		)
		return false
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	if editor_settings == null:
		push_error(
			"Vark could not access EditorSettings for F9/F10 shortcut isolation."
		)
		return false

	var suspend_isolated: bool = _remap_if_conflicting(
		editor_settings,
		ShortcutPolicy.EMBED_SUSPEND_SHORTCUT,
		KEY_F9
	)
	var next_frame_isolated: bool = _remap_if_conflicting(
		editor_settings,
		ShortcutPolicy.EMBED_NEXT_FRAME_SHORTCUT,
		KEY_F10
	)
	if not suspend_isolated or not next_frame_isolated:
		push_error(
			"Vark refused the project run because Godot still owns a plain "
			+ "F9/F10 embedded-game shortcut."
		)
	return suspend_isolated and next_frame_isolated


func _remap_if_conflicting(
	editor_settings: EditorSettings,
	shortcut_path: String,
	keycode: Key
) -> bool:
	var shortcut: Shortcut = editor_settings.get_shortcut(shortcut_path)
	if shortcut == null:
		push_error(
			"Vark expected Godot editor shortcut '%s' but it is unavailable."
			% shortcut_path
		)
		return false
	if not ShortcutPolicy.contains_unmodified_key(shortcut.events, keycode):
		return true

	if not _saved_events.has(shortcut_path):
		_saved_events[shortcut_path] = shortcut.events.duplicate(true)
	shortcut.events = ShortcutPolicy.remap_unmodified_function_key(
		shortcut.events,
		keycode
	)
	var isolated: bool = not ShortcutPolicy.contains_unmodified_key(
		shortcut.events,
		keycode
	)
	if isolated:
		print(
			"Vark editor shortcut isolation: '%s' moved off its plain Vark function key."
			% shortcut_path
		)
	return isolated


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
