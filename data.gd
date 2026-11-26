extends RefCounted
# data.gd - all static game data (tiers, weapons, ships, aircraft, abilities, visual styles)
# plus a few pure geometry helpers.  No game logic lives here, so you can add ships and
# weapons just by editing this file.
#
# HOW TO ADD A SHIP: copy one of the _s(...) lines in _build() and change the numbers.
# HOW TO ADD A WEAPON: add an entry to WEAPONS and use its id in a ship's g("id", ...) group.
# Ship extras: {"lvl": n} locks the ship until account level n, {"squad": n} gives the
# player an n-plane squadron that flies as one, {"air2": id, "n2": n} adds an AI-controlled
# squadron, {"sec": true} on weapon groups marks auto-firing secondaries.
#
# Mount coordinates are fractions: x = fraction of hull LENGTH (+ = bow), y = fraction of
# hull WIDTH (+ = starboard).  Angles are in degrees (0 = straight ahead, 90 = starboard).

const TIER_NEED := [0, 90, 250, 550, 1000, 1700, 2700, 4200, 6300, 9000]
const TIER_ZOOM := [1.0, 0.92, 0.84, 0.76, 0.68, 0.60, 0.54, 0.48, 0.45, 0.42]
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
const MAX_TIER := 10
const KIND := {"bullet": 0, "shell": 1, "torp": 2, "missile": 3, "rocket": 4, "mine": 5, "bomb": 6}

# ---- meta progression (account XP, levels, ranked rating, ship unlocks) ----
const MAX_LEVEL := 30
const RANKS := [
	[0, "Rookie"], [250, "Bronze"], [600, "Silver"], [1100, "Gold"], [1800, "Platinum"],
	[2800, "Diamond"], [4200, "Master"], [6000, "Elite"], [8500, "Legend"], [12000, "PLUTONIUM"],
]

const RANK_META := [
	{"sh": 0, "col": Color(0.62, 0.66, 0.70), "pips": 0},
	{"sh": 1, "col": Color(0.80, 0.56, 0.30), "pips": 1},
	{"sh": 1, "col": Color(0.74, 0.76, 0.80), "pips": 2},
	{"sh": 1, "col": Color(0.96, 0.81, 0.20), "pips": 3},
	{"sh": 2, "col": Color(0.55, 0.82, 0.96), "pips": 2},
	{"sh": 2, "col": Color(0.44, 0.72, 0.99), "pips": 3},
	{"sh": 3, "col": Color(0.58, 0.56, 0.99), "pips": 3},
	{"sh": 3, "col": Color(0.80, 0.50, 0.96), "pips": 4},
	{"sh": 4, "col": Color(0.96, 0.36, 0.36), "pips": 4},
	{"sh": 5, "col": Color(0.12, 0.98, 0.46), "pips": 0},
]

static func rank_i_from_rp(rp: int) -> int:
	var idx := 0
	for r in RANKS.size():
		if rp >= int(RANKS[r][0]):
			idx = r
	return idx

const PAINTS := {
	"navy": {"n": "Navy Blue", "c": Color(0.30, 0.45, 0.65)},
	"arctic": {"n": "Arctic", "c": Color(0.82, 0.87, 0.91)},
	"jungle": {"n": "Jungle", "c": Color(0.31, 0.45, 0.30)},
	"desert": {"n": "Desert", "c": Color(0.72, 0.60, 0.42)},
	"crimson": {"n": "Crimson", "c": Color(0.62, 0.17, 0.14)},
	"gold": {"n": "Emperor Gold", "c": Color(0.86, 0.69, 0.22)},
	"stealth": {"n": "Stealth", "c": Color(0.13, 0.15, 0.17)},
	"radiation": {"n": "Radioactive", "c": Color(0.22, 0.82, 0.32)},
}

const BP_TIER_COST := 120
const BP_REWARDS := [
	{"k": "xp", "v": 250, "n": "+250 XP"},
	{"k": "paint", "v": "arctic", "n": "Paint: Arctic"},
	{"k": "rp", "v": 60, "n": "+60 Ranked Rating"},
	{"k": "xp", "v": 400, "n": "+400 XP"},
	{"k": "paint", "v": "jungle", "n": "Paint: Jungle"},
	{"k": "xp", "v": 500, "n": "+500 XP"},
	{"k": "paint", "v": "desert", "n": "Paint: Desert"},
	{"k": "rp", "v": 80, "n": "+80 Ranked Rating"},
	{"k": "xp", "v": 650, "n": "+650 XP"},
	{"k": "paint", "v": "crimson", "n": "Paint: Crimson"},
	{"k": "xp", "v": 800, "n": "+800 XP"},
	{"k": "paint", "v": "gold", "n": "Paint: Emperor Gold"},
	{"k": "xp", "v": 1000, "n": "+1000 XP"},
	{"k": "rp", "v": 100, "n": "+100 Ranked Rating"},
	{"k": "xp", "v": 1250, "n": "+1250 XP"},
	{"k": "paint", "v": "stealth", "n": "Paint: Stealth"},
	{"k": "xp", "v": 1500, "n": "+1500 XP"},
	{"k": "rp", "v": 150, "n": "+150 Ranked Rating"},
	{"k": "xp", "v": 2000, "n": "+2000 XP"},
	{"k": "paint", "v": "radiation", "n": "Paint: Radioactive"},
]

const BP_MISSIONS := [
	{"n": "Sink %d ships", "k": "kills", "t": [2, 4, 6], "r": 40},
	{"n": "Collect %d supply crates", "k": "crates", "t": [12, 20, 30], "r": 30},
	{"n": "Deal %d damage", "k": "dmg", "t": [3000, 6000, 9000], "r": 40},
	{"n": "Earn %d XP", "k": "xp", "t": [400, 700, 1000], "r": 30},
	{"n": "Promote %d time in battle", "k": "promo", "t": [1, 1, 2], "r": 50},
]


static func level_from_xp(xp: int) -> int:
	var lvl := 1
	var cost := 250
	var left := maxi(xp, 0)
	while lvl < MAX_LEVEL and left >= cost:
		left -= cost
		lvl += 1
		cost = int(float(cost) * 1.32)
	return lvl

static func level_progress(xp: int) -> Dictionary:
	var lvl := level_from_xp(xp)
	if lvl >= MAX_LEVEL:
		return {"lvl": lvl, "have": 0, "need": 0}
	var cost := 250
	var left := maxi(xp, 0)
	var l := 1
	while l < lvl:
		left -= cost
		cost = int(float(cost) * 1.32)
		l += 1
	return {"lvl": lvl, "have": left, "need": cost}

static func rank_from_rp(rp: int) -> String:
	var r := "Rookie"
	for e in RANKS:
		if rp >= int(e[0]):
			r = str(e[1])
	return r

static func unlocked(def: Dictionary, level: int) -> bool:
	return level >= int(def.get("lvl", 1))

