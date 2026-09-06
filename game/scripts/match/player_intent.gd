class_name PlayerIntent
extends RefCounted

# One frame of "what this player is trying to do". Humans, the AI and remote
# peers all fill in the same struct, so the pawn never knows who is driving it.

var move := Vector2.ZERO
var aim := Vector2.ZERO
var sprint := false

var shoot_held := false
var shoot_pressed := false
var shoot_released := false
var pass_pressed := false
var special_pressed := false
var switch_pressed := false

## Set by the AI and by directional passing; -1 means "pick the best option".
var pass_target := -1


func clear_edges() -> void:
	shoot_pressed = false
	shoot_released = false
	pass_pressed = false
	special_pressed = false
	switch_pressed = false


func reset() -> void:
	move = Vector2.ZERO
	aim = Vector2.ZERO
	sprint = false
	shoot_held = false
	pass_target = -1
	clear_edges()
