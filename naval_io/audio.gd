extends Node
# audio.gd - fully procedural sound (no asset files).
# Every sound is synthesised once at start-up into an AudioStreamWAV (a few per frame, so the
# menu stays responsive) and played through a small pool of positional players.
# Buses "SFX", "Ambient" and "Engine" are created at runtime and controlled from settings.

const RATE := 22050
const LRATE := 16000

const SettingsScript := preload("res://settings.gd")
var S: SettingsScript                   # settings object (settings.gd)
var sounds: Dictionary = {}
var build_queue: Array = []
var pool: Array[AudioStreamPlayer2D] = []
var pool_i := 0
var ui_pool: Array[AudioStreamPlayer] = []
var ui_i := 0
var eng: AudioStreamPlayer
var amb: AudioStreamPlayer
var rotor: AudioStreamPlayer
var eng_on := false
var rotor_on := false
var rng := RandomNumberGenerator.new()

func setup(settings: SettingsScript) -> void:
	S = settings
	rng.randomize()
	for nm in ["SFX", "Ambient", "Engine"]:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, nm)
		AudioServer.set_bus_send(idx, "Master")
	for k in 22:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = 2200.0
		p.attenuation = 1.6
		add_child(p)
		pool.append(p)
	for k in 4:
		var u := AudioStreamPlayer.new()
		u.bus = "SFX"
		add_child(u)
		ui_pool.append(u)
	eng = AudioStreamPlayer.new()
	eng.bus = "Engine"
	add_child(eng)
	amb = AudioStreamPlayer.new()
	amb.bus = "Ambient"
	add_child(amb)
	rotor = AudioStreamPlayer.new()
	rotor.bus = "Engine"
	add_child(rotor)
	# order = priority (UI + loops first, the rest trickle in)
	build_queue = ["click", "ambient", "engine", "gun_m", "mg", "explode_m", "splash", "torp", "missile", "levelup",
		"hit", "gun_s", "gun_l", "gun_xl", "ac", "ciws", "rocket", "explode_s", "explode_l", "mine", "pickup",
		"ability", "ping", "bomb", "rotor", "sink", "alarm", "splash_big", "crackle"]
	apply_volumes()

func _process(_dt: float) -> void:
	# synthesise queued sounds, but never spend more than ~6 ms of a frame on it
	var t0 := Time.get_ticks_usec()
	while not build_queue.is_empty():
		var nm: String = build_queue.pop_front()
		_build(nm)
		if nm == "ambient":
			amb.stream = sounds["ambient"]
			amb.play()
		if Time.get_ticks_usec() - t0 > 6000:
			break

