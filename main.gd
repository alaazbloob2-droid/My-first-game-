extends Node2D
# Naval IO - top-down naval combat (Godot 4.x, Compatibility renderer).
#
# FILES
#   data.gd      ships, weapons, aircraft, abilities, tiers (edit this to add content)
#   settings.gd  all options + key bindings, saved to user://
#   audio.gd     procedural sound effects (no asset files needed)
#   ui.gd        HUD, menus, promotion / respawn pop-ups, settings window
#   main.gd      this file: world, ships, weapons, projectiles, AI, aircraft
#
# PERFORMANCE DESIGN (weak GPUs / Intel HD 4000):
#  - Compatibility (OpenGL) renderer. Water is ONE shader quad.
#  - Islands and ships are retained Polygon2D nodes built once; the engine culls them.
#  - Only projectiles / effects are drawn dynamically and only when on screen.
#  - HUD is Control nodes updated at 10 Hz. Bot AI thinks ~5x per second.
#  - Quality levels (F2) and an auto mode that steps down when FPS stays low.

const UIScript := preload("res://ui.gd")
const AudioScript := preload("res://audio.gd")
const SettingsScript := preload("res://settings.gd")
const D := preload("res://data.gd")
const WATER_SHADER := preload("res://water.gdshader")
const WATER_FAST_SHADER := preload("res://water_fast.gdshader")

const WORLD := 9500.0
const GRID := 900.0
const CRATE_COUNT := 420
const MAX_DT := 0.05
const TRAIL_POINTS := 14
const MAX_SHOTS := 420

# projectile kinds (must match D.KIND)
const K_BULLET := 0
const K_SHELL := 1
const K_TORP := 2
const K_MISSILE := 3
const K_ROCKET := 4
const K_MINE := 5
const K_BOMB := 6

enum State { MENU, PLAYING, DEAD }

const CRATE_COLORS := [Color(1.0, 0.85, 0.2), Color(0.3, 1.0, 0.4), Color(1.0, 0.5, 0.2)]
const QUALITY_NAMES := ["Low", "Medium", "High"]

# ---------------- Data classes ----------------

class MountRT extends RefCounted:
	var x := 0.0
	var y := 0.0
	var dir := 0.0
	var arc := PI
	var b := 1
	var rot := 0.0
	var muz := 6.0
	var bsp := 2.0
	var bstart := 0
	var bptr := 0
	var recoil := 0.0
	var node: Node2D
	var barrels: Node2D

class WRT extends RefCounted:
	var id := ""
	var d: Dictionary = {}
	var sec := false
	var mounts: Array[MountRT] = []
	var cd := PackedFloat32Array()
	var bm := PackedInt32Array()
	var bi := PackedInt32Array()
	var ptr := 0
	var gap_t := 0.0
	var aimpt := Vector2.ZERO
	var kind := 0
	var total := 0

class Air extends RefCounted:
	var d: Dictionary = {}
	var id := ""
	var wing := false
	var leader = null
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var angle := 0.0
	var spd := 0.0
	var hp := 30.0
	var alive := false
	var cd := 0.0
	var ctrl_thr := 0.6
	var warn := false
	var aimpt := Vector2.ZERO
	var owner = null
	var mode := 0
	var mode_t := 0.0
	var target = null
	var mark_cd := 0.0
	var orbit := 1.0
	var weapons: Array[WRT] = []
	var wsel := 0
	var node: Node2D
	var shadow: Node2D
	var rotor: Node2D

class Ship extends RefCounted:
	var def: Dictionary = {}
	var tier := 1
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var angle := 0.0
	var speed := 0.0
	var throttle := 0.0
	var score := 0.0
	var hp := 60.0
	var max_hp := 60.0
	var hl := 15.0
	var hw := 4.0
	var alive := false
	var is_player := false
	var nick := ""
	var color := Color.WHITE
	var kills := 0
	var flash := 0.0
	var desired := 0.0
	var think_t := 0.0
	var wander_until := 0.0
	var respawn := 0.0
	var cursor := Vector2.ZERO
	var weapons: Array[WRT] = []
	var wsel := 0
	var ab_cd := PackedFloat32Array([0.0, 0.0, 0.0])
	var boost_t := 0.0
	var repair_t := 0.0
	var smoke_t := 0.0
	var radar_t := 0.0
	var barrage_t := 0.0
	var reveal_t := 0.0
	var mark_t := 0.0
	var invuln := 0.0
	var sink_t := 0.0
	var sink_max := 2.0
	var sink_list := 0.0
	var dmg_d := 0.0
	var smoke_emit := 0.0
	var fire_emit := 0.0
	var has_pd := false
	var pd_t := 0.0
	var target: Ship = null
	var fire_set: Array[int] = []
	var air_tgt := false
	var aim_err := 0.0
	var side := 1.0
	var seen := true
	var air: Air = null
	# scene nodes
	var node: Node2D
	var body: Node2D
	var shadow: Polygon2D
	var flash_poly: Polygon2D
	var bow_poly: Polygon2D
	var tag: Node2D
	var name_label: Label
	var hp_fill: ColorRect
	var trail: Line2D
	var details: Array[Node2D] = []
	var fine: Array[Node2D] = []
	var built_id := ""
	var shown_hp := -1.0
	var was_on := false
	var fire_t := 0.0
	var flood_t := 0.0
	var fire_pt := Vector2.ZERO
	var last_attacker = null
	var stealth := 0.8
	var last_seen_t := 99.0
	var last_seen_pos := Vector2.ZERO
	var fire_delay := 0.0
	var wsel_t := 0.0
	var flee := false
	var fx_t := 0.0
	var fire_ok := false
	var lod_n := 0
	var lod_dt := 0.0
	var aa_mode := false
	var air_threat = null
	var border_t := 0.0
	var dive_t := 0.0
	var mine_t := 0.0
	var sec_t := 0.0
	var sec_tgt = null
	var wing: Array = []
	var air2 = null
	var wing2: Array = []
	var foam: Node2D
	var parked: Node2D
	var spinners: Array[Node2D] = []

class Shot extends RefCounted:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var ang := 0.0
	var spd := 0.0
	var life := 1.0
	var t := 0.0
	var dmg := 0.0
	var spl := 0.0
	var src: Ship = null
	var kind := 0
	var mode := 0
	var turn := 0.0
	var seek := 0.0
	var scan := 0.0
	var tgt := Vector2.ZERO
	var aa := false
	var dead := false
	var sz := 2.0
	var col := Color(1, 0.9, 0.5)
	var trail := PackedVector2Array()
	var trail_t := 0.0
	var lock = null
	var hp := 0.0
	var ar := 0.0
	var mt := 0

class Crate extends RefCounted:
	var pos := Vector2.ZERO
	var kind := 0
	var temp := false
	var life := 0.0
	var phase := 0.0
	var cell := Vector2i.ZERO

class Fx extends RefCounted:
	var kind := 0   # 0 explosion 1 splash 2 muzzle flash 3 ring 4 smoke puff 5 tracer 6 text
	var pos := Vector2.ZERO
	var pos2 := Vector2.ZERO
	var age := 0.0
	var dur := 0.5
	var size := 30.0
	var col := Color.WHITE
	var sd := 0.0
	var ang := 0.0
	var txt := ""

# ---------------- State ----------------

var S: SettingsScript     # settings.gd instance
var audio: Node
var ships: Array[Ship] = []
var shots: Array[Shot] = []
var crates: Array[Crate] = []
var fxs: Array[Fx] = []
var island_pos := PackedVector2Array()
var island_r := PackedFloat32Array()
var island_grid: Dictionary = {}
var reef_pos := PackedVector2Array()
var reef_r := PackedFloat32Array()
var air_alive: Array = []
var island_sd: Array = []
var reef_sd: Array = []
var wreck_pos := PackedVector2Array()
var wreck_rot := PackedFloat32Array()
var wreck_sd: Array = []
var buoy_pos := PackedVector2Array()
var buoy_red: Array = []
var tex: Dictionary = {}          # baked textures (key -> ImageTexture)
var tex_sc: Dictionary = {}       # bake scale of each texture
var bake_jobs: Array = []
var bake_keys: Dictionary = {}
var premult: CanvasItemMaterial
var world_ready := false
var reef_grid: Dictionary = {}
var ship_grid: Dictionary = {}
var crate_grid: Dictionary = {}
var shot_drawn := false
var fx_drawn := false
var aa_ok := true
const SGRID := 512.0
const CGRID := 500.0
var missiles: Array[Shot] = []
var player: Ship
var follow: Ship = null
var cam: Camera2D
var ui
var rng := RandomNumberGenerator.new()
var time := 0.0
var state: int = State.MENU
var zoom_user := 1.0
var zoom_cur := 1.0
var shake := 0.0
var fire_lock := 0.0
var vp_size := Vector2(1280, 720)
var quality := 2
var auto_quality := true
var perf_timer := 0.0
var water_fast := false
var water_layer: CanvasLayer
var wave_tex_res: ImageTexture
var noise_tex_res: ImageTexture
var auto_acc := 0.0
var auto_t := 0.0
var auto_pending := ""
var auto_before := 0.0
var auto_useless: Array = []
var auto_done: Array = []
var prof: Dictionary = {}
var hud_timer := 0.0
var board_timer := 0.0
var crate_acc := 0.0
var board: Array = []
var ctrl_air := false
var fire_held := false
var fire2_held := false
var promo_open := false
var death_timer := 0.0
var death_info: Dictionary = {}
var death_pending := false
var bot_dmg := 1.0
var bot_err := 0.05
var bot_det := 1.0

var water_mat: ShaderMaterial
var islands_root: Node2D
var trails_root: Node2D
var crate_layer: Node2D
var ships_root: Node2D
var shot_layer: Node2D
var air_layer: Node2D
var fx_layer: Node2D
var trail_curve: Curve
var trail_grad: Gradient
var zone_k := PackedFloat32Array()
var zone_pts := PackedVector2Array()
var zone_layer: Node2D

# ---------------- Setup ----------------

func _ready() -> void:
	rng.randomize()
	S = SettingsScript.new()
	premult = CanvasItemMaterial.new()
	premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	audio = AudioScript.new()
	add_child(audio)
	audio.setup(S)
	_setup_water()
	islands_root = Node2D.new()
	add_child(islands_root)
	trails_root = Node2D.new()
	add_child(trails_root)
	crate_layer = Node2D.new()
	add_child(crate_layer)
	ships_root = Node2D.new()
	add_child(ships_root)
	shot_layer = Node2D.new()
	add_child(shot_layer)
	air_layer = Node2D.new()
	add_child(air_layer)
	fx_layer = Node2D.new()
	add_child(fx_layer)
	crate_layer.draw.connect(_draw_crates)
	shot_layer.draw.connect(_draw_shots)
	fx_layer.draw.connect(_draw_fx)

	zone_layer = Node2D.new()
	add_child(zone_layer)
	zone_layer.draw.connect(_draw_zone)

	trail_curve = Curve.new()
	trail_curve.add_point(Vector2(0.0, 1.0))
	trail_curve.add_point(Vector2(1.0, 0.3))
	trail_grad = Gradient.new()
	trail_grad.set_color(0, Color(1, 1, 1, 0.0))
	trail_grad.set_color(1, Color(1, 1, 1, 0.30))

	_gen_islands()
	_gen_zone()
	for i in CRATE_COUNT:
		crates.append(_new_crate(rng.randf() < 0.45))
	player = Ship.new()
	player.is_player = true
	player.nick = "Player"
	player.color = Color(0.30, 0.65, 1.0)
	ships.append(player)
	_apply_difficulty()
	_setup_ui()
	_apply_display()
	_apply_quality()
	_apply_difficulty()
	# every ship, turret and island is rendered ONCE into a texture (see the bake system below)
	if S.b("bake"):
		_queue_world_jobs()
		_queue_ship_jobs()
		ui.set_loading(0.0)
		_run_bake()
		get_tree().create_timer(90.0).timeout.connect(_finish_world)
	else:
		_finish_world()

func _setup_water() -> void:
	water_layer = CanvasLayer.new()
	water_layer.layer = -10
	add_child(water_layer)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	water_layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	water_mat = ShaderMaterial.new()
	water_mat.shader = WATER_SHADER
	water_mat.set_shader_parameter("world_size", WORLD)
	rect.material = water_mat

# switch between the full-quality analytic water and the cheaper texture-driven one
func _apply_water() -> void:
	if water_fast and wave_tex_res == null:
		wave_tex_res = _make_wave_tex()
		noise_tex_res = _make_noise_tex()
	water_mat.shader = WATER_FAST_SHADER if water_fast else WATER_SHADER
	water_mat.set_shader_parameter("world_size", WORLD)
	if water_fast:
		water_mat.set_shader_parameter("wave_tex", wave_tex_res)
		water_mat.set_shader_parameter("noise_tex", noise_tex_res)
	water_mat.set_shader_parameter("quality", 0 if quality == 0 else (2 if quality >= 2 else 1))

func _setup_ui() -> void:
	ui = UIScript.new()
	add_child(ui)
	ui.map_isl_pos = island_pos
	ui.map_isl_r = island_r
	ui.map_world = WORLD
	ui.map_zone = zone_pts
	ui.setup(S)
	ui.game = self
	ui.exit_requested.connect(request_exit)
	ui.play_pressed.connect(_on_play)
	ui.ship_picked.connect(_on_ship_picked)
	ui.slot_clicked.connect(_select_weapon)
	ui.ability_clicked.connect(_use_ability_player)
	ui.setting_changed.connect(_on_setting_changed)
	ui.show_menu()
	ui.set_fps_visible(S.b("show_fps"))
	ui.set_minimap_visible(S.b("minimap"))

func _apply_difficulty() -> void:
	match S.i("difficulty"):
		0:
			bot_dmg = 0.75
			bot_err = 0.11
			bot_det = 0.8
		2:
			bot_dmg = 1.25
			bot_err = 0.025
			bot_det = 1.2
		_:
			bot_dmg = 1.0
			bot_err = 0.055
			bot_det = 1.0

func _gen_islands() -> void:
	var sizes: Array = []
	for i in 9:
		sizes.append(rng.randf_range(240.0, 430.0))
	for i in 28:
		sizes.append(rng.randf_range(110.0, 230.0))
	for i in 34:
		sizes.append(rng.randf_range(50.0, 105.0))
	for i in 50:
		sizes.append(rng.randf_range(16.0, 38.0))
	var centers := PackedVector2Array()
	for i in 16:
		centers.append(Vector2(rng.randf_range(-WORLD, WORLD), rng.randf_range(-WORLD, WORLD)) * 0.86)
	for sz in sizes:
		var r: float = sz
		for t in 60:
			var p := Vector2(rng.randf_range(-WORLD, WORLD), rng.randf_range(-WORLD, WORLD)) * 0.93
			if rng.randf() < 0.7:
				p = centers[rng.randi() % centers.size()] + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * rng.randf_range(250.0, 1400.0)
			p = p.clamp(Vector2(-WORLD, -WORLD) * 0.94, Vector2(WORLD, WORLD) * 0.94)
			var ok := true
			for k in island_pos.size():
				var lim: float = island_r[k] + r + 120.0
				if p.distance_squared_to(island_pos[k]) < lim * lim:
					ok = false
					break
			if ok:
				island_pos.append(p)
				island_r.append(r)
				island_sd.append(rng.randi())
				break
	# spatial grid so projectiles only test nearby islands
	for i in island_pos.size():
		var rr: float = island_r[i] + 110.0
		var ip := island_pos[i]
		for gx in range(floori((ip.x - rr) / GRID), floori((ip.x + rr) / GRID) + 1):
			for gy in range(floori((ip.y - rr) / GRID), floori((ip.y + rr) / GRID) + 1):
				var key := Vector2i(gx, gy)
				if not island_grid.has(key):
					island_grid[key] = []
				island_grid[key].append(i)
	_gen_decor()

func _gen_decor() -> void:
	# shoals (slow ships down), wrecks and buoys scattered across the sea
	for i in 70:
		reef_pos.append(_free_pos())
		reef_r.append(rng.randf_range(60.0, 170.0))
		reef_sd.append(rng.randi())
	for i in 14:
		wreck_pos.append(_free_pos())
		wreck_rot.append(rng.randf() * TAU)
		wreck_sd.append(rng.randi())
	for i in 60:
		buoy_pos.append(_free_pos())
		buoy_red.append(i % 2 == 0)
	for i in reef_pos.size():
		var rp := reef_pos[i]
		var rr: float = reef_r[i] + 10.0
		for gx in range(floori((rp.x - rr) / GRID), floori((rp.x + rr) / GRID) + 1):
			for gy in range(floori((rp.y - rr) / GRID), floori((rp.y + rr) / GRID) + 1):
				var key := Vector2i(gx, gy)
				if not reef_grid.has(key):
					reef_grid[key] = []
				reef_grid[key].append(i)

func _gen_zone() -> void:
	# irregular "warzone" border: a warped circle, not a square wall
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var ph3 := rng.randf() * TAU
	zone_k.clear()
	zone_pts.clear()
	for i in 48:
		var a := TAU * float(i) / 48.0
		var r := WORLD * (0.82 + 0.07 * sin(3.0 * a + ph1) + 0.05 * sin(5.0 * a + ph2) + 0.035 * sin(9.0 * a + ph3))
		zone_k.append(r)
		zone_pts.append(Vector2.from_angle(a) * r)

func _zone_radius_at(p: Vector2) -> float:
	if zone_k.is_empty():
		return WORLD * 0.85
	var a := wrapf(p.angle(), 0.0, TAU)
	var f := a / TAU * 48.0
	var i0 := wrapi(int(floor(f)), 0, 48)
	var i1 := (i0 + 1) % 48
	var t := clampf(f - floor(f), 0.0, 1.0)
	return lerpf(zone_k[i0], zone_k[i1], t)

func _zone_clamp(p: Vector2, margin: float) -> Vector2:
	if zone_k.is_empty():
		return p.clamp(Vector2(-WORLD, -WORLD), Vector2(WORLD, WORLD))
	if p.length() < 1.0:
		return p
	var r := _zone_radius_at(p) - margin
	return p.limit_length(maxf(r, 1.0))

func _draw_zone() -> void:
	if zone_pts.size() < 4:
		return
	var ring := zone_pts.duplicate()
	ring.append(zone_pts[0])
	zone_layer.draw_polyline(ring, Color(1.0, 0.28, 0.20, 0.85), 5.0)
	zone_layer.draw_polyline(ring, Color(1.0, 0.10, 0.05, 0.18), 16.0)
	var num := ring.size()
	for i in range(0, num - 1, 4):
		var dir := ring[i].normalized()
		var a := ring[i] - dir * 10.0
		var b := ring[i] - dir * 30.0
		zone_layer.draw_line(a, b, Color(1.0, 0.30, 0.22, 0.70), 3.0)
	# supply hot-spots: wrecks near the map edge drop extra supplies fleets fight over
	var pulse := 0.35 + 0.2 * sin(time * 2.2)
	for i in wreck_pos.size():
		var wp: Vector2 = wreck_pos[i]
		zone_layer.draw_arc(wp, 260.0, 0.0, TAU, 40, Color(1.0, 0.82, 0.30, 0.35 + pulse * 0.4), 2.5)
		zone_layer.draw_arc(wp, 200.0, 0.0, TAU, 36, Color(1.0, 0.82, 0.30, 0.18 + pulse * 0.3), 1.5)

func _draw_reef(c: Node2D, r: float, sd: int) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = sd
	var ph := Vector3(g.randf() * TAU, g.randf() * TAU, g.randf() * TAU)
	c.draw_colored_polygon(_blob(r * 1.15, ph), Color(0.30, 0.78, 0.80, 0.10))
	c.draw_colored_polygon(_blob(r * 0.9, ph), Color(0.42, 0.85, 0.82, 0.16))
	c.draw_colored_polygon(_blob(r * 0.6, ph + Vector3(1, 1, 1)), Color(0.55, 0.88, 0.78, 0.20))
	for i in 14:
		var q := Vector2.from_angle(g.randf() * TAU) * r * sqrt(g.randf()) * 0.85
		c.draw_circle(q, g.randf_range(2.0, 5.0), Color(0.25, 0.30, 0.22, 0.55))
		if g.randf() < 0.4:
			c.draw_arc(q, g.randf_range(4.0, 8.0), 0.0, TAU, 10, Color(1, 1, 1, 0.35), 1.2)

func _draw_wreck(c: Node2D, sd: int) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = sd
	var L := g.randf_range(50.0, 110.0)
	var W := L * 0.14
	var hull := D.hull_pts(L, W, 0.74, 1.7, 0.8)
	c.draw_colored_polygon(_scale_pts(hull, 1.35, 2.4), Color(0.3, 0.75, 0.75, 0.10))
	var cut := PackedVector2Array()
	for p in hull:
		if p.x < L * (0.1 + g.randf() * 0.3):
			cut.append(p)
	if cut.size() > 3:
		c.draw_colored_polygon(cut, Color(0.22, 0.17, 0.13, 0.9))
		c.draw_polyline(cut, Color(0.5, 0.3, 0.15, 0.9), 1.5)
		for i in 6:
			c.draw_rect(Rect2(Vector2(g.randf_range(-L * 0.4, 0.0), g.randf_range(-W * 0.3, W * 0.3)), Vector2(g.randf_range(2.0, 6.0), g.randf_range(1.0, 3.0))), Color(0.35, 0.2, 0.1, 0.8))
	c.draw_arc(Vector2.ZERO, L * 0.35, 0.0, TAU, 20, Color(1, 1, 1, 0.18), 3.0)

func _draw_buoy(c: Node2D, red: bool) -> void:
	c.draw_circle(Vector2.ZERO, 9.0, Color(1, 1, 1, 0.10))
	c.draw_circle(Vector2(1.5, 2.0), 3.6, Color(0, 0, 0, 0.25))
	c.draw_circle(Vector2.ZERO, 3.4, Color(0.85, 0.15, 0.12) if red else Color(0.15, 0.7, 0.25))
	c.draw_circle(Vector2.ZERO, 1.8, Color(0.95, 0.95, 0.95))
	c.draw_arc(Vector2.ZERO, 5.5, 0.0, TAU, 12, Color(1, 1, 1, 0.45), 1.0)

func _blob(r: float, ph: Vector3) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 56
	for i in n:
		var a := float(i) / float(n) * TAU
		var k := 1.0 + 0.07 * sin(a * 3.0 + ph.x) + 0.04 * sin(a * 5.0 + ph.y) + 0.022 * sin(a * 9.0 + ph.z) + 0.012 * sin(a * 17.0 + ph.x * 2.0)
		pts.append(Vector2.from_angle(a) * r * k)
	return pts

func _tree(c: Node2D, p: Vector2, tr: float, g: RandomNumberGenerator) -> void:
	c.draw_circle(p + Vector2(tr * 0.35, tr * 0.45), tr * 0.95, Color(0, 0, 0, 0.22))
	var tone := g.randf_range(-0.03, 0.04)
	c.draw_circle(p, tr, Color(0.09 + tone, 0.26 + tone, 0.12))
	c.draw_circle(p + Vector2(-tr * 0.18, -tr * 0.22), tr * 0.72, Color(0.15 + tone, 0.36 + tone, 0.16))
	c.draw_circle(p + Vector2(-tr * 0.3, -tr * 0.36), tr * 0.38, Color(0.27 + tone, 0.50 + tone, 0.22))

func _palm(c: Node2D, p: Vector2, g: RandomNumberGenerator) -> void:
	c.draw_circle(p + Vector2(2, 3), 4.0, Color(0, 0, 0, 0.18))
	var a0 := g.randf() * TAU
	for k in 6:
		var d := Vector2.from_angle(a0 + float(k) * TAU / 6.0)
		c.draw_line(p, p + d * 6.0, Color(0.12, 0.38, 0.14), 1.8)
		c.draw_line(p + d * 2.0, p + d * 6.0 + d.orthogonal() * 1.0, Color(0.2, 0.5, 0.2), 1.0)
	c.draw_circle(p, 1.1, Color(0.35, 0.22, 0.10))

func _house(c: Node2D, p: Vector2, ang: float, g: RandomNumberGenerator) -> void:
	c.draw_set_transform(p, ang, Vector2.ONE)
	var w := g.randf_range(5.0, 9.0)
	var h := g.randf_range(4.0, 6.0)
	c.draw_rect(Rect2(Vector2(-w * 0.5 + 1.5, -h * 0.5 + 2.0), Vector2(w, h)), Color(0, 0, 0, 0.25))
	c.draw_rect(Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h)), Color(0.85, 0.80, 0.70))
	var roof := Color(0.65, 0.22, 0.16) if g.randf() < 0.6 else Color(0.35, 0.37, 0.40)
	c.draw_rect(Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h * 0.5)), roof)
	c.draw_rect(Rect2(Vector2(-w * 0.5, 0.0), Vector2(w, h * 0.5)), roof.darkened(0.25))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_island_halo(c: Node2D, r: float, sd: int) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = sd
	var ph := Vector3(g.randf() * TAU, g.randf() * TAU, g.randf() * TAU)
	c.draw_colored_polygon(_blob(r * 1.9, ph), Color(0.25, 0.75, 0.80, 0.05))
	c.draw_colored_polygon(_blob(r * 1.6, ph), Color(0.30, 0.80, 0.84, 0.08))
	c.draw_colored_polygon(_blob(r * 1.36, ph), Color(0.38, 0.85, 0.88, 0.12))
	c.draw_colored_polygon(_blob(r * 1.2, ph), Color(0.48, 0.90, 0.90, 0.18))

func _draw_island_land(c: Node2D, r: float, sd: int) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = sd
	var ph := Vector3(g.randf() * TAU, g.randf() * TAU, g.randf() * TAU)
	var rock := r < 45.0
	var big := r >= 110.0
	# shallow-water halo, soft shadow, wet sand, dry sand, surf line
	c.draw_colored_polygon(_shift_pts(_blob(r * 1.1, ph), Vector2(8.0, 10.0)), Color(0, 0, 0, 0.20))
	c.draw_colored_polygon(_blob(r * 1.10, ph), Color(0.68, 0.60, 0.41))
	c.draw_colored_polygon(_blob(r * 1.05, ph), Color(0.88, 0.80, 0.58))
	c.draw_polyline(_closed_pts(_blob(r * 1.14, ph)), Color(1, 1, 1, 0.50), 3.0)
	c.draw_polyline(_closed_pts(_blob(r * 1.22, ph)), Color(1, 1, 1, 0.20), 2.0)
	if rock:
		c.draw_colored_polygon(_blob(r * 0.92, ph), Color(0.36, 0.36, 0.38))
		c.draw_colored_polygon(_shift_pts(_blob(r * 0.62, ph), Vector2(-r * 0.1, -r * 0.12)), Color(0.50, 0.50, 0.52))
		c.draw_colored_polygon(_shift_pts(_blob(r * 0.3, ph), Vector2(-r * 0.2, -r * 0.24)), Color(0.64, 0.64, 0.66))
		return
	# grass + varied terrain patches
	c.draw_colored_polygon(_blob(r * 0.93, ph + Vector3(0.3, 0.3, 0.3)), Color(0.30, 0.50, 0.24))
	var patches := 8 if big else 3
	for i in patches:
		var pc := Vector2.from_angle(g.randf() * TAU) * g.randf() * r * 0.55
		var cols := [Color(0.22, 0.42, 0.19, 0.85), Color(0.40, 0.56, 0.27, 0.85), Color(0.50, 0.55, 0.30, 0.75), Color(0.26, 0.46, 0.22, 0.85)]
		c.draw_colored_polygon(_shift_pts(_blob(r * g.randf_range(0.18, 0.36), Vector3(g.randf() * 6.0, g.randf() * 6.0, g.randf() * 6.0)), pc), cols[i % 4])
	# hills with a lit north-west face and a shaded south-east face
	var hills := 1 if r < 150.0 else 3
	for h in hills:
		var hc := Vector2.from_angle(g.randf() * TAU) * g.randf() * r * 0.3
		var hr := r * g.randf_range(0.26, 0.42)
		var hp := ph + Vector3(float(h), float(h) * 2.0, float(h))
		c.draw_colored_polygon(_shift_pts(_blob(hr, hp), hc + Vector2(hr * 0.09, hr * 0.12)), Color(0.12, 0.25, 0.11, 0.9))
		c.draw_colored_polygon(_shift_pts(_blob(hr * 0.94, hp), hc), Color(0.28, 0.45, 0.21))
		c.draw_colored_polygon(_shift_pts(_blob(hr * 0.62, hp), hc + Vector2(-hr * 0.07, -hr * 0.09)), Color(0.38, 0.54, 0.27))
		if r > 200.0:
			c.draw_colored_polygon(_shift_pts(_blob(hr * 0.32, hp), hc + Vector2(-hr * 0.04, -hr * 0.05)), Color(0.48, 0.46, 0.42))
			c.draw_colored_polygon(_shift_pts(_blob(hr * 0.16, hp), hc + Vector2(-hr * 0.08, -hr * 0.1)), Color(0.66, 0.65, 0.62))
	# forests
	var forests := int(r / 22.0)
	for f in forests:
		var fc := Vector2.from_angle(g.randf() * TAU) * sqrt(g.randf()) * r * 0.66
		for k in 5 + int(r / 40.0):
			_tree(c, fc + Vector2(g.randf_range(-1.0, 1.0), g.randf_range(-1.0, 1.0)) * r * 0.12, g.randf_range(4.5, 8.5), g)
	# palms and rocks along the shore
	for k in int(r / 14.0):
		var a := g.randf() * TAU
		if g.randf() < 0.55:
			_palm(c, Vector2.from_angle(a) * r * g.randf_range(0.93, 1.0), g)
		else:
			var rp := Vector2.from_angle(a) * r * g.randf_range(1.04, 1.14)
			c.draw_circle(rp + Vector2(1.5, 2.0), 4.2, Color(0, 0, 0, 0.25))
			c.draw_circle(rp, g.randf_range(2.5, 5.0), Color(0.40, 0.40, 0.43))
	if not big:
		return
	# settlement: houses, a track, a pier with a boat
	if g.randf() < 0.8:
		var va := g.randf() * TAU
		var vc := Vector2.from_angle(va) * r * 0.74
		for k in 5 + int(r / 45.0):
			_house(c, vc + Vector2(g.randf_range(-1.0, 1.0), g.randf_range(-1.0, 1.0)) * 28.0, g.randf_range(-0.5, 0.5) + va, g)
		c.draw_polyline(PackedVector2Array([Vector2.from_angle(va) * r * 1.0, vc, vc * 0.4, vc * 0.1 + Vector2(10, 14)]), Color(0.66, 0.58, 0.40), 3.0)
		var pd := Vector2.from_angle(va)
		c.draw_line(pd * r * 1.04, pd * r * 1.30, Color(0.30, 0.22, 0.14), 4.0)
		c.draw_line(pd * r * 1.04, pd * r * 1.30, Color(0.50, 0.38, 0.24), 2.4)
		c.draw_set_transform(pd * r * 1.34 + pd.orthogonal() * 5.0, va, Vector2.ONE)
		c.draw_colored_polygon(_scale_pts(_circle_pts(5.0, 10), 1.0, 0.45), Color(0.92, 0.92, 0.9))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# lighthouse
	if r > 150.0 and g.randf() < 0.7:
		var la := g.randf() * TAU
		var lp := Vector2.from_angle(la) * r * 0.98
		c.draw_circle(lp, 18.0, Color(1.0, 0.95, 0.6, 0.10))
		c.draw_circle(lp + Vector2(2, 3), 4.0, Color(0, 0, 0, 0.3))
		c.draw_circle(lp, 3.8, Color(0.95, 0.95, 0.95))
		c.draw_circle(lp, 2.4, Color(0.85, 0.2, 0.18))
		c.draw_circle(lp, 1.0, Color(1.0, 0.95, 0.5))

