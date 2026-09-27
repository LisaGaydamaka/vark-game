class_name VarkEditorShortcutPolicy
extends RefCounted


const EMBED_SUSPEND_SHORTCUT: String = "editor/suspend_resume_embedded_project"
const EMBED_NEXT_FRAME_SHORTCUT: String = "editor/next_frame_embedded_project"


static func remap_unmodified_function_key(
	events: Array,
	keycode: Key
) -> Array[InputEvent]:
	var remapped: Array[InputEvent] = []
	var replacement_added: bool = false
	for value: Variant in events:
		var event := value as InputEvent
		var key_event := event as InputEventKey
		if key_event != null and _is_unmodified_key(key_event, keycode):
			if not replacement_added:
				remapped.append(_make_shifted_key(keycode))
				replacement_added = true
			continue
		if event != null:
			remapped.append(event.duplicate(true) as InputEvent)
	return remapped


static func contains_unmodified_key(events: Array, keycode: Key) -> bool:
	for value: Variant in events:
		var key_event := value as InputEventKey
		if key_event != null and _is_unmodified_key(key_event, keycode):
			return true
	return false


static func contains_shifted_key(events: Array, keycode: Key) -> bool:
	for value: Variant in events:
		var key_event := value as InputEventKey
		if (
			key_event != null
			and key_event.keycode == keycode
			and key_event.shift_pressed
			and not key_event.ctrl_pressed
			and not key_event.alt_pressed
			and not key_event.meta_pressed
		):
			return true
	return false


static func _is_unmodified_key(event: InputEventKey, keycode: Key) -> bool:
	return (
		event.keycode == keycode
		and not event.shift_pressed
		and not event.ctrl_pressed
		and not event.alt_pressed
		and not event.meta_pressed
	)


static func _make_shifted_key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.shift_pressed = true
	return event
