class_name PlayerSupportContact
extends RefCounted


enum Source {
	NONE,
	FOOTPRINT,
	CAPSULE_CONTACT,
}


var valid: bool = false
var separation: float = INF
var point: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var walkable: bool = false
var collider_rid: RID = RID()
var source: int = Source.NONE


func clear(origin: Vector3 = Vector3.ZERO) -> void:
	valid = false
	separation = INF
	point = origin
	normal = Vector3.UP
	walkable = false
	collider_rid = RID()
	source = Source.NONE


func set_contact(
	contact_separation: float,
	contact_point: Vector3,
	contact_normal: Vector3,
	contact_walkable: bool,
	contact_collider_rid: RID,
	contact_source: int
) -> void:
	valid = true
	separation = contact_separation
	point = contact_point
	normal = contact_normal
	walkable = contact_walkable
	collider_rid = contact_collider_rid
	source = contact_source


func copy_from(other: PlayerSupportContact) -> void:
	if other == null or not other.valid:
		clear(other.point if other != null else Vector3.ZERO)
		return
	set_contact(
		other.separation,
		other.point,
		other.normal,
		other.walkable,
		other.collider_rid,
		other.source
	)
