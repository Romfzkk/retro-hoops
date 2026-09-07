class_name SimProbe
extends Node

# Dev helper: `-- --sim 1400` runs a match headless and prints a box score
# summary, so gameplay balance can be measured instead of guessed at.
#
# There is deliberately no speed multiplier. Engine.time_scale scales the
# physics delta, which changes every trajectory being measured; headless
# already runs the loop as fast as the CPU allows.

const SIM_ARG := "--sim"

var _remaining := 0.0


static func attach(host: Node) -> void:
	if FrameCapture.argument(SIM_ARG).is_empty():
		return
	var probe := SimProbe.new()
	probe.name = "SimProbe"
	host.add_child(probe)


func _ready() -> void:
	_remaining = float(FrameCapture.argument(SIM_ARG))


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0:
		return
	_report()
	get_tree().quit()


func _report() -> void:
	var match_scene := get_parent()
	var box: BoxScore = match_scene.box
	var setup: MatchSetup = match_scene.setup
	var events: Dictionary = match_scene.events
	var clock: MatchClock = match_scene.clock

	print("--- sim summary ---")
	print("period %s  clock %s" % [clock.period_name(), clock.format_remaining()])
	for team_index in 2:
		var team: Dictionary = setup.home if team_index == 0 else setup.away
		var totals := _totals(box, team_index)
		print("%s  %d pts | FG %d/%d (%s) | 3P %d/%d | REB %d | AST %d | TO %d | PF %d | BLK %d" % [
			String(team["abbr"]), box.team_points[team_index],
			totals["fgm"], totals["fga"], _percent(totals["fgm"], totals["fga"]),
			totals["tpm"], totals["tpa"], totals["reb"], totals["ast"], totals["to"],
			totals["pf"], totals["blk"],
		])
	print("team fouls %d / %d" % [match_scene.team_fouls[0], match_scene.team_fouls[1]])
	print("out of bounds %d | shot clock %d | possessions %d | dunks %d" % [
		events["out_of_bounds"], events["shot_clock"], events["possessions"],
		events["dunks"]])
	print("passes %d | catches %d | loose pickups %d | pass steals %d" % [
		events["passes"], events["catches"], events["loose_pickups"],
		events["steals_from_pass"]])
	var shots := int(events["shots"])
	if shots > 0:
		print("avg shot accuracy %.3f | avg distance %.2fm" % [
			float(events["shot_quality_sum"]) / float(shots),
			float(events["shot_distance_sum"]) / float(shots)])


func _totals(box: BoxScore, team_index: int) -> Dictionary:
	var totals := {}
	for key in BoxScore.STAT_KEYS:
		totals[key] = 0
	for row in box.team_rows(team_index):
		for key in BoxScore.STAT_KEYS:
			totals[key] = int(totals[key]) + int(row[key])
	return totals


func _percent(made: int, attempted: int) -> String:
	if attempted <= 0:
		return "--"
	return "%.1f%%" % (float(made) / float(attempted) * 100.0)