# ---------------------------------------------------------------------------------------
# WEAPONS
#  n=name  vis=how the mount is drawn  pk=projectile kind  dmg=damage per projectile
#  spd=projectile speed  rng=range (px)  rl=reload PER BARREL (s)  gap=min time between
#  shots of this weapon (s)  spr=random spread (rad)  trav=mount traverse speed (rad/s)
#  sal=projectiles per shot  mode=0 fly to aim point, 1 follow cursor, 2 seeker homing
#  turn=projectile turn rate  seek=seeker range  spl=splash radius  bw/bl=barrel width/length
#  aa=can hit aircraft  pd=point defence (auto-shoots incoming missiles)  pick=choose the
#  mount closest to the aim direction instead of firing in sequence  ic=HUD icon
# ---------------------------------------------------------------------------------------
const WEAPONS := {
	"mg": {"n": "12.7mm Machine Gun", "vis": "gun", "pk": "bullet", "dmg": 5.0, "spd": 720.0, "rl": 0.2, "gap": 0.05, "spr": 0.07, "trav": 9.0, "bw": 0.8, "bl": 5.0, "snd": "mg", "aa": true, "ic": "bullet", "ar": 12.0, "rng": 430.0},
	"ac20": {"n": "20mm Autocannon", "vis": "gun", "pk": "bullet", "dmg": 7.0, "spd": 700.0, "rl": 0.4, "gap": 0.08, "spr": 0.05, "trav": 7.0, "bw": 1.0, "bl": 6.0, "snd": "ac", "aa": true, "ic": "bullet", "ar": 14.0, "rng": 520.0},
	"ac40": {"n": "40mm Bofors", "vis": "gun", "pk": "bullet", "dmg": 11.0, "spd": 640.0, "rl": 0.75, "gap": 0.12, "spr": 0.045, "trav": 5.0, "bw": 1.0, "bl": 8.0, "snd": "ac", "aa": true, "ic": "shell_s", "ar": 18.0, "rng": 620.0},
	"aa37": {"n": "37mm Quad AA", "vis": "gun", "pk": "bullet", "dmg": 9.0, "spd": 660.0, "rl": 0.35, "gap": 0.1, "spr": 0.05, "trav": 6.5, "bw": 1.1, "bl": 7.0, "snd": "ac", "aa": true, "ic": "shell_s", "ar": 20.0, "rng": 620.0},
	"aa57": {"n": "57mm Twin AA", "vis": "gun", "pk": "bullet", "dmg": 16.0, "spd": 640.0, "rl": 0.7, "gap": 0.18, "spr": 0.04, "trav": 5.5, "bw": 1.2, "bl": 9.0, "snd": "ac", "aa": true, "ic": "shell_s", "ar": 26.0, "rng": 620.0},
	"g88": {"n": "88mm Deck Gun", "vis": "gun", "pk": "shell", "dmg": 24.0, "spd": 650.0, "rl": 1.1, "gap": 0.3, "spr": 0.03, "trav": 4.5, "bw": 1.2, "bl": 11.0, "spl": 10.0, "snd": "gun_s", "aa": true, "ic": "shell_s", "ar": 28.0, "rng": 800.0},
	"g76": {"n": "76mm Dual-Purpose Gun", "vis": "gun", "pk": "shell", "dmg": 30.0, "spd": 650.0, "rl": 1.0, "gap": 0.28, "spr": 0.03, "trav": 4.5, "bw": 1.2, "bl": 11.0, "spl": 12.0, "snd": "gun_s", "aa": true, "ic": "shell_s", "ar": 28.0, "rng": 740.0},
	"g76r": {"n": "76mm Super Rapid", "vis": "gun", "pk": "shell", "dmg": 26.0, "spd": 660.0, "rl": 0.6, "gap": 0.2, "spr": 0.03, "trav": 5.5, "bw": 1.2, "bl": 11.0, "spl": 11.0, "snd": "gun_s", "aa": true, "ic": "shell_s", "ar": 28.0, "mod": true, "rng": 760.0},
	"g100": {"n": "100mm Gun", "vis": "gun", "pk": "shell", "dmg": 40.0, "spd": 640.0, "rl": 1.5, "gap": 0.35, "spr": 0.03, "trav": 3.8, "bw": 1.4, "bl": 13.0, "spl": 15.0, "snd": "gun_s", "aa": true, "ic": "shell_s", "ar": 30.0, "rng": 800.0},
	"g127": {"n": "127mm Gun", "vis": "gun", "pk": "shell", "dmg": 50.0, "spd": 630.0, "rl": 1.9, "gap": 0.4, "spr": 0.028, "trav": 3.5, "bw": 1.6, "bl": 15.0, "spl": 19.0, "snd": "gun_m", "ic": "shell_m", "aa": true, "ar": 32.0, "rng": 870.0},
	"g127m": {"n": "127mm Mk 45 Automatic", "vis": "gun", "pk": "shell", "dmg": 46.0, "spd": 650.0, "rl": 1.2, "gap": 0.3, "spr": 0.025, "trav": 4.5, "bw": 1.6, "bl": 15.0, "spl": 18.0, "snd": "gun_m", "ic": "shell_m", "aa": true, "ar": 32.0, "mod": true, "rng": 900.0},
	"g152": {"n": "152mm Gun", "vis": "gun", "pk": "shell", "dmg": 62.0, "spd": 610.0, "rl": 2.7, "gap": 0.45, "spr": 0.028, "trav": 2.8, "bw": 1.9, "bl": 18.0, "spl": 24.0, "snd": "gun_m", "ic": "shell_m", "rng": 950.0},
	"g155": {"n": "155mm Advanced Gun", "vis": "gun", "pk": "shell", "dmg": 85.0, "spd": 640.0, "rl": 2.4, "gap": 0.5, "spr": 0.02, "trav": 3.2, "bw": 2.0, "bl": 19.0, "spl": 28.0, "snd": "gun_m", "ic": "shell_m", "mod": true, "rng": 1100.0},
	"g203": {"n": "203mm Gun", "vis": "gun", "pk": "shell", "dmg": 100.0, "spd": 600.0, "rl": 3.5, "gap": 0.5, "spr": 0.026, "trav": 2.3, "bw": 2.2, "bl": 21.0, "spl": 32.0, "snd": "gun_l", "ic": "shell_l", "rng": 1030.0},
	"g305": {"n": "305mm Gun", "vis": "gun", "pk": "shell", "dmg": 160.0, "spd": 590.0, "rl": 4.3, "gap": 0.55, "spr": 0.025, "trav": 1.8, "bw": 2.5, "bl": 25.0, "spl": 40.0, "snd": "gun_l", "ic": "shell_l", "rng": 1120.0},
	"g356": {"n": "356mm Gun", "vis": "gun", "pk": "shell", "dmg": 200.0, "spd": 585.0, "rl": 4.8, "gap": 0.6, "spr": 0.024, "trav": 1.6, "bw": 2.7, "bl": 27.0, "spl": 44.0, "snd": "gun_xl", "ic": "shell_l", "rng": 1180.0},
	"g381": {"n": "381mm Gun", "vis": "gun", "pk": "shell", "dmg": 235.0, "spd": 580.0, "rl": 5.2, "gap": 0.65, "spr": 0.024, "trav": 1.5, "bw": 2.8, "bl": 29.0, "spl": 48.0, "snd": "gun_xl", "ic": "shell_l", "rng": 1240.0},
	"g406": {"n": "406mm Gun", "vis": "gun", "pk": "shell", "dmg": 280.0, "spd": 580.0, "rl": 5.6, "gap": 0.7, "spr": 0.022, "trav": 1.4, "bw": 3.0, "bl": 31.0, "spl": 52.0, "snd": "gun_xl", "ic": "shell_l", "rng": 1300.0},
	"g460": {"n": "460mm Gun", "vis": "gun", "pk": "shell", "dmg": 340.0, "spd": 575.0, "rl": 6.2, "gap": 0.75, "spr": 0.022, "trav": 1.2, "bw": 3.2, "bl": 34.0, "spl": 58.0, "snd": "gun_xl", "ic": "shell_l", "rng": 1380.0},
	"g510": {"n": "510mm Gun", "vis": "gun", "pk": "shell", "dmg": 500.0, "spd": 570.0, "rl": 7.0, "gap": 0.8, "spr": 0.02, "trav": 1.1, "bw": 3.4, "bl": 37.0, "spl": 64.0, "snd": "gun_xl", "ic": "shell_l", "rng": 1380.0},
	"ciws": {"n": "CIWS Gatling", "vis": "ciws", "pk": "bullet", "dmg": 2.0, "spd": 800.0, "rl": 0.45, "gap": 0.03, "spr": 0.05, "trav": 9.0, "bw": 1.0, "bl": 6.0, "snd": "ciws", "aa": true, "pd": true, "ic": "bullet", "ar": 15.0, "rng": 400.0},
	"torp": {"n": "533mm Torpedo", "vis": "tubes", "pk": "torp", "dmg": 130.0, "spd": 135.0, "rl": 9.0, "gap": 0.6, "spr": 0.02, "trav": 1.4, "mode": 0, "turn": 1.1, "spl": 26.0, "pick": true, "snd": "torp", "ic": "torp", "tl": 12.0, "rng": 900.0},
	"torp_l": {"n": "Lightweight Homing Torpedo", "vis": "tubes", "pk": "torp", "dmg": 90.0, "spd": 150.0, "rl": 6.0, "gap": 0.5, "spr": 0.02, "trav": 1.6, "mode": 2, "turn": 2.2, "seek": 420.0, "spl": 20.0, "pick": true, "snd": "torp", "ic": "torp", "tl": 9.0, "rng": 650.0},
	"torp_h": {"n": "Long Lance Torpedo", "vis": "tubes", "pk": "torp", "dmg": 360.0, "spd": 185.0, "rl": 14.0, "gap": 0.8, "spr": 0.015, "trav": 1.2, "mode": 0, "turn": 0.9, "spl": 38.0, "pick": true, "snd": "torp", "ic": "torp", "tl": 16.0, "seek": 0.0, "rng": 1400.0},
	"torp_w": {"n": "Wire-Guided Torpedo", "vis": "tubes", "pk": "torp", "dmg": 230.0, "spd": 170.0, "rl": 11.0, "gap": 0.8, "spr": 0.015, "trav": 1.4, "mode": 2, "turn": 2.0, "spl": 32.0, "pick": true, "snd": "torp", "ic": "torp", "tl": 14.0, "seek": 520.0, "rng": 1200.0},
	"mine": {"n": "Mine / Depth Charge Rack", "vis": "mine", "pk": "mine", "dmg": 220.0, "spd": 40.0, "rng": 60.0, "rl": 8.0, "gap": 1.2, "spr": 0.3, "trav": 1.0, "spl": 58.0, "snd": "mine", "ic": "mine"},
	"rocket": {"n": "Rocket Barrage", "vis": "rack", "pk": "rocket", "dmg": 16.0, "sal": 8, "spd": 460.0, "rl": 7.0, "gap": 0.8, "spr": 0.16, "trav": 2.0, "mode": 0, "turn": 0.6, "spl": 17.0, "snd": "rocket", "ic": "rocket", "mt": 5, "rng": 720.0},
	"rocket_h": {"n": "Unguided Missile Salvo", "vis": "rack", "pk": "rocket", "dmg": 55.0, "sal": 2, "spd": 540.0, "rl": 11.0, "gap": 1.0, "spr": 0.05, "trav": 1.6, "mode": 0, "turn": 0.0, "spl": 24.0, "snd": "rocket", "ic": "rocket_h", "mt": 6, "rng": 1100.0},
	"ssm_s": {"n": "Light Anti-Ship Missile", "vis": "can", "pk": "missile", "dmg": 90.0, "spd": 380.0, "rl": 12.0, "gap": 1.1, "spr": 0.02, "trav": 1.5, "mode": 2, "turn": 2.6, "seek": 700.0, "spl": 20.0, "snd": "missile", "ic": "missile_s", "mt": 1, "rng": 1500.0},
	"ssm_l": {"n": "Sea-Skimmer Anti-Ship Missile", "vis": "can", "pk": "missile", "dmg": 170.0, "spd": 420.0, "rl": 16.0, "gap": 1.5, "spr": 0.02, "trav": 1.5, "mode": 2, "turn": 2.3, "seek": 900.0, "spl": 26.0, "snd": "missile", "ic": "missile", "mt": 2, "rng": 2300.0},
	"ssm_h": {"n": "Heavy Supersonic Missile", "vis": "can", "pk": "missile", "dmg": 430.0, "spd": 520.0, "rl": 24.0, "gap": 2.0, "spr": 0.02, "trav": 1.5, "mode": 2, "turn": 1.7, "seek": 1200.0, "spl": 44.0, "snd": "missile", "ic": "missile_h", "mt": 3, "rng": 3200.0},
	"cruise": {"n": "Long-Range Cruise Missile", "vis": "vls", "pk": "missile", "dmg": 230.0, "spd": 430.0, "rl": 20.0, "gap": 1.5, "spr": 0.0, "trav": 1.0, "mode": 2, "turn": 3.0, "spl": 34.0, "snd": "missile", "ic": "cruise", "seek": 1500.0, "mt": 4, "rng": 4200.0},
	"a_mg": {"n": "Door / Chain Gun", "vis": "gun", "pk": "bullet", "dmg": 8.0, "spd": 700.0, "rl": 0.16, "gap": 0.06, "spr": 0.06, "trav": 9.0, "bw": 0.8, "bl": 5.0, "snd": "mg", "ic": "bullet", "rng": 480.0},
	"a_rocket": {"n": "Rocket Pod", "vis": "rack", "pk": "rocket", "dmg": 21.0, "sal": 6, "spd": 520.0, "rl": 8.0, "gap": 0.9, "spr": 0.1, "trav": 1.0, "mode": 0, "turn": 0.0, "spl": 16.0, "snd": "rocket", "ic": "rocket", "mt": 5, "rng": 700.0},
	"a_torp": {"n": "Air-Dropped Torpedo", "vis": "tubes", "pk": "torp", "dmg": 210.0, "spd": 145.0, "rl": 14.0, "gap": 1.0, "spr": 0.0, "trav": 1.0, "mode": 2, "turn": 1.5, "seek": 260.0, "spl": 28.0, "snd": "torp", "ic": "torp", "tl": 9.0, "rng": 800.0},
	"bomb_s": {"n": "Light Bombs", "vis": "rack", "pk": "bomb", "dmg": 95.0, "spd": 0.0, "rng": 0.0, "rl": 7.0, "gap": 0.5, "spr": 0.0, "trav": 1.0, "spl": 36.0, "snd": "bomb", "ic": "bomb"},
	"bomb_l": {"n": "Heavy Bombs", "vis": "rack", "pk": "bomb", "dmg": 320.0, "spd": 0.0, "rng": 0.0, "rl": 12.0, "gap": 1.0, "spr": 0.0, "trav": 1.0, "spl": 54.0, "snd": "bomb", "ic": "bomb"},
	"a_ms": {"n": "Light Air-Launched Missile", "vis": "can", "pk": "missile", "dmg": 165.0, "spd": 440.0, "rl": 9.0, "gap": 1.0, "spr": 0.02, "trav": 1.5, "mode": 2, "turn": 2.6, "seek": 800.0, "spl": 22.0, "snd": "missile", "ic": "missile_s", "mt": 7, "rng": 1700.0},
	"a_ms_h": {"n": "Supersonic Air Missile", "vis": "can", "pk": "missile", "dmg": 390.0, "spd": 560.0, "rl": 16.0, "gap": 1.4, "spr": 0.02, "trav": 1.5, "mode": 2, "turn": 2.0, "seek": 1100.0, "spl": 40.0, "snd": "missile", "ic": "missile_h", "mt": 8, "rng": 2800.0},
	"a_bomb_h": {"n": "Armor-Piercing Bomb", "vis": "rack", "pk": "bomb", "dmg": 470.0, "spd": 0.0, "rng": 0.0, "rl": 14.0, "gap": 1.2, "spr": 0.0, "trav": 1.0, "spl": 62.0, "snd": "bomb", "ic": "bomb"},
	"mark": {"n": "Target Designator", "vis": "rack", "pk": "bullet", "dmg": 0.0, "spd": 0.0, "rng": 700.0, "rl": 6.0, "gap": 0.2, "spr": 0.0, "trav": 1.0, "special": "mark", "snd": "ping", "ic": "mark"},
}

