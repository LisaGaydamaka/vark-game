class_name VarkSpeechLine
extends Resource


@export var line_id: StringName = &""
@export_multiline var text: String = ""
@export var sound_kind: StringName = &""
@export_range(0.01, 4.0, 0.01) var gameplay_sound_strength: float = 0.55


func is_valid_line() -> bool:
	return (
		not line_id.is_empty()
		and not text.strip_edges().is_empty()
		and not sound_kind.is_empty()
		and is_finite(gameplay_sound_strength)
		and gameplay_sound_strength > 0.0
	)
