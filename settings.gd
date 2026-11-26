extends RefCounted
# settings.gd - every user-facing option lives here, saved to user://naval_io_settings.cfg

const PATH := "user://naval_io_settings.cfg"
const ACC_PATH := "user://naval_io_accounts.cfg"
const SEASON_DAYS := 20
const ACCOUNT_FIELDS := ["nick", "xp", "rp", "ranked_mode", "bp", "bp_claim", "season", "season_start", "paint", "battles", "kills", "best", "played", "m_day", "m_kills", "m_dmg", "m_xp", "m_crates", "m_gift"]

const DEFAULTS := {
	# audio
	"mute": false,
	"vol_master": 0.8,
	"vol_sfx": 1.0,
	"vol_amb": 0.5,
	"vol_eng": 0.6,
	# graphics
	"quality": 3,          # 0 Low, 1 Medium, 2 High, 3 Auto
	"shadows": true,
	"msaa": true,
	"bake": true,
	"wakes": true,
	"fx_density": 1.0,
	"shake": 1.0,
	"fps_cap": 0,          # 0 = unlimited
	"vsync": true,
	"fullscreen": false,
	"show_fps": false,
	# gameplay
	"bots": 32,
	"difficulty": 1,       # 0 Easy, 1 Normal, 2 Hard
	"names": true,
	"fog": true,
	"hpbars": true,
	"dmgnums": true,
	"aimline": true,
	"minimap": true,
	"zoom_sens": 1.0,
	"autossec": true,
	# meta progression
	"xp": 0,
	"rp": 0,
	"ranked_mode": false,
	"nick": "Captain",
	# season / battle pass / career
	"bp": 0,
	"bp_claim": 0,
	"season": 1,
	"season_start": 0,
	"paint": "navy",
	"battles": 0,
	"kills": 0,
	"best": 0,
	"played": "",
	"m_day": 0,
	"m_kills": 0,
	"m_dmg": 0,
	"m_xp": 0,
	"m_crates": 0,
	"m_gift": 0,
}

const DEFAULT_KEYS := {
	"up": KEY_W,
	"down": KEY_S,
	"left": KEY_A,
	"right": KEY_D,
	"fire": KEY_SPACE,
	"ab1": KEY_Q,
	"ab2": KEY_E,
	"ab3": KEY_R,
	"air": KEY_V,
	"upgrade": KEY_U,
}

const KEY_LABELS := {
	"up": "Throttle up",
	"down": "Throttle down / reverse",
	"left": "Steer left",
	"right": "Steer right",
	"fire": "Fire selected weapon",
	"ab1": "Ability 1",
	"ab2": "Ability 2",
	"ab3": "Ability 3",
	"air": "Switch ship / aircraft",
	"upgrade": "Open promotion window",
}

var d: Dictionary = {}
var keys: Dictionary = {}
var account_key := ""
var logged_in := false

func _init() -> void:
	reset_all()
	load_file()

func reset_all() -> void:
	d = DEFAULTS.duplicate()
	keys = DEFAULT_KEYS.duplicate()

func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in d.keys():
		if cf.has_section_key("s", k):
			d[k] = type_convert(cf.get_value("s", k), typeof(d[k]))
	for k in keys.keys():
		if cf.has_section_key("k", k):
			keys[k] = int(cf.get_value("k", k))

func save_file() -> void:
	var cf := ConfigFile.new()
	for k in d.keys():
		cf.set_value("s", k, d[k])
	for k in keys.keys():
		cf.set_value("k", k, keys[k])
	cf.save(PATH)

func key(action: String) -> int:
	return int(keys[action])

func down(action: String) -> bool:
	return Input.is_key_pressed(key(action) as Key)

static func pin_hash(pin: String) -> String:
	return pin.sha256_text().substr(0, 24)

func load_account(pin: String) -> bool:
	var key := pin_hash(pin.strip_edges())
	if key.is_empty():
		return false
	account_key = key
	var cf := ConfigFile.new()
	if cf.load(ACC_PATH) == OK and cf.has_section(key):
		for f_name in ACCOUNT_FIELDS:
			if cf.has_section_key(key, f_name):
				d[f_name] = cf.get_value(key, f_name)
		logged_in = true
		season_check()
		save_file()
		return true
	# fresh account for this PIN
	for f_name in ACCOUNT_FIELDS:
		d[f_name] = DEFAULTS.get(f_name, d.get(f_name, 0))
	d["nick"] = "Captain%04d" % (randi() % 10000)
	d["season_start"] = int(Time.get_unix_time_from_system())
	logged_in = true
	store_account()
	save_file()
	return true

func store_account() -> void:
	if account_key.is_empty():
		return
	var cf := ConfigFile.new()
	cf.load(ACC_PATH)
	for f_name in ACCOUNT_FIELDS:
		cf.set_value(account_key, f_name, d.get(f_name))
	cf.save(ACC_PATH)

func logout() -> void:
	store_account()
	account_key = ""
	logged_in = false

func season_check() -> void:
	var now := int(Time.get_unix_time_from_system())
	var start := int(d.get("season_start", 0))
	if start <= 0:
		d["season_start"] = now
		return
	if now - start >= SEASON_DAYS * 86400:
		d["rp"] = 0
		d["bp"] = 0
		d["bp_claim"] = 0
		d["m_day"] = 0
		d["m_kills"] = 0
		d["m_dmg"] = 0
		d["m_xp"] = 0
		d["m_crates"] = 0
		d["m_gift"] = 0
		d["season"] = int(d.get("season", 1)) + 1
		d["season_start"] = now

func mark_played(ship_id: String) -> void:
	var played := String(d.get("played", ""))
	var parts := played.split(",") if not played.is_empty() else PackedStringArray()
	if parts.has(ship_id):
		return
	parts.append(ship_id)
	while parts.size() > 60:
		parts.remove_at(0)
	d["played"] = ",".join(parts)

func has_played(ship_id: String) -> bool:
	return String(d.get("played", "")).split(",").has(ship_id)

func season_days_left() -> int:
	var start := int(d.get("season_start", 0))
	if start <= 0:
		return SEASON_DAYS
	var left := SEASON_DAYS * 86400 - (int(Time.get_unix_time_from_system()) - start)
	return maxi(0, int(ceil(float(left) / 86400.0)))

func f(k: String) -> float:
	return float(d[k])

func i(k: String) -> int:
	return int(d[k])

func b(k: String) -> bool:
	return bool(d[k])
