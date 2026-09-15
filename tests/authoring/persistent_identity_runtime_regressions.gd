extends RefCounted


const WorldSession = preload("res://application/world_session.gd")
const MissingIdentityWorld = preload(
	"res://tests/authoring/fixtures/persistent_identity_missing_world.tscn"
)
const DuplicateIdentityWorld = preload(
	"res://tests/authoring/fixtures/persistent_identity_duplicate_world.tscn"
)


func run(assert_true: Callable) -> void:
	var session: Node = WorldSession.new()

	var missing_built: bool = bool(session.call("build", 9001, MissingIdentityWorld))
	assert_true.call(
		not missing_built
		and int(session.get("state")) == WorldSession.State.EMPTY
		and session.get("world") == null
		and session.get("player") == null
		and int(session.get("session_id")) == 0,
		"WorldSession fails closed and tears down when an authored persistent ID is missing"
	)
	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")

	var duplicate_built: bool = bool(session.call(
		"build",
		9002,
		DuplicateIdentityWorld
	))
	assert_true.call(
		not duplicate_built
		and int(session.get("state")) == WorldSession.State.EMPTY
		and session.get("world") == null
		and session.get("player") == null
		and int(session.get("session_id")) == 0,
		"WorldSession fails closed and tears down when authored persistent IDs are duplicated"
	)
	if int(session.get("state")) != WorldSession.State.EMPTY:
		session.call("teardown")

	session.free()