func _draw_island(c: Node2D, r: float, sd: int) -> void:
	_draw_island_halo(c, r, sd)
	_draw_island_land(c, r, sd)

func _closed_pts(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out

func _circle_pts(r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2.from_angle(float(i) / float(n) * TAU) * r)
	return pts

func _rect_pts(p: Vector2, sz: Vector2) -> PackedVector2Array:
	return PackedVector2Array([p, p + Vector2(sz.x, 0.0), p + sz, p + Vector2(0.0, sz.y)])

func _scale_pts(pts: PackedVector2Array, sx: float, sy: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x * sx, p.y * sy))
	return out

func _shift_pts(pts: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + off)
	return out

func _add_poly(parent: Node, pts: PackedVector2Array, col: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = col
	parent.add_child(poly)
	return poly

# polygon with a cheap lighting gradient: brighter along the centreline, darker at the edges
func _shaded(parent: Node, pts: PackedVector2Array, col: Color, amount: float, half: float) -> Polygon2D:
	var poly := _add_poly(parent, pts, col)
	var vc := PackedColorArray()
	for p in pts:
		var t := clampf(absf(p.y) / maxf(half, 0.001), 0.0, 1.0)
		var k := 1.0 + amount * (1.0 - t) - amount * 0.4 * t
		vc.append(Color(col.r * k, col.g * k, col.b * k, col.a))
	poly.vertex_colors = vc
	return poly

func _add_line(parent: Node, a: Vector2, b: Vector2, col: Color, w: float) -> Line2D:
	var l := Line2D.new()
	l.points = PackedVector2Array([a, b])
	l.width = w
	l.default_color = col
	parent.add_child(l)
	return l

# ---------------- World helpers ----------------

func _free_pos() -> Vector2:
	for t in 50:
		var p := Vector2(rng.randf_range(-WORLD, WORLD), rng.randf_range(-WORLD, WORLD)) * 0.95
		if zone_k.size() > 0 and p.length() > _zone_radius_at(p) - 170.0:
			continue
		var ok := true
		for i in island_pos.size():
			var lim: float = island_r[i] + 140.0
			if p.distance_squared_to(island_pos[i]) < lim * lim:
				ok = false
				break
		if ok:
			return p
	return Vector2.ZERO

func _new_crate(hot := false) -> Crate:
	var c := Crate.new()
	# supply hot-spots: destroyed cargo ships near the map edges drop twice the supplies,
	# so fleets fight over the wrecks
	if hot and not wreck_pos.is_empty() and rng.randf() < 0.72:
		var wr := wreck_pos[rng.randi() % wreck_pos.size()]
		c.pos = wr + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 240.0)
	else:
		c.pos = _free_pos()
	c.kind = rng.randi_range(0, 2) # 0 score, 1 health, 2 big score
	c.phase = rng.randf() * TAU
	c.cell = _cell(c.pos)
	_cgrid_add(c)
	return c

func _bot_name() -> String:
	var a := ["Iron", "Storm", "Dark", "Red", "Grey", "Swift", "Sea", "Black", "Steel", "Ghost"]
	var b := ["Wolf", "Shark", "Hawk", "Viper", "Kraken", "Fang", "Tide", "Bear", "Anchor", "Reaper"]
	return a[rng.randi() % a.size()] + b[rng.randi() % b.size()]

func _len(s: Ship) -> float:
	return float(s.def["len"])

func _view_rect(margin: float) -> Rect2:
	var half := vp_size * 0.5 / zoom_cur
	return Rect2(cam.position - half, half * 2.0).grow(margin)

func _fx_cap() -> int:
	return int(float(30 + 25 * quality) * S.f("fx_density"))

# ---------------- Ships: spawn + runtime ----------------

func _add_bot() -> void:
	var b := Ship.new()
	ships.append(b)
	_spawn_bot(b)

func _spawn_bot(b: Ship) -> void:
	var base := player.tier if player != null else 1
	var t := clampi(base + rng.randi_range(-1, 1), 1, D.MAX_TIER)
	var opts := D.of_tier(t)
	_spawn(b, opts[rng.randi() % opts.size()])

func _spawn(s: Ship, def: Dictionary) -> void:
	s.pos = _free_pos()
	s.angle = rng.randf() * TAU
	s.desired = s.angle
	s.speed = 0.0
	s.throttle = 0.0 if s.is_player else 0.7
	s.vel = Vector2.ZERO
	s.alive = true
	s.kills = 0
	s.flash = 0.0
	s.shown_hp = -1.0
	s.was_on = false
	s.sink_t = 0.0
	s.think_t = rng.randf() * 0.25
	s.target = null
	s.fire_set.clear()
	s.air_tgt = false
	s.fire_ok = false
	s.aa_mode = false
	s.air_threat = null
	s.fire_t = 0.0
	s.flood_t = 0.0
	s.flee = false
	s.last_seen_t = 99.0
	s.seen = true
	s.boost_t = 0.0
	s.repair_t = 0.0
	s.smoke_t = 0.0
	s.radar_t = 0.0
	s.barrage_t = 0.0
	s.reveal_t = 0.0
	s.mark_t = 0.0
	s.ab_cd = PackedFloat32Array([0.0, 0.0, 0.0])
	s.invuln = 3.0 if s.is_player else 1.0
	s.side = 1.0 if rng.randf() < 0.5 else -1.0
	s.cursor = s.pos + Vector2.from_angle(s.angle) * 300.0
	s.score = float(D.TIER_NEED[int(def["tier"]) - 1])
	if not s.is_player:
		s.nick = _bot_name()
		s.color = Color.from_hsv(rng.randf(), 0.65, 0.95)
	_ensure_ship_node(s)
	s.built_id = ""
	_apply_def(s, def, 1.0)
	s.name_label.text = s.nick
	s.name_label.add_theme_color_override("font_color", Color(0.65, 0.9, 1.0) if s.is_player else Color(1, 1, 1, 0.92))
	s.node.position = s.pos
	s.node.visible = true
	s.node.modulate = Color(1, 1, 1, 1)
	s.node.scale = Vector2.ONE
	s.trail.clear_points()

func _ensure_ship_node(s: Ship) -> void:
	if s.node != null:
		return
	s.node = Node2D.new()
	ships_root.add_child(s.node)
	s.shadow = Polygon2D.new()
	s.shadow.color = Color(0, 0, 0, 0.24)
	s.shadow.position = Vector2(5, 7)
	s.node.add_child(s.shadow)
	s.body = Node2D.new()
	s.node.add_child(s.body)
	s.tag = Node2D.new()
	s.node.add_child(s.tag)
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	lbl.position = Vector2(-60, -20)
	lbl.size = Vector2(120, 18)
	s.tag.add_child(lbl)
	s.name_label = lbl
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0, 0, 0, 0.55)
	bg.position = Vector2(-26, 2)
	bg.size = Vector2(52, 7)
	s.tag.add_child(bg)
	s.hp_fill = ColorRect.new()
	s.hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.hp_fill.position = Vector2(-25, 3)
	s.hp_fill.size = Vector2(50, 5)
	s.tag.add_child(s.hp_fill)
	s.trail = Line2D.new()
	s.trail.width_curve = trail_curve
	s.trail.gradient = trail_grad
	s.trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trails_root.add_child(s.trail)

func _apply_def(s: Ship, def: Dictionary, keep_ratio: float) -> void:
	s.def = def
	s.tier = int(def["tier"])
	s.max_hp = float(def["hp"])
	s.hp = s.max_hp * keep_ratio
	s.hl = float(def["len"]) * 0.5 + 1.0
	s.hw = maxf(float(def["wid"]) * 0.5 * 1.2, 6.0)
	_build_weapons(s)
	s.wsel = 0
	_build_ship_visual(s)
	_apply_ship_quality(s)
	_setup_air(s)
	if s.is_player:
		ctrl_air = false

func _build_weapons(s: Ship) -> void:
	s.weapons.clear()
	s.has_pd = false
	var L := float(s.def["len"])
	var W := float(s.def["wid"])
	for g in s.def["weapons"]:
		var gd: Dictionary = g
		var wid := str(gd["w"])
		var wd: Dictionary = D.WEAPONS[wid]
		var w := WRT.new()
		w.id = wid
		w.d = wd
		w.kind = int(D.KIND[str(wd["pk"])])
		w.sec = bool(gd.get("sec", false))
		if bool(wd.get("pd", false)):
			s.has_pd = true
		for md in gd["m"]:
			var m := MountRT.new()
			m.x = float(md["x"]) * L
			m.y = float(md["y"]) * W
			m.dir = float(md["dir"])
			m.arc = float(md["arc"])
			# realistic arcs: turret mounts are trained by hull position, not 360 spinners.
			# mounts sitting aft of the bridge sweep towards the stern, fore mounts towards the
			# bow, and the superstructure physically blocks about +/-65 degrees each side.
			if w.kind == int(D.KIND["shell"]):
				if m.x < L * -0.02:
					m.dir = PI
					m.arc = minf(m.arc, 1.15)
				elif m.x > L * 0.02:
					m.arc = minf(m.arc, 1.15)
				elif absf(m.y) > W * 0.12 and m.arc >= 2.8:
					# broadside secondary battery: trained outward on its own side
					m.dir = PI * 0.5 if m.y > 0.0 else -PI * 0.5
					m.arc = minf(m.arc, 1.15)
				else:
					m.arc = minf(m.arc, 1.15)
			m.b = int(md["b"])
			m.rot = m.dir
			var dims := D.mount_dims(wd, m.b)
			m.muz = dims.x
			m.bsp = dims.y
			var mi := w.mounts.size()
			w.mounts.append(m)
			m.bstart = w.cd.size()
			for k in m.b:
				w.cd.append(0.0)
				w.bm.append(mi)
				w.bi.append(k)
		w.total = w.cd.size()
		w.aimpt = s.pos + Vector2.from_angle(s.angle) * 300.0
		s.weapons.append(w)

# ---------------- Ships: visuals ----------------

func _new_group(s: Ship, list: Array[Node2D]) -> Node2D:
	var g := Node2D.new()
	s.body.add_child(g)
	list.append(g)
	return g

func _build_ship_visual(s: Ship) -> void:
	var d: Dictionary = s.def
	var did := str(d["id"])
	if s.built_id == did:
		return
	s.built_id = did
	for ch in s.body.get_children():
		s.body.remove_child(ch)
		ch.queue_free()
	s.details.clear()
	s.fine.clear()
	s.spinners.clear()
	s.parked = null
	var ctx := _ship_ctx(d)
	var L: float = ctx["L"]
	var W: float = ctx["W"]
	var hull: PackedVector2Array = ctx["hull"]
	var st: Dictionary = ctx["st"]
	var is_cv: bool = ctx["cv"]
	var modern: bool = ctx["modern"]
	s.stealth = float(d["stealth"])
	s.shadow.polygon = _flight_deck(L, W) if is_cv else hull
	# foam hugging the hull + prop wash (alpha follows speed)
	var baked := tex.has("h:" + did) and tex.has("f:" + did)
	if baked:
		s.foam = _sprite("f:" + did, s.body)
	else:
		s.foam = Node2D.new()
		s.body.add_child(s.foam)
		s.foam.draw.connect(_draw_foam.bind(s.foam, L, W, hull))
	# bow wave chevron
	s.bow_poly = _add_poly(s.body, PackedVector2Array([
		Vector2(L * 0.54, 0.0), Vector2(L * 0.20, W * 0.95), Vector2(L * 0.08, W * 0.72), Vector2(L * 0.30, 0.0),
		Vector2(L * 0.08, -W * 0.72), Vector2(L * 0.20, -W * 0.95)]), Color(1, 1, 1, 0.0))
	if baked:
		_sprite("h:" + did, s.body)
		_flag_overlay(s, ctx)
	else:
		# hull, deck, structures: three retained canvas items (base / fine / ultra detail)
		var base := Node2D.new()
		s.body.add_child(base)
		base.draw.connect(_draw_ship_static.bind(base, d, s.color, 0))
		var fine := Node2D.new()
		s.body.add_child(fine)
		fine.draw.connect(_draw_ship_static.bind(fine, d, s.color, 1))
		s.details.append(fine)
		var ultra := Node2D.new()
		s.body.add_child(ultra)
		ultra.draw.connect(_draw_ship_static.bind(ultra, d, s.color, 2))
		s.fine.append(ultra)
	# parked aircraft (hidden while it is airborne)
	if str(d["air"]) != "":
		s.parked = Node2D.new()
		s.body.add_child(s.parked)
		s.parked.draw.connect(_draw_parked.bind(s.parked, str(d["air"]), L, W))
	# rotating radars
	if int(d["tier"]) >= 3:
		var mast: Array = st["mast"]
		var pos: Array = []
		if is_cv:
			pos.append(Vector2(L * 0.10, W * 0.46))
		else:
			for i in mini(mast.size(), 2):
				pos.append(Vector2(float(mast[i]) * L, 0.0))
		for pp in pos:
			var sp := Node2D.new()
			sp.position = pp
			sp.set_meta("spd", 3.2 if modern else 1.6)
			s.body.add_child(sp)
			sp.draw.connect(_draw_spinner.bind(sp, modern))
			s.spinners.append(sp)
			s.details.append(sp)
	# weapon mounts (rotating nodes)
	for w in s.weapons:
		for m in w.mounts:
			var n := Node2D.new()
			n.position = Vector2(m.x, m.y)
			n.rotation = m.rot
			s.body.add_child(n)
			m.node = n
			m.barrels = null
			_build_mount_visual(n, w, m)
	s.flash_poly = _add_poly(s.body, hull, Color(1, 1, 1, 0.0))
	s.flash_poly.visible = false
	s.tag.position = Vector2(0.0, -minf(L * 0.45, 60.0) - 20.0)
	s.trail.width = W * 0.9

func _dshade(c: CanvasItem, pts: PackedVector2Array, col: Color, amount: float, half: float) -> void:
	var vc := PackedColorArray()
	for p in pts:
		var t := clampf(absf(p.y) / maxf(half, 0.001), 0.0, 1.0)
		var k := 1.0 + amount * (1.0 - t) - amount * 0.45 * t
		vc.append(Color(col.r * k, col.g * k, col.b * k, col.a))
	c.draw_polygon(pts, vc)

func _ship_ctx(d: Dictionary) -> Dictionary:
	var style := str(d["style"])
	var st: Dictionary = D.STYLES[style]
	var pn := str(d["pal"])
	if pn == "":
		pn = str(st["pal"])
	var pal: Dictionary = D.PAL[pn]
	var L := float(d["len"])
	var W := float(d["wid"])
	return {"L": L, "W": W, "st": st, "style": style, "hcol": pal["hull"], "dcol": pal["deck"], "scol": pal["sup"],
		"modern": style in ["mods", "modm", "modl", "rum", "rul", "ars"], "cv": style == "cv",
		"bow": float(st["bow"]), "bp": float(st["bp"]), "stn": float(st["st"]),
		"hull": D.hull_pts(L, W, float(st["bow"]), float(st["bp"]), float(st["st"])),
		"air": str(d["air"]), "id": str(d["id"]), "tier": int(d["tier"])}

func _hw(ctx: Dictionary, x: float) -> float:
	return D.half_width(x, float(ctx["L"]), float(ctx["W"]), float(ctx["bow"]), float(ctx["bp"]), float(ctx["stn"]))

func _flight_deck(L: float, W: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-L * 0.5, -W * 0.55), Vector2(L * 0.40, -W * 0.55), Vector2(L * 0.5, -W * 0.28),
		Vector2(L * 0.5, W * 0.40), Vector2(L * 0.40, W * 0.55), Vector2(-L * 0.5, W * 0.55)])

func _draw_small_plane(c: CanvasItem, p: Vector2, ang: float, k: float, col: Color) -> void:
	c.draw_set_transform(p, ang, Vector2.ONE * k)
	c.draw_colored_polygon(_shift_pts(PackedVector2Array([Vector2(-3.0, -11.0), Vector2(1.0, -11.0), Vector2(2.0, 0.0), Vector2(1.0, 11.0), Vector2(-3.0, 11.0)]), Vector2(1.5, 2.0)), Color(0, 0, 0, 0.25))
	c.draw_colored_polygon(PackedVector2Array([Vector2(-3.0, -11.0), Vector2(1.0, -11.0), Vector2(2.0, 0.0), Vector2(1.0, 11.0), Vector2(-3.0, 11.0)]), col)
	c.draw_colored_polygon(PackedVector2Array([Vector2(-10.0, -4.0), Vector2(-7.0, -4.0), Vector2(-6.0, 0.0), Vector2(-7.0, 4.0), Vector2(-10.0, 4.0)]), col.darkened(0.1))
	c.draw_colored_polygon(PackedVector2Array([Vector2(-10.0, -1.1), Vector2(4.0, -1.6), Vector2(9.0, -0.8), Vector2(10.5, 0.0), Vector2(9.0, 0.8), Vector2(4.0, 1.6), Vector2(-10.0, 1.1)]), col.lightened(0.12))
	c.draw_circle(Vector2(10.6, 0.0), 1.2, Color(0.15, 0.15, 0.17))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_structure(c: CanvasItem, cx: float, cy: float, bl: float, bw: float, scol: Color, level: int) -> void:
	var loc := PackedVector2Array([Vector2(-bl * 0.5, -bw * 0.5), Vector2(bl * 0.28, -bw * 0.5), Vector2(bl * 0.5, -bw * 0.28),
		Vector2(bl * 0.5, bw * 0.28), Vector2(bl * 0.28, bw * 0.5), Vector2(-bl * 0.5, bw * 0.5)])
	c.draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE)
	if level == 0:
		c.draw_colored_polygon(_scale_pts(loc, 1.16, 1.22), Color(0, 0, 0, 0.30))
		_dshade(c, loc, scol.darkened(0.06), 0.28, bw * 0.5)
		_dshade(c, _shift_pts(_scale_pts(loc, 0.74, 0.70), Vector2(-bl * 0.03, 0.0)), scol, 0.34, bw * 0.35)
		_dshade(c, _shift_pts(_scale_pts(loc, 0.40, 0.52), Vector2(bl * 0.13, 0.0)), scol.lightened(0.10), 0.40, bw * 0.26)
		c.draw_polyline(_closed_pts(loc), scol.darkened(0.35), 0.7)
	elif level == 1:
		c.draw_rect(Rect2(Vector2(bl * 0.12, -bw * 0.74), Vector2(bl * 0.12, bw * 1.48)), scol.darkened(0.18))
		c.draw_rect(Rect2(Vector2(bl * 0.30, -bw * 0.20), Vector2(1.1, bw * 0.40)), Color(0.04, 0.07, 0.11, 0.9))
		c.draw_circle(Vector2(-bl * 0.05, 0.0), minf(bw * 0.12, 2.3), Color(0.12, 0.13, 0.15))
		c.draw_circle(Vector2(-bl * 0.05, -0.3), minf(bw * 0.07, 1.4), Color(0.45, 0.47, 0.50))
		c.draw_rect(Rect2(Vector2(-bl * 0.30, -bw * 0.16), Vector2(bl * 0.12, bw * 0.12)), scol.darkened(0.25))
		c.draw_rect(Rect2(Vector2(-bl * 0.30, bw * 0.06), Vector2(bl * 0.12, bw * 0.10)), scol.darkened(0.25))
	else:
		for k in 4:
			var x := -bl * 0.32 + float(k) * bl * 0.17
			c.draw_circle(Vector2(x, -bw * 0.47), 0.5, Color(0.95, 0.9, 0.6, 0.6))
			c.draw_circle(Vector2(x, bw * 0.47), 0.5, Color(0.95, 0.9, 0.6, 0.6))
		c.draw_line(Vector2(bl * 0.1, 0.0), Vector2(bl * 0.1, -bw * 0.9), Color(0.1, 0.1, 0.12, 0.7), 0.5)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ship_static(c: Node2D, d: Dictionary, flag: Color, level: int) -> void:
	var ctx := _ship_ctx(d)
	if level == 0:
		_ship_l0(c, ctx, flag)
	elif level == 1:
		_ship_l1(c, ctx, flag)
	else:
		_ship_l2(c, ctx)

func _ship_l0(c: Node2D, ctx: Dictionary, flag: Color) -> void:
	var L: float = ctx["L"]
	var W: float = ctx["W"]
	var hull: PackedVector2Array = ctx["hull"]
	var hcol: Color = ctx["hcol"]
	var dcol: Color = ctx["dcol"]
	var scol: Color = ctx["scol"]
	var st: Dictionary = ctx["st"]
	var modern: bool = ctx["modern"]
	var is_cv: bool = ctx["cv"]
	# waterline contact shadow, hull plating with a lit centre, rubbing strake
	c.draw_colored_polygon(_scale_pts(hull, (L + 4.0) / L, (W + 2.2) / W), Color(0.02, 0.04, 0.07, 0.65))
	_dshade(c, hull, hcol, 0.26, W * 0.5)
	c.draw_polyline(_closed_pts(_scale_pts(hull, 0.998, 0.998)), hcol.lightened(0.20), 0.6)
	if not is_cv:
		var dk := _scale_pts(hull, 0.965, 0.80)
		_dshade(c, dk, dcol, 0.30, W * 0.4)
		c.draw_polyline(_closed_pts(dk), dcol.darkened(0.35), 0.5)
		if not modern:
			for k in range(-3, 4):
				var y := float(k) * W * 0.095
				var x1 := L * 0.30 if absf(y) < W * 0.25 else L * 0.18
				c.draw_line(Vector2(-L * 0.43, y), Vector2(x1, y), Color(0, 0, 0, 0.10), 0.6)
		else:
			for k in range(-2, 3):
				c.draw_line(Vector2(-L * 0.42, float(k) * W * 0.12), Vector2(L * 0.30, float(k) * W * 0.12), Color(1, 1, 1, 0.05), 0.8)
	else:
		var fd := _flight_deck(L, W)
		for k in 7:
			var sx := -L * 0.44 + float(k) * L * 0.125
			c.draw_rect(Rect2(Vector2(sx, W * 0.53), Vector2(L * 0.07, W * 0.07)), hcol.darkened(0.25))
			c.draw_rect(Rect2(Vector2(sx, -W * 0.60), Vector2(L * 0.07, W * 0.07)), hcol.darkened(0.25))
		_dshade(c, fd, dcol, 0.16, W * 0.55)
		c.draw_polyline(_closed_pts(fd), Color(0.08, 0.09, 0.10, 0.55), 0.8)
		c.draw_rect(Rect2(Vector2(L * 0.18, -W * 0.40), Vector2(L * 0.07, W * 0.22)), Color(0.17, 0.19, 0.21))
		c.draw_rect(Rect2(Vector2(-L * 0.20, W * 0.14), Vector2(L * 0.07, W * 0.26)), Color(0.17, 0.19, 0.21))
		c.draw_rect(Rect2(Vector2(-L * 0.04, -W * 0.40), Vector2(L * 0.07, W * 0.22)), Color(0.17, 0.19, 0.21))
		for k in 8:
			var px := -L * 0.44 + float(k) * L * 0.032
			var py := -W * 0.34 + float(k % 3) * W * 0.07
			_draw_small_plane(c, Vector2(px, py), 0.0, 0.30, Color(0.58, 0.60, 0.62))
		_draw_structure(c, L * 0.10, W * 0.45, L * 0.11, W * 0.17, scol, 0)
	for b in st["sup"]:
		_draw_structure(c, float(b[0]) * L, 0.0, float(b[1]) * L, float(b[2]) * W, scol, 0)
	# funnels: shaded stack, flag-colour band, black cap
	for fx in st["fun"]:
		var fr := W * 0.15
		c.draw_set_transform(Vector2(float(fx) * L, 0.0), 0.0, Vector2.ONE)
		c.draw_colored_polygon(_scale_pts(_circle_pts(fr * 1.3, 14), 1.5, 1.0), Color(0, 0, 0, 0.28))
		_dshade(c, _scale_pts(_circle_pts(fr, 14), 1.5, 1.0), Color(0.19, 0.20, 0.22), 0.3, fr)
		if flag.a > 0.0:
			c.draw_colored_polygon(_shift_pts(_scale_pts(_circle_pts(fr * 0.78, 14), 1.5, 1.0), Vector2(-0.5, 0.0)), flag.darkened(0.1))
			c.draw_colored_polygon(_scale_pts(_circle_pts(fr * 0.5, 12), 1.4, 1.0), Color(0.03, 0.03, 0.04))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# ensign stripe at the stern, mast bases
	if flag.a > 0.0:
		c.draw_rect(Rect2(Vector2(-L * 0.5 + 1.0, -0.9), Vector2(maxf(L * 0.06, 3.0), 1.8)), flag)
	for mx in st["mast"]:
		c.draw_circle(Vector2(float(mx) * L, 0.0), 1.3, Color(0.12, 0.13, 0.15))
	# helicopter pad
	if str(ctx["air"]) != "" and str(D.AIR[str(ctx["air"])]["kind"]) == "heli":
		var pr := minf(W * 0.36, L * 0.06)
		var padx := -L * 0.30
		c.draw_circle(Vector2(padx, 0.0), pr, Color(0.20, 0.22, 0.24, 0.95))
		c.draw_arc(Vector2(padx, 0.0), pr * 0.85, 0.0, TAU, 18, Color(0.95, 0.80, 0.20, 0.85), 0.9)
		c.draw_line(Vector2(padx - pr * 0.3, -pr * 0.35), Vector2(padx - pr * 0.3, pr * 0.35), Color(1, 1, 1, 0.8), 0.9)
		c.draw_line(Vector2(padx + pr * 0.3, -pr * 0.35), Vector2(padx + pr * 0.3, pr * 0.35), Color(1, 1, 1, 0.8), 0.9)
		c.draw_line(Vector2(padx - pr * 0.3, 0.0), Vector2(padx + pr * 0.3, 0.0), Color(1, 1, 1, 0.8), 0.9)

