extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const SpeechLineScript = preload("res://gameplay/speech/speech_line.gd")
const SpeakerScript = preload("res://gameplay/speech/world_speech_speaker.gd")
const ProofLine: Resource = preload("res://gameplay/speech/lines/proof_cover_line.tres")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _assert_speech_lab()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_speech_lab() -> void:
	var default_application: Node = ApplicationScene.instantiate()
	var default_labels: PackedStringArray = default_application.get(
		"development_launch_labels"
	)
	var default_paths: PackedStringArray = default_application.get(
		"development_launch_resource_paths"
	)
	_assert_true(
		default_labels.has("Speech Lab")
		and default_paths.has("res://scenes/SpeechLab.tscn"),
		"Application Development Launch exposes the 3.9 Speech Lab"
	)
	default_application.free()

	_assert_true(
		ProofLine != null
		and ProofLine.get_script() == SpeechLineScript
		and bool(ProofLine.call("is_valid_line"))
		and ProofLine.get("line_id") == &"speech.proof.cover"
		and ProofLine.get("sound_kind") == &"speech.proof.cover"
		and not str(ProofLine.get("text")).is_empty()
		and is_equal_approx(
			float(ProofLine.get("presentation_duration_seconds")),
			2.6
		),
		"Speech proof keeps authored words behind a tiny line-ID/data resource instead of hardcoding dialogue in actor AI"
	)

	var application: Node = ApplicationScene.instantiate()
	application.set("development_launch_labels", PackedStringArray(["Speech Lab"]))
	application.set(
		"development_launch_resource_paths",
		PackedStringArray(["res://scenes/SpeechLab.tscn"])
	)
	get_root().add_child(application)
	await process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	await process_frame
	await _completed_physics_frame()

	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var session := application.get("current_session") as Node
	var speaker := (
		world.get_node_or_null("Speaker") as VarkWorldSpeechSpeaker
		if world != null
		else null
	)
	var listener := (
		world.get_node_or_null("Player/SpeechListener") as VarkAcousticListener
		if world != null
		else null
	)
	var propagation := (
		world.get_node_or_null("AcousticPropagation") as VarkAcousticPropagation
		if world != null
		else null
	)
	var speech_label := (
		world.get_node_or_null("Speaker/SpeechLabel") as Label3D
		if world != null
		else null
	)
	_assert_true(
		launched
		and world != null
		and world.name == &"SpeechLab"
		and player != null
		and session != null
		and speaker != null
		and speaker.get_script() == SpeakerScript
		and listener != null
		and propagation != null
		and propagation.is_configured()
		and propagation.has_topology()
		and speech_label != null,
		"Speech Lab launches through the production application/session/player/acoustic path"
	)
	if (
		world == null
		or player == null
		or speaker == null
		or listener == null
		or propagation == null
		or speech_label == null
	):
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	speaker.set_auto_repeat_enabled(false)
	var propagation_summary: Dictionary = propagation.get_debug_summary()
	_assert_true(
		int(propagation_summary.get("space_count", 0)) == 1
		and int(propagation_summary.get("listener_count", 0)) == 1
		and is_equal_approx(listener.hearing_threshold, 0.18)
		and speech_label.no_depth_test
		and speech_label.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
		"Speech proof uses the existing acoustic graph plus a world-space Label3D that may remain readable through visual cover"
	)

	await _move_player_to_marker(world, player, "NearMarker")
	listener.clear_perception()
	var near_before: Dictionary = speaker.get_debug_summary()
	var near_queued: bool = speaker.speak_line()
	var near_hidden_before_drain: bool = not speech_label.visible
	await _completed_physics_frame()
	var near_summary: Dictionary = speaker.get_debug_summary()
	var near_perception: Dictionary = listener.get_last_perception()
	var near_alpha: float = float(near_summary.get("label_alpha", 0.0))
	var near_outline_alpha: float = float(
		near_summary.get("outline_alpha", -1.0)
	)
	_assert_true(
		near_queued
		and near_hidden_before_drain
		and int(near_before.get("heard_count", 0)) == 0
		and bool(near_perception.get("heard", false))
		and speech_label.visible
		and speech_label.text == str(ProofLine.get("text"))
		and near_alpha > 0.65
		and is_equal_approx(near_outline_alpha, near_alpha)
		and is_equal_approx(speech_label.outline_modulate.a, near_alpha),
		"Near speech appears above the speaker only after the existing controlled acoustic consequence pass reports it heard"
	)

	await _move_player_to_marker(world, player, "CoverMarker")
	listener.clear_perception()
	var cover_ray: Object = _first_world_ray_collider(
		world,
		player.global_position + Vector3.UP * 1.1,
		speaker.global_position + Vector3.UP * 1.1
	)
	var cover_queued: bool = speaker.speak_line()
	await _completed_physics_frame()
	var cover_summary: Dictionary = speaker.get_debug_summary()
	var cover_perception: Dictionary = listener.get_last_perception()
	var cover_alpha: float = float(cover_summary.get("label_alpha", 0.0))
	var cover_outline_alpha: float = float(
		cover_summary.get("outline_alpha", -1.0)
	)
	var live_utterance_queue_count: int = int(
		cover_summary.get("queued_count", 0)
	)
	var semantic_heard_count: int = int(cover_summary.get("heard_count", 0))
	_assert_true(
		cover_queued
		and cover_ray == world.get_node("CoverWall")
		and bool(cover_perception.get("heard", false))
		and bool(cover_summary.get("utterance_active", false))
		and speech_label.visible
		and speech_label.no_depth_test
		and speech_label.text == str(ProofLine.get("text"))
		and is_equal_approx(cover_outline_alpha, cover_alpha)
		and is_equal_approx(speech_label.outline_modulate.a, cover_alpha),
		"Acoustically heard speech remains visible through representative visual cover instead of requiring visual line of sight"
	)

	var live_alphas: Array[float] = []
	var live_outline_alphas: Array[float] = []
	for z_position: float in [2.75, 3.5, 4.25, 4.5]:
		await _move_player_to_position(
			player,
			Vector3(0.0, 0.0, z_position)
		)
		var live_summary: Dictionary = speaker.get_debug_summary()
		live_alphas.append(float(live_summary.get("label_alpha", 0.0)))
		live_outline_alphas.append(
			float(live_summary.get("outline_alpha", -1.0))
		)
	var whole_glyph_tracks_alpha: bool = true
	for alpha_index: int in live_alphas.size():
		whole_glyph_tracks_alpha = (
			whole_glyph_tracks_alpha
			and is_equal_approx(
				live_outline_alphas[alpha_index],
				live_alphas[alpha_index]
			)
		)
	_assert_true(
		live_alphas.size() == 4
		and cover_alpha > live_alphas[0]
		and live_alphas[0] > live_alphas[1]
		and live_alphas[1] > live_alphas[2]
		and live_alphas[2] > live_alphas[3]
		and live_alphas[3] > 0.0
		and whole_glyph_tracks_alpha
		and speech_label.visible
		and int(speaker.get_debug_summary().get("queued_count", -1))
			== live_utterance_queue_count
		and int(speaker.get_debug_summary().get("heard_count", -1))
			== semantic_heard_count,
		"One active utterance fades fill and outline together as the player moves away without emitting another semantic gameplay sound"
	)

	var threshold_tail_alphas: Array[float] = []
	for z_position: float in [4.65, 4.8, 4.95, 5.1, 5.2]:
		await _move_player_to_position(
			player,
			Vector3(0.0, 0.0, z_position)
		)
		var tail_summary: Dictionary = speaker.get_debug_summary()
		var tail_alpha: float = float(
			tail_summary.get("label_alpha", 0.0)
		)
		threshold_tail_alphas.append(tail_alpha)
		whole_glyph_tracks_alpha = (
			whole_glyph_tracks_alpha
			and is_equal_approx(
				float(tail_summary.get("outline_alpha", -1.0)),
				tail_alpha
			)
		)
	var smooth_tail: bool = threshold_tail_alphas.size() == 5
	if smooth_tail:
		for alpha_index: int in range(1, threshold_tail_alphas.size()):
			var previous_alpha: float = threshold_tail_alphas[alpha_index - 1]
			var current_alpha: float = threshold_tail_alphas[alpha_index]
			smooth_tail = (
				smooth_tail
				and previous_alpha > current_alpha
				and current_alpha > 0.0
				and previous_alpha - current_alpha < 0.04
			)
	_assert_true(
		smooth_tail
		and whole_glyph_tracks_alpha
		and threshold_tail_alphas[0] < live_alphas[3]
		and threshold_tail_alphas[4] < 0.005,
		"Speech opacity eases through several small fill-and-outline steps all the way toward zero near the hearing boundary instead of jumping"
	)

	await _move_player_to_marker(world, player, "InaudibleMarker")
	var inaudible_summary: Dictionary = speaker.get_debug_summary()
	_assert_true(
		bool(inaudible_summary.get("utterance_active", false))
		and int(inaudible_summary.get("queued_count", -1))
			== live_utterance_queue_count
		and int(inaudible_summary.get("heard_count", -1))
			== semantic_heard_count
		and is_zero_approx(float(inaudible_summary.get("label_alpha", -1.0)))
		and is_zero_approx(float(inaudible_summary.get("outline_alpha", -1.0)))
		and is_zero_approx(speech_label.modulate.a)
		and is_zero_approx(speech_label.outline_modulate.a)
		and not speech_label.visible,
		"The same still-active utterance hides immediately when current acoustic strength falls to or below the hearing threshold"
	)

	await _move_player_to_marker(world, player, "CoverMarker")
	var recovered_summary: Dictionary = speaker.get_debug_summary()
	var recovered_alpha: float = float(
		recovered_summary.get("label_alpha", 0.0)
	)
	_assert_true(
		bool(recovered_summary.get("utterance_active", false))
		and int(recovered_summary.get("queued_count", -1))
			== live_utterance_queue_count
		and int(recovered_summary.get("heard_count", -1))
			== semantic_heard_count
		and speech_label.visible
		and is_equal_approx(
			float(recovered_summary.get("outline_alpha", -1.0)),
			recovered_alpha
		)
		and recovered_alpha > live_alphas[0]
		and absf(recovered_alpha - cover_alpha) < 0.03,
		"Moving back into audible range during the same utterance reveals the line again at the current continuous acoustic opacity"
	)

	var short_line := ProofLine.duplicate(true) as VarkSpeechLine
	short_line.presentation_duration_seconds = 0.08
	speaker.speech_line = short_line
	await _move_player_to_marker(world, player, "NearMarker")
	var expiry_queued: bool = speaker.speak_line()
	for _frame_index: int in 8:
		await physics_frame
		await process_frame
	var expired_summary: Dictionary = speaker.get_debug_summary()
	_assert_true(
		expiry_queued
		and not bool(expired_summary.get("utterance_active", true))
		and is_zero_approx(
			float(expired_summary.get("utterance_remaining_seconds", -1.0))
		)
		and not speech_label.visible,
		"World-space words disappear when the active utterance lifetime ends"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _move_player_to_marker(
	world: Node3D,
	player: CharacterBody3D,
	marker_name: String
) -> void:
	var marker := world.get_node(marker_name) as Node3D
	await _move_player_to_position(
		player,
		Vector3(marker.global_position.x, 0.0, marker.global_position.z)
	)


func _move_player_to_position(
	player: CharacterBody3D,
	position: Vector3
) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	for _frame_index: int in 2:
		await physics_frame
		await process_frame


func _first_world_ray_collider(
	world: Node3D,
	from: Vector3,
	to: Vector3
) -> Object:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider", null) as Object


func _completed_physics_frame() -> void:
	await physics_frame
	await process_frame


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	failures.append(message)
	push_error("FAIL: " + message)


func _print_summary() -> void:
	print("")
	print("==============================")
	if failures.is_empty():
		print("ALL SPEECH TESTS PASSED")
		return
	print("%d SPEECH TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
