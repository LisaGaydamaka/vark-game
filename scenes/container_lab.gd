extends Node3D


const CollectibleScene = preload("res://gameplay/pickups/Collectible.tscn")
const GoldCupAsset = preload("res://assets/items/gold_cup.tres")
const BrassKeyAsset = preload("res://assets/items/brass_key.tres")
const SilverCandlestickAsset = preload("res://assets/items/silver_candlestick.tres")
const SealedScrollAsset = preload("res://assets/items/sealed_scroll.tres")


func _ready() -> void:
	_spawn_collectible(
		$Drawer.get_contents_anchor(),
		"container_lab.drawer.loot25",
		"loot.container.drawer.25",
		VarkCollectible.KIND_LOOT,
		25,
		"LOOT · 25",
		GoldCupAsset,
		Vector3(-0.15, 0.0, 0.02)
	)
	_spawn_collectible(
		$Drawer.get_contents_anchor(),
		"container_lab.drawer.key",
		"key.container.lab",
		VarkCollectible.KIND_KEY,
		0,
		"KEY · container.lab",
		BrassKeyAsset,
		Vector3(0.18, 0.01, 0.02)
	)
	_spawn_collectible(
		$Chest.get_contents_anchor(),
		"container_lab.chest.loot75",
		"loot.container.chest.75",
		VarkCollectible.KIND_LOOT,
		75,
		"LOOT · 75",
		SilverCandlestickAsset,
		Vector3.ZERO
	)
	_spawn_collectible(
		$Cabinet.get_contents_anchor(),
		"container_lab.cabinet.item",
		"item.container.note",
		VarkCollectible.KIND_MISSION_ITEM,
		0,
		"MISSION ITEM",
		SealedScrollAsset,
		Vector3(0.0, 0.0, 0.05)
	)


func _spawn_collectible(
	parent: Node3D,
	persistent_id: String,
	content_id: String,
	kind: StringName,
	loot_value: int,
	label: String,
	item_asset: VarkCollectibleAsset,
	position: Vector3
) -> void:
	assert(parent != null)
	var collectible := CollectibleScene.instantiate() as VarkCollectible
	collectible.persistent_id = persistent_id
	collectible.content_id = content_id
	collectible.pickup_kind = kind
	collectible.loot_value = loot_value
	collectible.display_label = label
	collectible.asset = item_asset
	collectible.position = position
	parent.add_child(collectible)
