class_name PlayerAnimator
extends RefCounted

# Procedural animation. Legs come from the locomotion cycle, arms from whatever
# the player is doing with the ball, and the two are written to the rig
# separately so a player can shoot while still running.

enum Action { NONE, SHOOT, PASS, DUNK, LAYUP, BLOCK, REBOUND, STEAL, CELEBRATE }

# Metres covered by one full cycle, which is two steps. At 1.55 the legs
# cycled about twice as fast as the player actually moved and the feet skated.
const STRIDE_LENGTH := 2.90
const RUN_LEAN := 0.30
const DEFENCE_CROUCH := 0.55

var rig: PlayerRig
var stride_phase := 0.0
var dribble_phase := 0.0
var dribble_driven := false
var landing := 0.0

var speed := 0.0
var top_speed := 7.0
var grounded := true
var airborne := 0.0
var action: Action = Action.NONE
var action_t := 0.0
var has_ball := false
var defending := false
var ball_hand := 1.0
var lean := Vector2.ZERO

var _bob := 0.0


func _init(target_rig: PlayerRig) -> void:
	rig = target_rig


func tick(delta: float) -> void:
	var gait := clampf(speed / maxf(top_speed, 0.01), 0.0, 1.4)
	if grounded:
		stride_phase += delta * (speed / STRIDE_LENGTH) * TAU
	if not dribble_driven:
		dribble_phase += delta * PI * (2.2 + gait * 1.9)
	landing = maxf(0.0, landing - delta * 6.0)

	_legs(gait)
	_torso(gait)
	_arms(gait)
	if defending:
		apply_defensive_arms()

	rig.apply(delta, 20.0 if action == Action.NONE else 26.0)
	rig.position.y = _bob
	if grounded and rig.is_inside_tree():
		rig.ground_feet()


func _legs(gait: float) -> void:
	if not grounded:
		_air_legs()
		return
	if speed < 0.4:
		_planted_legs(gait)
		return

	var amplitude := 0.30 + gait * 0.42
	var knee_amount := 0.55 + gait * 0.85
	for side in [1.0, -1.0]:
		var tag := "l" if side > 0.0 else "r"
		var phase := stride_phase + (0.0 if side > 0.0 else PI)
		var thigh := sin(phase) * amplitude
		var knee := -(0.12 + 0.92 * maxf(0.0, cos(phase))) * knee_amount
		rig.set_target("hip_%s" % tag, Vector3(thigh, 0.0, rig.lateral_side(side) * 0.04))
		rig.set_target("knee_%s" % tag, Vector3(knee, 0.0, 0.0))
		rig.set_target("ankle_%s" % tag, Vector3(-thigh * 0.35 + 0.12, 0.0, 0.0))
	_bob = -absf(sin(stride_phase)) * (0.02 + gait * 0.035) * rig.height


func _planted_legs(gait: float) -> void:
	var crouch := (DEFENCE_CROUCH if defending else 0.16) + landing * 0.35
	var idle_sway := sin(dribble_phase * 0.35) * 0.02
	for side in [1.0, -1.0]:
		var tag := "l" if side > 0.0 else "r"
		var stance := 0.16 if defending else 0.06
		rig.set_target("hip_%s" % tag,
			Vector3(crouch * 0.55 + idle_sway, 0.0, rig.lateral_side(side) * stance))
		rig.set_target("knee_%s" % tag, Vector3(-crouch * 1.5, 0.0, 0.0))
		rig.set_target("ankle_%s" % tag, Vector3(crouch * 0.7, 0.0, 0.0))
	_bob = -crouch * 0.30 * rig.height


func _air_legs() -> void:
	# Tuck on the way up, reach for the floor on the way down.
	var rising := clampf(airborne, -1.0, 1.0)
	var tuck := 0.12 + maxf(rising, 0.0) * 0.55
	rig.set_target("hip_l", Vector3(tuck, 0.0, rig.lateral_side(1.0) * 0.10))
	rig.set_target("knee_l", Vector3(-tuck * 1.7, 0.0, 0.0))
	rig.set_target("ankle_l", Vector3(0.25, 0.0, 0.0))
	rig.set_target("hip_r", Vector3(tuck * 0.55, 0.0, rig.lateral_side(-1.0) * 0.10))
	rig.set_target("knee_r", Vector3(-tuck * 1.1, 0.0, 0.0))
	rig.set_target("ankle_r", Vector3(0.25, 0.0, 0.0))
	_bob = 0.0


