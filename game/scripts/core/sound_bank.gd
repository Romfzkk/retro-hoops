class_name SoundBank
extends RefCounted

# Every sound in the game is synthesised at load. It keeps the repository free
# of binary audio, and a rim hit built from three inharmonic partials sits
# better with generated visuals than a sampled one would.
#
# 22.05kHz mono, which is plenty for this material and halves the generation
# cost on a phone.

const RATE := 22050
const TAU_F := TAU


static func build_all() -> Dictionary:
	return {
		"bounce": bounce(),
		"catch": catch(),
		"swish": swish(),
		"rim": rim(),
		"backboard": backboard(),
		"squeak": squeak(),
		"whistle": whistle(),
		"buzzer": buzzer(),
		"cheer": cheer(),
		"groan": groan(),
		"crowd": crowd_bed(),
		"ui_move": ui_move(),
		"ui_select": ui_select(),
	}


static func bounce() -> AudioStreamWAV:
	# Low thump with a click of leather on wood over the top.
	var frames := int(RATE * 0.13)
	var data := PackedFloat32Array()
	data.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in frames:
		var t := float(i) / RATE
		var env := exp(-t * 42.0)
		var thump := sin(TAU_F * 96.0 * t) * env
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 320.0) * 0.5
		data[i] = (thump * 0.8 + click) * 0.55
	return _to_stream(data)