# ---------------------------------------------------------------------------------------
# AIRCRAFT  (launched from some ships, press V to take control)
#  vis = detection radius around the aircraft, leash = max distance from its ship,
#  cd = rebuild time after being shot down, w = [[weapon id, barrels], ...]
#  Carriers launch a whole squadron (ship key "squad") that flies as ONE formation.
# ---------------------------------------------------------------------------------------
const AIR := {
	"uav": {"n": "Recon Drone", "kind": "plane", "hp": 60.0, "spd": 260.0, "turn": 3.2, "vis": 1500.0, "leash": 2000.0, "cd": 6.0, "cam": 0.8, "size": 0.7, "col": Color(0.82, 0.84, 0.86), "w": [["mark", 1]], "desc": "Long-range recon. Marks enemies (+25% damage taken)."},
	"heli_scout": {"n": "Scout Helicopter", "kind": "heli", "hp": 95.0, "spd": 220.0, "turn": 2.8, "vis": 1250.0, "leash": 1500.0, "cd": 6.0, "cam": 0.85, "size": 1.0, "col": Color(0.70, 0.74, 0.78), "w": [["mark", 1], ["a_mg", 1]], "desc": "Hovering spotter. Marks enemies for your guns."},
	"heli_asw": {"n": "ASW Helicopter", "kind": "heli", "hp": 130.0, "spd": 195.0, "turn": 2.6, "vis": 900.0, "leash": 1400.0, "cd": 7.0, "cam": 0.85, "size": 1.1, "col": Color(0.36, 0.40, 0.44), "w": [["a_torp", 2], ["a_mg", 1]], "desc": "Drops homing torpedoes and has a door gun."},
	"heli_attack": {"n": "Attack Helicopter", "kind": "heli", "hp": 175.0, "spd": 210.0, "turn": 2.6, "vis": 800.0, "leash": 1500.0, "cd": 7.0, "cam": 0.85, "size": 1.2, "col": Color(0.22, 0.26, 0.22), "turret": true, "w": [["a_mg", 2], ["a_rocket", 1]], "desc": "Chain gun that follows the cursor, plus rocket pods."},
	"heli_heavy": {"n": "Heavy Gunship", "kind": "heli", "hp": 235.0, "spd": 190.0, "turn": 2.4, "vis": 850.0, "leash": 1600.0, "cd": 8.0, "cam": 0.82, "size": 1.35, "col": Color(0.18, 0.20, 0.18), "turret": true, "w": [["a_rocket", 2], ["a_ms", 1], ["a_mg", 2]], "desc": "Twin rocket pods, a light anti-ship missile and twin chain guns."},
	"floatplane": {"n": "Spotter Floatplane", "kind": "plane", "hp": 75.0, "spd": 280.0, "turn": 2.0, "vis": 1400.0, "leash": 2400.0, "cd": 6.0, "cam": 0.75, "size": 1.0, "col": Color(0.60, 0.64, 0.58), "w": [["mark", 1], ["bomb_s", 2]], "desc": "Fast scout. Marks targets and drops light bombs."},
	"patrol_seaplane": {"n": "Patrol Seaplane", "kind": "plane", "hp": 150.0, "spd": 265.0, "turn": 1.8, "vis": 1500.0, "leash": 2600.0, "cd": 7.0, "cam": 0.75, "size": 1.5, "col": Color(0.55, 0.60, 0.55), "w": [["a_torp", 1], ["bomb_s", 2]], "desc": "Twin-engine flying boat with a torpedo and light bombs."},
	"torp_bomber": {"n": "Torpedo Bomber", "kind": "plane", "hp": 145.0, "spd": 300.0, "turn": 1.9, "vis": 1000.0, "leash": 2600.0, "cd": 6.0, "cam": 0.74, "size": 1.4, "col": Color(0.35, 0.40, 0.38), "w": [["a_torp", 2]], "desc": "Drops a pair of homing torpedoes on the run-in."},
	"dive_bomber": {"n": "Dive Bomber", "kind": "plane", "hp": 160.0, "spd": 320.0, "turn": 1.7, "vis": 1000.0, "leash": 2600.0, "cd": 6.0, "cam": 0.72, "size": 1.5, "col": Color(0.30, 0.34, 0.42), "w": [["bomb_l", 2], ["a_mg", 2]], "desc": "Heavy bombs and forward machine guns."},
	"jet_strike": {"n": "Strike Jet", "kind": "plane", "hp": 220.0, "spd": 430.0, "turn": 2.2, "vis": 1100.0, "leash": 3000.0, "cd": 7.0, "cam": 0.68, "size": 1.5, "col": Color(0.42, 0.46, 0.50), "w": [["a_ms", 2], ["a_mg", 2]], "desc": "Fast carrier jet with a pair of anti-ship missiles and cannon."},
	"jet_bomber": {"n": "Carrier Jet Bomber", "kind": "plane", "hp": 260.0, "spd": 410.0, "turn": 1.9, "vis": 1200.0, "leash": 3000.0, "cd": 8.0, "cam": 0.68, "size": 1.7, "col": Color(0.30, 0.33, 0.38), "w": [["bomb_l", 3]], "desc": "A rack of heavy bombs delivered at jet speed."},
	"jet_heavy": {"n": "Heavy Strike Jet", "kind": "plane", "hp": 290.0, "spd": 450.0, "turn": 1.9, "vis": 1150.0, "leash": 3200.0, "cd": 8.0, "cam": 0.66, "size": 1.85, "col": Color(0.26, 0.29, 0.33), "w": [["a_ms_h", 1], ["a_rocket", 1], ["a_mg", 2]], "desc": "Big twin-engine strike jet: one supersonic missile, rockets and cannon."},
}

