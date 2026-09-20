extends RefCounted


const CURRENT_VERSION: int = 1
const DEVELOPMENT_SCENE_REVISION: int = 1
const DEVELOPMENT_SCENE_PREFIX: String = "dev_scene:"


static func mission_id_for(
	definition: Resource,
	world_scene_path: String
) -> StringName:
	if definition != null:
		return StringName(str(definition.get("mission_id")))
	return StringName(DEVELOPMENT_SCENE_PREFIX + world_scene_path)


static func mission_revision_for(definition: Resource) -> int:
	if definition != null:
		return int(definition.get("mission_content_revision"))
	return DEVELOPMENT_SCENE_REVISION