func _torso(gait: float) -> void:
	var forward_lean := RUN_LEAN * gait
	if defending and speed < 1.5:
		forward_lean = 0.34
	if action == Action.SHOOT:
		forward_lean *= 0.4
	rig.set_target("hips", Vector3(forward_lean * 0.18, 0.0, lean.x * 0.2))
	rig.set_target("spine", Vector3(forward_lean * 0.6, -sin(stride_phase) * 0.10 * gait,
		lean.y * 0.15))
	rig.set_target("chest", Vector3(forward_lean * 0.4, sin(stride_phase) * 0.16 * gait, 0.0))
	rig.set_target("head", Vector3(-forward_lean * 0.7, 0.0, 0.0))


func _arms(gait: float) -> void:
	match action:
		Action.SHOOT:
			_shoot_arms()
		Action.PASS:
			_pass_arms()
		Action.DUNK:
			_dunk_arms()
		Action.LAYUP:
			_layup_arms()
		Action.BLOCK, Action.REBOUND:
			_arms_overhead()
		Action.STEAL:
			_steal_arms()
		Action.CELEBRATE:
			_celebrate_arms()
		_:
			if has_ball:
				_dribble_arms(gait)
			else:
				_running_arms(gait)


func _running_arms(gait: float) -> void:
	var swing := (0.25 + gait * 0.75) * 0.9
	for side in [1.0, -1.0]:
		var tag := "l" if side > 0.0 else "r"
		# Arms counter the legs, so the left arm follows the right leg.
		var phase := stride_phase + (PI if side > 0.0 else 0.0)
		rig.set_target("shoulder_%s" % tag,
			Vector3(sin(phase) * swing, 0.0, rig.lateral_side(side) * (0.15 + gait * 0.09)))
		rig.set_target("elbow_%s" % tag,
			Vector3(0.42 + gait * 0.62 + maxf(0.0, sin(phase)) * 0.5, 0.0, 0.0))


func _dribble_arms(gait: float) -> void:
	var pump := absf(sin(dribble_phase)) * 2.0 - 1.0
	var off_hand := -ball_hand
	var ball_tag := "l" if ball_hand > 0.0 else "r"
	var free_tag := "l" if off_hand > 0.0 else "r"
	rig.set_target("shoulder_%s" % ball_tag,
		Vector3(0.42 + pump * 0.30, 0.0, rig.lateral_side(ball_hand) * 0.30))
	rig.set_target("elbow_%s" % ball_tag, Vector3(0.85 + pump * 0.45, 0.0, 0.0))
	# Off arm shields the ball.
	rig.set_target("shoulder_%s" % free_tag,
		Vector3(0.55, 0.0, rig.lateral_side(off_hand) * (0.55 + gait * 0.2)))
	rig.set_target("elbow_%s" % free_tag, Vector3(1.25, 0.0, 0.0))


func _shoot_arms() -> void:
	# Set point, then extension, then hold the follow-through.
	var t := clampf(action_t, 0.0, 1.0)
	var raise_amount: float
	var elbow: float
	if t < 0.42:
		var k := t / 0.42
		raise_amount = lerpf(0.5, 1.85, k)
		elbow = lerpf(0.9, 1.75, k)
	elif t < 0.62:
		var k := (t - 0.42) / 0.20
		raise_amount = lerpf(1.85, 2.62, k)
		elbow = lerpf(1.75, 0.18, k)
	else:
		raise_amount = 2.62
		elbow = 0.12
	var shoot_tag := "l" if ball_hand > 0.0 else "r"
	var guide_tag := "l" if ball_hand < 0.0 else "r"
	rig.set_target("shoulder_%s" % shoot_tag, Vector3(raise_amount, 0.0, rig.lateral_side(ball_hand) * 0.12))
	rig.set_target("elbow_%s" % shoot_tag, Vector3(elbow, 0.0, 0.0))
	rig.set_target("shoulder_%s" % guide_tag,
		Vector3(raise_amount * 0.78, 0.0, -rig.lateral_side(ball_hand) * 0.45))
	rig.set_target("elbow_%s" % guide_tag, Vector3(maxf(elbow, 0.9), 0.0, 0.0))