func _boat(c: CanvasItem, p: Vector2, ang: float, col: Color) -> void:
	c.draw_set_transform(p, ang, Vector2.ONE)
	c.draw_colored_polygon(_scale_pts(_circle_pts(1.0, 10), 3.6, 1.6), Color(0, 0, 0, 0.3))
	c.draw_colored_polygon(_scale_pts(_circle_pts(1.0, 10), 3.3, 1.4), col)
	c.draw_colored_polygon(_scale_pts(_circle_pts(1.0, 10), 2.4, 0.8), col.darkened(0.3))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _ship_l1(c: Node2D, ctx: Dictionary, flag: Color) -> void:
	var L: float = ctx["L"]
	var W: float = ctx["W"]
	var hull: PackedVector2Array = ctx["hull"]
	var scol: Color = ctx["scol"]
	var st: Dictionary = ctx["st"]
	var modern: bool = ctx["modern"]
	var is_cv: bool = ctx["cv"]
	var g := RandomNumberGenerator.new()
	g.seed = hash(str(ctx["id"]))
	var sup: Array = st["sup"]
	var fun: Array = st["fun"]
	var mast: Array = st["mast"]
	if not is_cv:
		c.draw_polyline(_closed_pts(_scale_pts(hull, 0.975, 0.88)), Color(0.85, 0.88, 0.90, 0.30), 0.6)
		for b in sup:
			_draw_structure(c, float(b[0]) * L, 0.0, float(b[1]) * L, float(b[2]) * W, scol, 1)
	else:
		c.draw_set_transform(Vector2(0.0, W * 0.45), 0.0, Vector2.ONE)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_structure(c, L * 0.10, W * 0.45, L * 0.11, W * 0.17, scol, 1)
		# deck markings: centreline, angled landing strip, catapults, arresting wires
		for k in 15:
			var dx := -L * 0.46 + float(k) * L * 0.057
			c.draw_line(Vector2(dx, 0.0), Vector2(dx + L * 0.03, 0.0), Color(1, 0.95, 0.7, 0.55), 0.8)
		c.draw_line(Vector2(-L * 0.48, -W * 0.50), Vector2(L * 0.38, -W * 0.50), Color(1, 1, 1, 0.55), 0.8)
		c.draw_line(Vector2(-L * 0.46, -W * 0.14), Vector2(L * 0.28, W * 0.40), Color(1, 1, 1, 0.38), 0.8)
		c.draw_line(Vector2(-L * 0.44, -W * 0.20), Vector2(L * 0.26, W * 0.34), Color(1, 1, 1, 0.20), 0.6)
		c.draw_line(Vector2(L * 0.12, W * 0.02), Vector2(L * 0.46, W * 0.02), Color(0.1, 0.1, 0.1, 0.6), 1.0)
		c.draw_line(Vector2(L * 0.12, W * 0.08), Vector2(L * 0.46, W * 0.08), Color(0.1, 0.1, 0.1, 0.6), 1.0)
		for k in 4:
			var wx := -L * 0.36 + float(k) * L * 0.035
			c.draw_line(Vector2(wx, -W * 0.30), Vector2(wx, W * 0.10), Color(0.08, 0.08, 0.1, 0.5), 0.6)
	# lifeboats / RHIBs and davits
	if L >= 44.0:
		var bxs: Array = []
		if fun.size() > 0:
			bxs = [float(fun[0]) * L + L * 0.08, float(fun[0]) * L - L * 0.08]
		elif sup.size() > 0:
			bxs = [float(sup[sup.size() - 1][0]) * L - L * 0.02]
		if modern:
			bxs = [float(sup[0][0]) * L - L * 0.04] if sup.size() > 0 else []
		for bx in bxs:
			for side in [-1.0, 1.0]:
				var by: float = float(side) * _hw(ctx, float(bx)) * 0.80
				_boat(c, Vector2(float(bx), by), 0.0, Color(0.92, 0.92, 0.90) if not modern else Color(0.45, 0.48, 0.5))
				c.draw_line(Vector2(float(bx) - 2.5, by), Vector2(float(bx) - 2.5, by - float(side) * 1.6), Color(0.1, 0.1, 0.12, 0.8), 0.6)
	# AA gun tubs
	if not modern and L >= 70.0:
		var tubs := [0.20, -0.33]
		if fun.size() > 0:
			tubs.append(float(fun[0]) + 0.07)
		for tx in tubs:
			for side in [-1.0, 1.0]:
				var tp := Vector2(float(tx) * L, float(side) * W * 0.28)
				c.draw_circle(tp, 2.3, Color(0.13, 0.14, 0.16))
				c.draw_arc(tp, 2.0, 0.0, TAU, 10, Color(0.42, 0.44, 0.48), 0.7)
	# mast details
	for mx in mast:
		var mp := Vector2(float(mx) * L, 0.0)
		if modern:
			c.draw_arc(mp, 2.6, 0.0, TAU, 10, Color(0.14, 0.15, 0.17), 1.0)
			c.draw_circle(mp + Vector2(2.2, 2.6), 1.5, Color(0.9, 0.92, 0.95))
			c.draw_circle(mp + Vector2(2.2, -2.6), 1.5, Color(0.9, 0.92, 0.95))
			c.draw_rect(Rect2(mp + Vector2(-4.0, -0.6), Vector2(2.0, 1.2)), Color(0.3, 0.32, 0.35))
		else:
			c.draw_line(mp + Vector2(0.0, -W * 0.20), mp + Vector2(0.0, W * 0.20), Color(0.12, 0.13, 0.15, 0.9), 0.8)
			c.draw_line(mp, mp + Vector2(L * 0.05, 0.0), Color(0.12, 0.13, 0.15, 0.8), 0.6)
			c.draw_rect(Rect2(mp + Vector2(-1.5, -0.5), Vector2(3.0, 1.0)), Color(0.55, 0.57, 0.6))
	# funnel details / modern exhaust
	for fx in fun:
		var fr := W * 0.15
		var fp := Vector2(float(fx) * L, 0.0)
		c.draw_circle(fp + Vector2(0.8, -fr * 0.4), 0.8, Color(0.45, 0.47, 0.5))
		c.draw_line(fp + Vector2(-fr * 1.4, 0.0), fp + Vector2(-fr * 1.4 - 3.0, fr * 0.6), Color(0.15, 0.16, 0.18), 0.7)
	if modern and sup.size() > 0:
		var ex := float(sup[sup.size() - 1][0]) * L - float(sup[sup.size() - 1][1]) * L * 0.5 - 2.5
		c.draw_rect(Rect2(Vector2(ex - 1.5, -W * 0.20), Vector2(3.0, W * 0.12)), Color(0.07, 0.07, 0.08))
		c.draw_rect(Rect2(Vector2(ex - 1.5, W * 0.08), Vector2(3.0, W * 0.12)), Color(0.07, 0.07, 0.08))
	# catapult + crane for floatplane ships
	if str(ctx["air"]) == "floatplane":
		c.draw_line(Vector2(-L * 0.20, -W * 0.38), Vector2(-L * 0.20, W * 0.38), Color(0.12, 0.13, 0.15), 1.4)
		c.draw_line(Vector2(-L * 0.215, -W * 0.38), Vector2(-L * 0.215, W * 0.38), Color(0.12, 0.13, 0.15), 0.7)
		c.draw_line(Vector2(-L * 0.38, 0.0), Vector2(-L * 0.38, -W * 0.30), Color(0.15, 0.15, 0.17), 1.2)
		c.draw_line(Vector2(-L * 0.38, -W * 0.30), Vector2(-L * 0.43, -W * 0.36), Color(0.15, 0.15, 0.17), 0.8)
	# anchors, capstan, breakwater, hull number, deck vents
	if not is_cv:
		for side in [-1.0, 1.0]:
			c.draw_circle(Vector2(L * 0.41, float(side) * _hw(ctx, L * 0.41) * 0.55), 1.3, Color(0.07, 0.07, 0.08))
			c.draw_rect(Rect2(Vector2(L * 0.25, float(side) * _hw(ctx, L * 0.25) * 0.82 - 0.5), Vector2(2.0, 1.0)), Color(1, 1, 1, 0.75))
			c.draw_rect(Rect2(Vector2(L * 0.25 + 3.2, float(side) * _hw(ctx, L * 0.25) * 0.82 - 0.5), Vector2(1.4, 1.0)), Color(1, 1, 1, 0.75))
		c.draw_circle(Vector2(L * 0.37, 0.0), 1.9, Color(0.14, 0.15, 0.17))
		c.draw_circle(Vector2(L * 0.37, 0.0), 1.1, Color(0.4, 0.42, 0.46))
		if not modern:
			c.draw_line(Vector2(L * 0.33, -W * 0.26), Vector2(L * 0.33, W * 0.26), Color(0.1, 0.1, 0.12, 0.7), 1.0)
		for k in int(L / 16.0):
			var vp := Vector2(g.randf_range(-L * 0.40, L * 0.34), g.randf_range(-W * 0.28, W * 0.28))
			if g.randf() < 0.5:
				c.draw_circle(vp, g.randf_range(0.7, 1.3), Color(0.10, 0.11, 0.13, 0.55))
			else:
				c.draw_rect(Rect2(vp, Vector2(g.randf_range(1.5, 3.0), g.randf_range(0.9, 1.8))), Color(0.12, 0.13, 0.15, 0.5))
	if str(ctx["style"]) in ["ww2l", "ww2xl", "jpl", "jpxl"]:
		_draw_bridge(c, ctx)

func _draw_bridge(c: Node2D, ctx: Dictionary) -> void:
	# proper battleship superstructure: tiered bridge tower, open windows, rangefinder,
	# director and a stub antenna mast - the thing that was missing on Iowa/Yamato
	var L: float = ctx["L"]
	var W: float = ctx["W"]
	var scol: Color = ctx["scol"]
	var pagoda: bool = str(ctx["style"]) in ["jpl", "jpxl"]
	var bx: float = float(ctx["st"]["mast"][0]) * L
	var w1: float = W * 0.62
	var w2: float = W * 0.44
	var w3: float = W * 0.28
	var stages: Array = [[bx - L * 0.055, bx + L * 0.075, w1], [bx - L * 0.028, bx + L * 0.048, w2]]
	if pagoda:
		stages.append([bx - L * 0.014, bx + L * 0.034, w3])
	var pts: PackedVector2Array
	for szi in stages.size():
		var sg: Array = stages[szi]
		var x0: float = sg[0]
		var x1: float = sg[1]
		var hw: float = sg[2] * 0.5
		pts = PackedVector2Array([Vector2(x0, -hw * 0.45), Vector2(x1, -hw), Vector2(x1, hw), Vector2(x0, hw * 0.45)])
		c.draw_colored_polygon(_scale_pts(pts, 1.12, 1.14), Color(0, 0, 0, 0.28))
		_dshade(c, pts, scol.darkened(0.05 + 0.07 * float(szi)), 0.35, hw)
		c.draw_polyline(_closed_pts(pts), scol.darkened(0.4), 0.6)
	# open bridge windows right at the top block
	var tx: float = stages[stages.size() - 1][0]
	var thw: float = stages[stages.size() - 1][2] * 0.5
	c.draw_rect(Rect2(Vector2(tx + 1.0, -thw * 0.52), Vector2(maxf((stages[stages.size() - 1][1] - tx) * 0.55, 2.6), thw * 1.04)), Color(0.05, 0.07, 0.09, 0.95))
	c.draw_line(Vector2(tx + 1.0, -thw * 0.52), Vector2(tx + 1.0, thw * 0.52), Color(0.55, 0.60, 0.65), 0.5)
	# rangefinder ears on the top block
	var hx: float = float(stages[stages.size() - 1][1])
	c.draw_line(Vector2(hx, -thw * 1.5), Vector2(hx, thw * 1.5), Color(0.10, 0.11, 0.13, 0.85), 1.1)
	c.draw_line(Vector2(hx - 1.6, -thw), Vector2(hx, -thw), Color(0.35, 0.37, 0.40), 0.8)
	c.draw_line(Vector2(hx - 1.6, thw), Vector2(hx, thw), Color(0.35, 0.37, 0.40), 0.8)
	# fire-control director + stub mast above the tower
	c.draw_rect(Rect2(Vector2(hx - 1.6, -1.3), Vector2(1.6, 2.6)), scol.darkened(0.3))
	c.draw_line(Vector2(bx, 0.0), Vector2(bx - L * 0.02, -W * 0.75), Color(0.10, 0.11, 0.13, 0.85), 1.2)
	c.draw_line(Vector2(bx - L * 0.02, -W * 0.75), Vector2(bx - L * 0.045, -W * 0.62), Color(0.10, 0.11, 0.13, 0.85), 1.0)
	c.draw_circle(Vector2(bx - L * 0.045, -W * 0.62), maxf(1.2, W * 0.05), Color(0.13, 0.14, 0.16))
	c.draw_circle(Vector2(bx - L * 0.045, -W * 0.62), maxf(0.7, W * 0.028), Color(0.55, 0.58, 0.62))

func _ship_l2(c: Node2D, ctx: Dictionary) -> void:
	var L: float = ctx["L"]
	var W: float = ctx["W"]
	var st: Dictionary = ctx["st"]
	var is_cv: bool = ctx["cv"]
	var g := RandomNumberGenerator.new()
	g.seed = hash(str(ctx["id"])) + 977
	# portholes along the hull edge, bollards, rust streaks
	var x := -L * 0.44
	while x < L * 0.36:
		var h := _hw(ctx, x)
		if not is_cv:
			c.draw_circle(Vector2(x, -h * 0.985), 0.35, Color(0.95, 0.90, 0.65, 0.5))
			c.draw_circle(Vector2(x, h * 0.985), 0.35, Color(0.95, 0.90, 0.65, 0.5))
		x += 6.0
	x = -L * 0.45
	while x < L * 0.40:
		var h2 := _hw(ctx, x)
		if not is_cv:
			c.draw_circle(Vector2(x, -h2 * 0.86), 0.6, Color(0.08, 0.08, 0.1, 0.8))
			c.draw_circle(Vector2(x, h2 * 0.86), 0.6, Color(0.08, 0.08, 0.1, 0.8))
		x += 13.0
	for k in int(L / 10.0):
		var rx := g.randf_range(-L * 0.42, L * 0.36)
		var side := 1.0 if g.randf() < 0.5 else -1.0
		var ry := side * _hw(ctx, rx) * 0.9
		c.draw_line(Vector2(rx, ry), Vector2(rx + g.randf_range(-1.0, 1.0), ry - side * g.randf_range(1.5, 3.5)), Color(0.35, 0.22, 0.12, 0.22), 0.8)
	# mast stays
	for mx in st["mast"]:
		var mp := Vector2(float(mx) * L, 0.0)
		for dx in [-0.08, 0.08]:
			for side in [-1.0, 1.0]:
				c.draw_line(mp, Vector2(float(mx) * L + float(dx) * L, float(side) * _hw(ctx, float(mx) * L + float(dx) * L) * 0.7), Color(0.1, 0.1, 0.12, 0.18), 0.4)
	if is_cv:
		for k in 10:
			c.draw_circle(Vector2(-L * 0.46 + float(k) * L * 0.09, W * 0.50), 0.7, Color(1.0, 0.8, 0.2, 0.6))

func _draw_foam(c: Node2D, L: float, W: float, hull: PackedVector2Array) -> void:
	var outer := _closed_pts(_scale_pts(hull, 1.03, 1.16))
	c.draw_polyline(outer, Color(1, 1, 1, 0.20), 5.0)
	c.draw_polyline(outer, Color(1, 1, 1, 0.55), 2.0)
	for side in [-1.0, 1.0]:
		c.draw_circle(Vector2(-L * 0.5 - 3.0, float(side) * W * 0.14), W * 0.34, Color(1, 1, 1, 0.28))
	c.draw_circle(Vector2(-L * 0.5 - 6.0, 0.0), W * 0.5, Color(1, 1, 1, 0.16))

func _draw_spinner(c: Node2D, modern: bool) -> void:
	if modern:
		c.draw_rect(Rect2(Vector2(-4.0, -0.9), Vector2(8.0, 1.8)), Color(0.16, 0.17, 0.19))
		c.draw_rect(Rect2(Vector2(-4.0, -0.9), Vector2(8.0, 0.6)), Color(0.55, 0.57, 0.60))
		c.draw_circle(Vector2.ZERO, 1.3, Color(0.72, 0.74, 0.77))
	else:
		c.draw_rect(Rect2(Vector2(-3.0, -0.7), Vector2(6.0, 1.4)), Color(0.20, 0.20, 0.22))
		c.draw_circle(Vector2.ZERO, 1.0, Color(0.55, 0.57, 0.6))

func _draw_parked(c: Node2D, aid: String, L: float, W: float) -> void:
	var ad: Dictionary = D.AIR[aid]
	var col: Color = ad["col"]
	if str(ad["kind"]) == "heli":
		c.draw_set_transform(Vector2(-L * 0.30, 0.0), 0.0, Vector2.ONE * float(ad["size"]) * 0.34)
		c.draw_colored_polygon(_shift_pts(_ellipse_pts(7.0, 3.0, 10), Vector2(1.5, 2.0)), Color(0, 0, 0, 0.28))
		c.draw_line(Vector2(-4.0, 0.0), Vector2(-17.0, 0.0), col.darkened(0.4), 1.6)
		c.draw_colored_polygon(_ellipse_pts(6.5, 2.8, 10), col)
		c.draw_colored_polygon(_shift_pts(_ellipse_pts(2.4, 1.6, 8), Vector2(3.5, 0.0)), Color(0.12, 0.22, 0.32))
		for a in [0.0, 1.57, 3.14, 4.71]:
			c.draw_line(Vector2.ZERO, Vector2.from_angle(float(a) + 0.4) * 12.0, Color(0.1, 0.1, 0.11, 0.8), 0.9)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var at := Vector2(-L * 0.20, 0.0)
		if str(ad["n"]).begins_with("Recon"):
			at = Vector2(-L * 0.38, 0.0)
		_draw_small_plane(c, at, 0.0, 0.36 * float(ad["size"]), col)

func _ellipse_pts(rx: float, ry: float, n: int) -> PackedVector2Array:
	return _scale_pts(_circle_pts(1.0, n), rx, ry)

# ---------------- weapon mount visuals ----------------

func _build_mount_visual(n: Node2D, w: WRT, m: MountRT) -> void:
	var wd := w.d
	var kb := "m:%s:%d:" % [w.id, m.b]
	if str(wd["vis"]) == "gun":
		if tex.has(kb + "base") and tex.has(kb + "bar") and tex.has(kb + "roof"):
			_sprite(kb + "base", n)
			m.barrels = _sprite(kb + "bar", n)
			_sprite(kb + "roof", n)
			return
		n.draw.connect(_draw_mount_base.bind(n, wd, m))
		var bar := Node2D.new()
		n.add_child(bar)
		bar.draw.connect(_draw_gun_barrels.bind(bar, wd, m))
		m.barrels = bar
		var roof := Node2D.new()
		n.add_child(roof)
		roof.draw.connect(_draw_gun_roof.bind(roof, wd, m))
	else:
		if tex.has(kb + "all"):
			_sprite(kb + "all", n)
		else:
			n.draw.connect(_draw_mount_base.bind(n, wd, m))

func _draw_gun_barrels(c: Node2D, wd: Dictionary, m: MountRT) -> void:
	var bw := float(wd["bw"]) * D.MSCALE
	var bl := float(wd["bl"]) * D.MSCALE
	var tl := bl * 0.6 + 2.5
	for k in m.b:
		var y := (float(k) - float(m.b - 1) * 0.5) * m.bsp
		var x0 := tl * 0.3
		c.draw_rect(Rect2(Vector2(x0 - 1.0, y - bw * 0.85), Vector2(bl * 0.30, bw * 1.7)), Color(0.18, 0.19, 0.22))
		c.draw_rect(Rect2(Vector2(x0, y - bw * 0.5), Vector2(bl, bw)), Color(0.09, 0.10, 0.12))
		if bw >= 1.2:
			c.draw_line(Vector2(x0, y - bw * 0.18), Vector2(x0 + bl, y - bw * 0.18), Color(0.34, 0.36, 0.40), maxf(bw * 0.3, 0.5))
		c.draw_rect(Rect2(Vector2(x0 + bl - 1.8, y - bw * 0.7), Vector2(1.8, bw * 1.4)), Color(0.05, 0.05, 0.06))

func _draw_gun_roof(c: Node2D, wd: Dictionary, m: MountRT) -> void:
	var bw := float(wd["bw"]) * D.MSCALE
	var bl := float(wd["bl"]) * D.MSCALE
	var tl := bl * 0.6 + 2.5
	var tw := float(m.b) * m.bsp + 2.0
	var metal := Color(0.40, 0.43, 0.48)
	var pts: PackedVector2Array
	if bw < 1.4:
		pts = PackedVector2Array([Vector2(-tl * 0.40, -tw * 0.5), Vector2(tl * 0.2, -tw * 0.45), Vector2(tl * 0.35, 0.0), Vector2(tl * 0.2, tw * 0.45), Vector2(-tl * 0.40, tw * 0.5)])
		c.draw_arc(Vector2.ZERO, maxf(tw, tl * 0.7) * 0.55, 0.0, TAU, 12, Color(0.1, 0.1, 0.12, 0.8), 1.0)
	elif bool(wd.get("mod", false)):
		pts = PackedVector2Array([Vector2(-tl * 0.5, -tw * 0.35), Vector2(-tl * 0.1, -tw * 0.5), Vector2(tl * 0.3, -tw * 0.28), Vector2(tl * 0.42, 0.0),
			Vector2(tl * 0.3, tw * 0.28), Vector2(-tl * 0.1, tw * 0.5), Vector2(-tl * 0.5, tw * 0.35)])
		metal = Color(0.50, 0.54, 0.58)
	else:
		pts = PackedVector2Array([Vector2(-tl * 0.5, -tw * 0.38), Vector2(-tl * 0.35, -tw * 0.5), Vector2(tl * 0.15, -tw * 0.5), Vector2(tl * 0.42, -tw * 0.3),
			Vector2(tl * 0.42, tw * 0.3), Vector2(tl * 0.15, tw * 0.5), Vector2(-tl * 0.35, tw * 0.5), Vector2(-tl * 0.5, tw * 0.38)])
	c.draw_colored_polygon(_scale_pts(pts, 1.12, 1.14), Color(0, 0, 0, 0.30))
	_dshade(c, pts, metal, 0.40, tw * 0.5)
	c.draw_polyline(_closed_pts(pts), metal.darkened(0.45), 0.7)
	if bw >= 1.4:
		_dshade(c, _shift_pts(_scale_pts(pts, 0.66, 0.66), Vector2(-tl * 0.08, 0.0)), metal.lightened(0.10), 0.3, tw * 0.33)
		c.draw_circle(Vector2(-tl * 0.30, -tw * 0.16), maxf(tw * 0.07, 0.6), Color(0.12, 0.13, 0.15))
		c.draw_circle(Vector2(-tl * 0.30, tw * 0.16), maxf(tw * 0.07, 0.6), Color(0.12, 0.13, 0.15))
		for k in m.b:
			var y := (float(k) - float(m.b - 1) * 0.5) * m.bsp
			c.draw_rect(Rect2(Vector2(tl * 0.36, y - bw * 0.7), Vector2(1.5, bw * 1.4)), Color(0.04, 0.04, 0.05))
		if bw >= 2.4:
			c.draw_line(Vector2(-tl * 0.40, -tw * 0.66), Vector2(-tl * 0.40, tw * 0.66), Color(0.10, 0.11, 0.13), 1.2)
			c.draw_circle(Vector2(-tl * 0.40, -tw * 0.66), 0.9, Color(0.5, 0.52, 0.55))
			c.draw_circle(Vector2(-tl * 0.40, tw * 0.66), 0.9, Color(0.5, 0.52, 0.55))
		if bw >= 1.8:
			c.draw_rect(Rect2(Vector2(tl * 0.05, -tw * 0.58), Vector2(tl * 0.12, tw * 0.14)), Color(0.14, 0.15, 0.17))
			c.draw_rect(Rect2(Vector2(tl * 0.05, tw * 0.44), Vector2(tl * 0.12, tw * 0.14)), Color(0.14, 0.15, 0.17))

func _draw_mount_base(c: Node2D, wd: Dictionary, m: MountRT) -> void:
	var dark := Color(0.10, 0.11, 0.13)
	match str(wd["vis"]):
		"gun":
			var bl := float(wd["bl"]) * D.MSCALE
			var tl := bl * 0.6 + 2.5
			var tw := float(m.b) * m.bsp + 2.0
			var rb := maxf(tw, tl * 0.8) * 0.56
			c.draw_circle(Vector2(1.0, 1.5), rb, Color(0, 0, 0, 0.28))
			c.draw_circle(Vector2.ZERO, rb, Color(0.17, 0.18, 0.21))
			c.draw_arc(Vector2.ZERO, rb * 0.9, 0.0, TAU, 20, Color(0.38, 0.40, 0.44), 0.8)
		"ciws":
			c.draw_circle(Vector2(0.8, 1.2), 4.4, Color(0, 0, 0, 0.3))
			c.draw_rect(Rect2(Vector2(1.5, -1.4), Vector2(6.0, 2.8)), dark)
			c.draw_line(Vector2(1.5, -0.5), Vector2(7.5, -0.5), Color(0.34, 0.36, 0.4), 0.6)
			c.draw_circle(Vector2.ZERO, 3.7, Color(0.5, 0.52, 0.55))
			c.draw_circle(Vector2(-0.3, -0.3), 3.0, Color(0.84, 0.86, 0.88))
			c.draw_circle(Vector2(-0.8, -0.8), 1.2, Color(1, 1, 1, 0.7))
			c.draw_arc(Vector2(-1.6, 0.0), 1.8, -1.3, 1.3, 8, Color(0.2, 0.2, 0.22), 0.9)
		"tubes":
			var tl2 := float(wd.get("tl", 10.0)) * 0.65
			var hh := float(m.b) * m.bsp + 1.0
			c.draw_circle(Vector2.ZERO, tl2 * 0.5, Color(0, 0, 0, 0.25))
			c.draw_circle(Vector2.ZERO, tl2 * 0.42, Color(0.20, 0.22, 0.25))
			c.draw_rect(Rect2(Vector2(-tl2 * 0.5, -hh * 0.5), Vector2(tl2, hh)), Color(0.25, 0.27, 0.30))
			for k in m.b:
				var y2 := (float(k) - float(m.b - 1) * 0.5) * m.bsp
				c.draw_rect(Rect2(Vector2(-tl2 * 0.5, y2 - 1.0), Vector2(tl2 + 1.0, 2.0)), Color(0.58, 0.60, 0.63))
				c.draw_line(Vector2(-tl2 * 0.5, y2 - 0.5), Vector2(tl2 * 0.5, y2 - 0.5), Color(0.8, 0.82, 0.85), 0.5)
				c.draw_rect(Rect2(Vector2(tl2 * 0.5, y2 - 1.0), Vector2(1.0, 2.0)), dark)
			c.draw_rect(Rect2(Vector2(-tl2 * 0.5 - 1.0, -hh * 0.5 - 0.5), Vector2(1.2, hh + 1.0)), Color(0.5, 0.2, 0.15))
		"can":
			var hh2 := float(m.b) * m.bsp + 0.8
			c.draw_rect(Rect2(Vector2(-3.4, -hh2 * 0.5 + 1.0), Vector2(8.0, hh2)), Color(0, 0, 0, 0.28))
			c.draw_rect(Rect2(Vector2(-4.0, -hh2 * 0.5), Vector2(8.0, hh2)), Color(0.30, 0.34, 0.30))
			c.draw_line(Vector2(-4.0, -hh2 * 0.5 + 0.6), Vector2(4.0, -hh2 * 0.5 + 0.6), Color(0.5, 0.55, 0.5), 0.6)
			for k in m.b:
				var y3 := (float(k) - float(m.b - 1) * 0.5) * m.bsp
				c.draw_rect(Rect2(Vector2(2.8, y3 - 1.0), Vector2(1.2, 2.0)), Color(0.74, 0.22, 0.15))
				c.draw_line(Vector2(-4.0, y3 + m.bsp * 0.5), Vector2(2.8, y3 + m.bsp * 0.5), Color(0.1, 0.12, 0.1, 0.8), 0.5)
		"vls":
			var cols := mini(m.b, 4)
			var rows := ceili(float(m.b) / float(cols))
			var gw := float(cols) * 2.4 + 1.6
			var gh := float(rows) * 2.4 + 1.6
			c.draw_rect(Rect2(Vector2(-gw * 0.5 + 1.0, -gh * 0.5 + 1.2), Vector2(gw, gh)), Color(0, 0, 0, 0.3))
			c.draw_rect(Rect2(Vector2(-gw * 0.5, -gh * 0.5), Vector2(gw, gh)), dark)
			for k in m.b:
				var cx := float(k % cols) * 2.4 - float(cols) * 1.2
				var cy := float(floori(float(k) / float(cols))) * 2.4 - float(rows) * 1.2
				c.draw_rect(Rect2(Vector2(cx + 0.25, cy + 0.25), Vector2(1.9, 1.9)), Color(0.32, 0.35, 0.38))
				c.draw_line(Vector2(cx + 0.45, cy + 0.45), Vector2(cx + 2.0, cy + 2.0), Color(0.18, 0.2, 0.22), 0.4)
		"rack":
			c.draw_rect(Rect2(Vector2(-4.0, -2.1), Vector2(9.6, 5.6)), Color(0, 0, 0, 0.25))
			c.draw_rect(Rect2(Vector2(-5.0, -3.0), Vector2(9.8, 5.6)), Color(0.24, 0.27, 0.22))
			c.draw_rect(Rect2(Vector2(-5.0, -3.0), Vector2(9.8, 0.9)), Color(0.38, 0.42, 0.34))
			for k in 3:
				for j in 2:
					var p := Vector2(float(k) * 2.9 - 2.9, float(j) * 2.9 - 1.45)
					c.draw_circle(p, 1.1, Color(0.08, 0.09, 0.08))
					c.draw_circle(p, 0.7, Color(0.66, 0.54, 0.30))
		"mine":
			c.draw_rect(Rect2(Vector2(-6.0, -3.5), Vector2(12.0, 0.8)), Color(0.25, 0.26, 0.28))
			c.draw_rect(Rect2(Vector2(-6.0, 2.7), Vector2(12.0, 0.8)), Color(0.25, 0.26, 0.28))
			for k in 3:
				var q := Vector2(float(k) * 4.0 - 4.0, 0.0)
				c.draw_circle(q + Vector2(0.6, 0.9), 1.6, Color(0, 0, 0, 0.3))
				c.draw_circle(q, 1.6, Color(0.12, 0.13, 0.14))
				c.draw_circle(q + Vector2(-0.4, -0.4), 0.6, Color(0.4, 0.42, 0.45))

