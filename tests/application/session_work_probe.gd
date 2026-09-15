extends Node


var _deferred_callback: Callable = Callable()
var _timer_callback: Callable = Callable()
var _timer: Timer = null


func arm_deferred(callback: Callable) -> void:
	_deferred_callback = callback
	call_deferred("_fire_deferred")


func arm_timer(callback: Callable) -> void:
	_timer_callback = callback
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.001
	add_child(_timer)
	_timer.timeout.connect(_fire_timer)
	_timer.start()


func _fire_deferred() -> void:
	if _deferred_callback.is_valid():
		_deferred_callback.call()


func _fire_timer() -> void:
	if _timer_callback.is_valid():
		_timer_callback.call()
