extends RefCounted
# settings.gd - every user-facing option lives here, saved to user://naval_io_settings.cfg

const PATH := "user://naval_io_settings.cfg"

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

func f(k: String) -> float:
	return float(d[k])

func i(k: String) -> int:
	return int(d[k])

func b(k: String) -> bool:
	return bool(d[k])