# ---------------- Aircraft ----------------

func _free_air(a: Air) -> void:
	if a == null:
		return
	if a.node != null:
		a.node.queue_free()
	if a.shadow != null:
		a.shadow.queue_free()

func _mk_air(s: Ship, aid: String) -> Air:
	var a := Air.new()
	a.owner = s
	a.orbit = 1.0 if rng.randf() < 0.5 else -1.0
	a.id = aid
	a.d = D.AIR[aid]
	a.hp = float(a.d["hp"])
	a.alive = true
	a.pos = s.pos
	a.angle = s.angle
	a.spd = float(a.d["spd"]) * 0.5
	for wp in a.d["w"]:
		var w := WRT.new()
		w.id = str(wp[0])
		w.d = D.WEAPONS[w.id]
		w.kind = int(D.KIND[str(w.d["pk"])])
		var m := MountRT.new()
		m.b = int(wp[1])
		m.muz = 9.0
		m.bsp = 2.2
		w.mounts.append(m)
		for k in m.b:
			w.cd.append(0.0)
			w.bm.append(0)
			w.bi.append(k)
		w.total = w.cd.size()
		a.weapons.append(w)
	a.shadow = Node2D.new()
	air_layer.add_child(a.shadow)
	a.node = Node2D.new()
	air_layer.add_child(a.node)
	_air_shapes(a.shadow, a, true)
	_air_shapes(a.node, a, false)
	return a

func _setup_air(s: Ship) -> void:
	if s.air != null:
		_free_air(s.air)
	s.air = null
	for a in s.wing:
		_free_air(a)
	s.wing.clear()
	if s.air2 != null:
		_free_air(s.air2)
	s.air2 = null
	for a in s.wing2:
		_free_air(a)
	s.wing2.clear()
	var aid := str(s.def.get("air", ""))
	if aid != "":
		s.air = _mk_air(s, aid)
		for i in int(s.def.get("squad", 1)) - 1:
			var wm := _mk_air(s, aid)
			wm.wing = true
			wm.leader = s.air
			s.wing.append(wm)
	var aid2 := str(s.def.get("air2", ""))
	if aid2 != "":
		s.air2 = _mk_air(s, aid2)
		for i in int(s.def.get("n2", 1)) - 1:
			var wm2 := _mk_air(s, aid2)
			wm2.wing = true
			wm2.leader = s.air2
			s.wing2.append(wm2)

func _ac(shadow: bool, c: Color) -> Color:
	return Color(0, 0, 0, 0.25) if shadow else c

func _air_shapes(parent: Node2D, a: Air, shadow: bool) -> void:
	# aircraft are drawn small: a scout plane should be a speck against a carrier,
	# not a second ship parked on its deck
	var k := float(a.d["size"]) * 0.5
	var col: Color = a.d["col"]
	var dk := col.darkened(0.4)
	if str(a.d["kind"]) == "heli":
		_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(-17.0, -0.8), Vector2(-4.0, -0.8), Vector2(-4.0, 0.8), Vector2(-17.0, 0.8)]), k, k), _ac(shadow, dk))
		_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(-17.5, -0.3), Vector2(-15.0, -0.3), Vector2(-16.0, -3.2), Vector2(-17.5, -3.2)]), k, k), _ac(shadow, dk))
		_shaded(parent, _scale_pts(PackedVector2Array([Vector2(-5.0, -1.8), Vector2(2.0, -3.0), Vector2(6.5, -1.5), Vector2(7.8, 0.0), Vector2(6.5, 1.5), Vector2(2.0, 3.0), Vector2(-5.0, 1.8)]), k, k), _ac(shadow, col), 0.35, 3.0 * k)
		if not shadow:
			_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(3.5, -1.5), Vector2(6.0, -1.0), Vector2(6.6, 0.0), Vector2(6.0, 1.0), Vector2(3.5, 1.5)]), k, k), Color(0.12, 0.22, 0.32))
		_add_line(parent, Vector2(-4.0, -3.6) * k, Vector2(6.0, -3.6) * k, _ac(shadow, dk), 0.9)
		_add_line(parent, Vector2(-4.0, 3.6) * k, Vector2(6.0, 3.6) * k, _ac(shadow, dk), 0.9)
		if bool(a.d.get("turret", false)):
			_add_poly(parent, _scale_pts(_rect_pts(Vector2(-1.0, -6.0), Vector2(3.0, 12.0)), k, k), _ac(shadow, dk))
		if not shadow:
			var rt := Node2D.new()
			parent.add_child(rt)
			a.rotor = rt
			_add_poly(rt, _circle_pts(13.0 * k, 16), Color(1, 1, 1, 0.07))
			_add_poly(rt, _rect_pts(Vector2(-13.0, -0.5) * k, Vector2(26.0, 1.0) * k), Color(0.08, 0.08, 0.09, 0.8))
			_add_poly(rt, _rect_pts(Vector2(-0.5, -13.0) * k, Vector2(1.0, 26.0) * k), Color(0.08, 0.08, 0.09, 0.5))
	else:
		var span := 11.0
		if a.id == "uav":
			span = 13.0
		_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(-3.0, -span), Vector2(1.5, -span), Vector2(2.5, 0.0), Vector2(1.5, span), Vector2(-3.0, span)]), k, k), _ac(shadow, col))
		_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(-10.0, -4.0), Vector2(-7.0, -4.0), Vector2(-6.0, 0.0), Vector2(-7.0, 4.0), Vector2(-10.0, 4.0)]), k, k), _ac(shadow, col))
		_shaded(parent, _scale_pts(PackedVector2Array([Vector2(-10.0, -1.1), Vector2(4.0, -1.6), Vector2(9.0, -0.8), Vector2(10.5, 0.0), Vector2(9.0, 0.8), Vector2(4.0, 1.6), Vector2(-10.0, 1.1)]), k, k), _ac(shadow, col.lightened(0.1)), 0.3, 1.6 * k)
		if a.id == "floatplane":
			_add_poly(parent, _scale_pts(_rect_pts(Vector2(-4.0, -4.6), Vector2(9.0, 1.4)), k, k), _ac(shadow, dk))
			_add_poly(parent, _scale_pts(_rect_pts(Vector2(-4.0, 3.2), Vector2(9.0, 1.4)), k, k), _ac(shadow, dk))
		if a.id == "torp_bomber":
			_add_poly(parent, _scale_pts(_rect_pts(Vector2(-1.0, -1.2), Vector2(8.0, 2.4)), k, k), _ac(shadow, Color(0.16, 0.18, 0.22)))
			_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(-2.0, -span * 0.75), Vector2(1.5, -span * 0.75), Vector2(2.0, -span * 1.1), Vector2(-2.5, -span * 1.1)]), k, k), _ac(shadow, dk))
		if a.id == "patrol_seaplane":
			_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(2.0, -2.0), Vector2(-2.0, -3.0), Vector2(-2.0, 3.0), Vector2(2.0, 2.0)]), k, k), _ac(shadow, dk))
			_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(-4.5, -1.0), Vector2(-1.5, -1.0), Vector2(-0.5, 0.0), Vector2(-1.5, 1.0), Vector2(-4.5, 1.0)]), k, k), _ac(shadow, Color(0.45, 0.50, 0.55)))
		if a.id == "dive_bomber":
			_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(-2.0, -2.4), Vector2(3.0, -1.2), Vector2(3.0, 1.2), Vector2(-2.0, 2.4)]), k, k), _ac(shadow, Color(0.10, 0.10, 0.12, 0.85)))
		if a.id == "jet_strike" or a.id == "jet_bomber":
			_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(5.0, -2.2), Vector2(7.0, -1.0), Vector2(7.0, 1.0), Vector2(5.0, 2.2)]), k, k), _ac(shadow, dk))
			_add_poly(parent, _scale_pts(PackedVector2Array([Vector2(-9.0, -2.0), Vector2(-7.5, -1.2), Vector2(-7.5, 1.2), Vector2(-9.0, 2.0)]), k, k), _ac(shadow, dk))
			_add_poly(parent, _scale_pts(_rect_pts(Vector2(-6.0, -span * 0.85), Vector2(7.0, 1.6)), k, k), _ac(shadow, dk))
			_add_poly(parent, _scale_pts(_rect_pts(Vector2(-6.0, span * 0.85 - 1.6), Vector2(7.0, 1.6)), k, k), _ac(shadow, dk))
		if a.id == "heli_heavy" and not shadow:
			_add_poly(parent, _scale_pts(_rect_pts(Vector2(-1.0, -6.0), Vector2(4.0, 2.2)), k, k), dk)
			_add_poly(parent, _scale_pts(_rect_pts(Vector2(-1.0, 3.8), Vector2(4.0, 2.2)), k, k), dk)
		if not shadow:
			var rt2 := Node2D.new()
			rt2.position = Vector2(10.5, 0.0) * k
			parent.add_child(rt2)
			a.rotor = rt2
			_add_poly(rt2, _circle_pts(3.6 * k, 10), Color(1, 1, 1, 0.08))
			_add_poly(rt2, _rect_pts(Vector2(-0.4, -3.6) * k, Vector2(0.8, 7.2) * k), Color(0.08, 0.08, 0.09, 0.7))

# ---------------- Input ----------------

func _k_up() -> bool:
	return S.down("up") or Input.is_key_pressed(KEY_UP)

func _k_down() -> bool:
	return S.down("down") or Input.is_key_pressed(KEY_DOWN)

func _k_left() -> bool:
	return S.down("left") or Input.is_key_pressed(KEY_LEFT)

func _k_right() -> bool:
	return S.down("right") or Input.is_key_pressed(KEY_RIGHT)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb: InputEventMouseButton = e
		if mb.button_index == MOUSE_BUTTON_LEFT:
			fire_held = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			fire2_held = mb.pressed
		elif mb.pressed:
			var step := 1.0 + 0.1 * S.f("zoom_sens")
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_user = clampf(zoom_user * step, 0.6, 1.8)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_user = clampf(zoom_user / step, 0.6, 1.8)
	elif e is InputEventKey:
		var k: InputEventKey = e
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE:
			if ui.settings_open:
				ui.close_settings()
			else:
				ui.open_settings()
			return
		if ui.settings_open:
			return
		if k.keycode == KEY_F2:
			S.d["quality"] = (S.i("quality") + 1) % 4
			_apply_quality()
			S.save_file()
			var qn := "Auto" if S.i("quality") == 3 else str(QUALITY_NAMES[S.i("quality")])
			ui.toast("Graphics: " + qn)
			return
		if k.keycode == KEY_F3:
			S.d["show_fps"] = not S.b("show_fps")
			ui.set_fps_visible(S.b("show_fps"))
			S.save_file()
			return
		if state != State.PLAYING:
			return
		if k.keycode >= KEY_1 and k.keycode <= KEY_9:
			_select_weapon(int(k.keycode) - int(KEY_1))
		elif int(k.keycode) == S.key("air"):
			_toggle_air()
		elif int(k.keycode) == S.key("ab1"):
			_use_ability(player, 0)
		elif int(k.keycode) == S.key("ab2"):
			_use_ability(player, 1)
		elif int(k.keycode) == S.key("ab3"):
			_use_ability(player, 2)
		elif int(k.keycode) == S.key("upgrade"):
			if promo_open:
				ui.expand_levelup()

func _on_play(nick: String, ship_id: String) -> void:
	var n := nick.strip_edges()
	if not D.nick_ok(n):
		ui.toast("That nickname is not allowed - renamed.")
		n = "Sailor"
	player.nick = n if n != "" else "Player"
	if n != "" :
		S.d["nick"] = n
		settings_dirty = true
	var def := D.by_id(ship_id)
	if def.is_empty() or int(def["tier"]) != 1:
		for opt in D.of_tier(1):
			def = opt
			break
	_spawn(player, def)
	player.color = _player_paint()
	fire_lock = 0.4
	cam.position = player.pos
	state = State.PLAYING
	promo_open = false
	death_pending = false
	_ensure_missions()
	battle_xp0 = int(S.d.get("xp", 0))
	battle_rp0 = int(S.d.get("rp", 0))
	battle_bp0 = int(S.d.get("bp", 0))
	battle_kills = 0
	battle_dmg = 0.0
	battle_time = 0.0
	battle_promos = 0
	in_battle = true
	S.d["battles"] = int(S.d.get("battles", 0)) + 1
	S.mark_played(String(def["id"]))
	settings_dirty = true
	ui.show_game()
	_refresh_loadout()
	audio.play_ui("click")

func _on_ship_picked(ship_id: String, mode: String) -> void:
	var def := D.by_id(ship_id)
	if def.is_empty():
		return
	audio.play_ui("levelup" if mode == "levelup" else "click")
	if mode == "levelup":
		if not player.alive:
			return
		promo_open = false
		var ratio := maxf(player.hp / player.max_hp, 0.6)
		_apply_def(player, def, ratio)
		_add_fx(3, player.pos, player.hl * 1.8, 0.7, Color(0.5, 0.85, 1.0))
		ui.hide_levelup()
		ui.toast("Now commanding the %s" % str(def["name"]))
		_refresh_loadout()
	elif mode == "respawn":
		if state != State.DEAD:
			return
		death_pending = false
		_spawn(player, def)
		player.color = _player_paint()
		fire_lock = 0.4
		cam.position = player.pos
		state = State.PLAYING
		promo_open = false
		ui.hide_respawn()
		ui.show_game()
		_refresh_loadout()

func _select_weapon(idx: int) -> void:
	if state != State.PLAYING or not player.alive:
		return
	if ctrl_air and player.air != null:
		if idx >= player.air.weapons.size():
			return
		player.air.wsel = idx
	else:
		if idx >= player.weapons.size():
			return
		player.wsel = idx
	audio.play_ui("click")
	ui.set_selected(idx)

func _toggle_air() -> void:
	var p := player
	if not p.alive or p.air == null:
		return
	if not p.air.alive:
		ui.toast("Aircraft is being rebuilt...")
		return
	ctrl_air = not ctrl_air
	audio.play_ui("ability")
	ui.toast("Controlling: " + (str(p.air.d["n"]) if ctrl_air else str(p.def["name"])))
	_refresh_loadout()

func _use_ability_player(idx: int) -> void:
	if state == State.PLAYING:
		_use_ability(player, idx)

# push the current weapon / ability / aircraft set to the HUD
func _refresh_loadout() -> void:
	var wl: Array = []
	var sel := 0
	if ctrl_air and player.air != null:
		for w in player.air.weapons:
			wl.append({"n": str(w.d["n"]), "ic": str(w.d["ic"]), "total": w.total, "rng": float(w.d["rng"]), "dmg": float(w.d["dmg"]) * float(w.d.get("sal", 1)), "aa": bool(w.d.get("aa", false))})
		sel = player.air.wsel
	else:
		for w in player.weapons:
			wl.append({"n": str(w.d["n"]), "ic": str(w.d["ic"]), "total": w.total, "rng": float(w.d["rng"]), "dmg": float(w.d["dmg"]) * float(w.d.get("sal", 1)), "aa": bool(w.d.get("aa", false))})
		sel = player.wsel
	var al: Array = []
	for aid in player.def["abil"]:
		var ad: Dictionary = D.ABILITIES[str(aid)]
		al.append({"n": str(ad["n"]), "desc": str(ad["desc"])})
	var air_name := ""
	if player.air != null:
		air_name = str(player.air.d["n"])
	ui.set_loadout(wl, al, air_name, ctrl_air)
	ui.set_selected(sel)

# ---------------- Player control ----------------

func _player_input(dt: float) -> void:
	var p := player
	if not p.alive:
		return
	fire_lock = maxf(0.0, fire_lock - dt)
	if ui.settings_open or state != State.PLAYING:
		return
	var mouse := get_global_mouse_position()
	p.cursor = mouse
	if not ctrl_air:
		if _k_up():
			p.throttle = minf(1.0, p.throttle + dt * 0.8)
		if _k_down():
			p.throttle = maxf(-0.3, p.throttle - dt * 0.8)
		var steer := 0.0
		if _k_left():
			steer -= 1.0
		if _k_right():
			steer += 1.0
		var turn := float(p.def["turn"])
		p.angle += steer * turn * dt * clampf(absf(p.speed) / 60.0, 0.25, 1.0)
		for w in p.weapons:
			w.aimpt = mouse
	else:
		if p.air != null:
			p.air.aimpt = mouse
	var firing := fire_lock <= 0.0 and ((fire_held and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or (fire2_held and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) or S.down("fire"))
	if firing:
		if ctrl_air:
			if p.air != null and p.air.alive:
				_air_fire(p, p.air, p.air.wsel)
		elif p.wsel < p.weapons.size():
			_try_fire(p, p.weapons[p.wsel])

# ---------------- Abilities ----------------

func _use_ability(s: Ship, idx: int) -> void:
	if not s.alive:
		return
	var abl: Array = s.def["abil"]
	if idx >= abl.size():
		return
	if s.ab_cd[idx] > 0.0:
		return
	var id := str(abl[idx])
	var ad: Dictionary = D.ABILITIES[id]
	s.ab_cd[idx] = float(ad["cd"])
	var dur := float(ad["dur"])
	var snd := "ability"
	match id:
		"boost":
			s.boost_t = dur
		"repair":
			s.repair_t = dur
			s.fire_t = 0.0
			s.flood_t = 0.0
		"smoke":
			s.smoke_t = dur
		"radar":
			s.radar_t = dur
			snd = "ping"
		"barrage":
			s.barrage_t = dur
		"chaff":
			for sh in shots:

				if sh.src != s and (sh.kind == K_TORP or sh.kind == K_MISSILE) and sh.mode != 0:
					if sh.pos.distance_squared_to(s.pos) < 520.0 * 520.0:
						sh.mode = 0
						sh.lock = null
						sh.tgt = sh.pos + Vector2.from_angle(sh.ang + rng.randf_range(-1.2, 1.2)) * 300.0
		"mine_l":
			s.mine_t = dur
		"dive":
			s.dive_t = dur
			for sh in shots:
				if sh.src != s and (sh.kind == K_TORP or sh.kind == K_MISSILE) and sh.mode != 0:
					if sh.pos.distance_squared_to(s.pos) < 640.0 * 640.0:
						sh.mode = 0
						sh.lock = null
						sh.tgt = sh.pos + Vector2.from_angle(sh.ang + rng.randf_range(-1.2, 1.2)) * 300.0
	_add_fx(3, s.pos, s.hl * 1.8, 0.6, Color(0.6, 0.9, 1.0))
	if s.is_player:
		audio.play_ui(snd, -2.0)
		ui.toast(str(ad["n"]))
	else:
		audio.play(snd, s.pos, -6.0)

# ---------------- Weapons ----------------

func _mount_target(m: MountRT, ang: float, mp: Vector2, aimpt: Vector2) -> float:
	var rel := angle_difference(m.dir, (aimpt - mp).angle() - ang)
	rel = clampf(rel, -m.arc, m.arc)
	return m.dir + rel

func _tick_weapons(s: Ship, dt: float) -> void:
	var rate := 2.0 if s.barrage_t > 0.0 else 1.0
	var step := dt * rate
	for w in s.weapons:
		var wstep := step
		if s.mine_t > 0.0 and w.kind == K_MINE:
			wstep = dt * 4.0
		w.gap_t = maxf(0.0, w.gap_t - wstep)
		for k in w.total:
			if w.cd[k] > 0.0:
				w.cd[k] = maxf(0.0, w.cd[k] - wstep)

func _update_mounts(s: Ship, dt: float) -> void:
	var only := -1
	if not s.is_player:
		if not s.fire_ok and s.pos.distance_squared_to(cam.position) > 3200.0 * 3200.0:
			return
		only = s.wsel
	for wi in s.weapons.size():
		var w: WRT = s.weapons[wi]
		if only >= 0 and wi != only and not w.sec:
			continue
		var trav := float(w.d["trav"]) * dt
		if w.kind == K_SHELL:
			# heavy turrets are hydraulically slow: a 460mm mount swings nothing like an AA gun
			trav *= 0.9 / (0.5 + float(w.d.get("bw", 1.0)))
		for m in w.mounts:
			if m.arc <= 0.001:
				continue
			var mp := s.pos + Vector2(m.x, m.y).rotated(s.angle)
			var tr := _mount_target(m, s.angle, mp, w.aimpt)
			m.rot = wrapf(m.rot + clampf(angle_difference(m.rot, tr), -trav, trav), -PI, PI)

# out-of-zone damage: kills in ~10s at entry, ramping up the longer you stay
func _step_border(s: Ship, dt: float) -> void:
	if zone_k.is_empty():
		return
	if s.pos.length() < _zone_radius_at(s.pos):
		s.border_t = maxf(0.0, s.border_t - dt)
		return
	s.border_t += dt
	var dps := s.max_hp * (0.10 + 0.02 * s.border_t)
	s.hp -= dps * dt
	s.flash = maxf(s.flash, 0.35)
	if s.is_player and s.fx_t <= 0.0:
		_add_fx(1, s.pos + Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0)), 8.0, 0.6)
		_add_fx(9, s.pos + Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0)), 6.0, 0.4)
	if s.hp <= 0.0 and s.alive:
		_kill(s, null)

# ship-to-ship ramming: ships push each other apart and grind slowly against the hull
func _step_ram(s: Ship, dt: float) -> void:
	var mass_s := float(s.def["len"]) * float(s.def["wid"])
	var rad := s.hl * 0.7
	var gkey := Vector2i(floori(s.pos.x / SGRID), floori(s.pos.y / SGRID))
	if not ship_grid.has(gkey):
		return
	for o in ship_grid[gkey]:
		var ob: Ship = o
		if ob == s or not ob.alive:
			continue
		var dv := s.pos - ob.pos
		var d2 := dv.length_squared()
		var min_d := rad + ob.hl * 0.7
		if d2 >= min_d * min_d or d2 < 0.001:
			continue
		var dl := sqrt(d2)
		var n := dv / dl
		var overlap := min_d - dl
		var mass_o := float(ob.def["len"]) * float(ob.def["wid"])
		var w_s := mass_o / (mass_s + mass_o)
		s.pos += n * overlap * w_s * dt * 6.0
		var relspd := absf((ob.vel - s.vel).dot(n))
		var weight := clampf(w_s * 2.0, 0.15, 1.6)
		var dmg_s := maxf(2.0, s.max_hp * (0.10 + 0.6 * relspd / 240.0) * weight * dt)
		ob.reveal_t = maxf(ob.reveal_t, 1.0)
		s.reveal_t = maxf(s.reveal_t, 1.0)
		s.flash = maxf(s.flash, 0.4)
		s.last_attacker = ob
		ob.last_attacker = s
		s.hp -= dmg_s
		if s.hp <= 0.0 and s.alive:
			_kill(s, ob)

func _auto_sec_aim(s: Ship, dt: float) -> void:
	s.sec_t -= dt
	if s.sec_t > 0.0:
		return
	s.sec_t = 0.25
	if s.sec_tgt != null and (not s.sec_tgt.alive or s.sec_tgt.dive_t > 0.0 or not _can_see(s, s.sec_tgt)):
		s.sec_tgt = null
	if s.sec_tgt == null:
		var best: Ship = null
		var bd := 1100.0 * 1100.0
		var gkey := Vector2i(floori(s.pos.x / SGRID), floori(s.pos.y / SGRID))
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var key: Vector2i = gkey + Vector2i(dx, dy)
				if not ship_grid.has(key):
					continue
				for o in ship_grid[key]:
					if o == s or not o.alive or o.dive_t > 0.0:
						continue
					var d2 := s.pos.distance_squared_to(o.pos)
					if d2 < bd and _can_see(s, o):
						bd = d2
						best = o
		s.sec_tgt = best
	if s.sec_tgt != null:
		var t: Ship = s.sec_tgt
		var dist := s.pos.distance_to(t.pos)
		var lead := t.pos + t.vel * (dist / 400.0)
		for w in s.weapons:
			if w.sec:
				w.aimpt = lead

func _auto_sec_fire(s: Ship) -> void:
	if s.sec_tgt == null or not s.sec_tgt.alive:
		return
	for w in s.weapons:
		if not w.sec:
			continue
		var mid := s.pos + Vector2.from_angle(s.angle) * (s.hl * 0.5)
		if mid.distance_to(s.sec_tgt.pos) > float(w.d["rng"]) * 0.85:
			continue
		w.aimpt = s.sec_tgt.pos
		if _try_fire(s, w):
			s.reveal_t = maxf(s.reveal_t, 2.0)

# Fire the next barrel of weapon w. Barrels fire in sequence (barrel by barrel, turret by
# turret). Torpedo-style weapons ("pick") use the mount nearest to the aim direction instead.
# A launcher can only rotate within its arc; the projectile leaves in that direction and then
# turns toward the aim point.
func _try_fire(s: Ship, w: WRT) -> bool:
	if w.gap_t > 0.0 or w.total == 0:
		return false
	var wd := w.d
	# submerged: only torpedo tubes work under water. Guns and missiles are on deck.
	if s.dive_t > 0.0 and w.kind != int(D.KIND["torp"]):
		return false
	# fire from the mount CLOSEST to the aim point that still has a loaded barrel
	var bm := -1
	var bd := INF
	for mi in w.mounts.size():
		var mm: MountRT = w.mounts[mi]
		var loaded := false
		for j in mm.b:
			if w.cd[mm.bstart + j] <= 0.0:
				loaded = true
				break
		if not loaded:
			continue
		var dd := (s.pos + Vector2(mm.x, mm.y).rotated(s.angle)).distance_squared_to(w.aimpt)
		if dd < bd:
			bd = dd
			bm = mi
	if bm < 0:
		return false
	var m: MountRT = w.mounts[bm]
	var mp := s.pos + Vector2(m.x, m.y).rotated(s.angle)
	var tr := _mount_target(m, s.angle, mp, w.aimpt)
	if absf(angle_difference(m.rot, tr)) > 0.13:
		return false
	# inside that turret the barrels fire one after another
	var kk := -1
	for j in m.b:
		var cand := m.bstart + (m.bptr + j) % m.b
		if w.cd[cand] <= 0.0:
			kk = cand
			m.bptr = (cand - m.bstart + 1) % m.b
			break
	if kk < 0:
		return false
	var fire_ang := s.angle + tr
	var dirv := Vector2.from_angle(s.angle + m.rot)
	var side := Vector2(-dirv.y, dirv.x)
	var by := (float(kk - m.bstart) - float(m.b - 1) * 0.5) * m.bsp
	var origin := mp + dirv * m.muz + side * by
	_spawn_shot(s, w, origin, fire_ang, w.aimpt, s.vel)
	w.cd[kk] = float(wd["rl"]) * float(s.def["rlm"])
	w.gap_t = float(wd["gap"]) * float(s.def["rlm"])
	m.recoil = 1.0
	s.reveal_t = 3.0
	_fire_effects(s, wd, origin, fire_ang)
	return true

func _fire_effects(s: Ship, wd: Dictionary, origin: Vector2, ang: float) -> void:
	var vis := str(wd["vis"])
	var big := 6.0
	if vis == "gun":
		big = 6.0 + float(wd["bw"]) * 3.0
		_add_fx(2, origin, big, 0.12, Color(1.0, 0.85, 0.5), ang)
		if float(wd["bw"]) >= 1.5:
			_add_fx(4, origin + Vector2.from_angle(ang) * 6.0, big * 0.8, 0.7, Color(0.8, 0.8, 0.8))
	elif vis == "ciws":
		_add_fx(2, origin, 6.0, 0.08, Color(1.0, 0.9, 0.5), ang)
	else:
		_add_fx(4, origin, 12.0, 0.8, Color(0.9, 0.9, 0.9))
	var near := origin.distance_squared_to(cam.position) < 2200.0 * 2200.0
	if s.is_player:
		audio.play(str(wd["snd"]), origin, 0.0)
		var sk := 1.0
		if vis == "gun":
			sk = float(wd["bw"]) * 0.9
		shake = maxf(shake, sk * S.f("shake"))
	elif near:
		audio.play(str(wd["snd"]), origin, -4.0)
	if near and vis == "gun" and float(wd["bw"]) >= 2.0:
		# salvo drama: heavy broadsides rattle the camera even from other ships
		shake = maxf(shake, (float(wd["bw"]) - 1.6) * 6.0 * S.f("shake"))
		_add_fx(2, origin, big * 1.7, 0.2, Color(1.0, 0.75, 0.35), ang)
		_add_fx(7, origin + Vector2.from_angle(ang) * 10.0, big * 2.4, 0.5, Color(1.0, 0.8, 0.5))
		_add_fx(4, origin + Vector2.from_angle(ang) * 16.0, big * 1.5, 1.2, Color(0.75, 0.75, 0.78))