const ABILITIES := {
	"boost": {"n": "Flank Speed", "dur": 4.0, "cd": 22.0, "desc": "+45% speed"},
	"repair": {"n": "Damage Control", "dur": 6.0, "cd": 35.0, "desc": "Restores 30% hull"},
	"smoke": {"n": "Smoke Screen", "dur": 9.0, "cd": 30.0, "desc": "Enemies spot you from far less distance"},
	"radar": {"n": "Radar Sweep", "dur": 6.0, "cd": 28.0, "desc": "Reveals every ship on the map"},
	"barrage": {"n": "Barrage", "dur": 6.0, "cd": 38.0, "desc": "Weapons reload twice as fast"},
	"chaff": {"n": "Countermeasures", "dur": 0.5, "cd": 24.0, "desc": "Nearby missiles and torpedoes lose lock"},
	"mine_l": {"n": "Rapid Laying", "dur": 5.0, "cd": 30.0, "desc": "Mine reloads four times faster"},
	"dive": {"n": "Emergency Dive", "dur": 16.0, "cd": 1.5, "desc": "Submerge for 16s: guns cannot touch you, only torpedoes. Dive again whenever you need it."},
}

const PAL := {
	"us": {"hull": Color(0.40, 0.45, 0.50), "deck": Color(0.52, 0.49, 0.42), "sup": Color(0.62, 0.66, 0.70)},
	"de": {"hull": Color(0.37, 0.40, 0.43), "deck": Color(0.44, 0.41, 0.37), "sup": Color(0.56, 0.59, 0.61)},
	"jp": {"hull": Color(0.33, 0.37, 0.40), "deck": Color(0.49, 0.41, 0.32), "sup": Color(0.50, 0.53, 0.56)},
	"ru": {"hull": Color(0.47, 0.52, 0.56), "deck": Color(0.38, 0.41, 0.43), "sup": Color(0.67, 0.70, 0.72)},
	"mod": {"hull": Color(0.48, 0.53, 0.58), "deck": Color(0.42, 0.45, 0.48), "sup": Color(0.72, 0.75, 0.78)},
	"pt": {"hull": Color(0.36, 0.42, 0.38), "deck": Color(0.50, 0.43, 0.30), "sup": Color(0.58, 0.61, 0.57)},
	"cv": {"hull": Color(0.40, 0.44, 0.48), "deck": Color(0.26, 0.28, 0.30), "sup": Color(0.58, 0.61, 0.65)},
	"sub": {"hull": Color(0.22, 0.26, 0.28), "deck": Color(0.28, 0.32, 0.33), "sup": Color(0.40, 0.45, 0.47)},
}

# bow = where the bow taper starts (0..1 along the hull), bp = bow fullness, st = stern width
# sup = [x, length, width] superstructure blocks, fun = funnel x positions, mast = mast x
const STYLES := {
	"pt": {"bow": 0.55, "bp": 1.6, "st": 0.72, "pal": "pt", "sup": [[0.02, 0.30, 0.50]], "fun": [], "mast": [0.02]},
	"boat": {"bow": 0.62, "bp": 1.7, "st": 0.75, "pal": "pt", "sup": [[0.12, 0.26, 0.50], [-0.12, 0.18, 0.40]], "fun": [], "mast": [0.12]},
	"ww2s": {"bow": 0.72, "bp": 1.7, "st": 0.80, "pal": "us", "sup": [[0.08, 0.20, 0.55], [-0.14, 0.12, 0.40]], "fun": [-0.08], "mast": [0.08, -0.24]},
	"ww2m": {"bow": 0.74, "bp": 1.7, "st": 0.82, "pal": "us", "sup": [[0.12, 0.14, 0.55], [-0.06, 0.10, 0.45]], "fun": [0.0, -0.14], "mast": [0.12, -0.10]},
	"ww2l": {"bow": 0.78, "bp": 1.8, "st": 0.86, "pal": "us", "sup": [[0.10, 0.10, 0.50], [0.03, 0.07, 0.34], [-0.07, 0.13, 0.55]], "fun": [-0.04, -0.15], "mast": [0.10, -0.26]},
	"ww2xl": {"bow": 0.80, "bp": 1.8, "st": 0.88, "pal": "de", "sup": [[0.12, 0.10, 0.50], [0.03, 0.08, 0.36], [-0.06, 0.12, 0.55], [-0.18, 0.08, 0.40]], "fun": [-0.02, -0.14], "mast": [0.12, -0.30]},
	"jpm": {"bow": 0.74, "bp": 1.7, "st": 0.80, "pal": "jp", "sup": [[0.12, 0.12, 0.55], [-0.04, 0.10, 0.45]], "fun": [0.02, -0.10, -0.18], "mast": [0.12]},
	"jpl": {"bow": 0.78, "bp": 1.8, "st": 0.84, "pal": "jp", "sup": [[0.10, 0.09, 0.55], [0.10, 0.05, 0.34], [-0.02, 0.12, 0.50]], "fun": [-0.08, -0.17], "mast": [0.10]},
	"jpxl": {"bow": 0.80, "bp": 1.85, "st": 0.88, "pal": "jp", "sup": [[0.12, 0.08, 0.52], [0.02, 0.06, 0.36], [-0.04, 0.10, 0.50], [-0.16, 0.09, 0.42]], "fun": [-0.10, -0.22], "mast": [0.12, -0.34]},
	"mods": {"bow": 0.74, "bp": 1.8, "st": 0.88, "pal": "mod", "sup": [[0.06, 0.40, 0.55]], "fun": [], "mast": [0.10]},
	"modm": {"bow": 0.76, "bp": 1.8, "st": 0.90, "pal": "mod", "sup": [[0.10, 0.18, 0.55], [-0.12, 0.20, 0.55]], "fun": [], "mast": [0.10, -0.12]},
	"modl": {"bow": 0.78, "bp": 1.9, "st": 0.90, "pal": "mod", "sup": [[0.10, 0.16, 0.55], [-0.10, 0.20, 0.55]], "fun": [], "mast": [0.10, -0.10]},
	"modxl": {"bow": 0.80, "bp": 1.9, "st": 0.92, "pal": "mod", "sup": [[0.12, 0.14, 0.55], [-0.08, 0.16, 0.55], [-0.26, 0.12, 0.48]], "fun": [], "mast": [0.12, -0.16, -0.36]},
	"rum": {"bow": 0.74, "bp": 1.8, "st": 0.88, "pal": "ru", "sup": [[0.12, 0.20, 0.55], [-0.12, 0.16, 0.50]], "fun": [-0.02, -0.16], "mast": [0.12]},
	"rul": {"bow": 0.78, "bp": 1.9, "st": 0.90, "pal": "ru", "sup": [[0.14, 0.16, 0.55], [-0.10, 0.18, 0.55]], "fun": [-0.04, -0.14], "mast": [0.14, -0.10]},
	"sub": {"bow": 0.66, "bp": 1.4, "st": 0.62, "pal": "sub", "sup": [[0.14, 0.16, 0.30]], "fun": [], "mast": [0.10]},
	"cv": {"bow": 0.82, "bp": 1.9, "st": 0.88, "pal": "cv", "sup": [], "fun": [], "mast": []},
	"ars": {"bow": 0.78, "bp": 2.0, "st": 0.92, "pal": "mod", "sup": [[-0.30, 0.16, 0.55], [0.0, 0.08, 0.40]], "fun": [], "mast": [-0.30, 0.0]},
}

static var _ships: Array = []
static var _by_id: Dictionary = {}

static func ships() -> Array:
	if _ships.is_empty():
		_ships = _build()
		for s in _ships:
			_by_id[str(s["id"])] = s
	return _ships

static func by_id(id: String) -> Dictionary:
	ships()
	return _by_id.get(id, {})

static func of_tier(t: int) -> Array:
	var out: Array = []
	for s in ships():
		if int(s["tier"]) == t:
			out.append(s)
	return out

static func tier_progress(score: float, tier: int) -> float:
	if tier >= MAX_TIER:
		return clampf((score - float(TIER_NEED[MAX_TIER - 1])) / 2500.0, 0.0, 1.0)
	var a := float(TIER_NEED[tier - 1])
	var b := float(TIER_NEED[tier])
	return clampf((score - a) / (b - a), 0.0, 1.0)

# ---- helpers used when building the ship table ----
# sec = true marks a group as an automatic secondary: it keeps firing by itself at the
# closest enemy that is in range, inside its arc and visible (even while you steer).
static func g(w: String, pts: Array, b: int = 1, dir: float = 0.0, arc: float = 180.0, sec: bool = false) -> Dictionary:
	var ms: Array = []
	for e in pts:
		var m := {"x": float(e[0]), "y": float(e[1]), "b": b, "dir": deg_to_rad(dir), "arc": deg_to_rad(arc)}
		if e.size() > 2:
			m["dir"] = deg_to_rad(float(e[2]))
		if e.size() > 3:
			m["arc"] = deg_to_rad(float(e[3]))
		ms.append(m)
	var d := {"w": w, "m": ms}
	if sec:
		d["sec"] = true
	return d

static func _s(id: String, nm: String, tier: int, cls: String, style: String, L: float, W: float, hp: float, spd: float, turn: float, det: float, rlm: float, abil: Array, air: String, weapons: Array, ex: Dictionary = {}) -> Dictionary:
	spd *= 0.80
	turn *= 0.92
	if cls == "Submarine":
		hp *= 1.30
		spd *= 1.08
	var d := {"id": id, "name": nm, "tier": tier, "cls": cls, "style": style, "len": L, "wid": W, "hp": hp, "spd": spd, "turn": turn, "det": det, "rlm": rlm, "abil": abil, "air": air, "weapons": weapons, "cam": float(TIER_ZOOM[tier - 1]), "pal": "", "desc": "", "stealth": clampf(0.5 + L / 500.0, 0.6, 1.0)}
	for k in ex.keys():
		d[k] = ex[k]
	# reload speed depends on tier (bigger ships are slower) and era (modern autoloaders are faster)
	var r := rlm * (0.8 + 0.03 * float(tier)) * 1.05
	if str(d["style"]) in ["mods", "modm", "modl", "modxl", "rum", "rul", "ars", "cv", "sub"]:
		r *= 0.94
	d["rlm"] = r
	if ex.has("cz"):
		d["cam"] = float(TIER_ZOOM[tier - 1]) * float(ex["cz"])
	return d

