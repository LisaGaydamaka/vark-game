from pathlib import Path

path = Path("tests/props/phase_3_5_transition_regressions.gd")
text = path.read_text(encoding="utf-8")
old = '''\tawait _settle_physics(tree)\n\tassert_true.call(prop.linear_velocity.length() > 2.0, "Initial player overlap does not cancel throw velocity")\n'''
new = '''\tawait tree.physics_frame\n\tawait tree.process_frame\n\tvar colliders: Array[String] = []\n\tfor body: Node in prop.get_colliding_bodies():\n\t\tcolliders.append(str(body.get_path()))\n\tvar player_slides: Array[String] = []\n\tfor slide_index: int in player.get_slide_collision_count():\n\t\tvar collision: KinematicCollision3D = player.get_slide_collision(slide_index)\n\t\tif collision != null:\n\t\t\tvar collider: Object = collision.get_collider()\n\t\t\tplayer_slides.append(str(collider) + " normal=" + str(collision.get_normal()))\n\tprint("PHASE35 FIRST TICK prop_pos=", prop.global_position, " velocity=", prop.linear_velocity, " freeze=", prop.freeze, " sleeping=", prop.sleeping, " layer=", prop.collision_layer, " mask=", prop.collision_mask, " contacts=", prop.get_contact_count(), " colliders=", colliders, " player_pos=", player.global_position, " player_velocity=", player.velocity, " prop_exceptions=", prop.get_collision_exceptions(), " player_exceptions=", player.get_collision_exceptions(), " overlap=", bool(prop.call("_shape_overlaps_body_at_transform", prop.global_transform, player)), " player_slides=", player_slides)\n\tassert_true.call(prop.linear_velocity.length() > 2.0, "Initial player overlap does not cancel throw velocity")\n'''
count = text.count(old)
if count != 1:
    raise SystemExit(f"first-tick diagnostic marker count={count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