func _spawn_shot(s: Ship, w: WRT, origin: Vector2, ang: float, tgt: Vector2, carry: Vector2 = Vector2.ZERO) -> void:
	if shots.size() >= MAX_SHOTS:
		return
	var wd := w.d
	var sal := int(wd.get("sal", 1))
	var dm := 1.0 if s.is_player else bot_dmg
	var lock = null
	if (w.kind == K_MISSILE or w.kind == K_TORP) and int(wd.get("mode", 0)) >= 1:
		lock = _find_lock(s, origin, tgt, float(wd["rng"]))
	for i in sal:
		var sh := Shot.new()
		sh.src = s
		sh.kind = w.kind
		sh.ang = ang + rng.randf_range(-1.0, 1.0) * float(wd.get("spr", 0.0))
		sh.spd = float(wd["spd"])
		if sal > 1:
			sh.spd *= rng.randf_range(0.9, 1.1)
		sh.dmg = float(wd["dmg"]) * dm
		sh.spl = float(wd.get("spl", 0.0))
		sh.mode = int(wd.get("mode", 0))
		sh.turn = float(wd.get("turn", 0.0))
		sh.seek = float(wd.get("seek", 0.0))
		sh.aa = bool(wd.get("aa", false))
		sh.ar = float(wd.get("ar", 0.0))
		sh.mt = int(wd.get("mt", 0))
		sh.lock = lock
		sh.pos = origin
		sh.vel = Vector2.from_angle(sh.ang) * sh.spd
		sh.tgt = tgt
		sh.scan = 0.3
		sh.life = float(wd["rng"]) / maxf(sh.spd, 1.0)
		if sh.kind == K_SHELL:
			sh.sz = 1.6 + float(wd.get("bw", 2.0)) * 0.45
			sh.col = Color(1.0, 0.85, 0.45)
		elif sh.kind == K_ROCKET:
			sh.tgt = tgt + Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
			sh.hp = 4.0
		elif sh.kind == K_MISSILE:
			sh.life *= 1.25
			sh.hp = 12.0
		elif sh.kind == K_MINE:
			sh.vel = Vector2.from_angle(sh.ang) * 40.0
			sh.life = 70.0
		elif sh.kind == K_BOMB:
			sh.vel = carry * 0.7
			sh.life = 0.7
			sh.hp = 10.0
		shots.append(sh)

# the closest visible enemy to the direction we are aiming in (within a ~28 degree cone)
func _find_lock(s: Ship, origin: Vector2, aimpt: Vector2, max_range: float):
	var aim_ang := (aimpt - origin).angle()
	var best = null
	var ba := 0.5
	for o in ships:
		if not o.alive or o == s or o.invuln > 0.0:
			continue
		var dv := o.pos - origin
		var dl := dv.length()
		if dl > max_range or dl < 60.0:
			continue
		var da := absf(angle_difference(aim_ang, dv.angle()))
		if da < ba and _can_see(s, o):
			ba = da
			best = o
	return best

func _air_fire(s: Ship, a: Air, wi: int) -> void:
	if wi >= a.weapons.size():
		return
	var w: WRT = a.weapons[wi]
	var wd := w.d
	if w.gap_t > 0.0:
		return
	if str(wd.get("special", "")) == "mark":
		if w.cd[0] > 0.0:
			return
		var best: Ship = null
		var bd := 280.0 * 280.0
		for o in ships:
			if o != s and o.alive:
				var d2 := o.pos.distance_squared_to(a.aimpt)
				if d2 < bd:
					bd = d2
					best = o
		if best == null:
			return
		best.mark_t = 12.0
		w.cd[0] = float(wd["rl"])
		w.gap_t = float(wd["gap"])
		_add_fx(3, best.pos, best.hl * 2.0, 0.8, Color(1.0, 0.3, 0.3))
		if s.is_player:
			audio.play_ui("ping")
			ui.toast("Target marked: %s" % best.nick)
		return
	var k := -1
	for j in w.total:
		var kk := (w.ptr + j) % w.total
		if w.cd[kk] <= 0.0:
			k = kk
			break
	if k < 0:
		return
	var ang := a.angle
	if bool(a.d.get("turret", false)) and w.kind == K_BULLET:
		ang = (a.aimpt - a.pos).angle()
	var dirv := Vector2.from_angle(ang)
	var m: MountRT = w.mounts[0]
	var by := (float(w.bi[k]) - float(m.b - 1) * 0.5) * m.bsp
	var origin := a.pos + dirv * m.muz + Vector2(-dirv.y, dirv.x) * by
	if w.kind == K_BOMB:
		origin = a.pos + Vector2(-dirv.y, dirv.x) * by
	_spawn_shot(s, w, origin, ang, a.aimpt, a.vel)
	w.cd[k] = float(wd["rl"])
	w.gap_t = float(wd["gap"])
	w.ptr = (k + 1) % w.total
	s.reveal_t = 3.0
	if w.kind == K_BOMB:
		audio.play("bomb", origin, -4.0)
	else:
		_fire_effects(s, wd, origin, ang)

func _tick_air_weapons(a: Air, dt: float) -> void:
	for w in a.weapons:
		w.gap_t = maxf(0.0, w.gap_t - dt)
		for k in w.total:
			if w.cd[k] > 0.0:
				w.cd[k] = maxf(0.0, w.cd[k] - dt)

# close-in weapons shoot down incoming missiles, rockets and bombs
func _step_pd(s: Ship, dt: float) -> void:
	s.pd_t -= dt
	if s.pd_t > 0.0:
		return
	s.pd_t = 0.25
	for sh in missiles:
		if sh.dead or sh.src == s:
			continue
		if sh.kind != K_MISSILE and sh.kind != K_ROCKET and sh.kind != K_BOMB:
			continue
		if sh.pos.distance_squared_to(s.pos) > 300.0 * 300.0:
			continue
		var f := _add_fx(5, s.pos, 0.0, 0.12, Color(1.0, 0.9, 0.5))
		if f != null:
			f.pos2 = sh.pos
		if rng.randf() < 0.55:
			sh.dead = true
			_add_fx(0, sh.pos, 16.0, 0.35)
			audio.play("explode_s", sh.pos, -6.0)
		audio.play("ciws", s.pos, -6.0)
		return

# ---------------- Projectiles ----------------

func _step_shots(dt: float) -> void:
	var i := shots.size() - 1
	while i >= 0:
		var sh: Shot = shots[i]
		var remove := false
		if sh.dead:
			remove = true
		else:
			sh.t += dt
			sh.life -= dt
			var p0 := sh.pos
			_move_shot(sh, dt)
			if _shot_collide(sh, p0):
				remove = true
			elif sh.life <= 0.0:
				_shot_expire(sh)
				remove = true
		if remove:
			shots.remove_at(i)
		i -= 1

func _move_shot(sh: Shot, dt: float) -> void:
	if sh.kind == K_TORP or sh.kind == K_MISSILE or sh.kind == K_ROCKET:
		_steer_shot(sh, dt)
	elif sh.kind == K_MINE:
		sh.vel *= maxf(0.0, 1.0 - 1.4 * dt)
	sh.pos += sh.vel * dt
	if sh.kind == K_MISSILE or sh.kind == K_ROCKET:
		sh.trail_t -= dt
		if sh.trail_t <= 0.0 and quality >= 1:
			sh.trail_t = 0.04
			sh.trail.append(sh.pos)
			if sh.trail.size() > 9:
				sh.trail.remove_at(0)

func _steer_shot(sh: Shot, dt: float) -> void:
	var spd := sh.spd
	if sh.kind == K_MISSILE:
		spd = sh.spd * minf(1.0, 0.45 + sh.t * 0.9)
	elif sh.kind == K_ROCKET:
		spd = sh.spd * minf(1.0, 0.5 + sh.t * 2.0)
	if sh.mode >= 1:
		# lock-on guidance: chase the target chosen at launch, never the cursor
		if sh.lock != null and sh.lock.alive:
			var lp: Vector2 = sh.lock.pos
			var lv: Vector2 = sh.lock.vel
			sh.tgt = lp + lv * minf(sh.pos.distance_to(lp) / maxf(spd, 1.0), 1.5) * 0.8
		else:
			sh.lock = null
			if sh.t > 0.4 and sh.seek > 0.0:
				sh.scan -= dt
				if sh.scan <= 0.0:
					sh.scan = 0.12
					_seek(sh)
	var to := sh.tgt - sh.pos
	if sh.turn > 0.0 and (sh.lock != null or to.length_squared() > 625.0):
		var lim := sh.turn * dt
		sh.ang += clampf(angle_difference(sh.ang, to.angle()), -lim, lim)
	sh.vel = Vector2.from_angle(sh.ang) * spd

func _seek(sh: Shot) -> void:
	var best: Ship = null
	var bd := sh.seek * sh.seek
	for o in ships:
		if not o.alive or o == sh.src or o.invuln > 0.0:
			continue
		var d2 := sh.pos.distance_squared_to(o.pos)
		if d2 < bd:
			if absf(angle_difference(sh.ang, (o.pos - sh.pos).angle())) < 0.7:
				if sh.src == null or _can_see(sh.src, o):
					bd = d2
					best = o
	if best != null:
		sh.lock = best

func _hit_ship(o: Ship, q: Vector2) -> bool:
	var loc := (q - o.pos).rotated(-o.angle)
	return absf(loc.x) <= o.hl and absf(loc.y) <= o.hw

func _shot_collide(sh: Shot, p0: Vector2) -> bool:
	var kind := sh.kind
	# islands stop everything except missiles, bombs and mines
	if kind != K_MISSILE and kind != K_BOMB and kind != K_MINE:
		var key := Vector2i(floori(sh.pos.x / GRID), floori(sh.pos.y / GRID))
		if island_grid.has(key):
			for k in island_grid[key]:
				var rr: float = island_r[k]
				if sh.pos.distance_squared_to(island_pos[k]) < rr * rr:
					_add_fx(1, sh.pos, 14.0, 0.4)
					return true
	if kind == K_BOMB:
		return false
	if kind == K_MINE:
		if sh.t > 1.5:
			for o in ships:
				if o.alive and o != sh.src and o.invuln <= 0.0 and o.pos.distance_squared_to(sh.pos) < 1764.0:
					_explode_area(sh)
					return true
		return false
	# anti-aircraft fire: hits enemy aircraft and shoots down incoming missiles / rockets / bombs
	if sh.aa and sh.ar > 0.0:
		for a in air_alive:
			if a.owner == sh.src:
				continue
			var ra := sh.ar + 6.0
			if sh.pos.distance_squared_to(a.pos) < ra * ra:
				_damage_air(a, maxf(sh.dmg * 0.8, 2.5), sh.src)
				_add_fx(0, sh.pos, 7.0, 0.2)
				return true
		for ms in missiles:
			if ms.dead or ms.src == sh.src:
				continue
			var rm := sh.ar * 0.7 + 3.0
			if sh.pos.distance_squared_to(ms.pos) < rm * rm:
				ms.hp -= maxf(sh.dmg, 1.5)
				if ms.hp <= 0.0:
					ms.dead = true
					_add_fx(0, ms.pos, 18.0, 0.4)
					_add_fx(7, ms.pos, 40.0, 0.4)
					audio.play("explode_s", ms.pos, -4.0)
				else:
					_add_fx(0, sh.pos, 5.0, 0.15)
				return true
	var mv := sh.pos - p0
	var mvl := mv.length()
	var steps := clampi(int(mvl / 8.0) + 1, 1, 6)
	var cand = ship_grid.get(Vector2i(floori(sh.pos.x / SGRID), floori(sh.pos.y / SGRID)))
	if cand == null:
		return false
	for o in cand:
		if not o.alive or o == sh.src or o.invuln > 0.0:
			continue
		# a dived submarine only fears torpedoes and mines - shells and missiles scream overhead
		if o.dive_t > 0.0 and sh.kind != int(D.KIND["torp"]) and sh.kind != int(D.KIND["mine"]):
			continue
		var reach: float = o.hl + mvl + 10.0
		if o.pos.distance_squared_to(sh.pos) > reach * reach:
			continue
		for st in range(1, steps + 1):
			var q := p0 + mv * (float(st) / float(steps))
			if _hit_ship(o, q):
				_on_hit(sh, o, q)
				return true
	return false

func _on_hit(sh: Shot, o: Ship, q: Vector2) -> void:
	_damage(o, sh.dmg, sh.src)
	_hit_effects(o, sh.dmg, sh.src)
	var size := clampf(sh.spl * 0.9 + 8.0, 8.0, 64.0)
	_add_fx(0, q, size, 0.25 + size * 0.008)
	if sh.kind == K_MISSILE or sh.kind == K_ROCKET:
		_add_fx(7, q, size * 2.6, 0.55, Color(1.0, 0.85, 0.6))
		_add_fx(4, q, size * 0.9, 1.6, Color(0.12, 0.12, 0.12))
	elif sh.kind == K_TORP:
		_add_fx(8, q, 46.0 + sh.spl, 1.0)
		_add_fx(7, q, size * 2.0, 0.6, Color(0.8, 0.9, 1.0))
		audio.play("splash_big", q, -2.0)
	if sh.dmg >= 60.0:
		audio.play("explode_m", q, 0.0)
	elif sh.dmg >= 20.0:
		audio.play("explode_s", q, -2.0)
	elif sh.dmg >= 3.0 or rng.randf() < 0.15:
		audio.play("hit", q, -6.0)
	if sh.spl > 0.0:
		_area_damage(q, sh.spl, sh.dmg * 0.5, sh.src, o, 0.2)

func _explode_area(sh: Shot) -> void:
	var n := _area_damage(sh.pos, sh.spl, sh.dmg, sh.src, null, 0.4)
	if n == 0:
		_add_fx(8, sh.pos, sh.spl * 1.3, 1.0)
		audio.play("splash_big", sh.pos, -2.0)
	else:
		_add_fx(0, sh.pos, sh.spl * 1.1, 0.6)
	_add_fx(7, sh.pos, sh.spl * 2.4, 0.6, Color(1.0, 0.9, 0.7))
	audio.play("explode_m" if sh.dmg >= 60.0 else "explode_s", sh.pos, 0.0)

func _area_damage(p: Vector2, r: float, dmg: float, src: Ship, skip: Ship, min_frac: float) -> int:
	var hits := 0
	for o in ships:
		if not o.alive or o == src or o == skip or o.invuln > 0.0:
			continue
		var edge := maxf(o.pos.distance_to(p) - o.hw, 0.0)
		if edge < r:
			var dd := dmg * lerpf(1.0, min_frac, edge / r)
			_damage(o, dd, src)
			_hit_effects(o, dd, src)
			hits += 1
	return hits

func _shot_expire(sh: Shot) -> void:
	if sh.kind == K_BOMB:
		_explode_area(sh)
	elif sh.kind == K_MINE or sh.kind == K_BULLET:
		return
	elif sh.kind == K_TORP:
		_add_fx(1, sh.pos, 12.0, 0.45)
	else:
		var is_shell := sh.kind == K_SHELL
		_add_fx(1, sh.pos, 16.0 if is_shell else 12.0, 0.55)
		if is_shell:
			# near-miss: a towering water column where the shell splashed down
			_add_fx(8, sh.pos, maxf(24.0, sh.spl * 1.5), 1.25)
		var chance := 0.7 if is_shell else 0.3
		if sh.pos.distance_squared_to(cam.position) < 1500.0 * 1500.0 and rng.randf() < chance:
			audio.play("splash", sh.pos, -3.0 if is_shell else -8.0)

# ---------------- Damage / kills / progression ----------------

func _damage(s: Ship, dmg: float, killer: Ship) -> void:
	if not s.alive or s.invuln > 0.0:
		return
	var dd := dmg
	if s.mark_t > 0.0:
		dd *= 1.25
	s.hp -= dd
	s.flash = 1.0
	if killer != null:
		killer.reveal_t = maxf(killer.reveal_t, 3.0)
		if killer.alive:
			killer.dmg_d += dd
			if killer.is_player:
				battle_dmg += dd
				_mission_bump("dmg", int(dd))
	var by_player := killer != null and killer.is_player
	if S.b("dmgnums") and dd >= 4.0 and (by_player or s.is_player):
		var tc := Color(1.0, 0.5, 0.4) if s.is_player else Color(1.0, 0.95, 0.6)
		_add_text(s.pos + Vector2(rng.randf_range(-12.0, 12.0), -s.hl * 0.3), str(int(dd)), tc)
	if s.is_player:
		shake = maxf(shake, minf(dd * 0.15 + 3.0, 12.0) * S.f("shake"))
		ui.hit_flash(minf(0.55, dd / maxf(s.max_hp, 1.0) * 2.2))
		if s.hp > 0.0 and s.hp < s.max_hp * 0.25 and rng.randf() < 0.25:
			audio.play_ui("alarm", -8.0)
	if s.hp <= 0.0:
		_kill(s, killer)

func _kill(victim: Ship, killer: Ship) -> void:
	victim.alive = false
	victim.speed = 0.0
	var vlen := _len(victim)
	victim.sink_max = 2.0 if vlen < 90.0 else minf(16.0, 9.0 + float(victim.tier) * 1.6)
	victim.sink_list = 0.5 if rng.randf() < 0.5 else -0.5
	victim.sink_t = victim.sink_max
	victim.respawn = victim.sink_max + 2.5
	victim.target = null
	var big := _len(victim)
	_add_fx(0, victim.pos, big * 0.9, 0.9)
	_add_fx(1, victim.pos, big * 0.7, 0.8)
	audio.play("explode_l", victim.pos, 0.0)
	audio.play("sink", victim.pos, -4.0)
	var killer_name := "the sea"
	if killer != null:
		killer_name = killer.nick
		if killer.alive:
			killer.score += 50.0 + victim.score * 0.5
			killer.hp = minf(killer.max_hp, killer.hp + killer.max_hp * 0.08)
			killer.kills += 1
			if killer.is_player:
				var xpg := 25 + victim.tier * 15
				S.d["xp"] = int(S.d.get("xp", 0)) + xpg
				_mission_bump("xp", xpg)
				_gain_bp(xpg)
				battle_kills += 1
				S.d["kills"] = int(S.d.get("kills", 0)) + 1
				_mission_bump("kills", 1)
				if S.b("ranked_mode"):
					S.d["rp"] = maxi(0, int(S.d.get("rp", 0)) + 12 + victim.tier * 3)
				settings_dirty = true
	ui.add_feed("%s sank %s" % [killer_name, victim.nick])
	for i in 4 + victim.tier * 2:
		var c := Crate.new()
		c.pos = victim.pos + Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-60.0, 60.0))
		c.kind = 2 if i % 3 == 0 else (1 if i % 5 == 4 else 0)
		c.temp = true
		c.life = 40.0
		c.phase = rng.randf() * TAU
		crates.append(c)
		_cgrid_add(c)
	if victim.air != null:
		victim.air.alive = false
		victim.air.node.visible = false
		victim.air.shadow.visible = false
	for a in victim.wing:
		a.alive = false
		if a.node != null:
			a.node.visible = false
		if a.shadow != null:
			a.shadow.visible = false
	if victim.air2 != null:
		victim.air2.alive = false
		victim.air2.node.visible = false
		victim.air2.shadow.visible = false
	for a in victim.wing2:
		a.alive = false
		if a.node != null:
			a.node.visible = false
		if a.shadow != null:
			a.shadow.visible = false
	if victim.is_player:
		state = State.DEAD
		shake = 14.0 * S.f("shake")
		ctrl_air = false
		if victim.air != null:
			victim.air.alive = false
			victim.air.node.visible = false
			victim.air.shadow.visible = false
		promo_open = false
		ui.hide_levelup()
		audio.set_engine(false, 0.0)
		audio.set_rotor(false, 0.0)
		if S.b("ranked_mode"):
			S.d["rp"] = maxi(0, int(S.d.get("rp", 0)) - 25)
			settings_dirty = true
		# demotion: the closer you were to the next tier, the smaller the drop
		var prog := D.tier_progress(victim.score, victim.tier)
		var drop := 3 if prog < 0.2 else (2 if prog < 0.6 else 1)
		var nt := maxi(1, victim.tier - drop)
		death_info = {"killer": killer_name, "score": int(victim.score), "kills": victim.kills, "ship": str(victim.def["name"]),
			"from": victim.tier, "to": nt, "progress": prog, "xp": int(S.d.get("xp", 0)), "rp": int(S.d.get("rp", 0))}
		death_pending = true
		death_timer = 1.5

func _check_promotion(s: Ship) -> void:
	if s.tier >= D.MAX_TIER:
		return
	if s.score < float(D.TIER_NEED[s.tier]):
		return
	var nt := s.tier + 1
	if s.is_player:
		battle_promos += 1
		_mission_bump("promo", 1)
		if not promo_open:
			promo_open = true
			ui.show_levelup(nt, D.of_tier(nt))
			ui.toast("Promotion available - choose a ship!")
			audio.play_ui("levelup")
	else:
		var opts := D.of_tier(nt)
		var def: Dictionary = opts[rng.randi() % opts.size()]
		_apply_def(s, def, maxf(s.hp / s.max_hp, 0.6))
		_add_fx(3, s.pos, s.hl * 1.6, 0.6, Color(0.5, 0.85, 1.0))

func _player_paint() -> Color:
	var pk := str(S.d.get("paint", "navy"))
	if D.PAINTS.has(pk):
		return D.PAINTS[pk]["c"]
	return Color(0.30, 0.65, 1.0)

func _gain_bp(xp_amount: int) -> void:
	S.d["bp"] = int(S.d.get("bp", 0)) + maxi(1, xp_amount / 25)

func _mission_bump(key: String, amt: int) -> void:
	_ensure_missions()
	var k := "m_" + key
	S.d[k] = int(S.d.get(k, 0)) + amt
	settings_dirty = true

func _mission_day() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)

func _ensure_missions() -> void:
	var day := _mission_day()
	if int(S.d.get("m_day", 0)) != day:
		S.d["m_day"] = day
		S.d["m_gift"] = 0
		S.d["m_kills"] = 0
		S.d["m_dmg"] = 0
		S.d["m_xp"] = 0
		S.d["m_crates"] = 0
		settings_dirty = true

func get_missions() -> Array:
	_ensure_missions()
	var day := _mission_day()
	var out: Array = []
	for i in 3:
		var mi := (day * 7 + i * 2) % D.BP_MISSIONS.size()
		var m: Dictionary = D.BP_MISSIONS[mi]
		var diff := mini(2, (day + i) % 3)
		var tgt := int(m["t"][diff])
		var bit := 1 << (diff * 4 + i)
		var have := int(S.d.get("m_" + str(m["k"]), 0))
		out.append({"n": str(m["n"]) % tgt, "k": str(m["k"]), "have": have, "need": tgt, "reward": int(m["r"]), "done": have >= tgt, "claimed": (int(S.d.get("m_gift", 0)) & bit) != 0, "slot_bit": bit})
	return out

func claim_mission(slot_bit: int, reward: int) -> void:
	if (int(S.d.get("m_gift", 0)) & slot_bit) != 0:
		return
	S.d["m_gift"] = int(S.d.get("m_gift", 0)) | slot_bit
	S.d["bp"] = int(S.d.get("bp", 0)) + reward
	settings_dirty = true
	audio.play_ui("pickup", -4.0)

func request_exit() -> void:
	in_battle = false
	ui.in_battle = false
	if state == State.MENU:
		return
	var xpn := int(S.d.get("xp", 0))
	var rpn := int(S.d.get("rp", 0))
	var bpn := int(S.d.get("bp", 0))
	var meta1 := D.level_progress(xpn)
	var res := {
		"kills": battle_kills,
		"dmg": int(battle_dmg),
		"score": int(player.score),
		"time": int(battle_time),
		"xp0": battle_xp0, "xp1": xpn,
		"rp0": battle_rp0, "rp1": rpn,
		"bp0": battle_bp0, "bp": maxi(0, bpn - battle_bp0),
		"lvl0": int(D.level_progress(battle_xp0)["lvl"]), "lvl1": int(meta1["lvl"]),
		"xp_have": int(meta1["have"]), "xp_need": int(meta1["need"]),
		"ri0": D.rank_i_from_rp(battle_rp0), "ri1": D.rank_i_from_rp(rpn),
		"ranked": S.b("ranked_mode"),
		"promos": battle_promos,
	}
	S.d["best"] = maxi(int(S.d.get("best", 0)), int(player.score))
	if player.alive:
		player.alive = false
		player.sink_t = 0.0
		player.respawn = 0.0
		if player.air != null:
			player.air.alive = false
			if player.air.node != null:
				player.air.node.visible = false
			if player.air.shadow != null:
				player.air.shadow.visible = false
		for a2 in player.wing:
			a2.alive = false
			if a2.node != null:
				a2.node.visible = false
	promo_open = false
	death_pending = false
	ctrl_air = false
	state = State.MENU
	audio.set_engine(false, 0.0)
	audio.set_rotor(false, 0.0)
	S.season_check()
	S.store_account()
	S.save_file()
	ui.show_battle_results(res)

func _damage_air(a: Air, dmg: float, attacker = null) -> void:
	if not a.alive:
		return
	a.hp -= dmg
	if a.hp > 0.0:
		return
	a.alive = false
	a.cd = float(a.d["cd"])
	a.node.visible = false
	a.shadow.visible = false
	_add_fx(0, a.pos, 26.0, 0.5)
	_add_fx(4, a.pos, 20.0, 1.4, Color(0.12, 0.12, 0.12))
	audio.play("explode_s", a.pos, -2.0)
	var own = a.owner
	if own != null and own.is_player:
		if a == own.air:
			if ctrl_air:
				ctrl_air = false
				ui.toast("Aircraft shot down!")
				_refresh_loadout()
			else:
				ui.toast("Aircraft lost")
		elif a == own.air2 or a in own.wing2:
			ui.toast("Support squadron lost")
		else:
			ui.toast("Wingman lost")
	if attacker != null and attacker.is_player:
		ui.toast("Aircraft shot down")

# ---------------- Ship stepping ----------------

