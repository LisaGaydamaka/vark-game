extends SceneTree

const LayoutRegressions = preload(
	"res://tests/visibility/animated_lightmap_layout_regressions.gd"
)
const BakeRegressions = preload(
	"res://tests/visibility/animated_lightmap_bake_regressions.gd"
)
const IntegrationRegressions = preload(
	"res://tests/visibility/animated_lightmap_regressions.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[8.4.1C_DIAG] BEFORE_A")
	await LayoutRegressions.new().run(self, Callable(self, "_assert_true"))
	print("[8.4.1C_DIAG] AFTER_A failures=", failures.size())
	print("[8.4.1C_DIAG] BEFORE_B")
	await BakeRegressions.new().run(self, Callable(self, "_assert_true"))
	print("[8.4.1C_DIAG] AFTER_B failures=", failures.size())
	print("[8.4.1C_DIAG] BEFORE_C")
	await IntegrationRegressions.new().run(self, Callable(self, "_assert_true"))
	print("[8.4.1C_DIAG] AFTER_C failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	failures.append(message)
	push_error("FAIL: %s" % message)
