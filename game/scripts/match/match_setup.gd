class_name MatchSetup
extends RefCounted

enum Controller { AI, LOCAL_1, LOCAL_2, REMOTE }
enum Mode { FIVE_V_FIVE, THREE_V_THREE }

var home: Dictionary = {}
var away: Dictionary = {}
var home_controller: Controller = Controller.LOCAL_1
var away_controller: Controller = Controller.AI
var mode: Mode = Mode.FIVE_V_FIVE
var arena: int = 0
var quarters: int = 4
var quarter_seconds: int = 300
var difficulty: int = 1
var online: bool = false

# Set when the match came from a season so the result can be written back.
var season_day: int = -1
var season_playoff_round: int = -1


func lineup_size() -> int:
	return 5 if mode == Mode.FIVE_V_FIVE else 3


func is_human(controller: Controller) -> bool:
	return controller != Controller.AI


func local_human_count() -> int:
	var n := 0
	for c in [home_controller, away_controller]:
		if c == Controller.LOCAL_1 or c == Controller.LOCAL_2:
			n += 1
	return n


func duplicate_setup() -> MatchSetup:
	var copy := MatchSetup.new()
	copy.home = home
	copy.away = away
	copy.home_controller = home_controller
	copy.away_controller = away_controller
	copy.mode = mode
	copy.arena = arena
	copy.quarters = quarters
	copy.quarter_seconds = quarter_seconds
	copy.difficulty = difficulty
	copy.online = online
	copy.season_day = season_day
	copy.season_playoff_round = season_playoff_round
	return copy