func _step_ship(s: Ship, dt: float) -> void:
	var d := s.def
	_tick_weapons(s, dt)
	s.flash = maxf(0.0, s.flash - dt * 5.0)
	s.invuln = maxf(0.0, s.invuln - dt)
	s.reveal_t = maxf(0.0, s.reveal_t - dt)
	s.mark_t = maxf(0.0, s.mark_t - dt)
	s.boost_t = maxf(0.0, s.boost_t - dt)
	s.repair_t = maxf(0.0, s.repair_t - dt)
	s.smoke_t = maxf(0.0, s.smoke_t - dt)
	s.radar_t = maxf(0.0, s.radar_t - dt)
	s.dive_t = maxf(0.0, s.dive_t - dt)
	s.mine_t = maxf(0.0, s.mine_t - dt)
	s.barrage_t = maxf(0.0, s.barrage_t - dt)
	for i in s.ab_cd.size():
		s.ab_cd[i] = maxf(0.0, s.ab_cd[i] - dt)
	var boost := s.boost_t > 0.0
	var target_speed := s.throttle * float(d["spd"]) * (1.45 if boost else 1.0)
	if s.flood_t > 0.0:
		target_speed *= 0.7
	if s.dive_t > 0.0:
		target_speed *= 1.25
	var gkey := Vector2i(floori(s.pos.x / GRID), floori(s.pos.y / GRID))
	if reef_grid.has(gkey):
		for i in reef_grid[gkey]:
			var rr: float = reef_r[i]
			if s.pos.distance_squared_to(reef_pos[i]) < rr * rr:
				target_speed *= 0.6
				break
	var acc := (90.0 - 7.0 * float(s.tier)) * (2.0 if boost else 1.0)
	s.speed = move_toward(s.speed, target_speed, acc * dt)
	s.vel = Vector2.from_angle(s.angle) * s.speed
	s.pos += s.vel * dt
	if s.dive_t > 0.0:
		s.throttle = clampf(s.throttle, -0.7, 0.7)
		# periscope wake + escaping air bubbles while running submerged
		if fmod(time, 0.55) < dt:
			_add_fx(3, s.pos + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0)), 7.0, 0.5, Color(0.8, 0.95, 1.0, 0.7))
	var rad := s.hl * 0.6 + 4.0
	var gkey2 := Vector2i(floori(s.pos.x / GRID), floori(s.pos.y / GRID))
	if island_grid.has(gkey2):
		for i in island_grid[gkey2]:
			var dv: Vector2 = s.pos - island_pos[i]
			var min_d: float = island_r[i] * 1.02 + rad
			var d2 := dv.length_squared()
			if d2 < min_d * min_d:
				var dl := maxf(sqrt(d2), 0.001)
				s.pos = island_pos[i] + dv / dl * min_d
				s.speed *= maxf(0.0, 1.0 - 6.0 * dt)
	if s.repair_t > 0.0:
		s.hp = minf(s.max_hp, s.hp + s.max_hp * 0.30 / 6.0 * dt)
	# fire and flooding keep hurting until they burn out or damage control deals with them
	var near_cam := s.pos.distance_squared_to(cam.position) < 2200.0 * 2200.0
	s.fx_t -= dt
	if s.fire_t > 0.0:
		s.fire_t = maxf(0.0, s.fire_t - dt)
		_dot(s, s.max_hp * 0.006 * dt)
		if not s.alive:
			return
		if s.fx_t <= 0.0 and near_cam:
			var fp := s.pos + s.fire_pt.rotated(s.angle)
			_add_fx(9, fp + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)), rng.randf_range(4.0, 8.0), 0.5)
			_add_fx(4, fp, 10.0, 1.6, Color(0.1, 0.1, 0.1))
	if s.flood_t > 0.0:
		s.flood_t = maxf(0.0, s.flood_t - dt)
		_dot(s, s.max_hp * 0.003 * dt)
		if not s.alive:
			return
		if s.fx_t <= 0.0 and near_cam:
			_add_fx(1, s.pos + Vector2(rng.randf_range(-0.4, 0.4) * _len(s), 0.0).rotated(s.angle) + Vector2.from_angle(s.angle + PI * 0.5) * float(d["wid"]) * 0.6 * (1.0 if rng.randf() < 0.5 else -1.0), 9.0, 0.6)
	if s.fx_t <= 0.0:
		s.fx_t = 0.1
	_step_border(s, dt)
	if not s.alive:
		return
	_step_ram(s, dt)
	if not s.alive:
		return
	_auto_sec_aim(s, dt)
	_update_mounts(s, dt)
	if s.has_pd and (not s.is_player or ctrl_air):
		_step_pd(s, dt)
	_check_promotion(s)
	if s.hp < s.max_hp * 0.4:
		s.fire_emit -= dt
		if s.fire_emit <= 0.0:
			s.fire_emit = 0.22 if s.hp < s.max_hp * 0.2 else 0.4
			if near_cam:
				_add_fx(4, s.pos + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * s.hl * 0.3, 14.0 + s.hl * 0.1, 1.4, Color(0.15, 0.15, 0.15))
	if s.smoke_t > 0.0:
		s.smoke_emit -= dt
		if s.smoke_emit <= 0.0:
			s.smoke_emit = 0.14
			_add_fx(4, s.pos - Vector2.from_angle(s.angle) * s.hl * 0.8, 38.0, 4.0, Color(0.78, 0.80, 0.82))
	if S.b("autossec") or not s.is_player:
		_auto_sec_fire(s)

# ---------------- Aircraft stepping ----------------

func _air_ready(a: Air, kind: int) -> bool:
	for w in a.weapons:
		if w.kind == kind and not w.d.has("special"):
			for k in w.total:
				if w.cd[k] <= 0.0:
					return true
	return false

func _step_air(s: Ship, dt: float) -> void:
	_step_air_unit(s, s.air, dt, false)
	_step_squad(s, s.wing, s.air, dt)
	_step_air_unit(s, s.air2, dt, true)
	_step_squad(s, s.wing2, s.air2, dt)

func _step_air_unit(s: Ship, a: Air, dt: float, ai_only: bool) -> void:
	if a == null:
		return
	_tick_air_weapons(a, dt)
	if not a.alive:
		a.cd -= dt
		if a.cd <= 0.0 and s.alive:
			a.alive = true
			a.hp = float(a.d["hp"])
			a.pos = s.pos
			a.angle = s.angle
			a.spd = float(a.d["spd"]) * 0.5
			a.vel = Vector2.ZERO
			a.mode = 0
			a.node.visible = true
			a.shadow.visible = true
			if s.is_player and a == s.air:
				ui.toast("Aircraft ready - press V")
		return
	var d := a.d
	var spd := float(d["spd"])
	var turn := float(d["turn"])
	var heli := str(d["kind"]) == "heli"
	var to_ship := s.pos - a.pos
	var dist := to_ship.length()
	a.warn = false
	a.mark_cd = maxf(0.0, a.mark_cd - dt)
	a.mode_t = maxf(0.0, a.mode_t - dt)
	if s.is_player and ctrl_air and not ai_only:
		var steer := 0.0
		if _k_left():
			steer -= 1.0
		if _k_right():
			steer += 1.0
		var dthr := 0.0
		if _k_up():
			dthr += 1.0
		if _k_down():
			dthr -= 1.0
		if heli:
			a.ctrl_thr = clampf(a.ctrl_thr + dthr * dt * 1.2, -0.3, 1.0)
		else:
			a.ctrl_thr = clampf(a.ctrl_thr + dthr * dt, 0.45, 1.0)
		a.angle += steer * turn * dt
		a.spd = move_toward(a.spd, a.ctrl_thr * spd, spd * dt * 1.2)
		if dist > float(d["leash"]):
			a.warn = true
			a.angle += clampf(angle_difference(a.angle, to_ship.angle()), -1.0, 1.0) * turn * dt * 1.6
		a.vel = Vector2.from_angle(a.angle) * a.spd
	else:
		# uncontrolled aircraft keep station near the ship but hunt on their own
		_air_ai(s, a, dt)
	a.pos += a.vel * dt
	a.pos = _zone_clamp(a.pos, -140.0)
	var show := s.is_player or s.seen or not S.b("fog")
	a.node.visible = show
	a.shadow.visible = show
	a.node.position = a.pos
	a.node.rotation = a.angle
	a.shadow.position = a.pos + Vector2(9.0, 14.0)
	a.shadow.rotation = a.angle
	if a.rotor != null:
		a.rotor.rotation += dt * (35.0 if heli else 70.0)
	if s.is_player and not (ctrl_air and a == s.air):
		_auto_air_fire(s, a, dt)

# wingmen hold a V-formation on the leader and shoot on their own
func _step_squad(s: Ship, wing: Array, lead: Air, dt: float) -> void:
	for i in wing.size():
		var a: Air = wing[i]
		if not a.alive:
			a.cd -= dt
			if a.cd <= 0.0 and s.alive and lead != null and lead.alive:
				a.alive = true
				a.hp = float(a.d["hp"])
				a.pos = s.pos
				a.angle = s.angle
				a.spd = float(a.d["spd"]) * 0.5
				a.vel = Vector2.ZERO
				if a.node != null:
					a.node.visible = true
				if a.shadow != null:
					a.shadow.visible = true
			continue
		_tick_air_weapons(a, dt)
		var anchor: Vector2 = s.pos
		var face_ang: float = s.angle
		if lead != null and lead.alive:
			anchor = lead.pos
			face_ang = lead.angle
		var rank := float(i / 2 + 1)
		var side := -1.0 if i % 2 == 0 else 1.0
		var off := Vector2.from_angle(face_ang + PI) * (55.0 + 32.0 * rank) + Vector2.from_angle(face_ang + PI * 0.5) * (46.0 + 24.0 * rank) * side
		var tp := anchor + off
		var dv := tp - a.pos
		var dl := dv.length()
		var spd := float(a.d["spd"])
		var turn := float(a.d["turn"])
		var face := dv.angle() if dl > 40.0 else face_ang
		a.angle += clampf(angle_difference(a.angle, face), -1.0, 1.0) * turn * dt
		var want := clampf(dl * 2.2, spd * 0.4, spd)
		a.spd = move_toward(a.spd, want, spd * dt)
		a.vel = Vector2.from_angle(a.angle) * a.spd
		a.pos += a.vel * dt
		a.pos = _zone_clamp(a.pos, -140.0)
		_auto_air_fire(s, a, dt)
		var heli := str(a.d["kind"]) == "heli"
		var show := s.is_player or s.seen or not S.b("fog")
		a.node.visible = show
		a.shadow.visible = show
		a.node.position = a.pos
		a.node.rotation = a.angle
		a.shadow.position = a.pos + Vector2(9.0, 14.0)
		a.shadow.rotation = a.angle
		if a.rotor != null:
			a.rotor.rotation += dt * (35.0 if heli else 70.0)

# idle aircraft orbiting their ship still defend it: shoot at whatever comes close
func _auto_air_fire(s: Ship, a: Air, dt: float) -> void:
	var vis := float(a.d["vis"])
	var best: Ship = null
	var bd := vis * vis
	for o in ships:
		if not o.alive or o == s or o.invuln > 0.0:
			continue
		var d2 := a.pos.distance_squared_to(o.pos)
		if d2 < bd and _can_see(s, o):
			bd = d2
			best = o
	if best == null:
		return
	var lead := best.pos + best.vel * 0.4
	a.aimpt = lead
	var dist := a.pos.distance_to(lead)
	for wi in a.weapons.size():
		var w: WRT = a.weapons[wi]
		if w.d.has("special"):
			continue
		var ready := false
		for k in w.total:
			if w.cd[k] <= 0.0:
				ready = true
				break
		if not ready:
			continue
		var rng_w := float(w.d["rng"])
		if w.kind == K_TORP:
			if dist < 320.0:
				_air_fire(s, a, wi)
		elif w.kind == K_BOMB:
			if dist < 110.0:
				_air_fire(s, a, wi)
		elif dist < rng_w * 0.9:
			_air_fire(s, a, wi)

# uncontrolled aircraft pick their own mark: nearest enemy the PILOT can see, inside the leash
func _air_pick_target(s: Ship, a: Air, leash: float) -> Ship:
	var vis := float(a.d["vis"])
	var best: Ship = null
	var bd := leash * leash
	for o in ships:
		if not o.alive or o == s or o.invuln > 0.0 or o.dive_t > 0.0:
			continue
		var d2 := a.pos.distance_squared_to(o.pos)
		if d2 >= bd:
			continue
		var f := o.stealth
		if o.mark_t > 0.0 or s.radar_t > 0.0 or o.reveal_t > 0.0:
			f = 1.0
		elif o.smoke_t > 0.0:
			f *= 0.3
		var r := vis * f
		if not s.is_player:
			r *= bot_det
		if d2 < r * r:
			bd = d2
			best = o
	return best

func _air_has_shot(a: Air) -> bool:
	for w in a.weapons:
		if w.d.has("special"):
			continue
		for k in w.total:
			if w.cd[k] <= 0.0:
				return true
	return false

# enemy aircraft: scouts mark targets, helicopters hover and shoot, bombers make attack runs
func _air_ai(s: Ship, a: Air, dt: float) -> void:
	var d := a.d
	var spd := float(d["spd"])
	var turn := float(d["turn"])
	var heli := str(d["kind"]) == "heli"
	var role := a.id
	var leash := float(d["leash"])
	var tgt: Ship = null
	if s.target != null and s.target.alive and s.target.pos.distance_squared_to(s.pos) < leash * leash:
		tgt = s.target
	if tgt == null:
		# autonomous hunting: remember our own mark and pick the nearest one the crew can spot
		if a.target != null and (not a.target.alive or a.target.dive_t > 0.0 or a.target.pos.distance_squared_to(s.pos) > leash * leash):
			a.target = null
		if a.target == null:
			a.target = _air_pick_target(s, a, leash)
		if a.target != null and a.target.alive:
			tgt = a.target
	var attacker := role in ["dive_bomber", "torp_bomber", "patrol_seaplane", "jet_strike", "jet_bomber", "heli_attack", "heli_asw", "heli_heavy", "floatplane"]
	var scout := role in ["uav", "heli_scout", "heli_l", "floatplane", "patrol_seaplane"]
	var vis := float(d["vis"])
	if scout and tgt != null and a.mark_cd <= 0.0 and a.pos.distance_squared_to(tgt.pos) < vis * vis:
		tgt.mark_t = 10.0
		a.mark_cd = 20.0
	var to_ship := s.pos - a.pos
	var back := to_ship.length() > leash * 0.9
	if heli:
		var tp := s.pos + Vector2.from_angle(s.angle + 2.3) * (s.hl + 60.0)
		var face := s.angle
		var engage := attacker and tgt != null and not back
		if engage:
			var dirt := tgt.pos - a.pos
			var hold := 300.0 if role == "heli_attack" else 430.0
			tp = tgt.pos - dirt.normalized() * hold
			face = dirt.angle()
			a.aimpt = tgt.pos + tgt.vel * 0.35
			if absf(angle_difference(a.angle, face)) < 0.35:
				for wi in a.weapons.size():
					var w: WRT = a.weapons[wi]
					if not w.d.has("special") and dirt.length() < float(w.d["rng"]) * 0.9:
						_air_fire(s, a, wi)
		var dv := tp - a.pos
		var dl := dv.length()
		if not engage and dl > 25.0:
			face = dv.angle()
		a.angle += clampf(angle_difference(a.angle, face), -1.0, 1.0) * turn * dt * 1.5
		a.spd = move_toward(a.spd, clampf(dl * 1.6, 0.0, spd), spd * dt * 1.5)
		a.vel = dv / maxf(dl, 0.001) * a.spd
		return
	var desired := a.angle
	var spd_t := spd * 0.8
	if a.mode == 0:
		var around := (a.pos - s.pos).angle()
		var tp2 := s.pos + Vector2.from_angle(around + 0.55 * a.orbit) * 220.0
		desired = (tp2 - a.pos).angle()
		if back:
			desired = to_ship.angle()
		if attacker and tgt != null and not back and a.mode_t <= 0.0 and _air_has_shot(a):
			a.mode = 1
	elif a.mode == 1:
		if tgt == null or back:
			a.mode = 0
			a.mode_t = 3.0
		else:
			var lead := tgt.pos + tgt.vel * 0.5
			var dirt2 := lead - a.pos
			var dl2 := dirt2.length()
			desired = dirt2.angle()
			spd_t = spd * 0.95
			a.aimpt = lead
			if absf(angle_difference(a.angle, desired)) < 0.5:
				for wi2 in a.weapons.size():
					var w2: WRT = a.weapons[wi2]
					if w2.d.has("special"):
						continue
					if w2.kind == K_BULLET and dl2 < 380.0:
						_air_fire(s, a, wi2)
					elif w2.kind == K_TORP and dl2 < 340.0:
						_air_fire(s, a, wi2)
					elif w2.kind == K_BOMB and dl2 < 150.0:
						_air_fire(s, a, wi2)
					elif w2.kind == K_MISSILE and dl2 < float(w2.d["rng"]) * 0.8:
						_air_fire(s, a, wi2)
					elif w2.kind == K_ROCKET and dl2 < 480.0:
						_air_fire(s, a, wi2)
			if dl2 < 60.0:
				a.mode = 2
				a.mode_t = 1.8
	else:
		spd_t = spd
		if a.mode_t <= 0.0:
			a.mode = 0
			a.mode_t = 4.0
	a.angle += clampf(angle_difference(a.angle, desired), -1.0, 1.0) * turn * dt * 1.4
	a.spd = move_toward(a.spd, spd_t, spd * dt)
	a.vel = Vector2.from_angle(a.angle) * a.spd

# ---------------- Bots ----------------

func _lead_point(s: Ship, t: Ship, spd: float) -> Vector2:
	var dvec := t.pos - s.pos
	var tt := dvec.length() / maxf(spd, 60.0)
	var p := t.pos + t.vel * tt * 0.9
	return s.pos + (p - s.pos).rotated(s.aim_err)

func _bot_update(s: Ship, dt: float) -> void:
	s.think_t -= dt
	s.fire_delay = maxf(0.0, s.fire_delay - dt)
	s.wsel_t = maxf(0.0, s.wsel_t - dt)
	s.last_seen_t += dt
	if s.think_t <= 0.0:
		s.think_t = rng.randf_range(0.15, 0.30)
		_bot_think(s)
	var turn := float(s.def["turn"])
	s.angle += clampf(angle_difference(s.angle, s.desired), -1.0, 1.0) * turn * dt
	var t: Ship = null
	if s.target != null and s.target.alive:
		t = s.target
	var air_ok: bool = s.aa_mode and s.air_threat != null and s.air_threat.alive
	# like a human player the AI uses ONE selected weapon at a time (so only that weapon aims)
	if s.wsel < s.weapons.size():
		var w: WRT = s.weapons[s.wsel]
		if air_ok and bool(w.d.get("aa", false)):
			var ap: Vector2 = s.air_threat.pos
			var av: Vector2 = s.air_threat.vel
			w.aimpt = ap + av * 0.25
		elif t != null:
			w.aimpt = _lead_point(s, t, float(w.d["spd"]))
		else:
			w.aimpt = s.pos + Vector2.from_angle(s.angle) * 300.0
		if s.fire_ok and s.fire_delay <= 0.0:
			s.cursor = w.aimpt
			_try_fire(s, w)

func _ready_count(w: WRT) -> int:
	var n := 0
	for k in w.total:
		if w.cd[k] <= 0.0:
			n += 1
	return n

func _bot_weapon_ok(s: Ship, wi: int, dist: float) -> bool:
	if wi < 0 or wi >= s.weapons.size():
		return false
	var w: WRT = s.weapons[wi]
	if str(w.d["vis"]) == "mine" or w.d.has("special"):
		return false
	return dist <= float(w.d["rng"]) * 0.92 and _ready_count(w) > 0

func _bot_pick_weapon(s: Ship, dist: float) -> int:
	var bi := -1
	var bs := -1.0
	for pass_no in 2:
		for wi in s.weapons.size():
			if not _bot_weapon_ok(s, wi, dist):
				continue
			var w: WRT = s.weapons[wi]
			var wd := w.d
			# first pass: real anti-ship weapons only; small AA guns are the fallback
			if pass_no == 0 and float(wd["dmg"]) < 6.0 and w.kind == K_BULLET:
				continue
			var sc := float(wd["dmg"]) * float(wd.get("sal", 1)) * (1.0 + 0.1 * float(_ready_count(w)))
			if w.kind == K_TORP and (dist < 250.0 or dist > float(wd["rng"]) * 0.75):
				sc *= 0.4
			if w.kind == K_MISSILE and dist < 450.0:
				sc *= 0.5
			if sc > bs:
				bs = sc
				bi = wi
		if bi >= 0:
			return bi
	return bi

func _bot_pick_aa(s: Ship, dist: float) -> int:
	var bi := -1
	var bs := -1.0
	for wi in s.weapons.size():
		var w: WRT = s.weapons[wi]
		if not bool(w.d.get("aa", false)) or _ready_count(w) == 0:
			continue
		if dist > maxf(float(w.d["rng"]) * 0.95, 200.0):
			continue
		var sc := float(w.d["dmg"]) / maxf(float(w.d["gap"]), 0.03)
		if sc > bs:
			bs = sc
			bi = wi
	return bi

func _bot_think(s: Ship) -> void:
	s.aim_err = rng.randf_range(-bot_err, bot_err)
	var captain := s.is_player
	var best: Ship = null
	var bd2 := INF
	var flee_vec := Vector2.ZERO
	var danger := s.hp < s.max_hp * 0.35
	var seen_n := 0
	for o in ships:
		if o == s or not o.alive or o.invuln > 0.0:
			continue
		if not _can_see(s, o):
			continue
		seen_n += 1
		var dv := o.pos - s.pos
		var dl := maxf(dv.length(), 120.0)
		var stronger := o.tier >= s.tier + 2
		if (captain or stronger or danger) and dl < 2800.0:
			flee_vec -= dv / dl * (900.0 / dl) * clampf(1.0 + 0.4 * float(o.tier - s.tier), 0.5, 3.0)
		if stronger and not captain:
			continue
		if dv.length_squared() < bd2:
			bd2 = dv.length_squared()
			best = o
	var prev := s.target
	s.target = best
	if best != null:
		s.last_seen_pos = best.pos
		s.last_seen_t = 0.0
		if prev != best:
			s.fire_delay = maxf(s.fire_delay, rng.randf_range(0.5, 1.4) * (1.5 - 0.5 * float(S.i("difficulty"))))
	# ---- weapon choice (anti-aircraft when aircraft are close, otherwise anti-ship)
	s.fire_ok = false
	s.aa_mode = false
	s.air_threat = null
	var best_air = null
	var bad := 700.0 * 700.0
	for a in air_alive:
		if a.owner == s:
			continue
		var d2a := s.pos.distance_squared_to(a.pos)
		if d2a < bad:
			bad = d2a
			best_air = a
	if best_air != null and (best == null or bad < 450.0 * 450.0):
		var wa := _bot_pick_aa(s, sqrt(bad))
		if wa >= 0:
			s.air_threat = best_air
			s.aa_mode = true
			s.wsel = wa
			s.fire_ok = true
	var bdist := sqrt(bd2)
	if not s.aa_mode and best != null:
		if not _bot_weapon_ok(s, s.wsel, bdist) or s.wsel_t <= 0.0:
			var wi2 := _bot_pick_weapon(s, bdist)
			if wi2 >= 0 and wi2 != s.wsel:
				s.wsel = wi2
				s.fire_delay = maxf(s.fire_delay, 0.45)
			s.wsel_t = 1.2
		s.fire_ok = _bot_weapon_ok(s, s.wsel, bdist)
	# ---- movement: engage at a sensible range, kite, or run
	var desired := s.angle
	var thr := 0.7
	var main_rng := 600.0
	if s.weapons.size() > 0:
		main_rng = float(s.weapons[0].d["rng"])
	var ideal := clampf(main_rng * 0.65, 250.0, 900.0)
	var fleeing := flee_vec.length() > 0.05
	s.flee = fleeing
	if fleeing:
		desired = flee_vec.angle()
		thr = 1.0
	elif best != null:
		var to_t := (best.pos - s.pos).angle()
		if bdist > ideal * 1.1:
			desired = (_lead_point(s, best, 300.0) - s.pos).angle()
			thr = 0.9
		elif bdist < ideal * 0.5:
			desired = to_t + PI + s.side * 0.5
			thr = 0.9
		else:
			desired = to_t + s.side * PI * 0.5
			thr = 0.6
	elif s.last_seen_t < 5.0 and not captain:
		desired = (s.last_seen_pos - s.pos).angle()
		thr = 0.8
	elif captain:
		thr = 0.35
	else:
		if time >= s.wander_until:
			s.wander_until = time + rng.randf_range(2.0, 5.0)
			var cp: Crate = null
			var cd2 := 1.0e12
			var cc0 := _cell(s.pos)
			for gx in range(cc0.x - 2, cc0.x + 3):
				for gy in range(cc0.y - 2, cc0.y + 3):
					var lst = crate_grid.get(Vector2i(gx, gy))
					if lst == null:
						continue
					for cr in lst:
						var d3 := s.pos.distance_squared_to(cr.pos)
						if d3 < cd2:
							cd2 = d3
							cp = cr
			s.desired = (cp.pos - s.pos).angle() if cp != null else rng.randf() * TAU
		desired = s.desired
		thr = 0.6
	s.throttle = thr
	# ---- abilities
	var hpr := s.hp / s.max_hp
	var incoming := false
	for ms in missiles:
		if ms.src != s and ms.kind == K_MISSILE and ms.pos.distance_squared_to(s.pos) < 600.0 * 600.0:
			incoming = true
			break
	var abl: Array = s.def["abil"]
	for ai in abl.size():
		if s.ab_cd[ai] > 0.0:
			continue
		match str(abl[ai]):
			"repair":
				if hpr < 0.5 or s.fire_t > 0.0 or s.flood_t > 0.0:
					_use_ability(s, ai)
			"boost":
				if (fleeing and seen_n > 0) or (best != null and bd2 < 400.0 * 400.0 and rng.randf() < 0.1):
					_use_ability(s, ai)
			"smoke":
				if (fleeing or danger) and seen_n > 0 and hpr < 0.75:
					_use_ability(s, ai)
			"barrage":
				if s.fire_ok and rng.randf() < 0.2:
					_use_ability(s, ai)
			"chaff":
				if incoming:
					_use_ability(s, ai)
			"dive":
				if hpr < 0.4 or incoming:
					_use_ability(s, ai)
	# ---- avoid islands and the world edge
	for i in island_pos.size():
		var dd: Vector2 = island_pos[i] - s.pos
		var lim2: float = island_r[i] + 200.0 + s.hl
		if dd.length_squared() < lim2 * lim2:
			var df := angle_difference(s.angle, dd.angle())
			if absf(df) < 1.2:
				var side := 1.0 if df < 0.0 else -1.0
				desired = dd.angle() + side * PI * 0.5
	if s.pos.length() > _zone_radius_at(s.pos) - 220.0:
		desired = (-s.pos).angle()
	s.desired = desired

# ---------------- Crates / effects ----------------

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CGRID), floori(p.y / CGRID))

func _cgrid_add(c: Crate) -> void:
	var k := _cell(c.pos)
	if crate_grid.has(k):
		crate_grid[k].append(c)
	else:
		crate_grid[k] = [c]

func _cgrid_move(c: Crate) -> void:
	if _cell(c.pos) == c.cell:
		return
	var lst = crate_grid.get(c.cell)
	if lst != null:
		lst.erase(c)
	_cgrid_add(c)
	c.cell = _cell(c.pos)

func _step_crates(dt: float) -> void:
	var i := crates.size() - 1
	while i >= 0:
		var cr: Crate = crates[i]
		if cr.temp:
			cr.life -= dt
			if cr.life <= 0.0:
				var lk = crate_grid.get(_cell(cr.pos))
				if lk != null:
					lk.erase(cr)
				crates.remove_at(i)
		i -= 1
	for s in ships:
		if not s.alive:
			continue
		var rr := s.hl + 9.0
		# supply magnet: bigger hulls pull floating supplies from further away
		var mag := 46.0 + s.hl * 1.9
		var c0 := _cell(s.pos)
		for gx in range(c0.x - 1, c0.x + 2):
			for gy in range(c0.y - 1, c0.y + 2):
				var lst = crate_grid.get(Vector2i(gx, gy))
				if lst == null:
					continue
				var j: int = lst.size() - 1
				while j >= 0:
					var cc: Crate = lst[j]
					j -= 1
					var dd := s.pos.distance_to(cc.pos)
					if dd >= mag:
						continue
					if dd >= rr:
						cc.pos += (s.pos - cc.pos).normalized() * (40.0 + s.hl * 0.5) * dt
						_cgrid_move(cc)
						continue
					var mul := 1.0 + 0.3 * float(s.tier - 1)
					match cc.kind:
						0:
							s.score += 7.0 * mul
						1:
							s.hp = minf(s.max_hp, s.hp + maxf(30.0, s.max_hp * 0.10))
						2:
							s.score += 18.0 * mul
					_add_fx(3, cc.pos, 16.0, 0.35, CRATE_COLORS[cc.kind])
					if s.is_player:
						audio.play_ui("pickup", -8.0)
						_mission_bump("crates", 1)
					lst.erase(cc)
					if cc.temp:
						crates.erase(cc)
					else:
						cc.pos = Vector2.ZERO
						var hot := rng.randf() < 0.45 and not wreck_pos.is_empty()
						if hot:
							var wr2 := wreck_pos[rng.randi() % wreck_pos.size()]
							cc.pos = wr2 + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 240.0)
						else:
							cc.pos = _free_pos()
						cc.kind = rng.randi_range(0, 2)
						cc.cell = _cell(cc.pos)
						_cgrid_add(cc)

func _add_fx(kind: int, p: Vector2, size: float, dur: float, col: Color = Color(1, 1, 1), ang: float = 0.0) -> Fx:
	if fxs.size() > _fx_cap():
		return null
	var f := Fx.new()
	f.kind = kind
	f.pos = p
	f.size = size
	f.dur = dur
	f.col = col
	f.ang = ang
	f.sd = rng.randf() * TAU
	fxs.append(f)
	return f

func _add_text(p: Vector2, text: String, col: Color) -> void:
	var f := _add_fx(6, p, 0.0, 0.9, col)
	if f != null:
		f.txt = text

func _step_fx(dt: float) -> void:
	var i := fxs.size() - 1
	while i >= 0:
		var f: Fx = fxs[i]
		f.age += dt
		if f.age >= f.dur:
			fxs.remove_at(i)
		i -= 1

# ---------------- Frame update ----------------

var in_battle := false
var battle_xp0 := 0
var battle_rp0 := 0
var battle_bp0 := 0
var battle_kills := 0
var battle_dmg := 0.0
var battle_time := 0.0
var battle_promos := 0
var settings_dirty := false
var save_timer := 0.0

