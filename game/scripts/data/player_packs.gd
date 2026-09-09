class_name PlayerPacks
extends RefCounted

# Roster packs are user-authored JSON dropped into user://packs/. Nothing ships
# with the game; the format exists so players can build their own rosters
# without the project distributing anyone else's likeness.
#
# See docs/player-packs.md for the schema.

const DIR := "user://packs"
const ENABLED_PATH := "user://packs_enabled.json"
const FORMAT_VERSION := 1
const RATING_MIN := 25
const RATING_MAX := 99


static func packs_dir() -> String:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	return DIR


static func list_available() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := DirAccess.open(packs_dir())
	if dir == null:
		return found
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var pack := _read_pack(DIR.path_join(file_name))
		if not pack.is_empty():
			found.append(pack)
	found.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	return found


static func enabled_ids() -> Array[String]:
	var ids: Array[String] = []
	if not FileAccess.file_exists(ENABLED_PATH):
		return ids
	var file := FileAccess.open(ENABLED_PATH, FileAccess.READ)
	if file == null:
		return ids
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_ARRAY:
		for entry in parsed:
			if typeof(entry) == TYPE_STRING:
				ids.append(entry)
	return ids


static func set_enabled(ids: Array[String]) -> void:
	var file := FileAccess.open(ENABLED_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot save enabled packs: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(ids))


static func apply_enabled(lg: Dictionary) -> Array[String]:
	var applied: Array[String] = []
	var wanted := enabled_ids()
	for pack in list_available():
		if wanted.has(String(pack["id"])):
			apply(lg, pack)
			applied.append(String(pack["id"]))
	return applied


static func apply(lg: Dictionary, pack: Dictionary) -> void:
	var matched_none := 0
	for entry in pack["teams"]:
		var team := _find_team(lg, entry)
		if team.is_empty():
			# Silence here is why a whole pack could look like it simply did not
			# load: abbr_match names the existing team to replace, so a code that
			# matches nothing quietly skips the entry.
			push_warning("Pack %s: no team matches abbr_match %s" % [
				pack.get("id", "?"),
				entry.get("abbr_match", entry.get("abbr", "?"))])
			matched_none += 1
			continue
		for key in ["city", "name", "abbr", "primary", "secondary", "accent"]:
			if entry.has(key):
				team[key] = entry[key]
		var players: Array = entry.get("players", [])
		if players.is_empty():
			continue
		if bool(entry.get("replace_roster", true)):
			team["roster"] = players.duplicate()
		else:
			(team["roster"] as Array).append_array(players)
		(team["roster"] as Array).sort_custom(
			func(a, b): return int(a["ovr"]) > int(b["ovr"]))
		# A pack that replaces a squad with two players must not leave that team
		# unable to field five.
		var filled := League.ensure_full_roster(team, hash(pack.get("id", "")))
		if filled > 0:
			push_warning("Pack %s left %s with too few players; filled %d slots"
				% [pack.get("id", "?"), team["abbr"], filled])


	if matched_none == (pack["teams"] as Array).size():
		push_error("Pack %s changed nothing: none of its abbr_match codes name a team in this league" % pack.get("id", "?"))


static func _find_team(lg: Dictionary, entry: Dictionary) -> Dictionary:
	var wanted_abbr := String(entry.get("abbr_match", entry.get("abbr", "")))
	for team in lg["teams"]:
		if String(team["abbr"]) == wanted_abbr:
			return team
	return {}


