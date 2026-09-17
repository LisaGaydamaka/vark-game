extends RefCounted


const WorldSession = preload("res://application/world_session.gd")
const SemanticEventPhysicsProbe = preload(
	"res://tests/application/semantic_event_physics_probe.gd"
)
const TEST_WORLD: PackedScene = preload("res://scenes/VarkTest.tscn")


func run(tree: SceneTree, assert_true: Callable) -> void:
	var session: Node = WorldSession.new()
	session.name = "SemanticEventWorldSession"
	tree.get_root().add_child(session)
	var source_session_id: int = 31001
	var built: bool = bool(session.call("build", source_session_id, TEST_WORLD))
	assert_true.call(
		built
		and int(session.get("state")) == WorldSession.State.READY
		and int(session.call("get_stable_gameplay_boundary_serial")) == 0,
		"3.2 semantic-event fixture builds as a non-playing world session"
	)
	if not built:
		session.queue_free()
		await tree.process_frame
		return

	assert_true.call(
		not bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"blocked.ready",
			{}
		)),
		"Semantic gameplay events do not enter normal dispatch while the session is READY"
	)

	for blocked_state: int in [
		WorldSession.State.BUILDING,
		WorldSession.State.RESTORING,
		WorldSession.State.TEARING_DOWN,
	]:
		session.set("state", blocked_state)
		assert_true.call(
			not bool(session.call(
				"queue_semantic_gameplay_event",
				source_session_id,
				&"blocked.lifecycle",
				{"state": blocked_state}
			)),
			"Semantic gameplay dispatch rejects BUILDING/RESTORING/TEARING_DOWN lifecycle state %d"
			% blocked_state
		)
	session.set("state", WorldSession.State.READY)

	var fifo_log: Array[String] = []
	var observed_payload_values: Array[int] = []
	var root_first: Callable = func(event: Dictionary) -> bool:
		fifo_log.append("root:first:%d" % int(event.get("sequence", 0)))
		var event_payload: Dictionary = event.get("payload", {})
		var nested_payload: Dictionary = event_payload.get("nested", {})
		observed_payload_values.append(int(nested_payload.get("value", -1)))
		nested_payload["value"] = 777
		return bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"nested",
			{"origin_sequence": int(event.get("sequence", 0))}
		))
	var root_second: Callable = func(event: Dictionary) -> bool:
		fifo_log.append("root:second:%d" % int(event.get("sequence", 0)))
		var event_payload: Dictionary = event.get("payload", {})
		var nested_payload: Dictionary = event_payload.get("nested", {})
		observed_payload_values.append(int(nested_payload.get("value", -1)))
		return true
	var nested_handler: Callable = func(event: Dictionary) -> bool:
		fifo_log.append("nested:%d" % int(event.get("sequence", 0)))
		return true

	assert_true.call(
		bool(session.call("register_semantic_event_handler", &"root", root_first))
		and bool(session.call("register_semantic_event_handler", &"root", root_second))
		and bool(session.call("register_semantic_event_handler", &"nested", nested_handler)),
		"WorldSession registers ordered synchronous semantic-event handlers"
	)
	assert_true.call(
		not bool(session.call(
			"queue_gameplay_sound",
			source_session_id,
			&"door.use",
			Vector3.ZERO,
			1.0
		)),
		"Gameplay-significant sound cannot queue before the world session is PLAYING"
	)
	assert_true.call(
		bool(session.call("begin_play")),
		"3.2 semantic-event fixture enters PLAYING before normal emission"
	)
	assert_true.call(
		not bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id + 1,
			&"root",
			{}
		)),
		"Semantic gameplay emission rejects a stale or foreign world-session identity"
	)
	assert_true.call(
		not bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"invalid.payload",
			{"live_node": session}
		)),
		"Semantic gameplay payloads reject live Object references instead of leaking mutable world state"
	)

	var source_payload: Dictionary = {"nested": {"value": 1}}
	var fifo_serial_before: int = int(session.call("get_stable_gameplay_boundary_serial"))
	assert_true.call(
		bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"root",
			source_payload
		)),
		"A valid semantic gameplay fact queues for the current PLAYING session"
	)
	(source_payload["nested"] as Dictionary)["value"] = 99
	await _settle_physics(tree)
	assert_true.call(
		fifo_log == ["root:first:1", "root:second:1", "nested:2"],
		"Semantic gameplay events drain FIFO and nested emission appends instead of recursing"
	)
	assert_true.call(
		observed_payload_values == [1, 1],
		"Queued semantic payloads are detached and each handler receives isolated value-owned data"
	)
	assert_true.call(
		int(session.call("get_pending_semantic_event_count")) == 0
		and int(session.call("get_stable_gameplay_boundary_serial")) == fifo_serial_before + 1
		and not bool(session.call("is_semantic_event_drain_active")),
		"Stable gameplay boundary advances only after the current semantic consequence pass drains"
	)

	var physics_log: Array[String] = []
	var physics_handler: Callable = func(event: Dictionary) -> bool:
		physics_log.append(str(event.get("name", &"")))
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			&"physics.probe",
			physics_handler
		)),
		"3.2 registers the controlled-physics-point probe handler"
	)
	var physics_probe: Node = SemanticEventPhysicsProbe.new()
	physics_probe.call(
		"configure",
		session,
		source_session_id,
		&"physics.probe",
		{"source": "default-priority physics"}
	)
	session.add_child(physics_probe)
	var physics_serial_before: int = int(session.call("get_stable_gameplay_boundary_serial"))
	await _settle_physics(tree)
	assert_true.call(
		bool(physics_probe.get("attempted"))
		and bool(physics_probe.get("accepted"))
		and physics_log == ["physics.probe"]
		and int(session.call("get_stable_gameplay_boundary_serial")) == physics_serial_before + 1,
		"Default-priority gameplay physics can enqueue a fact that drains at the later controlled session point in the same tick"
	)
	physics_probe.queue_free()
	await tree.process_frame

	var outside_log: Array[String] = []
	var outside_handler: Callable = func(_event: Dictionary) -> bool:
		outside_log.append("handled")
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			&"outside.callback",
			outside_handler
		)),
		"3.2 registers an out-of-pass semantic work handler"
	)
	var outside_serial_before: int = int(session.call("get_stable_gameplay_boundary_serial"))
	var outside_accepted: bool = bool(session.call(
		"queue_semantic_gameplay_event",
		source_session_id,
		&"outside.callback",
		{"value": 3}
	))
	assert_true.call(
		outside_accepted
		and outside_log.is_empty()
		and int(session.call("get_pending_semantic_event_count")) == 1
		and int(session.call("get_stable_gameplay_boundary_serial")) == outside_serial_before,
		"Out-of-pass callers can queue future semantic work but cannot dispatch durable consequences immediately"
	)
	await _settle_physics(tree)
	assert_true.call(
		outside_log == ["handled"]
		and int(session.call("get_stable_gameplay_boundary_serial")) == outside_serial_before + 1,
		"Queued out-of-pass semantic work becomes authoritative only at the next controlled consequence pass"
	)

	var rejecting_handler: Callable = func(_event: Dictionary) -> bool:
		return false
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			&"invalid.handler",
			rejecting_handler
		)),
		"3.2 registers the synchronous-handler contract probe"
	)
	var rejecting_serial_before: int = int(session.call("get_stable_gameplay_boundary_serial"))
	assert_true.call(
		bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"invalid.handler",
			{}
		)),
		"Synchronous-handler contract probe queues normally"
	)
	await _settle_physics(tree)
	assert_true.call(
		int(session.call("get_stable_gameplay_boundary_serial")) == rejecting_serial_before
		and int(session.call("get_pending_semantic_event_count")) == 0
		and str(session.call("get_last_semantic_event_error")).contains(
			"must return true synchronously"
		),
		"A handler that does not acknowledge synchronous completion fails the drain before a stable boundary is published"
	)
	assert_true.call(
		bool(session.call(
			"unregister_semantic_event_handler",
			&"invalid.handler",
			rejecting_handler
		)),
		"Synchronous-handler contract probe unregisters cleanly"
	)

	var loop_calls: Array[int] = []
	var loop_handler: Callable = func(_event: Dictionary) -> bool:
		loop_calls.append(1)
		return bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"runaway.loop",
			{}
		))
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			&"runaway.loop",
			loop_handler
		))
		and bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"runaway.loop",
			{}
		)),
		"Runaway semantic cascade fixture starts from one valid event"
	)
	var runaway_serial_before: int = int(session.call("get_stable_gameplay_boundary_serial"))
	await _settle_physics(tree)
	assert_true.call(
		loop_calls.size() == WorldSession.SEMANTIC_EVENT_CASCADE_LIMIT
		and int(session.call("get_pending_semantic_event_count")) == 0
		and int(session.call("get_stable_gameplay_boundary_serial")) == runaway_serial_before
		and str(session.call("get_last_semantic_event_error")).contains("cascade exceeded"),
		"Development cascade guard reports and stops a self-sustaining semantic event loop instead of hanging the gameplay tick"
	)
	assert_true.call(
		bool(session.call(
			"unregister_semantic_event_handler",
			&"runaway.loop",
			loop_handler
		)),
		"Runaway cascade handler unregisters after the guarded failure"
	)

	var recovery_log: Array[String] = []
	var recovery_handler: Callable = func(_event: Dictionary) -> bool:
		recovery_log.append("recovered")
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			&"recovery",
			recovery_handler
		))
		and bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"recovery",
			{}
		)),
		"Semantic event route can accept a fresh bounded pass after a guarded cascade failure"
	)
	await _settle_physics(tree)
	assert_true.call(
		recovery_log == ["recovered"]
		and str(session.call("get_last_semantic_event_error")).is_empty(),
		"A later valid semantic pass reaches a stable boundary after the guarded failure is cleared"
	)

	var gameplay_sound_events: Array[Dictionary] = []
	var gameplay_sound_handler: Callable = func(event: Dictionary) -> bool:
		gameplay_sound_events.append(event)
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			WorldSession.GAMEPLAY_SOUND_EVENT_NAME,
			gameplay_sound_handler
		)),
		"3.3 gameplay sound uses the existing world-session semantic event route"
	)
	assert_true.call(
		not bool(session.call(
			"queue_gameplay_sound", source_session_id + 1, &"door.use", Vector3.ZERO, 1.0
		))
		and not bool(session.call(
			"queue_gameplay_sound", source_session_id, &"", Vector3.ZERO, 1.0
		))
		and not bool(session.call(
			"queue_gameplay_sound", source_session_id, &"door.use", Vector3.ZERO, 0.0
		))
		and not bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			WorldSession.GAMEPLAY_SOUND_EVENT_NAME,
			{
				"kind": &"door.use",
				"origin": Vector3.ZERO,
				"strength": 1.0,
				"volume_db": -6.0,
			}
		)),
		"Gameplay-sound validation rejects stale, empty, nonpositive, and presentation-audio-shaped facts"
	)
	var sound_origin := Vector3(2.0, 1.5, -3.0)
	var sound_serial_before: int = int(session.call("get_stable_gameplay_boundary_serial"))
	assert_true.call(
		bool(session.call(
			"queue_gameplay_sound",
			source_session_id,
			&"door.use",
			sound_origin,
			0.75
		))
		and gameplay_sound_events.is_empty()
		and int(session.call("get_pending_semantic_event_count")) == 1
		and int(session.call("get_stable_gameplay_boundary_serial")) == sound_serial_before,
		"Gameplay sound queues semantic hearing work without immediate dispatch or presentation playback ownership"
	)
	await _settle_physics(tree)
	var sound_payload: Dictionary = {}
	if gameplay_sound_events.size() == 1:
		sound_payload = gameplay_sound_events[0].get("payload", {})
	assert_true.call(
		gameplay_sound_events.size() == 1
		and sound_payload.size() == 3
		and sound_payload.get("kind", &"") == &"door.use"
		and sound_payload.get("origin", Vector3.ZERO) == sound_origin
		and is_equal_approx(float(sound_payload.get("strength", 0.0)), 0.75)
		and not sound_payload.has("audio_stream")
		and not sound_payload.has("volume_db")
		and not sound_payload.has("bus")
		and not sound_payload.has("pitch_scale")
		and int(session.call("get_stable_gameplay_boundary_serial")) == sound_serial_before + 1,
		"Gameplay sound arrives as only kind/origin/relative-strength semantic data at the controlled consequence boundary"
	)

	session.call("teardown")
	assert_true.call(
		int(session.get("state")) == WorldSession.State.EMPTY
		and int(session.get("session_id")) == 0
		and int(session.call("get_pending_semantic_event_count")) == 0
		and int(session.call("get_stable_gameplay_boundary_serial")) == 0,
		"WorldSession teardown discards semantic queue/handler/boundary state with the old world scope"
	)

	var replacement_session_id: int = source_session_id + 1
	var replacement_log: Array[String] = []
	var replacement_built: bool = bool(session.call(
		"build",
		replacement_session_id,
		TEST_WORLD
	))
	var replacement_handler: Callable = func(_event: Dictionary) -> bool:
		replacement_log.append("replacement")
		return true
	assert_true.call(
		replacement_built
		and bool(session.call(
			"register_semantic_event_handler",
			&"replacement",
			replacement_handler
		))
		and bool(session.call("begin_play")),
		"Replacement WorldSession scope can establish a fresh semantic event route"
	)
	assert_true.call(
		not bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"replacement",
			{}
		))
		and bool(session.call(
			"queue_semantic_gameplay_event",
			replacement_session_id,
			&"replacement",
			{}
		)),
		"Replacement semantic route rejects stale source-world work and accepts only its current session identity"
	)
	await _settle_physics(tree)
	assert_true.call(
		replacement_log == ["replacement"],
		"Only replacement-world semantic work dispatches after teardown/rebuild"
	)

	session.call("teardown")
	session.queue_free()
	await tree.process_frame


func _settle_physics(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
