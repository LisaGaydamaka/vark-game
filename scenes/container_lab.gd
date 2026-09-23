extends Node3D


const CollectibleScene = preload("res://gameplay/pickups/Collectible.tscn")


func _ready() -> void:
	_spawn_collectible(
		$Drawer/Contents,
		"container_lab.drawer.loot25",
		"loot.container.drawer.25",
		VarkCollectible.KIND_LOOT,
		25,
		"LOOT · 25",
		Vector3(-0.22, 0.22, 0.13)
	)
	_spawn_collectible(
		$Drawer/Contents,
		"container_lab.drawer.key",
		"key.container.lab",
		VarkCollectible.KIND_KEY,
		0,
		"KEY · container.lab",
		Vector3(0.25, 0.22, 0.13)
	)
	_spawn_collectible(
		$Chest/Contents,
		"container_lab.chest.loot75",
		"loot.container.chest.75",
		VarkCollectible.KIND_LOOT,
		75,
		"LOOT · 75",
		Vector3(0.0, 0.02, 0.0)
	)
	_spawn_collectible(
		$Cabinet/Contents,
		"container_lab.cabinet.item",
		"item.container.note",
		VarkCollectible.KIND_MISSION_ITEM,
		0,
		"MISSION ITEM",
		Vector3(0.0, 0.0, 0.05)
	)


func _spawn_collectible(
	parent: Node3D,
	persistent_id: String,
	content_id: String,
	kind: StringName,
	loot_value: int,
	label: String,
	position: Vector3
) -> void:
	var collectible := CollectibleScene.instantiate() as VarkCollectible
	collectible.persistent_id = persistent_id
	collectible.content_id = content_id
	collectible.pickup_kind = kind
	collectible.loot_value = loot_value
	collectible.display_label = label
	collectible.position = position
	parent.add_child(collectible)
