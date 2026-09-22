class_name VarkSurfaceProfile
extends Resource


const LOUDNESS_QUIET: int = 0
const LOUDNESS_NORMAL: int = 1
const LOUDNESS_LOUD: int = 2

const QUIET_FOOTSTEP_STRENGTH: float = 0.09
const NORMAL_FOOTSTEP_STRENGTH: float = 0.21
const LOUD_FOOTSTEP_STRENGTH: float = 0.90


@export var surface_id: StringName = &""
@export_enum("Quiet", "Normal", "Loud") var loudness_level: int = LOUDNESS_NORMAL

# Compatibility read seam for existing callers. Strength is no longer authored
# per surface; it is derived from the three-level loudness contract.
var footstep_strength: float:
	get:
		return get_footstep_strength()


func is_valid_profile() -> bool:
	return (
		not surface_id.is_empty()
		and loudness_level >= LOUDNESS_QUIET
		and loudness_level <= LOUDNESS_LOUD
		and get_footstep_strength() > 0.0
	)


func get_loudness_id() -> StringName:
	match loudness_level:
		LOUDNESS_QUIET:
			return &"quiet"
		LOUDNESS_NORMAL:
			return &"normal"
		LOUDNESS_LOUD:
			return &"loud"
	return &""


func get_footstep_strength() -> float:
	match loudness_level:
		LOUDNESS_QUIET:
			return QUIET_FOOTSTEP_STRENGTH
		LOUDNESS_NORMAL:
			return NORMAL_FOOTSTEP_STRENGTH
		LOUDNESS_LOUD:
			return LOUD_FOOTSTEP_STRENGTH
	return 0.0


func get_footstep_sound_kind() -> StringName:
	if surface_id.is_empty():
		return &""
	return StringName("footstep.%s" % str(surface_id))


func get_semantic_summary() -> Dictionary:
	return {
		"surface_id": surface_id,
		"loudness_level": loudness_level,
		"loudness_id": get_loudness_id(),
		"footstep_sound_kind": get_footstep_sound_kind(),
		"footstep_strength": get_footstep_strength(),
	}
