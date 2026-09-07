extends Node

# Autoload: owns the generated sound bank, a pool of players, and the crowd
# bed whose level tracks how interesting the game is.

const VOICES := 12
const CROWD_ATTACK := 2.5
const CROWD_DECAY := 0.45

var _bank: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _crowd: AudioStreamPlayer
var _crowd_excitement := 0.0
var _crowd_target := 0.0


func _ready() -> void:
	_build_buses()
	_bank = SoundBank.build_all()
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_voices.append(player)

	_crowd = AudioStreamPlayer.new()
	_crowd.bus = "Crowd"
	_crowd.stream = _bank["crowd"]
	add_child(_crowd)
	_crowd.play()

	Settings.changed.connect(_on_setting_changed)
	_apply_volumes()


func _build_buses() -> void:
	for name in ["SFX", "Music", "Crowd"]:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, "Master")


func play(id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _bank.has(id):
		push_warning("No sound named %s" % id)
		return
	var player := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	player.stream = _bank[id]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## Nudge the crowd. 1.0 is a dunk, 0.3 is a routine bucket.
func react(amount: float) -> void:
	_crowd_target = maxf(_crowd_target, clampf(amount, 0.0, 1.0))


func crowd_level() -> float:
	return _crowd_excitement


func _process(delta: float) -> void:
	if _crowd_excitement < _crowd_target:
		_crowd_excitement = minf(_crowd_excitement + delta * CROWD_ATTACK, _crowd_target)
	else:
		_crowd_excitement = maxf(_crowd_excitement - delta * CROWD_DECAY, 0.0)
	_crowd_target = maxf(_crowd_target - delta * CROWD_DECAY, 0.0)
	if _crowd != null:
		var base := float(Settings.get_value("crowd_volume"))
		# Excitement lifts the bed rather than replacing it.
		_crowd.volume_db = linear_to_db(maxf(base, 0.0001)
			* (0.45 + _crowd_excitement * 0.75))


func _on_setting_changed(key: String) -> void:
	if key.ends_with("_volume"):
		_apply_volumes()


func _apply_volumes() -> void:
	_set_bus("Master", float(Settings.get_value("master_volume")))
	_set_bus("SFX", float(Settings.get_value("sfx_volume")))
	_set_bus("Music", float(Settings.get_value("music_volume")))


func _set_bus(name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