static func _build() -> Array:
	var a: Array = []
	# ================= TIER I =================
	a.append(_s("pt_boat", "Elco PT Boat", 1, "Motor Torpedo Boat", "pt", 30.0, 7.5, 110.0, 235.0, 3.4, 520.0, 1.0, ["boost"], "", [
		g("mg", [[0.14, 0.0], [-0.30, 0.0]], 2), g("torp", [[-0.04, 0.34, 90, 60], [-0.04, -0.34, -90, 60]], 1)],
		{"desc": "Fast and fragile. Hit and run with torpedoes."}))
	a.append(_s("fac", "Fast Attack Craft", 1, "Torpedo Boat", "pt", 34.0, 7.5, 125.0, 220.0, 3.1, 560.0, 1.0, ["boost"], "", [
		g("ac40", [[0.28, 0.0]], 1), g("mg", [[-0.30, 0.0]], 2), g("torp", [[-0.04, 0.32, 90, 60], [-0.04, -0.32, -90, 60]], 1)],
		{"desc": "Autocannon, machine guns and torpedoes."}))
	a.append(_s("gunboat", "Patrol Gunboat", 1, "Gunboat", "boat", 32.0, 8.5, 145.0, 185.0, 2.8, 500.0, 1.0, ["repair"], "", [
		g("ac20", [[0.28, 0.0]], 1), g("mg", [[-0.20, 0.0]], 2), g("mine", [[-0.5, 0.0, 180, 10]], 4)],
		{"desc": "Sturdy hull, drops mines behind it."}))
	a.append(_s("eboat", "Schnellboot", 1, "Fast Torpedo Boat", "boat", 42.0, 7.5, 135.0, 245.0, 3.3, 580.0, 1.0, ["boost"], "", [
		g("ac20", [[0.30, 0.0]], 1), g("torp", [[0.08, 0.32, 90, 60], [0.08, -0.32, -90, 60]], 2)],
		{"desc": "Fastest thing on the water. Quad torpedo salvo."}))
	# ================= TIER II =================
	a.append(_s("trawler", "Armed Trawler", 2, "Escort Trawler", "boat", 46.0, 8.0, 210.0, 140.0, 2.4, 560.0, 1.0, ["repair"], "", [
		g("g88", [[0.30, 0.0]], 1), g("mg", [[-0.25, 0.0]], 2), g("mine", [[-0.5, 0.0, 180, 10]], 6)],
		{"desc": "Slow, cheap, stubborn. Mines and an 88mm gun."}))
	a.append(_s("flower", "Flower-class Corvette", 2, "Escort Corvette", "ww2s", 52.0, 8.5, 230.0, 152.0, 2.3, 620.0, 1.0, ["repair"], "", [
		g("g100", [[0.30, 0.0]], 1), g("ac40", [[-0.30, 0.0]], 2, 0.0, 180.0, true), g("mine", [[-0.5, 0.0, 180, 10]], 6)],
		{"desc": "Cheap WWII escort with a 100mm gun and depth charges."}))
	a.append(_s("corvette_mod", "Modern Corvette", 2, "Corvette", "mods", 60.0, 9.0, 250.0, 168.0, 2.5, 720.0, 1.0, ["chaff"], "", [
		g("g76r", [[0.28, 0.0]], 1), g("torp_l", [[0.0, 0.30, 90, 60], [0.0, -0.30, -90, 60]], 2), g("ciws", [[-0.28, 0.0]], 3)],
		{"desc": "Stealth hull, rapid 76mm gun, homing torpedoes and CIWS."}))
	a.append(_s("gun_monitor", "Heavy Gunboat", 2, "Gunboat", "boat", 54.0, 9.5, 265.0, 150.0, 2.2, 640.0, 1.0, ["repair", "mine_l"], "", [
		g("g100", [[0.30, 0.0]], 1), g("g76", [[-0.28, 0.0]], 1, 0.0, 180.0, true), g("mg", [[0.0, 0.0]], 2)],
		{"desc": "Two dual-purpose guns on a sturdy hull."}))
	# ================= TIER III =================
	a.append(_s("river", "River-class Frigate", 3, "Escort Frigate", "ww2s", 74.0, 10.5, 430.0, 145.0, 2.0, 820.0, 1.0, ["repair", "smoke"], "", [
		g("g100", [[0.30, 0.0], [-0.30, 0.0]], 1), g("ac40", [[-0.12, 0.0], [-0.40, 0.0]], 2, 0.0, 180.0, true), g("rocket", [[0.12, 0.0, 0, 45]], 4), g("mine", [[-0.5, 0.0, 180, 10]], 8)],
		{"desc": "Two 100mm guns, a Hedgehog rocket launcher and depth charges."}))
	a.append(_s("aa_frigate", "Halland-class AA Frigate", 3, "AA Frigate", "ww2m", 78.0, 10.0, 410.0, 152.0, 2.1, 860.0, 1.05, ["radar", "barrage"], "", [
		g("g100", [[0.30, 0.0], [-0.28, 0.0]], 1), g("aa57", [[0.06, 0.18], [0.06, -0.18], [-0.14, 0.20], [-0.14, -0.20]], 2, 0.0, 180.0, true), g("aa37", [[0.18, 0.0], [-0.38, 0.0]], 2, 0.0, 180.0, true)],
		{"desc": "A wall of flak. Aeroplanes hate this one frigate.", "lvl": 3}))
	a.append(_s("type23", "Modern Frigate", 3, "Frigate", "modm", 86.0, 11.0, 480.0, 155.0, 2.1, 1000.0, 1.0, ["chaff", "radar"], "uav", [
		g("g127m", [[0.30, 0.0]], 1), g("torp_l", [[-0.10, 0.30, 90, 60], [-0.10, -0.30, -90, 60]], 3), g("ac40", [[0.05, 0.0]], 2, 0.0, 180.0, true), g("rocket_h", [[0.08, 0.0, 0, 40]], 2), g("ciws", [[-0.18, 0.0]], 6)],
		{"desc": "Recon drone, 127mm gun, homing torpedoes and missile salvos."}))
	a.append(_s("krivak", "Krivak-class Frigate", 3, "Soviet Frigate", "rum", 80.0, 11.0, 450.0, 158.0, 2.0, 940.0, 1.0, ["smoke", "boost"], "", [
		g("g76", [[0.30, 0.0], [-0.30, 0.0]], 2), g("rocket", [[0.16, 0.0, 0, 50]], 6), g("torp", [[-0.04, 0.30, 90, 60], [-0.04, -0.30, -90, 60]], 2)],
		{"desc": "Twin 76mm guns and anti-submarine rocket launchers."}))
	a.append(_s("sub_t3", "Type VII U-boat", 3, "Submarine", "sub", 68.0, 8.0, 400.0, 100.0, 1.9, 540.0, 1.1, ["dive", "boost"], "", [
		g("torp", [[0.30, 0.10, 0, 20], [0.30, -0.10, 0, 20]], 1), g("torp_l", [[-0.32, 0.08, 180, 20]], 1), g("aa37", [[0.0, 0.0]], 1, 0.0, 180.0, true)],
		{"desc": "Wolf-pack legend. Dives to escape detection - torpedoes while they sleep.", "stealth": 0.46, "lvl": 3}))
	# ================= TIER IV =================
	a.append(_s("fletcher", "Fletcher-class Destroyer", 4, "Destroyer", "ww2m", 92.0, 10.8, 700.0, 148.0, 1.9, 950.0, 1.0, ["boost", "smoke"], "", [
		g("g127", [[0.34, 0.0], [0.23, 0.0], [-0.15, 0.0], [-0.27, 0.0], [-0.38, 0.0]], 1), g("ac40", [[0.0, 0.12], [-0.08, -0.12]], 2, 0.0, 180.0, true), g("torp", [[-0.04, 0.1, 90, 70], [-0.04, -0.1, -90, 70]], 5)],
		{"desc": "Five 127mm guns and two quintuple torpedo banks."}))
	a.append(_s("fubuki", "Fubuki-class Destroyer", 4, "Torpedo Destroyer", "jpm", 90.0, 9.8, 660.0, 155.0, 2.0, 950.0, 1.0, ["boost", "smoke"], "", [
		g("g127", [[0.30, 0.0], [-0.22, 0.0], [-0.34, 0.0]], 2), g("torp_h", [[0.06, 0.08, 90, 70], [0.06, -0.08, -90, 70]], 3)],
		{"desc": "Devastating long-range oxygen torpedoes."}))
	a.append(_s("burke", "Arleigh Burke-class Destroyer", 4, "Guided-Missile Destroyer", "modm", 106.0, 13.0, 780.0, 160.0, 2.0, 1250.0, 1.0, ["radar", "repair"], "heli_asw", [
		g("g127m", [[0.30, 0.0]], 1), g("cruise", [[0.17, 0.0, 0, 0], [-0.10, 0.0, 0, 0]], 4), g("ssm_l", [[0.0, 0.3, 50, 15], [0.0, -0.3, -50, 15]], 4), g("torp_l", [[-0.2, 0.3, 90, 60], [-0.2, -0.3, -90, 60]], 3), g("ciws", [[0.06, 0.0], [-0.34, 0.0]], 6)],
		{"desc": "Cruise missiles guided by your cursor. Carries an ASW helicopter.", "cz": 0.95, "lvl": 3}))
	a.append(_s("sovremenny", "Sovremenny-class Destroyer", 4, "Missile Destroyer", "rum", 102.0, 12.0, 740.0, 155.0, 1.9, 1180.0, 1.0, ["smoke", "chaff"], "heli_scout", [
		g("g127", [[0.32, 0.0], [-0.32, 0.0]], 2), g("ssm_h", [[0.16, 0.30, 25, 10], [0.16, -0.30, -25, 10]], 2), g("ssm_s", [[0.05, 0.3, 30, 15], [0.05, -0.3, -30, 15]], 2), g("rocket", [[0.02, 0.0, 0, 40]], 6), g("ciws", [[-0.12, 0.2], [-0.12, -0.2]], 4)],
		{"desc": "Heavy supersonic and light missiles. Carries a scout helicopter.", "lvl": 5}))
	a.append(_s("sub_t4", "Kilo-class Submarine", 4, "Submarine", "sub", 76.0, 9.0, 560.0, 95.0, 1.8, 600.0, 1.1, ["dive", "smoke"], "", [
		g("torp", [[0.32, 0.10, 0, 20], [0.32, -0.10, 0, 20], [0.32, 0.0, 0, 20]], 1), g("ssm_s", [[-0.30, 0.0, 180, 30]], 2), g("aa37", [[0.0, 0.0]], 1, 0.0, 180.0, true)],
		{"desc": "The 'Black Hole': near-silent until her missiles hit you.", "stealth": 0.45, "lvl": 5}))
	a.append(_s("escort_carrier", "Casablanca-class Escort Carrier", 4, "Escort Carrier", "cv", 110.0, 16.0, 620.0, 132.0, 1.5, 950.0, 1.0, ["radar", "repair"], "torp_bomber", [
		g("g76", [[0.42, 0.26], [-0.36, 0.30]], 1, 0.0, 180.0, true), g("aa37", [[0.30, -0.30], [0.05, -0.36], [-0.20, 0.36], [-0.42, -0.28]], 2, 0.0, 180.0, true)],
		{"desc": "Small carrier with a full torpedo squadron. Feeble guns - fly (V).", "squad": 3, "lvl": 5}))
	# ================= TIER V =================
	a.append(_s("abdiel", "Abdiel-class Minelayer", 5, "Minelayer", "ww2s", 118.0, 12.0, 1350.0, 145.0, 1.8, 1000.0, 1.0, ["mine_l", "smoke"], "", [
		g("g100", [[0.30, 0.0], [-0.04, 0.0]], 1), g("ac40", [[0.10, 0.20], [0.10, -0.20], [-0.30, 0.0]], 2, 0.0, 180.0, true), g("mine", [[-0.5, 0.0, 180, 10]], 10)],
		{"desc": "Turns half the map into a no-go zone. Nobody respects minelayers. Yet.", "lvl": 4}))
	a.append(_s("cleveland", "Cleveland-class Light Cruiser", 5, "Light Cruiser", "ww2l", 126.0, 13.5, 1600.0, 140.0, 1.6, 1100.0, 1.0, ["repair", "smoke"], "floatplane", [
		g("g152", [[0.34, 0.0], [0.23, 0.0], [-0.25, 0.0], [-0.36, 0.0]], 3), g("g127", [[0.10, 0.2], [0.10, -0.2], [-0.12, 0.2], [-0.12, -0.2]], 2, 0.0, 180.0, true), g("aa37", [[0.0, 0.24], [-0.04, -0.24], [0.16, 0.26], [-0.16, -0.26]], 2, 0.0, 180.0, true)],
		{"desc": "Twelve 152mm guns in four triple turrets."}))
	a.append(_s("atlanta", "Atlanta-class AA Cruiser", 5, "AA Cruiser", "ww2l", 125.0, 12.8, 1500.0, 150.0, 1.7, 1050.0, 1.05, ["radar", "barrage"], "heli_scout", [
		g("g127", [[0.32, 0.0], [0.22, 0.0], [-0.22, 0.0], [-0.32, 0.0]], 2, 0.0, 180.0, true), g("aa57", [[0.05, 0.2], [0.05, -0.2], [-0.10, 0.2], [-0.10, -0.2]], 2, 0.0, 180.0, true), g("aa37", [[0.14, 0.26], [0.14, -0.26], [-0.02, 0.28], [-0.02, -0.28], [-0.20, 0.24], [-0.20, -0.24]], 2, 0.0, 180.0, true)],
		{"desc": "Sixteen rapid 5-inch barrels and enough flak to blot out the sky.", "lvl": 6}))
	a.append(_s("agano", "Agano-class Light Cruiser", 5, "Light Cruiser", "jpl", 122.0, 12.5, 1450.0, 152.0, 1.7, 1050.0, 1.0, ["boost", "smoke"], "floatplane", [
		g("g152", [[0.34, 0.0], [0.22, 0.0], [-0.32, 0.0]], 2), g("g100", [[0.04, 0.2], [-0.10, -0.2]], 2), g("torp_h", [[-0.20, 0.12, 90, 70], [-0.20, -0.12, -90, 70]], 4)],
		{"desc": "Fast cruiser with long-range torpedoes."}))
	a.append(_s("ticonderoga", "Ticonderoga-class Cruiser", 5, "Guided-Missile Cruiser", "modl", 136.0, 15.0, 1750.0, 152.0, 1.7, 1400.0, 1.0, ["radar", "repair"], "heli_asw", [
		g("g127m", [[0.34, 0.0], [-0.32, 0.0]], 1), g("cruise", [[0.20, 0.0, 0, 0], [-0.20, 0.0, 0, 0]], 8), g("ssm_l", [[0.0, 0.3, 50, 15], [0.0, -0.3, -50, 15]], 4), g("torp_l", [[-0.08, 0.3, 90, 60], [-0.08, -0.3, -90, 60]], 3), g("ciws", [[0.08, 0.0], [-0.40, 0.0]], 6)],
		{"desc": "Sixteen cruise missiles and an ASW helicopter.", "cz": 0.95, "lvl": 6}))
	# ================= TIER VI =================
	a.append(_s("baltimore", "Baltimore-class Heavy Cruiser", 6, "Heavy Cruiser", "ww2l", 152.0, 16.0, 2300.0, 138.0, 1.4, 1200.0, 1.0, ["repair", "smoke"], "floatplane", [
		g("g203", [[0.34, 0.0], [0.23, 0.0], [-0.30, 0.0]], 3), g("g127", [[0.08, 0.2], [0.08, -0.2], [-0.10, 0.2], [-0.10, -0.2]], 2, 0.0, 180.0, true), g("aa37", [[0.0, 0.25], [-0.2, -0.25], [0.14, 0.27]], 2, 0.0, 180.0, true)],
		{"desc": "Nine 203mm guns. A balanced cruiser."}))
	a.append(_s("takao", "Takao-class Heavy Cruiser", 6, "Heavy Cruiser", "jpl", 154.0, 15.5, 2250.0, 146.0, 1.5, 1150.0, 1.0, ["boost", "smoke"], "floatplane", [
		g("g203", [[0.35, 0.0], [0.26, 0.0], [0.17, 0.0], [-0.30, 0.0], [-0.40, 0.0]], 2), g("g127", [[0.0, 0.2], [0.0, -0.2]], 2), g("torp_h", [[-0.12, 0.12, 90, 70], [-0.12, -0.12, -90, 70]], 4)],
		{"desc": "Ten 203mm guns and quad long-lance torpedoes."}))
	a.append(_s("slava", "Slava-class Missile Cruiser", 6, "Missile Cruiser", "rul", 170.0, 19.0, 2400.0, 142.0, 1.4, 1500.0, 1.0, ["radar", "chaff"], "heli_attack", [
		g("ssm_h", [[0.26, 0.30, 35, 15], [0.26, -0.30, -35, 15], [0.12, 0.30, 35, 15], [0.12, -0.30, -35, 15]], 2), g("g127", [[0.38, 0.0]], 2), g("rocket_h", [[0.30, 0.0, 0, 45]], 4), g("torp_w", [[-0.05, 0.28, 90, 60], [-0.05, -0.28, -90, 60]], 2), g("ciws", [[-0.10, 0.22], [-0.10, -0.22], [-0.30, 0.0]], 6)],
		{"desc": "Eight heavy missiles. Carries an attack helicopter.", "cz": 0.92, "lvl": 9}))
	a.append(_s("light_carrier", "Independence-class Light Carrier", 6, "Light Carrier", "cv", 165.0, 20.0, 2000.0, 145.0, 1.4, 1300.0, 1.0, ["radar", "repair"], "dive_bomber", [
		g("aa37", [[0.35, 0.26], [0.20, -0.32], [-0.10, 0.34], [-0.30, -0.30]], 2, 0.0, 180.0, true), g("g127", [[0.44, 0.0]], 1, 0.0, 180.0, true), g("ciws", [[-0.22, 0.30]], 6)],
		{"desc": "Fast carrier built on a cruiser hull. Dive bombers included.", "squad": 3, "lvl": 8}))
	a.append(_s("sub_t6", "Foxtrot-class Submarine", 6, "Submarine", "sub", 92.0, 9.5, 1100.0, 110.0, 1.7, 650.0, 1.0, ["dive", "radar"], "", [
		g("torp", [[0.32, 0.10, 0, 20], [0.32, -0.10, 0, 20]], 2), g("cruise", [[-0.28, 0.0, 180, 40]], 4), g("aa37", [[0.0, 0.0]], 1, 0.0, 180.0, true)],
		{"desc": "Sneaks up, launches cruise missiles, slips away underwater.", "stealth": 0.47, "lvl": 10}))
	# ================= TIER VII =================
	a.append(_s("scharnhorst", "Scharnhorst-class Battlecruiser", 7, "Battlecruiser", "ww2l", 182.0, 20.0, 3300.0, 155.0, 1.3, 1300.0, 1.0, ["repair", "barrage"], "floatplane", [
		g("g305", [[0.34, 0.0], [0.22, 0.0], [-0.30, 0.0]], 3), g("g152", [[0.04, 0.22], [0.04, -0.22], [-0.14, 0.22], [-0.14, -0.22]], 2, 0.0, 180.0, true), g("aa37", [[0.14, 0.26], [-0.04, -0.26], [0.24, 0.28]], 2, 0.0, 180.0, true)],
		{"desc": "Nine 305mm guns and fast for her size."}))
	a.append(_s("kongo", "Kongo-class Battlecruiser", 7, "Battlecruiser", "jpl", 180.0, 20.0, 3200.0, 160.0, 1.35, 1250.0, 1.0, ["boost", "barrage"], "floatplane", [
		g("g356", [[0.35, 0.0], [0.24, 0.0], [-0.24, 0.0], [-0.35, 0.0]], 2), g("g152", [[0.08, 0.22], [0.0, 0.22], [-0.08, 0.22], [0.08, -0.22], [0.0, -0.22], [-0.08, -0.22]], 1, 0.0, 180.0, true), g("aa37", [[0.14, 0.0], [-0.14, 0.0]], 2, 0.0, 180.0, true)],
		{"desc": "Eight 356mm guns in four twin turrets."}))
	a.append(_s("alaska", "Alaska-class Large Cruiser", 7, "Large Cruiser", "ww2xl", 195.0, 21.0, 3600.0, 152.0, 1.25, 1350.0, 1.0, ["repair", "barrage"], "heli_scout", [
		g("g305", [[0.34, 0.0], [0.22, 0.0], [-0.28, 0.0]], 3), g("g127", [[0.06, 0.22], [0.06, -0.22], [-0.10, 0.22], [-0.10, -0.22], [-0.22, 0.20], [-0.22, -0.20]], 2, 0.0, 180.0, true), g("aa57", [[0.16, 0.26], [0.16, -0.26], [-0.02, 0.28]], 2, 0.0, 180.0, true)],
		{"desc": "A cruiser that ate a battleship. Twelve rapid 12-inch rifles.", "lvl": 12}))
	a.append(_s("kirov", "Kirov-class Battlecruiser", 7, "Nuclear Missile Cruiser", "rul", 198.0, 24.0, 3800.0, 148.0, 1.2, 1600.0, 1.0, ["radar", "repair"], "heli_heavy", [
		g("ssm_h", [[0.30, 0.14, 20, 15], [0.30, -0.14, -20, 15]], 8), g("ssm_l", [[0.12, 0.3, 40, 15], [0.12, -0.3, -40, 15]], 4), g("g127", [[0.42, 0.0]], 2), g("rocket", [[0.24, 0.0, 0, 40]], 8), g("ciws", [[0.05, 0.28], [0.05, -0.28], [-0.20, 0.28], [-0.20, -0.28]], 6)],
		{"desc": "Sixteen heavy missiles, rocket launchers and CIWS. Nuclear-powered.", "cz": 0.9, "lvl": 12}))
	a.append(_s("sub_t7", "Oscar II Cruise Submarine", 7, "Submarine", "sub", 155.0, 18.0, 2400.0, 112.0, 1.3, 720.0, 1.0, ["dive", "chaff"], "", [
		g("ssm_h", [[0.24, 0.22, 15, 25], [0.24, -0.22, -15, 25]], 6), g("torp", [[0.32, 0.12, 0, 20], [0.32, -0.12, 0, 20], [-0.30, 0.10, 180, 20]], 2), g("aa37", [[0.16, 0.0]], 1, 0.0, 180.0, true)],
		{"desc": "Twelve Granit missiles in the 'hump'. Deep, quiet, deadly.", "stealth": 0.48, "lvl": 14}))
	# ================= TIER VIII =================
	a.append(_s("des_moines", "Des Moines-class Cruiser", 8, "Heavy Cruiser", "ww2l", 180.0, 20.5, 4200.0, 150.0, 1.3, 1400.0, 1.05, ["radar", "barrage"], "heli_asw", [
		g("g203", [[0.34, 0.0], [0.24, 0.0], [-0.28, 0.0]], 3), g("aa37", [[0.06, 0.24], [0.06, -0.24], [-0.04, 0.26], [-0.04, -0.26], [-0.16, 0.22], [-0.16, -0.22]], 2, 0.0, 180.0, true), g("aa57", [[0.24, 0.0]], 2, 0.0, 180.0, true)],
		{"desc": "The fastest-loading heavy guns ever bolted to a hull.", "lvl": 12}))
	a.append(_s("iowa", "Iowa-class Battleship", 8, "Battleship", "ww2l", 210.0, 24.0, 5200.0, 148.0, 1.1, 1400.0, 1.0, ["repair", "barrage"], "floatplane", [
		g("g406", [[0.34, 0.0], [0.22, 0.0], [-0.28, 0.0]], 3), g("g127", [[0.10, 0.22], [0.10, -0.22], [-0.02, 0.22], [-0.02, -0.22], [-0.14, 0.22], [-0.14, -0.22]], 2, 0.0, 180.0, true), g("aa57", [[0.0, 0.0], [-0.20, 0.0]], 2, 0.0, 180.0, true), g("aa37", [[0.20, 0.28], [0.20, -0.28], [-0.30, 0.26]], 2, 0.0, 180.0, true)],
		{"desc": "Nine 406mm guns. Fast for a battleship."}))
	a.append(_s("bismarck", "Bismarck-class Battleship", 8, "Battleship", "ww2xl", 202.0, 24.0, 5000.0, 154.0, 1.15, 1350.0, 1.0, ["smoke", "barrage"], "floatplane", [
		g("g381", [[0.33, 0.0], [0.22, 0.0], [-0.24, 0.0], [-0.34, 0.0]], 2), g("g152", [[0.06, 0.22], [0.06, -0.22], [-0.04, 0.22], [-0.04, -0.22], [-0.14, 0.22], [-0.14, -0.22]], 2, 0.0, 180.0, true), g("aa37", [[0.14, 0.0], [-0.18, 0.0]], 2, 0.0, 180.0, true)],
		{"desc": "Eight 381mm guns. Faster and nimbler than her rivals."}))
	a.append(_s("carrier", "Essex-class Carrier", 8, "Aircraft Carrier", "cv", 250.0, 30.0, 4200.0, 142.0, 1.05, 1450.0, 1.0, ["radar", "repair"], "dive_bomber", [
		g("g127", [[0.40, 0.3], [0.30, -0.36], [-0.30, 0.36], [-0.40, -0.3]], 1, 0.0, 180.0, true), g("aa37", [[0.2, 0.38], [0.0, -0.38], [-0.2, 0.38]], 2, 0.0, 180.0, true), g("ciws", [[0.34, -0.3], [-0.46, 0.0]], 6)],
		{"desc": "A full dive-bomber squadron plus AI recon planes. Fly them (V).", "squad": 3, "air2": "uav", "n2": 3, "lvl": 12}))
	a.append(_s("arsenal", "Arsenal Ship", 8, "Missile Battleship", "ars", 202.0, 24.0, 4600.0, 152.0, 1.2, 1800.0, 1.0, ["radar", "chaff"], "heli_attack", [
		g("cruise", [[0.30, 0.0, 0, 0], [0.12, 0.0, 0, 0], [-0.10, 0.0, 0, 0], [-0.40, 0.0, 0, 0]], 4), g("ssm_h", [[0.20, 0.3, 30, 15], [0.20, -0.3, -30, 15]], 6), g("ssm_s", [[0.0, 0.3, 30, 15], [0.0, -0.3, -30, 15]], 4), g("g155", [[0.42, 0.0], [-0.30, 0.0]], 2, 0.0, 180.0, true), g("ciws", [[0.05, 0.28], [-0.2, -0.28]], 6)],
		{"desc": "Sixteen cursor-guided cruise missiles and heavy missiles.", "cz": 0.85, "lvl": 14}))
	# ================= TIER IX =================
	a.append(_s("sub_t9", "Seawolf-class Submarine", 9, "Submarine", "sub", 110.0, 12.0, 3300.0, 132.0, 1.2, 820.0, 1.0, ["dive", "radar"], "", [
		g("torp_w", [[0.32, 0.14, 0, 25], [0.32, -0.14, 0, 25], [0.20, 0.20, 90, 40], [0.20, -0.20, -90, 40]], 2), g("ssm_l", [[-0.30, 0.0, 180, 45]], 4), g("aa37", [[0.0, 0.0]], 1, 0.0, 180.0, true)],
		{"desc": "Quietest hunter in the ocean. Wire-guided torpedoes and Tomahawks.", "stealth": 0.44, "lvl": 12}))
	a.append(_s("yamato", "Yamato-class Battleship", 9, "Super Battleship", "jpxl", 310.0, 40.0, 12500.0, 120.0, 0.82, 1650.0, 1.0, ["repair", "barrage"], "floatplane", [
		g("g460", [[0.34, 0.0], [0.22, 0.0], [-0.28, 0.0]], 3), g("g155", [[0.06, 0.30], [0.06, -0.30], [-0.20, 0.31]], 2, 0.0, 180.0, true), g("g127", [[0.14, 0.0], [-0.10, 0.0], [-0.30, 0.0]], 2, 0.0, 180.0, true), g("aa57", [[0.10, 0.34], [-0.04, -0.34], [0.28, 0.0]], 2, 0.0, 180.0, true), g("aa37", [[0.0, 0.32], [-0.26, 0.28], [-0.26, -0.28], [0.22, -0.32]], 2, 0.0, 180.0, true)],
		{"desc": "The biggest battleship ever floated. Nine 460mm guns.", "lvl": 10}))
	a.append(_s("montana", "Montana-class Battleship", 9, "Super Battleship", "ww2xl", 292.0, 37.0, 12000.0, 126.0, 0.85, 1550.0, 1.0, ["repair", "barrage"], "floatplane", [
		g("g406", [[0.34, 0.0], [0.24, 0.0], [0.14, 0.0], [-0.26, 0.0]], 3), g("g127", [[0.02, 0.22], [0.02, -0.22], [-0.08, 0.22], [-0.08, -0.22], [-0.16, 0.22], [-0.16, -0.22], [-0.30, 0.20], [-0.30, -0.20], [0.24, 0.24], [0.24, -0.24]], 2, 0.0, 180.0, true), g("aa57", [[0.10, 0.30], [-0.02, -0.30]], 2, 0.0, 180.0, true)],
		{"desc": "Twelve 406mm guns. The battleship the US Navy wanted but never built.", "lvl": 14}))
	a.append(_s("h44", "H-44-class Super Battleship", 9, "Super Battleship", "ww2xl", 320.0, 40.0, 13500.0, 124.0, 0.8, 1580.0, 1.0, ["repair", "smoke"], "floatplane", [
		g("g460", [[0.34, 0.0], [0.20, 0.0], [-0.30, 0.0], [-0.44, 0.0]], 2), g("g127", [[0.06, 0.22], [0.06, -0.22], [-0.12, 0.22], [-0.12, -0.22], [-0.36, 0.20], [-0.36, -0.20]], 2, 0.0, 180.0, true), g("aa57", [[0.14, 0.28], [-0.02, -0.28]], 2, 0.0, 180.0, true)],
		{"desc": "Half a kilometre of German steel that only existed on paper.", "lvl": 16}))
	# ================= TIER X =================
	a.append(_s("t10_battlecv", "Shinano-class Battle Carrier", 10, "Battle Carrier", "cv", 300.0, 38.0, 15500.0, 126.0, 0.85, 1700.0, 1.0, ["radar", "repair", "barrage"], "jet_strike", [
		g("g406", [[0.36, 0.0], [0.22, 0.0], [-0.30, 0.0]], 3), g("aa57", [[0.10, 0.32], [0.10, -0.32], [-0.10, 0.34], [-0.10, -0.34]], 2, 0.0, 180.0, true), g("g127", [[0.02, 0.28], [0.02, -0.28], [-0.20, 0.30], [-0.20, -0.30]], 2, 0.0, 180.0, true), g("ciws", [[-0.40, 0.0]], 6)],
		{"desc": "Battleship guns AND a jet squadron. It shouldn't exist. It does.", "squad": 3, "lvl": 18}))
	a.append(_s("t10_arsenal", "Arsenal Battleship", 10, "Missile Battleship", "ars", 310.0, 36.0, 15000.0, 130.0, 0.82, 2000.0, 1.0, ["radar", "chaff", "barrage"], "heli_heavy", [
		g("cruise", [[0.34, 0.0, 0, 0], [0.16, 0.0, 0, 0], [-0.06, 0.0, 0, 0], [-0.24, 0.0, 0, 0], [-0.42, 0.0, 0, 0]], 5), g("ssm_h", [[0.02, 0.30, 30, 15], [0.02, -0.30, -30, 15], [-0.16, 0.30, 30, 15], [-0.16, -0.30, -30, 15]], 6), g("ssm_s", [[0.24, 0.30, 30, 15], [0.24, -0.30, -30, 15]], 4), g("g155", [[0.44, 0.0], [-0.50, 0.0]], 2, 0.0, 180.0, true), g("ciws", [[0.10, 0.30], [0.10, -0.30], [-0.34, 0.26], [-0.34, -0.26]], 6)],
		{"desc": "A floating VLS farm. Twenty cruise missiles held ready.", "lvl": 16}))
	a.append(_s("t10_bb", "Super Yamato (A-150)", 10, "Super Battleship", "jpxl", 340.0, 46.0, 18000.0, 114.0, 0.72, 1750.0, 1.0, ["repair", "barrage", "smoke"], "floatplane", [
		g("g510", [[0.34, 0.0], [0.20, 0.0], [-0.30, 0.0]], 2), g("g155", [[0.04, 0.32], [0.04, -0.32], [-0.18, 0.32], [-0.18, -0.32]], 2, 0.0, 180.0, true), g("g127", [[0.10, 0.0], [-0.32, 0.0], [-0.44, 0.0]], 2, 0.0, 180.0, true), g("aa57", [[0.14, 0.34], [-0.08, -0.34], [0.28, 0.0]], 2, 0.0, 180.0, true), g("aa37", [[0.0, 0.34], [-0.24, 0.30], [-0.24, -0.30], [0.26, -0.32], [-0.44, 0.0]], 2, 0.0, 180.0, true)],
		{"desc": "Six 510mm rifles. Each shot is a small earthquake.", "lvl": 20}))
	a.append(_s("t10_cv", "Supercarrier CVN-10 Leviathan", 10, "Aircraft Carrier", "cv", 380.0, 48.0, 16000.0, 128.0, 0.75, 1900.0, 1.0, ["radar", "repair", "barrage"], "jet_strike", [
		g("g127", [[0.42, 0.34], [0.32, -0.40], [-0.32, 0.40], [-0.42, -0.34]], 1, 0.0, 180.0, true), g("aa57", [[0.20, 0.42], [0.0, -0.44], [-0.18, 0.40]], 2, 0.0, 180.0, true), g("aa37", [[0.30, 0.0], [-0.10, 0.0]], 2, 0.0, 180.0, true), g("ciws", [[0.36, -0.30], [-0.44, 0.0], [-0.28, 0.34]], 6)],
		{"desc": "Nuclear-powered floating airbase: jets plus an AI heavy strike squadron.", "squad": 3, "air2": "jet_heavy", "n2": 3, "lvl": 20}))
	return a