func _process(delta: float) -> void:
	var dt := minf(delta, MAX_DT)
	time += dt
	vp_size = get_viewport_rect().size
	_player_input(dt)
	air_alive.clear()
	for s in ships:
		if s.air != null and s.air.alive:
			air_alive.append(s.air)
		for w1 in s.wing:
			if w1.alive:
				air_alive.append(w1)
		if s.air2 != null and s.air2.alive:
			air_alive.append(s.air2)
		for w2 in s.wing2:
			if w2.alive:
				air_alive.append(w2)
	missiles.clear()
	for sh in shots:
		if (sh.kind == K_MISSILE or sh.kind == K_ROCKET or sh.kind == K_BOMB) and not sh.dead:
			missiles.append(sh)
	var marked := false
	var t0 := Time.get_ticks_usec()
	for s in ships:
		if s.alive:
			var sdt := dt
			# distant AI ships that are just cruising are simulated every 4th frame (4x the time step)
			if not s.is_player and s.target == null and not s.fire_ok and s.pos.distance_squared_to(cam.position) > 3600.0 * 3600.0:
				s.lod_dt += dt
				s.lod_n = (s.lod_n + 1) % 4
				if s.lod_n != 0:
					continue
				sdt = s.lod_dt
				s.lod_dt = 0.0
			else:
				s.lod_dt = 0.0
			if not s.is_player or ctrl_air:
				_bot_update(s, sdt)
			_step_ship(s, sdt)
			if s.alive and (s.air != null or s.air2 != null or s.wing.size() > 0 or s.wing2.size() > 0):
				_step_air(s, sdt)
			if s.mark_t > 0.0:
				marked = true
		else:
			if s.sink_t > 0.0:
				s.sink_t -= dt
				if s.sink_max > 4.0:
					if fmod(time, 0.5) < dt:
						var fp := s.pos + Vector2.from_angle(s.angle + s.sink_list * (1.0 - s.sink_t / s.sink_max)) * rng.randf_range(-_len(s) * 0.35, _len(s) * 0.35)
						_add_fx(0, fp, _len(s) * 0.35, 0.8)
						_add_fx(4, fp, _len(s) * 0.55, 1.8, Color(0.16, 0.16, 0.16))
				if s.sink_t <= 0.0 and s.sink_max > 4.0:
					_add_fx(8, s.pos, _len(s) * 1.3, 1.4)
					audio.play("sink", s.pos, -2.0)
			if not s.is_player:
				s.respawn -= dt
				if s.respawn <= 0.0 and world_ready:
					_spawn_bot(s)
	_pt("ships", t0)
	if death_pending:
		death_timer -= dt
		if death_timer <= 0.0:
			death_pending = false
			ui.show_respawn(death_info, D.of_tier(int(death_info["to"])))
	t0 = Time.get_ticks_usec()
	_build_ship_grid()
	_step_shots(dt)
	_pt("shots", t0)
	crate_acc += dt
	if crate_acc >= 0.1:
		_step_crates(crate_acc)
		crate_acc = 0.0
	_step_fx(dt)
	_update_camera(dt)
	t0 = Time.get_ticks_usec()
	_update_visuals(dt)
	_pt("visuals", t0)
	crate_layer.queue_redraw()
	# only redraw the dynamic layers when they actually contain something
	var aim_on := S.b("aimline") and state == State.PLAYING and player.alive and not ctrl_air
	if shots.size() > 0 or aim_on or shot_drawn:
		shot_layer.queue_redraw()
		shot_drawn = shots.size() > 0 or aim_on
	if fxs.size() > 0 or marked or fx_drawn:
		fx_layer.queue_redraw()
		fx_drawn = fxs.size() > 0 or marked
	t0 = Time.get_ticks_usec()
	_update_hud(dt)
	_pt("hud", t0)
	_adapt_quality(dt)
	if state == State.PLAYING and player.alive:
		battle_time += dt
	prof["frame"] = lerpf(float(prof.get("frame", delta * 1000.0)), delta * 1000.0, 0.1)
	if settings_dirty:
		save_timer -= dt
		if save_timer <= 0.0:
			settings_dirty = false
			S.save_file()

func _update_camera(dt: float) -> void:
	var target_pos := cam.position
	var have := false
	var zt := 0.8
	if player.alive:
		have = true
		if ctrl_air and player.air != null and player.air.alive:
			target_pos = player.air.pos
			zt = float(player.air.d["cam"])
		else:
			target_pos = player.pos
			zt = float(player.def["cam"])
	elif state == State.MENU:
		if follow == null or not follow.alive:
			follow = null
			for s in ships:
				if s.alive and not s.is_player:
					follow = s
					break
		if follow != null:
			have = true
			target_pos = follow.pos
			zt = float(follow.def["cam"])
	if have:
		cam.position = cam.position.lerp(target_pos, minf(1.0, dt * 6.0))
	zoom_cur = lerpf(zoom_cur, zoom_user * zt, minf(1.0, dt * 3.0))
	cam.zoom = Vector2(zoom_cur, zoom_cur)
	shake = maxf(0.0, shake - dt * 30.0)
	if shake > 0.01:
		cam.offset = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * shake
	else:
		cam.offset = Vector2.ZERO
	water_mat.set_shader_parameter("cam_pos", cam.position + cam.offset)
	water_mat.set_shader_parameter("zoom", zoom_cur)
	water_mat.set_shader_parameter("view_size", vp_size)
	water_mat.set_shader_parameter("t", time)

func _update_visuals(dt: float) -> void:
	var r := _view_rect(170.0)
	var trails_on := quality >= 1 and S.b("wakes")
	var names := S.b("names")
	var bars := S.b("hpbars")
	var hidden := Color(0, 0, 0, 0)
	for s in ships:
		if s.node == null:
			continue
		var sinking := (not s.alive) and s.sink_t > 0.0
		if (not s.alive) and not sinking:
			if s.node.modulate != hidden:
				s.node.modulate = hidden
				s.trail.visible = false
			continue
		# Ships are hidden with modulate, never with `visible`: toggling visibility makes Godot redraw
		# every child graphic of the ship, which caused big stalls whenever a ship entered the screen.
		var shown := s.seen or s.is_player or sinking
		var in_view := r.has_point(s.pos)
		var on := shown and in_view
		if not sinking:
			var want := Color(1, 1, 1, 1) if shown else hidden
			if shown and s.dive_t > 0.0:
				# submerged: blue-green silhouette under the waterline
				want = Color(0.42, 0.62, 0.72, 0.5)
			if s.node.modulate != want:
				s.node.modulate = want
		var show_trail := on and trails_on
		if s.trail.visible != show_trail:
			s.trail.visible = show_trail
		# the node position is ALWAYS kept current (a stale position leaves a frozen "ghost" ship behind)
		if s.node.position != s.pos:
			s.node.position = s.pos
		if not in_view:
			s.was_on = false
			continue
		if not s.was_on:
			s.was_on = true
			s.trail.clear_points()
		s.body.rotation = s.angle
		s.shadow.rotation = s.angle
		var sp_ratio := clampf(absf(s.speed) / float(s.def["spd"]), 0.0, 1.0)
		if sinking:
			var k := clampf(s.sink_t / s.sink_max, 0.0, 1.0)
			s.node.modulate = Color(k, k, k, k)
			s.node.scale = Vector2.ONE * (0.85 + 0.15 * k)
			s.body.rotation = s.angle + s.sink_list * (1.0 - k) * 0.6
			if k < 0.5 and fmod(time, 0.35) < dt:
				_add_fx(8, s.pos + Vector2.from_angle(rng.randf() * TAU) * _len(s) * rng.randf_range(0.1, 0.45), 14.0, 0.8)
			s.tag.visible = false
			continue
		var show_tag := on and s.seen and (names or bars)
		if s.tag.visible != show_tag:
			s.tag.visible = show_tag
		if show_tag:
			s.name_label.visible = names
			s.tag.get_child(1).visible = bars
			s.hp_fill.visible = bars
		for w in s.weapons:
			for m in w.mounts:
				if m.node != null:
					if m.arc > 0.001 and absf(m.node.rotation - m.rot) > 0.0004:
						m.node.rotation = m.rot
					if m.recoil > 0.0:
						m.recoil = maxf(0.0, m.recoil - dt * 5.0)
						if m.barrels != null:
							m.barrels.position.x = -m.recoil * 3.0
		if quality >= 1:
			for sp in s.spinners:
				sp.rotation += dt * float(sp.get_meta("spd"))
		if s.parked != null:
			s.parked.visible = s.air == null or not s.air.alive
		if s.foam != null:
			var fa := sp_ratio * (1.0 if quality >= 1 else 0.0)
			if s.foam is Sprite2D:
				s.foam.modulate = Color(fa, fa, fa, fa)   # baked sprites are premultiplied
			else:
				s.foam.modulate.a = fa
		if s.flash > 0.0:
			s.flash_poly.visible = true
			s.flash_poly.color = Color(1, 1, 1, s.flash * 0.5)
		elif s.flash_poly.visible:
			s.flash_poly.visible = false
		var ratio := clampf(s.hp / s.max_hp, 0.0, 1.0)
		if absf(ratio - s.shown_hp) > 0.005:
			s.shown_hp = ratio
			s.hp_fill.size.x = 50.0 * ratio
			s.hp_fill.color = Color(0.3, 1.0, 0.4) if ratio > 0.4 else Color(1.0, 0.4, 0.3)
		s.bow_poly.color = Color(1, 1, 1, sp_ratio * 0.3 if quality >= 1 else 0.0)
		if trails_on:
			_update_trail(s)

func _update_trail(s: Ship) -> void:
	var tr := s.trail
	var n := tr.get_point_count()
	if absf(s.speed) > 25.0:
		var stern := s.pos - Vector2.from_angle(s.angle) * _len(s) * 0.5
		if n == 0 or tr.get_point_position(n - 1).distance_squared_to(stern) > 196.0:
			tr.add_point(stern)
			if n + 1 > TRAIL_POINTS:
				tr.remove_point(0)
	elif n > 0 and Engine.get_frames_drawn() % 8 == 0:
		tr.remove_point(0)

# ---------------- Quality / display / settings ----------------

func _apply_quality() -> void:
	var qp := S.i("quality")
	auto_quality = qp == 3
	if not auto_quality:
		quality = qp
	water_mat.set_shader_parameter("quality", 0 if quality == 0 else (2 if quality >= 2 else 1))
	get_viewport().msaa_2d = Viewport.MSAA_2X if (quality >= 2 and aa_ok and S.b("msaa")) else Viewport.MSAA_DISABLED
	trails_root.visible = quality >= 1 and S.b("wakes")
	for s in ships:
		_apply_ship_quality(s)

func _apply_ship_quality(s: Ship) -> void:
	if s.shadow != null:
		s.shadow.visible = quality >= 1 and S.b("shadows")
	for g in s.details:
		g.visible = quality >= 1
	for g in s.fine:
		g.visible = quality >= 2

func _auto_apply(step: String, on: bool) -> void:
	match step:
		"msaa":
			aa_ok = not on
		"water":
			water_fast = on
		"q1":
			quality = 1 if on else 2
		"q0":
			quality = 0 if on else 1
	if step == "water":
		_apply_water()
	_apply_quality()

func _adapt_quality(dt: float) -> void:
	if not auto_quality or state != State.PLAYING or not world_ready or ui.settings_open:
		auto_acc = 0.0
		auto_t = 0.0
		return
	auto_acc += float(Engine.get_frames_per_second()) * dt
	auto_t += dt
	if auto_t < 4.0:
		return
	var avg := auto_acc / auto_t
	auto_acc = 0.0
	auto_t = 0.0
	if auto_pending != "":
		if avg < auto_before * 1.12:
			_auto_apply(auto_pending, false)
			auto_useless.append(auto_pending)
			ui.toast("Auto graphics: '%s' did not help - restored" % auto_pending)
		else:
			auto_done.append(auto_pending)
			ui.toast("Auto graphics: '%s' enabled (%d -> %d FPS)" % [auto_pending, int(auto_before), int(avg)])
		auto_pending = ""
		return
	if avg >= 28.0:
		return
	for step in ["msaa", "water", "q1", "q0"]:
		if auto_done.has(step) or auto_useless.has(step):
			continue
		if step == "msaa" and not (quality >= 2 and S.b("msaa")):
			continue
		if step == "q1" and quality < 2:
			continue
		if step == "q0" and quality != 1:
			continue
		_auto_apply(step, true)
		auto_pending = step
		auto_before = avg
		return

func _apply_display() -> void:
	Engine.max_fps = S.i("fps_cap")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if S.b("vsync") else DisplayServer.VSYNC_DISABLED)
	var want_fs := S.b("fullscreen")
	var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if want_fs != is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)

func _resize_bots(n: int) -> void:
	var count := ships.size() - 1
	while count < n:
		_add_bot()
		count += 1
	while count > n and ships.size() > 1:
		var b: Ship = ships.pop_back()
		b.alive = false
		b.sink_t = 0.0
		if b.node != null:
			b.node.queue_free()
			b.trail.queue_free()
		count -= 1

func _on_setting_changed(key: String) -> void:
	match key:
		"vol_master", "vol_sfx", "vol_amb", "vol_eng", "mute":
			audio.apply_volumes()
		"quality", "shadows", "wakes", "msaa":
			_apply_quality()
		"fps_cap", "vsync", "fullscreen":
			_apply_display()
		"show_fps":
			ui.set_fps_visible(S.b("show_fps"))
		"minimap":
			ui.set_minimap_visible(S.b("minimap"))
		"difficulty":
			_apply_difficulty()
		"bots":
			if world_ready:
				_resize_bots(S.i("bots"))
		"_reset":
			audio.apply_volumes()
			_apply_display()
			_apply_quality()
			_apply_difficulty()
			if world_ready:
				_resize_bots(S.i("bots"))
			ui.set_fps_visible(S.b("show_fps"))
			ui.set_minimap_visible(S.b("minimap"))
	settings_dirty = true
	save_timer = 1.0

# ---------------- HUD feed ----------------

func _weapon_state(w: WRT, rlm: float) -> Dictionary:
	var ready := 0
	var mn := 999.0
	for k in w.total:
		if w.cd[k] <= 0.0:
			ready += 1
		else:
			mn = minf(mn, w.cd[k])
	var frac := 0.0
	if ready == 0:
		frac = clampf(mn / maxf(float(w.d["rl"]) * rlm, 0.01), 0.0, 1.0)
	elif w.gap_t > 0.0:
		frac = clampf(w.gap_t / maxf(float(w.d["gap"]) * rlm, 0.01), 0.0, 1.0) * 0.5
	return {"cd": frac, "ready": ready, "total": w.total}

func _ab_active(s: Ship, id: String) -> bool:
	match id:
		"boost":
			return s.boost_t > 0.0
		"repair":
			return s.repair_t > 0.0
		"smoke":
			return s.smoke_t > 0.0
		"radar":
			return s.radar_t > 0.0
		"barrage":
			return s.barrage_t > 0.0
		"dive":
			return s.dive_t > 0.0
		"mine_l":
			return s.mine_t > 0.0
	return false

func _update_hud(dt: float) -> void:
	hud_timer += dt
	board_timer += dt
	if board_timer >= 0.5:
		board_timer = 0.0
		_build_board()
	var p := player
	var playing := p.alive and state == State.PLAYING
	var heli_ctrl := ctrl_air and p.air != null and p.air.alive
	audio.set_engine(playing, absf(p.speed) / maxf(float(p.def["spd"]) if not p.def.is_empty() else 100.0, 1.0))
	audio.set_rotor(playing and heli_ctrl, 1.0)
	if hud_timer < 0.1:
		return
	hud_timer = 0.0
	var snap := {}
	snap["alive"] = p.alive
	snap["fps"] = int(Engine.get_frames_per_second())
	snap["quality"] = QUALITY_NAMES[quality] + (" (auto)" if auto_quality else "") + ("" if aa_ok else ", no AA")
	snap["board"] = board
	snap["cam_pos"] = cam.position
	snap["view_half"] = vp_size * 0.5 / zoom_cur
	# detection: what the player can currently see on the map
	var blips := PackedVector2Array()
	var blip_t := PackedInt32Array()
	var det := 0.0
	var air_vis := 0.0
	var air_pos := Vector2.ZERO
	if p.alive:
		det = float(p.def["det"])
		if p.air != null and p.air.alive:
			air_vis = float(p.air.d["vis"])
			air_pos = p.air.pos
	for s in ships:
		if s == p or not s.alive:
			continue
		var vis := true
		if p.alive:
			vis = _can_see(p, s)
		s.seen = vis
		if vis:
			blips.append(s.pos)
			blip_t.append(s.tier)
	snap["blips"] = blips
	snap["blip_t"] = blip_t
	snap["pp"] = p.pos
	snap["pa"] = p.angle
	snap["det"] = det
	snap["air_vis"] = air_vis
	snap["air_pos"] = air_pos
	snap["air_ang"] = p.air.angle if (p.air != null and p.air.alive) else 0.0
	if p.alive:
		snap["cname"] = str(p.def["name"])
		snap["tier"] = p.tier
		snap["border"] = p.border_t
		var meta := D.level_progress(int(S.d.get("xp", 0)))
		snap["xp"] = meta["have"]
		snap["level"] = meta["lvl"]
		snap["xp_next"] = meta["need"]
		snap["rank"] = str(D.rank_from_rp(int(S.d.get("rp", 0))))
		snap["squad_n"] = (1 + p.wing.size()) if p.air != null else 0
		snap["squad_alive"] = (1 + p.wing.size()) if (p.air != null and p.air.alive) else 0
		snap["roman"] = str(D.ROMAN[p.tier - 1])
		snap["score"] = int(p.score)
		snap["hp"] = clampf(p.hp / p.max_hp, 0.0, 1.0)
		snap["hp_text"] = "%d / %d" % [int(ceilf(p.hp)), int(p.max_hp)]
		snap["throttle"] = p.throttle
		snap["promo"] = promo_open
		snap["fire"] = p.fire_t > 0.0
		snap["flood"] = p.flood_t > 0.0
		snap["auto"] = ctrl_air
		var prog := D.tier_progress(p.score, p.tier)
		snap["progress"] = prog
		if p.tier < D.MAX_TIER:
			snap["next_text"] = "Next: Tier %s at %d" % [str(D.ROMAN[p.tier]), int(D.TIER_NEED[p.tier])]
		else:
			snap["next_text"] = "Highest tier reached"
		var wl: Array = []
		if ctrl_air and p.air != null:
			for w in p.air.weapons:
				wl.append(_weapon_state(w, 1.0))
			snap["wsel"] = p.air.wsel
		else:
			for w in p.weapons:
				wl.append(_weapon_state(w, float(p.def["rlm"])))
			snap["wsel"] = p.wsel
		snap["w"] = wl
		var abl: Array = p.def["abil"]
		var al: Array = []
		for i in abl.size():
			var id := str(abl[i])
			var ad: Dictionary = D.ABILITIES[id]
			al.append({"cd": float(p.ab_cd[i]) / float(ad["cd"]), "on": _ab_active(p, id), "ready": p.ab_cd[i] <= 0.0})
		snap["ab"] = al
		var ai := {}
		if p.air != null:
			var a := p.air
			ai["name"] = str(a.d["n"])
			ai["hp"] = clampf(a.hp / float(a.d["hp"]), 0.0, 1.0)
			ai["state"] = 2 if not a.alive else (1 if ctrl_air else 0)
			ai["cd"] = maxf(a.cd, 0.0)
			ai["warn"] = a.warn
		snap["air"] = ai
	ui.refresh(snap)

func _build_board() -> void:
	var alive: Array = []
	for s in ships:
		if s.alive:
			alive.append(s)
	alive.sort_custom(func(a, b): return a.score > b.score)
	board.clear()
	var shown := mini(8, alive.size())
	for i in shown:
		var e: Ship = alive[i]
		board.append([i + 1, e.nick, int(e.score), e.is_player, e.tier])
	if player.alive and shown == 8:
		var rank := alive.find(player)
		if rank >= 8:
			board[7] = [rank + 1, player.nick, int(player.score), true, player.tier]

# ---------------- Dynamic drawing ----------------

func _draw_crates() -> void:
	var r := _view_rect(40.0)
	var glow := quality >= 1
	for cr in crates:
		if not r.has_point(cr.pos):
			continue
		var col: Color = CRATE_COLORS[cr.kind]
		var p := cr.pos + Vector2(0.0, sin(time * 3.0 + cr.phase) * 2.0)
		if glow:
			crate_layer.draw_circle(p, 11.0, Color(col.r, col.g, col.b, 0.14))
		crate_layer.draw_rect(Rect2(p + Vector2(-4, -3), Vector2(10, 10)), Color(0, 0, 0, 0.22))
		crate_layer.draw_rect(Rect2(p + Vector2(-5, -5), Vector2(10, 10)), col)
		crate_layer.draw_rect(Rect2(p + Vector2(-5, -5), Vector2(10, 10)), Color(0, 0, 0, 0.5), false, 1.1)
		if cr.kind == 1:
			crate_layer.draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), Color(1, 1, 1, 0.95), 2.5)
			crate_layer.draw_line(p + Vector2(0, -4), p + Vector2(0, 4), Color(1, 1, 1, 0.95), 2.5)
		else:
			crate_layer.draw_line(p + Vector2(-7, 0), p + Vector2(7, 0), Color(0, 0, 0, 0.3), 1.0)
			crate_layer.draw_line(p + Vector2(0, -7), p + Vector2(0, 7), Color(0, 0, 0, 0.3), 1.0)

func _draw_shots() -> void:
	var r := _view_rect(60.0)
	var L := shot_layer
	if S.b("aimline") and state == State.PLAYING and player.alive and not ctrl_air and player.wsel < player.weapons.size():
		var rg := float(player.weapons[player.wsel].d["rng"])
		var to := player.cursor - player.pos
		var tl := to.length()
		if tl > 40.0:
			var nd := to / tl
			L.draw_dashed_line(player.pos + nd * 20.0, player.pos + nd * minf(tl, rg), Color(1, 1, 1, 0.15), 1.0, 8.0)
			if tl > rg:
				L.draw_circle(player.pos + nd * rg, 3.0, Color(1, 1, 1, 0.3))
	for sh in shots:
		if not r.has_point(sh.pos):
			continue
		var dir := Vector2.from_angle(sh.ang)
		if sh.kind == K_BULLET:
			L.draw_line(sh.pos - dir * 8.0, sh.pos, Color(1.0, 0.9, 0.5, 0.85), 1.6)
			L.draw_circle(sh.pos, 1.1, Color(1.0, 1.0, 0.85))
		elif sh.kind == K_SHELL:
			L.draw_line(sh.pos - dir * 18.0, sh.pos, Color(1.0, 0.8, 0.35, 0.45), sh.sz * 0.9)
			L.draw_circle(sh.pos, sh.sz, Color(1.0, 0.92, 0.6))
			L.draw_circle(sh.pos, sh.sz * 0.55, Color(1, 1, 1))
		elif sh.kind == K_TORP:
			# running just under the surface: dark hull, faint bubbles, thin wake crest
			for k in range(1, 7):
				L.draw_circle(sh.pos - dir * float(k) * 10.0, 2.0 - float(k) * 0.22, Color(0.85, 0.95, 1.0, 0.30 - float(k) * 0.038))
			L.draw_line(sh.pos - dir * 15.0, sh.pos, Color(0.55, 0.72, 0.78, 0.35), 1.4)
			L.draw_line(sh.pos - dir * 7.0, sh.pos, Color(0.08, 0.13, 0.16, 0.85), 3.2)
			L.draw_circle(sh.pos, 3.0, Color(0.07, 0.11, 0.13, 0.9))
			L.draw_circle(sh.pos, 1.5, Color(0.75, 0.16, 0.14, 0.8))
		elif sh.kind == K_MISSILE or sh.kind == K_ROCKET:
			_draw_missile(L, sh)
		elif sh.kind == K_MINE:
			L.draw_circle(sh.pos, 4.2, Color(0.12, 0.13, 0.15, 0.9))
			for k in 4:
				var sp := Vector2.from_angle(float(k) * PI * 0.5 + 0.4) * 5.5
				L.draw_line(sh.pos, sh.pos + sp, Color(0.12, 0.13, 0.15, 0.9), 1.4)
			if sh.t > 1.5 and fmod(time, 1.0) < 0.2:
				L.draw_circle(sh.pos, 1.6, Color(1.0, 0.2, 0.2))
		elif sh.kind == K_BOMB:
			var k2 := clampf(sh.t / 0.7, 0.0, 1.0)
			L.draw_circle(sh.pos, 2.0 + k2 * 9.0, Color(0, 0, 0, 0.12))
			var bp := sh.pos + Vector2(0.0, -(1.0 - k2) * 28.0)
			L.draw_circle(bp, 3.2, Color(0.14, 0.15, 0.17))
			L.draw_line(bp + Vector2(0, -4), bp + Vector2(0, -7), Color(0.14, 0.15, 0.17), 1.6)

func _draw_fx() -> void:
	var r := _view_rect(80.0)
	var fancy := quality >= 2
	var font := ThemeDB.fallback_font
	var F := fx_layer
	for s in ships:
		if s.alive and s.mark_t > 0.0 and r.has_point(s.pos) and (s.seen or s.is_player):
			F.draw_arc(s.pos, s.hl * 0.9 + 8.0 + sin(time * 6.0) * 2.0, 0.0, TAU, 28, Color(1.0, 0.3, 0.3, 0.85), 2.0)
	for f in fxs:
		if not r.has_point(f.pos):
			continue
		var p := f.age / f.dur
		var inv := 1.0 - p
		match f.kind:
			0:
				var rad := f.size * (0.3 + 0.7 * p)
				if p > 0.2:
					F.draw_circle(f.pos + Vector2(6.0, -9.0) * p, rad * 0.95, Color(0.13, 0.13, 0.14, 0.40 * inv))
				F.draw_circle(f.pos, rad * 0.80, Color(1.0, 0.42, 0.10, 0.60 * inv))
				F.draw_circle(f.pos, rad * 0.55, Color(1.0, 0.70, 0.20, 0.75 * inv))
				F.draw_circle(f.pos, rad * 0.32, Color(1.0, 0.95, 0.72, 0.90 * inv))
				if p < 0.15:
					F.draw_circle(f.pos, rad * 1.5, Color(1, 1, 1, 0.6 * (1.0 - p / 0.15)))
				if fancy:
					F.draw_arc(f.pos, rad * 1.15, 0.0, TAU, 20, Color(1, 1, 1, 0.40 * inv), 2.0)
					for k in 9:
						var d := Vector2.from_angle(f.sd + float(k) * TAU / 9.0)
						F.draw_line(f.pos + d * rad * 0.6, f.pos + d * rad * (0.95 + p), Color(1.0, 0.8, 0.3, inv), 2.0)
					for k in 6:
						var d2 := Vector2.from_angle(f.sd * 1.7 + float(k) * 1.05)
						F.draw_circle(f.pos + d2 * rad * (0.5 + 1.6 * p), 1.3 * inv + 0.4, Color(0.15, 0.13, 0.12, inv))
			1:
				var e1 := 1.0 - pow(inv, 2.0)
				F.draw_arc(f.pos, f.size * e1 + 4.0, 0.0, TAU, 18, Color(1, 1, 1, 0.7 * inv), 2.0)
				F.draw_circle(f.pos, f.size * 0.30 * sin(p * PI) + 1.0, Color(0.9, 0.96, 1.0, 0.5 * inv))
				if fancy:
					F.draw_arc(f.pos, f.size * e1 * 0.55 + 2.0, 0.0, TAU, 14, Color(1, 1, 1, 0.4 * inv), 1.5)
					for k in 7:
						var d3 := Vector2.from_angle(f.sd + float(k) * TAU / 7.0)
						F.draw_circle(f.pos + d3 * f.size * (0.2 + 0.6 * e1) + Vector2(0.0, -sin(p * PI) * 6.0), 1.4 * inv + 0.3, Color(1, 1, 1, 0.7 * inv))
			2:
				var d4 := Vector2.from_angle(f.ang)
				var pr := Vector2(-d4.y, d4.x) * f.size * 0.35 * inv
				F.draw_colored_polygon(PackedVector2Array([f.pos + pr, f.pos + d4 * f.size * (1.4 + p), f.pos - pr]), Color(1.0, 0.85, 0.50, 0.9 * inv))
				F.draw_colored_polygon(PackedVector2Array([f.pos + pr * 0.5, f.pos + d4 * f.size * 0.8, f.pos - pr * 0.5]), Color(1.0, 1.0, 0.9, 0.95 * inv))
				F.draw_circle(f.pos, f.size * 0.45 * inv, Color(1.0, 0.95, 0.75, 0.9 * inv))
				F.draw_circle(f.pos, f.size * 1.1 * inv, Color(1.0, 0.7, 0.3, 0.15 * inv))
			3:
				F.draw_arc(f.pos, f.size * (0.4 + 0.6 * p), 0.0, TAU, 20, Color(f.col.r, f.col.g, f.col.b, 0.9 * inv), 2.5)
			4:
				F.draw_circle(f.pos + Vector2(10.0, -8.0) * p, f.size * (0.4 + 0.8 * p), Color(f.col.r, f.col.g, f.col.b, 0.34 * inv))
			5:
				F.draw_line(f.pos, f.pos2, Color(f.col.r, f.col.g, f.col.b, inv), 1.5)
			6:
				F.draw_string(font, f.pos + Vector2(-20.0, -p * 26.0), f.txt, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 14, Color(f.col.r, f.col.g, f.col.b, inv))
			7:
				# shockwave: a fast expanding ring with a soft inner band and a flash
				var e7 := 1.0 - pow(inv, 2.5)
				var rr := f.size * (0.12 + 0.88 * e7)
				F.draw_arc(f.pos, rr, 0.0, TAU, 40, Color(f.col.r, f.col.g, f.col.b, 0.55 * inv), 3.0 * inv + 1.0)
				F.draw_arc(f.pos, rr * 0.84, 0.0, TAU, 36, Color(f.col.r, f.col.g, f.col.b, 0.22 * inv), 7.0 * inv + 1.0)
				if p < 0.25:
					F.draw_circle(f.pos, rr * 0.55, Color(1, 1, 1, 0.28 * (1.0 - p / 0.25)))
			8:
				# water shatter: ring waves, a collapsing white column, radial spray and droplets
				var e8 := 1.0 - pow(inv, 2.0)
				F.draw_arc(f.pos, f.size * (0.2 + 0.8 * e8), 0.0, TAU, 32, Color(0.85, 0.95, 1.0, 0.6 * inv), 3.0)
				F.draw_arc(f.pos, f.size * (0.1 + 0.5 * e8), 0.0, TAU, 28, Color(0.9, 0.97, 1.0, 0.5 * inv), 2.0)
				F.draw_circle(f.pos, f.size * 0.7 * e8, Color(0.75, 0.90, 0.95, 0.20 * inv))
				var colr := f.size * 0.34 * sin(clampf(p * 1.15, 0.0, 1.0) * PI)
				F.draw_circle(f.pos, colr, Color(0.88, 0.96, 1.0, 0.60 * inv))
				F.draw_circle(f.pos, colr * 0.55, Color(1, 1, 1, 0.75 * inv))
				for k in 14:
					var d5 := Vector2.from_angle(f.sd + float(k) * TAU / 14.0)
					var l1 := f.size * (0.25 + 0.7 * e8) * (0.7 + 0.3 * sin(float(k) * 1.7))
					F.draw_line(f.pos + d5 * f.size * 0.12 * e8, f.pos + d5 * l1, Color(0.92, 0.98, 1.0, 0.8 * inv), 2.0 * inv + 0.6)
				if fancy:
					for k in 10:
						var d6 := Vector2.from_angle(f.sd * 2.3 + float(k) * 0.63)
						F.draw_circle(f.pos + d6 * f.size * (0.3 + 0.9 * e8) + Vector2(0.0, -sin(p * PI) * f.size * 0.3), 1.8 * inv + 0.4, Color(1, 1, 1, 0.8 * inv))
			9:
				var fl := 0.6 + 0.4 * sin(f.age * 40.0 + f.sd)
				F.draw_circle(f.pos, f.size * 2.2, Color(1.0, 0.5, 0.1, 0.10 * inv))
				F.draw_circle(f.pos, f.size * (1.0 - p * 0.5) * fl, Color(1.0, 0.45, 0.10, 0.85 * inv))
				F.draw_circle(f.pos, f.size * 0.55 * (1.0 - p * 0.5), Color(1.0, 0.88, 0.35, 0.95 * inv))

