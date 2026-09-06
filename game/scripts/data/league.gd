class_name League
extends RefCounted

# League state is plain Dictionary/Array so a save file is just JSON.

enum Pos { PG, SG, SF, PF, C }

const POS_NAMES := ["PG", "SG", "SF", "PF", "C"]
const ROSTER_SIZE := 12
const GAMES_VS_EACH := 2
const PLAYOFF_SEEDS_PER_CONF := 8

const RATING_KEYS := [
	"spd", "acc", "str", "thr", "mid", "cls", "dnk", "lay",
	"pas", "hnd", "stl", "blk", "reb", "def", "sta", "vrt",
]

const POS_BIAS := {
	Pos.PG: {"spd": 12, "acc": 12, "str": -14, "thr": 8, "mid": 4, "cls": -6,
		"dnk": -12, "lay": 6, "pas": 16, "hnd": 16, "stl": 10, "blk": -16,
		"reb": -14, "def": 0, "sta": 6, "vrt": 0},
	Pos.SG: {"spd": 8, "acc": 8, "str": -6, "thr": 12, "mid": 10, "cls": 0,
		"dnk": 4, "lay": 8, "pas": 2, "hnd": 8, "stl": 6, "blk": -10,
		"reb": -8, "def": 2, "sta": 4, "vrt": 6},
	Pos.SF: {"spd": 2, "acc": 2, "str": 2, "thr": 4, "mid": 6, "cls": 4,
		"dnk": 8, "lay": 6, "pas": 0, "hnd": 0, "stl": 2, "blk": 0,
		"reb": 2, "def": 4, "sta": 2, "vrt": 6},
	Pos.PF: {"spd": -6, "acc": -6, "str": 10, "thr": -8, "mid": 0, "cls": 8,
		"dnk": 10, "lay": 4, "pas": -6, "hnd": -8, "stl": -4, "blk": 8,
		"reb": 12, "def": 6, "sta": -2, "vrt": 0},
	Pos.C: {"spd": -12, "acc": -12, "str": 16, "thr": -18, "mid": -8, "cls": 12,
		"dnk": 12, "lay": 2, "pas": -8, "hnd": -14, "stl": -8, "blk": 16,
		"reb": 16, "def": 8, "sta": -4, "vrt": -6},
}

const POS_HEIGHT := {
	Pos.PG: [180, 193], Pos.SG: [188, 199], Pos.SF: [196, 206],
	Pos.PF: [201, 211], Pos.C: [206, 219],
}

const OVR_WEIGHTS := {
	Pos.PG: {"pas": 3, "hnd": 3, "thr": 3, "spd": 2, "mid": 2, "def": 2, "stl": 1, "lay": 1},
	Pos.SG: {"thr": 3, "mid": 3, "spd": 2, "def": 2, "hnd": 2, "lay": 2, "stl": 1, "dnk": 1},
	Pos.SF: {"mid": 3, "thr": 2, "def": 2, "reb": 2, "dnk": 2, "lay": 2, "spd": 2, "cls": 1},
	Pos.PF: {"cls": 3, "reb": 3, "def": 2, "dnk": 2, "str": 2, "mid": 2, "blk": 2, "lay": 1},
	Pos.C: {"cls": 3, "reb": 3, "blk": 3, "def": 2, "str": 2, "dnk": 2, "mid": 1, "pas": 1},
}