# firepower estimate (sustained damage per second if everything hits) - used by the ship cards
static func dps(def: Dictionary) -> float:
	var tot := 0.0
	var rlm := float(def["rlm"])
	for gr in def["weapons"]:
		var wd: Dictionary = WEAPONS[gr["w"]]
		var barrels := 0
		for m in gr["m"]:
			barrels += int(m["b"])
		var per := float(wd["dmg"]) * float(wd.get("sal", 1))
		var by_reload := per * float(barrels) / maxf(float(wd["rl"]) * rlm, 0.05)
		var by_gap := per / maxf(float(wd["gap"]) * rlm, 0.02)
		tot += minf(by_reload, by_gap)
	return tot

const MSCALE := 0.52

static func mount_dims(wd: Dictionary, b: int) -> Vector2:
	# returns Vector2(muzzle forward offset, barrel spacing)
	match str(wd["vis"]):
		"gun":
			var bw := float(wd["bw"]) * MSCALE
			var bl := float(wd["bl"]) * MSCALE
			var tl := bl * 0.6 + 2.5
			return Vector2(tl * 0.3 + bl, bw * 1.4)
		"ciws":
			return Vector2(6.0, 1.0)
		"tubes":
			return Vector2(float(wd.get("tl", 10.0)) * 0.5 * 0.65 + 2.0, 2.6)
		"can":
			return Vector2(6.0, 2.4)
		"vls":
			return Vector2(0.0, 0.0)
		"rack":
			return Vector2(6.0, 2.0)
		"mine":
			return Vector2(2.0, 3.0)
	return Vector2(6.0, 2.0)

