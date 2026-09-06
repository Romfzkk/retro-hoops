class_name MatchClock
extends RefCounted

signal quarter_expired(quarter: int)
signal shot_clock_expired()

const SHOT_CLOCK := 24.0
const SHOT_CLOCK_RESET_OFFENSIVE_REBOUND := 14.0
const MINIMUM_SHOT_CLOCK_ON_INBOUND := 14.0
const OVERTIME_SECONDS := 300.0

var quarters := 4
var quarter_seconds := 300.0

var quarter := 1
var remaining := 300.0
var shot_clock := SHOT_CLOCK
var running := false


func _init(quarter_count: int, seconds_per_quarter: float) -> void:
	quarters = quarter_count
	quarter_seconds = seconds_per_quarter
	remaining = seconds_per_quarter


func tick(delta: float) -> void:
	if not running:
		return
	remaining = maxf(0.0, remaining - delta)
	shot_clock = maxf(0.0, shot_clock - delta)
	if shot_clock <= 0.0:
		running = false
		shot_clock_expired.emit()
		return
	if remaining <= 0.0:
		running = false
		quarter_expired.emit(quarter)


func reset_shot_clock(seconds: float = SHOT_CLOCK) -> void:
	# Never hand back more time than is left in the period.
	shot_clock = minf(seconds, maxf(remaining, 0.1))


## The clock only tops up to 14 when the offence keeps the ball on the glass.
func offensive_rebound_reset() -> void:
	reset_shot_clock(maxf(shot_clock, SHOT_CLOCK_RESET_OFFENSIVE_REBOUND))


func advance_quarter() -> bool:
	if quarter >= quarters:
		return false
	quarter += 1
	remaining = quarter_seconds
	reset_shot_clock()
	return true


func start_overtime() -> void:
	quarter += 1
	remaining = OVERTIME_SECONDS
	reset_shot_clock()


func is_overtime() -> bool:
	return quarter > quarters


func period_name() -> String:
	if is_overtime():
		var number := quarter - quarters
		return "OT" if number == 1 else "OT%d" % number
	return "Q%d" % quarter


func format_remaining() -> String:
	if remaining >= 60.0:
		return "%d:%02d" % [int(remaining) / 60, int(remaining) % 60]
	# Under a minute the tenths matter.
	return "%.1f" % remaining