# ---------------- Fire, flooding, detection ----------------

func _hit_effects(o: Ship, dmg: float, src: Ship) -> void:
	if dmg < 8.0 or not o.alive or o.invuln > 0.0:
		return
	if src != null:
		o.last_attacker = src
	if rng.randf() < 0.05:
		o.fire_t = 10.0
		o.fire_pt = Vector2(rng.randf_range(-0.35, 0.35) * _len(o), rng.randf_range(-0.2, 0.2) * float(o.def["wid"]))
		if o.is_player:
			ui.toast("FIRE ON BOARD!  Use Damage Control")
			audio.play_ui("alarm", -4.0)
	if rng.randf() < 0.02:
		o.flood_t = 16.0
		if o.is_player:
			ui.toast("FLOODING!  Speed reduced")
			audio.play_ui("alarm", -4.0)

func _dot(s: Ship, amount: float) -> void:
	s.hp -= amount
	s.flash = maxf(s.flash, 0.0)
	if s.hp <= 0.0 and s.alive:
		_kill(s, s.last_attacker)

# can `obs` currently see `o`?  Range = observer detection x target stealth.  Firing exposes you,
# smoke hides you, radar / aircraft / target-marking extend what you can see.
func _can_see(obs: Ship, o: Ship) -> bool:
	if obs == o:
		return true
	if obs.is_player and not S.b("fog"):
		return true
	if o.mark_t > 0.0 or obs.radar_t > 0.0:
		return true
	var f := o.stealth
	if o.reveal_t > 0.0:
		f = 1.0
	elif o.dive_t > 0.0:
		f *= 0.22
	elif o.smoke_t > 0.0:
		f *= 0.3
	var r := float(obs.def["det"]) * f
	if not obs.is_player:
		r *= bot_det
	if obs.pos.distance_squared_to(o.pos) < r * r:
		return true
	if obs.air != null and obs.air.alive:
		var ar := float(obs.air.d["vis"]) * f
		if obs.air.pos.distance_squared_to(o.pos) < ar * ar:
			return true
	return false

# Each missile family has its own silhouette and colours (kept small - it is a detail, not a sprite).
func _draw_missile(L: CanvasItem, sh: Shot) -> void:
	var sc := minf(1.0, 0.55 + sh.t * 1.5)
	var tc := Color(0.85, 0.85, 0.88)
	var tw := 2.4
	match sh.mt:
		1:
			tc = Color(0.80, 0.82, 0.86)
			tw = 2.0
		2:
			tc = Color(0.96, 0.96, 0.98)
			tw = 2.6
		3:
			tc = Color(0.70, 0.76, 0.86)
			tw = 3.6
		4:
			tc = Color(0.93, 0.90, 0.82)
			tw = 2.0
		5:
			tc = Color(0.72, 0.72, 0.70)
			tw = 1.3
		6:
			tc = Color(0.76, 0.70, 0.60)
			tw = 2.0
		7:
			tc = Color(0.78, 0.80, 0.84)
			tw = 1.8
		8:
			tc = Color(0.88, 0.90, 0.94)
			tw = 2.8
	if sh.trail.size() >= 2 and quality >= 1:
		var pts := PackedVector2Array(sh.trail)
		pts.append(sh.pos)
		var cols := PackedColorArray()
		for k in pts.size():
			cols.append(Color(tc.r, tc.g, tc.b, 0.5 * float(k) / float(pts.size())))
		L.draw_polyline_colors(pts, cols, tw * sc)
	L.draw_set_transform(sh.pos, sh.ang, Vector2(sc, sc))
	var fl := 3.0 + rng.randf() * 2.0
	match sh.mt:
		1:
			L.draw_line(Vector2(-4.5, 0.0), Vector2(-4.5 - fl, 0.0), Color(1.0, 0.6, 0.2, 0.9), 1.8)
			L.draw_colored_polygon(PackedVector2Array([Vector2(-4.5, -1.1), Vector2(-2.8, -1.1), Vector2(-4.5, -2.9)]), Color(0.6, 0.63, 0.68))
			L.draw_colored_polygon(PackedVector2Array([Vector2(-4.5, 1.1), Vector2(-2.8, 1.1), Vector2(-4.5, 2.9)]), Color(0.6, 0.63, 0.68))
			L.draw_rect(Rect2(Vector2(-4.5, -1.1), Vector2(8.0, 2.2)), Color(0.92, 0.93, 0.95))
			L.draw_rect(Rect2(Vector2(0.6, -2.6), Vector2(1.0, 5.2)), Color(0.62, 0.65, 0.70))
			L.draw_colored_polygon(PackedVector2Array([Vector2(3.5, -1.1), Vector2(6.0, 0.0), Vector2(3.5, 1.1)]), Color(0.85, 0.20, 0.18))
		2:
			L.draw_line(Vector2(-5.5, 0.0), Vector2(-5.5 - fl, 0.0), Color(1.0, 0.75, 0.3, 0.9), 2.2)
			L.draw_colored_polygon(PackedVector2Array([Vector2(-1.5, -3.4), Vector2(0.9, -3.4), Vector2(0.9, 3.4), Vector2(-1.5, 3.4)]), Color(0.35, 0.37, 0.42))
			L.draw_colored_polygon(PackedVector2Array([Vector2(-5.5, -1.3), Vector2(-3.8, -1.3), Vector2(-5.5, -2.8)]), Color(0.35, 0.37, 0.42))
			L.draw_colored_polygon(PackedVector2Array([Vector2(-5.5, 1.3), Vector2(-3.8, 1.3), Vector2(-5.5, 2.8)]), Color(0.35, 0.37, 0.42))
			L.draw_rect(Rect2(Vector2(-5.5, -1.3), Vector2(10.0, 2.6)), Color(0.88, 0.90, 0.92))
			L.draw_rect(Rect2(Vector2(1.4, -3.0), Vector2(1.1, 6.0)), Color(0.32, 0.34, 0.38))
			L.draw_rect(Rect2(Vector2(-1.0, -1.3), Vector2(1.6, 2.6)), Color(0.20, 0.40, 0.80))
			L.draw_colored_polygon(PackedVector2Array([Vector2(4.5, -1.3), Vector2(7.5, 0.0), Vector2(4.5, 1.3)]), Color(0.95, 0.60, 0.15))
		3:
			L.draw_line(Vector2(-7.0, 0.0), Vector2(-7.0 - fl * 1.6, 0.0), Color(0.6, 0.8, 1.0, 0.95), 3.0)
			L.draw_circle(Vector2(-7.0, 0.0), 2.0, Color(0.6, 0.8, 1.0, 0.8))
			L.draw_colored_polygon(PackedVector2Array([Vector2(-1.0, -1.8), Vector2(-6.0, -1.8), Vector2(-6.0, -5.5)]), Color(0.28, 0.31, 0.36))
			L.draw_colored_polygon(PackedVector2Array([Vector2(-1.0, 1.8), Vector2(-6.0, 1.8), Vector2(-6.0, 5.5)]), Color(0.28, 0.31, 0.36))
			L.draw_rect(Rect2(Vector2(-7.0, -1.8), Vector2(14.0, 3.6)), Color(0.38, 0.42, 0.48))
			L.draw_colored_polygon(PackedVector2Array([Vector2(5.0, -1.8), Vector2(3.6, -3.4), Vector2(2.8, -1.8)]), Color(0.28, 0.31, 0.36))
			L.draw_colored_polygon(PackedVector2Array([Vector2(5.0, 1.8), Vector2(3.6, 3.4), Vector2(2.8, 1.8)]), Color(0.28, 0.31, 0.36))
			L.draw_circle(Vector2(-4.4, 0.0), 1.0, Color(0.16, 0.18, 0.20))
			L.draw_colored_polygon(PackedVector2Array([Vector2(7.0, -1.8), Vector2(10.5, 0.0), Vector2(7.0, 1.8)]), Color(0.85, 0.86, 0.88))
		4:
			L.draw_line(Vector2(-6.0, 0.0), Vector2(-6.0 - fl * 0.7, 0.0), Color(1.0, 0.8, 0.5, 0.9), 1.4)
			L.draw_rect(Rect2(Vector2(-1.5, -5.5), Vector2(1.7, 11.0)), Color(0.30, 0.32, 0.35))
			L.draw_rect(Rect2(Vector2(-6.0, -2.2), Vector2(1.6, 4.4)), Color(0.30, 0.32, 0.35))
			L.draw_rect(Rect2(Vector2(-6.0, -0.9), Vector2(12.0, 1.8)), Color(0.93, 0.90, 0.80))
			L.draw_colored_polygon(PackedVector2Array([Vector2(6.0, -0.9), Vector2(8.5, 0.0), Vector2(6.0, 0.9)]), Color(0.40, 0.42, 0.45))
		5:
			L.draw_line(Vector2(-3.0, 0.0), Vector2(-3.0 - fl * 0.6, 0.0), Color(1.0, 0.65, 0.2, 0.9), 1.2)
			L.draw_rect(Rect2(Vector2(-3.0, -0.6), Vector2(5.0, 1.2)), Color(0.45, 0.50, 0.30))
			L.draw_circle(Vector2(2.5, 0.0), 0.8, Color(1.0, 0.85, 0.3))
		6:
			L.draw_line(Vector2(-4.5, 0.0), Vector2(-4.5 - fl, 0.0), Color(1.0, 0.65, 0.2, 0.9), 1.8)
			L.draw_colored_polygon(PackedVector2Array([Vector2(-4.5, -1.0), Vector2(-3.0, -1.0), Vector2(-4.5, -2.6)]), Color(0.35, 0.30, 0.20))
			L.draw_colored_polygon(PackedVector2Array([Vector2(-4.5, 1.0), Vector2(-3.0, 1.0), Vector2(-4.5, 2.6)]), Color(0.35, 0.30, 0.20))
			L.draw_rect(Rect2(Vector2(-4.5, -1.0), Vector2(8.0, 2.0)), Color(0.50, 0.45, 0.28))
			L.draw_rect(Rect2(Vector2(-1.0, -1.0), Vector2(1.2, 2.0)), Color(0.95, 0.80, 0.20))
			L.draw_colored_polygon(PackedVector2Array([Vector2(3.5, -1.0), Vector2(5.5, 0.0), Vector2(3.5, 1.0)]), Color(0.80, 0.20, 0.18))
		7:
			# light air-launched missile: slim body, small cruciform fins
			L.draw_line(Vector2(-3.8, 0.0), Vector2(-3.8 - fl * 0.7, 0.0), Color(1.0, 0.7, 0.25, 0.9), 1.4)
			L.draw_colored_polygon(PackedVector2Array([Vector2(-3.8, -0.8), Vector2(-2.6, -0.8), Vector2(-3.8, -2.2)]), Color(0.5, 0.53, 0.58))
			L.draw_colored_polygon(PackedVector2Array([Vector2(-3.8, 0.8), Vector2(-2.6, 0.8), Vector2(-3.8, 2.2)]), Color(0.5, 0.53, 0.58))
			L.draw_rect(Rect2(Vector2(-3.8, -0.9), Vector2(7.0, 1.8)), Color(0.90, 0.91, 0.94))
			L.draw_rect(Rect2(Vector2(-0.4, -2.3), Vector2(0.9, 4.6)), Color(0.55, 0.58, 0.62))
			L.draw_rect(Rect2(Vector2(1.2, -0.9), Vector2(1.0, 1.8)), Color(0.2, 0.3, 0.45))
			L.draw_colored_polygon(PackedVector2Array([Vector2(3.2, -0.9), Vector2(5.0, 0.0), Vector2(3.2, 0.9)]), Color(0.82, 0.24, 0.18))
		8:
			# heavy supersonic air-launched missile: long nose, swept wings, twin boosters
			L.draw_line(Vector2(-6.5, 0.5), Vector2(-6.5 - fl * 1.4, 0.5), Color(0.75, 0.85, 1.0, 0.95), 2.4)
			L.draw_line(Vector2(-6.5, -0.5), Vector2(-6.5 - fl * 1.4, -0.5), Color(1.0, 0.65, 0.25, 0.9), 1.6)
			L.draw_colored_polygon(PackedVector2Array([Vector2(0.5, -1.9), Vector2(-2.5, -5.2), Vector2(-4.2, -5.2), Vector2(-1.5, -1.9)]), Color(0.30, 0.33, 0.40))
			L.draw_colored_polygon(PackedVector2Array([Vector2(0.5, 1.9), Vector2(-2.5, 5.2), Vector2(-4.2, 5.2), Vector2(-1.5, 1.9)]), Color(0.30, 0.33, 0.40))
			L.draw_circle(Vector2(-5.8, -1.1), 1.1, Color(0.25, 0.27, 0.30))
			L.draw_circle(Vector2(-5.8, 1.1), 1.1, Color(0.25, 0.27, 0.30))
			L.draw_rect(Rect2(Vector2(-6.5, -1.9), Vector2(13.5, 3.8)), Color(0.94, 0.95, 0.97))
			L.draw_rect(Rect2(Vector2(-6.5, -1.9), Vector2(2.0, 3.8)), Color(0.32, 0.35, 0.40))
			L.draw_colored_polygon(PackedVector2Array([Vector2(3.0, -1.9), Vector2(4.6, -4.0), Vector2(5.4, -1.9)]), Color(0.30, 0.33, 0.40))
			L.draw_colored_polygon(PackedVector2Array([Vector2(3.0, 1.9), Vector2(4.6, 4.0), Vector2(5.4, 1.9)]), Color(0.30, 0.33, 0.40))
			L.draw_colored_polygon(PackedVector2Array([Vector2(7.0, -1.9), Vector2(10.0, 0.0), Vector2(7.0, 1.9)]), Color(0.85, 0.22, 0.16))
		_:
			var ln := 9.0
			L.draw_line(Vector2(-ln, 0.0), Vector2(-ln - 4.0 - rng.randf() * 3.0, 0.0), Color(1.0, 0.6, 0.2, 0.9), 2.2)
			L.draw_line(Vector2(-ln, 0.0), Vector2(2.0, 0.0), Color(0.93, 0.94, 0.96), 3.0)
	L.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ============================================================================================
# BAKE SYSTEM - the big performance feature.
# Every ship hull, turret, island, reef and wreck is drawn ONCE into a texture (with 4x MSAA and
# mipmaps) and then shown as a sprite. The picture is identical, but the GPU/driver now handles
# 1 draw call per object instead of hundreds - that is what makes a weak GPU like the Intel HD 4000
# run the game smoothly when many ships and islands are on screen.
# ============================================================================================

func _queue_bake(key: String, size: Vector2, sc: float, fn: Callable) -> void:
	if bake_keys.has(key):
		return
	bake_keys[key] = true
	bake_jobs.append({"key": key, "size": size, "sc": sc, "fn": fn})

func _bake_draw(c: Node2D, fn: Callable) -> void:
	fn.call(c)

func _sprite(key: String, parent: Node) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex[key]
	var k := 1.0 / float(tex_sc[key])
	sp.scale = Vector2(k, k)
	sp.material = premult
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(sp)
	return sp

func _bake_scale(tier: int) -> float:
	if tier <= 4:
		return 2.0
	if tier <= 6:
		return 1.5
	return 1.0

func _wreck_len(sd: int) -> float:
	var g := RandomNumberGenerator.new()
	g.seed = sd
	return g.randf_range(50.0, 110.0)

func _queue_world_jobs() -> void:
	for i in island_pos.size():
		var r: float = island_r[i]
		var sd: int = island_sd[i]
		_queue_bake("il%d" % i, Vector2.ONE * r * 2.9, clampf(1100.0 / (r * 2.9), 0.7, 1.0), _draw_island_land.bind(r, sd))
		_queue_bake("ih%d" % i, Vector2.ONE * r * 4.6, 0.25, _draw_island_halo.bind(r, sd))
	for i in reef_pos.size():
		var rr: float = reef_r[i]
		_queue_bake("rf%d" % i, Vector2.ONE * rr * 2.7, 0.5, _draw_reef.bind(rr, int(reef_sd[i])))
	for i in wreck_pos.size():
		var wl := _wreck_len(int(wreck_sd[i]))
		_queue_bake("w%d" % i, Vector2(wl * 1.7 + 30.0, wl * 0.8 + 30.0), 1.0, _draw_wreck.bind(int(wreck_sd[i])))
	_queue_bake("bu_r", Vector2(26.0, 26.0), 2.0, _draw_buoy.bind(true))
	_queue_bake("bu_g", Vector2(26.0, 26.0), 2.0, _draw_buoy.bind(false))

func _queue_ship_jobs() -> void:
	for def in D.ships():
		var d: Dictionary = def
		var did := str(d["id"])
		var L := float(d["len"])
		var W := float(d["wid"])
		var sc := _bake_scale(int(d["tier"]))
		_queue_bake("h:" + did, Vector2(L + 24.0, maxf(W * 1.3, W + 14.0) + 10.0), sc, _bake_hull.bind(d))
		_queue_bake("f:" + did, Vector2(L + 44.0, W * 1.9 + 8.0), sc, _bake_foam.bind(d))
		for g in d["weapons"]:
			for m in g["m"]:
				_queue_mount_jobs(str(g["w"]), int(m["b"]))

func _queue_mount_jobs(wid: String, b: int) -> void:
	var wd: Dictionary = D.WEAPONS[wid]
	if str(wd["vis"]) == "gun":
		var bw := float(wd["bw"])
		var bl := float(wd["bl"])
		var tl := bl * 0.6 + 4.0
		var tw := float(b) * bw * 1.4 + 2.0
		var R := maxf(tl * 0.3 + bl + 3.0, maxf(tw, tl) * 0.8) + 4.0
		for part in ["base", "bar", "roof"]:
			_queue_bake("m:%s:%d:%s" % [wid, b, part], Vector2.ONE * R * 2.0, 2.0, _bake_mount.bind(wid, b, part))
	else:
		var R2 := 12.0 + float(b) * 1.8
		_queue_bake("m:%s:%d:all" % [wid, b], Vector2.ONE * R2 * 2.0, 2.0, _bake_mount.bind(wid, b, "all"))

func _bake_hull(c: Node2D, d: Dictionary) -> void:
	var ctx := _ship_ctx(d)
	_ship_l0(c, ctx, Color(0, 0, 0, 0))
	_ship_l1(c, ctx, Color.WHITE)
	_ship_l2(c, ctx)

func _bake_foam(c: Node2D, d: Dictionary) -> void:
	var ctx := _ship_ctx(d)
	_draw_foam(c, float(ctx["L"]), float(ctx["W"]), ctx["hull"])

func _bake_mount(c: Node2D, wid: String, b: int, part: String) -> void:
	var wd: Dictionary = D.WEAPONS[wid]
	var m := MountRT.new()
	m.b = b
	var dims := D.mount_dims(wd, b)
	m.muz = dims.x
	m.bsp = dims.y
	if part == "bar":
		_draw_gun_barrels(c, wd, m)
	elif part == "roof":
		_draw_gun_roof(c, wd, m)
	else:
		_draw_mount_base(c, wd, m)

func _flag_overlay(s: Ship, ctx: Dictionary) -> void:
	var L: float = ctx["L"]
	var W: float = ctx["W"]
	var st: Dictionary = ctx["st"]
	_add_poly(s.body, _rect_pts(Vector2(-L * 0.5 + 1.0, -0.9), Vector2(maxf(L * 0.06, 3.0), 1.8)), s.color)
	for fx in st["fun"]:
		var fr := W * 0.15
		var fp := Vector2(float(fx) * L, 0.0)
		var band := _add_poly(s.body, _shift_pts(_scale_pts(_circle_pts(fr * 0.78, 14), 1.5, 1.0), Vector2(-0.5, 0.0)), s.color.darkened(0.1))
		band.position = fp
		var cap := _add_poly(s.body, _scale_pts(_circle_pts(fr * 0.5, 12), 1.4, 1.0), Color(0.03, 0.03, 0.04))
		cap.position = fp

func _run_bake() -> void:
	var total := bake_jobs.size()
	var done := 0
	var i := 0
	while i < total:
		var batch: Array = []
		var px := 0
		while i < total and batch.size() < 14:
			var j: Dictionary = bake_jobs[i]
			var wsz: Vector2 = j["size"]
			var sc: float = j["sc"]
			var vs := Vector2i(maxi(ceili(wsz.x * sc), 8), maxi(ceili(wsz.y * sc), 8))
			if not batch.is_empty() and px + vs.x * vs.y > 3000000:
				break
			var vp := SubViewport.new()
			vp.size = vs
			vp.transparent_bg = true
			vp.disable_3d = true
			vp.msaa_2d = Viewport.MSAA_4X
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			add_child(vp)
			var holder := Node2D.new()
			holder.position = Vector2(vs) * 0.5
			holder.scale = Vector2(sc, sc)
			vp.add_child(holder)
			holder.draw.connect(_bake_draw.bind(holder, j["fn"]))
			batch.append({"vp": vp, "key": str(j["key"]), "sc": sc})
			px += vs.x * vs.y
			i += 1
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		for b in batch:
			var vp2: SubViewport = b["vp"]
			var img := vp2.get_texture().get_image()
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				tex[b["key"]] = ImageTexture.create_from_image(img)
				tex_sc[b["key"]] = b["sc"]
			vp2.queue_free()
			done += 1
		ui.set_loading(float(done) / float(maxi(total, 1)))
	_finish_world()

func _finish_world() -> void:
	if world_ready:
		return
	world_ready = true
	_build_world_visuals()
	for i in S.i("bots"):
		_add_bot()
	_apply_quality()
	ui.set_loading(1.0)

func _build_world_visuals() -> void:
	for i in island_pos.size():
		var r: float = island_r[i]
		var root := Node2D.new()
		root.position = island_pos[i]
		islands_root.add_child(root)
		if tex.has("ih%d" % i) and tex.has("il%d" % i):
			_sprite("ih%d" % i, root)
			_sprite("il%d" % i, root)
		else:
			root.draw.connect(_draw_island.bind(root, r, int(island_sd[i])))
	for i in reef_pos.size():
		var rn := Node2D.new()
		rn.position = reef_pos[i]
		islands_root.add_child(rn)
		if tex.has("rf%d" % i):
			_sprite("rf%d" % i, rn)
		else:
			rn.draw.connect(_draw_reef.bind(rn, float(reef_r[i]), int(reef_sd[i])))
	for i in wreck_pos.size():
		var wn := Node2D.new()
		wn.position = wreck_pos[i]
		wn.rotation = wreck_rot[i]
		islands_root.add_child(wn)
		if tex.has("w%d" % i):
			_sprite("w%d" % i, wn)
		else:
			wn.draw.connect(_draw_wreck.bind(wn, int(wreck_sd[i])))
	for i in buoy_pos.size():
		var bn := Node2D.new()
		bn.position = buoy_pos[i]
		islands_root.add_child(bn)
		var key := "bu_r" if bool(buoy_red[i]) else "bu_g"
		if tex.has(key):
			_sprite(key, bn)
		else:
			bn.draw.connect(_draw_buoy.bind(bn, bool(buoy_red[i])))

# Tileable wave texture: R = height, G/B = slope. Built once from a sum of sines with whole-number
# frequencies (so it tiles seamlessly), then the shader scrolls it at three scales.
func _make_wave_tex() -> ImageTexture:
	var n := 96
	var waves := [[1.0, 0.0, 1.0, 0.0], [0.0, 1.0, 0.8, 1.7], [1.0, 1.0, 0.6, 3.1], [2.0, 1.0, 0.45, 0.9],
		[1.0, 2.0, 0.35, 2.3], [3.0, 1.0, 0.25, 4.4], [2.0, 3.0, 0.2, 5.2], [4.0, 3.0, 0.12, 0.4]]
	var hs := PackedFloat32Array()
	var gx := PackedFloat32Array()
	var gy := PackedFloat32Array()
	hs.resize(n * n)
	gx.resize(n * n)
	gy.resize(n * n)
	var hmax := 0.001
	var gmax := 0.001
	for y in n:
		for x in n:
			var u := float(x) / float(n)
			var v := float(y) / float(n)
			var h := 0.0
			var du := 0.0
			var dv := 0.0
			for wv in waves:
				var kx: float = wv[0]
				var ky: float = wv[1]
				var amp: float = wv[2]
				var arg := TAU * (kx * u + ky * v) + float(wv[3])
				h += amp * sin(arg)
				var cs := amp * cos(arg)
				du += kx * cs
				dv += ky * cs
			var idx := y * n + x
			hs[idx] = h
			gx[idx] = du
			gy[idx] = dv
			hmax = maxf(hmax, absf(h))
			gmax = maxf(gmax, maxf(absf(du), absf(dv)))
	var bytes := PackedByteArray()
	bytes.resize(n * n * 4)
	for i in n * n:
		bytes[i * 4] = int(clampf(hs[i] / hmax * 0.5 + 0.5, 0.0, 1.0) * 255.0)
		bytes[i * 4 + 1] = int(clampf(gx[i] / gmax * 0.5 + 0.5, 0.0, 1.0) * 255.0)
		bytes[i * 4 + 2] = int(clampf(gy[i] / gmax * 0.5 + 0.5, 0.0, 1.0) * 255.0)
		bytes[i * 4 + 3] = 255
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make_noise_tex() -> ImageTexture:
	var n := 64
	var bytes := PackedByteArray()
	bytes.resize(n * n * 4)
	for i in n * n:
		var v := rng.randi() % 256
		bytes[i * 4] = v
		bytes[i * 4 + 1] = v
		bytes[i * 4 + 2] = v
		bytes[i * 4 + 3] = 255
	return ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes))

func _build_ship_grid() -> void:
	ship_grid.clear()
	for s in ships:
		if not s.alive:
			continue
		var rr := s.hl + 70.0
		for gx in range(floori((s.pos.x - rr) / SGRID), floori((s.pos.x + rr) / SGRID) + 1):
			for gy in range(floori((s.pos.y - rr) / SGRID), floori((s.pos.y + rr) / SGRID) + 1):
				var key := Vector2i(gx, gy)
				if ship_grid.has(key):
					ship_grid[key].append(s)
				else:
					ship_grid[key] = [s]

func _pt(name: String, t0: int) -> void:
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	prof[name] = lerpf(float(prof.get(name, ms)), ms, 0.1)

