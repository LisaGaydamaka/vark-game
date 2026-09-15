extends Node3D


@onready var func_map: Node = $FuncGodotMap


func _ready() -> void:
	# Phase 2.1 keeps the authoritative spatial source inside the mission
	# package. The tiny development playground builds that source synchronously
	# before WorldSession enables ordinary gameplay. Mission metadata/player-start
	# selection arrives in later Phase 2 items rather than being invented here.
	func_map.call("build")