func _pass_arms() -> void:
	var t := clampf(action_t, 0.0, 1.0)
	var push := lerpf(1.05, 1.62, minf(t * 2.4, 1.0))
	var elbow := lerpf(1.5, 0.15, minf(t * 2.4, 1.0))
	for tag in ["l", "r"]:
		var side := 1.0 if tag == "l" else -1.0
		rig.set_target("shoulder_%s" % tag, Vector3(push, 0.0, rig.lateral_side(side) * 0.22))
		rig.set_target("elbow_%s" % tag, Vector3(elbow, 0.0, 0.0))


func _dunk_arms() -> void:
	var t := clampf(action_t, 0.0, 1.0)
	var tag := "l" if ball_hand > 0.0 else "r"
	var other := "l" if ball_hand < 0.0 else "r"
	var cock := lerpf(1.4, 3.05, minf(t * 1.8, 1.0))
	rig.set_target("shoulder_%s" % tag, Vector3(cock, 0.0, rig.lateral_side(ball_hand) * 0.30))
	rig.set_target("elbow_%s" % tag, Vector3(lerpf(1.3, 0.08, minf(t * 2.0, 1.0)), 0.0, 0.0))
	rig.set_target("shoulder_%s" % other, Vector3(2.2 * t + 0.6, 0.0, -rig.lateral_side(ball_hand) * 0.55))
	rig.set_target("elbow_%s" % other, Vector3(0.7, 0.0, 0.0))


func _layup_arms() -> void:
	var t := clampf(action_t, 0.0, 1.0)
	var tag := "l" if ball_hand > 0.0 else "r"
	var other := "l" if ball_hand < 0.0 else "r"
	rig.set_target("shoulder_%s" % tag,
		Vector3(lerpf(1.1, 2.75, minf(t * 1.6, 1.0)), 0.0, rig.lateral_side(ball_hand) * 0.20))
	rig.set_target("elbow_%s" % tag,
		Vector3(lerpf(1.5, 0.35, minf(t * 1.6, 1.0)), 0.0, 0.0))
	rig.set_target("shoulder_%s" % other, Vector3(0.9, 0.0, -rig.lateral_side(ball_hand) * 0.5))
	rig.set_target("elbow_%s" % other, Vector3(1.4, 0.0, 0.0))


func _arms_overhead() -> void:
	var reach := lerpf(1.2, 3.02, clampf(action_t * 2.2, 0.0, 1.0))
	for tag in ["l", "r"]:
		var side := 1.0 if tag == "l" else -1.0
		rig.set_target("shoulder_%s" % tag, Vector3(reach, 0.0, rig.lateral_side(side) * 0.24))
		rig.set_target("elbow_%s" % tag, Vector3(0.10, 0.0, 0.0))


func _steal_arms() -> void:
	var t := clampf(action_t * 2.6, 0.0, 1.0)
	var tag := "l" if ball_hand > 0.0 else "r"
	rig.set_target("shoulder_%s" % tag, Vector3(lerpf(0.5, 1.55, t), 0.0, rig.lateral_side(ball_hand) * 0.5))
	rig.set_target("elbow_%s" % tag, Vector3(lerpf(1.2, 0.2, t), 0.0, 0.0))


func _celebrate_arms() -> void:
	var wave := sin(dribble_phase * 1.6) * 0.35
	for tag in ["l", "r"]:
		var side := 1.0 if tag == "l" else -1.0
		rig.set_target("shoulder_%s" % tag, Vector3(2.7 + wave * side, 0.0, rig.lateral_side(side) * 0.6))
		rig.set_target("elbow_%s" % tag, Vector3(0.4 - wave * 0.3, 0.0, 0.0))


# Defensive stance is a pose, not an action, so it only claims the arms when
# the player has nothing else going on.
func apply_defensive_arms() -> void:
	if action != Action.NONE or has_ball:
		return
	for tag in ["l", "r"]:
		var side := 1.0 if tag == "l" else -1.0
		rig.set_target("shoulder_%s" % tag, Vector3(0.30, 0.0, rig.lateral_side(side) * 1.15))
		rig.set_target("elbow_%s" % tag, Vector3(0.55, 0.0, 0.0))