static func _read_pack(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Pack unreadable: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Pack is not a JSON object: %s" % path)
		return {}
	var problems: Array[String] = []
	var pack := validate(parsed, problems)
	if not problems.is_empty():
		push_warning("Pack %s rejected: %s" % [path, ", ".join(problems)])
		return {}
	pack["id"] = path.get_file().trim_suffix(".json")
	pack["path"] = path
	return pack


# Returns a normalised pack. Anything wrong is appended to `problems` and the
# result should be discarded rather than half-applied.
static func validate(raw: Dictionary, problems: Array[String]) -> Dictionary:
	if int(raw.get("format", 0)) != FORMAT_VERSION:
		problems.append("format must be %d" % FORMAT_VERSION)
		return {}
	var teams_in: Variant = raw.get("teams", [])
	if typeof(teams_in) != TYPE_ARRAY or (teams_in as Array).is_empty():
		problems.append("teams must be a non-empty array")
		return {}
	var teams_out: Array = []
	for i in (teams_in as Array).size():
		var entry: Variant = teams_in[i]
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append("teams[%d] is not an object" % i)
			continue
		var team := _validate_team(entry, i, problems)
		if not team.is_empty():
			teams_out.append(team)
	if teams_out.is_empty():
		problems.append("no usable teams")
		return {}
	return {
		"name": String(raw.get("name", "Untitled pack")),
		"author": String(raw.get("author", "")),
		"teams": teams_out,
	}


static func _validate_team(entry: Dictionary, index: int,
		problems: Array[String]) -> Dictionary:
	var out := {}
	var abbr := String(entry.get("abbr_match", entry.get("abbr", "")))
	if abbr.is_empty():
		problems.append("teams[%d] needs abbr or abbr_match" % index)
		return {}
	out["abbr_match"] = abbr
	for key in ["city", "name", "abbr"]:
		if entry.has(key):
			out[key] = String(entry[key])
	for key in ["primary", "secondary", "accent"]:
		if entry.has(key):
			var hex := String(entry[key])
			if not hex.is_valid_html_color():
				problems.append("teams[%d].%s is not a colour" % [index, key])
				return {}
			out[key] = hex
	out["replace_roster"] = bool(entry.get("replace_roster", true))
	var players_in: Variant = entry.get("players", [])
	if typeof(players_in) != TYPE_ARRAY:
		problems.append("teams[%d].players must be an array" % index)
		return {}
	var players_out: Array = []
	for j in (players_in as Array).size():
		var player := _validate_player(players_in[j], index, j, problems)
		if player.is_empty():
			return {}
		players_out.append(player)
	out["players"] = players_out
	return out


static func _validate_player(raw: Variant, team_index: int, index: int,
		problems: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		problems.append("teams[%d].players[%d] is not an object" % [team_index, index])
		return {}
	var entry: Dictionary = raw
	var first := String(entry.get("fn", "")).strip_edges()
	var last := String(entry.get("ln", "")).strip_edges()
	if first.is_empty() or last.is_empty():
		problems.append("teams[%d].players[%d] needs fn and ln" % [team_index, index])
		return {}
	var pos_name := String(entry.get("pos", "SF")).to_upper()
	var pos := League.POS_NAMES.find(pos_name)
	if pos < 0:
		problems.append("teams[%d].players[%d] has unknown position %s"
			% [team_index, index, pos_name])
		return {}
	var player := {
		"id": 900000 + team_index * 100 + index,
		"fn": first.substr(0, 16),
		"ln": last.substr(0, 20),
		"num": clampi(int(entry.get("num", index)), 0, 99),
		"pos": pos,
		"h": clampi(int(entry.get("h", 198)), 150, 240),
		"skin": clampi(int(entry.get("skin", 2)), 0, 5),
		"hair": clampi(int(entry.get("hair", 0)), 0, 4),
		"age": clampi(int(entry.get("age", 25)), 16, 45),
	}
	var ratings: Variant = entry.get("ratings", {})
	if typeof(ratings) != TYPE_DICTIONARY:
		problems.append("teams[%d].players[%d].ratings must be an object"
			% [team_index, index])
		return {}
	var fallback := int((ratings as Dictionary).get("base", 70))
	for key in League.RATING_KEYS:
		player[key] = clampi(int((ratings as Dictionary).get(key, fallback)),
			RATING_MIN, RATING_MAX)
	player["ovr"] = League.overall(player)
	return player


static func example_pack_json() -> String:
	return JSON.stringify({
		"format": FORMAT_VERSION,
		"name": "Example pack",
		"author": "you",
		"teams": [{
			"abbr_match": "BAY",
			"city": "Your City",
			"name": "Your Team",
			"abbr": "YRC",
			"primary": "#204080",
			"secondary": "#f0f0f0",
			"accent": "#101828",
			# Left out on purpose in the shipped example: replacing a squad
			# with a handful of players is the easy way to break a team, and
			# appending shows the format just as well.
			"replace_roster": false,
			"players": [
				{"fn": "First", "ln": "Last", "num": 7, "pos": "PG",
					"h": 190, "skin": 3, "hair": 1,
					"ratings": {"base": 78, "thr": 88, "pas": 90, "spd": 86}},
				{"fn": "Second", "ln": "Name", "num": 21, "pos": "C",
					"h": 211, "skin": 1, "hair": 2,
					"ratings": {"base": 80, "reb": 92, "blk": 90, "cls": 85}},
			],
		}],
	}, "\t")
