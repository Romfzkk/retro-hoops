class_name SimProbe
extends Node

# A physics-time limit for seeded AI matches. Use --fixed-fps 60 to run faster
# without changing the timestep or projectile trajectories.
const SIM_ARG := "--sim"

var _remaining := 0.0
var _reported := false


static func attach(host: Node) -> void:
	if FrameCapture.argument(SIM_ARG).is_empty():
		return
	var probe := SimProbe.new()
	probe.name = "SimProbe"
	host.add_child(probe)


func _ready() -> void:
	_remaining = float(FrameCapture.argument(SIM_ARG))
	get_parent().finished.connect(_on_finished)


func _physics_process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_report(false)


func _on_finished(_result: Dictionary) -> void:
	_report(true)


func _report(complete: bool) -> void:
	if _reported:
		return
	_reported = true
	var match_scene := get_parent()
	var box: BoxScore = match_scene.box
	var setup: MatchSetup = match_scene.setup
	var report := {
		"seed": FrameCapture.argument("--seed"), "complete": complete,
		"home": setup.home["id"], "away": setup.away["id"],
		"score": box.team_points, "totals": [_totals(box, 0), _totals(box, 1)],
		"period": match_scene.clock.quarter, "remaining": match_scene.clock.remaining,
		"elapsed": match_scene._elapsed, "events": match_scene.events,
	}
	print("MATCH_SAMPLE " + JSON.stringify(report))
	get_tree().quit(0 if complete else 2)


func _totals(box: BoxScore, team_index: int) -> Dictionary:
	var totals := {}
	for key in BoxScore.STAT_KEYS:
		totals[key] = 0
	for row in box.team_rows(team_index):
		for key in BoxScore.STAT_KEYS:
			totals[key] = int(totals[key]) + int(row[key])
	return totals
