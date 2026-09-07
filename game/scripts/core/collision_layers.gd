class_name CollisionLayers
extends RefCounted

# The ball must not collide with player capsules. It is released from above the
# shoulder, which is inside the shooter's own capsule, so physical contact
# there deflects every single shot. Blocks and steals are decided by the match
# rules instead.

const WORLD := 1 << 0
const BALL := 1 << 1
const PLAYER := 1 << 2


static func apply_to_ball(body: CollisionObject3D) -> void:
	body.collision_layer = BALL
	body.collision_mask = WORLD


static func apply_to_player(body: CollisionObject3D) -> void:
	body.collision_layer = PLAYER
	body.collision_mask = WORLD


static func apply_to_world(body: CollisionObject3D) -> void:
	body.collision_layer = WORLD
	body.collision_mask = 0