static func catch() -> AudioStreamWAV:
	var frames := int(RATE * 0.09)
	var data := PackedFloat32Array()
	data.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i in frames:
		var t := float(i) / RATE
		data[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.35
	return _to_stream(_low_pass(data, 0.35))


static func swish() -> AudioStreamWAV:
	# Nylon net: a short noise wash that opens then closes quickly.
	var frames := int(RATE * 0.34)
	var data := PackedFloat32Array()
	data.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in frames:
		var t := float(i) / RATE
		var env := minf(t * 26.0, 1.0) * exp(-t * 11.0)
		data[i] = rng.randf_range(-1.0, 1.0) * env * 0.5
	return _to_stream(_high_pass(_low_pass(data, 0.55), 0.25))


static func rim() -> AudioStreamWAV:
	# Three inharmonic partials is what makes it read as metal rather than tone.
	const PARTIALS := [1180.0, 1867.0, 2543.0]
	const DECAY := [16.0, 22.0, 30.0]
	var frames := int(RATE * 0.5)
	var data := PackedFloat32Array()
	data.resize(frames)
	for i in frames:
		var t := float(i) / RATE
		var sample := 0.0
		for p in PARTIALS.size():
			sample += sin(TAU_F * PARTIALS[p] * t) * exp(-t * DECAY[p])
		data[i] = sample * 0.22
	return _to_stream(data)


static func backboard() -> AudioStreamWAV:
	var frames := int(RATE * 0.28)
	var data := PackedFloat32Array()
	data.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in frames:
		var t := float(i) / RATE
		var env := exp(-t * 26.0)
		var body := sin(TAU_F * 210.0 * t) * 0.6 + sin(TAU_F * 415.0 * t) * 0.3
		data[i] = (body + rng.randf_range(-1.0, 1.0) * 0.35) * env * 0.5
	return _to_stream(data)


static func squeak() -> AudioStreamWAV:
	var frames := int(RATE * 0.2)
	var data := PackedFloat32Array()
	data.resize(frames)
	for i in frames:
		var t := float(i) / RATE
		var env := sin(PI * clampf(t / 0.2, 0.0, 1.0))
		# Rising pitch with a wobble; a flat tone sounds like a beep.
		var pitch := 1500.0 + t * 2600.0 + sin(TAU_F * 40.0 * t) * 120.0
		data[i] = sin(TAU_F * pitch * t) * env * 0.16
	return _to_stream(data)


static func whistle() -> AudioStreamWAV:
	var frames := int(RATE * 0.42)
	var data := PackedFloat32Array()
	data.resize(frames)
	for i in frames:
		var t := float(i) / RATE
		var env := minf(t * 40.0, 1.0) * minf((0.42 - t) * 14.0, 1.0)
		var warble := sin(TAU_F * 28.0 * t) * 55.0
		var sample := sin(TAU_F * (2650.0 + warble) * t) * 0.6
		sample += sin(TAU_F * (3380.0 + warble) * t) * 0.4
		data[i] = sample * env * 0.3
	return _to_stream(data)


static func buzzer() -> AudioStreamWAV:
	var frames := int(RATE * 1.1)
	var data := PackedFloat32Array()
	data.resize(frames)
	for i in frames:
		var t := float(i) / RATE
		var env := minf(t * 60.0, 1.0) * minf((1.1 - t) * 8.0, 1.0)
		var square := 1.0 if fmod(t * 233.0, 1.0) < 0.5 else -1.0
		var second := 1.0 if fmod(t * 311.0, 1.0) < 0.5 else -1.0
		data[i] = (square * 0.6 + second * 0.4) * env * 0.28
	return _to_stream(_low_pass(data, 0.6))


static func cheer() -> AudioStreamWAV:
	var frames := int(RATE * 1.9)
	var data := PackedFloat32Array()
	data.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in frames:
		var t := float(i) / RATE
		var env := minf(t * 7.0, 1.0) * exp(-maxf(t - 0.4, 0.0) * 2.1)
		var voices := sin(TAU_F * 3.1 * t) * 0.15 + sin(TAU_F * 5.7 * t) * 0.1
		data[i] = rng.randf_range(-1.0, 1.0) * env * (0.7 + voices) * 0.55
	return _to_stream(_low_pass(data, 0.42))


static func groan() -> AudioStreamWAV:
	var frames := int(RATE * 1.3)
	var data := PackedFloat32Array()
	data.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in frames:
		var t := float(i) / RATE
		var env := minf(t * 5.0, 1.0) * exp(-maxf(t - 0.3, 0.0) * 2.6)
		data[i] = rng.randf_range(-1.0, 1.0) * env * 0.34
	return _to_stream(_low_pass(data, 0.2))


static func crowd_bed() -> AudioStreamWAV:
	# Seamless four second loop of murmur, so the arena is never silent.
	var frames := int(RATE * 4.0)
	var data := PackedFloat32Array()
	data.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	for i in frames:
		var t := float(i) / RATE
		var swell := 0.75 + 0.25 * sin(TAU_F * t / 4.0) + 0.08 * sin(TAU_F * t * 0.37)
		data[i] = rng.randf_range(-1.0, 1.0) * swell
	data = _low_pass(data, 0.16)
	_crossfade_loop(data, int(RATE * 0.25))
	for i in data.size():
		data[i] *= 0.30
	var stream := _to_stream(data)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = data.size() - 1
	return stream


static func ui_move() -> AudioStreamWAV:
	var frames := int(RATE * 0.05)
	var data := PackedFloat32Array()
	data.resize(frames)
	for i in frames:
		var t := float(i) / RATE
		data[i] = sin(TAU_F * 880.0 * t) * exp(-t * 90.0) * 0.18
	return _to_stream(data)


static func ui_select() -> AudioStreamWAV:
	var frames := int(RATE * 0.12)
	var data := PackedFloat32Array()
	data.resize(frames)
	for i in frames:
		var t := float(i) / RATE
		var pitch := 660.0 + t * 1400.0
		data[i] = sin(TAU_F * pitch * t) * exp(-t * 26.0) * 0.2
	return _to_stream(data)


# --- helpers --------------------------------------------------------------

static func _low_pass(data: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size())
	var previous := 0.0
	for i in data.size():
		previous += (data[i] - previous) * amount
		out[i] = previous
	return out


static func _high_pass(data: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size())
	var previous := 0.0
	for i in data.size():
		previous += (data[i] - previous) * amount
		out[i] = data[i] - previous
	return out


## Blends the tail into the head so a looped bed has no seam.
static func _crossfade_loop(data: PackedFloat32Array, fade: int) -> void:
	var count := data.size()
	for i in fade:
		var blend := float(i) / float(fade)
		var tail := data[count - fade + i]
		data[i] = lerpf(tail, data[i], blend)


static func _to_stream(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		var value := int(clampf(data[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream
