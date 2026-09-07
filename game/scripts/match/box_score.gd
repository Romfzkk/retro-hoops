class_name BoxScore
extends RefCounted

# Per-player counting stats plus the team totals the scoreboard reads.

const STAT_KEYS := ["pts", "fta", "ftm", "fga", "fgm", "tpa", "tpm", "reb", "ast", "stl", "blk", "to", "pf"]

var team_points := [0, 0]
var quarter_points := [[], []]
var players: Dictionary = {}

var _last_passer := {}


func register(player_id: int, team_index: int, player: Dictionary) -> void:
	var row := {"team": team_index, "name": League.short_name(player),
		"num": int(player["num"]), "pos": int(player["pos"])}
	for key in STAT_KEYS:
		row[key] = 0
	players[player_id] = row


func add(player_id: int, key: String, amount: int = 1) -> void:
	if not players.has(player_id):
		return
	players[player_id][key] = int(players[player_id][key]) + amount


func record_basket(player_id: int, points: int, quarter: int) -> void:
	if not players.has(player_id):
		return
	var row: Dictionary = players[player_id]
	row["pts"] = int(row["pts"]) + points
	var made_key := "ftm" if points == 1 else "fgm"
	var attempt_key := "fta" if points == 1 else "fga"
	row[made_key] = int(row[made_key]) + 1
	row[attempt_key] = int(row[attempt_key]) + 1
	if points == 3:
		row["tpm"] = int(row["tpm"]) + 1
		row["tpa"] = int(row["tpa"]) + 1
	var team: int = row["team"]
	record_team_basket(team, points, quarter)


func record_miss(player_id: int, points: int) -> void:
	if not players.has(player_id):
		return
	var row: Dictionary = players[player_id]
	var key := "fta" if points == 1 else "fga"
	row[key] = int(row[key]) + 1
	if points == 3:
		row["tpa"] = int(row["tpa"]) + 1


## An assist only counts if the pass was the last touch before the basket and
## the shooter did not hold it forever.
func note_pass(passer_id: int, receiver_id: int, at_time: float) -> void:
	_last_passer[receiver_id] = {"id": passer_id, "time": at_time}


func credit_assist(scorer_id: int, at_time: float) -> void:
	if not _last_passer.has(scorer_id):
		return
	var entry: Dictionary = _last_passer[scorer_id]
	if at_time - float(entry["time"]) <= 3.0:
		add(int(entry["id"]), "ast")
	_last_passer.erase(scorer_id)


func record_team_basket(team: int, points: int, quarter: int) -> void:
	team_points[team] += points
	_ensure_quarter(team, quarter)
	quarter_points[team][quarter - 1] += points


func clear_assists() -> void:
	_last_passer.clear()


func clear_pass_credit(player_id: int) -> void:
	_last_passer.erase(player_id)


func team_rows(team_index: int) -> Array:
	var rows: Array = []
	for id in players:
		if int(players[id]["team"]) == team_index:
			rows.append(players[id])
	rows.sort_custom(func(a, b): return int(a["pts"]) > int(b["pts"]))
	return rows


func leader(team_index: int) -> Dictionary:
	var rows := team_rows(team_index)
	return rows[0] if not rows.is_empty() else {}


func _ensure_quarter(team: int, quarter: int) -> void:
	while quarter_points[team].size() < quarter:
		quarter_points[team].append(0)
