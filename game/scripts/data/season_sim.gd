class_name SeasonSim
extends RefCounted

# Fast result for games the player is not on the floor for. Deliberately a
# possession-and-efficiency model rather than a shortcut like "better team
# wins": it produces believable scorelines and the occasional upset.

const BASE_POSSESSIONS := 97.0
const BASE_RATING := 108.0
const HOME_EDGE := 2.6
const RATING_WEIGHT := 1.55
const NOISE := 7.5


static func play(home: Dictionary, away: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var possessions := BASE_POSSESSIONS + rng.randfn(0.0, 4.0)
	var home_score := _score(home, away, possessions, HOME_EDGE, rng)
	var away_score := _score(away, home, possessions, 0.0, rng)
	if home_score == away_score:
		# Overtime, decided by the same model over four extra minutes.
		var extra := 9.0
		home_score += _score(home, away, extra, HOME_EDGE, rng)
		away_score += _score(away, home, extra, 0.0, rng)
		if home_score == away_score:
			home_score += 1
	return {"home": home_score, "away": away_score}


static func _score(team: Dictionary, opponent: Dictionary, possessions: float,
		edge: float, rng: RandomNumberGenerator) -> int:
	var offence := float(League.team_ovr(team)) - 75.0
	var defence := float(League.team_ovr(opponent)) - 75.0
	var rating := BASE_RATING + (offence - defence * 0.85) * RATING_WEIGHT + edge
	rating += rng.randfn(0.0, NOISE)
	return int(round(maxf(possessions * rating / 100.0, 55.0)))


## Plays every unplayed game on the current day except the one the user is in.
static func advance_day(lg: Dictionary, skip_home: int = -1,
		skip_away: int = -1) -> Array:
	var day := int(lg["day"])
	var schedule: Array = lg["schedule"]
	if day >= schedule.size():
		return []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var played: Array = []
	for game in schedule[day]:
		if bool(game["played"]):
			continue
		if int(game["h"]) == skip_home and int(game["a"]) == skip_away:
			continue
		var result := play(lg["teams"][int(game["h"])], lg["teams"][int(game["a"])], rng)
		game["hs"] = result["home"]
		game["as"] = result["away"]
		game["played"] = true
		League.record_result(lg, int(game["h"]), int(game["a"]),
			int(result["home"]), int(result["away"]))
		played.append(game)
	return played


static func day_complete(lg: Dictionary) -> bool:
	var day := int(lg["day"])
	var schedule: Array = lg["schedule"]
	if day >= schedule.size():
		return true
	for game in schedule[day]:
		if not bool(game["played"]):
			return false
	return true


static func find_user_game(lg: Dictionary) -> Dictionary:
	var day := int(lg["day"])
	var schedule: Array = lg["schedule"]
	if day >= schedule.size():
		return {}
	var user := int(lg["user_team"])
	for game in schedule[day]:
		if int(game["h"]) == user or int(game["a"]) == user:
			return game
	return {}
