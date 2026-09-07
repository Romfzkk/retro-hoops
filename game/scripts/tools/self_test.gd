extends Node

# Headless checks for the things that are easy to break without noticing.
# Exits non-zero on failure so CI can gate on it.
#
# godot --headless --path game res://scenes/self_test.tscn

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_league_generation()
	_court_geometry()
	_shot_solver()
	_roster_packs()
	_roster_repair()
	_season_simulation()
	_sound_bank()
	_match_clock()
	_full_season()

	print("\n%d checks, %d failed" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAIL  %s" % failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _close(label: String, value: float, expected: float, tolerance: float) -> void:
	_check("%s (got %.4f, wanted %.4f +/- %.4f)" % [label, value, expected, tolerance],
		absf(value - expected) <= tolerance)


func _league_generation() -> void:
	var lg := League.new_league(4242)
	var teams: Array = lg["teams"]
	_check("30 teams", teams.size() == 30)

	var east := 0
	for team in teams:
		if int(team["conf"]) == Teams.Conf.EAST:
			east += 1
	_check("conferences split evenly", east == 15)

	for team in teams:
		var roster: Array = team["roster"]
		_check("%s has a full roster" % team["abbr"], roster.size() == League.ROSTER_SIZE)
		var numbers := {}
		for player in roster:
			numbers[int(player["num"])] = true
			_check("%s rating in range" % team["abbr"],
				int(player["ovr"]) >= 25 and int(player["ovr"]) <= 99)
		_check("%s has no duplicate numbers" % team["abbr"],
			numbers.size() == roster.size())

	# Double round robin: every team plays every other twice.
	var schedule: Array = lg["schedule"]
	_check("schedule length", schedule.size() == (teams.size() - 1) * League.GAMES_VS_EACH)
	var appearances := {}
	for day in schedule:
		_check("every team plays each day", (day as Array).size() == teams.size() / 2)
		var seen := {}
		for game in day:
			_check("nobody plays themselves", int(game["h"]) != int(game["a"]))
			_check("one game per team per day",
				not seen.has(game["h"]) and not seen.has(game["a"]))
			seen[game["h"]] = true
			seen[game["a"]] = true
			for id in [int(game["h"]), int(game["a"])]:
				appearances[id] = int(appearances.get(id, 0)) + 1
	for id in appearances:
		_check("team %d plays a full schedule" % id,
			int(appearances[id]) == (teams.size() - 1) * League.GAMES_VS_EACH)

	# Standings order by wins, then point difference.
	lg["teams"][0]["w"] = 10
	lg["teams"][1]["w"] = 12
	var table := League.standings(lg)
	_check("standings sort by wins", int(table[0]["w"]) >= int(table[1]["w"]))


func _court_geometry() -> void:
	_close("court length", CourtMetrics.LENGTH, 28.65, 0.001)
	_close("rim height", CourtMetrics.RIM_HEIGHT, 3.048, 0.001)

	var rim := CourtMetrics.rim_position(0)
	_check("basket 0 is at +X", rim.x > 0.0)
	_check("baskets are mirrored",
		is_equal_approx(CourtMetrics.rim_position(1).x, -rim.x))

	# Straight on, just inside and just outside the arc.
	var inside := Vector3(rim.x - CourtMetrics.THREE_ARC_RADIUS + 0.4, 0.0, 0.0)
	var outside := Vector3(rim.x - CourtMetrics.THREE_ARC_RADIUS - 0.4, 0.0, 0.0)
	_check("inside the arc is two", not CourtMetrics.is_behind_three(inside, 0))
	_check("beyond the arc is three", CourtMetrics.is_behind_three(outside, 0))

	# The corner is a three even though it is closer than the arc radius.
	var corner := Vector3(rim.x - 0.8, 0.0, CourtMetrics.THREE_CORNER_Z + 0.1)
	_check("corner is a three", CourtMetrics.is_behind_three(corner, 0))
	_check("paint is inside the paint",
		CourtMetrics.in_paint(Vector3(rim.x, 0.0, 0.0), 0))
	_check("centre court is not in the paint",
		not CourtMetrics.in_paint(Vector3.ZERO, 0))


func _shot_solver() -> void:
	# A perfectly aimed shot has to arrive at the rim, allowing for the half
	# step of gravity the launch adds to cancel the engine's integrator.
	var rim := CourtMetrics.rim_position(0)
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	for distance in [2.0, 5.0, 7.24, 9.5]:
		var from := Vector3(rim.x - distance, 2.15, 0.0)
		var time := ShotSolver.flight_time(from.distance_to(rim), 0.5)
		var launch := ShotSolver.launch_velocity(from, rim, time)
		var x := from.x + launch.x * time
		var y := from.y + launch.y * time \
			- 0.5 * ShotSolver.GRAVITY * (time * time + time * step)
		_close("shot from %.1fm reaches the rim in x" % distance, x, rim.x, 0.01)
		_close("shot from %.1fm reaches the rim in y" % distance, y, rim.y, 0.01)
		_check("shot from %.1fm arcs above the rim" % distance,
			from.y + launch.y * launch.y / (2.0 * ShotSolver.GRAVITY) > rim.y)

	# Accuracy has to respond to the inputs in the right direction.
	var shooter: Dictionary = League.new_league(7)["teams"][0]["roster"][0]
	var clean := ShotSolver.accuracy(shooter, 5.0, false, 1.0, 0.0, 0.0, 0.0, 1)
	var contested := ShotSolver.accuracy(shooter, 5.0, false, 1.0, 1.0, 0.0, 0.0, 1)
	var rushed := ShotSolver.accuracy(shooter, 5.0, false, 0.1, 0.0, 0.0, 0.0, 1)
	var tired := ShotSolver.accuracy(shooter, 5.0, false, 1.0, 0.0, 0.0, 1.0, 1)
	_check("contest lowers accuracy", contested < clean)
	_check("a bad release lowers accuracy", rushed < clean)
	_check("fatigue lowers accuracy", tired < clean)
	_check("accuracy stays in range", clean <= 1.0 and rushed > 0.0)

	# Longer shots hang longer.
	_check("arc time grows with distance",
		ShotSolver.flight_time(9.0, 0.5) > ShotSolver.flight_time(3.0, 0.5))


func _roster_packs() -> void:
	var problems: Array[String] = []
	var good := PlayerPacks.validate(JSON.parse_string(
		PlayerPacks.example_pack_json()), problems)
	_check("the example pack validates", problems.is_empty() and not good.is_empty())

	var cases := {
		"wrong format version": {"format": 99, "teams": []},
		"no teams": {"format": 1, "teams": []},
		"team without a target": {"format": 1, "teams": [{"city": "Nowhere"}]},
		"unknown position": {"format": 1, "teams": [{"abbr_match": "BAY",
			"players": [{"fn": "A", "ln": "B", "pos": "QB"}]}]},
		"player with no name": {"format": 1, "teams": [{"abbr_match": "BAY",
			"players": [{"fn": "", "ln": ""}]}]},
		"colour that is not a colour": {"format": 1, "teams": [{"abbr_match": "BAY",
			"primary": "not a colour"}]},
	}
	for label in cases:
		var found: Array[String] = []
		var result := PlayerPacks.validate(cases[label], found)
		_check("rejects %s" % label, result.is_empty() and not found.is_empty())

	# Ratings outside the range are clamped rather than rejected.
	var clamped: Array[String] = []
	var pack := PlayerPacks.validate({"format": 1, "teams": [{"abbr_match": "BAY",
		"players": [{"fn": "Over", "ln": "Powered",
			"ratings": {"base": 500, "spd": -20}}]}]}, clamped)
	_check("out of range ratings are accepted", clamped.is_empty())
	if not pack.is_empty():
		var player: Dictionary = pack["teams"][0]["players"][0]
		_check("high ratings clamp to 99", int(player["thr"]) == PlayerPacks.RATING_MAX)
		_check("low ratings clamp to 25", int(player["spd"]) == PlayerPacks.RATING_MIN)


func _roster_repair() -> void:
	var lg := League.new_league(99)
	var team: Dictionary = lg["teams"][0]
	var star: Dictionary = (team["roster"] as Array)[0]
	team["roster"] = [star]

	var added := League.ensure_full_roster(team, 1234)
	var roster: Array = team["roster"]
	_check("a one-man roster is topped up", roster.size() == League.ROSTER_SIZE)
	_check("filling reports what it added", added == League.ROSTER_SIZE - 1)
	_check("the existing player is kept", roster.has(star))

	var numbers: Array = []
	for player in roster:
		numbers.append(int(player["num"]))
	_check("filled rosters have no duplicate numbers",
		_unique(numbers).size() == numbers.size())
	_check("a full roster is left alone", League.ensure_full_roster(team, 1234) == 0)

	# The bug this guards: a pack replacing a squad with fewer than five players
	# left that team unable to take the floor, and every match with them crashed.
	var packed := League.new_league(7)
	var problems: Array[String] = []
	var pack := PlayerPacks.validate({
		"format": PlayerPacks.FORMAT_VERSION,
		"name": "One man team",
		"teams": [{
			"abbr_match": String((packed["teams"] as Array)[0]["abbr"]),
			"replace_roster": true,
			"players": [{"fn": "Solo", "ln": "Act", "pos": "PG", "ratings": {}}],
		}],
	}, problems)
	_check("the one-man pack is well formed", problems.is_empty())
	pack["id"] = "one_man"
	PlayerPacks.apply(packed, pack)
	for entry in packed["teams"]:
		_check("%s can still field a squad" % entry["abbr"],
			(entry["roster"] as Array).size() == League.ROSTER_SIZE)
	var names: Array = []
	for player in (packed["teams"] as Array)[0]["roster"]:
		names.append(String(player["ln"]))
	_check("the pack's own player survives the fill", names.has("Act"))


func _unique(values: Array) -> Array:
	var seen: Array = []
	for value in values:
		if not seen.has(value):
			seen.append(value)
	return seen


func _season_simulation() -> void:
	var lg := League.new_league(99)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var low := 999
	var high := 0
	for i in 400:
		var result := SeasonSim.play(lg["teams"][i % 30], lg["teams"][(i + 7) % 30], rng)
		_check("no ties in a simulated game", int(result["home"]) != int(result["away"]))
		low = mini(low, mini(int(result["home"]), int(result["away"])))
		high = maxi(high, maxi(int(result["home"]), int(result["away"])))
	_check("simulated scores are plausible (%d-%d)" % [low, high],
		low >= 60 and high <= 165)

	# Playing a day marks the games and moves the table.
	var before := int(lg["teams"][0]["w"]) + int(lg["teams"][0]["l"])
	SeasonSim.advance_day(lg)
	_check("a simulated day is complete", SeasonSim.day_complete(lg))
	var after := int(lg["teams"][0]["w"]) + int(lg["teams"][0]["l"])
	_check("a simulated day adds a game to the record", after == before + 1)

	# Playoffs seed eight per conference and keep them apart until the final.
	var playoffs := League.make_playoffs(lg)
	_check("sixteen playoff teams", (playoffs["seeds"] as Array).size() == 16)
	_check("eight first round games", (playoffs["rounds"][0] as Array).size() == 8)
	for game in playoffs["rounds"][0]:
		_check("first round is inside one conference",
			int(lg["teams"][int(game["h"])]["conf"])
			== int(lg["teams"][int(game["a"])]["conf"]))


func _sound_bank() -> void:
	var bank := SoundBank.build_all()
	_check("the bank is populated", bank.size() >= 10)
	for id in bank:
		var stream: AudioStreamWAV = bank[id]
		var bytes := stream.data
		_check("%s has audio data" % id, bytes.size() > 0)
		var peak := 0
		var energy := 0.0
		var samples := bytes.size() / 2
		for i in range(0, samples, maxi(samples / 500, 1)):
			var value := absi(bytes.decode_s16(i * 2))
			peak = maxi(peak, value)
			energy += float(value)
		_check("%s is not silent" % id, peak > 500)
		_check("%s is not clipped flat" % id, peak < 32767)


func _match_clock() -> void:
	var clock := MatchClock.new(4, 300.0)
	clock.running = true
	var expired := [false]
	clock.quarter_expired.connect(func(_q): expired[0] = true)
	clock.remaining = 0.05
	clock.tick(0.1)
	_check("the period horn fires", expired[0])

	# With the period over, the shot clock must not keep expiring forever.
	clock.reset_shot_clock()
	_check("a dead period does not hand out a 0.1s shot clock",
		clock.shot_clock > 1.0)

	var fresh := MatchClock.new(4, 300.0)
	fresh.remaining = 8.0
	fresh.reset_shot_clock()
	_check("the shot clock never exceeds the period", fresh.shot_clock <= 8.0)
	_check("advancing a period resets the clock",
		fresh.advance_quarter() and is_equal_approx(fresh.remaining, 300.0))


# Plays a whole year with the simulator to prove the season actually finishes
# and produces one champion, rather than stalling in a round.
func _full_season() -> void:
	var lg := League.new_league(2026)
	var days: int = (lg["schedule"] as Array).size()
	var guard := 0
	while not League.regular_season_done(lg) and guard < days + 10:
		guard += 1
		SeasonSim.advance_day(lg)
		if SeasonSim.day_complete(lg):
			lg["day"] = int(lg["day"]) + 1
	_check("the regular season finishes", League.regular_season_done(lg))

	var games := 0
	for team in lg["teams"]:
		games = maxi(games, int(team["w"]) + int(team["l"]))
	_check("every team played a full season (%d games)" % games, games == days)

	var playoffs := League.make_playoffs(lg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var rounds := 0
	while int(playoffs["champion"]) < 0 and rounds < 8:
		rounds += 1
		var current: Array = playoffs["rounds"][int(playoffs["round"])]
		for game in current:
			var result := SeasonSim.play(lg["teams"][int(game["h"])],
				lg["teams"][int(game["a"])], rng)
			game["hs"] = result["home"]
			game["as"] = result["away"]
			game["played"] = true
		League.advance_playoffs(playoffs)
	_check("the playoffs produce a champion", int(playoffs["champion"]) >= 0)
	_check("the bracket is four rounds", rounds == 4)
	_check("the final is a single game",
		(playoffs["rounds"][3] as Array).size() == 1)