static func new_league(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var teams: Array = []
	for i in Teams.DEFS.size():
		teams.append(_build_team(i, Teams.DEFS[i], rng))
	return {
		"seed": seed_value,
		"season": 1,
		"teams": teams,
		"schedule": _round_robin(teams.size()),
		"day": 0,
		"user_team": 0,
		"playoffs": {},
		"history": [],
	}


static func _build_team(id: int, def: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# One tier roll per team so the league has real contenders and real cellar
	# dwellers instead of thirty average rosters.
	var tier := rng.randf_range(-6.0, 6.0)
	var slots := [Pos.PG, Pos.SG, Pos.SF, Pos.PF, Pos.C,
		Pos.PG, Pos.SG, Pos.SF, Pos.PF, Pos.C, Pos.SG, Pos.PF]
	var roster: Array = []
	var taken_numbers: Array = []
	for i in ROSTER_SIZE:
		var base := 74.0 + tier + (6.0 if i < 5 else -8.0) + rng.randf_range(-6.0, 6.0)
		var num := rng.randi_range(0, 55)
		while taken_numbers.has(num):
			num = rng.randi_range(0, 55)
		taken_numbers.append(num)
		roster.append(_build_player(id * 100 + i, slots[i], base, num, rng))
	roster.sort_custom(func(a, b): return int(a["ovr"]) > int(b["ovr"]))
	return {
		"id": id,
		"city": def["city"],
		"name": def["name"],
		"abbr": def["abbr"],
		"conf": def["conf"],
		"primary": def["primary"],
		"secondary": def["secondary"],
		"accent": def["accent"],
		"roster": roster,
		"w": 0, "l": 0, "pf": 0, "pa": 0,
	}


static func _build_player(pid: int, pos: int, base: float, num: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var p := {
		"id": pid,
		"fn": Names.first_name(rng),
		"ln": Names.last_name(rng),
		"num": num,
		"pos": pos,
		"h": rng.randi_range(POS_HEIGHT[pos][0], POS_HEIGHT[pos][1]),
		"skin": rng.randi_range(0, 5),
		"hair": rng.randi_range(0, 4),
		"age": rng.randi_range(19, 36),
	}
	var bias: Dictionary = POS_BIAS[pos]
	for k in RATING_KEYS:
		p[k] = int(clampf(base + float(bias[k]) + rng.randf_range(-7.0, 7.0), 25.0, 99.0))
	p["ovr"] = overall(p)
	return p


static func overall(p: Dictionary) -> int:
	var weights: Dictionary = OVR_WEIGHTS[int(p["pos"])]
	var total := 0.0
	var denom := 0.0
	for k in weights:
		total += float(p[k]) * float(weights[k])
		denom += float(weights[k])
	return int(round(total / maxf(denom, 1.0)))


static func team_ovr(team: Dictionary) -> int:
	var roster: Array = team["roster"]
	if roster.is_empty():
		return 0
	var total := 0.0
	var denom := 0.0
	for i in roster.size():
		var weight := 2.0 if i < 5 else 1.0
		total += float(roster[i]["ovr"]) * weight
		denom += weight
	return int(round(total / denom))


static func player_name(p: Dictionary) -> String:
	return "%s %s" % [p["fn"], p["ln"]]


static func short_name(p: Dictionary) -> String:
	return "%s. %s" % [String(p["fn"]).substr(0, 1), p["ln"]]


static func team_full(t: Dictionary) -> String:
	return "%s %s" % [t["city"], t["name"]]


static func _round_robin(team_count: int) -> Array:
	# Circle method: fix entry 0, rotate the rest. The second leg swaps
	# home/away so every pairing is played both ways.
	var rotation: Array = []
	for i in team_count:
		rotation.append(i)
	var days: Array = []
	for leg in GAMES_VS_EACH:
		for _round in team_count - 1:
			var day: Array = []
			for i in team_count / 2:
				var a: int = rotation[i]
				var b: int = rotation[team_count - 1 - i]
				var home: int = a if leg % 2 == 0 else b
				var away: int = b if leg % 2 == 0 else a
				day.append({"h": home, "a": away, "played": false, "hs": 0, "as": 0})
			days.append(day)
			rotation.insert(1, rotation.pop_back())
	return days


static func standings(lg: Dictionary, conf: int = -1) -> Array:
	var rows: Array = []
	for t in lg["teams"]:
		if conf < 0 or int(t["conf"]) == conf:
			rows.append(t)
	rows.sort_custom(func(a, b):
		if int(a["w"]) != int(b["w"]):
			return int(a["w"]) > int(b["w"])
		return int(a["pf"]) - int(a["pa"]) > int(b["pf"]) - int(b["pa"]))
	return rows


static func regular_season_done(lg: Dictionary) -> bool:
	return int(lg["day"]) >= (lg["schedule"] as Array).size()


static func record_result(lg: Dictionary, home_id: int, away_id: int,
		home_score: int, away_score: int) -> void:
	var home: Dictionary = lg["teams"][home_id]
	var away: Dictionary = lg["teams"][away_id]
	home["pf"] = int(home["pf"]) + home_score
	home["pa"] = int(home["pa"]) + away_score
	away["pf"] = int(away["pf"]) + away_score
	away["pa"] = int(away["pa"]) + home_score
	var home_won := home_score > away_score
	home["w"] = int(home["w"]) + (1 if home_won else 0)
	home["l"] = int(home["l"]) + (0 if home_won else 1)
	away["w"] = int(away["w"]) + (0 if home_won else 1)
	away["l"] = int(away["l"]) + (1 if home_won else 0)


static func make_playoffs(lg: Dictionary) -> Dictionary:
	# Round one is ordered East then West and later rounds pair adjacent
	# winners, so conferences stay separate until the final without any
	# per-round bracket bookkeeping.
	var seeds: Array = []
	var games: Array = []
	for conf in [Teams.Conf.EAST, Teams.Conf.WEST]:
		var qualified := standings(lg, conf).slice(0, PLAYOFF_SEEDS_PER_CONF)
		var ids: Array = []
		for t in qualified:
			ids.append(int(t["id"]))
		seeds.append_array(ids)
		for i in PLAYOFF_SEEDS_PER_CONF / 2:
			games.append({"h": ids[i], "a": ids[PLAYOFF_SEEDS_PER_CONF - 1 - i],
				"played": false, "hs": 0, "as": 0})
	return {"round": 0, "rounds": [games], "champion": -1, "seeds": seeds}


static func advance_playoffs(po: Dictionary) -> void:
	var rounds: Array = po["rounds"]
	var current: Array = rounds[int(po["round"])]
	for g in current:
		if not g["played"]:
			return
	var winners: Array = []
	for g in current:
		winners.append(int(g["h"]) if int(g["hs"]) > int(g["as"]) else int(g["a"]))
	if winners.size() == 1:
		po["champion"] = winners[0]
		return
	var next_round: Array = []
	for i in range(0, winners.size(), 2):
		next_round.append({"h": winners[i], "a": winners[i + 1],
			"played": false, "hs": 0, "as": 0})
	rounds.append(next_round)
	po["round"] = int(po["round"]) + 1


static func round_name(po: Dictionary, index: int) -> String:
	match (po["rounds"][index] as Array).size():
		8: return "First Round"
		4: return "Conference Semifinals"
		2: return "Conference Finals"
		1: return "Finals"
	return "Round %d" % (index + 1)