func apply_volumes() -> void:
	var m := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(m, linear_to_db(maxf(S.f("vol_master"), 0.0001)))
	AudioServer.set_bus_mute(m, S.b("mute"))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(S.f("vol_sfx"), 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), linear_to_db(maxf(S.f("vol_amb"), 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Engine"), linear_to_db(maxf(S.f("vol_eng"), 0.0001)))

# ---------------- playback ----------------

func play(nm: String, pos: Vector2, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sounds.has(nm):
		return
	var p := pool[pool_i]
	pool_i = (pool_i + 1) % pool.size()
	p.stream = sounds[nm]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch * 0.9 * rng.randf_range(0.95, 1.05)
	p.play()

func play_ui(nm: String, vol_db: float = -4.0, pitch: float = 1.0) -> void:
	if not sounds.has(nm):
		return
	var p := ui_pool[ui_i]
	ui_i = (ui_i + 1) % ui_pool.size()
	p.stream = sounds[nm]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

# ratio 0..1 of the player's current speed; active=false fades the engine out
func set_engine(active: bool, ratio: float) -> void:
	if not sounds.has("engine"):
		return
	if active:
		if not eng.playing:
			eng.stream = sounds["engine"]
			eng.play()
		eng.pitch_scale = 0.7 + 0.9 * clampf(ratio, 0.0, 1.0)
		eng.volume_db = linear_to_db(0.12 + 0.88 * clampf(absf(ratio), 0.0, 1.0)) - 6.0
	elif eng.playing:
		eng.stop()

func set_rotor(active: bool, ratio: float) -> void:
	if not sounds.has("rotor"):
		return
	if active:
		if not rotor.playing:
			rotor.stream = sounds["rotor"]
			rotor.play()
		rotor.pitch_scale = 0.85 + 0.3 * clampf(ratio, 0.0, 1.0)
		rotor.volume_db = -9.0
	elif rotor.playing:
		rotor.stop()

# ---------------- synthesis ----------------

func _build(nm: String) -> void:
	match nm:
		"click":
			sounds[nm] = _synth(0.06, RATE, {"tone": 1.0, "f0": 1500.0, "f1": 1100.0, "dec": 60.0, "vol": 0.5})
		"mg":
			sounds[nm] = _synth(0.12, RATE, {"noise": 1.0, "lp": 0.30, "tone": 0.7, "f0": 110.0, "f1": 60.0, "dec": 34.0, "vol": 0.6})
		"ac":
			sounds[nm] = _synth(0.2, RATE, {"noise": 1.0, "lp": 0.20, "tone": 0.9, "f0": 105.0, "f1": 52.0, "dec": 20.0, "vol": 0.7})
		"ciws":
			sounds[nm] = _synth(0.14, RATE, {"noise": 0.8, "lp": 0.4, "tone": 0.8, "f0": 70.0, "f1": 70.0, "am": 60.0, "dec": 20.0, "vol": 0.55})
		"gun_s":
			sounds[nm] = _mix(0.62, RATE, 0.85, [
				{"dur": 0.05, "noise": 1.0, "lp": 0.5, "tone": 0.4, "f0": 1900.0, "f1": 700.0, "dec": 90.0, "g": 0.55},
				{"dur": 0.38, "noise": 0.8, "lp": 0.13, "tone": 1.0, "f0": 95.0, "f1": 42.0, "dec": 9.0},
				{"dur": 0.6, "noise": 0.4, "lp": 0.06, "tone": 0.8, "f0": 46.0, "f1": 18.0, "dec": 4.0, "at": 0.02, "g": 0.6},
				{"dur": 0.38, "noise": 0.8, "lp": 0.13, "tone": 1.0, "f0": 95.0, "f1": 42.0, "dec": 9.0, "at": 0.12, "g": 0.3}])
		"gun_m":
			sounds[nm] = _mix(1.25, RATE, 0.95, [
				{"dur": 0.05, "noise": 1.0, "lp": 0.45, "tone": 0.3, "f0": 1400.0, "f1": 500.0, "dec": 80.0, "g": 0.5},
				{"dur": 0.6, "noise": 0.9, "lp": 0.09, "tone": 1.1, "f0": 62.0, "f1": 26.0, "dec": 6.0},
				{"dur": 1.0, "noise": 0.4, "lp": 0.05, "tone": 0.9, "f0": 32.0, "f1": 14.0, "dec": 2.6, "at": 0.04, "g": 0.7},
				{"dur": 0.6, "noise": 0.9, "lp": 0.09, "tone": 1.1, "f0": 62.0, "f1": 26.0, "dec": 6.0, "at": 0.11, "g": 0.35},
				{"dur": 0.5, "noise": 0.2, "lp": 0.04, "tone": 1.2, "f0": 26.0, "f1": 22.0, "dec": 4.0, "at": 0.05, "g": 0.5}])
		"gun_l":
			sounds[nm] = _mix(1.9, RATE, 1.0, [
				{"dur": 0.06, "noise": 1.0, "lp": 0.4, "tone": 0.3, "f0": 900.0, "f1": 350.0, "dec": 70.0, "g": 0.5},
				{"dur": 0.8, "noise": 1.0, "lp": 0.06, "tone": 1.1, "f0": 50.0, "f1": 20.0, "dec": 4.2},
				{"dur": 1.6, "noise": 0.5, "lp": 0.04, "tone": 0.9, "f0": 27.0, "f1": 12.0, "dec": 1.8, "at": 0.05, "g": 0.8},
				{"dur": 0.8, "noise": 1.0, "lp": 0.06, "tone": 1.1, "f0": 50.0, "f1": 20.0, "dec": 4.2, "at": 0.16, "g": 0.4},
				{"dur": 0.8, "noise": 0.15, "lp": 0.035, "tone": 1.3, "f0": 21.0, "f1": 18.0, "dec": 3.0, "at": 0.03, "g": 0.6}])
		"gun_xl":
			sounds[nm] = _mix(2.6, RATE, 1.0, [
				{"dur": 0.06, "noise": 1.0, "lp": 0.35, "tone": 0.25, "f0": 700.0, "f1": 260.0, "dec": 60.0, "g": 0.45},
				{"dur": 1.0, "noise": 1.0, "lp": 0.05, "tone": 1.2, "f0": 40.0, "f1": 15.0, "dec": 3.2},
				{"dur": 2.3, "noise": 0.6, "lp": 0.03, "tone": 0.9, "f0": 22.0, "f1": 9.0, "dec": 1.4, "at": 0.06, "g": 0.85},
				{"dur": 1.0, "noise": 1.0, "lp": 0.05, "tone": 1.2, "f0": 40.0, "f1": 15.0, "dec": 3.2, "at": 0.19, "g": 0.42},
				{"dur": 1.2, "noise": 0.12, "lp": 0.03, "tone": 1.4, "f0": 17.0, "f1": 15.0, "dec": 2.2, "at": 0.04, "g": 0.7}])
		"torp":
			sounds[nm] = _synth(0.7, RATE, {"noise": 1.0, "lp": 0.2, "tone": 0.4, "f0": 160.0, "f1": 60.0, "att": 0.12, "dec": 5.0, "vol": 0.7})
		"missile":
			sounds[nm] = _synth(1.2, RATE, {"noise": 1.0, "lp": 0.16, "tone": 0.3, "f0": 90.0, "f1": 260.0, "att": 0.1, "dec": 2.4, "vol": 0.75})
		"rocket":
			sounds[nm] = _synth(0.7, RATE, {"noise": 1.0, "lp": 0.22, "att": 0.02, "dec": 5.0, "vol": 0.75})
		"mine":
			sounds[nm] = _synth(0.3, RATE, {"noise": 0.5, "lp": 0.1, "tone": 1.0, "f0": 120.0, "f1": 60.0, "dec": 14.0, "vol": 0.8})
		"explode_s":
			sounds[nm] = _mix(1.0, RATE, 0.9, [
				{"dur": 0.06, "noise": 1.0, "lp": 0.55, "dec": 70.0, "g": 0.5},
				{"dur": 0.5, "noise": 1.0, "lp": 0.1, "tone": 0.9, "f0": 70.0, "f1": 28.0, "dec": 5.5},
				{"dur": 0.9, "noise": 0.4, "lp": 0.05, "tone": 0.8, "f0": 36.0, "f1": 14.0, "dec": 2.4, "at": 0.03, "g": 0.6}])
		"explode_m":
			sounds[nm] = _mix(1.7, RATE, 1.0, [
				{"dur": 0.08, "noise": 1.0, "lp": 0.5, "dec": 55.0, "g": 0.5},
				{"dur": 0.8, "noise": 1.0, "lp": 0.07, "tone": 1.0, "f0": 55.0, "f1": 21.0, "dec": 3.6},
				{"dur": 1.5, "noise": 0.5, "lp": 0.04, "tone": 0.8, "f0": 28.0, "f1": 11.0, "dec": 1.7, "at": 0.04, "g": 0.75},
				{"dur": 0.8, "noise": 1.0, "lp": 0.07, "tone": 1.0, "f0": 55.0, "f1": 21.0, "dec": 3.6, "at": 0.14, "g": 0.35}])
		"explode_l":
			sounds[nm] = _mix(2.5, RATE, 1.0, [
				{"dur": 0.09, "noise": 1.0, "lp": 0.45, "dec": 45.0, "g": 0.5},
				{"dur": 1.1, "noise": 1.0, "lp": 0.05, "tone": 1.0, "f0": 44.0, "f1": 16.0, "dec": 2.4},
				{"dur": 2.2, "noise": 0.6, "lp": 0.03, "tone": 0.8, "f0": 22.0, "f1": 8.0, "dec": 1.3, "at": 0.05, "g": 0.8},
				{"dur": 1.1, "noise": 1.0, "lp": 0.05, "tone": 1.0, "f0": 44.0, "f1": 16.0, "dec": 2.4, "at": 0.18, "g": 0.45},
				{"dur": 1.1, "noise": 1.0, "lp": 0.05, "tone": 1.0, "f0": 44.0, "f1": 16.0, "dec": 2.4, "at": 0.34, "g": 0.22}])
		"sink":
			sounds[nm] = _mix(2.8, RATE, 0.9, [
				{"dur": 2.4, "noise": 0.7, "lp": 0.035, "tone": 0.7, "f0": 42.0, "f1": 13.0, "att": 0.25, "dec": 1.1, "g": 0.9},
				{"dur": 1.6, "noise": 0.1, "lp": 0.08, "tone": 1.0, "h2": 0.5, "f0": 210.0, "f1": 55.0, "dec": 2.2, "at": 0.15, "g": 0.4},
				{"dur": 1.1, "noise": 1.0, "lp": 0.24, "am": 16.0, "dec": 2.0, "at": 0.55, "g": 0.35},
				{"dur": 0.9, "noise": 1.0, "lp": 0.3, "am": 24.0, "dec": 2.4, "at": 1.1, "g": 0.22}])
		"hit":
			sounds[nm] = _synth(0.2, RATE, {"noise": 0.5, "lp": 0.5, "tone": 0.6, "f0": 900.0, "f1": 300.0, "h2": 0.6, "dec": 20.0, "vol": 0.6})
		"splash":
			sounds[nm] = _synth(0.5, RATE, {"noise": 1.0, "lp": 0.35, "att": 0.03, "dec": 8.0, "vol": 0.5})
		"pickup":
			sounds[nm] = _synth(0.22, RATE, {"tone": 1.0, "f0": 700.0, "f1": 1500.0, "dec": 14.0, "vol": 0.5})
		"levelup":
			sounds[nm] = _synth(0.9, RATE, {"tone": 1.0, "h2": 0.4, "notes": [523.0, 659.0, 784.0, 1047.0], "nl": 0.18, "dec": 5.0, "vol": 0.6})
		"ability":
			sounds[nm] = _synth(0.5, RATE, {"noise": 0.3, "lp": 0.3, "tone": 0.8, "f0": 300.0, "f1": 900.0, "att": 0.05, "dec": 5.0, "vol": 0.6})
		"ping":
			sounds[nm] = _synth(0.7, RATE, {"tone": 1.0, "f0": 1100.0, "f1": 1100.0, "dec": 4.5, "vol": 0.5})
		"bomb":
			sounds[nm] = _synth(0.6, RATE, {"noise": 0.25, "lp": 0.6, "tone": 0.5, "f0": 1200.0, "f1": 400.0, "dec": 3.0, "vol": 0.5})
		"alarm":
			sounds[nm] = _synth(0.5, RATE, {"tone": 1.0, "notes": [880.0, 660.0], "nl": 0.25, "dec": 4.0, "vol": 0.45})
		"splash_big":
			sounds[nm] = _mix(1.4, RATE, 0.9, [
				{"dur": 0.7, "noise": 1.0, "lp": 0.16, "tone": 0.5, "f0": 90.0, "f1": 34.0, "att": 0.02, "dec": 5.0},
				{"dur": 1.1, "noise": 0.8, "lp": 0.3, "att": 0.06, "dec": 3.4, "at": 0.25, "g": 0.5},
				{"dur": 0.7, "noise": 1.0, "lp": 0.16, "tone": 0.5, "f0": 90.0, "f1": 34.0, "att": 0.02, "dec": 5.0, "at": 0.16, "g": 0.3}])
		"crackle":
			sounds[nm] = _synth(0.4, RATE, {"noise": 1.0, "lp": 0.5, "am": 38.0, "att": 0.02, "dec": 6.0, "vol": 0.4})
		"engine":
			sounds[nm] = _engine_loop()
		"ambient":
			sounds[nm] = _synth(3.0, 11025, {"noise": 1.0, "lp": 0.04, "att": 0.0001, "dec": 0.0, "am": 0.33, "loop": true, "vol": 0.55})
		"rotor":
			sounds[nm] = _rotor_loop()

func _mix(dur: float, rate: int, vol: float, parts: Array) -> AudioStreamWAV:
	# layer several synth voices (with optional delay/echo per part) into one sample
	var n := int(dur * float(rate))
	var data := PackedFloat32Array()
	data.resize(n)
	for part in parts:
		var sub: PackedFloat32Array = _synth_data(float(part["dur"]), rate, part)
		var off := int(float(part.get("at", 0.0)) * float(rate))
		var g := float(part.get("g", 1.0))
		for i in sub.size():
			var j := i + off
			if j >= n:
				break
			data[j] += sub[i] * g
	return _finish(data, rate, false, vol)

func _synth(dur: float, rate: int, p: Dictionary) -> AudioStreamWAV:
	return _finish(_synth_data(dur, rate, p), rate, bool(p.get("loop", false)), float(p.get("vol", 0.8)))

func _synth_data(dur: float, rate: int, p: Dictionary) -> PackedFloat32Array:
	var n := int(dur * float(rate))
	var data := PackedFloat32Array()
	data.resize(n)
	var nz: float = p.get("noise", 0.0)
	var lp: float = p.get("lp", 0.3)
	var tn: float = p.get("tone", 0.0)
	var f0: float = maxf(p.get("f0", 100.0), 1.0)
	var f1: float = maxf(p.get("f1", 100.0), 1.0)
	var dec: float = p.get("dec", 10.0)
	var att: float = maxf(p.get("att", 0.002), 0.00005)
	var am: float = p.get("am", 0.0)
	var h2: float = p.get("h2", 0.0)
	var notes: Array = p.get("notes", [])
	var nl: float = maxf(p.get("nl", 0.2), 0.01)
	var ng := sqrt((2.0 - lp) / maxf(lp, 0.01))
	var ls := 0.0
	var ph := 0.0
	var ratio := f1 / f0
	for i in n:
		var t := float(i) / float(rate)
		var lt := t
		var f := f0 * pow(ratio, t / dur)
		if notes.size() > 0:
			var ni := mini(int(t / nl), notes.size() - 1)
			f = float(notes[ni])
			lt = t - float(ni) * nl
		var env := minf(lt / att, 1.0) * exp(-lt * dec)
		if am > 0.0:
			env *= 0.65 + 0.35 * sin(TAU * am * t)
		ls += (rng.randf() * 2.0 - 1.0 - ls) * lp
		ph += TAU * f / float(rate)
		data[i] = (ls * ng * nz + (sin(ph) + h2 * sin(ph * 2.0)) * tn) * env
	return data

func _engine_loop() -> AudioStreamWAV:
	# 1 second, 38 Hz fundamental + harmonics -> whole cycles, so the loop is seamless
	var n := LRATE
	var data := PackedFloat32Array()
	data.resize(n)
	var ls := 0.0
	for i in n:
		var t := float(i) / float(LRATE)
		var v := 0.0
		v += sin(TAU * 38.0 * t) * 1.0
		v += sin(TAU * 76.0 * t) * 0.6
		v += sin(TAU * 114.0 * t) * 0.35
		v += sin(TAU * 152.0 * t) * 0.25
		v += sin(TAU * 228.0 * t) * 0.12
		v *= 0.8 + 0.2 * sin(TAU * 4.0 * t)
		ls += (rng.randf() * 2.0 - 1.0 - ls) * 0.08
		data[i] = v * 0.5 + ls * 0.5
	return _finish(data, LRATE, true, 0.6)

func _rotor_loop() -> AudioStreamWAV:
	var n := LRATE
	var data := PackedFloat32Array()
	data.resize(n)
	var ls := 0.0
	for i in n:
		var t := float(i) / float(LRATE)
		var beat := maxf(sin(TAU * 18.0 * t), 0.0)
		beat = beat * beat * beat
		ls += (rng.randf() * 2.0 - 1.0 - ls) * 0.12
		data[i] = (ls * 2.2 + sin(TAU * 54.0 * t) * 0.6) * (0.15 + beat)
	return _finish(data, LRATE, true, 0.5)

func _finish(data: PackedFloat32Array, rate: int, loop: bool, vol: float) -> AudioStreamWAV:
	var n := data.size()
	if loop:
		# cross-fade the tail into the head so the loop has no click
		var xf := n / 4
		for i in xf:
			var a := float(i) / float(xf)
			data[i] = data[i] * a + data[n - xf + i] * (1.0 - a)
		n -= xf
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, absf(data[i]))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var fade := mini(80, n / 4)
	for i in n:
		var v := data[i] / peak * vol
		if not loop and i > n - fade:
			v *= float(n - i) / float(fade)
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = bytes
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = n
	return st
