extends "res://missions/integrated_slice/world.gd"


@onready var receiver_guard: VarkGuard = $ReceiverGuard


func _ready() -> void:
	if not navigation_rebuilt.is_connected(_on_navigation_rebuilt_for_receiver):
		navigation_rebuilt.connect(_on_navigation_rebuilt_for_receiver)
	super._ready()


func _on_navigation_rebuilt_for_receiver(_serial: int) -> void:
	var patrol_points: Dictionary = {
		"communication.receiver.a": $ReceiverPatrolA,
		"communication.receiver.b": $ReceiverPatrolB,
	}
	if receiver_guard.configure_patrol(patrol_points, ordinary_door):
		return
	navigation_ready = false
	var message: String = str(
		receiver_guard.get_debug_summary().get(
			"last_error",
			"Communication Lab receiver guard failed patrol configuration."
		)
	)
	navigation_errors.append(message)
	push_error(message)