# Hull outline, stern at -L/2 and bow at +L/2.  bow = where the taper starts (0..1),
# bp = bow fullness, st = transom width (0..1).
static func hull_pts(L: float, W: float, bow: float, bp: float, st: float) -> PackedVector2Array:
	var n := 26
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in range(n + 1):
		var u := float(i) / float(n)
		var f := 1.0
		if u < 0.12:
			f = st + (1.0 - st) * sin(u / 0.12 * PI * 0.5)
		elif u > bow:
			var t := (u - bow) / (1.0 - bow)
			f = pow(maxf(1.0 - pow(t, bp), 0.0), 0.55)
		var x := -L * 0.5 + u * L
		var hw := W * 0.5 * f
		top.append(Vector2(x, -hw))
		if i < n:
			bot.append(Vector2(x, hw))
	var pts := PackedVector2Array()
	for p in top:
		pts.append(p)
	var j := bot.size() - 1
	while j >= 0:
		pts.append(bot[j])
		j -= 1
	return pts

static func half_width(x: float, L: float, W: float, bow: float, bp: float, st: float) -> float:
	var u := clampf((x + L * 0.5) / L, 0.0, 1.0)
	var f := 1.0
	if u < 0.12:
		f = st + (1.0 - st) * sin(u / 0.12 * PI * 0.5)
	elif u > bow:
		var t := (u - bow) / (1.0 - bow)
		f = pow(maxf(1.0 - pow(t, bp), 0.0), 0.55)
	return W * 0.5 * f

# ---- nickname filter: block 18+ and rude nicknames (with l33t-speak folding) ----
const _BAD_NICKS := [
	"fuck", "shit", "bitch", "asshole", "cunt", "dick", "cock", "penis", "vagina", "boob",
	"titties", "tits", "anal", "cum", "jizz", "porn", "xxx", "nigger", "nigga", "faggot",
	"fag", "rape", "rapist", "whore", "slut", "nazi", "hitler", "pedophile", "pornhub",
]

static func nick_ok(n: String) -> bool:
	var s := n.to_lower()
	var t := ""
	for ch in s:
		var cc := ch
		match ch:
			"0": cc = "o"
			"1", "!", "|": cc = "i"
			"3": cc = "e"
			"4", "@": cc = "a"
			"5", "$": cc = "s"
			"7": cc = "t"
			"8": cc = "b"
			"9": cc = "g"
		if cc >= "a" and cc <= "z":
			t += cc
	for w in _BAD_NICKS:
		if t.contains(w):
			return false
	return true
