extends Node


enum Level {
	TRACE,
	DEBUG,
	INFO,
	WARN,
	ERROR,
}


const TRACE_CAPACITY: int = 500
const TRACE_DIRECTORY: String = "user://logs"
const LEVEL_NAMES: Array[String] = [
	"TRACE",
	"DEBUG",
	"INFO",
	"WARN",
	"ERROR",
]


var minimum_level: int = Level.DEBUG
var category_minimum_levels: Dictionary = {}
var trace_buffer: Array[String] = []


func _ready() -> void:
	if not OS.is_debug_build():
		minimum_level = Level.INFO
	info("system", "session_started", {
		"build": "debug" if OS.is_debug_build() else "release",
		"scene": _get_scene_name(),
	})


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_F8
	):
		dump_trace()


func trace(category: String, event_name: String, data: Dictionary = {}) -> void:
	_write(Level.TRACE, category, event_name, data)


func debug(category: String, event_name: String, data: Dictionary = {}) -> void:
	_write(Level.DEBUG, category, event_name, data)


func info(category: String, event_name: String, data: Dictionary = {}) -> void:
	_write(Level.INFO, category, event_name, data)


func warn(category: String, event_name: String, data: Dictionary = {}) -> void:
	_write(Level.WARN, category, event_name, data)


func error(category: String, event_name: String, data: Dictionary = {}) -> void:
	_write(Level.ERROR, category, event_name, data)


func set_minimum_level(level: int) -> void:
	minimum_level = clampi(level, Level.TRACE, Level.ERROR)


func set_category_level(category: String, level: int) -> void:
	category_minimum_levels[category] = clampi(level, Level.TRACE, Level.ERROR)


func clear_category_level(category: String) -> void:
	category_minimum_levels.erase(category)


func dump_trace() -> String:
	var absolute_directory: String = ProjectSettings.globalize_path(TRACE_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		printerr("[GameLog] Failed to create trace directory: %s" % directory_error)
		return ""

	var timestamp: String = Time.get_datetime_string_from_system(false, false).replace(":", "-")
	var path: String = "%s/trace_%s.log" % [TRACE_DIRECTORY, timestamp]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("[GameLog] Failed to open trace file: %s" % path)
		return ""

	for line: String in trace_buffer:
		file.store_line(line)
	file.close()

	info("system", "trace_dumped", {
		"events": trace_buffer.size(),
		"path": path,
	})
	return path


func _write(
	level: int,
	category: String,
	event_name: String,
	data: Dictionary
) -> void:
	var line: String = _format_line(level, category, event_name, data)
	_record(line)

	var required_level: int = minimum_level
	if category_minimum_levels.has(category):
		required_level = int(category_minimum_levels[category])
	if level < required_level:
		return

	if level >= Level.WARN:
		printerr(line)
	else:
		print(line)


func _record(line: String) -> void:
	trace_buffer.append(line)
	if trace_buffer.size() > TRACE_CAPACITY:
		trace_buffer.pop_front()


func _format_line(
	level: int,
	category: String,
	event_name: String,
	data: Dictionary
) -> String:
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	var level_name: String = "UNKNOWN"
	if level >= 0 and level < LEVEL_NAMES.size():
		level_name = LEVEL_NAMES[level]
	var line: String = "[%s][F:%d][%s][%s] %s" % [
		timestamp,
		Engine.get_physics_frames(),
		category,
		level_name,
		event_name,
	]
	var data_text: String = _format_data(data)
	if not data_text.is_empty():
		line += " " + data_text
	return line


func _format_data(data: Dictionary) -> String:
	if data.is_empty():
		return ""

	var keys: Array = data.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in keys:
		var value_text: String = str(data[key]).replace("\n", "\\n")
		parts.append("%s=%s" % [str(key), value_text])
	return " ".join(parts)


func _get_scene_name() -> String:
	if get_tree() == null or get_tree().current_scene == null:
		return "<none>"
	return get_tree().current_scene.scene_file_path
