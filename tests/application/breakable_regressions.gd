extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const ApplicationRoot = preload("res://application/application_root.gd")
const OrdinaryProp = preload("res://gameplay/props/ordinary_prop.gd")
const ConfiguredBreakable = preload("res://gameplay/effects/configured_breakable.gd")


func run(tree: SceneTree, assert_true: Callable) -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Breakable Lab"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray(["res://scenes/BreakableLab.tscn"])
	)
	tree.get_root().add_child(application)
	await tree.process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	await tree.process_frame
	await _settle(tree, 3)

	var world: Node3D = application.get("current_world") as Node3D
	var player: CharacterBody3D = application.get("current_player") as CharacterBody3D
	var session: Node = application.get("current_session") as Node
	assert_true.call(
		launched
		and world != null
		and player != null
		and session != null
		and int(application.call("get_control_mode"))
			== ApplicationRoot.ControlMode.GAMEPLAY,
		"Breakable Lab launches through production Application/WorldSession ownership"
	)
	if world == null or player == null or session == null:
		return

	var target := world.get_node("BreakablePanel") as VarkConfiguredBreakable
	var projectile := world.get_node("ProjectileProp") as RigidBody3D
	var ordinary_door := world.get_node("OrdinaryDoorControl") as AnimatableBody3D
	assert_true.call(
		target != null
		and projectile != null
		and ordinary_door != null
		and projectile.get_script() == OrdinaryProp
		and target.get_script() == ConfiguredBreakable,
		"Breakable Lab contains one explicit effect responder, one ordinary prop source, and one ordinary nonbreakable door control"
	)
	if target == null or projectile == null or ordinary_door == null:
		return

	var target_mesh := target.get_node("MeshInstance3D") as MeshInstance3D
	assert_true.call(
		not bool(target.call("is_broken"))
		and target.collision_layer != 0
		and target_mesh != null
		and target_mesh.visible,
		"Configured breakable starts intact with ordinary world collision/presentation"
	)
	assert_true.call(
		not ordinary_door.has_method("apply_gameplay_effect")
		and not ordinary_door.has_method("receive_prop_impact"),
		"Ordinary doors remain nonbreakable because they expose no damage/effect responder seam"
	)

	var broken_events: Array[Dictionary] = []
	var handler: Callable = func(event: Dictionary) -> bool:
		broken_events.append(event.duplicate(true))
		return true
	assert_true.call(
		bool(session.call(
			"register_semantic_event_handler",
			ConfiguredBreakable.BROKEN_EVENT_NAME,
			handler
		)),
		"Configured breakage publishes through the detached semantic gameplay-event route"
	)
	assert_true.call(
		not bool(target.call("apply_gameplay_effect", &"fire", 99.0, Vector3.ZERO))
		and not bool(target.call(
			"apply_gameplay_effect",
			ConfiguredBreakable.EFFECT_IMPACT,
			float(target.get("break_threshold")) - 0.1,
			Vector3.ZERO
		))
		and not bool(target.call("is_broken")),
		"Unconfigured effect IDs and sub-threshold strengths do not damage explicit breakables"
	)

	player.global_position = Vector3(0.0, 0.0, 3.1)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	var head := player.get_node("Head") as Node3D
	head.rotation.x = 0.0
	await _settle(tree, 2)
	assert_true.call(
		bool(player.call("try_carry_prop", projectile)),
		"Breakable proof acquires the ordinary prop through the production carried-Junk seam"
	)
	var carry: RefCounted = player.get("prop_carry") as RefCounted
	assert_true.call(
		carry != null and bool(carry.call("throw_held")),
		"Breakable proof launches the ordinary prop through the production F-throw owner"
	)

	var broke_from_real_impact: bool = false
	for _frame_index: int in range(120):
		await tree.physics_frame
		await tree.process_frame
		if bool(target.call("is_broken")):
			broke_from_real_impact = true
			break
	await _settle(tree, 3)
	assert_true.call(
		broke_from_real_impact
		and target.collision_layer == 0
		and target.collision_mask == 0
		and not target_mesh.visible,
		"A real thrown ordinary-prop impact crosses the configured threshold and removes only the authored breakable's world obstruction/presentation"
	)
	assert_true.call(
		broken_events.size() == 1
		and str(broken_events[0].get("persistent_id", ""))
			== "breakable-lab-panel"
		and str(broken_events[0].get("content_id", ""))
			== "breakable.lab.panel"
		and broken_events[0].get("effect_id", &"") == &"impact"
		and float(broken_events[0].get("strength", 0.0))
			>= float(target.get("break_threshold")),
		"Breakage emits one detached event carrying stable authored IDs plus the accepted effect/strength"
	)
	assert_true.call(
		not bool(target.call(
			"apply_gameplay_effect",
			ConfiguredBreakable.EFFECT_IMPACT,
			100.0,
			Vector3.ZERO
		))
		and broken_events.size() == 1,
		"Already-broken authored content is idempotent and does not replay break consequences"
	)

	var envelope: Dictionary = session.call("capture_save_envelope")
	var world_state: Dictionary = envelope.get("world_state", {})
	var persistent_entities: Dictionary = world_state.get("persistent_entities", {})
	var saved_breakable: Dictionary = persistent_entities.get(
		"breakable-lab-panel",
		{}
	)
	assert_true.call(
		not envelope.is_empty()
		and saved_breakable == {"broken": true},
		"Configured breakable persists only semantic broken truth under its stable authored persistent ID"
	)

	assert_true.call(
		bool(target.call("apply_semantic_state", {"broken": false}))
		and bool(target.call("reconcile_after_restore"))
		and not bool(target.call("is_broken"))
		and target.collision_layer != 0
		and target_mesh.visible,
		"Semantic restore can reconstruct the intact authored breakable without replaying a break event"
	)
	assert_true.call(
		bool(target.call("apply_semantic_state", saved_breakable))
		and bool(target.call("reconcile_after_restore"))
		and bool(target.call("after_restore"))
		and bool(target.call("is_broken"))
		and target.collision_layer == 0
		and not target_mesh.visible
		and broken_events.size() == 1,
		"Semantic restore reconstructs broken presentation/collision without replaying break consequences"
	)

	application.call("exit_current_world")
	application.queue_free()
	await tree.process_frame


func _settle(tree: SceneTree, frame_count: int = 1) -> void:
	for _frame_index: int in frame_count:
		await tree.physics_frame
		await tree.process_frame
