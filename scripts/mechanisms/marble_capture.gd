extends RefCounted

const OWNER_META = &"marble_transport_owner"
var marble: RigidBody3D
var holder: Node
var original: Dictionary = {}

static func is_carried(body: RigidBody3D) -> bool:
	return is_instance_valid(body) and body.has_meta(OWNER_META)

func claim(body: RigidBody3D, owner_node: Node) -> bool:
	if not is_instance_valid(body) or body.is_queued_for_deletion() or is_carried(body): return false
	marble = body
	holder = owner_node
	original = {"freeze": body.freeze, "freeze_mode": body.freeze_mode, "layer": body.collision_layer, "mask": body.collision_mask, "linear": body.linear_velocity, "angular": body.angular_velocity, "sleeping": body.sleeping}
	body.set_meta(OWNER_META, owner_node.get_instance_id())
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.collision_layer = 0
	body.collision_mask = 0
	return true

func place(world_position: Vector3) -> void:
	if is_instance_valid(marble): marble.global_position = world_position

func release(exit_velocity: Variant = null) -> void:
	if not is_instance_valid(marble): marble = null; return
	marble.remove_meta(OWNER_META)
	marble.collision_layer = original.layer
	marble.collision_mask = original.mask
	marble.freeze_mode = original.freeze_mode
	marble.freeze = original.freeze
	marble.linear_velocity = original.linear if exit_velocity == null else exit_velocity
	marble.angular_velocity = original.angular
	marble.sleeping = original.sleeping if exit_velocity == null else false
	marble = null
